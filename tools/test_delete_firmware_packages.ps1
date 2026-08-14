Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "[test_delete_firmware_packages] $Message" }
}

$repoPath = Split-Path -Parent $PSScriptRoot
$sourceManifest = Get-Content -Raw -LiteralPath (Join-Path $repoPath "manifest.json") |
  ConvertFrom-Json
$sources = @($sourceManifest.packages | Select-Object -First 2)
if ($sources.Count -ne 2) { throw "Two source packages are required" }

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) (
  "koma_delete_batch_test_" + [Guid]::NewGuid().ToString("N")
)
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$tempManifest = Join-Path $tempRoot "manifest.json"

try {
  $fixture = [ordered]@{
    schema = 1
    packages = @($sources)
    audit = @()
  }
  [IO.File]::WriteAllText(
    $tempManifest,
    (($fixture | ConvertTo-Json -Depth 20) + "`n"),
    (New-Object Text.UTF8Encoding($false))
  )
  $ids = @($sources | ForEach-Object { [string]$_.id })
  $resultPath = Join-Path $tempRoot "result.json"
  & (Join-Path $PSScriptRoot "delete_firmware_packages.ps1") `
    -PackageIdsJson ($ids | ConvertTo-Json -Compress) `
    -RequestId "test-delete-batch" `
    -AuditNote "Batch test" `
    -ManifestPath $tempManifest `
    -ResultPath $resultPath | Out-Null

  $after = Get-Content -Raw -LiteralPath $tempManifest | ConvertFrom-Json
  $result = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json
  Assert-True (@($after.packages).Count -eq 0) "Packages remain in manifest"
  Assert-True ($result.deletedCount -eq 2) "Wrong deleted count"
  Assert-True ($after.audit[0].action -eq "delete-packages") "Batch audit missing"

  & (Join-Path $PSScriptRoot "delete_firmware_packages.ps1") `
    -PackageIdsJson ($ids | ConvertTo-Json -Compress) `
    -RequestId "test-delete-batch" `
    -ManifestPath $tempManifest `
    -ResultPath $resultPath | Out-Null
  $repeat = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json
  Assert-True ($repeat.idempotent -eq $true) "Repeated request is not idempotent"
  Write-Host "Firmware batch deletion tests passed."
} finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
