[CmdletBinding()]
param(
  [ValidateSet("Check", "Repair")]
  [string]$Mode = "Check",
  [string]$StatusFile,
  [switch]$Json
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$NodeDownloadUrl = "https://nodejs.org/en/download"

function Refresh-ProcessPath {
  $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $paths = @($env:Path, $machinePath, $userPath) |
    Where-Object { $_ } |
    ForEach-Object { $_ -split ";" } |
    Where-Object { $_ } |
    Select-Object -Unique
  $env:Path = $paths -join ";"
}

function Resolve-Application {
  param([string[]]$Names)

  foreach ($name in $Names) {
    $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($command) {
      return $command.Source
    }
  }

  if ($Names -contains "devecocli") {
    $candidates = @()
    if ($env:APPDATA) {
      $candidates += Join-Path $env:APPDATA "npm\devecocli.cmd"
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

function Read-CommandVersion {
  param([string]$Path)

  try {
    $output = & $Path --version 2>&1
    if ($LASTEXITCODE -ne 0) {
      return $null
    }
    return (($output | Out-String).Trim())
  } catch {
    return $null
  }
}

function Get-NodeStatus {
  $path = Resolve-Application @("node.cmd", "node.exe", "node")
  $version = if ($path) { Read-CommandVersion $path } else { $null }

  [pscustomobject]@{
    Ready = [bool]($path -and $version)
    Path = $path
    Version = $version
    Requirement = "Node.js"
  }
}

function Get-DevEcoCliStatus {
  $path = Resolve-Application @("devecocli.cmd", "devecocli.exe", "devecocli")
  $version = if ($path) { Read-CommandVersion $path } else { $null }

  [pscustomobject]@{
    Ready = [bool]($path -and $version)
    Path = $path
    Version = $version
    Requirement = "DevEco CLI"
  }
}

function Get-EnvironmentStatus {
  Refresh-ProcessPath
  $components = [ordered]@{
    Node = Get-NodeStatus
    DevEcoCli = Get-DevEcoCliStatus
  }
  $missing = @($components.Values | Where-Object { -not $_.Ready } | ForEach-Object { $_.Requirement })

  [pscustomobject]@{
    Ready = ($missing.Count -eq 0)
    Summary = if ($missing.Count -eq 0) {
      "Node.js 和 DevEco CLI 均已安装且可用。"
    } else {
      "缺少或无法运行：" + ($missing -join "、")
    }
    Components = [pscustomobject]$components
  }
}

function Write-StatusFile {
  param($Status)

  if (-not $StatusFile) {
    return
  }
  $safeSummary = $Status.Summary -replace "[\r\n]", " "
  $ready = if ($Status.Ready) { "1" } else { "0" }
  $content = "[environment]`r`nready=$ready`r`nsummary=$safeSummary`r`n"
  [IO.File]::WriteAllText($StatusFile, $content, [Text.Encoding]::Unicode)
}

function Invoke-Winget {
  param([string[]]$Arguments)

  $winget = Resolve-Application @("winget.exe", "winget")
  if (-not $winget) {
    return $false
  }
  $process = Start-Process -FilePath $winget -ArgumentList $Arguments -Wait -PassThru
  return ($process.ExitCode -eq 0)
}

function Open-DownloadPage {
  param([string]$Url)

  try {
    Start-Process $Url | Out-Null
  } catch {
    # The final status still reports the unresolved requirement.
  }
}

function Repair-Environment {
  param($Status)

  $wingetArguments = @("--accept-source-agreements", "--accept-package-agreements", "--silent")

  if (-not $Status.Components.Node.Ready) {
    $installed = Invoke-Winget (@("install", "--exact", "--id", "OpenJS.NodeJS.LTS") + $wingetArguments)
    if (-not $installed) {
      Open-DownloadPage $NodeDownloadUrl
    }
    Refresh-ProcessPath
  }

  $afterNode = Get-EnvironmentStatus
  if (-not $afterNode.Components.DevEcoCli.Ready) {
    $npm = Resolve-Application @("npm.cmd", "npm.exe", "npm")
    if ($npm) {
      & $npm install --global "@deveco/deveco-cli@latest"
      if ($LASTEXITCODE -ne 0) {
        Write-Warning "DevEco CLI 安装失败，npm 退出码：$LASTEXITCODE"
      }
      Refresh-ProcessPath
    }
  }
}

$status = Get-EnvironmentStatus
if ($Mode -eq "Repair" -and -not $status.Ready) {
  Repair-Environment $status
  $status = Get-EnvironmentStatus
}

Write-StatusFile $status
$stateDirectory = Join-Path $env:LOCALAPPDATA "ArkTSDevEco"
New-Item $stateDirectory -ItemType Directory -Force | Out-Null
$statusRecord = [ordered]@{
  checkedAt = (Get-Date).ToUniversalTime().ToString("o")
  mode = $Mode
  ready = $status.Ready
  summary = $status.Summary
  components = $status.Components
}
$utf8NoBom = New-Object Text.UTF8Encoding -ArgumentList $false
[IO.File]::WriteAllText(
  (Join-Path $stateDirectory "environment-check.json"),
  (($statusRecord | ConvertTo-Json -Depth 6) + "`n"),
  $utf8NoBom
)
if ($Json) {
  $status | ConvertTo-Json -Depth 5 -Compress
}

if ($status.Ready) {
  exit 0
}
exit 2
