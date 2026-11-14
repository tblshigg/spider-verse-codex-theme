@echo off
chcp 65001 >nul
title Spider-Verse Theme Installer
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
pause
