[CmdletBinding()]
param(
  [string]$OutputDirectory = ([Environment]::GetFolderPath("Desktop"))
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$stateDirectory = Join-Path $env:LOCALAPPDATA "ArkTSDevEco"
$logDirectory = Join-Path $stateDirectory "logs"
if (-not (Test-Path $logDirectory -PathType Container)) {
  throw "No ArkTS DevEco diagnostic logs were found in $logDirectory"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$stagingDirectory = Join-Path $env:TEMP "ArkTSDevEco-diagnostics-$timestamp-$PID"
$archive = Join-Path $OutputDirectory "ArkTSDevEco-diagnostics-$timestamp.zip"
New-Item $stagingDirectory -ItemType Directory -Force | Out-Null
New-Item $OutputDirectory -ItemType Directory -Force | Out-Null

try {
  Copy-Item $logDirectory (Join-Path $stagingDirectory "logs") -Recurse -Force

  $nodeVersion = try { (& node --version 2>&1 | Out-String).Trim() } catch { "unavailable" }
  $npmVersion = try { (& npm --version 2>&1 | Out-String).Trim() } catch { "unavailable" }
  $metadata = [ordered]@{
    collectedAt = (Get-Date).ToUniversalTime().ToString("o")
    windowsVersion = [Environment]::OSVersion.VersionString
    processArchitecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    nodeVersion = $nodeVersion
    npmVersion = $npmVersion
    devecoSdkHomeConfigured = [bool]$env:DEVECO_SDK_HOME
    logDirectory = $logDirectory
  }
  $metadata | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $stagingDirectory "environment.json") -Encoding UTF8

  foreach ($zedLogDirectory in @(
    (Join-Path $env:LOCALAPPDATA "Zed\logs"),
    (Join-Path $env:APPDATA "Zed\logs")
  )) {
    if (Test-Path $zedLogDirectory -PathType Container) {
      Copy-Item $zedLogDirectory (Join-Path $stagingDirectory "zed-logs") -Recurse -Force
      break
    }
  }

  if (Test-Path $archive -PathType Leaf) { Remove-Item $archive -Force }
  Compress-Archive -Path (Join-Path $stagingDirectory "*") -DestinationPath $archive -CompressionLevel Optimal
  Write-Host "Diagnostics package created: $archive"
} finally {
  Remove-Item $stagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

