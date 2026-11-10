class_name QualityAuto
extends RefCounted

## The first-run quality pick: which QualityPreset a computer gets before its player has chosen
## any graphics row (docs/systems/graphics_quality.md).
##
## The model. A first run measures instead of guessing from the GPU's name (names go stale, and a
## mislabelled driver string must not pin a fast card to Low): QualityBench draws a small fixed
## table behind the title and reports its GPU time, predicted_ms() turns that into the frame
## time of a filled 200 ft map at the home view with the shipped defaults (the view that decides
## whether a 1060-class GPU holds 60 fps, docs/PERFORMANCE.md "Minimum-spec estimate"), and
## decide() reads the preset off a table: HIGH while that frame leaves DEFAULT_SHARE of the 60 fps
## budget spare, LOW while LOW's frame (LOW_RATIO of it) fits the budget, else LOWEST, the floor.
## The adapter type (integrated, discrete, software) only stands in when there is no valid
## measurement.
##
## Once per install, honest and overridable. The pick runs only when the settings file has no
## [quality] auto_done and no [graphics] row at all (pending()), so a player who ever saved a
## graphics row is never touched. Its result is written once (record()): auto_done, the preset,
## the measurement. It is never re-run by itself, so a card near a boundary cannot flip from
## launch to launch; Settings' Re-detect runs it again on request, and decide() then leans
## HYSTERESIS toward the preset already in use. Every row stays editable after it.
##
## Shipped off: the project setting FLAG_SETTING (default false) gates the automatic first-run
## pick until the board's look question on LOW is answered; with it off a first run is exactly
## the game before this (no measurement, no file written). Re-detect works either way, since a
## player asks for it.

## The project setting that turns the first-run pick on (project.godot [tt_sim]
## graphics/auto_quality=true; an override.cfg beside the game can set it too).
const FLAG_SETTING := "tt_sim/graphics/auto_quality"
## The settings file section and its keys.
const SECTION := "quality"
const KEY_DONE := "auto_done"
const KEY_PRESET := "auto_preset"
const KEY_PREDICTED := "auto_predicted_ms"
const KEY_BENCH := "auto_bench_ms"
const KEY_ADAPTER := "auto_adapter_type"
const KEY_RULE := "auto_rule"
## The table's version, saved with a pick so a later rule can tell an old pick from its own.
const RULE := 1

## The frame budget: 60 fps.
const TARGET_MS := 16.7
## HIGH needs its predicted frame within this share of the budget: the rest is headroom for
## tokens (about 3 to 5 ms for 100 on a 1060), the full zoom-out and the game's own CPU.
const DEFAULT_SHARE := 0.8
## LOW's frame over HIGH's at the decision view on an RTX 3080: 3.558 against 4.541 ms in the
## verdict run, 3.685 against 4.757 in the first (docs/PERFORMANCE.md "Quality presets").
const LOW_RATIO := 0.78
## How far a Re-detect's thresholds lean toward the preset in use (a share of each threshold).
const HYSTERESIS := 0.1
## The filled 200 ft home view's GPU ms at the shipped defaults over QualityBench's, measured in
## one run on an RTX 3080 at 1920x1080: 4.757 against 2.084 ms (docs/PERFORMANCE.md "Quality
## presets"). The same ratio held at 3840x2160 within 10 to 15 % (14.49 against 6.99 to 7.26).
const GAME_PER_BENCH := 2.28


## Whether a first run picks the quality by itself (FLAG_SETTING).
static func applies_automatically() -> bool:
	return bool(ProjectSettings.get_setting(FLAG_SETTING, false))


## Whether [param config] (the loaded settings file, empty for a first run) still wants the
## first-run pick: none recorded and no graphics row saved. Pure.
static func pending(config: ConfigFile) -> bool:
	return not bool(config.get_value(SECTION, KEY_DONE, false)) and not config.has_section("graphics")


## The decision view's predicted GPU ms for a QualityBench result of [param bench_ms]. Pure.
static func predicted_ms(bench_ms: float) -> float:
	return bench_ms * GAME_PER_BENCH


## The preset for a computer whose decision view is predicted at [param predicted] ms with the
## shipped defaults, whose GPU is of [param adapter_type] (a RenderingDevice.DeviceType), on a
## re-run [param previous] being the preset in use (QualityPreset.CUSTOM for none). A missing or
## unusable measurement (0, negative, NaN or infinite) falls back on the adapter type. Pure.
static func decide(
	predicted: float, adapter_type: int, previous: int = QualityPreset.CUSTOM
) -> int:
	if is_nan(predicted) or is_inf(predicted) or predicted <= 0.0:
		return fallback_for(adapter_type)
	var high_limit := TARGET_MS * DEFAULT_SHARE
	var low_limit := TARGET_MS / LOW_RATIO
	match previous:
		QualityPreset.HIGH:
			high_limit *= 1.0 + HYSTERESIS
			low_limit *= 1.0 + HYSTERESIS
		QualityPreset.LOW:
			high_limit *= 1.0 - HYSTERESIS
			low_limit *= 1.0 + HYSTERESIS
		QualityPreset.LOWEST:
			high_limit *= 1.0 - HYSTERESIS
			low_limit *= 1.0 - HYSTERESIS
	if predicted <= high_limit:
		return QualityPreset.HIGH
	if predicted <= low_limit:
		return QualityPreset.LOW
	return QualityPreset.LOWEST


## The preset when nothing was measured: a discrete or unknown GPU keeps the defaults, an
## integrated one gets LOW, a virtual or software one LOWEST. Pure.
static func fallback_for(adapter_type: int) -> int:
	match adapter_type:
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
			return QualityPreset.LOW
		RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU, RenderingDevice.DEVICE_TYPE_CPU:
			return QualityPreset.LOWEST
	return QualityPreset.HIGH


## Writes a pick into [param config]: the [quality] record and the preset's rows, except that a
## HIGH pick into a file with no [graphics] section leaves it without one (that computer then runs
## exactly as with no settings file). [param bench] is QualityBench's result ({"gpu_ms",
## "adapter_type"}). Not saved to disk.
static func record(config: ConfigFile, preset: int, bench: Dictionary) -> void:
	var rows_too := preset != QualityPreset.HIGH or config.has_section("graphics")
	var bench_ms := float(bench.get("gpu_ms", 0.0))
	config.set_value(SECTION, KEY_DONE, true)
	config.set_value(SECTION, KEY_PRESET, preset)
	config.set_value(SECTION, KEY_BENCH, snappedf(bench_ms, 0.001))
	config.set_value(SECTION, KEY_PREDICTED, snappedf(predicted_ms(bench_ms), 0.001))
	config.set_value(SECTION, KEY_ADAPTER, int(bench.get("adapter_type", -1)))
	config.set_value(SECTION, KEY_RULE, RULE)
	if rows_too:
		QualityPreset.write(config, preset)


## The preset a pick recorded in [param config], or QualityPreset.CUSTOM when none ran.
static func recorded_preset(config: ConfigFile) -> int:
	if not bool(config.get_value(SECTION, KEY_DONE, false)):
		return QualityPreset.CUSTOM
	return int(config.get_value(SECTION, KEY_PRESET, QualityPreset.CUSTOM))
