class_name MapAnchorsIO
extends RefCounted

## Reads and writes the grass-mass anchors entry of `map.ttmap` (MapDocument.mass_anchors;
## contract: docs/ASSET_PIPELINE.md section 9, "Saved levels: mass anchors"):
##   mass_anchors.bin    {asset id: [dx0, dz0, dx1, dz1, ...]} in MapRowsCodec's column form
##                       ("TTAN"), one (dx, dz) per row of that asset in scatter.bin, in row
##                       order, metres from the row to its anchor, on the STEP grid
## Optional. Format 4 stores it binary (formats 1 to 3 had `mass_anchors.json`; the format bump
## refuses those documents whole, MapDocumentIO). parse() runs after the scatter rows are read and
## keeps an asset's offsets only when they are within MAX_OFFSET_M and exactly two per scatter row
## of that asset; anything else is dropped with a warning. The check against each rule's reach
## needs the palette and happens where the anchors are loaded (ScatterMass.table_of).

const ENTRY := "mass_anchors.bin"
## One unit of the grid the offsets are snapped to: 0.1 mm, far below a tuft. Not a power of two,
## so the code of a stored float32 is found by rounding; that is exact while the float32 spacing
## stays under STEP (offsets below about 1600 m, MAX_OFFSET_M keeps well inside).
const STEP := 0.0001
## No mass reaches this far; a larger offset is corrupt.
const MAX_OFFSET_M := 1000.0


## `offset` rounded to the STEP grid written, as saving and reading the level does. The
## generator snaps every offset it makes (ScatterMass.collect), as it snaps the rows, so a map
## built in a session and the same map reopened carry the same offsets bit for bit: unsnapped,
## a mass whose anchor lay within 0.05 mm of a GroundMassStamps.ANCHOR_GRID line split in two
## on reopening and its shade stamp moved (2026-10-15).
static func snap(offset: float) -> float:
	return snappedf(offset, STEP)


## Adds the entry to `entries` when `doc` has anchors. An asset whose offsets do not match its
## scatter rows (two per row) or lie beyond MAX_OFFSET_M is left out, so nothing is written
## that parse() would drop.
@warning_ignore("integer_division")
static func serialize(doc: MapDocument, entries: Dictionary) -> void:
	var kept: Dictionary[String, PackedFloat32Array] = {}
	for asset_id: String in doc.mass_anchors:
		var offsets: PackedFloat32Array = doc.mass_anchors[asset_id]
		var rows: PackedFloat32Array = doc.scatter.get(asset_id, PackedFloat32Array())
		if offsets.is_empty() or offsets.size() != rows.size() / MapDocument.ROW_STRIDE * 2:
			continue
		if _out_of_range(offsets):
			continue
		kept[asset_id] = offsets
	if not kept.is_empty():
		entries[ENTRY] = MapDocumentIO.codec().encode_offsets(kept, STEP)


## Reads the entry from `blobs` into `doc.mass_anchors` (see the header); none when absent.
@warning_ignore("integer_division")
static func parse(
	blobs: Dictionary, doc: MapDocument, warn_log: MapDocumentIO._WarningLog
) -> void:
	doc.mass_anchors = {}
	if not blobs.has(ENTRY):
		return
	var data: Dictionary = MapDocumentIO.codec().decode_offsets(
		blobs[ENTRY], STEP, MAX_OFFSET_M, ENTRY, warn_log
	)
	for asset_id in data:
		var rows: PackedFloat32Array = doc.scatter.get(asset_id, PackedFloat32Array())
		var offsets: PackedFloat32Array = data[asset_id]
		if offsets.size() != rows.size() / MapDocument.ROW_STRIDE * 2 or rows.is_empty():
			warn_log.add(
				(
					"%s: '%s' dropped: %d offsets for %d rows"
					% [
						ENTRY,
						MapDocumentIO._label(asset_id),
						offsets.size() / 2,
						rows.size() / MapDocument.ROW_STRIDE
					]
				)
			)
		else:
			doc.mass_anchors[asset_id] = offsets


## True when an offset is not finite or beyond MAX_OFFSET_M.
static func _out_of_range(offsets: PackedFloat32Array) -> bool:
	for value in offsets:
		if is_nan(value) or is_inf(value) or absf(value) > MAX_OFFSET_M:
			return true
	return false
