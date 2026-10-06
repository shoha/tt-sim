extends RefCounted

## Avatar token probe (2026-10-05): the stand-in figure for probes/avatar.gd. A chunky,
## angular-leaning humanoid about 1.6 m tall (head and hair a third of the height), built in
## code as one flat-shaded ArrayMesh skinned to a 19-bone humanoid skeleton named as Godot's
## SkeletonProfileHumanoid names its bones. Every part is a closed shell (tubes, faceted
## ellipsoids, boxes, pyramids) so the inverted-hull outline has no open edges.
##
## Vertex data, as a parts kit GLB would carry it:
## - NORMAL: the flat face normal (crisp facets in the toon ramp).
## - TANGENT: the smoothed normal (face normals averaged per position), which the hull pushes
##   along so chamfers do not crack. Godot skins NORMAL and TANGENT, not CUSTOM channels.
## - COLOR.r: outline width scale (0 none, 1 normal, more on silhouette parts like hair and
##   cloak); COLOR.g: shade bias (0.5 neutral, lower darkens earlier).
## - UV.x: the palette block, (block + 0.5) / BLOCKS; the row is an instance uniform.
## - BONES / WEIGHTS: two bones per vertex at most, blended at joints.
##
## Proportions are bone pose scales and stances bone pose rotations (`stance`, `variant`).

const BLOCKS := 8
const SKIN := 0
const HAIR := 1
const TOP := 2
const SKIRT := 3
const CLOAK := 4
const BOOTS := 5
const ACCENT := 6
const MARK := 7

## Name, parent, joint in the rest pose (model space, metres; the figure faces +Z, its left
## is +X). Bone rests carry no rotation, so a pose rotation turns about model axes.
const BONES := [
	["Hips", "", Vector3(0, 0.56, 0)],
	["Spine", "Hips", Vector3(0, 0.66, 0)],
	["Chest", "Spine", Vector3(0, 0.82, 0)],
	["Neck", "Chest", Vector3(0, 1.0, 0)],
	["Head", "Neck", Vector3(0, 1.07, 0)],
	["LeftShoulder", "Chest", Vector3(0.08, 0.97, 0)],
	["LeftUpperArm", "LeftShoulder", Vector3(0.19, 0.96, 0)],
	["LeftLowerArm", "LeftUpperArm", Vector3(0.36, 0.82, 0)],
	["LeftHand", "LeftLowerArm", Vector3(0.51, 0.69, 0)],
	["RightShoulder", "Chest", Vector3(-0.08, 0.97, 0)],
	["RightUpperArm", "RightShoulder", Vector3(-0.19, 0.96, 0)],
	["RightLowerArm", "RightUpperArm", Vector3(-0.36, 0.82, 0)],
	["RightHand", "RightLowerArm", Vector3(-0.51, 0.69, 0)],
	["LeftUpperLeg", "Hips", Vector3(0.09, 0.52, 0)],
	["LeftLowerLeg", "LeftUpperLeg", Vector3(0.10, 0.29, 0)],
	["LeftFoot", "LeftLowerLeg", Vector3(0.11, 0.07, 0)],
	["RightUpperLeg", "Hips", Vector3(-0.09, 0.52, 0)],
	["RightLowerLeg", "RightUpperLeg", Vector3(-0.10, 0.29, 0)],
	["RightFoot", "RightLowerLeg", Vector3(-0.11, 0.07, 0)],
]

## Stances: bone -> Euler degrees (X, Y, Z) of its pose rotation.
const STANCES := [
	{
		"Hips": Vector3(0, 12, 3),
		"Spine": Vector3(5, -8, 0),
		"Chest": Vector3(0, -6, -3),
		"Head": Vector3(-6, 18, -9),
		"LeftUpperArm": Vector3(0, -15, -38),
		"LeftLowerArm": Vector3(-55, 0, 0),
		"RightUpperArm": Vector3(-20, 0, -72),
		"RightLowerArm": Vector3(-60, 0, 0),
		"LeftUpperLeg": Vector3(-16, 0, 2),
		"LeftLowerLeg": Vector3(22, 0, 0),
		"LeftFoot": Vector3(-6, 0, 0),
		"RightUpperLeg": Vector3(10, 0, -3),
		"RightLowerLeg": Vector3(8, 0, 0),
	},
	{
		"Hips": Vector3(0, -10, -2),
		"Spine": Vector3(-4, 10, 0),
		"Chest": Vector3(3, 8, 4),
		"Head": Vector3(8, -14, 6),
		"LeftUpperArm": Vector3(25, 0, 30),
		"LeftLowerArm": Vector3(-80, 20, 0),
		"RightUpperArm": Vector3(0, 20, 34),
		"RightLowerArm": Vector3(-35, 0, 0),
		"LeftUpperLeg": Vector3(4, 0, 6),
		"RightUpperLeg": Vector3(-6, 0, -7),
		"RightLowerLeg": Vector3(10, 0, 0),
	},
]

## Proportion variants: bone -> pose scale. 0 is the base figure, 1 short and stocky, 2 tall
## and slender. Scales propagate to children (Skeleton3D has no inherit-scale switch), so
## the head carries a counter-scale.
const VARIANTS := [
	{},
	{
		"Hips": Vector3(1.14, 0.9, 1.14),
		"LeftUpperLeg": Vector3(1.05, 0.86, 1.05),
		"RightUpperLeg": Vector3(1.05, 0.86, 1.05),
		"Head": Vector3(1.0, 1.08, 1.0),
	},
	{
		"Hips": Vector3(0.9, 1.06, 0.9),
		"LeftUpperLeg": Vector3(0.95, 1.14, 0.95),
		"RightUpperLeg": Vector3(0.95, 1.14, 0.95),
		"Head": Vector3(1.04, 0.92, 1.04),
	},
]


## Accumulates a flat-shaded, skinned triangle soup. Each corner's skin is a Vector3:
## (bone a, bone b, weight of b).
class Mb:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var block := 0
	var width := 1.0
	var bias := 0.5

	## One triangle wound so its face normal points away from `inside` (Godot's front faces
	## are clockwise, so the corners go in as a, c, b of the counter-clockwise order).
	func tri(
		a: Vector3, b: Vector3, c: Vector3, sa: Vector3, sb: Vector3, sc: Vector3, inside: Vector3
	) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			return
		n = n.normalized()
		if n.dot((a + b + c) / 3.0 - inside) < 0.0:
			var t := b
			b = c
			c = t
			var ts := sb
			sb = sc
			sc = ts
			n = -n
		for corner in [[a, sa], [c, sc], [b, sb]]:
			pos.append(corner[0])
			nrm.append(n)
			col.append(Color(width, bias, 0.0, 1.0))
			uv.append(Vector2((block + 0.5) / BLOCKS, 0.5))
			var s: Vector3 = corner[1]
			bones.append_array([int(s.x), int(s.y), 0, 0])
			weights.append_array([1.0 - s.z, s.z, 0.0, 0.0])

	func quad(p: Array, s: Array, inside: Vector3) -> void:
		tri(p[0], p[1], p[2], s[0], s[1], s[2], inside)
		tri(p[0], p[2], p[3], s[0], s[2], s[3], inside)

	## A tube from a to b: `sides`-gon rings (elliptical radii ra, rb across the axis) in
	## `bands` bands, capped at both ends. Skins lerp from sa to sb along it.
	func tube(
		a: Vector3,
		b: Vector3,
		ra: Vector2,
		rb: Vector2,
		sides: int,
		bands: int,
		sa: Vector3,
		sb: Vector3,
		phase := 0.5
	) -> void:
		var u := (b - a).normalized()
		var e2 := Vector3.BACK - u * u.dot(Vector3.BACK)
		if e2.length_squared() < 1e-4:
			e2 = Vector3.UP - u * u.dot(Vector3.UP)
		e2 = e2.normalized()
		var e1 := e2.cross(u).normalized()
		var rings: Array = []
		var skins: Array = []
		for k in bands + 1:
			var t := float(k) / bands
			var c := a.lerp(b, t)
			var r := ra.lerp(rb, t)
			var ring := PackedVector3Array()
			for j in sides:
				var ang := TAU * (j + phase) / sides
				ring.append(c + e1 * cos(ang) * r.x + e2 * sin(ang) * r.y)
			rings.append(ring)
			skins.append(Vector3(sa.x, sa.y, lerpf(sa.z, sb.z, t)))
		for k in bands:
			var mid := a.lerp(b, (k + 0.5) / bands)
			for j in sides:
				var j1 := (j + 1) % sides
				quad(
					[rings[k][j], rings[k][j1], rings[k + 1][j1], rings[k + 1][j]],
					[skins[k], skins[k], skins[k + 1], skins[k + 1]],
					mid
				)
		_cap(rings[0], skins[0], a, a + u * 0.01)
		_cap(rings[bands], skins[bands], b, b - u * 0.01)

	func _cap(ring: PackedVector3Array, s: Vector3, centre: Vector3, inside: Vector3) -> void:
		for j in ring.size():
			tri(centre, ring[j], ring[(j + 1) % ring.size()], s, s, s, inside)

	## A faceted ellipsoid, or the part of it from the top pole down to `cut` (0..1 of the
	## pole-to-pole angle), which may vary around it: `cut_back` at the back (-Z), `cut` at
	## the front. A cut shell is closed with a fan.
	func ellipsoid(
		c: Vector3, r: Vector3, slices: int, stacks: int, s: Vector3, cut := 1.0, cut_back := -1.0
	) -> void:
		if cut_back < 0.0:
			cut_back = cut
		var grid: Array = []
		for i in stacks + 1:
			var row := PackedVector3Array()
			for j in slices:
				var ang := TAU * (j + 0.5) / slices
				var back := (1.0 - cos(ang - PI * 0.5)) * 0.5
				var v := PI * float(i) / stacks * lerpf(cut, cut_back, back)
				var d := Vector3(sin(v) * cos(ang), cos(v), sin(v) * sin(ang))
				row.append(c + d * r)
			grid.append(row)
		for i in stacks:
			for j in slices:
				var j1 := (j + 1) % slices
				var p := [grid[i][j], grid[i][j1], grid[i + 1][j1], grid[i + 1][j]]
				if i == 0:
					tri(p[0], p[2], p[3], s, s, s, c)
				elif i == stacks - 1 and cut >= 1.0:
					tri(p[0], p[1], p[2], s, s, s, c)
				else:
					quad(p, [s, s, s, s], c)
		if cut < 1.0 or cut_back < 1.0:
			var bottom: PackedVector3Array = grid[stacks]
			var centre := Vector3.ZERO
			for p in bottom:
				centre += p
			centre /= bottom.size()
			_cap(bottom, s, centre, c)

	## A box centred at c with half extents h along the basis axes.
	func box(c: Vector3, h: Vector3, basis: Basis, s: Vector3) -> void:
		var x := basis.x * h.x
		var y := basis.y * h.y
		var z := basis.z * h.z
		var faces := [
			[c + x - y - z, c + x + y - z, c + x + y + z, c + x - y + z],
			[c - x - y - z, c - x - y + z, c - x + y + z, c - x + y - z],
			[c - x + y - z, c - x + y + z, c + x + y + z, c + x + y - z],
			[c - x - y - z, c + x - y - z, c + x - y + z, c - x - y + z],
			[c - x - y + z, c + x - y + z, c + x + y + z, c - x + y + z],
			[c - x - y - z, c - x + y - z, c + x + y - z, c + x - y - z],
		]
		for f in faces:
			quad(f, [s, s, s, s], c)

	## A four-sided pyramid: square base of half size h around `at`, apex at `apex`.
	func pyramid(at: Vector3, apex: Vector3, h: float, s: Vector3) -> void:
		var u := (apex - at).normalized()
		var e1 := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized() * h
		var e2 := u.cross(e1).normalized() * h
		var base := [at + e1 + e2, at - e1 + e2, at - e1 - e2, at + e1 - e2]
		var inside := at + (apex - at) * 0.25
		for j in 4:
			tri(base[j], base[(j + 1) % 4], apex, s, s, s, inside)
		quad(base, [s, s, s, s], inside)


static func bone_index(name: String) -> int:
	for i in BONES.size():
		if BONES[i][0] == name:
			return i
	return -1


static func _joint(name: String) -> Vector3:
	return BONES[bone_index(name)][2]


## Skin value: rigid on `a`, or blended toward `b` by w.
static func _sk(a: String, b := "", w := 0.0) -> Vector3:
	var ia := bone_index(a)
	return Vector3(ia, bone_index(b) if b != "" else ia, w)


## Builds the stand-in figure mesh (skinned arrays, one surface).
static func build_mesh() -> ArrayMesh:
	var m := Mb.new()
	_torso(m)
	_head(m)
	for side in ["Left", "Right"]:
		_arm(m, side)
		_leg(m, side)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = m.pos
	arrays[Mesh.ARRAY_NORMAL] = m.nrm
	arrays[Mesh.ARRAY_TANGENT] = _smooth_tangents(m.pos, m.nrm)
	arrays[Mesh.ARRAY_COLOR] = m.col
	arrays[Mesh.ARRAY_TEX_UV] = m.uv
	arrays[Mesh.ARRAY_BONES] = m.bones
	arrays[Mesh.ARRAY_WEIGHTS] = m.weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _torso(m: Mb) -> void:
	m.block = TOP
	m.tube(
		Vector3(0, 0.48, 0),
		Vector3(0, 0.62, 0),
		Vector2(0.15, 0.11),
		Vector2(0.14, 0.10),
		8,
		2,
		_sk("Hips", "Spine", 0.0),
		_sk("Hips", "Spine", 0.3)
	)
	m.tube(
		Vector3(0, 0.62, 0),
		Vector3(0, 0.80, 0),
		Vector2(0.135, 0.095),
		Vector2(0.165, 0.11),
		8,
		2,
		_sk("Spine", "Hips", 0.3),
		_sk("Spine", "Chest", 0.3)
	)
	m.tube(
		Vector3(0, 0.80, 0),
		Vector3(0, 1.0, 0),
		Vector2(0.165, 0.11),
		Vector2(0.12, 0.085),
		8,
		2,
		_sk("Chest", "Spine", 0.3),
		_sk("Chest", "Neck", 0.0)
	)
	m.block = ACCENT
	m.tube(
		Vector3(0, 0.60, 0),
		Vector3(0, 0.665, 0),
		Vector2(0.158, 0.114),
		Vector2(0.155, 0.112),
		8,
		1,
		_sk("Spine", "Hips", 0.5),
		_sk("Spine", "Hips", 0.4)
	)
	m.block = SKIRT
	m.width = 1.2
	m.tube(
		Vector3(0, 0.63, 0),
		Vector3(0, 0.36, 0),
		Vector2(0.17, 0.125),
		Vector2(0.27, 0.22),
		10,
		2,
		_sk("Hips"),
		_sk("Hips")
	)
	m.block = CLOAK
	m.width = 1.3
	var cloak := [
		Vector3(0, 0.98, -0.12),
		Vector3(0, 0.80, -0.16),
		Vector3(0, 0.60, -0.21),
		Vector3(0, 0.40, -0.27)
	]
	var cloak_w := [
		Vector2(0.15, 0.018), Vector2(0.17, 0.018), Vector2(0.19, 0.018), Vector2(0.22, 0.018)
	]
	var cloak_s := [
		_sk("Chest"), _sk("Chest", "Spine", 0.5), _sk("Spine", "Hips", 0.6), _sk("Hips")
	]
	for k in 3:
		m.tube(
			cloak[k],
			cloak[k + 1],
			cloak_w[k],
			cloak_w[k + 1],
			4,
			1,
			cloak_s[k],
			cloak_s[k + 1],
			0.5
		)
	m.width = 1.0


static func _head(m: Mb) -> void:
	m.block = SKIN
	m.tube(
		Vector3(0, 0.98, 0),
		Vector3(0, 1.11, 0),
		Vector2(0.05, 0.05),
		Vector2(0.052, 0.05),
		6,
		1,
		_sk("Neck", "Chest", 0.3),
		_sk("Neck", "Head", 0.5)
	)
	var c := Vector3(0, 1.29, 0)
	m.ellipsoid(c, Vector3(0.20, 0.22, 0.19), 12, 8, _sk("Head"))
	m.block = MARK
	m.width = 0.0
	for x in [0.07, -0.07]:
		m.box(Vector3(x, 1.27, 0.171), Vector3(0.019, 0.036, 0.016), Basis(), _sk("Head"))
	m.block = HAIR
	m.width = 1.3
	var hc := Vector3(0, 1.31, -0.015)
	var hr := Vector3(0.225, 0.24, 0.215)
	m.ellipsoid(hc, hr, 12, 5, _sk("Head"), 0.42, 0.78)
	# Spikes: direction from the hair centre, length, droop.
	var spikes := [
		[Vector3(0.0, 0.7, -0.7), 0.17],
		[Vector3(0.6, 0.4, -0.6), 0.15],
		[Vector3(-0.6, 0.4, -0.6), 0.15],
		[Vector3(0.9, 0.1, -0.3), 0.12],
		[Vector3(-0.9, 0.1, -0.3), 0.12],
		[Vector3(0.0, 0.1, -1.0), 0.16],
		[Vector3(0.35, 0.45, 0.8), 0.12],
		[Vector3(-0.25, 0.5, 0.82), 0.13],
		[Vector3(0.0, 1.0, 0.1), 0.1],
	]
	for sp in spikes:
		var d: Vector3 = (sp[0] as Vector3).normalized()
		var at := hc + d * hr * 0.92
		var tip_dir := (
			(
				d
				+ Vector3(0, -0.55, 0)
				+ (Vector3(0, 0, -0.2) if d.z < 0.5 else Vector3(0, -0.4, 0.1))
			)
			. normalized()
		)
		m.pyramid(at, at + tip_dir * float(sp[1]), 0.055, _sk("Head"))
	m.width = 1.0


static func _arm(m: Mb, side: String) -> void:
	var sh := _joint(side + "UpperArm")
	var el := _joint(side + "LowerArm")
	var wr := _joint(side + "Hand")
	m.block = ACCENT
	m.ellipsoid(
		sh + Vector3(0, 0.01, 0),
		Vector3(0.078, 0.065, 0.078),
		8,
		4,
		_sk(side + "UpperArm", "Chest", 0.3),
		0.5
	)
	m.block = TOP
	m.tube(
		sh,
		el,
		Vector2(0.05, 0.05),
		Vector2(0.044, 0.044),
		8,
		3,
		_sk(side + "UpperArm", side + "LowerArm", 0.0),
		_sk(side + "UpperArm", side + "LowerArm", 0.5)
	)
	m.block = SKIN
	m.tube(
		el,
		wr,
		Vector2(0.044, 0.044),
		Vector2(0.038, 0.04),
		8,
		3,
		_sk(side + "LowerArm", side + "UpperArm", 0.5),
		_sk(side + "LowerArm", side + "Hand", 0.2)
	)
	var d := (wr - el).normalized()
	var basis := Basis(d.cross(Vector3.BACK).normalized(), d, Vector3.BACK)
	m.box(wr + d * 0.05, Vector3(0.022, 0.05, 0.036), basis, _sk(side + "Hand"))


static func _leg(m: Mb, side: String) -> void:
	var hip := _joint(side + "UpperLeg")
	var knee := _joint(side + "LowerLeg")
	var ankle := _joint(side + "Foot")
	m.block = TOP
	m.tube(
		hip,
		knee,
		Vector2(0.075, 0.075),
		Vector2(0.06, 0.06),
		8,
		3,
		_sk(side + "UpperLeg", "Hips", 0.3),
		_sk(side + "UpperLeg", side + "LowerLeg", 0.5)
	)
	m.block = BOOTS
	m.tube(
		knee,
		ankle,
		Vector2(0.066, 0.066),
		Vector2(0.06, 0.062),
		8,
		3,
		_sk(side + "LowerLeg", side + "UpperLeg", 0.5),
		_sk(side + "LowerLeg", side + "Foot", 0.3)
	)
	m.box(ankle + Vector3(0, -0.035, 0.045), Vector3(0.055, 0.04, 0.1), Basis(), _sk(side + "Foot"))


## Smoothed normals per position (rounded to 0.1 mm), as TANGENT with w = 1.
static func _smooth_tangents(
	pos: PackedVector3Array, nrm: PackedVector3Array
) -> PackedFloat32Array:
	var sums := {}
	for i in pos.size():
		var key := Vector3i((pos[i] * 10000.0).round())
		sums[key] = sums.get(key, Vector3.ZERO) + nrm[i]
	var out := PackedFloat32Array()
	out.resize(pos.size() * 4)
	for i in pos.size():
		var s: Vector3 = sums[Vector3i((pos[i] * 10000.0).round())]
		var n := s.normalized() if s.length_squared() > 1e-10 else nrm[i]
		out[i * 4] = n.x
		out[i * 4 + 1] = n.y
		out[i * 4 + 2] = n.z
		out[i * 4 + 3] = 1.0
	return out


## The shared Skin: one named bind per bone, the inverse of its rest joint.
static func build_skin() -> Skin:
	var skin := Skin.new()
	for b in BONES:
		skin.add_named_bind(String(b[0]), Transform3D(Basis(), b[2]).affine_inverse())
	return skin


## A Skeleton3D with the humanoid bones, posed in `stance` with `variant`'s proportions.
static func build_skeleton(stance: int, variant: int) -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	for b in BONES:
		sk.add_bone(String(b[0]))
	for i in BONES.size():
		var parent := bone_index(String(BONES[i][1]))
		var joint: Vector3 = BONES[i][2]
		var local: Vector3 = joint
		if parent >= 0:
			local = joint - (BONES[parent][2] as Vector3)
		sk.set_bone_parent(i, parent)
		sk.set_bone_rest(i, Transform3D(Basis(), local))
	sk.reset_bone_poses()
	var pose: Dictionary = STANCES[stance % STANCES.size()]
	for bone in pose:
		var deg: Vector3 = pose[bone]
		var q := Quaternion.from_euler(deg * PI / 180.0)
		sk.set_bone_pose_rotation(bone_index(bone), q)
	var scales: Dictionary = VARIANTS[variant % VARIANTS.size()]
	for bone in scales:
		sk.set_bone_pose_scale(bone_index(bone), scales[bone])
	return sk


## A skinned figure: Node3D > Skeleton3D > MeshInstance3D sharing `mesh` and `skin`.
static func skinned(
	mesh: ArrayMesh, skin: Skin, material: Material, stance: int, variant: int
) -> Node3D:
	var root := Node3D.new()
	root.name = "AvatarSkinned"
	var sk := build_skeleton(stance, variant)
	root.add_child(sk)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh
	mi.skin = skin
	mi.material_override = material
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	return root


## The posed figure resolved on the CPU into a static ArrayMesh (linear blend skinning of
## positions, normals and the smoothed-normal tangents), keeping colours and UVs.
static func cpu_bake(mesh: ArrayMesh, skin: Skin, sk: Skeleton3D) -> ArrayMesh:
	var src := mesh.surface_get_arrays(0)
	var mats: Array[Transform3D] = []
	for i in BONES.size():
		mats.append(sk.get_bone_global_pose(i) * skin.get_bind_pose(i))
	var pos: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var tan: PackedFloat32Array = src[Mesh.ARRAY_TANGENT]
	var bones: PackedInt32Array = src[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = src[Mesh.ARRAY_WEIGHTS]
	var out_pos := PackedVector3Array()
	var out_nrm := PackedVector3Array()
	var out_tan := PackedFloat32Array()
	out_pos.resize(pos.size())
	out_nrm.resize(pos.size())
	out_tan.resize(tan.size())
	for i in pos.size():
		var ma := mats[bones[i * 4]]
		var mb := mats[bones[i * 4 + 1]]
		var w := weights[i * 4 + 1]
		var t := Vector3(tan[i * 4], tan[i * 4 + 1], tan[i * 4 + 2])
		out_pos[i] = (ma * pos[i]).lerp(mb * pos[i], w)
		out_nrm[i] = (ma.basis * nrm[i]).lerp(mb.basis * nrm[i], w).normalized()
		var tt := (ma.basis * t).lerp(mb.basis * t, w).normalized()
		out_tan[i * 4] = tt.x
		out_tan[i * 4 + 1] = tt.y
		out_tan[i * 4 + 2] = tt.z
		out_tan[i * 4 + 3] = 1.0
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_pos
	arrays[Mesh.ARRAY_NORMAL] = out_nrm
	arrays[Mesh.ARRAY_TANGENT] = out_tan
	arrays[Mesh.ARRAY_COLOR] = src[Mesh.ARRAY_COLOR]
	arrays[Mesh.ARRAY_TEX_UV] = src[Mesh.ARRAY_TEX_UV]
	var baked := ArrayMesh.new()
	baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return baked
