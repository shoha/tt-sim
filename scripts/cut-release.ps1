<#
.SYNOPSIS
    Automates the mechanical steps of cutting a TTSim release.

.DESCRIPTION
    Encodes the process documented in AGENTS.md's "Cutting a release" section:
      1. Verify the working tree is clean and on main, and the local tag list is
         up to date with the remote.
      2. Run the GUT test suite; abort if anything fails.
      3. Bump project.godot's config/version to the release version (defaults to
         the current version's patch+1), commit it, and tag it (vX.Y.Z).
      4. Immediately bump project.godot again to the next dev version and commit
         it -- this is the step that has been missed twice by hand (v0.1.10 and
         v0.1.11 both shipped without it), leaving main re-using the just-shipped
         version number until the next manual fix. Doing both bumps in one
         script run makes that mistake structurally impossible.
      5. Only if -Push is given: push main, then push the release tag. Pushing
         the tag is what triggers CI to build, code-sign, notarize, create a
         GitHub Release, and deploy to Steam's `testing` branch -- real external
         side effects against production credentials. Omit -Push to stop after
         the local commits/tag so a human (or the calling agent, after asking
         you) can review before pushing.

    This script never touches Steam's `testing` -> `default` (live) promotion --
    that step is manual in the Steamworks partner web UI and cannot be
    automated from CI or this script.

.PARAMETER Version
    Explicit release version (e.g. "0.1.12"). Defaults to the current
    project.godot version's patch component incremented by 1.

.PARAMETER Push
    Push the version-bump commits and the release tag to origin. Without this,
    the script stops after creating the local commits and tag.

.EXAMPLE
    .\scripts\cut-release.ps1
    Dry run: bumps to the next patch version, tags locally, bumps main to the
    following dev version -- nothing pushed.

.EXAMPLE
    .\scripts\cut-release.ps1 -Version 0.2.0 -Push
    Cuts release 0.2.0 explicitly and pushes everything, triggering the CI
    release pipeline immediately.
#>
param(
    [string]$Version,
    [switch]$Push
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ProjectGodot = Join-Path $ProjectRoot "project.godot"

function Get-CurrentVersion {
    $line = Select-String -Path $ProjectGodot -Pattern '^config/version="([^"]+)"' | Select-Object -First 1
    if (-not $line) {
        throw "Could not find config/version in $ProjectGodot"
    }
    return $line.Matches[0].Groups[1].Value
}

function Set-Version([string]$NewVersion) {
    $content = Get-Content $ProjectGodot -Raw
    $updated = $content -replace '(?m)^config/version="[^"]+"', "config/version=`"$NewVersion`""
    if ($updated -eq $content) {
        throw "Version substitution did not change $ProjectGodot -- pattern mismatch?"
    }
    Set-Content -Path $ProjectGodot -Value $updated -NoNewline
}

function Get-NextPatch([string]$Ver) {
    $parts = $Ver.Split('.')
    if ($parts.Length -lt 3) {
        throw "Version '$Ver' doesn't look like X.Y.Z -- pass -Version explicitly"
    }
    $parts[-1] = [string]([int]$parts[-1] + 1)
    return [string]::Join('.', $parts)
}

Push-Location $ProjectRoot
try {
    # --- Preflight ---
    $branch = git rev-parse --abbrev-ref HEAD
    if ($branch -ne "main") {
        throw "Not on main (currently on '$branch'). Switch to main before cutting a release."
    }

    # Untracked files are ignored -- this project deliberately leaves plan/spec
    # docs (docs/superpowers/**) untracked forever, so a plain `git status
    # --porcelain` would false-positive on every normal working tree. Only
    # changes to already-tracked files (staged or unstaged) block the release.
    $dirty = git status --porcelain --untracked-files=no
    if ($dirty) {
        throw "Working tree has uncommitted changes to tracked files:`n$dirty`nCommit or stash before cutting a release."
    }

    Write-Host "Fetching tags from origin to check for collisions..." -ForegroundColor Cyan
    git fetch origin --tags --quiet

    $currentVersion = Get-CurrentVersion
    Write-Host "Current project.godot version: $currentVersion" -ForegroundColor Cyan

    $releaseVersion = if ($Version) { $Version } else { Get-NextPatch $currentVersion }
    $tagName = "v$releaseVersion"

    $existingTag = git tag --list $tagName
    if ($existingTag) {
        throw "Tag $tagName already exists. Pick a different -Version."
    }

    # --- Test suite ---
    Write-Host "Running GUT test suite..." -ForegroundColor Cyan
    # The -gconfig arg must be quoted -- unquoted, the godot.cmd Scoop shim's
    # batch-file argument forwarding splits it apart (observed: Godot receives
    # "tests/" and ".gutconfig.json" as two separate/unknown arguments).
    & godot --headless --path . --script res://addons/gut/gut_cmdln.gd -- "-gconfig=tests/.gutconfig.json"
    if ($LASTEXITCODE -ne 0) {
        throw "Test suite failed (exit code $LASTEXITCODE). Fix failing tests before cutting a release."
    }

    # --- Bump to release version, commit, tag ---
    Write-Host "Bumping to release version $releaseVersion and tagging $tagName..." -ForegroundColor Cyan
    Set-Version $releaseVersion
    git add project.godot
    git commit -m "Bump version to $releaseVersion"
    git tag $tagName

    # --- Immediately bump to next dev version, commit ---
    $nextDevVersion = Get-NextPatch $releaseVersion
    Write-Host "Bumping to next dev version $nextDevVersion so future pre-release builds are versioned correctly..." -ForegroundColor Cyan
    Set-Version $nextDevVersion
    git add project.godot
    git commit -m "Bump version to $nextDevVersion"

    Write-Host ""
    Write-Host "Local commits and tag created:" -ForegroundColor Green
    git log --oneline -3
    Write-Host "Tag: $tagName"

    if ($Push) {
        Write-Host ""
        Write-Host "Pushing main and $tagName to origin -- this triggers the CI release pipeline." -ForegroundColor Yellow
        git push origin main
        git push origin $tagName
        Write-Host ""
        Write-Host "Pushed. CI will build, sign/notarize, create a GitHub Release, and deploy to Steam's 'testing' branch." -ForegroundColor Green
        Write-Host "REMINDER: promoting the Steam build from 'testing' to live ('default') is a manual step in the Steamworks partner web UI -- this script and CI never do that." -ForegroundColor Yellow
    }
    else {
        Write-Host ""
        Write-Host "Not pushed (run with -Push to push and trigger CI). Review the commits/tag above, then either:" -ForegroundColor Yellow
        Write-Host "  git push origin main && git push origin $tagName"
        Write-Host "or re-run this script with -Push."
    }
}
finally {
    Pop-Location
}
