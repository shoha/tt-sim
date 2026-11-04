class_name PropFootprints
extends RefCounted

## Where the bulky village props stand, as boxes a token keeps out of (card eyepin, option A3). A
## prop has no collision (villages.md "Collision and tokens": `blocks: none` is the default), so a
## token dropped on a haystack or a crate stack lands on the ground inside it and the bales go
## through its legs; at the eye that is the ugliest thing in a token frame. The placer cannot cast
## against the prop, but it can read its footprint: the prop's default size (procgen
## props_and_settlements.md) times the placement's scale, turned by its yaw. `push_out` moves a
## point to the nearest ground outside every such box plus the token's radius, so a drop beside a
## haystack settles beside it. Pure; the registry (`active`) is filled by whoever draws the
## settlements, and holds no box in a map without a dressed village.

## The width and depth, in metres, of each prop a token cannot share ground with, at scale 1.
## Low and thin props (bench, signpost, lamp post, gates, laundry) are left out: a token may
## stand against them.
const SIZES: Dictionary = {
	"barrel": Vector2(1.5, 1.2),
	"crate_stack": Vector2(1.3, 1.0),
	"well": Vector2(1.8, 1.8),
	"haystack": Vector2(2.2, 2.0),
	"woodpile": Vector2(1.6, 0.9),
	"market_stall": Vector2(2.4, 1.7),
	"hand_cart": Vector2(1.3, 2.3),
	"farm_wagon": Vector2(1.8, 3.4),
	"wayside_shrine": Vector2(1.1, 1.1),
	"water_trough": Vector2(1.8, 0.8),
	"beehive_skeps": Vector2(1.6, 1.0),
	"planter": Vector2(0.9, 0.9),
	"parked_car": Vector2(1.9, 4.3),
}
## Whether a drop steps off the props (DraggableToken._step_off_props). Off until the owner decides.
static var enabled: bool = false
## The boxes of the map now playing: {"at": Vector2, "half": Vector2, "yaw": float}.
static var active: Array[Dictionary] = []


## The boxes of `placements` (SettlementPlan items): the props in SIZES, each box half its size
## times the placement's scale.
static func boxes_of(placements: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in placements:
		var size: Vector2 = SIZES.get(String(item["prop"]), Vector2.ZERO)
		if size == Vector2.ZERO:
			continue
		out.append(
			{
				"at": item["position"],
				"half": size * 0.5 * maxf(float(item.get("scale", 1.0)), 0.1),
				"yaw": float(item["yaw"]),
			}
		)
	return out


## `point` (map XZ) moved to the nearest spot at least `radius` outside every box in `boxes`. A
## point already clear stays. Boxes are resolved one after another, up to four rounds, so a point
## wedged between two settles on the side that clears both when there is room.
static func push_out(point: Vector2, radius: float, boxes: Array[Dictionary]) -> Vector2:
	var at := point
	for _round in 4:
		var moved := false
		for box in boxes:
			var next := _clear_of(at, radius, box)
			if not next.is_equal_approx(at):
				at = next
				moved = true
		if not moved:
			break
	return at


## `point` kept `radius` outside one box.
static func _clear_of(point: Vector2, radius: float, box: Dictionary) -> Vector2:
	var half: Vector2 = box["half"]
	var yaw: float = box["yaw"]
	# World to the box's frame (a Y rotation by yaw sends local (x, z) to world (x, z).rotated(-yaw)).
	var local := (point - (box["at"] as Vector2)).rotated(yaw)
	var near := local.clamp(-half, half)
	var gap := local - near
	var out_local := local
	if gap == Vector2.ZERO:
		# Inside: out through the nearest face, plus the radius.
		var room := half - local.abs()
		if room.x < room.y:
			out_local.x = signf(local.x if local.x != 0.0 else 1.0) * (half.x + radius)
		else:
			out_local.y = signf(local.y if local.y != 0.0 else 1.0) * (half.y + radius)
	elif gap.length() < radius:
		out_local = near + gap.normalized() * radius
	else:
		return point
	return (box["at"] as Vector2) + out_local.rotated(-yaw)


## `position` (a world point) with its XZ moved out of the boxes of the map now playing; the
## height is left for the landing cast.
static func clear_of(position: Vector3, radius: float) -> Vector3:
	if active.is_empty():
		return position
	var at := push_out(Vector2(position.x, position.z), radius, active)
	return Vector3(at.x, position.y, at.y)
