@echo off
rem {{AppName}} launcher for Windows: prefers PowerShell 7 (pwsh.exe), falls back to Windows PowerShell 5.1.
rem The execution policy is bypassed for THIS process only; nothing on the system is changed.
setlocal EnableExtensions DisableDelayedExpansion
set "APP_ROOT=%~dp0"
set "APP_ENTRY=%APP_ROOT%Start-{{AppId}}.ps1"
if not exist "%APP_ENTRY%" goto :noentry
set "APP_PS="
for %%P in (pwsh.exe) do set "APP_PS=%%~$PATH:P"
if defined APP_PS goto :run
for %%P in (powershell.exe) do set "APP_PS=%%~$PATH:P"
if defined APP_PS goto :run
if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" set "APP_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if defined APP_PS goto :run
echo ERROR: Neither PowerShell 7 ^(pwsh.exe^) nor Windows PowerShell was found.
endlocal & exit /b 3
:noentry
echo ERROR: The entry script was not found: "%APP_ENTRY%"
endlocal & exit /b 2
:run
"%APP_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%APP_ENTRY%" %*
set "APP_RC=%ERRORLEVEL%"
endlocal & exit /b %APP_RC%
