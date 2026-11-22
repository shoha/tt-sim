class_name PainterTreeRows
extends RefCounted

## The painted trees' pure halves (docs/systems/painter.md "Trees"), split from PainterTrees: the
## LISTING of the scatters' tree rows a sync draws (wanted(), whole or one landed cell at a time,
## card painter-edit-hitch2) and the TABLES of the drawn trees (the row map's role rows and eight
## nearest crowns, and the occluder table). Nothing here holds state; PainterTrees uploads.


## Every mapped tree row of `scatters` as key -> {"pos", "species", "asset", "cx", "seed"}, and a
## bush's also "box" (PainterTreeBush.box_of; a bush whose asset has not resolved is left out)
## (pure in the rows, the document and the resolved meshes); `glb` adds a GLB map's rows.
static func wanted(scatters: Array, doc: MapDocument, glb := {}) -> Dictionary:
	var out := PainterGlbMap.wanted(glb, doc)
	for scatter in scatters:
		# A hidden scatter (the eye view's rim in the orbit view) draws nothing, painted or not.
		if not is_instance_valid(scatter) or not scatter.visible:
			continue
		want_rows(out, scatter.rows_by_asset(), scatter, doc)
	return out


## wanted()'s entries for the rows `by_asset` (asset id -> flat rows) of `scatter`, into `out`.
static func want_rows(
	out: Dictionary, by_asset: Dictionary, scatter: Node, doc: MapDocument
) -> void:
	var stride := MapDocument.ROW_STRIDE
	var resolved := {}
	for asset_id: String in by_asset:
		var species := PainterTreeSpecies.species_for(asset_id)
		if species == "":
			continue
		var aabb := AABB()
		if PainterTreeSpecies.is_bush(species):
			if resolved.is_empty():
				resolved = scatter.resolved_species()
			var mesh: Mesh = (resolved.get(asset_id, {}) as Dictionary).get("mesh")
			if mesh == null:
				continue
			aabb = mesh.get_aabb()
		var rows: PackedFloat32Array = by_asset[asset_id]
		for i in rows.size() / stride:
			var p := Vector3(rows[i * stride], rows[i * stride + 1], rows[i * stride + 2])
			var key := PainterTreeSpecies.key_of(p)
			var scale := rows[i * stride + PainterTreeSpecies.SCALE_AT]
			out[key] = {
				"pos": p,
				"species": species,
				"asset": asset_id,
				"cx": PainterTreeSpecies.context(asset_id, scale, p, density_at(doc, p)),
				"seed": PainterTreeSpecies.seed_of(key)
			}
			if PainterTreeSpecies.is_bush(species):
				out[key]["box"] = PainterTreeBush.box_of(aabb, scale)


## The keys of the mapped rows `by_asset` (one cell of a scatter), wanted() or not (a bush whose
## asset has not resolved is listed too: listing a key nothing draws erases nothing).
static func keys_of(by_asset: Dictionary) -> Array:
	var stride := MapDocument.ROW_STRIDE
	var keys: Array = []
	for asset_id: String in by_asset:
		if PainterTreeSpecies.species_for(asset_id) == "":
			continue
		var rows: PackedFloat32Array = by_asset[asset_id]
		for i in rows.size() / stride:
			keys.append(
				PainterTreeSpecies.key_of(
					Vector3(rows[i * stride], rows[i * stride + 1], rows[i * stride + 2])
				)
			)
	return keys


## The document's biome density (0..1) at the sample nearest `p`, 0.5 without one.
static func density_at(doc: MapDocument, p: Vector3) -> float:
	if doc == null or doc.biome_density.size() != doc.sample_count():
		return 0.5
	var s := doc.world_to_sample(Vector2(p.x, p.z))
	var x := clampi(roundi(s.x), 0, doc.samples_x() - 1)
	var z := clampi(roundi(s.y), 0, doc.samples_z() - 1)
	return doc.biome_density[doc.sample_index(x, z)] / 255.0


## The row map (each tree's role rows and its eight nearest crowns within `near_m`, `map_w` floats
## a line) and the occluder table of the drawn `trees` (PainterTrees.trees) over `lines` rows:
## {"rows", "occ"}.
static func tables(trees: Dictionary, lines: int, map_w: int, near_m: float) -> Dictionary:
	var rows := PackedFloat32Array()
	rows.resize(map_w * lines)
	rows.fill(-1.0)
	var occ := PackedFloat32Array()
	occ.resize(lines * 8)
	var grid := {}
	var conifers := {}
	for key: Vector3i in trees:
		var t: Dictionary = trees[key]
		if t["bush"]:
			# (A bush is no tree's neighbouring form: the eight a tree lists stay its trees.)
			continue
		if PainterTreeTones.has_variants(t["species"]):
			conifers[key] = t["pos"]
		var gc := Vector2i(floori(t["pos"].x / 9.0), floori(t["pos"].z / 9.0))
		if not grid.has(gc):
			grid[gc] = []
		grid[gc].append(t)
	# Each conifer's needle variant (painter-look-taiga): its seed's pick, none shared by near trees.
	var variants := PainterConiferVariants.assign(conifers)
	for key: Vector3i in trees:
		var t: Dictionary = trees[key]
		var p: Vector3 = t["pos"]
		var row: int = t["row"]
		var line := PainterTreeTones.role_rows(t["species"], int(variants.get(key, 0)))
		for r in line.size():
			rows[row * map_w + r] = float(line[r])
		var near: Array = []
		var gc := Vector2i(floori(p.x / 9.0), floori(p.z / 9.0))
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				for q: Dictionary in grid.get(gc + Vector2i(dx, dz), []):
					var dist := (q["pos"] as Vector3).distance_to(p)
					if q != t and dist < near_m:
						near.append(Vector2(dist, float(q["row"])))
		near.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		for k in mini(near.size(), 8):
			rows[row * map_w + 9 + k] = (near[k] as Vector2).y
		_occluder(occ, lines, row, p, (t["d"] as Dictionary)["forms"])
	return {"rows": rows, "occ": occ}


static func _occluder(
	occ: PackedFloat32Array, lines: int, row: int, p: Vector3, forms: Array
) -> void:
	var ow := row * 4
	if forms.is_empty():
		occ[ow] = p.x
		occ[ow + 1] = -50.0
		occ[ow + 2] = p.z
		occ[ow + 3] = 1.0
		for k in 3:
			occ[lines * 4 + ow + k] = 0.1
		return
	var form: Dictionary = forms[0]
	var c: Vector3 = form["c"]
	var r: Vector3 = (form["r"] as Vector3) * 0.85
	occ[ow] = p.x + c.x
	occ[ow + 1] = p.y + c.y
	occ[ow + 2] = p.z + c.z
	occ[ow + 3] = float(form["kind"])
	occ[lines * 4 + ow] = r.x
	occ[lines * 4 + ow + 1] = r.y
	occ[lines * 4 + ow + 2] = r.z
