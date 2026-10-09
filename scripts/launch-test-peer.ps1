<#
.SYNOPSIS
    Launches a second game instance on a second Steam account, inside a
    Sandboxie-Plus box, for multiplayer testing alongside the Godot editor.

.DESCRIPTION
    Steam refuses a second client from the same install while one is running
    (-master_ipc_name_override hangs before startup, checked 2026-10-09), so the
    second account's Steam client runs inside a Sandboxie-Plus box. A Godot
    process reaches that client only when it runs in the same box.

    The peer runs the project from source (no export), so it always has the
    current code.

    First-time setup:
      1. Install Sandboxie-Plus (winget install --id Sandboxie.Plus --exact)
      2. Create a free second Steam account at store.steampowered.com
      3. Run: .\scripts\launch-test-peer.ps1 -SetupSteam
         This creates the box if needed and starts Steam in it. Pick or log in
         the second account. The box's Steam window may keep showing its
         loading spinner; the account is still logged on (check the box's
         logs/connection_log.txt for "Logged On").

    Testing:
      1. Run the Godot editor normally (main Steam account) and host.
      2. Run: .\scripts\launch-test-peer.ps1
         and join with the room code.

.PARAMETER SetupSteam
    Create the box (if missing) and start the second Steam client in it. Only
    needed once per login session.

.PARAMETER Box
    Sandboxie box name. Default: SteamAlt.

.PARAMETER GodotArgs
    Extra arguments passed to Godot after --path (for example a scene path,
    or "--headless").
#>
param(
    [switch]$SetupSteam,
    [string]$Box = "SteamAlt",
    [string[]]$GodotArgs = @()
)

$ErrorActionPreference = "Stop"

# --- Configuration ---
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SteamExe = "C:\Program Files (x86)\Steam\steam.exe"
$SbieDir = "C:\Program Files\Sandboxie-Plus"
$SbieStart = Join-Path $SbieDir "Start.exe"
$SbieIni = Join-Path $SbieDir "SbieIni.exe"
$GodotRoot = "D:\Apps\Godot"

# --- Functions ---

function Assert-Sandboxie {
    if (-not (Test-Path $SbieStart)) {
        throw "Sandboxie-Plus not found at $SbieDir. Install it: winget install --id Sandboxie.Plus --exact"
    }
}

# Newest Godot under D:\Apps\Godot, picked the same way as the godot wrapper.
# The wrapper itself does not resolve inside a box, so the exe path is passed.
function Get-GodotExe {
    $best = Get-ChildItem -Path $GodotRoot -Directory |
        Where-Object { $_.Name -match '\d+\.\d+(\.\d+)?' } |
        Sort-Object { [version]([regex]::Match($_.Name, '\d+\.\d+(\.\d+)?').Value) } |
        Select-Object -Last 1
    if (-not $best) { throw "No Godot version folder under $GodotRoot" }
    $exe = Get-ChildItem $best.FullName -Filter '*.exe' |
        Where-Object { $_.Name -notlike '*console*' } |
        Select-Object -First 1
    if (-not $exe) { throw "No Godot exe in $($best.FullName)" }
    return $exe.FullName
}

function Start-SecondarySteam {
    if ((& $SbieIni query $Box Enabled) -ne "y") {
        Write-Host "Creating Sandboxie box '$Box'..." -ForegroundColor Cyan
        & $SbieIni set $Box Enabled y
    }
    Write-Host "Launching Steam in box '$Box'..." -ForegroundColor Cyan
    Write-Host "Pick or log in the second account when prompted." -ForegroundColor Yellow
    & $SbieStart "/box:$Box" $SteamExe -userchooser
}

function Start-TestPeer {
    $godot = Get-GodotExe
    Write-Host "Launching test peer in box '$Box' with $godot" -ForegroundColor Cyan
    & $SbieStart "/box:$Box" $godot --path $ProjectRoot @GodotArgs
    Write-Host "Test peer launched." -ForegroundColor Green
}

# --- Main ---

Assert-Sandboxie

if ($SetupSteam) {
    Start-SecondarySteam
    return
}

Start-TestPeer
