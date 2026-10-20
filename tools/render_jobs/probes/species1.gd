extends RefCounted

## Render-job probe for treecube's species rounds (the bench's nine-placed views, treecube
## scripts/bench.py).
## `action`:
## - `grid` (`biome`, `species`, `n`, `cols`, `spacing` m, `shift` [dx, dz] m): places `n` props of
##   the species on a grid centred `shift` from the ground point at the screen centre, then pans
##   the camera by `shift` so the grid sits at the centre of the view.
## - `only` (`keep`: substrings): hides every MultiMeshInstance3D under the map whose name holds
##   none of them; `keep` empty hides them all. Logs a few names.
## - `show`: shows every MultiMeshInstance3D again.


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	match String(step.get("action", "")):
		"grid":
			return _grid(base, gm, step)
		"only":
			return _only(gm, step.get("keep", []))
		"show":
			for node in gm.map_container.find_children("*", "MultiMeshInstance3D", true, false):
				(node as Node3D).visible = true
			return "shown"
	return "unknown action"


static func _grid(base: Node, gm: GameMap, step: Dictionary) -> String:
	var c: AuthoringController = base.get("_authoring_controller")
	var rule: Dictionary = c.editor.species_rule(String(step.biome), String(step.species))
	if rule.is_empty():
		return "no species %s in %s" % [step.species, step.biome]
	var cc := gm.get_camera_controller()
	var off: Vector2 = cc.call("_get_view_center_ground_offset")
	var holder := gm.cameraholder_node
	var shift: Array = step.get("shift", [0.0, 0.0])
	var cx := holder.global_position.x + off.x + float(shift[0])
	var cz := holder.global_position.z + off.y + float(shift[1])
	var n := int(step.get("n", 9))
	var cols := int(step.get("cols", 3))
	var s := float(step.get("spacing", 2.0))
	var rows := ceili(float(n) / cols)
	for i in range(n):
		var x := cx + (float(i % cols) - (cols - 1) * 0.5) * s
		var z := cz + (float(int(i / cols)) - (rows - 1) * 0.5) * s
		var p: Vector3 = c.brush.bedded(Vector3(x, 0.0, z))
		c.editor.place_prop(rule, p, Vector3.UP)
		c.editor.commit_prop_edit()
	holder.global_position += Vector3(float(shift[0]), 0.0, float(shift[1]))
	return "placed %d %s at %.1f %.1f" % [n, step.species, cx, cz]


static func _only(gm: GameMap, keep: Array) -> String:
	var shown := 0
	var hidden := 0
	var names: Array[String] = []
	for node in gm.map_container.find_children("*", "MultiMeshInstance3D", true, false):
		var label := String(node.name)
		var ok := false
		for k in keep:
			if label.contains(String(k)):
				ok = true
		(node as Node3D).visible = ok
		if ok:
			shown += 1
			if names.size() < 4:
				names.append(label)
		else:
			hidden += 1
	return "only %s: shown %d hidden %d %s" % [str(keep), shown, hidden, str(names)]
