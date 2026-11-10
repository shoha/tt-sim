class_name SettingsQuality
extends RefCounted

## The Graphics tab's "Quality" row (QualityPreset: High, Low, Lowest), its note and its
## Re-detect button, split out of settings_menu.gd to keep that file under the lint budget. The
## menu loads it by path when it opens (settings_menu.gd is on the start-up graph, this and the
## quality scripts are not).
##
## Picking a preset puts its four rows (Shadow quality, Shadow cascades, Ambient occlusion,
## Render scale) on their controls, and Apply applies and saves them as it does any row; the
## rows stay editable, and one that no longer matches makes the row read Custom. The note says
## when the preset shown is the one measured for this computer (QualityAuto's record).
## Re-detect measures now (QualityBench) and applies and saves the pick at once, like a one-click
## Apply of those four rows; it leans toward the preset in use, so a borderline computer does
## not flip.

const TOOLTIP := (
	"Sets the four rows that cost the most on a slower graphics card: Shadow quality, Shadow "
	+ "cascades, Ambient occlusion and Render scale. High is the full look. Low turns the "
	+ "ambient occlusion and the shadow cascade blend off. Lowest also draws the board at "
	+ "75% and enlarges it, a little softer. Each row can still be changed."
)
const REDETECT_TOOLTIP := (
	"Measures how fast this computer draws the table (about two seconds) and picks the "
	+ "quality that keeps it smooth."
)
const NOTE_CHOSEN := "Chosen for this computer."
const NOTE_MEASURING := "Measuring this computer..."
const NOTE_FAILED := "Could not measure this computer; nothing was changed."

var _menu: SettingsMenu = null
var _option: OptionButton = null
var _button: Button = null
var _note_row: Control = null
var _note: Label = null
var _bench: Node = null
## The preset QualityAuto recorded for this computer (QualityPreset.CUSTOM for none).
var _recorded := QualityPreset.CUSTOM


func _init(menu: SettingsMenu) -> void:
	_menu = menu
	_option = menu.get_node("%QualityOption")
	_button = menu.get_node("%QualityRedetectButton")
	_note_row = menu.get_node("%QualityNoteRow")
	_note = menu.get_node("%QualityNote")
	_option.clear()
	for preset in QualityPreset.CHOICES:
		_option.add_item(QualityPreset.LABELS[preset], preset)
	_option.add_item(QualityPreset.LABELS[QualityPreset.CUSTOM], QualityPreset.CUSTOM)
	_option.set_item_disabled(_option.get_item_index(QualityPreset.CUSTOM), true)
	_option.tooltip_text = TOOLTIP
	_button.tooltip_text = REDETECT_TOOLTIP
	_option.item_selected.connect(_on_preset_selected)
	_button.pressed.connect(_on_redetect_pressed)
	menu.shadow_quality_option.item_selected.connect(_on_row_changed)
	menu.shadow_cascades_option.item_selected.connect(_on_row_changed)
	menu.render_scale_option.item_selected.connect(_on_row_changed)
	menu.ssao_check.toggled.connect(_on_row_changed)


## Shows the preset the saved rows make and whether it was measured for this computer.
func show_saved(config: ConfigFile) -> void:
	_recorded = QualityAuto.recorded_preset(config)
	refresh()


## Re-reads the four rows' controls: selects the preset they make (Custom when none) and shows
## or hides the note.
func refresh() -> void:
	var preset := QualityPreset.matching(_shown_rows())
	_option.select(_option.get_item_index(preset))
	_set_note(NOTE_CHOSEN if preset != QualityPreset.CUSTOM and preset == _recorded else "")


## The four rows as the controls show them now.
func _shown_rows() -> Dictionary:
	return {
		"shadow_quality": _menu.shadow_quality_option.get_selected_id(),
		"shadow_cascades": _menu.shadow_cascades_option.get_selected_id(),
		"ssao_enabled": _menu.ssao_check.button_pressed,
		"render_scale": _menu.render_scale_option.get_selected_id(),
	}


## Puts [param preset]'s rows on their controls without applying them (Apply does).
func _show_rows(preset: int) -> void:
	var rows := QualityPreset.rows_for(preset)
	_select(_menu.shadow_quality_option, int(rows.shadow_quality))
	_select(_menu.shadow_cascades_option, int(rows.shadow_cascades))
	_select(_menu.render_scale_option, int(rows.render_scale))
	_menu.ssao_check.set_pressed_no_signal(bool(rows.ssao_enabled))


func _on_preset_selected(index: int) -> void:
	var preset := _option.get_item_id(index)
	if preset == QualityPreset.CUSTOM:
		return
	_show_rows(preset)
	refresh()


func _on_row_changed(_value: Variant) -> void:
	refresh()


func _on_redetect_pressed() -> void:
	if is_instance_valid(_bench):
		return
	_button.disabled = true
	_set_note(NOTE_MEASURING)
	var bench := QualityBench.new()
	bench.name = "QualityBench"
	# Over a map, vsync stays on: the map is still on screen and would tear.
	bench.may_cover = _menu._find_game_map() == null
	bench.measured.connect(_on_measured, CONNECT_ONE_SHOT)
	_bench = bench
	_menu.add_child(bench)


func _on_measured(result: Dictionary) -> void:
	_bench = null
	_button.disabled = false
	var config := ConfigFile.new()
	config.load(Paths.SETTINGS_PATH)
	if not bool(result.get("ok", false)):
		_set_note(NOTE_FAILED)
		return
	var previous := QualityPreset.matching(QualityPreset.saved_rows(config))
	var predicted := QualityAuto.predicted_ms(float(result.gpu_ms))
	var preset := QualityAuto.decide(predicted, int(result.adapter_type), previous)
	QualityAuto.record(config, preset, result)
	QualityPreset.write(config, preset)
	config.save(Paths.SETTINGS_PATH)
	QualityPreset.apply_rows(QualityPreset.rows_for(preset), _menu._find_game_map(), config)
	print(
		(
			"SettingsQuality: re-detect picked %s (bench %.2f ms, predicted %.1f ms)"
			% [QualityPreset.LABELS[preset], float(result.gpu_ms), predicted]
		)
	)
	_recorded = preset
	_show_rows(preset)
	refresh()


func _set_note(text: String) -> void:
	_note.text = text
	_note_row.visible = not text.is_empty()


static func _select(option: OptionButton, id: int) -> void:
	var index := option.get_item_index(id)
	option.select(index if index >= 0 else 0)
