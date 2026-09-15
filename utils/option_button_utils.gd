class_name OptionButtonUtils
extends RefCounted


## Select the dropdown item whose metadata equals [param value]; true if found.
static func select_by_metadata(dropdown: OptionButton, value: Variant) -> bool:
	for i in range(dropdown.item_count):
		if dropdown.get_item_metadata(i) == value:
			dropdown.select(i)
			return true
	return false
