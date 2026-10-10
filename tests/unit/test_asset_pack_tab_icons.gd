extends GutTest

## AssetPackTab decodes icons on WorkerThreadPool tasks and applies them back on the main
## thread through a deferred call. The table can be torn down at any moment while those are
## queued or running (the host left the table 30 ms after it loaded in the probe that found
## this), and a task that is mid-run on a worker logs a SCRIPT ERROR at its next use of the
## tab ("Invalid access ... on a previously freed object"); is_instance_valid() inside the
## tab cannot help. The pipeline must therefore hold no reference to the tab beyond its
## instance id. GUT fails a test on any unhandled engine error, from any thread, so freeing
## the tab and letting the pool drain is the assertion.

const SCENE := preload("res://scenes/states/playing/asset_pack_tab.tscn")
const ICON_DIR := "user://_icon_task_race_/"
const ICON_COUNT := 24
const BIG_ICON_PATH := ICON_DIR + "big.png"
const BIG_ICON_SIZE := 3072
const BIG_ICON_COUNT := 4
## Time for the pool to pick the big decodes up before the tab is deleted.
const STARTED_MSEC := 5
## Generous: the small icons are 8x8 PNGs that decode in well under a millisecond, and the
## big ones take about 70 ms each.
const DECODE_MSEC := 200
const DRAIN_SEC := 0.5
const BIG_DRAIN_SEC := 1.0


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(ICON_DIR)
	var big := Image.create(BIG_ICON_SIZE, BIG_ICON_SIZE, false, Image.FORMAT_RGBA8)
	big.fill(Color(0.3, 0.6, 0.2))
	big.save_png(BIG_ICON_PATH)


func after_all() -> void:
	DirAccess.remove_absolute(BIG_ICON_PATH)
	DirAccess.remove_absolute(ICON_DIR)


func before_each() -> void:
	for i in range(ICON_COUNT):
		var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		image.fill(Color.from_hsv(float(i) / ICON_COUNT, 0.6, 0.9))
		image.save_png(_icon_path(i))


func after_each() -> void:
	for i in range(ICON_COUNT):
		DirAccess.remove_absolute(_icon_path(i))


func _icon_path(i: int) -> String:
	return ICON_DIR + "icon_%d.png" % i


func _item(i: int) -> Dictionary:
	return {
		"name": "icon %d" % i,
		"asset_id": "_icon_task_race_%d" % i,
		"icon_path": _icon_path(i),
	}


func _big_item(i: int) -> Dictionary:
	return {
		"name": "big icon %d" % i,
		"asset_id": "_icon_task_race_big_%d" % i,
		"icon_path": BIG_ICON_PATH,
	}


func _tab() -> AssetPackTab:
	var tab: AssetPackTab = SCENE.instantiate()
	add_child(tab)
	return tab


## Detach, then free. The tab's own item thread holds a call lock on it while it is in the
## tree, so a bare free() is refused; leaving the tree runs _exit_tree, which joins that
## thread, and then the delete is what a real teardown does.
func _free_tab(tab: AssetPackTab) -> void:
	remove_child(tab)
	tab.free()


## Decoded icons are queued for the main thread when the tab goes. Blocking the test body
## for DECODE_MSEC lets the pool finish every decode while the deferred applies cannot run
## (they wait for the main loop), so they all fire on a freed tab.
func test_freeing_the_tab_with_icon_results_queued_logs_no_error() -> void:
	var tab := _tab()
	for i in range(ICON_COUNT):
		tab._add_item_to_list(_item(i))
	OS.delay_msec(DECODE_MSEC)
	_free_tab(tab)
	await wait_seconds(DRAIN_SEC)
	await wait_process_frames(2)
	assert_false(is_instance_valid(tab))


## Workers are mid-decode when the tab goes, which is the reported failure: the task kept
## running on a tab that the table's teardown had deleted underneath it. The icons are big
## enough (about 70 ms each to decode) that the delete lands inside the decode, and the tab
## is torn down through the deferred queue, the way a scene teardown does it.
func test_freeing_the_tab_while_workers_decode_logs_no_error() -> void:
	var tab := _tab()
	for i in range(BIG_ICON_COUNT):
		tab._add_item_to_list(_big_item(i))
	OS.delay_msec(STARTED_MSEC)
	tab.queue_free()
	await wait_process_frames(2)
	assert_false(is_instance_valid(tab), "the tab is gone while its icon tasks decode")
	await wait_seconds(BIG_DRAIN_SEC)
	await wait_process_frames(2)


## A task that only starts after the tab is gone: run it directly with a stale id, then let
## its deferred apply fire.
func test_icon_task_started_after_the_tab_is_freed_logs_no_error() -> void:
	var tab := _tab()
	var tab_id := tab.get_instance_id()
	_free_tab(tab)
	AssetPackTab._load_icon_task(tab_id, _icon_path(0), "_icon_task_race_0", 0)
	await wait_process_frames(2)
	assert_null(instance_from_id(tab_id))


## The apply step alone, given a stale id and given a tab that is queued for deletion: both
## are dropped without touching the tab.
func test_apply_icon_drops_a_freed_tab() -> void:
	var tab := _tab()
	var tab_id := tab.get_instance_id()
	_free_tab(tab)
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	AssetPackTab._apply_icon(tab_id, image, "_icon_task_race_0", 0)
	assert_null(instance_from_id(tab_id))


func test_apply_icon_drops_a_tab_queued_for_deletion() -> void:
	var tab := _tab()
	tab.queue_free()
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	AssetPackTab._apply_icon(tab.get_instance_id(), image, "_icon_task_race_0", 0)
	assert_true(tab._icon_cache.is_empty(), "nothing is cached for a doomed tab")
	await wait_process_frames(2)


## A tab that stays alive still gets every icon: cached, and set on its list item.
func test_live_tab_receives_every_icon() -> void:
	var tab := _tab()
	autoqfree(tab)
	for i in range(ICON_COUNT):
		tab._add_item_to_list(_item(i))
	var all_set := func() -> bool:
		for i in range(ICON_COUNT):
			if tab.item_list.get_item_icon(i) == null:
				return false
		return true
	await wait_until(all_set, 3.0, "every list item gets its icon")
	assert_eq(tab._icon_cache.size(), ICON_COUNT)
	assert_true(tab._icon_cache.has("_icon_task_race_5"))


## The bounds check stays: a result for an item index the list no longer has is cached but
## not applied.
func test_apply_icon_ignores_an_out_of_range_index() -> void:
	var tab := _tab()
	autoqfree(tab)
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	AssetPackTab._apply_icon(tab.get_instance_id(), image, "_icon_task_race_0", 7)
	assert_true(tab._icon_cache.has("_icon_task_race_0"))
	assert_eq(tab.item_list.item_count, 0)
