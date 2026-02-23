@echo off
:: =============================================================================
:: Kiro-Guard — Windows Installer
:: Installs kiro-guard.py + kg-sync.bat to %ProgramFiles%\KiroGuard and
:: adds that folder to the system PATH.
:: Must be run as Administrator.
:: =============================================================================

setlocal enabledelayedexpansion

set "INSTALL_DIR=%ProgramFiles%\KiroGuard"
set "SCRIPT_DIR=%~dp0"

:: ── Admin check ───────────────────────────────────────────────────────────────
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Error: Run this script as Administrator.
    echo Right-click install.bat and choose "Run as administrator".
    pause
    exit /b 1
)

echo Installing Kiro-Guard...
echo   Source  : %SCRIPT_DIR%
echo   Install : %INSTALL_DIR%
echo.

:: ── Copy files ────────────────────────────────────────────────────────────────
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
copy /Y "%SCRIPT_DIR%kiro-guard.py" "%INSTALL_DIR%\kiro-guard.py" >nul
copy /Y "%SCRIPT_DIR%kg-sync.bat"   "%INSTALL_DIR%\kg-sync.bat"   >nul

:: ── Create kiro-guard.bat wrapper ─────────────────────────────────────────────
(
    echo @echo off
    echo python "%INSTALL_DIR%\kiro-guard.py" %%*
) > "%INSTALL_DIR%\kiro-guard.bat"

:: ── Add to system PATH if not already present ────────────────────────────────
echo %PATH% | find /i "%INSTALL_DIR%" >nul 2>&1
if %errorlevel% neq 0 (
    setx /M PATH "%PATH%;%INSTALL_DIR%" >nul
    echo   Added "%INSTALL_DIR%" to system PATH.
    echo   NOTE: Open a new terminal for the PATH change to take effect.
) else (
    echo   "%INSTALL_DIR%" already in PATH.
)

echo.
echo Done! You can now run 'kiro-guard' from any terminal (after reopening it).
echo.
echo Try it:
echo   kiro-guard sync       (from inside any project with a .kiro-guard file)
echo   kiro-guard login      (first-time auth as kiro-runner)
echo   kiro-guard run        (open kiro-cli interactive session)
echo   kiro-guard ask "your question"
echo.
pause
endlocal
