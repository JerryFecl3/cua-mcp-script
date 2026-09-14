@echo off
setlocal
set "CUA_LINK_ENTRY=%~dp0CuaLink.ps1"
set "CUA_LINK_HOST=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "CUA_LINK_HOST=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
rem Unblock only our entry script. No persistent execution-policy changes.
"%CUA_LINK_HOST%" -NoProfile -ExecutionPolicy RemoteSigned -Command "$ErrorActionPreference='Stop'; Unblock-File -LiteralPath $env:CUA_LINK_ENTRY"
if errorlevel 1 goto failed
"%CUA_LINK_HOST%" -NoProfile -ExecutionPolicy RemoteSigned -File "%CUA_LINK_ENTRY%" %*
set "CUA_LINK_EXIT=%ERRORLEVEL%"
if not "%CUA_LINK_EXIT%"=="0" pause
exit /b %CUA_LINK_EXIT%
:failed
echo Unable to prepare CuaLink.ps1. See the error above.
pause
exit /b 1
