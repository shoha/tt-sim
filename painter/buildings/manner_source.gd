class_name PainterMannerSource
extends RefCounted

## PROBE (card painter-manner; delete with the probe if it is not chosen): procgen's manner
## records for a built structure. The live build (StructureGeometry.build_one) keeps no records,
## so the probe evaluates the structure's recipe again with `ProcgenStructureInputs.manner` set,
## on a worker, and remakes its meshes the way build_one does (role split, StructurePaint), so the probe has the
## arrays on the CPU without reading a mesh back from the GPU. A shipped version would ask for the
## records in build_one itself and keep them with the parts (one evaluation, not two).
##
## The flag and the records are read by name (`set`, `get`): a procgen without the manner data
## (tt-sim's pin before procgen-manner) compiles and gives no records, and the probe then changes
## nothing.


## The map document the structures of the running game stand in (the authoring document, else the
## played level's), or null.
static func document(tree: SceneTree) -> MapDocument:
	if tree == null:
		return null
	for n: Node in tree.root.get_children():
		var ctrl: Object = n.get("_authoring_controller")
		if ctrl != null and ctrl.get("document") != null:
			return ctrl.get("document") as MapDocument
		var lpc: Object = n.get("_level_play_controller")
		if lpc != null and lpc.get("loaded_map_document") != null:
			return lpc.get("loaded_map_document") as MapDocument
	return null


## The structure record `id` of `doc`, or null.
static func structure_of(doc: MapDocument, id: int) -> Structure:
	if doc == null:
		return null
	for s: Structure in doc.structures:
		if s.id == id:
			return s
	return null


## Worker-safe. {"meshes": `<role>_<kind>` -> mesh dictionary (StructureGeometry.split_surface,
## painted), "records": tag path -> record, "building": the building record or {}, "ms"}; {} when
## the recipe is unknown or fails, or procgen gives no manner data.
static func evaluate(doc: MapDocument, structure: Structure, decor: bool) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var recipe := StructureRecipes.document(structure.recipe)
	if recipe == null:
		return {}
	StructureOrnaments.apply(recipe, structure.params, structure.seed_value)
	if decor:
		StructureOrnaments.soften(recipe)
	var evaluator := StructureProcgen.new_evaluator(recipe.registry)
	var inputs := StructureGeometry.inputs_for(doc, structure, recipe)
	inputs.set("manner", true)
	var plant: Variant = evaluator.evaluate_structure(recipe, inputs, true)
	if plant == null or not evaluator.errors.is_empty():
		return {}
	var geometry: PlantGeometry = plant["lods"][0]
	var manner: Variant = geometry.get("manner")
	if manner == null or (manner as Array).is_empty():
		return {}
	var roles := PackedStringArray()
	for path in geometry.tag_table:
		roles.append(StructureLook.role_of_path(recipe, path))
	var meshes: Array = []
	for surface in geometry.merged_by_kind():
		meshes.append_array(StructureGeometry.split_surface(surface, roles))
	var hints := StructureLook.palette_hints(recipe)
	var palette := StructurePaint.palette_of(structure.seed_value, structure.id, hints)
	StructurePaint.paint(meshes, PackedInt32Array(), [palette])
	var by_name: Dictionary = {}
	for mesh: Dictionary in meshes:
		by_name["%s_%s" % [mesh.role, mesh.kind]] = mesh
	var records: Dictionary = {}
	var building: Dictionary = {}
	for rec: Dictionary in manner:
		if str(rec["kind"]) == "building":
			building = rec
		else:
			records[str(rec["id"])] = rec
	return {
		"meshes": by_name,
		"table": PackedStringArray(geometry.tag_table),
		"records": records,
		"building": building,
		"ms": (Time.get_ticks_usec() - t0) / 1000.0
	}
