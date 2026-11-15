extends GutTest

## The painted trees' per-tree view cull (painter-perf-cull; PainterTreePack.tree_row texels 5 and
## 6, tree_view_box in painter_tree.gdshaderinc): the box covers every mass and every strand point
## of every species at every age (a willow's strokes included, which the shader moves by its bend),
## the row carries the masses' own half extents, the shaders' pad constant equals the pack's, the
## cull ships on, and a CPU twin of the shader's extent math never culls a box that has a corner in
## the view.

const INCLUDE := "res://painter/shaders/painter_tree.gdshaderinc"
const AGES: Array[String] = ["lo", "mid", "hi"]
const EPS := 0.001


func _masses(species: String, age: String, openness: float, seed: int) -> Array[PainterTreeMass]:
	var cx := {"age": PainterTreeSpecies.AGE[age], "openness": openness}
	return PainterTreeGrowth.tree(
		PainterTreeSpecies.architecture(species), cx, seed, PainterTreeSpecies.is_conifer(species)
	)


## The unit sphere's points on the Fibonacci spiral, `n` of them.
static func _sphere(n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for k in n:
		var y := 1.0 - 2.0 * (float(k) + 0.5) / float(n)
		var r := sqrt(maxf(1.0 - y * y, 0.0))
		var a := float(k) * 2.399963
		out.append(Vector3(cos(a) * r, y, sin(a) * r))
	return out


## Where the shaders put a strand mass's stroke root at unit-sphere point `u` (the willow branch of
## painter_tree_stroke_body: the spindle's taper, then the bend).
static func _strand_point(m: PainterTreeMass, u: Vector3, bend: Vector3) -> Vector3:
	var b: Basis = m.xform.basis
	var e0: Vector3 = m.xform.origin
	var e1: Vector3 = b.x * m.size.x
	var e2: Vector3 = b.y * m.size.y
	var e3: Vector3 = b.z * m.size.z
	var p := e0 + e1 * u.x + e2 * u.y + e3 * u.z
	var tq := (1.0 - u.y) * 0.5
	var l0 := maxf(2.0 * sqrt(maxf(tq * (1.0 - tq), 0.0)), 0.08)
	var prof := (
		lerpf(0.8, 1.0, smoothstep(0.0, 0.22, tq))
		* pow(maxf(1.0 - smoothstep(0.22, 1.0, tq), 0.0), 0.75)
	)
	var a_p := p + ((p - e0) - e2 * u.y) * (minf(prof / l0, 3.0) - 1.0)
	return a_p + bend * (1.0 - (1.0 - tq) * (1.0 - tq))


func test_the_box_covers_every_mass_and_strand_point_of_every_species_and_age() -> void:
	var sphere := _sphere(48)
	var trees := 0
	var strand_masses := 0
	for species in PainterTreeSpecies.names():
		for age in AGES:
			for openness: float in [0.2, 0.5, 0.8]:
				var masses := _masses(species, age, openness, 4242 + trees)
				trees += 1
				var d: Dictionary = PainterTreePack.pack(
					masses, 4242, 3.0, PainterTreeSpecies.wide()
				)
				var box: AABB = (d["aabb"] as AABB).grow(EPS)
				var where := "%s %s %.1f" % [species, age, openness]
				for m: PainterTreeMass in masses:
					if m.shape == PainterTreeMass.Shape.ELLIPSOID:
						for u in sphere:
							var q: Vector3 = m.xform * (u * m.size)
							assert_true(box.has_point(q), "%s: a clump's surface point" % where)
						if m.params.has("bend"):
							strand_masses += 1
							var bend: Vector3 = m.params["bend"]
							for u in sphere:
								var q := _strand_point(m, u, bend)
								assert_true(box.has_point(q), "%s: a strand's stroke root" % where)
					elif m.shape == PainterTreeMass.Shape.STRAND:
						for q: Vector3 in m.params["pts"]:
							assert_true(box.has_point(q), "%s: a limb's point" % where)
	assert_gt(trees, 60, "a spread of trees")
	assert_gt(strand_masses, 0, "the willow's strand masses are among them")


func test_the_row_carries_the_masses_own_box() -> void:
	var masses := _masses("oak", "hi", 0.5, 77)
	var d: Dictionary = PainterTreePack.pack(masses, 77, 3.0, PainterTreeSpecies.wide())
	var box: AABB = d["aabb"]
	var row := PainterTreePack.tree_row(d, 0, 0, 0, 0.0, 0.0, 0.0, 0.0)
	var mid := box.get_center()
	var half := box.size * 0.5
	assert_eq(row[23], 1.0, "w 1: a box")
	assert_almost_eq(Vector3(row[20], row[21], row[22]), mid, Vector3.ONE * 1e-4)
	assert_almost_eq(Vector3(row[24], row[25], row[26]), half, Vector3.ONE * 1e-4)


func test_the_shaders_pad_equals_the_packs_and_the_cull_ships_on() -> void:
	var code := FileAccess.get_file_as_string(INCLUDE)
	var re := RegEx.create_from_string("const float TREE_BOX_PAD = ([0-9.]+);")
	var hit := re.search(code)
	assert_not_null(hit, "TREE_BOX_PAD is declared")
	if hit != null:
		assert_eq(hit.get_string(1).to_float(), PainterTreePack.BOUND_PAD)
	assert_true(code.contains("uniform float view_cull = 1.0;"), "the cull is on by default")
	assert_true(code.contains("uniform float view_margin = 1.0;"), "a metre of margin")


## tree_view_box's test in GDScript: `view` is the camera's inverse transform, `proj` its
## projection; true when the box (`centre`, `half` in the tree's frame, turned by `model`) is not
## wholly outside one of the four side planes with `margin` metres to spare.
static func _in_view(
	centre: Vector3,
	half: Vector3,
	model: Transform3D,
	view: Transform3D,
	proj: Projection,
	margin: float
) -> bool:
	var c: Vector3 = view * (model * centre)
	var vm := view.basis * model.basis
	var h := Vector3(
		(Vector3(vm.x.x, vm.y.x, vm.z.x).abs()).dot(half),
		(Vector3(vm.x.y, vm.y.y, vm.z.y).abs()).dot(half),
		(Vector3(vm.x.z, vm.y.z, vm.z.z).abs()).dot(half)
	)
	h += Vector3.ONE * margin
	var rx := Vector4(proj.x.x, proj.y.x, proj.z.x, proj.w.x)
	var ry := Vector4(proj.x.y, proj.y.y, proj.z.y, proj.w.y)
	var rw := Vector4(proj.x.w, proj.y.w, proj.z.w, proj.w.w)
	for side: Vector4 in [rw + rx, rw - rx, rw + ry, rw - ry]:
		var n := Vector3(side.x, side.y, side.z)
		if n.dot(c) + side.w < -n.abs().dot(h):
			return false
	return true


func _soundness(proj: Projection, eye: Transform3D) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var view := eye.affine_inverse()
	var checked := 0
	for k in 400:
		var half := Vector3(
			rng.randf_range(0.2, 6.0), rng.randf_range(0.2, 9.0), rng.randf_range(0.2, 6.0)
		)
		var centre := Vector3(rng.randf_range(-3, 3), rng.randf_range(0, 5), rng.randf_range(-3, 3))
		var turn := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		var model := Transform3D(
			turn.scaled(Vector3.ONE * rng.randf_range(0.8, 1.3)),
			Vector3(rng.randf_range(-80, 80), 0.0, rng.randf_range(-60, 10))
		)
		var culled := not _in_view(centre, half, model, view, proj, 0.0)
		if not culled:
			continue
		checked += 1
		# Wholly outside: no corner may lie in the view (a point inside every side plane).
		for i in 8:
			var sx := half.x if i & 1 else -half.x
			var sy := half.y if i & 2 else -half.y
			var sz := half.z if i & 4 else -half.z
			var p: Vector3 = view * (model * (centre + Vector3(sx, sy, sz)))
			var clip := proj * Vector4(p.x, p.y, p.z, 1.0)
			var in_view := absf(clip.x) <= clip.w + 1e-4 and absf(clip.y) <= clip.w + 1e-4
			assert_false(in_view and clip.w > 0.0, "a culled box has a corner in view")
	return checked


func test_the_extent_math_never_culls_a_box_with_a_corner_in_view_orthographic() -> void:
	var proj := Projection.create_orthogonal(-7.0, 7.0, -4.0, 4.0, 0.1, 200.0)
	var eye := Transform3D(Basis.looking_at(Vector3(-0.3, -0.6, -0.74)), Vector3(0, 40, 30))
	assert_gt(_soundness(proj, eye), 20, "a spread of culled boxes was checked")


func test_the_extent_math_never_culls_a_box_with_a_corner_in_view_perspective() -> void:
	var proj := Projection.create_perspective(60.0, 16.0 / 9.0, 0.1, 400.0)
	var eye := Transform3D(Basis.looking_at(Vector3(0.1, -0.2, -1.0)), Vector3(0, 8, 20))
	assert_gt(_soundness(proj, eye), 20, "a spread of culled boxes was checked")


func test_a_box_a_metre_past_the_edge_is_kept_by_the_margin_and_far_past_it_is_culled() -> void:
	var proj := Projection.create_orthogonal(-7.0, 7.0, -4.0, 4.0, 0.1, 200.0)
	var view := Transform3D(Basis.IDENTITY, Vector3(0, 0, 10)).affine_inverse()
	var half := Vector3(1.0, 1.0, 1.0)
	var edge := Transform3D(Basis.IDENTITY, Vector3(7.0, 0, 0))
	var past := Transform3D(Basis.IDENTITY, Vector3(8.5, 0, 0))
	var far := Transform3D(Basis.IDENTITY, Vector3(11.0, 0, 0))
	assert_true(_in_view(Vector3.ZERO, half, edge, view, proj, 0.0), "straddling the edge")
	assert_false(_in_view(Vector3.ZERO, half, past, view, proj, 0.0), "wholly outside")
	assert_true(_in_view(Vector3.ZERO, half, past, view, proj, 1.0), "kept by a metre of margin")
	assert_false(_in_view(Vector3.ZERO, half, far, view, proj, 1.0), "far past it")
