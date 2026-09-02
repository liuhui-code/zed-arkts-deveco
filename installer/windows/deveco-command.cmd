@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0deveco-command.ps1" %*
exit /b %ERRORLEVEL%
