@echo off
setlocal
rem ManuBrightness v7.0.2 - start a console-free background tray process.
rem Main.cmd may appear briefly, but its window must close automatically.
rem The background ManuBrightness process is NOT tied to this terminal.
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
"%PS_EXE%" -NoLogo -NoProfile -STA -NonInteractive -ExecutionPolicy Bypass -File "%~dp0ManuBrightness.ps1" -LaunchBackground
if errorlevel 1 (
    echo ManuBrightness failed to launch. Check any error dialog above.
    pause
    exit /b 1
)
endlocal
exit /b 0
