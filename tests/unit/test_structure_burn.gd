extends GutTest

## The buildings a fire burns (card painter-structure-fire; StructureBurn, StructureRuin,
## StructureEditor.burn_down, docs/systems/painter.md "Fire and events"): which buildings a fire
## reaches, the burn and collapse timeline and pose, the painted host's `burn` uniform on a
## building's parts, that Classic (no host) plays nothing, the ruin the change leaves as one history
## entry that travels to a peer, its undo, and a ruin that does not burn again.

const STATE := {"sheet": "core", "mood": "summer", "elevation": 60.0}
const HOUSES: Array[String] = [
	"core:thatched_cottage", "core:stone_house", "core:half_timber_house"
]

var _map: Node3D = null
var _doc: MapDocument = null
var _history: AuthoringHistory = null


func before_each() -> void:
	PainterSheet.clear_cache()
	StructureRecipes.ensure_served()
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_doc = MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
	_history = AuthoringHistory.new()


func _plan(at: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in [Vector2(-3, -2.5), Vector2(3, -2.5), Vector2(3, 2.5), Vector2(-3, 2.5)]:
		out.append(p + at)
	return out


## Three houses at x = -9, 0 and 9 (ids 1 to 3) in the document.
func _village() -> void:
	for i in HOUSES.size():
		_doc.structures.append(Structure.make(i + 1, HOUSES[i], _plan(Vector2(i * 9.0 - 9.0, 0)), 5))


func _built() -> AuthoredStructures:
	_village()
	var structures := AuthoredStructures.create(_doc)
	_map.add_child(structures)
	return structures


func _editor() -> AuthoringEditor:
	_map.add_child(AuthoredTerrain.create(_doc))
	return AuthoringEditor.create(_doc, _map, _history)


func _puffs() -> Array:
	var flames := EventPuffs.new(120, FireSweep.FLAME_PRIORITY)
	var smoke := SmokePuffs.new(24)
	add_child_autofree(flames)
	add_child_autofree(smoke)
	return [flames, smoke]


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	return rng


## `structures`' parts drawn by the painter (the host a burn needs); the caller releases it.
func _painted(structures: AuthoredStructures) -> PainterBuildings:
	var buildings := PainterBuildings.new()
	assert_true(buildings.paint(_map, STATE))
	assert_not_null(StructureBurn.host_of(structures), "the host is found by the node's meta")
	return buildings


## A burn of the middle house (id 2) of `structures` (painted), caught at second 0.
func _burn_middle(structures: AuthoredStructures) -> StructureBurn:
	var found: Array[Dictionary] = [
		{"id": 2, "centre": Vector2(0, 0), "radius": 3.9, "distance": 0.0, "start": 0.0}
	]
	var puffs := _puffs()
	var burn := StructureBurn.new()
	assert_eq(burn.setup(structures, found, puffs[0], puffs[1], _rng(), Vector3.ZERO), 1)
	return burn


# --- the timeline ---------------------------------------------------------------------------


func test_the_burn_runs_on_the_trees_scale_and_the_collapse_follows_it() -> void:
	assert_eq(StructureBurn.BURN_RATE, FireSweep.BURN_RATE, "the shader's scale")
	assert_eq(StructureBurn.burn_value(-1.0, 2.4), 0.0, "nothing before it catches")
	assert_almost_eq(StructureBurn.burn_value(1.2, 2.4), StructureBurn.BURN_RATE * 0.5, 0.001)
	assert_eq(StructureBurn.burn_value(9.0, 2.4), StructureBurn.BURN_RATE, "held once out")
	assert_eq(
		StructureBurn.burn_value(1.0, 2.0), FireSweep.burn_progress(1.0, 2.0), "the trees' curve"
	)
	var burn_s := 2.4
	var start := burn_s * StructureBurn.COLLAPSE_AT
	assert_eq(StructureBurn.collapse_amount(start - 0.01, burn_s), 0.0, "it stands while it burns")
	assert_almost_eq(
		StructureBurn.collapse_amount(start + StructureBurn.COLLAPSE_S * 0.5, burn_s), 0.5, 0.001
	)
	assert_eq(StructureBurn.collapse_amount(99.0, burn_s), 1.0)
	assert_almost_eq(
		StructureBurn.end_after(burn_s), start + StructureBurn.COLLAPSE_S, 0.001, "its end"
	)
	assert_lt(
		StructureBurn.end_after(StructureBurn.BURN_S.y) + FireSweep.SPREAD_S + FireSweep.SPREAD_JITTER,
		7.0,
		"the longest a building takes after the front, inside a few seconds"
	)


func test_motion_is_held_in_ten_hertz_steps() -> void:
	assert_eq(StructureBurn.STEP_S, 0.1)
	assert_almost_eq(StructureBurn.stepped(0.19), 0.1, 0.0001)
	assert_almost_eq(StructureBurn.stepped(0.2), 0.2, 0.0001)
	assert_eq(StructureBurn.stepped(0.0), 0.0)


func test_the_node_only_shudders_and_sinks_never_squashes() -> void:
	assert_eq(StructureBurn.node_pose(0.0, 0.4), Transform3D.IDENTITY)
	for x: float in [0.05, 0.2, 0.5, 1.0]:
		var pose := StructureBurn.node_pose(x, 0.4)
		assert_true(pose.basis.is_equal_approx(Basis.IDENTITY), "no scale or turn at %.2f" % x)
	assert_almost_eq(StructureBurn.node_pose(1.0, 0.4).origin.y, -0.4, 0.001, "sunk at the end")
	var still := StructureBurn.node_pose(1.0, 0.4).origin
	assert_almost_eq(Vector2(still.x, still.z).length(), 0.0, 0.001, "the shudder is over")


## A roof slab of a gable building 8 by 5 m with its ridge along X, eaves at 3 m, ridge at 5 m.
func _slab() -> Dictionary:
	return {
		"key": 1,
		"stump": false,
		"roof": true,
		"pivot": Vector3(0.0, 3.0, 2.5),
		"tip": Vector3(0.0, 0.0, -1.0),
		"sag": 0.25,
		"angle": 0.9,
		"drop": 2.6,
		"slide": Vector3(0.0, 0.0, -0.5),
		"twist": 0.1,
		"delay": 0.05,
		"bounce": 0.15,
		"rock": 0.06,
	}


func test_a_roof_slab_sags_then_falls_in_with_gathering_speed_and_settles() -> void:
	var slab := _slab()
	var ridge := Vector3(0.0, 5.0, 0.0)
	assert_eq(StructureCollapse.pose(slab, 0.0), Transform3D.IDENTITY)
	var sagged := StructureCollapse.pose(slab, StructureCollapse.SAG_END)
	assert_lt((sagged * ridge).y, ridge.y - 0.3, "the ridge sags")
	assert_almost_eq((sagged * (slab.pivot as Vector3)).y, 3.0, 0.001, "about its eave")
	for x: float in [0.3, 0.5, 0.7, 0.9, 1.0]:
		var scale := StructureCollapse.pose(slab, x).basis.get_scale()
		assert_true(scale.is_equal_approx(Vector3.ONE), "rigid, never shrunk, at %.1f" % x)
	var start := StructureCollapse.SAG_END + float(slab.delay)
	var span := StructureCollapse.FALL_END - start
	var eave := slab.pivot as Vector3
	var first := 3.0 - (StructureCollapse.pose(slab, start + span * 0.5) * eave).y
	var down := 3.0 - (StructureCollapse.pose(slab, StructureCollapse.FALL_END) * eave).y
	assert_gt(down - first, first * 2.0, "the second half of the fall is the longer drop")
	assert_almost_eq(down, 2.6, 0.001, "down to the heap")
	var landed := StructureCollapse.pose(slab, StructureCollapse.FALL_END)
	var bounce := StructureCollapse.pose(slab, 0.9)
	var rest := StructureCollapse.pose(slab, 1.0)
	assert_gt((bounce * eave).y, (landed * eave).y, "one small bounce")
	assert_true(rest.is_equal_approx(landed), "and it rests where it landed")
	assert_lt((rest * ridge).z, eave.z, "the slab fell in, toward the middle")


func test_a_building_is_cut_into_rigid_pieces_that_cover_every_face_from_both_sides() -> void:
	# A box 8 x 4 x 5 m (walls) as two triangles a face, the top face a "roof".
	var frame := {
		"centre": Vector3.ZERO,
		"axis": Vector3.RIGHT,
		"half": Vector2(4.0, 2.5),
		"height": 4.0,
		"seed": 3,
	}
	var box := BoxMesh.new()
	box.size = Vector3(8.0, 4.0, 5.0)
	var walls := box.get_mesh_arrays()
	var lift := Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0))
	var parts: Array = [
		{"arrays": walls, "to_node": lift, "roof": false},
		{"arrays": walls, "to_node": lift.translated(Vector3(0.0, 4.0, 0.0)), "roof": true},
	]
	var pieces := StructureCollapse.split(parts, frame)
	assert_eq(int(pieces[0].key), 0, "the stump first")
	assert_true(bool(pieces[0].stump))
	var count := StructureCollapse.segments(4.0)
	assert_eq(count, 3, "an 8 m building in three segments")
	var roofs := 0
	var area := 0.0
	for piece in pieces:
		assert_true(
			StructureCollapse.pose(piece, 1.0).basis.get_scale().is_equal_approx(Vector3.ONE),
			"rigid"
		)
		if bool(piece.roof):
			roofs += 1
		for surface: Dictionary in piece.surfaces:
			var points: PackedVector3Array = (surface.arrays as Array)[Mesh.ARRAY_VERTEX]
			assert_eq(points.size() % 6, 0, "every triangle twice, once a face")
			for t in range(0, points.size(), 6):
				area += (points[t + 1] - points[t]).cross(points[t + 2] - points[t]).length() * 0.5
	assert_eq(roofs, 2 * count, "the roof in slabs, both sides of the ridge")
	var faces := 2.0 * (8.0 * 4.0 + 8.0 * 5.0 + 4.0 * 5.0)
	# Two boxes (the front copies counted; the vertex count holds the backs): nothing lost (no hole
	# to see through) and nothing doubled.
	assert_almost_eq(area, faces * 2.0, 0.05, "every face kept")
	for piece in pieces:
		if not bool(piece.stump):
			assert_gt((piece.pivot as Vector3).y, 0.9, "every falling piece is above the stump")


func test_the_dust_is_a_rich_ochre_ring_outside_the_footprint() -> void:
	var dust := StructureBurn.dust_color()
	var pale := ForestFall.DUST
	assert_gt(dust.s, pale.s, "richer than a fallen tree's dust")
	assert_lt(dust.v, pale.v, "darker")
	assert_gt(StructureBurn.DUST_RING, 1.0, "outside the footprint's own radius")
	var brush := EventPuffs.kind_marker(EventPuffs.Kind.BLOB, true)
	var plain := EventPuffs.kind_marker(EventPuffs.Kind.BLOB, false)
	assert_gt(brush, 0.1, "the brush blob is marked for the Painted edge")
	assert_eq(plain, 0.0, "any other blob is not")
	assert_lt(brush, 0.5, "and still a blob to the shader's kinds (is_kind rounds it away)")
	assert_eq(EventPuffs.kind_marker(EventPuffs.Kind.RING, false), 2.0)
	var puffs := EventPuffs.new(4, FireSweep.FLAME_PRIORITY)
	add_child_autofree(puffs)
	puffs.emit_brush(Vector3.ZERO, Vector3.ZERO, 1.0, 1.0, dust)
	puffs.emit(Vector3.ZERO, Vector3.ZERO, 1.0, 1.0, dust)
	assert_eq(puffs._brush[0], 1, "the brush blob is flagged")
	assert_eq(puffs._brush[1], 0, "the plain one is not")


func test_a_ruins_roof_remnant_is_painted_as_its_roof_kind_not_charred() -> void:
	# Card painter-roofs-ivy: held charred (painter-structure-fire), a placed ruin's remnant read as a
	# flat black plane where Classic draws it blue or brown; it is painted as the roof kind it is.
	var refs: Array[String] = ["core:ruin_cottage", "core:ruin_barn"]
	for i in refs.size():
		_doc.structures.append(Structure.make(4 + i, refs[i], _plan(Vector2(i * 12.0, 0)), 5))
	var structures := AuthoredStructures.create(_doc)
	_map.add_child(structures)
	var buildings := _painted(structures)
	for i in refs.size():
		var node := structures.get_structure_node(4 + i)
		if node == null:
			continue
		assert_true(bool(node.get_meta(StructureRuin.META, false)), "%s marked a ruin" % refs[i])
		var roofs := 0
		for found: Node in node.find_children("*", "MeshInstance3D", true, false):
			var mi := found as MeshInstance3D
			var kind := PainterBuildings.kind_of(String(mi.name))
			var raw: Variant = mi.get_instance_shader_parameter(&"burn")
			assert_eq(0.0 if raw == null else float(raw), 0.0, "%s is not charred" % mi.name)
			if kind.size() > 2 and String(kind[2]) == "roof":
				roofs += 1
				var stand_in := mi.material_override as ShaderMaterial
				assert_not_null(stand_in, "%s %s is painted" % [refs[i], mi.name])
				if stand_in != null:
					assert_true(stand_in.has_meta(PainterBuildings.META), "%s stand-in" % mi.name)
		assert_gt(roofs, 0, "%s has roof pieces" % refs[i])
	buildings.release()


func test_the_burn_runs_on_into_the_break_up_and_the_flames_are_out_first() -> void:
	assert_eq(StructureBurn.break_value(-1.0), 0.0)
	assert_eq(StructureBurn.break_value(0.0), 0.0)
	assert_almost_eq(StructureBurn.break_value(0.5), StructureBurn.BREAK_SPAN * 0.5, 0.001)
	assert_eq(StructureBurn.break_value(9.0), StructureBurn.BREAK_SPAN)
	var slump_at := StructureBurn.BURN_S.x * StructureBurn.COLLAPSE_AT
	assert_lt(
		StructureBurn.BURN_S.x * StructureBurn.FLAME_WHEN.y + StructureBurn.FLAME_LIFE.y,
		slump_at,
		"no flame stands over a lowered roof"
	)
	var dust := StructureBurn.dust_color()
	assert_lt(dust.r, ForestFall.DUST.r, "darker than a fallen tree's dust")
	assert_gt(dust.a, ForestFall.DUST.a, "more opaque")
	var include := "res://painter/shaders/painter_building_burn.gdshaderinc"
	var shader := FileAccess.get_file_as_string(include)
	assert_true(
		shader.contains("const float BURN_CHARRED = %.1f;" % StructureBurn.BURN_RATE),
		"the shader's charred value is the burn's"
	)
	# The owner's "weird hole in the ceiling" (look23): the collapse never cuts a part open.
	var cut := shader.get_slice("bool building_break(vec3 wp, float h) {", 1).get_slice("}", 0)
	assert_eq(cut.strip_edges(), "return false;", "no chunk of a roof is cut away")


# --- which buildings --------------------------------------------------------------------------


func test_a_circle_reaches_the_buildings_whose_footprint_it_touches() -> void:
	_village()
	var near := StructureBurn.find(_doc, TerrainEvent.fire(Vector2(0.0, 0.0), 2.0, 1))
	assert_eq(near.size(), 1, "only the house it stands on")
	assert_eq(near[0].id, 2)
	var edge := StructureBurn.find(_doc, TerrainEvent.fire(Vector2(0.0, 7.0), 4.6, 1))
	assert_eq(edge.size(), 1, "reaching a footprint's edge counts")
	var wide := StructureBurn.find(_doc, TerrainEvent.fire(Vector2(0.0, 0.0), 8.0, 1))
	assert_eq(wide.size(), 3)
	assert_eq(wide[0].id, 2, "nearest the start first")
	var missed := StructureBurn.find(_doc, TerrainEvent.fire(Vector2(0.0, 12.0), 3.0, 1))
	assert_true(missed.is_empty())
	assert_eq(StructureBurn.find(_doc, TerrainEvent.fire(Vector2.ZERO, 8.0, 1), 2).size(), 2, "limit")
	assert_eq(StructureBurn.ids_in(_doc, TerrainEvent.fire(Vector2.ZERO, 2.0, 1)), [2] as Array[int])


func test_a_path_reaches_the_buildings_it_passes_and_a_ruin_is_passed_over() -> void:
	_village()
	var line := PackedVector2Array([Vector2(-14, 0.5), Vector2(14, 0.5)])
	var event := TerrainEvent.fire_path(line, 1.5, 3)
	assert_eq(StructureBurn.find(_doc, event).size(), 3, "all three along the line")
	var aside := PackedVector2Array([Vector2(-14, 9.0), Vector2(14, 9.0)])
	assert_eq(StructureBurn.find(_doc, TerrainEvent.fire_path(aside, 1.5, 3)).size(), 0)
	_doc.structures[1] = Structure.make(2, "core:ruin_cottage", _plan(Vector2.ZERO), 5)
	assert_eq(StructureBurn.find(_doc, event).size(), 2, "a ruin does not burn again")


# --- the ruin ---------------------------------------------------------------------------------


func test_the_ruin_follows_what_the_building_was() -> void:
	assert_eq(StructureRuin.ruin_id_for("gambrel_barn", ["barn"], false), "ruin_barn")
	assert_eq(StructureRuin.ruin_id_for("stone_chapel", [], false), "ruin_chapel")
	assert_eq(StructureRuin.ruin_id_for("tudor_townhouse", ["townhouse"], false), "ruin_townhouse")
	assert_eq(StructureRuin.ruin_id_for("thatched_cottage", ["cottage"], false), "ruin_cottage")
	assert_eq(StructureRuin.ruin_id_for("watch_tower", [], true), "ruin_tower", "a round plan")
	assert_eq(StructureRuin.ruin_id_for("anything", [], false), StructureRuin.FALLBACK)


func test_a_building_becomes_its_ruin_on_the_same_footprint() -> void:
	var house := Structure.make(7, "core:stone_house", _plan(Vector2(3, 3)), 11, {}, "")
	var ruin := StructureRuin.ruin_of(house, _doc.extent_m(), 1.0)
	assert_not_null(ruin, "a ruin fits")
	assert_eq(ruin.id, 7, "the same record")
	assert_eq(ruin.seed_value, 11)
	assert_true(ruin.recipe.begins_with("core:ruin_"), ruin.recipe)
	assert_eq(MapStructureIO.structure_problem(ruin, _doc.extent_m()), "")
	assert_true(StructureRuin.is_ruin(ruin))
	assert_false(StructureRuin.is_ruin(house))
	assert_null(StructureRuin.ruin_of(ruin, _doc.extent_m(), 1.0), "a ruin has no ruin")
	var drawn := StructureRecipes.document(ruin.recipe)
	if not StructureEdit.param_spec(drawn.interface, StructureRuin.PARAM).is_empty():
		assert_almost_eq(float(ruin.params["ruin"]), StructureRuin.AMOUNT, 0.001, "far gone")


func test_burning_down_is_one_history_entry_that_travels_and_undoes() -> void:
	_village()
	var editor := _editor()
	var entries: Array[Dictionary] = []
	_history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var before: Array[Structure] = editor.structures.list()
	assert_true(editor.structures.burn_down([1, 3]))
	assert_eq(entries.size(), 1, "one entry")
	assert_true(StructureRuin.is_ruin(_doc.structures[0]), "house 1 is a ruin")
	assert_true(_doc.structures[1].same_as(before[1]), "house 2 untouched")
	assert_true(StructureRuin.is_ruin(_doc.structures[2]), "house 3 is a ruin")
	assert_false(editor.structures.burn_down([1]), "a ruin burns no further: nothing changed")
	assert_false(editor.structures.burn_down([99]), "an unknown id: nothing changed")
	var op := LiveEditCodec.op_of(entries[0], editor)
	assert_eq(op.kind, "structures")
	var peer_doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
	var peer_map := Node3D.new()
	add_child_autofree(peer_map)
	peer_map.add_child(AuthoredTerrain.create(peer_doc))
	var peer := AuthoringEditor.create(peer_doc, peer_map, AuthoringHistory.new())
	peer_doc.structures = before.duplicate()
	var decoded := LiveEditCodec.decode(LiveEditCodec.encode(op), peer.document)
	assert_eq(decoded.problem, "")
	LiveEditCodec.apply(decoded.op, peer)
	assert_eq(peer.document.structures.size(), 3)
	for i in 3:
		assert_true(peer.document.structures[i].same_as(_doc.structures[i]), "peer matches %d" % i)
	assert_eq(_history.undo(), "Burn down")
	for i in 3:
		assert_true(_doc.structures[i].same_as(before[i]), "the undo brings %d back" % i)


func test_a_building_no_ruin_fits_is_removed() -> void:
	var odd := Structure.make(
		5,
		"core:stone_house",
		PackedVector2Array(
			[Vector2(0, 0), Vector2(6, 0), Vector2(7, 3), Vector2(3, 6), Vector2(-1, 3)]
		),
		3
	)
	_doc.structures.append(odd)
	var editor := _editor()
	var ruin := StructureRuin.ruin_of(odd, _doc.extent_m(), 1.0)
	var changed := editor.structures.burn_down([5])
	assert_true(changed)
	if ruin == null:
		assert_eq(_doc.structures.size(), 0, "removed when no ruin fits")
	else:
		assert_eq(_doc.structures.size(), 1)
		assert_true(StructureRuin.is_ruin(_doc.structures[0]))


# --- the painted host and the play ------------------------------------------------------------


func test_a_painted_building_burns_collapses_and_is_let_go() -> void:
	var structures := _built()
	var buildings := _painted(structures)
	var node := structures.get_structure_node(2)
	var burn := _burn_middle(structures)
	var entry: Dictionary = burn.entries[0]
	assert_false((entry.actor as Dictionary).is_empty(), "the painted parts are taken")
	var part: MeshInstance3D = (entry.actor.nodes as Array)[0]
	burn.step(0.0)
	assert_eq(float(part.get_instance_shader_parameter(&"burn")), 0.0, "just caught")
	burn.step(1.3)
	var mid := float(part.get_instance_shader_parameter(&"burn"))
	assert_gt(mid, 0.0)
	assert_lt(mid, StructureBurn.BURN_RATE, "burning")
	burn.step(1.3)
	assert_eq(
		float(part.get_instance_shader_parameter(&"burn")), mid, "held within a step: no new work"
	)
	assert_eq(node.transform, Transform3D.IDENTITY, "standing before its collapse")
	var tall := StructureBurn.bounds_of(node)
	burn.step(burn.end_at() + 0.2)
	assert_eq(
		float(part.get_instance_shader_parameter(&"burn")),
		StructureBurn.BURN_RATE + StructureBurn.BREAK_SPAN,
		"charred and broken up"
	)
	assert_true(node.transform.basis.is_equal_approx(Basis.IDENTITY), "never squashed")
	assert_lt(node.transform.origin.y, 0.0, "sunk a little")
	assert_false(part.visible, "its parts give way to the pieces")
	var pieces: Array = entry.piece_nodes
	assert_gt(pieces.size(), 6, "broken into many pieces")
	var top := -INF
	for piece: Node3D in pieces:
		assert_true(piece.visible)
		assert_true(piece.transform.basis.get_scale().is_equal_approx(Vector3.ONE), "rigid")
		for found: Node in piece.get_children():
			var mi := found as MeshInstance3D
			assert_not_null(mi.material_override, "worn as its part wears it (the burn follows)")
			var box := piece.transform * mi.mesh.get_aabb()
			top = maxf(top, box.end.y)
	var charred := 0
	for found: Node in node.find_children("Collapse_*", "Node3D", false, false):
		for mi: Node in found.get_children():
			if (entry.actor.nodes as Array).has(mi):
				charred += 1
				assert_eq(
					float((mi as MeshInstance3D).get_instance_shader_parameter(&"burn")),
					StructureBurn.BURN_RATE + StructureBurn.BREAK_SPAN,
					"%s charred" % found.name
				)
	assert_gt(charred, 6, "the pieces burn with it")
	assert_lt(top - tall.position.y, tall.size.y * 0.6, "come down to a low heap")
	assert_true(burn.is_done(burn.end_at()))
	assert_false(burn.landed(), "the stand-in waits for the change")
	burn.release()
	assert_eq(node.transform, Transform3D.IDENTITY, "let go: standing as it was")
	assert_eq(float(part.get_instance_shader_parameter(&"burn")), 0.0, "unburnt")
	assert_true(part.visible, "its parts shown again")
	assert_eq(node.find_children("Collapse_*", "", true, false).size(), 0, "the pieces are gone")
	assert_true(burn.landed(), "nothing held")
	buildings.release()


func test_pieces_made_early_are_hidden_and_follow_the_burn() -> void:
	var structures := _built()
	var buildings := _painted(structures)
	var burn := _burn_middle(structures)
	var entry: Dictionary = burn.entries[0]
	while not WorkerThreadPool.is_task_completed(int(entry.task)):
		OS.delay_msec(2)
	burn.step(0.5)
	var made: Array = entry.piece_nodes
	assert_gt(made.size(), 6, "made the step its worker was done")
	var part := (made[1] as Node).get_child(0) as MeshInstance3D
	assert_eq((made[1] as Node3D).transform, StructureCollapse.PARKED, "out of sight while it stands")
	assert_true((entry.actor.nodes as Array).has(part), "taken with the building's parts")
	burn.step(burn.end_at() - 0.3)
	assert_gt((made[1] as Node3D).transform.origin.y, -50.0, "in place as it falls")
	assert_eq(float(part.get_instance_shader_parameter(&"burn")), float(entry.value), "following")
	burn.release()
	buildings.release()


func test_a_piece_casts_as_its_part_so_a_shadow_caster_stays_unseen() -> void:
	# The hand-drawn manner gives a painted part a shadows-only child (PainterMannerHost.SHADOW)
	# wearing the part's Classic material; cut and drawn, its pieces hid the charred ones under an
	# uncharred copy (card painter-fire-polish2).
	var structures := _built()
	var buildings := _painted(structures)
	var node := structures.get_structure_node(2)
	var part: MeshInstance3D = null
	for found: Node in node.get_children():
		if found is MeshInstance3D and (found as MeshInstance3D).material_override is ShaderMaterial:
			part = found
			break
	assert_not_null(part, "a painted part")
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shadow := MeshInstance3D.new()
	shadow.name = PainterMannerHost.SHADOW
	shadow.mesh = part.mesh
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	part.add_child(shadow)
	var burn := _burn_middle(structures)
	var entry: Dictionary = burn.entries[0]
	burn.step(burn.end_at() - 0.3)
	var sources: Array = entry.sources
	var made: Array = entry.piece_nodes
	var seen := {"shadow": 0, "part": 0}
	for i in made.size():
		var surfaces: Array = (entry.pieces as Array)[i].surfaces
		for k in surfaces.size():
			var mi := (made[i] as Node).get_child(k) as MeshInstance3D
			var src: MeshInstance3D = sources[int(surfaces[k].part)]
			assert_eq(mi.cast_shadow, src.cast_shadow, "%s casts as its part" % src.name)
			if src == shadow:
				seen.shadow += 1
			elif src == part:
				seen.part += 1
				assert_true((entry.actor.nodes as Array).has(mi), "the part's pieces burn")
	assert_gt(int(seen.shadow), 0, "the shadow caster is cut too, and stays shadows only")
	assert_gt(int(seen.part), 0)
	burn.release()
	buildings.release()


func test_a_part_over_the_eave_rides_a_slab_unless_it_is_on_an_end() -> void:
	# A ridge trim on a wall piece stood up as tall as it was deep when the wall toppled.
	var frame := {
		"centre": Vector3.ZERO,
		"axis": Vector3.RIGHT,
		"half": Vector2(4.0, 2.5),
		"height": 8.0,
		"seed": 3,
		"eave": 4.0,
	}
	var planes := StructureCollapse.planes_of(frame)
	var count := planes.size() - 1
	var ridge := StructureCollapse.piece_of(Vector3(0.5, 6.5, 0.1), false, planes, frame)
	assert_between(ridge, 1, 2 * count, "a ridge trim rides a roof slab")
	var gable := StructureCollapse.piece_of(Vector3(3.8, 6.0, 0.1), false, planes, frame)
	assert_between(gable, 1 + 2 * count, 2 * count + 4, "a gable stays with its end wall")
	var wall := StructureCollapse.piece_of(Vector3(0.5, 3.0, 2.5), false, planes, frame)
	assert_gt(wall, 2 * count + 4, "under the eave a long wall is a wall")


func test_a_slab_lands_by_its_faces_pitch_not_its_extents() -> void:
	# A thatch slab 4 m along, 3 m up the slope and 0.5 m thick at 0.9 rad: its two big faces set
	# the pitch; the thick eave and the ends count for little.
	var box := BoxMesh.new()
	box.size = Vector3(4.0, 0.5, 3.0)
	var arrays := box.get_mesh_arrays()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var order: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var turn := Basis(Vector3.RIGHT, 0.9)
	var soup := PackedVector3Array()
	for i in order:
		soup.append(turn * points[i])
	var flat: Array = []
	flat.resize(Mesh.ARRAY_MAX)
	flat[Mesh.ARRAY_VERTEX] = soup
	var slab := {"surfaces": [{"part": 0, "arrays": flat}]}
	assert_almost_eq(StructureCollapse.slab_pitch(slab), 0.9, 0.01, "the slab's own pitch")
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in soup:
		lo = lo.min(p)
		hi = hi.max(p)
	assert_gt(absf(atan2(hi.y - lo.y, hi.z - lo.z) - 0.9), 0.02, "the extents misjudge it")
	assert_eq(StructureCollapse.slab_pitch({"surfaces": []}), -1.0, "none for no area")


func test_the_stand_in_is_landed_when_its_node_goes() -> void:
	var structures := _built()
	var buildings := _painted(structures)
	var burn := _burn_middle(structures)
	burn.step(burn.end_at() + 0.2)
	assert_false(burn.landed())
	var node := structures.get_structure_node(2)
	structures.remove_child(node)
	node.free()
	assert_true(burn.landed(), "the ruin's node took its place")
	burn.step(burn.end_at() + 0.4)
	burn.release()
	buildings.release()


func test_classic_plays_nothing_and_the_building_stands_until_the_change() -> void:
	var structures := _built()
	assert_null(StructureBurn.host_of(structures), "no painter, no host")
	var node := structures.get_structure_node(2)
	var found: Array[Dictionary] = [
		{"id": 2, "centre": Vector2(0, 0), "radius": 3.9, "distance": 0.0, "start": 0.0}
	]
	var puffs := _puffs()
	var burn := StructureBurn.new()
	assert_eq(burn.setup(structures, found, puffs[0], puffs[1], _rng(), Vector3.ZERO), 0)
	assert_eq(burn.end_at(), 0.0, "the change waits for nothing")
	burn.step(3.0)
	assert_eq(node.transform, Transform3D.IDENTITY, "standing through the fire")
	assert_true(burn.landed())
	burn.release()


func test_a_burn_with_no_structures_node_or_a_missing_one_holds_nothing() -> void:
	var burn := StructureBurn.new()
	var puffs := _puffs()
	var found: Array[Dictionary] = [{"id": 4, "centre": Vector2.ZERO, "radius": 2.0, "start": 0.0}]
	assert_eq(burn.setup(null, found, puffs[0], puffs[1], _rng(), Vector3.ZERO), 0)
	var structures := _built()
	assert_eq(burn.setup(structures, found, puffs[0], puffs[1], _rng(), Vector3.ZERO), 0)
	assert_true(burn.landed())
	assert_eq(burn.end_at(), 0.0)
	burn.step(3.0)
	burn.release()


func test_a_fire_with_no_buildings_waits_for_nothing_of_theirs() -> void:
	var sweep := FireSweep.new()
	autofree(sweep)
	assert_eq(sweep.hold_s(), sweep.duration, "no buildings: its own duration")
