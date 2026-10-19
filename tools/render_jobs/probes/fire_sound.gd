extends RefCounted

## Render-job probe (`call` op) for the persistent fire's sound (FireSound, cards F7, F7b and
## F7c), in two actions:
##
## - "log" (the default): the camera's size and place in FireSound's frame, the clusters nearest
##   the view's middle with each one's distance from the camera's axis (aside), the players with
##   each one's place, gain, target and pan (its direction's sideways share in the listener's,
##   the camera's, frame: -1 hard left, 1 hard right), and the SFX bus's peak over the last mix,
##   read `step.reads` times (default 3), `step.gap_s` apart (default 0.25), on the main thread's
##   clock, since one peak reading holds only the last mixed block.
## - "aim": pans the view's middle onto a point of the fire (in FireSound's frame, taken to the
##   world): `step.target` "centroid" (the largest cluster's place plus `step.offset` [x, z]
##   metres), "gap" (the burning mask sample farthest from every cluster's place) or "edge" (from
##   the largest cluster's place along +x to the first sample under FireField.FLAME_MIN, then
##   `step.beyond_m` further). Follow it with a wait: the players re-pick on the next frame and
##   fade over about a second.


static func run(base: Node, step: Dictionary) -> String:
	var field := base.get_tree().get_first_node_in_group(FireField.GROUP) as FireField
	var sound: FireSound = field.sound() if field != null else null
	if String(step.get("action", "log")) == "aim":
		return _aim(base, field, sound, step)
	var out := "no fire sound"
	if sound != null:
		out = _describe(sound)
	var bus := AudioServer.get_bus_index(AudioManager.BUS_SFX)
	var peaks := PackedStringArray()
	var reads := int(step.get("reads", 3))
	for k in reads:
		if k > 0:
			OS.delay_msec(int(1000.0 * float(step.get("gap_s", 0.25))))
		var left := AudioServer.get_bus_peak_volume_left_db(bus, 0)
		var right := AudioServer.get_bus_peak_volume_right_db(bus, 0)
		peaks.append("%.1f/%.1f" % [left, right])
	return "%s; SFX bus peak L/R dB: %s" % [out, " ".join(peaks)]


## The view, the clusters near it and the players, as one line.
static func _describe(sound: FireSound) -> String:
	var camera := sound.get_viewport().get_camera_3d()
	var parts := PackedStringArray()
	var eye := Vector3.ZERO
	var axis := Vector3.DOWN
	if camera != null:
		var to_local := sound.global_transform.affine_inverse()
		eye = to_local * camera.global_position
		axis = (to_local.basis * -camera.global_basis.z).normalized()
		var scale := (to_local.basis * -camera.global_basis.z).length()
		var middle := _middle(eye, axis)
		parts.append(
			(
				"camera size %.2f (local %.2f), eye (%.1f, %.1f, %.1f), middle (%.2f, %.2f)"
				% [camera.size, camera.size * scale, eye.x, eye.y, eye.z, middle.x, middle.y]
			)
		)
	var near := PackedStringArray()
	var asides: Array = []
	for cluster in sound.clusters():
		var off: Vector3 = cluster["at"] - eye
		asides.append([(off - axis * off.dot(axis)).length(), cluster])
	asides.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for k in mini(6, asides.size()):
		var c: Dictionary = asides[k][1]
		near.append(
			(
				"(%.1f, %.1f) %.1f m2 aside %.2f"
				% [c["at"].x, c["at"].z, float(c["size"]), float(asides[k][0])]
			)
		)
	parts.append("clusters %d nearest: %s" % [sound.clusters().size(), ", ".join(near)])
	var places := PackedStringArray()
	var players := sound.players()
	for slot in players.size():
		var player := players[slot]
		var pan := 0.0
		if camera != null:
			var v := camera.global_transform.affine_inverse() * player.global_position
			pan = v.x / maxf(v.length(), 1e-6)
		places.append(
			(
				"(%.2f, %.2f) gain %.3f target %.3f %.1f dB pan %.2f"
				% [
					player.position.x,
					player.position.z,
					sound.gains()[slot],
					sound.targets()[slot],
					player.volume_db,
					pan
				]
			)
		)
	parts.append("players %d: %s" % [players.size(), ", ".join(places)])
	return "; ".join(parts)


## Where the camera's axis meets the ground plane (y 0) in FireSound's frame, as (x, z).
static func _middle(eye: Vector3, axis: Vector3) -> Vector2:
	if absf(axis.y) < 1e-6:
		return Vector2.INF
	var middle := eye + axis * (-eye.y / axis.y)
	return Vector2(middle.x, middle.z)


static func _aim(base: Node, field: FireField, sound: FireSound, step: Dictionary) -> String:
	if field == null or sound == null or sound.clusters().is_empty():
		return "aim: no fire"
	var clusters := sound.clusters()
	var doc := field.document
	var largest: Vector3 = clusters[0]["at"]
	var target := String(step.get("target", "centroid"))
	var point := Vector2(largest.x, largest.z)
	var note := ""
	match target:
		"centroid":
			var offset: Array = step.get("offset", [0.0, 0.0])
			point += Vector2(float(offset[0]), float(offset[1]))
		"gap":
			var best := -1.0
			var half := doc.extent_m() * 0.5
			var sample_step := doc.sample_step()
			for iz in doc.samples_z():
				for ix in doc.samples_x():
					if doc.fire_mask[doc.sample_index(ix, iz)] < FireField.FLAME_MIN:
						continue
					var p := -half + Vector2(ix, iz) * sample_step
					var nearest := INF
					for cluster in clusters:
						var at: Vector3 = cluster["at"]
						nearest = minf(nearest, p.distance_to(Vector2(at.x, at.z)))
					if nearest > best:
						best = nearest
						point = p
			note = " %.2f m from the nearest cluster" % best
		"edge":
			var x := point.x
			while FireField.mask_at(doc, Vector2(x, point.y)) >= FireField.FLAME_MIN:
				x += 0.25
			note = " flames end at x %.2f" % x
			point = Vector2(x + float(step.get("beyond_m", 2.0)), point.y)
	var world := sound.global_transform * Vector3(point.x, 0.0, point.y)
	var gm: GameMap = base.get("_game_map")
	var cc: CameraController = gm.get_camera_controller()
	var off: Vector2 = cc.call("_get_view_center_ground_offset")
	var holder := gm.cameraholder_node
	holder.global_position = Vector3(world.x - off.x, holder.global_position.y, world.z - off.y)
	return "aim %s at (%.2f, %.2f)%s" % [target, point.x, point.y, note]
