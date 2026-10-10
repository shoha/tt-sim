extends RefCounted

## Probe codec for live map edits (tier b of the v0.2 live-edits design; findings in
## docs/plans/2026-10-09-v0.2-evaluation/probes/live_edits_probe.md, local): one
## AuthoringHistory entry's redo side as a plain-value op that crosses the network as bytes,
## and back, with the bytes read as untrusted input the way MapDocumentIO reads a document. A
## peer applies a decoded op through the same redo method on its own AuthoringEditor
## (apply()), so its document ends as the host's by construction; derived geometry (terrain
## chunks, water, crossings, scatter) is rebuilt there.
##
## An op is {"v": VERSION, "kind": one of KINDS, "args": Array}. Only the after side travels:
## diffs keep their "after" blocks, records their *_after fields (an undo is the before side,
## sent as one more op). Objects never travel (bytes_to_var refuses them): water bodies and
## crossings go in the document's JSON forms and come back through MapWaterIO's and
## MapCrossingIO's own readers and rules.
##
## decode() checks everything before anything is applied: the byte cap, the shape and type of
## every field (a fresh op is built from the checked values, nothing is passed through),
## rectangles inside the sample grid, mask names against the masks a stroke writes (apply_diff
## sets the named property), every compressed block decompressing to exactly its rectangle's
## size (the size comes from the rectangle, never from the payload), slot bytes naming a biome
## in the list, finite heights within MapDocument's range, rows MapDocumentIO would accept and
## that lie in the cell they are filed under, and biome, surface and asset ids the palette has.

const VERSION := 1
## Largest payload decode() reads. Steam drops reliable messages past about 512 KB queued; a
## channel would chunk anything bigger.
const MAX_BYTES := 256 * 1024
const KINDS: Array[String] = ["mask", "surface", "height", "water", "crossings", "props"]
## The masks a MaskStroke writes; a diff naming any other property is refused.
const MASKS: Array[String] = ["biome_slots", "biome_density", "erase_mask"]
## Bytes per sample of a surface diff block (two RGBA8 planes), a heights block (float32)
## and the wet dressing (RGBA8).
const SURFACE_BYTES := 8
const HEIGHT_BYTES := 4
const DRESSING_BYTES := 4
## Rows one op may carry, over all its cells.
const MAX_OP_ROWS := 200000
const COMPRESSION := FileAccess.COMPRESSION_ZSTD


## The after side of history entry `entry` ({"label", "undo", "redo"}) as an op, or {} when
## its redo is not one of the editor's apply methods this codec knows.
static func op_of(entry: Dictionary) -> Dictionary:
	var redo: Callable = entry.get("redo", Callable())
	if not redo.is_valid():
		return {}
	var target := redo.get_object()
	var method := String(redo.get_method())
	var args := redo.get_bound_arguments()
	var key := method
	if target is WaterEditor:
		key = "water." + method
	elif target is CrossingEditor:
		key = "crossings." + method
	elif not target is AuthoringEditor:
		key = ""
	var op := {}
	match key:
		"_apply_diff":
			op = _op("mask", [_diff_after(args[0])])
		"_apply_surface_diff":
			op = _op("surface", [_diff_after(args[0])])
		"_apply_height_diff":
			op = _op("height", [_diff_after(args[0]), _record_after(args[2])])
		"_set_prop_cell":
			op = _op("props", [args[0], args[1]])
		"water._apply":
			op = _op("water", [_diff_after(args[0]), _record_after(args[2])])
		"crossings._apply":
			op = _op("crossings", [_crossings_json(args[0]), args[1]])
	return op


## `op` as bytes (no objects inside: op_of() turned them into their JSON forms).
static func encode(op: Dictionary) -> PackedByteArray:
	return var_to_bytes(op)


## Reads untrusted `bytes` against `doc` (the receiving peer's document): {"op": a fresh op
## with water bodies and crossings rebuilt, ready for apply(), "problem": ""}, or {"op": {},
## "problem": why it was refused}.
static func decode(bytes: PackedByteArray, doc: MapDocument) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_BYTES:
		return _refused("%d bytes, outside 1..%d" % [bytes.size(), MAX_BYTES])
	var value: Variant = bytes_to_var(bytes)
	if not value is Dictionary:
		return _refused("not an op")
	var version: Variant = value.get("v")
	var kind: Variant = value.get("kind")
	var args: Variant = value.get("args")
	if not version is int or version != VERSION:
		return _refused("not a version %d op" % VERSION)
	if not kind is String or not KINDS.has(kind) or not args is Array:
		return _refused("unknown kind, or no argument list")
	var reader := _Reader.new(doc)
	var checked := reader.read(kind, args)
	if reader.problem != "":
		return _refused(reader.problem)
	return {"op": _op(kind, checked), "problem": ""}


## Applies a decoded op to `editor` (the peer's) through the redo method the host's history
## entry calls.
static func apply(op: Dictionary, editor: AuthoringEditor) -> void:
	var args: Array = op.args
	match String(op.kind):
		"mask":
			editor._apply_diff(args[0], true)
		"surface":
			editor._apply_surface_diff(args[0], true)
		"height":
			editor._apply_height_diff(args[0], true, args[1])
		"water":
			editor.water._apply(args[0], true, args[1])
		"crossings":
			editor.crossings._apply(args[0], args[1])
		"props":
			editor._set_prop_cell(args[0], args[1])


static func _op(kind: String, args: Array) -> Dictionary:
	return {"v": VERSION, "kind": kind, "args": args}


static func _refused(why: String) -> Dictionary:
	return {"op": {}, "problem": why}


## A stroke diff (MaskStroke, SurfaceStroke, HeightStroke) without its before blocks.
static func _diff_after(diff: Dictionary) -> Dictionary:
	var out := {}
	for key in diff:
		if key != "blocks" and key != "bytes":
			out[key] = diff[key]
	var blocks: Array = []
	for block: Dictionary in diff.get("blocks", []):
		blocks.append({"rect": block.rect, "after": block.after})
	out["blocks"] = blocks
	return out


## A sculpt or water edit record without its before sides, objects as JSON forms.
static func _record_after(record: Dictionary) -> Dictionary:
	var out := {"props_after": record.get("props_after", {}), "kept": record.get("kept", {})}
	var followed: Dictionary = record.get("crossings", {})
	out["crossings"] = (
		{} if followed.is_empty()
		else {"after": _crossings_json(followed.after), "area": followed.area}
	)
	if record.has("water_after"):
		var model: Dictionary = record.water_after
		var bodies: Array = []
		for body: WaterBody in model.get("bodies", []):
			bodies.append(MapWaterIO._body_json(body))
		out["water_after"] = {
			"bodies": bodies, "pond_mask": model.pond_mask, "pond_size": model.pond_size
		}
		out["dressing_after"] = record.dressing_after
		out["region"] = record.region
	return out


static func _crossings_json(list: Array) -> Array:
	var out: Array = []
	for crossing: Crossing in list:
		out.append(MapCrossingIO._crossing_json(crossing))
	return out


## Checks one op's arguments against a document, building fresh values; the first problem
## found is kept in `problem` and the rest of the read is skipped.
class _Reader:
	var problem: String = ""
	var doc: MapDocument = null
	var grid: Rect2i = Rect2i()
	var _biomes: Dictionary = {}
	var _surfaces: Dictionary = {}
	## biome id -> {asset id: true}.
	var _assets: Dictionary = {}
	## Row floats read so far, against MAX_OP_ROWS.
	var _floats: int = 0

	func _init(document: MapDocument) -> void:
		doc = document
		grid = Rect2i(0, 0, doc.samples_x(), doc.samples_z())
		for biome in PaletteLibrary.biomes():
			_biomes[String(biome.get("id", ""))] = true
		_surfaces = PaletteLibrary.surfaces()

	## The checked arguments of an op of `kind` ([] with `problem` set when refused).
	func read(kind: String, args: Array) -> Array:
		var arity := {"mask": 1, "surface": 1, "height": 2, "water": 2, "crossings": 2, "props": 2}
		if args.size() != arity[kind]:
			_fail("%s takes %d arguments" % [kind, arity[kind]])
			return []
		var out: Array = []
		match kind:
			"mask":
				out = [_mask_diff(args[0])]
			"surface":
				out = [_surface_diff(args[0])]
			"height":
				out = [_height_diff(args[0], false), _record(args[1], false)]
			"water":
				out = [_height_diff(args[0], true), _record(args[1], true)]
			"crossings":
				out = [_crossing_list(args[0]), _area(args[1])]
			"props":
				out = [args[0], _cell_rows(args[0], args[1])]
		return out if problem == "" else []

	func _fail(why: String) -> void:
		if problem == "":
			problem = why

	func _rect(value: Variant) -> Rect2i:
		if not value is Rect2i or not (value as Rect2i).has_area() or not grid.encloses(value):
			_fail("a rectangle outside the sample grid")
			return Rect2i()
		return value

	## `packed` decompressed to exactly `size` bytes ([] with `problem` set otherwise).
	func _unpack(packed: Variant, size: int) -> PackedByteArray:
		if not packed is PackedByteArray or (packed as PackedByteArray).is_empty():
			_fail("a block is not compressed bytes")
			return PackedByteArray()
		var raw := (packed as PackedByteArray).decompress(size, COMPRESSION)
		if raw.size() != size:
			_fail("a block does not hold its rectangle")
		return raw

	## The diff fields every stroke diff has: "blocks" (each {"rect", "after"} with `after`
	## read by `read_after` from the block's rectangle) and "rect".
	func _blocks(diff: Variant, read_after: Callable) -> Dictionary:
		if not diff is Dictionary or not diff.get("blocks") is Array:
			_fail("a diff needs a block list")
			return {}
		var listed: Array = diff.blocks
		var most := ceili(grid.size.x / 40.0) * ceili(grid.size.y / 40.0)
		if listed.size() > most:
			_fail("more blocks than the grid has")
			return {}
		var blocks: Array = []
		for block: Variant in listed:
			var rect := _rect(block.get("rect") if block is Dictionary else null)
			if problem != "":
				return {}
			blocks.append({"rect": rect, "after": read_after.call(rect, block.get("after"))})
		var whole := _rect(diff.get("rect")) if not blocks.is_empty() else Rect2i()
		return {"blocks": blocks, "rect": whole}

	func _ids(value: Variant, known: Dictionary, cap: int) -> PackedStringArray:
		if not value is PackedStringArray or (value as PackedStringArray).size() > cap:
			_fail("an id list is not a short string list")
			return PackedStringArray()
		for id in value:
			if not known.has(id):
				_fail("unknown palette id '%s'" % id.left(MapDocumentIO.MAX_ID_LENGTH))
		return (value as PackedStringArray).duplicate()

	func _mask_diff(value: Variant) -> Dictionary:
		var ids_after := _ids(
			value.get("ids_after") if value is Dictionary else null, _biomes, MapDocument.MAX_BIOMES
		)
		var read_after := func(rect: Rect2i, after: Variant) -> Dictionary:
			var out := {}
			if not after is Dictionary:
				_fail("a mask block is not an object")
				return out
			for mask: Variant in after:
				if not (mask is StringName or mask is String) or not MASKS.has(String(mask)):
					_fail("a block names something that is not a mask")
					return out
				var raw := _unpack(after[mask], rect.size.x * rect.size.y)
				if String(mask) == "biome_slots" and raw.size() > 0:
					var top := Array(raw).max() as int
					if top > ids_after.size():
						_fail("a slot names a biome past the list")
				out[StringName(mask)] = after[mask]
			return out
		var out := _blocks(value, read_after)
		if problem != "":
			return {}
		var allocated: Array[StringName] = []
		for mask: Variant in value.get("allocated", []):
			if not (mask is StringName or mask is String) or not MASKS.has(String(mask)):
				_fail("allocates something that is not a mask")
			allocated.append(StringName(mask))
		out["ids_after"] = ids_after
		out["ids_before"] = _ids(value.get("ids_before"), _biomes, MapDocument.MAX_BIOMES)
		out["allocated"] = allocated
		return out

	func _surface_diff(value: Variant) -> Dictionary:
		var read_after := func(rect: Rect2i, after: Variant) -> PackedByteArray:
			_unpack(after, rect.size.x * rect.size.y * SURFACE_BYTES)
			return after if after is PackedByteArray else PackedByteArray()
		var out := _blocks(value, read_after)
		if problem != "":
			return {}
		out["ids_after"] = _ids(value.get("ids_after"), _surfaces, MapDocument.MAX_SURFACES)
		out["ids_before"] = _ids(value.get("ids_before"), _surfaces, MapDocument.MAX_SURFACES)
		out["has_after"] = value.get("has_after") == true
		out["had_before"] = value.get("had_before") == true
		return out

	## A heights diff; `may_be_empty` for a water edit that carved nothing ({}).
	func _height_diff(value: Variant, may_be_empty: bool) -> Dictionary:
		if may_be_empty and value is Dictionary and (value as Dictionary).is_empty():
			return {}
		var read_after := func(rect: Rect2i, after: Variant) -> PackedByteArray:
			var raw := _unpack(after, rect.size.x * rect.size.y * HEIGHT_BYTES)
			for h in raw.to_float32_array():
				if is_nan(h) or is_inf(h) or absf(h) > MapDocument.MAX_ABS_HEIGHT_M:
					_fail("a height is not finite or out of range")
					break
			return after if after is PackedByteArray else PackedByteArray()
		return _blocks(value, read_after)

	## A sculpt (`water` false) or water edit record's after side.
	func _record(value: Variant, water: bool) -> Dictionary:
		if not value is Dictionary:
			_fail("a record is not an object")
			return {}
		var out := {
			"props_after": _cells(value.get("props_after")),
			"kept": _cells(value.get("kept")),
			"crossings": {},
		}
		var followed: Variant = value.get("crossings")
		if followed is Dictionary and not (followed as Dictionary).is_empty():
			out.crossings = {
				"after": _crossing_list(followed.get("after")), "area": _area(followed.get("area"))
			}
		elif not followed is Dictionary:
			_fail("followed crossings are not an object")
		if water:
			out["water_after"] = _water_model(value.get("water_after"))
			var dressing: Variant = value.get("dressing_after")
			var size: Variant = dressing.get("size") if dressing is Dictionary else null
			if size is int and size == 0:
				out["dressing_after"] = {"data": PackedByteArray(), "size": 0}
			elif size is int and size == doc.sample_count() * DRESSING_BYTES:
				_unpack(dressing.get("data"), size)
				out["dressing_after"] = {"data": dressing.get("data"), "size": size}
			else:
				_fail("the wet dressing is not the grid's size")
			out["region"] = _rect(value.get("region"))
		return out

	func _water_model(value: Variant) -> Dictionary:
		var size: Variant = value.get("pond_size") if value is Dictionary else null
		if not size is int or (size != 0 and size != doc.sample_count()):
			_fail("the pond mask is not the grid's size")
			return {}
		var bodies_json: Variant = value.get("bodies")
		var log := MapDocumentIO._WarningLog.new()
		var bodies := MapWaterIO._parse_bodies(
			bodies_json if bodies_json is Array else [null], doc.extent_m(), log
		)
		if not log.items.is_empty():
			_fail("water: " + log.items[0])
		var mask := PackedByteArray()
		if size > 0:
			mask = _unpack(value.get("pond_mask"), size)
			# Every byte is 0 or a pond's id: the counts (C++ scans) add up to the whole mask.
			var named := mask.count(0)
			for body in bodies:
				if not body.is_river():
					named += mask.count(body.id)
			if named != mask.size():
				_fail("the pond mask names a pond that is not there")
		return {
			"bodies": bodies, "pond_mask": value.get("pond_mask") if size > 0 else mask,
			"pond_size": size
		}

	func _crossing_list(value: Variant) -> Array[Crossing]:
		var log := MapDocumentIO._WarningLog.new()
		var list := MapCrossingIO._parse_list(
			value if value is Array else [null], doc.extent_m(), log
		)
		if not log.items.is_empty():
			_fail("crossings: " + log.items[0])
		return list

	## A map XZ rectangle: finite, within the map grown by its own size.
	func _area(value: Variant) -> Rect2:
		var extent := doc.extent_m()
		var bounds := Rect2(-extent, extent * 2.0)
		if not value is Rect2 or not (value as Rect2).is_finite():
			_fail("an area is not a finite rectangle")
			return Rect2()
		if (value as Rect2).has_area() and not bounds.encloses(value):
			_fail("an area is off the map")
			return Rect2()
		return value

	## cell -> rows (hand-placed or scattered) of `value`, each cell checked.
	func _cells(value: Variant) -> Dictionary:
		var out := {}
		if not value is Dictionary:
			_fail("a cell table is not an object")
			return out
		for cell: Variant in value:
			out[cell] = _cell_rows(cell, value[cell])
		return out

	## Asset id -> rows of one 10 m cell, every row checked as MapDocumentIO checks a
	## document's and lying in `cell`.
	func _cell_rows(cell: Variant, value: Variant) -> Dictionary:
		var out := {}
		if not cell is Vector2i or not value is Dictionary:
			_fail("a cell is not a cell of rows")
			return out
		for asset_id: Variant in value:
			var rows: Variant = value[asset_id]
			if not asset_id is String or not _known_asset(asset_id):
				_fail("an unknown asset")
				return out
			if not rows is PackedFloat32Array or rows.size() % MapDocument.ROW_STRIDE != 0:
				_fail("rows are not whole rows")
				return out
			_floats += rows.size()
			if _floats > MAX_OP_ROWS * MapDocument.ROW_STRIDE:
				_fail("more than %d rows" % MAX_OP_ROWS)
				return out
			for start in range(0, rows.size(), MapDocument.ROW_STRIDE):
				var row: PackedFloat32Array = rows.slice(start, start + MapDocument.ROW_STRIDE)
				if not MapDocumentIO._row_ok(rows, start) or PropRows.cell_of(row) != cell:
					_fail("a row is degenerate or outside its cell")
					return out
			out[asset_id] = (rows as PackedFloat32Array).duplicate()
		return out

	func _known_asset(asset_id: String) -> bool:
		var biome_id := asset_id.get_slice("/", 0)
		if not _biomes.has(biome_id):
			return false
		if not _assets.has(biome_id):
			var known := {}
			for rule in PaletteLibrary.species(biome_id):
				for id in rule.get("assets", []):
					known[String(id)] = true
			_assets[biome_id] = known
		return (_assets[biome_id] as Dictionary).has(asset_id)
