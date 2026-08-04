[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$PackageId,

  [string]$AuditNote = "",
  [string]$RequestId = "",
  [string]$Actor = "",
  [string]$ManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "manifest.json"),
  [string]$ResultPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-Delete {
  param([string]$Message)
  throw "[delete_firmware_package] $Message"
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
    Stop-Delete "Package URL points outside srp1-updates/main"
  }
  return [Uri]::UnescapeDataString($uri.AbsolutePath.Substring($index + $marker.Length))
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
  Stop-Delete "Manifest not found"
}
if ($PackageId.Trim().Length -eq 0) {
  Stop-Delete "Package ID is empty"
}
if ($RequestId.Length -eq 0) {
  $RequestId = [Guid]::NewGuid().ToString("N")
}
if ($RequestId -notmatch '^[A-Za-z0-9._-]{1,80}$') {
  Stop-Delete "RequestId contains forbidden characters"
}
if ($Actor.Length -gt 80 -or $AuditNote.Length -gt 500) {
  Stop-Delete "Actor or audit note is too long"
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
  $result = [ordered]@{
    ok = $true
    idempotent = $true
    requestId = $RequestId
    packageId = $PackageId
    fileDeleted = $false
  }
  $resultJson = $result | ConvertTo-Json -Depth 5
  if ($ResultPath.Length -gt 0) {
    [IO.File]::WriteAllText(
      $ResultPath,
      $resultJson,
      (New-Object Text.UTF8Encoding($false))
    )
  }
  Write-Output $resultJson
  exit 0
}

$matches = @($manifest.packages | Where-Object { $_.id -eq $PackageId })
if ($matches.Count -eq 0) {
  $result = [ordered]@{
    ok = $true
    idempotent = $true
    requestId = $RequestId
    packageId = $PackageId
    fileDeleted = $false
  }
  $resultJson = $result | ConvertTo-Json -Depth 5
  if ($ResultPath.Length -gt 0) {
    [IO.File]::WriteAllText(
      $ResultPath,
      $resultJson,
      (New-Object Text.UTF8Encoding($false))
    )
  }
  Write-Output $resultJson
  exit 0
}
if ($matches.Count -gt 1) {
  Stop-Delete "Expected exactly one package with id $PackageId"
}
$package = $matches[0]
$remaining = @($manifest.packages | Where-Object { $_.id -ne $PackageId })
$sameUrl = @($remaining | Where-Object { $_.url -eq $package.url })

$repoPath = Split-Path -Parent (Resolve-Path -LiteralPath $ManifestPath)
$deletedFile = $false
if ($sameUrl.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$package.url)) {
  $relativePath = Get-SourceRelativePath -Url ([string]$package.url)
  $filePath = [IO.Path]::GetFullPath((Join-Path $repoPath ($relativePath -replace '/', '\')))
  $repoFullPath = [IO.Path]::GetFullPath($repoPath).TrimEnd('\') + '\'
  if (-not $filePath.StartsWith($repoFullPath, [StringComparison]::OrdinalIgnoreCase)) {
    Stop-Delete "Resolved package path escapes repository"
  }
  if (Test-Path -LiteralPath $filePath -PathType Leaf) {
    Remove-Item -LiteralPath $filePath -Force
    $deletedFile = $true
  }
}

$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$auditEntry = [ordered]@{
  action = "delete-package"
  packageId = $PackageId
  version = [string]$package.version
  target = [string]$package.target
  requestId = $RequestId
  actor = $Actor
  note = $AuditNote.Trim()
  timestamp = $timestamp
  fileDeleted = $deletedFile
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
  if (@($check.packages | Where-Object { $_.id -eq $PackageId }).Count -ne 0) {
    Stop-Delete "Deleted package remains in generated manifest"
  }
  Move-Item -LiteralPath $manifestTemp -Destination $ManifestPath -Force
} finally {
  Remove-Item -LiteralPath $manifestTemp -Force -ErrorAction SilentlyContinue
}

$result = [ordered]@{
  ok = $true
  idempotent = $false
  requestId = $RequestId
  packageId = $PackageId
  fileDeleted = $deletedFile
}
$resultJson = $result | ConvertTo-Json -Depth 5
if ($ResultPath.Length -gt 0) {
  [IO.File]::WriteAllText(
    $ResultPath,
    $resultJson,
    (New-Object Text.UTF8Encoding($false))
  )
}
Write-Output $resultJson
