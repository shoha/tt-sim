extends GutTest

## The 3D world renders into a SubViewport whose texture the lo-fi canvas shader
## post-processes. Debanding is a per-viewport property, so the SubViewport does not
## pick up the rendering/anti_aliasing/quality/use_debanding project setting and must
## enable it itself. Without it the 8-bit render target quantises smooth sky and fog
## gradients into visible bands, and the shader's vignette and tint multiplies then
## widen those bands instead of smoothing them. Regression coverage for that bug:
## assert the scene stores use_debanding on the world SubViewport.

const SCENE := preload("res://scenes/states/playing/game_map.tscn")
const SUBVIEWPORT_PATH := "WorldViewportLayer/SubViewportContainer/SubViewport"


func _stored_properties(node_path: String) -> Dictionary:
	var state := SCENE.get_state()
	for i in state.get_node_count():
		# SceneState reports paths relative to the scene root, prefixed with "./".
		if str(state.get_node_path(i)).trim_prefix("./") != node_path:
			continue
		var props := {}
		for j in state.get_node_property_count(i):
			props[state.get_node_property_name(i, j)] = state.get_node_property_value(i, j)
		return props
	return {}


func test_world_subviewport_enables_debanding() -> void:
	var props := _stored_properties(SUBVIEWPORT_PATH)
	assert_true(props.has("use_debanding"), "world SubViewport should store use_debanding")
	assert_eq(props.get("use_debanding"), true, "debanding must be on to avoid gradient banding")
