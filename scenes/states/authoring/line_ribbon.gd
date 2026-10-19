class_name LineRibbon
extends RefCounted

## The ribbon every line tool previews its line with (card F5e: Water's River and Fire's Line,
## and each one's erase): one shape in two tints, so the river and the fire line read as one
## line tool. A band `radius` either side of the line, filled from the line's start (fainter)
## to its end, round caps at both ends, one closed edge over an ink outline on a soft glow, and
## chevrons every ARROW_M pointing the way the line runs (a river's, the way its water will
## flow). It is drawn on BrushCursor's overlay with its fill on the cursor's glow layer
## (BrushCursor.glow_item(), premultiplied), where a fill lit above gain 1 adds light as well as
## covering (lit_fill()). It takes the scene's light (scene_light()): NIGHT_LIGHT of its colour
## under a sun well below the horizon, so at night it sits in the dark scene instead of glowing
## over it, and its full colour from the horizon up (a dusk sun 2.5 degrees up weighs about
## nothing while the scene is still bright, card F5d).
##
## What a tool changes is its style, as data: STYLE's keys, of which a tool passes only those it
## changes (WaterBrush.RIBBON_STYLE, FireBrush.LAY_STYLE; erase_style() for an erase):
##   tint                  the fill's colour, and the edge's and glow's where those are null
##   alpha_up, alpha_down  the fill's coverage at the line's start and at its end
##   fill_profile          the coverage across the band: [offset, coverage] pairs from the edge
##                         (offset 1) in to the centre line (0), each scaling the fill's alpha
##                         there, mirrored about the centre; empty: even, edge to edge
##   fill_gain             0: a plain fill; above 0 the fill premultiplied and lit by that gain
##                         for the glow layer (1 blends as a plain fill)
##   edge, edge_alpha, edge_width          the edge round the band (edge null: the tint)
##   shadow, shadow_alpha, shadow_width    the ink outline under the edge
##   glow, glow_alpha, glow_width          a soft line under both (glow null: the edge's colour;
##                                         width 0: none)
##   chevrons              false: none
##   chevron, chevron_alpha, chevron_width, chevron_shadow_alpha, chevron_shadow_width
##                         the chevrons over their ink outline
##   caps                  round ends, the edge running round them as one outline (false: cut
##                         square)
##   night_light           the share of its colour the ribbon keeps under no sun (1: all)
## An erase ribbon is the same shape with the erase salmon (BrushCursor.CLEAR_TINT, every
## brush's erase) on its edge and glow over the erase's ink (the erase ring's,
## BrushCursor.ring_strokes), the lay's chevrons with only their colour salmon, and no wash
## inside (ERASE_STYLE), so what it erases shows through untouched. Every colour is a theme
## role, the erase tint or a tool's tint; only alphas and widths are set here.

## Metres between chevrons along the line, the first half that from the start.
const ARROW_M := 2.5
## A round cap's half circle, in segments.
const CAP_SEGMENTS := 12
## The share of its colour a ribbon keeps under a sun well below the horizon (0.6 lost the thin
## lines in the dark, card F5d's first round).
const NIGHT_LIGHT := 0.75
## The published sun's height (FoliageLight.last_sun's y) at and under which a ribbon is at its
## night_light: about 6 degrees below the horizon.
const DARK_HEIGHT := -0.1
## A chevron's width across on screen (px) at which it is drawn at its style's widths: a 1.5 m
## chevron at zoom 22 (the reference zoom) in a CHEVRON_VIEW_H window. A larger one scales its
## strokes with it, so it is one glyph at any zoom (thin strokes on a close erase's chevrons read
## as hollow outlines, F5f).
const CHEVRON_PX := 44.0
## The view height CHEVRON_PX is measured in. A chevron is never drawn wider across than
## CHEVRON_PX times the view's height over this, its look at the reference zoom: closer in, the
## glyph keeps that size and weight instead of growing (at zoom 8 the scaled glyph was 120 px of
## 7 px strokes on 12 px of ink, read as road markings, F5g).
const CHEVRON_VIEW_H := 720.0
## Every line tool's look, before its own keys (the class header names them). The edge's ink
## at 0.55 (the ring's shadow) keeps the edge a crisp line over the fire's lit rails as over the
## river's wash (at 0.3 the fire's edge sank into its rail and glow, F5f).
const STYLE := {
	"tint": ThemeColors.CHALK,
	"alpha_up": 0.12,
	"alpha_down": 0.34,
	"fill_profile": [],
	"fill_gain": 1.0,
	"edge": null,
	"edge_alpha": 1.0,
	"edge_width": 2.5,
	"shadow": ThemeColors.INK,
	"shadow_alpha": 0.55,
	"shadow_width": 4.5,
	"glow": null,
	"glow_alpha": 0.3,
	"glow_width": 9.0,
	"chevrons": true,
	"chevron": ThemeColors.CHALK,
	"chevron_alpha": 0.95,
	"chevron_width": 2.5,
	"chevron_shadow_alpha": 0.6,
	"chevron_shadow_width": 4.5,
	"caps": true,
	"night_light": NIGHT_LIGHT,
}
## An erase's keys over STYLE: the erase salmon on the edge and its glow over the erase's ink,
## which holds the salmon at 3:1 over bright flames and pale water alike (BrushCursor
## .ring_strokes, the erase ring's own); the lay's chevrons, glyph, places, weights and ink, with
## only their colour salmon; and no wash inside, so what goes shows through untouched and the
## salmon lines alone say "erase". Any wash shifted what it lay on: at about half coverage (F5e)
## it hid the river as a flat dusty rose and greyed the flames to mud, and even at 0.08 to 0.14
## the salmon, the water's complement, pulled the river's blue over red from about 40 to about
## 20, and the light lake cooled the flames (F5f, F5g).
const ERASE_STYLE := {
	"alpha_up": 0.0,
	"alpha_down": 0.0,
	"edge": BrushCursor.CLEAR_TINT,
	"edge_width": BrushCursor.ERASE_LINE_WIDTH,
	"chevron": BrushCursor.CLEAR_TINT,
	"shadow_alpha": BrushCursor.ERASE_INK_ALPHA,
	"shadow_width": BrushCursor.ERASE_INK_WIDTH,
}


## An erase ribbon's style: ERASE_STYLE with `interior`'s keys (its tint; a tool that wants a
## wash back sets its alphas there too). Pure.
static func erase_style(interior: Dictionary) -> Dictionary:
	return ERASE_STYLE.merged(interior, true)


## Draws the ribbon of `line` (world XZ; `ground` maps a point to the screen on the ground) at
## half-width `radius` in `style` on `cursor`: its lines on the cursor's canvas, its fill on the
## glow layer, every colour in the scene's light under the published sun and times `strength`,
## its chevrons no larger than the reference zoom's in the canvas's view.
static func draw(
	cursor: BrushCursor,
	ground: Callable,
	line: PackedVector2Array,
	radius: float,
	style: Dictionary,
	strength: float = 1.0
) -> void:
	var light := light_of(style, FoliageLight.last_sun)
	var view_height := cursor.canvas.get_viewport_rect().size.y
	var shape := ribbon(ground, line, radius, style, strength, light, view_height)
	draw_shape(cursor.canvas, shape, cursor.glow_item())


## Draws a ribbon() `shape` on `canvas`: the fill's triangles on `fill_item` when valid (the
## glow layer), else on the canvas, then its lines in order. Nothing for {}.
static func draw_shape(canvas: Control, shape: Dictionary, fill_item: RID = RID()) -> void:
	if shape.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(
		fill_item if fill_item.is_valid() else canvas.get_canvas_item(),
		shape.indices,
		shape.points,
		shape.colors
	)
	for stroke: Array in shape.lines:
		canvas.draw_polyline(stroke[0], stroke[1], stroke[2], true)


## The ribbon's `ground`: a world XZ point to the screen, on `editor`'s ground there (lifted
## 5 cm), seen by `camera`.
static func on_ground(camera: Camera3D, editor: AuthoringEditor) -> Callable:
	return func(xz: Vector2) -> Vector2:
		var p := Vector3(xz.x, 0.0, xz.y)
		p.y = editor.ground_height_at(p) + 0.05
		return camera.unproject_position(p)


## The light `style`'s ribbon takes under the published `sun` (scene_light() at its
## night_light). Pure.
static func light_of(style: Dictionary, sun: Vector4) -> float:
	return scene_light(sun, float(style.get("night_light", STYLE.night_light)))


## The light a ribbon takes under the published `sun` (FoliageLight.last_sun: xyz toward it):
## `least` with the sun DARK_HEIGHT or more under the horizon, rising smoothly to 1 as it comes
## up to the horizon. A map with no sun publishes FoliageLight.NO_SUN, straight up: full. Pure.
static func scene_light(sun: Vector4, least: float) -> float:
	return lerpf(least, 1.0, smoothstep(DARK_HEIGHT, 0.0, sun.y))


## What draw() draws, as data: the fill's triangles ("points", "colors", "indices") and
## "lines", [points, colour, width] per polyline in drawing order (the glow, the ink outline,
## the edge, then each chevron's outline and chevron; with caps the two edges are one closed
## outline, and each cap a fan after the band's triangles), every colour times `strength` and
## at `light` of itself (alpha kept), the chevrons clamped for a view `view_height` px tall
## (_chevrons()); {} for a line under two points. Pure but for `ground`.
static func ribbon(
	ground: Callable,
	line: PackedVector2Array,
	radius: float,
	style: Dictionary = {},
	strength: float = 1.0,
	light: float = 1.0,
	view_height: float = CHEVRON_VIEW_H
) -> Dictionary:
	var n := line.size()
	if n < 2:
		return {}
	var look := STYLE.merged(style, true)
	var tint: Color = look.tint
	var gain := float(look.fill_gain)
	var row := fill_row(look.fill_profile)
	var width := row.size()
	var total := StrokePath.line_length(line)
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var walked := 0.0
	var last_l := Vector2.INF
	var last_r := Vector2.INF
	for i in n:
		if i > 0:
			walked += line[i - 1].distance_to(line[i])
		var tangent := (line[mini(i + 1, n - 1)] - line[maxi(i - 1, 0)]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var world_l := line[i] + normal * radius
		var world_r := line[i] - normal * radius
		# The inside of a bend tighter than the ribbon never runs backwards (no twisted quads).
		if last_l != Vector2.INF and (world_l - last_l).dot(tangent) < 0.0:
			world_l = last_l
		if last_r != Vector2.INF and (world_r - last_r).dot(tangent) < 0.0:
			world_r = last_r
		last_l = world_l
		last_r = world_r
		var alpha := lerpf(look.alpha_up, look.alpha_down, walked / maxf(total, 0.001))
		for step: Array in row:
			var offset: float = step[0]
			var world := world_l if offset > 0.0 else world_r
			if absf(offset) < 1.0:
				world = line[i] + (world - line[i]) * absf(offset)
			points.append(ground.call(world))
			var fill := _at_alpha(tint, alpha * strength * float(step[1]))
			colors.append(lit_fill(fill, gain) if gain > 0.0 else fill)
		left.append(points[width * i])
		right.append(points[width * i + width - 1])
	var indices := PackedInt32Array()
	for i in n - 1:
		for k in width - 1:
			var a := width * i + k
			indices.append_array([a, a + 1, a + width, a + 1, a + width + 1, a + width])
	var sides: Array = [left, right]
	if look.caps:
		var capped := _with_caps(ground, line, radius, row, points, colors, indices)
		points = capped.points
		colors = capped.colors
		indices = capped.indices
		sides = [_outline(left, right, capped.arcs)]
	var edge: Color = tint if look.edge == null else look.edge
	var shadow: Color = look.shadow
	var lines: Array = []
	if float(look.glow_width) > 0.0:
		var glow: Color = edge if look.glow == null else look.glow
		for side in sides:
			lines.append([side, _at_alpha(glow, look.glow_alpha * strength), look.glow_width])
	for side in sides:
		var under := _at_alpha(shadow, look.shadow_alpha * strength)
		lines.append([side, under, look.shadow_width])
		lines.append([side, _at_alpha(edge, look.edge_alpha * strength), look.edge_width])
	if look.chevrons:
		lines.append_array(_chevrons(ground, line, radius, look, strength, view_height))
	var shape := {"points": points, "colors": colors, "indices": indices, "lines": lines}
	return in_light(shape, light)


## The three world points of a chevron at `at` pointing along `tangent` (unit), `size` metres
## across: a barb either side behind, the tip ahead. Pure.
static func chevron(at: Vector2, tangent: Vector2, size: float) -> PackedVector2Array:
	var normal := Vector2(-tangent.y, tangent.x)
	return PackedVector2Array(
		[
			at - tangent * size * 0.2 + normal * size * 0.45,
			at + tangent * size * 0.3,
			at - tangent * size * 0.2 - normal * size * 0.45,
		]
	)


## A fill colour for a premultiplied-alpha canvas item: `fill` times its alpha and `gain`, the
## alpha kept. A gain of 1 blends as a plain fill; above 1 the fill adds light as well as
## covering, so it brightens what is under it instead of greying it (a fire line). Pure.
static func lit_fill(fill: Color, gain: float) -> Color:
	var lit := fill * (fill.a * gain)
	lit.a = fill.a
	return lit


## The fill's row across the band, left edge to right: [offset, coverage] pairs, the offset
## signed (1 the left edge, -1 the right, 0 the centre line), from `profile` (STYLE's
## fill_profile, edge in to centre) mirrored about the centre; an empty profile is the two
## edges at full coverage. Pure.
static func fill_row(profile: Array) -> Array:
	var half: Array = [[1.0, 1.0]] if profile.is_empty() else profile
	var row: Array = []
	for step: Array in half:
		row.append([float(step[0]), float(step[1])])
	for k in range(half.size() - 1, -1, -1):
		if float(half[k][0]) > 0.0:
			row.append([-float(half[k][0]), float(half[k][1])])
	return row


## `shape` with every colour, fill and line, at `light` of its own (alpha kept). Pure.
static func in_light(shape: Dictionary, light: float) -> Dictionary:
	if light >= 1.0:
		return shape
	var out := shape.duplicate()
	var colors := PackedColorArray()
	for c: Color in shape.colors:
		colors.append(_dimmed(c, light))
	var lines: Array = []
	for stroke: Array in shape.lines:
		lines.append([stroke[0], _dimmed(stroke[1], light), stroke[2]])
	out.colors = colors
	out.lines = lines
	return out


## `c` with alpha `alpha` (a style's colours are theme roles; only their alpha is set here).
static func _at_alpha(c: Color, alpha: float) -> Color:
	var out := c
	out.a = alpha
	return out


static func _dimmed(c: Color, light: float) -> Color:
	var out := c * light
	out.a = c.a
	return out


## The chevrons along `line` every ARROW_M, the first half that from the start, each as its
## ink outline then itself: ribbon()'s lines. A chevron wider across on screen than its look at
## the reference zoom (CHEVRON_PX in a CHEVRON_VIEW_H view, scaled to `view_height`) is drawn at
## that width about the same point; its strokes take the style's widths scaled by its width
## across over CHEVRON_PX (never below 1). Pure but for `ground`.
static func _chevrons(
	ground: Callable,
	line: PackedVector2Array,
	radius: float,
	look: Dictionary,
	strength: float,
	view_height: float
) -> Array:
	var lines: Array = []
	var under := _at_alpha(look.shadow, look.chevron_shadow_alpha * strength)
	var over := _at_alpha(look.chevron, look.chevron_alpha * strength)
	var size := minf(radius, 1.5)
	var widest := CHEVRON_PX * view_height / CHEVRON_VIEW_H
	var next := ARROW_M * 0.5
	var walked := 0.0
	for i in line.size() - 1:
		var length := line[i].distance_to(line[i + 1])
		var tangent := (line[i + 1] - line[i]) / maxf(length, 0.0001)
		while next <= walked + length:
			var at := line[i] + tangent * (next - walked)
			var arrow := _on_screen(ground, chevron(at, tangent, size))
			var across := arrow[0].distance_to(arrow[2])
			if across > widest:
				arrow = _on_screen(ground, chevron(at, tangent, size * widest / across))
				across = arrow[0].distance_to(arrow[2])
			var scale := maxf(1.0, across / CHEVRON_PX)
			lines.append([arrow, under, float(look.chevron_shadow_width) * scale])
			lines.append([arrow, over, float(look.chevron_width) * scale])
			next += ARROW_M
		walked += length
	return lines


## `world` (XZ points) through `ground` to the screen.
static func _on_screen(ground: Callable, world: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in world:
		out.append(ground.call(p))
	return out


## The band's two sides and its caps' arcs (_with_caps()) as one closed outline: the left side,
## the end's arc, the right side back, the start's arc, closed at the left side's start.
static func _outline(
	left: PackedVector2Array, right: PackedVector2Array, arcs: Array
) -> PackedVector2Array:
	var outline := left.duplicate()
	outline.append_array(arcs[0])
	var back := right.duplicate()
	back.reverse()
	outline.append_array(back)
	outline.append_array(arcs[1])
	outline.append(left[0])
	return outline


## The band's arrays with a round cap at each end (ribbon()'s caps): per end, a ring of
## CAP_SEGMENTS - 1 arc points for every offset of `row` off the centre line, from that offset's
## point on one side of the end's row round to the other, strips between the rings and a fan to
## the centre (the row's centre point, or a new one at the tip when the row has none). Every
## ring takes its row point's colour, so a fill_profile's coverage runs round the end too.
## Returns the new "points", "colors" and "indices" and "arcs" (each end's outer arc, the end's
## then the start's). Pure but for `ground`.
static func _with_caps(
	ground: Callable,
	line: PackedVector2Array,
	radius: float,
	row: Array,
	band_points: PackedVector2Array,
	band_colors: PackedColorArray,
	band_indices: PackedInt32Array
) -> Dictionary:
	var points := band_points.duplicate()
	var colors := band_colors.duplicate()
	var indices := band_indices.duplicate()
	var n := line.size()
	var width := row.size()
	var rings_n := 0
	var middle := -1
	for k in width:
		if float(row[k][0]) > 0.0:
			rings_n += 1
		elif float(row[k][0]) == 0.0:
			middle = k
	# The end's row runs left to right round its cap; the start's, seen from outside, right to
	# left.
	var ends := [
		[line[n - 1], line[n - 1] - line[n - 2], width * (n - 1), false],
		[line[0], line[0] - line[1], 0, true],
	]
	var arcs: Array = []
	for end: Array in ends:
		var tip: Vector2 = end[0]
		var forward: Vector2 = (end[1] as Vector2).normalized()
		var base: int = end[2]
		var flip: bool = end[3]
		var centre := base + middle
		if middle < 0:
			centre = points.size()
			points.append(ground.call(tip))
			colors.append(colors[base + rings_n - 1])
		var rings: Array[PackedInt32Array] = []
		for k in rings_n:
			var from := base + (width - 1 - k if flip else k)
			var ring := PackedInt32Array([from])
			var offset: float = row[k][0]
			var arc := _cap_arc(ground, tip, forward, radius if offset >= 1.0 else radius * offset)
			if k == 0:
				arcs.append(arc)
			for p in arc:
				ring.append(points.size())
				points.append(p)
				colors.append(colors[from])
			ring.append(base + (k if flip else width - 1 - k))
			rings.append(ring)
		for k in rings_n - 1:
			var outer := rings[k]
			var inner := rings[k + 1]
			for j in outer.size() - 1:
				indices.append_array(
					[outer[j], outer[j + 1], inner[j], outer[j + 1], inner[j + 1], inner[j]]
				)
		var last := rings[rings_n - 1]
		for j in last.size() - 1:
			indices.append_array([centre, last[j], last[j + 1]])
	return {"points": points, "colors": colors, "indices": indices, "arcs": arcs}


## The half circle round a ribbon's end at world XZ `centre`, bulging toward `forward` (a unit
## vector out of the ribbon), from the band's side on the left of `forward` to the right, through
## `ground` to the screen; the two side points themselves left out.
static func _cap_arc(
	ground: Callable, centre: Vector2, forward: Vector2, radius: float
) -> PackedVector2Array:
	var side := Vector2(-forward.y, forward.x)
	var arc := PackedVector2Array()
	for k in range(1, CAP_SEGMENTS):
		var angle := PI * float(k) / CAP_SEGMENTS
		arc.append(ground.call(centre + (side * cos(angle) + forward * sin(angle)) * radius))
	return arc
