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


## Flat reaches (card terraform-p2-bridge, today's conditioner rule): levels on the 5 cm
## lattice but a join's last point (the receiver's level), every fall-sized step a fall record and
## every other step a riffle at least the dead band (a step the conditioner may not drop without
## making a fall is allowed and counted), and the water level WL only ever one of the levels.
func test_river_levels_are_flat_reaches() -> void:
	if _n == null:
		pending(TerraCorpus.NO_LIBRARY)
		return
	var rivers: Array = _n.call("water_records")["rivers"]
	var off_lattice := 0
	var fall_steps := 0
	var small := 0
	var reaches := 0
	var levels := {}
	for r: Dictionary in rivers:
		var lv: PackedFloat32Array = r["level"]
		var joined := int(r["recv_river"]) >= 0 or int(r["recv_pond"]) >= 0
		var last := lv.size() - (2 if joined else 1)
		reaches += 1
		for k in lv.size():
			levels[lv[k]] = true
			var q := lv[k] / 0.05
			if k <= last and absf(q - roundf(q)) > 1e-3:
				off_lattice += 1
			if k == 0:
				continue
			var step := lv[k - 1] - lv[k]
			if step > 1e-6:
				reaches += 1
			# A step under CHUTE_MAX_M is a chute, not a fall (card terraform-p2-chutes).
			if step >= WaterFalls.CHUTE_MAX_M - 1e-4:
				fall_steps += 1
			elif step > 1e-6 and step < 0.25 - 1e-4 and k <= last:
				small += 1
		assert_eq(fall_steps, _falls_up_to(rivers, r), "every tall step is a fall record")
	assert_eq(off_lattice, 0, "levels on the lattice")
	assert_lt(small, 3, "steps under the dead band are rare (%d)" % small)
	gut.p("flat reaches: %d reaches, %d falls, %d small steps" % [reaches, fall_steps, small])
	var wl: PackedFloat32Array = (_n.call("array_bytes", "WL") as PackedByteArray).to_float32_array()
	var h2: PackedFloat32Array = (_n.call("array_bytes", "H2") as PackedByteArray).to_float32_array()
	var ponds: Array = _n.call("water_records")["ponds"]
	for p: Dictionary in ponds:
		levels[float(p["level"])] = true
	var stray := 0
	var wet := 0
	for i in wl.size():
		if wl[i] > h2[i]:
			wet += 1
			stray += 0 if levels.has(wl[i]) else 1
	assert_gt(wet, 1000, "the corpus has water")
	assert_eq(stray, 0, "every wet sample stands at one body's level")


## The fall counts of the records up to and including river `upto`.
func _falls_up_to(rivers: Array, upto: Dictionary) -> int:
	var n := 0
	for r: Dictionary in rivers:
		n += int(r["falls"])
		if r == upto:
			break
	return n


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
