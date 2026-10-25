class_name DesignerPatch
extends RefCounted

## Small reversible edits of a JSON-like document (the designer's draft biome-def). The undo
## stack of the biome designer is a list of these patches, so an edit costs the bytes it changed
## and not a copy of a 120-rule biome. Pure: apply() changes the dictionary it is given and
## returns the patch that undoes what it did.
##
## An op is a Dictionary:
##   {"op": "set", "path": [...], "value": v}       a key of a dictionary or an index of an array
##   {"op": "erase", "path": [...]}                 a key of a dictionary
##   {"op": "insert", "path": [...], "index": i, "value": v}   into the array at `path`
##   {"op": "remove", "path": [...], "index": i}    out of the array at `path`
##   {"op": "move", "path": [...], "from": i, "to": j}   inside the array at `path`
## `path` items are keys (String) and indices (int) from the document root. Values are deep
## copied in and out, so a patch never shares structure with the document.


## Applies `ops` in order and returns the ops that undo them (already in the order to apply).
static func apply(doc: Dictionary, ops: Array) -> Array:
	var inverse: Array = []
	for op: Dictionary in ops:
		inverse.push_front(_apply_one(doc, op))
	return inverse


## `op` as a convenience builder: set a value at a path.
static func set_op(path: Array, value: Variant) -> Dictionary:
	return {"op": "set", "path": path, "value": value}


static func erase_op(path: Array) -> Dictionary:
	return {"op": "erase", "path": path}


static func insert_op(path: Array, index: int, value: Variant) -> Dictionary:
	return {"op": "insert", "path": path, "index": index, "value": value}


static func remove_op(path: Array, index: int) -> Dictionary:
	return {"op": "remove", "path": path, "index": index}


static func move_op(path: Array, from_index: int, to_index: int) -> Dictionary:
	return {"op": "move", "path": path, "from": from_index, "to": to_index}


## The value at `path`, or `fallback` when the path leads nowhere.
static func get_at(doc: Variant, path: Array, fallback: Variant = null) -> Variant:
	var here: Variant = doc
	for step: Variant in path:
		if step is int and here is Array and step >= 0 and step < (here as Array).size():
			here = (here as Array)[step]
		elif step is String and here is Dictionary and (here as Dictionary).has(step):
			here = (here as Dictionary)[step]
		else:
			return fallback
	return here


static func _apply_one(doc: Dictionary, op: Dictionary) -> Dictionary:
	var path: Array = op["path"]
	match String(op["op"]):
		"set":
			return _put(doc, path, op["value"])
		"erase":
			return _take(doc, path)
		"insert":
			var target: Variant = _container(doc, path)
			if target is Array:
				var index := clampi(int(op["index"]), 0, (target as Array).size())
				(target as Array).insert(index, _copy(op["value"]))
				return remove_op(path, index)
		"remove":
			var target: Variant = _container(doc, path)
			var index := int(op["index"])
			if target is Array and index >= 0 and index < (target as Array).size():
				var old: Variant = (target as Array)[index]
				(target as Array).remove_at(index)
				return insert_op(path, index, old)
		"move":
			var target: Variant = _container(doc, path)
			var from_index := int(op["from"])
			var to_index := int(op["to"])
			if target is Array and from_index >= 0 and from_index < (target as Array).size():
				var item: Variant = (target as Array)[from_index]
				(target as Array).remove_at(from_index)
				to_index = clampi(to_index, 0, (target as Array).size())
				(target as Array).insert(to_index, item)
				return move_op(path, to_index, from_index)
	return {"op": "noop", "path": []}


static func _put(doc: Dictionary, path: Array, value: Variant) -> Dictionary:
	var parent: Variant = _container(doc, path.slice(0, path.size() - 1))
	var last: Variant = path[path.size() - 1]
	if parent is Dictionary and last is String:
		var existed: bool = (parent as Dictionary).has(last)
		var old: Variant = (parent as Dictionary).get(last)
		(parent as Dictionary)[last] = _copy(value)
		return set_op(path, old) if existed else erase_op(path)
	if parent is Array and last is int and last >= 0 and last < (parent as Array).size():
		var old_item: Variant = (parent as Array)[last]
		(parent as Array)[last] = _copy(value)
		return set_op(path, old_item)
	return {"op": "noop", "path": []}


static func _take(doc: Dictionary, path: Array) -> Dictionary:
	var parent: Variant = _container(doc, path.slice(0, path.size() - 1))
	var last: Variant = path[path.size() - 1]
	if parent is Dictionary and last is String and (parent as Dictionary).has(last):
		var old: Variant = (parent as Dictionary)[last]
		(parent as Dictionary).erase(last)
		return set_op(path, old)
	return {"op": "noop", "path": []}


## The array or dictionary at `path` (the root for an empty path), or null.
static func _container(doc: Variant, path: Array) -> Variant:
	var here: Variant = get_at(doc, path)
	return here if here is Dictionary or here is Array else null


static func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value
