@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\ArkTSDevEco\collect-diagnostics.ps1"
if errorlevel 1 (
  echo.
  echo Failed to create the diagnostics package.
) else (
  echo.
  echo The diagnostics package was written to your Desktop.
)
pause
