extends GutTest

## A map that will not open says which map, why (gone from the maps folder, or there but
## damaged) and how to recover (UI_TASTE W3), and calls it a map, not a level (W5).


func test_a_missing_map_says_it_is_gone_and_how_to_recover() -> void:
	var text := MapLoadError.for_info({"path": "res://no_such_map/", "name": "Mossy Hollow"})
	assert_eq(
		text,
		(
			'"Mossy Hollow" could not be opened: it is no longer in your maps folder.'
			+ " Choose another map."
		)
	)


## Any folder that is there stands in for a level folder whose save will not read.
func test_a_map_that_is_there_but_will_not_read_is_damaged() -> void:
	var text := MapLoadError.text("res://tests/unit/", "Mossy Hollow")
	assert_string_contains(text, "its save file is damaged")
	assert_string_contains(text, "Choose another map")


func test_an_unnamed_map_is_that_map() -> void:
	assert_string_starts_with(MapLoadError.text(""), "That map could not be opened")
	assert_false(MapLoadError.text("").to_lower().contains("level"))
