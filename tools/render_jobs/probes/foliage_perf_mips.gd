extends RefCounted

## Card foliagelod, part 2: the foliage mipmaps A/B (FoliageMips). Two uses:
##   foliage_perf.gd's `mips` variant key calls set_mips(): every scatter mesh's wind materials draw
##   their albedo, ORM and normal textures with the mip chain the game gives them (true) or as the
##   level-0-only ImageTextures the glTF parse made before the change (false). The flat copy is the
##   chain's own level 0, which FoliageMips never alters, so "false" is the old look exactly.
##   {action: "shimmer", name, dir, shifts: [pixels], settle}  at the current camera, for each of
##   mips off and on: the world viewport before and after a sub-pixel pan along the camera's right
##   axis, compared with Image.compute_image_metrics (mean and RMS difference over the frame). Wind
##   should be frozen (the `wind` op). Less difference = less shimmer under a slow pan. Writes
##   <dir>/<name>_shimmer.txt.

const PARAMS: Array[String] = ["albedo_texture", "orm_texture", "normal_texture"]

## mipped Texture2D -> its level-0-only twin, and back.
static var _flat_of: Dictionary = {}
static var _mipped_of: Dictionary = {}


## The wind materials of `mesh` drawn with mipmapped textures (`on`) or without.
static func set_mips(mesh: Mesh, on: bool) -> void:
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as ShaderMaterial
		if material == null:
			continue
		for param in PARAMS:
			var current := material.get_shader_parameter(param) as Texture2D
			if current == null:
				continue
			var wanted := _mipped_form(current) if on else _flat_form(current)
			if wanted != current:
				material.set_shader_parameter(param, wanted)


## {"textures": distinct textures, "bytes": their pixel data} the wind materials of `meshes` hold.
static func texture_bytes(meshes: Array) -> Dictionary:
	var seen := {}
	var bytes := 0
	for mesh: Mesh in meshes:
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as ShaderMaterial
			if material == null:
				continue
			for param in PARAMS:
				var texture := material.get_shader_parameter(param) as Texture2D
				if texture != null and not seen.has(texture):
					seen[texture] = true
					bytes += texture.get_image().get_data().size()
	return {"textures": seen.size(), "bytes": bytes}


static func _flat_form(texture: Texture2D) -> Texture2D:
	if _mipped_of.has(texture):
		return texture  # already a flat twin
	if not _flat_of.has(texture):
		var image := texture.get_image()
		if image == null or not image.has_mipmaps():
			return texture
		image.clear_mipmaps()
		var flat := ImageTexture.create_from_image(image)
		_flat_of[texture] = flat
		_mipped_of[flat] = texture
	return _flat_of[texture]


static func _mipped_form(texture: Texture2D) -> Texture2D:
	return _mipped_of.get(texture, texture)


static func run(base: Node, step: Dictionary) -> String:
	if String(step.get("action", "")) != "shimmer":
		return "unknown action"
	var rig := Shimmer.new()
	rig.gm = base.get("_game_map")
	rig.step = step
	rig.apply_mips = set_mips
	rig.texture_bytes = texture_bytes
	base.get_tree().root.add_child(rig)
	return "shimmer started"


static func blocker(base: Node, step: Dictionary) -> String:
	var running := base.get_tree().get_nodes_in_group("mips_shimmer")
	if String(step.get("action", "")) == "await" and not running.is_empty():
		return "the shimmer rig is still running"
	return ""


class Shimmer:
	extends Node
	var gm: GameMap
	var step: Dictionary
	var apply_mips: Callable
	var texture_bytes: Callable

	func _ready() -> void:
		add_to_group("mips_shimmer")
		_run()

	func _frames(n: int) -> void:
		for _i in n:
			await get_tree().process_frame

	func _grab() -> Image:
		await RenderingServer.frame_post_draw
		var img := gm.world_viewport.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		return img

	func _run() -> void:
		var meshes := {}
		for node in gm.find_children("*", "MultiMeshInstance3D", true, false):
			var mmi := node as MultiMeshInstance3D
			var chunk := mmi.multimesh != null and mmi.multimesh.mesh != null
			if chunk and String(mmi.name).contains("_MultiMesh"):
				meshes[mmi.multimesh.mesh] = true
		var holder := gm.cameraholder_node
		var right := gm.camera_node.global_basis.x
		var pixel := gm.camera_node.size / float(gm.world_viewport.size.y)
		var lines: Array[String] = [
			"shimmer at camera size %.2f, %d meshes" % [gm.camera_node.size, meshes.size()]
		]
		for on in [false, true]:
			for mesh: Mesh in meshes:
				apply_mips.call(mesh, on)
			var held: Dictionary = texture_bytes.call(meshes.keys())
			var label := "on" if on else "off"
			lines.append("mips %-3s: %d textures, %d bytes" % [label, held.textures, held.bytes])
		for shift in step.get("shifts", [0.25, 0.5, 0.75]):
			for on in [false, true]:
				for mesh: Mesh in meshes:
					apply_mips.call(mesh, on)
				await _frames(int(step.get("settle", 20)))
				var before := await _grab()
				var home := holder.global_position
				holder.global_position = home + right * pixel * float(shift)
				await _frames(4)
				var after := await _grab()
				holder.global_position = home
				var metrics := before.compute_image_metrics(after, false)
				lines.append(
					"shift %.2f px mips %-3s mean %.4f rms %.4f"
					% [shift, "on" if on else "off", metrics["mean"], metrics["root_mean_squared"]]
				)
		for mesh: Mesh in meshes:
			apply_mips.call(mesh, true)
		var dir := ProjectSettings.globalize_path(String(step.get("dir", "user://render_jobs")))
		DirAccess.make_dir_recursive_absolute(dir)
		var file_name := "%s_shimmer.txt" % String(step.get("name", "mips"))
		var f := FileAccess.open(dir.path_join(file_name), FileAccess.WRITE)
		for line in lines:
			f.store_line(line)
			print("RJ|shimmer| ", line)
		queue_free()
