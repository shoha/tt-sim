extends SceneTree

## Map-size helper (see README.md): the document build of a new map at each probed size,
## headless, no rendering. User args after `--`:
##   seeds <landform> <first> <last>   per seed, what the recipe drew at every size (rivers,
##                                     falls, crossings), to pick a worst-case seed
##   time <landform> <seed> <runs>     NewMap.create median and range per size, against Flat
## Sizes are width x depth in feet. Over 320 ft (MapDocument.MAX_SIZE_CELLS) a size clamps,
## and a depth other than the width needs a depth_ft key in NewMap.from_spec: both were
## patched in for the 2026-10-09 sweep and reverted (README.md).

const BIOME := "temperate_forest_summer_s1"
const SIZES: Array[Vector2i] = [
	Vector2i(200, 200),
	Vector2i(250, 250),
	Vector2i(300, 300),
	Vector2i(350, 350),
	Vector2i(400, 400),
	Vector2i(400, 200),
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := String(args[0]) if args.size() > 0 else "seeds"
	var landform := String(args[1]) if args.size() > 1 else StartingLandform.TERRACES
	if mode == "time":
		var seed_value := int(args[2]) if args.size() > 2 else 1
		var runs := int(args[3]) if args.size() > 3 else 3
		for size in SIZES:
			_time(size, landform, seed_value, runs)
	else:
		var first := int(args[2]) if args.size() > 2 else 1
		var last := int(args[3]) if args.size() > 3 else 12
		for s in range(first, last + 1):
			_seeds(s, landform)
	quit()


func _seeds(seed_value: int, landform: String) -> void:
	var parts := PackedStringArray()
	for size in SIZES:
		var doc := MapDocument.create_flat(
			Vector2i(NewMap.cells_for_feet(size.x), NewMap.cells_for_feet(size.y)),
			"forest_floor",
			"",
			seed_value
		)
		StartingLandform.apply(doc, landform, seed_value, BIOME)
		var rivers := 0
		for body in doc.water_bodies:
			if body.is_river():
				rivers += 1
		parts.append(
			(
				"%dx%d r%d f%d c%d"
				% [size.x, size.y, rivers, WaterFalls.falls(doc).size(), doc.crossings.size()]
			)
		)
	print("MS| %s seed %d: %s" % [landform, seed_value, " | ".join(parts)])


func _time(size: Vector2i, landform: String, seed_value: int, runs: int) -> void:
	var shaped := PackedFloat64Array()
	var flat := PackedFloat64Array()
	var doc: MapDocument = null
	var spec := {"size_ft": size.x, "depth_ft": size.y, "biome_id": BIOME, "seed": seed_value}
	var flat_spec := spec.duplicate()
	spec["landform"] = landform
	for i in runs:
		var t0 := Time.get_ticks_usec()
		doc = NewMap.from_spec(spec)
		var t1 := Time.get_ticks_usec()
		NewMap.from_spec(flat_spec)
		var t2 := Time.get_ticks_usec()
		shaped.append((t1 - t0) / 1000.0)
		flat.append((t2 - t1) / 1000.0)
	shaped.sort()
	flat.sort()
	print(
		(
			(
				"MS| create %s %dx%d ft seed %d: %d cells, %d samples, "
				+ "median %.0f ms (%.0f-%.0f), flat %.0f ms (%.0f-%.0f)"
			)
			% [
				landform,
				size.x,
				size.y,
				seed_value,
				doc.size_cells.x * doc.size_cells.y,
				doc.sample_count(),
				shaped[shaped.size() / 2],
				shaped[0],
				shaped[shaped.size() - 1],
				flat[flat.size() / 2],
				flat[0],
				flat[flat.size() - 1],
			]
		)
	)
