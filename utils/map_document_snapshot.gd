class_name MapDocumentSnapshot
extends RefCounted

## One map document frozen at a moment, so it can be written off the main thread (topic
## perfaudit, card authsave). MapDocumentIO.serialize() is capture() followed by encode(); a
## save that must not stall the frame calls capture() on the main thread and leaves encode()
## (through MapDocumentIO.write_snapshot, on a MapDocumentWriter task) to a worker.
##
## capture() is the only half that reads anything but packed data. It copies every packed
## array and every dictionary of packed arrays into a private MapDocument. GDScript shares a
## packed array between two variables or properties (probed on 4.7.2: after `b = a`, a write
## through either is seen by both), but duplicate() is copy-on-write: O(1), and the first later
## write to the live array copies it (a 16 MB array: 1 us to duplicate, 2 ms on the first
## write). So a capture costs microseconds per field, and an edit after it never reaches the
## snapshot. Dictionaries are duplicated deep for the same reason (a shallow duplicate shares
## its packed values, appends included). The object lists (water bodies, crossings, walls,
## structures, settlements) are not copied: their rule checks and their small JSON entries run
## at capture, on the calling thread, with the manifest (which reads the library registry).
##
## encode() reads only the snapshot (its copy, its entries and the pond ids), so it runs on
## any thread: it checks the packed data against the reader's rules (heights, masks, biomes,
## surfaces, water grids, rows), builds the heavy entries (rows JSON, PNGs, surfaces, anchors)
## and applies the caps. Its entries are byte-identical to the one-call serialize() it split.

## The private copy encode() reads; its object lists are empty.
var document: MapDocument = null
## Entries written at capture: the manifest, biomes.json and the object lists' entries.
var entries: Dictionary[String, PackedByteArray] = {}
## The first rule the document breaks, "" while none was found (capture or encode sets it).
var error: String = ""
## Pond id -> true, from the water bodies at capture (the pond mask check needs it).
var pond_ids: Dictionary = {}


## Freezes `doc` (see the header). Main thread: it reads the library registry and the
## document's object lists. A document that breaks a rule comes back with `error` set.
static func capture(doc: MapDocument) -> MapDocumentSnapshot:
	var snap := MapDocumentSnapshot.new()
	snap.error = MapDocumentIO.capture_problem(doc)
	if snap.error != "":
		return snap
	snap.document = copy_document(doc)
	snap.pond_ids = MapWaterIO.pond_ids(doc)
	var manifest := JSON.stringify(MapDocumentIO._manifest(doc), "\t", false, true)
	snap.entries[MapDocumentIO.MANIFEST_ENTRY] = manifest.to_utf8_buffer()
	if not doc.biome_ids.is_empty():
		var biomes := {"biomes": Array(doc.biome_ids)}
		snap.entries[MapDocumentIO.BIOMES_JSON_ENTRY] = JSON.stringify(biomes, "\t").to_utf8_buffer()
	MapWaterIO.serialize_bodies(doc, snap.entries)
	MapCrossingIO.serialize(doc, snap.entries)
	MapWallIO.serialize(doc, snap.entries)
	MapStructureIO.serialize(doc, snap.entries)
	MapSettlementIO.serialize(doc, snap.entries)
	return snap


## A MapDocument holding copy-on-write copies of `doc`'s scalars, packed arrays and row
## dictionaries, and none of its object lists or derived fields. Pure.
static func copy_document(doc: MapDocument) -> MapDocument:
	var copy := MapDocument.new()
	copy.palette_version = doc.palette_version
	copy.map_seed = doc.map_seed
	copy.size_cells = doc.size_cells
	copy.cell_size_m = doc.cell_size_m
	copy.sample_spacing_m = doc.sample_spacing_m
	copy.tier_height_m = doc.tier_height_m
	copy.base_surface = doc.base_surface
	copy.has_base_map = doc.has_base_map
	copy.procgen_crossings = doc.procgen_crossings
	copy.heights = doc.heights.duplicate()
	copy.scatter = doc.scatter.duplicate(true)
	copy.props = doc.props.duplicate(true)
	copy.mass_anchors = doc.mass_anchors.duplicate(true)
	copy.erase_mask = doc.erase_mask.duplicate()
	copy.biome_ids = doc.biome_ids.duplicate()
	copy.biome_slots = doc.biome_slots.duplicate()
	copy.biome_density = doc.biome_density.duplicate()
	copy.surface_ids = doc.surface_ids.duplicate()
	copy.surface_weights = doc.surface_weights.duplicate()
	copy.pond_mask = doc.pond_mask.duplicate()
	copy.water_flow = doc.water_flow.duplicate()
	copy.water_flow_size = doc.water_flow_size
	copy.fire_mask = doc.fire_mask.duplicate()
	return copy


## The entries MapDocumentIO.serialize() returns: {"entries": Dictionary[String,
## PackedByteArray], "error": String}, `entries` empty when `error` is not. Any thread: reads
## only this snapshot. Sets `error` when the packed data breaks a rule or a cap.
func encode() -> Dictionary:
	var out: Dictionary[String, PackedByteArray] = {}
	if error == "":
		error = MapDocumentIO.data_problem(document, pond_ids)
	if error != "":
		return {"entries": out, "error": error}
	var doc := document
	out.assign(entries)
	out[MapDocumentIO.HEIGHT_ENTRY] = doc.heights.to_byte_array()
	out[MapDocumentIO.SCATTER_ENTRY] = MapDocumentIO._rows_json(doc.scatter).to_utf8_buffer()
	out[MapDocumentIO.PROPS_ENTRY] = MapDocumentIO._rows_json(doc.props).to_utf8_buffer()
	if not doc.erase_mask.is_empty():
		out[MapDocumentIO.ERASE_ENTRY] = MapDocumentIO._png(doc.erase_mask, doc, Image.FORMAT_L8)
	if not doc.biome_slots.is_empty():
		var interleaved := MapDocumentIO._interleave(doc.biome_slots, doc.biome_density)
		out[MapDocumentIO.BIOMES_PNG_ENTRY] = MapDocumentIO._png(interleaved, doc, Image.FORMAT_RG8)
	if not doc.surface_ids.is_empty():
		MapSurfacesIO.serialize(doc, out)
	MapWaterIO.serialize_grids(doc, out)
	if MapDocumentIO.has_fire(doc.fire_mask):
		out[MapDocumentIO.FIRE_ENTRY] = MapDocumentIO._png(doc.fire_mask, doc, Image.FORMAT_L8)
	MapAnchorsIO.serialize(doc, out)
	error = _caps_problem(out)
	if error != "":
		return {"entries": {}, "error": error}
	return {"entries": out, "error": ""}


static func _caps_problem(out: Dictionary[String, PackedByteArray]) -> String:
	var total := 0
	for entry_name in out:
		var size := out[entry_name].size()
		total += size
		var cap: int = MapDocumentIO.ENTRY_CAPS[entry_name]
		if size > cap:
			return "%s is %d bytes, over its cap of %d" % [entry_name, size, cap]
	if total > MapDocumentIO.MAX_TOTAL_BYTES:
		return "entries total %d bytes, over %d" % [total, MapDocumentIO.MAX_TOTAL_BYTES]
	return ""
