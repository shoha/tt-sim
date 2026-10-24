extends GutTest

## The arrival motion (utils/scatter_arrival.gd; card motion, 2026-10-20): species wait by size
## class, plants overshoot and ripple out from the brush centre a job carries, rocks drop and
## rebound, a row kept across landings never starts over, and every real wind shader variant
## reads the new uniforms while the burn variant stays as it was.

const BIOME := "temperate_forest_summer_s1"
const OAK := BIOME + "/Tree_Oak_summer_01"
const BIG_BUDGET := 1_000_000_000
const REAL_VARIANTS := [
	"res://shaders/wind_foliage.gdshader",
	"res://shaders/wind_foliage_no_aa.gdshader",
	"res://shaders/wind_foliage_painted.gdshader",
	"res://shaders/wind_foliage_painted_no_aa.gdshader",
	"res://shaders/wind_foliage_debug_trivial.gdshader",
	"res://shaders/wind_foliage_debug_cheap_lighting.gdshader",
	"res://shaders/wind_foliage_debug_unshaded.gdshader",
]
const BURN := "res://shaders/wind_foliage_burn.gdshader"

var _map: Node3D = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)


func _regen() -> ScatterRegen:
	var doc := MapDocument.create_flat(Vector2i(40, 20), "", "", 11)
	doc.biome_ids = PackedStringArray([BIOME])
	var regen := ScatterRegen.for_document(doc)
	regen.set_biome(BIOME, PaletteLibrary.species(BIOME))
	return regen


## Every job `regen` has left at `now`: cell -> the brush centre its job carried.
func _centres(regen: ScatterRegen, now: int) -> Dictionary:
	var found := {}
	for _i in 100:
		var job := regen.take_job(1, now)
		if job.is_empty():
			break
		found.merge(job.centres, true)
	return found


func _oaks(points: Array) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	for p: Vector2 in points:
		rows.append_array([p.x, 0.0, p.y, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])
	return rows


## `path`'s source with every #include expanded (each file once).
func _expanded(path: String, seen: Dictionary = {}) -> String:
	if seen.has(path):
		return ""
	seen[path] = true
	var out := PackedStringArray()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var text := line.strip_edges()
		if text.begins_with("#include"):
			out.append(_expanded(text.get_slice("\"", 1), seen))
		else:
			out.append(line)
	return "\n".join(out)


func test_species_wait_by_size_class() -> void:
	var order := ["large", "medium", "small", "ground"].map(ScatterArrival.stage_of)
	assert_eq(order, [0, 1, 2, 3], "large first, ground cover last")
	assert_eq(ScatterArrival.stage_of("unknown"), 1, "an unknown class counts as medium")
	assert_almost_eq(ScatterArrival.stage_delay(3), 0.36, 1e-6, "ground cover waits 0.36 s")
	assert_eq(ScatterArrival.stage_delay(0), 0.0)
	assert_eq(ScatterArrival.stage_for(OAK, PaletteLibrary.DEFAULT_ROOT), 0, "an oak is large")


func test_plants_overshoot_and_settle() -> void:
	assert_almost_eq(ScatterArrival.back_out(0.0), 0.0, 1e-6)
	assert_almost_eq(ScatterArrival.back_out(1.0), 1.0, 1e-6)
	var peak := 0.0
	for i in 101:
		peak = maxf(peak, ScatterArrival.back_out(i / 100.0))
	assert_between(peak, 1.08, 1.12, "about 10 percent over full size")


func test_rocks_drop_and_rebound() -> void:
	assert_almost_eq(ScatterArrival.drop_height(0.0, 1.0), 1.0, 1e-6, "starts at its drop")
	var fall := 1.0 - ScatterArrival.ROCK_SETTLE
	assert_almost_eq(ScatterArrival.drop_height(fall, 1.0), 0.0, 1e-6, "lands")
	var rebound := ScatterArrival.drop_height(fall + ScatterArrival.ROCK_SETTLE * 0.5, 1.0)
	assert_almost_eq(rebound, ScatterArrival.ROCK_REBOUND, 1e-6, "bounces up a little")
	assert_almost_eq(ScatterArrival.drop_height(1.0, 1.0), 0.0, 1e-6, "and settles")
	assert_eq(ScatterArrival.drop_of(0.1), ScatterArrival.ROCK_DROP_MIN_M)
	assert_eq(ScatterArrival.drop_of(10.0), ScatterArrival.ROCK_DROP_MAX_M)
	assert_almost_eq(ScatterArrival.drop_of(1.0), 0.6, 1e-6)


func test_the_ripple_grows_with_distance_and_is_capped() -> void:
	assert_eq(ScatterArrival.ripple_delay(0.0), 0.0)
	assert_almost_eq(ScatterArrival.ripple_delay(2.0), 0.12, 1e-6)
	assert_eq(ScatterArrival.ripple_delay(100.0), ScatterArrival.RIPPLE_MAX_SECONDS)


func test_a_dab_carries_its_centre() -> void:
	var regen := _regen()
	regen.request_region(Rect2(2.0, 2.0, 1.0, 1.0), true, 0)
	var centres := _centres(regen, 0)
	assert_eq(centres.get(Vector2i(0, 0)), Vector2(2.5, 2.5))


func test_a_stroke_carries_the_nearest_point_of_its_path() -> void:
	var regen := _regen()
	for i in 13:  # along z = 5 from x = 1 to x = 37, one dab every 3 m
		regen.request_region(Rect2(0.5 + 3.0 * i, 4.5, 1.0, 1.0), true, i * 10)
	regen.request_region(Rect2(0.0, 0.0, 40.0, 10.0), false, 200)  # a revert: noted, not nearer
	var centres := _centres(regen, 1000)
	assert_eq(centres.get(Vector2i(0, 0)), Vector2(4.0, 5.0), "nearest (5, 5) of cell (0, 0)")
	assert_eq(centres.get(Vector2i(2, 0)), Vector2(25.0, 5.0), "the dab through (25, 5)")


func test_accepted_cells_forget_their_centre() -> void:
	var regen := _regen()
	regen.request_region(Rect2(2.0, 2.0, 1.0, 1.0))
	regen.accept(regen.take_job(1))
	regen.request_region(Rect2(7.0, 7.0, 1.0, 1.0))
	assert_eq(_centres(regen, 0).get(Vector2i(0, 0)), Vector2(7.5, 7.5), "the new edit's own")


func test_a_row_kept_across_landings_does_not_restart() -> void:
	var scatter := AuthoredScatter.create()
	scatter.budget = BIG_BUDGET
	_map.add_child(scatter)
	var cell := Vector2i.ZERO
	var first := _oaks([Vector2(2.0, 2.0), Vector2(8.0, 8.0)])
	scatter.rebuild_cells({cell: {OAK: first}}, true, {cell: Vector2(2.0, 2.0)})
	var entry: Dictionary = (scatter.get("_growing") as Dictionary)[cell][OAK][0]
	var node: MultiMeshInstance3D = entry.node
	var tween: Tween = entry.tween
	tween.custom_step(0.2)
	var wave: Vector4 = node.get_instance_shader_parameter(ScatterArrival.WAVE_UNIFORM)
	assert_eq(Vector2(wave.x, wave.y), Vector2(2.0, 2.0), "ripples from the landing's centre")
	var later := first + _oaks([Vector2(5.0, 5.0)])
	scatter.rebuild_cells({cell: {OAK: later}}, true, {cell: Vector2(9.0, 9.0)})

	var nodes := scatter.get_growing_nodes(cell, OAK)
	assert_eq(nodes.size(), 2, "the new row grows in its own node")
	assert_same(nodes[0], node, "the kept rows keep their node")
	assert_same(entry.tween, tween, "and their tween")
	assert_almost_eq(tween.get_total_elapsed_time(), 0.2, 1e-4, "which carries on")
	var clock: Vector2 = node.get_instance_shader_parameter(ScatterArrival.CLOCK_UNIFORM)
	assert_almost_eq(clock.x, 0.2, 1e-4, "the clock is not set back")
	wave = node.get_instance_shader_parameter(ScatterArrival.WAVE_UNIFORM)
	assert_eq(Vector2(wave.x, wave.y), Vector2(2.0, 2.0), "nor the centre moved")
	var fresh: Vector4 = nodes[1].get_instance_shader_parameter(ScatterArrival.WAVE_UNIFORM)
	assert_eq(Vector2(fresh.x, fresh.y), Vector2(9.0, 9.0), "the new row ripples from its own")


func test_a_row_leaving_mid_arrival_leaves_from_its_size() -> void:
	var tween := create_tween()
	tween.tween_interval(5.0)
	tween.custom_step(0.21)
	var entry := {"arrival": {"delay": 0.0, "at": Vector3.ZERO}, "tween": tween}
	var near := Transform3D(Basis(), Vector3.ZERO)
	var far := Transform3D(Basis(), Vector3(10.0, 0.0, 0.0))  # its ripple (0.35 s) not over
	var shown := ScatterArrival.as_shown(entry, _map, [near, far], true, 1.0)
	assert_eq(shown.size(), 1, "one not yet shown is left out")
	assert_almost_eq(shown[0].basis.x.x, ScatterArrival.back_out(0.5), 1e-4, "the size it reached")
	var rock := ScatterArrival.as_shown(entry, _map, [near], false, 1.0)
	var height := ScatterArrival.drop_height(0.21 / ScatterArrival.ROCK_DROP_SECONDS, 0.6)
	assert_almost_eq(rock[0].origin.y, height, 1e-4, "a rock where its drop is")
	tween.kill()


func test_every_real_wind_variant_reads_the_arrival_uniforms() -> void:
	for path: String in REAL_VARIANTS:
		var code := _expanded(path)
		assert_string_contains(code, "instance uniform vec4 grow_wave", false)
		assert_string_contains(code, "instance uniform vec2 grow_clock", false)
		assert_string_contains(code, "VERTEX *= grow_scale(MODEL_MATRIX[3].xyz);", false)


func test_the_burn_variant_gains_nothing() -> void:
	var code := _expanded(BURN)
	for uniform_name in ["grow_wave", "grow_clock", "grow_scale"]:
		assert_false(
			code.contains(uniform_name), "the burn shader and its includes never read " + uniform_name
		)
	assert_string_contains(code, "VERTEX *= grow;", false)
