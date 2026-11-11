@echo off
setlocal
rem ManuBrightness v7.0.0 - Windows built-in PowerShell 5.1 launcher.
rem Double-click this file; there is no separate runtime to install.
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%~dp0ManuBrightness.ps1" (
    echo Missing ManuBrightness.ps1 in the same folder.
    pause
    exit /b 1
)
if not exist "%PS_EXE%" (
    echo Windows PowerShell 5.1 was not found.
    pause
    exit /b 1
)
start "" "%PS_EXE%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0ManuBrightness.ps1"
endlocal
