class_name StructureDoorPaint
extends RefCounted

## Whether the map's own paint already runs out of a building's door (a Dress laid its door paths
## as painted surfaces, which a split into buildings keeps, or the author painted a path). Then
## StructureDressing leaves out its alpha path ribbon there (the stepping stones and steps stay)
## so two paths do not lie on each other. Pure and safe on any thread: it reads the document's
## surface weights only. The answer is part of the structure's key
## (StructureDressing.ground_samples), so painting a door path and then rebuilding the structures
## (a split, any structure edit) draws the yard without the ribbon; a paint stroke alone does not
## rebuild a yard. Summary: docs/systems/settlements.md "Ground".

## How far out of the door the paint is read, metres: inside the ribbon's first 2 m.
const PROBES_M: Array[float] = [0.8, 1.8]
## The least painted cover (of 255) a probe point needs.
const MIN_COVER := 128


## 1.0 when paint covers every probe point out of the door at `door_at` facing `out`, else 0.0.
static func joined(doc: MapDocument, door_at: Vector2, out: Vector2) -> float:
	if doc.surface_weights.is_empty():
		return 0.0
	for metres in PROBES_M:
		if _cover(doc, door_at + out * metres) < MIN_COVER:
			return 0.0
	return 1.0


## The painted cover (the entries' weights added, 0..255) at the sample nearest `xz`.
static func _cover(doc: MapDocument, xz: Vector2) -> int:
	var sample := doc.world_to_sample(xz).round()
	var x := clampi(int(sample.x), 0, doc.samples_x() - 1)
	var z := clampi(int(sample.y), 0, doc.samples_z() - 1)
	var base := doc.sample_count() * MapDocument.SURFACE_CHANNELS
	base += doc.sample_index(x, z) * MapDocument.SURFACE_CHANNELS
	var total := 0
	for e in MapDocument.SURFACE_ENTRIES:
		total += doc.surface_weights[base + e]
	return mini(total, 255)
