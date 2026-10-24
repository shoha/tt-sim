class_name MapSurfacesIO
extends RefCounted

## The painted-surface entries of `map.ttmap`, split from MapDocumentIO as MapWaterIO and
## MapCrossingIO are (MapDocumentIO's header lists every entry; MapDocument's header the
## entry layout and its canonical form):
##   surfaces.json          {"surfaces": [palette surface name, ...]}, at most MAX_SURFACES
##   surfaces_index.png     format 2: RGBA8, four indices into surfaces.json per sample
##   surfaces_weight.png    format 2: RGBA8, their four weights, high to low, 0 = unused
##   surfaces.png           format 1: RGBA8 weights of slots 0-3, one channel per slot
##   surfaces_b.png         format 1: slots 4-7, written only with 5+ surfaces
## Only format 2 is written. A format 1 document is migrated on read: per sample the
## non-zero of its eight channels, high to low, the strongest SURFACE_ENTRIES kept and
## renormalised to the sample's painted total, with one warning counting the samples that
## painted more. Everything read is untrusted (a host peer sends it): the images must match
## the sample grid (checked from the PNG header before decoding), and the entries are made
## canonical (SurfaceEntries.canonical) with a warning per kind of fix. A problem only drops
## the painted surfaces: without them the map is whole, dressed by automatic ground.

const JSON_ENTRY := MapDocumentIO.SURFACES_JSON_ENTRY
const INDEX_ENTRY := MapDocumentIO.SURFACES_INDEX_ENTRY
const WEIGHT_ENTRY := MapDocumentIO.SURFACES_WEIGHT_ENTRY
const SLOTS_A_ENTRY := MapDocumentIO.SURFACES_PNG_ENTRY
const SLOTS_B_ENTRY := MapDocumentIO.SURFACES_B_PNG_ENTRY


## Adds surfaces.json and the two entry images of `doc` to `entries`. The entries are made
## canonical on the way out, so the reader never has to fix what it reads; the document is
## not touched. The caller checked problem() and that `doc` has painted surfaces.
static func serialize(doc: MapDocument, entries: Dictionary) -> void:
	var count := doc.sample_count()
	var plane := count * MapDocument.SURFACE_CHANNELS
	var fixed := SurfaceEntries.canonical(doc.surface_weights, count, doc.surface_ids.size())
	var weights: PackedByteArray = fixed["weights"]
	var surfaces := {"surfaces": Array(doc.surface_ids)}
	entries[JSON_ENTRY] = JSON.stringify(surfaces, "\t").to_utf8_buffer()
	entries[INDEX_ENTRY] = MapDocumentIO._png(weights.slice(0, plane), doc, Image.FORMAT_RGBA8)
	entries[WEIGHT_ENTRY] = MapDocumentIO._png(weights.slice(plane), doc, Image.FORMAT_RGBA8)


## The first rule of the surface fields that the reader enforces and `doc` breaks, or "".
static func problem(doc: MapDocument, count: int) -> String:
	var ids := ids_problem(Array(doc.surface_ids))
	if ids != "":
		return ids
	if doc.surface_ids.is_empty() != doc.surface_weights.is_empty():
		return "surface_ids and surface_weights must both be empty or both set"
	if (
		not doc.surface_weights.is_empty()
		and doc.surface_weights.size() != count * MapDocument.SURFACE_BYTES
	):
		return "surface_weights do not match the sample grid"
	return ""


## "" when `ids` is a valid surface list (at most MAX_SURFACES distinct ids), else what
## is wrong. Shared by the writer and the reader.
static func ids_problem(ids: Array) -> String:
	if ids.size() > MapDocument.MAX_SURFACES:
		return "more than %d surfaces" % MapDocument.MAX_SURFACES
	var seen := {}
	for surface in ids:
		if not MapDocumentIO._is_id(surface):
			return "surface id '%s' is malformed, empty or too long" % MapDocumentIO._label(surface)
		if seen.has(surface):
			return "surface id '%s' is listed twice" % MapDocumentIO._label(surface)
		seen[surface] = true
	return ""


## Fills `doc`'s surface fields from `blobs` (the known entries within their caps) of a
## document of manifest format `format`.
static func parse(
	blobs: Dictionary, doc: MapDocument, warn_log: MapDocumentIO._WarningLog, format: int
) -> void:
	if format == 1:
		_parse_slots(blobs, doc, warn_log)
	else:
		_parse_entries(blobs, doc, warn_log)


## Format 2: surfaces.json and the entry pair. Unknown surface names are kept; they resolve
## against the palette at load and draw as the fallback earth.
static func _parse_entries(
	blobs: Dictionary, doc: MapDocument, warn_log: MapDocumentIO._WarningLog
) -> void:
	var ids: Variant = _surface_list(blobs, [INDEX_ENTRY, WEIGHT_ENTRY], warn_log)
	if ids == null:
		return
	for entry_name in [INDEX_ENTRY, WEIGHT_ENTRY]:
		if not blobs.has(entry_name):
			warn_log.add("surfaces.json without %s; painted surfaces dropped" % entry_name)
			return
	var rgba := Image.FORMAT_RGBA8
	var index := MapDocumentIO._parse_mask(blobs[INDEX_ENTRY], doc, rgba, INDEX_ENTRY, warn_log)
	if index.is_empty():
		return
	var weight := MapDocumentIO._parse_mask(blobs[WEIGHT_ENTRY], doc, rgba, WEIGHT_ENTRY, warn_log)
	if weight.is_empty():
		return
	var fixed := SurfaceEntries.canonical(index + weight, doc.sample_count(), ids.size())
	if fixed["dropped"] > 0:
		warn_log.add("surfaces: %d entries name an unlisted surface, dropped" % fixed["dropped"])
	if fixed["merged"] > 0:
		warn_log.add("surfaces: %d samples name a surface twice, merged" % fixed["merged"])
	if fixed["over"] > 0:
		warn_log.add("surfaces: %d samples sum past 255, scaled down" % fixed["over"])
	doc.surface_ids = ids
	doc.surface_weights = fixed["weights"]


## Format 1: surfaces.json, surfaces.png and surfaces_b.png (one weight channel per slot,
## at most FORMAT_1_SLOTS), migrated to entries (SurfaceEntries.from_slots).
static func _parse_slots(
	blobs: Dictionary, doc: MapDocument, warn_log: MapDocumentIO._WarningLog
) -> void:
	var ids: Variant = _surface_list(blobs, [SLOTS_A_ENTRY, SLOTS_B_ENTRY], warn_log)
	if ids == null:
		return
	if ids.size() > MapDocument.FORMAT_1_SLOTS:
		var cap := MapDocument.FORMAT_1_SLOTS
		warn_log.add("surfaces.json: more than %d surfaces in format 1; dropped" % cap)
		return
	if not blobs.has(SLOTS_A_ENTRY):
		warn_log.add("surfaces.json without surfaces.png; painted surfaces dropped")
		return
	var rgba := Image.FORMAT_RGBA8
	var plane_a := MapDocumentIO._parse_mask(
		blobs[SLOTS_A_ENTRY], doc, rgba, SLOTS_A_ENTRY, warn_log
	)
	if plane_a.is_empty():
		return
	var plane_b := PackedByteArray()
	if ids.size() > MapDocument.SURFACE_CHANNELS:
		if blobs.has(SLOTS_B_ENTRY):
			var b_bytes: PackedByteArray = blobs[SLOTS_B_ENTRY]
			plane_b = MapDocumentIO._parse_mask(b_bytes, doc, rgba, SLOTS_B_ENTRY, warn_log)
		if plane_b.is_empty():
			warn_log.add("surfaces 5-%d have no usable surfaces_b.png; dropped" % ids.size())
			ids = ids.slice(0, MapDocument.SURFACE_CHANNELS)
	elif blobs.has(SLOTS_B_ENTRY):
		warn_log.add("surfaces_b.png with %d surfaces listed; ignored" % ids.size())
	if plane_b.is_empty():
		plane_b.resize(plane_a.size())
	var migrated := SurfaceEntries.from_slots(plane_a + plane_b, doc.sample_count(), ids.size())
	if migrated["stray"] > 0:
		warn_log.add("surfaces: %d samples paint an unlisted slot, cleared" % migrated["stray"])
	if migrated["over"] > 0:
		warn_log.add("surfaces: %d samples sum past 255, scaled down" % migrated["over"])
	if migrated["crowded"] > 0:
		var crowded: int = migrated["crowded"]
		var kept := MapDocument.SURFACE_ENTRIES
		warn_log.add(
			"surfaces: %d samples paint over %d surfaces; weakest dropped" % [crowded, kept]
		)
	doc.surface_ids = ids
	doc.surface_weights = migrated["weights"]


## The parsed surfaces.json list when it names surfaces, else null (with a warning when
## `images`, the two image entries of the format being read, are present without one).
static func _surface_list(
	blobs: Dictionary, images: Array, warn_log: MapDocumentIO._WarningLog
) -> Variant:
	var has_png: bool = blobs.has(images[0]) or blobs.has(images[1])
	var ids: Variant = null
	if blobs.has(JSON_ENTRY):
		ids = _parse_ids(blobs[JSON_ENTRY], warn_log)
	elif has_png:
		warn_log.add("%s without surfaces.json; ignored" % images[0])
	if ids == null or ids.is_empty():
		if ids != null and has_png:
			warn_log.add("surfaces.json lists no surfaces; its images are ignored")
		return null
	return ids


static func _parse_ids(bytes: PackedByteArray, warn_log: MapDocumentIO._WarningLog) -> Variant:
	var data: Variant = MapDocumentIO._json(bytes, JSON_ENTRY, warn_log)
	var list: Variant = data.get("surfaces") if data is Dictionary else null
	if not list is Array:
		warn_log.add("surfaces.json needs a surfaces list; painted surfaces dropped")
		return null
	var problem_text := ids_problem(list)
	if problem_text != "":
		warn_log.add("surfaces.json: %s; painted surfaces dropped" % problem_text)
		return null
	return PackedStringArray(list)
