class_name DesignerSplit
extends RefCounted

## The painting behind the designer's A/B view (step S9): ONE map, two biomes. The proving ground
## is painted with the draft in biome slot 1 on one side of a line and the reference in slot 2 on
## the other, so the real scatter solver, the real ground (each biome's own surfaces, accents and
## look) and the real renderer draw both, from the same terrain, seed and camera. The line is the
## DIVIDER: the designer shows it as a vertical line on the screen (the game camera is fixed and
## orthographic, so a ground line perpendicular to the camera's right vector is vertical there),
## and `t` is a ground position along that right vector in map metres. Samples with a smaller `t`
## belong to the draft, the rest to the reference. Moving the divider repaints only the samples it
## crossed. Pure over a MapDocument: no nodes, no scene tree; the session turns the changed
## rectangle into a ground update and a scatter request (BiomeDesignerSession).

const DRAFT_SLOT := 1
const REFERENCE_SLOT := 2
const FAR := 1.0e9
## Grid of the share estimate (draft_share), per side.
const SHARE_GRID := 24


## The ground position of the world XZ point `xz` along `right` (a unit vector in map XZ).
static func position_along(xz: Vector2, right: Vector2) -> float:
	return xz.dot(right)


## The least and greatest `t` the map's corners have.
static func span(doc: MapDocument, right: Vector2) -> Vector2:
	var half := doc.extent_m() * 0.5
	var low := FAR
	var high := -FAR
	for corner: Vector2 in [
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(-half.x, half.y), half
	]:
		low = minf(low, corner.dot(right))
		high = maxf(high, corner.dot(right))
	return Vector2(low, high)


## Paints the samples the divider crossed in moving from `from_t` to `to_t` (NAN for `from_t`:
## the whole map from scratch) and returns the rectangle of samples whose slot changed (empty
## when none, or when the document has no biome masks). Slots are DRAFT_SLOT below the divider.
static func paint(doc: MapDocument, right: Vector2, from_t: float, to_t: float) -> Rect2i:
	if doc.biome_slots.size() != doc.sample_count():
		return Rect2i()
	if is_nan(from_t):
		var low := _band(doc, right, -FAR, to_t, DRAFT_SLOT)
		return MaskBrush.merge_rect(low, _band(doc, right, to_t, FAR, REFERENCE_SLOT))
	if to_t > from_t:
		return _band(doc, right, from_t, to_t, DRAFT_SLOT)
	return _band(doc, right, to_t, from_t, REFERENCE_SLOT)


## Paints the whole map with the draft (the A/B view is off); the changed rectangle.
static func clear(doc: MapDocument) -> Rect2i:
	if doc.biome_slots.size() != doc.sample_count():
		return Rect2i()
	var changed := false
	var slots := doc.biome_slots
	for i in slots.size():
		if slots[i] != DRAFT_SLOT:
			slots[i] = DRAFT_SLOT
			changed = true
	doc.biome_slots = slots
	return Rect2i(0, 0, doc.samples_x(), doc.samples_z()) if changed else Rect2i()


## The scatter cells (world rectangles of `cell_m` metres, aligned to multiples of it) of the map
## whose ground position range along `right` overlaps lo <= t < hi: the cells a divider move from
## one `t` to another can change, so only those are regenerated.
static func cells_crossed(
	doc: MapDocument, right: Vector2, lo: float, hi: float, cell_m: float
) -> Array[Rect2]:
	var half := doc.extent_m() * 0.5
	var out: Array[Rect2] = []
	for cz in range(floori(-half.y / cell_m), floori(half.y / cell_m) + 1):
		for cx in range(floori(-half.x / cell_m), floori(half.x / cell_m) + 1):
			var cell := Rect2(Vector2(cx, cz) * cell_m, Vector2(cell_m, cell_m))
			var inside := cell.intersection(Rect2(-half, half * 2.0))
			if not inside.has_area():
				continue
			var low := FAR
			var high := -FAR
			for corner: Vector2 in [
				inside.position,
				inside.position + Vector2(inside.size.x, 0.0),
				inside.position + Vector2(0.0, inside.size.y),
				inside.end
			]:
				low = minf(low, corner.dot(right))
				high = maxf(high, corner.dot(right))
			if high >= lo and low < hi:
				out.append(cell)
	return out


## The share (0..1) of the map the draft side covers when the divider is at `t`, estimated on a
## coarse grid (the budget meter scales the draft's instances by it).
static func draft_share(doc: MapDocument, right: Vector2, t: float) -> float:
	var half := doc.extent_m() * 0.5
	var inside := 0
	for gz in SHARE_GRID:
		for gx in SHARE_GRID:
			var xz := Vector2(
				(float(gx) + 0.5) / SHARE_GRID * 2.0 - 1.0, (float(gz) + 0.5) / SHARE_GRID * 2.0 - 1.0
			) * half
			if xz.dot(right) < t:
				inside += 1
	return float(inside) / float(SHARE_GRID * SHARE_GRID)


## Writes `slot` into the samples with lo <= t < hi; returns the rectangle of those that changed.
static func _band(doc: MapDocument, right: Vector2, lo: float, hi: float, slot: int) -> Rect2i:
	var width := doc.samples_x()
	var height := doc.samples_z()
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	var slots := doc.biome_slots
	var slope := step.x * right.x
	var low := Vector2i(width, height)
	var high := Vector2i(-1, -1)
	for z in height:
		var t0 := -half.x * right.x + (z * step.y - half.y) * right.y
		var first := 0
		var last := width - 1
		if absf(slope) < 1.0e-9:
			if t0 < lo or t0 >= hi:
				continue
		else:
			# t(x) = t0 + x * slope: the x range with lo <= t < hi.
			var a := (lo - t0) / slope
			var b := (hi - t0) / slope
			var x_low := minf(a, b)
			var x_high := maxf(a, b)
			first = maxi(0, int(ceilf(clampf(x_low, -1.0, float(width)))))
			last = mini(width - 1, int(ceilf(clampf(x_high, -1.0, float(width)))) - 1)
		var row := z * width
		for x in range(first, last + 1):
			var t := t0 + x * slope
			if t < lo or t >= hi:
				continue
			if slots[row + x] != slot:
				slots[row + x] = slot
				low = Vector2i(mini(low.x, x), mini(low.y, z))
				high = Vector2i(maxi(high.x, x), maxi(high.y, z))
	doc.biome_slots = slots
	if high.x < 0:
		return Rect2i()
	return Rect2i(low, high - low + Vector2i.ONE)
