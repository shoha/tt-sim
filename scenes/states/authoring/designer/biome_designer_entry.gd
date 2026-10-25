class_name BiomeDesignerEntry
extends RefCounted

## The way into the biome designer (step S8a): from a library and a biome id to the request
## Root hands the authoring state. The draft is compiled and laid over the palette BEFORE the
## proving ground is built, because the ground takes its surfaces from the palette biome. Also the
## list the picker shows (every biome of every library served from a folder) and the copy
## "New biome from a core biome" makes. Pure of nodes; the picker dialog and Root call it.

const PROVING_NAME := "Designing %s"


## Prepares the designer for biome `biome_id` of library `library_id`: opens the model, compiles
## the draft, lays it over the palette. Returns {ok, error, model, request (Root's authoring
## request), runtime_id}.
static func prepare(library_id: String, biome_id: String) -> Dictionary:
	var model := BiomeDesignerModel.open(library_id, biome_id)
	if not model.valid():
		return {"ok": false, "error": model.error}
	var result := model.compile()
	if not result["ok"]:
		var errors: Array = (result["validation"] as Dictionary).get("errors", [])
		var why := String(errors[0]) if not errors.is_empty() else "the biome compiles to nothing"
		return {"ok": false, "error": "This biome cannot be opened in the designer: %s" % why}
	var report := LibraryRegistry.serve_draft(result["compiled"], model.context)
	if not report["ok"]:
		return {"ok": false, "error": String(report["error"])}
	var level := AuthoringController.new_level()
	level.level_name = PROVING_NAME % String(model.def.get("name", biome_id))
	var runtime_id := model.runtime_ids()[0]
	return {
		"ok": true,
		"error": "",
		"model": model,
		"runtime_id": runtime_id,
		"request":
		{
			"level": level,
			"new_map": {"proving_ground": runtime_id, "seed": ProvingGround.SEED},
			"designer": {"model": model},
			"return_to": &"title",
		},
	}


## Every biome the designer can open: [{library, library_name, biome, name, source, writable,
## official, version}] over the libraries served from a folder, official ones first.
static func designable() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in LibraryRegistry.list():
		if entry["status"] != LibraryResolver.OK or String(entry["folder"]) == "":
			continue
		for biome: Dictionary in entry["biomes"]:
			var writable := LibraryRegistry.designer_writable(entry["id"], entry["source"])
			out.append(
				{
					"library": entry["id"],
					"library_name": entry["name"],
					"biome": biome["id"],
					"name": biome["name"],
					"source": entry["source"],
					"writable": writable,
					"official": entry["official"],
					"version": entry["version"],
				}
			)
	return out


## "New biome from a core biome": creates the user collection `collection_id` holding a copy of
## `biome_id` of `library_id` (depending on that library for its plants) and serves it.
## Returns {ok, error, library, biome}.
static func new_from(
	library_id: String, biome_id: String, collection_id: String, collection_name: String
) -> Dictionary:
	var source := LibraryRegistry.designer_context(library_id)
	if not source.get("ok", false):
		return {"ok": false, "error": String(source.get("error", ""))}
	var model := BiomeDesignerModel.from_context(source, biome_id)
	if not model.valid():
		return {"ok": false, "error": model.error}
	var made := LibraryWriter.create_collection(
		LibraryRegistry.user_root, collection_id, collection_name, source, biome_id, model.def
	)
	if not made["ok"]:
		return {"ok": false, "error": String(made["error"])}
	var applied := FoliageLibrary.apply(FoliageLibrary.current(), FoliageLibrary.active_package())
	if not applied.get("ok", true):
		return {
			"ok": false, "error": String(applied.get("error", "the new collection did not load"))
		}
	return {"ok": true, "error": "", "library": collection_id, "biome": biome_id}
