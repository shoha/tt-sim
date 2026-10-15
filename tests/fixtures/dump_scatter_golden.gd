extends SceneTree

## One-off: writes the scatter golden fixture (tests/unit/scatter_golden.gd dump()).


func _initialize() -> void:
	load("res://tests/unit/scatter_golden.gd").dump()
	print("golden written")
	quit()
