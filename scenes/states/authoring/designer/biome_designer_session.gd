class_name BiomeDesignerSession
extends Node

## The live half of the biome designer (steps S8a and S9): keeps the proving ground in step with
## the draft. Every edit of the BiomeDesignerModel is debounced, compiled (model.compile), laid
## over the palette (LibraryRegistry.serve_draft), and the scatter is regenerated for exactly the
## rules the edit can change (ScatterRefresh.biome, ScatterRegen.replace_biome), so a single-rule
## edit costs a fraction of a whole-map regeneration. A change to the ground (surfaces, accents, the
## look) rebuilds the open map from its document instead (AuthoringController.reopen_async),
## because the terrain reads those at build time. The session reports progress (cells left) and
## can cancel; it measures the time from an edit to the moment the new rows are on the map.
##
## S9: the SEASON on the map (set_season; each season is its own palette biome, so switching it
## regenerates the map for that biome, and rebuilds the proving ground when the seasons differ in
## their ground), the A/B view (`compare`, BiomeDesignerCompare) and the "show only this rule"
## focus (DesignerFocus).
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
## The season on the map changed (the index into the model's seasons).
signal season_changed(index: int)
## The "show only this rule" focus changed (rule key, "" for none).
signal focus_changed(rule_key: String)
## What the ground strip and the look editor write to changed (a season id, "" for every season).
signal edit_target_changed(season: String)

enum State { IDLE, WAITING, REGENERATING, CANCELLED }

## Seconds after the last edit before the draft is compiled (a slider drag settles).
const DEBOUNCE_SEC := 0.12
## The ground rebuild waits longer: it reopens the map.
const GROUND_DEBOUNCE_SEC := 0.6
## Keys of the season's biome-def whose change needs the map rebuilt (the terrain reads the
## ground when the map is built). The ground LOOK is not one: it is baked again in place
## (_refresh_look), which costs one GPU pass instead of a new map.
const GROUND_KEYS: Array[String] = ["ground"]
## The palette biome fields the ground is made of: two seasons that differ in one of them need
## the proving ground built again.
const GROUND_FIELDS: Array[String] = [
	"ground_surface",
	"cliff_surface",
	"scree_surface",
	"water_bed_surface",
	"shore_surface",
	"ground_accents",
	"path_surfaces",
]
## Seconds between two reapplications of the focus while it is on (nodes made by a regeneration).
const FOCUS_INTERVAL_SEC := 0.3

var model: BiomeDesignerModel = null
var controller: AuthoringController = null
## The map the designer draws on (the A/B divider maps screen pixels to the ground through its
## camera); set by the host.
var game_map: GameMap = null
var state: State = State.IDLE
var selected_rule: String = ""
var season_index: int = 0
## The A/B view (BiomeDesignerCompare), off until the header turns it on.
var compare: BiomeDesignerCompare = null
## The rule whose plants alone are shown ("" for all of them).
var focus_rule: String = ""
## Where the ground strip and the look editor write: "" is the biome (every season), a season id
## is that season's own changes.
var edit_season: String = ""
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
var _season_id: String = ""
## The palette biome id the scatter and the document currently work on.
var _laid_id: String = ""
var _focus_wait: float = 0.0
## Hashes of the ground looks of the painted biomes, and of the part the scatter reads (the zone
## shapes), as last laid.
var _look_sig: int = 0
var _zone_sig: int = 0


func _ready() -> void:
	set_process(false)


## Binds the session to its model and the authoring controller whose map it keeps in step.
func setup(designed: BiomeDesignerModel, authoring: AuthoringController) -> void:
	model = designed
	controller = authoring
	compare = BiomeDesignerCompare.new(self)
	_season_id = model.season_ids()[0]
	_laid_id = runtime_biome_id()
	_ground_hash = _hash_of_ground()
	var signatures := _look_signatures()
	_look_sig = signatures[0]
	_zone_sig = signatures[1]
	model.changed.connect(_on_model_changed)


func runtime_biome_id() -> String:
	var ids := model.runtime_ids()
	return ids[clampi(season_index, 0, ids.size() - 1)]


## The id of the season on the map.
func season_id() -> String:
	return model.season_ids()[clampi(season_index, 0, model.season_ids().size() - 1)]


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
	if compare.active:
		var other := ScatterRefresh.biome(made, compare.reference_runtime(), true)
		info["cells"] = int(info.get("cells", 0)) + int(other.get("cells", 0))
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


## Switches the season the proving ground shows (each season is a palette biome of its own: the
## map regenerates for it, and is built again when the seasons differ in their ground).
func set_season(index: int) -> void:
	var count := model.season_ids().size()
	var next := clampi(index, 0, count - 1)
	if next == season_index:
		return
	season_index = next
	_season_id = season_id()
	_ground_hash = _hash_of_ground()
	if edit_season != "":
		set_edit_season(_season_id)  # Editing "this season only" follows the scrub.
	if compare.active and runtime_biome_id() == compare.reference_runtime():
		compare.stop()  # The reference would be the draft itself.
	season_changed.emit(season_index)
	if controller != null and controller.document != null:
		apply_now()


## Points the ground strip and the look editor at season `id` ("" for every season).
func set_edit_season(id: String) -> void:
	var wanted := id if id in model.season_ids() else ""
	if wanted == edit_season:
		return
	edit_season = wanted
	edit_target_changed.emit(edit_season)


## Selects rule `key` ("" clears the selection).
func select_rule(key: String) -> void:
	if key == selected_rule:
		return
	selected_rule = key
	selection_changed.emit(key)


## Shows only rule `key`'s plants on the map ("" shows all of them again).
func set_focus(key: String) -> void:
	if key == focus_rule:
		return
	focus_rule = key
	_apply_focus()
	set_process(true)
	focus_changed.emit(key)


## The rule key that places palette asset `asset_id` in the biome being designed, "" if none.
func rule_of_asset(asset_id: String) -> String:
	for rule: Dictionary in PaletteLibrary.species(runtime_biome_id()):
		if asset_id in rule.get("assets", []):
			return String(rule["key"])
	return ""


## Everything the budget meter needs, from the scatter as it is now: DesignerBudget.estimate's
## result for the proving ground. In the A/B view only the draft's plants count, over the share
## of the map they stand on.
func budget() -> Dictionary:
	var made := scatter()
	if made == null:
		return {}
	var held := ScatterRefresh.counts(made)
	var rules := PaletteLibrary.species(runtime_biome_id())
	var biome := PaletteLibrary.biome(runtime_biome_id())
	var triangles := DesignerBudget.triangles_of(biome, model.catalog())
	var area := controller.document.extent_m().x * controller.document.extent_m().y
	var counts: Dictionary = held["counts"]
	var cells: Dictionary = held["cells"]
	if compare.active:
		counts = _only_assets_of(counts, rules)
		cells = _only_assets_of(cells, rules)
		area *= compare.draft_share()
	return DesignerBudget.estimate(counts, cells, triangles, rules, area)


## Called by the A/B view and the season switch with the info of a regeneration request they made.
func begin_request(info: Dictionary, asked_usec: int) -> void:
	_edit_usec = asked_usec
	_timing = {"compile_ms": 0.0, "serve_ms": 0.0}
	_finish_request(info, asked_usec)


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
	if compare != null and compare.active:
		compare.tick(delta)
	if focus_rule != "":
		_focus_wait -= delta
		if _focus_wait <= 0.0:
			_focus_wait = FOCUS_INTERVAL_SEC
			_apply_focus()
	var comparing := compare != null and compare.active
	if (
		not _pending
		and state != State.REGENERATING
		and not _ground_pending
		and focus_rule == ""
		and not comparing
	):
		set_process(false)


func _on_model_changed(_reason: String) -> void:
	_edit_usec = Time.get_ticks_usec()
	_pending = true
	_wait = debounce
	_follow_season()
	var ground := _hash_of_ground()
	if ground != _ground_hash:
		_ground_hash = ground
		_ground_pending = true
		_ground_left = GROUND_DEBOUNCE_SEC
	if state == State.IDLE or state == State.CANCELLED:
		state = State.WAITING
		progress_changed.emit(state, progress())
	set_process(true)


## Keeps `season_index` on the season it named when seasons are added, removed or reordered by an
## edit (a season that went falls back to the first).
func _follow_season() -> void:
	var ids := model.season_ids()
	var at := ids.find(_season_id)
	if at < 0:
		at = 0
		_season_id = ids[0]
	if at != season_index:
		season_index = at
		season_changed.emit(season_index)
	if edit_season != "" and not edit_season in ids:
		set_edit_season("")


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
	if runtime_biome_id() != _laid_id:
		_switch_biome(_laid_id)
		return _timing
	var zones_moved := _refresh_look()
	var asked := Time.get_ticks_usec()
	var everything := whole or zones_moved
	var info := ScatterRefresh.biome(made, runtime_biome_id(), everything)
	if compare.follows_draft():
		var other := ScatterRefresh.biome(made, compare.reference_runtime(), everything)
		info["species"] = int(info.get("species", 0)) + int(other.get("species", 0))
		info["cells"] = int(info.get("cells", 0)) + int(other.get("cells", 0))
	_finish_request(info, asked)
	return _timing


## Bakes the ground look again when a painted biome's look changed since the last time (one GPU
## pass over the map, GroundLookBake.sync; the grass binds the new tuft and mass colours). Returns
## true when the zone shapes the scatter reads moved too, so the plants that stand on them are
## generated again.
func _refresh_look() -> bool:
	var signatures := _look_signatures()
	if signatures[0] == _look_sig:
		return false
	var moved: bool = signatures[1] != _zone_sig
	_look_sig = signatures[0]
	_zone_sig = signatures[1]
	var editor := controller.editor
	if editor != null and is_instance_valid(editor.terrain):
		var started := Time.get_ticks_usec()
		editor.terrain.refresh_ground_look()
		_timing["look_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	return moved


## [hash of the painted biomes' ground looks, hash of the zone shapes the scatter reads of them].
func _look_signatures() -> Array[int]:
	var looks := []
	var zones := []
	for id in compare.ids():
		var look := PaletteLibrary.ground_look(id)
		looks.append(look)
		zones.append(GroundZones.record(look, 0))
	return [hash(looks), hash(zones)]


## The map goes from palette biome `old_id` to the biome of the season now chosen (or whose seed
## changed): the old biome's plants and rules go, the document paints the new one, and the proving
## ground is built again when the two differ in their ground.
func _switch_biome(old_id: String) -> void:
	var made := scatter()
	var regen := made.get_regen()
	ScatterRefresh.drop_assets(made, regen.assets_of(old_id))
	regen.forget_biome(old_id)
	_laid_id = runtime_biome_id()
	if _ground_differs(old_id, _laid_id):
		_rebuild_proving_ground()
		return
	controller.document.biome_ids = compare.ids()
	var editor := controller.editor
	if editor != null and is_instance_valid(editor.terrain):
		editor.terrain.update_ground_region(
			Rect2i(0, 0, controller.document.samples_x(), controller.document.samples_z())
		)
	regenerate_all()


## Opens a fresh proving ground for the biome now laid (the seasons differ in their ground), in
## the A/B painting when that view is on, and generates the plants on it.
func _rebuild_proving_ground() -> void:
	_reopening = true
	var doc := ProvingGround.build(_laid_id)
	if doc == null:
		_reopening = false
		return
	if compare.active:
		compare.paint_document(doc)
	await controller.reopen_async(doc)
	_reopening = false
	_ground_hash = _hash_of_ground()
	_ground_pending = false
	if not is_instance_valid(scatter()):
		return
	regenerate_all()


func _ground_differs(a: String, b: String) -> bool:
	var first := PaletteLibrary.biome(a)
	var second := PaletteLibrary.biome(b)
	for field in GROUND_FIELDS:
		if first.get(field) != second.get(field):
			return true
	return false


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
	if focus_rule != "":
		_apply_focus()


func _apply_focus() -> void:
	var made := scatter()
	if made == null:
		return
	if focus_rule == "":
		DesignerFocus.apply(made, null)
	else:
		DesignerFocus.apply(made, DesignerFocus.assets_of_rule(runtime_biome_id(), focus_rule))


## The part of `by_asset` ({asset id: n}) the draft's `rules` place.
func _only_assets_of(by_asset: Dictionary, rules: Array) -> Dictionary:
	var out := {}
	for rule: Dictionary in rules:
		for asset_id: String in rule.get("assets", []):
			if by_asset.has(asset_id):
				out[asset_id] = by_asset[asset_id]
	return out


## What the terrain has to rebuild for: the season's ground, accents, paths and look as the
## compiler reads them.
func _hash_of_ground() -> int:
	var effective := BiomeSeasons.effective(model.def, _season_id)
	var parts := []
	for key in GROUND_KEYS:
		parts.append(effective.get(key))
	return hash(parts)
