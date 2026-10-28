class_name LibraryVerify
extends RefCounted

## The manager's Verify: AssetStore.verify over every GLB a served library supplies, one asset at
## a time so the UI can show progress, cancel and keep drawing frames. Pure over the store (no
## scene tree): the manager decides how many assets it checks per frame.
##
## What a check covers is AssetStore.verify's: the file is there, within the size cap, matches the
## catalog's byte count and sha256 (also for an official library, which load skips) and passes
## GlbGuard (container, no external uri, embedded textures within the caps). A library that is
## not served (turned off, or failing) has nothing registered, so it cannot be checked until it
## is on. Core is checked like any other library (its GLBs are files of the pack).

const NOT_SERVED := "not_served"
const READY := "ready"
## A structure of the library is listed among the assets as `structure:<library>:<id>`; its check
## builds the recipe at the index entry's default footprint on flat ground.
const STRUCTURE_PREFIX := "structure:"
## A recipe that builds over this many triangles or takes longer than this many milliseconds at
## its default footprint fails the check (design.md "Registry and checks"). The palette would
## refuse it; the library manager shows it.
const STRUCTURE_MAX_TRIANGLES := 60000
const STRUCTURE_MAX_MSEC := 400.0
## The flat map a structure is built on, in cells (wide enough for the widest footprint).
const STRUCTURE_MAP_CELLS := Vector2i(64, 64)
const STRUCTURE_SEED := 5


## {state (READY or NOT_SERVED), assets: Array[String]} for library `library_id`: its asset ids,
## then `structure:<ref>` for each structure.
static func plan(library_id: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> Dictionary:
	var info := LibraryRegistry.info(library_id, root)
	if info.is_empty() or not bool(info.get("served", false)):
		return {"state": NOT_SERVED, "assets": [] as Array[String]}
	var assets := AssetStore.assets_of(library_id, root)
	for row in LibraryStructureStore.structures(library_id):
		assets.append(STRUCTURE_PREFIX + String(row["ref"]))
	return {"state": READY, "assets": assets}


## The check of one asset: {asset, ok, error}. A structure's result also holds triangles and msec.
static func check(asset_id: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> Dictionary:
	if asset_id.begins_with(STRUCTURE_PREFIX):
		return check_structure(asset_id)
	var result := AssetStore.verify(asset_id, root)
	return {"asset": asset_id, "ok": bool(result["ok"]), "error": String(result["error"])}


## The check of `item` (`structure:<ref>`): the recipe builds at the entry's default footprint
## (no placeholder, no problem), within the triangle and time budgets. {asset, ok, error,
## triangles, msec}.
static func check_structure(item: String) -> Dictionary:
	var ref := item.trim_prefix(STRUCTURE_PREFIX)
	var out := {"asset": item, "ok": false, "error": "", "triangles": 0, "msec": 0.0}
	var row := LibraryStructureStore.structure(ref)
	if row.is_empty():
		out["error"] = "structure %s is not served" % ref
		return out
	var size: Array = row["default_size_m"]
	var doc := MapDocument.create_flat(STRUCTURE_MAP_CELLS, "grass", "v", STRUCTURE_SEED)
	var half := Vector2(float(size[0]), float(size[1])) * 0.5
	var plan := PackedVector2Array(
		[
			Vector2(-half.x, -half.y),
			Vector2(half.x, -half.y),
			Vector2(half.x, half.y),
			Vector2(-half.x, half.y)
		]
	)
	var started := Time.get_ticks_usec()
	var parts := StructureGeometry.build_one(doc, Structure.make(1, ref, plan, STRUCTURE_SEED))
	out["msec"] = float(Time.get_ticks_usec() - started) / 1000.0
	out["triangles"] = int(parts["triangles"])
	if String(parts["problem"]) != "":
		out["error"] = "recipe did not build: %s" % parts["problem"]
	elif int(out["triangles"]) > STRUCTURE_MAX_TRIANGLES:
		out["error"] = (
			"recipe builds %d triangles (over %d)" % [out["triangles"], STRUCTURE_MAX_TRIANGLES]
		)
	elif float(out["msec"]) > STRUCTURE_MAX_MSEC:
		out["error"] = (
			"recipe takes %.0f ms to build (over %.0f)" % [out["msec"], STRUCTURE_MAX_MSEC]
		)
	out["ok"] = String(out["error"]) == ""
	return out


## {checked, failed (the failing results), ok (nothing failed)} over a list of check() results.
static func summarize(results: Array) -> Dictionary:
	var failed: Array[Dictionary] = []
	for result: Dictionary in results:
		if not bool(result["ok"]):
			failed.append(result)
	return {"checked": results.size(), "failed": failed, "ok": failed.is_empty()}


## One line for a summary: "All 12 files check out." or "3 of 12 files have a problem."
static func summary_text(summary: Dictionary) -> String:
	var checked := int(summary["checked"])
	var bad := (summary["failed"] as Array).size()
	if checked == 0:
		return "There are no files to check."
	if bad == 0:
		return "All %d %s check out." % [checked, "file" if checked == 1 else "files"]
	return "%d of %d files have a problem." % [bad, checked]


## A check's `error` in a player's words: no sha256, no catalog (review UX-3). The original text
## stays available to the caller (a tooltip).
static func plain_error(error: String) -> String:
	var lowered := error.to_lower()
	if lowered.begins_with("recipe") or "structure" in lowered:
		return "this building recipe does not build well"
	if "sha256" in lowered or "byte" in lowered or "size" in lowered:
		return "this file has changed or is damaged"
	if "missing" in lowered or "not found" in lowered or "no such" in lowered or "open" in lowered:
		return "this file is missing"
	if "external" in lowered or "texture" in lowered or "container" in lowered:
		return "this file is not a safe model"
	return "this file did not pass the check"


## The asset id without its biome prefix ("alienworld__x_summer_s1/Tree" -> "Tree") for a list.
static func short_name(asset_id: String) -> String:
	if asset_id.begins_with(STRUCTURE_PREFIX):
		return asset_id.get_slice(":", 2)
	return asset_id.get_slice("/", 1) if "/" in asset_id else asset_id
