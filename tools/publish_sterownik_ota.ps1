[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Version,

  [string]$SketchPath = "C:\Users\SRynkiewicz\Documents\Arduino\Moje apki\Konsolka\Ster_v2_2",
  [string]$RepoPath = (Split-Path -Parent $PSScriptRoot),
  [string]$ArduinoCliPath = "C:\Program Files\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe",
  [string[]]$Libraries = @(
    "C:\Users\SRynkiewicz\Documents\Arduino\libraries",
    "C:\Users\SRynkiewicz\OneDrive\Dokumenty\Arduino\libraries"
  ),
  [string]$Fqbn = "esp32:esp32:esp32s3:UploadSpeed=921600,USBMode=hwcdc,CDCOnBoot=default,MSCOnBoot=default,DFUOnBoot=default,UploadMode=default,CPUFreq=240,FlashMode=qio,FlashSize=16M,PartitionScheme=app3M_fat9M_16MB,DebugLevel=none,PSRAM=disabled,LoopCore=1,EventsCore=1,EraseFlash=none,JTAGAdapter=default,ZigbeeMode=default",

  [string]$Product = "SRP-1",
  [string]$Target = "sterownik",
  [string]$Vin = "s3/n16r8///1/1/1/1/1//",
  [string]$Mac = "84:FC:E6:6A:BE:8C",
  [string[]]$CompatVin = @(
    "s3/n16r8///1/1/1/1/1//",
    "s3/n16r8///P1/K1/SD1/RTC1/RS1"
  ),
  [string[]]$CompatMac = @("84:FC:E6:6A:BE:8C"),
  [string]$Notes = "",
  [string]$PackageId = "",

  [string]$PrivateKeyPath = "C:\Users\SRynkiewicz\.koma\ota-signing\srp1_ota_p256_private_blob.b64",
  [string]$PublicKeyPath = "C:\Users\SRynkiewicz\.koma\ota-signing\srp1_ota_p256_public_blob.b64",
  [string[]]$RejectPayloadVersions = @("2.2.8", "2.2.11"),
  [string]$BuildPath = "",
  [switch]$NoManifestUpdate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Publish {
  param([string]$Message)
  throw "[publish_sterownik_ota] $Message"
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

function Get-FileSha256Hex {
  param([string]$Path)
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function ConvertTo-JsonString {
  param([string]$Value)
  return ($Value | ConvertTo-Json -Compress)
}

function Convert-HexToBytes {
  param([string]$Hex)
  if (($Hex.Length % 2) -ne 0) {
    Stop-Publish "Hex string has odd length"
  }
  $out = New-Object byte[] ($Hex.Length / 2)
  for ($i = 0; $i -lt $out.Length; $i++) {
    $out[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16)
  }
  return $out
}

function New-EcdsaFromPrivateBlob {
  param([string]$Path)
  $blob = [Convert]::FromBase64String((Get-Content -Raw -LiteralPath $Path).Trim())
  if ($blob.Length -ne 104) {
    Stop-Publish "Unexpected private key blob length: $($blob.Length)"
  }
  $magic = [Text.Encoding]::ASCII.GetString($blob, 0, 4)
  if ($magic -ne "ECS2") {
    Stop-Publish "Unsupported private key blob magic: $magic"
  }

  $x = New-Object byte[] 32
  $y = New-Object byte[] 32
  $d = New-Object byte[] 32
  [Array]::Copy($blob, 8, $x, 0, 32)
  [Array]::Copy($blob, 40, $y, 0, 32)
  [Array]::Copy($blob, 72, $d, 0, 32)

  $params = New-Object System.Security.Cryptography.ECParameters
  $params.Curve = [System.Security.Cryptography.ECCurve+NamedCurves]::nistP256
  $q = New-Object System.Security.Cryptography.ECPoint
  $q.X = $x
  $q.Y = $y
  $params.Q = $q
  $params.D = $d
  return [System.Security.Cryptography.ECDsa]::Create($params)
}

function New-EcdsaFromPublicBlob {
  param([string]$Path)
  $blob = [Convert]::FromBase64String((Get-Content -Raw -LiteralPath $Path).Trim())
  if ($blob.Length -ne 72) {
    Stop-Publish "Unexpected public key blob length: $($blob.Length)"
  }
  $magic = [Text.Encoding]::ASCII.GetString($blob, 0, 4)
  if ($magic -ne "ECS1") {
    Stop-Publish "Unsupported public key blob magic: $magic"
  }

  $x = New-Object byte[] 32
  $y = New-Object byte[] 32
  [Array]::Copy($blob, 8, $x, 0, 32)
  [Array]::Copy($blob, 40, $y, 0, 32)

  $params = New-Object System.Security.Cryptography.ECParameters
  $params.Curve = [System.Security.Cryptography.ECCurve+NamedCurves]::nistP256
  $q = New-Object System.Security.Cryptography.ECPoint
  $q.X = $x
  $q.Y = $y
  $params.Q = $q
  return [System.Security.Cryptography.ECDsa]::Create($params)
}

function Get-IsoUtcNow {
  return (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function Format-JsonStringArray {
  param([string[]]$Values, [string]$Indent)
  return (($Values | ForEach-Object { "$Indent$(ConvertTo-JsonString $_)" }) -join ",`n")
}

function New-PackageJsonBlock {
  param(
    [string]$Id,
    [string]$Version,
    [string]$FileName,
    [int]$Size,
    [string]$Sha256,
    [string]$Notes
  )

  $vinLines = Format-JsonStringArray -Values $CompatVin -Indent "          "
  $macLines = Format-JsonStringArray -Values $CompatMac -Indent "          "
  $url = "https://raw.githubusercontent.com/serwiskoma321-lgtm/srp1-updates/main/firmware/$Target/$Version/$FileName"
  $publishedAt = Get-Date -Format "yyyy-MM-dd"

  return @"
    {
      "id": $(ConvertTo-JsonString $Id),
      "target": $(ConvertTo-JsonString $Target),
      "version": $(ConvertTo-JsonString $Version),
      "publishedAt": $(ConvertTo-JsonString $publishedAt),
      "fileName": $(ConvertTo-JsonString $FileName),
      "url": $(ConvertTo-JsonString $url),
      "size": $Size,
      "sha256": $(ConvertTo-JsonString $Sha256),
      "notes": $(ConvertTo-JsonString $Notes),
      "api": {
        "app": 1,
        "sterConsole": 1,
        "sterMeasure": 1,
        "otaPackage": 1
      },
      "compat": {
        "product": $(ConvertTo-JsonString $Product),
        "target": $(ConvertTo-JsonString $Target),
        "vin": [
$vinLines
        ],
        "mac": [
$macLines
        ]
      }
    }
"@
}

function Update-Manifest {
  param(
    [string]$ManifestPath,
    [string]$PackageBlock,
    [string]$Version
  )

  $manifest = [IO.File]::ReadAllText($ManifestPath)
  $manifest = $manifest -replace "`r`n", "`n"
  if ($manifest.Contains('"version": "' + $Version + '"')) {
    Stop-Publish "Manifest already contains version $Version"
  }

  $manifest = [regex]::Replace(
    $manifest,
    '  "generatedAt": "[^"]+"',
    '  "generatedAt": "' + (Get-IsoUtcNow) + '"',
    1
  )

  $marker = "  `"packages`": [`n"
  $index = $manifest.IndexOf($marker)
  if ($index -lt 0) {
    Stop-Publish "Cannot find packages array in manifest"
  }
  $insertAt = $index + $marker.Length
  $manifest = $manifest.Substring(0, $insertAt) + $PackageBlock + ",`n" + $manifest.Substring($insertAt)

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($ManifestPath, $manifest, $utf8NoBom)

  $parsed = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
  if ($parsed.packages[0].version -ne $Version) {
    Stop-Publish "Manifest top package is not $Version after update"
  }
}

if (-not (Test-Path -LiteralPath $ArduinoCliPath)) {
  Stop-Publish "arduino-cli not found: $ArduinoCliPath"
}
if (-not (Test-Path -LiteralPath $SketchPath)) {
  Stop-Publish "Sketch path not found: $SketchPath"
}
if (-not (Test-Path -LiteralPath $PrivateKeyPath)) {
  Stop-Publish "Private key not found: $PrivateKeyPath"
}
if (-not (Test-Path -LiteralPath $PublicKeyPath)) {
  Stop-Publish "Public key not found: $PublicKeyPath"
}

if ([string]::IsNullOrWhiteSpace($BuildPath)) {
  $safeVersion = $Version -replace '[^A-Za-z0-9_.-]', '_'
  $BuildPath = Join-Path $env:TEMP ("koma_ota_build_{0}_{1}_{2}" -f $Target, $safeVersion, (Get-Date -Format "yyyyMMdd_HHmmss"))
}
New-Item -ItemType Directory -Force -Path $BuildPath | Out-Null

Write-Host "== Compile fresh build =="
$compileArgs = @("compile", "--build-path", $BuildPath, "--clean")
foreach ($lib in $Libraries) {
  $compileArgs += @("--libraries", $lib)
}
$compileArgs += @("--fqbn", $Fqbn, $SketchPath)
& $ArduinoCliPath @compileArgs
if ($LASTEXITCODE -ne 0) {
  Stop-Publish "Arduino compile failed with exit code $LASTEXITCODE"
}

$firmwareBins = @(Get-ChildItem -LiteralPath $BuildPath -File -Filter "*.ino.bin" | Where-Object {
  $_.Name -notlike "*.bootloader.bin" -and
  $_.Name -notlike "*.partitions.bin" -and
  $_.Name -notlike "*.merged.bin"
})
if ($firmwareBins.Count -ne 1) {
  Stop-Publish "Expected one firmware .ino.bin in build path, found $($firmwareBins.Count)"
}
$binPath = $firmwareBins[0].FullName
$payload = [IO.File]::ReadAllBytes($binPath)
$payloadText = [Text.Encoding]::ASCII.GetString($payload)

Write-Host "== Verify payload version =="
if (-not $payloadText.Contains($Version)) {
  Stop-Publish "Payload does not contain expected version $Version"
}
foreach ($reject in $RejectPayloadVersions) {
  if ($reject -ne $Version -and $payloadText.Contains($reject)) {
    Stop-Publish "Payload contains rejected stale version $reject"
  }
}

$payloadSha256 = Get-Sha256Hex -Bytes $payload
$fileName = "ster.kfw"
$outDir = Join-Path $RepoPath "firmware\$Target\$Version"
$outFile = Join-Path $outDir $fileName
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if ([string]::IsNullOrWhiteSpace($PackageId)) {
  $PackageId = "srp1-$Target-$Version-auto-publish"
}
if ([string]::IsNullOrWhiteSpace($Notes)) {
  $Notes = "Automatyczna publikacja przez tools/publish_sterownik_ota.ps1. Payload zostal zbudowany w swiezym katalogu i sprawdzony przed podpisem."
}

$signedText = "KFW2`nproduct=$Product`ntarget=$Target`nversion=$Version`nvin=$Vin`nmac=$Mac`npayload_size=$($payload.Length)`npayload_sha256=$payloadSha256"
$sha = [System.Security.Cryptography.SHA256]::Create()
$digest = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($signedText))
$ecdsaPrivate = New-EcdsaFromPrivateBlob -Path $PrivateKeyPath
$signature = $ecdsaPrivate.SignHash($digest)
$ecdsaPrivate.Dispose()
if ($signature.Length -ne 64) {
  Stop-Publish "Unexpected ECDSA signature length $($signature.Length)"
}
$signatureHex = (($signature | ForEach-Object { $_.ToString("x2") }) -join "")

Write-Host "== Verify signature =="
$ecdsaPublic = New-EcdsaFromPublicBlob -Path $PublicKeyPath
try {
  if (-not $ecdsaPublic.VerifyHash($digest, $signature)) {
    Stop-Publish "Generated signature does not verify with public key"
  }
} finally {
  $ecdsaPublic.Dispose()
  $sha.Dispose()
}

Write-Host "== Write KFW package =="
$header = "$signedText`nsignature=$signatureHex`n`n"
[IO.File]::WriteAllBytes($outFile, ([Text.Encoding]::ASCII.GetBytes($header) + $payload))

$kfwBytes = [IO.File]::ReadAllBytes($outFile)
$kfwSha256 = Get-Sha256Hex -Bytes $kfwBytes
$headerText, $payloadFromKfwText = ([Text.Encoding]::ASCII.GetString($kfwBytes)).Split("`n`n", 2)
if (-not $payloadFromKfwText.Contains($Version)) {
  Stop-Publish "Written KFW payload does not contain expected version $Version"
}

if (-not $NoManifestUpdate) {
  Write-Host "== Update manifest =="
  $manifestPath = Join-Path $RepoPath "manifest.json"
  $packageBlock = New-PackageJsonBlock -Id $PackageId -Version $Version -FileName $fileName -Size $kfwBytes.Length -Sha256 $kfwSha256 -Notes $Notes
  Update-Manifest -ManifestPath $manifestPath -PackageBlock $packageBlock -Version $Version

  $manifestTop = (Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json).packages[0]
  if ($manifestTop.sha256 -ne $kfwSha256 -or $manifestTop.size -ne $kfwBytes.Length) {
    Stop-Publish "Manifest top package hash/size does not match written KFW"
  }
}

Write-Host "== Done =="
Write-Host "Version: $Version"
Write-Host "Build:   $BuildPath"
Write-Host "Bin:     $binPath"
Write-Host "KFW:     $outFile"
Write-Host "Payload: $($payload.Length) bytes, sha256=$payloadSha256"
Write-Host "KFW:     $($kfwBytes.Length) bytes, sha256=$kfwSha256"
