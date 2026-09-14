class_name FoliageDensityController
extends Node

## Applies the player's foliage density setting to a loaded map by writing
## MultiMesh.visible_instance_count on every scatter chunk.
##
## Import builds every scatter instance (see ScatterGlbUtils.process_scatter_instances) and
## shuffles each chunk, so drawing a prefix of a chunk is a spatially even sample of that
## cell. This turns the budget into a runtime dial that moves in both directions with no
## map reload: 1,372 integer writes on the reference map, imperceptible.
##
## The setting is per-user and deliberately NOT networked -- a host and its clients may run
## different densities to suit their own hardware. Scatter foliage carries no collision, so
## peers disagreeing about it cannot desync anything.

const SETTINGS_SECTION := "graphics"
const SETTINGS_KEY := "foliage_budget"
const MULTIMESH_SUFFIX := "_MultiMesh"


## The player's configured budget, or FoliageBudget.PRIMITIVE_BUDGET when unset. Wrapped in
## int(...) because ConfigFile.get_value returns whatever Variant type is on disk -- a
## slider always writes a float or int, but a hand-edited or corrupt settings.cfg could
## hold a String or bool, which would otherwise be a hard runtime type error on every map
## load instead of a coerced number.
##
## `path` defaults to the real settings file and exists so tests can point this at a
## disposable user:// path instead -- production callers never pass it.
static func budget_from_settings(path: String = Paths.SETTINGS_PATH) -> int:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return FoliageBudget.PRIMITIVE_BUDGET
	return int(config.get_value(SETTINGS_SECTION, SETTINGS_KEY, FoliageBudget.PRIMITIVE_BUDGET))


## Writes visible_instance_count on every scatter chunk under `map_root` so the total stays
## within `budget`. Returns FoliageBudget.plan()'s report so the caller can decide whether
## to tell the player.
##
## Chunks are found by `has_meta("wind_foliage_category")`, which every chunk carries --
## including deny-listed rock species, whose value is the empty string. Testing the value
## instead of its presence would wrongly exclude rocks from the budget.
static func apply(map_root: Node3D, budget: int) -> Dictionary:
	var chunks_by_species := {}
	var per_instance := {}
	_collect(map_root, chunks_by_species, per_instance)

	var species := {}
	for name in chunks_by_species.keys():
		var total := 0
		for count in (chunks_by_species[name] as Dictionary).values():
			total += count
		species[name] = {"count": total, "primitives_per_instance": per_instance[name]}

	var report := FoliageBudget.plan(species, budget)
	for name in chunks_by_species.keys():
		var chunk_counts: Dictionary = chunks_by_species[name]
		var total: int = species[name]["count"]
		var kept: int = report.kept.get(name, total)
		var visible := FoliageBudget.visible_counts_for_chunks(chunk_counts, kept, total)
		for node in visible.keys():
			var mmi := node as MultiMeshInstance3D
			if mmi and mmi.multimesh:
				mmi.multimesh.visible_instance_count = visible[node]
	return report


## Groups scatter chunks by species name, recording each chunk's instance count keyed by
## the MultiMeshInstance3D node itself (not its name or path), plus one
## primitives-per-instance figure per species.
##
## Keyed by node object rather than name or NodePath: `_collect` recurses arbitrarily deep
## (ScatterGlbUtils parents chunks under the GLB scene root, which level_loader then
## parents under map_container as "LevelMap", so real chunks sit two levels below the root
## `apply()` is given), and a bare node name can only ever be resolved back to a DIRECT
## child via get_node_or_null -- silently dropping the write-back for anything deeper. Node
## objects also can't collide the way two identically-named chunks in different subtrees
## would under a name-keyed dictionary, which would otherwise undercount one of them.
static func _collect(node: Node, chunks_by_species: Dictionary, per_instance: Dictionary) -> void:
	for child in node.get_children():
		if child is MultiMeshInstance3D and child.has_meta("wind_foliage_category"):
			var mmi := child as MultiMeshInstance3D
			if mmi.multimesh and mmi.multimesh.mesh:
				var species_name := _species_of(String(mmi.name))
				if not chunks_by_species.has(species_name):
					chunks_by_species[species_name] = {}
					per_instance[species_name] = FoliageBudget.primitives_per_instance(
						mmi.multimesh.mesh
					)
				chunks_by_species[species_name][mmi] = mmi.multimesh.instance_count
		_collect(child, chunks_by_species, per_instance)


## "GrassBlade_MultiMesh_c-1_2" -> "GrassBlade". A species occupying one cell has no cell
## suffix, so the species name is simply everything before "_MultiMesh".
##
## rfind, not find: a species whose own name contains "_MultiMesh" (e.g. a chunk literally
## named "Rock_MultiMeshFoo_MultiMesh") would otherwise cut at the first occurrence and
## collapse into the same species as a plain "Rock_MultiMesh" chunk, merging two unrelated
## groups under one name and costing the merged group with whichever mesh was recorded
## first. Cell suffixes ("_c<x>_<z>") never contain "_MultiMesh", so the last occurrence is
## always the real separator.
static func _species_of(node_name: String) -> String:
	var cut := node_name.rfind(MULTIMESH_SUFFIX)
	return node_name.substr(0, cut) if cut > 0 else node_name
