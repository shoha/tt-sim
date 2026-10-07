class_name AvatarStanceTiles
extends TileRow

## The builder's stance row: one tile per kit stance whose icon is the player's own figure
## standing in that stance, rendered as a flat white silhouette in a small viewport so the
## Tile theme tints it like any icon (muted at rest, accent when picked). Silhouettes follow
## the figure's parts and proportions (refresh) and are drawn once per change
## (UPDATE_ONCE), so six idle viewports cost nothing between picks. fit() grows the tiles to
## the pane's height, so the two rows of stances fill the Pose pane rather than leave its
## lower part empty; the silhouettes are rendered at the largest size a tile shows them.

## The silhouette render size in pixels (the largest a tile shows it).
const CELL := Vector2i(210, 286)
const VIEW_HEIGHT_M := 2.1
const FOCUS_HEIGHT_M := 0.95
const CAMERA_DISTANCE_M := 12.0
## Tile heights fit() keeps to, and the room a tile keeps for its caption and padding.
const MIN_TILE_HEIGHT := 112.0
const MAX_TILE_HEIGHT := 420.0
const CAPTION_ROOM := 44.0
const SIDE_ROOM := 16.0

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
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = VIEW_HEIGHT_M
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.near = 0.05
		camera.far = 50.0
		camera.basis = AvatarBuilderPreview.view_basis(AvatarBuilderPreview.FULL_PITCH_DEG)
		camera.position = Vector3(0.0, FOCUS_HEIGHT_M, 0.0) + camera.basis.z * CAMERA_DISTANCE_M
		viewport.add_child(camera)
		add_child(viewport)
		_viewports[id] = viewport
		var tile := add_tile(id, AvatarPresets.stance_label(id), "", "", viewport.get_texture())
		tile.expand_icon = false
	refresh(recipe)
	fit(MIN_TILE_HEIGHT)


## Grows the tiles to `tile_height` (clamped) and their silhouettes to what a tile of that
## height and the row's column width shows.
func fit(tile_height: float) -> void:
	var height := clampf(tile_height, MIN_TILE_HEIGHT, MAX_TILE_HEIGHT)
	_fit_height = height
	tile_min_size.y = height
	var gap := float(get_theme_constant("h_separation"))
	var column := (size.x - gap * float(columns - 1)) / float(maxi(columns, 1))
	var by_height := (height - CAPTION_ROOM) * float(CELL.x) / float(CELL.y)
	var by_width := column - SIDE_ROOM if size.x > 0.0 else by_height
	var icon_width := int(clampf(minf(by_height, by_width), 32.0, float(CELL.x)))
	for id in _tiles:
		(_tiles[id] as Button).add_theme_constant_override("icon_max_width", icon_width)
	_fit_columns()


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
