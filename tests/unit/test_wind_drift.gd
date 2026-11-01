extends GutTest

## The last consumers of the global wind (docs/systems/wind.md phase f): the pure smoke lean,
## event drift, dust drift and water chop of WindDrift, each off at motion scale 0; the dust a
## terrain event throws up taking its drift; and a guard that the shaders read the global
## uniforms through wind_global.gdshaderinc with WindDrift's constants and the plants' gust field.

const SHADERS: Array[String] = [
	"res://shaders/fire_smoke_book.gdshader",
	"res://shaders/fire_flames.gdshader",
	"res://shaders/water.gdshader",
]
const INCLUDE := "res://shaders/wind_global.gdshaderinc"
const FOLIAGE_INCLUDE := "res://shaders/wind_foliage_include.gdshaderinc"

var _motion_was := 1.0


func before_each() -> void:
	_motion_was = Wind.wind_motion()


func after_each() -> void:
	Wind.set_wind_motion(_motion_was)
	Wind.set_preset("calm")
	Wind.snap()


func test_strength_runs_from_the_calm_stop_to_the_storm_stop() -> void:
	var calm: Array = WindPresets.STOPS[0]
	var storm: Array = WindPresets.STOPS[WindPresets.STOPS.size() - 1]
	assert_eq(WindDrift.CALM_SPEED, float(calm[WindPresets.COL_SPEED]))
	assert_eq(WindDrift.STORM_SPEED, float(storm[WindPresets.COL_SPEED]))
	assert_eq(WindDrift.strength01(0.0), 0.0)
	assert_eq(WindDrift.strength01(WindDrift.CALM_SPEED), 0.0)
	assert_eq(WindDrift.strength01(WindDrift.STORM_SPEED), 1.0)
	assert_eq(WindDrift.strength01(40.0), 1.0)
	assert_almost_eq(WindDrift.strength01(7.75), 0.5, 1e-5)


func test_calm_smoke_leans_as_it_did_before_the_wind() -> void:
	assert_eq(WindDrift.SMOKE_LEAN_CALM, FireFieldSmoke.LEAN, "calm is the tuned lean")
	var rest := WindDrift.SMOKE_GUST_REST
	assert_almost_eq(WindDrift.smoke_lean(1.5, 0.35, rest), FireFieldSmoke.LEAN, 1e-6)


func test_smoke_leans_further_in_a_storm_and_as_a_gust_passes() -> void:
	var calm := WindDrift.smoke_lean(1.5, 0.35, 0.5)
	var windy := WindDrift.smoke_lean(8.0, 0.75, 0.5)
	var storm := WindDrift.smoke_lean(14.0, 1.0, 0.5)
	assert_gt(windy, calm)
	assert_gt(storm, windy)
	var lull := WindDrift.smoke_lean(14.0, 1.0, 0.0)
	var front := WindDrift.smoke_lean(14.0, 1.0, 1.0)
	assert_gt(front, storm, "a front leans it over")
	assert_lt(lull, storm, "the lull stands it back up")
	assert_lte(front, WindDrift.SMOKE_LEAN_MAX)
	assert_eq(WindDrift.smoke_lean(40.0, 3.0, 1.0), WindDrift.SMOKE_LEAN_MAX, "capped")


func test_smoke_follows_the_map_at_motion_zero_and_the_wind_at_one() -> void:
	var still := Vector2(0.0, 1.0)
	var wind := Vector2(1.0, 0.0)
	assert_eq(WindDrift.smoke_lean_at(0.45, 1.1, 0.0), 0.45)
	assert_eq(WindDrift.smoke_lean_at(0.45, 1.1, 1.0), 1.1)
	assert_eq(WindDrift.smoke_dir_at(still, wind, 0.0), still)
	assert_eq(WindDrift.smoke_dir_at(still, wind, 1.0), wind)
	var half := WindDrift.smoke_dir_at(still, wind, 0.5)
	assert_almost_eq(half.length(), 1.0, 1e-5, "unit between the two")
	assert_eq(WindDrift.smoke_dir_at(-wind, wind, 0.5), wind, "the wind's when they cancel")


func test_event_drift_turns_onto_the_wind_and_keeps_its_own_at_motion_zero() -> void:
	var still := Vector3(0.0, 0.0, 0.35)
	assert_eq(WindDrift.event_drift(still, Vector3(8.0, 0.0, 0.0), 0.0), still)
	assert_eq(WindDrift.event_drift(still, Vector3.ZERO, 1.0), still, "no wind: its own")
	var calm := WindDrift.event_drift(still, Vector3(1.5, 0.0, 0.0), 1.0)
	assert_almost_eq(calm, Vector3(WindDrift.EVENT_DRIFT_CALM, 0.0, 0.0), Vector3.ONE * 1e-5)
	var storm := WindDrift.event_drift(still, Vector3(0.0, 3.0, -14.0), 1.0)
	assert_almost_eq(storm, Vector3(0.0, 0.0, -WindDrift.EVENT_DRIFT_STORM), Vector3.ONE * 1e-5)


func test_dust_drifts_with_a_share_of_the_wind_capped_and_off_at_motion_zero() -> void:
	var wind := Vector3(5.0, 1.0, 0.0)
	assert_eq(WindDrift.dust_drift(wind, 0.0), Vector3.ZERO)
	assert_almost_eq(WindDrift.dust_drift(wind, 1.0), Vector3(1.0, 0.0, 0.0), Vector3.ONE * 1e-5)
	assert_almost_eq(WindDrift.dust_drift(wind, 0.5), Vector3(0.5, 0.0, 0.0), Vector3.ONE * 1e-5)
	var gale := WindDrift.dust_drift(Vector3(0.0, 0.0, 60.0), 1.0)
	assert_almost_eq(gale.length(), WindDrift.DUST_MAX, 1e-4)


func test_chop_is_one_at_calm_and_at_motion_zero_and_rises_with_wind_and_gusts() -> void:
	assert_eq(WindDrift.chop_factor(1.5, 0.35, 1.0, 1.0), 1.0, "calm water is untouched")
	assert_eq(WindDrift.chop_factor(14.0, 1.0, 1.0, 0.0), 1.0, "motion 0 is untouched")
	var breezy := WindDrift.chop_factor(4.0, 0.55, 0.5, 1.0)
	var storm := WindDrift.chop_factor(14.0, 1.0, 0.5, 1.0)
	assert_gt(breezy, 1.0)
	assert_gt(storm, breezy)
	assert_gt(WindDrift.chop_factor(14.0, 1.0, 1.0, 1.0), storm, "rougher under a gust")
	var most := 1.0 + WindDrift.CHOP_BASE + WindDrift.CHOP_GUST
	assert_almost_eq(WindDrift.chop_factor(14.0, 1.0, 1.0, 1.0), most, 1e-6)
	assert_lte(most, 2.0, "faint: never more than twice the ripples' slope")


func test_a_dust_blob_takes_the_wind_and_a_drop_does_not() -> void:
	Wind.set_preset("storm")
	Wind.snap()
	Wind.set_wind_motion(1.0)
	var puffs := EventPuffs.new(4)
	add_child_autofree(puffs)
	puffs.emit(Vector3.ZERO, Vector3.UP * 0.3, 1.0, 1.2, Color.WHITE)
	puffs.emit(Vector3.ZERO, Vector3.UP * 3.0, 1.0, 1.2, Color.WHITE, 9.8)
	var blown := puffs._blown[0]
	if Wind.motion_scale() > 0.0:
		var along := Wind.direction_at(Vector3.ZERO)
		assert_gt(blown.dot(along), 0.5, "dust drifts downwind")
	assert_eq(puffs._blown[1], Vector3.ZERO, "a thrown drop is not blown")
	Wind.set_wind_motion(0.0)
	puffs.emit(Vector3.ZERO, Vector3.UP * 0.3, 1.0, 1.2, Color.WHITE)
	assert_eq(puffs._blown[2], Vector3.ZERO, "motion 0: no drift")


func test_the_column_bounds_make_room_for_the_storm_lean() -> void:
	assert_gte(WindDrift.SMOKE_LEAN_MAX, FireFieldSmoke.LEAN)
	var src := FileAccess.get_file_as_string("res://scenes/terrain/fire_field_smoke.gd")
	assert_string_contains(src, "WindDrift.SMOKE_LEAN_MAX")


func test_the_shaders_read_the_global_wind_with_windrifts_constants() -> void:
	var include := FileAccess.get_file_as_string(INCLUDE)
	for global_name in ["wind_dir", "wind_phase", "wind_gust"]:
		assert_string_contains(include, "global uniform vec4 %s;" % global_name)
	assert_string_contains(include, "const float WIND_CALM_SPEED = %s;" % str(WindDrift.CALM_SPEED))
	assert_string_contains(
		include, "const float WIND_STORM_SPEED = %s;" % str(WindDrift.STORM_SPEED)
	)
	for path in SHADERS:
		assert_not_null(load(path) as Shader, path)
		var sources := GraphicsWarmup.shader_sources_for([path], FileAccess.get_file_as_string)
		var joined := "\n".join(sources)
		assert_string_contains(joined, "global uniform vec4 wind_gust;", path)
		assert_string_contains(FileAccess.get_file_as_string(path), INCLUDE, path)
	var smoke := FileAccess.get_file_as_string(SHADERS[0])
	for pair in [
		["SMOKE_LEAN_CALM", WindDrift.SMOKE_LEAN_CALM],
		["SMOKE_LEAN_STORM", WindDrift.SMOKE_LEAN_STORM],
		["SMOKE_GUST", WindDrift.SMOKE_GUST],
		["SMOKE_GUST_REST", WindDrift.SMOKE_GUST_REST],
		["SMOKE_LEAN_MAX", WindDrift.SMOKE_LEAN_MAX],
	]:
		assert_string_contains(smoke, "const float %s = %s;" % [pair[0], str(pair[1])])
	var water := FileAccess.get_file_as_string(SHADERS[2])
	assert_string_contains(water, "const float CHOP_BASE = %s;" % str(WindDrift.CHOP_BASE))
	assert_string_contains(water, "const float CHOP_GUST = %s;" % str(WindDrift.CHOP_GUST))
	assert_string_contains(water, "wind_global_gust(p)")
	assert_string_contains(smoke, "wind_global_gust(born.xz)")


func test_the_gust_field_is_the_plants_term_for_term() -> void:
	var ours := _body(FileAccess.get_file_as_string(INCLUDE), "float wind_global_gust(")
	var plants := _body(FileAccess.get_file_as_string(FOLIAGE_INCLUDE), "float wind_gust_field(")
	assert_ne(ours, "", "found the include's gust field")
	assert_eq(ours, plants, "the smoke and the water see the fronts the plants do")


## The text of the function opening with `head` up to its closing brace at column 0, without
## its signature line and with whitespace collapsed.
func _body(src: String, head: String) -> String:
	var at := src.find(head)
	if at < 0:
		return ""
	var open := src.find("{", at)
	var close := src.find("\n}", open)
	return _collapse(src.substr(open + 1, close - open - 1))


func _collapse(text: String) -> String:
	var parts := PackedStringArray()
	for word in text.replace("\r", " ").replace("\n", " ").replace("\t", " ").split(" ", false):
		parts.append(word)
	return " ".join(parts)
