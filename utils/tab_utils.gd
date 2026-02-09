class_name TabUtils
## Static helpers for consistent TabContainer behaviour.
##
## Provides a shared cross-fade animation so every TabContainer in the project
## looks and sounds the same when switching tabs.


## Animate the newly-visible tab with a quick opacity fade and play a tick sound.
## Call this from a TabContainer's `tab_changed` signal handler.
##
## [codeblock]
## tab_container.tab_changed.connect(_on_tab_changed)
##
## func _on_tab_changed(_tab_idx: int) -> void:
##     TabUtils.animate_tab_change(tab_container, self)
## [/codeblock]
static func animate_tab_change(tab_container: TabContainer, owner: Node) -> void:
	var tab := tab_container.get_current_tab_control()
	if tab:
		tab.modulate.a = 0.0
		var tw := owner.create_tween()
		tw.set_ease(Tween.EASE_OUT)
		tw.set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(tab, "modulate:a", 1.0, Constants.ANIM_FADE_OUT_DURATION)
	AudioManager.play_tick()
