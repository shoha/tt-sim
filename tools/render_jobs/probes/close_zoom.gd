extends RefCounted

## Render-job probe (`call` op) for trees at close zoom (Polish). `action`:
## - `camera` (default): logs the camera's size, local and world position, near and far, the
##   world height of the screen centre's and bottom corners' ray origins (where the near
##   plane cuts), and the camera's distance to the ground point at the screen centre.
## - `back` (`d`, metres): moves the camera `d` further back along its view axis without
##   changing the frame (an orthographic camera shows the same picture), so a capture can
##   tell a near-plane slice from canopies that simply fill the view. A later zoom resets it.
##   A negative `d` moves it nearer.
## - `near` (`near`, default 0.001): sets the camera's near; 0.001 is the plane before the
##   canopy hold (CameraController._hold_near_plane_over_canopies), for an old/new A/B.
## - `hold`: re-runs the camera placement, restoring the hold after `near` or `back`.
## - `shadow` (`max`): logs the sun's shadow max distance, splits and mode; sets the distance.
## - `fade` (`on`, default true): turns the close-zoom canopy fade off by setting canopy_part
##   to 0 on every foliage material that takes part, and back on by restoring exactly those
##   materials' parts. A GPU or look A/B.

## Material -> its canopy_part while the fade is off.
static var _faded: Dictionary = {}


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	var cam: Camera3D = gm.camera_node
	match String(step.get("action", "camera")):
		"back":
			var d := float(step.get("d", 10.0))
			cam.global_position += cam.global_basis.z.normalized() * d
			return "moved back %.2f m; %s" % [d, _describe(gm, cam)]
		"fade":
			return _fade(gm, bool(step.get("on", true)))
		"near":
			cam.near = float(step.get("near", 0.001))
			return "near set; %s" % _describe(gm, cam)
		"hold":
			gm.get_camera_controller().call("_update_camera_offset")
			return "hold restored; %s" % _describe(gm, cam)
		"shadow":
			var suns := base.get_tree().root.find_children("*", "DirectionalLight3D", true, false)
			if suns.is_empty():
				return "no sun"
			var sun := suns[0] as DirectionalLight3D
			if step.has("max"):
				sun.directional_shadow_max_distance = float(step.max)
			return (
				"sun shadow max %.1f splits %.2f %.2f %.2f mode %d"
				% [
					sun.directional_shadow_max_distance,
					sun.directional_shadow_split_1,
					sun.directional_shadow_split_2,
					sun.directional_shadow_split_3,
					sun.directional_shadow_mode
				]
			)
		_:
			return _describe(gm, cam)


static func _fade(gm: GameMap, on: bool) -> String:
	if on:
		for mat: ShaderMaterial in _faded:
			mat.set_shader_parameter("canopy_part", _faded[mat])
		var n := _faded.size()
		_faded.clear()
		return "canopy fade on for %d materials" % n
	for mat in WindFoliage.collect_foliage_shader_materials(gm.map_container):
		var part: Variant = mat.get_shader_parameter("canopy_part")
		if part is int and int(part) != 0 and not _faded.has(mat):
			mat.set_shader_parameter("canopy_part", 0)
			_faded[mat] = int(part)
	return "canopy fade off on %d materials" % _faded.size()


static func _describe(gm: GameMap, cam: Camera3D) -> String:
	var vp := Vector2(gm.world_viewport.size)
	var centre := cam.project_ray_origin(vp * 0.5)
	var bl := cam.project_ray_origin(Vector2(0.0, vp.y))
	var forward := -cam.global_basis.z.normalized()
	# Distance along the view axis from the centre ray origin to the y = 0 plane.
	var to_ground := centre.y / maxf(-forward.y, 0.001)
	return (
		(
			"size %.2f local %s world %s near %.3f far %.1f | origin y: centre %.2f bottom %.2f"
			+ " | centre ray to y=0 %.2f m"
		)
		% [
			cam.size,
			str(cam.position),
			str(cam.global_position),
			cam.near,
			cam.far,
			centre.y,
			bl.y,
			to_ground
		]
	)
