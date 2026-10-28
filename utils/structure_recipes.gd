class_name StructureRecipes
extends RefCounted

## Turns a structure's recipe reference (`<library id>:<structure id>`, Structure.recipe) into the
## procgen document that builds it. Since card S3 the references are served by LibraryRegistry
## (the `structures/` kind of each library: `LibraryStructureStore.recipe`); this class parses
## the text, digests it (sha256 of the text, so a library update rebuilds) and clamps parameters.
## Lookup order: `resolver` (a Callable (ref: String) -> Dictionary {"text": the recipe's JSON text}
## or {} for an unknown reference; tests lay one), then the registry, then, only when
## `procgen_fallback` is on, the shared module's committed recipes (res://procgen/recipes/*.json,
## the S2 starter set; off in the game, on for a test that builds without serving libraries).
## An unknown reference gives null/"" and the caller shows a placeholder plot.
##
## A recipe is untrusted data whoever supplied it: document() refuses a text over the recipe caps
## (LibraryStructures.recipe_problem: bytes, nodes, connections, registered node types).
##
## Safe on any thread. Every call parses a fresh document (a document is never shared between
## evaluations); the built-in texts and digests are cached under a mutex.
##
## The starter set (design.md "Core starter set"): stone house (the building recipe, gable roof),
## cottage (timber), cottage with chimney and shutters, townhouse, townhouse with trim.
## Summary: docs/systems/structures.md.

const CORE_LIBRARY := "core"
## Local id -> {"name": the palette name, "file": the recipe under RECIPE_FOLDER}.
const CORE: Dictionary = {
	"stone_house": {"name": "Stone house", "file": "building"},
	"cottage": {"name": "Cottage", "file": "cottage"},
	"cottage_chimneyed": {"name": "Cottage with chimney", "file": "cottage_chimneyed"},
	"townhouse": {"name": "Townhouse", "file": "townhouse"},
	"townhouse_trimmed": {"name": "Townhouse, trimmed", "file": "townhouse_trimmed"},
}
const RECIPE_FOLDER := "res://procgen/recipes/"

## A Callable (reference: String) -> Dictionary {"text": String} that replaces every other source
## when valid (a test). {} or no "text" means the reference is unknown.
static var resolver: Callable = Callable()
## Read the S2 starter set from res://procgen/recipes when neither the resolver nor the registry
## knows a reference. Off in the game.
static var procgen_fallback: bool = false

static var _mutex := Mutex.new()
## Reference -> {"text": String, "digest": String}, only for built-in references.
static var _cache: Dictionary = {}


## Makes sure the libraries are served (the first read of the default palette serves them), so the
## registry holds the recipes before a worker asks for one. Call it on the main thread before
## building structures; it costs nothing once the libraries are served.
static func ensure_served() -> void:
	PaletteLibrary.get_palette()


## The references of the built-in starter set, in table order.
static func core_refs() -> PackedStringArray:
	var out := PackedStringArray()
	for local_id: String in CORE:
		out.append("%s:%s" % [CORE_LIBRARY, local_id])
	return out


## The recipe document for `ref`, or null when the reference is unknown or the text is not a graph.
static func document(ref: String) -> PlantGraphDocument:
	var text := text_of(ref)
	if text == "":
		return null
	var registry := ProcgenStructureRegistry.new()
	if LibraryStructures.recipe_problem(text, registry) != "":
		return null
	return PlantGraphDocument.from_json(text, registry)


## The digest of `ref`'s recipe text (sha256, hex), "" when unknown. A key part: a changed recipe
## rebuilds every instance.
static func digest(ref: String) -> String:
	var found := _find(ref)
	return String(found.get("digest", ""))


## The recipe text of `ref`, "" when unknown.
static func text_of(ref: String) -> String:
	var found := _find(ref)
	return String(found.get("text", ""))


## Whether `ref` resolves to a recipe text.
static func exists(ref: String) -> bool:
	return text_of(ref) != ""


## The values of `params` that `doc`'s interface declares, clamped to the declared range (a bool
## becomes 0 or 1); a name the interface lacks is dropped. The reader of a record keeps only a
## well formed name, so this is where an untrusted number meets the recipe's own limits.
static func clamp_params(doc: PlantGraphDocument, params: Dictionary) -> Dictionary:
	var out := {}
	for entry in doc.interface:
		var key := String(entry.get("name", ""))
		if not params.has(key):
			continue
		var value: Variant = params[key]
		var number := (1.0 if value else 0.0) if value is bool else float(value)
		var low := float(entry.get("min", -INF))
		var high := float(entry.get("max", INF))
		out[key] = clampf(number, low, high)
	return out


## Whether `doc` declares a parameter named `name`.
static func has_param(doc: PlantGraphDocument, param_name: String) -> bool:
	for entry in doc.interface:
		if String(entry.get("name", "")) == param_name:
			return true
	return false


static func _find(ref: String) -> Dictionary:
	if resolver.is_valid():
		var made: Variant = resolver.call(ref)
		if made is Dictionary and (made as Dictionary).has("text"):
			var text := String((made as Dictionary)["text"])
			return {"text": text, "digest": text.sha256_text()}
		return {}
	var served := LibraryStructureStore.recipe(ref)
	if not served.is_empty():
		return served
	if not procgen_fallback:
		return {}
	_mutex.lock()
	var cached: Variant = _cache.get(ref)
	_mutex.unlock()
	if cached is Dictionary:
		return cached
	var parts := LibraryIds.split_ref(ref)
	if parts.is_empty() or String(parts["library"]) != CORE_LIBRARY:
		return {}
	var entry: Variant = CORE.get(String(parts["local"]))
	if not entry is Dictionary:
		return {}
	var path := "%s%s.json" % [RECIPE_FOLDER, String((entry as Dictionary)["file"])]
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var found := {"text": text, "digest": text.sha256_text()}
	_mutex.lock()
	_cache[ref] = found
	_mutex.unlock()
	return found
