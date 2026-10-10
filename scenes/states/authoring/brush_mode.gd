class_name BrushMode
extends RefCounted

## One tool's gestures on the brush: what a press, the frames after it, the end and a cancel
## do, what the size gesture steps, and how the cursor looks. BrushTool hosts the tool's mode
## and routes its input and frames to it; the mode does the tool's work through the editor.
## A ToolDescriptor names its mode's class in `brush_mode`; BrushTool.mode_for() makes one per
## tool and keeps it for the brush's life, so what a pane picked (a tile, a depth, a surface)
## survives switching tools. The base class starts nothing and draws a plain ring: the brush's
## mode before a tool is picked.
##
## Host. Every hook takes the BrushTool (`brush`): the pointer's ground point (`hit`,
## `hit_normal`), the press and its modifiers (`pressed`, `press_ctrl`, `press_shift`, `ctrl`,
## `shift`), the dab stroke (`stroking`, `dwell`), the brush size, `editor`, the level's units,
## and the `refused` signal for a toast. A mode never reaches AuthoringController, so a play
## side can host the same modes over LiveEdits.editor.
##
## Dab strokes. press() returns true when it began an editor stroke (begin_stroke,
## begin_height_stroke, begin_surface_stroke, a pond or a water erase); BrushTool then dabs
## it every frame along the pointer's path at stroke_radius(), with the dwell gain, calls
## dabbed() after each dab, and ends or cancels it with the editor. A mode whose press returns
## false does its own work in frame(), end() and cancel() (a river's line, a crossing's line,
## a prop being turned).
##
## Cursor. draw_cursor() draws on BrushCursor's overlay; the default is the brush ring in
## cursor_tint() with cursor_text() under it. A mode with a cursor of its own overrides it.

## The mode works on a target under the pointer (Place: a prop) as well as the ground:
## Shift+wheel then scales the target, and only over one; RMB and Delete remove it
## (BrushTool.decide).
var picks: bool = false
## The brush's rays see crossings (the Bridge tool picks a deck where it is drawn); every
## other mode edits the ground under a deck or a stone.
var sees_crossings: bool = false
## The canopy over the cursor fades (BrushTool.occlusion_fade, at fade_focus()), so the ground
## being worked stays in view under a forest.
var fades: bool = false


## The smallest brush radius the mode takes (BrushTool.set_radius).
func min_radius() -> float:
	return BrushTool.MIN_RADIUS


## The radius the ring shows and a dab paints with. Default: the brush size.
func stroke_radius(brush: BrushTool) -> float:
	return brush.get_radius()


## True while a target the mode picks is under the pointer (see `picks`).
func has_target() -> bool:
	return false


## A press at `brush.hit` (the editor is set and the hit is on the ground). True when it began
## a dab stroke the brush is to paint; false when the mode took the press itself or refused
## it (emitting `brush.refused` with the reason when the author should hear why).
func press(_brush: BrushTool) -> bool:
	return false


## One frame while the brush is active, before the stroke's dab: follow the pointer.
func frame(_brush: BrushTool) -> void:
	pass


## After each dab of the mode's stroke (BrushTool flushed it).
func dabbed(_brush: BrushTool) -> void:
	pass


## Ends whatever the mode has in progress, keeping its result: on release, and before an
## undo, a tool switch or putting the brush down. The brush ends its dab stroke itself.
func end(_brush: BrushTool) -> void:
	pass


## Drops whatever the mode has in progress (RMB or Escape during a press). The brush cancels
## its dab stroke itself.
func cancel(_brush: BrushTool) -> void:
	pass


## The brush is put down or switched to another tool (after end()): forget the pointer's
## surroundings.
func leave(_brush: BrushTool) -> void:
	pass


## Shift+wheel or a bracket key, `steps` notches (positive grows). Default: the brush size.
func step(brush: BrushTool, steps: int) -> void:
	brush.set_radius(BrushTool.stepped_radius(brush.get_radius(), steps))


## RMB or Delete over the target under the pointer (see `picks`).
func remove_target(_brush: BrushTool) -> void:
	pass


## Where the pointer ray from `origin` along `direction` meets the mode's ground when it
## meets no collision (a river drawn on past the map edge), or Vector3.INF.
func hit_past_edge(_origin: Vector3, _direction: Vector3) -> Vector3:
	return Vector3.INF


## The canopy fade's focus while `fades`: world centre in xyz, reach (metres, before
## BrushTool.fade_radius_factor) in w. Default: the ring.
func fade_focus(brush: BrushTool) -> Vector4:
	return Vector4(brush.hit.x, brush.hit.y, brush.hit.z, stroke_radius(brush))


## The ring's tint. Default: the glass accent.
func cursor_tint(_brush: BrushTool) -> Color:
	return BrushCursor.PLACE_TINT


## The readout under the ring, or "" for none.
func cursor_text(_brush: BrushTool) -> String:
	return ""


## Draws the cursor at `brush.hit` on `cursor`. Default: the ring, conformed to the ground's
## collision.
func draw_cursor(brush: BrushTool, cursor: BrushCursor) -> void:
	cursor.draw_ring(brush, cursor_tint(brush), cursor_text(brush), false)
