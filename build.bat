@echo off
cd /d "%~dp0"
if not exist icon.ico (
    python make-icon.py
    if errorlevel 1 exit /b 1
)
odin build . -out:mini-task-manager.exe -o:speed -subsystem:windows
if errorlevel 1 exit /b 1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0embed-icon.ps1"
if errorlevel 1 exit /b 1
