class_name BridgeEval
extends RefCounted

## Expression evaluation and JSON-safe serialization for the validation bridge.
##
## Lets an agent read any value out of the running game without editing the bridge and recompiling,
## which was previously required for every new field worth observing. The fixed state snapshot
## (tokens, camera, UI) stays as the curated common case; this is the escape hatch for everything
## else.
##
## Only reachable when the game was launched with `-- --validation-bridge`, so it never exists in a
## release build. Godot's Expression cannot declare variables, loop, or assign, which bounds what a
## malformed expression can do to the running game, but it CAN call methods on the base instance --
## this is a development tool and is not a security boundary.

## How deep nested containers are walked before bailing out. Deep object graphs are rarely what the
## caller wanted and cheaply blow up the response size.
const MAX_DEPTH: int = 4

## How many array entries are reported before truncating with a count of the remainder.
const MAX_ARRAY_ITEMS: int = 50


## Parses and runs `text` with `base_instance` as `self`.
##
## Returns `{ok: false, error: String}` on a parse or execution failure, otherwise
## `{ok: true, value: Variant, truthy: bool}` where `value` is the JSON-safe rendering of the
## result and `truthy` is GDScript's own truthiness of the RAW result, computed before
## serialization. Callers wanting to branch on the result -- `step_until` above all -- must use
## `truthy` and never re-derive it from `value`: `to_json_safe` renders `Vector2.ZERO` and the
## default `Color` as non-empty Dictionaries, which are truthy where the values themselves are
## false.
static func evaluate(text: String, base_instance: Object) -> Dictionary:
	var expression := Expression.new()
	if expression.parse(text) != OK:
		return {"ok": false, "error": "Parse error: %s" % expression.get_error_text()}
	var result: Variant = expression.execute([], base_instance, false)
	if expression.has_execute_failed():
		return {"ok": false, "error": "Execution failed: %s" % expression.get_error_text()}
	return {"ok": true, "value": to_json_safe(result, 0), "truthy": is_truthy(result)}


## GDScript's own truthiness for an arbitrary Variant.
##
## Delegating to `if value:` rather than comparing against literals is deliberate: comparing
## mismatched Variant types (a bool against an int, say) is a runtime script error in GDScript, not
## a clean "not equal", so a hand-rolled `value != false and value != 0` throws on every value that
## is not already a bool. Going through `if` also gives callers the contract they should expect --
## an empty String, Array or Dictionary is false, exactly as `if` would treat it, not merely "not
## null". A caller meaning "exists at all" rather than "is non-empty" should write an explicit size
## check instead of relying on this.
static func is_truthy(value: Variant) -> bool:
	if value:
		return true
	return false


## Converts an arbitrary Variant into something JSON.stringify can encode without losing meaning.
##
## Godot's JSON encoder turns Vector3, Color and Object into opaque strings or nulls, which is
## exactly the information an agent inspecting a running game needs. Each of those gets an explicit
## shape here instead.
static func to_json_safe(value: Variant, depth: int) -> Variant:
	var type := typeof(value)

	if type == TYPE_NIL or type == TYPE_BOOL or type == TYPE_INT or type == TYPE_FLOAT:
		return value
	if type == TYPE_STRING or type == TYPE_STRING_NAME or type == TYPE_NODE_PATH:
		return str(value)
	if type == TYPE_VECTOR2 or type == TYPE_VECTOR2I:
		# Constructed rather than assigned to a typed var: the integer variants are separate types,
		# and going through the constructor converts both without relying on implicit coercion.
		var v2 := Vector2(value)
		return {"x": v2.x, "y": v2.y}
	if type == TYPE_VECTOR3 or type == TYPE_VECTOR3I:
		var v3 := Vector3(value)
		return {"x": v3.x, "y": v3.y, "z": v3.z}
	if type == TYPE_COLOR:
		var color: Color = value
		return {"r": color.r, "g": color.g, "b": color.b, "a": color.a}

	if depth >= MAX_DEPTH:
		return "<max depth>"

	if type == TYPE_ARRAY:
		var source: Array = value
		var out: Array = []
		var limit := mini(source.size(), MAX_ARRAY_ITEMS)
		for i in range(limit):
			out.append(to_json_safe(source[i], depth + 1))
		if source.size() > limit:
			out.append("... (%d more)" % (source.size() - limit))
		return out

	if type == TYPE_DICTIONARY:
		var source_dict: Dictionary = value
		var out_dict: Dictionary = {}
		for key: Variant in source_dict:
			out_dict[str(key)] = to_json_safe(source_dict[key], depth + 1)
		return out_dict

	if type == TYPE_OBJECT:
		var obj: Object = value
		if obj == null:
			return null
		if obj is Node:
			var node: Node = obj
			return {"node": str(node.get_path()), "type": node.get_class()}
		return {"object": obj.get_class()}

	return str(value)
