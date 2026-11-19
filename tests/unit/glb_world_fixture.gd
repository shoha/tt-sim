extends RefCounted

## A multi-asset Blender-style map GLB for the painter's GLB parity tests and render jobs
## (card painter-glb-parity), written with GLTFDocument and the scene extras the way terrain-paint
## writes them: two terrain tiles with a baked albedo texture (planar UVs) and their `-colonly`
## twins, a water plane (`-water`), a house (two materials in one mesh), three barrels, a row of
## duplicate fence posts (collapsed to a MultiMesh on load), and the scatter sources named in
## tt_scatter_instances (two trees, grass, flowers, a bush, a rock) with their instances on the
## ground. Not a test file itself (GUT only collects test_*.gd); preload it as a const.

const GLB := preload("res://tests/unit/glb_fixtures.gd")

const HALF := 24.0
const TREE_OAK := "Tree_Oak_Source"
const TREE_PINE := "Tree_Pine_Source"
const GRASS := "Grass_Tuft_Source"
const FLOWER := "Flower_Daisy_Source"
const BUSH := "Bush_Source"
const ROCK := "Rock_Boulder_Source"
const SOURCE_AT := Vector3(500.0, 0.0, 0.0)
const LAKE := Vector2(8.0, 8.0)
const LAKE_Y := -0.45
const HOUSE_AT := Vector2(-9.0, -6.0)
const TEXELS := 96


## The ground's height at map point (x, z): rolling hills, a steep bank on the east side and the
## lake's bowl.
static func height(x: float, z: float) -> float:
	var h := 0.9 * sin(x / 9.0) * cos(z / 11.0)
	h += 4.5 * smoothstep(15.0, 18.0, x) * smoothstep(-20.0, -10.0, z)
	h -= 1.6 * exp(-(Vector2(x, z).distance_squared_to(LAKE)) / 18.0)
	return h


## The baked terrain colour at (x, z): meadow green with soft noise, a tan path winding across, a
## grey rock patch and the bank in grey brown.
static func ground_color(x: float, z: float) -> Color:
	var n := 0.5 + 0.5 * sin(x * 1.7 + sin(z * 1.3)) * cos(z * 1.1)
	var color := Color(0.27 + 0.06 * n, 0.5 + 0.08 * n, 0.18 + 0.04 * n)
	if absf(z - 4.0 * sin(x / 7.0)) < 1.3:
		color = Color(0.6 + 0.05 * n, 0.48 + 0.05 * n, 0.3)
	if Vector2(x, z).distance_to(Vector2(-12.0, 10.0)) < 4.0:
		color = Color(0.5, 0.5, 0.52).lerp(color, 0.15 * n)
	if x > 15.5:
		color = Color(0.45, 0.4, 0.34)
	return color


## Writes the map to `path`; OK or the write's error.
static func write(path: String, seed: int = 7) -> Error:
	var root := Node3D.new()
	root.name = "Map"
	for tile in [[-HALF, 0.0], [0.0, HALF]]:
		var name := "Terrain_%s" % ("West" if tile[0] < 0.0 else "East")
		var ground := _tile(name, tile[0], tile[1])
		root.add_child(ground)
		var twin := _tile(name + "-colonly", tile[0], tile[1], false)
		root.add_child(twin)
	var lake := MeshInstance3D.new()
	lake.name = "Lake-water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	lake.mesh = plane
	lake.position = Vector3(LAKE.x, LAKE_Y, LAKE.y)
	root.add_child(lake)
	root.add_child(_house())
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.4
	barrel_mesh.bottom_radius = 0.4
	barrel_mesh.height = 0.9
	barrel_mesh.material = _material("Barrel_Wood", Color(0.45, 0.3, 0.16))
	for i in 3:
		var barrel := MeshInstance3D.new()
		barrel.name = "Barrel_%02d" % i
		barrel.mesh = barrel_mesh
		var bx := HOUSE_AT.x + 5.0 + i * 0.9
		barrel.position = Vector3(bx, height(bx, -4.0) + 0.45, -4.0)
		root.add_child(barrel)
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.18, 1.1, 0.18)
	post_mesh.material = _material("Fence_Wood", Color(0.5, 0.36, 0.2))
	for i in 30:
		var post := MeshInstance3D.new()
		post.name = "Fence_Post_%02d" % i
		post.mesh = post_mesh
		var px := -18.0 + i * 1.2
		post.position = Vector3(px, height(px, 16.0) + 0.55, 16.0)
		root.add_child(post)
	root.add_child(_source(TREE_OAK, _tree(false)))
	root.add_child(_source(TREE_PINE, _tree(true)))
	root.add_child(_source(GRASS, _tuft()))
	root.add_child(_source(FLOWER, _tuft("Flower_Petal", Color(0.9, 0.85, 0.3))))
	root.add_child(_source(BUSH, _bush()))
	root.add_child(_source(ROCK, _rock()))
	var state := GLTFState.new()
	var gltf := GLTFDocument.new()
	var err := gltf.append_from_scene(root, state)
	if err == OK:
		err = gltf.write_to_filesystem(state, path)
	root.free()
	if err != OK:
		return err
	var extras := {
		"tt_scatter_instances": _instances(seed),
		"tt_ambient_light_energy": 0.8,
	}
	return GLB.patch_scene_extras(path, extras)


## Rows of tt_scatter_instances: source name -> rows [lx, ly, lz, qx, qy, qz, qw, sx, sy, sz].
static func _instances(seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out := {}
	for spec in [
		[TREE_OAK, 14, 1.0, 1.15],
		[TREE_PINE, 10, 0.9, 1.2],
		[GRASS, 520, 0.8, 1.3],
		[FLOWER, 110, 0.8, 1.2],
		[BUSH, 24, 0.8, 1.3],
		[ROCK, 22, 0.7, 1.6],
	]:
		var rows: Array = []
		var guard := 0
		while rows.size() < int(spec[1]) and guard < 4000:
			guard += 1
			var x := rng.randf_range(-HALF + 1.0, HALF - 1.0)
			var z := rng.randf_range(-HALF + 1.0, HALF - 1.0)
			if _blocked(x, z):
				continue
			var yaw := Quaternion(Vector3.UP, rng.randf() * TAU)
			var s := rng.randf_range(float(spec[2]), float(spec[3]))
			rows.append([x, height(x, z), z, yaw.x, yaw.y, yaw.z, yaw.w, s, s, s])
		out[spec[0]] = rows
	return out


## Where nothing grows: the lake, the path's middle and the house.
static func _blocked(x: float, z: float) -> bool:
	if Vector2(x, z).distance_to(LAKE) < 4.6:
		return true
	if absf(z - 4.0 * sin(x / 7.0)) < 0.8:
		return true
	return absf(x - HOUSE_AT.x) < 3.4 and absf(z - HOUSE_AT.y) < 3.4


static func _tile(node_name: String, x0: float, x1: float, textured := true) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tile_arrays(x0, x1))
	if textured:
		var image := Image.create(TEXELS, TEXELS, false, Image.FORMAT_RGB8)
		for ty in TEXELS:
			for tx in TEXELS:
				var x := x0 + (tx + 0.5) / TEXELS * (x1 - x0)
				var z := -HALF + (ty + 0.5) / TEXELS * HALF * 2.0
				image.set_pixel(tx, ty, ground_color(x, z))
		var material := StandardMaterial3D.new()
		material.resource_name = "Terrain_Baked_" + node_name
		material.albedo_texture = ImageTexture.create_from_image(image)
		mesh.surface_set_material(0, material)
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	return node


## The surface arrays of the terrain tile between x0 and x1 (planar UVs over the tile).
static func tile_arrays(x0: float, x1: float) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := int(x1 - x0)
	var nz := int(HALF * 2.0)
	for iz in nz:
		for ix in nx:
			var xs := [x0 + ix, x0 + ix + 1.0]
			var zs := [-HALF + iz, -HALF + iz + 1.0]
			var corners := [[0, 0], [1, 1], [0, 1], [0, 0], [1, 0], [1, 1]]
			for c: Array in corners:
				var x: float = xs[c[0]]
				var z: float = zs[c[1]]
				st.set_uv(Vector2((x - x0) / (x1 - x0), (z + HALF) / (HALF * 2.0)))
				st.add_vertex(Vector3(x, height(x, z), z))
	st.generate_normals()
	return st.commit_to_arrays()


static func _material(
	material_name: String, color: Color, textured: bool = false
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = material_name
	material.albedo_color = color
	if textured:
		# A flat baked colour, as a wind material needs a texture to carry its albedo.
		var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
		image.fill(color)
		material.albedo_texture = ImageTexture.create_from_image(image)
		material.albedo_color = Color.WHITE
	return material


## One ArrayMesh from primitive meshes moved by `offsets`, each surface its own material.
static func _merged(parts: Array, offsets: Array, materials: Array) -> ArrayMesh:
	var out := ArrayMesh.new()
	for i in parts.size():
		var arrays: Array = (parts[i] as PrimitiveMesh).get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for j in verts.size():
			verts[j] += offsets[i]
		arrays[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(i, materials[i])
	return out


static func _house() -> MeshInstance3D:
	var walls := BoxMesh.new()
	walls.size = Vector3(5.0, 3.0, 4.0)
	var roof := PrismMesh.new()
	roof.size = Vector3(5.6, 2.0, 4.6)
	var node := MeshInstance3D.new()
	node.name = "House_01"
	node.mesh = _merged(
		[walls, roof],
		[Vector3(0.0, 1.5, 0.0), Vector3(0.0, 4.0, 0.0)],
		[
			_material("House_Wall", Color(0.82, 0.76, 0.64)),
			_material("House_Roof", Color(0.7, 0.28, 0.18))
		]
	)
	node.position = Vector3(HOUSE_AT.x, height(HOUSE_AT.x, HOUSE_AT.y) - 0.2, HOUSE_AT.y)
	return node


## A tree: a trunk and a crown (a sphere, or a cone for a pine), the crown's material carrying the
## painted-foliage extra treecube writes.
static func _tree(pine: bool) -> ArrayMesh:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.26
	trunk.height = 3.0
	var crown: PrimitiveMesh
	var crown_at := Vector3(0.0, 4.2, 0.0)
	if pine:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 1.5
		cone.height = 5.0
		crown = cone
		crown_at = Vector3(0.0, 4.6, 0.0)
	else:
		var ball := SphereMesh.new()
		ball.radius = 2.0
		ball.height = 3.6
		crown = ball
	var leaf := _material(
		"Pine_Tree_Leaf" if pine else "Oak_Tree_Leaf",
		Color(0.14, 0.34, 0.16) if pine else Color(0.28, 0.5, 0.16),
		true
	)
	leaf.set_meta("extras", {"tt_foliage_light": "painted"})
	return _merged(
		[trunk, crown],
		[Vector3(0.0, 1.5, 0.0), crown_at],
		[_material("Tree_Bark", Color(0.34, 0.24, 0.15), true), leaf]
	)


static func _tuft(
	material_name: String = "Grass_Blade", color: Color = Color(0.34, 0.6, 0.2)
) -> ArrayMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.7)
	var material := _material(material_name, color, true)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# A blade-shaped cutout in the texture's alpha, as a real wind material's picture has.
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var width := 0.5 * (1.0 - float(y) / 16.0)
			var inside := absf(float(x) + 0.5 - 8.0) / 8.0 <= width
			image.set_pixel(x, y, Color(color, 1.0 if inside else 0.0))
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.albedo_color = Color.WHITE
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var a := _merged([quad], [Vector3(0.0, 0.35, 0.0)], [material])
	return a


static func _bush() -> ArrayMesh:
	var ball := SphereMesh.new()
	ball.radius = 0.7
	ball.height = 1.1
	return _merged(
		[ball], [Vector3(0.0, 0.5, 0.0)], [_material("Bush_Leaf", Color(0.24, 0.46, 0.16), true)]
	)


static func _rock() -> ArrayMesh:
	var ball := SphereMesh.new()
	ball.radius = 0.6
	ball.height = 0.8
	return _merged(
		[ball], [Vector3(0.0, 0.2, 0.0)], [_material("Rock_Grey", Color(0.5, 0.5, 0.52))]
	)


static func _source(node_name: String, mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = SOURCE_AT
	return node
