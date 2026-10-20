extends GutTest

## The native scatter generator (utils/scatter_native.gd and native/; card native-scatter)
## against GDScript's, bit for bit: the pattern noise on every noise setting the palettes use, and
## the rows and mass anchors of whole painted cells. Pending, with the reason, where the library
## is not built: CI's tests and a fresh clone run the GDScript path only, and the rest of the
## suite checks that path.

const SIZE_FT := 200
const SEED := 1234
## How far past the cell the full-density paint reaches (metres).
const PAINT_MARGIN_M := 2.0
const NOISE_POINTS := 1500


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


## A fresh map of `biome_id` as the New map dialog makes it, with `cell` and PAINT_MARGIN_M
## around it painted to full density (the gen-native probe's cell).
func _painted_doc(biome_id: String, cell: Vector2i) -> MapDocument:
	var doc := NewMap.create(SIZE_FT, biome_id, SEED)
	_paint(doc, biome_id, Rect2(Vector2(cell) * 10.0, Vector2(10.0, 10.0)).grow(PAINT_MARGIN_M))
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
		fields.density_ceiling_at
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
