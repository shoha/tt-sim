extends RefCounted

## Render-job probe for the GM's presets with spectacle (TerrainEvents: a bridge collapsing,
## a stand of trees toppling, a fire), on a table played from a _gm_events_ level. Fires an
## event on the GM's side with its clock held, so a filmstrip steps it to exact times, and arms the
## presets in the Events pane for the pane captures. Used by jobs/terrain_events.json.
##
## Actions (step "action"):
##   look     {"at": "bridge" | "forest" | [x, z] (map frame), "zoom": camera size, "yaw":
##            degrees, "lift": metres}: the view centred exactly there (the bridge's deck, the
##            ground elsewhere, `lift` above it to frame crowns; "forest": the densest stand
##            found near the bridge, see find), the
##            zoom set at once (an eased zoom drifts toward the cursor), the camera turned
##            `yaw` about the vertical from the play angle (0, the default, turns it back)
##   fire     {"kind": "collapse" | "fall" | "fire", "radius": m, "seed": n}: starts the event
##            on the table's TerrainEvents (the bridge, or the forest spot `look` found), its
##            clock held so `advance` steps it; "path" with "points" (world XZ, as a gesture
##            draws them) and "radius" (its half-width) a fire along them, as IgniteMode's Path
##            makes one (card F6); kind "fire" takes "at" ([x, z], map frame) for its centre;
##            from the first fire on, F6B| lines print when a change is made and when the
##            scatter applies cells (card F6b)
##   status   {"pixels": [[x, y], ...] in a 1920x1080 frame}: one timeline line (_status)
##   treeless {"radius": m}: straight 8 m world lines over the view with no burnable tree
##            within the radius (a Path a release refuses whole)
##   delete_level  deletes exactly the _firefeat_path test level (firefeat_path.json's)
##   advance  {"s": seconds}: the events' clock that much further, in frame-sized slices
##   free     the clock back to the frame loop (the change lands, the effects let go)
##   abort    every playing event stopped without its change (its trees stood back up), the
##            clock back to the frame loop: look iterations fire again on the same stand
##   arm      {"preset": "collapse" | "topple"}: PlayEvents.pick, as the preset's tile does
##   hover    {"at": "bridge" | "forest"}: the brush's pointer there, not pressed
##   report   the bridges, the forest spot and what is playing
##   burn     {"view": n}: the fire's ground scorch (GroundBurn's shader, shared by every burn)
##            swapped for a debug view of its noise, drawn opaque over the box (BURN_VIEWS: 1
##            the specks, the smoulder and the hot band's breaks as RGB; 2 the metres behind
##            the ragged front as repeating bands, the hottest patches and the ash); 0 puts the
##            shader's own code back (card F4b-5). With "source" (fire_ab.gd's
##            "<archive>.zip:<inner>" form: main's ground_burn.gdshader) the view, or with 0
##            the plain look, is drawn from that code instead, for a before

const FireAb := preload("res://tools/render_jobs/probes/fire_ab.gd")
const FIND_RADIUS := 6.0
const FIND_STEP := 3.0
const FIND_REACH := 18.0
## The test level firefeat_path.json saves, which delete_level removes (and nothing else).
const PATH_LEVEL := "_firefeat_path"
## `advance` steps the clock in slices this long (a frame at 30 fps).
const SLICE_S := 1.0 / 30.0
## The scorch's last line, after which a debug view overwrites its outputs.
const BURN_ANCHOR := "\tALBEDO = colour + hot * ENERGY * glow;"
const BURN_VIEWS := {
	1: "ALBEDO = vec3(speck, smoulder, whole); ALPHA = keep;",
	2: "ALBEDO = vec3(fract(b), hottest, ash); ALPHA = keep;",
}

static var _forest := Vector2.INF
static var _burn_code := ""


static func run(base: Node, step: Dictionary) -> String:
	var map: GameMap = base.get("_game_map")
	if String(step.get("action", "")) == "delete_level":
		return delete_path_level()
	if String(step.get("action", "")) == "burn":
		return _burn_debug(int(step.get("view", 0)), String(step.get("source", "")))
	var lpc: LevelPlayController = map.get_level_play_controller() if map != null else null
	if lpc == null or lpc.live_edits == null:
		return "no table with live edits"
	var edits := lpc.live_edits
	match String(step.get("action", "")):
		"look":
			var at := _point(edits, step.get("at", "bridge"))
			if at == Vector2.INF:
				return "nothing to look at"
			var world := _world(edits, step.get("at", "bridge"), at)
			world.y += float(step.get("lift", 0.0))
			var cc := map.get_camera_controller()
			if step.has("zoom"):
				cc.set("_target_zoom", float(step.zoom))
				map.camera_node.size = cc.call("_corrected_size", float(step.zoom))
				cc.call("_update_camera_offset")
			map.cameraholder_node.rotation.y = deg_to_rad(float(step.get("yaw", 0.0)))
			var miss := _centre_on(map, world)
			return "looking at map %s (world %s), %.1f px off centre" % [str(at), str(world), miss]
		"fire":
			var event: TerrainEvent = null
			if String(step.get("kind", "collapse")) == "path":
				event = _path_event(edits, step)
			elif String(step.get("kind", "collapse")) == "collapse":
				var bridge := _bridge(edits)
				if bridge == null:
					return "no bridge"
				var middle := (bridge.start + bridge.end) * 0.5
				event = TerrainEvent.bridge_collapse(bridge.id, middle, int(step.get("seed", 7)))
			else:
				var at := _point(edits, step.get("at", "forest"))
				var radius := float(step.get("radius", FIND_RADIUS))
				var event_seed := int(step.get("seed", 7))
				if String(step.get("kind")) == "fire":
					event = TerrainEvent.fire(at, radius, event_seed)
				else:
					event = TerrainEvent.forest_fall(at, radius, event_seed)
			edits.events.set_process(false)
			_trace(edits)
			# PlayEvents hears the table's history once a brush or preset was wired (its
			# first pick): the event's toast comes from there.
			var play := _play_events(map)
			if play != null:
				play.call("_wired_brush")
			var why := edits.events.start(event)
			return "fired %s: %s" % [step.get("kind"), why if why != "" else "playing"]
		"advance":
			# In frame-sized slices, as the frame loop steps it: one long step emitted every
			# puff of that span at once, all born at its end.
			var left := float(step.get("s", 0.1))
			while left > 0.0:
				var slice := minf(left, SLICE_S)
				edits.events.advance(slice)
				left -= slice
			return "%d playing" % edits.events.active_count()
		"free":
			edits.events.set_process(true)
			return "clock free"
		"abort":
			var active: Array = edits.events.get("_active")
			var stopped := active.size()
			for entry: Dictionary in active:
				edits.events.call("_free_effect", entry)
			active.clear()
			edits.events.set_process(true)
			return "aborted %d without their change" % stopped
		"arm":
			var events := _play_events(map)
			if events == null:
				return "no PlayEvents"
			events.pick(StringName(String(step.get("preset", "topple"))))
			return "armed %s" % events.armed
		"hover":
			var events := _play_events(map)
			var brush := events.brush() if events != null else null
			if brush == null:
				return "no brush"
			var at := _point(edits, step.get("at", "bridge"))
			var world := _world(edits, step.get("at", "bridge"), at)
			brush.pointer = map.camera_node.unproject_position(world)
			brush.has_pointer = true
			return "pointer at %s" % str(brush.pointer)
		"status":
			return _status(map, edits, step.get("pixels", []))
		"treeless":
			# Straight world lines 8 m long on a grid over the view with no burnable tree within
			# `radius` of them (a Path that a release refuses whole), the first few found.
			var radius := float(step.get("radius", 2.5))
			var found := PackedStringArray()
			for ix in range(-20, 32, 3):
				for iz in range(-18, 20, 3):
					var a := Vector2(ix, iz)
					var b := a + Vector2(6.0, 5.0)
					var line := PackedVector2Array(
						[
							edits.editor.to_map_xz(Vector3(a.x, 0.0, a.y)),
							edits.editor.to_map_xz(Vector3(b.x, 0.0, b.y))
						]
					)
					var root := edits.editor.palette_root
					if FireSweep.burnable_along(edits.editor.scatter, line, radius, root, 1).is_empty():
						found.append("%s-%s" % [str(a), str(b)])
			return "treeless: %s" % ", ".join(found)
		"report":
			var bridges := []
			for crossing in edits.editor.document.crossings:
				bridges.append([crossing.id, crossing.kind, (crossing.start + crossing.end) * 0.5])
			return (
				"bridges %s, forest %s, %d playing"
				% [str(bridges), str(_point(edits, "forest")), edits.events.active_count()]
			)
	return "unknown action"


## Prints (F6B| lines, in the raw output) when the table's events make their change and when
## the scatter applies regenerated cells, with the wall clock (card F6b's handover timeline).
static func _trace(edits: LiveEdits) -> void:
	if edits.has_meta(&"f6b_traced"):
		return
	edits.set_meta(&"f6b_traced", true)
	edits.events.applied.connect(
		func(_event: TerrainEvent) -> void: print("F6B| applied at %d ms" % Time.get_ticks_msec())
	)
	if edits.editor.scatter != null:
		edits.editor.scatter.cells_applied.connect(
			func(cells: Array[Vector2i]) -> void:
				print("F6B| cells_applied %d at %d ms" % [cells.size(), Time.get_ticks_msec()])
		)


## One timeline line (card F6b): the wall clock, each playing event's clock, whether its change
## was made, its char's alpha (GroundBurn.char_at), whether it has played and its scatter
## change landed, the scatter's regeneration, the ground look's restamp wait and bakes, and at
## each window pixel of `pixels` (1920x1080 frame) the ground point there with its ash weight
## and the scatter rows within 0.6 m.
static func _status(map: GameMap, edits: LiveEdits, pixels: Array) -> String:
	var events := edits.events
	var clock: float = events.get("_clock")
	var parts := PackedStringArray(["wall %d ms" % Time.get_ticks_msec()])
	for entry: Dictionary in events.get("_active"):
		var event: TerrainEvent = entry.event
		var elapsed := clock - float(entry.begin)
		var node: Node3D = entry.get("node")
		var end := event.duration_s
		if node is FireSweep and is_instance_valid(node):
			end = (node as FireSweep).end_at(elapsed)
		var line := (
			"event %.2f/%.2f s applied %s char %.2f"
			% [elapsed, event.duration_s, str(entry.get("applied", false)), GroundBurn.char_at(elapsed, end)]
		)
		if node != null and is_instance_valid(node):
			line += (
				" played %s landed %s"
				% [str(node.call(&"is_played", elapsed)), str(node.call(&"is_removed"))]
			)
		parts.append(line)
	var editor := edits.editor
	var scatter := editor.scatter
	if scatter != null:
		parts.append(
			"scatter regen %s growing %s" % [str(scatter.is_regenerating()), str(scatter.is_growing())]
		)
	var look := editor.terrain.ground_look() if is_instance_valid(editor.terrain) else null
	if look != null:
		parts.append("look stamp_wait %.2f bakes %d" % [float(look.get("_stamp_wait")), look.bakes])
	var doc := editor.document
	var ash := doc.surface_ids.find(FireSweep.ASH)
	var camera := map.camera_node
	var scale := Vector2(map.world_viewport.size) / Vector2(1920.0, 1080.0)
	var rows: Dictionary = scatter.rows_by_asset() if scatter != null else {}
	for px: Array in pixels:
		var at := Vector2(float(px[0]), float(px[1])) * scale
		var from := camera.project_ray_origin(at)
		var dir := camera.project_ray_normal(at)
		var hit := from
		var ground_y := 0.0
		for i in 3:
			hit = from + dir * ((ground_y - from.y) / dir.y)
			ground_y = editor.ground_height_at(hit)
		var xz := editor.to_map_xz(hit)
		var s := doc.world_to_sample(xz).round()
		var sample := doc.sample_index(int(s.x), int(s.y))
		var weight := doc.surface_weight(sample, ash) if ash >= 0 else -1
		var near := 0
		for asset_id in rows:
			var flat: PackedFloat32Array = rows[asset_id]
			for r in range(0, flat.size(), MapDocument.ROW_STRIDE):
				if Vector2(flat[r], flat[r + 2]).distance_to(xz) <= 0.6:
					near += 1
		var where := str(xz.snapped(Vector2(0.1, 0.1)))
		parts.append("px %s map %s ash %d rows %d" % [str(px), where, weight, near])
	return " | ".join(parts)


## Swaps the scorch's shader for debug view `view` (see the header's burn) of its own code or of
## `source`'s, or puts that code back for 0.
static func _burn_debug(view: int, source: String) -> String:
	var shader: Shader = GroundBurn.SHADER
	if _burn_code == "":
		_burn_code = shader.code
	var code := _burn_code if source == "" else FireAb._read(source)
	var from := "its own" if source == "" else source
	if code == "":
		return "no ground burn code at %s" % source
	if view == 0:
		shader.code = code
		return "ground burn shader: %s" % from
	if not code.contains(BURN_ANCHOR) or not BURN_VIEWS.has(view):
		return "no anchor or no view %d for the burn debug" % view
	shader.code = code.replace(BURN_ANCHOR, BURN_ANCHOR + "\n\t" + String(BURN_VIEWS[view]))
	return "ground burn debug view %d of %s" % [view, from]


## A fire along `step.points` (world XZ, as the gesture op draws them), made as IgniteMode makes
## one on release: to the map frame, smoothed, capped and resampled, `step.radius` its
## half-width.
static func _path_event(edits: LiveEdits, step: Dictionary) -> TerrainEvent:
	var line := PackedVector2Array()
	for p: Array in step.get("points", []):
		line.append(edits.editor.to_map_xz(Vector3(float(p[0]), 0.0, float(p[1]))))
	var capped := StrokePath.capped(StrokePath.smooth_line(line), TerrainEvent.MAX_PATH_LENGTH_M)
	var even := StrokePath.resample(
		capped, TerrainEvent.MAX_PATH_POINTS, StrokePath.MIN_SPACING_M
	)
	return TerrainEvent.fire_path(even, float(step.get("radius", 2.5)), int(step.get("seed", 7)))


## Deletes exactly the `_firefeat_path` test level (the one firefeat_path.json saves).
static func delete_path_level() -> String:
	var path := LevelManager.folder_path(PATH_LEVEL)
	if not DirAccess.dir_exists_absolute(path):
		return "no %s level" % PATH_LEVEL
	return "deleted %s: %s" % [PATH_LEVEL, LevelManager.delete_level_folder(path)]


static func _play_events(map: GameMap) -> PlayEvents:
	var menu := map.gameplay_menu.get_node_or_null("GameplayMenu")
	return menu.get("play_events") as PlayEvents if menu != null else null


## The world point over map point `at` named by `key`: the bridge's deck, or the ground.
static func _world(edits: LiveEdits, key: Variant, at: Vector2) -> Vector3:
	var world := edits.editor.to_world(Vector3(at.x, 0.0, at.y))
	world.y = edits.editor.ground_height_at(world)
	var bridge := _bridge(edits)
	if key is String and String(key) == "bridge" and bridge != null:
		world.y = edits.editor.to_world(Vector3(0.0, bridge.levels.y, 0.0)).y
	return world


## Pans the camera holder over the ground (its height kept) until world point `world` falls at
## the screen centre; an orthographic camera's pan moves the picture without changing it.
## Returns how far off centre it still is, in pixels.
static func _centre_on(map: GameMap, world: Vector3) -> float:
	var camera := map.camera_node
	var size := Vector2(map.world_viewport.size)
	var high := camera.keep_aspect == Camera3D.KEEP_HEIGHT
	var per_px := camera.size / (size.y if high else size.x)
	for i in 3:
		var off := camera.unproject_position(world) - size * 0.5
		var right := camera.global_basis.x
		var up := camera.global_basis.y
		var up_flat := Vector3(up.x, 0.0, up.z)
		var move := right * off.x * per_px
		move -= up_flat.normalized() * off.y * per_px / maxf(up_flat.length(), 0.01)
		map.cameraholder_node.global_position += move
	return (camera.unproject_position(world) - size * 0.5).length()


static func _bridge(edits: LiveEdits) -> Crossing:
	for crossing in edits.editor.document.crossings:
		if crossing.is_deck():
			return crossing
	return null


## Map point `at`: [x, z], the bridge's middle, or the forest spot: the point of a grid around
## the bridge with the most drawn trees within FIND_RADIUS (found once a run).
static func _point(edits: LiveEdits, at: Variant) -> Vector2:
	if at is Array:
		return Vector2(float(at[0]), float(at[1]))
	var bridge := _bridge(edits)
	var middle := (bridge.start + bridge.end) * 0.5 if bridge != null else Vector2.ZERO
	if String(at) == "bridge":
		return middle if bridge != null else Vector2.INF
	if _forest != Vector2.INF:
		return _forest
	var best := 0
	var steps := int(FIND_REACH / FIND_STEP)
	for ix in range(-steps, steps + 1):
		for iz in range(-steps, steps + 1):
			var p := middle + Vector2(ix, iz) * FIND_STEP
			var count := ForestFall.trees_near(edits.editor.scatter, p, FIND_RADIUS).size()
			if count > best:
				best = count
				_forest = p
	return _forest
