@echo off
REM Launches the validation bridge MCP server with a node that is guaranteed to exist.
REM
REM node is installed through fnm, which only puts it on PATH from the interactive PowerShell
REM profile. MCP servers are spawned with the PATH Claude Code itself inherited, which has no node,
REM so registering "node dist/server.js" directly fails with CONNECTION_CLOSED at session start.
REM
REM This wrapper selects the newest fnm installation by numeric version comparison (major.minor.patch),
REM not lexicographic sorting. Lexicographic ordering would incorrectly prefer v20.9.0 over v20.10.0
REM or v9.x over v24.x, leaving the wrapper silently using a stale node if newer versions exist.
REM Numeric comparison ensures the newest version is always selected.

setlocal enabledelayedexpansion
set "FNM_ROOT=%APPDATA%\fnm\node-versions"

set "BEST_VERSION=0.0.0"
set "BEST_NODE_EXE="

for /f "delims=" %%v in ('dir /b /ad "%FNM_ROOT%" 2^>nul') do (
  if exist "%FNM_ROOT%\%%v\installation\node.exe" (
    set "CURRENT_VER=%%v"
    REM Strip leading 'v' for numeric parsing
    set "CURRENT_VER=!CURRENT_VER:v=!"
    set "CURRENT_NODE_EXE=%FNM_ROOT%\%%v\installation\node.exe"

    REM Parse current version components
    for /f "tokens=1,2,3 delims=." %%a in ("!CURRENT_VER!") do (
      set "CUR_MAJOR=%%a"
      set "CUR_MINOR=%%b"
      set "CUR_PATCH=%%c"
    )

    REM Parse best version components
    for /f "tokens=1,2,3 delims=." %%a in ("!BEST_VERSION!") do (
      set "BEST_MAJOR=%%a"
      set "BEST_MINOR=%%b"
      set "BEST_PATCH=%%c"
    )

    REM Compare versions numerically: major, then minor, then patch
    if !CUR_MAJOR! gtr !BEST_MAJOR! (
      set "BEST_VERSION=!CURRENT_VER!"
      set "BEST_NODE_EXE=!CURRENT_NODE_EXE!"
    ) else if !CUR_MAJOR! equ !BEST_MAJOR! (
      if !CUR_MINOR! gtr !BEST_MINOR! (
        set "BEST_VERSION=!CURRENT_VER!"
        set "BEST_NODE_EXE=!CURRENT_NODE_EXE!"
      ) else if !CUR_MINOR! equ !BEST_MINOR! (
        if !CUR_PATCH! gtr !BEST_PATCH! (
          set "BEST_VERSION=!CURRENT_VER!"
          set "BEST_NODE_EXE=!CURRENT_NODE_EXE!"
        )
      )
    )
  )
)

if not defined BEST_NODE_EXE (
  echo No fnm node installation found under "%FNM_ROOT%" 1>&2
  exit /b 1
)

"!BEST_NODE_EXE!" "%~dp0dist\server.js" %*
