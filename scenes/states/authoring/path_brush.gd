class_name PathBrush
extends BrushMode

## The Path tool's mode (PathTool, the Paint hub's Path tab; card terraform-p2-paint-path): the
## line tool the river and the line of fire are (LineGesture: the press begins the line, every
## frame records the pointer, the preview is the line tool's ribbon out to the pointer, Esc or RMB
## drops it, a line under StrokePath.MIN_LENGTH_M makes nothing, the chip reads "Path  Dirt track
## 40 ft"). Nothing lands while the line is drawn, so no press ever waits.
##
## The release. With the terrain core on (AuthoringEditor.terra.active()), the line becomes one
## path primitive (TerraPaint.add_path: kind 6, `width` and the surface, one history entry): its
## landing benches and grades the ground, steps where it climbs, a ford where it meets water, and
## lays the surface as a coat. Ctrl at the press erases instead: every path the line touches is
## removed (TerraPaint.erase_paths). With the core off, the release paints the surface along the
## line as one Paint stroke (capsules of half the width plus a soft edge; Ctrl erases paint), the
## path the Paint tool would lay by hand, with no grading.
##
## The surface is the Paint tab's pick (PaintBrush.surface: the map's biome path surface until the
## author picks another), so the two tabs paint one thing. The width is the pane's (PathToolPane)
## or Shift+wheel; the ring and the ribbon are the path's width.

const ERASE_TEXT := "Erase path"
const LABEL := "Path"
## The path's hue over the line tool's look (LineRibbon.lay_style): the river's in ochre.
const LAY_HUE := {"tint": ThemeColors.OCHRE_DEEP, "glow": ThemeColors.OCHRE_LIGHT}
const MIN_WIDTH := 0.6
const MAX_WIDTH := 6.0
## Shift+wheel's step (metres a notch).
const WIDTH_STEP := 0.2
## The switch-off lay: capsules of half the width plus SOFT_EDGE_M, LAY_SECONDS of exposure each
## per LAY_SPACING metres (the landform wash's 1.5 s covers fully).
const SOFT_EDGE_M := 0.5
const LAY_SECONDS := 1.5
const LAY_SPACING := 0.5
const MAX_LAY_DABS := 4096

## The path's width (world metres).
var width: float = 1.6
## The line being drawn (the line tool's gesture).
var gesture := LineGesture.new()
## The surface the line being drawn paints (the Paint tab's at the press).
var _surface: String = ""


func _init() -> void:
	fades = true


## The surface the Path tab paints on `brush`: the Paint tab's pick.
static func surface_of(brush: BrushTool) -> String:
	return PaintTool.of(brush).surface


## The chip's label for `surface`: "Path  Dirt track". Pure.
static func label_for(surface: String) -> String:
	return LABEL if surface == "" else "%s  %s" % [LABEL, AuthoringPanel.surface_label(surface)]


## The width a Shift+wheel of `steps` notches gives from `from`, clamped. Pure.
static func stepped_width(from: float, steps: int) -> float:
	return clampf(snappedf(from + WIDTH_STEP * steps, 0.1), MIN_WIDTH, MAX_WIDTH)


## Lays `line` (world XZ) on `editor` and returns true when anything changed: a path primitive
## with the core on (or with `erase` the paths it touches removed), else a Paint stroke along it
## (see the header). `width` is world metres.
static func lay(
	editor: AuthoringEditor,
	line: PackedVector2Array,
	width: float,
	surface: String,
	erase: bool
) -> bool:
	if not LineGesture.long_enough(line):
		return false
	if editor.terra.active():
		var map_line := PackedVector2Array()
		for p in line:
			map_line.append(editor.to_map_xz(Vector3(p.x, 0.0, p.y)))
		var map_width := width / editor.map_scale()
		if erase:
			return editor.terra.paint.erase_paths(map_line, map_width * 0.5) > 0
		return editor.terra.paint.add_path(map_line, map_width, surface) >= 0
	if not editor.begin_surface_stroke(surface, erase):
		return false
	var radius := width * 0.5 + SOFT_EDGE_M
	var points := StrokePath.resample(line, MAX_LAY_DABS + 1, LAY_SPACING)
	for i in points.size() - 1:
		var length := points[i].distance_to(points[i + 1])
		if length <= 0.0:
			continue
		var from := Vector3(points[i].x, 0.0, points[i].y)
		var to := Vector3(points[i + 1].x, 0.0, points[i + 1].y)
		editor.stroke_dab(from, to, radius, LAY_SECONDS * length / LAY_SPACING)
	editor.flush()
	return editor.end_stroke()


## Begins the line (the release lays it); refused while there is no surface to paint.
func press(brush: BrushTool) -> bool:
	_surface = surface_of(brush)
	if _surface == "" and not brush.press_ctrl:
		brush.refused.emit("Path: pick a surface in the Paint tab first")
		return false
	if not brush.press_ctrl:
		var reason := brush.editor.terra.paint_refusal(_surface)
		if reason != "":
			brush.refused.emit(reason)
			return false
	gesture.begin(brush.hit)
	return false


func took_press() -> bool:
	return gesture.drawing


## Records the line under the pointer.
func frame(brush: BrushTool) -> void:
	gesture.track(brush.hit, width * 0.5)


## Lays the line being drawn (the release, or a tool switch or undo before it).
func end(brush: BrushTool) -> void:
	var line := gesture.finish()
	if not line.is_empty() and brush.editor != null:
		lay(brush.editor, line, width, _surface, brush.press_ctrl)


func cancel(_brush: BrushTool) -> void:
	gesture.reset()


## Shift+wheel or a bracket key: the path's width.
func step(brush: BrushTool, steps: int) -> void:
	width = stepped_width(width, steps)
	brush.redraw()


## The ring is the path's half width.
func stroke_radius(_brush: BrushTool) -> float:
	return width * 0.5


func min_radius() -> float:
	return MIN_WIDTH * 0.5


func cursor_tint(brush: BrushTool) -> Color:
	return BrushCursor.CLEAR_TINT if _erasing(brush) else PaintTool.of(brush).tint


## "Path  Dirt track" (or "Erase path" with Ctrl), with the line's length while drawn.
func cursor_text(brush: BrushTool) -> String:
	var surface := _surface if gesture.drawing else surface_of(brush)
	return gesture.readout(ERASE_TEXT if _erasing(brush) else label_for(surface), brush)


## The line being drawn as the line tool's ribbon out to the pointer at the path's width, then
## the ring.
func draw_cursor(brush: BrushTool, cursor: BrushCursor) -> void:
	if gesture.drawing and brush.editor != null:
		var style := (
			LineRibbon.ERASE_STYLE
			if _erasing(brush)
			else LineRibbon.lay_style(LAY_HUE, LineRibbon.FILL)
		)
		var ground := LineRibbon.on_ground(cursor.camera, brush.editor)
		LineRibbon.draw(cursor, ground, gesture.live(brush.hit), stroke_radius(brush), style)
	super.draw_cursor(brush, cursor)


func _erasing(brush: BrushTool) -> bool:
	return brush.press_ctrl if (gesture.drawing or brush.pressed) else brush.ctrl
