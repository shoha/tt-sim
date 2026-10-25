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
## is on; the built-in core ships inside the game and has no files to check.

const NOT_SERVED := "not_served"
const BUILTIN := "builtin"
const READY := "ready"


## {state (READY, NOT_SERVED or BUILTIN), assets: Array[String]} for library `library_id`.
static func plan(library_id: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> Dictionary:
	var info := LibraryRegistry.info(library_id, root)
	if info.is_empty() or not bool(info.get("served", false)):
		var builtin := String(info.get("source", "")) == "builtin"
		return {"state": BUILTIN if builtin else NOT_SERVED, "assets": [] as Array[String]}
	var assets := AssetStore.assets_of(library_id, root)
	return {"state": READY, "assets": assets}


## The check of one asset: {asset, ok, error}.
static func check(asset_id: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> Dictionary:
	var result := AssetStore.verify(asset_id, root)
	return {"asset": asset_id, "ok": bool(result["ok"]), "error": String(result["error"])}


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


## The asset id without its biome prefix ("alienworld__x_summer_s1/Tree" -> "Tree") for a list.
static func short_name(asset_id: String) -> String:
	return asset_id.get_slice("/", 1) if "/" in asset_id else asset_id
