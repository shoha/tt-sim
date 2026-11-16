extends GutTest
## PainterOcclusion (card painter-grounding): the footprint raster, the sheet's grounding numbers.

const MOODS: Array[String] = ["summer", "dusk", "grimdark", "winter", "autumn"]


func _field(host: PainterOcclusion, w: int, h: int) -> PackedFloat32Array:
	host._origin = Vector2(-4.0, -4.0)
	host._size = Vector2i(w, h)
	var field := PackedFloat32Array()
	field.resize(w * h)
	return field


func _at(host: PainterOcclusion, field: PackedFloat32Array, x: float, z: float) -> float:
	var i := int((x - host._origin.x) / PainterOcclusion.TEXEL_M)
	var j := int((z - host._origin.y) / PainterOcclusion.TEXEL_M)
	return field[j * host._size.x + i]


func test_cover_is_half_at_the_reach() -> void:
	assert_eq(PainterOcclusion.cover(0.0), 1.0)
	assert_almost_eq(PainterOcclusion.cover(1.0), 0.5, 0.001)
	assert_eq(PainterOcclusion.cover(1.6), 0.0)


func test_disc_covers_its_middle_and_stops_past_its_reach() -> void:
	var host := PainterOcclusion.new()
	var field := _field(host, 16, 16)
	host._disc(field, 0.0, 0.0, 1.0)
	assert_eq(_at(host, field, 0.25, 0.25), 1.0)
	assert_gt(_at(host, field, 0.75, 0.25), 0.4)
	assert_eq(_at(host, field, 3.25, 0.25), 0.0)


func test_disc_keeps_the_maximum_of_two() -> void:
	var host := PainterOcclusion.new()
	var field := _field(host, 16, 16)
	host._disc(field, 0.0, 0.0, 1.0)
	var before := _at(host, field, 0.25, 0.25)
	host._disc(field, 0.5, 0.0, 0.3)
	assert_eq(_at(host, field, 0.25, 0.25), before)


func test_box_follows_its_turn() -> void:
	var host := PainterOcclusion.new()
	var field := _field(host, 16, 16)
	# A long box (half 2 by 0.25) along x: its far end is covered, the same distance off axis is not.
	host._box(field, 0.0, 0.0, 0.0, Vector2(2.0, 0.25), 0.3)
	assert_eq(_at(host, field, 1.75, 0.25), 1.0)
	assert_eq(_at(host, field, 0.25, 1.75), 0.0)
	var turned := _field(host, 16, 16)
	host._box(turned, 0.0, 0.0, PI * 0.5, Vector2(2.0, 0.25), 0.3)
	assert_eq(_at(host, turned, 0.25, 1.75), 1.0)
	assert_eq(_at(host, turned, 1.75, 0.25), 0.0)


func test_every_mood_has_the_grounding_numbers_in_range() -> void:
	var sheet := PainterSheet.load_sheet("core")
	for mood in MOODS:
		for key in ["occ-pool", "occ-core", "occ-dark", "occ-soil", "occ-cool", "occ-shade", "base-dark"]:
			var v := PainterSheet.number(sheet, mood, key, 30.0)
			assert_between(v, 0.0, 1.0, "%s %s" % [mood, key])
		assert_eq(PainterSheet.number(sheet, "winter", "occ-soil", 30.0), 0.0, "snow bases take no soil")
