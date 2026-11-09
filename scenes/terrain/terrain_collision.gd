class_name TerrainCollision
extends Node3D

## The collision of an AuthoredTerrain: the document's height grid cut into square
## HeightMapShape3D tiles, one StaticBody3D each, so a height edit rebuilds only the tiles whose
## samples it changed. Jolt rebuilds a heightfield in time proportional to its samples: the whole
## 391 x 391 grid of a 320 ft map took 11.4 ms headless (6.7-7.2 ms in the running game at every
## stroke end, carve and undo), a 33 x 33 tile 0.10 ms (docs/PERFORMANCE.md "Collision tiles").
##
## Layout (tile_starts). A tile is `size` x `size` quads, one sample more each way, square because
## Jolt builds a heightfield only for a square shape (any other falls back to a slower triangle
## mesh). Neighbouring tiles share their border samples, and the last tile on an axis starts where
## it ends on the map edge, overlapping its neighbour when the grid is not a multiple of the tile.
## A shared or overlapping sample holds the same height in every tile that has it, so a ray on a
## border hits the same triangles whichever tile answers. The tile is TILE_QUADS, or the shorter
## side of a smaller map.
##
## This node carries TerrainMeshBuilder.collision_transform (the sample step on X and Z); each tile
## body sits at its tile's centre in grid units, so every sample lands on its document position, as
## with one shape over the whole grid. Bodies are on layer 1 / mask 1 with input_ray_pickable off,
## like the StaticBody3Ds GlbUtils makes for a map GLB. Separate bodies rather than one body of
## many shapes: Jolt rebuilds a body's compound shape on every shape change, which made four tile
## updates in a 49-tile body cost twice as much as in four bodies.

## Tile side in quads (8 m at the 0.25 m sample step). Measured per update: 32 quads 0.10 ms, 64
## 0.35 ms, 128 1.34 ms; a sculpt stroke's rectangle touches about as many samples either way, so
## the smallest tile wastes least past the rectangle's edge (169 bodies at 320 ft).
const TILE_QUADS := 32
const TILE_PREFIX := "CollisionTile"

## Grid columns and rows the tiles are laid out for (Vector2i.ZERO before the first build).
var _grid: Vector2i = Vector2i.ZERO
var _size: int = 0
var _starts_x: PackedInt32Array = PackedInt32Array()
var _starts_z: PackedInt32Array = PackedInt32Array()
## Tile (i, j) -> its shape, i along X, j along Z.
var _shapes: Dictionary[Vector2i, HeightMapShape3D] = {}
var _bodies: Array[StaticBody3D] = []
## Tiles marked for the next flush().
var _dirty: Dictionary[Vector2i, bool] = {}


## The tile side in quads for a grid of `columns` x `rows` samples.
static func tile_size(columns: int, rows: int) -> int:
	return maxi(mini(TILE_QUADS, mini(columns, rows) - 1), 1)


## The first sample of each tile along an axis of `quads` quads, tiles of `size` quads: every
## `size` quads, the last one moved back to end on the edge.
static func tile_starts(quads: int, size: int) -> PackedInt32Array:
	var starts := PackedInt32Array()
	var at := 0
	while at + size < quads:
		starts.append(at)
		at += size
	starts.append(maxi(quads - size, 0))
	return starts


## Indexes of the starts whose tiles hold a sample in [first, last] (a tile holds `size` + 1).
static func touching(
	starts: PackedInt32Array, size: int, first: int, last: int
) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in starts.size():
		if starts[i] <= last and starts[i] + size >= first:
			out.append(i)
	return out


## The heights of the tile whose first sample is (x0, z0), `size` + 1 samples a side, row by row.
static func cut(
	heights: PackedFloat32Array, columns: int, x0: int, z0: int, size: int
) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for z in size + 1:
		var row := (z0 + z) * columns + x0
		out.append_array(heights.slice(row, row + size + 1))
	return out


## Lays the tiles out for `doc` (again only when its grid size changed) and fills every tile.
func build(doc: MapDocument) -> void:
	var grid := Vector2i(doc.samples_x(), doc.samples_z())
	if grid != _grid:
		_layout(grid)
	transform = TerrainMeshBuilder.collision_transform(doc)
	var heights := TerrainMeshBuilder.collision_heights(doc)
	for tile in _shapes:
		_fill(tile, heights)
	_dirty.clear()


## Marks the tiles holding any sample of `rect` (document samples) for the next flush(). A
## stroke marks each dab's rectangle, so a long or bent stroke marks only the tiles it crossed.
func mark(rect: Rect2i) -> void:
	var area := rect.intersection(Rect2i(Vector2i.ZERO, _grid))
	if not area.has_area():
		return
	for j in touching(_starts_z, _size, area.position.y, area.end.y - 1):
		for i in touching(_starts_x, _size, area.position.x, area.end.x - 1):
			_dirty[Vector2i(i, j)] = true


## True while marked tiles wait for flush().
func has_marked() -> bool:
	return not _dirty.is_empty()


## Refills the marked tiles from `doc`'s heights (every tile when the grid size changed since the
## layout) and clears the marks. Returns the number of tiles refilled.
func flush(doc: MapDocument) -> int:
	if Vector2i(doc.samples_x(), doc.samples_z()) != _grid:
		build(doc)
		return _shapes.size()
	var heights := TerrainMeshBuilder.collision_heights(doc)
	var count := _dirty.size()
	for tile in _dirty:
		_fill(tile, heights)
	_dirty.clear()
	return count


## The tile bodies (for ray exclusion lists).
func bodies() -> Array[StaticBody3D]:
	return _bodies


func tile_count() -> int:
	return _shapes.size()


func _layout(grid: Vector2i) -> void:
	for body in _bodies:
		remove_child(body)
		body.queue_free()
	_bodies.clear()
	_shapes.clear()
	_dirty.clear()
	_grid = grid
	_size = tile_size(grid.x, grid.y)
	_starts_x = tile_starts(grid.x - 1, _size)
	_starts_z = tile_starts(grid.y - 1, _size)
	var half := Vector2(grid - Vector2i.ONE) * 0.5
	for j in _starts_z.size():
		for i in _starts_x.size():
			var body := StaticBody3D.new()
			body.name = "%s_%d_%d" % [TILE_PREFIX, i, j]
			body.input_ray_pickable = false
			body.position = Vector3(
				_starts_x[i] + _size * 0.5 - half.x, 0.0, _starts_z[j] + _size * 0.5 - half.y
			)
			var shape := HeightMapShape3D.new()
			shape.map_width = _size + 1
			shape.map_depth = _size + 1
			var collision := CollisionShape3D.new()
			collision.shape = shape
			body.add_child(collision)
			add_child(body)
			_bodies.append(body)
			_shapes[Vector2i(i, j)] = shape


func _fill(tile: Vector2i, heights: PackedFloat32Array) -> void:
	_shapes[tile].map_data = cut(heights, _grid.x, _starts_x[tile.x], _starts_z[tile.y], _size)
