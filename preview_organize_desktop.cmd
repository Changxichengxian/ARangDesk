@echo off
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0organize_desktop.ps1" -Preview
pause
