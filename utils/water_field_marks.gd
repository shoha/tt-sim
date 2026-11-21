class_name WaterFieldMarks
extends RefCounted

## The continuous marks of a WaterField (cards painter-water-mouths and painter-water-shoreline;
## docs/systems/water_field.md "Marks and the one shoreline"): what the Painted shader used to
## read from one enum per vertex (CUSTOM1.w: 0, film 0.125, bank spill 0.5, pond ramp 1).
## Interpolated across a triangle between a 0 and a 1 vertex that float passed through the film
## and bank-spill values, so every rule keyed to them drew a band along the border. Here each
## quantity is its own channel:
##
## - `film` (0 or 1 per sample): a stroke's water the dug bed no longer holds (WaterField's film).
##   The shader draws it as mid-depth water.
## - `bank` (0..1): the thin water a bank sheds, rising from 0 at the channel's edge to 1 over
##   BANK_SHARE_M beyond it (a function of the distance across the stroke, not of the grid). The
##   shader fades the wash of such water where it is under a few centimetres.
##
## Neither is read by the white at the water's edge. That white (the lap) is a function of
## `WaterField.shore` alone, the distance to the waterline of all the water together, so it needs
## no mark where water meets water: a mouth has no shore across it. The `mouth` distance and the
## per-sample stroke id this class held for one card (a fade of the lap towards the line between
## a mouth's two land corners) removed the lap from a pond's neck and from every land corner, and
## are gone.
##
## They ride CUSTOM2 of the field's mesh (WaterFieldMesh), interpolated per vertex: no texture
## fetch. Both are written in GDScript (the stroke's per-sample write is); the native mesh builder
## copies them into CUSTOM2 in its one call (card painter-water-editcost; it was a second call).

## The bank share reaches 1 this far beyond the channel's edge.
const BANK_SHARE_M := 0.25

var film := PackedFloat32Array()
var bank := PackedFloat32Array()


## Sizes the arrays to `n` samples, cleared.
func fit(n: int) -> void:
	film.resize(n)
	bank.resize(n)
	film.fill(0.0)
	bank.fill(0.0)


## Clears the marks in `rect` of `f`'s grid (the strokes that meet it write them again).
func reset(f: WaterField, rect: Rect2i) -> void:
	if rect == Rect2i(Vector2i.ZERO, f.size):
		film.fill(0.0)
		bank.fill(0.0)
		return
	for z in range(rect.position.y, rect.end.y):
		var row := z * f.size.x
		for i in range(row + rect.position.x, row + rect.end.x):
			film[i] = 0.0
			bank[i] = 0.0
