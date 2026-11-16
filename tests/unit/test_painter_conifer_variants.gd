extends GutTest

## The painted conifers' needle variants (PainterConiferVariants, PainterTreeTones' extra evergreen
## rows; docs/systems/painter.md "Trees", painter-look-taiga): a conifer paints several needle rows,
## the pack gives each tree one by its seed so near neighbours differ, the rows stay luminous and
## in a green family, and a mood's quiet narrows them.


func test_a_conifer_has_a_needle_row_per_variant_and_a_broadleaf_has_none() -> void:
	var table := PainterTreeTones.row_table()
	for species: String in ["spruce", "scotspine"]:
		assert_true(PainterTreeTones.has_variants(species), "%s has needle variants" % species)
		var seen := {}
		for v in PainterConiferVariants.count():
			var rows := PainterTreeTones.role_rows(species, v)
			seen[rows[8]] = true
			assert_lt(rows[8], PainterTreeTones.MAX_ROWS, "%s variant %d fits the palette" % [species, v])
		assert_eq(seen.size(), PainterConiferVariants.count(), "%s variants use distinct rows" % species)
		assert_eq(PainterTreeTones.role_rows(species)[8], int(table[species]["evergreen"]))
	assert_false(PainterTreeTones.has_variants("oak"))
	assert_eq(PainterTreeTones.role_rows("oak", 3)[8], 0, "a broadleaf has no needle row")
	var last := 0
	for species: String in table:
		for role: String in table[species]:
			last = maxi(last, int(table[species][role]))
	assert_lt(last, PainterTreeTones.MAX_ROWS, "every row fits the palette")


func test_the_variants_stay_luminous_and_green() -> void:
	var sheet := PainterSheet.load_sheet("core")
	var table := PainterTreeTones.row_table()
	var palette: Image = PainterTreeTones.bake(sheet, "summer", 60.0)["palette"]
	var hues := {}
	for v in PainterConiferVariants.count():
		var row := int(PainterTreeTones.role_rows("spruce", v)[8])
		var mid := PainterSheet.lch_of_color(palette.get_pixel(15, row * PainterTreeTones.VARIANTS + 1))
		assert_gt(mid.x, 0.42, "variant %d is not a dark mass (L %.2f)" % [v, mid.x])
		assert_between(mid.z, 135.0, 195.0, "variant %d stays green to teal (h %.0f)" % [v, mid.z])
		hues[snappedf(mid.z, 1.0)] = true
	assert_gt(hues.size(), 3, "the family spans several hues")
	assert_true(table["spruce"].has("evergreen_1"))


func test_a_quiet_mood_narrows_the_family() -> void:
	var sheet := PainterSheet.load_sheet("core")
	var spreads := {}
	for mood: String in ["summer", "grimdark"]:
		var palette: Image = PainterTreeTones.bake(sheet, mood, 20.0)["palette"]
		var lo := 1.0
		var hi := 0.0
		for v in PainterConiferVariants.count():
			var row := int(PainterTreeTones.role_rows("spruce", v)[8])
			var mid := PainterSheet.lch_of_color(palette.get_pixel(15, row * PainterTreeTones.VARIANTS + 1))
			lo = minf(lo, mid.x)
			hi = maxf(hi, mid.x)
		spreads[mood] = hi - lo
	assert_lt(spreads["grimdark"], spreads["summer"], "a dark mood narrows the family")


func test_assign_gives_near_neighbours_different_variants() -> void:
	var trees := {}
	for i in 40:
		var p := Vector3(float(i % 8) * 4.0, 0.0, float(i / 8) * 4.0)
		trees[PainterTreeSpecies.key_of(p)] = p
	var got := PainterConiferVariants.assign(trees)
	assert_eq(got.size(), trees.size())
	var kinds := {}
	for key: Vector3i in got:
		kinds[got[key]] = true
		assert_between(int(got[key]), 0, PainterConiferVariants.count() - 1)
	assert_eq(kinds.size(), PainterConiferVariants.count(), "every variant is used")
	# The nearest neighbours (4 m apart on this grid) seldom share one: a seed-only pick would share
	# a fifth of the time.
	var pairs := 0
	var shared := 0
	for a: Vector3i in trees:
		for b: Vector3i in trees:
			if a != b and (trees[a] as Vector3).distance_to(trees[b]) <= 4.1:
				pairs += 1
				if got[a] == got[b]:
					shared += 1
	var note := "%d of %d near pairs share needles" % [shared, pairs]
	assert_lt(float(shared) / float(pairs), 0.06, note)
	assert_eq(PainterConiferVariants.assign(trees), got, "pure in the set")
