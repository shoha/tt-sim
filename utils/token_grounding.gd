class_name TokenGrounding
extends RefCounted

## Sets saved tokens back down on ground that moved under them. A token at rest sits where
## its last drop landed (DraggableToken settles every drop onto TokenWater.landing_position),
## so one that no longer does had its ground changed under it: a sculpt raised or lowered
## it, water was carved or filled there, or a dressed GLB was re-exported. Authoring
## re-grounds its tokens when an edit settles and before it saves (AuthoringTokens), and a
## play-time load re-grounds each placement as it spawns (LevelPlayLoader), through this one
## function, so a saved token never floats, sinks into a hill or stands on a vanished bed.
##
## The landing is the drop's: cast down from the token's top, so a bridge or a roof above
## it stays out of the cast, with the float rule in water. A token buried by raised ground
## has no ground under its top; it is cast from cast_top() (above every surface) instead.
## Props have no collision, so a token inside a placed prop stays there; authoring shows
## it, and the author moves it.

## A token this close to its landing height is left where it is (the settle tween's and the
## float32 save's rounding).
const TOLERANCE_M := 0.01


## A world height above every surface of `game_map`'s map (its mesh bounds, which take in
## terrain chunks and crossings, plus the terrain downcast's clearance), for a buried
## token's cast. Walks the map's mesh instances, so call it once per pass, not per token.
static func cast_top(game_map: GameMap) -> float:
	return (
		LevelEnvironmentManager.compute_map_bounds(game_map.map_container).end.y
		+ DragPlaceController.TERRAIN_DOWNCAST_HEIGHT
	)


## Where `token`'s rigid body rests on the ground as it is now, or Vector3.INF when nothing
## is under it (or it is not in the tree). `cast_top` is cast_top()'s.
static func resting_position(token: BoardToken, cast_top: float) -> Vector3:
	if not is_instance_valid(token) or token.rigid_body == null:
		return Vector3.INF
	if not token.rigid_body.is_inside_tree():
		return Vector3.INF
	var dragging := token.get_dragging_object()
	if dragging == null:
		return Vector3.INF
	var landing: Variant = dragging.water.landing_position()
	if landing == null:
		landing = dragging.water.landing_from(cast_top)
	return landing if landing is Vector3 else Vector3.INF


## Moves `token` straight onto its resting position, with no animation, when it stands more
## than TOLERANCE_M off it. Returns true when it moved. Leaves a token mid-drag alone (the
## drop decides where that one lands; a settle tween in flight overwrites any move).
static func reground(token: BoardToken, cast_top: float) -> bool:
	var dragging := token.get_dragging_object() if is_instance_valid(token) else null
	if dragging == null or dragging.is_being_dragged():
		return false
	var rest := resting_position(token, cast_top)
	if rest == Vector3.INF:
		return false
	if absf(rest.y - token.rigid_body.global_position.y) <= TOLERANCE_M:
		return false
	token.rigid_body.global_position = rest
	dragging.water.update_floating()
	dragging.water.update_cue(false)
	return true
