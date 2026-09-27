extends RefCounted

## Render-job probe (`call` op) for the Paint tool (phase 3, P3-6): at each map point of
## `points` ([[x, z], ...] world metres), the painted weights of the open authoring map's
## document (surface -> 0..255 at the nearest sample), what the ground lets grow there
## (ScatterGround's sampler: open, rock and scree shares) and how many scatter rows stand
## within `r` metres (default 0.75) and of which assets, and the nearest row's distance, so
## a look pass can tell a plant
## left on a path by the rules from one the regeneration never reached.


static func run(root: Node, step: Dictionary) -> String:
	var ctrl := root.get("_authoring_controller") as AuthoringController
	if ctrl == null or ctrl.editor == null:
		return "no authoring map"
	var doc := ctrl.document
	var radius := float(step.get("r", 0.75))
	var sampler := ScatterGround.sampler(
		doc,
		doc.heights,
		Rect2i(0, 0, doc.samples_x(), doc.samples_z()),
		PackedStringArray(PaletteLibrary.surfaces_with_role("built")),
		PackedStringArray(PaletteLibrary.surfaces_with_role("cliff"))
	)
	var rows: Dictionary = ctrl.scatter.rows_by_asset() if ctrl.scatter else {}
	var lines := PackedStringArray()
	for value in step.get("points", []):
		var p := Vector2(float(value[0]), float(value[1]))
		var at := doc.world_to_sample(p).round()
		var sample := doc.sample_index(int(at.x), int(at.y))
		var weights := PackedStringArray()
		for s in doc.surface_ids.size():
			var w := doc.surface_weight(sample, s)
			if w > 0:
				weights.append("%s %d" % [doc.surface_ids[s], w])
		var g: Vector3 = sampler.call(p)
		var near := {}
		var closest := INF
		for asset_id in rows:
			var flat: PackedFloat32Array = rows[asset_id]
			for r in range(0, flat.size(), MapDocument.ROW_STRIDE):
				var d := Vector2(flat[r], flat[r + 2]).distance_to(p)
				closest = minf(closest, d)
				if d <= radius:
					near[asset_id.get_file()] = int(near.get(asset_id.get_file(), 0)) + 1
		lines.append(
			(
				"%s paint [%s] open %.2f rock %.2f scree %.2f rows %s nearest %.2f m"
				% [p, ", ".join(weights), g.x, g.y, g.z, str(near), closest]
			)
		)
	return "\n".join(lines)
