class_name PainterMannerSource
extends RefCounted

## procgen's manner records for a built structure, as the hand-drawn manner's feed
## (PainterMannerHost): the meshes by `<role>_<kind>`, the tag table, the records by tag path and
## the building record.
##
## One evaluation (card painter-manner-c). While the painted look is on, StructureGeometry.build_one
## records them in its own evaluation (`manner_records`) and AuthoredStructures keeps them in its
## cached parts: of_parts() reads them there, worker-safe, with no second evaluation. A structure
## built before the look was on (or whose parts left the cache) has none, and evaluate() asks
## procgen again on a worker (about 65 ms a house), the fallback.


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
	inputs.manner = true
	var plant: Variant = evaluator.evaluate_structure(recipe, inputs, true)
	if plant == null or not evaluator.errors.is_empty():
		return {}
	var geometry: PlantGeometry = plant["lods"][0]
	if geometry.manner.is_empty():
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
	var feed := _feed(meshes, PackedStringArray(geometry.tag_table), geometry.manner)
	feed["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return feed


## Worker-safe, reads only: the feed (as evaluate's) of parts StructureGeometry.build_one made with
## `manner_records` set; {} when they hold no records.
static func of_parts(parts: Dictionary) -> Dictionary:
	var manner: Array = parts.get("manner", [])
	if manner.is_empty():
		return {}
	var feed := _feed(parts.get("meshes", []), parts.get("tag_table", PackedStringArray()), manner)
	feed["ms"] = 0.0
	return feed


static func _feed(meshes: Array, table: PackedStringArray, manner: Array) -> Dictionary:
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
	return {"meshes": by_name, "table": table, "records": records, "building": building}
