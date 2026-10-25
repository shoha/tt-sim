class_name MapLibraryGate
extends RefCounted

## The step between reading a map document and building it: the libraries the map names are
## compared with the ones served now (MapLibraries.check). A map that matches is only given its
## renamed ids (a library's `aliases`). A map that names a library this game lacks, or has at
## another major version, is NEVER opened with a quiet substitution: the player is asked
## (ask_dialog, LibraryMismatchDialog: the collection's name and link, the version the map was
## saved with and why it is missing; the choices Cancel, Manage collections, Import file...,
## Import folder... and "Open without those collections"), and the last drops the rows of those
## libraries, points their biomes at the default biome and says so in a toast. An import from the
## dialog that succeeds ends the dialog with RETRY and run() checks the map again (the open is
## re-run with the new library served) before it asks again. MapSourceLoader.load_async runs it
## after the document is read, for authoring and for play alike; a loader with no `library_choice`
## set (a test, a tool) takes the first choice and still shows the toast, because the
## substitution is visible whichever way it was chosen. The words that name the content come from
## LibraryNames (no "plants").
##
## run() is a coroutine; ask_dialog() too (it waits for a button).

## Emitted by the dialog's buttons; one gate object per question.
signal chosen(proceed: bool)

## What a `choose` callable may return instead of a bool: a collection was installed from the
## dialog, check the map again.
const RETRY := "retry"
## How many times the question is asked again after an install (a guard, not a limit anyone meets).
const MAX_RETRIES := 8
const HINT := (
	"\n\nYou can open the map without them: their areas use the default place and stay empty"
	+ " until you paint them again. Nothing is changed until you save."
)


## Checks `doc` against the served libraries. `choose` is `func(report) -> bool` (a coroutine
## is fine; ask_dialog is the dialog), invalid to take "open without" at once. Returns
## {proceed (false when the player cancelled), changed (rows or ids of `doc` were changed, so
## its cells must be split again), report (MapLibraries.check's), dropped
## (MapLibraries.without_libraries's, {} when nothing was dropped), fetched (the library ids
## `fetch` installed). `fetch` is `func(doc) -> Dictionary` (a coroutine; LibraryTransferChannel.
## fetch_for_document on a client): it asks the host for the plants this install lacks, with the
## player's consent, BEFORE the check, so a library that arrived is served and the mismatch dialog
## only follows when the player skipped or the transfer failed.
static func run(
	doc: MapDocument,
	choose: Callable = Callable(),
	root: String = PaletteLibrary.DEFAULT_ROOT,
	fetch: Callable = Callable()
) -> Dictionary:
	var out := {"proceed": true, "changed": false, "report": {}, "dropped": {}, "fetched": []}
	out["changed"] = MapLibraries.apply_aliases(doc, root) > 0
	if fetch.is_valid():
		var got: Dictionary = await fetch.call(doc)
		out["fetched"] = got.get("installed", [])
		if not (out["fetched"] as Array).is_empty():
			out["changed"] = MapLibraries.apply_aliases(doc, root) > 0 or out["changed"]
	var report := MapLibraries.check(doc.libraries)
	out["report"] = report
	LibraryFromHost.note_open_map(MapLibraries.used_ids(doc))  # last-used stamps, never evicted
	for warning: String in report["warnings"]:
		print("MapLibraryGate: " + warning)
	if report["ok"]:
		return out
	if choose.is_valid():
		var proceed: Variant = await choose.call(report)
		var retries := 0
		while proceed is String and proceed == RETRY and retries < MAX_RETRIES:
			# A collection was installed from the dialog: the map is checked again against
			# what is served now, and the question only returns if something is still lacking.
			retries += 1
			out["changed"] = MapLibraries.apply_aliases(doc, root) > 0 or out["changed"]
			report = MapLibraries.check(doc.libraries)
			out["report"] = report
			if report["ok"]:
				return out
			proceed = await choose.call(report)
		if not (proceed is bool and proceed):
			out["proceed"] = false
			return out
	var fallback := fallback_biome(root)
	var dropped := MapLibraries.without_libraries(doc, report["blocked"], fallback)
	out["dropped"] = dropped
	out["changed"] = true
	var message := toast_text(report, dropped, fallback, root)
	print("MapLibraryGate: " + message.replace("\n", " "))
	UIManager.show_toast(message, UIManager.TOAST_INFO, 8.0)
	return out


## The biome id a missing library's areas fall back to: the served default biome when the
## palette has it, else the first core biome, else "" (the ids are then left as they were).
static func fallback_biome(root: String = PaletteLibrary.DEFAULT_ROOT) -> String:
	var wanted := LibraryBindings.default_biome()
	if PaletteLibrary.biome(wanted, root) != {}:
		return wanted
	for biome in PaletteLibrary.biomes(root):
		if LibraryIds.library_of(String(biome["id"])) == LibraryContracts.CORE_ID:
			return String(biome["id"])
	return ""


## The toast after "Open without those plants".
static func toast_text(
	report: Dictionary,
	dropped: Dictionary,
	fallback: String,
	root: String = PaletteLibrary.DEFAULT_ROOT
) -> String:
	var names: Array[String] = []
	for item: Dictionary in report["missing"]:
		names.append(String(item["name"]))
	for item: Dictionary in report["incompatible"]:
		names.append(String(item["id"]))
	var left_out: int = dropped.get("rows", 0)
	var text := (
		"Opened without %s from %s: %d left out"
		% [LibraryNames.lower(2), ", ".join(names), left_out]
	)
	if int(dropped.get("biomes", 0)) > 0 and fallback != "":
		text += "; %d areas now use %s" % [dropped["biomes"], _biome_name(fallback, root)]
	return text + "."


static func _biome_name(biome_id: String, root: String) -> String:
	var found := PaletteLibrary.biome(biome_id, root)
	return String(found.get("name", biome_id))


## The mismatch dialog (LibraryMismatchDialog) as a coroutine: true for "Open without those
## collections", RETRY after a collection was imported from the dialog (run() checks the map
## again), false for Cancel, Escape and closing the dialog, and for "Manage collections", which
## also opens the manager (LibraryManager, over the scrim) over the title the cancelled open
## returns to, so the missing collection can be added and the map opened again.
static func ask_dialog(report: Dictionary) -> Variant:
	return await LibraryMismatchDialog.ask(report)
