extends GutTest

## The persistent fire's sound (cards F7, F7b and F7c; FireSound): the manifest declares the roar
## a loop on the SFX bus, AudioManager hands out its stream and refuses to play it as a one-shot,
## the file imports looping (QOA) and its last sample runs into its first without a click; a
## field's players exist only while flames do, stand at the strongest clusters, fade in and out
## and are freed once the fire is erased; pick hears the clusters near the view only, loudest
## first, each cluster by its flames (FireClusters.spots) rather than its centroid, so a view over
## any flame hears the fire at the closest zoom, centred.

const SOUND := &"fire_roar"
const PATH := "res://assets/audio/sfx/fire_roar.wav"
## tools/sfx_render.py LOOP_SEAM_MAX_RATIO.
const SEAM_MAX_RATIO := 4.0


## A flat 40-cell map burning at mask byte `heat` in discs of `radius` metres at `centres`.
func _doc(centres: Array, radius: float, heat: int = 255) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 5)
	var mask := PackedByteArray()
	mask.resize(doc.sample_count())
	var half := doc.extent_m() * 0.5
	var step := doc.sample_step()
	for iz in doc.samples_z():
		for ix in doc.samples_x():
			var p := -half + Vector2(ix, iz) * step
			for centre: Vector2 in centres:
				if p.distance_to(centre) <= radius:
					mask[doc.sample_index(ix, iz)] = heat
	doc.fire_mask = mask
	return doc


## The flames' cells of `doc` as FireField sums them (every block planned, row order).
func _cells(doc: MapDocument) -> Dictionary:
	var per_block := {}
	for block in FireField.blocks_of(doc, Rect2i(0, 0, doc.samples_x(), doc.samples_z())):
		var plan := FireField.plan_block(doc, block)
		if not plan.is_empty():
			per_block[block] = FireClusters.cells_of(plan)
	return FireClusters.merge(per_block)


## The burning clusters of `doc` as FireField finds them.
func _clusters(doc: MapDocument) -> Array[Dictionary]:
	return FireClusters.find(_cells(doc), false)


## A band of flames along x, about 23 m long and 7 m wide.
func _band() -> MapDocument:
	var centres := []
	for k in 5:
		centres.append(Vector2(-8.0 + 4.0 * k, 0.0))
	return _doc(centres, 3.5)


func _cluster(cell: Vector2i, at: Vector3, size: float) -> Dictionary:
	return {"cell": cell, "at": at, "size": size, "blaze": 0.0, "top": 1.0}


## The RMS step between neighbouring samples of `pcm` (16-bit) over frames [from, to).
func _typical_step(pcm: PackedByteArray, from: int, to: int) -> float:
	var sum := 0.0
	var last := pcm.decode_s16(from * 2)
	for i in range(from + 1, to):
		var value := pcm.decode_s16(i * 2)
		sum += float(value - last) * float(value - last)
		last = value
	return sqrt(sum / (to - from - 1))


# --- the manifest and the file -----------------------------------------------------------------


func test_the_manifest_declares_a_loop_on_the_sfx_bus() -> void:
	var entry := AudioManager.sound_entry(SOUND)
	assert_eq(entry.get("loop"), true)
	assert_eq(entry.get("bus"), AudioManager.BUS_SFX)
	assert_eq(entry.get("path"), PATH)
	var drop := float(AudioManager.sound_entry(&"token_drop")["volume_db"])
	assert_lt(float(entry["volume_db"]), drop, "an ambience under the token sounds")
	assert_false(AudioManager.sound_entry(&"token_drop").get("loop", true), "one-shots say so")


func test_the_stream_imports_looping_and_compressed() -> void:
	var stream := AudioManager.loop_stream(SOUND) as AudioStreamWAV
	assert_not_null(stream, "a loop's stream")
	if stream == null:
		return
	assert_null(AudioManager.loop_stream(&"token_drop"), "a one-shot has no loop stream")
	assert_eq(stream.format, AudioStreamWAV.FORMAT_QOA, "QOA keeps the minute small")
	assert_false(stream.stereo)
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(stream.loop_begin, 0)
	var pcm := AudioStreamWAV.load_from_file(PATH, {"compress/mode": 0})
	assert_not_null(pcm, "the committed file reads as PCM")
	if pcm == null:
		return
	@warning_ignore("integer_division")
	var frames := pcm.data.size() / 2
	assert_eq(stream.mix_rate, pcm.mix_rate)
	assert_gt(frames, pcm.mix_rate * 30, "a long loop: no repeat heard within half a minute")
	# The import's loop_end -1 is the last frame, so the file ends in a guard sample equal to
	# the first: the loop plays every other sample and wraps where it is the same value.
	assert_eq(stream.loop_end, frames - 1, "the whole file loops")


func test_the_loop_joins_its_start_without_a_click() -> void:
	var pcm := AudioStreamWAV.load_from_file(PATH, {"compress/mode": 0})
	assert_eq(pcm.format, AudioStreamWAV.FORMAT_16_BITS)
	@warning_ignore("integer_division")
	var frames := pcm.data.size() / 2
	var data := pcm.data
	assert_eq(data.decode_s16((frames - 1) * 2), data.decode_s16(0), "the guard is the first")
	var second := pcm.mix_rate
	var typical := (
		0.5 * (_typical_step(data, 0, second) + _typical_step(data, frames - 1 - second, frames - 1))
	)
	var seam := absf(float(data.decode_s16(0) - data.decode_s16((frames - 2) * 2)))
	assert_lte(seam / typical, SEAM_MAX_RATIO, "the seam steps like any neighbour")


func test_play_refuses_a_loop() -> void:
	var queue := SoundRequestQueue.new({&"_test_loop": {"bus": "SFX", "loop": true}})
	assert_true(queue.is_loop(&"_test_loop"))
	assert_false(queue.request(&"_test_loop", 0.0), "a loop would hold a voice for ever")
	assert_false(queue.has_pending())
	assert_engine_error("is a loop")


# --- pick ---------------------------------------------------------------------------------------


func test_pick_hears_the_loudest_near_the_view_ties_in_order() -> void:
	var eye := Vector3(0.0, 20.0, 0.0)
	var clusters: Array[Dictionary] = [
		_cluster(Vector2i(0, 0), Vector3(30.0, 0.0, 0.0), 40.0),
		_cluster(Vector2i(1, 0), Vector3(2.0, 0.0, 1.0), 3.0),
		_cluster(Vector2i(2, 0), Vector3(-3.0, 0.0, 0.0), 12.0),
		_cluster(Vector2i(3, 0), Vector3(1.0, 0.0, -2.0), 3.0),
	]
	var picked := FireSound.pick(clusters, eye, Vector3.DOWN, 10.0)
	assert_eq(picked.size(), FireSound.MAX_PLAYERS)
	assert_eq(picked[0]["cell"], Vector2i(2, 0), "the largest in view; the biggest is off it")
	assert_almost_eq(float(picked[0]["gain"]), 1.0, 1e-6, "full size, in the middle")
	assert_eq(picked[1]["cell"], Vector2i(1, 0), "a tie keeps the given order")
	assert_almost_eq(float(picked[1]["gain"]), FireSound.gain_for(3.0), 1e-6)
	var no_view := FireSound.pick(clusters, eye, Vector3.DOWN, INF)
	assert_eq(no_view[0]["cell"], Vector2i(0, 0), "without a camera every cluster is heard")


func test_pick_fades_a_cluster_across_the_view_edge() -> void:
	var view := 10.0
	# Its flames reach SPOT_REACH_M around its centroid: this far out they are half way from
	# whole (FULL_SHARE of the view) to silent (REACH_SHARE).
	var edge := FireSound.SPOT_REACH_M + 0.75 * view
	var at_edge: Array[Dictionary] = [_cluster(Vector2i.ZERO, Vector3(edge, 0.0, 0.0), 12.0)]
	var picked := FireSound.pick(at_edge, Vector3(0.0, 20.0, 0.0), Vector3.DOWN, view)
	assert_eq(picked.size(), 1)
	assert_between(float(picked[0]["gain"]), 0.01, 0.99, "half way out: partly heard")
	var out := FireSound.SPOT_REACH_M + 1.05 * view
	var gone: Array[Dictionary] = [_cluster(Vector2i.ZERO, Vector3(out, 0.0, 0.0), 12.0)]
	assert_eq(FireSound.pick(gone, Vector3(0.0, 20.0, 0.0), Vector3.DOWN, view).size(), 0)
	assert_eq(FireSound.gain_for(0.0), 0.0)
	assert_almost_eq(FireSound.gain_for(FireSound.FULL_SIZE_M2 * 4.0), 1.0, 1e-6)


func test_pick_at_the_closest_zoom_hears_a_cluster_over_its_flames_off_its_centroid() -> void:
	# Card F7c's report: at zoom 2 a cluster counted by its centroid alone fell silent 3 m from
	# it, with the view full of its flames.
	var centroid := Vector3(1.5, 0.0, 0.2)
	var cluster := _cluster(Vector2i.ZERO, centroid, 12.0)
	cluster["spots"] = PackedVector3Array(
		[Vector3.ZERO, Vector3(3.5, 0.0, 0.0), Vector3(7.0, 0.0, 0.5)]
	)
	var eye := Vector3(9.5, 20.0, 0.0)
	var one: Array[Dictionary] = [cluster]
	var picked := FireSound.pick(one, eye, Vector3.DOWN, 2.0)
	assert_eq(picked.size(), 1)
	assert_almost_eq(float(picked[0]["gain"]), 1.0, 1e-6, "whole over its flames")
	var at: Vector3 = picked[0]["at"]
	assert_almost_eq(Vector2(at.x, at.z), Vector2(9.5, 0.0), Vector2.ONE * 1e-5, "centred")
	var point: Array[Dictionary] = [_cluster(Vector2i.ZERO, centroid, 12.0)]
	assert_eq(FireSound.pick(point, eye, Vector3.DOWN, 2.0).size(), 0, "its centroid alone: out")


func test_pick_pulls_a_place_toward_the_view_middle_within_the_reach() -> void:
	var at := Vector3(0.0, 0.0, 0.0)
	var clusters: Array[Dictionary] = [_cluster(Vector2i.ZERO, at, 12.0)]
	var inside := FireSound.pick(clusters, Vector3(1.0, 20.0, 0.0), Vector3.DOWN, 2.0)
	assert_almost_eq(inside[0]["at"], Vector3(1.0, 0.0, 0.0), Vector3.ONE * 1e-5, "the middle")
	for view in [2.0, 8.0, 14.0]:
		# The cluster left of the view's middle, its flames 30% of the way out of the fade.
		var full := maxf(FireSound.FULL_SHARE * view, FireSound.FULL_MIN_M)
		var reach := maxf(FireSound.REACH_SHARE * view, FireSound.REACH_MIN_M)
		var eye := Vector3(FireSound.SPOT_REACH_M + full + 0.3 * (reach - full), 20.0, 0.0)
		var picked := FireSound.pick(clusters, eye, Vector3.DOWN, view)
		assert_eq(picked.size(), 1, "heard at view %.0f" % view)
		var place: Vector3 = picked[0]["at"]
		assert_almost_eq(place.distance_to(at), FireSound.SPOT_REACH_M, 1e-5, "within the reach")
		assert_between(place.x, 0.0, eye.x - full, "toward the middle, still left of it")
		assert_between(float(picked[0]["gain"]), 0.5, 0.99, "partly heard")


func test_pick_leaves_a_far_cluster_silent_at_every_zoom() -> void:
	for view in [2.0, 8.0, 14.0]:
		var reach := maxf(FireSound.REACH_SHARE * view, FireSound.REACH_MIN_M)
		var far := Vector3(FireSound.SPOT_REACH_M + reach + 0.5, 0.0, 0.0)
		var cluster := _cluster(Vector2i.ZERO, far, 40.0)
		cluster["spots"] = PackedVector3Array([far, far + Vector3(3.0, 0.0, 0.0)])
		var one: Array[Dictionary] = [cluster]
		var picked := FireSound.pick(one, Vector3(0.0, 20.0, 0.0), Vector3.DOWN, view)
		assert_eq(picked.size(), 0, "silent at view %.0f" % view)


func test_spots_give_every_burning_cell_to_one_cluster() -> void:
	var cells := _cells(_band())
	var clusters := FireClusters.find(cells, false)
	var spots := FireClusters.spots(cells)
	var wanted := []
	for cluster in clusters:
		wanted.append(cluster["cell"])
	var keys := spots.keys()
	assert_eq(keys.size(), wanted.size(), "one entry per cluster")
	for key in keys:
		assert_has(wanted, key)
	var count := 0
	for key in keys:
		count += (spots[key] as PackedVector3Array).size()
	var burning := 0
	for cell in cells:
		if (cells[cell] as PackedFloat64Array)[FireClusters.SIZE] > 0.0:
			burning += 1
	assert_eq(count, burning, "every burning cell in exactly one cluster")


func test_a_view_over_any_flame_hears_the_fire_at_the_closest_zoom() -> void:
	var field := FireField.create(_band())
	add_child_autofree(field)
	var clusters := field.sound().clusters()
	assert_gt(clusters.size(), 0)
	var missed := 0
	var spots := 0
	for cluster in clusters:
		for spot: Vector3 in cluster["spots"]:
			spots += 1
			var eye := spot + Vector3(0.3, 20.0, -0.4)
			var picked := FireSound.pick(clusters, eye, Vector3.DOWN, 2.0)
			assert_gt(picked.size(), 0, "heard over the flames at %s" % str(spot))
			var bare: Array[Dictionary] = []
			for c in clusters:
				bare.append(_cluster(c["cell"], c["at"], float(c["size"])))
			if FireSound.pick(bare, eye, Vector3.DOWN, 2.0).is_empty():
				missed += 1
	gut.p("%d clusters, %d spots; centroids alone silent over %d" % [clusters.size(), spots, missed])
	assert_gt(missed, 0, "the band has flames its centroids alone would leave silent")


func test_pick_costs_little_for_a_wide_fire() -> void:
	var clusters: Array[Dictionary] = []
	for k in 300:
		var at := Vector3(fmod(k * 7.3, 120.0) - 60.0, 0.0, fmod(k * 3.1, 90.0) - 45.0)
		clusters.append(_cluster(Vector2i(k, 0), at, 1.0 + k % 13))
	var start := Time.get_ticks_usec()
	for i in 20:
		FireSound.pick(clusters, Vector3(0.0, 30.0, 0.0), Vector3.DOWN, 14.0)
	var each_us := (Time.get_ticks_usec() - start) / 20.0
	gut.p("FireSound.pick over 300 clusters: %.0f us" % each_us)
	assert_lt(each_us, 20000.0, "a placement update is not a frame's worth of work")


# --- the field's players ------------------------------------------------------------------------


func test_players_exist_only_while_flames_do_at_the_strongest_clusters() -> void:
	var doc := _doc([Vector2(-15.0, -10.0), Vector2(12.0, 9.0)], 4.0)
	var field := FireField.create(doc)
	add_child_autofree(field)
	var sound := field.sound()
	assert_not_null(sound, "made with the first fire")
	var players := sound.players()
	assert_eq(players.size(), FireSound.MAX_PLAYERS)
	var expected := FireSound.pick(_clusters(doc), Vector3.ZERO, Vector3.DOWN, INF)
	assert_eq(expected.size(), 2, "two fires, two clusters heard")
	for slot in players.size():
		assert_eq(players[slot].position, expected[slot]["at"], "at the strongest clusters")
		assert_eq(players[slot].bus, AudioManager.BUS_SFX, "the Settings SFX volume governs it")
		assert_eq(
			players[slot].attenuation_model,
			AudioStreamPlayer3D.ATTENUATION_DISABLED,
			"the level is the view's fire, not the camera's height"
		)
	assert_ne(players[0].pitch_scale, players[1].pitch_scale, "the pair never phases")

	# Fades in over about a second.
	sound.advance(0.25)
	assert_almost_eq(sound.gains()[0], minf(0.25, float(expected[0]["gain"])), 1e-5)
	sound.advance(2.0)
	for slot in players.size():
		assert_almost_eq(sound.gains()[slot], float(expected[slot]["gain"]), 1e-5)
	var base := float(AudioManager.sound_entry(SOUND)["volume_db"])
	var full_db := base + linear_to_db(float(expected[0]["gain"]))
	assert_almost_eq(players[0].volume_db, full_db, 0.01, "the entry's gain under the fade")

	# Erased: the players fade out, then go.
	var cleared := PackedByteArray()
	cleared.resize(doc.sample_count())
	doc.fire_mask = cleared
	field.refresh(Rect2i(0, 0, doc.samples_x(), doc.samples_z()))
	assert_eq(sound.players().size(), FireSound.MAX_PLAYERS, "still fading")
	sound.advance(0.1)
	assert_eq(sound.players().size(), FireSound.MAX_PLAYERS)
	assert_lt(sound.gains()[0], float(expected[0]["gain"]), "fading out")
	sound.advance(1.5)
	assert_eq(sound.players().size(), 0, "no flames, no players")
	assert_eq(sound.gains().size(), 0)


func test_embers_alone_make_no_sound() -> void:
	var field := FireField.create(_doc([Vector2.ZERO], 6.0, FireField.EMBER_MIN + 20))
	add_child_autofree(field)
	var sound := field.sound()
	assert_true(sound == null or sound.players().is_empty(), "embers glow silently")
