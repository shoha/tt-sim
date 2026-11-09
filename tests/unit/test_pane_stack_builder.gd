extends GutTest

## PaneStack.add_pane_builder (perfaudit F-system-2): a pane registered with a builder is not made
## until it is shown or asked for, then made once and announced (pane_built); the authoring drawer
## builds a tool's own pane that way, and its controller wires the pane when it is built.

var _stack: PaneStack
var _calls := 0


func before_each() -> void:
	_calls = 0
	_stack = PaneStack.new()
	add_child_autofree(_stack)


func _make() -> Control:
	_calls += 1
	var pane := VBoxContainer.new()
	pane.name = "Built"
	return pane


func test_builder_runs_on_first_show_only() -> void:
	_stack.add_pane(&"eager", VBoxContainer.new())
	_stack.add_pane_builder(&"lazy", _make)
	assert_true(_stack.has_pane(&"lazy"))
	assert_false(_stack.is_built(&"lazy"))
	assert_eq(_calls, 0, "registering builds nothing")
	watch_signals(_stack)
	_stack.show_pane(&"lazy", false)
	assert_eq(_calls, 1)
	assert_true(_stack.is_built(&"lazy"))
	assert_eq(_stack.current, &"lazy")
	assert_signal_emitted(_stack, "pane_built")
	_stack.show_pane(&"eager", false)
	_stack.show_pane(&"lazy", false)
	assert_eq(_calls, 1, "built once")


func test_get_pane_builds() -> void:
	_stack.add_pane_builder(&"lazy", _make)
	var pane := _stack.get_pane(&"lazy")
	assert_not_null(pane)
	assert_eq(String(pane.name), "Built")
	assert_eq(_calls, 1)


func test_authoring_tool_panes_wait_for_first_show() -> void:
	var panel := AuthoringPanel.new()
	add_child_autofree(panel)
	assert_true(panel.is_tool_pane_built(AuthoringPanel.TOOL_BIOME), "the panel's own panes are built")
	assert_false(panel.is_tool_pane_built(StructureTool.ID), "a tool's own pane waits")
	assert_not_null(panel.tool_pane(StructureTool.ID))
	assert_true(panel.is_tool_pane_built(StructureTool.ID))
