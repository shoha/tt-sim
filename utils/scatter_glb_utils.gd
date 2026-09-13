class_name ScatterGlbUtils
extends RefCounted

## The Geoscatter-instance -> MultiMeshInstance3D pipeline, extracted from GlbUtils to
## keep both files under this repo's gdlint max-file-lines gate, the same way
## WaterGlbUtils and MeshInstancingUtils were. See utils/glb_utils.gd for GLB
## loading/processing in general, and utils/foliage_budget.gd for the primitive budget
## this pipeline enforces on imported maps.

const _SCATTER_INSTANCES_EXTRAS_KEY := "tt_scatter_instances"

## Scene-meta key holding the FoliageBudget report when a map was thinned; absent when it
## was not. Read by scenes/states/playing/level_loader.gd, which shows the player one
## toast -- utils/ must not reference UIManager or any other autoload.
const FOLIAGE_BUDGET_REPORT_META := "tt_foliage_budget_report"


## Prototype: build a real MultiMeshInstance3D for each group of Geoscatter instance
## transforms terrain-paint wrote into this GLB's scene extras (see
## engine/scatter_instancing.py in the terrain-paint repo for the write side), instead
## of the many-real-duplicated-triangles shape a "Bake Scatter to Mesh" export produces.
##
## Each extras entry is keyed by the exact Blender object name of the single low-poly
## asset Geoscatter was instancing -- that same object was exported normally alongside
## the transform data (a plain MeshInstance3D node with that name, wherever Blender
## happened to place it), purely to get its Mesh resource (and baked material) into the
## file. This function finds that node by name, builds a MultiMesh from its Mesh, and
## frees the original node so it doesn't also render once, standalone, at whatever
## arbitrary transform it had in the Blender scene.
##
## Only wired into load_glb_with_processing()/_async() (the live user://-uploaded-map
## path) -- NOT load_map()'s res:// PackedScene branch, since that path never parses a
## live GLB and has no scene extras meta to read at all (see _extract_scene_extras).
##
## Values are untrusted network input (maps are downloaded from a host peer), same as
## extract_lighting_config() above -- guarded the same way: a malformed group or row is
## skipped rather than raising.
##
## Two-pass so FoliageBudget.plan() can allocate a single global primitive cap across
## every species before any MultiMesh is built -- the budget is global, so no one
## species' share can be decided from inside its own build. A map whose total exceeds
## `primitive_budget` gets every species thinned proportionally, and the outcome is
## recorded on the scene as FOLIAGE_BUDGET_REPORT_META so the caller can tell the player.
##
## `primitive_budget` exists only so tests can drive thinning at counts a test can build;
## it is the more exposed of the two budget-override parameters (see FoliageBudget.plan's
## own "nothing should set this" note), so nothing user-facing should ever wire it to
## something like LevelData -- the budget is fixed by design, not a per-level setting.
##
## Each species' surviving transforms are further split into ScatterChunker cells, one
## MultiMeshInstance3D per occupied cell, so a MultiMeshInstance3D's single-AABB frustum
## culling can discard the off-screen ones instead of processing every instance whenever
## any part of that species is on screen. `chunk_size` exists for tests, the same way
## `primitive_budget` does -- nothing user-facing should ever set it either.
static func process_scatter_instances(
	scene: Node3D,
	foliage_overrides: Dictionary = {},
	primitive_budget: int = FoliageBudget.PRIMITIVE_BUDGET,
	chunk_size: float = ScatterChunker.CHUNK_SIZE_WORLD_UNITS
) -> void:
	var extras: Dictionary = scene.get_meta(GlbUtils.SCENE_EXTRAS_META, {})
	if not extras.has(_SCATTER_INSTANCES_EXTRAS_KEY):
		return
	var groups: Variant = extras[_SCATTER_INSTANCES_EXTRAS_KEY]
	if not groups is Dictionary:
		return

	# Pass one: resolve every species' template mesh and surviving transforms. The budget
	# is global, so no single species' share can be decided from inside its own build.
	var resolved: Array[Dictionary] = []
	var species := {}
	for source_name in groups.keys():
		var transforms: Variant = groups[source_name]
		if not transforms is Array or transforms.is_empty():
			continue
		var source_node := GlbUtils.find_node_by_name(scene, String(source_name))
		if not source_node is MeshInstance3D:
			continue
		var mesh_node := source_node as MeshInstance3D
		if not mesh_node.mesh:
			continue
		var valid := _collect_valid_transforms(transforms)
		if valid.is_empty():
			continue
		var key := String(source_name)
		resolved.append({"key": key, "mesh_node": mesh_node, "transforms": valid})
		species[key] = {
			"count": valid.size(),
			"primitives_per_instance": FoliageBudget.primitives_per_instance(mesh_node.mesh),
		}

	var report := FoliageBudget.plan(species, primitive_budget)

	# Pass two: build each species' MultiMesh set, truncated to its allocated share and split
	# into spatial cells so frustum culling can discard the off-screen ones.
	for entry in resolved:
		var key: String = entry.key
		var mesh_node: MeshInstance3D = entry.mesh_node
		var all_transforms: Array[Transform3D] = entry.transforms
		var keep: int = report.kept.get(key, all_transforms.size())
		var kept_transforms: Array[Transform3D] = all_transforms
		if keep < all_transforms.size():
			var subset: Array[Transform3D] = []
			for index in FoliageBudget.select_indices(all_transforms.size(), keep, key):
				subset.append(all_transforms[index])
			kept_transforms = subset
		var wind_category := WindFoliage.classify_category(key)
		# MultiMesh itself has no material slot -- Godot renders every instance with
		# mesh_node.mesh's own surface material(s) as-is unless mutated here. Mutates
		# mesh_node.mesh's own per-surface materials directly rather than setting anything
		# on multimesh_instance -- MultiMeshInstance3D has no per-surface override API (see
		# WindFoliage.apply_material's own docstring). No-op (mesh keeps its own imported
		# static material) when wind_category is "".
		#
		# Hoisted out of _build_multimesh_from_transforms for chunking: a per-chunk call
		# would repeat this pointlessly, since WindFoliage.apply_material skips any surface
		# whose material is no longer a BaseMaterial3D -- its own first call replaces the
		# surface material with a ShaderMaterial, so calls 2..N would be no-ops that keep
		# the first material rather than the last.
		WindFoliage.apply_material(mesh_node.mesh, wind_category, foliage_overrides)
		var buckets := ScatterChunker.bucket_by_cell(kept_transforms, chunk_size)
		for cell in buckets.keys():
			# A species that fits in one cell keeps its original `<Species>_MultiMesh` name,
			# so the suffix reads as a signal that a species was split rather than noise on
			# every foliage node.
			var suffix := "" if buckets.size() == 1 else ScatterChunker.cell_suffix(cell)
			_build_multimesh_from_transforms(scene, mesh_node, buckets[cell], wind_category, suffix)
		# Hoisted out of _build_multimesh_from_transforms too: it used to free the template
		# as its last statement, which would free the same node once per chunk.
		var old_parent := mesh_node.get_parent()
		if old_parent:
			old_parent.remove_child(mesh_node)
		mesh_node.free()

	if report.thinned:
		scene.set_meta(FOLIAGE_BUDGET_REPORT_META, report)
		print("ScatterGlbUtils: ", FoliageBudget.describe(report))
		for key in report.kept.keys():
			print(
				(
					"ScatterGlbUtils:   %s kept %d of %d instances"
					% [key, report.kept[key], species[key]["count"]]
				)
			)


## Builds one MultiMeshInstance3D (sharing mesh_node's Mesh, and by default its
## surface material(s) too) from an array of already-converted Transform3D values (see
## _collect_valid_transforms for the row format they started as). `wind_category` ("" for
## none, otherwise a WindFoliage.PRESETS key from WindFoliage.classify_category) tags the
## built node's "wind_foliage_category" meta and gates the grass cast_shadow branch below
## -- the wind-sway ShaderMaterial itself is applied once per species by
## process_scatter_instances, not here. The "wind_foliage_category" meta lets
## OcclusionFadeManager find tree-category instances without re-deriving the
## classification itself. Grass-category instances also get cast_shadow forced to
## SHADOW_CASTING_SETTING_OFF -- see the inline comment where it's assigned below for
## why (measured perf finding, not a default carried by MultiMeshInstance3D itself).
##
## `name_suffix` is appended to the built node's name (see ScatterChunker.cell_suffix) --
## "" for a species that fits in a single cell, keeping its name unsuffixed.
##
## Each entry in `valid_transforms` is a Blender WORLD-space (matrix_world) transform,
## already converted from its row form by the caller (see _collect_valid_transforms) and
## already axis-converted into glTF/Godot's convention on the Python side (terrain-paint's
## scatter_instancing.py) -- these are the exact same translation/rotation/scale
## components a glTF node itself would carry relative to an IDENTITY scene root, no
## further axis conversion needed here. That's the reason scene_root is a required
## parameter rather than just using mesh_node.get_parent(): glTF/Godot compose node
## transforms up the tree starting from an identity scene root, so a node's cumulative
## transform-to-root always reconstructs its own recorded world matrix regardless of
## how many intermediate Blender-side parent objects existed along the way. The new
## MultiMeshInstance3D must sit DIRECTLY under scene_root with an identity transform
## (the Node3D default, left untouched here) to land in that same frame -- parenting
## it under mesh_node's own parent, or copying mesh_node's own local transform onto it,
## would double-apply mesh_node's individual placement in the Blender scene on top of
## the already-absolute per-instance transforms.
static func _build_multimesh_from_transforms(
	scene_root: Node3D,
	mesh_node: MeshInstance3D,
	valid_transforms: Array[Transform3D],
	wind_category: String = "",
	name_suffix: String = ""
) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh_node.mesh

	if valid_transforms.is_empty():
		return

	multimesh.instance_count = valid_transforms.size()
	for i in valid_transforms.size():
		multimesh.set_instance_transform(i, valid_transforms[i])

	var multimesh_instance := MultiMeshInstance3D.new()
	multimesh_instance.name = mesh_node.name + "_MultiMesh" + name_suffix
	multimesh_instance.multimesh = multimesh
	# Tags the node itself (not the Mesh resource) with its wind category so
	# OcclusionFadeManager._collect_tree_materials() can find tree-category instances
	# without re-deriving WindFoliage.classify_category()'s result.
	multimesh_instance.set_meta("wind_foliage_category", wind_category)
	if wind_category == "grass":
		# Grass no longer casts shadows: Godot runs the shadow pass's fragment() with the
		# exact same code as the color pass (no shadow-only variant -- see
		# godot-proposals#4443), and this shader's alpha-cutout discard disables early-Z
		# for that draw. Dense overlapping grass therefore pays full fragment cost per
		# covered sample in the shadow depth pass, disproportionate to its actual primitive
		# count (measured -2.53ms/-17% of total frame time removing this on a forest map,
		# more than trees' shadow removal despite trees contributing 3x the shadow-pass
		# primitives). Trees keep casting real shadows -- this branch only fires for
		# "grass". WindFoliage.apply_material's base_darken/blade_height gradient replaces
		# the contact-darkening a real shadow would otherwise have given grass at its base.
		multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene_root.add_child(multimesh_instance)


## Converts a flat array of [lx, ly, lz, qx, qy, qz, qw, sx, sy, sz] rows to Transform3D,
## dropping any row _row_to_transform rejects. Split out of
## _build_multimesh_from_transforms so process_scatter_instances' first pass can count a
## species' real surviving instances before the budget is allocated.
static func _collect_valid_transforms(rows: Array) -> Array[Transform3D]:
	var valid: Array[Transform3D] = []
	for row in rows:
		var xform: Variant = _row_to_transform(row)
		if xform != null:
			valid.append(xform)
	return valid


## Converts one [lx, ly, lz, qx, qy, qz, qw, sx, sy, sz] row into a Transform3D, or
## null if the row is malformed. Deliberately isolated from
## _build_multimesh_from_transforms as its own testable function rather than inlined
## in that loop -- confirmed via a real headless probe that
## MultiMesh.get_instance_transform() always reads back an identity transform
## regardless of what set_instance_transform() was actually given, under Godot's
## headless/dummy rendering driver (reproduced with zero scene tree involvement at
## all, so it's not something this module or its caller could work around). That
## makes MultiMesh itself a dead end for verifying this math in an automated test
## run -- this function exists so the row -> Transform3D conversion can be checked
## directly, independent of MultiMesh's own set/get round trip.
static func _row_to_transform(row: Variant) -> Variant:
	if not row is Array or row.size() < 10:
		return null
	for component in row:
		if not (component is float or component is int):
			return null

	var origin := Vector3(row[0], row[1], row[2])
	var rotation := Quaternion(row[3], row[4], row[5], row[6]).normalized()
	var scale := Vector3(row[7], row[8], row[9])
	return Transform3D(Basis(rotation).scaled(scale), origin)
