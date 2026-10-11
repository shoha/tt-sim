class_name FireField
extends Node3D

## The persistent ground fire of a map document, drawn (MapDocument.fire_mask; design:
## docs/plans/2026-10-11-fire-features/design.md section 4). One per map with a document, a
## child of the map root (MapSourceLoader adds it), so its frame is the document's.
##
## Placement is pure (plan_block): per diff block of the mask (MaskStroke.BLOCK samples, 10 m
## at the default spacing), a jittered lattice at FLAME_SPACING_M seeded by the map seed and
## the lattice point, so peers agree and re-planning one block moves nothing elsewhere. A
## point burns where the bilinear mask is at least EMBER_MIN and the ground is neither wet
## (the wet dressing's wet line) nor steeper than the cliff rule (TerrainRules); its height is
## the document's own triangle (ScatterGenerator.triangle_height). Where flames may stand is
## derived here and never saved: a river carved through a fire puts it out on screen and the
## fire comes back if the river is erased.
##
## The look (F1 placeholder): one camera-facing flame card per lattice point, a MultiMesh per
## burning block, the card painted once from FlameAtlas's first frames and coloured by its
## heat. Intensity sets the card's height (embers a low glow, a blaze tall tongues) and picks
## its frame. No LOD, lights, glow or smoke: those are the F3 probe's and F4's. The whole map
## holds at most MAX_FLAMES cards: a block re-planned when the budget is spent keeps an evenly
## spaced share of its points.

const NODE_NAME := "FireField"
## Lattice spacing of the flames, and how far each is moved off its lattice point (a share of
## the spacing, either way).
const FLAME_SPACING_M := 0.9
const JITTER := 0.35
## Intensity bands (mask bytes): below EMBER_MIN nothing burns.
const EMBER_MIN := 40
const FLAME_MIN := 110
const BLAZE_MIN := 200
## Cards on the whole map, at most.
const MAX_FLAMES := 1536
## A sample whose wet line (the wet dressing's alpha) is at least this does not burn.
const WET_LINE_MIN := 128
## A face steeper than this does not burn (the cliff rule's start).
const STEEP_DEG := TerrainRules.CLIFF_START_DEG
## Floats per planned flame: x, y, z (document metres), intensity 0..1, variant 0..1.
const STRIDE := 5
## A card's height at EMBER_MIN and at full intensity, and its width as a share of it.
const HEIGHT_M := Vector2(0.3, 1.5)
const ASPECT := 0.5
## The flame card's colours by heat: rim, amber body, pale core.
const RIM := Color(0.86, 0.22, 0.08)
const AMBER := Color(1.0, 0.56, 0.12)
const CORE := Color(1.0, 0.93, 0.62)

static var _mesh: QuadMesh = null
static var _material: StandardMaterial3D = null

var document: MapDocument = null
## block Vector2i -> MultiMeshInstance3D, for burning blocks only.
var _chunks: Dictionary = {}
## block Vector2i -> cards shown there.
var _counts: Dictionary = {}


## A field for `doc`, already drawn.
static func create(doc: MapDocument) -> FireField:
	var field := FireField.new()
	field.name = NODE_NAME
	field.document = doc
	field.rebuild()
	return field


## Re-plans the whole map (after a load or a whole-document change).
func rebuild() -> void:
	for block in _chunks:
		(_chunks[block] as Node).free()
	_chunks.clear()
	_counts.clear()
	if document == null:
		return
	refresh(Rect2i(0, 0, document.samples_x(), document.samples_z()))


## Re-plans the blocks the samples of `sample_rect` touch (a stroke's frame, an undo).
func refresh(sample_rect: Rect2i) -> void:
	if document == null or not sample_rect.has_area():
		return
	var blocks := blocks_of(document, sample_rect)
	var others := 0
	for block in _counts:
		if not block in blocks:
			others += int(_counts[block])
	var budget := maxi(MAX_FLAMES - others, 0)
	for block in blocks:
		var plan := plan_block(document, block)
		var shown := thin(plan, budget)
		budget -= shown.size() / STRIDE
		_show(block, shown)


## Cards shown on the whole map.
func flame_count() -> int:
	var total := 0
	for block in _counts:
		total += int(_counts[block])
	return total


## The diff blocks the samples of `sample_rect` touch, row by row.
static func blocks_of(doc: MapDocument, sample_rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var rect := sample_rect.intersection(Rect2i(0, 0, doc.samples_x(), doc.samples_z()))
	if not rect.has_area():
		return out
	@warning_ignore("integer_division")
	var first := rect.position / MaskStroke.BLOCK
	@warning_ignore("integer_division")
	var last := (rect.end - Vector2i.ONE) / MaskStroke.BLOCK
	for bz in range(first.y, last.y + 1):
		for bx in range(first.x, last.x + 1):
			out.append(Vector2i(bx, bz))
	return out


## The band of mask byte `intensity`: 0 none, 1 embers, 2 flames, 3 blaze.
static func band(intensity: int) -> int:
	if intensity >= BLAZE_MIN:
		return 3
	if intensity >= FLAME_MIN:
		return 2
	if intensity >= EMBER_MIN:
		return 1
	return 0


## The flames of diff block `block` of `doc` (see the header): STRIDE floats each. Pure and
## deterministic; empty without a fire mask.
static func plan_block(doc: MapDocument, block: Vector2i) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var count := doc.sample_count()
	if doc.fire_mask.size() != count or doc.heights.size() != count:
		return out
	var rect := MaskStroke.block_rect(doc, block)
	if not rect.has_area():
		return out
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	var low := -half + Vector2(rect.position) * step
	var high := -half + Vector2(rect.end) * step
	var wet := doc.water_dressing.size() == count * 4
	var flat_y := cos(deg_to_rad(STEEP_DEG))
	# Lattice points whose unjittered spot lies in [low, high): each belongs to one block.
	for iz in range(ceili(low.y / FLAME_SPACING_M), ceili(high.y / FLAME_SPACING_M)):
		for ix in range(ceili(low.x / FLAME_SPACING_M), ceili(high.x / FLAME_SPACING_M)):
			var key := (ix * 73856093) ^ (iz * 19349663)
			var jitter := Vector2(
				MaskBrush.sample_noise(doc.map_seed, key) - 0.5,
				MaskBrush.sample_noise(doc.map_seed + 1, key) - 0.5
			)
			var p := Vector2(ix, iz) * FLAME_SPACING_M + jitter * (2.0 * JITTER * FLAME_SPACING_M)
			if absf(p.x) > half.x or absf(p.y) > half.y:
				continue
			var at := (p + half) / step
			var heat := _bilinear(doc.fire_mask, columns, rows, at)
			if heat < EMBER_MIN:
				continue
			var nearest := doc.sample_index(
				clampi(roundi(at.x), 0, columns - 1), clampi(roundi(at.y), 0, rows - 1)
			)
			if wet and doc.water_dressing[nearest * 4 + 3] >= WET_LINE_MIN:
				continue
			var normal := ScatterGenerator.triangle_normal(doc.heights, columns, rows, at, step)
			if normal.y < flat_y:
				continue
			var y := ScatterGenerator.triangle_height(doc.heights, columns, rows, at)
			out.append_array(
				[p.x, y, p.y, heat / 255.0, MaskBrush.sample_noise(doc.map_seed + 2, key)]
			)
	return out


## At most `budget` flames of `plan`, evenly spaced through it. Pure.
static func thin(plan: PackedFloat32Array, budget: int) -> PackedFloat32Array:
	@warning_ignore("integer_division")
	var total := plan.size() / STRIDE
	if total <= budget:
		return plan
	var out := PackedFloat32Array()
	for j in budget:
		@warning_ignore("integer_division")
		var i := (j * total) / budget
		out.append_array(plan.slice(i * STRIDE, (i + 1) * STRIDE))
	return out


## A card's height (metres) at intensity `t` (0..1 of 255).
static func card_height(t: float) -> float:
	var lowest := float(EMBER_MIN) / 255.0
	return lerpf(HEIGHT_M.x, HEIGHT_M.y, clampf((t - lowest) / (1.0 - lowest), 0.0, 1.0))


static func _bilinear(mask: PackedByteArray, columns: int, rows: int, at: Vector2) -> float:
	var fx := clampf(at.x, 0.0, columns - 1)
	var fz := clampf(at.y, 0.0, rows - 1)
	var x0 := mini(floori(fx), columns - 2)
	var z0 := mini(floori(fz), rows - 2)
	var tx := fx - x0
	var tz := fz - z0
	var i := z0 * columns + x0
	var top := lerpf(mask[i], mask[i + 1], tx)
	var bottom := lerpf(mask[i + columns], mask[i + columns + 1], tx)
	return lerpf(top, bottom, tz)


func _show(block: Vector2i, plan: PackedFloat32Array) -> void:
	@warning_ignore("integer_division")
	var total := plan.size() / STRIDE
	var chunk: MultiMeshInstance3D = _chunks.get(block)
	if total == 0:
		if chunk != null:
			chunk.free()
		_chunks.erase(block)
		_counts.erase(block)
		return
	if chunk == null:
		chunk = MultiMeshInstance3D.new()
		chunk.name = "Fire_%d_%d" % [block.x, block.y]
		chunk.material_override = flame_material()
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = flame_mesh()
		chunk.multimesh = multimesh
		add_child(chunk)
		_chunks[block] = chunk
	var mm := chunk.multimesh
	mm.instance_count = total
	var box := AABB()
	for k in total:
		var o := k * STRIDE
		var at := Vector3(plan[o], plan[o + 1], plan[o + 2])
		var h := card_height(plan[o + 3])
		mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(h, h, h)), at))
		# Particle billboards read the frame from custom.z (StandardMaterial3D).
		mm.set_instance_custom_data(k, Color(0.0, 0.0, plan[o + 4], 0.0))
		var card := AABB(at - Vector3(h, 0.0, h), Vector3(2.0 * h, 1.5 * h, 2.0 * h))
		box = card if k == 0 else box.merge(card)
	chunk.custom_aabb = box
	_counts[block] = total


## The flame card: a quad standing on its foot (shared).
static func flame_mesh() -> QuadMesh:
	if _mesh == null:
		_mesh = QuadMesh.new()
		_mesh.size = Vector2(ASPECT, 1.0)
		_mesh.center_offset = Vector3(0.0, 0.5, 0.0)
	return _mesh


## The flame cards' material (shared): unshaded, camera-facing, its flipbook frame per card.
static func flame_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_material.particles_anim_h_frames = FlameAtlas.FRAMES
		_material.particles_anim_v_frames = 1
		_material.particles_anim_loop = true
		_material.albedo_texture = ImageTexture.create_from_image(flame_image())
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material


## FlameAtlas's flipbook coloured by its heat (red) with its coverage (green) as alpha.
static func flame_image() -> Image:
	var source := FlameAtlas.paint()
	if source.get_format() != Image.FORMAT_RG8:
		source.convert(Image.FORMAT_RG8)
	var size := source.get_size()
	var out := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			var texel := source.get_pixel(x, y)
			out.set_pixel(x, y, heat_color(texel.r, texel.g))
	return out


## The card's colour at `heat` (0..1) with coverage `alpha`. Pure.
static func heat_color(heat: float, alpha: float) -> Color:
	var color := RIM.lerp(AMBER, clampf((heat - 0.12) / 0.45, 0.0, 1.0))
	color = color.lerp(CORE, clampf((heat - 0.57) / 0.43, 0.0, 1.0))
	color.a = alpha
	return color
