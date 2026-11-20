extends GutTest

## The exact waterline (field-resolution spike F1, ported by the foot-2 spike): WaterField.ew, the
## first buried ring standing at the neighbouring surface extended over the ground, and the
## marching-triangles shore, on the canonical 61 m map test_water_field.gd uses.

const FIXTURE := "res://tests/fixtures/water_field_canonical.ttmap"

var _doc: MapDocument = null
var _field: WaterField = null


func before_all() -> void:
	_doc = MapDocumentIO.read(FIXTURE).get("document")
	_field = WaterField.build(_doc)


func test_the_exact_shore_extends_the_first_ring() -> void:
	var was := WaterField.exact_shore
	WaterField.exact_shore = false
	var off := WaterField.build(_doc)
	WaterField.exact_shore = was
	for i in off.w.size():
		assert_eq(off.ew[i], off.w[i], "without F1 the drawn surface is w")
	var raised := 0
	for i in _field.w.size():
		if _field.ew[i] != _field.w[i]:
			raised += 1
			assert_gt(_field.ew[i], _field.w[i], "the extended ring stands above the buried one")
			assert_lt(_field.ew[i], _field.ground[i], "and still under the ground")
	assert_gt(raised, 100, "the first ring of the canonical map's shores is extended")


func test_the_foot_coordinate_runs_across_a_pond() -> void:
	# Foot-2 spike: a fall that lands in a pond (the pond holds the level) still has its foot
	# coordinate on the pond's samples.
	var in_pond := 0
	for i in _field.foot.size():
		if _doc.pond_mask[i] != 0 and _field.foot[i] < WaterFieldStroke.NO_FOOT * 0.5:
			in_pond += 1
	assert_gt(in_pond, 0, "pond samples under a plunge carry a foot coordinate")


func test_dry_samples_have_no_surface() -> void:
	for i in _field.w.size():
		if _field.w[i] == WaterGeometry.DRY:
			assert_eq(_field.ew[i], WaterGeometry.DRY)
