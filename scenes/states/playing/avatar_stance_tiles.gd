class_name AvatarStanceTiles
extends TileRow

## The builder's stance row: one tile per kit stance whose icon is the player's own figure
## standing in that stance, rendered as a flat white silhouette in a small viewport so the
## Tile theme tints it like any icon (muted at rest, accent when picked). Silhouettes follow
## the figure's parts and proportions (refresh) and are drawn once per change
## (UPDATE_ONCE), so six idle viewports cost nothing between picks. fit() grows the tiles to
## the pane's height, so the two rows of stances fill the Pose pane rather than leave its
## lower part empty. The silhouette's render takes the shape of the room a tile has above
## its caption (icon_area()), so the figure fills that room and the caption sits right under
## its feet; a fixed-shape render in a tall tile left the caption far below the figure.

## The largest silhouette render in pixels (a tile shows it at most this size).
const CELL := Vector2i(270, 368)
const MAX_CELL := Vector2i(480, 720)
## The view's least height and width in metres (the camera widens it to keep both), and the
## point it centres on: the figure, its raised arms and a turned stance's reach.
const VIEW_HEIGHT_M := 2.1
const VIEW_WIDTH_M := 1.0
const FOCUS_HEIGHT_M := 0.95
const CAMERA_DISTANCE_M := 12.0
## Tile heights fit() keeps to, and the room a tile keeps for its caption and padding.
const MIN_TILE_HEIGHT := 112.0
const MAX_TILE_HEIGHT := 640.0
const CAPTION_ROOM := 44.0
const SIDE_ROOM := 16.0
## A render is redrawn only when the room changes by more than this many pixels.
const RESIZE_SLACK_PX := 4

var _kit: AvatarKit = null
var _viewports: Dictionary = {}  # stance -> SubViewport
var _figures: Dictionary = {}  # stance -> Node3D
var _silhouette: StandardMaterial3D
## The tile height fit() last asked for, kept for a refit when the row's width changes.
var _fit_height := MIN_TILE_HEIGHT


func _init() -> void:
	tile_min_size = Vector2(96, 112)
	resized.connect(func() -> void: fit(_fit_height))
	_silhouette = StandardMaterial3D.new()
	_silhouette.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_silhouette.albedo_color = Color.WHITE


## Makes a tile per stance of `kit`, each showing `recipe`'s figure in it.
func build(kit: AvatarKit, recipe: Dictionary) -> void:
	_kit = kit
	for stance in kit.stance_names():
		var id := String(stance)
		var viewport := SubViewport.new()
		viewport.name = id.to_pascal_case() + "Viewport"
		viewport.own_world_3d = true
		viewport.transparent_bg = true
		viewport.size = CELL
		viewport.msaa_3d = Viewport.MSAA_4X
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		var camera := Camera3D.new()
		camera.name = "Camera"
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.near = 0.05
		camera.far = 50.0
		camera.basis = AvatarBuilderPreview.view_basis(AvatarBuilderPreview.FULL_PITCH_DEG)
		_frame(camera, CELL)
		viewport.add_child(camera)
		add_child(viewport)
		_viewports[id] = viewport
		var tile := add_tile(id, AvatarPresets.stance_label(id), "", "", viewport.get_texture())
		tile.expand_icon = false
	refresh(recipe)
	fit(MIN_TILE_HEIGHT)


## Grows the tiles to `tile_height` (clamped), and each silhouette's render to the room a
## tile of that height and the row's column width has above its caption (icon_area()).
func fit(tile_height: float) -> void:
	var height := clampf(tile_height, MIN_TILE_HEIGHT, MAX_TILE_HEIGHT)
	_fit_height = height
	tile_min_size.y = height
	var gap := float(get_theme_constant("h_separation"))
	var column := (size.x - gap * float(columns - 1)) / float(maxi(columns, 1))
	var area := icon_area(height, column if size.x > 0.0 else 0.0)
	for id in _tiles:
		(_tiles[id] as Button).add_theme_constant_override("icon_max_width", area.x)
		var viewport: SubViewport = _viewports.get(id)
		if viewport == null:
			continue
		var grown := (viewport.size - area).abs()
		if grown.x > RESIZE_SLACK_PX or grown.y > RESIZE_SLACK_PX:
			viewport.size = area
			_frame(viewport.get_node("Camera") as Camera3D, area)
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_fit_columns()


## The silhouette's size in a tile `tile_height` tall in a column `column` wide (0 before the
## row has a width: CELL's shape at that height): the room above the caption, at most
## MAX_CELL. Pure.
static func icon_area(tile_height: float, column: float) -> Vector2i:
	var tall := maxf(tile_height - CAPTION_ROOM, 32.0)
	var wide := column - SIDE_ROOM if column > 0.0 else tall * float(CELL.x) / float(CELL.y)
	return Vector2i(
		int(clampf(wide, 32.0, float(MAX_CELL.x))), int(clampf(tall, 32.0, float(MAX_CELL.y)))
	)


## The orthographic camera's height (KEEP_HEIGHT) for a render `cell` pixels: VIEW_HEIGHT_M,
## or taller when the cell is too narrow to show VIEW_WIDTH_M across. Pure.
static func view_size(cell: Vector2i) -> float:
	var aspect := float(maxi(cell.x, 1)) / float(maxi(cell.y, 1))
	return maxf(VIEW_HEIGHT_M, VIEW_WIDTH_M / aspect)


## Sizes `camera`'s view for a render `cell` pixels (view_size()) with the view's bottom edge
## kept where VIEW_HEIGHT_M puts it: a taller view adds its room above the head, so the feet
## stay at the render's foot, right over the caption.
static func _frame(camera: Camera3D, cell: Vector2i) -> void:
	camera.size = view_size(cell)
	var lift := (camera.size - VIEW_HEIGHT_M) * 0.5
	camera.position = (
		Vector3(0.0, FOCUS_HEIGHT_M, 0.0)
		+ camera.basis.y * lift
		+ camera.basis.z * CAMERA_DISTANCE_M
	)


## Rebuilds every silhouette for `recipe`'s parts and proportions (the stance is each
## tile's own) and draws them once.
func refresh(recipe: Dictionary) -> void:
	if _kit == null:
		return
	for id in _viewports:
		var viewport: SubViewport = _viewports[id]
		var old: Node3D = _figures.get(id)
		if old != null:
			viewport.remove_child(old)
			old.queue_free()
		var posed := recipe.duplicate(true)
		posed["stance"] = id
		var figure := _kit.build_figure(posed)
		figure.rotation.y = AvatarBuilderPreview.FACING_RAD
		for part in AvatarKit.figure_parts(figure):
			part.material_override = _silhouette
		viewport.add_child(figure)
		_figures[id] = figure
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
