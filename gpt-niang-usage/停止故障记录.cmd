@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0runtime\start-diagnostics.ps1" -Stop
pause
