extends GutTest

## The native scatter generator (utils/scatter_native.gd and native/; card native-scatter)
## against GDScript's, bit for bit: the pattern noise on every noise setting the palettes use, and
## the rows and mass anchors of whole painted cells. Pending, with the reason, where the library
## is not built: CI's tests and a fresh clone run the GDScript path only, and the rest of the
## suite checks that path. The landform recipes' whole maps are compared in
## test_scatter_native_landforms_dry.gd and _wet.gd (scatter_native_landform_parity.gd).

const SIZE_FT := 200
const SEED := 1234
## How far past the cell the full-density paint reaches (metres).
const PAINT_MARGIN_M := 2.0
const NOISE_POINTS := 1500
const Parity := preload("res://tests/unit/scatter_native_landform_parity.gd")


func after_each() -> void:
	ScatterNative.force_gdscript = false


func _skip_without_library() -> bool:
	if ScatterNative.available():
		return false
	pending("the native library is not built (AGENTS.md Testing): GDScript path only")
	return true


func test_noise_equals_fastnoiselite_on_every_palette_setting() -> void:
	if _skip_without_library():
		return
	var points := PackedFloat64Array()
	for k in NOISE_POINTS:
		var h := ScatterGenerator._mix(k * 0x9E3779B1 + 11)
		var span := 10.0 if k % 3 == 0 else 400.0
		points.append((ScatterGenerator._unit(h, 1) - 0.5) * span)
		points.append((ScatterGenerator._unit(h, 2) - 0.5) * span)
	var settings := {}
	var checked := 0
	var off := 0
	for biome in PaletteLibrary.biomes():
		var biome_id := String(biome.id)
		var plan := ScatterPlan.build(biome_id, PaletteLibrary.species(biome_id), SEED)
		var fields: Array[Dictionary] = []
		fields.assign(plan.fields)
		for entry: Dictionary in plan.species:
			var noise := ScatterGenerator._noise(entry, fields)
			if noise == null:
				continue
			settings["%s / %d" % [noise.frequency, noise.fractal_octaves]] = true
			var native := ScatterNative.noise_2d(
				noise.seed, noise.frequency, noise.fractal_octaves, points
			)
			assert_eq(native.size(), NOISE_POINTS)
			for i in native.size():
				checked += 1
				if native[i] != noise.get_noise_2d(points[i * 2], points[i * 2 + 1]):
					off += 1
	gut.p("noise: %d values over settings %s, %d off" % [checked, settings.keys(), off])
	assert_gt(checked, 0)
	assert_eq(off, 0, "native FastNoiseLite equals Godot's bit for bit")


func test_painted_cell_rows_equal_gdscript_for_every_biome() -> void:
	if _skip_without_library():
		return
	for biome in PaletteLibrary.biomes():
		var biome_id := String(biome.id)
		var doc := _painted_doc(biome_id, Vector2i.ZERO)
		_assert_same_rows(doc, biome_id, _work(doc, biome_id, Vector2i.ZERO))


## Species `avoid_bare` on every rule (openings on entries of any kind, and on savanna grass the
## clump's openings plus its own) places the same rows natively.
func test_avoid_bare_rows_equal_gdscript() -> void:
	if _skip_without_library():
		return
	for biome_id in ["wetland_riparian_summer_s1", "savanna_summer_s1"]:
		var doc := _painted_doc(biome_id, Vector2i.ZERO)
		var work := _work(doc, biome_id, Vector2i.ZERO)
		var species: Array[Dictionary] = []
		for rule: Dictionary in work.species:
			species.append(rule.merged({"avoid_bare": 0.02}, true))
		work.species = species
		_assert_same_rows(doc, biome_id, work)


func test_regen_run_gives_the_same_result_native_and_forced_to_gdscript() -> void:
	if _skip_without_library():
		return
	var biome_id := "temperate_forest_summer_s1"
	var doc := _painted_doc(biome_id, Vector2i(1, -1))
	var work := {biome_id: _work(doc, biome_id, Vector2i(1, -1))}
	ScatterNative.reset_counts()
	var native := ScatterRegen.run(doc, work)
	ScatterNative.force_gdscript = true
	var gdscript := ScatterRegen.run(doc, work)
	assert_eq(ScatterNative.fallbacks(), {"native": 1, "forced": 1})
	assert_false((native.rows_by_cell as Dictionary).is_empty())
	assert_eq(native.rows_by_cell, gdscript.rows_by_cell)
	assert_eq(native.anchors, gdscript.anchors)


func test_force_switch_and_missing_library_send_jobs_to_gdscript() -> void:
	var biome_id := "grassland_meadow_summer_s1"
	var doc := _painted_doc(biome_id, Vector2i.ZERO)
	ScatterNative.reset_counts()
	ScatterNative.force_gdscript = true
	assert_false(ScatterNative.active())
	assert_null(ScatterNative.run_biome(doc, biome_id, _work(doc, biome_id, Vector2i.ZERO), {}))
	ScatterNative.force_gdscript = false
	var reason := "native" if ScatterNative.available() else "missing"
	var rows: Variant = ScatterNative.run_biome(doc, biome_id, _work(doc, biome_id, Vector2i.ZERO), {})
	assert_eq(rows == null, not ScatterNative.available())
	assert_eq(ScatterNative.fallbacks(), {"forced": 1, reason: 1})


## S12b: a loaded library must carry the terrain response (version() names "curves"). This FAILS,
## it does not pend, on a stale library: one built before S12b would load, ignore the curve keys
## and place rows GDScript would not (rebuild it: native/README.md).
func test_the_library_reports_the_curves_capability() -> void:
	if _skip_without_library():
		return
	assert_string_contains(ScatterNative.version(), ScatterNative.CAPABILITY_CURVES)
	var curved: Array[Dictionary] = PaletteLibrary.species("grassland_meadow_summer_s1")
	assert_eq(ScatterNative._refusal(Parity.curved_species(curved)), "", "curved jobs run natively")


## Terrain response on every rule (slope minimum, slope, height and wet curves) places the same
## rows natively as in GDScript, on steep terraces with a synthetic shore weight, and the curves
## visibly change the placement.
func test_terrain_response_rows_equal_gdscript_dry_and_wet() -> void:
	if _skip_without_library():
		return
	for biome_id in ["temperate_forest_summer_s1", "grassland_meadow_summer_s1"]:
		for landform in ["rolling", "terraces"]:
			for wet in [false, true]:
				var doc := _rolling_doc(biome_id, Vector2i.ZERO, landform)
				if wet:
					_dress_shore(doc)
				var plain := _work(doc, biome_id, Vector2i.ZERO)
				var work := _curved_work(doc, biome_id, Vector2i.ZERO)
				_assert_same_rows(doc, biome_id, work)
				var base := _native_rows(doc, biome_id, plain)
				var curved := _native_rows(doc, biome_id, work)
				var label := "%s %s wet %s: curves thin" % [biome_id, landform, wet]
				assert_lt(_row_count(curved), _row_count(base), label)


## Each kind of terrain response alone (so a missed field cannot hide behind another), on rolling
## ground with a shore weight that varies in both directions.
func test_each_terrain_response_alone_equals_gdscript() -> void:
	if _skip_without_library():
		return
	var biome_id := "temperate_forest_summer_s1"
	var kinds: Array[Dictionary] = [
		{"slope_min_deg": 4.0},
		{"response": {"slope": [[0, 1], [10, 0.5], [30, 0.0]]}},
		{"response": {"slope": [[0, 0.2], [40, 1.0]]}},
		{"response": {"height": [[-500, 1.0], [1, 1.0], [5, 0.1]]}},
		{"response": {"wet": [[0, 1.0], [0.5, 0.3]]}},
		{"response": {"wet": [[0, 0.0], [1, 1.0]]}},
	]
	var doc := _rolling_doc(biome_id, Vector2i.ZERO)
	_dress_shore(doc)
	for kind in kinds:
		var work := _work(doc, biome_id, Vector2i.ZERO)
		var species: Array[Dictionary] = []
		for rule: Dictionary in work.species:
			species.append(rule.merged(kind.duplicate(true), true))
		work.species = species
		_assert_same_rows(doc, biome_id, work)


## A cell generated alone equals the same cell inside a bigger job, with curved rules, natively
## (the curves are pointwise, so no job size moves a row).
func test_terrain_response_rows_do_not_depend_on_the_job_region() -> void:
	if _skip_without_library():
		return
	var biome_id := "temperate_forest_summer_s1"
	var doc := _rolling_doc(biome_id, Vector2i.ZERO)
	_dress_shore(doc)
	_paint(doc, biome_id, Rect2(Vector2(10.0, 0.0), Vector2(10.0, 10.0)).grow(PAINT_MARGIN_M))
	var alone := _curved_work(doc, biome_id, Vector2i.ZERO)
	var both := _curved_work(doc, biome_id, Vector2i.ZERO)
	var cells: Array = []
	for _s in (both.species as Array).size():
		cells.append([Vector2i.ZERO, Vector2i(1, 0)])
	both.cells_by_species = cells
	both.window = (alone.window as Rect2).merge(Rect2(Vector2(10.0, 0.0), Vector2(10.0, 10.0)))
	var single := _native_rows(doc, biome_id, alone)
	var wide := _native_rows(doc, biome_id, both)
	var stride := MapDocument.ROW_STRIDE
	var checked := 0
	for asset_id in single:
		var kept := PackedFloat32Array()
		var rows: PackedFloat32Array = wide.get(asset_id, PackedFloat32Array())
		for r in rows.size() / stride:
			if rows[r * stride] < 10.0:
				kept.append_array(rows.slice(r * stride, (r + 1) * stride))
		var expected: PackedFloat32Array = single[asset_id]
		assert_eq(kept.to_byte_array(), expected.to_byte_array(), asset_id)
		checked += (kept.size() / stride)
	assert_gt(checked, 20)


## The grids the library computes from pack()'s "source" (card native-cover) against grids_for's
## GDScript, byte for byte: steep landforms (curvature, steepness, face proximity), the map edge,
## and plain, built, cliff and ash surfaces painted in overlapping weights (painted fields and the
## path fringe).
func test_native_grids_equal_grids_for_on_steep_painted_ground() -> void:
	if _skip_without_library():
		return
	var biome_id := "grassland_meadow_summer_s1"
	var built := PackedStringArray(PaletteLibrary.surfaces_with_role("built"))
	var cliff := PackedStringArray(PaletteLibrary.surfaces_with_role("cliff"))
	var keys := [
		"density", "heights", "curvature", "steep", "near_face", "paint_total", "paint_built",
		"paint_rock", "paint_ash", "fringe"
	]
	var checked := 0
	var off: Array[String] = []
	for landform in ["gorge", "terraces"]:
		var doc := NewMap.create(SIZE_FT, biome_id, SEED, PaletteLibrary.DEFAULT_ROOT, landform)
		_paint_surfaces(doc, built, cliff)
		_paint(doc, biome_id, Rect2(-4.0, -4.0, 9.0, 7.0))
		for cell in [Vector2i(-3, -3), Vector2i(0, 0), Vector2i(-1, 0), Vector2i(2, 2)]:
			var window := Rect2(Vector2(cell) * 10.0, Vector2(10.0, 10.0)).grow(3.0)
			var expected := ScatterNative.grids_for(doc, biome_id, window, built, cliff)
			var actual := ScatterNative.native_grids(
				ScatterNative.source_for(doc, biome_id, window, built, cliff)
			)
			for key in keys:
				checked += 1
				var a: PackedFloat32Array = expected.get(key, PackedFloat32Array())
				var b: PackedFloat32Array = actual.get(key, PackedFloat32Array())
				if a.to_byte_array() != b.to_byte_array():
					off.append("%s %s %s (%d vs %d)" % [landform, cell, key, a.size(), b.size()])
		assert_true(doc.has_surface_entries(), "%s has painted surfaces" % landform)
		# And the rows over that ground, through pack's source path.
		_assert_same_rows(doc, biome_id, _work(doc, biome_id, Vector2i(0, -1)))
	gut.p("grids: %d compared, off %s" % [checked, off])
	assert_eq(checked, 2 * 4 * keys.size())
	assert_eq(off, [] as Array[String], "native grids equal grids_for byte for byte")


## Paints a plain, a built, a cliff and the ash surface over overlapping patches of `doc`, with
## weights varying by sample, so samples carry one to four entries of every kind.
@warning_ignore("integer_division")
func _paint_surfaces(doc: MapDocument, built: PackedStringArray, cliff: PackedStringArray) -> void:
	var names: Array[String] = []
	for surface in PaletteLibrary.surfaces():
		if not built.has(surface) and not cliff.has(surface) and surface != "ash":
			names.append(String(surface))
			break
	names.append_array([built[0], cliff[0], "ash"])
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	for k in names.size():
		var slot := doc.ensure_surface(names[k])
		var centre := Vector2i(columns / 2 + (k - 2) * 9, rows / 2 + (k % 2) * 7 - 3)
		for z in range(maxi(centre.y - 30, 0), mini(centre.y + 30, rows)):
			for x in range(maxi(centre.x - 26, 0), mini(centre.x + 26, columns)):
				var value := 40 + ((x * 7 + z * 13 + k * 31) % 200)
				doc.set_surface_weight(z * columns + x, slot, value)


## A fresh map of `biome_id` as the New map dialog makes it, with `cell` and PAINT_MARGIN_M
## around it painted to full density (the gen-native probe's cell).
func _painted_doc(
	biome_id: String, cell: Vector2i, landform: String = StartingLandform.FLAT
) -> MapDocument:
	var doc := NewMap.create(SIZE_FT, biome_id, SEED, PaletteLibrary.DEFAULT_ROOT, landform)
	_paint(doc, biome_id, Rect2(Vector2(cell) * 10.0, Vector2(10.0, 10.0)).grow(PAINT_MARGIN_M))
	return doc


## `_painted_doc` on the named landform, or, for "rolling", on flat ground raised into hills:
## slopes from 0 to about 35 degrees and heights within +-3.5 m, so the slope and height curves
## act on real values (the flat cell and the terraces' level tiers leave them at one value).
func _rolling_doc(biome_id: String, cell: Vector2i, landform: String = "rolling") -> MapDocument:
	if landform != "rolling":
		return _painted_doc(biome_id, cell, landform)
	var doc := _painted_doc(biome_id, cell)
	var heights := PackedFloat32Array()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			heights.append(3.0 * sin(p.x * 0.17) * cos(p.y * 0.13) + 0.15 * p.x)
	doc.heights = heights
	return doc


func _paint(doc: MapDocument, biome_id: String, rect: Rect2) -> void:
	var slot := doc.biome_ids.find(biome_id) + 1
	var first := Vector2i(doc.world_to_sample(rect.position).ceil())
	var last := Vector2i(doc.world_to_sample(rect.end).floor())
	var columns := doc.samples_x()
	for z in range(maxi(first.y, 0), mini(last.y, doc.samples_z() - 1) + 1):
		for x in range(maxi(first.x, 0), mini(last.x, columns - 1) + 1):
			doc.biome_slots[z * columns + x] = slot
			doc.biome_density[z * columns + x] = 255


## ScatterRegen's work entry for every species of `biome_id` in `cell`.
func _work(doc: MapDocument, biome_id: String, cell: Vector2i) -> Dictionary:
	var species := PaletteLibrary.species(biome_id)
	var reach := ScatterGenerator.species_reach(ScatterPlan.build(biome_id, species, doc.map_seed))
	var deepest := 0.0
	for r in reach:
		deepest = maxf(deepest, r)
	var step := doc.sample_step()
	var cells_by_species: Array = []
	for _s in species.size():
		cells_by_species.append([cell])
	return {
		"species": species,
		"cells_by_species": cells_by_species,
		"window":
		Rect2(Vector2(cell) * 10.0, Vector2(10.0, 10.0)).grow(deepest + 2.0 * maxf(step.x, step.y)),
		"built": PackedStringArray(PaletteLibrary.surfaces_with_role("built")),
		"cliff": PackedStringArray(PaletteLibrary.surfaces_with_role("cliff")),
	}


## `_work` with terrain response on every rule (scatter_native_landform_parity.gd).
func _curved_work(doc: MapDocument, biome_id: String, cell: Vector2i) -> Dictionary:
	var work := _work(doc, biome_id, cell)
	var species: Array[Dictionary] = []
	species.assign(work.species)
	work.species = Parity.curved_species(species)
	return work


## A stored shore weight (channel G) rising along x with a ripple along z; no bed or depth, so
## the wet dressing's own ground rules stay quiet and only the `wet` axis reads it.
func _dress_shore(doc: MapDocument) -> void:
	var columns := doc.samples_x()
	var field := PackedByteArray()
	field.resize(doc.sample_count() * WaterDressing.CHANNELS)
	for z in doc.samples_z():
		for x in columns:
			var at := (z * columns + x) * WaterDressing.CHANNELS
			var along := float(x) / (columns - 1)
			field[at + 1] = clampi(roundi(255.0 * (0.25 + 0.5 * along) + 20.0 * sin(z * 0.7)), 0, 255)
	doc.water_dressing = field


## The native rows of `work` ({asset id: PackedFloat32Array}), failing the test on a refusal.
func _native_rows(doc: MapDocument, biome_id: String, work: Dictionary) -> Dictionary:
	var native: Variant = ScatterNative.run_biome(doc, biome_id, work, {})
	assert_not_null(native, "%s ran natively (fallbacks %s)" % [biome_id, ScatterNative.fallbacks()])
	return native if native != null else {}


func _row_count(rows: Dictionary) -> int:
	var count := 0
	for asset_id in rows:
		count += (rows[asset_id] as PackedFloat32Array).size() / MapDocument.ROW_STRIDE
	return count


## GDScript's rows and anchors for `work` (ScatterRegen.run's calls) against the native ones.
@warning_ignore("integer_division")
func _assert_same_rows(doc: MapDocument, biome_id: String, work: Dictionary) -> void:
	var fields := ScatterGenerator.document_fields(
		doc, biome_id, work.window, work.built, work.cliff
	)
	var species: Array[Dictionary] = []
	species.assign(work.species)
	var anchors := {}
	var rows := ScatterGenerator.generate_species_cells(
		biome_id,
		species,
		fields.density_at,
		fields.height_at,
		fields.normal_at,
		doc.map_seed,
		work.cells_by_species,
		fields.bounds,
		fields.species_density_at,
		work.get("blockers", PackedFloat32Array()),
		anchors,
		fields.density_ceiling_at,
		null,
		fields.wet_at
	)
	var native_anchors := {}
	var native: Variant = ScatterNative.run_biome(doc, biome_id, work, native_anchors)
	assert_not_null(native, "%s ran natively (fallbacks %s)" % [biome_id, ScatterNative.fallbacks()])
	if native == null:
		return
	var count := 0
	for asset_id in rows:
		count += (rows[asset_id] as PackedFloat32Array).size() / MapDocument.ROW_STRIDE
	var problems := _row_differences(rows, native)
	if anchors.keys() != native_anchors.keys() or anchors.values() != native_anchors.values():
		problems.append("anchors %d vs %d differ" % [anchors.size(), native_anchors.size()])
	gut.p("%s: %d rows, %d anchors, %s" % [biome_id, count, anchors.size(), problems])
	assert_gt(count, 0, "%s placed rows" % biome_id)
	assert_eq(problems, [] as Array[String], "%s rows and anchors bit-equal" % biome_id)


@warning_ignore("integer_division")
func _row_differences(expected: Dictionary, actual: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if expected.keys() != actual.keys():
		out.append("assets %s vs %s" % [expected.keys(), actual.keys()])
	for asset_id in expected:
		var a: PackedFloat32Array = expected[asset_id]
		var b: PackedFloat32Array = actual.get(asset_id, PackedFloat32Array())
		if a.to_byte_array() == b.to_byte_array():
			continue
		var stride := MapDocument.ROW_STRIDE
		var differing := 0
		var first := -1
		for r in mini(a.size(), b.size()) / stride:
			if a.slice(r * stride, r * stride + stride) != b.slice(r * stride, r * stride + stride):
				differing += 1
				first = r if first < 0 else first
		out.append(
			(
				"%s: %d vs %d rows, %d differ (first %d)"
				% [asset_id, a.size() / stride, b.size() / stride, differing, first]
			)
		)
	return out
