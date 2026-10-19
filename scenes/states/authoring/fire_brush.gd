class_name FireBrush
extends BrushMode

## The Fire tool's mode (FireTool), with two shapes as Water has River and Pond (design
## section 2), Tab switching them (toggle_shape()):
##   Area   an LMB drag lays persistent ground fire with Paint's falloff and dwell, the fire
##          mask approaching the pane's intensity (BrushTool dabs the stroke).
##   Line   the line tool the river is (card F5e; user, 2026-10-11: the same affordance as
##          driving a river, and 2026-10-18: every shape and icon the same): its gesture
##          (LineGesture: capture, the live line to the pointer, Esc or RMB dropping it, the
##          minimum length, the chip "Line of fire  Blaze  40 ft") and its ribbon (LineRibbon)
##          in the river's look in orange (lay_style(): LAY_HUE over the line tool's fill, by
##          default persimmon rails at both edges on an ember glow, lit on the cursor's glow
##          layer, falling in a thin seam to clear along the centre line, chalk chevrons down
##          the middle; card F5d's variant C, card F5h one look for both). The release lays it
##          (lay_line()): resampled evenly every LINE_SPACING radii and dabbed segment by segment
##          as capsules at a fixed exposure per segment, so a line is even whatever the drawing
##          speed.
## The Line's ring and ribbon are as wide as the band its fire will stand in, not the brush:
## the soft falloff leaves the brush's rim under the flames band, so the shown half-width is
## line_reach() of the brush radius (about 0.7 to 0.8 of it), as a river's ring shows its
## channel. The lay itself keeps the brush radius, so its burnt forest and ash rim stay where
## an Area stroke of that size puts them.
## Both shapes lay through AuthoringEditor.begin_fire_stroke, so a lay is one history entry
## "Lay fire" with its burnt forest and ash (FireEditor), synced and undoable in play as any
## stroke. Ctrl at the press puts fire out instead (the area, or along the line), leaving its
## ash and snags. The ring is ember orange, the erase salmon (BrushCursor.CLEAR_TINT, every
## brush's erase) to put out; the put-out line's ribbon is the line tool's one erase
## (LineRibbon.ERASE_STYLE: the salmon edge and chevrons on ink, no wash), through which the
## flames it is drawn on keep their colour. Every colour is a theme role or the erase tint.

enum Shape { LINE, AREA }

const ERASE_TEXT := "Put out fire"
const LINE_TEXT := "Line of fire"
## The pane's intensity tiles, as mask bytes (design section 2).
const EMBERS := 96
const FLAMES := 176
const BLAZE := 255
## The intensity tiles' names (FireToolPane's), which the Line's chip names as the river's
## names its depth.
const INTENSITY_LABELS: Array[String] = ["Embers", "Flames", "Blaze"]
const TINT := ThemeColors.EMBER
## A laid line's dabs: one capsule every LINE_SPACING brush radii along the line, each with
## LINE_SECONDS of exposure (times the brush's flow). Along the centre a sample gathers about
## 5.3 dabs' worth, about 1.2 s: 97 % of the way to the intensity, the edges falling off as
## an Area stroke's do. MAX_LINE_DABS bounds a very long line's work.
const LINE_SPACING := 0.25
const LINE_SECONDS := 0.22
const MAX_LINE_DABS := 4096
## The fire line's hue over the line tool's look (LineRibbon.lay_style): the band and its edge
## in persimmon, the glow in ember, the ring's colour; the river's RIBBON_HUE in orange (card
## F5h: every width, alpha, edge, glow, ink, cap, chevron and fill one). Putting out along a
## line is the line tool's one erase (LineRibbon.ERASE_STYLE: the salmon lines on ink, no wash),
## the flames showing through in their own colour: any wash shifted them (a lake at half
## coverage left grey ghosts, card F5f; even a light lake at 0.08 to 0.14 cooled them, F5g).
const LAY_HUE := {"tint": ThemeColors.PERSIMMON, "glow": ThemeColors.EMBER}

## The mask byte a lay approaches (EMBERS, FLAMES or BLAZE).
var intensity: int = FLAMES
## The shape a press draws (Shape; Area until Tab or the pane picks Line).
var shape: int = Shape.AREA
## The line's fill (LineRibbon.FILLS; the firefeat_line_tool job shows "even" beside the
## default to compare), the river's always the same.
var fill: String = LineRibbon.FILL
## The line being drawn (the line tool's gesture).
var gesture := LineGesture.new()
## True while a line is being drawn (the gesture's).
var drawing: bool:
	get:
		return gesture.drawing


func _init() -> void:
	fades = true


## The dabs that lay `path` (world XZ, already smoothed) with a brush of `radius` metres at
## `flow`: [from: Vector3, to: Vector3, seconds: float] each, world space on the plane y = 0
## (the fire mask reads XZ alone). The path is resampled evenly (StrokePath.resample) about
## LINE_SPACING radii apart, and each segment's exposure is LINE_SECONDS scaled by its length
## over that spacing, so the exposure per metre, and with it the mask, does not depend on how
## the line was captured. Pure.
static func line_dabs(path: PackedVector2Array, radius: float, flow: float) -> Array:
	var spacing := maxf(radius * LINE_SPACING, 0.05)
	var points := StrokePath.resample(path, MAX_LINE_DABS + 1, spacing)
	var dabs: Array = []
	for i in points.size() - 1:
		var length := points[i].distance_to(points[i + 1])
		if length <= 0.0:
			continue
		var from := Vector3(points[i].x, 0.0, points[i].y)
		var to := Vector3(points[i + 1].x, 0.0, points[i + 1].y)
		dabs.append([from, to, LINE_SECONDS * flow * length / spacing])
	return dabs


## The share of the brush radius within which a line's fire stands (the half-width its ring
## and ribbon show): where a line laid at `intensity` (a mask byte) with `flow` over bare
## ground passes its band's start (FireField.FLAME_MIN, or EMBER_MIN for an intensity under
## the flames band), or with `erase`, where a blaze falls under EMBER_MIN. A sample at t
## radii from a long straight line gathers line_exposure(t) * LINE_SECONDS * flow seconds,
## which MaskBrush.amount turns into the mask (CLEAR_GAIN times faster to put out). Pure.
static func line_reach(intensity: int, flow: float, erase: bool) -> float:
	var seconds := LINE_SECONDS * maxf(flow, 0.0)
	var need := 0.0
	if erase:
		var rate := MaskBrush.RATE * MaskBrush.CLEAR_GAIN
		need = log(float(BLAZE) / FireField.EMBER_MIN) / rate
	else:
		var band := FireField.FLAME_MIN if intensity > FireField.FLAME_MIN else FireField.EMBER_MIN
		if intensity <= band:
			return 0.0
		need = -log(1.0 - float(band) / float(intensity)) / MaskBrush.RATE
	if line_exposure(0.0) * seconds < need:
		return 0.0
	var inside := 0.0
	var outside := 1.0
	for i in 24:
		var t := (inside + outside) * 0.5
		if line_exposure(t) * seconds >= need:
			inside = t
		else:
			outside = t
	return inside


## The dabs' worth of exposure a sample at `t` brush radii from a long straight laid line
## gathers (line_dabs()): the capsule beside it weighs MaskBrush.falloff(t) = c^4 (c^2 =
## 1 - t^2), and the ones along the line, LINE_SPACING radii apart, add their falloff's
## integral along the line over the spacing, 16/15 c^5 / LINE_SPACING (5.3 at the centre). Pure.
static func line_exposure(t: float) -> float:
	if t >= 1.0:
		return 0.0
	var c2 := 1.0 - t * t
	return c2 * c2 + 16.0 / 15.0 * c2 * c2 * sqrt(c2) / LINE_SPACING


## Lays the line `path` (world XZ, smoothed) on `editor` with a brush of `radius` metres: fire
## toward `target` (0..1 of 255), or with `erase` put out along it, as one stroke (one history
## entry, FireEditor). A path too short for a line (LineGesture.long_enough) lays nothing. True
## when the fire changed.
static func lay_line(
	editor: AuthoringEditor,
	path: PackedVector2Array,
	radius: float,
	target: float,
	erase: bool,
	flow: float = 1.0
) -> bool:
	if not LineGesture.long_enough(path):
		return false
	if not editor.begin_fire_stroke(target, erase):
		return false
	for dab: Array in line_dabs(path, radius, flow):
		editor.stroke_dab(dab[0], dab[1], radius, dab[2])
	editor.flush()
	return editor.end_stroke()


## The intensity tile's name for mask byte `value`: Embers up to EMBERS, Flames up to FLAMES,
## else Blaze. Pure.
static func intensity_label(value: int) -> String:
	if value <= EMBERS:
		return INTENSITY_LABELS[0]
	return INTENSITY_LABELS[1] if value <= FLAMES else INTENSITY_LABELS[2]


## The Line's chip label, the line tool's "<shape>  <setting>": "Line of fire  Blaze".
func line_label() -> String:
	return "%s  %s" % [LINE_TEXT, intensity_label(intensity)]


## The fire line's ribbon style: its hue (LAY_HUE) over the line tool's fill `fill`, the
## river's with only the hue changed.
func lay_style() -> Dictionary:
	return LineRibbon.lay_style(LAY_HUE, fill)


## Area: a fire stroke for the brush to dab. Line: the line begins (the release lays it).
func press(brush: BrushTool) -> bool:
	if shape == Shape.AREA:
		return brush.editor.begin_fire_stroke(intensity / 255.0, brush.press_ctrl)
	gesture.begin(brush.hit)
	return false


## Records the line under the pointer (LineGesture.track at the brush's radius, the lay's).
func frame(brush: BrushTool) -> void:
	gesture.track(brush.hit, brush.get_radius())


## Lays the line being drawn (the release, or a tool switch or undo before it).
func end(brush: BrushTool) -> void:
	var path := gesture.finish()
	if not path.is_empty() and brush.editor != null:
		var target := intensity / 255.0
		lay_line(brush.editor, path, brush.get_radius(), target, brush.press_ctrl, brush.get_flow())


func cancel(_brush: BrushTool) -> void:
	gesture.reset()


func has_shapes() -> bool:
	return true


## Tab: Area to Line and back (the pane's tiles and the hint bar follow,
## BrushTool.shape_toggled).
func toggle_shape(brush: BrushTool) -> bool:
	shape = Shape.LINE if shape == Shape.AREA else Shape.AREA
	brush.redraw()
	return true


## Red while putting out: Ctrl held at the press during a gesture, else Ctrl held now.
func cursor_tint(brush: BrushTool) -> Color:
	return BrushCursor.CLEAR_TINT if _erasing(brush) else TINT


## Line: the half-width of the band its fire stands in (or is put out in), line_reach() of
## the brush radius, which the ring and the ribbon show. Area: the brush radius.
func stroke_radius(brush: BrushTool) -> float:
	if shape == Shape.AREA:
		return brush.get_radius()
	var reach := line_reach(intensity, brush.get_flow(), _erasing(brush))
	return brush.get_radius() * maxf(reach, 0.1)


## The red ring names its erase under it ("Put out fire"), as Paint's "Erase paint"; the Line
## shape says what it lays as the river does ("Line of fire  Blaze", line_label(), or "Put out
## fire" with Ctrl), with the line's length in the level's units while drawn
## (LineGesture.readout).
func cursor_text(brush: BrushTool) -> String:
	var erasing := _erasing(brush)
	if shape == Shape.AREA:
		return ERASE_TEXT if erasing else ""
	return gesture.readout(ERASE_TEXT if erasing else line_label(), brush)


## The line being drawn as the line tool's ribbon out to the pointer, at the ring's width, in
## the fire line's style (lay_style(), or the line tool's erase with Ctrl), then the ring.
func draw_cursor(brush: BrushTool, cursor: BrushCursor) -> void:
	if drawing and brush.editor != null:
		var style := LineRibbon.ERASE_STYLE if _erasing(brush) else lay_style()
		var ground := LineRibbon.on_ground(cursor.camera, brush.editor)
		LineRibbon.draw(cursor, ground, gesture.live(brush.hit), stroke_radius(brush), style)
	super.draw_cursor(brush, cursor)


func _erasing(brush: BrushTool) -> bool:
	return brush.press_ctrl if (brush.stroking or brush.pressed) else brush.ctrl
