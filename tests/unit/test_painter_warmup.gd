extends GutTest

## The painted look's warm-up (PainterWarmup): it covers every painter shader the painter draws, its
## copied shader paths are the owners' and its vertex layouts make the surface formats the real
## producers make (and the ones measured on a live Painted level, card painter-perf-warmup).

const MEASURED_GROUND := 0x800001037
const MEASURED_LIT := 0x80000101f
const MEASURED_TREE := 0x800001031
const MEASURED_MANNER := 0x80000f06f
const MEASURED_YARD := 0x80000100f


func _format_of(sample: Dictionary) -> int:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES, sample.arrays, [], {}, int(sample.get("flags", 0))
	)
	return mesh.surface_get_format(0)


func _sample_named(sample_name: String) -> Dictionary:
	for sample in PainterWarmup.collect(false) + PainterWarmup.collect(true):
		if sample.name == sample_name:
			return sample
	return {}


func test_every_painter_shader_is_warmed() -> void:
	var covered := PainterWarmup.covered_shaders()
	var dir := DirAccess.open("res://painter/shaders")
	assert_not_null(dir)
	var found := 0
	for file in dir.get_files():
		if file.ends_with(".gdshader"):
			found += 1
			assert_true(
				covered.has("res://painter/shaders/" + file),
				"%s is in PainterWarmup.covered_shaders()" % file
			)
	assert_eq(found, covered.size(), "no covered shader is missing from painter/shaders")


func test_every_drawn_shader_has_a_sample() -> void:
	var named := {}
	for sample in PainterWarmup.collect(false) + PainterWarmup.collect(true):
		named[(sample.material as ShaderMaterial).shader.resource_path] = true
	for path in PainterWarmup.covered_shaders():
		if path != PainterWarmup.SKY:
			assert_true(named.has(path), "%s has a warm-up sample" % path)


func test_the_copied_constants_are_the_owners() -> void:
	assert_eq(PainterWarmup.GROUND, PainterSurfaces.GROUND_SHADER)
	assert_eq(PainterWarmup.PLANT, PainterSurfaces.PLANT_SHADER)
	assert_eq(PainterWarmup.SOLID, PainterSurfaces.SOLID_SHADER)
	assert_eq(PainterWarmup.STRUCTURE, PainterBuildings.SHADER)
	assert_eq(PainterWarmup.YARD, PainterBuildings.YARD_SHADER)
	assert_eq(PainterWarmup.YARD_GROUND, PainterBuildings.YARD_GROUND_SHADER)
	assert_eq(PainterWarmup.MANNER, PainterMannerHost.SHADER)
	assert_eq(PainterWarmup.TREE_STROKE, PainterTrees.STROKE_SHADER)
	assert_eq(PainterWarmup.TREE_BLOCKIN, PainterTrees.BLOCKIN_SHADER)
	assert_eq(PainterWarmup.TREE_STROKE_BARE, PainterTrees.STROKE_BARE_SHADER)
	assert_eq(PainterWarmup.TREE_BLOCKIN_BARE, PainterTrees.BLOCKIN_BARE_SHADER)
	assert_eq(PainterWarmup.SKY, PainterScene.SKY_SHADER)
	assert_eq(PainterWarmup.MANNER_FLAGS, PainterMannerMesh.FORMAT)
	assert_eq(PainterWarmup.DEFAULT_SHEET, RenderStyle.DEFAULT_SHEET)


func test_the_layouts_make_the_measured_formats() -> void:
	assert_eq(_format_of(_sample_named("ground")), MEASURED_GROUND)
	assert_eq(_format_of(_sample_named("plant_lit")), MEASURED_LIT)
	assert_eq(_format_of(_sample_named("solid_lit")), MEASURED_LIT)
	assert_eq(_format_of(_sample_named("structure")), MEASURED_LIT)
	assert_eq(_format_of(_sample_named("tree_stroke")), MEASURED_TREE)
	assert_eq(_format_of(_sample_named("tree_stroke_bare")), MEASURED_TREE)
	assert_eq(_format_of(_sample_named("manner")), MEASURED_MANNER)
	assert_eq(_format_of(_sample_named("yard")), MEASURED_YARD)
	assert_eq(_format_of(_sample_named("yard_ground")), MEASURED_YARD)


func test_the_layouts_match_the_real_producers() -> void:
	assert_eq(
		_format_of(_sample_named("tree_stroke")),
		PainterTreeMeshes.strokes(0, 1).surface_get_format(0),
		"tree strokes"
	)
	assert_eq(
		_format_of(_sample_named("tree_blockin")),
		PainterTreeMeshes.block(1).surface_get_format(0),
		"tree blocks"
	)
	var chunk: Dictionary = TerrainMeshBuilder.warmup_samples()[0]
	assert_eq(_format_of(_sample_named("ground")), _format_of(chunk), "ground chunk")


func test_headless_is_ready_and_starts_nothing() -> void:
	if PainterWarmup.available():
		pending("a window can draw: the warm-up would start")
		return
	PainterWarmup.start()
	assert_true(PainterWarmup.is_ready(true))
