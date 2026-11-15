extends GutTest
## The painted trees' wood is continuous in width (card painter-look-wood, docs/systems/painter.md
## "Trees"): a limb never starts wider than its parent is where it leaves, and no strand narrows
## by more than PainterTreeSkeleton.NARROW_MIN from one node to the next. Both were broken: the
## shader swelled every limb 1.6 times at its base on top of the pack's collar (a limb began up to
## 1.47 times as wide as its parent), and the pipe model took a heavy limb's whole area off the
## trunk at its node (the trunk above a fork stood at a third of the width below it, under a limb
## thicker than itself). The pack's radii are what the block-in draws (no shader swell any more),
## so the checks read the skeleton's radii: pure functions, the same on every platform.

const SEEDS: Array[int] = [11, 90210, 7]
const AGES: Array[float] = [0.3, 0.6, 0.95]
## A child's base against its parent's width at the joint (the flare caps at 0.92).
const JOINT_MAX := 0.95
const EPS := 1e-4
## The least radius the skeleton gives a limb (0.019, a twig 0.016).
const MIN_R := 0.0191


func _skeleton(species: String, age: float, seed_v: int) -> PainterTreeSkeleton.Sk:
	var c: Dictionary = {}
	return PainterTreeSkeleton.skeleton(
		PainterTreeSpecies.architecture(species), {"age": age, "openness": 0.5}, seed_v, false, c
	)


func test_no_limb_starts_wider_than_its_parent_at_the_joint() -> void:
	var worst := 0.0
	var worst_label := ""
	for species: String in PainterTreeSpecies.names():
		for age: float in AGES:
			for seed_v: int in SEEDS:
				var sk := _skeleton(species, age, seed_v)
				for i: int in range(1, sk.pts.size()):
					var pr: float = sk.rad[sk.parent[i]][sk.at[i]]
					var ratio: float = sk.rad[i][0] / pr
					# (a twig on a twig, both at the least width, is as wide as its parent)
					if sk.rad[i][0] <= MIN_R:
						ratio = minf(ratio, JOINT_MAX - EPS)
					if ratio > worst:
						worst = ratio
						worst_label = "%s age %.2f seed %d limb %d" % [species, age, seed_v, i]
	assert_lt(worst, JOINT_MAX, "worst child/parent width at a joint, at " + worst_label)


func test_no_strand_narrows_by_more_than_the_floor_between_nodes() -> void:
	var worst := 1.0
	var worst_label := ""
	for species: String in PainterTreeSpecies.names():
		for age: float in AGES:
			for seed_v: int in SEEDS:
				var sk := _skeleton(species, age, seed_v)
				for i: int in sk.pts.size():
					if sk.state[i] == 2:
						continue
					var r: PackedFloat32Array = sk.rad[i]
					for j: int in range(r.size() - 1):
						var ratio: float = r[j + 1] / r[j]
						if ratio < worst:
							worst = ratio
							worst_label = "%s age %.2f seed %d strand %d node %d" % [
								species, age, seed_v, i, j
							]
	assert_gt(
		worst, PainterTreeSkeleton.NARROW_MIN - EPS, "sharpest narrowing between nodes, at " + worst_label
	)


## The width the block-in draws a strand at, at node `at` (the tip's point, mirrored from
## painter_tree_blockin_body.gdshaderinc: `point_from`, `thick_end`; limb_point19 is 1): the pack's
## radius times the point that closes over the strand's last segment.
static func _drawn(r: PackedFloat32Array, at: int, forked: bool) -> float:
	var np: int = r.size()
	var along := float(at) / float(maxi(np - 1, 1))
	var twig := 1.0 - smoothstep(0.03 * 0.8, 0.03 * 1.3, r[0])
	var thick_end := smoothstep(0.4, 0.7, r[np - 1] / maxf(r[0], 0.001)) * (1.0 - twig)
	if forked:
		thick_end = 1.0 - twig
	var from := maxf(0.78, float(np - 2) / float(maxi(np - 1, 1)))
	return r[at] * (1.0 - (1.0 - thick_end) * smoothstep(from, 1.0, along))


## The old law began the point at 0.78 of the strand whatever its length: a trunk drawn narrowing
## to nothing over its last four nodes of twenty, under the limbs that leave it there (worst 4.9
## times as wide as the trunk at the joint, 1280 where it had closed). A limb of any real width
## (over 3 cm) is never wider than its parent as drawn at the joint.
func test_no_limb_is_drawn_wider_than_its_parent_at_the_joint() -> void:
	var worst := 0.0
	var worst_label := ""
	for species: String in PainterTreeSpecies.names():
		for age: float in AGES:
			for seed_v: int in SEEDS:
				var sk := _skeleton(species, age, seed_v)
				# (flag 16: limbs leave from the strand's last node, as the pack marks it)
				var forked := {}
				for i: int in range(1, sk.pts.size()):
					if sk.at[i] >= sk.pts[sk.parent[i]].size() - 1:
						forked[sk.parent[i]] = true
				for i: int in range(1, sk.pts.size()):
					if sk.rad[i][0] <= 0.03:
						continue
					var pr: PackedFloat32Array = sk.rad[sk.parent[i]]
					var ratio: float = (
						sk.rad[i][0]
						/ maxf(_drawn(pr, sk.at[i], forked.has(sk.parent[i])), 1e-4)
					)
					if ratio > worst:
						worst = ratio
						worst_label = "%s age %.2f seed %d limb %d on %d at node %d of %d" % [
							species, age, seed_v, i, sk.parent[i], sk.at[i], pr.size()
						]
	assert_lt(worst, JOINT_MAX, "worst limb / parent as drawn at the joint, at " + worst_label)
	var src := FileAccess.get_file_as_string(
		"res://painter/shaders/painter_tree_blockin_body.gdshaderinc"
	)
	assert_true(
		src.contains("float point_from = max(0.78, float(np - 2) / float(max(np - 1, 1)));"),
		"the shader's point law is the one mirrored here"
	)


## The block-in draws a limb at the pack's radius: no limb's radius is widened in the vertex stage
## except the stem's flare into the ground (a swell at a limb's base would put it above its parent
## again: the pack bakes the capped collar).
func test_the_blockin_widens_no_limb_but_the_stems_foot() -> void:
	var src := FileAccess.get_file_as_string(
		"res://painter/shaders/painter_tree_blockin_body.gdshaderinc"
	)
	var from := src.find("float rr = limb_r19(")
	var to := src.find("mat3 m3w", from)
	assert_true(from > 0 and to > from, "the limb radius block is found")
	for line: String in src.substr(from, to - from).split("\n"):
		var t := line.strip_edges()
		if t.begins_with("rr *= 1.0 +"):
			assert_true(t.contains("exp("), "only the ground flare widens: " + t)


func test_a_flared_limb_gets_its_collar_node_and_keeps_its_own_width_beyond_it() -> void:
	# A wide limb of an old oak leaves its parent flared (at most FLARE_MAX of the parent's width) and
	# is back to its own width at the next node.
	var sk := _skeleton("oak", 0.95, 11)
	var flared := 0
	for i: int in range(1, sk.pts.size()):
		var r: PackedFloat32Array = sk.rad[i]
		if sk.state[i] != 0 or r.size() < 3 or r[0] < PainterTreeSkeleton.FLARE_MIN_R:
			continue
		var pr: float = sk.rad[sk.parent[i]][sk.at[i]]
		if r[0] > r[1] * 1.05:
			flared += 1
			assert_lt(r[0], pr * PainterTreeSkeleton.FLARE_MAX + EPS, "flare under the parent")
	assert_gt(flared, 3, "an old oak has flared limbs")
