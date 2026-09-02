[CmdletBinding()]
param(
  [string]$OutputDirectory = ([Environment]::GetFolderPath("Desktop"))
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$stateDirectory = Join-Path $env:LOCALAPPDATA "ArkTSDevEco"
$logDirectory = Join-Path $stateDirectory "logs"

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$stagingDirectory = Join-Path $env:TEMP "ArkTSDevEco-diagnostics-$timestamp-$PID"
$archive = Join-Path $OutputDirectory "ArkTSDevEco-diagnostics-$timestamp.zip"
New-Item $stagingDirectory -ItemType Directory -Force | Out-Null
New-Item $OutputDirectory -ItemType Directory -Force | Out-Null

try {
  if (Test-Path $logDirectory -PathType Container) {
    Copy-Item $logDirectory (Join-Path $stagingDirectory "logs") -Recurse -Force
  }

  $nodeVersion = try { (& node --version 2>&1 | Out-String).Trim() } catch { "unavailable" }
  $npmVersion = try { (& npm --version 2>&1 | Out-String).Trim() } catch { "unavailable" }
  $devecocliCommand = Get-Command @("devecocli.cmd", "devecocli.exe", "devecocli") -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  $devecocliPath = if ($devecocliCommand) { $devecocliCommand.Source } else { $null }
  $devecocliVersion = if ($devecocliPath) { try { (& $devecocliPath --version 2>&1 | Out-String).Trim() } catch { "unavailable" } } else { "unavailable" }
  $lspHelpAvailable = if ($devecocliPath) {
    try {
      & $devecocliPath serve lsp --help *> $null
      $LASTEXITCODE -eq 0
    } catch { $false }
  } else { $false }
  $extensionDirectory = Join-Path $env:LOCALAPPDATA "Zed\extensions\installed\arkts"
  $extensionManifest = Join-Path $extensionDirectory "extension.toml"
  $extensionIndex = Join-Path $env:LOCALAPPDATA "Zed\extensions\index.json"
  $tasksFile = Join-Path $env:APPDATA "Zed\tasks.json"
  $wrapper = Join-Path $stateDirectory "deveco-command.cmd"
  $manifestText = if (Test-Path $extensionManifest -PathType Leaf) { [IO.File]::ReadAllText($extensionManifest) } else { "" }
  $tasksText = if (Test-Path $tasksFile -PathType Leaf) { [IO.File]::ReadAllText($tasksFile) } else { "" }
  $indexRegistrationValid = $false
  if (Test-Path $extensionIndex -PathType Leaf) {
    try {
      $index = [IO.File]::ReadAllText($extensionIndex) | ConvertFrom-Json
      $indexRegistrationValid = [bool]($index.extensions.arkts.manifest.repository -eq "https://github.com/liuhui-code/zed-arkts-deveco")
    } catch {}
  }
  $registeredTaskLabels = @([regex]::Matches($tasksText, '"label"\s*:\s*"ArkTS:[^"]+"') | ForEach-Object { $_.Value })
  $metadata = [ordered]@{
    collectedAt = (Get-Date).ToUniversalTime().ToString("o")
    windowsVersion = [Environment]::OSVersion.VersionString
    processArchitecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    nodeVersion = $nodeVersion
    npmVersion = $npmVersion
    devecocliPath = $devecocliPath
    devecocliVersion = $devecocliVersion
    officialLspCommandAvailable = $lspHelpAvailable
    devecoSdkHomeConfigured = [bool]$env:DEVECO_SDK_HOME
    logDirectory = $logDirectory
    logDirectoryExists = (Test-Path $logDirectory -PathType Container)
    extensionManifest = $extensionManifest
    extensionInstalled = [bool]($manifestText -match 'id\s*=\s*"arkts"' -and $manifestText -match 'liuhui-code/zed-arkts-deveco')
    extensionIndex = $extensionIndex
    extensionIndexRegistered = $indexRegistrationValid
    tasksFile = $tasksFile
    registeredArktsTaskCount = $registeredTaskLabels.Count
    commandWrapper = $wrapper
    commandWrapperInstalled = (Test-Path $wrapper -PathType Leaf)
  }
  $metadata | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $stagingDirectory "environment.json") -Encoding UTF8

  $latestLspSummary = Get-ChildItem $logDirectory -Filter "session-summary-*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $latestCommandSummary = Get-ChildItem $logDirectory -Filter "command-summary-*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $report = @(
    "ArkTS DevEco diagnostics",
    "Collected: $($metadata.collectedAt)",
    "Extension installed: $($metadata.extensionInstalled)",
    "Extension registered in Zed index: $($metadata.extensionIndexRegistered)",
    "ArkTS tasks registered: $($metadata.registeredArktsTaskCount)",
    "Command wrapper installed: $($metadata.commandWrapperInstalled)",
    "DevEco CLI: $($metadata.devecocliPath)",
    "DevEco CLI version: $($metadata.devecocliVersion)",
    "Official ArkTS LSP command available: $($metadata.officialLspCommandAvailable)",
    "Latest LSP summary: $(if ($latestLspSummary) { $latestLspSummary.Name } else { 'none - the LSP was never started' })",
    "Latest build/task summary: $(if ($latestCommandSummary) { $latestCommandSummary.Name } else { 'none - no packaged task was executed' })"
  )
  $report | Set-Content (Join-Path $stagingDirectory "REPORT.txt") -Encoding UTF8

  foreach ($zedLogDirectory in @(
    (Join-Path $env:LOCALAPPDATA "Zed\logs"),
    (Join-Path $env:APPDATA "Zed\logs")
  )) {
    if (Test-Path $zedLogDirectory -PathType Container) {
      Copy-Item $zedLogDirectory (Join-Path $stagingDirectory "zed-logs") -Recurse -Force
      break
    }
  }

  foreach ($devecoLogDirectory in @(
    (Join-Path $env:LOCALAPPDATA "devecocli-mcp-server\logs"),
    (Join-Path $env:LOCALAPPDATA "devecocli-mcp-server")
  )) {
    if (Test-Path $devecoLogDirectory -PathType Container) {
      Copy-Item $devecoLogDirectory (Join-Path $stagingDirectory "devecocli-lsp-logs") -Recurse -Force
      break
    }
  }

  if (Test-Path $archive -PathType Leaf) { Remove-Item $archive -Force }
  Compress-Archive -Path (Join-Path $stagingDirectory "*") -DestinationPath $archive -CompressionLevel Optimal
  Write-Host "Diagnostics package created: $archive"
} finally {
  Remove-Item $stagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
