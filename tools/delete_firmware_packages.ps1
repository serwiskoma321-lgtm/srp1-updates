[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$PackageIdsJson,

  [string]$AuditNote = "",
  [string]$RequestId = "",
  [string]$Actor = "",
  [string]$ManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "manifest.json"),
  [string]$ResultPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-DeleteBatch {
  param([string]$Message)
  throw "[delete_firmware_packages] $Message"
}

function Set-ObjectProperty {
  param([object]$Object, [string]$Name, [object]$Value)
  if ($Object.PSObject.Properties.Name -contains $Name) {
    $Object.$Name = $Value
  } else {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
  }
}

function Get-SourceRelativePath {
  param([string]$Url)
  $uri = [Uri]$Url
  $marker = "/serwiskoma321-lgtm/srp1-updates/main/"
  $index = $uri.AbsolutePath.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase)
  if ($index -lt 0) {
    Stop-DeleteBatch "Package URL points outside srp1-updates/main"
  }
  return [Uri]::UnescapeDataString($uri.AbsolutePath.Substring($index + $marker.Length))
}

function Write-Result {
  param([object]$Result)
  $json = $Result | ConvertTo-Json -Depth 10
  if ($ResultPath.Length -gt 0) {
    [IO.File]::WriteAllText($ResultPath, $json, (New-Object Text.UTF8Encoding($false)))
  }
  Write-Output $json
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
  Stop-DeleteBatch "Manifest not found"
}
if ($RequestId.Length -eq 0) {
  $RequestId = [Guid]::NewGuid().ToString("N")
}
if ($RequestId -notmatch '^[A-Za-z0-9._-]{1,96}$') {
  Stop-DeleteBatch "RequestId contains forbidden characters"
}
if ($Actor.Length -gt 80 -or $AuditNote.Length -gt 500) {
  Stop-DeleteBatch "Actor or audit note is too long"
}

try {
  $decodedIds = $PackageIdsJson | ConvertFrom-Json
} catch {
  Stop-DeleteBatch "PackageIdsJson is not valid JSON"
}
$packageIds = @($decodedIds | ForEach-Object { ([string]$_).Trim() } |
  Where-Object { $_.Length -gt 0 } | Select-Object -Unique)
if ($packageIds.Count -lt 1 -or $packageIds.Count -gt 100) {
  Stop-DeleteBatch "Expected between 1 and 100 unique package IDs"
}
if ($packageIds | Where-Object { $_.Length -gt 200 -or $_ -match '[\r\n]' }) {
  Stop-DeleteBatch "Package ID contains forbidden characters"
}

$manifest = [IO.File]::ReadAllText($ManifestPath) | ConvertFrom-Json
$audit = if ($manifest.PSObject.Properties.Name -contains "audit") {
  @($manifest.audit)
} else {
  @()
}
$existingRequest = @($audit | Where-Object {
    $_.PSObject.Properties.Name -contains "requestId" -and
    $_.requestId -eq $RequestId
  })
if ($existingRequest.Count -gt 0) {
  Write-Result ([ordered]@{
    ok = $true
    idempotent = $true
    requestId = $RequestId
    requestedCount = $packageIds.Count
    deletedCount = 0
    deletedPackageIds = @()
  })
  exit 0
}

$idSet = @{}
foreach ($id in $packageIds) { $idSet[$id] = $true }
$matches = @($manifest.packages | Where-Object { $idSet.ContainsKey([string]$_.id) })
$matchedIds = @($matches | ForEach-Object { [string]$_.id })
$matchedSet = @{}
foreach ($id in $matchedIds) { $matchedSet[$id] = $true }
$absentIds = @($packageIds | Where-Object { -not $matchedSet.ContainsKey($_) })

if ($matches.Count -eq 0) {
  Write-Result ([ordered]@{
    ok = $true
    idempotent = $true
    requestId = $RequestId
    requestedCount = $packageIds.Count
    deletedCount = 0
    deletedPackageIds = @()
    absentPackageIds = $absentIds
  })
  exit 0
}

$remaining = @($manifest.packages | Where-Object { -not $matchedSet.ContainsKey([string]$_.id) })
$repoPath = Split-Path -Parent (Resolve-Path -LiteralPath $ManifestPath)
$repoFullPath = [IO.Path]::GetFullPath($repoPath).TrimEnd('\') + '\'
$deletedFiles = @()
foreach ($package in $matches) {
  $url = [string]$package.url
  if ([string]::IsNullOrWhiteSpace($url)) { continue }
  if (@($remaining | Where-Object { [string]$_.url -eq $url }).Count -gt 0) { continue }
  $relativePath = Get-SourceRelativePath -Url $url
  $filePath = [IO.Path]::GetFullPath((Join-Path $repoPath ($relativePath -replace '/', '\')))
  if (-not $filePath.StartsWith($repoFullPath, [StringComparison]::OrdinalIgnoreCase)) {
    Stop-DeleteBatch "Resolved package path escapes repository"
  }
  if (Test-Path -LiteralPath $filePath -PathType Leaf) {
    Remove-Item -LiteralPath $filePath -Force
    $deletedFiles += $relativePath
  }
}

$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$auditEntry = [ordered]@{
  action = "delete-packages"
  packageIds = $matchedIds
  versions = @($matches | ForEach-Object { [string]$_.version })
  targets = @($matches | ForEach-Object { [string]$_.target })
  requestId = $RequestId
  actor = $Actor
  note = $AuditNote.Trim()
  timestamp = $timestamp
  deletedFiles = $deletedFiles
  absentPackageIds = $absentIds
}

$manifest.packages = $remaining
Set-ObjectProperty -Object $manifest -Name "generatedAt" -Value $timestamp
Set-ObjectProperty -Object $manifest -Name "audit" -Value (@($auditEntry) + $audit)

$manifestTemp = "$ManifestPath.tmp"
try {
  [IO.File]::WriteAllText(
    $manifestTemp,
    (($manifest | ConvertTo-Json -Depth 20) + "`n"),
    (New-Object Text.UTF8Encoding($false))
  )
  $check = [IO.File]::ReadAllText($manifestTemp) | ConvertFrom-Json
  if (@($check.packages | Where-Object { $matchedSet.ContainsKey([string]$_.id) }).Count -ne 0) {
    Stop-DeleteBatch "Deleted package remains in generated manifest"
  }
  Move-Item -LiteralPath $manifestTemp -Destination $ManifestPath -Force
} finally {
  Remove-Item -LiteralPath $manifestTemp -Force -ErrorAction SilentlyContinue
}

Write-Result ([ordered]@{
  ok = $true
  idempotent = $false
  requestId = $RequestId
  requestedCount = $packageIds.Count
  deletedCount = $matchedIds.Count
  deletedPackageIds = $matchedIds
  absentPackageIds = $absentIds
  deletedFiles = $deletedFiles
})
