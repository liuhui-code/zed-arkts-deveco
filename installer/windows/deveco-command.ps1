[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CommandArguments
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$stateDirectory = Join-Path $env:LOCALAPPDATA "ArkTSDevEco"
$logDirectory = Join-Path $stateDirectory "logs"
New-Item $logDirectory -ItemType Directory -Force | Out-Null

$sessionId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff"), $PID
$eventFile = Join-Path $logDirectory "command-$sessionId.jsonl"
$summaryFile = Join-Path $logDirectory "command-summary-$sessionId.json"
$outputFile = Join-Path $logDirectory "command-output-$sessionId.log"
$utf8NoBom = New-Object Text.UTF8Encoding -ArgumentList $false

function Write-Event {
  param([string]$Event, [hashtable]$Data = @{})

  $record = [ordered]@{
    schemaVersion = 1
    timestamp = (Get-Date).ToUniversalTime().ToString("o")
    event = $Event
    processId = $PID
  }
  foreach ($key in $Data.Keys) { $record[$key] = $Data[$key] }
  [IO.File]::AppendAllText($eventFile, (($record | ConvertTo-Json -Depth 8 -Compress) + "`n"), $utf8NoBom)
}

function Write-Summary {
  param($Summary)
  [IO.File]::WriteAllText($summaryFile, (($Summary | ConvertTo-Json -Depth 8) + "`n"), $utf8NoBom)
}

function Resolve-Application {
  param([string[]]$Names)

  $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $pathEntries = @($env:Path, $machinePath, $userPath) |
    Where-Object { $_ } |
    ForEach-Object { $_ -split ";" } |
    Where-Object { $_ } |
    Select-Object -Unique
  $env:Path = $pathEntries -join ";"

  foreach ($name in $Names) {
    $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
  }

  if ($Names -contains "devecocli") {
    $candidates = @()
    if ($env:APPDATA) {
      $candidates += Join-Path $env:APPDATA "npm\devecocli.cmd"
    }
    $environmentCheck = Join-Path $stateDirectory "environment-check.json"
    if (Test-Path $environmentCheck -PathType Leaf) {
      try {
        $recorded = [IO.File]::ReadAllText($environmentCheck) | ConvertFrom-Json
        $candidates += $recorded.components.DevEcoCli.Path
      } catch {}
    }
    $npm = Get-Command @("npm.cmd", "npm.exe", "npm") -CommandType Application -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($npm) {
      try {
        $prefix = ((& $npm.Source config get prefix 2>$null | Select-Object -Last 1) | Out-String).Trim()
        if ($prefix) { $candidates += Join-Path $prefix "devecocli.cmd" }
      } catch {}
    }
    foreach ($candidate in $candidates | Where-Object { $_ } | Select-Object -Unique) {
      if (Test-Path $candidate -PathType Leaf) { return (Resolve-Path $candidate).Path }
    }
  }
  return $null
}

$devecocli = Resolve-Application @("devecocli.cmd", "devecocli.exe", "devecocli")
$node = Resolve-Application @("node.exe", "node.cmd", "node")
$nodeVersion = if ($node) { try { ((& $node --version 2>&1 | Out-String).Trim()) } catch { $null } } else { $null }
$devecocliVersion = if ($devecocli) { try { ((& $devecocli --version 2>&1 | Out-String).Trim()) } catch { $null } } else { $null }
$startedAt = Get-Date
$workingDirectory = (Get-Location).Path
$toolchainEnvironment = [ordered]@{
  DEVECO_CLI_STUDIO_PATH = $env:DEVECO_CLI_STUDIO_PATH
  DEVECO_CLI_CLT_PATH = $env:DEVECO_CLI_CLT_PATH
  DEVECO_SDK_HOME = $env:DEVECO_SDK_HOME
  OHOS_BASE_SDK_HOME = $env:OHOS_BASE_SDK_HOME
}
$projectMarkers = [ordered]@{
  buildProfile = (Test-Path (Join-Path $workingDirectory "build-profile.json5") -PathType Leaf)
  ohPackage = (Test-Path (Join-Path $workingDirectory "oh-package.json5") -PathType Leaf)
  localProperties = (Test-Path (Join-Path $workingDirectory "local.properties") -PathType Leaf)
}

$summary = [ordered]@{
  schemaVersion = 1
  sessionId = $sessionId
  status = "starting"
  startedAt = $startedAt.ToUniversalTime().ToString("o")
  workingDirectory = $workingDirectory
  command = "devecocli"
  arguments = @($CommandArguments)
  resolvedCommand = $devecocli
  devecocliVersion = $devecocliVersion
  node = $node
  nodeVersion = $nodeVersion
  toolchainEnvironment = $toolchainEnvironment
  projectMarkers = $projectMarkers
  outputFile = $outputFile
  eventFile = $eventFile
}
Write-Summary $summary
Write-Event "command-start" @{
  workingDirectory = $summary.workingDirectory
  arguments = @($CommandArguments)
  resolvedCommand = $devecocli
  devecocliVersion = $devecocliVersion
  node = $node
  nodeVersion = $nodeVersion
  toolchainEnvironment = $toolchainEnvironment
  projectMarkers = $projectMarkers
  outputFile = $outputFile
}

if (-not $devecocli) {
  $summary.status = "command-not-found"
  $summary.exitCode = 127
  $summary.finishedAt = (Get-Date).ToUniversalTime().ToString("o")
  Write-Summary $summary
  Write-Event "command-not-found" @{ command = "devecocli"; exitCode = 127 }
  [Console]::Error.WriteLine("ArkTS DevEco: devecocli was not found in PATH, the npm global prefix, or %APPDATA%\npm. Run: npm install -g @deveco/deveco-cli@stable")
  exit 127
}

$exitCode = 1
try {
  $ErrorActionPreference = "Continue"
  & $devecocli @CommandArguments 2>&1 | Tee-Object -FilePath $outputFile -Append
  $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
} catch {
  $_ | Out-String | Tee-Object -FilePath $outputFile -Append | Write-Host
  Write-Event "command-error" @{ message = $_.Exception.Message }
  $exitCode = 1
} finally {
  $finishedAt = Get-Date
  $summary.status = if ($exitCode -eq 0) { "succeeded" } else { "failed" }
  $summary.exitCode = $exitCode
  $summary.finishedAt = $finishedAt.ToUniversalTime().ToString("o")
  $summary.durationMs = [Math]::Round(($finishedAt - $startedAt).TotalMilliseconds)
  Write-Summary $summary
  Write-Event "command-exit" @{
    exitCode = $exitCode
    durationMs = $summary.durationMs
    outputFile = $outputFile
  }
}

exit $exitCode
