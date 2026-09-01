[CmdletBinding()]
param(
  [ValidateSet("Check", "Repair")]
  [string]$Mode = "Check",
  [string]$StatusFile,
  [switch]$Json
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$DevEcoDownloadUrl = "https://developer.huawei.com/consumer/cn/deveco-studio/"
$NodeDownloadUrl = "https://nodejs.org/en/download"
$ZedDownloadUrl = "https://zed.dev/download"

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

function Get-ZedStatus {
  $path = Resolve-Application @("zed.exe", "zed")
  if (-not $path) {
    $candidates = @()
    if ($env:LOCALAPPDATA) {
      $candidates += Join-Path $env:LOCALAPPDATA "Programs\Zed\Zed.exe"
      $candidates += Join-Path $env:LOCALAPPDATA "Zed\Zed.exe"
    }
    $path = $candidates | Where-Object { Test-Path $_ -PathType Leaf } | Select-Object -First 1
  }

  [pscustomobject]@{
    Ready = [bool]$path
    Path = $path
    Version = $null
    Requirement = "Zed"
  }
}

function Get-NodeStatus {
  $path = Resolve-Application @("node.exe", "node")
  $version = if ($path) { Read-CommandVersion $path } else { $null }
  $major = $null
  if ($version -and $version -match "v?(\d+)") {
    $major = [int]$Matches[1]
  }

  [pscustomobject]@{
    Ready = ($null -ne $major -and $major -ge 22)
    Path = $path
    Version = $version
    Requirement = if ($version) { "Node.js 22+（当前 $version）" } else { "Node.js 22+" }
  }
}

function Get-NpmStatus {
  $path = Resolve-Application @("npm.cmd", "npm.exe", "npm")
  $version = if ($path) { Read-CommandVersion $path } else { $null }

  [pscustomobject]@{
    Ready = [bool]($path -and $version)
    Path = $path
    Version = $version
    Requirement = "npm"
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

function Get-DevEcoToolchainStatus {
  foreach ($variableName in @("DEVECO_CLI_STUDIO_PATH", "DEVECO_CLI_CLT_PATH")) {
    $candidate = [Environment]::GetEnvironmentVariable($variableName, "Process")
    if ($candidate -and (Test-Path $candidate)) {
      return [pscustomobject]@{
        Ready = $true
        Path = $candidate
        Version = $null
        Requirement = "DevEco Studio 6.0+ 或 Command Line Tools 26.0+"
      }
    }
  }

  $registryPaths = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
  )
  $entry = Get-ItemProperty $registryPaths -ErrorAction SilentlyContinue |
    Where-Object {
      $property = $_.PSObject.Properties["DisplayName"]
      $property -and (
        $property.Value -like "*DevEco Studio*" -or
        $property.Value -like "*DevEco*Command Line Tools*" -or
        $property.Value -like "*HarmonyOS*Command Line Tools*"
      )
    } |
    Select-Object -First 1
  if ($entry) {
    $displayName = [string]$entry.PSObject.Properties["DisplayName"].Value
    $versionProperty = $entry.PSObject.Properties["DisplayVersion"]
    $locationProperty = $entry.PSObject.Properties["InstallLocation"]
    $displayVersion = if ($versionProperty) { [string]$versionProperty.Value } else { $null }
    $installLocation = if ($locationProperty) { [string]$locationProperty.Value } else { $null }
    $isClt = $displayName -like "*Command Line Tools*"
    $minimumMajor = if ($isClt) { 26 } else { 6 }
    $major = $null
    if ($displayVersion -and $displayVersion -match "^(\d+)") {
      $major = [int]$Matches[1]
    }
    return [pscustomobject]@{
      Ready = ($null -eq $major -or $major -ge $minimumMajor)
      Path = $installLocation
      Version = $displayVersion
      Requirement = "DevEco Studio 6.0+ 或 Command Line Tools 26.0+"
    }
  }

  $candidates = @()
  foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
    if ($root) {
      $candidates += Join-Path $root "Huawei\DevEco Studio"
      $candidates += Join-Path $root "Programs\Huawei\DevEco Studio"
    }
  }
  $path = $candidates | Where-Object { Test-Path $_ -PathType Container } | Select-Object -First 1

  [pscustomobject]@{
    Ready = [bool]$path
    Path = $path
    Version = $null
    Requirement = "DevEco Studio 6.0+ 或 Command Line Tools 26.0+"
  }
}

function Get-EnvironmentStatus {
  Refresh-ProcessPath
  $components = [ordered]@{
    Zed = Get-ZedStatus
    Node = Get-NodeStatus
    Npm = Get-NpmStatus
    DevEcoCli = Get-DevEcoCliStatus
    DevEcoToolchain = Get-DevEcoToolchainStatus
  }
  $missing = @($components.Values | Where-Object { -not $_.Ready } | ForEach-Object { $_.Requirement })

  [pscustomobject]@{
    Ready = ($missing.Count -eq 0)
    Summary = if ($missing.Count -eq 0) {
      "Zed、Node.js、npm、DevEco CLI 和 DevEco 工具链均已就绪。"
    } else {
      "缺少或版本不符合要求：" + ($missing -join "、")
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

  if (-not $Status.Components.Zed.Ready) {
    $installed = Invoke-Winget (@("install", "--exact", "--id", "ZedIndustries.Zed") + $wingetArguments)
    if (-not $installed) {
      Open-DownloadPage $ZedDownloadUrl
    }
  }

  if (-not $Status.Components.Node.Ready -or -not $Status.Components.Npm.Ready) {
    $updated = Invoke-Winget (@("upgrade", "--exact", "--id", "OpenJS.NodeJS.LTS") + $wingetArguments)
    if (-not $updated) {
      $updated = Invoke-Winget (@("install", "--exact", "--id", "OpenJS.NodeJS.LTS") + $wingetArguments)
    }
    if (-not $updated) {
      Open-DownloadPage $NodeDownloadUrl
    }
    Refresh-ProcessPath
  }

  $afterNode = Get-EnvironmentStatus
  if (-not $afterNode.Components.DevEcoCli.Ready -and $afterNode.Components.Npm.Ready) {
    $npm = $afterNode.Components.Npm.Path
    & $npm install --global "@deveco/deveco-cli@latest"
    if ($LASTEXITCODE -ne 0) {
      Write-Warning "DevEco CLI 安装失败，npm 退出码：$LASTEXITCODE"
    }
    Refresh-ProcessPath
  }

  if (-not $Status.Components.DevEcoToolchain.Ready) {
    Open-DownloadPage $DevEcoDownloadUrl
  }
}

$status = Get-EnvironmentStatus
if ($Mode -eq "Repair" -and -not $status.Ready) {
  Repair-Environment $status
  $status = Get-EnvironmentStatus
}

Write-StatusFile $status
if ($Json) {
  $status | ConvertTo-Json -Depth 5 -Compress
}

if ($status.Ready) {
  exit 0
}
exit 2
