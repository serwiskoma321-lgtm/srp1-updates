[CmdletBinding()]
param(
  [string]$PrivateKeyPath = "C:\Users\SRynkiewicz\.koma\ota-signing\srp1_ota_p256_private_blob.b64"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "[test_repack_firmware_policy] $Message"
  }
}

function New-TestEcdsa {
  param([string]$Path)
  $blob = [Convert]::FromBase64String((Get-Content -Raw -LiteralPath $Path).Trim())
  $parameters = New-Object System.Security.Cryptography.ECParameters
  $parameters.Curve = [System.Security.Cryptography.ECCurve+NamedCurves]::nistP256
  $point = New-Object System.Security.Cryptography.ECPoint
  $point.X = [byte[]]$blob[8..39]
  $point.Y = [byte[]]$blob[40..71]
  $parameters.Q = $point
  $parameters.D = [byte[]]$blob[72..103]
  return [System.Security.Cryptography.ECDsa]::Create($parameters)
}

function Get-TestPolicySignature {
  param(
    [string]$SourcePath,
    [string]$Vin,
    [string]$Mac
  )
  $bytes = [IO.File]::ReadAllBytes($SourcePath)
  $headerEnd = -1
  for ($i = 0; $i -lt $bytes.Length - 1; $i++) {
    if ($bytes[$i] -eq 10 -and $bytes[$i + 1] -eq 10) {
      $headerEnd = $i
      break
    }
  }
  if ($headerEnd -le 0) {
    throw "Test source is not KFW2"
  }
  $header = @{}
  $headerText = [Text.Encoding]::ASCII.GetString($bytes, 0, $headerEnd)
  foreach ($line in @($headerText -split "`n") | Select-Object -Skip 1) {
    $separator = $line.IndexOf("=")
    if ($separator -gt 0) {
      $header[$line.Substring(0, $separator).Trim().ToLowerInvariant()] = `
        $line.Substring($separator + 1).Trim()
    }
  }
  $signedText = "KFW2`nproduct=$($header['product'])`ntarget=$($header['target'])" +
    "`nversion=$($header['version'])`nvin=$Vin`nmac=$Mac" +
    "`npayload_size=$($header['payload_size'])" +
    "`npayload_sha256=$($header['payload_sha256'])"
  foreach ($optional in @("payload_enc", "payload_iv", "payload_plain_sha256")) {
    if ($header.ContainsKey($optional)) {
      $signedText += "`n$optional=$($header[$optional])"
    }
  }
  $sha = [Security.Cryptography.SHA256]::Create()
  $ecdsa = New-TestEcdsa -Path $PrivateKeyPath
  try {
    $digest = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($signedText))
    $formatType = [Type]::GetType(
      "System.Security.Cryptography.DSASignatureFormat, System.Security.Cryptography.Algorithms"
    )
    if ($null -eq $formatType) {
      $signature = $ecdsa.SignHash($digest)
    } else {
      $format = [Enum]::Parse($formatType, "IeeeP1363FixedFieldConcatenation")
      $signature = $ecdsa.SignHash($digest, $format)
    }
    return (($signature | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $ecdsa.Dispose()
    $sha.Dispose()
  }
}

$repoPath = Split-Path -Parent $PSScriptRoot
$sourceManifest = Get-Content -Raw -LiteralPath (Join-Path $repoPath "manifest.json") | ConvertFrom-Json
$source = @($sourceManifest.packages | Where-Object {
    $_.id -eq "srp1-sterownik-2.3.22-auto-publish"
  })[0]
if ($null -eq $source) {
  throw "Test source package not found"
}

$uri = [Uri]$source.url
$relativeSource = $uri.AbsolutePath.Substring(
  "/serwiskoma321-lgtm/srp1-updates/main/".Length
)
$sourceFile = Join-Path $repoPath ($relativeSource -replace '/', '\')
$tempRoot = Join-Path $env:TEMP ("koma_policy_test_" + [Guid]::NewGuid().ToString("N"))
$tempSource = Join-Path $tempRoot ($relativeSource -replace '/', '\')
$tempManifest = Join-Path $tempRoot "manifest.json"
$resultPath = Join-Path $tempRoot "result.json"

try {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $tempSource) | Out-Null
  Copy-Item -LiteralPath $sourceFile -Destination $tempSource
  $testManifest = [ordered]@{
    schema = 1
    product = "SRP-1"
    generatedAt = "2026-07-30T00:00:00Z"
    packages = @($source)
  }
  [IO.File]::WriteAllText(
    $tempManifest,
    (($testManifest | ConvertTo-Json -Depth 20) + "`n"),
    (New-Object Text.UTF8Encoding($false))
  )

  $updateVin = "s3/n16r8/*/2607/1/1/1/1/1//"
  $updateSignature = Get-TestPolicySignature `
    -SourcePath $tempSource `
    -Vin $updateVin `
    -Mac ""

  & (Join-Path $PSScriptRoot "repack_firmware_policy.ps1") `
    -SourceId $source.id `
    -Mode update `
    -VinJson '["s3/n16r8/*/2607/1/1/1/1/1//"]' `
    -MacJson '[]' `
    -RequestId "test-update" `
    -Actor "local-test" `
    -ManifestPath $tempManifest `
    -SignatureHex $updateSignature `
    -ResultPath $resultPath | Out-Null

  $afterUpdate = Get-Content -Raw -LiteralPath $tempManifest | ConvertFrom-Json
  $update = $afterUpdate.packages[0]
  Assert-True ($update.policyRevision -eq 2) "First policy revision should be 2"
  Assert-True ($update.emergencyUsb -eq $false) "Update variant has emergency flag"
  Assert-True ($update.compat.vin[0] -eq "s3/n16r8/*/2607/1/1/1/1/1//") "VIN was not written"
  Assert-True ($update.compat.mac.Count -eq 0) "Update MAC list should be empty"
  Assert-True ($afterUpdate.packages[1].status -eq "disabled") "Source package was not disabled"
  Assert-True (Test-Path -LiteralPath (Join-Path $tempRoot ($update.url.Split("/main/")[1] -replace '/', '\'))) "Update KFW file missing"

  $hardwareChangeRejected = $false
  try {
    & (Join-Path $PSScriptRoot "repack_firmware_policy.ps1") `
      -SourceId $source.id `
      -Mode update `
      -VinJson '["s3/n4r2/1/2607/1/1/1/1/1//"]' `
      -MacJson '[]' `
      -RequestId "test-hardware-change" `
      -Actor "local-test" `
      -ManifestPath $tempManifest `
      -SignatureHex ("00" * 64) | Out-Null
  } catch {
    $hardwareChangeRejected = $_.Exception.Message.Contains(
      "Only serial number and production date may change"
    )
  }
  Assert-True $hardwareChangeRejected "Immutable hardware VIN was changed"

  $rangeVin = "s3/n16r8/5-20;!8/2607-2712/1/1/1/1/1//"
  $rangeSignature = Get-TestPolicySignature `
    -SourcePath $tempSource `
    -Vin $rangeVin `
    -Mac ""

  & (Join-Path $PSScriptRoot "repack_firmware_policy.ps1") `
    -SourceId $source.id `
    -Mode update `
    -VinJson '["s3/n16r8/5-20;!8/2607-2712/1/1/1/1/1//"]' `
    -MacJson '[]' `
    -Notes "Opis paczki testowej" `
    -AuditNote "Zakres pilotazowy" `
    -RequestId "test-range-and-exclusion" `
    -Actor "local-test" `
    -DisableSource false `
    -ManifestPath $tempManifest `
    -SignatureHex $rangeSignature | Out-Null

  $afterRange = Get-Content -Raw -LiteralPath $tempManifest | ConvertFrom-Json
  $range = $afterRange.packages[0]
  Assert-True (
    $range.compat.vin[0] -eq "s3/n16r8/5-20;!8/2607-2712/1/1/1/1/1//"
  ) "VIN range or exclusion was not written"
  Assert-True (
    $range.policyAuditNote -eq "Zakres pilotazowy"
  ) "Audit note was not written: '$($range.policyAuditNote)'"
  Assert-True (
    $range.notes -eq "Opis paczki testowej"
  ) "Package description was not written"

  $tamperedSignature = $rangeSignature.Substring(0, 127) + $(
    if ($rangeSignature.EndsWith("0")) { "1" } else { "0" }
  )
  $tamperedSignatureRejected = $false
  try {
    & (Join-Path $PSScriptRoot "repack_firmware_policy.ps1") `
      -SourceId $source.id `
      -Mode update `
      -VinJson '["s3/n16r8/5-20;!8/2607-2712/1/1/1/1/1//"]' `
      -MacJson '[]' `
      -RequestId "test-tampered-signature" `
      -Actor "local-test" `
      -DisableSource false `
      -ManifestPath $tempManifest `
      -SignatureHex $tamperedSignature | Out-Null
  } catch {
    $tamperedSignatureRejected = $_.Exception.Message.Contains(
      "Administrator policy signature is invalid"
    )
  }
  Assert-True $tamperedSignatureRejected "Tampered administrator signature was accepted"

  $emergencyMac = "84:FC:E6:6A:BE:8C|E4:B3:23:F7:E8:B8"
  $emergencySignature = Get-TestPolicySignature `
    -SourcePath $tempSource `
    -Vin "*" `
    -Mac $emergencyMac

  & (Join-Path $PSScriptRoot "repack_firmware_policy.ps1") `
    -SourceId $source.id `
    -Mode emergency `
    -VinJson '[]' `
    -MacJson '["84-FC-E6-6A-BE-8C","E4:B3:23:F7:E8:B8"]' `
    -RequestId "test-emergency" `
    -Actor "local-test" `
    -DisableSource false `
    -ManifestPath $tempManifest `
    -SignatureHex $emergencySignature `
    -ResultPath $resultPath | Out-Null

  $afterEmergency = Get-Content -Raw -LiteralPath $tempManifest | ConvertFrom-Json
  $emergency = $afterEmergency.packages[0]
  Assert-True ($emergency.policyRevision -eq 4) "Third policy revision should be 4"
  Assert-True ($emergency.emergencyUsb -eq $true) "Emergency flag missing"
  Assert-True ($emergency.compat.vin[0] -eq "*") "Emergency VIN should be wildcard"
  Assert-True ($emergency.compat.mac.Count -eq 2) "Emergency MAC list should contain two addresses"
  Assert-True ($emergency.compat.mac[0] -eq "84:FC:E6:6A:BE:8C") "MAC normalization failed"

  $failedAsExpected = $false
  try {
    & (Join-Path $PSScriptRoot "repack_firmware_policy.ps1") `
      -SourceId $source.id `
      -Mode emergency `
      -VinJson '[]' `
      -MacJson '[]' `
      -RequestId "test-invalid" `
      -ManifestPath $tempManifest `
      -SignatureHex ("00" * 64) | Out-Null
  } catch {
    $failedAsExpected = $_.Exception.Message.Contains(
      "Emergency mode requires at least one exact MAC address"
    )
  }
  Assert-True $failedAsExpected "Emergency policy without MAC was accepted"

  Write-Host "Policy repack tests passed."
} finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
