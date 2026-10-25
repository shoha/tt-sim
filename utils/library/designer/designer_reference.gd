class_name DesignerReference
extends RefCounted

## What the designer's A/B view can compare the draft with (step S9): the SAVED version of the
## same biome (the draft as last saved, compiled under a runtime id of its own so both stand in the
## palette at once), another SEASON of the draft, or ANOTHER BIOME of any served library. A
## reference is a Dictionary {kind ("saved", "season", "biome"), label, runtime (the palette biome
## id it is drawn from; "" for "saved" until compile_saved gives it one), season/library/biome
## where they apply}. Pure over the model and the registry's listing: no nodes.

## The seed a saved-version compile uses, counted up from here until no season of the draft has
## it, so its runtime id (`<biome>_<season>_s<seed>`) never clashes with a real season.
const SEED_BASE := 9000


## The references offered for the draft's current season `season`: the saved version, the other
## seasons, then every other biome served from a library (core's first).
static func options(model: BiomeDesignerModel, season: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"kind": "saved", "label": "Saved version of this biome", "runtime": ""})
	var seasons := model.season_ids()
	var runtime := model.runtime_ids()
	for i in seasons.size():
		if seasons[i] != season:
			out.append(
				{
					"kind": "season",
					"label": "This biome in %s" % seasons[i].capitalize(),
					"runtime": runtime[i],
					"season": seasons[i],
				}
			)
	for entry in LibraryRegistry.list():
		if entry["status"] != LibraryResolver.OK:
			continue
		var first := {}
		for id: String in entry["biome_ids"]:
			var local := String(LibraryIds.parse_runtime_biome(id).get("biome", ""))
			if local != "" and not first.has(local):
				first[local] = id
		for biome: Dictionary in entry["biomes"]:
			var id := String(biome["id"])
			if not first.has(id) or (entry["id"] == model.library_id and id == model.biome_id):
				continue
			out.append(
				{
					"kind": "biome",
					"label": "%s (%s)" % [biome["name"], entry["name"]],
					"runtime": first[id],
					"library": entry["id"],
					"biome": id,
				}
			)
	return out


## The seed the saved version is compiled under.
static func saved_seed(model: BiomeDesignerModel) -> int:
	var taken := {}
	for season: Dictionary in model.season_list():
		taken[int(season.get("seed", 1))] = true
	var seed_value := SEED_BASE
	while taken.has(seed_value):
		seed_value += 1
	return seed_value


## Compiles the saved version of the draft's biome for season `season` under its own runtime id:
## {ok, compiled (BiomeCompiler's result), runtime (the palette biome id), warnings}. The season
## keeps its overrides; the other seasons are left out (the view shows one).
static func compile_saved(model: BiomeDesignerModel, season: String) -> Dictionary:
	var def := model.saved_def()
	var kept: Array = []
	for item: Dictionary in def.get("seasons", BiomeDesignerModel.SEASON_DEFAULT):
		if item["id"] == season:
			var copy := item.duplicate(true)
			copy["seed"] = saved_seed(model)
			kept.append(copy)
	if kept.is_empty():
		return {"ok": false, "compiled": {}, "runtime": "", "warnings": []}
	def["seasons"] = kept
	var read: Dictionary = (model.context["read"] as Dictionary).duplicate()
	read["biomes"] = [{"file": model.biome_id + ".json", "def": def}]
	read["locks"] = {model.biome_id: {"rules": model.saved_locks()}}
	var compiled := (
		BiomeCompiler
		. compile(
			read,
			{
				"folder": model.folder,
				"surfaces": model.context["surfaces"],
				"hash": String(model.context["hash"]),
				"files": model.context["files"],
				"dependencies": model.context["dependencies"],
			}
		)
	)
	var ids: Array = compiled["biome_ids"]
	return {
		"ok": not ids.is_empty(),
		"compiled": compiled,
		"runtime": String(ids[0]) if not ids.is_empty() else "",
		"warnings": compiled["warnings"],
	}
