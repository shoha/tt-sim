class_name DesignerValidation
extends RefCounted

## Sorts the validators' lines about a draft biome (LibraryReader.check_biome's errors and
## warnings, BiomeCompiler's and PaletteLibrary.validate_palette's warnings) into the places
## the designer shows them: per rule and per field, or about the biome as a whole. Pure; the
## lines are the validators' own text, so a message here is never a second opinion.
##
## A report is {errors: Array[String], warnings: Array[String], by_rule: {rule key: Array of
## {field, level ("error" or "warning"), message}}, general: Array of {level, message}}.

const FIELDS: Array[String] = [
	"density_per_m2",
	"density_factor",
	"spacing_m",
	"slope_max_deg",
	"slope_min_deg",
	"response",
	"scale_spread",
	"scale_floor",
	"yaw_random_deg",
	"align",
	"pattern",
	"clump",
	"near",
	"avoid",
	"avoid_bare",
	"keep_colour",
	"habit",
	"weight",
	"size_class",
	"role",
	"seasons",
	"query",
	"key",
]
const RULE_PATTERNS: Array[String] = ["rule '([^']+)'", " rule ([^ :]+):", "species '([^']+)'"]

static var _rule_expressions: Array[RegEx] = []


## A report from the validators' lines. `compile_warnings` are BiomeCompiler's and
## validate_palette's (the latter prefixed "palette: " by the registry).
static func report(
	errors: Array[String], warnings: Array[String], compile_warnings: Array[String] = []
) -> Dictionary:
	var out := {
		"errors": errors.duplicate(),
		"warnings": warnings.duplicate(),
		"by_rule": {},
		"general": [],
	}
	for line in errors:
		_file(out, line, "error")
	for line in warnings:
		_file(out, line, "warning")
	for line in compile_warnings:
		out["warnings"].append(line)
		_file(out, line, "warning")
	return out


## The lines about one rule.
static func for_rule(validation: Dictionary, key: String) -> Array:
	return (validation.get("by_rule", {}) as Dictionary).get(key, [])


## The lines about one field of one rule.
static func for_field(validation: Dictionary, key: String, field: String) -> Array:
	var out: Array = []
	for item: Dictionary in for_rule(validation, key):
		if item["field"] == field:
			out.append(item)
	return out


## Whether the report holds an error about rule `key` (any field when `field` is "").
static func has_error(validation: Dictionary, key: String, field: String = "") -> bool:
	for item: Dictionary in for_rule(validation, key):
		if item["level"] == "error" and (field == "" or item["field"] == field):
			return true
	return false


## The field a message is about: the first field name it contains as a word, "" when none.
static func field_of(message: String) -> String:
	var body := message.get_slice(": ", message.count(": ")) if ": " in message else message
	var best := ""
	var best_at := 1 << 30
	for field in FIELDS:
		var at := _word_at(body, field)
		if at >= 0 and at < best_at:
			best = field
			best_at = at
	if best == "" and (" asset" in body or " ref " in body or "catalog" in body or "pin " in body):
		return "query"
	return best


## The rule key a message names, "" for a line about the biome.
static func rule_of(message: String) -> String:
	if _rule_expressions.is_empty():
		for pattern in RULE_PATTERNS:
			_rule_expressions.append(RegEx.create_from_string(pattern))
	for expression in _rule_expressions:
		var found := expression.search(message)
		if found != null:
			return found.get_string(1)
	return ""


static func _file(out: Dictionary, line: String, level: String) -> void:
	var key := rule_of(line)
	var item := {"field": field_of(line), "level": level, "message": line}
	if key == "":
		(out["general"] as Array).append({"level": level, "message": line})
		return
	var by_rule: Dictionary = out["by_rule"]
	var held: Array = by_rule.get(key, [])
	held.append(item)
	by_rule[key] = held


## The index of `word` in `text` where it stands alone, or -1.
static func _word_at(text: String, word: String) -> int:
	var from := 0
	while true:
		var at := text.find(word, from)
		if at < 0:
			return -1
		var before := at == 0 or not _is_word_char(text.unicode_at(at - 1))
		var end := at + word.length()
		var after := end >= text.length() or not _is_word_char(text.unicode_at(end))
		if before and after:
			return at
		from = at + 1
	return -1


static func _is_word_char(code: int) -> bool:
	return (
		(code >= 48 and code <= 57)
		or (code >= 65 and code <= 90)
		or code == 95
		or (code >= 97 and code <= 122)
	)
