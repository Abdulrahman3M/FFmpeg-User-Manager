@echo off
rem ======================================================================
rem  FFmpeg User Manager - Windows launcher
rem  Double-click this file (or run it from any terminal) to start the app.
rem  Launcher logic only: it locates Start-FFmpegTUI.ps1 next to this file,
rem  picks PowerShell 7 (pwsh.exe) when available, otherwise Windows
rem  PowerShell 5.1, and passes all arguments through. No system policy is changed.
rem  Optional: set FFUM_POWERSHELL to a full path to force a specific PowerShell,
rem  and FFUM_TRACE=1 to print which one is used.
rem  (No parenthesized blocks: paths such as "C:\Program Files (x86)\..." would break them.)
rem ======================================================================
setlocal EnableExtensions DisableDelayedExpansion

rem --- directory of this file (always ends with a backslash), independent of the current directory
set "FFUM_ROOT=%~dp0"
set "FFUM_ENTRY=%FFUM_ROOT%Start-FFmpegTUI.ps1"
set "FFUM_RC=0"

rem --- a double-click start runs as: cmd.exe /c ""<path>\FFmpeg-User-Manager.bat"" (the command line names this file); keep errors visible then
set "FFUM_DBLCLICK="
echo %CMDCMDLINE% | find /i " /c " >nul 2>&1 && echo %CMDCMDLINE% | find /i "%~nx0" >nul 2>&1 && set "FFUM_DBLCLICK=1"

if exist "%FFUM_ENTRY%" goto :have_entry
echo.
echo ERROR: The application entry script was not found:
echo   "%FFUM_ENTRY%"
echo Make sure the whole project folder is extracted and that
echo Start-FFmpegTUI.ps1 is located next to this launcher.
set "FFUM_RC=2"
goto :finish

:have_entry
rem --- runtime: FFUM_POWERSHELL (optional override) > PowerShell 7 (pwsh.exe) > Windows PowerShell 5.1 (powershell.exe)
set "FFUM_PS=%FFUM_POWERSHELL%"
if defined FFUM_PS goto :run
for %%P in (pwsh.exe) do set "FFUM_PS=%%~$PATH:P"
if defined FFUM_PS goto :run
for %%P in (powershell.exe) do set "FFUM_PS=%%~$PATH:P"
if defined FFUM_PS goto :run
if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" set "FFUM_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if defined FFUM_PS goto :run
echo.
echo ERROR: Neither PowerShell 7 ^(pwsh.exe^) nor Windows PowerShell ^(powershell.exe^) was found on this computer.
set "FFUM_RC=3"
goto :finish

:run
rem --- -ExecutionPolicy Bypass applies to this launched process only; machine/user policy is never modified
if defined FFUM_TRACE echo Launcher runtime: %FFUM_PS%
"%FFUM_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%FFUM_ENTRY%" %*
set "FFUM_RC=%ERRORLEVEL%"

:finish
if "%FFUM_RC%"=="0" goto :done
if not defined FFUM_DBLCLICK goto :done
echo.
echo The application exited with code %FFUM_RC%.
pause
:done
endlocal & exit /b %FFUM_RC%
