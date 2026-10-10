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
##            clock held so `advance` steps it
##   advance  {"s": seconds}: the events' clock that much further
##   free     the clock back to the frame loop (the change lands, the effects let go)
##   abort    every playing event stopped without its change (its trees stood back up), the
##            clock back to the frame loop: look iterations fire again on the same stand
##   arm      {"preset": "collapse" | "topple"}: PlayEvents.pick, as the preset's tile does
##   hover    {"at": "bridge" | "forest"}: the brush's pointer there, not pressed
##   report   the bridges, the forest spot and what is playing

const FIND_RADIUS := 6.0
const FIND_STEP := 3.0
const FIND_REACH := 18.0

static var _forest := Vector2.INF


static func run(base: Node, step: Dictionary) -> String:
	var map: GameMap = base.get("_game_map")
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
			if String(step.get("kind", "collapse")) == "collapse":
				var bridge := _bridge(edits)
				if bridge == null:
					return "no bridge"
				var middle := (bridge.start + bridge.end) * 0.5
				event = TerrainEvent.bridge_collapse(bridge.id, middle, int(step.get("seed", 7)))
			else:
				var at := _point(edits, "forest")
				var radius := float(step.get("radius", FIND_RADIUS))
				var event_seed := int(step.get("seed", 7))
				if String(step.get("kind")) == "fire":
					event = TerrainEvent.fire(at, radius, event_seed)
				else:
					event = TerrainEvent.forest_fall(at, radius, event_seed)
			edits.events.set_process(false)
			# PlayEvents hears the table's history once a brush or preset was wired (its
			# first pick): the event's toast comes from there.
			var play := _play_events(map)
			if play != null:
				play.call("_wired_brush")
			var why := edits.events.start(event)
			return "fired %s: %s" % [step.get("kind"), why if why != "" else "playing"]
		"advance":
			edits.events.advance(float(step.get("s", 0.1)))
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
		"report":
			var bridges := []
			for crossing in edits.editor.document.crossings:
				bridges.append([crossing.id, crossing.kind, (crossing.start + crossing.end) * 0.5])
			return "bridges %s, forest %s, %d playing" % [
				str(bridges), str(_point(edits, "forest")), edits.events.active_count()
			]
	return "unknown action"


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
