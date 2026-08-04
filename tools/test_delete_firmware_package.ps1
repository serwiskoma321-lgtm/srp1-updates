[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "[test_delete_firmware_package] $Message"
  }
}

$repoPath = Split-Path -Parent $PSScriptRoot
$sourceManifest = Get-Content -Raw -LiteralPath (Join-Path $repoPath "manifest.json") |
  ConvertFrom-Json
$source = @($sourceManifest.packages)[0]
if ($null -eq $source) {
  throw "Test source package not found"
}

$relativeSource = ([Uri]$source.url).AbsolutePath.Substring(
  "/serwiskoma321-lgtm/srp1-updates/main/".Length
)
$sourceFile = Join-Path $repoPath ($relativeSource -replace '/', '\')
$tempRoot = Join-Path $env:TEMP (
  "koma_delete_test_" + [Guid]::NewGuid().ToString("N")
)
$tempSource = Join-Path $tempRoot ($relativeSource -replace '/', '\')
$tempManifest = Join-Path $tempRoot "manifest.json"
$resultPath = Join-Path $tempRoot "result.json"

try {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $tempSource) |
    Out-Null
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

  & (Join-Path $PSScriptRoot "delete_firmware_package.ps1") `
    -PackageId $source.id `
    -AuditNote "Nieaktualna paczka testowa" `
    -RequestId "test-delete" `
    -Actor "local-test" `
    -ManifestPath $tempManifest `
    -ResultPath $resultPath | Out-Null

  $afterDelete = Get-Content -Raw -LiteralPath $tempManifest | ConvertFrom-Json
  Assert-True (@($afterDelete.packages).Count -eq 0) "Package remains in manifest"
  Assert-True (-not (Test-Path -LiteralPath $tempSource)) "Package file remains"
  Assert-True ($afterDelete.audit[0].requestId -eq "test-delete") "Audit missing"

  & (Join-Path $PSScriptRoot "delete_firmware_package.ps1") `
    -PackageId $source.id `
    -RequestId "test-delete" `
    -ManifestPath $tempManifest `
    -ResultPath $resultPath | Out-Null
  $replay = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json
  Assert-True ($replay.idempotent -eq $true) "Replay was not idempotent"

  & (Join-Path $PSScriptRoot "delete_firmware_package.ps1") `
    -PackageId $source.id `
    -RequestId "test-delete-new-request" `
    -ManifestPath $tempManifest `
    -ResultPath $resultPath | Out-Null
  $alreadyAbsent = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json
  Assert-True ($alreadyAbsent.idempotent -eq $true) `
    "Already absent package was not idempotent"
  Assert-True ($alreadyAbsent.fileDeleted -eq $false) `
    "Already absent package reported a deleted file"

  Write-Host "Firmware package deletion tests passed."
} finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
