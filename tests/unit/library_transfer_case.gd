extends GutTest

## The shared setup of the library transfer tests (not a test file): a host world on disk (the
## two-library world of library_world.gd with `alienworld` grown by library_transfer_world.gd), a
## client with an empty user root, and the helpers both halves use. A test file extends this and
## names its own scratch folder with _root(), because the sharded test run puts files in different
## processes that share the user folder.

const Tw := preload("res://tests/unit/library_transfer_world.gd")
const World := preload("res://tests/unit/library_world.gd")

var _paths: Dictionary = {}
var _client_user: String = ""
var _saved_settings: String = ""
var _saved_official: String = ""
var _saved_user: String = ""


## The scratch folder of this test file.
func _root() -> String:
	return "user://test_library_transfer"


func before_all() -> void:
	_saved_settings = LibraryRegistry.settings_path
	_saved_official = LibraryRegistry.official_root
	_saved_user = LibraryRegistry.user_root


func after_all() -> void:
	LibraryRegistry.settings_path = _saved_settings
	LibraryRegistry.official_root = _saved_official
	LibraryRegistry.user_root = _saved_user
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	World.remove_tree(_root())


func before_each() -> void:
	World.remove_tree(_root())
	_paths = Tw.build(_root())
	_client_user = _root() + "/client_user"
	DirAccess.make_dir_recursive_absolute(_client_user)
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryReceivedStore._this_session.clear()
	LibraryRegistry.settings_path = _root() + "/settings.cfg"
	LibraryRegistry.official_root = _paths["official"]
	LibraryRegistry.user_root = _paths["user"]


# ---- helpers ----


func _host_served() -> Dictionary:
	LibraryRegistry.user_root = _paths["user"]
	LibraryRegistry.apply(_paths["base"])
	var served := LibraryRegistry.served()
	assert_true(served.has("alienworld"), "the host serves alienworld")
	return served


## Points the registry at the client's empty user root.
func _become_client() -> void:
	LibraryRegistry.user_root = _client_user
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryRegistry.official_root = _paths["official"]
	LibraryRegistry.apply(_paths["base"])


func _assets() -> Dictionary:
	return PaletteLibrary.get_palette(_paths["base"])["assets"]


func _view(ids: Array) -> Dictionary:
	var out := {}
	for id: String in ids:
		var info := LibraryRegistry.info(id, _paths["base"])
		if not info.is_empty():
			out[id] = info
	return out


func _request() -> Dictionary:
	_become_client()
	var doc := Tw.map_using_spire()
	return Tw.request_for(doc, _view(["core"]), _assets())


func _bundle_files(request: Dictionary, served: Dictionary) -> Dictionary:
	var bytes := LibraryTransfer.build_bundle(request, served)
	assert_false(bytes.is_empty(), "the bundle builds")
	var decoded := LibraryPartial.decode(bytes)
	assert_true(decoded["ok"], decoded["error"])
	return decoded["files"]


func _ctx(extra: Dictionary = {}) -> Dictionary:
	var ctx := {
		"library": "alienworld",
		"wanted_version": "0.3.1",
		"root": LibraryRegistry.received_root(),
		"official_ids": ["core"],
		"surfaces": PaletteLibrary.get_palette(_paths["base"])["surfaces"],
		"now": 1000,
	}
	ctx.merge(extra, true)
	return ctx


func _codes(made: Dictionary) -> Array:
	return (made["errors"] as Array).map(func(e: Dictionary) -> String: return e["code"])


func _received_root() -> String:
	return LibraryRegistry.received_root()


func _has_dir(path: String) -> bool:
	return DirAccess.dir_exists_absolute(path)
