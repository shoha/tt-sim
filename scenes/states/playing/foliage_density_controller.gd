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


## The player's configured budget, or FoliageBudget.PRIMITIVE_BUDGET when unset.
static func budget_from_settings() -> int:
	var config := ConfigFile.new()
	if config.load(Paths.SETTINGS_PATH) != OK:
		return FoliageBudget.PRIMITIVE_BUDGET
	return config.get_value(SETTINGS_SECTION, SETTINGS_KEY, FoliageBudget.PRIMITIVE_BUDGET)


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
		for node_path in visible.keys():
			var node := map_root.get_node_or_null(node_path) as MultiMeshInstance3D
			if node and node.multimesh:
				node.multimesh.visible_instance_count = visible[node_path]
	return report


## Groups scatter chunks by species name, recording each chunk's instance count keyed by
## its own node name, plus one primitives-per-instance figure per species.
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
				chunks_by_species[species_name][String(mmi.name)] = mmi.multimesh.instance_count
		_collect(child, chunks_by_species, per_instance)


## "GrassBlade_MultiMesh_c-1_2" -> "GrassBlade". A species occupying one cell has no cell
## suffix, so the species name is simply everything before "_MultiMesh".
static func _species_of(node_name: String) -> String:
	var cut := node_name.find(MULTIMESH_SUFFIX)
	return node_name.substr(0, cut) if cut > 0 else node_name
