extends GutTest

## AssetBrowserContainer extends AnimatedVisibilityContainer with the default
## start_hidden = true. The base _ready() sets modulate.a = 0 and hides the
## container before calling the _on_ready() hook, so a subclass overriding
## _ready() (instead of _on_ready()) without calling super() skips that reset
## and every open's fade tween starts from full opacity. Regression coverage
## for that bug: assert the container is faded out and hidden the moment it
## enters the tree.

const SCENE := preload("res://scenes/states/playing/gameplay_menu.tscn")


func _menu() -> Node:
	var menu: Node = SCENE.instantiate()
	add_child_autofree(menu)
	return menu


func test_asset_browser_container_starts_hidden_and_faded_out() -> void:
	var menu := _menu()
	var container: Control = menu.get_node("GameplayMenu/AssetBrowserContainer")
	assert_eq(container.modulate.a, 0.0)
	assert_false(container.visible)
