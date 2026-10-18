class_name FireBrush
extends BrushMode

## The Fire tool's mode (FireTool), with two shapes as Water has River and Pond (design
## section 2), Tab switching them (toggle_shape()):
##   Area   an LMB drag lays persistent ground fire with Paint's falloff and dwell, the fire
##          mask approaching the pane's intensity (BrushTool dabs the stroke).
##   Line   the press starts a line captured as a river's (StrokePath: a point every
##          StrokePath.DECIMATE_M, or every WaterBrush.WIDTH_DECIMATE radii for a wide brush,
##          the release point added, Chaikin-smoothed), previewed while dragging with the
##          river's own ribbon (WaterBrush.draw_ribbon: gradient fill, edges, chevrons; user,
##          2026-10-11: the same affordance as driving a river) in the line's own style
##          (LAY_STYLE: a persimmon fill at about half coverage that adds light on the
##          cursor's glow layer, so it glows orange over green grass, a yellow meadow, a dark
##          wood and at night; a full persimmon edge, chalk chevrons, round ends). The
##          release lays it (lay_line()): resampled evenly every LINE_SPACING radii and dabbed
##          segment by segment as capsules at a fixed exposure per segment, so a line is even
##          whatever the drawing speed. A release under StrokePath.MIN_LENGTH_M lays nothing;
##          Esc or RMB mid-drag drops the line.
## The Line's ring and ribbon are as wide as the band its fire will stand in, not the brush:
## the soft falloff leaves the brush's rim under the flames band, so the shown half-width is
## line_reach() of the brush radius (about 0.7 to 0.8 of it), as a river's ring shows its
## channel. The lay itself keeps the brush radius, so its burnt forest and ash rim stay where
## an Area stroke of that size puts them.
## Both shapes lay through AuthoringEditor.begin_fire_stroke, so a lay is one history entry
## "Lay fire" with its burnt forest and ash (FireEditor), synced and undoable in play as any
## stroke. Ctrl at the press puts fire out instead (the area, or along the line), leaving its
## ash and snags. The ring is ember orange, the erase salmon (BrushCursor.CLEAR_TINT, every
## brush's erase) to put out; the put-out line's ribbon (PUT_OUT_STYLE) keeps that salmon on
## its edge and chevrons over a cool interior (put_out_tint) that reads over bright flames and
## over char alike. Every colour is a theme role or the erase tint; only alphas are set here.

enum Shape { LINE, AREA }

const ERASE_TEXT := "Put out fire"
const LINE_TEXT := "Line of fire"
## The pane's intensity tiles, as mask bytes (design section 2).
const EMBERS := 96
const FLAMES := 176
const BLAZE := 255
const TINT := ThemeColors.EMBER
## A laid line's dabs: one capsule every LINE_SPACING brush radii along the line, each with
## LINE_SECONDS of exposure (times the brush's flow). Along the centre a sample gathers about
## 5.3 dabs' worth, about 1.2 s: 97 % of the way to the intensity, the edges falling off as
## an Area stroke's do. MAX_LINE_DABS bounds a very long line's work.
const LINE_SPACING := 0.25
const LINE_SECONDS := 0.22
const MAX_LINE_DABS := 4096
## The line's ribbon fill, and its look over the river's (WaterBrush.RIBBON_STYLE's keys): a
## persimmon at about half coverage, stronger toward the pointer, lit by LAY_GAIN on the glow
## layer (WaterBrush.lit_fill), so it adds light where a plain fill greyed toward the ground's
## colour (ochre over green grass, brown over a pine wood); a full persimmon edge on a soft
## ember glow and a faint ink line keeps the band crisp; chalk chevrons; round ends.
const LAY_TINT := ThemeColors.PERSIMMON
const LAY_GAIN := 2.4
const LAY_STYLE := {
	"alpha_up": 0.46,
	"alpha_down": 0.56,
	"fill_gain": LAY_GAIN,
	"edge": ThemeColors.PERSIMMON,
	"edge_alpha": 1.0,
	"edge_width": 2.5,
	"shadow": ThemeColors.INK,
	"shadow_alpha": 0.3,
	"shadow_width": 4.5,
	"glow": ThemeColors.EMBER,
	"glow_alpha": 0.3,
	"glow_width": 9.0,
	"chevron": ThemeColors.CHALK,
	"chevron_alpha": 0.95,
	"chevron_width": 2.5,
	"chevron_shadow_alpha": 0.45,
	"chevron_shadow_width": 4.5,
	"caps": true,
}
## Putting out along a line: the erase salmon (BrushCursor.CLEAR_TINT, the ring's) on the edge
## and the chevrons over an ink outline, round ends, and a cool interior (put_out_tint) at the
## lay's coverage, a plain fill (gain 1), so the band reads over the glare of the flames it is
## drawn on and over char, calm rather than alarming. The interior is the lake, water on fire:
## against the warm blaze it parted more plainly than an ash plum-grey (PAPER_TRACK), whose
## mauve leaned into the flames' pinks (card F5c, firefeat_line erase_drag_a and _b).
const PUT_OUT_TINT := ThemeColors.LAKE
const PUT_OUT_STYLE := {
	"alpha_up": 0.46,
	"alpha_down": 0.56,
	"fill_gain": 1.0,
	"edge": BrushCursor.CLEAR_TINT,
	"edge_alpha": 1.0,
	"edge_width": 2.5,
	"shadow": ThemeColors.INK,
	"shadow_alpha": 0.7,
	"shadow_width": 5.5,
	"chevron": BrushCursor.CLEAR_TINT,
	"chevron_alpha": 1.0,
	"chevron_width": 2.5,
	"chevron_shadow_alpha": 0.6,
	"chevron_shadow_width": 4.5,
	"caps": true,
}

## The mask byte a lay approaches (EMBERS, FLAMES or BLAZE).
var intensity: int = FLAMES
## The shape a press draws (Shape; Area until Tab or the pane picks Line).
var shape: int = Shape.AREA
## The put-out ribbon's interior (PUT_OUT_TINT; the firefeat_line job sets the ash candidate
## and the lake in turn to show both).
var put_out_tint: Color = PUT_OUT_TINT
## A line being drawn: its recorded points (world XZ).
var line := PackedVector2Array()
var drawing: bool = false

## The pointer's last ground point while a line is drawn (world XZ; Vector2.INF: none): the
## release point, which the line ends at whether or not decimation recorded it.
var _tip: Vector2 = Vector2.INF


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
## entry, FireEditor). A path under StrokePath.MIN_LENGTH_M lays nothing. True when the fire
## changed.
static func lay_line(
	editor: AuthoringEditor,
	path: PackedVector2Array,
	radius: float,
	target: float,
	erase: bool,
	flow: float = 1.0
) -> bool:
	if StrokePath.line_length(path) < StrokePath.MIN_LENGTH_M:
		return false
	if not editor.begin_fire_stroke(target, erase):
		return false
	for dab: Array in line_dabs(path, radius, flow):
		editor.stroke_dab(dab[0], dab[1], radius, dab[2])
	editor.flush()
	return editor.end_stroke()


## The line a release lays now: the recorded points ended at the pointer
## (StrokePath.with_tip), smoothed (StrokePath.smooth_line).
func laid_line() -> PackedVector2Array:
	return StrokePath.smooth_line(StrokePath.with_tip(line, _tip, StrokePath.DECIMATE_M))


## Drops a line's state (release or cancel).
func reset() -> void:
	drawing = false
	line = PackedVector2Array()
	_tip = Vector2.INF


## Area: a fire stroke for the brush to dab. Line: the line begins (the release lays it).
func press(brush: BrushTool) -> bool:
	if shape == Shape.AREA:
		return brush.editor.begin_fire_stroke(intensity / 255.0, brush.press_ctrl)
	var at := Vector2(brush.hit.x, brush.hit.z)
	line = StrokePath.decimate(PackedVector2Array(), at, StrokePath.DECIMATE_M)
	_tip = at
	drawing = true
	return false


## Records the line under the pointer, a point once it lies the capture spacing from the last.
func frame(brush: BrushTool) -> void:
	if not drawing or brush.hit == Vector3.INF:
		return
	var at := Vector2(brush.hit.x, brush.hit.z)
	var spacing := maxf(StrokePath.DECIMATE_M, brush.get_radius() * WaterBrush.WIDTH_DECIMATE)
	line = StrokePath.decimate(line, at, spacing)
	_tip = at


## Lays the line being drawn (the release, or a tool switch or undo before it).
func end(brush: BrushTool) -> void:
	if not drawing:
		return
	var path := laid_line()
	reset()
	if brush.editor != null:
		var target := intensity / 255.0
		lay_line(brush.editor, path, brush.get_radius(), target, brush.press_ctrl, brush.get_flow())


func cancel(_brush: BrushTool) -> void:
	reset()


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
## shape says what it lays ("Line of fire", or "Put out fire" with Ctrl), with the line's
## length in the level's units while drawn.
func cursor_text(brush: BrushTool) -> String:
	var erasing := _erasing(brush)
	if shape == Shape.AREA:
		return ERASE_TEXT if erasing else ""
	var label := ERASE_TEXT if erasing else LINE_TEXT
	if not drawing:
		return label
	var length := StrokePath.line_length(laid_line())
	var shown := ScaleUtils.world_to_display(length, brush.unit_cell_m, brush.unit_per_cell)
	return "%s  %d %s" % [label, roundi(shown), brush.unit_label]


## The line being drawn as the river's ribbon up to the pointer, at the ring's width, in the
## line's style (LAY_STYLE, or PUT_OUT_STYLE with Ctrl), its fill on the cursor's glow layer,
## then the ring.
func draw_cursor(brush: BrushTool, cursor: BrushCursor) -> void:
	if drawing and not line.is_empty() and brush.editor != null:
		var live := line.duplicate()
		if brush.hit != Vector3.INF:
			var tip := Vector2(brush.hit.x, brush.hit.z)
			if live[-1].distance_to(tip) > 0.05:
				live.append(tip)
		var erasing := _erasing(brush)
		WaterBrush.draw_ribbon(
			cursor.canvas,
			WaterBrush.on_ground(cursor.camera, brush.editor),
			StrokePath.smooth_line(live),
			stroke_radius(brush),
			put_out_tint if erasing else LAY_TINT,
			1.0,
			true,
			PUT_OUT_STYLE if erasing else LAY_STYLE,
			cursor.glow_item()
		)
	super.draw_cursor(brush, cursor)


func _erasing(brush: BrushTool) -> bool:
	return brush.press_ctrl if (brush.stroking or brush.pressed) else brush.ctrl
