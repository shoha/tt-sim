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

## Emitted when any system wants to open the level editor. `level_path` names a saved
## level to edit (the title screen's per-card Edit action); "" means edit whichever
## level is currently playing, if any.
signal open_editor_requested(level_path: String)

## Emitted by FoliageLibrary.switch() once the palette serves another foliage library
## ("treecube" or "plantgen"). Root rebuilds the open map so its scatter uses the new plants.
signal foliage_library_changed(library: String)

## Emitted to open biome `biome_id` of library `library_id` in the biome designer (the title's
## picker, the designer's own "Save as new collection"). Root prepares and opens the session.
signal biome_designer_requested(library_id: String, biome_id: String)
