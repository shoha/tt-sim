class_name BiomeDesignerSession
extends Node

## The live half of the biome designer (step S8a): keeps the proving ground in step with the
## draft. Every edit of the BiomeDesignerModel is debounced, compiled (model.compile), laid over
## the palette (LibraryRegistry.serve_draft), and the scatter is regenerated for exactly the rules
## the edit can change (ScatterRefresh.biome, ScatterRegen.replace_biome), so a single-rule edit
## costs a fraction of a whole-map regeneration. A change to the ground (surfaces, accents, the
## look) rebuilds the open map from its document instead (AuthoringController.reopen_async),
## because the terrain reads those at build time. The session reports progress (cells left) and
## can cancel; it measures the time from an edit to the moment the new rows are on the map.
## Map and model: docs/systems/biome_designer.md.

## A compile finished: the model.compile() result (ok false when the validators found errors, in
## which case the map keeps the last good rules).
signal compiled(result: Dictionary)
## The state or progress changed (State, {left, total}).
signal progress_changed(state: int, progress: Dictionary)
## The new rows are on the map: {total_ms, compile_ms, serve_ms, request_ms, regen_ms, species, of,
## cells, ...} (the timing of one edit from its signal to the last landed job).
signal regenerated(stats: Dictionary)
signal selection_changed(rule_key: String)

enum State { IDLE, WAITING, REGENERATING, CANCELLED }

## Seconds after the last edit before the draft is compiled (a slider drag settles).
const DEBOUNCE_SEC := 0.12
## The ground rebuild waits longer: it reopens the map.
const GROUND_DEBOUNCE_SEC := 0.6
## Hash keys of the draft whose change needs the map rebuilt.
const GROUND_KEYS: Array[String] = ["ground", "ground_look", "density_scale"]

var model: BiomeDesignerModel = null
var controller: AuthoringController = null
var state: State = State.IDLE
var selected_rule: String = ""
var season_index: int = 0
## The most recent stats (see `regenerated`) and the compile of the same edit.
var stats: Dictionary = {}
var debounce: float = DEBOUNCE_SEC
## Regenerate every rule of the biome after each edit, not only the ones the edit can change (a
## measurement switch: the cost the partial path saves).
var whole: bool = false

var _wait: float = 0.0
var _pending: bool = false
var _ground_pending: bool = false
var _ground_left: float = 0.0
var _ground_hash: int = 0
var _edit_usec: int = 0
var _timing: Dictionary = {}
var _total_cells: int = 0
var _reopening: bool = false


func _ready() -> void:
	set_process(false)


## Binds the session to its model and the authoring controller whose map it keeps in step.
func setup(designed: BiomeDesignerModel, authoring: AuthoringController) -> void:
	model = designed
	controller = authoring
	_ground_hash = _hash_of_ground()
	model.changed.connect(_on_model_changed)


func runtime_biome_id() -> String:
	var ids := model.runtime_ids()
	return ids[clampi(season_index, 0, ids.size() - 1)]


func scatter() -> AuthoredScatter:
	return controller.scatter if controller != null else null


## Compiles the draft and regenerates now (no debounce); returns the stats of the compile and
## the request (the regeneration then runs over the next frames).
func apply_now() -> Dictionary:
	_pending = false
	_wait = 0.0
	return _apply()


## Regenerates every rule of the biome (after a cancel, or on request).
func regenerate_all() -> void:
	var made := scatter()
	if made == null:
		return
	_edit_usec = Time.get_ticks_usec()
	_timing = {"compile_ms": 0.0, "serve_ms": 0.0}
	var started := Time.get_ticks_usec()
	var info := ScatterRefresh.biome(made, runtime_biome_id(), true)
	_finish_request(info, started)


## Stops the regeneration under way; the map then shows rows from the old and the new rules.
func cancel() -> void:
	var made := scatter()
	if made == null or state != State.REGENERATING:
		return
	ScatterRefresh.cancel(made)
	state = State.CANCELLED
	progress_changed.emit(state, progress())


## {left, total}: cells still to regenerate of the request.
func progress() -> Dictionary:
	var made := scatter()
	var left := ScatterRefresh.left(made) if made != null else 0
	return {"left": left, "total": maxi(_total_cells, left)}


## Switches the season the proving ground shows (the compiled biome of that season replaces the
## painted one and the map regenerates for it).
func set_season(index: int) -> void:
	var ids := model.runtime_ids()
	var next := clampi(index, 0, ids.size() - 1)
	if next == season_index or controller == null or controller.document == null:
		return
	var old_id := runtime_biome_id()
	season_index = next
	var made := scatter()
	var regen := made.get_regen()
	ScatterRefresh.drop_assets(made, regen.assets_of(old_id))
	regen.forget_biome(old_id)
	controller.document.biome_ids = PackedStringArray([runtime_biome_id()])
	apply_now()
	regenerate_all()


## Selects rule `key` ("" clears the selection).
func select_rule(key: String) -> void:
	if key == selected_rule:
		return
	selected_rule = key
	selection_changed.emit(key)


## The rule key that places palette asset `asset_id` in the biome being designed, "" if none.
func rule_of_asset(asset_id: String) -> String:
	for rule: Dictionary in PaletteLibrary.species(runtime_biome_id()):
		if asset_id in rule.get("assets", []):
			return String(rule["key"])
	return ""


## Everything the budget meter needs, from the scatter as it is now: DesignerBudget.estimate's
## result for the proving ground.
func budget() -> Dictionary:
	var made := scatter()
	if made == null:
		return {}
	var held := ScatterRefresh.counts(made)
	var rules := PaletteLibrary.species(runtime_biome_id())
	var biome := PaletteLibrary.biome(runtime_biome_id())
	var triangles := DesignerBudget.triangles_of(biome, model.catalog())
	var area := controller.document.extent_m().x * controller.document.extent_m().y
	return DesignerBudget.estimate(held["counts"], held["cells"], triangles, rules, area)


func _process(delta: float) -> void:
	if _pending:
		_wait -= delta
		if _wait <= 0.0:
			_pending = false
			_apply()
	if state == State.REGENERATING:
		var made := scatter()
		if made == null or not made.is_regenerating():
			_land()
		else:
			progress_changed.emit(state, progress())
	if _ground_pending and not _pending and not _reopening and state != State.REGENERATING:
		_ground_left -= delta
		if _ground_left <= 0.0:
			_ground_pending = false
			_reopen()
	if not _pending and state != State.REGENERATING and not _ground_pending:
		set_process(false)


func _on_model_changed(_reason: String) -> void:
	_edit_usec = Time.get_ticks_usec()
	_pending = true
	_wait = debounce
	var ground := _hash_of_ground()
	if ground != _ground_hash:
		_ground_hash = ground
		_ground_pending = true
		_ground_left = GROUND_DEBOUNCE_SEC
	if state == State.IDLE or state == State.CANCELLED:
		state = State.WAITING
		progress_changed.emit(state, progress())
	set_process(true)


## Rebuilds the open map from its document so the terrain reads the new ground.
func _reopen() -> void:
	_reopening = true
	await controller.reopen_async()
	_reopening = false


## The compile, the lay-over and the request.
func _apply() -> Dictionary:
	var started := Time.get_ticks_usec()
	var result := model.compile()
	var compile_ms := (Time.get_ticks_usec() - started) / 1000.0
	compiled.emit(result)
	_timing = {"compile_ms": compile_ms}
	if not result["ok"]:
		state = State.IDLE
		progress_changed.emit(state, progress())
		return _timing
	var served := Time.get_ticks_usec()
	var report := LibraryRegistry.serve_draft(result["compiled"], model.context)
	_timing["serve_ms"] = (Time.get_ticks_usec() - served) / 1000.0
	if not report["ok"]:
		push_warning("BiomeDesignerSession: %s" % report["error"])
		state = State.IDLE
		return _timing
	var made := scatter()
	if made == null:
		state = State.IDLE
		return _timing
	var asked := Time.get_ticks_usec()
	var info := ScatterRefresh.biome(made, runtime_biome_id(), whole)
	_finish_request(info, asked)
	return _timing


func _finish_request(info: Dictionary, asked_usec: int) -> void:
	_timing["request_ms"] = (Time.get_ticks_usec() - asked_usec) / 1000.0
	_timing.merge(info, true)
	var made := scatter()
	_total_cells = ScatterRefresh.left(made) if made != null else 0
	state = State.REGENERATING if made != null and made.is_regenerating() else State.IDLE
	progress_changed.emit(state, progress())
	if state == State.IDLE:
		_land()
	else:
		set_process(true)


func _land() -> void:
	if state != State.REGENERATING and not (state == State.IDLE and not _timing.is_empty()):
		return
	var total_ms := (Time.get_ticks_usec() - _edit_usec) / 1000.0
	stats = _timing.duplicate()
	stats["total_ms"] = total_ms
	stats["regen_ms"] = (
		total_ms - float(stats.get("compile_ms", 0.0)) - float(stats.get("serve_ms", 0.0))
	)
	state = State.IDLE
	_timing = {}
	_total_cells = 0
	progress_changed.emit(state, progress())
	regenerated.emit(stats)


func _hash_of_ground() -> int:
	var parts := []
	for key in GROUND_KEYS:
		parts.append(model.def.get(key))
	return hash(parts)
