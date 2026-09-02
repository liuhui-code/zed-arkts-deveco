[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("Prepare", "Install", "Uninstall")]
  [string]$Mode,
  [Parameter(Mandatory = $true)]
  [string]$StateDir,
  [string]$Version = "0.4.0",
  [string]$ExtensionDir = (Join-Path $env:LOCALAPPDATA "Zed\extensions\installed\arkts"),
  [string]$IndexFile = (Join-Path $env:LOCALAPPDATA "Zed\extensions\index.json")
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$stateFile = Join-Path $StateDir "extension-registration-state.json"
$backupDirectory = Join-Path $StateDir "extension-before-arkts-deveco"
$utf8NoBom = New-Object Text.UTF8Encoding -ArgumentList $false

function Ensure-Property {
  param($Object, [string]$Name, $DefaultValue)
  if (-not $Object.PSObject.Properties[$Name]) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $DefaultValue
  }
  return $Object.$Name
}

function Get-PropertyValue {
  param($Object, [string]$Name)
  $property = $Object.PSObject.Properties[$Name]
  if ($property) { return $property.Value }
  return $null
}

function Set-PropertyValue {
  param($Object, [string]$Name, $Value)
  $property = $Object.PSObject.Properties[$Name]
  if ($property) { $property.Value = $Value } else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Remove-PropertyValue {
  param($Object, [string]$Name)
  if ($Object.PSObject.Properties[$Name]) { $Object.PSObject.Properties.Remove($Name) }
}

function Read-Index {
  if (Test-Path $IndexFile -PathType Leaf) {
    return ([IO.File]::ReadAllText($IndexFile, [Text.Encoding]::UTF8) | ConvertFrom-Json)
  }
  return [pscustomobject][ordered]@{
    extensions = [pscustomobject]@{}
    themes = [pscustomobject]@{}
    icon_themes = [pscustomobject]@{}
    languages = [pscustomobject]@{}
  }
}

function Write-Index {
  param($Index)
  $directory = Split-Path -Parent $IndexFile
  New-Item $directory -ItemType Directory -Force | Out-Null
  $temporary = "$IndexFile.arkts-deveco.tmp"
  [IO.File]::WriteAllText($temporary, (($Index | ConvertTo-Json -Depth 20) + "`n"), $utf8NoBom)
  Move-Item $temporary $IndexFile -Force
}

function Prepare-Registration {
  New-Item $StateDir -ItemType Directory -Force | Out-Null
  if (Test-Path $stateFile -PathType Leaf) { return }

  $index = Read-Index
  $extensions = Ensure-Property $index "extensions" ([pscustomobject]@{})
  $languages = Ensure-Property $index "languages" ([pscustomobject]@{})
  $previousExtensionEntry = Get-PropertyValue $extensions "arkts"
  $previousLanguageEntry = Get-PropertyValue $languages "ArkTS"
  $state = [ordered]@{
    indexExisted = (Test-Path $IndexFile -PathType Leaf)
    hadExtensionEntry = ($null -ne $previousExtensionEntry)
    extensionEntry = $previousExtensionEntry
    hadLanguageEntry = ($null -ne $previousLanguageEntry)
    languageEntry = $previousLanguageEntry
    extensionDirectoryBackedUp = $false
  }

  if (Test-Path $ExtensionDir -PathType Container) {
    $manifestPath = Join-Path $ExtensionDir "extension.toml"
    $isThisProduct = (Test-Path $manifestPath -PathType Leaf) -and
      ([IO.File]::ReadAllText($manifestPath) -match 'liuhui-code/zed-arkts-deveco')
    if (-not $isThisProduct) {
      Copy-Item $ExtensionDir $backupDirectory -Recurse -Force
      $state.extensionDirectoryBackedUp = $true
    }
  }

  [IO.File]::WriteAllText($stateFile, (($state | ConvertTo-Json -Depth 20) + "`n"), $utf8NoBom)
}

function Install-Registration {
  if (-not (Test-Path (Join-Path $ExtensionDir "extension.toml") -PathType Leaf)) {
    throw "Packaged ArkTS extension is missing from $ExtensionDir"
  }

  $index = Read-Index
  $extensions = Ensure-Property $index "extensions" ([pscustomobject]@{})
  $languages = Ensure-Property $index "languages" ([pscustomobject]@{})
  Remove-PropertyValue $extensions "arkts-deveco"
  Remove-PropertyValue $languages "ArkTS DevEco"

  $manifest = [ordered]@{
    id = "arkts"
    name = "ArkTS"
    version = $Version
    schema_version = 1
    description = "ArkTS language support and DevEco CLI build tasks for HarmonyOS projects"
    repository = "https://github.com/liuhui-code/zed-arkts-deveco"
    authors = @("liuhui-code", "liuyanghejerry <liuyanghejerry@126.com>")
    lib = [ordered]@{ kind = "Rust"; version = "0.7.0" }
    themes = @()
    icon_themes = @()
    languages = @("languages/arkts")
    grammars = [ordered]@{
      arkts = [ordered]@{
        repository = "https://github.com/liuyanghejerry/tree-sitter-arkts.git"
        rev = "2b3d4b944ea4417729ebcd030834a5352cff7bb2"
        path = $null
      }
    }
    language_servers = [ordered]@{
      "arkts-language-server" = [ordered]@{
        language = $null
        languages = @("ArkTS")
        language_ids = [ordered]@{ ArkTS = "ets" }
        code_action_kinds = $null
      }
    }
    context_servers = [ordered]@{}
    agent_servers = [ordered]@{}
    slash_commands = [ordered]@{}
    snippets = $null
    capabilities = @()
  }
  Set-PropertyValue $extensions "arkts" ([pscustomobject][ordered]@{
    manifest = [pscustomobject]$manifest
    dev = $false
  })
  Set-PropertyValue $languages "ArkTS" ([pscustomobject][ordered]@{
    extension = "arkts"
    path = "languages/arkts"
    matcher = [pscustomobject][ordered]@{
      path_suffixes = @("ets")
      first_line_pattern = $null
      modeline_aliases = @()
    }
    hidden = $false
    grammar = "arkts"
  })
  Write-Index $index
}

function Uninstall-Registration {
  $index = Read-Index
  $extensions = Ensure-Property $index "extensions" ([pscustomobject]@{})
  $languages = Ensure-Property $index "languages" ([pscustomobject]@{})
  Remove-PropertyValue $extensions "arkts"
  Remove-PropertyValue $languages "ArkTS"
  Remove-PropertyValue $extensions "arkts-deveco"
  Remove-PropertyValue $languages "ArkTS DevEco"

  if (Test-Path $stateFile -PathType Leaf) {
    $state = [IO.File]::ReadAllText($stateFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($state.hadExtensionEntry) { Set-PropertyValue $extensions "arkts" $state.extensionEntry }
    if ($state.hadLanguageEntry) { Set-PropertyValue $languages "ArkTS" $state.languageEntry }
  }
  Write-Index $index

  Remove-Item $ExtensionDir -Recurse -Force -ErrorAction SilentlyContinue
  if (Test-Path $backupDirectory -PathType Container) {
    Copy-Item $backupDirectory $ExtensionDir -Recurse -Force
  }
}

switch ($Mode) {
  "Prepare" { Prepare-Registration }
  "Install" { Install-Registration }
  "Uninstall" { Uninstall-Registration }
}
