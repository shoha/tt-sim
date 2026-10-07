extends GutTest

## The avatar library (AvatarLibrary) and the builder's saves into it: an avatar round-trips
## through its file, the list is newest first, a corrupt, foreign or unknown-format file is
## skipped, duplicate, rename and delete work on the file, and an id never leaves the
## directory. The builder saves a library avatar without a game, offers to save an avatar
## made in a game (on by default) and tags the token with its entry, and on an avatar from
## the library updates that entry or saves a new one. Every test uses its own directory.

const DIR := "user://_avatarlibrary_test/"
const RECIPE := {
	"format": 1,
	"parts": {"body": "body_a", "head": "head_round", "hair": "hair_bun"},
	"colours": {"skin": 1, "hair": 0, "eyes": 0, "primary": 0, "secondary": 1, "accent": 2},
	"face": {"eyes": 1, "brows": 1, "mouths": 0, "marks": 0},
	"proportions": {"height": 0.5, "build": 0.45, "head": 0.55},
	"stance": "stance_ready",
}

var _old_scene: Node = null
var _scene: Node = null


func before_each() -> void:
	AvatarLibrary.directory = DIR
	_old_scene = get_tree().current_scene
	_scene = Node.new()
	_scene.name = "AvatarLibraryTestScene"
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene


func after_each() -> void:
	get_tree().current_scene = _old_scene
	_scene.free()
	AvatarLibrary.directory = AvatarLibrary.DEFAULT_DIRECTORY
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file in dir.get_files():
			dir.remove(file)


func after_all() -> void:
	DirAccess.remove_absolute(DIR)


func _write_raw(file_name: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var file := FileAccess.open(DIR.path_join(file_name), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _entry_json(id: String, created: int) -> String:
	return (
		JSON
		. stringify(
			{
				"format": 1,
				"id": id,
				"name": id,
				"recipe": RECIPE,
				"created": created,
				"updated": created,
			}
		)
	)


# --- the library -------------------------------------------------------------------------------


func test_an_avatar_round_trips_through_its_file() -> void:
	var saved := AvatarLibrary.save("  Plum ", RECIPE)
	assert_false(saved.is_empty())
	assert_true(String(saved.id).begins_with(AvatarLibrary.ID_PREFIX))
	assert_true(FileAccess.file_exists(DIR.path_join(String(saved.id) + ".json")))
	var loaded := AvatarLibrary.get_entry(String(saved.id))
	assert_eq(loaded.name, "Plum", "names are trimmed")
	assert_eq(loaded.recipe, AvatarRecipe.normalized(RECIPE), "the recipe reads back typed")
	assert_eq(loaded.format, AvatarLibrary.FORMAT)
	assert_eq(loaded.created, saved.created)
	var again := AvatarLibrary.save("Plum the second", loaded.recipe, String(saved.id))
	assert_eq(again.id, saved.id, "a save with its id updates it")
	assert_eq(again.created, saved.created, "and keeps when it was made")
	assert_eq(AvatarLibrary.list().size(), 1)
	assert_eq(AvatarLibrary.list()[0].name, "Plum the second")


func test_the_list_is_newest_first() -> void:
	_write_raw("av_1_a.json", _entry_json("av_1_a", 100))
	_write_raw("av_3_c.json", _entry_json("av_3_c", 300))
	_write_raw("av_2_b.json", _entry_json("av_2_b", 200))
	_write_raw("av_2_d.json", _entry_json("av_2_d", 200))
	var ids: Array = []
	for entry in AvatarLibrary.list():
		ids.append(entry.id)
	assert_eq(ids, ["av_3_c", "av_2_d", "av_2_b", "av_1_a"], "by when made, then by id")


func test_corrupt_foreign_and_unknown_files_are_skipped() -> void:
	_write_raw("av_1_a.json", _entry_json("av_1_a", 100))
	_write_raw("av_bad.json", "{not json")
	_write_raw("av_empty.json", "")
	_write_raw("av_list.json", "[1, 2]")
	var future := JSON.parse_string(_entry_json("av_future", 50)) as Dictionary
	future["format"] = 99
	_write_raw("av_future.json", JSON.stringify(future))
	var no_recipe := JSON.parse_string(_entry_json("av_norecipe", 60)) as Dictionary
	no_recipe.erase("recipe")
	_write_raw("av_norecipe.json", JSON.stringify(no_recipe))
	_write_raw("notes.txt", "not an avatar")
	var listed := AvatarLibrary.list()
	assert_eq(listed.size(), 1, "only the good file is listed")
	assert_eq(listed[0].id, "av_1_a")
	assert_true(FileAccess.file_exists(DIR.path_join("av_future.json")), "skipped files stay")
	assert_engine_error(5, "one warning per skipped avatar file")


func test_duplicate_rename_and_delete() -> void:
	var plum := AvatarLibrary.save("Plum", RECIPE)
	var copy := AvatarLibrary.duplicate_entry(String(plum.id))
	assert_ne(copy.id, plum.id)
	assert_eq(copy.name, "Plum copy")
	assert_eq(copy.recipe, plum.recipe)
	assert_true(AvatarLibrary.rename(String(copy.id), "Damson"))
	assert_eq(AvatarLibrary.get_entry(String(copy.id)).name, "Damson")
	assert_true(AvatarLibrary.delete(String(plum.id)))
	assert_false(AvatarLibrary.delete(String(plum.id)), "a second delete finds nothing")
	assert_true(AvatarLibrary.get_entry(String(plum.id)).is_empty())
	assert_eq(AvatarLibrary.list().size(), 1)
	assert_false(AvatarLibrary.rename("av_missing", "x"))


func test_an_id_never_leaves_the_directory() -> void:
	assert_true(AvatarLibrary.get_entry("../settings").is_empty())
	assert_false(AvatarLibrary.delete("../settings"))
	var saved := AvatarLibrary.save("Plum", RECIPE, "../escape")
	assert_true(String(saved.id).begins_with(AvatarLibrary.ID_PREFIX), "an unknown id saves new")


func test_the_library_tells_views_it_changed() -> void:
	watch_signals(AvatarLibrary.events())
	var saved := AvatarLibrary.save("Plum", RECIPE)
	AvatarLibrary.delete(String(saved.id))
	assert_signal_emit_count(AvatarLibrary.events(), "changed", 2)


# --- the builder's saves -----------------------------------------------------------------------


func test_a_library_avatar_is_made_and_edited_without_a_game() -> void:
	var builder := AvatarBuilder.open_for_library(_scene)
	assert_null(builder.save_choice(), "no choice: a library avatar is always saved")
	builder.name_input.text = "Fig"
	builder.pick_face("mouths", 2)
	builder.confirm()
	var listed := AvatarLibrary.list()
	assert_eq(listed.size(), 1)
	assert_eq(listed[0].name, "Fig")
	assert_eq(int(listed[0].recipe.face.mouths), 2)
	var edit := AvatarBuilder.open_for_library(_scene, listed[0])
	edit.pick_stance("stance_heroic")
	edit.confirm()
	assert_eq(AvatarLibrary.list().size(), 1, "an edit updates the same avatar")
	assert_eq(AvatarLibrary.list()[0].recipe.stance, "stance_heroic")


func test_an_avatar_made_in_a_game_is_offered_for_saving() -> void:
	var builder := AvatarBuilder.open_for_new(_scene, RECIPE, "Plum")
	assert_true(builder.save_choice().wants_save(), "saving is pre-selected")
	builder.confirm()
	assert_eq(AvatarLibrary.list().size(), 1)
	assert_eq(builder.saved_entry.id, AvatarLibrary.list()[0].id)
	var declined := AvatarBuilder.open_for_new(_scene, RECIPE, "Damson")
	declined.save_choice().set_save(false)
	declined.confirm()
	assert_eq(AvatarLibrary.list().size(), 1, "unticked, nothing is saved")


func test_editing_a_placed_library_avatar_updates_or_saves_new() -> void:
	var plum := AvatarLibrary.save("Plum", RECIPE)
	var token := AvatarTokenFactory.create(plum.recipe, "Plum")
	token.set_meta(AvatarBuilder.LIBRARY_META, plum.id)
	_scene.add_child(token)
	var builder := AvatarBuilder.open_for_token(_scene, token)
	assert_eq(builder.save_choice().update_id(), plum.id, "updating it is the default")
	builder.pick_colour("hair", 3)
	builder.confirm()
	assert_eq(AvatarLibrary.list().size(), 1)
	assert_eq(int(AvatarLibrary.get_entry(String(plum.id)).recipe.colours.hair), 3)
	var again := AvatarBuilder.open_for_token(_scene, token)
	again.save_choice().choose_new(true)
	again.pick_colour("hair", 4)
	again.confirm()
	assert_eq(AvatarLibrary.list().size(), 2, "or it saves a new one")
	assert_ne(token.get_meta(AvatarBuilder.LIBRARY_META), plum.id, "and the token follows it")
