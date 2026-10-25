class_name DesignerPicking
extends RefCounted

## Which plant is under the pointer on the proving ground (design doc 4.3, "click a plant to
## select its rule"). Scatter has no collision, so the pick works on the screen: every instance
## near the ground point under the pointer is drawn as a line from its foot to its top
## (position plus its asset's height times its scale), and the nearest line within PICK_PX of
## the pointer wins; a tie goes to the instance nearer the camera (larger screen y in the game's
## fixed view). Pure over the cell rows and a projection callable, so a test drives it without a
## camera.

const PICK_PX := 22.0
## Cells (10 m) around the ground point searched.
const SEARCH_CELLS := 1


## The asset id of the instance nearest the pointer: `project` maps a world Vector3 to screen
## pixels (Camera3D.unproject_position), `pointer` is the pointer in the same space, `ground` the
## ground point under it (map XZ as a Vector2), `cells` the scatter's {cell: {asset id: rows}},
## `heights` {asset id: height in metres}. {} when nothing is near enough, else {asset,
## distance (px), row (index in the cell's rows), cell}.
static func pick(
	project: Callable, pointer: Vector2, ground: Vector2, cells: Dictionary, heights: Dictionary
) -> Dictionary:
	var size := ScatterChunker.CHUNK_SIZE_WORLD_UNITS
	var centre := Vector2i(floori(ground.x / size), floori(ground.y / size))
	var best := {}
	var best_distance := PICK_PX
	for dx in range(-SEARCH_CELLS, SEARCH_CELLS + 1):
		for dz in range(-SEARCH_CELLS, SEARCH_CELLS + 1):
			var cell := centre + Vector2i(dx, dz)
			var held: Dictionary = cells.get(cell, {})
			for asset_id: String in held:
				var rows: PackedFloat32Array = held[asset_id]
				var height := float(heights.get(asset_id, 1.0))
				for r in rows.size() / MapDocument.ROW_STRIDE:
					var at := r * MapDocument.ROW_STRIDE
					var foot := Vector3(rows[at], rows[at + 1], rows[at + 2])
					var top := foot + Vector3.UP * height * rows[at + 8]
					var distance := _segment_distance(
						pointer, project.call(foot), project.call(top)
					)
					if (
						distance < best_distance
						or (
							not best.is_empty()
							and is_equal_approx(distance, best_distance)
							and foot.x + foot.z > float(best["depth"])
						)
					):
						best_distance = distance
						best = {
							"asset": asset_id,
							"distance": distance,
							"row": r,
							"cell": cell,
							"depth": foot.x + foot.z,
						}
	return best


static func _segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
	return point.distance_to(a + ab * t)
