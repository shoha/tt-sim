class_name StructureLoadInfo
extends RefCounted

## What the structures of a map need from the decor library and from the document before their
## nodes can be made, as pure data a loader's worker computes (staged_load2, docs/systems/
## structure_performance.md "Fifth round"). Before it the main thread did all of it inside
## AuthoredStructures.create, the one frame of a staged load that still cost 130 to 160 ms for 128
## structures: the first read of the decor library's meshes (108 ms), the plant plans a worker
## could not make without it (44 ms) and the structures' keys (25 ms).
##
## Thread-safe: AssetStore parses a GLB under its own lock (a mesh is read, never changed, here)
## and the keys read the document only. The wind-dressed copies and baked surfaces that
## AuthoredStructures makes from the same meshes stay on the main thread, a structure at a time as
## its node is made.


## The decor library at palette `root` as StructureDecor.plan reads it: {"rows"
## (AssetStore.decor_rows), "by_id" (row id -> row), "cost" (row id -> triangles of its mesh, 0
## without one), "sig" (a hash of rows and costs: a plan made from another state is made again)}.
## Parses the meshes not parsed yet.
static func info_of(root: String) -> Dictionary:
	var rows := AssetStore.decor_rows(root)
	var by_id := {}
	var cost := {}
	for row in rows:
		by_id[row.id] = row
		cost[row.id] = StructureDecor.triangles_of(
			AssetStore.mesh(str(row.library), str(row.id), root)
		)
	return {"rows": rows, "by_id": by_id, "cost": cost, "sig": hash([rows, cost])}


## The structures part of AuthoredLoadPrep for `doc`: StructureGeometry.build's result plus
## "keys" (StructureGeometry.keys_of), and, when `with_info` and the library serves decor plants,
## "info" (info_of) and "root" with the plans made on the worker. `with_info` is false for a
## worker that must not parse GLBs (the headless dummy renderer, GlbUtils.threaded_loads_safe):
## create then reads the library itself.
static func prepare(doc: MapDocument, root: String, with_info: bool) -> Dictionary:
	var decor := StructureDecor.available(root)
	var info := info_of(root) if decor and with_info else {}
	var out := StructureGeometry.build(doc, true, decor, info)
	out["keys"] = StructureGeometry.keys_of(doc, decor)
	if not info.is_empty():
		out["info"] = info
		out["root"] = root
	return out


## The decor info for a create from `built` (a prepare() result, or {}) at palette `root`: the
## worker's when it was made from the library as it is now, else read here.
static func info_for(built: Dictionary, root: String) -> Dictionary:
	var held: Dictionary = built.get("info", {})
	var same_root: bool = built.get("root", "") == root
	if not held.is_empty() and same_root and held.rows == AssetStore.decor_rows(root):
		return held
	return info_of(root)


## The keys of `doc`'s structures for a create from `built`: the worker's when it made them for the
## same structures, else computed here.
static func keys_for(doc: MapDocument, built: Dictionary, decor: bool) -> Dictionary:
	var held: Variant = built.get("keys")
	if held is Dictionary and (held as Dictionary).size() == doc.structures.size():
		for structure in doc.structures:
			if not (held as Dictionary).has(structure.id):
				return StructureGeometry.keys_of(doc, decor)
		return held
	return StructureGeometry.keys_of(doc, decor)
