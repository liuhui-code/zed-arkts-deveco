$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $env:RUNNER_TEMP "arkts-windows-integration"
$stateDirectory = Join-Path $testRoot "state"
$extensionDirectory = Join-Path $testRoot "extensions\installed\arkts"
$indexFile = Join-Path $testRoot "extensions\index.json"
$tasksFile = Join-Path $testRoot "tasks.json"
$wrapper = Join-Path $testRoot "deveco-command.cmd"

New-Item $extensionDirectory -ItemType Directory -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $extensionDirectory "extension.toml"), "id = `"arkts`"`nrepository = `"https://example.invalid/original`"`n", [Text.UTF8Encoding]::new($false))
$originalIndex = @{
  extensions = @{ arkts = @{ manifest = @{ id = "arkts"; repository = "https://example.invalid/original" }; dev = $false } }
  themes = @{}
  icon_themes = @{}
  languages = @{ ArkTS = @{ extension = "arkts"; path = "languages/arkts"; matcher = @{ path_suffixes = @("ets") }; hidden = $false; grammar = "arkts" } }
} | ConvertTo-Json -Depth 20
[IO.File]::WriteAllText($indexFile, $originalIndex, [Text.UTF8Encoding]::new($false))

$registration = Join-Path $root "installer\windows\extension-registration.ps1"
& $registration -Mode Prepare -StateDir $stateDirectory -ExtensionDir $extensionDirectory -IndexFile $indexFile -Version "0.4.1"
Remove-Item $extensionDirectory -Recurse -Force
New-Item $extensionDirectory -ItemType Directory -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $extensionDirectory "extension.toml"), "id = `"arkts`"`nrepository = `"https://github.com/liuhui-code/zed-arkts-deveco`"`n", [Text.UTF8Encoding]::new($false))
& $registration -Mode Install -StateDir $stateDirectory -ExtensionDir $extensionDirectory -IndexFile $indexFile -Version "0.4.1"
$registered = [IO.File]::ReadAllText($indexFile) | ConvertFrom-Json
if ($registered.extensions.arkts.manifest.version -ne "0.4.1") { throw "Packaged extension was not registered" }
& $registration -Mode Uninstall -StateDir $stateDirectory -ExtensionDir $extensionDirectory -IndexFile $indexFile
$restored = [IO.File]::ReadAllText($indexFile) | ConvertFrom-Json
if ($restored.extensions.arkts.manifest.repository -ne "https://example.invalid/original") { throw "Previous extension registration was not restored" }

[IO.File]::WriteAllText($wrapper, "@echo off`r`n", [Text.Encoding]::ASCII)
$originalTasks = "// existing`r`n[{`r`n  `"label`": `"Existing Task`",`r`n  `"command`": `"echo existing`"`r`n},]`r`n"
[IO.File]::WriteAllText($tasksFile, $originalTasks, [Text.UTF8Encoding]::new($false))
$taskRegistration = Join-Path $root "installer\windows\task-registration.ps1"
$sourceTasks = Join-Path $root "languages\arkts\tasks.json"
& $taskRegistration -Mode Install -StateDir $stateDirectory -SourceTasks $sourceTasks -CommandWrapper $wrapper -TasksFile $tasksFile
$installedTasks = [IO.File]::ReadAllText($tasksFile)
if ($installedTasks -notmatch 'ArkTS: Build Debug' -or -not $installedTasks.Contains($wrapper.Replace("\", "\\"))) { throw "Build tasks were not wired through the command wrapper" }
& $taskRegistration -Mode Uninstall -StateDir $stateDirectory -TasksFile $tasksFile
if ([IO.File]::ReadAllText($tasksFile) -cne $originalTasks) { throw "Existing task configuration was not restored" }

$fakeBin = Join-Path $testRoot "bin"
New-Item $fakeBin -ItemType Directory -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $fakeBin "node.cmd"), "@echo off`r`necho v22.0.0`r`n", [Text.Encoding]::ASCII)
$env:APPDATA = Join-Path $testRoot "app-data"
$npmGlobalBin = Join-Path $env:APPDATA "npm"
New-Item $npmGlobalBin -ItemType Directory -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $npmGlobalBin "devecocli.cmd"), "@echo off`r`necho fake-devecocli %*`r`n", [Text.Encoding]::ASCII)
$env:Path = "$fakeBin;$env:Path"
$env:LOCALAPPDATA = Join-Path $testRoot "local-app-data"
& (Join-Path $root "installer\windows\deveco-command.ps1") build --build-mode debug
if ($LASTEXITCODE -ne 0) { throw "Command wrapper changed the CLI exit code" }
$summaryFile = Get-Item (Join-Path $env:LOCALAPPDATA "ArkTSDevEco\logs\command-summary-*.json")
$summary = [IO.File]::ReadAllText($summaryFile.FullName) | ConvertFrom-Json
if ($summary.status -ne "succeeded" -or ($summary.arguments -join " ") -ne "build --build-mode debug") { throw "Command summary is incomplete" }
if ($summary.resolvedCommand -ne (Join-Path $npmGlobalBin "devecocli.cmd")) { throw "Command wrapper did not discover the default npm global bin directory" }

Write-Host "Windows extension, task, and command integration tests passed"
