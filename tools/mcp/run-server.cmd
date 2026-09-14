@echo off
REM Launches the validation bridge MCP server with a node that is guaranteed to exist.
REM
REM node is installed through fnm, which only puts it on PATH from the interactive PowerShell
REM profile. MCP servers are spawned with the PATH Claude Code itself inherited, which has no node,
REM so registering "node dist/server.js" directly fails with CONNECTION_CLOSED at session start.
REM Resolving the newest fnm installation here keeps the registration working regardless of which
REM shell, if any, has been initialised.

setlocal
set "FNM_ROOT=%APPDATA%\fnm\node-versions"
for /f "delims=" %%v in ('dir /b /ad /o-n "%FNM_ROOT%" 2^>nul') do (
  if exist "%FNM_ROOT%\%%v\installation\node.exe" (
    set "NODE_EXE=%FNM_ROOT%\%%v\installation\node.exe"
    goto :found
  )
)
echo No fnm node installation found under "%FNM_ROOT%" 1>&2
exit /b 1

:found
"%NODE_EXE%" "%~dp0dist\server.js" %*
