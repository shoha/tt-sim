class_name GroundHeightField
extends RefCounted

## The ground under a map as a regular grid of heights, which the grid overlay draws on
## (GridOverlay.set_ground, through GameMap.set_grid_ground): a one-channel float texture with
## one texel per sample (read with texelFetch, interpolated on the triangles
## ScatterGenerator.triangle_height uses), the map-frame XZ of sample (0, 0), the step between
## samples, and the node whose global transform places the map frame in the world (a level's
## map scale and offset, followed live). Two sources:
##
## - Authored terrain (from_terrain): the document heights on the terrain's own triangles, so
##   the grid's ground is the rendered surface exactly. The texture is the terrain's
##   (AuthoredTerrain.get_height_texture), refreshed in place when a sculpt settles.
## - A Blender (GLB) map (for_glb): heights sampled from its layer-1 collision (DressingGround
##   rays, the ground tokens land on) on a grid over the map's bounds, misses filled from the
##   nearest hit so the grid stays continuous over holes and past the collision's edge. Water
##   planes and Geoscatter scatter are not layer-1 collision, so they are never the ground.
##   A map with no layer-1 collision at all, or whose ground already sits in the fixed Y = 0
##   band (keeps_fixed_band: a dungeon or room floor at the glTF origin), gets no field and
##   keeps the band exactly as before.
##
## Sample spacing for GLB maps: SPACING_M, widened only when a map would need more than
## MAX_SAMPLES rays. Measured against the collision at 4000 random points (P3-3c, the
## tools/render_jobs/probes/grid_ground.gd survey): at 0.25 m the interpolated surface is
## within 0.025 m (worst) of Deciduous clusters' terrain and 0.029 m of River's, well inside
## GridOverlay.GROUND_TOLERANCE_M (0.2 m); at 0.5 m River's worst was 0.094 m and at 1 m
## 0.24 m (0.15 % of points past the tolerance). Rays cost about 2.3 us each there.

## Sample spacing (metres, map frame) for a GLB map's ground.
const SPACING_M := 0.25
## Most samples a GLB map's ground takes; a bigger map spaces them wider (grid_for_bounds).
const MAX_SAMPLES := 65536
## A GLB map keeps the fixed Y = 0 band when at least FLAT_SHARE of its sampled ground lies
## within FLAT_BAND_M of world Y = 0 (the band's smallest tolerance): the ground is the
## band's already, and the rest is furniture, walls and props that the band keeps the grid
## off. Measured at 4000 random points (P3-3c): Oak's lab 87 % of its collision within
## 0.5 m of Y = 0; Deciduous clusters 63 % and River 61 %, whose clearing and riverbed sit
## about 1.2 m lower.
const FLAT_BAND_M := 0.5
const FLAT_SHARE := 0.8

## Map-frame XZ of sample (0, 0) and the step between samples.
var origin: Vector2 = Vector2.ZERO
var step: Vector2 = Vector2.ONE
var columns: int = 0
var rows: int = 0
## Row-major map-frame heights (a sampled field; a terrain's live in its document).
var heights: PackedFloat32Array = PackedFloat32Array()

var _frame: Node3D = null
var _terrain: AuthoredTerrain = null
var _texture: ImageTexture = null


## The field of authored terrain `terrain` (null for null).
static func from_terrain(terrain: AuthoredTerrain) -> GroundHeightField:
	if terrain == null or terrain.document == null:
		return null
	var field := GroundHeightField.new()
	var doc := terrain.document
	field._terrain = terrain
	field._frame = terrain
	field.origin = -doc.extent_m() * 0.5
	field.step = doc.sample_step()
	field.columns = doc.samples_x()
	field.rows = doc.samples_z()
	return field


## A field of sampled heights `values` (row-major, `grid_columns` x `grid_rows`, no misses
## left), sample (0, 0) at map-frame XZ `grid_origin`, `grid_step` apart, in the frame of
## `frame` (the map root).
static func from_samples(
	frame: Node3D,
	values: PackedFloat32Array,
	grid_columns: int,
	grid_rows: int,
	grid_origin: Vector2,
	grid_step: Vector2
) -> GroundHeightField:
	var field := GroundHeightField.new()
	field._frame = frame
	field.heights = values
	field.columns = grid_columns
	field.rows = grid_rows
	field.origin = grid_origin
	field.step = grid_step
	return field


## The grid overlay's field for a GLB map from its sampled collision (DressingGround heights,
## misses filled, and its hit bytes), or null when the map keeps the fixed band
## (keeps_fixed_band: no collision was hit, or the ground is at Y = 0 already).
static func for_glb(
	frame: Node3D,
	values: PackedFloat32Array,
	hit: PackedByteArray,
	grid_columns: int,
	grid_rows: int,
	grid_origin: Vector2,
	grid_step: Vector2
) -> GroundHeightField:
	var to_world := frame.global_transform if frame.is_inside_tree() else frame.transform
	if keeps_fixed_band(values, hit, grid_columns, grid_origin, grid_step, to_world):
		return null
	return from_samples(frame, values, grid_columns, grid_rows, grid_origin, grid_step)


## True when a GLB map's sampled ground should leave the grid on the fixed Y = 0 band: no
## sample hit collision, or at least FLAT_SHARE of the hits lie within FLAT_BAND_M of world
## Y = 0 (`to_world` places the map frame). Pure.
@warning_ignore("integer_division")
static func keeps_fixed_band(
	values: PackedFloat32Array,
	hit: PackedByteArray,
	grid_columns: int,
	grid_origin: Vector2,
	grid_step: Vector2,
	to_world: Transform3D
) -> bool:
	var total := 0
	var flat := 0
	for i in hit.size():
		if hit[i] == 0:
			continue
		total += 1
		var local := grid_origin + Vector2(i % grid_columns, i / grid_columns) * grid_step
		var world := to_world * Vector3(local.x, values[i], local.y)
		if absf(world.y) <= FLAT_BAND_M:
			flat += 1
	return total == 0 or flat >= FLAT_SHARE * total


## The sampling grid for map-frame bounds `bounds` (only X and Z are used): {"origin",
## "step", "columns", "rows"}, samples `spacing` apart, or wider so there are about
## `max_samples` at most (whole rows and columns round it up a little), the last row and
## column on the far edges. Pure.
static func grid_for_bounds(
	bounds: AABB, spacing: float = SPACING_M, max_samples: int = MAX_SAMPLES
) -> Dictionary:
	var size := Vector2(maxf(bounds.size.x, 0.0), maxf(bounds.size.z, 0.0))
	var wanted := (size.x / spacing + 1.0) * (size.y / spacing + 1.0)
	if wanted > max_samples:
		# Widen so the count fits: (w / s + 1) (d / s + 1) <= n, solved for s.
		var n := float(max_samples)
		var a := n - 1.0
		var b := -(size.x + size.y)
		var c := -size.x * size.y
		spacing = maxf(spacing, (-b + sqrt(b * b - 4.0 * a * c)) / (2.0 * a))
	var grid_columns := maxi(int(ceil(size.x / spacing - 0.0001)) + 1, 2)
	var grid_rows := maxi(int(ceil(size.y / spacing - 0.0001)) + 1, 2)
	return {
		"origin": Vector2(bounds.position.x, bounds.position.z),
		"step":
		Vector2(
			size.x / (grid_columns - 1) if size.x > 0.0 else spacing,
			size.y / (grid_rows - 1) if size.y > 0.0 else spacing
		),
		"columns": grid_columns,
		"rows": grid_rows,
	}


## True while the field's source is alive: the terrain with its document, or the map root.
func is_valid() -> bool:
	if _terrain != null:
		return is_instance_valid(_terrain) and _terrain.document != null
	return is_instance_valid(_frame)


## The heights as one R32F texel per sample. A terrain's own texture (refreshed in place as
## its heights settle); a sampled field's is built once.
func get_texture() -> Texture2D:
	if _terrain != null:
		return _terrain.get_height_texture()
	if _texture == null:
		var image := Image.create_from_data(
			columns, rows, false, Image.FORMAT_RF, heights.to_byte_array()
		)
		_texture = ImageTexture.create_from_image(image)
	return _texture


## Map frame to world: the frame node's global transform (its local one outside the tree).
func get_transform() -> Transform3D:
	if not is_instance_valid(_frame):
		return Transform3D.IDENTITY
	return _frame.global_transform if _frame.is_inside_tree() else _frame.transform


## The ground's world Y at world XZ `world_xz`, on the triangles the grid shader uses; past
## the grid the edge heights continue.
func world_height_at(world_xz: Vector2) -> float:
	var to_world := get_transform()
	if _terrain != null:
		return TerrainMeshBuilder.world_ground_height(_terrain.document, to_world, world_xz)
	var local := to_world.affine_inverse() * Vector3(world_xz.x, 0.0, world_xz.y)
	var at := (Vector2(local.x, local.z) - origin) / step
	var h := ScatterGenerator.triangle_height(heights, columns, rows, at)
	return (to_world * Vector3(local.x, h, local.z)).y
