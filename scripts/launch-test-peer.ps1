<#
.SYNOPSIS
    Launches a second game instance connected to a secondary Steam account
    for multiplayer testing alongside the Godot editor.

.DESCRIPTION
    Workflow:
      1. Run the Godot editor normally (uses your primary Steam account)
      2. Run this script to launch a debug build as a second peer

    First-time setup:
      1. Create a free second Steam account at store.steampowered.com
      2. Run: .\scripts\launch-test-peer.ps1 -SetupSteam
         This launches a second Steam client - log in with the second account.
      3. Run: .\scripts\launch-test-peer.ps1
         This exports a debug build and launches it as the second peer.

.PARAMETER SetupSteam
    Launch the secondary Steam client for login. Only needed once or after
    the secondary client is closed.

.PARAMETER SkipExport
    Skip the debug export step (use the last exported build).

.PARAMETER ExportOnly
    Export the debug build without launching it.
#>
param(
    [switch]$SetupSteam,
    [switch]$SkipExport,
    [switch]$ExportOnly
)

$ErrorActionPreference = "Stop"

# --- Configuration ---
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SteamExe = "C:\Program Files (x86)\Steam\steam.exe"
$IpcName = "tt-sim-testing"
$BuildDir = Join-Path $ProjectRoot "build\windows-debug"
$BuildExe = Join-Path $BuildDir "TTSim.exe"
$GodotCmd = "godot"

# --- Functions ---

function Start-SecondarySteam {
    Write-Host "Launching secondary Steam client..." -ForegroundColor Cyan
    Write-Host "Log in with your second Steam account when prompted." -ForegroundColor Yellow
    Start-Process $SteamExe -ArgumentList "-master_ipc_name_override $IpcName -userchooser"
}

function Export-DebugBuild {
    Write-Host "Exporting debug build..." -ForegroundColor Cyan

    if (-not (Test-Path $BuildDir)) {
        New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
    }

    # Copy steam_appid.txt into the build directory
    $appIdSrc = Join-Path $ProjectRoot "steam_appid.txt"
    if (Test-Path $appIdSrc) {
        Copy-Item $appIdSrc (Join-Path $BuildDir "steam_appid.txt") -Force
    } else {
        Write-Warning "steam_appid.txt not found in project root - the build may fail to init Steam"
    }

    & $GodotCmd --headless --path $ProjectRoot --export-debug "Windows Desktop" $BuildExe
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Export failed (exit code $LASTEXITCODE)"
        return $false
    }

    Write-Host "Export complete: $BuildExe" -ForegroundColor Green
    return $true
}

function Start-TestPeer {
    Write-Host "Launching test peer (secondary Steam account)..." -ForegroundColor Cyan

    if (-not (Test-Path $BuildExe)) {
        Write-Error "No debug build found at $BuildExe. Run without -SkipExport first."
        return
    }

    $env:steam_master_ipc_name_override = $IpcName
    Start-Process $BuildExe -WorkingDirectory $BuildDir
    Remove-Item Env:\steam_master_ipc_name_override -ErrorAction SilentlyContinue

    Write-Host "Test peer launched." -ForegroundColor Green
}

# --- Main ---

if ($SetupSteam) {
    Start-SecondarySteam
    return
}

if ($ExportOnly) {
    Export-DebugBuild | Out-Null
    return
}

if (-not $SkipExport) {
    $ok = Export-DebugBuild
    if (-not $ok) { return }
}

Start-TestPeer
