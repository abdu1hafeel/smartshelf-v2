@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_staging.ps1" %*
endlocal
