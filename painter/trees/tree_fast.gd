class_name PainterTreeFast
extends RefCounted
## The painted trees' crown masses as the camera draws them (card painter-perf-blockin).
##
## The block-in shader discards in many places (a disabled role, the thinning and rim dissolves, the
## sun pass's erosion, the canopy fade). Any discard makes a shader's depth pre-pass run every
## fragment and takes away early-z in the opaque pass; the presence alone cost the taiga home view
## about 0.3 ms and the discards' own work about 0.3 more. So a cell's masses draw with a variant
## compiled with TREE_FAST, which has none (the two whole-fragment kills collapse the mass in the
## vertex stage), and cast no shadow; a twin node over the same MultiMesh, SHADOWS_ONLY with the
## full shader, casts the crown's shadow with its eroded edge and gaps. Play always draws the
## discard-free masses; only while an authoring fade is live (a brush's window or the Village
## tool's cut, which are discards) do the camera masses draw with the full shader again.
## docs/systems/painter.md "The cost of a discard".

const SHADER := "res://painter/shaders/painter_tree_blockin_fast.gdshader"
## The same in a bare season (TREE_BARE as well).
const BARE_SHADER := "res://painter/shaders/painter_tree_blockin_fast_bare.gdshader"
## The index of the twin among a cell's nodes (0..4 are the block-in's two and the stroke levels').
const SHADOW_NODE := 5


## The shader the camera masses draw with: the discard-free variant, or (`fading`, a canopy fade is
## live) the block-in's full shader, which holds the fade's discard.
static func shader_path(is_bare: bool, fading: bool) -> String:
	if fading:
		return PainterTrees.shader_path(true, is_bare)
	return BARE_SHADER if is_bare else SHADER


## The camera masses' material: `source`'s (slot 0) uniforms under the fast shader. A copy, so the
## five-slot indexing of the host's material set stays as it was.
static func make_material(source: ShaderMaterial) -> ShaderMaterial:
	var fast := source.duplicate() as ShaderMaterial
	fast.shader = load(SHADER) as Shader
	for meta: StringName in source.get_meta_list():
		fast.set_meta(meta, source.get_meta(meta))
	return fast


## Gives the cell nodes `nodes` (0 the masses) their fast material and appends the shadow twin,
## which shares node 0's MultiMesh and draws with `full` (the host's slot 0). `meta` marks them
## tree nodes.
static func split_masses(
	nodes: Array, fast: ShaderMaterial, full: ShaderMaterial, name_stem: String, meta: StringName
) -> void:
	var camera_node := nodes[0] as MultiMeshInstance3D
	camera_node.material_override = fast
	camera_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var twin := MultiMeshInstance3D.new()
	twin.multimesh = camera_node.multimesh
	twin.material_override = full
	twin.custom_aabb = camera_node.custom_aabb
	twin.name = "%s_%d" % [name_stem, SHADOW_NODE]
	twin.set_meta(meta, true)
	twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	nodes.append(twin)


## Puts the shader `fast` should draw with now on it: the full one while a canopy fade is live (a
## shader swap compiles, so only when a fade starts or ends), else the discard-free one.
static func follow_fade(fast: ShaderMaterial, is_bare: bool) -> void:
	if fast == null:
		return
	var want := shader_path(is_bare, CanopyFade.live())
	if fast.shader == null or fast.shader.resource_path != want:
		fast.shader = load(want) as Shader
