@echo off
:: =============================================================================
:: Kiro-Guard — Windows Sync Script
::
:: Normally called by kiro-guard.py which passes:
::   %1 = project root (absolute path)
::   %2 = resolved-paths file (absolute paths, one per line, already glob-expanded)
::
:: Can also be called directly (standalone):
::   kg-sync.bat [project-root]
:: In standalone mode, walks up from cwd to find .kiro-guard and expands
:: patterns using "for /r" for ** and "for" for single-level *.
:: Must be run as Administrator.
:: =============================================================================

setlocal enabledelayedexpansion

set "RESTRICTED_USER=kiro-runner"
set "GUARD_FILE=.kiro-guard"

:: ── Admin check ───────────────────────────────────────────────────────────────
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Error: This script must be run as Administrator.
    pause
    exit /b 1
)

:: ── Resolve project root ──────────────────────────────────────────────────────
if not "%~1"=="" (
    set "PROJECT_ROOT=%~1"
    goto :got_root
)

:: Walk up from cwd to find .kiro-guard
set "PROJECT_ROOT="
set "walkdir=%CD%"
:walk_up
if exist "!walkdir!\%GUARD_FILE%" (
    set "PROJECT_ROOT=!walkdir!"
    goto :got_root
)
for %%P in ("!walkdir!\..") do set "parent=%%~fP"
if "!parent!"=="!walkdir!" (
    echo Error: "%GUARD_FILE%" not found in "%CD%" or any parent directory.
    pause
    exit /b 1
)
set "walkdir=!parent!"
goto :walk_up
:got_root

echo Project root : %PROJECT_ROOT%
echo.

:: ── Create restricted local user if needed ────────────────────────────────────
net user "%RESTRICTED_USER%" >nul 2>&1
if %errorlevel% neq 0 (
    echo Creating restricted local user: %RESTRICTED_USER%
    net user "%RESTRICTED_USER%" /add /active:yes /comment:"Kiro-Guard restricted runner" >nul
) else (
    echo User "%RESTRICTED_USER%" already exists.
)

:: ── Apply deny rules ─────────────────────────────────────────────────────────
echo.
echo Applying deny rules...
set /a LOCKED=0
set /a SKIPPED=0

if not "%~2"=="" (
    if exist "%~2" (
        :: --- Mode A: pre-resolved list from kiro-guard.py -------------------
        echo Using pre-resolved paths from kiro-guard.py...
        echo.
        for /f "usebackq tokens=* delims=" %%A in ("%~2") do (
            set "abs_path=%%A"
            if exist "!abs_path!" (
                icacls "!abs_path!" /deny "%RESTRICTED_USER%:(OI)(CI)(F)" /t >nul 2>&1
                echo   LOCKED : !abs_path!
                set /a LOCKED+=1
            ) else (
                echo   SKIPPED: !abs_path! ^(not found^)
                set /a SKIPPED+=1
            )
        )
        goto :summary
    )
)

:: --- Mode B: standalone — read .kiro-guard and expand patterns ---------------
set "GUARD_PATH=%PROJECT_ROOT%\%GUARD_FILE%"
if not exist "%GUARD_PATH%" (
    echo Error: "%GUARD_PATH%" not found.
    pause
    exit /b 1
)
echo Expanding patterns from "%GUARD_FILE%" (standalone mode)...
echo.

for /f "usebackq tokens=* delims=" %%A in ("%GUARD_PATH%") do (
    set "line=%%A"
    if defined line (
        :: Skip comment lines
        if not "!line:~0,1!"=="#" (
            set "pattern=!line!"
            :: Check if pattern contains a wildcard
            echo !pattern! | findstr /r "[*?]" >nul 2>&1
            if !errorlevel!==0 (
                :: Has wildcard — use for /r for recursive, for otherwise
                echo !pattern! | findstr "\*\*" >nul 2>&1
                if !errorlevel!==0 (
                    :: ** recursive pattern — extract filename part after last backslash/slash
                    for %%F in ("!pattern!") do set "fname=%%~nxF"
                    for /r "%PROJECT_ROOT%" %%M in (!fname!) do (
                        if exist "%%M" (
                            icacls "%%M" /deny "%RESTRICTED_USER%:(OI)(CI)(F)" /t >nul 2>&1
                            echo   LOCKED : %%M
                            set /a LOCKED+=1
                        )
                    )
                ) else (
                    :: Single-level wildcard
                    for %%M in ("%PROJECT_ROOT%\!pattern!") do (
                        if exist "%%M" (
                            icacls "%%M" /deny "%RESTRICTED_USER%:(OI)(CI)(F)" /t >nul 2>&1
                            echo   LOCKED : %%M
                            set /a LOCKED+=1
                        )
                    )
                )
            ) else (
                :: No wildcard — direct path
                set "abs_path=%PROJECT_ROOT%\!pattern!"
                if exist "!abs_path!" (
                    icacls "!abs_path!" /deny "%RESTRICTED_USER%:(OI)(CI)(F)" /t >nul 2>&1
                    echo   LOCKED : !pattern!
                    set /a LOCKED+=1
                ) else (
                    echo   SKIPPED: !pattern! ^(not found^)
                    set /a SKIPPED+=1
                )
            )
        )
    )
)

:summary
echo.
echo ═══════════════════════════════════════════════════════
echo   Kiro-Guard sync complete.
echo   Locked : %LOCKED% path(s)
echo   Skipped: %SKIPPED% path(s) (not found)
echo ═══════════════════════════════════════════════════════
echo.
echo Next steps:
echo   1. First-time login: kiro-guard login
echo   2. Run Kiro:         kiro-guard run "your prompt"
echo.
pause
endlocal
