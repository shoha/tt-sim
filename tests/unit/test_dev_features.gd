extends GutTest

## DevFeatures.avatars holds avatars back from exported builds: with it off there is no
## Avatar tab in the asset browser and no Edit Avatar on a token's menu. Tests run on the
## editor binary, where it is on. (The menu's side is in test_avatar_builder.)

const BROWSER_SCENE := preload("res://scenes/states/playing/asset_browser.tscn")

var _was: bool


func before_each() -> void:
	_was = DevFeatures.avatars


func after_each() -> void:
	DevFeatures.avatars = _was


func test_avatars_are_on_in_the_editor_binary() -> void:
	assert_true(DevFeatures.avatars)


func test_the_asset_browser_has_no_avatar_tab_when_avatars_are_off() -> void:
	DevFeatures.avatars = false
	var browser: AssetBrowser = BROWSER_SCENE.instantiate()
	add_child_autofree(browser)
	assert_null(browser.get_avatar_tab())
	assert_null(browser.tab_container.get_node_or_null(NodePath(AvatarTab.TAB_TITLE)))


func test_the_asset_browser_has_the_avatar_tab_when_avatars_are_on() -> void:
	DevFeatures.avatars = true
	var browser: AssetBrowser = BROWSER_SCENE.instantiate()
	add_child_autofree(browser)
	assert_not_null(browser.get_avatar_tab())
