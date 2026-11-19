class_name PainterGrassMarks
extends RefCounted

## The painted look's meadow grass as MARKS (card painter-grass-mark; docs/systems/painter.md "Plant
## roles"): every wide grass tuft of the authored scatter is drawn as one quad turned to the view,
## on which painter_grass_mark.gdshader paints the tuft with blade strokes, in place of core's three
## crossed cards (which collapse to thin spikes seen from above). Painted only: Classic keeps the
## cards, and so does a crop (PainterFields) or a narrow tuft (reeds, rushes).
##
## How it swaps. A tuft species' card mesh is shared by every cell; its painted stand-in (the
## painter_plant material PainterSurfaces put on it) stays where it is. This host makes, once per
## species, a MARK MESH (quad()) carrying a MARK MATERIAL (the stand-in duplicated onto the mark's
## shader, so every wind, grow-in and fade uniform keeps its value) and points each cell's
## MultiMesh at it (multimesh.mesh), remembering nothing per node: a rebuilt node keeps its
## MultiMesh's mesh (AuthoredScatter._place_settled), a new one is caught as the scatter's child,
## and release() turns every node whose mesh is a mark mesh back to its card mesh. The shared
## card mesh is never edited.
##
## The pitch crossfade (the sheet's grass-mark-pitch, PITCH_NUMBER): 0 draws the mark at every
## pitch; a pitch P > 0 puts the card surfaces into the mark mesh beside the quad, and each tuft
## draws its cards below about P degrees of camera pitch and its mark above (painter_selector's
## grass_mark_on, in both shaders), so the oblique orbit can keep the cards' leafy patches.
##
## Tones: sync() copies the stand-in's tone and thinning uniforms (TONED) onto its mark, so the
## sheet's grass ramp, keep and frost reach the marks whenever PainterSurfaces re-tones. Tokens:
## the ground's token feet (PainterOcclusion's tok) are copied to the marks each frame they change,
## so a tuft beside a token's feet shrinks and a small token stands clear.

const SHADER := "res://painter/shaders/painter_grass_mark.gdshader"
## The sheet number: the camera pitch in degrees below which a tuft keeps its cards (0: never).
const PITCH_NUMBER := "grass-mark-pitch"
## A tuft is drawn as a mark when its half width is at least this share of its height
## (painter_selector's TUFT_WIDE: meadow grass, not reeds).
const WIDE := 0.7
## The uniforms copied from a tuft's stand-in onto its mark at every sync.
const TONED: Array[StringName] = [
	&"c_shade0",
	&"c_mid0",
	&"c_lit0",
	&"c_shade1",
	&"c_mid1",
	&"c_lit1",
	&"keep",
	&"keep_freq",
	&"frost",
	&"c_frost_lit",
	&"c_frost_shd",
	&"selector_height",
	&"selector_extent",
]
## The A/B switch (render jobs, tests): false keeps the shipped cards under Painted too.
static var enabled := true

## Card mesh id -> {"card": Mesh, "mark": ArrayMesh, "material": ShaderMaterial (the mark's),
## "stand_in": ShaderMaterial, "height": float, "extent": Vector3, "cards": bool (whether the mark
## mesh carries the card surfaces too)}.
var _species: Dictionary = {}
## The plant sources followed for new cells.
var _scatters: Array = []
## The pitch the marks were last laid out for (grass-mark-pitch).
var _pitch := 0.0
## The ground material the token feet are read from, and the last ones copied.
var _ground: ShaderMaterial = null
var _tok_n := -1
var _tok := PackedVector4Array()
var _watching := false


## Brings the marks up to date with `surfaces` (a PainterSurfaces): a mark for every wide grass
## species it painted, every cell of theirs pointed at its mark, the tones and the pitch copied.
## Puts the cards back instead when nothing is painted or enabled is off. Cheap when nothing is new.
func sync(surfaces: Object) -> void:
	if not enabled or not bool(surfaces.call("is_active")):
		release()
		return
	var applied: Dictionary = surfaces.get("applied")
	var sheet := PainterSheet.load_sheet(str(applied["sheet"]))
	_pitch = maxf(
		PainterSheet.number(sheet, applied["mood"], PITCH_NUMBER, applied["elevation"]), 0.0
	)
	var fresh := false
	for scatter in surfaces.call("scatters"):
		if not is_instance_valid(scatter):
			continue
		fresh = _add_species(scatter) or fresh
		if not scatter.child_entered_tree.is_connected(_on_scatter_child):
			scatter.child_entered_tree.connect(_on_scatter_child)
			_scatters.append(scatter)
			fresh = true
	for id: int in _species:
		var entry: Dictionary = _species[id]
		fresh = _lay_out(entry) or fresh
		_tone(entry)
	if fresh:
		for scatter in _scatters:
			if is_instance_valid(scatter):
				for node in (scatter as Node).find_children("*", "MultiMeshInstance3D", true, false):
					_swap(node)
	_ground = surfaces.call("ground_material")
	_tok_n = -1
	_watch()


## Puts every cell back on its card mesh and the stand-ins' pitch to 0, and stops following.
func release() -> void:
	var marks := {}
	for id: int in _species:
		marks[(_species[id]["mark"] as Mesh).get_instance_id()] = _species[id]["card"]
		(_species[id]["stand_in"] as ShaderMaterial).set_shader_parameter(&"mark_pitch", 0.0)
	for scatter in _scatters:
		if not is_instance_valid(scatter):
			continue
		if scatter.child_entered_tree.is_connected(_on_scatter_child):
			scatter.child_entered_tree.disconnect(_on_scatter_child)
		for node in (scatter as Node).find_children("*", "MultiMeshInstance3D", true, false):
			var mm := (node as MultiMeshInstance3D).multimesh
			if mm != null and mm.mesh != null and marks.has(mm.mesh.get_instance_id()):
				mm.mesh = marks[mm.mesh.get_instance_id()]
	_species.clear()
	_scatters.clear()
	_ground = null
	_unwatch()


## The marks' materials, one per species (tests, render jobs).
func materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for id: int in _species:
		out.append(_species[id]["material"])
	return out


## The mark mesh standing in for `card` (null when it has none).
func mark_of(card: Mesh) -> ArrayMesh:
	if card == null or not _species.has(card.get_instance_id()):
		return null
	return _species[card.get_instance_id()]["mark"]


## Whether a tuft of half size `extent` and `height` m painted with `stand_in` is drawn as a mark:
## grass (PainterPlantRoles.KIND_GRASS), wide (WIDE) and not a crop's blades. Pure.
static func is_mark_tuft(stand_in: Material, extent: Vector3, height: float) -> bool:
	var m := stand_in as ShaderMaterial
	if m == null or not m.has_meta(PainterSurfaces.META):
		return false
	if int(m.get_shader_parameter(&"kind")) != PainterPlantRoles.KIND_GRASS:
		return false
	if m.get_shader_parameter(&"tuft_blades") == true:
		return false
	return maxf(extent.x, extent.z) >= WIDE * maxf(height, 0.01)


## The mark mesh's arrays: one quad (UV.x across, UV.y 1 at the foot) for a tuft of half size
## `extent` and `height`; its corners only bound what culling sees (the shader places the quad
## toward the view). Pure.
static func quad(extent: Vector3, height: float) -> Array:
	var w := maxf(extent.x, extent.z) * 2.0
	var top := height * 2.5
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
		[Vector3(-w, 0.0, -w), Vector3(w, 0.0, -w), Vector3(-w, top, w), Vector3(w, top, w)]
	)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(
		[Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]
	)
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(
		[Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0)]
	)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 1, 3, 2])
	return arrays


## The box culling sees for a mark of a tuft of half size `extent` and `height`: a cube round the
## root that holds the largest quad the shader can draw (its reach up to about 1.8 times the half
## size, its top about 1.8 times the height, the whole lifted toward the eye by up to its reach).
## Pure.
static func bounds(extent: Vector3, height: float) -> AABB:
	var r := maxf(extent.x, extent.z) * 3.6 + height * 1.8 + 0.1
	return AABB(Vector3(-r, -r, -r), Vector3.ONE * r * 2.0)


# ---------------------------------------------------------------- species


## Makes the marks of `scatter`'s wide grass species not seen yet; true when one was added.
func _add_species(scatter: Object) -> bool:
	var added := false
	var species: Dictionary = scatter.call("resolved_species")
	for asset_id: String in species:
		var record: Dictionary = species[asset_id]
		var card := record["mesh"] as Mesh
		if card == null or card.get_surface_count() == 0 or _species.has(card.get_instance_id()):
			continue
		var stand_in := card.surface_get_material(0) as ShaderMaterial
		var extent := card.get_aabb().size * 0.5
		var height := maxf(float(record["height"]), 0.05)
		if not is_mark_tuft(stand_in, extent, height):
			continue
		var material := stand_in.duplicate() as ShaderMaterial
		material.shader = load(SHADER) as Shader
		material.set_meta(PainterSurfaces.META, true)
		material.set_meta(WindFoliage.META_STAND_IN, stand_in.get_meta(WindFoliage.META_STAND_IN))
		var mark := ArrayMesh.new()
		mark.custom_aabb = bounds(extent, height)
		_species[card.get_instance_id()] = {
			"card": card,
			"mark": mark,
			"material": material,
			"stand_in": stand_in,
			"height": height,
			"extent": extent,
			"cards": null,
		}
		added = true
	return added


## Builds `entry`'s mark mesh for the current pitch: the quad alone, or the card surfaces (their
## stand-ins) and the quad; true when it was (re)built.
func _lay_out(entry: Dictionary) -> bool:
	var with_cards := _pitch > 0.0
	if entry["cards"] == with_cards:
		return false
	entry["cards"] = with_cards
	var mark := entry["mark"] as ArrayMesh
	mark.clear_surfaces()
	if with_cards:
		var card := entry["card"] as Mesh
		for i in card.get_surface_count():
			mark.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, card.surface_get_arrays(i))
			mark.surface_set_material(i, card.surface_get_material(i))
	mark.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES, quad(entry["extent"], float(entry["height"]))
	)
	mark.surface_set_material(mark.get_surface_count() - 1, entry["material"])
	return true


## Copies `entry`'s stand-in tones onto its mark and sets the pitch on both.
func _tone(entry: Dictionary) -> void:
	var stand_in := entry["stand_in"] as ShaderMaterial
	var material := entry["material"] as ShaderMaterial
	for uniform in TONED:
		material.set_shader_parameter(uniform, stand_in.get_shader_parameter(uniform))
	material.set_shader_parameter(&"mark_pitch", _pitch)
	stand_in.set_shader_parameter(&"mark_pitch", _pitch)


# ---------------------------------------------------------------- cells


## Points `node`'s MultiMesh at its species' mark when it draws a card mesh this host marks.
func _swap(node: Node) -> void:
	if not is_instance_valid(node) or not node is MultiMeshInstance3D:
		return
	var mm := (node as MultiMeshInstance3D).multimesh
	if mm == null or mm.mesh == null or not _species.has(mm.mesh.get_instance_id()):
		return
	mm.mesh = _species[mm.mesh.get_instance_id()]["mark"]


func _on_scatter_child(node: Node) -> void:
	# (A chunk node may get its MultiMesh after add_child: look once it is in place.)
	_swap.call_deferred(node)


# ---------------------------------------------------------------- tokens


func _watch() -> void:
	if _watching:
		return
	_watching = true
	(Engine.get_main_loop() as SceneTree).process_frame.connect(_on_frame)


func _unwatch() -> void:
	if not _watching:
		return
	_watching = false
	var tree := Engine.get_main_loop() as SceneTree
	if tree.process_frame.is_connected(_on_frame):
		tree.process_frame.disconnect(_on_frame)


## Copies the ground's token feet onto the marks when they change.
func _on_frame() -> void:
	if _ground == null:
		return
	var n: Variant = _ground.get_shader_parameter(&"tok_n")
	var count := int(n) if n != null else 0
	var tok: Variant = _ground.get_shader_parameter(&"tok")
	var feet := tok as PackedVector4Array if tok is PackedVector4Array else PackedVector4Array()
	if count == _tok_n and (count == 0 or feet == _tok):
		return
	_tok_n = count
	_tok = feet
	for material in materials():
		material.set_shader_parameter(&"tok_n", count)
		if count > 0:
			material.set_shader_parameter(&"tok", feet)
