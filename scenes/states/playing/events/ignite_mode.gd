class_name IgniteMode
extends ToppleMode

## The Start a fire preset's gestures on the play brush (EventPresets), in two shapes Tab
## switches between (toggle_shape(); the pane's Shape field, ShapeField, line first):
##
##   Circle  (the default, as before card F6) Topple's ring and gestures: a click fires over
##           the brush ring around it, a drag from the press widens the ring up to
##           TerrainEvent.MAX_RADIUS_M and fires on release; [ ] and Shift+wheel size it. The
##           fire (TerrainEvent.fire) spreads out from the click. The ring is the presets'
##           ochre with "Start a fire" under it in a glass chip, and no marks: the whole forest
##           in the ring burns, not a counted set of trees.
##   Path    a drag draws the line the fire runs along (TerrainEvent.fire_path, design 3b-3d),
##           through the line tools' gesture (LineGesture: capture, the live line to the
##           pointer, Esc or RMB dropping it and staying armed, the minimum length) and ribbon
##           (LineRibbon: the river's and the fire line's look in Start a fire's own hue,
##           PATH_HUE, so the colour says which tool and the ribbon's shape which gesture). Its
##           half-width is the brush size within TerrainEvent's 1-6 m (path_radius()). At rest
##           the ring at the half-width alone, as the River's and the Line of fire's: the chip's
##           words tell the shapes apart (a dash across it read as a no-entry sign, card F6c);
##           while drawn one ribbon to the pointer in its stretches (Stretch, path_style(): the
##           forest spans, where trees catch, in the lay's full rails; the stretches between,
##           where only the ground burns, in the same ochre with the rails narrowed, eased in and
##           out along the arc, LineRibbon's quiet_spans; a line with no forest anywhere along
##           it, which a release refuses, in the refused ring's chalk_soft as lines alone; the
##           spans found again at most every SPAN_REFRESH_MS, FirePath.forest_spans) and the
##           chip (path_chip()). The line stops growing at
##           TerrainEvent.MAX_PATH_LENGTH_M; a release under StrokePath.MIN_LENGTH_M fires
##           nothing and says DRAW_PATH through `refused`.
##
## Only a forest burns: the ring searches for trees as Topple's marks do (the burnt forest's
## own snags passed over, FireSweep.burnable), and where none stands it is drawn in chalk_soft
## (CollapseMode.REFUSED_TINT: a click does nothing there) with "Only a forest burns" in its
## chip, and a click there says so through the brush's `refused` instead of firing; a path
## with no forest along it the same.

enum Shape { PATH, CIRCLE }
## A stretch of the Path while it is drawn, by what a release would do there (path_style()):
## TREES a forest span (the trees catch and the ground burns), GROUND between them (only the
## ground burns: the fire still runs there, quieter), REFUSED the whole line when no forest
## stands anywhere along it (a release fires nothing, as a click in the refused ring).
enum Stretch { TREES, GROUND, REFUSED }

## The pill's words, and the preset tile's label (EventPresets). (ToppleMode's TEXT is the
## parent's, so this one has a name of its own.)
const IGNITE_TEXT := "Start a fire"
const NOT_A_FOREST := "Only a forest burns"
## The Path's chip at rest and while drawn ("Fire along a path  48 ft"), at the length cap, and
## its refusal of a release too short to be a path.
const PATH_TEXT := "Fire along a path"
const LONGEST_TEXT := "Longest fire path"
const DRAW_PATH := "Draw the fire's path"
## The Path's ribbon: Start a fire's hue over the line tools' look (LineRibbon.lay_style),
## deep amber with its ring's light ochre glow, as the river is lake on light lake and the fire
## line persimmon on ember: each tint a deep step its rails' light brings up (ochre itself,
## lifted 1.36 to 1.53 times, clipped to lemon and white, card F6b). Amber, the user's pick of
## card F6c's three (2026-10-19): its rails near the river's and the fire line's presence, and
## standing off the golden meadow by hue where ochre merged with it.
const PATH_HUE := {"tint": ThemeColors.AMBER_DEEP, "glow": ToppleMode.TINT}
## The three hues card F6c offered, each a tint on the ring's glow, kept to compare: A deep
## ochre (its rails the lightest of the three line tools'), B ochre deeper still (its rails at
## the fire line's luminance, olive by day and bronze at night), C PATH_HUE.
const PATH_HUES := {
	"A": {"tint": ThemeColors.OCHRE_DEEP, "glow": ToppleMode.TINT},
	"B": {"tint": ThemeColors.OCHRE_DEEPER, "glow": ToppleMode.TINT},
	"C": PATH_HUE,
}
const HUE := "C"
## A path refused whole: the refused ring's chalk_soft, its lines alone with no fill
## (REFUSED_FILL), so it reads as the refused ring does, an outline where nothing will happen
## (its rails lifted read as a pure white band, the loudest thing on the board, card F6b).
const REFUSED_HUE := {"tint": CollapseMode.REFUSED_TINT, "glow": CollapseMode.REFUSED_TINT}
const REFUSED_FILL := {"alpha_up": 0.0, "alpha_down": 0.0}
## The forest spans of the line being drawn are found again at most this often (ms), and when
## its length has changed by SPAN_REFRESH_M (metres).
const SPAN_REFRESH_MS := 200
const SPAN_REFRESH_M := 0.5

var shape: int = Shape.CIRCLE
## The ribbon's fill (LineRibbon.FILLS), the line tools' own.
var fill: String = LineRibbon.FILL
## The ribbon's hue (PATH_HUES), HUE unless a look run picks another.
var hue: String = HUE
var gesture := LineGesture.new()

## The line being drawn's forest spans (FirePath.forest_spans along the live line, world
## metres), the length they were found at, and when.
var _spans := PackedVector2Array()
var _spans_length := -1.0
var _spans_msec := 0


## The ring's colour and words while the ring holds a forest (`has_forest`) or not. Pure.
static func ring_look(has_forest: bool) -> Dictionary:
	if has_forest:
		return {"tint": TINT, "text": IGNITE_TEXT}
	return {"tint": CollapseMode.REFUSED_TINT, "text": NOT_A_FOREST}


## The Path's chip: PATH_TEXT at rest; while a line `length_m` long is drawn its length in the
## level's units (`cell_m`, `per_cell`, `unit`; LineGesture.chip: "Fire along a path  48 ft"),
## LONGEST_TEXT once it reached the cap (`capped`), NOT_A_FOREST while no forest stands along
## it (`has_forest`). Pure.
static func path_chip(
	length_m: float,
	capped: bool,
	has_forest: bool,
	cell_m: float = 1.0,
	per_cell: float = 1.0,
	unit: String = "m"
) -> String:
	if length_m <= 0.0:
		return PATH_TEXT
	if not has_forest:
		return NOT_A_FOREST
	if capped:
		return LONGEST_TEXT
	return LineGesture.chip(PATH_TEXT, length_m, cell_m, per_cell, unit)


## The line a path event carries for a drawn `line` (map XZ): cut at
## TerrainEvent.MAX_PATH_LENGTH_M and resampled evenly (StrokePath, at most
## TerrainEvent.MAX_PATH_POINTS points at least StrokePath.MIN_SPACING_M apart). Pure.
static func event_line(line: PackedVector2Array) -> PackedVector2Array:
	var capped := StrokePath.capped(line, TerrainEvent.MAX_PATH_LENGTH_M)
	return StrokePath.resample(capped, TerrainEvent.MAX_PATH_POINTS, StrokePath.MIN_SPACING_M)


## The Path's ribbon style for a `stretch` (Stretch) along its whole length: over a forest span
## its hue (PATH_HUES[hue]) over the line tools' fill, every other key the river's and the fire
## line's; where only the ground burns the same as LineRibbon's quieter stretch (QUIET_STYLE);
## refused, the refused ring's chalk_soft with no fill (REFUSED_FILL).
func lay_style(stretch: int = Stretch.TREES) -> Dictionary:
	var own: Dictionary = PATH_HUES.get(hue, PATH_HUE)
	match stretch:
		Stretch.GROUND:
			return LineRibbon.lay_style(own, fill).merged(LineRibbon.QUIET_STYLE, true)
		Stretch.REFUSED:
			return LineRibbon.lay_style(REFUSED_HUE, fill).merged(REFUSED_FILL, true)
	return LineRibbon.lay_style(own, fill)


## The style of a line `length` metres long drawn with forest spans `spans` (arc spans, as
## FirePath.forest_spans), one ribbon: the TREES stretch's, the stretches between the spans
## its quiet_spans in the GROUND stretch's profile (the rails narrowing in and widening out
## along the arc, never a cut across the band); with no span at all the REFUSED stretch's.
func path_style(spans: PackedVector2Array, length: float) -> Dictionary:
	if spans.is_empty():
		return lay_style(Stretch.REFUSED)
	var quiet := PackedVector2Array()
	for run: Array in FirePath.runs(spans, length):
		if not bool(run[2]) and float(run[1]) > float(run[0]):
			quiet.append(Vector2(float(run[0]), float(run[1])))
	var style := lay_style(Stretch.TREES)
	style.quiet_spans = quiet
	style.quiet_profile = lay_style(Stretch.GROUND).fill_profile
	return style


## The Path's half-width on `brush` (world): the brush size within TerrainEvent's path range.
func path_radius(brush: BrushTool) -> float:
	var scale := _scale(brush)
	var low := TerrainEvent.MIN_PATH_RADIUS_M * scale
	return clampf(brush.get_radius(), low, TerrainEvent.MAX_PATH_RADIUS_M * scale)


func stroke_radius(brush: BrushTool) -> float:
	return path_radius(brush) if shape == Shape.PATH else super(brush)


func press(brush: BrushTool) -> bool:
	if shape == Shape.CIRCLE:
		return super(brush)
	gesture.begin(brush.hit)
	_spans = PackedVector2Array()
	_spans_length = -1.0
	return false


func frame(brush: BrushTool) -> void:
	if shape == Shape.CIRCLE:
		super(brush)
		return
	gesture.track(brush.hit, path_radius(brush))
	if gesture.drawing:
		_refresh_spans(brush)


func end(brush: BrushTool) -> void:
	if shape == Shape.PATH:
		_end_path(brush)
		return
	if not dragging:
		return
	dragging = false
	if brush.editor == null or centre == Vector3.INF:
		return
	var editor := brush.editor
	var radius := maxf(brush.get_radius(), reach) / _scale(brush)
	reach = 0.0
	var at := editor.to_map_xz(centre)
	if FireSweep.burnable(editor.scatter, at, radius, editor.palette_root, 1).is_empty():
		brush.refused.emit(TerrainEvents.NO_FOREST)
		return
	fired.emit(TerrainEvent.fire(at, radius, randi()))


func cancel(brush: BrushTool) -> void:
	super(brush)
	gesture.reset()


func leave(brush: BrushTool) -> void:
	super(brush)
	gesture.reset()
	_spans = PackedVector2Array()


func has_shapes() -> bool:
	return true


## Tab: Circle to Path and back (the pane's tiles, its Advanced and the hint bar follow,
## BrushTool.shape_toggled).
func toggle_shape(brush: BrushTool) -> bool:
	shape = Shape.PATH if shape == Shape.CIRCLE else Shape.CIRCLE
	brush.redraw()
	return true


func fade_focus(brush: BrushTool) -> Vector4:
	if shape == Shape.CIRCLE:
		return super(brush)
	return Vector4(brush.hit.x, brush.hit.y, brush.hit.z, path_radius(brush))


func cursor_tint(_brush: BrushTool) -> Color:
	if shape == Shape.PATH:
		return TINT if not gesture.drawing or not _spans.is_empty() else CollapseMode.REFUSED_TINT
	return ring_look(not marks().is_empty()).tint


func cursor_text(brush: BrushTool) -> String:
	if shape == Shape.PATH:
		var length := StrokePath.line_length(_live(brush)) if gesture.drawing else 0.0
		var most := TerrainEvent.MAX_PATH_LENGTH_M * _scale(brush)
		var capped := length >= most - 0.01
		var cell := brush.unit_cell_m
		return path_chip(
			length, capped, not _spans.is_empty(), cell, brush.unit_per_cell, brush.unit_label
		)
	return ring_look(not marks().is_empty()).text


func draw_cursor(brush: BrushTool, cursor: BrushCursor) -> void:
	if shape == Shape.PATH:
		_draw_path(brush, cursor)
		return
	var look := ring_look(not marks().is_empty())
	if not dragging:
		cursor.draw_ring(brush, look.tint, look.text, false)
		return
	cursor.draw_flat_ring(centre, stroke_radius(brush), look.tint)
	var at := cursor.camera.unproject_position(centre)
	cursor.canvas.draw_circle(at, 2.5, BrushCursor.SHADOW_COLOR)
	cursor.canvas.draw_circle(at, 1.5, look.tint)


## The trees a fire at world point `at` with world radius `radius` burns, as Topple's marks
## (never drawn: they say only whether a forest stands in the ring).
func _find_marks(editor: AuthoringEditor, at: Vector3, radius: float) -> PackedVector4Array:
	if editor == null:
		return PackedVector4Array()
	var burnt := FireSweep.burnt_biome(editor.palette_root)
	return base_marks(editor, at, radius, burnt + "/" if burnt != "" else "")


## The line being drawn out to the pointer (world XZ), cut at the path's longest.
func _live(brush: BrushTool) -> PackedVector2Array:
	var most := TerrainEvent.MAX_PATH_LENGTH_M * _scale(brush)
	return StrokePath.capped(gesture.live(brush.hit), most)


## A release in Path: the line drawn fires along its forest, or the brush says why not.
func _end_path(brush: BrushTool) -> void:
	if not gesture.drawing:
		return
	var drawn := gesture.finish()
	_spans = PackedVector2Array()
	if brush.editor == null:
		return
	if drawn.is_empty():
		brush.refused.emit(DRAW_PATH)
		return
	var editor := brush.editor
	var map_line := PackedVector2Array()
	for p in drawn:
		map_line.append(editor.to_map_xz(Vector3(p.x, 0.0, p.y)))
	var line := event_line(map_line)
	var radius := path_radius(brush) / _scale(brush)
	var root := editor.palette_root
	if FireSweep.burnable_along(editor.scatter, line, radius, root, 1).is_empty():
		brush.refused.emit(TerrainEvents.NO_FOREST_PATH)
		return
	fired.emit(TerrainEvent.fire_path(line, radius, randi()))


## Finds the live line's forest spans again when they are older than SPAN_REFRESH_MS and the
## line has grown or shrunk by SPAN_REFRESH_M since (every tree within the half-width,
## FireSweep.burnable_along, as the change searches).
func _refresh_spans(brush: BrushTool) -> void:
	var editor := brush.editor
	if editor == null:
		return
	var line := _live(brush)
	var length := StrokePath.line_length(line)
	var now := Time.get_ticks_msec()
	var stale := now - _spans_msec >= SPAN_REFRESH_MS or _spans_length < 0.0
	if not stale or absf(length - _spans_length) < SPAN_REFRESH_M and _spans_length >= 0.0:
		return
	_spans_msec = now
	_spans_length = length
	var scale := _scale(brush)
	var map_line := PackedVector2Array()
	for p in line:
		map_line.append(editor.to_map_xz(Vector3(p.x, 0.0, p.y)))
	var radius := path_radius(brush) / scale
	var trees := FireSweep.burnable_along(
		editor.scatter, map_line, radius, editor.palette_root, FirePath.ALL_TREES
	)
	var arcs := PackedFloat32Array()
	for tree in trees:
		arcs.append(float(tree.arc) * scale)
	_spans = FirePath.forest_spans(arcs, radius * scale, length)


## The Path's cursor: while drawn, its ribbon out to the pointer (path_style(): the forest spans
## and the ground between them in ochre, a path with no forest at all in chalk_soft), then the
## ring with its chip in the tip's colour; at rest the ring at the half-width alone.
func _draw_path(brush: BrushTool, cursor: BrushCursor) -> void:
	if gesture.drawing and brush.editor != null:
		var line := _live(brush)
		if line.size() >= 2:
			var ground := LineRibbon.on_ground(cursor.camera, brush.editor)
			var style := path_style(_spans, StrokePath.line_length(line))
			LineRibbon.draw(cursor, ground, line, path_radius(brush), style)
	cursor.draw_ring(brush, cursor_tint(brush), cursor_text(brush), false)
