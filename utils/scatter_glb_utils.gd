class_name ScatterGlbUtils
extends RefCounted

## The Geoscatter-instance -> MultiMeshInstance3D pipeline, extracted from GlbUtils to
## keep both files under this repo's gdlint max-file-lines gate, the same way
## WaterGlbUtils and MeshInstancingUtils were. See utils/glb_utils.gd for GLB
## loading/processing in general, and utils/foliage_budget.gd for the primitive budget
## FoliageDensityController applies at runtime to what this pipeline builds.

const _SCATTER_INSTANCES_EXTRAS_KEY := "tt_scatter_instances"


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
## Each species' transforms are split into ScatterChunker cells, one MultiMeshInstance3D
## per occupied cell, so a MultiMeshInstance3D's single-AABB frustum culling can discard
## the off-screen ones instead of processing every instance whenever any part of that
## species is on screen. `chunk_size` exists for tests -- nothing user-facing should ever
## set it.
##
## Import no longer thins to a primitive budget: every instance terrain-paint wrote is
## built. FoliageDensityController applies the density setting at runtime by adjusting
## each built MultiMesh's visible_instance_count over this full set, and can only ever
## raise that count as high as what was actually built here.
static func process_scatter_instances(
	scene: Node3D,
	foliage_overrides: Dictionary = {},
	chunk_size: float = ScatterChunker.CHUNK_SIZE_WORLD_UNITS
) -> void:
	var extras: Dictionary = scene.get_meta(GlbUtils.SCENE_EXTRAS_META, {})
	if not extras.has(_SCATTER_INSTANCES_EXTRAS_KEY):
		return
	var groups: Variant = extras[_SCATTER_INSTANCES_EXTRAS_KEY]
	if not groups is Dictionary:
		return

	# Pass one: resolve every species' template mesh and valid transforms.
	var resolved: Array[Dictionary] = []
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

	# Pass two: build every instance, split into spatial cells so frustum culling can
	# discard the off-screen ones. Density is applied at runtime by
	# FoliageDensityController via MultiMesh.visible_instance_count, over the full set
	# built here -- which is why nothing is thinned at import any more.
	for entry in resolved:
		var key: String = entry.key
		var mesh_node: MeshInstance3D = entry.mesh_node
		var all_transforms: Array[Transform3D] = entry.transforms
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
		var buckets := ScatterChunker.bucket_by_cell(all_transforms, chunk_size)
		for cell in buckets.keys():
			var suffix := "" if buckets.size() == 1 else ScatterChunker.cell_suffix(cell)
			_build_multimesh_from_transforms(
				scene, mesh_node, _shuffled(buckets[cell], key + suffix), wind_category, suffix
			)
		# Hoisted out of _build_multimesh_from_transforms too: it used to free the template
		# as its last statement, which would free the same node once per chunk.
		var old_parent := mesh_node.get_parent()
		if old_parent:
			old_parent.remove_child(mesh_node)
		mesh_node.free()


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
	# Defensive, not reachable today: the only caller (process_scatter_instances) builds
	# valid_transforms from ScatterChunker.bucket_by_cell, which returns only occupied
	# cells, so every bucket handed here already has at least one transform. Kept as a
	# guard against a future caller that isn't so careful. Checked before any allocation
	# so a hit returns having done nothing rather than leaking a MultiMesh.
	if valid_transforms.is_empty():
		return

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh_node.mesh

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
	# The wind shader displaces vertices beyond the mesh's own AABB (see
	# shaders/wind_foliage_include.gdshaderinc's wind_sway_vertex_offset, an unnormalized
	# object-space height times sway_amplitude, up to 0.06 for trees), but Godot culls
	# against the un-displaced AABB. A map-wide per-species AABB was always big enough to
	# absorb that overhang; these tight, chunk-sized AABBs are not, so displaced tips can
	# poke outside their own chunk's cull volume and flicker at the screen edge while panning.
	multimesh_instance.extra_cull_margin = 1.0
	scene_root.add_child(multimesh_instance)


## Reorders a chunk's transforms into FoliageBudget.shuffled_order, so that drawing a
## prefix of the MultiMesh -- which is how the density setting works -- samples the whole
## cell evenly instead of carving a bald patch out of one side of it. Seeded per chunk, so
## two cells of the same species do not thin in an identical pattern.
static func _shuffled(transforms: Array[Transform3D], seed_source: String) -> Array[Transform3D]:
	var reordered: Array[Transform3D] = []
	for index in FoliageBudget.shuffled_order(transforms.size(), seed_source):
		reordered.append(transforms[index])
	return reordered


## Converts a flat array of [lx, ly, lz, qx, qy, qz, qw, sx, sy, sz] rows to Transform3D,
## dropping any row _row_to_transform rejects. Split out of
## _build_multimesh_from_transforms so the row -> Transform3D conversion can be tested
## directly: MultiMesh.get_instance_transform() reads back identity under Godot's
## headless/dummy rendering driver regardless of what was set, so MultiMesh itself is a
## dead end for verifying this math (see _row_to_transform's own docstring).
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
