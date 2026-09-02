[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("Install", "Uninstall")]
  [string]$Mode,
  [Parameter(Mandatory = $true)]
  [string]$StateDir,
  [string]$SourceTasks,
  [string]$CommandWrapper,
  [string]$TasksFile = (Join-Path $env:APPDATA "Zed\tasks.json")
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$backupFile = Join-Path $StateDir "tasks.before-arkts-deveco.json"
$createdMarker = Join-Path $StateDir "tasks.created-by-arkts-deveco"
$installedHashFile = Join-Path $StateDir "tasks.arkts-deveco.sha256"

function Get-FileSha256 {
  param([string]$Path)

  $stream = [IO.File]::OpenRead($Path)
  try {
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
      $bytes = $sha256.ComputeHash($stream)
      return ([BitConverter]::ToString($bytes)).Replace("-", "").ToLowerInvariant()
    } finally {
      $sha256.Dispose()
    }
  } finally {
    $stream.Dispose()
  }
}

function Find-TopLevelArrayBoundary {
  param([string]$Text)

  $started = $false
  $depth = 0
  $inString = $false
  $escaped = $false
  $lineComment = $false
  $blockComment = $false
  $hasElements = $false
  $lastSignificant = $null

  for ($index = 0; $index -lt $Text.Length; $index++) {
    $character = $Text[$index]
    $next = if ($index + 1 -lt $Text.Length) { $Text[$index + 1] } else { [char]0 }

    if ($lineComment) {
      if ($character -eq "`r" -or $character -eq "`n") {
        $lineComment = $false
      }
      continue
    }
    if ($blockComment) {
      if ($character -eq "*" -and $next -eq "/") {
        $blockComment = $false
        $index++
      }
      continue
    }
    if ($inString) {
      if ($escaped) {
        $escaped = $false
      } elseif ($character -eq "\") {
        $escaped = $true
      } elseif ($character -eq '"') {
        $inString = $false
      }
      continue
    }
    if ($character -eq "/" -and $next -eq "/") {
      $lineComment = $true
      $index++
      continue
    }
    if ($character -eq "/" -and $next -eq "*") {
      $blockComment = $true
      $index++
      continue
    }
    if ([char]::IsWhiteSpace($character)) {
      continue
    }
    if (-not $started) {
      if ($character -ne "[") {
        throw "Zed tasks file must contain a top-level JSON array"
      }
      $started = $true
      $depth = 1
      continue
    }
    if ($character -eq '"') {
      $inString = $true
      if ($depth -eq 1) {
        $hasElements = $true
      }
      $lastSignificant = $character
      continue
    }
    if ($character -eq "[") {
      if ($depth -eq 1) {
        $hasElements = $true
      }
      $depth++
      $lastSignificant = $character
      continue
    }
    if ($character -eq "{") {
      if ($depth -eq 1) {
        $hasElements = $true
      }
      $depth++
      $lastSignificant = $character
      continue
    }
    if ($character -eq "]") {
      if ($depth -eq 1) {
        return [pscustomobject]@{
          CloseIndex = $index
          HasElements = $hasElements
          HasTrailingComma = ($lastSignificant -eq ",")
        }
      }
      $depth--
      $lastSignificant = $character
      continue
    }
    if ($character -eq "}") {
      $depth--
      if ($depth -lt 1) {
        throw "Zed tasks file has an invalid object boundary"
      }
      $lastSignificant = $character
      continue
    }

    if ($depth -eq 1 -and $character -ne ",") {
      $hasElements = $true
    }
    $lastSignificant = $character
  }

  throw "Zed tasks file is missing its top-level closing bracket"
}

function Test-TaskLabelPresent {
  param(
    [string]$Text,
    [string]$Label
  )

  $pattern = '"label"\s*:\s*"' + [regex]::Escape($Label) + '"'
  return [regex]::IsMatch($Text, $pattern)
}

function Format-TaskJson {
  param($Task)

  $json = $Task | ConvertTo-Json -Depth 10
  return (($json -split "`r?`n" | ForEach-Object { "  $_" }) -join "`r`n")
}

function Read-TaskDefinitions {
  param([string]$Path)

  # Windows PowerShell 5.1 can preserve a top-level JSON array as one pipeline
  # object. Copy every element into a generic list so later property access is
  # identical on Windows PowerShell 5.1 and PowerShell 7.
  $parsed = ConvertFrom-Json -InputObject (Get-Content $Path -Raw -Encoding UTF8)
  $definitions = New-Object 'System.Collections.Generic.List[object]'
  foreach ($definition in $parsed) {
    [void]$definitions.Add($definition)
  }
  return $definitions
}

function Install-GlobalTasks {
  if (-not $SourceTasks -or -not (Test-Path $SourceTasks -PathType Leaf)) {
    throw "Bundled ArkTS task definitions were not found"
  }

  New-Item $StateDir -ItemType Directory -Force | Out-Null
  $tasksDirectory = Split-Path -Parent $TasksFile
  New-Item $tasksDirectory -ItemType Directory -Force | Out-Null

  $source = @(Read-TaskDefinitions $SourceTasks)
  if ($source.Count -eq 0) {
    throw "Bundled ArkTS task definitions are empty"
  }

  if ($CommandWrapper) {
    if (-not (Test-Path $CommandWrapper -PathType Leaf)) {
      throw "ArkTS DevEco command wrapper was not found: $CommandWrapper"
    }
    foreach ($task in $source) {
      $commandProperty = $task.PSObject.Properties["command"]
      if (-not $commandProperty) {
        throw "Bundled ArkTS task '$($task.label)' is missing its command property"
      }
      if ($commandProperty.Value -eq "devecocli") {
        $commandProperty.Value = $CommandWrapper
      }
    }
  }

  # Refresh tasks previously managed by this installer. This is required when an
  # update changes command wiring while keeping stable user-facing task labels.
  if (Test-Path $installedHashFile -PathType Leaf) {
    $recordedHash = (Get-Content $installedHashFile -Raw).Trim()
    if ((Test-Path $TasksFile -PathType Leaf) -and
        $recordedHash -and
        (Get-FileSha256 $TasksFile) -ne $recordedHash) {
      throw "Zed tasks.json changed after ArkTS tasks were registered; leaving user changes untouched"
    }
    Uninstall-GlobalTasks
  }

  $existingText = if (Test-Path $TasksFile -PathType Leaf) {
    [IO.File]::ReadAllText($TasksFile, [Text.Encoding]::UTF8)
  } else {
    "[]`r`n"
  }
  $missing = @($source | Where-Object { -not (Test-TaskLabelPresent $existingText $_.label) })
  if ($missing.Count -eq 0) {
    return
  }

  if (-not (Test-Path $backupFile) -and -not (Test-Path $createdMarker)) {
    if (Test-Path $TasksFile -PathType Leaf) {
      Copy-Item $TasksFile $backupFile
    } else {
      New-Item $createdMarker -ItemType File | Out-Null
    }
  }

  $boundary = Find-TopLevelArrayBoundary $existingText
  $formattedTasks = @($missing | ForEach-Object { Format-TaskJson $_ })
  $separator = if (-not $boundary.HasElements -or $boundary.HasTrailingComma) {
    "`r`n"
  } else {
    ",`r`n"
  }
  $merged = $existingText.Substring(0, $boundary.CloseIndex) +
    $separator +
    ($formattedTasks -join ",`r`n") +
    "`r`n" +
    $existingText.Substring($boundary.CloseIndex)

  $temporaryFile = "$TasksFile.arkts-deveco.tmp"
  $rollbackFile = "$TasksFile.arkts-deveco.rollback"
  $hashTemporaryFile = "$installedHashFile.tmp"
  $tasksFileExisted = Test-Path $TasksFile -PathType Leaf
  if ($tasksFileExisted) {
    Copy-Item $TasksFile $rollbackFile -Force
  }

  try {
    $utf8NoBom = New-Object Text.UTF8Encoding -ArgumentList $false
    [IO.File]::WriteAllText($temporaryFile, $merged, $utf8NoBom)
    $installedHash = Get-FileSha256 $temporaryFile
    [IO.File]::WriteAllText($hashTemporaryFile, [string]$installedHash, [Text.Encoding]::ASCII)
    Move-Item $temporaryFile $TasksFile -Force
    Move-Item $hashTemporaryFile $installedHashFile -Force
  } catch {
    if ($tasksFileExisted -and (Test-Path $rollbackFile -PathType Leaf)) {
      Move-Item $rollbackFile $TasksFile -Force
    } elseif (-not $tasksFileExisted) {
      Remove-Item $TasksFile -Force -ErrorAction SilentlyContinue
    }
    throw
  } finally {
    Remove-Item $temporaryFile, $rollbackFile, $hashTemporaryFile -Force -ErrorAction SilentlyContinue
  }
}

function Uninstall-GlobalTasks {
  if (-not (Test-Path $installedHashFile -PathType Leaf)) {
    return
  }

  $recordedHash = (Get-Content $installedHashFile -Raw).Trim()
  $canRestore = -not (Test-Path $TasksFile -PathType Leaf) -or
    ((Get-FileSha256 $TasksFile) -eq $recordedHash)

  if ($canRestore) {
    if (Test-Path $backupFile -PathType Leaf) {
      $tasksDirectory = Split-Path -Parent $TasksFile
      New-Item $tasksDirectory -ItemType Directory -Force | Out-Null
      Copy-Item $backupFile $TasksFile -Force
    } elseif (Test-Path $createdMarker -PathType Leaf) {
      Remove-Item $TasksFile -Force -ErrorAction SilentlyContinue
    }
  }

  Remove-Item $backupFile, $createdMarker, $installedHashFile -Force -ErrorAction SilentlyContinue
}

if ($Mode -eq "Install") {
  Install-GlobalTasks
} else {
  Uninstall-GlobalTasks
}
