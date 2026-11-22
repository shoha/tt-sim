extends GutTest
## The terraforming core in the game (TerraSession, card terraform-p1-session). The switch-off
## contract: a load through MapSourceLoader makes no session and no TerraDerive, and the built map's
## fingerprint is that of the same map without its section. Switch on: the session's digests equal
## a fresh full derive, survive a save and a reload through the real load path (the record is
## written and matches), and edits (every op, some while a derive runs) land equal to a fresh
## derive of the edited document. Closing a map mid-derive never waits. A refused terrain section
## is kept and saved back untouched.

const DIR := "user://_terraform-p1-session_/"
const PATH := DIR + "map.ttmap"
## A small map (60 ft): the corpus scales to any extent, and the load stays quick.
const CELLS := Vector2i(12, 12)
## Frames a derive may take to land before a test gives up.
const MAX_FRAMES := 600


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_each() -> void:
	TerraCore.switch_override = null
	for file_name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file_name)
	DirAccess.remove_absolute(DIR.trim_suffix("/"))


## A flat map with the corpus's terrain (null terrain when `with_terra` is false).
func _map(with_terra := true) -> MapDocument:
	var doc := MapDocument.create_flat(CELLS, "grass", "v", 3)
	if with_terra:
		var c := TerraCorpus.build(CELLS)
		doc.terra = c.terra
	return doc


func _session(root: Node) -> TerraSession:
	return root.get_node_or_null("TerraSession") as TerraSession


## Waits (frames, the session in the tree) until `s` is ready; false when it never is.
func _settle(s: TerraSession) -> bool:
	for i in MAX_FRAMES:
		if s.is_ready():
			return true
		await get_tree().process_frame
	return s.is_ready()


## The digests of a fresh full derive of `doc`'s terrain.
func _fresh(doc: MapDocument) -> Dictionary:
	return TerraCache.digests_of(TerraCache.derive_for(doc.terra as TerraDoc, doc))


## A hill primitive's floats at world `p`, `height` m tall (radius 6 m, shape 2).
func _hill(p: Vector2, height: float) -> PackedFloat32Array:
	return PackedFloat32Array([p.x, p.y, height, 6.0, 2.0])


func _fingerprint_without_terra(root: Node, doc: MapDocument) -> Dictionary:
	var out := MapFingerprint.of(root, doc)
	out.erase("terra")
	return out


# --- switch off -------------------------------------------------------------------------


func test_switch_off_makes_no_session_and_no_derive_and_the_same_map() -> void:
	TerraCore.switch_override = false
	var doc := _map()
	var made := TerraCore.derives_made
	var root := await MapSourceLoader.new(get_tree()).build_async("", doc)
	assert_null(_session(root), "no session")
	assert_eq(TerraCore.derives_made, made, "no TerraDerive")
	var stripped := _map(false)
	var plain := await MapSourceLoader.new(get_tree()).build_async("", stripped)
	assert_eq(MapFingerprint.of(plain, stripped)["terra"], "", "the stripped map has no terra key")
	assert_ne(MapFingerprint.of(root, doc)["terra"], "", "the map with a section has one")
	assert_eq(
		_fingerprint_without_terra(root, doc),
		_fingerprint_without_terra(plain, stripped),
		"every other key equals the stripped map's"
	)
	root.free()
	plain.free()


func test_switch_on_without_a_section_makes_no_session() -> void:
	TerraCore.switch_override = true
	var made := TerraCore.derives_made
	var root := await MapSourceLoader.new(get_tree()).build_async("", _map(false))
	assert_null(_session(root))
	assert_eq(TerraCore.derives_made, made)
	root.free()


func test_the_switch_reads_the_project_setting() -> void:
	TerraCore.switch_override = null
	# The switch-on gate run (tests/gut_pre_run_terra_on.gd) sets the setting in memory and marks
	# the run: there the switch reads on; in every other run the project's default is off.
	var on_run := Engine.has_meta(&"gut_terra_on")
	var setting := bool(ProjectSettings.get_setting(TerraCore.SWITCH_SETTING, false))
	assert_eq(setting, on_run, "default off, or on for the switch-on run")
	assert_eq(TerraCore.enabled(), on_run)
	TerraCore.switch_override = true
	assert_true(TerraCore.enabled())


# --- switch on --------------------------------------------------------------------------


func test_digests_equal_a_fresh_derive_and_survive_save_and_reload() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	TerraCore.switch_override = true
	var doc := _map()
	var root := await MapSourceLoader.new(get_tree()).build_async("", doc)
	var s := _session(root)
	assert_not_null(s, "a session on a map with a section")
	if s == null:
		root.free()
		return
	add_child(root)
	assert_true(await _settle(s), "the attach derive lands")
	assert_eq(s.check["status"], TerraCache.NONE, "a new map has no record")
	var digests := s.digests()
	assert_eq(digests, _fresh(doc), "the session's digests equal a fresh derive_full")
	assert_false(is_nan(s.height_at(0.0, 0.0)), "queries answer")
	assert_eq(MapDocumentIO.write(doc, PATH), OK)
	assert_false((doc.terra as TerraDoc).derived.is_empty(), "the save refreshed the record")
	root.free()
	var loader := MapSourceLoader.new(get_tree())
	var loaded := await loader.load_async("", PATH)
	assert_not_null(loaded, "the saved map loads through the real load path")
	var again := _session(loaded)
	assert_not_null(again)
	if again == null:
		loaded.free()
		return
	add_child(loaded)
	assert_true(await _settle(again))
	assert_eq(again.check["status"], TerraCache.MATCH, "the saved record matches the reload")
	assert_eq(again.digests(), digests, "the digests survive the save and reload")
	assert_eq((loader.document.terra as TerraDoc).derived["digests"], digests)
	loaded.free()


func test_edits_land_equal_to_a_fresh_derive() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	TerraCore.switch_override = true
	var doc := _map()
	var c := TerraCorpus.build(CELLS)
	var root := await MapSourceLoader.new(get_tree()).build_async("", doc)
	var s := _session(root)
	add_child(root)
	# One edit while the attach derive runs (queued), the rest once it settled, some back to back
	# (each while the previous derive_async runs).
	var p := c.at(20, 30)
	var hill := s.apply({"op": "add", "kind": TerraCore.HILL, "data": _hill(p, 2.0)})
	assert_gt(hill, 0, "add returns the new id")
	assert_true(await _settle(s))
	var terrace := s.apply(
		{"op": "add", "kind": TerraCorpus.TERRACE, "data": c.dabs(TerraCorpus.terrace_dabs(4, 0))}
	)
	var more := c.dabs(TerraCorpus.terrace_dabs(4, 4))
	assert_eq(s.apply({"op": "append", "id": terrace, "data": more}), terrace)
	var q := c.at(24, 30)
	assert_eq(s.apply({"op": "replace", "id": hill, "data": _hill(q, 3.0)}), hill)
	assert_eq(s.apply({"op": "mute", "id": 3}), 3)
	assert_true(await _settle(s))
	assert_eq(s.digests(), _fresh(doc), "after add, append, replace and mute")
	assert_eq(s.apply({"op": "unmute", "id": 3}), 3)
	assert_eq(s.apply({"op": "move", "id": hill, "to": 1}), hill)
	assert_eq(s.apply({"op": "remove", "id": 4}), 4)
	assert_true(await _settle(s))
	assert_eq(s.digests(), _fresh(doc), "after unmute, move and remove")
	assert_eq(s.apply({"op": "remove", "id": 9999}), -1, "no such primitive")
	var one := PackedFloat32Array([1.0])
	assert_eq(s.apply({"op": "add", "kind": 999, "data": one}), -1, "an unknown kind")
	assert_eq(s.apply({"op": "bogus"}), -1)
	assert_true(s.capture_for_save())
	var terra := doc.terra as TerraDoc
	assert_true(TerraCache.key_matches(terra.derived, terra, doc), "the record follows the edits")
	root.free()


func test_closing_mid_derive_never_waits() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var doc := _map()
	var s := TerraSession.new()
	var before := TerraSession.parked_count()
	assert_true(s.attach(doc))
	s.free()
	assert_eq(TerraSession.parked_count(), before + 1, "the attach task is parked, not waited for")
	assert_false((doc.terra as TerraDoc).before_save.is_valid(), "the save hook is let go")
	s = TerraSession.new()
	add_child(s)
	assert_true(s.attach(doc))
	assert_true(await _settle(s))
	var p := TerraCorpus.build(CELLS).at(30, 30)
	s.apply({"op": "add", "kind": TerraCore.HILL, "data": _hill(p, 2.0)})
	assert_false(s.is_ready(), "a derive runs")
	s.free()
	for i in MAX_FRAMES:
		if TerraSession.parked_count() == before:
			break
		await get_tree().process_frame
	assert_eq(TerraSession.parked_count(), before, "every parked task and derive let go")


# --- the refused-section guard ----------------------------------------------------------


func test_a_refused_section_is_kept_and_saved_back_untouched() -> void:
	var doc := _map()
	var entries: Dictionary = MapDocumentIO.serialize(doc)["entries"]
	var bytes: PackedByteArray = entries[MapTerrainIO.ENTRY]
	bytes.encode_u16(4, MapTerrainIO.VERSION + 1)
	entries[MapTerrainIO.ENTRY] = bytes
	var read := MapDocumentIO.parse(entries)
	var back: MapDocument = read["document"]
	assert_null(back.terra, "refused")
	assert_string_contains(" ".join(read["warnings"]), MapTerrainIO.NEWER)
	assert_eq(back.terra_kept.keys(), [MapTerrainIO.ENTRY], "kept as read")
	var out: Dictionary = MapDocumentIO.serialize(back)
	assert_eq(out["error"], "")
	var saved: Dictionary = out["entries"]
	assert_eq(saved[MapTerrainIO.ENTRY], bytes, "written back untouched")
	var text: String = saved[MapDocumentIO.MANIFEST_ENTRY].get_string_from_utf8()
	var manifest: Dictionary = JSON.parse_string(text)
	assert_eq(int(manifest["format"]), MapDocument.FORMAT_TERRAIN, "still format 6")
	var copy := MapDocumentSnapshot.copy_document(back)
	assert_eq(copy.terra_kept, back.terra_kept, "the snapshot carries it")
	# A document that has its own terrain again writes that instead.
	back.terra = TerraDoc.new()
	var fresh: Dictionary = MapDocumentIO.serialize(back)["entries"]
	assert_ne(fresh[MapTerrainIO.ENTRY], bytes)
