extends GutTest
## The water laws of the derive (docs/systems/terraform.md), over the corpus: a river's level
## never climbs downstream, the tributary joins the main river and falls off its hill on the way,
## and the wall leaves an opening where the river crosses it.

var _n: RefCounted


func before_all() -> void:
	if TerraCore.native_available():
		_n = TerraCorpus.build().make_derive()
		_n.call("derive_full")


func test_levels_never_climb() -> void:
	if _n == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	var rivers: Array = _n.call("water_records")["rivers"]
	assert_eq(rivers.size(), 2, "two rivers")
	var climbs := 0
	var points := 0
	for r: Dictionary in rivers:
		var lv: PackedFloat32Array = r["level"]
		points += lv.size()
		for k in range(1, lv.size()):
			if lv[k] > lv[k - 1]:
				climbs += 1
	assert_gt(points, 100, "the rivers have level profiles")
	assert_eq(climbs, 0, "levels never climb downstream")


func test_tributary_joins_and_falls() -> void:
	if _n == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	var rivers: Array = _n.call("water_records")["rivers"]
	var trib: Dictionary = rivers[1]
	assert_eq(int(trib["recv_river"]), int(rivers[0]["id"]), "the tributary joins the main river")
	assert_gt(int(trib["falls"]), 0, "the tributary falls off the hill")
	var falls: PackedFloat32Array = _n.call("falls")
	assert_eq(falls.size() % 7, 0, "fall records are 7 floats each")
	assert_gt(falls.size(), 0, "fall records exist")
	for k in range(0, falls.size(), 7):
		assert_gt(falls[k + 4], falls[k + 5], "a fall's top is above its bottom")


func test_wall_opens_at_the_river() -> void:
	if _n == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	var walls: Array = _n.call("walls")
	assert_eq(walls.size(), 1, "one wall")
	var pts: PackedFloat32Array = walls[0]["pts"]
	var gaps := 0
	for k in range(3, pts.size(), 4):
		if pts[k] < 0.5:
			gaps += 1
	assert_gt(gaps, 0, "the wall leaves an opening where the river crosses")
	assert_lt(gaps, pts.size() / 4, "the wall stands elsewhere")


func test_pond_holds_water() -> void:
	if _n == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	var ponds: Array = _n.call("water_records")["ponds"]
	assert_eq(ponds.size(), 1, "one pond")
	var c := TerraCorpus.build()
	var centre := c.at(46.0, 34.0)
	var ground: float = _n.call("height_at", centre.x, centre.y)
	var water: float = _n.call("water_at", centre.x, centre.y)
	assert_gt(water, ground, "the pond's centre is under water")
	assert_almost_eq(water, float(ponds[0]["level"]), 1e-4, "at the pond's level")
