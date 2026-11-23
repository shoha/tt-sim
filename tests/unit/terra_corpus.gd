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
## The terrace kind's id (utils/terraform/kinds/terrace/).
const TERRACE := 16
## The level kind's id (utils/terraform/kinds/level/).
const LEVEL := 17

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


## The corpus with a terrace stroke (kind 16, the registry's proof kind) stepping the east hill,
## last in the document so it reads the hill and the plane under it.
static func build_terraced(cells := Vector2i(CELLS, CELLS)) -> TerraCorpus:
	var c := build(cells)
	c.add(TERRACE, c.dabs(terrace_dabs(8, 0)))
	return c


## The terraced corpus with the sculpt kinds (card terraform-p2-sculpt-kinds): a flatten stroke
## over the west hill, a tier stroke and a tier cut on the north-west hill, a smooth stroke over
## the plane's slope and a folded sculpt raster (a bump, made here so the case does not depend on
## consolidate), so every registered kind is in a corpus.
static func build_sculpted(cells := Vector2i(CELLS, CELLS)) -> TerraCorpus:
	var c := build_terraced(cells)
	var flat := PackedFloat32Array()
	var tier := PackedFloat32Array()
	var cut := PackedFloat32Array()
	var smooth: Array = []
	for k in 10:
		flat.append_array(c.capsule(10.0 + k * 0.5, 14.0, 0.5, 0.0, [3.0, 4.5, 0.05, 0]))
		tier.append_array(c.capsule(16.0 + k * 0.3, 44.0, 0.3, 0.0, [2.5, 6.0, 0.0, 1]))
		cut.append_array(c.capsule(22.0, 41.0 + k * 0.3, 0.0, 0.3, [2.0, 4.0, 0.0, 2]))
		smooth.append([40.0 + k * 0.4, 56.0, 3.0, 0.04, 2])
	c.add(LEVEL, flat)
	c.add(LEVEL, tier + cut)
	c.add(TerraCore.STROKE, c.dabs(smooth))
	c.add(TerraCore.SCULPT, c.bump_raster(c.at(8.0, 52.0), 24, 0.4))
	return c


## A level dab's floats: the capsule from layout point (x, z) to (x + dx, z + dz), placed, then
## `rest` (radius, target_y, strength, edge) as given.
func capsule(x: float, z: float, dx: float, dz: float, rest: Array) -> PackedFloat32Array:
	var a := at(x, z)
	var b := at(x + dx, z + dz)
	return PackedFloat32Array([a.x, a.y, b.x, b.y] + rest)


## A sculpt raster (kind 9) of `n` squared derive samples whose first sample is the one nearest
## `corner`: a (1 - t^2)^2 bump of `height` metres, no smoothing layer.
func bump_raster(corner: Vector2, n: int, height: float) -> PackedFloat32Array:
	var gd := TerraCore.grid_for(map_doc)
	var size: Vector2i = gd["size"]
	var ext: Vector2 = gd["extent"]
	var step := Vector2(ext.x / (size.x - 1), ext.y / (size.y - 1))
	var i0 := roundi((corner.x + ext.x * 0.5) / step.x)
	var j0 := roundi((corner.y + ext.y * 0.5) / step.y)
	var out := PackedFloat32Array(
		[-ext.x * 0.5 + i0 * step.x, -ext.y * 0.5 + j0 * step.y, step.x, step.y, n, n, 1]
	)
	var half := (n - 1) * 0.5
	for j in n:
		for i in n:
			var t2 := (Vector2(i, j) - Vector2(half, half)).length_squared() / (half * half)
			out.append(height * (1.0 - t2) * (1.0 - t2) if t2 < 1.0 else 0.0)
	return out


## The ids of the oldest run of compose primitives a fold takes: from the first stroke, level or
## terrace, every compose primitive in a row (in document order, other stages skipped) that is one.
func sculpt_run() -> Array[int]:
	var foldable := [TerraCore.STROKE, TERRACE, LEVEL]
	var run: Array[int] = []
	for p in terra.prims:
		var kind := int(p["kind"])
		if TerraKinds.script_for(kind).STAGE != "compose":
			continue
		if kind in foldable:
			run.append(int(p["id"]))
		elif not run.is_empty():
			break
	return run


## The splice that folds the run `ids` into `rasters` (TerraDerive.consolidate's floats) at the
## run's place, new ids from next_id, and the splice that undoes it: {"edit", "inverse"}, each
## {"remove", "insert", "at", "next_id"} for TerraDoc.splice.
func fold_splice(ids: Array[int], rasters: Array) -> Dictionary:
	var at := terra.index_of(ids[0])
	var next := terra.next_id
	var insert: Array = []
	var made: Array = []
	for k in rasters.size():
		insert.append({"id": next + k, "kind": TerraCore.SCULPT, "flags": 0, "data": rasters[k]})
		made.append(next + k)
	var back: Array = []
	for id in ids:
		var p := terra.find(id)
		back.append({"id": id, "kind": p["kind"], "flags": p.get("flags", 0), "data": p["data"]})
	return {
		"edit": {"remove": ids, "insert": insert, "at": at, "next_id": next + rasters.size()},
		"inverse": {"remove": made, "insert": back, "at": at, "next_id": next},
	}


## Applies a fold_splice() side to the document; true when TerraDoc.splice took it.
func splice(s: Dictionary) -> bool:
	return terra.splice(s["remove"], s["insert"], s["at"], s["next_id"])


## `count` terrace dabs from dab `from` of the stroke across the east hill (layout metres).
static func terrace_dabs(count: int, from: int) -> Array:
	var out: Array = []
	for k in range(from, from + count):
		out.append([43.0 + k * 0.9, 15.0 + k * 0.5, 4.0, 0.6, 0.35])
	return out


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
