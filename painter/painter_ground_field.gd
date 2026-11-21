class_name PainterGroundField
extends RefCounted

## PainterSurfaces' keeper of what the painted ground's FORM is lit from, for one authored
## terrain (card painter-ground-robust; docs/systems/painter.md "Ground shading"):
##   the shading field (GroundShadeField): the normal, slope, convexity and nearest steep face
##   painter_ground.gdshader reads in place of the mesh's, baked from the document's heights and
##   kept current per edit: AuthoredTerrain.ground_edited marks a rectangle, and the next sync()
##   (PainterSurfaces' zone rebuild, once that frame) redoes only the heights that changed in it;
##   the terrain's shadow caster: back faces only while painted (TerrainBackCaster), put back on
##   release().
## Events, never a poll: it follows the terrain's own signals from the first sync() to release().

var _field := GroundShadeField.new()
var _terrain: AuthoredTerrain = null
var _dirty := Rect2i()
## The heights may have changed anywhere (a new terrain, a rebuild): the next sync() compares all.
var _whole := true


## Brings the field up to `terrain`'s document and binds it to `materials` (the ground's).
func sync(terrain: AuthoredTerrain, materials: Array) -> void:
	if terrain != _terrain:
		release()
		_terrain = terrain
		terrain.ground_edited.connect(_on_ground_edited)
		terrain.child_entered_tree.connect(_on_terrain_child)
		terrain.set_back_caster(true)
	var doc := terrain.document
	if not _field.matches(doc):
		_field.bake(doc)
	elif _whole:
		_field.update(doc, Rect2i(0, 0, _field.width, _field.depth))
	elif _dirty.has_area():
		_field.update(doc, _dirty)
	_whole = false
	_dirty = Rect2i()
	for material: ShaderMaterial in materials:
		# Not `field_map`: that name is the village fields' (painter_field.gdshaderinc).
		material.set_shader_parameter(&"shade_map", _field.texture())
		material.set_shader_parameter(&"shade_present", true)


## Stops following the terrain and gives it its own shadow casting back.
func release() -> void:
	if is_instance_valid(_terrain):
		_terrain.ground_edited.disconnect(_on_ground_edited)
		_terrain.child_entered_tree.disconnect(_on_terrain_child)
		_terrain.set_back_caster(false)
	_terrain = null
	_dirty = Rect2i()
	_whole = true


## The field itself (tests and probes).
func field() -> GroundShadeField:
	return _field


func _on_ground_edited(rect: Rect2i) -> void:
	_dirty = _dirty.merge(rect) if _dirty.has_area() else rect


func _on_terrain_child(node: Node) -> void:
	# The skirt is built last by every AuthoredTerrain.build(): the heights may be new.
	if str(node.name) == AuthoredTerrain.SKIRT_NAME:
		_whole = true
