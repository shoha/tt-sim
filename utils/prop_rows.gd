class_name PropRows
extends RefCounted

## Pure rules of the Place brush's hand-placed props (MapDocument.props rows, the
## [lx, ly, lz, qx, qy, qz, qw, sx, sy, sz] format every scatter row uses): building a row
## bedded on the ground, turning and scaling one in place, finding the prop under the
## pointer, and the scale range a species allows. AuthoringEditor applies them to the
## AuthoredProps node; everything here is data in, data out.
##
## Orientation follows ScatterGenerator._append_row, so a placed oak stands exactly like a
## generated one: an upright species stands on +Y, a normal-aligned one (rocks, logs) on the
## ground normal, and the yaw turns it about that up axis:
## rotation = Quaternion(UP, up) * Quaternion(UP, yaw).

const STRIDE := MapDocument.ROW_STRIDE
## Placed props are heroes: their scale range is at least this either side of 1, even for
## species whose generated spread is narrower (trees are +-0.15), so Shift+wheel can make a
## noticeably grand oak or a small one.
const HERO_MIN_SPREAD := 0.25
## Scale change per wheel notch.
const SCALE_STEP := 0.05


## A row for a prop at `position` (map frame) on ground whose normal is `normal`, turned by
## `yaw` radians, uniformly scaled by `scale`.
static func make_row(
	position: Vector3, normal: Vector3, align_normal: bool, yaw: float, scale: float
) -> PackedFloat32Array:
	var up := normal.normalized() if align_normal and normal.length_squared() > 0.0 else Vector3.UP
	var rotation := Quaternion(Vector3.UP, up) * Quaternion(Vector3.UP, yaw)
	return PackedFloat32Array(
		[
			position.x,
			position.y,
			position.z,
			rotation.x,
			rotation.y,
			rotation.z,
			rotation.w,
			scale,
			scale,
			scale
		]
	)


## The up axis a row stands on (its rotation applied to +Y).
static func row_up(row: PackedFloat32Array) -> Vector3:
	return (_rotation(row) * Vector3.UP).normalized()


## `row` turned to `yaw` radians about its own up axis, keeping position, tilt and scale.
static func with_yaw(row: PackedFloat32Array, yaw: float) -> PackedFloat32Array:
	var up := row_up(row)
	var rotation := Quaternion(Vector3.UP, up) * Quaternion(Vector3.UP, yaw)
	var out := row.duplicate()
	out[3] = rotation.x
	out[4] = rotation.y
	out[5] = rotation.z
	out[6] = rotation.w
	return out


## The yaw (radians about its up axis) of a row made by make_row() / with_yaw().
static func row_yaw(row: PackedFloat32Array) -> float:
	var up := row_up(row)
	var tilt_free := Quaternion(Vector3.UP, up).inverse() * _rotation(row)
	var forward := tilt_free * Vector3.FORWARD
	return atan2(-forward.x, -forward.z)


## `row` uniformly scaled to `scale`.
static func with_scale(row: PackedFloat32Array, scale: float) -> PackedFloat32Array:
	var out := row.duplicate()
	out[7] = scale
	out[8] = scale
	out[9] = scale
	return out


## The scale range (Vector2(low, high)) of a species rule: 1 +- max(scale_spread,
## HERO_MIN_SPREAD), never below its scale_floor.
static func scale_range(rule: Dictionary) -> Vector2:
	var spread := maxf(float(rule.get("scale_spread", 0.0)), HERO_MIN_SPREAD)
	var low := 1.0 - spread
	var floor_value: Variant = rule.get("scale_floor")
	if floor_value is float or floor_value is int:
		low = maxf(low, float(floor_value))
	return Vector2(low, 1.0 + spread)


## `scale` moved `notches` wheel steps, clamped to `limits`.
static func stepped_scale(scale: float, notches: float, limits: Vector2) -> float:
	return clampf(scale + notches * SCALE_STEP, limits.x, limits.y)


## The prop nearest `point` (map-frame XZ) whose footprint contains it: {"asset_id": String,
## "index": int (row index within that asset's rows), "distance": float}, or {} when none
## does. `radius_of` maps an asset id to its footprint radius at scale 1 (metres).
static func pick(
	rows_by_asset: Dictionary, point: Vector2, radius_of: Callable, reach: float = 0.0
) -> Dictionary:
	var best := {}
	var best_distance := INF
	for asset_id in rows_by_asset:
		var rows: PackedFloat32Array = rows_by_asset[asset_id]
		var radius: float = radius_of.call(asset_id)
		@warning_ignore("integer_division")
		for r in rows.size() / STRIDE:
			var b := r * STRIDE
			var distance := Vector2(rows[b], rows[b + 2]).distance_to(point)
			if distance <= radius * rows[b + 7] + reach and distance < best_distance:
				best_distance = distance
				best = {"asset_id": asset_id, "index": r, "distance": distance}
	return best


## One row (STRIDE floats) of flat `rows`.
static func row_at(rows: PackedFloat32Array, index: int) -> PackedFloat32Array:
	return rows.slice(index * STRIDE, (index + 1) * STRIDE)


## `rows` with row `index` replaced by `row`.
static func replaced(
	rows: PackedFloat32Array, index: int, row: PackedFloat32Array
) -> PackedFloat32Array:
	var out := rows.duplicate()
	for k in STRIDE:
		out[index * STRIDE + k] = row[k]
	return out


## `rows` without row `index`.
static func removed(rows: PackedFloat32Array, index: int) -> PackedFloat32Array:
	var out := rows.slice(0, index * STRIDE)
	out.append_array(rows.slice((index + 1) * STRIDE))
	return out


static func _rotation(row: PackedFloat32Array) -> Quaternion:
	var q := Quaternion(row[3], row[4], row[5], row[6])
	return q.normalized() if q.length_squared() > 0.0 else Quaternion()
