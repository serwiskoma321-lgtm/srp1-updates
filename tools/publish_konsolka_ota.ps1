[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Mac,

  [string]$Version = "2.2.1",
  [string]$SketchPath = "C:\Users\SRynkiewicz\Documents\Arduino\Moje apki\Konsolka\Konsola_v2_2",
  [string]$RepoPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$compactMac = ($Mac -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
if ($compactMac.Length -ne 12) {
  throw "Niepoprawny MAC konsolki: $Mac"
}
$normalizedMac = (($compactMac -split '(.{2})' | Where-Object { $_ }) -join ':')

$publisher = Join-Path $PSScriptRoot "publish_sterownik_ota.ps1"
$fqbn = "esp32:esp32:esp32s3:UploadSpeed=921600,USBMode=hwcdc,CDCOnBoot=default,MSCOnBoot=default,DFUOnBoot=default,UploadMode=default,CPUFreq=240,FlashMode=qio,FlashSize=16M,PartitionScheme=app3M_fat9M_16MB,DebugLevel=none,PSRAM=disabled,LoopCore=1,EventsCore=1,EraseFlash=none,JTAGAdapter=default,ZigbeeMode=default"

& $publisher `
  -Version $Version `
  -SketchPath $SketchPath `
  -RepoPath $RepoPath `
  -Fqbn $fqbn `
  -Product "SRP-1" `
  -Target "konsolka" `
  -Vin "*" `
  -Mac $normalizedMac `
  -CompatVin @("*") `
  -CompatMac @($normalizedMac) `
  -Notes "Pierwsza paczka konsolki z identyfikacja firmware i metryka UART dla sterownika." `
  -PackageId "srp1-konsolka-$Version-emergency-usb" `
  -FileName "konsolka.kfw" `
  -EncryptPayload `
  -EmergencyUsb

if ($LASTEXITCODE -ne 0) {
  throw "Publikacja konsolki zakonczyla sie kodem $LASTEXITCODE"
}
