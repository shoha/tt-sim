class_name LineRibbon
extends RefCounted

## The ribbon every line tool previews its line with (card F5e: Water's River and Fire's Line,
## and each one's erase): one look in two hues, so the river and the fire line read as one
## line tool (card F5h; user, 2026-10-18: "fire should just be an orange-coded version of the
## visuals for water and vice versa"). A band `radius` either side of the line, filled from the
## line's start (fainter) to its end, round caps at both ends, one closed edge over an ink
## outline on a soft glow (the brush ring's own stroke, BrushCursor.ring_strokes), and
## chevrons every ARROW_M pointing the way the line runs (a river's, the way its water will
## flow). It is drawn on BrushCursor's overlay with its fill on the cursor's glow layer
## (BrushCursor.glow_item(), premultiplied), where a fill lit above gain 1 adds light as well as
## covering (lit_fill()). It takes the scene's light (scene_light()): NIGHT_LIGHT of its colour
## under a sun well below the horizon, so at night it sits in the dark scene instead of glowing
## over it, and its full colour from the horizon up (a dusk sun 2.5 degrees up weighs about
## nothing while the scene is still bright, card F5d); an erase keeps its full colour, as the
## erase ring does (card F5h).
##
## What a tool changes is its style, as data: STYLE's keys, of which a tool passes only those it
## changes. A lay passes only its hue (TINT_KEYS: WaterBrush.RIBBON_HUE, FireBrush.LAY_HUE) over
## one of FILLS, the same for every tool (lay_style()); an erase passes ERASE_STYLE:
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
##   cap_start, cap_end    which ends are round when caps is on (a line drawn as stretches in
##                         two tints, Start a fire's Path, rounds only its own two ends, so
##                         the stretches join without an edge across the band)
##   quiet_spans           arc spans (metres from the line's start, x to y) drawn quieter, in
##                         quiet_profile instead of fill_profile (Start a fire's Path where only
##                         the ground burns); the band narrows into a span and widens out of it
##                         over TAPER_RADII half-widths along the arc (quiet_at()), so the change
##                         reads as a soft narrowing inside one edge, never a cut across the band
##   quiet_profile         the quiet spans' fill_profile (QUIET_PROFILE), as many steps as
##                         fill_profile's so each step's offset eases from one to the other
##   night_light           the share of its colour the ribbon keeps under no sun (1: all)
## An erase ribbon is the same shape at the same weights with the erase salmon
## (BrushCursor.CLEAR_TINT, every brush's erase) on its edge, glow and chevrons, and no wash
## inside (ERASE_STYLE, one for every tool), so what it erases shows through untouched. Every
## colour is a theme role or the erase tint; the widths and the ink are the ring's
## (BrushCursor.LINE_WIDTH and the rest), and only the fills' alphas are set here.

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
## A quieter stretch's coverage across the band (Start a fire's Path where only the ground
## burns, card F6b): the rails narrowed to the band's outer edge at their full coverage and
## light, every line (edge, ink, glow, chevrons) the lay's, so the line still reads whole, its
## hue and its way plain, with less of it lit. Narrower, not fainter: at lower coverage the hue
## mixed with the ground under it, khaki over grass and the dark wood (F5f's olive seam). As
## many steps as FILLS.rails' profile, so the one eases into the other.
const QUIET_PROFILE := [[1.0, 1.0], [0.86, 0.78], [0.78, 0.03], [0.0, 0.0]]
## How far along the arc (half-widths) the band takes to narrow into a quiet span and widen out
## of it, and the points the ease is drawn with: switched from one point to the next, the rail
## stepped by a quarter of the half-width (a square notch, card F6c).
const TAPER_RADII := 1.0
const TAPER_STEPS := 4
## Every line tool's look, before its own keys (the class header names them). Every line is the
## brush ring's stroke (BrushCursor.ring_strokes): the edge and the chevrons LINE_WIDTH over the
## ring's ink, the edge on the ring's glow, lay and erase alike, so the ring and the line it
## draws read as one and an erase is as heavy as its lay (card F5h; the edge's ink was 0.55 at
## 4.5 px and the chevrons' 0.6, the erase's 0.85 at 5.5). Its fill keys are FILLS.even's.
const STYLE := {
	"tint": ThemeColors.CHALK,
	"alpha_up": 0.12,
	"alpha_down": 0.34,
	"fill_profile": [],
	"fill_gain": 1.0,
	"edge": null,
	"edge_alpha": 1.0,
	"edge_width": BrushCursor.LINE_WIDTH,
	"shadow": ThemeColors.INK,
	"shadow_alpha": BrushCursor.INK_ALPHA,
	"shadow_width": BrushCursor.INK_WIDTH,
	"glow": null,
	"glow_alpha": BrushCursor.GLOW_ALPHA,
	"glow_width": BrushCursor.GLOW_WIDTH,
	"chevrons": true,
	"chevron": ThemeColors.CHALK,
	"chevron_alpha": 0.95,
	"chevron_width": BrushCursor.LINE_WIDTH,
	"chevron_shadow_alpha": BrushCursor.INK_ALPHA,
	"chevron_shadow_width": BrushCursor.INK_WIDTH,
	"caps": true,
	"cap_start": true,
	"cap_end": true,
	"quiet_spans": [],
	"quiet_profile": QUIET_PROFILE,
	"night_light": NIGHT_LIGHT,
}
## The keys a tool's lay sets: its hue. The band and edge in `tint`, the glow under the edge in
## `glow` (the tool's ring colour), each one of the theme's paired ramps, so two tools differ in
## hue alone (lake and light lake, persimmon and ember).
const TINT_KEYS: Array[String] = ["tint", "glow"]
## The fills every tool's lay takes, one for all (card F5h): its coverage across and along the
## band and its light.
##   rails  a glowing tube (card F5d's variant C, the user's pick for the fire line, 2026-10-18):
##          the coverage high at the two edges and falling steeply to nearly clear along the
##          centre line, lit by fill_gain on the glow layer, so the hue stands where it is
##          solid and the ground and its plants show unmixed down the middle. The rails hold
##          their weight in to 0.62 radii, then fall to clear within 0.08 radii, so the
##          half-covered band where orange over green turns olive is a thin seam (a fall from
##          0.78 read grey-teal over the pine's dark ground, F5d; F5e's fall to 0.12 at 0.5 radii
##          left an olive-ochre band a quarter of the band wide each side, F5f).
##   even   the river's even translucent band, faint upstream and stronger down, a plain blend
##          (persimmon at that coverage over green mixed to olive, card F5).
const FILLS := {
	"rails":
	{
		"alpha_up": 0.8,
		"alpha_down": 0.9,
		"fill_gain": 1.7,
		"fill_profile": [[1.0, 1.0], [0.62, 0.78], [0.54, 0.03], [0.0, 0.0]],
	},
	"even":
	{
		"alpha_up": 0.12,
		"alpha_down": 0.34,
		"fill_gain": 1.0,
		"fill_profile": [],
	},
}
## The fill a tool's lay takes unless told otherwise (option R; the job shows E beside it).
const FILL := "rails"
## A lay quiet along its whole length, over its keys (QUIET_PROFILE across the band).
const QUIET_STYLE := {"fill_profile": QUIET_PROFILE}
## An erase's keys over STYLE, for every tool (the river's erase and the fire's put-out alike):
## the erase salmon on the edge, its glow and the chevrons, every weight and the ink the lay's,
## and no wash inside, so what goes shows through untouched and the salmon lines alone say
## "erase". Any wash shifted what it lay on: at about half coverage (F5e) it hid the river as a
## flat dusty rose and greyed the flames to mud, and even at 0.08 to 0.14 the salmon, the
## water's complement, pulled the river's blue over red from about 40 to about 20, and a light
## lake cooled the flames (F5f, F5g). Its salmon keeps its full colour at night, as the erase
## ring's does: dimmed with the scene it fell to about 2:1 over the river at night (card F5h).
const ERASE_STYLE := {
	"tint": BrushCursor.CLEAR_TINT,
	"alpha_up": 0.0,
	"alpha_down": 0.0,
	"chevron": BrushCursor.CLEAR_TINT,
	"night_light": 1.0,
}


## A lay's style: `hue` (TINT_KEYS) over the fill named `fill` (FILLS). Pure.
static func lay_style(hue: Dictionary, fill: String = FILL) -> Dictionary:
	return (FILLS.get(fill, FILLS[FILL]) as Dictionary).merged(hue, true)


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
	if line.size() < 2:
		return {}
	var look := STYLE.merged(style, true)
	var tint: Color = look.tint
	var gain := float(look.fill_gain)
	var band := rows_along(line, radius, look)
	line = band.line
	var rows: Array = band.rows
	var n := line.size()
	var width: int = (rows[0] as Array).size()
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
		for step: Array in rows[i]:
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
	if look.caps and (look.cap_start or look.cap_end):
		var ends := [bool(look.cap_end), bool(look.cap_start)]
		var end_rows := [rows[n - 1], rows[0]]
		var capped := _with_caps(ground, line, radius, end_rows, points, colors, indices, ends)
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


## The band's line and its row across at each point (fill_row()), for `line` at half-width
## `radius` in `look` (STYLE merged): with no quiet_spans the line as given and fill_profile's
## row at every point; with them the line with a point at each step of every taper
## (TAPER_STEPS over TAPER_RADII * radius) and each point's row eased from fill_profile's to
## quiet_profile's by quiet_at(), so the rails narrow along the arc. A quiet_profile of another
## step count than fill_profile's cannot ease: the spans are left out. Pure.
static func rows_along(line: PackedVector2Array, radius: float, look: Dictionary) -> Dictionary:
	var full := fill_row(look.get("fill_profile", []))
	var spans := PackedVector2Array(look.get("quiet_spans", []))
	var quiet := fill_row(look.get("quiet_profile", QUIET_PROFILE))
	var rows: Array = []
	if spans.is_empty() or quiet.size() != full.size():
		for _p in line:
			rows.append(full)
		return {"line": line, "rows": rows}
	var total := StrokePath.line_length(line)
	var taper := maxf(TAPER_RADII * radius, 0.01)
	var stopped := _with_stops(line, _taper_stops(spans, total, taper))
	var walked := 0.0
	for i in stopped.size():
		if i > 0:
			walked += stopped[i - 1].distance_to(stopped[i])
		var w := quiet_at(walked, spans, total, taper)
		var row: Array = []
		for k in full.size():
			var a: Array = full[k]
			var b: Array = quiet[k]
			row.append([lerpf(a[0], b[0], w), lerpf(a[1], b[1], w)])
		rows.append(row)
	return {"line": stopped, "rows": rows}


## How quiet a line `total` metres long is `at` metres along it, 0 (fill_profile) to 1
## (quiet_profile), with quiet arc spans `spans`: 1 inside a span, easing in from 0 at a span's
## end that meets a full stretch over its first `taper` metres (smoothstep), so the band narrows
## inside the quiet span and the full stretch keeps its whole rails; an end at the line's own
## start or end eases nothing. Pure.
static func quiet_at(at: float, spans: PackedVector2Array, total: float, taper: float) -> float:
	var most := 0.0
	for span in spans:
		if at < span.x or at > span.y:
			continue
		var w := 1.0
		if span.x > 0.001:
			w = minf(w, smoothstep(0.0, taper, at - span.x))
		if span.y < total - 0.001:
			w = minf(w, smoothstep(0.0, taper, span.y - at))
		most = maxf(most, w)
	return most


## The arcs a quiet span's tapers are drawn at (rows_along()): TAPER_STEPS + 1 evenly over each
## eased end's first `taper` metres into its span, within the span and the line. Pure.
static func _taper_stops(
	spans: PackedVector2Array, total: float, taper: float
) -> PackedFloat32Array:
	var stops := PackedFloat32Array()
	for span in spans:
		var reach := minf(taper, (span.y - span.x) * 0.5)
		for k in TAPER_STEPS + 1:
			var into := reach * float(k) / TAPER_STEPS
			if span.x > 0.001:
				stops.append(span.x + into)
			if span.y < total - 0.001:
				stops.append(span.y - into)
	var inside := PackedFloat32Array()
	for at in stops:
		if at > 0.0 and at < total:
			inside.append(at)
	inside.sort()
	return inside


## `line` with a point inserted at each arc of `arcs` (sorted, metres from its start) on the
## segment it falls on, none within a centimetre of a point it has. Pure.
static func _with_stops(line: PackedVector2Array, arcs: PackedFloat32Array) -> PackedVector2Array:
	var out := PackedVector2Array([line[0]])
	var walked := 0.0
	var next := 0
	for i in range(1, line.size()):
		var length := line[i - 1].distance_to(line[i])
		while next < arcs.size() and arcs[next] < walked + length:
			var into := arcs[next] - walked
			if into > 0.01 and length - into > 0.01:
				var at := line[i - 1].lerp(line[i], into / length)
				if out[-1].distance_to(at) > 0.01:
					out.append(at)
			next += 1
		out.append(line[i])
		walked += length
	return out


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


## The band's two sides and its caps' arcs (_with_caps(): the end's, then the start's, empty
## where that end is cut) as one outline: the left side, the end's arc, the right side back,
## the start's arc, closed at the left side's start. With one end cut it is left open there:
## from the left side's start round the end to the right side's start, or from the right
## side's end round the start to the left side's end.
static func _outline(
	left: PackedVector2Array, right: PackedVector2Array, arcs: Array
) -> PackedVector2Array:
	var back := right.duplicate()
	back.reverse()
	var end_arc: PackedVector2Array = arcs[0]
	var start_arc: PackedVector2Array = arcs[1]
	if end_arc.is_empty():
		var open := back.duplicate()
		open.append_array(start_arc)
		open.append_array(left)
		return open
	var outline := left.duplicate()
	outline.append_array(end_arc)
	outline.append_array(back)
	if start_arc.is_empty():
		return outline
	outline.append_array(start_arc)
	outline.append(left[0])
	return outline


## The band's arrays with a round cap at each end (ribbon()'s caps): per end, a ring of
## CAP_SEGMENTS - 1 arc points for every offset of that end's row (`rows`: the end's, then the
## start's, one structure) off the centre line, from that offset's point on one side of the end's
## row round to the other, strips between the rings and a fan to the centre (the row's centre
## point, or a new one at the tip when the row has none). Every ring takes its row point's
## colour, so a fill_profile's coverage runs round the end too. Returns the new "points",
## "colors" and "indices" and "arcs" (each end's outer arc, the end's then the start's, empty
## for an end `rounded` leaves cut: [the end's, the start's]). Pure but for `ground`.
static func _with_caps(
	ground: Callable,
	line: PackedVector2Array,
	radius: float,
	rows: Array,
	band_points: PackedVector2Array,
	band_colors: PackedColorArray,
	band_indices: PackedInt32Array,
	rounded: Array = [true, true]
) -> Dictionary:
	var points := band_points.duplicate()
	var colors := band_colors.duplicate()
	var indices := band_indices.duplicate()
	var n := line.size()
	var first: Array = rows[0]
	var width := first.size()
	var rings_n := 0
	var middle := -1
	for k in width:
		if float(first[k][0]) > 0.0:
			rings_n += 1
		elif float(first[k][0]) == 0.0:
			middle = k
	# The end's row runs left to right round its cap; the start's, seen from outside, right to
	# left.
	var ends := [
		[line[n - 1], line[n - 1] - line[n - 2], width * (n - 1), false],
		[line[0], line[0] - line[1], 0, true],
	]
	var arcs: Array = [PackedVector2Array(), PackedVector2Array()]
	for which in ends.size():
		if not bool(rounded[which]):
			continue
		var end: Array = ends[which]
		var tip: Vector2 = end[0]
		var forward: Vector2 = (end[1] as Vector2).normalized()
		var base: int = end[2]
		var flip: bool = end[3]
		var row: Array = rows[which]
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
				arcs[which] = arc
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
