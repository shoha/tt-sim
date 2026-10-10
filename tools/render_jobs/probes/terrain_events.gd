extends RefCounted

## Render-job probe for the GM's presets with spectacle (TerrainEvents: a bridge collapsing,
## a stand of trees toppling), on a table played from a _gm_events_ level. Fires an event on
## the GM's side with its clock held, so a filmstrip steps it to exact times, and arms the
## presets in the Events pane for the pane captures. Used by jobs/terrain_events.json.
##
## Actions (step "action"):
##   look     {"at": "bridge" | "forest" | [x, z] (map frame), "zoom": camera size}: the view
##            centred there ("forest": the densest stand found near the bridge, see find)
##   fire     {"kind": "collapse" | "fall", "radius": m, "seed": n}: starts the event on the
##            table's TerrainEvents (the bridge, or the forest spot `look` found), its clock
##            held so `advance` steps it
##   advance  {"s": seconds}: the events' clock that much further
##   free     the clock back to the frame loop (the change lands, the effects let go)
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
			var world := edits.editor.to_world(Vector3(at.x, 0.0, at.y))
			var cc := map.get_camera_controller()
			if step.has("zoom"):
				cc.set("_target_zoom", float(step.zoom))
			var off: Vector2 = cc.call("_get_view_center_ground_offset")
			var holder := map.cameraholder_node
			holder.global_position = Vector3(
				world.x - off.x, holder.global_position.y, world.z - off.y
			)
			return "looking at map %s (world %s)" % [str(at), str(world)]
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
				event = TerrainEvent.forest_fall(
					at, float(step.get("radius", FIND_RADIUS)), int(step.get("seed", 7))
				)
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
			var world := edits.editor.to_world(Vector3(at.x, 0.0, at.y))
			world.y = edits.editor.ground_height_at(world)
			if String(step.get("at")) == "bridge":
				var bridge := _bridge(edits)
				world.y = edits.editor.to_world(Vector3(0.0, bridge.levels.y, 0.0)).y
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
