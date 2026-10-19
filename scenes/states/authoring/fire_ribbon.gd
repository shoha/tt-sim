class_name FireRibbon
extends RefCounted

## The Fire tool's line ribbon (FireBrush.draw_cursor) built on the river's (WaterBrush.ribbon),
## with what a fire line's style adds to it, as data: the river's keys (RIBBON_STYLE) plus
##   band_spacing  metres between chevron bands laid across the band, front to front (0: none)
##   band_share    the share of that spacing each band fills, the rest left clear
##   band_slant    radii by which a band's two ends trail its middle (0: straight across), so
##                 each band is a chevron pointing the way the line was drawn
##   band_alpha    a band's coverage, lit by the style's fill_gain as the fill is
##   chevrons      false: no river chevrons (a banded style's bands point the way instead)
##   night_light   the share of its colour the ribbon keeps under no sun; with it the ribbon
##                 takes the scene's light (scene_light()), dimming as the published sun
##                 (FoliageLight.last_sun) sinks, so at night it sits in the dark scene instead
##                 of glowing over it; without it the ribbon keeps its colour whatever the light
## Orange at partial coverage over green mixes toward olive, so a line's style keeps its orange
## where it is solid (an edge, bands, an edge-weighted fill) and leaves the ground clear between
## (card F5d's lay variants, FireBrush.LAY_VARIANTS). Every colour comes from the style or the
## tint; nothing here names one.

## The published sun's height (FoliageLight.last_sun's y, the up component of the direction
## toward it) at and under which a ribbon that takes the scene's light is at its night_light:
## about 6 degrees below the horizon. It keeps its full colour from the horizon up. Not the
## sun's weight: a dusk sun 2.5 degrees up weighs about nothing (outdoor_sunset, card F5d's
## first round) while the scene is still bright, and the ribbon dimmed there turned brown.
const DARK_HEIGHT := -0.1


## What draw() draws for `line` (world XZ; `ground` maps a point to the screen on the ground)
## at half-width `radius` in `tint` and `style`: the river's ribbon (its chevrons unless
## style.chevrons is false) with the style's bands over its fill, every colour in the light
## the style takes under the published `sun` (FoliageLight.last_sun; scene_light()). {} for a
## line under two points. Pure but for `ground`.
static func build(
	ground: Callable,
	line: PackedVector2Array,
	radius: float,
	tint: Color,
	style: Dictionary,
	sun: Vector4
) -> Dictionary:
	var arrows := bool(style.get("chevrons", true))
	var shape := WaterBrush.ribbon(ground, line, radius, tint, 1.0, arrows, style)
	if shape.is_empty():
		return shape
	if float(style.get("band_spacing", 0.0)) > 0.0:
		shape = with_triangles(shape, bands(ground, line, radius, tint, style))
	if style.has("night_light"):
		shape = in_light(shape, scene_light(sun, float(style.night_light)))
	return shape


## Draws a build() shape on `canvas`, its fill on `fill_item` (the cursor's glow layer).
static func draw(canvas: Control, shape: Dictionary, fill_item: RID) -> void:
	WaterBrush.draw_shape(canvas, shape, fill_item)


## The light a ribbon takes under the published `sun` (FoliageLight.last_sun: xyz toward it):
## `least` with the sun DARK_HEIGHT or more under the horizon, rising smoothly to 1 as it comes
## up to the horizon. A map with no sun publishes FoliageLight.NO_SUN, straight up: full. Pure.
static func scene_light(sun: Vector4, least: float) -> float:
	return lerpf(least, 1.0, smoothstep(DARK_HEIGHT, 0.0, sun.y))


## The chevron bands across `line`'s band (style's band_* keys): "points", "colors" and
## "indices" for triangles, anchored at the line's start so they stay put as the line grows.
## Each band is six points, its back and front edge at the left side, the centre line and the
## right side, two quads; a band that would run past either end is left out. Pure but for
## `ground`.
static func bands(
	ground: Callable, line: PackedVector2Array, radius: float, tint: Color, style: Dictionary
) -> Dictionary:
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var spacing := float(style.get("band_spacing", 0.0))
	var total := StrokePath.line_length(line)
	if spacing <= 0.0 or line.size() < 2:
		return {"points": points, "colors": colors, "indices": indices}
	var depth := spacing * clampf(float(style.get("band_share", 0.5)), 0.05, 0.95)
	var slant := radius * float(style.get("band_slant", 0.0))
	var fill := tint
	fill.a = float(style.get("band_alpha", 1.0))
	if float(style.get("fill_gain", 0.0)) > 0.0:
		fill = WaterBrush.lit_fill(fill, float(style.fill_gain))
	var cumulative := _cumulative(line)
	var front := slant + depth + spacing * 0.25
	while front <= total:
		var base := points.size()
		for s in [front, front - depth]:
			var middle := _along(line, cumulative, s)
			var sides := _along(line, cumulative, s - slant)
			var centre: Vector2 = middle[0]
			var at: Vector2 = sides[0]
			var normal: Vector2 = sides[1]
			points.append(ground.call(at + normal * radius))
			points.append(ground.call(centre))
			points.append(ground.call(at - normal * radius))
		for _corner in 6:
			colors.append(fill)
		# Front row base..base + 2 (left, middle, right), back row base + 3..base + 5.
		for a in [base, base + 1]:
			indices.append_array([a + 3, a, a + 1, a + 3, a + 1, a + 4])
		front += spacing
	return {"points": points, "colors": colors, "indices": indices}


## `shape` with `extra`'s triangles ("points", "colors", "indices") drawn after its own fill.
## Pure.
static func with_triangles(shape: Dictionary, extra: Dictionary) -> Dictionary:
	var out := shape.duplicate()
	var points: PackedVector2Array = shape.points.duplicate()
	var colors: PackedColorArray = shape.colors.duplicate()
	var indices: PackedInt32Array = shape.indices.duplicate()
	var base := points.size()
	points.append_array(extra.points)
	colors.append_array(extra.colors)
	for i: int in extra.indices:
		indices.append(base + i)
	out.points = points
	out.colors = colors
	out.indices = indices
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


static func _dimmed(c: Color, light: float) -> Color:
	var out := c * light
	out.a = c.a
	return out


## The walked length at each of `line`'s points.
static func _cumulative(line: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0])
	for i in range(1, line.size()):
		out.append(out[i - 1] + line[i - 1].distance_to(line[i]))
	return out


## The point `s` metres along `line` and the unit normal to the left of its way there:
## [point, normal], clamped to the line's ends.
static func _along(line: PackedVector2Array, cumulative: PackedFloat32Array, s: float) -> Array:
	var i := 0
	while i < line.size() - 2 and cumulative[i + 1] < s:
		i += 1
	var length := maxf(cumulative[i + 1] - cumulative[i], 0.0001)
	var t := clampf((s - cumulative[i]) / length, 0.0, 1.0)
	var tangent := (line[i + 1] - line[i]) / length
	return [line[i].lerp(line[i + 1], t), Vector2(-tangent.y, tangent.x)]
