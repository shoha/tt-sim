extends GutTest

## MapDownloadWait (staged_load2): the level load of a client that downloads its map waits for the
## coordinator (files, build, finalise with the structure wait) before it sets a token down, with
## a fake coordinator and a fake finalise that stands the structures a few a frame.

const FOLDER := "clearing"

var _order: Array[String] = []
var _busy: bool = false
var _superseded: bool = false


func before_each() -> void:
	_order.clear()
	_busy = false
	_superseded = false


func _is_busy() -> bool:
	return _busy


func _is_superseded() -> bool:
	return _superseded


## The client's load as LevelPlayLoader runs it: wait for the map, then set the tokens down.
func _load_level() -> bool:
	var in_hand := await MapDownloadWait.wait_async(
		get_tree(), _is_busy, _is_superseded, func() -> void: _order.append("announced")
	)
	if not in_hand:
		_order.append("dropped")
		return false
	_order.append("tokens")
	return true


func test_nothing_to_wait_for_returns_at_once() -> void:
	var done: bool = await _load_level()
	assert_true(done)
	assert_eq(_order, ["tokens"], "no announcement, no frame")


func test_tokens_land_after_the_structures_stand() -> void:
	# The fake coordinator: busy from the request, 4 structures stand a frame each, then done.
	_busy = true
	var finalize := func() -> void:
		for k in 4:
			await get_tree().process_frame
			_order.append("structure %d" % (k + 1))
		_order.append("finalised")
		_busy = false
	finalize.call()
	var done: bool = await _load_level()
	assert_true(done)
	assert_eq(
		_order,
		[
			"announced",
			"structure 1",
			"structure 2",
			"structure 3",
			"structure 4",
			"finalised",
			"tokens"
		],
		"the wait ends with the finalise, before any token"
	)


## Starts the client's load without waiting for it; the result lands in the returned dictionary.
func _start_load() -> Dictionary:
	var result := {"done": null}
	var start := func() -> void: result.done = await _load_level()
	start.call()
	return result


func test_the_wait_announces_once_however_long_it_takes() -> void:
	_busy = true
	var result := _start_load()
	await wait_process_frames(6)
	assert_eq(_order, ["announced"])
	_busy = false
	await wait_process_frames(2)
	assert_eq(_order, ["announced", "tokens"])
	assert_true(result.done)


func test_a_superseded_load_drops_instead_of_spawning() -> void:
	_busy = true
	var result := _start_load()
	await wait_process_frames(2)
	_superseded = true
	await wait_process_frames(2)
	assert_false(result.done)
	assert_eq(_order, ["announced", "dropped"])


func test_a_load_superseded_as_the_map_lands_also_drops() -> void:
	_superseded = true
	var result := _start_load()
	assert_false(result.done)
	assert_eq(_order, ["dropped"])
