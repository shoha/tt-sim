extends GutTest

## The core library's pipeline digests come out the same whichever way they are built (topic
## digest_split, 2026-10-30): the game and the tests build from the served library, the exporter
## (tools/export_core_structures.gd) from its own in-process copy, and a build must not depend on
## the order of the builds before it or on the state the process starts in. Three causes were
## found: a `--script` main script that compiles before the autoloads exist (StructureGeometry's
## `textured` initialiser never ran: nine houses at ten times the triangles); the exporter pinning
## a prop at the style's default footprint instead of the served one (yard_gate); and nothing
## comparing the two. docs/systems/structures.md "Determinism".

const RUN := "res://tools/export_core_structures_run.gd"
const PINS := "res://libraries/core/structures/pins.txt"
const PROP_PINS := "res://libraries/core/structures/prop_pins.txt"
const SAMPLE := [
	"house_flat",
	"house_hip",
	"stone_house",
	"townhouse",
	"townhouse_chimneyed",
	"townhouse_end",
	"townhouse_flat",
	"townhouse_hip",
	"townhouse_trimmed",
	"cottage",
	"windmill_dutch",
	"yurt",
	"yard_gate 0",
	"yard_gate 3",
]

var _saved_official: String = ""
var _saved_user: String = ""


func before_all() -> void:
	_saved_official = LibraryRegistry.official_root
	_saved_user = LibraryRegistry.user_root


func after_all() -> void:
	LibraryRegistry.official_root = _saved_official
	LibraryRegistry.user_root = _saved_user
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()


func before_each() -> void:
	LibraryRegistry.official_root = LibraryRegistry.OFFICIAL_ROOT
	LibraryRegistry.user_root = "user://test_core_pin_paths/no_user_libraries"
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryRegistry.apply(PaletteLibrary.DEFAULT_ROOT)


func after_each() -> void:
	StructureGeometry.textured = true
	StructureRecipes.resolver = Callable()


## The first `columns` cells of each non-empty line of `text`.
static func _cells(text: String, columns: int) -> PackedStringArray:
	var out := PackedStringArray()
	for line in text.replace("\r\n", "\n").strip_edges().split("\n"):
		out.append(" ".join(line.strip_edges().split(" ").slice(0, columns)))
	return out


## [ref, footprint, label] of every served structure (the 100 placeable) and prop draw (72), the
## label being the pins' leading cells ("<id>" or "<id> <seed>").
func _cases() -> Array[Array]:
	var out: Array[Array] = []
	for row in LibraryStructureStore.structures("core"):
		out.append([String(row["ref"]), StructurePlacement.pin_plan(row), String(row["id"])])
	for row in LibraryStructureStore.props("core"):
		var size: Array = row["default_size_m"]
		var plan := ProcgenProps.footprint(Vector2(float(size[0]), float(size[1])))
		for k in LibraryStructures.PROP_VARIANTS:
			var ref := String(LibraryStructureStore.prop(String(row["id"]), k)["ref"])
			out.append([ref, plan, "%s %d" % [row["id"], k]])
	return out


## label -> "<digest> <triangles>" of the cases built in `order` (indices into `cases`), one
## document, one process.
func _digests(cases: Array[Array], order: Array[int]) -> Dictionary:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var out := {}
	for index in order:
		var item: Array = cases[index]
		var parts := StructureGeometry.build_one(
			doc, Structure.make(1, String(item[0]), item[1] as PackedVector2Array, 5)
		)
		assert_eq(parts.problem, "", String(item[0]))
		out[String(item[2])] = (
			"%s %d" % [StructureGeometry.digest_of(parts), StructureGeometry.triangle_count(parts)]
		)
	return out


func test_every_structure_and_prop_digests_the_same_in_any_build_order() -> void:
	var cases := _cases()
	assert_eq(cases.size(), 172, "100 structures and 72 prop draws")
	var forward: Array[int] = []
	var backward: Array[int] = []
	var shuffled: Array[int] = []
	for i in cases.size():
		forward.append(i)
		backward.append(cases.size() - 1 - i)
		shuffled.append((i * 37) % cases.size())
	var first := _digests(cases, forward)
	var second := _digests(cases, backward)
	var third := _digests(cases, shuffled)
	var moved := PackedStringArray()
	for label: String in first:
		if second[label] != first[label] or third[label] != first[label]:
			moved.append(label)
	assert_eq(moved.size(), 0, "a build depends on the builds before it: %s" % ", ".join(moved))
	var pinned := {}
	# pins.txt: `<id> <digest> <triangles> <raw>`; prop_pins.txt: `<id> <seed> <digest> <triangles>
	# <raw>`.
	for line in _cells(FileAccess.get_file_as_string(PINS), 3):
		var cells := line.split(" ")
		pinned[cells[0]] = " ".join(cells.slice(1))
	for line in _cells(FileAccess.get_file_as_string(PROP_PINS), 4):
		var cells := line.split(" ")
		pinned["%s %s" % [cells[0], cells[1]]] = " ".join(cells.slice(2))
	for label: String in SAMPLE:
		assert_true(first.has(label), "%s is a served structure" % label)
	var off := PackedStringArray()
	for label: String in first:
		if pinned.get(label, "") != first[label]:
			off.append(label)
	assert_eq(off.size(), 0, "digests that are not the committed pins: %s" % ", ".join(off))


func test_the_exporters_build_path_pins_what_the_game_builds_whatever_state_it_starts_in() -> void:
	var runner: RefCounted = (load(RUN) as GDScript).new()
	for textured_at_start in [true, false]:
		StructureGeometry.textured = textured_at_start
		var made: Dictionary = runner._make()
		assert_eq(
			StructureGeometry.textured,
			textured_at_start,
			"the exporter puts `textured` back as it found it"
		)
		var files: Dictionary = made["files"]
		assert_eq(
			String(files[LibraryStructures.PINS_FILE]).strip_edges().split("\n").size(), 100
		)
		for item in [[LibraryStructures.PINS_FILE, PINS], ["structures/prop_pins.txt", PROP_PINS]]:
			var have := _cells(String(files[item[0]]), 5)
			var committed := _cells(FileAccess.get_file_as_string(String(item[1])), 5)
			assert_eq(have, committed, "%s as the exporter makes it" % item[0])
		assert_eq(
			(made["warnings"] as Array).size(), 0, "no warnings: %s" % str(made["warnings"])
		)


## The cause itself needs a `--script` process: GUT's own run has the autoloads, so a `--script`
## main script that cannot compile its dependencies passes every test above. This starts the
## exporter as a tool is started and checks the shipped library against it.
func test_the_exporter_run_as_a_script_finds_the_shipped_structures_unchanged() -> void:
	var godot := OS.get_executable_path()
	var out: Array = []
	var code := OS.execute(
		godot,
		[
			"--headless",
			"--path",
			ProjectSettings.globalize_path("res://"),
			"--script",
			"res://tools/export_core_structures.gd",
			"--",
			"--out",
			ProjectSettings.globalize_path("res://libraries/core"),
			"--check",
			"1",
		],
		out,
		true
	)
	if code == -1:
		pending("the engine could not be started from the tests")
		return
	var text := "\n".join(PackedStringArray(out.map(func(item: Variant) -> String: return str(item))))
	var differing := PackedStringArray()
	for line in text.split("\n"):
		if line.begins_with("differs:"):
			differing.append(line)
	assert_eq(differing.size(), 0, "files the script run makes differently: %s" % str(differing))
	assert_eq(code, 0, "the exporter's --check 1 exits clean")
