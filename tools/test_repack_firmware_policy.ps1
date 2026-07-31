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

  & (Join-Path $PSScriptRoot "repack_firmware_policy.ps1") `
    -SourceId $source.id `
    -Mode update `
    -VinJson '["s3/n16r8/*/2607/1/1/1/1/1//"]' `
    -MacJson '[]' `
    -RequestId "test-update" `
    -Actor "local-test" `
    -ManifestPath $tempManifest `
    -PrivateKeyPath $PrivateKeyPath `
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
      -PrivateKeyPath $PrivateKeyPath | Out-Null
  } catch {
    $hardwareChangeRejected = $_.Exception.Message.Contains(
      "Only serial number and production date may change"
    )
  }
  Assert-True $hardwareChangeRejected "Immutable hardware VIN was changed"

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
    -PrivateKeyPath $PrivateKeyPath | Out-Null

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

  & (Join-Path $PSScriptRoot "repack_firmware_policy.ps1") `
    -SourceId $source.id `
    -Mode emergency `
    -VinJson '[]' `
    -MacJson '["84-FC-E6-6A-BE-8C","E4:B3:23:F7:E8:B8"]' `
    -RequestId "test-emergency" `
    -Actor "local-test" `
    -DisableSource false `
    -ManifestPath $tempManifest `
    -PrivateKeyPath $PrivateKeyPath `
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
      -PrivateKeyPath $PrivateKeyPath | Out-Null
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
