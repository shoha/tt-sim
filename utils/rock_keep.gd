class_name RockKeep
extends RefCounted

## Rocks survive terrain changes (P3-7, the user's decision of 2026-09-27). While a sculpt
## stroke runs, the per-frame snap tilts rocks with the moving ground; the regeneration at
## the stroke's end used to remove every rock the new ground's rules no longer allow there
## (slope, cliff, scree, footing, relations). Tilted rocks breaking up the edge of a height
## jump read well, so rocks are no longer removed by a terrain change: every rock-role
## instance (ScatterGround.ROLE_ROCK: boulders, rocks, stones; not logs, which are deadwood
## and would bridge a drop) drawn when the stroke ends that the regeneration would remove
## becomes a placed prop in the same history entry. Nothing is added: an instance the new
## ground newly allows follows the normal rules, and only survivors are kept.
##
## Why props. Generation is a pure function of the document, so a kept rock has to be stored
## somewhere, and the props rows (AuthoredProps, props.json) already save, load, undo, redo
## and reach peers with the map. A kept rock is then just a placed rock.
##
## Which instances. removed_keys() generates the rock species of the cells in question
## twice, on the heights at the stroke's start and at its end, and returns the rows the first
## has and the second lacks: exactly the rocks the stroke's regeneration removes, whatever the
## rule. Only rows drawn at the stroke's end are converted, so a rock that was never there is
## never kept. It runs on a worker (about 170 ms for nine cells of alpine meadow, headless;
## the conversion on the main thread about 12 ms), and AuthoringEditor requests the stroke's
## regeneration only when it lands, so no rock shrinks in the meantime.
##
## How they stand (kept_row). As during the stroke: on the new ground normal, keeping yaw and
## lean, but never tilted more than MAX_TILT_RAD off vertical (capped_rotation), so no rock
## sticks straight out of a sheer face; bedded with the footing rule on its own tilted base
## (GroundSnap.bed_under over its footprint), so none floats and none is buried in a face.
##
## Duplicates (blockers). A later regeneration must not grow a generated instance inside a
## kept rock (a second stroke that brings the ground back would otherwise recreate the
## boulder beside its kept copy). blockers() lists every rock-role prop as (x, z, footprint
## radius), and ScatterGenerator skips rock, tree and shrub candidates inside one. A
## hand-placed rock blocks the same way: nothing generated grows inside a placed boulder.

## The steepest a kept (or snapped) rock stands, radians off vertical: 55 degrees. Tier
## faces read about 63 to 66 degrees; rocks leaning back 10 degrees from them sit on the face
## instead of pointing out of it, and a hill flank (under 45) keeps its full tilt. Judged by
## eye at the game camera (P3-7 rocks-survive renders).
const MAX_TILT_RAD := 0.9599310885968813
## A prop's footprint: this share of its widest dimension (also what props are picked by,
## PropRows.pick_radius).
const FOOTPRINT_FRACTION := 0.45
## Footprint when the asset's size is unknown.
const DEFAULT_FOOTPRINT_M := 0.5


## True for a species rule whose instances survive terrain changes (rock kind).
static func is_rock(rule: Dictionary) -> bool:
	return ScatterGround.role_of(rule) == ScatterGround.ROLE_ROCK


## Palette asset id -> its species rule, for every rock species of `biome_ids`.
static func rock_assets(biome_ids: PackedStringArray, root: String) -> Dictionary:
	var out := {}
	for biome_id in biome_ids:
		for rule in PaletteLibrary.species(biome_id, root):
			if is_rock(rule):
				for asset_id in rule.get("assets", []):
					out[String(asset_id)] = rule
	return out


## The species rule that places palette asset `asset_id` (its biome is the id's first path
## segment), or {}.
static func rule_for_asset(asset_id: String, root: String) -> Dictionary:
	for rule in PaletteLibrary.species(asset_id.get_slice("/", 0), root):
		if asset_id in rule.get("assets", []):
			return rule
	return {}


## Footprint radius (map metres at scale 1) of palette asset `asset_id`: FOOTPRINT_FRACTION
## of its widest horizontal dimension.
static func footprint_radius(asset_id: String, root: String) -> float:
	var size: Variant = PaletteLibrary.asset(asset_id, root).get("dimensions_m")
	var widest := 0.0
	if size is Vector3:
		widest = maxf(size.x, size.z)
	elif size is Array and (size as Array).size() >= 3:
		widest = maxf(float(size[0]), float(size[2]))
	return widest * FOOTPRINT_FRACTION if widest > 0.0 else DEFAULT_FOOTPRINT_M


## `up` tilted back toward +Y so it stands at most `max_tilt` radians off vertical.
static func capped_up(up: Vector3, max_tilt: float) -> Vector3:
	var n := up.normalized()
	var angle := n.angle_to(Vector3.UP)
	if angle <= max_tilt:
		return n
	var axis := Vector3.UP.cross(n)
	if axis.length_squared() < 1e-12:
		# Upside down: any horizontal axis.
		axis = Vector3.RIGHT
	return Vector3.UP.rotated(axis.normalized(), max_tilt)


## `rotation` turned by the arc that brings its up axis within `max_tilt` of vertical
## (capped_up), keeping its yaw and lean about that axis; unchanged when already within.
static func capped_rotation(rotation: Quaternion, max_tilt: float) -> Quaternion:
	if rotation.length_squared() <= 0.0:
		return rotation
	var q := rotation.normalized()
	var up := q * Vector3.UP
	var capped := capped_up(up, max_tilt)
	if up.angle_to(capped) <= 1e-6:
		return rotation
	return (Quaternion(up.normalized(), capped) * q).normalized()


## The prop row a kept rock becomes: `row` (the instance as drawn at the stroke's end, on the
## new ground) with its rotation capped at `max_tilt` (when `tilt`, a normal-aligned species)
## and its Y bedded on `heights` so its tilted base floats nowhere under a footprint of
## `radius` (its species' GroundSnap.footing_radius, scaled by the row's scale): the footing
## rule on the rock's own base plane (GroundSnap.bed_under). The lowest ground under the
## footprint would bury a small rock lying on a face.
static func kept_row(
	row: PackedFloat32Array,
	heights: PackedFloat32Array,
	grid: Dictionary,
	radius: float,
	tilt: bool,
	max_tilt: float = MAX_TILT_RAD
) -> PackedFloat32Array:
	var out := row.duplicate()
	var p := Vector2(row[0], row[2])
	var up := Vector3.UP
	if tilt:
		var q := capped_rotation(Quaternion(row[3], row[4], row[5], row[6]), max_tilt)
		out[3] = q.x
		out[4] = q.y
		out[5] = q.z
		out[6] = q.w
		up = q.normalized() * Vector3.UP
	out[1] = GroundSnap.bed_under(heights, grid, p, radius * absf(row[7]), up)
	return out


## asset id -> {row key: true} of the rock instances a regeneration of `cells` would remove
## when the document's heights go from `before` to `after` (two documents that differ only
## in their heights): the rock species of every biome in `species_by_biome` (biome id ->
## Array[Dictionary], PaletteLibrary.species) generated on both, keys present before and
## absent after. `built` and `cliff` name the palette surfaces with those roles
## (ScatterGenerator.document_fields).
static func removed_keys(
	before: MapDocument,
	after: MapDocument,
	species_by_biome: Dictionary,
	cells: Array[Vector2i],
	built: PackedStringArray,
	cliff: PackedStringArray
) -> Dictionary:
	var out := {}
	if cells.is_empty():
		return out
	for biome_id in species_by_biome:
		var species: Array[Dictionary] = []
		species.assign(species_by_biome[biome_id])
		var cells_by_species: Array = []
		var rocks := false
		for rule in species:
			var list: Array[Vector2i] = []
			if is_rock(rule):
				list = cells.duplicate()
				rocks = true
			cells_by_species.append(list)
		if not rocks:
			continue
		var plan := ScatterPlan.build(biome_id, species, after.map_seed)
		var depth := 0.0
		var reach := ScatterGenerator.species_reach(plan)
		for s in species.size():
			if is_rock(species[s]):
				depth = maxf(depth, reach[s])
		var step := after.sample_step()
		var window := _cells_rect(cells).grow(depth + 2.0 * maxf(step.x, step.y))
		var was := _generate(before, biome_id, species, cells_by_species, window, built, cliff)
		var now := _generate(after, biome_id, species, cells_by_species, window, built, cliff)
		for asset_id in was:
			var gone := _keys_of(was[asset_id])
			if now.has(asset_id):
				for key in _keys_of(now[asset_id]):
					gone.erase(key)
			if gone.is_empty():
				continue
			var joined: Dictionary = out.get(asset_id, {})
			joined.merge(gone)
			out[asset_id] = joined
	return out


## A copy of what generation reads of `doc`, with `heights` (copied too) in place of its
## own, for removed_keys() on a worker thread: packed arrays are shared by reference in
## GDScript, so the brush must not be able to write into what the worker reads. `dressing`
## is the wet dressing (MapDocument.water_dressing) that goes with those heights; null keeps
## the document's.
static func snapshot(
	doc: MapDocument, heights: PackedFloat32Array, dressing: Variant = null
) -> MapDocument:
	var copy := MapDocument.new()
	copy.map_seed = doc.map_seed
	copy.size_cells = doc.size_cells
	copy.cell_size_m = doc.cell_size_m
	copy.sample_spacing_m = doc.sample_spacing_m
	copy.heights = heights.duplicate()
	copy.biome_ids = doc.biome_ids.duplicate()
	copy.biome_slots = doc.biome_slots.duplicate()
	copy.biome_density = doc.biome_density.duplicate()
	copy.surface_ids = doc.surface_ids.duplicate()
	copy.surface_weights = doc.surface_weights.duplicate()
	var wet: PackedByteArray = dressing if dressing is PackedByteArray else doc.water_dressing
	copy.water_dressing = wet.duplicate()
	return copy


## Every rock-role prop of `props_by_asset` (asset id -> flat rows) as a flat (x, z, radius)
## triple: its footprint (footprint_radius times its scale), which generated rocks, trees and
## shrubs do not grow inside (ScatterGenerator). `root` is the palette root.
@warning_ignore("integer_division")
static func blockers(props_by_asset: Dictionary, root: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for asset_id in props_by_asset:
		var rule := rule_for_asset(String(asset_id), root)
		if rule.is_empty() or not is_rock(rule):
			continue
		var radius := footprint_radius(String(asset_id), root)
		var rows: PackedFloat32Array = props_by_asset[asset_id]
		for r in rows.size() / MapDocument.ROW_STRIDE:
			var b := r * MapDocument.ROW_STRIDE
			out.append_array([rows[b], rows[b + 2], radius * absf(rows[b + 7])])
	return out


## blockers() of the props node `source` (AuthoredScatter.blocker_source), or none.
static func blockers_of(source: AuthoredScatter) -> PackedFloat32Array:
	if not is_instance_valid(source):
		return PackedFloat32Array()
	return blockers(source.rows_by_asset(), source.palette_root)


## A ScatterRegen job's work (biome id -> entry) with each entry given the blockers that
## reach into its window ("blockers", read by ScatterRegen.run). Returns `work`.
static func with_blockers(work: Dictionary, blockers_list: PackedFloat32Array) -> Dictionary:
	if blockers_list.is_empty():
		return work
	for biome_id in work:
		var entry: Dictionary = work[biome_id]
		entry["blockers"] = blockers_in(blockers_list, entry.window)
	return work


## `blockers_list` (blockers()) when ScatterPlan species entry `entry` is one a kept rock
## blocks (a rock, or a species with a footing: trees, shrubs, logs), else none. Ground
## cover may grow around and under a rock as before.
static func blockers_for(
	blockers_list: PackedFloat32Array, entry: Dictionary
) -> PackedFloat32Array:
	if entry.get("ground_role", -1) == ScatterGround.ROLE_ROCK:
		return blockers_list
	if float(entry.get("footing_m", 0.0)) > 0.0:
		return blockers_list
	return PackedFloat32Array()


## True when map XZ `p` lies inside one of `blockers`' footprints (blockers()).
static func blocked(blockers_list: PackedFloat32Array, p: Vector2) -> bool:
	for b in range(0, blockers_list.size() - 2, 3):
		var r := blockers_list[b + 2]
		if p.distance_squared_to(Vector2(blockers_list[b], blockers_list[b + 1])) < r * r:
			return true
	return false


## The blockers (blockers()) whose footprint reaches into `rect` (map XZ).
static func blockers_in(blockers_list: PackedFloat32Array, rect: Rect2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for b in range(0, blockers_list.size() - 2, 3):
		var r := blockers_list[b + 2]
		if rect.grow(r).has_point(Vector2(blockers_list[b], blockers_list[b + 1])):
			out.append_array([blockers_list[b], blockers_list[b + 1], r])
	return out


## Splits one asset's drawn rows into those whose key is in `gone` ("kept") and the rest
## ("rest"); "start" are the kept ones as `start_rows` (the rows when the stroke began, same
## identity) had them, or as drawn when the stroke never snapped them.
static func split_kept(
	rows: PackedFloat32Array, start_rows: PackedFloat32Array, gone: Dictionary
) -> Dictionary:
	var keys := ScatterRows.row_keys(rows.to_byte_array().to_int32_array())
	var start_keys := ScatterRows.row_keys(start_rows.to_byte_array().to_int32_array())
	var kept := PackedFloat32Array()
	var rest := PackedFloat32Array()
	var start := PackedFloat32Array()
	for r in keys.size():
		var row := PropRows.row_at(rows, r)
		if not gone.has(keys[r]):
			rest.append_array(row)
			continue
		kept.append_array(row)
		var s := start_keys.find(keys[r])
		start.append_array(PropRows.row_at(start_rows, s) if s >= 0 else row)
	return {"kept": kept, "rest": rest, "start": start}


## A scatter cell's rows (asset id -> rows) with the rocks of `kept` (asset id -> rows)
## removed (`redo`: they are props again) or put back (undo), matched by row identity.
static func swap_kept(cell_rows: Dictionary, kept: Dictionary, redo: bool) -> Dictionary:
	var out := cell_rows.duplicate()
	for asset_id in kept:
		var kept_rows: PackedFloat32Array = kept[asset_id]
		var gone := _keys_of(kept_rows)
		# Without them first, so an undo never doubles a rock the scatter already has.
		var rest: PackedFloat32Array = (
			split_kept(out.get(asset_id, PackedFloat32Array()), PackedFloat32Array(), gone).rest
		)
		if not redo:
			rest.append_array(kept_rows)
		if rest.is_empty():
			out.erase(asset_id)
		else:
			out[asset_id] = rest
	return out


static func _generate(
	doc: MapDocument,
	biome_id: String,
	species: Array[Dictionary],
	cells_by_species: Array,
	window: Rect2,
	built: PackedStringArray,
	cliff: PackedStringArray
) -> Dictionary:
	var fields := ScatterGenerator.document_fields(doc, biome_id, window, built, cliff)
	return ScatterGenerator.generate_species_cells(
		biome_id,
		species,
		fields.density_at,
		fields.height_at,
		fields.normal_at,
		doc.map_seed,
		cells_by_species,
		fields.bounds,
		fields.species_density_at
	)


static func _keys_of(rows: PackedFloat32Array) -> Dictionary:
	var out := {}
	for key in ScatterRows.row_keys(rows.to_byte_array().to_int32_array()):
		out[key] = true
	return out


static func _cells_rect(cells: Array[Vector2i]) -> Rect2:
	var size := ScatterChunker.CHUNK_SIZE_WORLD_UNITS
	var rect := Rect2(Vector2(cells[0]) * size, Vector2(size, size))
	for cell in cells:
		rect = rect.merge(Rect2(Vector2(cell) * size, Vector2(size, size)))
	return rect
