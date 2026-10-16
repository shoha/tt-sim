extends GutTest

## Grass masses (ScatterMass), the zone record they read (GroundLook, GroundZones), the saved
## anchors (MapAnchorsIO) and the golden rows of every built-in biome (scatter_golden.gd): the
## biomes without mass fields grow exactly main's rows, the zoned ones their pinned masses.

const Golden := preload("res://tests/unit/scatter_golden.gd")
const GRASS := "test_biome/Grass_Tuft"
const COLORS := [[0.2, 0.4, 0.1], [0.3, 0.5, 0.1], [0.4, 0.5, 0.2], [0.5, 0.4, 0.2]]
const SURFACES := {"turf": {"role": "ground"}, "road": {"role": "built"}}


func _entry(extra: Dictionary) -> Dictionary:
	var entry := {
		"rule": {"clump": {"transition_m": 0.0, "radius_m": 2.0, "angle_deg": 0.0}},
		"mass": true,
		"mass_stretch": 1.0,
		"mass_core_hold": 0.0,
		"mass_zone": {},
		"mass_zones": {},
		"mass_bare": [],
		"mass_follow": false,
		"ground_role": 0,
	}
	entry.merge(extra, true)
	return entry


func _look(zones: Dictionary) -> Dictionary:
	var warnings: Array[String] = []
	var raw := {"ref_surface": "turf", "zones": {"colors_linear": COLORS}.merged(zones)}
	return GroundLook.validate(raw, "b", "turf", SURFACES, warnings)


func _record() -> Dictionary:
	return GroundZones.record(_look({"cover": [0.5, 0.3, 0.2], "scale_m": [8.0, 6.0, 4.0]}), 1234)


func _cand(x: float, z: float, h: int) -> PackedFloat64Array:
	return PackedFloat64Array([x, z, 0.0, 0.0, float(h), float(h)])


func test_membership_is_an_ellipse_along_its_angle() -> void:
	var ctx := {"anchor": Vector2.ZERO}
	var entry := _entry({"mass_stretch": 4.0})
	var along_x := PackedFloat64Array([5.0, 5.0, 1.0, 0.0])
	assert_eq(ScatterMass.membership(ctx, entry, along_x, 6.8, 5.0).x, 1.0, "inside the long axis")
	assert_eq(ctx.anchor, Vector2(5.0, 5.0), "the parent is the anchor")
	assert_eq(ScatterMass.membership(ctx, entry, along_x, 5.0, 5.6).x, 0.0, "outside the short")
	var along_z := PackedFloat64Array([5.0, 5.0, 1.0, PI / 2.0])
	assert_eq(ScatterMass.membership(ctx, entry, along_z, 5.0, 6.8).x, 1.0, "turned")
	assert_eq(ScatterMass.membership(ctx, entry, along_z, 6.8, 5.0).x, 0.0)


func test_append_scale_domes_and_caps_the_height() -> void:
	var entry := _entry({"mass_core": 2.0, "mass_core_y": 3.0, "mass_core_y_max": 0.0})
	var rows := PackedFloat32Array()
	ScatterMass.append_scale(rows, 1.0, entry, 0.0)
	ScatterMass.append_scale(rows, 1.0, entry, 1.0)
	assert_eq(rows, PackedFloat32Array([2.0, 3.0, 2.0, 1.0, 1.0, 1.0]), "core grown, rim not")
	entry.mass_core_y_max = 1.5
	rows = PackedFloat32Array()
	ScatterMass.append_scale(rows, 1.0, entry, 0.0)
	ScatterMass.append_scale(rows, 2.0, entry, 0.0)
	assert_eq(rows, PackedFloat32Array([2.0, 1.5, 2.0, 4.0, 2.0, 4.0]), "capped, never shrunk")
	rows = PackedFloat32Array()
	ScatterMass.append_scale(rows, 0.7, _entry({"mass": false}), 0.0)
	assert_eq(rows, PackedFloat32Array([0.7, 0.7, 0.7]), "not a mass")


func test_held_edge() -> void:
	var entry := _entry({"mass_core_hold": 0.5})
	assert_eq(ScatterMass.held_edge(entry, 0.25), 0.0)
	assert_almost_eq(ScatterMass.held_edge(entry, 0.75), 0.5, 1e-6)
	assert_eq(ScatterMass.held_edge(entry, 1.0), 1.0)
	assert_eq(ScatterMass.held_edge(_entry({}), 0.3), 0.3, "unheld")


func test_zone_kept_by_zone_share() -> void:
	var zones := _record()
	var entry := _entry(
		{
			"mass_zones": zones,
			"mass_zone": ScatterMass.zone_rule({"zone_keep": [1.0, 0.0, 0.5, 1.0]}),
		}
	)
	var counts := {0: Vector2i.ZERO, 1: Vector2i.ZERO, 2: Vector2i.ZERO}
	for i in 900:
		var cand := _cand(float(i % 30) * 1.7, float(i / 30) * 1.7, i * 7919 + 13)
		var w := GroundZones.zone_weights(zones, cand[0], cand[1])
		var zone := ScatterMass._strongest(w)
		if counts.has(zone):
			var kept := ScatterMass.zone_kept(entry, cand, 0)
			counts[zone] += Vector2i(1 if kept else 0, 1)
	assert_eq(counts[0].x, counts[0].y, "zone 0 keeps all")
	assert_eq(counts[1].x, 0, "zone 1 keeps none")
	assert_gt(counts[2].y, 20, "zone 2 is drawn")
	assert_between(float(counts[2].x) / counts[2].y, 0.3, 0.7, "zone 2 keeps about half")
	assert_true(ScatterMass.zone_kept(_entry({"mass_zones": zones}), _cand(0, 0, 1), 0))


func test_filled_drops_a_core_in_an_opening_and_counts_an_outer_one() -> void:
	var bare := [[GroundAccents.threshold(0.3), 3.0, Vector2.ZERO, 0.0001, 1.0, 0.0, 0.0, 1]]
	var family := PackedInt32Array([0, 1, 2, 3])
	var entry := _entry(
		{"mass_bare": bare, "mass_zone": {"fill": 0.01, "share": 0.5, "family": family}}
	)
	var dropped := 0
	var counted := 0
	for i in 400:
		var c := Vector2(float(i % 20) * 0.9, float(i / 20) * 0.9)
		var inner := ScatterMass.bare_keep(bare, c.x, c.y) >= 0.5
		var outer_bare := false
		for k in ScatterMass.FILL_SPOKES:
			var t := TAU * k / ScatterMass.FILL_SPOKES
			var dir := Vector2(cos(t), sin(t)) * 2.0
			var near := c + dir * ScatterMass.FILL_RINGS[1]
			inner = inner and ScatterMass.bare_keep(bare, near.x, near.y) >= 0.5
			var far := c + dir * ScatterMass.FILL_RINGS[2]
			outer_bare = outer_bare or ScatterMass.bare_keep(bare, far.x, far.y) < 0.5
		if ScatterMass.bare_keep(bare, c.x, c.y) < 0.5:
			dropped += 1
			assert_false(ScatterMass.filled(entry, 0, c.x, c.y), "a core in an opening")
		elif inner and outer_bare:
			counted += 1
			assert_true(ScatterMass.filled(entry, 0, c.x, c.y), "an outer point only misses")
	assert_gt(dropped, 0, "some centre lies in an opening")
	assert_gt(counted, 0, "some swathe touches one at its rim")


func test_zone_weights_sum_to_one_and_hold_their_values() -> void:
	var zones := _record()
	assert_true(zones.is_read_only(), "the record is immutable")
	for i in 200:
		var w := GroundZones.zone_weights(zones, i * 0.37 - 30.0, i * 0.53 - 40.0)
		assert_almost_eq(w[0] + w[1] + w[2] + w[3], 1.0, 1e-9)
	# Pinned 2026-10-15 from the port: the CPU twin of the ground's zones must not drift.
	var pinned := {
		Vector2(0.0, 0.0): [0.0, 0.0, 0.0, 1.0],
		Vector2(3.5, -7.25): [0.0, 0.02372569904767, 0.97627430095233, 0.0],
		Vector2(-12.0, 20.0): [0.18016710844131, 0.07828982138635, 0.0, 0.74154307017234],
	}
	for p: Vector2 in pinned:
		var w := GroundZones.zone_weights(zones, p.x, p.y)
		for k in 4:
			assert_almost_eq(w[k], float(pinned[p][k]), 1e-9, "zone %d at %s" % [k, p])
	assert_eq(GroundZones.seed_offset(0), Vector2.ZERO)
	assert_ne(GroundZones.seed_offset(1234), GroundZones.seed_offset(1235), "maps differ")


func test_bare_keep() -> void:
	assert_eq(ScatterMass.bare_keep([], 1.0, 2.0), 1.0, "no openings")
	var never := [[100.0, 3.0, Vector2.ZERO, 0.1, 1.0, 0.0, 0.0, 1]]
	assert_eq(ScatterMass.bare_keep(never, 1.0, 2.0), 1.0, "no patch drawn")
	var everywhere := [[-100.0, 3.0, Vector2.ZERO, 0.1, 1.0, 0.0, 0.0, 1]]
	assert_eq(ScatterMass.bare_keep(everywhere, 1.0, 2.0), 0.0, "all an opening")


func test_shoulder_keep() -> void:
	var density := func(p: Vector2, _role: int) -> float: return 1.0 if p.x < 2.0 else 0.0
	var ctx := {"species_density_at": density}
	var entry := _entry({"mass_zone": {"shoulder": 1.0}})
	assert_eq(ScatterMass.shoulder_keep(ctx, entry, 0.0, 0.0), 1.0, "far from the edge")
	assert_eq(ScatterMass.shoulder_keep(ctx, entry, 1.5, 0.0), 0.0, "within the shoulder")
	assert_eq(ScatterMass.shoulder_keep(ctx, _entry({}), 1.5, 0.0), 1.0, "no shoulder")


func test_custom_data_carries_the_anchor() -> void:
	var transforms: Array[Transform3D] = [
		Transform3D(Basis(), Vector3(1.0, 0.0, 2.0)), Transform3D(Basis(), Vector3(3.0, 0.0, 3.0))
	]
	var anchors := {Vector2(1.0, 2.0): Vector2(0.5, -0.25)}
	# A headless run's dummy renderer reads custom data back as (0, 0, 0, 1), so the values
	# are checked on ScatterMass.custom_data, which build_multimesh writes.
	var data := ScatterMass.custom_data(anchors, transforms)
	assert_eq(data[0], Color(0.0, 0.5, -0.25, 1.0), ".x 0, .w 1")
	assert_eq(data[1], null, "no anchor")
	assert_eq(ScatterMass.custom_data({Vector2(9.0, 9.0): Vector2.ONE}, transforms), [], "none")
	var mm := ScatterGlbUtils.build_multimesh(BoxMesh.new(), transforms, anchors)
	assert_true(mm.use_custom_data)
	assert_false(ScatterGlbUtils.build_multimesh(BoxMesh.new(), transforms).use_custom_data)


func _doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(2, 2), "", "v", 1)
	var rows := PackedFloat32Array([1, 0, 2, 0, 0, 0, 1, 1, 1, 1, 3, 0, 3, 0, 0, 0, 1, 1, 1, 1])
	doc.scatter = {GRASS: rows}
	return doc


func test_anchors_round_trip_and_degrade() -> void:
	var doc := _doc()
	var table := {Vector2(1.0, 2.0): Vector2(0.5, -0.25), Vector2(3.0, 3.0): Vector2(-1.0, 0.75)}
	doc.mass_anchors = ScatterMass.anchors_entry(table, doc.scatter)
	var entries: Dictionary = MapDocumentIO.serialize(doc).entries
	var read: Dictionary = MapDocumentIO.parse(entries)
	assert_eq(read.warnings, PackedStringArray())
	assert_eq(read.document.mass_anchors, doc.mass_anchors, "round trip")
	var warnings: Array[String] = []
	var reach := {GRASS: 2.0}
	var back := ScatterMass.table_of(read.document.mass_anchors, doc.scatter, reach, warnings)
	assert_eq(back, table, "the table rebuilt")
	assert_eq(warnings, [] as Array[String])
	entries.erase(MapAnchorsIO.ENTRY)
	var old: Dictionary = MapDocumentIO.parse(entries)
	assert_true(old.document.mass_anchors.is_empty(), "an older level has none")
	assert_eq(old.warnings, PackedStringArray())
	entries[MapAnchorsIO.ENTRY] = ('{"%s": [1, "x", 0, 0]}' % GRASS).to_utf8_buffer()
	var bad: Dictionary = MapDocumentIO.parse(entries)
	assert_true(bad.document.mass_anchors.is_empty(), "malformed is dropped")
	assert_eq(bad.warnings.size(), 1)
	entries[MapAnchorsIO.ENTRY] = ('{"%s": [1, 0]}' % GRASS).to_utf8_buffer()
	var short: Dictionary = MapDocumentIO.parse(entries)
	assert_true(short.document.mass_anchors.is_empty(), "a count mismatch is dropped")
	assert_eq(short.warnings.size(), 1)
	var far := ScatterMass.table_of(doc.mass_anchors, doc.scatter, {GRASS: 0.5}, warnings)
	assert_true(far.is_empty(), "beyond the rule's reach")
	assert_eq(warnings.size(), 1)


func _palette(clump: Variant, look: Variant) -> Dictionary:
	var biome := {
		"id": "b",
		"ground_surface": "turf",
		"species":
		[
			{
				"key": "grass",
				"kind": "grass",
				"density_per_m2": 2.0,
				"clump": clump,
				"assets": [GRASS],
			}
		],
	}
	if look != null:
		biome["ground_look"] = look
	var surface := {"albedo": "a.png", "tile_m": 2.0, "kind": "grass", "role": "ground"}
	return {
		"format": 1,
		"palette_version": "x",
		"surfaces": {"turf": surface},
		"biomes": [biome],
		"assets": {GRASS: {"file": "g.glb", "node": "G", "dimensions_m": [0.2, 0.3, 0.2]}},
	}


func test_palette_parses_with_and_without_the_mass_fields() -> void:
	var base := {"parents_per_m2": 0.05, "radius_m": 4.0, "transition_m": 0.5}
	var plain: Dictionary = PaletteLibrary.validate_palette(_palette(base, null)).palette
	var plain_clump: Dictionary = plain.biomes[0].species[0].clump
	assert_eq(plain_clump.keys().size(), 4, "no mass field")
	assert_eq(plain.biomes[0].ground_look, {}, "no ground look")
	var fields := {"mass": 1, "stretch": 0.5, "zone_keep": [0.45, 0.45, 0.9, 2.0]}
	fields["zone_family"] = [0, 0, 1, 1]
	fields["core_hold"] = 0.99
	var massed: Dictionary = PaletteLibrary.validate_palette(_palette(base.merged(fields), null))
	var clump: Dictionary = massed.palette.biomes[0].species[0].clump
	assert_eq(clump.stretch, 1.0, "clamped")
	assert_eq(clump.core_hold, 0.95, "clamped")
	assert_eq(clump.zone_keep, [0.45, 0.45, 0.9, 1.0])
	assert_eq(clump.zone_family, [0.0, 0.0, 1.0, 1.0])
	var ignored := base.merged({"stretch": 3.0, "zone_keep": [0.0, 0.0, 0.0, 0.0]})
	var off: Dictionary = PaletteLibrary.validate_palette(_palette(ignored, null)).palette
	assert_false(off.biomes[0].species[0].clump.has("stretch"), "ignored without mass 1")
	var look := {"zones": {"colors_linear": COLORS, "warp": 0.7}}
	var looked: Dictionary = PaletteLibrary.validate_palette(_palette(base, look)).palette
	assert_eq(looked.biomes[0].ground_look.zones.warp, 0.7)


func test_ground_look_merges_over_base() -> void:
	var warnings: Array[String] = []
	assert_eq(GroundLook.validate(null, "b", "turf", SURFACES, warnings), {}, "absent: no look")
	assert_eq(GroundZones.record({}, 5), {}, "and no zone record")
	var raw := {
		"zones": {"colors_linear": COLORS, "rag": 3.0, "layers": ["turf", "road"], "bogus": 1},
		"light": {"key": "bright"},
		"ref_surface": "road",
	}
	var look := GroundLook.validate(raw, "b", "turf", SURFACES, warnings)
	assert_eq(look.zones.rag, 1.0, "clamped")
	assert_eq(look.zones.layers, ["turf"], "a non-ground layer dropped")
	assert_eq(look.light.key, GroundLook.BASE.light.key, "wrong type: base value")
	assert_eq(look.ref_surface, "turf", "a non-ground ref_surface falls back")
	assert_eq(look.mass.shade, GroundLook.BASE.mass.shade, "an absent key: base value")
	assert_eq(warnings.size(), 4, "bogus key, layer, wrong type, ref_surface")
	warnings.clear()
	var colorless := {"zones": {"warp": 0.2}}
	assert_eq(GroundLook.validate(colorless, "b", "turf", SURFACES, warnings), {})
	assert_eq(warnings.size(), 1, "no colours: ignored with a warning")


func test_golden_rows_equal_pinned() -> void:
	var pinned: Dictionary = Golden.pinned()
	assert_false(pinned.is_empty(), "the fixture reads")
	var now: Dictionary = Golden.digest_all()
	for biome_id in pinned:
		assert_eq(now.get(biome_id), pinned[biome_id], "%s rows at seed 1234" % biome_id)
	assert_eq(now.keys().size(), pinned.keys().size(), "every biome")
