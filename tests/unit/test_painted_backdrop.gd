extends GutTest

## PaintedBackdrop: the curated moods by environment preset, the slow cross-fade between
## them, Reduce motion holding the drift, and the zones that keep words legible.


func _backdrop() -> PaintedBackdrop:
	var backdrop := PaintedBackdrop.new()
	add_child_autofree(backdrop)
	return backdrop


func _param(backdrop: PaintedBackdrop, param: StringName) -> Variant:
	return (backdrop.material as ShaderMaterial).get_shader_parameter(param)


func test_presets_map_onto_the_six_moods() -> void:
	assert_eq(PaintedBackdrop.mood_of(""), PaintedBackdrop.Mood.MORNING, "no map, no preset")
	assert_eq(PaintedBackdrop.mood_of("forest"), PaintedBackdrop.Mood.MORNING)
	assert_eq(PaintedBackdrop.mood_of("outdoor_day"), PaintedBackdrop.Mood.MIDDAY)
	assert_eq(PaintedBackdrop.mood_of("outdoor_sunset"), PaintedBackdrop.Mood.GOLDEN_HOUR)
	assert_eq(PaintedBackdrop.mood_of("hell"), PaintedBackdrop.Mood.DUSK)
	assert_eq(PaintedBackdrop.mood_of("outdoor_overcast"), PaintedBackdrop.Mood.OVERCAST)
	assert_eq(PaintedBackdrop.mood_of("outdoor_night"), PaintedBackdrop.Mood.NIGHT)
	assert_eq(PaintedBackdrop.mood_of("cave"), PaintedBackdrop.Mood.NIGHT)
	assert_eq(PaintedBackdrop.mood_of("no_such_preset"), PaintedBackdrop.Mood.MORNING)


## Every preset the picker offers paints a mood the shader knows.
func test_every_preset_paints_a_known_mood() -> void:
	for group: String in EnvironmentPresets.PRESET_GROUPS:
		for preset: String in EnvironmentPresets.PRESET_GROUPS[group]:
			var mood := PaintedBackdrop.mood_of(preset)
			assert_between(int(mood), 0, PaintedBackdrop.Mood.size() - 1, preset)


func test_the_first_mood_shows_at_once_and_a_change_cross_fades() -> void:
	var backdrop := _backdrop()
	backdrop.show_mood(PaintedBackdrop.Mood.GOLDEN_HOUR)
	assert_eq(_param(backdrop, &"mood_to"), int(PaintedBackdrop.Mood.GOLDEN_HOUR))
	assert_eq(_param(backdrop, &"blend"), 1.0)
	backdrop.show_mood(PaintedBackdrop.Mood.NIGHT)
	assert_eq(backdrop.mood(), PaintedBackdrop.Mood.NIGHT)
	assert_eq(PaintedBackdrop.last_mood, PaintedBackdrop.Mood.NIGHT)
	assert_eq(_param(backdrop, &"mood_from"), int(PaintedBackdrop.Mood.GOLDEN_HOUR))
	assert_eq(_param(backdrop, &"mood_to"), int(PaintedBackdrop.Mood.NIGHT))
	assert_lt(float(_param(backdrop, &"blend")), 0.1, "fading, not cut")
	await wait_seconds(PaintedBackdrop.FADE_S + 0.2)
	assert_eq(_param(backdrop, &"blend"), 1.0)
	PaintedBackdrop.last_mood = PaintedBackdrop.Mood.MORNING


## A new mood part way through a fade starts from the mood that dominated the picture.
func test_an_interrupted_fade_starts_from_what_dominated() -> void:
	var backdrop := _backdrop()
	backdrop.show_mood(PaintedBackdrop.Mood.MORNING)
	backdrop.show_mood(PaintedBackdrop.Mood.DUSK)
	backdrop.show_mood(PaintedBackdrop.Mood.OVERCAST)
	assert_eq(_param(backdrop, &"mood_from"), int(PaintedBackdrop.Mood.MORNING))
	assert_eq(_param(backdrop, &"mood_to"), int(PaintedBackdrop.Mood.OVERCAST))
	PaintedBackdrop.last_mood = PaintedBackdrop.Mood.MORNING


func test_drift_follows_reduce_motion() -> void:
	var backdrop := _backdrop()
	var expected := 0.0 if UiMotion.reduced() else 1.0
	assert_eq(_param(backdrop, &"drift"), expected)


## A label's zone is its text, not its whole row; a group is one zone, the union of its words.
func test_zones_cover_the_words_where_they_sit() -> void:
	var backdrop := _backdrop()
	var label := Label.new()
	label.text = "Your room"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(100, 600)
	label.size = Vector2(800, 30)
	add_child_autofree(label)
	var corner := Label.new()
	corner.text = "v0.2"
	corner.position = Vector2(16, 690)
	add_child_autofree(corner)
	backdrop.keep_legible([[label], [corner]])
	var zones := backdrop.zone_rects()
	assert_eq(zones.size(), 2)
	assert_lt(zones[0].size.x, 400.0, "the text, not the label's 800 px row")
	assert_almost_eq(zones[0].get_center().x, 500.0, 1.0, "centred where the text is")
	assert_true(zones[1].has_point(Vector2(20, 700)))
	corner.visible = false
	assert_eq(backdrop.zone_rects().size(), 1, "a hidden control has no zone")
	await wait_frames(2)
	assert_eq(_param(backdrop, &"zone_count"), 1)
