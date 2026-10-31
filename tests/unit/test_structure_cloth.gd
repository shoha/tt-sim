extends GutTest

## The wind weights of banner, pennant and awning cloth (utils/structure_cloth.gd; topic wind_c):
## the pure shapes (a pennant is held at its pole, a hanging banner at its top edge, an awning at
## the wall) and a real build (the weights land in the second UV set, the digest does not move).

const COTTAGE := "core:cottage"
const KEEP := "core:castle_keep"


## A flat sheet standing in the plane through `origin` along horizontal `dir`: (along, y) points.
func _sheet(origin: Vector3, dir: Vector3, pts: Array[Vector2]) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in pts:
		out.append(origin + dir * p.x + Vector3(0.0, p.y, 0.0))
		out.append(origin + dir * p.x + Vector3(0.0, p.y, 0.0) + dir.cross(Vector3.UP) * 0.02)
	return out


func test_a_pennant_is_held_at_the_pole_and_free_at_the_tip() -> void:
	var pts: Array[Vector2] = [
		Vector2(0.0, 5.0 - 0.02), Vector2(0.0, 5.0 - 0.4), Vector2(0.95, 5.0 - 0.2)
	]
	for angle in [0.0, 0.7, 2.0, -2.5]:
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var points := _sheet(Vector3(3.0, 0.0, 4.0), dir, pts)
		var w := StructureCloth.weights_of(points, false)
		for k in points.size():
			var along := (points[k] - Vector3(3.0, 0.0, 4.0)).dot(dir)
			if along < 0.01:
				assert_almost_eq(w[k].x, 0.0, 0.01, "pole side stays (angle %.1f)" % angle)
			if along > 0.9:
				assert_almost_eq(w[k].x, 0.95, 0.05, "the tip moves most")
			assert_eq(w[k].y, StructureCloth.LEAN_FLAG)


func test_a_hanging_banner_swings_from_its_bar() -> void:
	var pts: Array[Vector2] = [
		Vector2(0.1, 4.9),
		Vector2(0.6, 4.9),
		Vector2(0.6, 4.15),
		Vector2(0.35, 3.9),
		Vector2(0.1, 4.15)
	]
	var points := _sheet(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), pts)
	var w := StructureCloth.weights_of(points, false)
	for k in points.size():
		var y := points[k].y
		if y > 4.89:
			assert_almost_eq(w[k].x, 0.0, 0.001, "the top edge is held")
		if y < 3.91:
			assert_almost_eq(w[k].x, 1.0, 0.01, "the point at the bottom moves most")
		assert_almost_eq(w[k].y, StructureCloth.LEAN_HANGING, 0.0001)


func test_an_awning_is_held_at_the_wall_and_free_at_the_hem() -> void:
	# A profile like procgen's: wall at x = 0 (top 3.0, bottom 2.95), hem at x = 0.8 (2.65 down to
	# 2.5), three stripes along z. Any wall direction gives the same weights.
	var profile: Array[Vector2] = [
		Vector2(0.0, 3.0), Vector2(0.8, 2.65), Vector2(0.8, 2.5), Vector2(0.0, 2.95)
	]
	for angle in [0.0, 1.0, 3.0, -2.0]:
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var along := out.cross(Vector3.UP)
		var points := PackedVector3Array()
		for stripe in 3:
			for p in profile:
				points.append(
					(
						Vector3(5.0, 0.0, 5.0)
						+ out * p.x
						+ along * (0.4 * stripe)
						+ Vector3(0.0, p.y, 0.0)
					)
				)
				points.append(
					(
						Vector3(5.0, 0.0, 5.0)
						+ out * p.x
						+ along * (0.4 * stripe + 0.4)
						+ Vector3(0.0, p.y, 0.0)
					)
				)
		var w := StructureCloth.weights_of(points, true)
		for k in points.size():
			var d := (points[k] - Vector3(5.0, 0.0, 5.0)).dot(out)
			if d < 0.01:
				assert_almost_eq(w[k].x, 0.0, 0.01, "wall edge (angle %.1f)" % angle)
			if d > 0.79:
				assert_almost_eq(w[k].x, 0.8, 0.02, "hem")
			assert_eq(w[k].y, StructureCloth.LEAN_AWNING)


func test_degenerate_pieces_stay_still() -> void:
	var two := PackedVector3Array([Vector3.ZERO, Vector3.ONE])
	for w in StructureCloth.weights_of(two, false):
		assert_eq(w, Vector2.ZERO)
	var flat := PackedVector3Array(
		[Vector3.ZERO, Vector3(0, 0, 0.001), Vector3(0.001, 0, 0), Vector3(0, 0.001, 0)]
	)
	for w in StructureCloth.weights_of(flat, true):
		assert_eq(w, Vector2.ZERO)


func test_groups_name_the_cloth_that_moves() -> void:
	assert_eq(StructureCloth.group_of("n5/ornament/banner1/cloth"), "n5/ornament/banner1/cloth")
	assert_eq(StructureCloth.group_of("n5/ornament/awning0/stripe3"), "n5/ornament/awning0")
	assert_eq(StructureCloth.group_of("n5/ornament/banner1/pole"), "")
	assert_eq(StructureCloth.group_of("n5/ornament/sign/plate"), "")
	assert_eq(StructureCloth.group_of("n5/roof/slab"), "")


func _cloth_weights(parts: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var table: PackedStringArray = parts.tag_table
	for mesh: Dictionary in parts.meshes:
		if mesh.kind != StructureCloth.KIND:
			continue
		var uv2: PackedVector2Array = mesh.arrays[Mesh.ARRAY_TEX_UV2]
		var tags: PackedInt32Array = mesh.tags
		for v in uv2.size():
			if StructureCloth.group_of(table[tags[v]]) != "":
				out.append(uv2[v])
	return out


func test_a_build_carries_the_weights_and_leaves_the_digest_alone() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	StructureRecipes.ensure_served()
	var plan := StructurePlacement.rect_plan(Vector2.ZERO, Vector2(6, 4), 0.0)
	var params := StructureOrnaments.with_kinds({}, ["banner", "awning"])
	var parts := StructureGeometry.build_one(doc, Structure.make(1, KEEP, plan, 7, params))
	assert_eq(parts.problem, "")
	var weights := _cloth_weights(parts)
	assert_gt(weights.size(), 0, "the keep has banner or awning cloth")
	var moving := 0
	var held := 0
	for w in weights:
		assert_between(w.x, 0.0, 1.6)
		assert_between(w.y, 0.0, 1.0)
		if w.x > 0.05:
			moving += 1
		else:
			held += 1
	assert_gt(moving, 0, "some vertices move")
	assert_gt(held, 0, "and some are held at the pole or the wall")
	# The weights are not in the digest: the same build with the second UV set removed digests
	# alike.
	var digest := StructureGeometry.digest_of(parts)
	for mesh: Dictionary in parts.meshes:
		(mesh.arrays as Array)[Mesh.ARRAY_TEX_UV2] = null
	assert_eq(StructureGeometry.digest_of(parts), digest)
