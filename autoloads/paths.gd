class_name Paths

## Centralized path constants for the project.
## Accessible everywhere via the class_name (no autoload needed).
##
## Every per-user store (levels, settings, the asset cache and its index, user asset packs,
## avatars, ...) lives under one data root: "user://" in the shipped game. A process started
## with the user argument `--data-root=<name>` (after `--`) puts all of them under the
## disposable test root user://_test_roots/<name>/ instead, so the local multi-process
## scenarios in tests/net/ give each peer its own data and never read, evict or overwrite
## the real user's. Nothing in the shipped game passes it. Not moved: Godot's own log (the
## scenarios pass the engine's --log-file instead), and two files only an interactive
## session writes, the Level Editor's autosave (LevelEditorHistory) and the update
## installer's restart scripts.
##
## A GUT command-line run (godot --script res://addons/gut/gut_cmdln.gd) gets its own test
## root, user://_test_roots/gut_<process id>/, without passing anything: the command is fixed,
## and the stores must already point there when the autoloads load (AssetCacheManager reads
## and rewrites its index, UpdateManager consumes the update-success file, several classes
## copy a path as a static default), which is before GUT runs any hook. tests/gut_post_run.gd,
## named by every tests/.gutconfig*.json, deletes the root when the run ends. An explicit
## --data-root wins over it.

## The user argument that selects a test data root.
const DATA_ROOT_ARG: String = "--data-root="
const SHIPPED_DATA_ROOT: String = "user://"
## Parent of every test data root; a scenario deletes its own roots when it ends.
const TEST_ROOTS_DIR: String = "user://_test_roots/"
## The file name of GUT's command-line runner, the engine's `--script` of a GUT run.
const GUT_RUNNER_SCRIPT: String = "gut_cmdln.gd"
## Prefix of a GUT run's test root name; the process id follows, so runs that overlap (a
## subset beside the full run) never share or delete each other's files.
const GUT_ROOT_PREFIX: String = "gut_"

# Special pack ID for map streaming (used by AssetStreamer)
const LEVEL_MAPS_PACK_ID: String = "_level_maps"
# The map files of a level folder, and the streaming variant id that names each one. A
# level has a Blender-made map.glb, an authored map.ttmap, or both.
const LEVEL_MAP_NAME: String = "map.glb"
const LEVEL_MAP_DOCUMENT_NAME: String = "map.ttmap"
const LEVEL_MAP_VARIANT: String = "map"
const LEVEL_MAP_DOCUMENT_VARIANT: String = "ttmap"
# AssetStreamer / AssetCacheManager file type of a streamed map document (cached as .ttmap;
# a streamed map.glb uses the "model" type and is cached as .glb).
const LEVEL_MAP_DOCUMENT_FILE_TYPE: String = "map_document"

# Data files
const POKEMON_DATA_PATH: String = "res://data/pokemon.json"

# Asset directories
const ASSETS_DIR: String = "res://assets/"
const MODELS_DIR: String = "res://assets/models/"
const ICONS_DIR: String = "res://assets/icons/"
const MAPS_DIR: String = "res://assets/models/maps/"

# Scene directories
const SCENES_DIR: String = "res://scenes/"
const BOARD_TOKEN_DIR: String = "res://scenes/board_token/"

# The per-user stores, each under the data root (user:// in the shipped game). Static
# rather than const only so --data-root can move them when this class loads, and named like
# the constants they were; nothing assigns them afterwards (tests that call use_data_root()
# put the run's root back).
# gdlint: disable=class-variable-name
## The data root itself, ending in "/".
static var DATA_ROOT: String = ""
static var LEVELS_DIR: String = ""
static var SETTINGS_PATH: String = ""
## GraphicsWarmup's marker: the cache key of the last completed warm-up.
static var GRAPHICS_WARMUP_PATH: String = ""
static var PERF_LOG_DIR: String = ""
## AssetCacheManager's downloaded and streamed files, and the LRU index over them.
static var ASSET_CACHE_DIR: String = ""
static var ASSET_CACHE_INDEX_PATH: String = ""
## Installed asset packs (AssetManager, AssetDownloader).
static var USER_ASSETS_DIR: String = ""
## The avatar library (AvatarLibrary).
static var AVATARS_DIR: String = ""
## Downloaded game updates (UpdateManager).
static var UPDATES_DIR: String = ""
# gdlint: enable=class-variable-name


static func _static_init() -> void:
	var root := data_root_from_args(OS.get_cmdline_user_args())
	if root == SHIPPED_DATA_ROOT:
		var gut_root := gut_data_root(OS.get_cmdline_args(), OS.get_process_id())
		if gut_root != "":
			# A leftover of an earlier process with this id; no live process shares it.
			remove_test_data_root(gut_root)
			root = gut_root
	use_data_root(root)


## Point every per-user store at `root` (ending in "/"). Runs once when this class loads,
## with the root the command line picks; a test may call it to check the redirect and must
## call it again with the root it found (DATA_ROOT before the call). Classes that copied a
## path when they loaded (LevelManager.levels_dir, UIPreferences.settings_path,
## AuthoringAutosave.directory, AvatarLibrary.directory) keep the root they loaded with.
static func use_data_root(root: String) -> void:
	var stores := store_paths(root)
	DATA_ROOT = root
	LEVELS_DIR = stores.LEVELS_DIR
	SETTINGS_PATH = stores.SETTINGS_PATH
	GRAPHICS_WARMUP_PATH = stores.GRAPHICS_WARMUP_PATH
	PERF_LOG_DIR = stores.PERF_LOG_DIR
	ASSET_CACHE_DIR = stores.ASSET_CACHE_DIR
	ASSET_CACHE_INDEX_PATH = stores.ASSET_CACHE_INDEX_PATH
	USER_ASSETS_DIR = stores.USER_ASSETS_DIR
	AVATARS_DIR = stores.AVATARS_DIR
	UPDATES_DIR = stores.UPDATES_DIR


## Every per-user store's path under the data root `root`, keyed by the name of its static
## variable here (folders end in "/"). Pure; the net launcher reads it to check that a run
## left the shipped stores alone.
static func store_paths(root: String) -> Dictionary:
	return {
		"LEVELS_DIR": root + "levels/",
		"SETTINGS_PATH": root + "settings.cfg",
		"GRAPHICS_WARMUP_PATH": root + "graphics_warmup.cfg",
		"PERF_LOG_DIR": root + "perf_logs/",
		"ASSET_CACHE_DIR": root + "asset_cache/",
		"ASSET_CACHE_INDEX_PATH": root + "asset_cache_index.json",
		"USER_ASSETS_DIR": root + "user_assets/",
		"AVATARS_DIR": root + "avatars/",
		"UPDATES_DIR": root + "updates/",
	}


## The data root that the user arguments `args` select: SHIPPED_DATA_ROOT without a
## DATA_ROOT_ARG, else that argument's test root (test_data_root()).
static func data_root_from_args(args: PackedStringArray) -> String:
	for arg in args:
		if arg.begins_with(DATA_ROOT_ARG):
			return test_data_root(arg.substr(DATA_ROOT_ARG.length()))
	return SHIPPED_DATA_ROOT


## The test data root of a GUT command-line run: `engine_args` (OS.get_cmdline_args()) name
## GUT's runner as the script the engine runs, `process_id` is the run's. "" for any other
## process, the shipped game included.
static func gut_data_root(engine_args: PackedStringArray, process_id: int) -> String:
	for arg in engine_args:
		if arg.get_file() == GUT_RUNNER_SCRIPT:
			return test_data_root("%s%d" % [GUT_ROOT_PREFIX, process_id])
	return ""


## The test data root named `root_name`: TEST_ROOTS_DIR + the name + "/", keeping only
## letters, digits, "_" and "-" so a name can never climb out of TEST_ROOTS_DIR or land on
## the shipped root ("unnamed" when nothing is left).
static func test_data_root(root_name: String) -> String:
	var allowed := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
	var safe := ""
	for c in root_name:
		if c in allowed:
			safe += c
	return TEST_ROOTS_DIR + (safe if safe != "" else "unnamed") + "/"


## Delete the test data root `root` and everything in it, then TEST_ROOTS_DIR if that left
## it empty. Refuses anything but a root test_data_root() names, so it can never reach the
## real user's data. True when `root` is gone afterwards.
static func remove_test_data_root(root: String) -> bool:
	var root_name := root.trim_prefix(TEST_ROOTS_DIR).trim_suffix("/")
	if not root.begins_with(TEST_ROOTS_DIR) or test_data_root(root_name) != root:
		push_error("Paths: refusing to delete %s, not a test data root" % root)
		return false
	_remove_tree(root)
	var parent := DirAccess.open(TEST_ROOTS_DIR)
	if parent != null and parent.get_directories().is_empty() and parent.get_files().is_empty():
		DirAccess.remove_absolute(TEST_ROOTS_DIR)
	return not DirAccess.dir_exists_absolute(root)


## Delete a folder (ending in "/") and everything below it.
static func _remove_tree(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	dir.include_hidden = true
	for sub in dir.get_directories():
		_remove_tree(folder + sub + "/")
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(folder)


## Get the folder path for a level (where level.json and map.glb are stored)
static func get_level_folder(level_name: String) -> String:
	return LEVELS_DIR + level_name + "/"


## Get the map GLB path within a level folder
static func get_level_map_path(level_name: String) -> String:
	return get_level_folder(level_name) + LEVEL_MAP_NAME


## Get the authored map document (map.ttmap) path within a level folder
static func get_level_map_document_path(level_name: String) -> String:
	return get_level_folder(level_name) + LEVEL_MAP_DOCUMENT_NAME


## The file a streaming variant id names in a level folder: the whitelist the host serves
## level map requests through. "" for any variant other than the two map files, so a
## client-chosen variant can never name another file.
static func get_level_map_file_for_variant(level_name: String, variant_id: String) -> String:
	match variant_id:
		LEVEL_MAP_VARIANT:
			return get_level_map_path(level_name)
		LEVEL_MAP_DOCUMENT_VARIANT:
			return get_level_map_document_path(level_name)
	return ""


## The streaming file type of a level map variant ("model" for the GLB, the map-document
## type for the ttmap), or "" for an unknown variant.
static func get_level_map_file_type(variant_id: String) -> String:
	match variant_id:
		LEVEL_MAP_VARIANT:
			return "model"
		LEVEL_MAP_DOCUMENT_VARIANT:
			return LEVEL_MAP_DOCUMENT_FILE_TYPE
	return ""


## Get the level.json path within a level folder
static func get_level_json_path(level_name: String) -> String:
	return get_level_folder(level_name) + "level.json"


## Sanitize a level name for use as a folder name
static func sanitize_level_name(level_name: String) -> String:
	var sanitized = level_name.strip_edges().to_lower()
	sanitized = sanitized.replace(" ", "_")

	# Remove invalid characters
	var valid_chars = "abcdefghijklmnopqrstuvwxyz0123456789_-"
	var result = ""
	for c in sanitized:
		if c in valid_chars:
			result += c

	if result == "":
		result = "level_" + str(Time.get_unix_time_from_system())

	return result
