class_name TerraCorpus
extends RefCounted
## The terraforming test corpus (from spike terraform-s2-cpu, card terraform-p1-native): hills, a
## valley river with a bend and a tributary that falls off a hill and joins it, a pond, a path
## over a hill, a wall the river crosses, a few paint coats and a sculpt stroke. Laid out on a
## 61 m square drawn from (0, 0) and placed on a map document's centred frame (scaled to its
## extent), so the same corpus serves every map size.
##
## The primitives are a TerraDoc (`terra`, card terraform-p1-document), so the corpus is also a
## real terrain document: the map document IO tests save it and read it back. add, append,
## replace, remove and find are the TerraDoc's; make_derive skips muted primitives.

## The 200 ft map the layout was drawn on (40 cells of 5 ft).
const CELLS := 40
## Every terra test's pending reason without the library: CI greps the shard logs for its
## first words, so a library that did not load fails CI rather than passing quietly.
const NO_LIBRARY := "the native library is not built (AGENTS.md Testing): no current TerraDerive"

var map_doc: MapDocument
## The corpus's terrain document (also set as map_doc.terra).
var terra := TerraDoc.new()
## Metres of map per metre of the 61 m layout, and the layout's origin in world metres.
var scale := 1.0
var origin := Vector2.ZERO


## A corpus on a map of `cells` (x, z), the layout scaled to its x extent and centred.
## `with_extras` false stops after the main river (the base a test grows one primitive at a
## time).
static func build(cells := Vector2i(CELLS, CELLS), with_extras := true) -> TerraCorpus:
	var c := TerraCorpus.new()
	c.map_doc = MapDocument.new()
	c.map_doc.size_cells = cells
	c.map_doc.heights.resize(c.map_doc.sample_count())
	c.map_doc.terra = c.terra
	var ext := c.map_doc.extent_m()
	c.scale = ext.x / 61.0
	c.origin = -Vector2(61.0, 61.0) * c.scale * 0.5
	var s := c.scale
	# The plane's base is its height at the map centre: the layout's 2.0 at z = 0 tilted by -0.05/m.
	var tilt := -0.05 / s
	c.add(TerraCore.PLANE, PackedFloat32Array([2.0 - tilt * c.origin.y, 0.0, tilt]))
	var valley := [30, 0, 28, 12, 34, 22, 30, 32, 33, 42, 31, 52, 32, 61]
	c.add(TerraCore.RIDGE, c.line([-1.8, 9.0 * s, 1.5], valley))
	for h in [[14, 16, 6.0, 13], [47, 18, 4.0, 11], [19, 46, 3.5, 10], [50, 50, 2.5, 9]]:
		var p := c.at(h[0], h[1])
		c.add(TerraCore.HILL, PackedFloat32Array([p.x, p.y, h[2], h[3] * s, 2.0]))
	var main := [30, 0.5, 28, 12, 34, 22, 30, 32, 33, 42, 31, 52, 32, 60.5]
	c.add(TerraCore.RIVER, c.line([3.0, 0.6], main))
	if not with_extras:
		return c
	c.add(TerraCore.RIVER, c.line([2.0, 0.45], [10, 14, 16, 20, 24, 25, 31.6, 28]))
	var ring: Array = []
	for k in 14:
		var a := TAU * k / 14.0
		ring.append(46.0 + cos(a) * 4.5 * (1.0 + 0.12 * sin(3.0 * a)))
		ring.append(34.0 + sin(a) * 4.0)
	c.add(TerraCore.POND, c.line([0.7], ring))
	c.add(TerraCore.PATH, c.line([1.6], [4, 38, 12, 42, 19, 46, 26, 50]))
	c.add(TerraCore.WALL, c.line([1.2, 0.5], [22, 36, 40, 38]))
	c.add(TerraCore.PAINT, c.dabs([[52, 44, 2.5, 6], [54, 46, 2.0, 6], [42, 29, 2.0, 8]]))
	var stroke: Array = []
	for k in 8:
		stroke.append([38.0 + k * 0.6, 8.0, 2.5, 0.12, 0])
	c.add(TerraCore.STROKE, c.dabs(stroke))
	return c


## A TerraDerive on this corpus's grid with every primitive set, not yet derived (null without
## the library).
func make_derive() -> RefCounted:
	var n := TerraCore.make_derive(map_doc)
	if n != null:
		for p in terra.prims:
			if not TerraDoc.is_muted(p):
				n.call("set_prim", p["id"], p["kind"], p["data"])
	return n


## A layout point (metres on the 61 m drawing) in world metres.
func at(x: float, z: float) -> Vector2:
	return origin + Vector2(x, z) * scale


## A line primitive's floats: the header as given, then each layout point placed.
func line(header: Array, pts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array(header)
	for k in range(0, pts.size() - 1, 2):
		var p := at(pts[k], pts[k + 1])
		out.append(p.x)
		out.append(p.y)
	return out


## A dab list's floats: per dab its layout centre placed, the rest as given.
func dabs(list: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for d: Array in list:
		var p := at(d[0], d[1])
		out.append(p.x)
		out.append(p.y)
		for v in d.slice(2):
			out.append(float(v))
	return out


## Adds a primitive at the end of the document and returns its id (TerraDoc.add).
func add(kind: int, data: PackedFloat32Array) -> int:
	return terra.add(kind, data)


## Appends floats (whole dabs) to a primitive (TerraDoc.append).
func append(id: int, data: PackedFloat32Array) -> void:
	terra.append(id, data)


## Replaces a primitive's floats, keeping its place in the order (TerraDoc.replace).
func replace(id: int, data: PackedFloat32Array) -> void:
	terra.replace(id, data)


## Removes a primitive (TerraDoc.remove).
func remove(id: int) -> void:
	terra.remove(id)


## The primitive with `id`, or an empty Dictionary (TerraDoc.find).
func find(id: int) -> Dictionary:
	return terra.find(id)
