extends GutTest

## The session file and Resume (SessionFile, SessionKeeper): a hosted session is written whole
## (the shelf, each map's kept state with its look and op log, the party and its grants by
## session id) and read back equal; a write never leaves a partial file where a good one was;
## Resume restores a map whose files are as they were, keeps the tokens and look but drops the
## op log of a map that changed, and keeps a map whose folder is gone on the shelf as missing;
## the op log is handed to the table when a resumed map is set out.
## tests/net/enet_session_file.gd resumes a session in a fresh host process between peers.

const KEY_A := "_session_file_a"
const KEY_B := "_session_file_b"
const KEY_C := "_session_file_c"
const PLAYER := "enet-client"
const HERO_ID := "hero-session-file"

var _controller: LevelPlayController
var _mover: TableMover
var _keeper: SessionKeeper
var _ops: Array[PackedByteArray] = [PackedByteArray([1, 2, 3]), PackedByteArray([4, 5])]


func before_each() -> void:
	NetworkManager.session.reset()
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	_controller = autofree(LevelPlayController.new())
	_mover = TableMover.new()
	add_child_autofree(_mover)
	_mover.setup(_controller)
	_keeper = _mover.keeper
	# Hosting began: the keeper gives the session an id.
	_keeper._on_connection_state_changed(
		NetworkManager.ConnectionState.CONNECTING, NetworkManager.ConnectionState.HOSTING
	)


func after_each() -> void:
	SessionFile.remove(_keeper.session_id())
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	NetworkManager.session.reset()
	for key in [KEY_A, KEY_B, KEY_C]:
		_remove_folder(key)


## A map in the library: an authored flat map (its document hashed on the shelf) with two
## placements, put on the shelf.
func _library_map(key: String, height := 0.0) -> LevelData:
	var doc := MapDocument.create_flat(Vector2i(4, 4), "grass", "test", 7)
	doc.heights[0] = height
	DirAccess.make_dir_recursive_absolute(LevelManager.folder_path(key))
	var document_path := LevelManager.map_document_path(key)
	assert_eq(MapDocumentIO.write(doc, document_path), OK, "the map document is written")
	MapFileHash.invalidate(document_path)
	var level := LevelData.new()
	level.level_name = key.capitalize()
	level.level_folder = key
	level.map_document = Paths.LEVEL_MAP_DOCUMENT_NAME
	for token_name in ["Goblin", "Ogre"]:
		var placement := TokenPlacement.new()
		placement.token_name = token_name
		placement.position = Vector3(1, 0, 2)
		level.add_token_placement(placement)
	assert_ne(LevelManager.save_level_folder(level, key), "", "the map is in the library")
	NetworkManager.session.shelve(level.to_dict())
	return level


## What the session did to `level`: a token moved, a dimmer light, and `ops` as its log.
func _kept(level: LevelData, ops: Array[PackedByteArray]) -> Dictionary:
	var table := LevelData.from_dict(level.to_dict())
	table.token_placements[1].position = Vector3(9, 0, 9)
	table.light_intensity_scale = 0.5
	return TableStates.capture(table, {}, ops)


## A party member: client's avatar, granted to it by session id.
func _party() -> void:
	var hero := TokenState.new()
	hero.network_id = HERO_ID
	hero.token_name = "Hero"
	hero.avatar_recipe = AvatarRecipe.normalized({"format": 1})
	hero.position = Vector3(3, 0, 4)
	NetworkManager.session.party.restore(
		[{"state": hero.to_dict(), "owners": [PLAYER]}], {PLAYER: [HERO_ID]}
	)
	NetworkManager.session._add_player(PLAYER, "Client", 2)


## The session file as a fresh host would read it.
func _read() -> Dictionary:
	return SessionFile.sanitize_session(
		SessionFile.read_json(SessionFile.session_path(_keeper.session_id()))
	)


## What a new host process has before it resumes: no session, no kept states.
func _forget_session() -> void:
	NetworkManager.session.reset()
	_mover.states.clear()


func _remove_folder(folder: String) -> void:
	var path := LevelManager.folder_path(folder)
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path.trim_suffix("/"))


# =============================================================================
# ROUND TRIP
# =============================================================================


## A map's kept state survives JSON: its placements, its look and its op log.
func test_a_kept_state_round_trips_as_plain_data() -> void:
	var level := _library_map(KEY_A)
	var entry := _kept(level, _ops)
	var text := SessionFile.to_text(TableStates.to_data(entry))
	var back := TableStates.from_data(JSON.parse_string(text))
	assert_eq(TableStates.op_log_of(back), _ops)
	var template := LevelManager.load_level_folder(KEY_A, false)
	var restored := LevelManager.load_level_folder(KEY_A, false)
	TableStates.overlay(template, entry)
	TableStates.overlay(restored, back)
	var look := TableStates.look_of(template)
	for key: String in look:
		assert_eq(TableStates.look_of(restored)[key], look[key], key)
	assert_almost_eq(restored.light_intensity_scale, 0.5, 0.001)
	assert_eq(restored.token_placements.size(), 2)
	assert_eq(restored.token_placements[1].position, Vector3(9, 0, 9))
	assert_eq(
		restored.token_placements[1].placement_id, template.token_placements[1].placement_id
	)


## save_now() writes the session whole, and reading it gives back what was written: the shelf
## with its hashes, the players by session id, the party and its grants, a table file per
## kept map. A map whose state goes loses its file on the next save.
func test_the_session_is_written_and_read_back_equal() -> void:
	var level_a := _library_map(KEY_A)
	var level_b := _library_map(KEY_B)
	_mover.states.store(KEY_A, _kept(level_a, _ops))
	_mover.states.store(KEY_B, _kept(level_b, []))
	_party()
	assert_true(_keeper.save_now(), "the session is written")
	var data := _read()
	assert_eq(data.id, _keeper.session_id())
	assert_eq(data.name, KEY_A.capitalize(), "named after its first map")
	var shelf := NetworkManager.session.get_shelf()
	assert_eq(
		(data.shelf as Array).map(func(r: Dictionary) -> String: return r.folder), [KEY_A, KEY_B]
	)
	assert_eq(data.shelf[0].hashes, shelf[0].hashes)
	assert_false((data.shelf[0].hashes as Dictionary).is_empty(), "the document is hashed")
	assert_eq(data.players[PLAYER], {"name": "Client", "role": SessionFile.ROLE_PLAYER})
	assert_eq(data.grants, {PLAYER: [HERO_ID]})
	assert_eq(data.party.size(), 1)
	assert_eq(data.party[0].owners, [PLAYER])
	assert_eq(TokenState.from_dict(data.party[0].state).position, Vector3(3, 0, 4))
	assert_eq(data.tables.keys(), [KEY_A, KEY_B])
	var table_a := SessionFile.sanitize_table(
		SessionFile.read_json(SessionFile.table_path(data.id, data.tables[KEY_A]))
	)
	assert_eq(table_a.key, KEY_A)
	assert_eq(table_a.base.hashes, shelf[0].hashes)
	assert_eq(TableStates.op_log_of(table_a.entry), _ops)
	_mover.states.erase(KEY_B)
	assert_true(_keeper.save_now())
	assert_eq(_read().tables.keys(), [KEY_A])
	assert_false(FileAccess.file_exists(SessionFile.table_path(data.id, KEY_B)), "B's file went")


## Nothing is written before the shelf has a map, and an id is a clean name.
func test_an_empty_session_is_not_written() -> void:
	assert_false(_keeper.save_now())
	assert_false(FileAccess.file_exists(SessionFile.session_path(_keeper.session_id())))
	assert_eq(SessionFile.clean_id(_keeper.session_id()), _keeper.session_id())
	assert_eq(SessionFile.clean_id("../levels"), "")
	assert_eq(SessionFile.table_stem(KEY_A), KEY_A)
	assert_true(SessionFile.table_stem("res://maps/a.glb").begins_with("map_"))


# =============================================================================
# ATOMIC WRITE
# =============================================================================


## A write that cannot finish leaves the good file as it was, and a partial file left by a
## process that died mid-write never replaces it either.
func test_a_partial_file_never_replaces_a_good_one() -> void:
	var path := SessionFile.folder_of(_keeper.session_id()) + "atomic.json"
	assert_eq(SessionFile.write_json(path, {"good": 1}), OK)
	# The temporary file cannot be opened: the write fails, the good file stays.
	DirAccess.make_dir_recursive_absolute(path + SessionFile.TMP_SUFFIX)
	assert_ne(SessionFile.write_json(path, {"good": 2}), OK)
	assert_eq(SessionFile.read_json(path), {"good": 1.0})
	DirAccess.remove_absolute(path + SessionFile.TMP_SUFFIX)
	# A process died mid-write: half a file under the temporary name.
	var partial := FileAccess.open(path + SessionFile.TMP_SUFFIX, FileAccess.WRITE)
	partial.store_string('{"good": 3, "tru')
	partial.close()
	assert_eq(SessionFile.read_json(path), {"good": 1.0}, "the good file is read")
	assert_eq(SessionFile.write_json(path, {"good": 4}), OK, "the next write goes through")
	assert_eq(SessionFile.read_json(path), {"good": 4.0})
	assert_false(FileAccess.file_exists(path + SessionFile.TMP_SUFFIX))


# =============================================================================
# RESUME
# =============================================================================


## Resume restores a map whose files are as the session left them (op log and document), keeps
## the tokens and look of a map that changed since but drops its op log, and keeps a map
## whose folder is gone on the shelf, marked missing, with its state as it was.
func test_resume_restores_same_changed_and_missing_maps() -> void:
	var level_a := _library_map(KEY_A)
	var level_b := _library_map(KEY_B)
	var level_c := _library_map(KEY_C)
	var with_document := _kept(level_a, _ops)
	with_document["document"] = MapDocument.create_flat(Vector2i(4, 4), "grass", "test", 7)
	_mover.states.store(KEY_A, with_document)
	_mover.states.store(KEY_B, _kept(level_b, _ops))
	_mover.states.store(KEY_C, _kept(level_c, _ops))
	assert_true(_keeper.save_now())
	var id := _keeper.session_id()
	_library_map(KEY_B, 3.0)
	_remove_folder(KEY_C)
	_forget_session()
	var notes := _keeper.restore(_read())
	assert_eq(_keeper.session_id(), id, "kept under its own id")
	assert_eq(notes, {KEY_B: SessionFile.CHANGED, KEY_C: SessionFile.MISSING})
	var shelf := NetworkManager.session.get_shelf()
	assert_eq(shelf.map(func(r: Dictionary) -> String: return r.folder), [KEY_A, KEY_B, KEY_C])
	assert_true((shelf[2].hashes as Dictionary).is_empty(), "nothing to fetch for C")
	var a := _mover.states.entry_for(KEY_A)
	assert_eq(TableStates.op_log_of(a), _ops)
	assert_not_null(a.get("document"), "A's document came back with its log")
	var b := _mover.states.entry_for(KEY_B)
	assert_true(TableStates.op_log_of(b).is_empty(), "B's edits were made on its old terrain")
	assert_eq((b.placements as Array)[1].position, {"x": 9.0, "y": 0.0, "z": 9.0})
	assert_almost_eq((b.look as LevelVisualState).light_intensity_scale, 0.5, 0.001)
	assert_eq(TableStates.op_log_of(_mover.states.entry_for(KEY_C)), _ops)
	# The next save keeps C's base though its folder is gone.
	assert_true(_keeper.save_now())
	var table_c := SessionFile.sanitize_table(
		SessionFile.read_json(SessionFile.table_path(id, KEY_C))
	)
	assert_false((table_c.base.hashes as Dictionary).is_empty())
	assert_eq(_read().shelf[2].hashes, table_c.base.hashes)


## The party and its grants come back by session id, and the players as away until they
## rejoin; the GM's own entry stays this host's.
func test_resume_restores_the_party_and_grants_by_session_id() -> void:
	_library_map(KEY_A)
	_party()
	assert_true(_keeper.save_now())
	var party := NetworkManager.session.party
	_forget_session()
	assert_true(party.is_empty())
	_keeper.restore(_read())
	assert_eq(party.get_grants(), {PLAYER: [HERO_ID]})
	var members := party.get_members()
	assert_eq(members.size(), 1)
	assert_eq(members[0].owners, [PLAYER])
	assert_eq(str(members[0].state.network_id), HERO_ID)
	assert_false((members[0].state.avatar_recipe as Dictionary).is_empty())
	assert_eq(NetworkManager.session.get_players()[PLAYER], {"name": "Client", "peer_id": 0})


## A resumed map hands its op log to the table when it is set out, with its tokens laid
## over the template.
func test_the_op_log_is_replayed_on_set_out_after_resume() -> void:
	_mover.states.store(KEY_A, _kept(_library_map(KEY_A), _ops))
	assert_true(_keeper.save_now())
	_forget_session()
	_keeper.restore(_read())
	var chosen: Array[LevelData] = []
	_mover.level_chosen.connect(func(level: LevelData) -> void: chosen.append(level))
	_mover.set_out(KEY_A)
	assert_eq(chosen.size(), 1)
	assert_eq(_controller.replay_log, _ops)
	assert_eq(chosen[0].token_placements[1].position, Vector3(9, 0, 9))


## Resume of a session that is not there says so and starts nothing.
func test_resume_of_a_missing_session_starts_nothing() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	var asked := []
	_keeper.host_requested.connect(func() -> void: asked.append(true))
	assert_false(_keeper.resume("no-such-session"))
	assert_true(asked.is_empty())
	assert_false(_keeper.resume("../levels"))
