class_name TerraCore
extends RefCounted
## The terraforming core's GDScript entry (docs/systems/terraform.md): finds the native derive,
## sizes its grid from a map document and loads the ground rule table.
##
## The core is a C++ class, TerraDerive, in the native library beside the scatter generator. It
## turns an ordered list of typed primitives (the terrain document) into every derived array of
## the map, by a fixed chain of stages over dirty tiles. GDScript never names the class as an
## identifier: it is found through ClassDB, so every script parses where the library is absent
## and every terra test shows as pending there.
##
## The derive grid is the map document's own frame, doubled: 2 (n - 1) + 1 samples per axis of
## the document's n, corner-aligned and centred, so every second derive sample is a document
## sample. Primitive positions are world metres in that frame (the origin is the map centre).
##
## Phase 1: the core runs in the game only behind its switch (enabled(): the project setting
## SWITCH_SETTING, default off), and then only as a TerraSession on a map that has a terrain
## section; nothing reads the session yet (docs/systems/terraform.md "The session").

## The native class's name, for ClassDB only.
const CLASS_NAME := "TerraDerive"
## The project setting that turns the core on for loaded maps (default false).
const SWITCH_SETTING := "tt_sim/terrain/core"
## What TerraDerive.version() must return; a library built from older sources fails the tests.
const NATIVE_VERSION := "terra 9 paint cache"
## The ground rule table (rows of [field, lo, hi, soft] terms, later rows over earlier ones).
const RULES_PATH := "res://utils/terraform/rules/ground_rules.json"
## Rule term fields by name, in the order of the native Field enum (terra_stages.h).
const FIELDS := {
	"depth": 0,
	"slope": 1,
	"dist_water": 2,
	"dist_path": 3,
	"dist_foot": 4,
	"wetness": 5,
	"paint": 6,
	"height": 7,
	"path_cov": 8,
	"curv": 9,
}

## The built-in kinds' ids, for code that names one. Each kind's script in the registry
## (TerraKinds, utils/terraform/kinds/) is its source and holds its float layout; test_terra_kinds
## checks that each of these equals its script's ID. 9 is the folded sculpt raster (SCULPT), 10 to
## 15 are reserved; new kinds start at 16.
const PLANE := 0
const HILL := 1
const RIDGE := 2
const STROKE := 3
const RIVER := 4
const POND := 5
const PATH := 6
const WALL := 7
const PAINT := 8
const SCULPT := 9

## The tests' override of the switch: null reads SWITCH_SETTING, true or false forces it.
static var switch_override: Variant = null
## TerraDerive instances made by make_derive_grid() since start-up (tests: the switch-off
## contract is that a load makes none).
static var derives_made := 0


## True when the native library holds TerraDerive at this version.
static func native_available() -> bool:
	if not ClassDB.class_exists(CLASS_NAME):
		return false
	var probe: RefCounted = ClassDB.instantiate(CLASS_NAME)
	return probe.call("version") == NATIVE_VERSION


## The switch that attaches the core to a loaded map (MapSourceLoader.add_terra_session): the
## project setting SWITCH_SETTING, default false, unless a test set switch_override.
static func enabled() -> bool:
	if switch_override is bool:
		return switch_override
	return bool(ProjectSettings.get_setting(SWITCH_SETTING, false))


## The derive grid of a map document: {"size": Vector2i samples per axis, "extent": Vector2
## metres}. Each axis has 2 (n - 1) + 1 samples, so the step is half the document's.
static func grid_for(doc: MapDocument) -> Dictionary:
	var n := Vector2i(doc.samples_x(), doc.samples_z())
	return {"size": Vector2i(2 * (n.x - 1) + 1, 2 * (n.y - 1) + 1), "extent": doc.extent_m()}


## A TerraDerive on the grid of `doc` with the ground rules set and no primitives, or null when
## the library is not built.
static func make_derive(doc: MapDocument) -> RefCounted:
	var gd := grid_for(doc)
	return make_derive_grid(gd["size"], gd["extent"])


## A TerraDerive on a `size` grid over a map of `extent` metres (tests and probes), or null.
static func make_derive_grid(size: Vector2i, extent: Vector2) -> RefCounted:
	if not native_available():
		return null
	var n: RefCounted = ClassDB.instantiate(CLASS_NAME)
	derives_made += 1
	n.call("setup", size.x, size.y, extent)
	n.call("set_rules", load_rules())
	return n


## The ground table from ground_rules.json, packed as TerraDerive.set_rules reads it: per row
## [class, term count, (field, lo, hi, soft) per term]; class -1 is the painted surface, and a
## null bound is unbounded.
static func load_rules() -> Array:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
	if not data is Dictionary:
		push_warning("TerraCore: %s is not a JSON object" % RULES_PATH)
		return []
	var classes: Array = []
	for c: Dictionary in data.get("classes", []):
		classes.append(c.get("name", ""))
	var rows: Array = []
	for row: Dictionary in data.get("rows", []):
		var cls: Variant = row.get("class", 0)
		var packed := PackedFloat32Array([-1.0 if cls is float else float(classes.find(cls))])
		var terms: Array = row.get("terms", [])
		packed.append(float(terms.size()))
		for t: Array in terms:
			packed.append(float(FIELDS[t[0]]))
			packed.append(-1e9 if t[1] == null else float(t[1]))
			packed.append(1e9 if t[2] == null else float(t[2]))
			packed.append(float(t[3]))
		rows.append(packed)
	return rows


## The class names of the ground table, in the order the control bytes index them.
static func class_names() -> PackedStringArray:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
	var out := PackedStringArray()
	if data is Dictionary:
		for c: Dictionary in data.get("classes", []):
			out.append(String(c.get("name", "")))
	return out
