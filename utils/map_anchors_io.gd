class_name MapAnchorsIO
extends RefCounted

## Reads and writes the grass-mass anchors entry of `map.ttmap` (MapDocument.mass_anchors;
## contract: docs/ASSET_PIPELINE.md section 9, "Saved levels: mass anchors"):
##   mass_anchors.json   {asset id: [dx0, dz0, dx1, dz1, ...]}, one (dx, dz) per row of that
##                       asset in scatter.json, in row order, metres from the row to its anchor
## Optional and unknown to older builds, which read a document with it as if it had none (no
## format bump). parse() runs after the scatter rows are read and keeps an asset's offsets only
## when they are finite, within MAX_OFFSET_M and exactly two per scatter row of that asset;
## anything else is dropped with a warning. The check against each rule's reach needs the
## palette and happens where the anchors are loaded (ScatterMass.table_of).

const ENTRY := "mass_anchors.json"
## Decimals written per offset: 0.1 mm, far below a tuft.
const DECIMALS := 4
## One unit of the last decimal written (snap()).
const STEP := 0.0001
## No mass reaches this far; a larger offset is corrupt.
const MAX_OFFSET_M := 1000.0


## `offset` rounded to the DECIMALS written, as saving and reading the level does. The
## generator snaps every offset it makes (ScatterMass.collect), as it snaps the rows, so a map
## built in a session and the same map reopened carry the same offsets bit for bit: unsnapped,
## a mass whose anchor lay within 0.05 mm of a GroundMassStamps.ANCHOR_GRID line split in two
## on reopening and its shade stamp moved (2026-10-15).
static func snap(offset: float) -> float:
	return snappedf(offset, STEP)


## Adds the entry to `entries` when `doc` has anchors. An asset whose offsets do not match its
## scatter rows (two per row) is left out, so nothing is written that parse() would drop.
@warning_ignore("integer_division")
static func serialize(doc: MapDocument, entries: Dictionary) -> void:
	var assets := PackedStringArray()
	var ids := doc.mass_anchors.keys()
	ids.sort()
	for asset_id: String in ids:
		var offsets: PackedFloat32Array = doc.mass_anchors[asset_id]
		var rows: PackedFloat32Array = doc.scatter.get(asset_id, PackedFloat32Array())
		if offsets.is_empty() or offsets.size() != rows.size() / MapDocument.ROW_STRIDE * 2:
			continue
		var numbers := PackedStringArray()
		for value in offsets:
			numbers.append(String.num(value, DECIMALS))
		assets.append(JSON.stringify(asset_id) + ":[" + ",".join(numbers) + "]")
	if not assets.is_empty():
		entries[ENTRY] = ("{" + ",".join(assets) + "}").to_utf8_buffer()


## Reads the entry from `blobs` into `doc.mass_anchors` (see the header); none when absent.
@warning_ignore("integer_division")
static func parse(
	blobs: Dictionary, doc: MapDocument, warn_log: MapDocumentIO._WarningLog
) -> void:
	doc.mass_anchors = {}
	if not blobs.has(ENTRY):
		return
	var data: Variant = MapDocumentIO._json(blobs[ENTRY], ENTRY, warn_log)
	if data == null:
		return
	if not data is Dictionary:
		warn_log.add("%s is not a JSON object; ignored" % ENTRY)
		return
	for asset_id: Variant in data:
		var rows: PackedFloat32Array = doc.scatter.get(asset_id, PackedFloat32Array())
		var offsets: Variant = _offsets(data[asset_id])
		if offsets == null:
			warn_log.add(
				"%s: '%s' dropped: malformed offsets" % [ENTRY, MapDocumentIO._label(asset_id)]
			)
		elif offsets.size() != rows.size() / MapDocument.ROW_STRIDE * 2 or rows.is_empty():
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


## The finite offsets of a JSON array (an even count, each within MAX_OFFSET_M), or null.
static func _offsets(value: Variant) -> Variant:
	if not value is Array or value.size() % 2 != 0:
		return null
	var out := PackedFloat32Array()
	out.resize(value.size())
	for i in value.size():
		var number: Variant = MapDocumentIO._number(value[i])
		if number == null or absf(number) > MAX_OFFSET_M:
			return null
		out[i] = number
	return out
