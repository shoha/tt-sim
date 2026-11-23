class_name LiveEditReader
extends RefCounted

## The checks behind LiveEditCodec.decode(): one live edit's argument list read as untrusted
## input against the receiving peer's document, the way MapDocumentIO reads a document. A
## fresh value is built from every checked one; the first problem found is kept in `problem`
## and the rest of the read is skipped.
##
## The rules: every rectangle inside the sample grid; mask names against the masks a stroke
## writes (MaskStroke.apply_diff sets the property a diff names, so an unchecked name could
## overwrite any document field); every compressed block decompressing to exactly its
## rectangle's size (the size comes from the rectangle, never from the payload); slot bytes
## naming a biome in the op's own list; finite heights within MapDocument.MAX_ABS_HEIGHT_M; a
## pond mask of no samples or the grid's, every byte of it 0 or a pond's id; a wet dressing of
## no samples or 4 bytes a sample; water bodies and crossings through MapWaterIO's and
## MapCrossingIO's own readers and rules; rows MapDocumentIO.row_ok() accepts, in the cell they
## are filed under, that cell on the map, at most MAX_OP_ROWS an op; biome, surface and asset
## ids the palette has; terrain edits against the session's ops, the id range, finite floats, the
## caps and each added primitive's kind (_terra_edits), on a map with terrain primitives only.
## The palette's id tables are built once per palette and cached
## (palette_ids(); rebuilding them was most of the probe's 1.1 to 2.6 ms per decode).

## Rows one op may carry, over all its cells.
const MAX_OP_ROWS := 200000
## The masks a MaskStroke writes (the Fire tool's fire_mask among them); a diff naming any
## other property is refused.
const MASKS: Array[StringName] = [
	MaskStroke.SLOTS, MaskStroke.DENSITY, MaskStroke.ERASE, MaskStroke.FIRE
]
## Bytes per sample of a surface diff block (two RGBA8 planes), a heights block (float32)
## and the wet dressing (RGBA8).
const SURFACE_BYTES := 8
const HEIGHT_BYTES := 4
const DRESSING_BYTES := 4
const COMPRESSION := FileAccess.COMPRESSION_ZSTD
## Arguments of each op kind (LiveEditCodec.KINDS).
const ARITY := {
	"mask": 1,
	"surface": 1,
	"height": 2,
	"water": 2,
	"crossings": 2,
	"walls": 2,
	"structures": 2,
	"settlements": 2,
	"props": 2,
	"terra": 4,
	"terra_check": 2,
}
## The terrain kind registry, by path (TerraKinds names the terraform scripts, which the start-up
## script graph leaves out; MapSourceLoader's TERRA_* likewise).
const TERRA_KINDS := "res://utils/terraform/terra_kinds.gd"
## The terrain session edit ops a "terra" op may carry (TerraSession.apply).
const TERRA_OPS: Array[String] = [
	"add", "replace", "append", "remove", "mute", "unmute", "move", "splice", "surfaces"
]
## TerraDoc.MAX_SURFACES and MAX_SURFACE_NAME (by value).
const TERRA_MAX_SURFACES := 64
const TERRA_MAX_SURFACE_NAME := 64
## Most edits one "terra" op carries (a fold's splice inverse is one edit per primitive).
const MAX_TERRA_EDITS := MapDocument.MAX_TERRA_PRIMS + 64
## TerraDoc.MAX_ID and TerraDoc.KNOWN_FLAGS (by value, as TERRA_KINDS is by path).
const TERRA_MAX_ID := 0x7FFFFFFF
const TERRA_KNOWN_FLAGS := 1
## Most digests a "terra" op carries, and the longest name.
const MAX_TERRA_DIGESTS := 32
const MAX_DIGEST_NAME := 32

## palette root -> {"palette": the PaletteLibrary dictionary the tables were built from,
## "biomes", "surfaces", "assets": id -> true}.
static var _tables: Dictionary = {}

## Why the read refused the op, or "".
var problem: String = ""

var _doc: MapDocument = null
var _grid: Rect2i = Rect2i()
## Cells a row may be filed under: the map's, one cell around.
var _cells_on_map: Rect2i = Rect2i()
var _ids: Dictionary = {}
## Row floats read so far, against MAX_OP_ROWS.
var _floats: int = 0
## The side the op carries: "after", or "before" for an undo (read()).
var _side: String = "after"


func _init(doc: MapDocument, palette_root: String = PaletteLibrary.DEFAULT_ROOT) -> void:
	_doc = doc
	_grid = Rect2i(0, 0, doc.samples_x(), doc.samples_z())
	var size := ScatterChunker.CHUNK_SIZE_WORLD_UNITS
	var half := doc.extent_m() * 0.5
	var first := Vector2i((-half / size).floor()) - Vector2i.ONE
	var last := Vector2i((half / size).floor()) + Vector2i.ONE
	_cells_on_map = Rect2i(first, last - first + Vector2i.ONE)
	_ids = palette_ids(palette_root)


## The biome, surface and placed asset ids of the palette under `root` ({"biomes", "surfaces",
## "assets"}: id -> true), cached until PaletteLibrary loads that palette again. An asset counts
## when a species of its own biome (the id's first path segment, as
## AuthoringEditor.rule_for_asset finds it) places it.
static func palette_ids(root: String) -> Dictionary:
	var palette := PaletteLibrary.get_palette(root)
	var cached: Dictionary = _tables.get(root, {})
	if not cached.is_empty() and is_same(cached.palette, palette):
		return cached
	var biomes := {}
	var assets := {}
	for biome: Dictionary in palette.get("biomes", []):
		var biome_id := String(biome.get("id", ""))
		biomes[biome_id] = true
		for rule: Dictionary in biome.get("species", []):
			for asset_id: Variant in rule.get("assets", []):
				if String(asset_id).get_slice("/", 0) == biome_id:
					assets[String(asset_id)] = true
	var surfaces := {}
	for surface_id: Variant in palette.get("surfaces", {}):
		surfaces[String(surface_id)] = true
	cached = {"palette": palette, "biomes": biomes, "surfaces": surfaces, "assets": assets}
	_tables[root] = cached
	return cached


## The checked arguments of an op of `kind` (one of LiveEditCodec.KINDS) carrying the side
## `redo` names (after, or before for an undo), or [] with `problem` set when refused.
func read(kind: String, args: Array, redo: bool = true) -> Array:
	if args.size() != ARITY[kind]:
		_fail("%s takes %d arguments" % [kind, ARITY[kind]])
		return []
	_side = LiveEditCodec.side_name(redo)
	var out: Array = []
	match kind:
		"mask":
			out = [_mask_diff(args[0], redo)]
		"surface":
			out = [_surface_diff(args[0])]
		"height":
			out = [_height_diff(args[0], false), _record(args[1], false)]
		"water":
			out = [_height_diff(args[0], true), _record(args[1], true)]
		"crossings":
			out = [_crossing_list(args[0]), _area(args[1])]
		"walls":
			out = [_wall_list(args[0]), _area(args[1])]
		"structures":
			out = [_structure_list(args[0]), _area(args[1])]
		"settlements":
			out = [_settlement_list(args[0]), _area(args[1])]
		"props":
			out = [args[0], _cell_rows(args[0], args[1])]
		"terra":
			var ground: Variant = args[1]
			var empty := ground is Dictionary and (ground as Dictionary).is_empty()
			out = [
				_terra_edits(args[0]),
				{} if empty else _record(ground, false),
				_digest_text(args[2]),
				_digest_table(args[3]),
			]
		"terra_check":
			_terra_edits([])
			out = [_digest_text(args[0]), _digest_table(args[1])]
	return out if problem == "" else []


func _fail(why: String) -> void:
	if problem == "":
		problem = why


func _rect(value: Variant) -> Rect2i:
	if not value is Rect2i or not (value as Rect2i).has_area() or not _grid.encloses(value):
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


## The fields every stroke diff has: "blocks" (each {"rect", side}, the side the op carries
## read by `read_after` from the block's rectangle) and "rect" (the union).
func _blocks(diff: Variant, read_after: Callable) -> Dictionary:
	if not diff is Dictionary or not diff.get("blocks") is Array:
		_fail("a diff needs a block list")
		return {}
	var listed: Array = diff.blocks
	var block_size := float(MaskStroke.BLOCK)
	var most := ceili(_grid.size.x / block_size) * ceili(_grid.size.y / block_size)
	if listed.size() > most:
		_fail("more blocks than the grid has")
		return {}
	var blocks: Array = []
	for block: Variant in listed:
		var rect := _rect(block.get("rect") if block is Dictionary else null)
		if problem != "":
			return {}
		var after: Variant = read_after.call(rect, block.get(_side))
		if problem != "":
			return {}
		blocks.append({"rect": rect, _side: after})
	var whole := _rect(diff.get("rect")) if not blocks.is_empty() else Rect2i()
	return {"blocks": blocks, "rect": whole}


## A copy of id list `value` when it is a short list of distinct ids in `known`.
func _id_list(value: Variant, known: Dictionary, cap: int) -> PackedStringArray:
	if not value is PackedStringArray or (value as PackedStringArray).size() > cap:
		_fail("an id list is not a short string list")
		return PackedStringArray()
	var seen := {}
	for id in value:
		if not known.has(id) or seen.has(id):
			_fail("an unknown or repeated palette id '%s'" % id.left(MapDocumentIO.MAX_ID_LENGTH))
		seen[id] = true
	return (value as PackedStringArray).duplicate()


func _mask_name(value: Variant) -> StringName:
	if (value is StringName or value is String) and MASKS.has(StringName(value)):
		return StringName(value)
	_fail("names something that is not a mask")
	return &""


static func _flag(value: Variant) -> bool:
	return value is bool and value


## A mask diff; `redo` false: its before side, whose slots name biomes of ids_before.
func _mask_diff(value: Variant, redo: bool) -> Dictionary:
	var biomes: Dictionary = _ids.biomes
	var ids_after := _id_list(
		value.get("ids_after") if value is Dictionary else null, biomes, MapDocument.MAX_BIOMES
	)
	var ids_before := _id_list(
		value.get("ids_before") if value is Dictionary else null, biomes, MapDocument.MAX_BIOMES
	)
	var slot_ids := ids_after if redo else ids_before
	var read_side := func(rect: Rect2i, side: Variant) -> Dictionary:
		var kept := {}
		if not side is Dictionary or (side as Dictionary).size() > MASKS.size():
			_fail("a mask block is not a table of masks")
			return kept
		for mask: Variant in side:
			var mask_name := _mask_name(mask)
			if problem != "":
				return kept
			var raw := _unpack(side[mask], rect.size.x * rect.size.y)
			if mask_name == MaskStroke.SLOTS and raw.size() > 0:
				if int(Array(raw).max()) > slot_ids.size():
					_fail("a slot names a biome past the list")
			kept[mask_name] = side[mask]
		return kept
	var out := _blocks(value, read_side)
	if problem != "":
		return {}
	var listed: Variant = value.get("allocated", [])
	var allocated: Array[StringName] = []
	if not listed is Array or (listed as Array).size() > MASKS.size():
		_fail("allocates something that is not a mask")
		return {}
	for mask: Variant in listed:
		allocated.append(_mask_name(mask))
	out["ids_after"] = ids_after
	out["ids_before"] = ids_before
	out["allocated"] = allocated
	return out if problem == "" else {}


func _surface_diff(value: Variant) -> Dictionary:
	var surfaces: Dictionary = _ids.surfaces
	var read_after := func(rect: Rect2i, after: Variant) -> PackedByteArray:
		_unpack(after, rect.size.x * rect.size.y * SURFACE_BYTES)
		return after if after is PackedByteArray else PackedByteArray()
	var out := _blocks(value, read_after)
	if problem != "":
		return {}
	out["ids_after"] = _id_list(value.get("ids_after"), surfaces, MapDocument.MAX_SURFACES)
	out["ids_before"] = _id_list(value.get("ids_before"), surfaces, MapDocument.MAX_SURFACES)
	out["has_after"] = _flag(value.get("has_after"))
	out["had_before"] = _flag(value.get("had_before"))
	return out if problem == "" else {}


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
	var out := _blocks(value, read_after)
	if problem == "" and (value as Dictionary).has("changed"):
		# The samples the stroke changed (HeightStroke.finish), inside its blocks.
		var changed := _rect(value.changed)
		if problem == "" and not (out.rect as Rect2i).encloses(changed):
			_fail("the changed samples lie outside the blocks")
		out["changed"] = changed
	return out if problem == "" else {}


## A sculpt (`water` false) or water edit record's side the op carries (its *_after fields, or
## *_before for an undo).
func _record(value: Variant, water: bool) -> Dictionary:
	if not value is Dictionary:
		_fail("a record is not an object")
		return {}
	var out := {
		"props_" + _side: _cells(value.get("props_" + _side)),
		"kept": _cells(value.get("kept")),
		"crossings": {},
		"walls": {},
		"structures": {},
	}
	var structures_followed: Variant = value.get("structures", {})
	if structures_followed is Dictionary and not (structures_followed as Dictionary).is_empty():
		out.structures = {"area": _area(structures_followed.get("area"))}
	elif not structures_followed is Dictionary:
		_fail("followed structures are not an object")
	var walls_followed: Variant = value.get("walls", {})
	if walls_followed is Dictionary and not (walls_followed as Dictionary).is_empty():
		out.walls = {"area": _area(walls_followed.get("area"))}
	elif not walls_followed is Dictionary:
		_fail("followed walls are not an object")
	var followed: Variant = value.get("crossings")
	if followed is Dictionary and not (followed as Dictionary).is_empty():
		out.crossings = {
			_side: _crossing_list(followed.get(_side)), "area": _area(followed.get("area"))
		}
	elif not followed is Dictionary:
		_fail("followed crossings are not an object")
	if water:
		out["water_" + _side] = _water_model(value.get("water_" + _side))
		var dressing: Variant = value.get("dressing_" + _side)
		var size: Variant = dressing.get("size") if dressing is Dictionary else null
		if size is int and size == 0:
			out["dressing_" + _side] = {"data": PackedByteArray(), "size": 0}
		elif size is int and size == _doc.sample_count() * DRESSING_BYTES:
			_unpack(dressing.get("data"), size)
			out["dressing_" + _side] = {"data": dressing.get("data"), "size": size}
		else:
			_fail("the wet dressing is not the grid's size")
		out["region"] = _rect(value.get("region"))
	return out if problem == "" else {}


func _water_model(value: Variant) -> Dictionary:
	var size: Variant = value.get("pond_size") if value is Dictionary else null
	if not size is int or (size != 0 and size != _doc.sample_count()):
		_fail("the pond mask is not the grid's size")
		return {}
	var bodies_json: Variant = value.get("bodies")
	var warn_log := MapDocumentIO._WarningLog.new()
	var bodies := MapWaterIO.parse_bodies(
		bodies_json if bodies_json is Array else [null], _doc.extent_m(), warn_log
	)
	if not warn_log.items.is_empty():
		_fail("water: " + warn_log.items[0])
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
		"bodies": bodies,
		"pond_mask": value.get("pond_mask") if size > 0 else mask,
		"pond_size": size,
	}


func _crossing_list(value: Variant) -> Array[Crossing]:
	var warn_log := MapDocumentIO._WarningLog.new()
	var list := MapCrossingIO.parse_list(
		value if value is Array else [null], _doc.extent_m(), warn_log
	)
	if not warn_log.items.is_empty():
		_fail("crossings: " + warn_log.items[0])
	return list


func _wall_list(value: Variant) -> Array[Wall]:
	var warn_log := MapDocumentIO._WarningLog.new()
	var list := MapWallIO.parse_list(value if value is Array else [null], _doc.extent_m(), warn_log)
	if not warn_log.items.is_empty():
		_fail("walls: " + warn_log.items[0])
	return list


func _settlement_list(value: Variant) -> Array[Settlement]:
	var warn_log := MapDocumentIO._WarningLog.new()
	var list := MapSettlementIO.parse_list(value if value is Array else [null], warn_log)
	if not warn_log.items.is_empty():
		_fail("settlements: " + warn_log.items[0])
	return list


func _structure_list(value: Variant) -> Array[Structure]:
	var warn_log := MapDocumentIO._WarningLog.new()
	var list := MapStructureIO.parse_list(
		value if value is Array else [null], _doc.extent_m(), warn_log
	)
	if not warn_log.items.is_empty():
		_fail("structures: " + warn_log.items[0])
	return list


## A map XZ rectangle: finite, within the map grown by its own size.
func _area(value: Variant) -> Rect2:
	var extent := _doc.extent_m()
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
		if problem != "":
			return {}
	return out


## Asset id -> rows of one 10 m cell, every row checked as MapDocumentIO checks a document's
## and lying in `cell`, a cell on the map.
func _cell_rows(cell: Variant, value: Variant) -> Dictionary:
	var out := {}
	if not cell is Vector2i or not value is Dictionary or not _cells_on_map.has_point(cell):
		_fail("a cell is not a cell of rows on the map")
		return out
	var assets: Dictionary = _ids.assets
	for asset_id: Variant in value:
		var rows: Variant = value[asset_id]
		if not asset_id is String or not assets.has(asset_id):
			_fail("an asset the palette does not place")
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
			if not MapDocumentIO.row_ok(rows, start) or PropRows.cell_of(row) != cell:
				_fail("a row is degenerate or outside its cell")
				return out
		out[asset_id] = (rows as PackedFloat32Array).duplicate()
	return out


# ============================================================================
# Terrain edits ("terra", "terra_check")
# ============================================================================


## A fresh copy of a terrain gesture side's session edits (TerraSession.apply's forms), each
## checked: an op of TERRA_OPS, ids in 1..TERRA_MAX_ID, finite floats within the per-primitive
## cap and the document's in all, an added or inserted primitive valid for its kind
## (TerraKinds.problem), no reserved flag, at most MAX_TERRA_EDITS edits. Refused on a map without
## a terrain section. Whether an id names a primitive is the session's to check when it applies.
func _terra_edits(value: Variant) -> Array:
	if _doc.terra == null:
		_fail("a terrain edit for a map without terrain primitives")
		return []
	if not value is Array or (value as Array).size() > MAX_TERRA_EDITS:
		_fail("terrain edits are not a short list")
		return []
	var kinds: GDScript = load(TERRA_KINDS)
	var out: Array = []
	var floats := 0
	for change: Variant in value:
		if not change is Dictionary or not TERRA_OPS.has(change.get("op")):
			_fail("a terrain edit is not one of the session's ops")
			return []
		var op := String(change.op)
		var fresh := {"op": op}
		match op:
			"add":
				fresh.merge(_terra_prim(change, kinds, false))
			"replace", "append":
				fresh["id"] = _terra_id(change.get("id"))
				fresh["data"] = _terra_floats(change.get("data"))
			"remove", "mute", "unmute":
				fresh["id"] = _terra_id(change.get("id"))
			"move":
				fresh["id"] = _terra_id(change.get("id"))
				fresh["to"] = _terra_count(change.get("to"), MapDocument.MAX_TERRA_PRIMS)
			"splice":
				fresh.merge(_terra_splice(change, kinds))
			"surfaces":
				fresh["names"] = _terra_surfaces(change.get("names"))
		if problem != "":
			return []
		floats += _terra_float_count(fresh)
		if floats > MapDocument.MAX_TERRA_FLOATS * 2:
			_fail("terrain edits carry too many floats")
			return []
		out.append(fresh)
	return out


## Floats one checked edit carries (its data, or a splice's inserted primitives').
static func _terra_float_count(change: Dictionary) -> int:
	var count := (change.get("data", PackedFloat32Array()) as PackedFloat32Array).size()
	for q: Dictionary in change.get("insert", []):
		count += (q.data as PackedFloat32Array).size()
	return count


## A splice's fields: removed ids (distinct), inserted primitives, the position and next_id.
func _terra_splice(change: Dictionary, kinds: GDScript) -> Dictionary:
	var removed: Variant = change.get("remove", [])
	var inserted: Variant = change.get("insert", [])
	if not removed is Array or not inserted is Array:
		_fail("a splice needs its id and primitive lists")
		return {}
	if (removed as Array).size() + (inserted as Array).size() > MAX_TERRA_EDITS:
		_fail("a splice past the primitive cap")
		return {}
	var ids: Array = []
	var seen := {}
	for id: Variant in removed:
		var checked := _terra_id(id)
		if seen.has(checked):
			_fail("a splice removes an id twice")
		seen[checked] = true
		ids.append(checked)
	var prims: Array = []
	for q: Variant in inserted:
		prims.append(_terra_prim(q, kinds, true))
		if problem != "":
			return {}
	var next: Variant = change.get("next_id", -1)
	if not next is int or (next != -1 and (next < 1 or next > TERRA_MAX_ID + 1)):
		_fail("a splice's next id is out of range")
		return {}
	return {
		"remove": ids,
		"insert": prims,
		"at": _terra_count(change.get("at", 0), MapDocument.MAX_TERRA_PRIMS),
		"next_id": next,
	}


## An added (`with_id` false: kind, flags, data) or inserted (with its id) primitive.
func _terra_prim(value: Variant, kinds: GDScript, with_id: bool) -> Dictionary:
	if not value is Dictionary:
		_fail("a terrain primitive is not an object")
		return {}
	var kind: Variant = value.get("kind")
	var flags: Variant = value.get("flags", 0)
	var data := _terra_floats(value.get("data"))
	if not kind is int or not flags is int or int(flags) & ~TERRA_KNOWN_FLAGS != 0:
		_fail("a terrain primitive's kind or flags are not valid")
		return {}
	if problem == "" and String(kinds.call("problem", kind, data)) != "":
		_fail("a terrain primitive its kind refuses")
		return {}
	var out := {"kind": kind, "flags": flags, "data": data}
	if with_id:
		out["id"] = _terra_id(value.get("id"))
	return out


func _terra_id(value: Variant) -> int:
	if not value is int or value < 1 or value > TERRA_MAX_ID:
		_fail("a terrain primitive id is out of range")
		return 0
	return value


func _terra_count(value: Variant, most: int) -> int:
	if not value is int or value < 0 or value > most:
		_fail("a terrain position is out of range")
		return 0
	return value


## A copy of float list `value` when it is finite and within the per-primitive cap.
func _terra_floats(value: Variant) -> PackedFloat32Array:
	if not value is PackedFloat32Array:
		_fail("terrain floats are not a float array")
		return PackedFloat32Array()
	var floats := value as PackedFloat32Array
	if floats.size() > MapDocument.MAX_TERRA_FLOATS_PER_PRIM:
		_fail("terrain floats past the per-primitive cap")
		return PackedFloat32Array()
	for f in floats:
		if not is_finite(f):
			_fail("terrain floats that are not finite")
			return PackedFloat32Array()
	return floats.duplicate()


## A copy of surface table `value` (TerraSession's "surfaces" op): at most TERRA_MAX_SURFACES
## printable ASCII names of 1 to TERRA_MAX_SURFACE_NAME characters (the session checks repeats).
func _terra_surfaces(value: Variant) -> PackedStringArray:
	if not value is PackedStringArray or (value as PackedStringArray).size() > TERRA_MAX_SURFACES:
		_fail("a terrain surface table is not a short list of names")
		return PackedStringArray()
	for n: String in value:
		var ascii := n.to_ascii_buffer()
		if n.is_empty() or ascii.size() > TERRA_MAX_SURFACE_NAME or ascii.get_string_from_ascii() != n:
			_fail("a terrain surface name is not short ASCII")
			return PackedStringArray()
	return (value as PackedStringArray).duplicate()


## TerraDoc.digest's text (64 hex digits), or "" for none.
func _digest_text(value: Variant) -> String:
	if not value is String:
		_fail("a terrain digest is not text")
		return ""
	var text := value as String
	if text != "" and (text.length() != 64 or not text.is_valid_hex_number()):
		_fail("a terrain digest is not 64 hex digits")
		return ""
	return text


## Digest name -> int (TerraEditor.CHECKED's form), short names, at most MAX_TERRA_DIGESTS.
func _digest_table(value: Variant) -> Dictionary:
	if not value is Dictionary or (value as Dictionary).size() > MAX_TERRA_DIGESTS:
		_fail("terrain digests are not a short table")
		return {}
	var out := {}
	for key: Variant in value:
		var digest: Variant = value[key]
		if not key is String or (key as String).length() > MAX_DIGEST_NAME or not digest is int:
			_fail("a terrain digest is not a named number")
			return {}
		out[key] = digest
	return out
