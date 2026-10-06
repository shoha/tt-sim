class_name AvatarStanceTiles
extends TileRow

## The builder's stance row: one tile per kit stance whose icon is the player's own figure
## standing in that stance, rendered as a flat white silhouette in a small viewport so the
## Tile theme tints it like any icon (muted at rest, accent when picked). Silhouettes follow
## the figure's parts and proportions (refresh) and are drawn once per change
## (UPDATE_ONCE), so six idle viewports cost nothing between picks.

## The silhouette render size in pixels; the icon is shown at CELL.x.
const CELL := Vector2i(56, 76)
const VIEW_HEIGHT_M := 2.1
const FOCUS_HEIGHT_M := 0.95
const CAMERA_DISTANCE_M := 12.0

var _kit: AvatarKit = null
var _viewports: Dictionary = {}  # stance -> SubViewport
var _figures: Dictionary = {}  # stance -> Node3D
var _silhouette: StandardMaterial3D


func _init() -> void:
	tile_min_size = Vector2(96, 112)
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
		camera.basis = AvatarBuilderPreview.CAMERA_BASIS
		camera.position = (
			Vector3(0.0, FOCUS_HEIGHT_M, 0.0)
			+ AvatarBuilderPreview.CAMERA_BASIS.z * CAMERA_DISTANCE_M
		)
		viewport.add_child(camera)
		add_child(viewport)
		_viewports[id] = viewport
		var tile := add_tile(id, AvatarPresets.stance_label(id), "", "", viewport.get_texture())
		tile.add_theme_constant_override("icon_max_width", CELL.x)
		tile.expand_icon = false
	refresh(recipe)


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
