extends RefCounted

## Extra knobs of the GPU audit probe (perfaudit_gpu.gd) for card gpuoptions (2026-11-09), kept
## out of the rig so that file stays under the line cap. The rig owns one instance and calls
## apply() at the end of its own _apply(): each knob goes to the configuration's value, or back
## to what the game had when the knob was first touched.
##
##   blend (bool)        every sun's directional_shadow_blend_splits
##   splits ([a, b, c])  every sun's split offsets 1 to 3
##   noaa ([class globs]) the wind materials of matching MultiMesh instances on their plain-cutout
##                       twin (WindFoliage.shader_for(.., false)) while the viewport's MSAA stays
##                       as set: the cutout without alpha-to-coverage edges, drawn opaque
##   a2c ("noedge")      every antialiased wind material on its include with the alpha_to_coverage
##                       render mode kept and the edge built-ins dropped (WIND_FOLIAGE_NO_AA)

const Util := preload("res://tools/render_jobs/probes/perfaudit_gpu_util.gd")
const MAIN := "res://shaders/wind_foliage_main.gdshaderinc"
const LIT_A2C := "cull_disabled, diffuse_burley, specular_schlick_ggx, alpha_to_coverage"
const LEAN_A2C := "cull_disabled, diffuse_lambert, specular_disabled, alpha_to_coverage"

var rig: Node = null
var _suns := {}
var _shaders := {}
var _built := {}


func apply(gm: GameMap, cfg: Dictionary) -> void:
	_apply_suns(gm, cfg)
	_apply_foliage(gm, cfg)


func _apply_suns(gm: GameMap, cfg: Dictionary) -> void:
	for node in gm.world_viewport.find_children("*", "DirectionalLight3D", true, false):
		var s := node as DirectionalLight3D
		if not _suns.has(s):
			_suns[s] = {
				"blend": s.directional_shadow_blend_splits,
				"splits":
				[
					s.directional_shadow_split_1,
					s.directional_shadow_split_2,
					s.directional_shadow_split_3
				],
			}
		var o: Dictionary = _suns[s]
		s.directional_shadow_blend_splits = bool(cfg.get("blend", o.blend))
		var sp: Array = cfg.get("splits", o.splits)
		s.directional_shadow_split_1 = float(sp[0])
		s.directional_shadow_split_2 = float(sp[1])
		s.directional_shadow_split_3 = float(sp[2])


## Every swapped wind material back on the shader it had. The rig calls it at the START of its
## _apply, before its msaa knob re-picks the variants, so a later level change is never undone.
func restore_foliage() -> void:
	for m: ShaderMaterial in _shaders:
		if m.shader == _shaders[m][1]:
			m.shader = _shaders[m][0]
	_shaders.clear()


func _apply_foliage(gm: GameMap, cfg: Dictionary) -> void:
	restore_foliage()
	var globs: Array = cfg.get("noaa", [])
	var a2c := String(cfg.get("a2c", ""))
	if globs.is_empty() and a2c.is_empty():
		return
	# Classes first, on the original shaders: materials are shared between chunks, so a swap
	# made for one instance would change the next one's class.
	var hits := {}
	var nodes := gm.map_container.find_children("*", "MultiMeshInstance3D", true, false)
	for node in nodes:
		hits[node] = not globs.is_empty() and rig._matches(rig._cls(node), globs)
	for node in nodes:
		var mmi := node as MultiMeshInstance3D
		if mmi.multimesh == null or mmi.multimesh.mesh == null:
			continue
		if not hits[node] and a2c.is_empty():
			continue
		var mesh := mmi.multimesh.mesh
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i) as ShaderMaterial
			if m == null or _shaders.has(m) or not WindFoliage.is_wind_shader(m.shader):
				continue
			var target: Shader = WindFoliage.shader_for(m, false) if hits[node] else _noedge(m)
			if target == null or target == m.shader:
				continue
			_shaders[m] = [m.shader, target]
			m.shader = target


## The antialiased wind shader of `m` rebuilt with alpha_to_coverage kept and the edge built-ins
## dropped; null for a material already on a plain-cutout shader.
func _noedge(m: ShaderMaterial) -> Shader:
	var file := m.shader.resource_path.get_file()
	match file:
		"wind_foliage.gdshader":
			return Util.define_shader(MAIN + "#WIND_FOLIAGE_NO_AA", LIT_A2C, _built)
		"wind_foliage_painted.gdshader":
			return Util.define_shader(
				MAIN + "#WIND_FOLIAGE_NO_AA,FOLIAGE_PAINTED_LIGHT", LIT_A2C, _built
			)
		"wind_foliage_ground.gdshader":
			return Util.define_shader(
				MAIN + "#WIND_FOLIAGE_NO_AA,FOLIAGE_GROUND_LEAN", LEAN_A2C, _built
			)
	return null
