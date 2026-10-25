class_name MapLibraryGate
extends RefCounted

## The step between reading a map document and building it: the libraries the map names are
## compared with the ones served now (MapLibraries.check). A map that matches is only given its
## renamed ids (a library's `aliases`). A map that names a library this game lacks, or has at
## another major version, is NEVER opened with a quiet substitution: the player is asked
## (ask_dialog: the library's name, the version the map was saved with and why it is missing,
## and two choices, "Open without those plants" and "Cancel"), and "Open without those plants"
## drops the rows of those libraries, points their biomes at the default biome and says so in a
## toast. MapSourceLoader.load_async runs it after the document is read, for authoring and for
## play alike; a loader with no `library_choice` set (a test, a tool) takes the first choice
## and still shows the toast, because the substitution is visible whichever way it was chosen.
##
## run() is a coroutine; ask_dialog() too (it waits for a button).

## Emitted by the dialog's buttons; one gate object per question.
signal chosen(proceed: bool)

const TITLE := "This map needs plants you do not have"
const OPEN_WITHOUT := "Open without those plants"
const HINT := (
	"\n\nYou can open the map without them: their areas use the default place and stay empty"
	+ " until you paint them again. Nothing is changed until you save."
)


## Checks `doc` against the served libraries. `choose` is `func(report) -> bool` (a coroutine
## is fine; ask_dialog is the dialog), invalid to take "open without" at once. Returns
## {proceed (false when the player cancelled), changed (rows or ids of `doc` were changed, so
## its cells must be split again), report (MapLibraries.check's), dropped
## (MapLibraries.without_libraries's, {} when nothing was dropped)}.
static func run(
	doc: MapDocument, choose: Callable = Callable(), root: String = PaletteLibrary.DEFAULT_ROOT
) -> Dictionary:
	var out := {"proceed": true, "changed": false, "report": {}, "dropped": {}}
	out["changed"] = MapLibraries.apply_aliases(doc, root) > 0
	var report := MapLibraries.check(doc.libraries)
	out["report"] = report
	for warning: String in report["warnings"]:
		print("MapLibraryGate: " + warning)
	if report["ok"]:
		return out
	if choose.is_valid():
		var proceed: bool = await choose.call(report)
		if not proceed:
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
	var text := "Opened without plants from %s: %d left out" % [", ".join(names), left_out]
	if int(dropped.get("biomes", 0)) > 0 and fallback != "":
		text += "; %d areas now use %s" % [dropped["biomes"], _biome_name(fallback, root)]
	return text + "."


static func _biome_name(biome_id: String, root: String) -> String:
	var found := PaletteLibrary.biome(biome_id, root)
	return String(found.get("name", biome_id))


## The mismatch dialog (a UIManager confirmation) as a coroutine: true for "Open without those
## plants", false for Cancel, Escape and closing the dialog.
static func ask_dialog(report: Dictionary) -> bool:
	var gate := MapLibraryGate.new()
	var answered := [false]
	var settle := func(proceed: bool) -> void:
		if not answered[0]:
			answered[0] = true
			gate.chosen.emit(proceed)
	UIManager.show_confirmation(
		TITLE,
		MapLibraries.describe(report) + HINT,
		OPEN_WITHOUT,
		"Cancel",
		func() -> void: settle.call(true),
		func() -> void: settle.call(false)
	)
	return await gate.chosen
