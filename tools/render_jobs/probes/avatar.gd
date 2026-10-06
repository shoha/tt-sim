extends RefCounted

## Render-job probe (`call` op) for player avatar tokens (2026-10-05): a stand-in figure
## (probes/avatar_figure.gd: about 1.4K triangles, 19 humanoid bones) drawn with the probe
## toon shader (avatar_toon.gdshader, outline hull avatar_hull.gdshader as its next_pass),
## skinned to a Skeleton3D or baked to a static mesh, to decide whether avatars stay skinned
## and what the look takes. All figures share one mesh (skinned), one Skin and one material;
## the palette row is an instance uniform. `action`:
## - `info`: the figure mesh's triangles, vertices, format and bones.
## - `bench` (`runs`, default 20): medians of building the mesh, assembling one skinned
##   figure (skeleton, pose, MeshInstance3D), adding it to the tree, baking it with
##   MeshInstance3D.bake_mesh_from_current_skeleton_pose and with the probe's GDScript bake,
##   and the largest position difference between the two bakes.
## - `spawn` (`config` "<mode>_<count>", any prefix before them ignored, e.g. "r2_baked_30";
##   or `mode` "skinned" / "baked" and `count`; `at` [x, z], `spacing`): clears the figures and
##   places `count` on the ground in a staggered grid facing the camera, cycling two stances,
##   three proportions (base, stocky, slender) and four palettes. Logs the time it took.
## - `clear`: removes the figures.
## - `twin` (`mode`, `at`, `stance`, `variant`, `palette`): one figure alone, with the screen
##   rectangle it covers (world viewport pixels, from its posed vertices), for a pixel diff of
##   a skinned capture against a baked one (probes/avatar_diff.gd).
## - `params` (`pass` "body" or "hull", `params` {uniform: value}): sets uniforms on the shared
##   material; arrays of three become colours. Logs the old values.
## - `adopt` (`index`, `highlight`, `hidden`): hides real token `index`'s meshes and stands a
##   skinned figure in its place under the token's rigid body, so the token's selection glow,
##   drag and visibility act on it; `highlight` adds the selection glow, `hidden` sets the
##   token hidden from players (the GM's semi-transparent view).
## - `save` (`folder`, `replace`): writes the open authoring map as a `_avatarprobe_` level.
## - `cleanup`: deletes every `_avatarprobe_*` level folder.

const Figure := preload("res://tools/render_jobs/probes/avatar_figure.gd")
const TOON := preload("res://tools/render_jobs/probes/avatar_toon.gdshader")
const HULL := preload("res://tools/render_jobs/probes/avatar_hull.gdshader")
const HOLDER := "AvatarProbe"
const PREFIX := "_avatarprobe_"

## Palette rows, sRGB, one colour per block: skin, hair, top, skirt, cloak, boots, accent,
## face marks.
const PALETTES := [
	[
		Color(1.0, 0.80, 0.66),
		Color(0.88, 0.16, 0.22),
		Color(0.10, 0.64, 0.70),
		Color(0.99, 0.88, 0.56),
		Color(0.98, 0.54, 0.12),
		Color(0.44, 0.22, 0.34),
		Color(1.0, 0.82, 0.25),
		Color(0.12, 0.08, 0.20),
	],
	[
		Color(0.97, 0.77, 0.62),
		Color(1.0, 0.86, 0.40),
		Color(0.16, 0.38, 0.90),
		Color(0.96, 0.96, 1.0),
		Color(0.92, 0.16, 0.28),
		Color(0.20, 0.22, 0.46),
		Color(0.98, 0.76, 0.18),
		Color(0.10, 0.08, 0.22),
	],
	[
		Color(0.80, 0.56, 0.40),
		Color(0.14, 0.16, 0.36),
		Color(0.38, 0.78, 0.24),
		Color(0.96, 0.66, 0.22),
		Color(0.12, 0.56, 0.50),
		Color(0.50, 0.28, 0.18),
		Color(0.98, 0.42, 0.56),
		Color(0.10, 0.08, 0.16),
	],
	[
		Color(1.0, 0.85, 0.76),
		Color(0.66, 0.40, 0.96),
		Color(0.99, 0.40, 0.58),
		Color(0.34, 0.24, 0.70),
		Color(1.0, 0.90, 0.40),
		Color(0.34, 0.20, 0.46),
		Color(0.42, 0.92, 0.92),
		Color(0.14, 0.08, 0.22),
	],
]

static var _mesh: ArrayMesh = null
static var _skin: Skin = null
static var _material: ShaderMaterial = null


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	match String(step.get("action", "info")):
		"info":
			return _info()
		"bench":
			return _bench(gm, int(step.get("runs", 20)))
		"spawn":
			var mode := String(step.get("mode", "skinned"))
			var count := int(step.get("count", 8))
			if step.has("config"):
				var parts := String(step.config).split("_")
				mode = parts[parts.size() - 2]
				count = int(parts[parts.size() - 1])
			var at := _vec2(step.get("at", [0, 0]))
			return _spawn(gm, mode, count, at, float(step.get("spacing", 1.5)))
		"clear":
			_clear(gm)
			return "cleared"
		"twin":
			return _twin(gm, step)
		"params":
			return _params(String(step.get("pass", "body")), step.get("params", {}))
		"adopt":
			return _adopt(gm, step)
		"save":
			return _save(base, step)
		"cleanup":
			return _cleanup()
	return "unknown action %s" % step.get("action", "")


static func _ensure() -> void:
	if _mesh != null:
		return
	_mesh = Figure.build_mesh()
	_skin = Figure.build_skin()
	# Two atlas rows per palette: lit, then the shadow colour (_shadow_of).
	var img := Image.create(Figure.BLOCKS, PALETTES.size() * 2, false, Image.FORMAT_RGBA8)
	for row in PALETTES.size():
		for block in Figure.BLOCKS:
			img.set_pixel(block, row * 2, PALETTES[row][block])
			img.set_pixel(block, row * 2 + 1, _shadow_of(PALETTES[row][block]))
	var tex := ImageTexture.create_from_image(img)
	var hull := ShaderMaterial.new()
	hull.shader = HULL
	hull.set_shader_parameter("palette", tex)
	hull.set_shader_parameter("palette_rows", float(PALETTES.size()))
	_material = ShaderMaterial.new()
	_material.shader = TOON
	_material.set_shader_parameter("palette", tex)
	_material.set_shader_parameter("palette_rows", float(PALETTES.size()))
	_material.next_pass = hull


## A block's shadow colour, as an artist would pick it: hue turned toward red-magenta for
## warm colours (skin, gold, orange) and toward blue-violet for the rest, more saturated,
## at about 70 % value. Never toward grey.
static func _shadow_of(c: Color) -> Color:
	var warm := c.h < 0.17 or c.h > 0.85
	var target := 0.98 if warm else 0.70
	var dh := clampf(wrapf(target - c.h, -0.5, 0.5), -0.07, 0.07)
	return Color.from_hsv(wrapf(c.h + dh, 0.0, 1.0), minf(1.0, c.s * 1.2 + 0.12), c.v * 0.72)


static func _info() -> String:
	_ensure()
	var arrays := _mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var names := PackedStringArray()
	for b in Figure.BONES:
		names.append(String(b[0]))
	return (
		(
			"figure: %d triangles, %d vertices, format %d (tangent %s, color %s, bones %s), "
			+ "aabb %s, %d bones: %s"
		)
		% [
			verts.size() / 3,
			verts.size(),
			_mesh.surface_get_format(0),
			str(_mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_TANGENT != 0),
			str(_mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR != 0),
			str(_mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_BONES != 0),
			str(_mesh.get_aabb()),
			names.size(),
			", ".join(names),
		]
	)


static func _ms(t0: int) -> float:
	return (Time.get_ticks_usec() - t0) / 1000.0


static func _median(values: PackedFloat64Array) -> float:
	var s := values.duplicate()
	s.sort()
	return s[s.size() / 2] if not s.is_empty() else 0.0


static func _bench(gm: GameMap, runs: int) -> String:
	_ensure()
	var t_mesh := PackedFloat64Array()
	var t_skinned := PackedFloat64Array()
	var t_tree := PackedFloat64Array()
	var t_bake := PackedFloat64Array()
	var t_cpu := PackedFloat64Array()
	var worst_diff := 0.0
	var tangent := false
	for r in runs:
		var t0 := Time.get_ticks_usec()
		Figure.build_mesh()
		t_mesh.append(_ms(t0))
		t0 = Time.get_ticks_usec()
		var fig := Figure.skinned(_mesh, _skin, _material, r % 2, r % 3)
		t_skinned.append(_ms(t0))
		t0 = Time.get_ticks_usec()
		gm.map_container.add_child(fig)
		t_tree.append(_ms(t0))
		var sk := fig.get_child(0) as Skeleton3D
		var mi := sk.get_child(0) as MeshInstance3D
		t0 = Time.get_ticks_usec()
		var baked := mi.bake_mesh_from_current_skeleton_pose()
		t_bake.append(_ms(t0))
		t0 = Time.get_ticks_usec()
		var cpu := Figure.cpu_bake(_mesh, _skin, sk)
		t_cpu.append(_ms(t0))
		if baked != null and baked.get_surface_count() > 0:
			tangent = baked.surface_get_format(0) & Mesh.ARRAY_FORMAT_TANGENT != 0
			var a: PackedVector3Array = baked.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var b: PackedVector3Array = cpu.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for i in mini(a.size(), b.size()):
				worst_diff = maxf(worst_diff, a[i].distance_to(b[i]))
		gm.map_container.remove_child(fig)
		fig.free()
	return (
		(
			"bench %d runs (median ms): build mesh %.3f, assemble skinned %.3f, add to tree %.3f, "
			+ "engine bake %.3f (tangent kept %s), gdscript bake %.3f, bake difference %.5f m"
		)
		% [
			runs,
			_median(t_mesh),
			_median(t_skinned),
			_median(t_tree),
			_median(t_bake),
			str(tangent),
			_median(t_cpu),
			worst_diff
		]
	)


static func _clear(gm: GameMap) -> void:
	var old := gm.map_container.get_node_or_null(HOLDER)
	if old:
		old.name = HOLDER + "_old"
		old.queue_free()


## Yaw that turns the figure's +Z toward the camera.
static func _facing(gm: GameMap) -> float:
	var z := gm.camera_node.global_basis.z
	return atan2(z.x, z.z)


static func _ground(gm: GameMap, xz: Vector2) -> Vector3:
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var hit := DragPlaceController.raycast_terrain_down(space, Vector3(xz.x, 0, xz.y))
	return Vector3(xz.x, hit.y if hit != Vector3.INF else 0.0, xz.y)


## One figure, skinned or baked. A baked one is posed as a skinned one in the tree, baked by
## the engine and replaced by a plain MeshInstance3D.
static func _make(holder: Node3D, mode: String, stance: int, variant: int, row: int) -> Node3D:
	var fig := Figure.skinned(_mesh, _skin, _material, stance, variant)
	holder.add_child(fig)
	if mode == "baked":
		var mi := fig.get_child(0).get_child(0) as MeshInstance3D
		var baked := mi.bake_mesh_from_current_skeleton_pose()
		holder.remove_child(fig)
		fig.free()
		fig = Node3D.new()
		fig.name = "AvatarBaked"
		var body := MeshInstance3D.new()
		body.name = "Body"
		body.mesh = baked
		body.material_override = _material
		fig.add_child(body)
		holder.add_child(fig)
	var body_mi := fig.find_child("Body", true, false) as MeshInstance3D
	body_mi.set_instance_shader_parameter("palette_row", float(row))
	return fig


static func _holder(gm: GameMap) -> Node3D:
	_clear(gm)
	var holder := Node3D.new()
	holder.name = HOLDER
	gm.map_container.add_child(holder)
	return holder


static func _spawn(gm: GameMap, mode: String, count: int, at: Vector2, spacing: float) -> String:
	_ensure()
	var holder := _holder(gm)
	if count <= 0 or mode == "none":
		return "spawn none"
	var cols := ceili(sqrt(count * 1.4))
	var rows := ceili(float(count) / cols)
	var yaw := _facing(gm)
	var t0 := Time.get_ticks_usec()
	for k in count:
		var row := k / cols
		var x := at.x + (k % cols - (cols - 1) * 0.5 + (row % 2) * 0.5) * spacing
		var z := at.y + (row - (rows - 1) * 0.5) * spacing
		var fig := _make(holder, mode, k % 2, k % 3, k % PALETTES.size())
		fig.global_position = _ground(gm, Vector2(x, z))
		fig.rotation.y = yaw + sin(k * 2.39) * 0.45
	var ms := _ms(t0)
	return "spawn %s x%d in %.1f ms (%.2f ms each)" % [mode, count, ms, ms / count]


static func _twin(gm: GameMap, step: Dictionary) -> String:
	_ensure()
	var holder := _holder(gm)
	var mode := String(step.get("mode", "skinned"))
	var stance := int(step.get("stance", 0))
	var variant := int(step.get("variant", 0))
	var fig := _make(holder, mode, stance, variant, int(step.get("palette", 0)))
	fig.global_position = _ground(gm, _vec2(step.get("at", [0, 0])))
	fig.rotation.y = _facing(gm) + float(step.get("yaw", 0.3))
	# Screen rectangle from the posed vertices (a skinned one through the GDScript bake).
	var posed := (fig.find_child("Body", true, false) as MeshInstance3D).mesh as ArrayMesh
	if mode != "baked":
		posed = Figure.cpu_bake(_mesh, _skin, fig.get_child(0) as Skeleton3D)
	var verts: PackedVector3Array = posed.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for v in verts:
		var p := gm.camera_node.unproject_position(fig.global_transform * v)
		lo = lo.min(p)
		hi = hi.max(p)
	return (
		"twin %s stance %d variant %d at %s: rect %d %d %d %d"
		% [
			mode,
			stance,
			variant,
			str(fig.global_position),
			floori(lo.x) - 8,
			floori(lo.y) - 8,
			ceili(hi.x) + 8,
			ceili(hi.y) + 8
		]
	)


static func _params(pass_name: String, params: Dictionary) -> String:
	_ensure()
	var mat: ShaderMaterial = _material if pass_name == "body" else _material.next_pass
	var out := PackedStringArray()
	for key in params:
		var value: Variant = params[key]
		if value is Array and (value as Array).size() == 3:
			value = Color(float(value[0]), float(value[1]), float(value[2]))
		out.append("%s %s -> %s" % [key, str(mat.get_shader_parameter(key)), str(value)])
		mat.set_shader_parameter(key, value)
	return "params %s: %s" % [pass_name, "; ".join(out)]


static func _adopt(gm: GameMap, step: Dictionary) -> String:
	_ensure()
	var tokens := gm.get_tree().get_nodes_in_group("board_tokens")
	var index := int(step.get("index", 0))
	if index >= tokens.size():
		return "no token %d (of %d)" % [index, tokens.size()]
	var token := tokens[index] as BoardToken
	var body := token.get_rigid_body()
	var hidden := 0
	for node in body.find_children("*", "MeshInstance3D", true, false):
		if not String(node.get_path()).contains("Avatar"):
			(node as MeshInstance3D).visible = false
			hidden += 1
	var fig := Figure.skinned(_mesh, _skin, _material, 1, 0)
	body.add_child(fig)
	var ground := _ground(gm, Vector2(body.global_position.x, body.global_position.z))
	fig.global_transform = Transform3D(Basis(Vector3.UP, _facing(gm) - 0.3), ground)
	(fig.find_child("Body", true, false) as MeshInstance3D).set_instance_shader_parameter(
		"palette_row", float(int(step.get("palette", 1)))
	)
	if bool(step.get("highlight", false)):
		token.add_highlight()
	if bool(step.get("hidden", false)):
		token.set_visible_to_players(false)
	return (
		"adopted token %s: %d meshes hidden, figure at %s, rigid body scale %s"
		% [token.name, hidden, str(ground), str(body.scale)]
	)


static func _vec2(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


# --- test level ------------------------------------------------------------------------------


static func _save(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	var folder := String(step.get("folder", PREFIX + "forest"))
	if ctrl == null or not folder.begins_with(PREFIX):
		return "no authoring controller, or not a %s folder" % PREFIX
	var path := LevelManager.folder_path(folder)
	if DirAccess.dir_exists_absolute(path) and not bool(step.get("replace", false)):
		return "folder %s exists; not touching it (replace: true overwrites)" % folder
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	var saved := ctrl.level.duplicate(true) as LevelData
	saved.level_name = folder
	saved.level_folder = folder
	ctrl.call("_sync_document")
	var ok := AuthoringController.write_level(saved, ctrl.document, null)
	return "saved %s: %s" % [folder, str(ok)]


static func _cleanup() -> String:
	var dir := DirAccess.open(LevelManager.levels_dir)
	if dir == null:
		return "no levels folder"
	var removed := PackedStringArray()
	for folder in dir.get_directories():
		if folder.begins_with(PREFIX):
			_remove_tree(LevelManager.folder_path(folder))
			removed.append(folder)
	return "removed %s" % str(removed)


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
