[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$SourceId,

  [Parameter(Mandatory = $true)]
  [ValidateSet("update", "emergency")]
  [string]$Mode,

  [string]$VinJson = "[]",
  [string]$MacJson = "[]",
  [string]$Notes = "",
  [string]$AuditNote = "",
  [string]$RequestId = "",
  [string]$Actor = "",
  [ValidateSet("true", "false")]
  [string]$DisableSource = "true",

  [string]$ManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "manifest.json"),

  [Parameter(Mandatory = $true)]
  [ValidatePattern("^[0-9A-Fa-f]{128}$")]
  [string]$SignatureHex,

  [string]$PublicKeyPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "keys/srp1_ota_p256_public_blob.b64"),

  [string]$ResultPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Policy {
  param([string]$Message)
  throw "[repack_firmware_policy] $Message"
}

function Get-Sha256Hex {
  param([byte[]]$Bytes)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return (($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $sha.Dispose()
  }
}

function Convert-HexToBytes {
  param([string]$Hex)
  if ([string]::IsNullOrWhiteSpace($Hex) -or ($Hex.Length % 2) -ne 0) {
    Stop-Policy "Invalid hexadecimal value"
  }
  $bytes = New-Object byte[] ($Hex.Length / 2)
  for ($i = 0; $i -lt $bytes.Length; $i++) {
    try {
      $bytes[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16)
    } catch {
      Stop-Policy "Invalid hexadecimal value"
    }
  }
  return $bytes
}

function Convert-BytesToHex {
  param([byte[]]$Bytes)
  return (($Bytes | ForEach-Object { $_.ToString("x2") }) -join "")
}

function New-EcdsaFromPublicBlob {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Stop-Policy "Public verification key not found"
  }
  $blob = [Convert]::FromBase64String((Get-Content -Raw -LiteralPath $Path).Trim())
  if ($blob.Length -ne 72) {
    Stop-Policy "Unexpected public key blob length"
  }
  if ([Text.Encoding]::ASCII.GetString($blob, 0, 4) -ne "ECS1") {
    Stop-Policy "Unsupported public key blob"
  }

  $x = New-Object byte[] 32
  $y = New-Object byte[] 32
  [Array]::Copy($blob, 8, $x, 0, 32)
  [Array]::Copy($blob, 40, $y, 0, 32)

  $parameters = New-Object System.Security.Cryptography.ECParameters
  $parameters.Curve = [System.Security.Cryptography.ECCurve+NamedCurves]::nistP256
  $point = New-Object System.Security.Cryptography.ECPoint
  $point.X = $x
  $point.Y = $y
  $parameters.Q = $point
  return [System.Security.Cryptography.ECDsa]::Create($parameters)
}

function Test-EcdsaSignature {
  param(
    [System.Security.Cryptography.ECDsa]$Ecdsa,
    [byte[]]$Digest,
    [byte[]]$Signature
  )
  $formatType = [Type]::GetType(
    "System.Security.Cryptography.DSASignatureFormat, System.Security.Cryptography.Algorithms"
  )
  if ($null -eq $formatType) {
    return $Ecdsa.VerifyHash($Digest, $Signature)
  }
  $format = [Enum]::Parse($formatType, "IeeeP1363FixedFieldConcatenation")
  return $Ecdsa.VerifyHash($Digest, $Signature, $format)
}

function Read-RuleArray {
  param([string]$Json, [string]$Name)
  try {
    $decoded = $Json | ConvertFrom-Json
  } catch {
    Stop-Policy "$Name must be a JSON array of strings"
  }
  if ($null -eq $decoded) {
    return @()
  }
  if ($decoded -is [string]) {
    $values = @($decoded)
  } elseif ($decoded -is [System.Collections.IEnumerable]) {
    $values = @($decoded)
  } else {
    Stop-Policy "$Name must be a JSON array of strings"
  }
  if ($values.Count -gt 100) {
    Stop-Policy "$Name contains too many entries"
  }
  $result = @()
  foreach ($value in $values) {
    if ($null -eq $value) {
      Stop-Policy "$Name contains a null value"
    }
    $text = $value.ToString().Trim()
    if ($text.Length -eq 0 -or $text.Length -gt 180) {
      Stop-Policy "$Name contains an empty or too long value"
    }
    if ($text.Contains("`n") -or $text.Contains("`r") -or $text.Contains("|")) {
      Stop-Policy "$Name contains a forbidden separator"
    }
    $result += $text
  }
  return $result
}

function Normalize-Mac {
  param([string]$Value)
  $hex = ($Value -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
  if ($hex.Length -ne 12) {
    Stop-Policy "Invalid MAC address: $Value"
  }
  return (($hex -split '(.{2})' | Where-Object { $_ }) -join ':')
}

function Get-VinTechnicalProfileKey {
  param([string]$Rule)
  $trimmed = $Rule.Trim()
  if ($trimmed.Length -eq 0 -or $trimmed -eq "*") {
    Stop-Policy "Source package has no immutable technical VIN profile"
  }

  $segments = [System.Collections.ArrayList]::new()
  foreach ($segment in $trimmed.Split(
      [char[]]@('/'),
      [System.StringSplitOptions]::None
    )) {
    [void]$segments.Add($segment.Trim())
  }
  while ($segments.Count -lt 10) {
    [void]$segments.Add("")
  }
  if ([string]::IsNullOrWhiteSpace([string]$segments[0]) -or
      [string]$segments[0] -eq "*" -or
      [string]::IsNullOrWhiteSpace([string]$segments[1]) -or
      [string]$segments[1] -eq "*") {
    Stop-Policy "VIN model and memory must be immutable"
  }

  $segments[2] = ""
  $segments[3] = ""
  return [string]::Join("/", [string[]]$segments.ToArray([string]))
}

function Assert-VinRolloutSyntax {
  param([string]$Rule)
  $segments = [System.Collections.ArrayList]::new()
  foreach ($segment in $Rule.Trim().Split(
      [char[]]@('/'),
      [System.StringSplitOptions]::None
    )) {
    [void]$segments.Add($segment.Trim())
  }
  while ($segments.Count -lt 10) {
    [void]$segments.Add("")
  }

  foreach ($serialNumber in ([string]$segments[2]).Split(';')) {
    $value = $serialNumber.Trim()
    if ($value.StartsWith("!")) {
      $value = $value.Substring(1).Trim()
    }
    if ($value.Length -eq 0 -or $value -eq "*") {
      continue
    }
    if ($value -match '^(\d{1,9})-(\d{1,9})$') {
      if ([int64]$Matches[1] -gt [int64]$Matches[2]) {
        Stop-Policy "VIN serial range starts after it ends"
      }
    } elseif ($value -notmatch '^\d{1,9}$') {
      Stop-Policy "VIN serial selector has invalid syntax: $value"
    }
  }

  foreach ($productionDate in ([string]$segments[3]).Split(';')) {
    $value = $productionDate.Trim()
    if ($value.StartsWith("!")) {
      $value = $value.Substring(1).Trim()
    }
    if ($value.Length -eq 0 -or $value -eq "*") {
      continue
    }
    $dateValues = if ($value -match '^(\d{4}|\d{6})-(\d{4}|\d{6})$') {
      if ($Matches[1].Length -ne $Matches[2].Length) {
        Stop-Policy "VIN date range must use one consistent format"
      }
      if ([int64]$Matches[1] -gt [int64]$Matches[2]) {
        Stop-Policy "VIN date range starts after it ends"
      }
      @($Matches[1], $Matches[2])
    } elseif ($value -match '^(?:\d{4}|\d{6})$') {
      @($value)
    } else {
      Stop-Policy "VIN production date selector has invalid syntax: $value"
    }
    foreach ($dateValue in $dateValues) {
      $month = [int]$dateValue.Substring($dateValue.Length - 2)
      if ($month -lt 1 -or $month -gt 12) {
        Stop-Policy "VIN production month must be between 01 and 12"
      }
    }
  }
}

function Test-VinUsesAdvancedSelectors {
  param([string[]]$Rules)
  foreach ($rule in $Rules) {
    $segments = $rule.Split(
      [char[]]@('/'),
      [System.StringSplitOptions]::None
    )
    foreach ($index in @(2, 3)) {
      if ($index -ge $segments.Count) {
        continue
      }
      foreach ($selector in ([string]$segments[$index]).Split(';')) {
        $value = $selector.Trim()
        if ($value.StartsWith("!") -or $value.Contains("-")) {
          return $true
        }
      }
    }
  }
  return $false
}

function Test-FirmwareVersionAtLeast {
  param(
    [string]$Value,
    [int]$Major,
    [int]$Minor,
    [int]$Patch
  )
  if ($Value -notmatch '^(\d+)\.(\d+)\.(\d+)') {
    return $false
  }
  $current = @([int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
  $required = @($Major, $Minor, $Patch)
  for ($index = 0; $index -lt 3; $index++) {
    if ($current[$index] -gt $required[$index]) {
      return $true
    }
    if ($current[$index] -lt $required[$index]) {
      return $false
    }
  }
  return $true
}

function Assert-VinRolloutOnlyChange {
  param(
    [string]$SourceRules,
    [string[]]$RequestedRules
  )
  $sourceProfiles = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
  )
  foreach ($sourceRule in $SourceRules.Split(
      [char[]]@('|'),
      [System.StringSplitOptions]::None
    )) {
    [void]$sourceProfiles.Add((Get-VinTechnicalProfileKey -Rule $sourceRule))
  }
  foreach ($requestedRule in $RequestedRules) {
    Assert-VinRolloutSyntax -Rule $requestedRule
    $requestedProfile = Get-VinTechnicalProfileKey -Rule $requestedRule
    if (-not $sourceProfiles.Contains($requestedProfile)) {
      Stop-Policy (
        "Requested VIN changes immutable hardware compatibility. " +
        "Only serial number and production date may change"
      )
    }
  }
}

function Find-HeaderEnd {
  param([byte[]]$Bytes)
  for ($i = 0; $i -lt $Bytes.Length - 1; $i++) {
    if ($Bytes[$i] -eq 10 -and $Bytes[$i + 1] -eq 10) {
      return $i
    }
  }
  return -1
}

function Read-Kfw {
  param([string]$Path)
  $bytes = [IO.File]::ReadAllBytes($Path)
  $headerEnd = Find-HeaderEnd -Bytes $bytes
  if ($headerEnd -le 0) {
    Stop-Policy "Source package has no KFW2 header"
  }
  $headerText = [Text.Encoding]::ASCII.GetString($bytes, 0, $headerEnd)
  $lines = @($headerText -split "`n")
  if ($lines.Count -eq 0 -or $lines[0].Trim() -ne "KFW2") {
    Stop-Policy "Source package is not KFW2"
  }

  $header = [ordered]@{}
  foreach ($rawLine in $lines | Select-Object -Skip 1) {
    $line = $rawLine.TrimEnd("`r")
    $separator = $line.IndexOf("=")
    if ($separator -le 0) {
      Stop-Policy "Invalid KFW2 header line"
    }
    $key = $line.Substring(0, $separator).Trim().ToLowerInvariant()
    $value = $line.Substring($separator + 1).Trim()
    $header[$key] = $value
  }

  foreach ($required in @(
      "product", "target", "version", "vin", "mac", "payload_size",
      "payload_sha256", "signature"
    )) {
    if (-not $header.Contains($required)) {
      Stop-Policy "Source KFW2 header is missing $required"
    }
  }

  $payloadSize = 0
  if (-not [int]::TryParse($header["payload_size"], [ref]$payloadSize) -or $payloadSize -le 0) {
    Stop-Policy "Invalid KFW2 payload size"
  }
  $payloadOffset = $headerEnd + 2
  if (($payloadOffset + $payloadSize) -ne $bytes.Length) {
    Stop-Policy "KFW2 package is truncated or has trailing data"
  }
  $payload = New-Object byte[] $payloadSize
  [Array]::Copy($bytes, $payloadOffset, $payload, 0, $payloadSize)
  if ((Get-Sha256Hex -Bytes $payload) -ne $header["payload_sha256"].ToLowerInvariant()) {
    Stop-Policy "KFW2 encrypted payload SHA-256 mismatch"
  }

  return @{
    Bytes = $bytes
    Header = $header
    Payload = $payload
  }
}

function New-SignedText {
  param(
    [System.Collections.IDictionary]$Header,
    [string]$Vin,
    [string]$Mac
  )
  $text = "KFW2`nproduct=$($Header['product'])`ntarget=$($Header['target'])" +
    "`nversion=$($Header['version'])`nvin=$Vin`nmac=$Mac" +
    "`npayload_size=$($Header['payload_size'])" +
    "`npayload_sha256=$($Header['payload_sha256'])"
  if ($Header.Contains("payload_enc")) {
    $text += "`npayload_enc=$($Header['payload_enc'])"
  }
  if ($Header.Contains("payload_iv")) {
    $text += "`npayload_iv=$($Header['payload_iv'])"
  }
  if ($Header.Contains("payload_plain_sha256")) {
    $text += "`npayload_plain_sha256=$($Header['payload_plain_sha256'])"
  }
  return $text
}

function Get-SourceRelativePath {
  param([string]$Url)
  try {
    $uri = [Uri]$Url
  } catch {
    Stop-Policy "Source package URL is invalid"
  }
  if ($uri.Scheme -ne "https" -or $uri.Host -ne "raw.githubusercontent.com") {
    Stop-Policy "Source package URL must use raw.githubusercontent.com"
  }
  $marker = "/serwiskoma321-lgtm/srp1-updates/main/"
  if (-not $uri.AbsolutePath.StartsWith($marker, [StringComparison]::OrdinalIgnoreCase)) {
    Stop-Policy "Source package URL points outside srp1-updates/main"
  }
  return [Uri]::UnescapeDataString($uri.AbsolutePath.Substring($marker.Length))
}

function Set-ObjectProperty {
  param([object]$Object, [string]$Name, [object]$Value)
  if ($Object.PSObject.Properties.Name -contains $Name) {
    $Object.$Name = $Value
  } else {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
  }
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
  Stop-Policy "Manifest not found"
}
if ($RequestId.Length -eq 0) {
  $RequestId = [Guid]::NewGuid().ToString("N")
}
if ($RequestId -notmatch '^[A-Za-z0-9._-]{1,80}$') {
  Stop-Policy "RequestId contains forbidden characters"
}
if ($Actor.Length -gt 80 -or $Notes.Length -gt 500 -or $AuditNote.Length -gt 500) {
  Stop-Policy "Actor, description or audit note is too long"
}

$vinRules = @(Read-RuleArray -Json $VinJson -Name "VIN")
$macInput = @(Read-RuleArray -Json $MacJson -Name "MAC")
$macRules = @($macInput | ForEach-Object { Normalize-Mac -Value $_ } | Select-Object -Unique)
if ($Mode -eq "update" -and $vinRules.Count -eq 0) {
  Stop-Policy "Update mode requires at least one VIN rule"
}
if ($Mode -eq "emergency" -and $macRules.Count -eq 0) {
  Stop-Policy "Emergency mode requires at least one exact MAC address"
}
if ($Mode -eq "emergency") {
  $vinRules = @("*")
}

$manifestText = [IO.File]::ReadAllText($ManifestPath)
$manifest = $manifestText | ConvertFrom-Json
$existingRequest = @($manifest.packages | Where-Object {
    $_.PSObject.Properties.Name -contains "policyRequestId" -and
    $_.policyRequestId -eq $RequestId
  })
if ($existingRequest.Count -gt 0) {
  $result = [ordered]@{
    ok = $true
    idempotent = $true
    requestId = $RequestId
    packageId = $existingRequest[0].id
    policyRevision = $existingRequest[0].policyRevision
  }
  $resultJson = $result | ConvertTo-Json -Depth 5
  if ($ResultPath.Length -gt 0) {
    [IO.File]::WriteAllText($ResultPath, $resultJson, (New-Object Text.UTF8Encoding($false)))
  }
  Write-Output $resultJson
  exit 0
}

$sources = @($manifest.packages | Where-Object { $_.id -eq $SourceId })
if ($sources.Count -ne 1) {
  Stop-Policy "Expected exactly one source package with id $SourceId"
}
$source = $sources[0]
if ($Mode -eq "update" -and
    [string]$source.target -eq "sterownik" -and
    (Test-VinUsesAdvancedSelectors -Rules $vinRules) -and
    -not (Test-FirmwareVersionAtLeast `
      -Value ([string]$source.version) `
      -Major 2 `
      -Minor 3 `
      -Patch 22)) {
  Stop-Policy (
    "Serial/date ranges and exclusions require sterownik firmware 2.3.22 " +
    "or newer"
  )
}
$repoPath = Split-Path -Parent (Resolve-Path -LiteralPath $ManifestPath)
$sourceRelativePath = Get-SourceRelativePath -Url $source.url
$sourcePath = [IO.Path]::GetFullPath((Join-Path $repoPath $sourceRelativePath))
$repoFullPath = [IO.Path]::GetFullPath($repoPath).TrimEnd('\') + '\'
if (-not $sourcePath.StartsWith($repoFullPath, [StringComparison]::OrdinalIgnoreCase)) {
  Stop-Policy "Resolved source package path escapes repository"
}
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
  Stop-Policy "Source package file is missing"
}

$sourceBytes = [IO.File]::ReadAllBytes($sourcePath)
if ($null -ne $source.size -and [int64]$source.size -ne $sourceBytes.Length) {
  Stop-Policy "Source package size does not match manifest"
}
if (-not [string]::IsNullOrWhiteSpace($source.sha256) -and
    (Get-Sha256Hex -Bytes $sourceBytes) -ne $source.sha256.ToLowerInvariant()) {
  Stop-Policy "Source package SHA-256 does not match manifest"
}

$kfw = Read-Kfw -Path $sourcePath
$ecdsa = New-EcdsaFromPublicBlob -Path $PublicKeyPath
try {
  $sourceSignedText = New-SignedText -Header $kfw.Header -Vin $kfw.Header["vin"] -Mac $kfw.Header["mac"]
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $sourceDigest = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($sourceSignedText))
    $sourceSignature = Convert-HexToBytes -Hex $kfw.Header["signature"]
    if (-not (Test-EcdsaSignature -Ecdsa $ecdsa -Digest $sourceDigest -Signature $sourceSignature)) {
      Stop-Policy "Source KFW2 signature is invalid"
    }

    if ($Mode -eq "update") {
      Assert-VinRolloutOnlyChange `
        -SourceRules $kfw.Header["vin"] `
        -RequestedRules $vinRules
    }
    $signedVin = $vinRules -join "|"
    $signedMac = $macRules -join "|"
    $newSignedText = New-SignedText -Header $kfw.Header -Vin $signedVin -Mac $signedMac
    $newDigest = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($newSignedText))
    $newSignature = Convert-HexToBytes -Hex $SignatureHex
    if (-not (Test-EcdsaSignature -Ecdsa $ecdsa -Digest $newDigest -Signature $newSignature)) {
      Stop-Policy "Administrator policy signature is invalid"
    }
  } finally {
    $sha.Dispose()
  }
} finally {
  $ecdsa.Dispose()
}
if ($newSignature.Length -ne 64) {
  Stop-Policy "Generated signature has an invalid size"
}

$sameFirmware = @($manifest.packages | Where-Object {
    $_.target -eq $source.target -and $_.version -eq $source.version
  })
$revisionValues = @($sameFirmware | ForEach-Object {
    if ($_.PSObject.Properties.Name -contains "policyRevision") {
      [int]$_.policyRevision
    } else {
      1
    }
  })
$policyRevision = (($revisionValues | Measure-Object -Maximum).Maximum) + 1
$safeTarget = $source.target -replace '[^A-Za-z0-9_-]', '_'
$safeVersion = $source.version -replace '[^A-Za-z0-9_.-]', '_'
$fileName = "${safeTarget}_${safeVersion}_${Mode}_p${policyRevision}.kfw"
$relativeOutDir = "firmware/$safeTarget/$safeVersion/policy-$policyRevision"
$relativeOutPath = "$relativeOutDir/$fileName"
$outPath = Join-Path $repoPath ($relativeOutPath -replace '/', '\')
if (Test-Path -LiteralPath $outPath) {
  Stop-Policy "Target policy package already exists"
}

$headerBytes = [Text.Encoding]::ASCII.GetBytes(
  "$newSignedText`nsignature=$(Convert-BytesToHex -Bytes $newSignature)`n`n"
)
$newBytes = New-Object byte[] ($headerBytes.Length + $kfw.Payload.Length)
[Array]::Copy($headerBytes, 0, $newBytes, 0, $headerBytes.Length)
[Array]::Copy($kfw.Payload, 0, $newBytes, $headerBytes.Length, $kfw.Payload.Length)
$newSha256 = Get-Sha256Hex -Bytes $newBytes
$packageId = "srp1-$safeTarget-$safeVersion-$Mode-p$policyRevision"
$publishedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
$generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$url = "https://raw.githubusercontent.com/serwiskoma321-lgtm/srp1-updates/main/$relativeOutPath"
$effectiveNotes = if ($Notes.Trim().Length -gt 0) {
  $Notes.Trim()
} else {
  "Rewizja polityki $policyRevision utworzona z $SourceId."
}

$newPackage = [ordered]@{
  id = $packageId
  target = $source.target
  version = $source.version
  publishedAt = $publishedAt
  fileName = $fileName
  url = $url
  size = $newBytes.Length
  sha256 = $newSha256
  notes = $effectiveNotes
  emergencyUsb = ($Mode -eq "emergency")
  status = "active"
  policyRevision = $policyRevision
  sourcePackageId = $SourceId
  policyRequestId = $RequestId
  createdBy = $Actor
  policyAuditNote = $AuditNote.Trim()
  api = $source.api
  compat = [ordered]@{
    product = $source.compat.product
    target = $source.target
    vin = @($vinRules)
    mac = @($macRules)
  }
}

if ($DisableSource -eq "true") {
  Set-ObjectProperty -Object $source -Name "status" -Value "disabled"
  Set-ObjectProperty -Object $source -Name "supersededBy" -Value $packageId
}
Set-ObjectProperty -Object $manifest -Name "generatedAt" -Value $generatedAt
$manifest.packages = @($newPackage) + @($manifest.packages)

$outDir = Split-Path -Parent $outPath
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$packageTemp = "$outPath.tmp"
$manifestTemp = "$ManifestPath.tmp"
try {
  [IO.File]::WriteAllBytes($packageTemp, $newBytes)
  $utf8NoBom = New-Object Text.UTF8Encoding($false)
  [IO.File]::WriteAllText(
    $manifestTemp,
    (($manifest | ConvertTo-Json -Depth 20) + "`n"),
    $utf8NoBom
  )

  $checkManifest = [IO.File]::ReadAllText($manifestTemp) | ConvertFrom-Json
  $checkPackage = $checkManifest.packages[0]
  if ($checkPackage.id -ne $packageId -or
      [int64]$checkPackage.size -ne $newBytes.Length -or
      $checkPackage.sha256 -ne $newSha256) {
    Stop-Policy "Generated manifest verification failed"
  }
  $checkKfw = Read-Kfw -Path $packageTemp
  if ($checkKfw.Header["vin"] -ne ($vinRules -join "|") -or
      $checkKfw.Header["mac"] -ne ($macRules -join "|")) {
    Stop-Policy "Generated KFW2 policy verification failed"
  }

  Move-Item -LiteralPath $packageTemp -Destination $outPath
  Move-Item -LiteralPath $manifestTemp -Destination $ManifestPath -Force
} finally {
  Remove-Item -LiteralPath $packageTemp -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $manifestTemp -Force -ErrorAction SilentlyContinue
}

$result = [ordered]@{
  ok = $true
  idempotent = $false
  requestId = $RequestId
  sourcePackageId = $SourceId
  packageId = $packageId
  mode = $Mode
  policyRevision = $policyRevision
  relativePath = $relativeOutPath
  sha256 = $newSha256
  size = $newBytes.Length
}
$resultJson = $result | ConvertTo-Json -Depth 5
if ($ResultPath.Length -gt 0) {
  [IO.File]::WriteAllText($ResultPath, $resultJson, (New-Object Text.UTF8Encoding($false)))
}
Write-Output $resultJson
