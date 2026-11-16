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


## (cause 6) A drop of a third in the trunk's width at one node (a heavy limb takes its area off the
## stem there) read as a horizontal seam across the trunk under the crown: the stem narrows by at
## most 1 - NARROW_STEM from node to node.
func test_the_stem_does_not_step_in_at_a_node() -> void:
	var worst := 1.0
	var worst_label := ""
	for species: String in PainterTreeSpecies.names():
		for age: float in AGES:
			for seed_v: int in SEEDS:
				var r: PackedFloat32Array = _skeleton(species, age, seed_v).rad[0]
				for j: int in range(1, r.size() - 1):
					if r[j + 1] / r[j] < worst:
						worst = r[j + 1] / r[j]
						worst_label = "%s age %.2f seed %d node %d" % [species, age, seed_v, j]
	assert_gt(worst, PainterTreeSkeleton.NARROW_STEM - EPS, "sharpest stem step, at " + worst_label)


## The width the block-in draws a strand at, at node `at` (the tip's point, mirrored from
## painter_tree_blockin_body.gdshaderinc: `point_from`, `thick_end`; limb_point19 is 1): the pack's
## radius times the point that closes over the strand's last segment.
static func _drawn(r: PackedFloat32Array, at: int, forked: bool) -> float:
	var np: int = r.size()
	var along := float(at) / float(maxi(np - 1, 1))
	var twig := 1.0 - smoothstep(0.03 * 0.8, 0.03 * 1.3, r[0])
	# (painter-look-wood2: only a forked strand keeps its width; the ratio rule is gone)
	var thick_end := (1.0 - twig) if forked else 0.0
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


## painter-look-wood2 (cause 1 of the sapling and stub frames): the block-in kept a strand blunt
## whenever its tip was over 0.4 to 0.7 of its base, and the skeleton's least width flattens every
## sapling's leader, every unbranched stick and every dead stub to exactly that: each ended in a
## square cut. Only a strand that limbs leave from its last node (the pack's flag 16) keeps its end.
func test_only_a_forked_strand_keeps_a_blunt_end() -> void:
	var src := FileAccess.get_file_as_string(
		"res://painter/shaders/painter_tree_blockin_body.gdshaderinc"
	)
	assert_true(
		src.contains("float thick_end = (hfl & 16) != 0 ? 1.0 - twig : 0.0;"),
		"the thick-end rule is the flag alone"
	)
	assert_false(src.contains("smoothstep(0.4, 0.7, pl.w"), "no tip-over-base ratio rule")
	# A sapling's leader, not forked, is drawn to a point.
	var sk := _skeleton("rowan", 0.12, 11)
	var r: PackedFloat32Array = sk.rad[0]
	assert_almost_eq(_drawn(r, r.size() - 1, false), 0.0, EPS, "a sapling's leader ends in a point")


## (cause 2) The twig breaks, which are for a hair on screen, cut a stick a few pixels wide into
## floating pieces with square ends and ate its base off its parent; the twig colour (the leaf's)
## made a stick brighter than the stem it grows from. Both fade with the twig's width in pixels, and
## the breaks never touch a twig's first and last eighth. (w_px used the projection's [1][1], which
## is negative on the viewport's flipped Y: the first version of this faded nothing.)
func test_twig_breaks_and_twig_colour_fade_with_width_on_screen() -> void:
	var src := FileAccess.get_file_as_string(
		"res://painter/shaders/painter_tree_blockin_body.gdshaderinc"
	)
	assert_true(
		src.contains("w_px = v_fn.z * abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y"),
		"the pixel width is the absolute projection scale"
	)
	assert_true(src.contains("(1.0 - smoothstep(1.5, 4.0, w_px))"), "breaks fade by 4 px")
	assert_true(src.contains("smoothstep(0.08, 0.16, v_fn.y)"), "no break at a twig's base")
	assert_true(src.contains("(1.0 - smoothstep(3.0, 7.0, w_px))"), "twig colour fades by 7 px")


## (cause 3) A stick on a thin stem began as thick as the stem (the least width, 0.019, on a stem
## that had narrowed to 0.019): a limb leaves at no more than 0.8 of its parent's width unless the
## least width (which is 0.75 of a thin parent's, but not under LEAST_STICK) is above that.
func test_a_stick_on_a_thin_parent_is_thinner_than_it() -> void:
	var worst := 0.0
	var worst_label := ""
	for species: String in PainterTreeSpecies.names():
		for age: float in AGES:
			for seed_v: int in SEEDS:
				var sk := _skeleton(species, age, seed_v)
				for i: int in range(1, sk.pts.size()):
					var pr: float = sk.rad[sk.parent[i]][sk.at[i]]
					if sk.state[i] != 0 or pr > 0.03 or sk.rad[i][0] >= PainterTreeSkeleton.FLARE_MIN_R:
						continue
					var over: float = sk.rad[i][0] - maxf(0.8 * pr, PainterTreeSkeleton.LEAST_STICK)
					if over > worst:
						worst = over
						worst_label = "%s age %.2f seed %d limb %d" % [species, age, seed_v, i]
	assert_lt(worst, EPS, "a stick over 0.8 of its parent (or the least stick), at " + worst_label)
	# A sapling's leader runs up to a fine tip, not a 4 cm pole.
	var sk := _skeleton("birch", 0.12, 11)
	assert_lt(sk.rad[0][sk.rad[0].size() - 1], 0.0185, "a young birch's leader ends under 1.9 cm")


## (cause 4) Where the leader gives out, the stem divides into co-dominant limbs; the floor under
## the
## stem's top kept it at 0.6 of the girth while the forks carried a few twigs each: a flat shoulder
## with limbs half its width pushed into it. The straight fork now takes FORK_LEAD of the stem's
## width at the top and the rest share what is left.
func test_the_forks_share_the_stems_width_at_its_top() -> void:
	var checked := 0
	for species: String in PainterTreeSpecies.names():
		for age: float in AGES:
			var sk := _skeleton(species, age, 11)
			var top: int = sk.pts[0].size() - 1
			var forks := PackedInt32Array()
			for i: int in range(1, sk.pts.size()):
				if sk.parent[i] == 0 and sk.order[i] == 0 and sk.at[i] == top:
					forks.append(i)
			if forks.size() < 2:
				continue
			checked += 1
			var big: float = sk.rad[0][top]
			assert_gte(
				sk.rad[forks[0]][0],
				big * PainterTreeSkeleton.FORK_LEAD - EPS,
				"the straight fork of %s age %.2f" % [species, age]
			)
			for f: int in forks:
				assert_gte(sk.rad[f][0], big * 0.3 - EPS, "every fork of %s age %.2f" % [species, age])
				assert_lt(sk.rad[f][0], big * 0.95, "and none as wide as the stem")
	assert_gt(checked, 6, "several species and ages divide their stem")


## (painter-look-wood3, the ring under the crown) The trunk comes down to its widest fork over its
## last nodes: no stem that divides stands more than a ninth wider than its widest fork where they
## meet, and the old oak (whose top was a flat shoulder at 0.54 against forks of 0.39) is narrowed.
func test_the_trunk_narrows_into_its_widest_fork() -> void:
	var checked := 0
	for species: String in PainterTreeSpecies.names():
		for age: float in AGES:
			for seed_v: int in SEEDS:
				var sk := _skeleton(species, age, seed_v)
				var top: int = sk.pts[0].size() - 1
				var widest := 0.0
				var forks := 0
				for i: int in range(1, sk.pts.size()):
					if sk.parent[i] == 0 and sk.order[i] == 0 and sk.at[i] == top:
						forks += 1
						widest = maxf(widest, sk.rad[i][0])
				if forks < 2 or sk.rad[0][top] < PainterTreeSkeleton.FLARE_MIN_R:
					continue
				checked += 1
				assert_gt(
					widest / sk.rad[0][top],
					0.89,
					"%s age %.2f seed %d: widest fork against the stem's top" % [species, age, seed_v]
				)
	assert_gt(checked, 10, "several trees divide their stem")


## The other forks take FORK_REST of the stem's area between them, so a crown of three or four forks
## is not one thick limb and thin ones.
func test_the_forks_after_the_lead_are_not_slender() -> void:
	var sk := _skeleton("oak", 0.95, 11)
	var top: int = sk.pts[0].size() - 1
	for i: int in range(1, sk.pts.size()):
		if sk.parent[i] == 0 and sk.order[i] == 0 and sk.at[i] == top:
			assert_gt(sk.rad[i][0] / sk.rad[0][top], 0.5, "fork %d of the old oak" % i)


## The fork count and spread are drawn per seed (the flat-topped trees all stood as one umbrella).
func test_the_fork_count_varies_with_the_seed() -> void:
	var counts := {}
	for seed_v: int in range(1, 25):
		var sk := _skeleton("oak", 0.95, seed_v)
		var top: int = sk.pts[0].size() - 1
		var n := 0
		for i: int in range(1, sk.pts.size()):
			if sk.parent[i] == 0 and sk.order[i] == 0 and sk.at[i] == top:
				n += 1
		counts[n] = true
	assert_gte(counts.size(), 2, "an oak's stem divides in a different number of forks by seed")


## A sapling bends a little by seed: not one ruled pole.
func test_a_sapling_bends_by_seed() -> void:
	var tops := {}
	var worst := 0.0
	for seed_v: int in range(1, 9):
		var sk := _skeleton("rowan", 0.12, seed_v)
		var p: PackedVector3Array = sk.pts[0]
		var off := Vector2(p[p.size() - 1].x, p[p.size() - 1].z)
		worst = maxf(worst, off.length())
		tops[snappedf(off.x, 0.01)] = true
	assert_gt(worst, 0.03, "some sapling stands off its foot by over 3 cm at the top")
	assert_gt(tops.size(), 3, "and each seed bends its own way")


## The shader's torn trunk end (w_cap) and the run-on past the last node are what the checks above
## assume: they stand in the source.
func test_the_forked_strand_ends_in_a_torn_edge_over_its_forks() -> void:
	var src := FileAccess.get_file_as_string(
		"res://painter/shaders/painter_tree_blockin_body.gdshaderinc"
	)
	assert_true(src.contains("bool w_cap = v_form > 3.5;"), "the fragment reads the forked flag")
	assert_true(src.contains("wood_form = 2.0 + twig + (capd ? 2.0 : 0.0);"), "from the vertex stage")
	assert_true(src.contains("const float cap_ext19 = 0.5;"), "the strand runs on by half its width")


## (cause 5) The buttress roots were three points ending 4 cm above the ground at a fifth of the
## stem's girth: log stubs with cut faces. They are four points that bend down and end in a fine
## point under the ground.
func test_buttress_roots_thin_to_a_point_under_the_ground() -> void:
	var masses := PainterTreeGrowth.tree(
		PainterTreeSpecies.architecture("oak"), {"age": 0.95, "openness": 0.5}, 11, false
	)
	var roots := 0
	for m: PainterTreeMass in masses:
		if m.shape != PainterTreeMass.Shape.STRAND:
			continue
		var pts: PackedVector3Array = m.params["pts"]
		var rad: PackedFloat32Array = m.params["radii"]
		var low := 1.0e9
		for p: Vector3 in pts:
			low = minf(low, p.y)
		# (a limb never goes under 0.3 m: only a root ends below the ground)
		if low >= 0.0:
			continue
		roots += 1
		assert_gte(pts.size(), 4, "a root bends in four points")
		assert_lt(rad[rad.size() - 1], 0.2 * rad[0], "and thins to a fine tip")
	assert_gte(roots, 3, "an old oak has buttress roots")
