class_name GroundClipmap
extends Node

## The ground clipmap on an authored map (card clipmap1, behind a flag; design and numbers:
## docs/systems/ground_clipmap.md and docs/plans/handoffs/clipmap1.md). AuthoredTerrain owns one,
## as a child, while AuthoredTerrain.set_clipmap(true) is on. The geometry (levels, tiles, the
## next strip) is GroundClipmapPlan; the shader's read is CLIPMAP in authored_ground.gdshaderinc.
##
## It bakes the layer-blended ground top-down into a pyramid of toroidal windows (two RGBA8
## textures each: lit albedo + AO, then normal + roughness) and binds them to the map's ground
## material; the ground shader reads them where a level covers a pixel and keeps the layer blend
## elsewhere. Windows are written a strip at a time: a strip viewport renders the chunk meshes
## (the real ground shader, GROUND_BAKE_OUT, a copy of the map's material) over one column or row
## of tiles, and the next frame a 2D draw copies it into the level's window (CLEAR_MODE_NEVER,
## blend off, so the strip overwrites whatever the slot held). One strip per two frames, coarsest
## level first, so a fresh map is covered top-down within a second and a pan only pays for the
## tiles that enter. A level's rectangle of baked tiles reaches the shader one frame after its
## window is drawn.
##
## Levels exist only from the finest one the view needs (from the screen's texels per metre, read
## every frame) up to the map's coarsest; a level the view stopped needing goes after
## RELEASE_S. The bake follows the ground. A brush or zone edit (AuthoredTerrain.ground_edited)
## marks its rectangle: at once the ground shader draws the layer blend inside it (clip_hole, the
## live ground, so the edit shows in the next frame), and once the edit has been quiet for
## EDIT_QUIET_S the strips over the tiles it touched are rebaked (patch_jobs) and the hole
## closes. A palette or look change, or anything else that changes the ground material, rebakes
## every level (invalidate()).

const NODE_NAME := "GroundClipmap"
const BAKE_SHADER := preload("res://shaders/authored_ground_bake.gdshader")
const BAKE_LOOKED_SHADER := preload("res://shaders/authored_ground_bake_looked.gdshader")
## The strip copy: a 2D draw with blending off (an overwrite).
const BLIT_SHADER := preload("res://shaders/ground_clipmap_blit.gdshader")
## The map ground with the clipmap's read compiled in, plain and looked.
const CLIP_SHADER := preload("res://shaders/authored_ground_clip.gdshader")
const CLIP_LOOKED_SHADER := preload("res://shaders/authored_ground_clip_looked.gdshader")
## Seconds a level stays after the view stopped needing it.
const RELEASE_S := 4.0
## Seconds the ground must stay unchanged before a rebake starts (a look's uniforms bind a frame
## after its bake).
const SETTLE_S := 0.4
## Seconds an edited rectangle must stay unedited (and the terrain's height work done) before its
## tiles rebake; a stroke's dabs keep the hole open and are rebaked once.
const EDIT_QUIET_S := 0.25
## Metres the hole grows past an edit (a sample step is added): the bake's filtering reaches.
const HOLE_PAD_M := 0.15
## Edits covering this share of the grid or more rebake everything.
const WHOLE_SHARE := 0.5
## Bytes of one level: two RGBA8 windows.
const LEVEL_BYTES := 2 * GroundClipmapPlan.WINDOW_PX * GroundClipmapPlan.WINDOW_PX * 4
## The command-line flags that turn the clipmap on and off for a run (on in authoring too).
const FLAG := "--ground-clipmap"
const NO_FLAG := "--no-ground-clipmap"
## Whether a map the player plays gets the clipmap without a flag (the Ground detail setting,
## GroundClipmapSetting, can still turn it off). Authoring never does: the editor needs the
## live ground, and the clipmap there is only for tests (FLAG).
const ON_BY_DEFAULT := false

var terrain: AuthoredTerrain = null
## Kept in authoring and with Ground detail off (a render job or a test attached it).
var forced: bool = false
## Whether the map's ground reads the windows (the clip shader) or draws the layer blend as ever;
## a measurement toggles it while the windows stay baked.
var read: bool = true:
	set(value):
		read = value
		_sync_shader()
## Strips baked since the node was made, and the cost of the last one's submission (usec).
var jobs_done: int = 0
var last_job_usec: int = 0
## Bumped when the ground changed and every level is being rebaked.
var rebakes: int = 0
## With measure on, the GPU milliseconds the last strip cost (its two strip viewports and two
## window draws), the sum over all strips, and the part read in this frame (0 in most frames).
var measure: bool = false:
	set(value):
		measure = value
		_measure_all()
var last_job_ms: float = 0.0
var bake_ms_total: float = 0.0
var frame_bake_ms: float = 0.0
## Edits rebaked in part (hole closed), the msec the last one took from the edit to the closed
## hole, and a measurement switch that keeps the hole open (the stale windows show).
var patches_done: int = 0
var last_patch_msec: int = 0
var hole_off: bool = false:
	set(value):
		hole_off = value
		_bind_hole()

var _dirty := Rect2()  # map-frame metres, valid while _has_dirty
var _has_dirty: bool = false
var _dirty_quiet: float = 0.0
var _dirty_since_msec: int = 0
var _patch: Array = []  # of {level, job} waiting
var _patching: bool = false
var _blit_material := ShaderMaterial.new()
var _levels: Array = []  # of Level, null where the level is not held
var _strips: Array = []  # [kind][pass] -> SubViewport
var _bake_mats: Array[ShaderMaterial] = []
var _copies: Array = []  # of MeshInstance3D in the strip viewports
var _signature: Array = []
var _settle: float = 0.0
var _stage: int = 0  # 0 idle, 1 a strip is drawing, 2 a window is drawing
var _job: Dictionary = {}
var _job_level: int = -1
var _commit_level: int = -1
var _bind_dirty: bool = true
var _top: int = 0
var _map_extent: float = 0.0
var _finest: int = 0
var _cam_y: float = 100.0
var _focus := Vector2.ZERO
var _px_per_m: float = 0.0


## One held level: its two window viewports, the tiles baked and the block it is heading for.
class Level:
	extends RefCounted
	var index: int = 0
	var is_static: bool = false
	var windows: Array[SubViewport] = []
	var sprites: Array = []  # [pass] -> [Sprite2D, Sprite2D]
	var valid := Rect2i()
	var target := Rect2i()
	var unused_s: float = 0.0


## True when a terrain being built gets a clipmap: the command line asks (FLAG), or it is on by
## default and the Ground detail setting is not Off (NO_FLAG says no either way).
static func flag_on() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has(FLAG):
		return true
	if args.has(NO_FLAG):
		return false
	return ON_BY_DEFAULT and GroundClipmapSetting.current != GroundClipmapSetting.OFF


## The clipmap of `terrain`, or null while it has none.
static func of(terrain_node: AuthoredTerrain) -> GroundClipmap:
	return terrain_node.get_node_or_null(NODE_NAME) as GroundClipmap


## Gives `terrain_node` a clipmap (the existing one if it has one); null on a headless run, which
## has no renderer to bake with.
static func attach(terrain_node: AuthoredTerrain, forced: bool = false) -> GroundClipmap:
	if DisplayServer.get_name() == "headless":
		return null
	var existing := of(terrain_node)
	if existing != null:
		return existing
	var made := GroundClipmap.new()
	made.terrain = terrain_node
	made.forced = forced
	terrain_node.add_child(made)
	return made


## Takes the clipmap off `terrain_node`: the plain shaders return and the windows are freed.
static func detach(terrain_node: AuthoredTerrain) -> void:
	var existing := of(terrain_node)
	if existing != null:
		existing.free()


## Bytes of GPU memory `levels` windows hold.
static func memory_bytes(levels: int) -> int:
	return levels * LEVEL_BYTES


func _ready() -> void:
	name = NODE_NAME
	_blit_material.shader = BLIT_SHADER
	_levels.resize(GroundClipmapPlan.CLIP_LEVELS)
	_levels.fill(null)
	_invalidate_state()
	if terrain != null and not terrain.ground_edited.is_connected(_on_edited):
		terrain.ground_edited.connect(_on_edited)


func _exit_tree() -> void:
	if terrain != null and is_instance_valid(terrain):
		terrain.ground_edited.disconnect(_on_edited)
	_unbind()
	read = false


## True when this clipmap should not run: the player turned Ground detail off, or the map is in
## authoring (a GameMap with authoring_mode, found up the tree), unless the command line forced
## the clipmap on.
func _suppressed() -> bool:
	if forced or OS.get_cmdline_user_args().has(FLAG):
		return false
	if GroundClipmapSetting.current == GroundClipmapSetting.OFF:
		return true
	var node: Node = terrain
	while node != null:
		if node.has_method("setup_authoring"):
			return bool(node.get("authoring_mode"))
		node = node.get_parent()
	return false


## The map ground's shader for the look and `read`: the clip variant while it reads the windows,
## else the plain one (AuthoredTerrain.set_looked puts the plain ones back on a look change, so
## this runs every frame).
func _sync_shader() -> void:
	if terrain == null or not is_instance_valid(terrain):
		return
	var mat := terrain.get_material()
	if mat == null:
		return
	if mat.shader != null and mat.shader.resource_path.is_empty():
		return  # a measurement's own shader (the render-job rig); leave it
	var looked := terrain.is_looked()
	var want: Shader = AuthoredTerrain.ground_shader(false, looked)
	if read:
		want = CLIP_LOOKED_SHADER if looked else CLIP_SHADER
	if mat.shader != want:
		mat.shader = want


## Rebakes everything once the ground has settled (the caller edited what the bake read).
func invalidate() -> void:
	_signature = []
	_settle = SETTLE_S


## The levels held, finest first.
func held_levels() -> Array[int]:
	var out: Array[int] = []
	for l in _levels.size():
		if _levels[l] != null:
			out.append(l)
	return out


## The baked rectangle of level `l` in tiles (empty before anything is baked).
func valid_tiles(l: int) -> Rect2i:
	var lv: Level = _levels[l]
	return lv.valid if lv != null else Rect2i()


## True when every held level is fully baked and nothing is drawing.
func is_settled() -> bool:
	if _stage != 0 or _settle > 0.0 or _has_dirty:
		return false
	for lv: Level in _levels:
		if lv != null and (lv.valid != lv.target or lv.target.size.x <= 0):
			return false
	return true


func _process(delta: float) -> void:
	if terrain == null or terrain.document == null or terrain.get_material() == null:
		return
	if Engine.get_process_frames() % 30 == 0 and _suppressed():
		queue_free()
		return
	_sync_shader()
	frame_bake_ms = 0.0
	if _stage == 2:
		_finish_window()
	elif _stage == 1:
		_blit()
		return
	_watch_ground(delta)
	if not _view():
		return
	_hold_levels(delta)
	if _settle > 0.0:
		return
	_retarget()
	_tick_edit(delta)
	if _bind_dirty:
		_bind()
	_start_job()


# ---- the ground the bake reads ----


## A signature of what the bake reads; when it changes the levels are emptied and rebuilt after
## the ground has stayed still for SETTLE_S.
func _watch_ground(delta: float) -> void:
	var mat := terrain.get_material()
	var chunks := 0
	for cell in terrain.chunk_cells():
		var mi := terrain.get_chunk(cell)
		if mi != null and mi.mesh != null:
			chunks += 1
	var look := terrain.ground_look()
	# Brush, zone and sculpt edits are not in it: they arrive as ground_edited rectangles (a
	# rebuilt chunk is a new mesh, which a patch picks up; the count changes while a map loads).
	var sig: Array = [
		mat.get_instance_id(),
		chunks,
		look.bakes if look != null else -1,
		mat.get_shader_parameter("look_present"),
	]
	if sig != _signature:
		_signature = sig
		_settle = SETTLE_S
		_clear_edit()
		_invalidate_state()
		return
	if _settle > 0.0:
		_settle -= delta
		if _settle <= 0.0:
			_settle = 0.0
			_rebuild_strips()
			rebakes += 1


func _invalidate_state() -> void:
	_stage = 0
	_job = {}
	for lv: Level in _levels:
		if lv != null:
			lv.valid = Rect2i()
	_bind_dirty = true


# ---- edits ----


## An edit of the grid samples `rect` (AuthoredTerrain.ground_edited): the ground shows the live
## blend over its rectangle from now on and the tiles under it rebake once it has been quiet.
func _on_edited(rect: Rect2i) -> void:
	var doc := terrain.document
	if doc == null or not rect.has_area():
		return
	var share := float(rect.get_area()) / float(maxi(doc.samples_x() * doc.samples_z(), 1))
	if share >= WHOLE_SHARE:
		invalidate()
		return
	var step := doc.sample_step()
	var world := MaskBrush.sample_rect_to_world(doc, rect).grow(maxf(step.x, step.y) + HOLE_PAD_M)
	if not _has_dirty:
		_dirty_since_msec = Time.get_ticks_msec()
	_dirty = _dirty.merge(world) if _has_dirty else world
	_has_dirty = true
	_patch.clear()
	_patching = false
	_dirty_quiet = EDIT_QUIET_S
	_bind_hole()


## Forgets the marked edit: a whole rebake follows or the ground is gone.
func _clear_edit() -> void:
	_has_dirty = false
	_patch.clear()
	_patching = false
	_bind_hole()


## Counts the quiet after the last edit (not while the terrain still moves chunks) and then
## plans the patch strips.
func _tick_edit(delta: float) -> void:
	if not _has_dirty or _patching:
		return
	if terrain.has_height_work() or terrain.has_unsettled_chunks():
		_dirty_quiet = EDIT_QUIET_S
		return
	_dirty_quiet -= delta
	if _dirty_quiet > 0.0:
		return
	_sync_bake_inputs()
	for l in GroundClipmapPlan.CLIP_LEVELS:
		var lv: Level = _levels[l]
		if lv == null:
			continue
		for job in GroundClipmapPlan.patch_jobs(l, lv.target, lv.valid, _dirty):
			_patch.append({"level": l, "job": job})
	_patching = true


## Brings the strips' copies of the ground up to the live one: the uniforms of the map's
## material (its textures are shared, but arrays and scalars were copied) and the chunks' current
## meshes (a rebuilt chunk is a new mesh).
func _sync_bake_inputs() -> void:
	var source := terrain.get_material()
	if source == null or source.shader == null:
		return
	for u: Dictionary in source.shader.get_shader_uniform_list():
		var uniform_name := String(u.name)
		if uniform_name.begins_with("clip_") or uniform_name == "bake_pass":
			continue
		var value: Variant = source.get_shader_parameter(uniform_name)
		for mat in _bake_mats:
			mat.set_shader_parameter(uniform_name, value)
	for mi: MeshInstance3D in _copies:
		var src := terrain.get_chunk(mi.get_meta("cell"))
		if src != null and src.mesh != null and mi.mesh != src.mesh:
			mi.mesh = src.mesh


## The patch's last strip is baked: the windows hold the live ground, so the hole closes.
func _end_patch() -> void:
	patches_done += 1
	last_patch_msec = Time.get_ticks_msec() - _dirty_since_msec
	_clear_edit()


## The hole as the shader's uniform (empty with no edit pending, or while hole_off).
func _bind_hole() -> void:
	var mat := terrain.get_material() if terrain != null else null
	if mat == null:
		return
	var hole := Vector4(1.0e9, 1.0e9, -1.0e9, -1.0e9)
	if _has_dirty and not hole_off:
		hole = Vector4(_dirty.position.x, _dirty.position.y, _dirty.end.x, _dirty.end.y)
	mat.set_shader_parameter("clip_hole", hole)


# ---- the view ----


## The focus on the ground (map frame, metres) and the screen's texels per metre there; false
## without a camera. The densest ground is at the bottom of the screen, so the finer of two rays.
func _view() -> bool:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return false
	var rect := vp.get_visible_rect()
	var heights := terrain.height_range()
	var y_ref := (heights.x + heights.y) * 0.5
	_cam_y = heights.y + 60.0
	var to_local := terrain.global_transform.affine_inverse()
	var best := 0.0
	var found := false
	for frac in [0.5, 0.9]:
		var at := Vector2(rect.size.x * 0.5, rect.size.y * frac)
		var from := to_local * cam.project_ray_origin(at)
		var dir := (to_local.basis * cam.project_ray_normal(at)).normalized()
		if absf(dir.y) < 1e-4:
			continue
		var t := (y_ref - from.y) / dir.y
		if t <= 0.0:
			continue
		var p := from + dir * t
		if not found:
			_focus = Vector2(p.x, p.z)
			found = true
		var world_p := terrain.to_global(p)
		var flat := Vector3(dir.x, 0.0, dir.z)
		if flat.length() < 1e-4:
			continue
		var right := terrain.global_transform.basis * flat.normalized().cross(Vector3.UP)
		var c := cam.unproject_position(world_p)
		var across := cam.unproject_position(world_p + right.normalized() * 0.5).distance_to(c) * 2.0
		best = maxf(best, across)
	_px_per_m = best
	return found


func _hold_levels(delta: float) -> void:
	var ext := terrain.document.extent_m()
	_map_extent = maxf(ext.x, ext.y)
	_top = GroundClipmapPlan.top_level(_map_extent)
	_finest = GroundClipmapPlan.finest_level(_px_per_m, _top)
	var cap := GroundClipmapSetting.current
	if cap > 0:
		_finest = maxi(_finest, _top - cap + 1)  # the setting's level cap: the sharpest go first
	for l in GroundClipmapPlan.CLIP_LEVELS:
		var wanted := l >= _finest and l <= _top
		var lv: Level = _levels[l]
		if wanted:
			if lv == null:
				_levels[l] = _make_level(l)
				_bind_dirty = true
				if measure:
					_measure_all()
			else:
				lv.unused_s = 0.0
		elif lv != null:
			lv.unused_s += delta
			if lv.unused_s >= RELEASE_S:
				_free_level(l)
				_bind_dirty = true


func _retarget() -> void:
	for l in GroundClipmapPlan.CLIP_LEVELS:
		var lv: Level = _levels[l]
		if lv == null:
			continue
		var target: Rect2i
		if lv.is_static:
			target = GroundClipmapPlan.static_block(l, Vector2.ZERO)
		else:
			target = GroundClipmapPlan.target_block(l, _focus, lv.target)
		if target != lv.target:
			lv.target = target
			var kept := GroundClipmapPlan.clip_valid(lv.valid, target)
			if kept != lv.valid:
				lv.valid = kept
				_bind_dirty = true


# ---- strips ----


## The next strip: the coarsest incomplete level first, so the map is always covered by the
## widest level before the finer ones fill.
func _start_job() -> void:
	if _strips.is_empty():
		_rebuild_strips()
		if _strips.is_empty():
			return
	for l in range(GroundClipmapPlan.CLIP_LEVELS - 1, -1, -1):
		var lv: Level = _levels[l]
		if lv == null:
			continue
		var job := GroundClipmapPlan.next_job(lv.valid, lv.target)
		if job.is_empty():
			continue
		_job = job
		_job_level = l
		_render_strip(l, job)
		_stage = 1
		return
	if _patching:
		_start_patch_job()


## The next strip of the edit's patch; a strip whose tile left the window (the block moved) or
## was never baked is dropped. The patch ends with its last strip.
func _start_patch_job() -> void:
	while not _patch.is_empty():
		var item: Dictionary = _patch.pop_front()
		var lv: Level = _levels[item.level]
		var job: Dictionary = item.job
		if lv == null or lv.valid.size.x <= 0 or lv.valid.size.y <= 0:
			continue
		var tile: int = job.tile
		var column: bool = job.kind == GroundClipmapPlan.Kind.COLUMN
		var inside := (
			tile >= lv.valid.position.x and tile < lv.valid.end.x
			if column
			else tile >= lv.valid.position.y and tile < lv.valid.end.y
		)
		var along: int = lv.target.position.y if column else lv.target.position.x
		if not inside or job.span != along:
			continue
		job.after = lv.valid
		_job = job
		_job_level = item.level
		_render_strip(_job_level, job)
		_stage = 1
		return
	_end_patch()


func _render_strip(l: int, job: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	var kind: int = job.kind
	var rect := GroundClipmapPlan.strip_rect(l, kind, job.tile, job.span)
	var centre := rect.get_center()
	for p in 2:
		var vp: SubViewport = _strips[kind][p]
		var cam := vp.get_child(0) as Camera3D
		cam.size = rect.size.y
		cam.position = Vector3(centre.x, _cam_y, centre.y)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	last_job_usec = Time.get_ticks_usec() - started


## The strip is drawn: copy it into the level's two windows.
func _blit() -> void:
	var lv: Level = _levels[_job_level]
	if lv == null:
		_stage = 0
		return
	var kind: int = _job.kind
	if measure:
		# The strips drew last frame; a timing is only readable the frame after its draw.
		last_job_ms = 0.0
		for vp: SubViewport in _strips[kind]:
			last_job_ms += _gpu_ms(vp)
		frame_bake_ms += last_job_ms
		bake_ms_total += last_job_ms
	var pieces := GroundClipmapPlan.blits(kind, _job.tile, _job.span)
	for p in 2:
		var tex: Texture2D = (_strips[kind][p] as SubViewport).get_texture()
		var pair: Array = lv.sprites[p]
		for i in 2:
			var sprite: Sprite2D = pair[i]
			sprite.visible = i < pieces.size()
			if sprite.visible:
				sprite.texture = tex
				sprite.region_rect = Rect2(pieces[i].src)
				sprite.position = Vector2(pieces[i].dst)
		lv.windows[p].render_target_update_mode = SubViewport.UPDATE_ONCE
	_commit_level = _job_level
	_stage = 2


## The windows were drawn last frame: the strip's tiles count as baked.
func _finish_window() -> void:
	_stage = 0
	var lv: Level = _levels[_commit_level] if _commit_level >= 0 else null
	if measure and lv != null and not _job.is_empty():
		# The windows drew last frame (the strips the frame before, read in _blit).
		var ms := 0.0
		for vp: SubViewport in lv.windows:
			ms += _gpu_ms(vp)
		last_job_ms += ms
		frame_bake_ms += ms
		bake_ms_total += ms
	if lv != null and not _job.is_empty():
		lv.valid = GroundClipmapPlan.clip_valid(_job.after, lv.target)
		# The job's after was computed from the valid rectangle when it started; a retarget since
		# may have cut it, and clip_valid keeps it inside the block.
		_bind_dirty = true
		jobs_done += 1
	_job = {}
	_commit_level = -1


# ---- levels, viewports, materials ----


func _gpu_ms(vp: SubViewport) -> float:
	return RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())


## Measurement only: draws every strip and window each frame (or stops), so their GPU times
## read out; a viewport drawn once never has its timing collected by the renderer. The windows
## repeat their last blit, the strips their last camera.
func hold_drawing(on: bool) -> void:
	measure = on
	var mode := SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	for lv: Level in _levels:
		if lv != null:
			for vp in lv.windows:
				vp.render_target_update_mode = mode
	for pair: Array in _strips:
		for vp: SubViewport in pair:
			vp.render_target_update_mode = mode


## Measurement only: points the `kind` strip cameras at the centre column (or row) of level `l`'s
## block, a full-length strip. The world rectangle it shows is strip_world_rect().
func place_strip(l: int, kind: int) -> void:
	var lv: Level = _levels[l]
	if lv == null or _strips.is_empty():
		return
	var rect := strip_world_rect(l, kind)
	for vp: SubViewport in _strips[kind]:
		var cam := vp.get_child(0) as Camera3D
		cam.size = rect.size.y
		cam.position = Vector3(rect.get_center().x, _cam_y, rect.get_center().y)


## The world rectangle (metres) of the centre strip of `kind` on level `l` (empty if not held).
func strip_world_rect(l: int, kind: int) -> Rect2:
	var lv: Level = _levels[l]
	if lv == null:
		return Rect2()
	var half := Vector2i(GroundClipmapPlan.TILES / 2, GroundClipmapPlan.TILES / 2)
	var centre := lv.target.position + half
	if kind == GroundClipmapPlan.Kind.COLUMN:
		return GroundClipmapPlan.strip_rect(l, kind, centre.x, lv.target.position.y)
	return GroundClipmapPlan.strip_rect(l, kind, centre.y, lv.target.position.x)


## The measured GPU ms of the held drawing: {column: both passes of a column strip, row: the
## same for a row strip, windows: all levels' windows}. Needs hold_drawing(true) for a few frames.
func drawing_cost_ms() -> Dictionary:
	var cost := {"column": 0.0, "row": 0.0, "windows": 0.0}
	for kind in _strips.size():
		for vp: SubViewport in _strips[kind]:
			cost["column" if kind == GroundClipmapPlan.Kind.COLUMN else "row"] += _gpu_ms(vp)
	for lv: Level in _levels:
		if lv != null:
			for vp in lv.windows:
				cost["windows"] += _gpu_ms(vp)
	return cost


## Switches GPU timing on every viewport the node owns (measure).
func _measure_all() -> void:
	for lv: Level in _levels:
		if lv != null:
			for vp in lv.windows:
				RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), measure)
	for pair: Array in _strips:
		for vp: SubViewport in pair:
			RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), measure)


func _make_level(l: int) -> Level:
	var lv := Level.new()
	lv.index = l
	lv.is_static = GroundClipmapPlan.is_static(l, _map_extent) and l == _top
	for p in 2:
		var vp := SubViewport.new()
		vp.name = "ClipL%dP%d" % [l, p]
		vp.size = Vector2i(GroundClipmapPlan.WINDOW_PX, GroundClipmapPlan.WINDOW_PX)
		vp.disable_3d = true
		vp.transparent_bg = true
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		var pair: Array = []
		for i in 2:
			var sprite := Sprite2D.new()
			sprite.centered = false
			sprite.region_enabled = true
			sprite.visible = false
			sprite.material = _blit_material
			vp.add_child(sprite)
			pair.append(sprite)
		lv.sprites.append(pair)
		add_child(vp)
		lv.windows.append(vp)
	return lv


func _free_level(l: int) -> void:
	var lv: Level = _levels[l]
	if lv == null:
		return
	for vp in lv.windows:
		vp.queue_free()
	_levels[l] = null
	if _job_level == l:
		_stage = 0
		_job = {}


## The strip viewports (column and row, pass 0 and 1) with a copy of every chunk and a copy of
## the map's ground material on the bake shader. Rebuilt whenever the ground changes, since the
## copies snapshot the material's uniforms.
func _rebuild_strips() -> void:
	for kind_vps: Array in _strips:
		for vp: SubViewport in kind_vps:
			vp.queue_free()
	_strips.clear()
	_bake_mats.clear()
	_copies.clear()
	var source := terrain.get_material()
	if source == null:
		return
	var look_present: Variant = source.get_shader_parameter("look_present")
	var looked: bool = look_present != null and int(look_present) != 0
	var shader: Shader = BAKE_LOOKED_SHADER if looked else BAKE_SHADER
	for p in 2:
		var mat := source.duplicate() as ShaderMaterial
		mat.shader = shader
		mat.render_priority = 0
		mat.set_shader_parameter("bake_pass", p)
		_bake_mats.append(mat)
	var px := GroundClipmapPlan.TILE_PX
	var long_px := GroundClipmapPlan.WINDOW_PX
	for kind in 2:
		var size := Vector2i(long_px, px)
		if kind == GroundClipmapPlan.Kind.COLUMN:
			size = Vector2i(px, long_px)
		var pair: Array = []
		for p in 2:
			var vp := SubViewport.new()
			vp.name = "ClipStrip%d%d" % [kind, p]
			vp.own_world_3d = true
			vp.size = size
			vp.transparent_bg = true
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.use_taa = false
			vp.use_debanding = false
			vp.positional_shadow_atlas_size = 0
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			var cam := Camera3D.new()
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.keep_aspect = Camera3D.KEEP_HEIGHT
			cam.near = 0.05
			cam.far = 400.0
			cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			var env := Environment.new()
			env.background_mode = Environment.BG_CLEAR_COLOR
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
			env.tonemap_exposure = 1.0
			cam.environment = env
			vp.add_child(cam)
			for cell in terrain.chunk_cells():
				var src := terrain.get_chunk(cell)
				if src == null or src.mesh == null:
					continue
				var mi := MeshInstance3D.new()
				mi.mesh = src.mesh
				mi.material_override = _bake_mats[p]
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				vp.add_child(mi)
				mi.set_meta("cell", cell)
				_copies.append(mi)
			add_child(vp)
			cam.current = true
			pair.append(vp)
		_strips.append(pair)
	for lv: Level in _levels:
		if lv != null:
			lv.valid = Rect2i()
	_bind_dirty = true
	if measure:
		_measure_all()


# ---- the ground material ----


## Hands the windows, the baked rectangles and the level constants to the map's ground material.
func _bind() -> void:
	_bind_dirty = false
	var mat := terrain.get_material()
	if mat == null:
		return
	var bounds := Rect2(-terrain.document.extent_m() * 0.5, terrain.document.extent_m())
	var valid := PackedVector4Array()
	var info := PackedVector4Array()
	for l in GroundClipmapPlan.CLIP_LEVELS:
		var lv: Level = _levels[l]
		var tile := GroundClipmapPlan.tile_m(l)
		var texel := 1.0 / GroundClipmapPlan.density(l)
		if lv == null:
			valid.append(GroundClipmapPlan.valid_rect_m(l, Rect2i(), Rect2()))
			info.append(Vector4(1.0 / GroundClipmapPlan.extent_m(l), tile, 0.0, 0.0))
			mat.set_shader_parameter("clip_a%d" % l, null)
			mat.set_shader_parameter("clip_b%d" % l, null)
			continue
		valid.append(GroundClipmapPlan.valid_rect_m(l, lv.valid, bounds if lv.is_static else Rect2()))
		var fade := texel if lv.is_static else tile * 0.5
		info.append(Vector4(1.0 / GroundClipmapPlan.extent_m(l), fade, texel * 2.0, 0.0))
		mat.set_shader_parameter("clip_a%d" % l, lv.windows[0].get_texture())
		mat.set_shader_parameter("clip_b%d" % l, lv.windows[1].get_texture())
	mat.set_shader_parameter("clip_valid", valid)
	mat.set_shader_parameter("clip_info", info)
	mat.set_shader_parameter("clip_d0", GroundClipmapPlan.D0)
	mat.set_shader_parameter("clip_top", _top)


func _unbind() -> void:
	if terrain == null or not is_instance_valid(terrain):
		return
	var mat := terrain.get_material()
	if mat == null:
		return
	var empty := GroundClipmapPlan.valid_rect_m(0, Rect2i(), Rect2())
	mat.set_shader_parameter("clip_valid", PackedVector4Array([empty, empty, empty, empty, empty]))
	mat.set_shader_parameter("clip_hole", empty)
	for l in GroundClipmapPlan.CLIP_LEVELS:
		mat.set_shader_parameter("clip_a%d" % l, null)
		mat.set_shader_parameter("clip_b%d" % l, null)
