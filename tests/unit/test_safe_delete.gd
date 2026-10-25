extends GutTest

## Destructive operations of the library code (docs/systems/library.md "Destructive operations").
## On 2026-10-24 a recursive delete given a root that was empty or relative emptied a whole
## worktree, because the file system reads "" and "." as the working directory. These tests feed
## every destructive entry point the hostile roots, ids, names and trees listed there and assert
## that nothing outside the intended folder is touched. Everything happens under a scratch
## folder in the user data folder; a canary file (with an ownership marker, the worst case) sits
## beside the libraries and must survive every case, and so must the project (res://).

const World := preload("res://tests/unit/library_world.gd")
const Zip := preload("res://tests/unit/zip_builder.gd")
const ScratchDir := preload("res://tests/unit/scratch_dir.gd")
const ROOT := "user://test_safe_delete"
const LIBS := ROOT + "/libs"
const RECEIVED := LIBS + "/.received"
const CACHE := ROOT + "/cache"
const CANARY := ROOT + "/canary"
const SOURCE := ROOT + "/source/alienworld"
const UNSAFE_ROOTS: Array[String] = [
	"",
	" ",
	".",
	"./",
	"..",
	"libraries",
	"libraries/",
	"./libraries",
	"../libraries",
	"user://",
	"user://..",
	"user://a/../..",
	"res://",
	"res://libraries",
	"C:/",
	"/",
]

var _saved_user: String = ""
var _saved_official: String = ""
var _saved_settings: String = ""
var _saved_override: String = ""
var _saved_cache: String = ""
var _saved_levels: String = ""


func before_all() -> void:
	_saved_user = LibraryRegistry.user_root
	_saved_official = LibraryRegistry.official_root
	_saved_settings = LibraryRegistry.settings_path
	_saved_override = LibraryImporter.incoming_override
	_saved_cache = SurfaceCache.root
	_saved_levels = LevelManager.levels_dir


func after_all() -> void:
	_restore()
	ScratchDir.clear(ROOT)


func before_each() -> void:
	_restore()
	ScratchDir.clear(ROOT)
	LibraryRegistry.clear()
	LibraryRegistry.settings_path = ROOT + "/settings.cfg"
	LibraryRegistry.official_root = ROOT + "/official"
	LibraryRegistry.user_root = LIBS
	SurfaceCache.root = CACHE
	DirAccess.make_dir_recursive_absolute(LIBS)
	DirAccess.make_dir_recursive_absolute(ROOT + "/official")
	_write(CANARY + "/precious.txt", "keep")
	_write(CANARY + "/" + SafeDelete.MARKER, "{}")


func _restore() -> void:
	LibraryRegistry.user_root = _saved_user
	LibraryRegistry.official_root = _saved_official
	LibraryRegistry.settings_path = _saved_settings
	LibraryImporter.incoming_override = _saved_override
	SurfaceCache.root = _saved_cache
	LevelManager.levels_dir = _saved_levels
	SafeDelete.max_entries = SafeDelete.MAX_ENTRIES
	LibraryPaths.extra_anchors = []
	LibraryRegistry.clear()


# ---- helpers ----


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## A folder with a file in it and (when `owned`) the ownership marker.
func _folder(path: String, owned: bool, base: String = LIBS) -> void:
	_write(path + "/library.json", "{}")
	_write(path + "/sub/data.txt", "x")
	if owned:
		assert_true(SafeDelete.mark(path, "test", base), "marked " + path)


func _survives() -> void:
	assert_true(FileAccess.file_exists(CANARY + "/precious.txt"), "the canary file is gone")
	assert_true(FileAccess.file_exists(CANARY + "/" + SafeDelete.MARKER), "the canary marker")
	assert_true(DirAccess.dir_exists_absolute("res://scenes"), "the project is still there")
	assert_true(FileAccess.file_exists("res://project.godot"), "project.godot is still there")


func _exists(path: String) -> bool:
	return DirAccess.dir_exists_absolute(path)


func _empty_plan() -> Dictionary:
	return {"ok": true, "kind": "folder", "files": [], "total_bytes": 0, "source": ""}


## A directory junction (no admin rights needed) from `link` to `target`; false off Windows or
## when the junction cannot be made.
func _junction(link: String, target: String) -> bool:
	if OS.get_name() != "Windows":
		return false
	DirAccess.make_dir_recursive_absolute(link.get_base_dir())
	var from := ProjectSettings.globalize_path(link).replace("/", "\\")
	var to := ProjectSettings.globalize_path(target).replace("/", "\\")
	var output: Array = []
	var code := OS.execute("cmd", ["/c", "mklink", "/J", from, to], output)
	return code == OK and _exists(link)


# ---- the resolver ----


func test_unsafe_roots_never_resolve() -> void:
	var hostile: Array[String] = UNSAFE_ROOTS.duplicate()
	hostile.append(ProjectSettings.globalize_path("res://"))
	hostile.append(ProjectSettings.globalize_path("res://scenes"))
	hostile.append(LibraryPaths.user_dir())
	hostile.append(LibraryPaths.user_dir().get_base_dir())
	hostile.append(LibraryPaths.user_dir() + "/..")
	hostile.append(LibraryPaths.user_dir() + "/libs/../../x")
	for bad in hostile:
		assert_ne(LibraryPaths.verify(bad), "", "'%s' must not resolve" % bad)
	for good in [LIBS, ROOT + "/a/b", LibraryPaths.user_dir() + "/x"]:
		assert_eq(LibraryPaths.verify(good), "", good)
	var resolved := LibraryPaths.resolve(LIBS + "//sub/./x/")
	assert_true(resolved["ok"])
	assert_true(String(resolved["path"]).is_absolute_path(), "absolute")
	assert_false("//" in String(resolved["path"]).trim_prefix("//"), "normalised")


func test_child_names_are_one_plain_segment() -> void:
	var root := LibraryPaths.libraries()
	assert_true(root["ok"])
	for bad in ["", ".", "..", "a/b", "a\\b", "C:", "../x"]:
		assert_false(LibraryPaths.child(root, bad)["ok"], "'%s' is not a folder name" % bad)
	assert_true(LibraryPaths.child(root, "alienworld")["ok"])


func test_named_roots_follow_the_settings_and_fail_closed() -> void:
	assert_true(LibraryPaths.libraries()["ok"])
	assert_true(String(LibraryPaths.incoming()["path"]).ends_with("/libs/.incoming"))
	assert_true(String(LibraryPaths.received()["path"]).ends_with("/libs/.received"))
	LibraryRegistry.user_root = ""
	assert_false(LibraryPaths.libraries()["ok"])
	assert_false(LibraryPaths.incoming()["ok"])
	assert_false(LibraryPaths.received()["ok"])
	assert_eq(LibraryPaths.allowed_bases().size(), 1, "only the cache root resolves")
	SurfaceCache.root = "."
	assert_eq(LibraryPaths.allowed_bases().size(), 0)


# ---- the root cause: an empty or relative root ----


func test_an_empty_or_relative_registry_root_touches_nothing() -> void:
	for bad in UNSAFE_ROOTS:
		LibraryRegistry.user_root = bad
		LibraryImporter.incoming_override = ""
		var label := "user_root '%s'" % bad
		assert_eq(LibraryImporter.sweep_incoming(), 0, label)
		assert_false(LibraryImporter.stage(_empty_plan())["ok"], label)
		assert_false(LibraryImporter.discard("scenes"), label)
		assert_false(LibraryImporter.is_quarantined("scenes"), label)
		for id in ["scenes", "utils", "addons", "tests", "docs", "alienworld"]:
			assert_false(LibraryInstall.remove(id)["ok"], label + " remove " + id)
		var card := {"can_install": true, "id": "scenes", "folder": ".incoming/x"}
		assert_false(LibraryInstall.install(card, true)["ok"], label)
		assert_false(LibraryReceivedStore.remove("scenes"), label)
		assert_eq(LibraryReceivedStore.sweep_leftovers(), [], label)
		assert_eq(LibraryReceivedStore.sweep_session(), [], label)
		assert_ne(LibraryReceivedStore.write_library("", "scenes", {}, 0, {}), "", label)
		assert_false(LibraryReceivedStore.promote("scenes")["ok"], label)
		_survives()


func test_an_unsafe_incoming_override_touches_nothing() -> void:
	for bad in UNSAFE_ROOTS:
		if bad == "":
			continue  # unset: the quarantine is <libraries>/.incoming
		LibraryImporter.incoming_override = bad
		assert_eq(LibraryImporter.sweep_incoming(), 0, "override '%s'" % bad)
		assert_false(LibraryImporter.stage(_empty_plan())["ok"], bad)
		_survives()
	# A real but wrongly named folder is no quarantine either: the sweep wants ".incoming".
	_folder(ROOT + "/not_incoming/abc", true, ROOT + "/not_incoming")
	LibraryImporter.incoming_override = ROOT + "/not_incoming"
	assert_eq(LibraryImporter.sweep_incoming(), 0)
	assert_true(_exists(ROOT + "/not_incoming/abc"))


func test_an_unsafe_cache_root_touches_nothing() -> void:
	var image := Image.create(4, 4, true, Image.FORMAT_RGBA8)
	for bad in UNSAFE_ROOTS:
		SurfaceCache.root = bad
		assert_false(SurfaceCache.write(bad + "/lib/h/s.ttimg", image), bad)
		assert_false(SurfaceCache.remove_library("alienworld"), bad)
		assert_false(SurfaceCache.remove_library("scenes"), bad)
		_survives()


func test_the_cache_refuses_a_path_outside_its_root() -> void:
	var image := Image.create(4, 4, true, Image.FORMAT_RGBA8)
	assert_false(SurfaceCache.write(ROOT + "/elsewhere/x.ttimg", image))
	assert_false(SurfaceCache.write(CACHE + "/../elsewhere/x.ttimg", image))
	assert_false(_exists(ROOT + "/elsewhere"))


# ---- SafeDelete itself ----


func test_tree_needs_the_marker() -> void:
	_folder(LIBS + "/plain", false)
	var refused := SafeDelete.tree(LIBS + "/plain", LIBS)
	assert_false(refused["ok"])
	assert_true(_exists(LIBS + "/plain/sub"), "an unmarked folder is never deleted")
	_folder(LIBS + "/mine", true)
	var done := SafeDelete.tree(LIBS + "/mine", LIBS)
	assert_true(done["ok"], str(done))
	assert_gt(int(done["deleted"]), 3, "counted the entries")
	assert_false(_exists(LIBS + "/mine"))
	assert_true(_exists(LIBS + "/plain"))
	assert_true(SafeDelete.tree(LIBS + "/never_was", LIBS)["ok"], "already gone is fine")
	_survives()


func test_tree_stays_strictly_inside_its_base() -> void:
	_folder(LIBS + "/mine", true)
	# The base itself and its parents carry a marker too: they still must not go.
	SafeDelete.mark(LIBS, "test", ROOT)
	SafeDelete.mark(ROOT, "test", LibraryPaths.user_dir() + "/..") # refused: outside
	assert_false(SafeDelete.tree(LIBS, LIBS)["ok"], "the base itself")
	assert_false(SafeDelete.tree(ROOT, LIBS)["ok"], "the parent of the base")
	assert_false(SafeDelete.tree(CANARY, LIBS)["ok"], "a sibling of the base, marker and all")
	assert_false(SafeDelete.tree(LIBS + "/mine/../../canary", LIBS)["ok"], "a .. path")
	assert_false(SafeDelete.tree(LIBS + "/mine/sub/../..", LIBS)["ok"], "a .. path to the base")
	assert_false(SafeDelete.tree(LIBS + "/mine", ROOT + "/canary")["ok"], "the wrong base")
	for bad in UNSAFE_ROOTS:
		if bad != "":  # "" means the default bases, which do cover the libraries folder
			assert_false(SafeDelete.tree(LIBS + "/mine", bad)["ok"], "base '%s'" % bad)
	assert_false(SafeDelete.tree(LIBS + "/mine/library.json", LIBS)["ok"], "a file is not a tree")
	assert_true(_exists(LIBS + "/mine/sub"))
	assert_true(_exists(LIBS), "the base survives")
	_survives()


func test_tree_with_default_bases_uses_only_the_managed_roots() -> void:
	_folder(LIBS + "/mine", true)
	_folder(ROOT + "/outside", true, ROOT)
	assert_false(SafeDelete.tree(ROOT + "/outside")["ok"], "outside every managed root")
	assert_true(SafeDelete.tree(LIBS + "/mine")["ok"], "inside the libraries")
	LibraryRegistry.user_root = ""
	_folder(LIBS + "/again", true)
	assert_false(SafeDelete.tree(LIBS + "/again")["ok"], "no root, no default base")
	assert_true(_exists(LIBS + "/again"))


func test_tree_refuses_an_oversized_or_too_deep_tree() -> void:
	_folder(LIBS + "/big", true)
	for index in 10:
		_write(LIBS + "/big/files/%d.txt" % index, "x")
	SafeDelete.max_entries = 5
	var refused := SafeDelete.tree(LIBS + "/big", LIBS)
	assert_false(refused["ok"])
	assert_true("more than 5" in String(refused["error"]), str(refused))
	assert_true(FileAccess.file_exists(LIBS + "/big/files/9.txt"), "nothing was removed")
	assert_true(FileAccess.file_exists(LIBS + "/big/" + SafeDelete.MARKER), "marker kept")
	SafeDelete.max_entries = SafeDelete.MAX_ENTRIES
	var deep := LIBS + "/deep"
	_folder(deep, true)
	var path := deep
	for level in SafeDelete.MAX_DEPTH + 3:
		path += "/d"
	DirAccess.make_dir_recursive_absolute(path)
	assert_false(SafeDelete.tree(deep, LIBS)["ok"], "too deep")
	assert_true(_exists(path))
	assert_true(SafeDelete.tree(LIBS + "/big", LIBS)["ok"], "within the cap it goes")


func test_hidden_files_do_not_stop_a_delete() -> void:
	_folder(LIBS + "/mine", true)
	_write(LIBS + "/mine/.hidden", "x")
	_write(LIBS + "/mine/sub/.also", "x")
	assert_true(SafeDelete.tree(LIBS + "/mine", LIBS)["ok"])
	assert_false(_exists(LIBS + "/mine"))


func test_file_stays_inside_its_base() -> void:
	_write(LIBS + "/a.txt", "x")
	assert_true(SafeDelete.file(LIBS + "/a.txt", LIBS)["ok"])
	assert_false(FileAccess.file_exists(LIBS + "/a.txt"))
	assert_false(SafeDelete.file(CANARY + "/precious.txt", LIBS)["ok"], "outside the base")
	assert_false(SafeDelete.file("precious.txt", LIBS)["ok"], "relative")
	assert_false(SafeDelete.file("", LIBS)["ok"], "empty")
	assert_false(SafeDelete.file(LIBS + "/../canary/precious.txt", LIBS)["ok"], "..")
	_folder(LIBS + "/mine", true)
	assert_false(SafeDelete.file(LIBS + "/mine", LIBS)["ok"], "a folder is not a file")
	assert_true(_exists(LIBS + "/mine"))
	_survives()


# ---- links ----


func test_a_junction_inside_a_tree_stops_the_delete() -> void:
	_folder(LIBS + "/victim", true)
	if not _junction(LIBS + "/victim/sub/link", CANARY):
		pending("no directory junction on this system")
		return
	var refused := SafeDelete.tree(LIBS + "/victim", LIBS)
	assert_false(refused["ok"])
	assert_true("link" in String(refused["error"]), str(refused))
	assert_true(FileAccess.file_exists(LIBS + "/victim/library.json"), "nothing was removed")
	_survives()
	assert_false(LibraryInstall.remove("victim")["ok"])
	_survives()
	assert_eq(LibraryImporter.sweep_incoming(), 0)
	_survives()


func test_a_junction_as_the_folder_or_on_the_way_is_refused() -> void:
	# The junction's target carries a marker (the canary folder): the link itself must stop it.
	if not _junction(LIBS + "/linked", CANARY):
		pending("no directory junction on this system")
		return
	assert_false(SafeDelete.tree(LIBS + "/linked", LIBS)["ok"], "the folder is a link")
	assert_false(LibraryInstall.remove("linked")["ok"])
	_survives()
	_folder(ROOT + "/other/victim2", true, ROOT + "/other")
	assert_true(_junction(LIBS + "/mid", ROOT + "/other"))
	assert_false(SafeDelete.tree(LIBS + "/mid/victim2", LIBS)["ok"], "a link on the way")
	assert_true(_exists(ROOT + "/other/victim2/sub"), "the target survived")
	assert_false(SafeDelete.file(LIBS + "/mid/victim2/library.json", LIBS)["ok"])
	assert_true(FileAccess.file_exists(ROOT + "/other/victim2/library.json"))
	_survives()


func test_a_junction_among_the_quarantine_folders_is_not_followed() -> void:
	var incoming := LIBS + "/.incoming"
	if not _junction(incoming + "/aaaa", CANARY):
		pending("no directory junction on this system")
		return
	assert_eq(LibraryImporter.sweep_incoming(), 0)
	assert_eq(LibraryImporter.last_sweep_skipped, 1)
	_survives()


# ---- ids and names ----


func test_remove_rejects_hostile_ids() -> void:
	_folder(LIBS + "/victim", true)
	var ids := [
		"..", ".", "", "a/b", "a\\b", "../libs/victim", "victim/..", "VICTIM", "core", ".incoming",
		".received", "victim ", "vi ctim", "C:", "~", "x".repeat(40)
	]
	for id in ids:
		assert_false(LibraryInstall.remove(id)["ok"], "'%s'" % id)
	assert_true(_exists(LIBS + "/victim/sub"))
	_survives()
	assert_true(LibraryInstall.remove("victim")["ok"])
	assert_false(_exists(LIBS + "/victim"))


func test_remove_needs_the_marker_and_the_scan_migrates_installed_libraries() -> void:
	World.write_alien(LIBS + "/alienworld")
	_write(LIBS + "/notes/readme.txt", "mine")
	var refused := LibraryInstall.remove("alienworld")
	assert_false(refused["ok"], "installed before the marker existed")
	assert_true("by hand" in String(refused["error"]), str(refused))
	assert_true(_exists(LIBS + "/alienworld"))
	LibraryRegistry.refresh()
	assert_true(SafeDelete.is_owned(LIBS + "/alienworld"), "the scan adopted it")
	assert_false(SafeDelete.is_owned(LIBS + "/notes"), "not a library: never adopted")
	assert_false(LibraryInstall.remove("notes")["ok"])
	assert_true(FileAccess.file_exists(LIBS + "/notes/readme.txt"))
	assert_true(LibraryInstall.remove("alienworld")["ok"])
	assert_false(_exists(LIBS + "/alienworld"))
	_survives()


func test_the_marker_is_not_part_of_a_library() -> void:
	World.write_alien(LIBS + "/alienworld")
	LibraryRegistry.refresh()
	assert_true(SafeDelete.is_owned(LIBS + "/alienworld"))
	var with_marker := _entry("alienworld")
	DirAccess.remove_absolute(LIBS + "/alienworld/" + SafeDelete.MARKER)
	LibraryRegistry.clear()
	LibraryRegistry.user_root = LIBS
	var scanned := LibraryRegistry.list()
	var without_marker := {}
	for item in scanned:
		if item["id"] == "alienworld":
			without_marker = item
	# The scan adopts again; the hash and size must be what they were with or without the file.
	assert_eq(with_marker["hash"], without_marker["hash"])
	assert_eq(with_marker["bytes"], without_marker["bytes"])


func _entry(id: String) -> Dictionary:
	for item in LibraryRegistry.list():
		if item["id"] == id:
			return item
	return {}


func test_an_archive_cannot_forge_a_marker_or_aim_at_the_quarantine() -> void:
	World.write_alien(SOURCE)
	var entries := Zip.entries_of(SOURCE, "")
	var forged := entries.duplicate()
	forged.append({"name": SafeDelete.MARKER, "data": "forged"})
	forged.append({"name": "assets/" + SafeDelete.MARKER, "data": "forged"})
	forged.append({"name": ".incoming/note.txt", "data": "x"})
	Zip.write(ROOT + "/forged.ttlib", forged)
	var plan := LibraryImporter.inspect(ROOT + "/forged.ttlib")
	assert_true(plan["ok"], str(plan.get("errors", [])))
	assert_true(plan["ignored"].has(SafeDelete.MARKER), "the forged marker is dropped as junk")
	var staged := LibraryImporter.stage(plan)
	assert_true(staged["ok"], str(staged))
	var folder := String(staged["folder"])
	assert_true(LibraryImporter.is_quarantined(folder))
	var text := FileAccess.get_file_as_string(folder + "/" + SafeDelete.MARKER)
	assert_true("tt-sim" in text, "the marker is the game's own: " + text)
	assert_false(FileAccess.file_exists(folder + "/assets/" + SafeDelete.MARKER))
	assert_true(LibraryImporter.discard(folder))
	assert_false(_exists(folder))
	_survives()


func test_a_staged_folder_is_owned_and_swept_but_a_stranger_is_not() -> void:
	World.write_alien(SOURCE)
	var staged := LibraryImporter.stage(LibraryImporter.inspect(SOURCE))
	assert_true(staged["ok"], str(staged))
	assert_true(SafeDelete.is_owned(String(staged["folder"])))
	# A folder someone else put in the quarantine has no marker and is reported, not deleted.
	_folder(LIBS + "/.incoming/stranger", false)
	assert_eq(LibraryImporter.sweep_incoming(String(staged["folder"])), 0, "the staged one is kept")
	assert_eq(LibraryImporter.last_sweep_skipped, 1)
	assert_true(_exists(LIBS + "/.incoming/stranger/sub"))
	assert_eq(LibraryImporter.sweep_incoming(), 1)
	assert_false(_exists(String(staged["folder"])))
	assert_true(_exists(LIBS + "/.incoming/stranger/sub"))
	_survives()


func test_install_replace_needs_an_owned_copy() -> void:
	World.write_alien(SOURCE)
	var staged := LibraryImporter.stage(LibraryImporter.inspect(SOURCE))
	assert_true(staged["ok"])
	var card := {"can_install": true, "id": "alienworld", "folder": staged["folder"]}
	_folder(LIBS + "/alienworld", false)
	var refused := LibraryInstall.install(card, true)
	assert_false(refused["ok"], str(refused))
	assert_true(_exists(LIBS + "/alienworld/sub"), "the stranger was not set aside")
	SafeDelete.mark(LIBS + "/alienworld", "test", LIBS)
	var done := LibraryInstall.install(card, true)
	assert_true(done["ok"], str(done))
	assert_true(done["replaced"])
	assert_true(SafeDelete.is_owned(LIBS + "/alienworld"), "the staged marker came along")
	assert_eq(DirAccess.get_directories_at(LIBS + "/.incoming").size(), 0, "no aside left")
	_survives()


# ---- the received cache ----


func test_the_received_store_is_marked_and_stays_inside() -> void:
	var files := {"library.json": "{}".to_utf8_buffer(), "a/b.json": "{}".to_utf8_buffer()}
	assert_eq(LibraryReceivedStore.write_library(RECEIVED, "hostworld", files, 1, {}), "")
	assert_true(SafeDelete.is_owned(RECEIVED + "/hostworld"))
	assert_false(_exists(RECEIVED + "/.staging-hostworld"))
	for id in ["..", ".", "", "a/b", "../canary", "Core", "x".repeat(40)]:
		assert_ne(LibraryReceivedStore.write_library(RECEIVED, id, files, 1, {}), "", id)
		assert_false(LibraryReceivedStore.remove(id, RECEIVED), id)
	var hostile := {"../../escape.json": "x".to_utf8_buffer()}
	assert_ne(LibraryReceivedStore.write_library(RECEIVED, "hostworld", hostile, 1, {}), "")
	var marker_name := {SafeDelete.MARKER: "x".to_utf8_buffer()}
	assert_ne(LibraryReceivedStore.write_library(RECEIVED, "hostworld", marker_name, 1, {}), "")
	assert_false(FileAccess.file_exists(ROOT + "/escape.json"))
	assert_true(LibraryReceivedStore.remove("hostworld", RECEIVED))
	assert_false(_exists(RECEIVED + "/hostworld"))
	_survives()


func test_received_sweeps_leave_what_the_game_did_not_make() -> void:
	_folder(RECEIVED + "/stranger", false, RECEIVED)
	_folder(RECEIVED + "/recorded", false, RECEIVED)
	# A folder from before the marker existed has its record beside it: that proves it is ours.
	_write(
		RECEIVED + "/recorded" + LibraryReceivedStore.MARKER_SUFFIX,
		'{"id": "recorded", "bytes": 1, "last_used": 1}'
	)
	assert_eq(LibraryReceivedStore.sweep_leftovers(RECEIVED), ["recorded"])
	assert_false(_exists(RECEIVED + "/recorded"))
	assert_true(_exists(RECEIVED + "/stranger/sub"), "no marker, no record: left alone")
	for bad in UNSAFE_ROOTS:
		if bad == "":
			continue  # "" is the default received folder
		assert_eq(LibraryReceivedStore.sweep_leftovers(bad), [], bad)
		assert_false(LibraryReceivedStore.remove("stranger", bad), bad)
	_survives()


func test_promote_stays_inside_the_user_folders() -> void:
	var files := {"library.json": "{}".to_utf8_buffer()}
	assert_eq(LibraryReceivedStore.write_library(RECEIVED, "hostworld", files, 1, {}), "")
	for bad in UNSAFE_ROOTS:
		if bad == "":
			continue  # "" is the default folder
		assert_false(LibraryReceivedStore.promote("hostworld", Callable(), bad, RECEIVED)["ok"])
		assert_false(LibraryReceivedStore.promote("hostworld", Callable(), LIBS, bad)["ok"])
	assert_true(_exists(RECEIVED + "/hostworld"))
	assert_true(LibraryReceivedStore.promote("hostworld", Callable(), LIBS, RECEIVED)["ok"])
	assert_true(SafeDelete.is_owned(LIBS + "/hostworld"))
	_survives()


# ---- the surface cache ----


func test_cache_folders_are_marked_and_only_theirs_go() -> void:
	var image := Image.create(16, 16, true, Image.FORMAT_RGBA8)
	var path := SurfaceCache.path_for("alienworld", "abcd", "grass", "albedo")
	assert_true(SurfaceCache.write(path, image))
	assert_true(SafeDelete.is_owned(CACHE + "/alienworld"))
	assert_true(SurfaceCache.write(path, image), "a rewrite replaces the file")
	# A cache from before the marker: only .ttimg files, adopted. A folder holding anything else
	# is refused.
	_write(CACHE + "/oldworld/h1/x.ttimg", "x")
	_write(CACHE + "/mixed/h1/x.ttimg", "x")
	_write(CACHE + "/mixed/h1/precious.txt", "mine")
	assert_true(SurfaceCache.remove_library("oldworld"))
	assert_false(_exists(CACHE + "/oldworld"))
	assert_false(SurfaceCache.remove_library("mixed"))
	assert_true(FileAccess.file_exists(CACHE + "/mixed/h1/precious.txt"))
	for id in ["..", ".", "", "a/b", "../canary"]:
		assert_false(SurfaceCache.remove_library(id), "'%s'" % id)
	assert_true(SurfaceCache.remove_library("alienworld"))
	assert_false(_exists(CACHE + "/alienworld"))
	assert_true(SurfaceCache.remove_library("nothing_here"), "nothing to remove is fine")
	_survives()


# ---- saved maps ----


func test_a_level_delete_cannot_reach_outside_the_levels_folder() -> void:
	LevelManager.levels_dir = ROOT + "/levels/"
	_write(ROOT + "/levels/mine/level.json", "{}")
	for bad in UNSAFE_ROOTS:
		assert_false(LevelManager.delete_level(bad), bad)
		assert_false(LevelManager.delete_level_folder(bad), bad)
	assert_false(LevelManager.delete_level(CANARY + "/"))
	assert_false(LevelManager.delete_level(ROOT + "/levels/"), "the levels folder itself")
	assert_false(LevelManager.delete_level(ROOT + "/levels/../canary/"))
	assert_true(FileAccess.file_exists(ROOT + "/levels/mine/level.json"))
	assert_true(LevelManager.delete_level(ROOT + "/levels/mine/"))
	assert_false(_exists(ROOT + "/levels/mine"))
	_survives()

