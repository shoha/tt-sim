class_name TokenPictures
extends Node

## The HUD's own copy of the token portraits: the same pictures the map pins wear (TokenPortraits,
## made by the same rules from the same sources), so a roster row and the selection marker show
## the face a player sees on the board. A second atlas rather than a reach into TokenMarkers'
## private one: the markers stay as they are, and a picture costs one small job (icons and
## avatars are cheap, a model is drawn once on a private stage).
##
## texture_for() answers null while a picture is not ready (or failed: no renderer in a headless
## run); the caller shows a plain disc in that case and asks again on its next refresh.

## The share of the pin's picture the HUD keeps, from the middle: tighter than the map pin, which
## is drawn at its own size with the whole picture.
const CROP := 0.78

var _portraits: TokenPortraits = null
var _textures: Dictionary = {}  ## picture key -> AtlasTexture


func _ready() -> void:
	name = "TokenPictures"
	_portraits = TokenPortraits.new()
	add_child(_portraits)


## The cache key of `token`'s picture, "" while it has no mesh (as TokenMarkers reads it).
static func key_of(token: BoardToken) -> String:
	if token == null or token.rigid_body == null:
		return ""
	for mesh_instance in TokenGhost.meshes_of(token.rigid_body):
		if mesh_instance.mesh == null:
			continue
		return TokenPortraits.identity_key(
			token.pack_id,
			token.asset_id,
			token.variant_id,
			token.avatar_recipe,
			mesh_instance.mesh.get_instance_id()
		)
	return ""


## What a token's picture is made from (TokenPortraits.request): the avatar's recipe, the pack's
## icon when it has one, else the token's own meshes.
static func source_for(token: BoardToken) -> Dictionary:
	if token.is_avatar():
		return {"kind": TokenPortraits.Kind.AVATAR, "recipe": token.avatar_recipe}
	if token.pack_id != "" and token.asset_id != "" and AssetManager.resolver != null:
		var path: String = AssetManager.resolver.resolve_icon_sync(
			token.pack_id, token.asset_id, token.variant_id
		)
		if path != "":
			return {"kind": TokenPortraits.Kind.ICON, "path": path}
	return {"kind": TokenPortraits.Kind.MODEL, "token": token.get_instance_id()}


## The picture of `token` as a texture (one cell of the atlas, PICTURE_PX square), or null while
## it is being made. Asks for it the first time.
func texture_for(token: BoardToken) -> Texture2D:
	var key := key_of(token)
	if key == "" or _portraits == null:
		return null
	var cell := _portraits.cell_of(key)
	if cell < 0:
		if not _portraits.knows(key):
			_portraits.request(key, source_for(token))
		return null
	if not _textures.has(key):
		var atlas_texture := AtlasTexture.new()
		atlas_texture.atlas = _portraits.atlas
		atlas_texture.region = crop_of(cell)
		_textures[key] = atlas_texture
	return _textures[key]


## The part of the picture in atlas cell `cell` the HUD shows, in atlas pixels: the middle CROP of
## the map pin's picture (a head-and-chest crop with a margin of hair colour and background around
## the face), so a portrait 40 px across reads as a face. Pure.
static func crop_of(cell: int) -> Rect2:
	var side := float(TokenPortraits.PICTURE_PX) * CROP
	var gutter := (TokenPortraits.CELL_PX - TokenPortraits.PICTURE_PX) / 2
	var corner := Vector2(TokenPortraits.cell_origin(cell) + Vector2i.ONE * gutter)
	# A little above the middle: the face sits in the upper part of a head-and-chest picture.
	var inset := (float(TokenPortraits.PICTURE_PX) - side) * 0.5
	return Rect2(corner + Vector2(inset, inset * 0.7), Vector2(side, side))


## The atlas itself (null before the first picture), for a textured polygon with UVs from
## uv_rect_of().
func atlas() -> Texture2D:
	return _portraits.atlas if _portraits != null else null


## The crop of `token`'s picture as a rectangle in atlas UV (0..1), or an empty rectangle while
## the picture is not ready.
func uv_rect_of(token: BoardToken) -> Rect2:
	var key := key_of(token)
	if key == "" or _portraits == null or _portraits.cell_of(key) < 0:
		return Rect2()
	var region := crop_of(_portraits.cell_of(key))
	var whole := float(TokenPortraits.ATLAS_PX)
	return Rect2(region.position / whole, region.size / whole)
