class_name MapDocumentIO
extends RefCounted

## Reads and writes `map.ttmap`, the ZIP document holding everything authored in tt-sim
## for one level (MapDocument is the in-memory form and documents the geometry). The
## format is tt-sim-internal, not a producer contract; it is summarised in
## docs/ARCHITECTURE.md "Map document (map.ttmap)".
##
## Format 2 entries (format 1 differs only in its painted surfaces, below):
##   manifest.json          {"format": 2, "palette_version", "map_seed", "size_cells": [w, h],
##                          "cell_size_m", "sample_spacing_m", "tier_height_m",
##                          "base_surface", "has_base_map"}                        required
##   height.bin             float32 little-endian heights on the sample grid        required
##   scatter.json           {asset id: [[lx, ly, lz, qx, qy, qz, qw, sx, sy, sz], ...]}
##   props.json             same shape, hand-placed assets
##   erase.png              8-bit greyscale on the sample grid, > 127 = erased
##   authoring/biomes.png   R = biome slot (0 none, else index + 1), G = density
##   authoring/biomes.json  {"biomes": [palette biome id, ...]}; required with biomes.png
##   surfaces.json          {"surfaces": [palette surface name, ...]}, at most 64
##   surfaces_index.png     RGBA8 on the sample grid: four indices into surfaces.json
##   surfaces_weight.png    RGBA8 on the sample grid: their four weights, high to low, 0 =
##                          unused (MapDocument's header has the canonical form)
##   splines.json           water bodies and flow map metadata         (MapWaterIO)
##   ponds.png              8-bit pond ids on the sample grid           (MapWaterIO)
##   water_flow.png         the baked flow map, RG8 as RGB              (MapWaterIO)
##   crossings.json         plank bridges and stepping stones           (MapCrossingIO)
##   fire.png               8-bit greyscale fire intensity on the sample grid, 0 = no fire;
##                          never written all zero, and an all-zero one reads as none
##   mass_anchors.json      grass-mass anchors, (dx, dz) per scatter row   (MapAnchorsIO)
## Unknown entries are ignored (_known_entries and _extract_entries only look at
## KNOWN_ENTRIES), so the surfaces, water, crossings, fire and anchors entries needed no
## format bump: an older build reads a document with water as if it had none, and one with
## crossings, fire or anchors as if it had none. Format 2 replaced format 1's surfaces.png
## (slots 0-3 in R, G, B, A) and surfaces_b.png (slots 4-7, at most 8 surfaces) with the
## entry pair, so it is a bump: a format 1 build refuses a format 2 document rather than
## read it as unpainted and lose the paint on its next save. The reader accepts both and
## migrates format 1 (MapSurfacesIO, which reads and writes the surface entries); it never
## writes format 1.
##
## Documents arrive from a host peer, so everything read is untrusted input, validated in
## the style of PaletteLibrary.validate_palette(): caps are checked before anything is
## allocated, NaN and Inf are rejected, a malformed row or optional entry is skipped with
## a warning, and nothing here raises. A document too broken to use (no manifest, bad
## geometry, missing or inconsistent heights) comes back as null with its warnings.
## JSON is parsed with JSON, PNGs with Image, heights by reinterpreting bytes; nothing
## goes through bytes_to_var.
##
## ZIPReader.read_file() sizes its buffer from the size the archive declares, so read()
## first reads every declared size from the ZIP central directory (ZipEntrySizes, which
## documents the probe) and only calls read_file on an entry within its cap and the total.
##
## write() is atomic: the new document is packed into `<path>.tmp` in the same directory
## and renamed over the target, so a failure at any step leaves the previous file as it
## was. Probed on Windows (4.7.1): DirAccess.rename_absolute over an existing file
## replaces it, so no remove-first window is needed; while another handle holds the target
## open, the rename fails with ERR_FAILED and both files are left untouched.

const MANIFEST_ENTRY := "manifest.json"
const HEIGHT_ENTRY := "height.bin"
const SCATTER_ENTRY := "scatter.json"
const PROPS_ENTRY := "props.json"
const ERASE_ENTRY := "erase.png"
const BIOMES_PNG_ENTRY := "authoring/biomes.png"
const BIOMES_JSON_ENTRY := "authoring/biomes.json"
const SURFACES_JSON_ENTRY := "surfaces.json"
const SURFACES_INDEX_ENTRY := "surfaces_index.png"
const SURFACES_WEIGHT_ENTRY := "surfaces_weight.png"
## Format 1's painted surfaces, read (and migrated) only from a format 1 document.
const SURFACES_PNG_ENTRY := "surfaces.png"
const SURFACES_B_PNG_ENTRY := "surfaces_b.png"
const FIRE_ENTRY := "fire.png"
## Every entry this format reads, in the order they are written and read.
const KNOWN_ENTRIES: Array[String] = [
	MANIFEST_ENTRY,
	HEIGHT_ENTRY,
	SCATTER_ENTRY,
	PROPS_ENTRY,
	ERASE_ENTRY,
	BIOMES_JSON_ENTRY,
	BIOMES_PNG_ENTRY,
	SURFACES_JSON_ENTRY,
	SURFACES_INDEX_ENTRY,
	SURFACES_WEIGHT_ENTRY,
	SURFACES_PNG_ENTRY,
	SURFACES_B_PNG_ENTRY,
	MapWaterIO.SPLINES_ENTRY,
	MapWaterIO.PONDS_ENTRY,
	MapWaterIO.FLOW_ENTRY,
	MapCrossingIO.ENTRY,
	FIRE_ENTRY,
	MapAnchorsIO.ENTRY,
]
const TEMP_SUFFIX := ".tmp"

## Uncompressed bytes per entry. height.bin is exact at the sample cap. A PNG of the
## largest grid is under 2 MB even incompressible (641 x 641 x 4 for RGBA). The row entries
## bound JSON.parse, which builds its whole Variant tree before any row cap can apply, so
## their byte caps are the real bound on parse memory; at about 90 bytes per written row,
## 32 MB is ~350,000 scatter rows. splines.json at its caps (32 rivers of 512 points) is
## about 0.8 MB of JSON; a 1024 x 1024 flow map is 3 MB even incompressible. crossings.json at
## its cap (64 crossings) is about 16 KB.
const ENTRY_CAPS := {
	MANIFEST_ENTRY: 64 * 1024,
	HEIGHT_ENTRY: MapDocument.MAX_SAMPLES_PER_AXIS * MapDocument.MAX_SAMPLES_PER_AXIS * 4,
	SCATTER_ENTRY: 32 * 1024 * 1024,
	PROPS_ENTRY: 8 * 1024 * 1024,
	ERASE_ENTRY: 4 * 1024 * 1024,
	BIOMES_PNG_ENTRY: 4 * 1024 * 1024,
	BIOMES_JSON_ENTRY: 64 * 1024,
	SURFACES_JSON_ENTRY: 64 * 1024,
	SURFACES_INDEX_ENTRY: 4 * 1024 * 1024,
	SURFACES_WEIGHT_ENTRY: 4 * 1024 * 1024,
	SURFACES_PNG_ENTRY: 4 * 1024 * 1024,
	SURFACES_B_PNG_ENTRY: 4 * 1024 * 1024,
	MapWaterIO.SPLINES_ENTRY: 2 * 1024 * 1024,
	MapWaterIO.PONDS_ENTRY: 4 * 1024 * 1024,
	MapWaterIO.FLOW_ENTRY: 4 * 1024 * 1024,
	MapCrossingIO.ENTRY: 256 * 1024,
	FIRE_ENTRY: 4 * 1024 * 1024,
	MapAnchorsIO.ENTRY: 16 * 1024 * 1024,
}
const MAX_TOTAL_BYTES := 64 * 1024 * 1024
## The archive file itself, checked before it is opened.
const MAX_ARCHIVE_BYTES := 64 * 1024 * 1024
const MAX_ARCHIVE_ENTRIES := 1024
const MAX_CENTRAL_DIRECTORY_BYTES := 1024 * 1024
const MAX_ROWS_PER_ASSET := 200000
const MAX_TOTAL_ROWS := 1000000
const MAX_ASSETS := 8192
const MAX_ID_LENGTH := 200
const MAX_TEXT_LENGTH := 128
## Row components beyond this are corrupt (and 1e300 would become Inf as float32).
const MAX_ROW_COMPONENT := 100000.0
## Integers survive a JSON double exactly up to 2^53.
const MAX_SEED := 9007199254740992
## At most this many warnings are kept; the rest are counted in one closing line.
const MAX_WARNINGS := 50
## Decimals written per row component: 1 um in position, far below float32 noise in the
## quaternion, and the reason a row costs ~90 bytes of JSON instead of ~170.
const ROW_DECIMALS := 6
## The step ROW_DECIMALS rounds to (snap_rows).
const ROW_STEP := 0.000001

const _PNG_SIGNATURE := [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]


## Bounded warning collector: keeps the first MAX_WARNINGS and counts the rest, so a
## document with a million bad rows cannot build a million strings.
class _WarningLog:
	var items: PackedStringArray = PackedStringArray()
	var dropped: int = 0

	func add(message: String) -> void:
		if items.size() < MAX_WARNINGS:
			items.append(message)
		else:
			dropped += 1

	func result() -> PackedStringArray:
		var out := items.duplicate()
		if dropped > 0:
			out.append("%d more problems not listed" % dropped)
		return out


## Writes `doc` to `path` atomically (see the header). Returns OK, or the error of the
## step that failed; a document that violates the reader's caps is refused with
## ERR_INVALID_DATA and a warning naming the problem, so nothing is ever written that
## read() would reject or trim.
static func write(doc: MapDocument, path: String) -> Error:
	var packed := serialize(doc)
	if packed["error"] != "":
		push_warning("MapDocumentIO: not writing %s: %s" % [path, packed["error"]])
		return ERR_INVALID_DATA
	var temp_path := path + TEMP_SUFFIX
	var err := _write_zip(temp_path, packed["entries"])
	if err == OK:
		err = DirAccess.rename_absolute(temp_path, path)
	if err == OK:
		MapFileHash.invalidate(path)
	if err != OK and FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(temp_path)
	return err


## Reads and validates the document at `path`. Returns {"document": MapDocument or null,
## "warnings": PackedStringArray}; never raises and never prints (the caller decides how
## to surface warnings).
static func read(path: String) -> Dictionary:
	var warn_log := _WarningLog.new()
	var entries: Variant = _extract_entries(path, warn_log)
	var doc: MapDocument = null
	if entries is Dictionary:
		doc = _parse_document(entries, warn_log)
	return {"document": doc, "warnings": warn_log.result()}


## Validates already-extracted entries (entry name -> PackedByteArray), with the same
## caps read() applies. Pure: the testable core of read().
static func parse(entries: Dictionary) -> Dictionary:
	var warn_log := _WarningLog.new()
	var doc := _parse_document(entries, warn_log)
	return {"document": doc, "warnings": warn_log.result()}


## The entries write() would store: {"entries": Dictionary[String, PackedByteArray],
## "error": String}. Pure. `error` is non-empty (and `entries` empty) when the document
## breaks a rule the reader enforces.
static func serialize(doc: MapDocument) -> Dictionary:
	var entries: Dictionary[String, PackedByteArray] = {}
	var problem := _writable_problem(doc)
	if problem != "":
		return {"entries": entries, "error": problem}
	entries[MANIFEST_ENTRY] = JSON.stringify(_manifest(doc), "\t", false, true).to_utf8_buffer()
	entries[HEIGHT_ENTRY] = doc.heights.to_byte_array()
	entries[SCATTER_ENTRY] = _rows_json(doc.scatter).to_utf8_buffer()
	entries[PROPS_ENTRY] = _rows_json(doc.props).to_utf8_buffer()
	if not doc.erase_mask.is_empty():
		entries[ERASE_ENTRY] = _png(doc.erase_mask, doc, Image.FORMAT_L8)
	if not doc.biome_ids.is_empty():
		var biomes := {"biomes": Array(doc.biome_ids)}
		entries[BIOMES_JSON_ENTRY] = JSON.stringify(biomes, "\t").to_utf8_buffer()
	if not doc.biome_slots.is_empty():
		var interleaved := _interleave(doc.biome_slots, doc.biome_density)
		entries[BIOMES_PNG_ENTRY] = _png(interleaved, doc, Image.FORMAT_RG8)
	if not doc.surface_ids.is_empty():
		MapSurfacesIO.serialize(doc, entries)
	MapWaterIO.serialize(doc, entries)
	MapCrossingIO.serialize(doc, entries)
	if has_fire(doc.fire_mask):
		entries[FIRE_ENTRY] = _png(doc.fire_mask, doc, Image.FORMAT_L8)
	MapAnchorsIO.serialize(doc, entries)
	var total := 0
	for entry_name in entries:
		var size := entries[entry_name].size()
		total += size
		if size > ENTRY_CAPS[entry_name]:
			var message := "%s is %d bytes, over its cap of %d"
			return {"entries": {}, "error": message % [entry_name, size, ENTRY_CAPS[entry_name]]}
	if total > MAX_TOTAL_BYTES:
		return {
			"entries": {}, "error": "entries total %d bytes, over %d" % [total, MAX_TOTAL_BYTES]
		}
	return {"entries": entries, "error": ""}


# --- writing --------------------------------------------------------------------------


static func _write_zip(path: String, entries: Dictionary) -> Error:
	var packer := ZIPPacker.new()
	var err := packer.open(path)
	if err != OK:
		return err
	for entry_name in KNOWN_ENTRIES:
		if not entries.has(entry_name):
			continue
		err = packer.start_file(entry_name)
		if err == OK:
			err = packer.write_file(entries[entry_name])
		if err == OK:
			err = packer.close_file()
		if err != OK:
			packer.close()
			return err
	return packer.close()


static func _manifest(doc: MapDocument) -> Dictionary:
	return {
		"format": MapDocument.FORMAT,
		"palette_version": doc.palette_version,
		"map_seed": doc.map_seed,
		"size_cells": [doc.size_cells.x, doc.size_cells.y],
		"cell_size_m": doc.cell_size_m,
		"sample_spacing_m": doc.sample_spacing_m,
		"tier_height_m": doc.tier_height_m,
		"base_surface": doc.base_surface,
		"has_base_map": doc.has_base_map,
	}


## Rounds every value of `rows`, in place, to ROW_DECIMALS decimals, as writing and reading
## map.ttmap does: ScatterGenerator snaps the rows it generates, so a cell regenerated in a
## session and the same cell loaded from the saved file are equal bit for bit (no 1 um
## difference to flip MapFingerprint's 1 mm rounding). Each value is the float32 the array
## holds, as when it is written.
static func snap_rows(rows: PackedFloat32Array) -> void:
	for i in rows.size():
		rows[i] = snappedf(rows[i], ROW_STEP)


## Rows as compact JSON, built as text rather than through JSON.stringify so a large
## document never exists as a tree of boxed Arrays, and so each number carries only
## ROW_DECIMALS decimals. Asset ids are sorted for a stable file.
static func _rows_json(rows_by_asset: Dictionary[String, PackedFloat32Array]) -> String:
	var assets := PackedStringArray()
	var ids := rows_by_asset.keys()
	ids.sort()
	for asset_id in ids:
		var flat: PackedFloat32Array = rows_by_asset[asset_id]
		var rows := PackedStringArray()
		for start in range(0, flat.size(), MapDocument.ROW_STRIDE):
			var numbers := PackedStringArray()
			for k in MapDocument.ROW_STRIDE:
				numbers.append(String.num(flat[start + k], ROW_DECIMALS))
			rows.append("[" + ",".join(numbers) + "]")
		assets.append(JSON.stringify(asset_id) + ":[" + ",".join(rows) + "]")
	return "{" + ",".join(assets) + "}"


## A PNG of one grid-sized byte buffer. FORMAT_RG8 is stored as an RGB PNG with B = 0
## (PNG has no two-channel colour type other than grey + alpha; probed on 4.7.1), and
## the reader converts back to RG8.
static func _png(data: PackedByteArray, doc: MapDocument, format: Image.Format) -> PackedByteArray:
	var image := Image.create_from_data(doc.samples_x(), doc.samples_z(), false, format, data)
	return image.save_png_to_buffer()


static func _interleave(first: PackedByteArray, second: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(first.size() * 2)
	for i in first.size():
		out[i * 2] = first[i]
		out[i * 2 + 1] = second[i]
	return out


## The first rule `doc` breaks that the reader enforces, or "" when it can be written.
static func _writable_problem(doc: MapDocument) -> String:
	if doc == null:
		return "no document"
	var geometry := _geometry_problem(
		doc.size_cells, doc.cell_size_m, doc.sample_spacing_m, doc.tier_height_m
	)
	if geometry != "":
		return geometry
	if doc.palette_version.length() > MAX_TEXT_LENGTH:
		return "palette_version is too long"
	if doc.base_surface.length() > MAX_TEXT_LENGTH:
		return "base_surface is too long"
	if absi(doc.map_seed) > MAX_SEED:
		return "map_seed does not fit a JSON number exactly"
	var count := doc.sample_count()
	if doc.heights.size() != count:
		return "heights hold %d samples, the grid has %d" % [doc.heights.size(), count]
	if _first_bad_height(doc.heights) >= 0:
		return "heights hold a NaN, Inf or out-of-range value"
	if not doc.erase_mask.is_empty() and doc.erase_mask.size() != count:
		return "erase_mask does not match the sample grid"
	if not doc.fire_mask.is_empty() and doc.fire_mask.size() != count:
		return "fire_mask does not match the sample grid"
	var biomes := _biomes_problem(doc, count)
	if biomes != "":
		return biomes
	var surfaces := MapSurfacesIO.problem(doc, count)
	if surfaces != "":
		return surfaces
	var water := MapWaterIO.problem(doc)
	if water != "":
		return water
	var crossings := MapCrossingIO.problem(doc)
	if crossings != "":
		return crossings
	var total_rows := 0
	for rows_by_asset in [doc.props, doc.scatter]:
		var rows_problem := _rows_problem(rows_by_asset)
		if rows_problem != "":
			return rows_problem
		total_rows += MapDocument.row_count(rows_by_asset)
	if total_rows > MAX_TOTAL_ROWS:
		return "%d rows in total, over %d" % [total_rows, MAX_TOTAL_ROWS]
	return ""


static func _biomes_problem(doc: MapDocument, count: int) -> String:
	if doc.biome_ids.size() > MapDocument.MAX_BIOMES:
		return "more than %d biomes" % MapDocument.MAX_BIOMES
	for biome_id in doc.biome_ids:
		if not _is_id(biome_id):
			return "biome id '%s' is empty or too long" % _label(biome_id)
	if doc.biome_slots.is_empty():
		return "" if doc.biome_density.is_empty() else "biome_density without biome_slots"
	if doc.biome_ids.is_empty():
		return "biome_slots without biome_ids"
	if doc.biome_slots.size() != count or doc.biome_density.size() != count:
		return "biome masks do not match the sample grid"
	for slot in doc.biome_slots:
		if slot > doc.biome_ids.size():
			return "a biome slot names biome %d of %d" % [slot, doc.biome_ids.size()]
	return ""


@warning_ignore("integer_division")
static func _rows_problem(rows_by_asset: Dictionary[String, PackedFloat32Array]) -> String:
	if rows_by_asset.size() > MAX_ASSETS:
		return "more than %d asset ids" % MAX_ASSETS
	for asset_id in rows_by_asset:
		if not _is_id(asset_id):
			return "asset id '%s' is empty or too long" % _label(asset_id)
		var flat: PackedFloat32Array = rows_by_asset[asset_id]
		if flat.size() % MapDocument.ROW_STRIDE != 0:
			return "asset '%s' has a partial row" % asset_id
		if flat.size() / MapDocument.ROW_STRIDE > MAX_ROWS_PER_ASSET:
			return "asset '%s' has more than %d rows" % [asset_id, MAX_ROWS_PER_ASSET]
		for start in range(0, flat.size(), MapDocument.ROW_STRIDE):
			if not row_ok(flat, start):
				return "asset '%s' has a non-finite or degenerate row" % asset_id
	return ""


# --- reading the archive --------------------------------------------------------------


## Known entries of the archive at `path` (name -> bytes), each read only after its
## declared size passed its cap and the running total; null when the file is missing,
## oversized, or not a ZIP this reader will open.
static func _extract_entries(path: String, warn_log: _WarningLog) -> Variant:
	if not FileAccess.file_exists(path):
		warn_log.add("no map document at %s" % path)
		return null
	var sizes: Variant = _entry_sizes(path, warn_log)
	if not sizes is Dictionary:
		return null
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		warn_log.add("%s cannot be opened as a ZIP" % path)
		return null
	var entries := {}
	var total := 0
	for entry_name in KNOWN_ENTRIES:
		if not sizes.has(entry_name):
			continue
		var declared: int = sizes[entry_name]
		if not _size_allowed(entry_name, declared, total, warn_log):
			continue
		if not reader.file_exists(entry_name):
			warn_log.add("%s is listed but cannot be read; ignored" % entry_name)
			continue
		total += declared
		entries[entry_name] = reader.read_file(entry_name)
	reader.close()
	return entries


## Declared uncompressed size of every entry (name -> bytes, the larger one for a
## repeated name), read from the ZIP central directory without trusting anything else;
## null (with a warning) when the file is not a plain ZIP within the caps (ZipEntrySizes).
static func _entry_sizes(path: String, warn_log: _WarningLog) -> Variant:
	var found := ZipEntrySizes.read(
		path, MAX_ARCHIVE_BYTES, MAX_ARCHIVE_ENTRIES, MAX_CENTRAL_DIRECTORY_BYTES
	)
	if found["error"] != "":
		warn_log.add(found["error"])
	return found["sizes"]


## True when an entry of `size` bytes may be kept after `total` bytes already were.
static func _size_allowed(
	entry_name: String, size: int, total: int, warn_log: _WarningLog
) -> bool:
	if size > ENTRY_CAPS[entry_name]:
		warn_log.add(
			(
				"%s is %d bytes, over its cap of %d; ignored"
				% [entry_name, size, ENTRY_CAPS[entry_name]]
			)
		)
		return false
	if total + size > MAX_TOTAL_BYTES:
		warn_log.add(
			"%s would take the document over %d bytes; ignored" % [entry_name, MAX_TOTAL_BYTES]
		)
		return false
	return true


# --- validating entries ---------------------------------------------------------------


static func _parse_document(entries: Dictionary, warn_log: _WarningLog) -> MapDocument:
	var blobs := _known_entries(entries, warn_log)
	if not blobs.has(MANIFEST_ENTRY):
		warn_log.add("no usable manifest.json")
		return null
	var meta := {}
	var doc := _parse_manifest(blobs[MANIFEST_ENTRY], warn_log, meta)
	if doc == null:
		return null
	if not blobs.has(HEIGHT_ENTRY):
		warn_log.add("no usable height.bin")
		return null
	var heights: Variant = _parse_heights(blobs[HEIGHT_ENTRY], doc.sample_count(), warn_log)
	if heights == null:
		return null
	doc.heights = heights
	# Props first: hand-placed assets are the scarcer work if the row budget runs out.
	doc.props = _parse_rows(blobs.get(PROPS_ENTRY), PROPS_ENTRY, MAX_TOTAL_ROWS, warn_log)
	var remaining := MAX_TOTAL_ROWS - MapDocument.row_count(doc.props)
	doc.scatter = _parse_rows(blobs.get(SCATTER_ENTRY), SCATTER_ENTRY, remaining, warn_log)
	if blobs.has(ERASE_ENTRY):
		doc.erase_mask = _parse_mask(
			blobs[ERASE_ENTRY], doc, Image.FORMAT_L8, ERASE_ENTRY, warn_log
		)
	_parse_biomes(blobs, doc, warn_log)
	MapSurfacesIO.parse(blobs, doc, warn_log, meta["format"])
	MapWaterIO.parse(blobs, doc, warn_log)
	MapCrossingIO.parse(blobs, doc, warn_log)
	if blobs.has(FIRE_ENTRY):
		var fire := _parse_mask(blobs[FIRE_ENTRY], doc, Image.FORMAT_L8, FIRE_ENTRY, warn_log)
		doc.fire_mask = fire if has_fire(fire) else PackedByteArray()
	MapAnchorsIO.parse(blobs, doc, warn_log)
	return doc


## True when `fire_mask` holds any burning sample (a mask that is all zero is no fire: it is
## never written, and reads as empty). Pure.
static func has_fire(fire_mask: PackedByteArray) -> bool:
	return not fire_mask.is_empty() and fire_mask.count(0) != fire_mask.size()


## The known entries of `entries` that are byte buffers within their caps, in
## KNOWN_ENTRIES order. Unknown names are ignored without a warning.
static func _known_entries(entries: Dictionary, warn_log: _WarningLog) -> Dictionary:
	var blobs := {}
	var total := 0
	for entry_name in KNOWN_ENTRIES:
		if not entries.has(entry_name):
			continue
		var bytes: Variant = entries[entry_name]
		if not bytes is PackedByteArray:
			warn_log.add("%s is not a byte buffer; ignored" % entry_name)
			continue
		if not _size_allowed(entry_name, bytes.size(), total, warn_log):
			continue
		total += bytes.size()
		blobs[entry_name] = bytes
	return blobs


## The document's geometry and scalars from manifest.json, or null; `meta` receives the
## "format" read (MIN_FORMAT..FORMAT).
static func _parse_manifest(
	bytes: PackedByteArray, warn_log: _WarningLog, meta: Dictionary
) -> MapDocument:
	var data: Variant = _json(bytes, MANIFEST_ENTRY, warn_log)
	if not data is Dictionary:
		warn_log.add("manifest.json is not a JSON object")
		return null
	var format: Variant = _integer(data.get("format"), MapDocument.MIN_FORMAT, MapDocument.FORMAT)
	if format == null:
		warn_log.add("unsupported map document format %s" % _label(data.get("format")))
		return null
	meta["format"] = format
	var cells: Variant = data.get("size_cells")
	var width: Variant = null
	var height: Variant = null
	if cells is Array and cells.size() == 2:
		width = _integer(cells[0], MapDocument.MIN_SIZE_CELLS, MapDocument.MAX_SIZE_CELLS)
		height = _integer(cells[1], MapDocument.MIN_SIZE_CELLS, MapDocument.MAX_SIZE_CELLS)
	var cell_size: Variant = _number(data.get("cell_size_m"))
	var spacing: Variant = _number(data.get("sample_spacing_m"))
	var tier: Variant = _number(data.get("tier_height_m"))
	if width == null or height == null or cell_size == null or spacing == null:
		warn_log.add("manifest.json needs size_cells, cell_size_m and sample_spacing_m")
		return null
	var geometry := _geometry_problem(
		Vector2i(width, height), cell_size, spacing, tier if tier != null else cell_size
	)
	if geometry != "":
		warn_log.add("manifest.json: " + geometry)
		return null
	var doc := MapDocument.new()
	doc.size_cells = Vector2i(width, height)
	doc.cell_size_m = cell_size
	doc.sample_spacing_m = spacing
	if tier != null:
		doc.tier_height_m = tier
	else:
		warn_log.add("manifest.json: no tier_height_m, using one cell")
		doc.tier_height_m = cell_size
	doc.palette_version = _text_field(data, "palette_version", MAX_TEXT_LENGTH, warn_log)
	doc.base_surface = _text_field(data, "base_surface", MAX_TEXT_LENGTH, warn_log)
	var seed_value: Variant = _integer(data.get("map_seed"), -MAX_SEED, MAX_SEED)
	if seed_value == null:
		warn_log.add("manifest.json: map_seed missing or not an integer, using 0")
	doc.map_seed = seed_value if seed_value != null else 0
	var base_map: Variant = data.get("has_base_map")
	if not base_map is bool:
		warn_log.add("manifest.json: has_base_map missing or not a bool, using false")
	doc.has_base_map = base_map if base_map is bool else false
	return doc


## "" when the geometry is inside every domain limit, else what is wrong. Pure; shared by
## the reader (before any grid is allocated) and the writer.
static func _geometry_problem(
	cells: Vector2i, cell_size: float, spacing: float, tier: float
) -> String:
	var low := MapDocument.MIN_SIZE_CELLS
	var high := MapDocument.MAX_SIZE_CELLS
	if cells.x < low or cells.x > high or cells.y < low or cells.y > high:
		return "size_cells %s outside %d..%d" % [cells, low, high]
	if not _within(cell_size, MapDocument.MIN_CELL_SIZE_M, MapDocument.MAX_CELL_SIZE_M):
		return "cell_size_m %s out of range" % cell_size
	if not _within(spacing, MapDocument.MIN_SAMPLE_SPACING_M, MapDocument.MAX_SAMPLE_SPACING_M):
		return "sample_spacing_m %s out of range" % spacing
	if not _within(tier, MapDocument.MIN_TIER_HEIGHT_M, MapDocument.MAX_TIER_HEIGHT_M):
		return "tier_height_m %s out of range" % tier
	var extent := Vector2(cells) * cell_size
	var samples := Vector2i(
		MapDocument.samples_for(extent.x, spacing), MapDocument.samples_for(extent.y, spacing)
	)
	if samples.x > MapDocument.MAX_SAMPLES_PER_AXIS or samples.y > MapDocument.MAX_SAMPLES_PER_AXIS:
		return "%s samples, over %d per axis" % [samples, MapDocument.MAX_SAMPLES_PER_AXIS]
	return ""


## The heights, or null (with a warning) unless the buffer holds exactly `count` finite
## float32 values within MAX_ABS_HEIGHT_M. The size is checked before decoding.
## to_float32_array() reads the host's byte order; every platform Godot ships is
## little-endian, which is what the format specifies.
static func _parse_heights(
	bytes: PackedByteArray, count: int, warn_log: _WarningLog
) -> Variant:
	if bytes.size() != count * 4:
		warn_log.add(
			"height.bin is %d bytes, the grid needs exactly %d" % [bytes.size(), count * 4]
		)
		return null
	var heights := bytes.to_float32_array()
	var bad := _first_bad_height(heights)
	if bad >= 0:
		warn_log.add("height.bin sample %d is NaN, Inf or out of range" % bad)
		return null
	return heights


static func _first_bad_height(heights: PackedFloat32Array) -> int:
	for i in heights.size():
		var h := heights[i]
		if is_nan(h) or is_inf(h) or absf(h) > MapDocument.MAX_ABS_HEIGHT_M:
			return i
	return -1


## Asset id -> flat rows from one rows entry, keeping at most `budget` rows. Malformed
## assets are skipped and malformed rows dropped, each with one warning per asset.
@warning_ignore("integer_division")
static func _parse_rows(
	bytes: Variant, label: String, budget: int, warn_log: _WarningLog
) -> Dictionary[String, PackedFloat32Array]:
	var result: Dictionary[String, PackedFloat32Array] = {}
	if bytes == null:
		return result
	var data: Variant = _json(bytes, label, warn_log)
	if data == null:
		return result
	if not data is Dictionary:
		warn_log.add("%s is not a JSON object; ignored" % label)
		return result
	var ids: Array = data.keys()
	if ids.size() > MAX_ASSETS:
		warn_log.add(
			(
				"%s: %d asset ids over the cap of %d ignored"
				% [label, ids.size() - MAX_ASSETS, MAX_ASSETS]
			)
		)
		ids = ids.slice(0, MAX_ASSETS)
	var remaining := budget
	for asset_id in ids:
		var rows: Variant = data[asset_id]
		if not _is_id(asset_id) or not rows is Array:
			warn_log.add(
				"%s: asset '%s' skipped: malformed id or rows" % [label, _label(asset_id)]
			)
			continue
		var take := mini(rows.size(), MAX_ROWS_PER_ASSET)
		if rows.size() > MAX_ROWS_PER_ASSET:
			warn_log.add(
				"%s: asset '%s' keeps its first %d rows" % [label, asset_id, MAX_ROWS_PER_ASSET]
			)
		if take > remaining:
			warn_log.add(
				"%s: total row cap of %d reached at '%s'" % [label, MAX_TOTAL_ROWS, asset_id]
			)
			take = remaining
		var flat := _collect_rows(rows, take)
		var kept := flat.size() / MapDocument.ROW_STRIDE
		if kept < take:
			warn_log.add(
				"%s: asset '%s': %d malformed rows skipped" % [label, asset_id, take - kept]
			)
		if kept > 0:
			result[asset_id] = flat
			remaining -= kept
	return result


## The well-formed rows among the first `take` of `rows`, flattened. Allocates the
## capped size up front and writes in place; a rejected row is simply overwritten.
static func _collect_rows(rows: Array, take: int) -> PackedFloat32Array:
	var stride := MapDocument.ROW_STRIDE
	var flat := PackedFloat32Array()
	flat.resize(take * stride)
	var kept := 0
	for i in take:
		var row: Variant = rows[i]
		if not row is Array or row.size() != stride:
			continue
		var numeric := true
		for k in stride:
			var value: Variant = row[k]
			if value is bool or not (value is float or value is int):
				numeric = false
				break
			flat[kept * stride + k] = value
		if numeric and row_ok(flat, kept * stride):
			kept += 1
	flat.resize(kept * stride)
	return flat


## True when the row at `start` is finite, within MAX_ROW_COMPONENT, and has a rotation
## that normalizes (a zero quaternion would turn into a NaN basis). The writer, the reader and
## a live edit's decoder (LiveEditReader) check every row with it.
static func row_ok(flat: PackedFloat32Array, start: int) -> bool:
	for k in MapDocument.ROW_STRIDE:
		var value := flat[start + k]
		if is_nan(value) or is_inf(value) or absf(value) > MAX_ROW_COMPONENT:
			return false
	var rotation := Vector4(flat[start + 3], flat[start + 4], flat[start + 5], flat[start + 6])
	return rotation.length_squared() > 1e-6


## One grid-sized mask from a PNG, or empty (with a warning). The PNG header's size is
## checked against the grid before decoding, so a small file cannot declare a huge image.
static func _parse_mask(
	bytes: PackedByteArray,
	doc: MapDocument,
	format: Image.Format,
	label: String,
	warn_log: _WarningLog
) -> PackedByteArray:
	var grid := Vector2i(doc.samples_x(), doc.samples_z())
	var declared := _png_size(bytes)
	if declared == Vector2i.ZERO:
		warn_log.add("%s is not a PNG; ignored" % label)
		return PackedByteArray()
	if declared != grid:
		warn_log.add("%s is %s, the sample grid is %s; ignored" % [label, declared, grid])
		return PackedByteArray()
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK or image.get_size() != grid:
		warn_log.add("%s could not be decoded; ignored" % label)
		return PackedByteArray()
	if image.get_format() != format:
		image.convert(format)
	return image.get_data()


## Width and height from a PNG's IHDR chunk, or Vector2i.ZERO when `bytes` does not
## start like a PNG. Pure; reads 24 bytes and allocates nothing.
static func _png_size(bytes: PackedByteArray) -> Vector2i:
	if bytes.size() < 24:
		return Vector2i.ZERO
	for i in _PNG_SIGNATURE.size():
		if bytes[i] != _PNG_SIGNATURE[i]:
			return Vector2i.ZERO
	if bytes.slice(12, 16).get_string_from_ascii() != "IHDR":
		return Vector2i.ZERO
	return Vector2i(_u32_big_endian(bytes, 16), _u32_big_endian(bytes, 20))


static func _u32_big_endian(bytes: PackedByteArray, at: int) -> int:
	return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]


## Fills the biome fields from authoring/biomes.json and authoring/biomes.png. Both are
## authoring-only (regenerable), so any problem drops them with a warning instead of
## rejecting the document. The mask needs the id list; the list alone is kept.
static func _parse_biomes(blobs: Dictionary, doc: MapDocument, warn_log: _WarningLog) -> void:
	var has_png := blobs.has(BIOMES_PNG_ENTRY)
	if not blobs.has(BIOMES_JSON_ENTRY):
		if has_png:
			warn_log.add("authoring/biomes.png without authoring/biomes.json; ignored")
		return
	var ids: Variant = _parse_biome_ids(blobs[BIOMES_JSON_ENTRY], warn_log)
	if ids == null:
		return
	doc.biome_ids = ids
	if not has_png:
		return
	var data := _parse_mask(
		blobs[BIOMES_PNG_ENTRY], doc, Image.FORMAT_RG8, BIOMES_PNG_ENTRY, warn_log
	)
	if data.is_empty():
		return
	var count := doc.sample_count()
	var slots := PackedByteArray()
	var density := PackedByteArray()
	slots.resize(count)
	density.resize(count)
	var unknown := 0
	for i in count:
		var slot := data[i * 2]
		if slot > ids.size():
			unknown += 1
			slot = 0
		slots[i] = slot
		density[i] = data[i * 2 + 1]
	if unknown > 0:
		warn_log.add("authoring/biomes.png: %d samples name no listed biome, cleared" % unknown)
	doc.biome_slots = slots
	doc.biome_density = density


static func _parse_biome_ids(bytes: PackedByteArray, warn_log: _WarningLog) -> Variant:
	var data: Variant = _json(bytes, BIOMES_JSON_ENTRY, warn_log)
	var list: Variant = data.get("biomes") if data is Dictionary else null
	if not list is Array or list.size() > MapDocument.MAX_BIOMES:
		warn_log.add(
			"authoring/biomes.json needs a biomes list of at most %d" % MapDocument.MAX_BIOMES
		)
		return null
	var ids := PackedStringArray()
	for biome_id in list:
		if not _is_id(biome_id):
			warn_log.add(
				"authoring/biomes.json: biome id '%s' malformed; biomes ignored" % _label(biome_id)
			)
			return null
		ids.append(biome_id)
	return ids


# --- small pure helpers ---------------------------------------------------------------


## Parsed JSON, or null with a warning. Bytes that are not UTF-8 decode to garbage the
## parser then rejects.
static func _json(bytes: PackedByteArray, label: String, warn_log: _WarningLog) -> Variant:
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		warn_log.add(
			(
				"%s is not valid JSON (line %d: %s)"
				% [label, json.get_error_line(), json.get_error_message()]
			)
		)
		return null
	return json.data


## A finite number as float, else null. JSON numbers are all floats; a bool is not one.
static func _number(value: Variant) -> Variant:
	if value is bool or not (value is float or value is int):
		return null
	var number := float(value)
	if is_nan(number) or is_inf(number):
		return null
	return number


## A whole number within [low, high] as int, else null.
static func _integer(value: Variant, low: int, high: int) -> Variant:
	var number: Variant = _number(value)
	if number == null or number != floorf(number) or number < low or number > high:
		return null
	return int(number)


static func _within(value: float, low: float, high: float) -> bool:
	return not is_nan(value) and value >= low and value <= high


## An optional short string field; "" with a warning when present but wrong.
static func _text_field(
	data: Dictionary, field: String, max_length: int, warn_log: _WarningLog
) -> String:
	var value: Variant = data.get(field)
	if value is String and value.length() <= max_length:
		return value
	warn_log.add('manifest.json: %s missing, not a string or too long; using ""' % field)
	return ""


## Palette ids (asset, biome and surface) are opaque here: any non-empty String up to
## MAX_ID_LENGTH. Unknown ids are kept; they are resolved against the palette at load.
static func _is_id(value: Variant) -> bool:
	return value is String and value != "" and value.length() <= MAX_ID_LENGTH


static func _label(value: Variant) -> String:
	var text := str(value)
	return text if text.length() <= 48 else text.substr(0, 48) + "..."
