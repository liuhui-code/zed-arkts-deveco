param(
  [string]$Version = "0.3.4"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Dist = Join-Path $Root "dist"
$Stage = Join-Path $Dist "arkts-deveco"
$GrammarArchive = Join-Path $Dist "arkts-grammar.tar.gz"
$ExpectedGrammarArchiveSha256 = "7fdf1154fa0a55e84d455be5fd60ca721d63c0d5f449ae1b3b106fc4b46bf1f6"
$InstallerScript = Join-Path $Root "installer\windows\installer.nsi"

$installerBytes = [IO.File]::ReadAllBytes($InstallerScript)
if ($installerBytes.Length -lt 3 -or
    $installerBytes[0] -ne 0xEF -or
    $installerBytes[1] -ne 0xBB -or
    $installerBytes[2] -ne 0xBF) {
  throw "installer.nsi must be UTF-8 with BOM so Windows NSIS preserves Chinese text"
}

Remove-Item $Dist -Recurse -Force -ErrorAction SilentlyContinue
New-Item $Stage -ItemType Directory -Force | Out-Null

rustup target add wasm32-wasip2
cargo build --manifest-path (Join-Path $Root "Cargo.toml") --release --target wasm32-wasip2

Copy-Item (Join-Path $Root "extension.toml") $Stage
Add-Content (Join-Path $Stage "extension.toml") "`n[lib]`nkind = `"Rust`"`nversion = `"0.7.0`""
Copy-Item (Join-Path $Root "languages") $Stage -Recurse
Copy-Item (Join-Path $Root "LICENSE") $Stage
Copy-Item (Join-Path $Root "THIRD_PARTY_NOTICES.md") $Stage
Copy-Item (Join-Path $Root "target\wasm32-wasip2\release\zed_arkts_deveco.wasm") (Join-Path $Stage "extension.wasm")

Invoke-WebRequest "https://api.zed.dev/extensions/arkts/0.3.0/download" -OutFile $GrammarArchive
$ActualHash = (Get-FileHash $GrammarArchive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($ActualHash -ne $ExpectedGrammarArchiveSha256) {
  throw "Unexpected grammar archive SHA-256: $ActualHash"
}

$GrammarTemp = Join-Path $Dist "grammar-source"
New-Item $GrammarTemp -ItemType Directory -Force | Out-Null
tar -xzf $GrammarArchive -C $GrammarTemp
New-Item (Join-Path $Stage "grammars") -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $GrammarTemp "grammars\arkts.wasm") (Join-Path $Stage "grammars\arkts.wasm")

$ExtensionArchive = Join-Path $Dist "zed-arkts-deveco-$Version.tar.gz"
tar -czf $ExtensionArchive -C $Stage .

$MakensisCommand = Get-Command makensis.exe -ErrorAction SilentlyContinue
$MakensisCandidates = @(
  $(if ($MakensisCommand) { $MakensisCommand.Source }),
  $(if ($env:NSIS_HOME) { Join-Path $env:NSIS_HOME "makensis.exe" }),
  (Join-Path ([Environment]::GetFolderPath("ProgramFilesX86")) "NSIS\makensis.exe"),
  (Join-Path ([Environment]::GetFolderPath("ProgramFiles")) "NSIS\makensis.exe"),
  $(if ($env:ChocolateyInstall) { Join-Path $env:ChocolateyInstall "bin\makensis.exe" })
)
$Makensis = $MakensisCandidates | Where-Object { $_ -and (Test-Path $_ -PathType Leaf) } | Select-Object -First 1
if (-not $Makensis) {
  throw "NSIS makensis.exe was not found"
}

$Installer = Join-Path $Dist "zed-arkts-deveco-$Version-x64.exe"
Push-Location (Join-Path $Root "installer\windows")
try {
  & $Makensis "/DVERSION=$Version" "/DSTAGE_DIR=$Stage" "/DOUTFILE=$Installer" $InstallerScript
} finally {
  Pop-Location
}

Write-Host "Created: $Installer"
Write-Host "Created: $ExtensionArchive"
