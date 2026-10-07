class_name AvatarThumbnails
extends Node

## Pictures of saved avatars for the title screen's roster (AvatarRoster) and the Add Token
## browser's Avatar tab: the whole figure on the builder preview's stage (its environment,
## sun, floor and default ambient, AvatarBuilderPreview.build_stage) fitted by the
## preview's framing (AvatarBuilderFraming), turned a little off the camera for a
## three-quarter view, on a transparent background the card's backdrop shows through.
##
## One renderer node under the tree root draws them one a frame from a queue, and every
## picture is kept in a cache keyed by the recipe (JSON hash), so a roster that opens again
## or a tab that refreshes shows them at once. A headless run (no real renderer) hands back
## null and caches nothing.

## The picture's size in pixels (tiles draw it smaller).
const SIZE := Vector2i(240, 320)
const NODE_NAME := "AvatarThumbnails"
## The figure's turn from facing the camera, for a three-quarter view.
const TURN_RAD := -0.4

## recipe key -> ImageTexture.
static var _cache: Dictionary = {}

var _viewport: SubViewport
var _camera: Camera3D
var _pivot: Node3D
## Pending [key, recipe] pairs, oldest first.
var _queue: Array = []
## key -> Array of Callable(texture) waiting for it.
var _waiting: Dictionary = {}
var _busy := false


## The thumbnail for `recipe` when it is cached; otherwise null, and `done` (a
## Callable(Texture2D)) is called with the picture once it is drawn.
static func request(recipe: Dictionary, done: Callable) -> Texture2D:
	var key := key_of(recipe)
	if _cache.has(key):
		return _cache[key]
	var renderer := _renderer()
	if renderer != null:
		renderer._enqueue(key, recipe, done)
	return null


## The cache key of a recipe: a hash of its normalised JSON (sorted keys).
static func key_of(recipe: Dictionary) -> String:
	return JSON.stringify(AvatarRecipe.normalized(recipe), "", true).md5_text()


## The cached thumbnail for `recipe`, or null.
static func cached(recipe: Dictionary) -> Texture2D:
	return _cache.get(key_of(recipe))


static func _renderer() -> AvatarThumbnails:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var node := tree.root.get_node_or_null(NODE_NAME) as AvatarThumbnails
	if node == null:
		node = AvatarThumbnails.new()
		node.name = NODE_NAME
		tree.root.add_child.call_deferred(node)
	return node


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "ThumbnailViewport"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.size = SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_camera = AvatarBuilderPreview.build_stage(_viewport)
	_pivot = Node3D.new()
	_pivot.name = "Turntable"
	_pivot.rotation.y = AvatarBuilderPreview.FACING_RAD + TURN_RAD
	_viewport.add_child(_pivot)


func _enqueue(key: String, recipe: Dictionary, done: Callable) -> void:
	if not _waiting.has(key):
		_waiting[key] = []
		_queue.append([key, recipe.duplicate(true)])
	if done.is_valid():
		(_waiting[key] as Array).append(done)


func _process(_delta: float) -> void:
	if _busy or _queue.is_empty() or _viewport == null:
		return
	var next: Array = _queue.pop_front()
	_render(String(next[0]), next[1])


func _render(key: String, recipe: Dictionary) -> void:
	_busy = true
	var texture: Texture2D = null
	var kit := AvatarTokenFactory.kit()
	if kit != null:
		var figure := kit.build_figure(recipe)
		AvatarBuilderPreview.light_figure(figure)
		_pivot.add_child(figure)
		var aspect := float(SIZE.x) / float(SIZE.y)
		var pitch := AvatarBuilderPreview.FULL_PITCH_DEG
		var view := AvatarBuilderFraming.fit(
			AvatarBuilderFraming.measure(figure), deg_to_rad(pitch), aspect
		)
		_camera.size = view.x
		_camera.basis = AvatarBuilderPreview.view_basis(pitch)
		_camera.position = (
			Vector3(0.0, view.y, 0.0) + _camera.basis.z * AvatarBuilderPreview.CAMERA_DISTANCE_M
		)
		# The skeleton re-poses as it enters the tree; draw on the frame after.
		await get_tree().process_frame
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var image := _viewport.get_texture().get_image()
		if image != null and not image.is_empty() and image.get_used_rect().has_area():
			texture = ImageTexture.create_from_image(image)
			_cache[key] = texture
		_pivot.remove_child(figure)
		figure.queue_free()
	for done: Callable in _waiting.get(key, []):
		if done.is_valid():
			done.call(texture)
	_waiting.erase(key)
	_busy = false
