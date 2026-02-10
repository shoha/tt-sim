extends Node

## Global event bus for cross-system communication.
##
## Provides a central hub for signals that span multiple systems,
## reducing coupling between the root state machine, UI layer, and
## game subsystems.  Only signals that genuinely cross system
## boundaries belong here — local parent/child signals should stay
## on the owning node.

# ---------------------------------------------------------------------------
# State-machine requests
# ---------------------------------------------------------------------------

## Request a pause-toggle from anywhere (UIManager, input hints, etc.)
## The root state machine listens to this and pushes/pops PAUSED.
signal pause_requested
signal resume_requested

## Emitted by the root state machine whenever the top-of-stack changes.
## Listeners can query the new state without importing the Root script.
## The state values match RootScript.State (int enum).
signal state_changed(old_state: int, new_state: int)

# ---------------------------------------------------------------------------
# Level lifecycle
# ---------------------------------------------------------------------------

## Emitted when any system wants to start playing a level.
## Root listens and orchestrates the state transition + network broadcast.
signal play_level_requested(level_data: LevelData)

## Emitted when any system wants to open the level editor.
signal open_editor_requested

# ---------------------------------------------------------------------------
# Network notifications (informational — no action required)
# ---------------------------------------------------------------------------

## A player disconnected (convenience relay for UI toast consumers).
signal player_disconnected(player_name: String)
