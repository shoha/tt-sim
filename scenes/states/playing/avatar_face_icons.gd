class_name AvatarFaceIcons
extends RefCounted

## Tile icons for the builder's Face pane, made from the kit's face sheet and painted on the
## avatar's own skin (the base colour of the picked skin swatch), so a blush or a pale brow
## reads as it will on the figure. Eyes and mouths are cropped to the painted mark with a
## little air, so an eye fills its tile instead of floating small in a 128 px cell. Brows and
## marks are thin or faint on their own (a 10 px stroke in a wide cell, a few freckles), so
## their tiles show them in the face they belong to: the candidate at full strength over the
## avatar's other picks faded back (CONTEXT_ALPHA), cropped to the part of the face that
## kind lives in (CONTEXT), which reads as the expression it makes.
##
## create() reads, crops and scales the sheet once per builder (every layer at ICON_PX, its
## transparent pixels given their neighbours' colour first so scaling leaves no dark rim);
## update() then only blends layers and refills the textures in place (ImageTexture.update,
## so the tiles keep them): a skin change repaints every tile, a face pick only the
## in-context ones.

## The icon's side in pixels (the tile draws it at this size).
const ICON_PX := 128
## Air round the painted mark, as a share of its longer side.
const AIR := 0.35
## The least crop, as a share of the cell, so a tiny mark is not blown up to a blur.
const MIN_CROP := 0.4
## Air round the face region of the in-context tiles.
const FACE_AIR := 0.08
## In-context kinds, each with the kinds whose marks (over every cell) bound its crop; the
## other picks shown in it are every other kind.
const CONTEXT := {"brows": ["eyes", "brows"], "marks": ["eyes", "marks", "mouths"]}
const CONTEXT_ALPHA := 0.32
const FALLBACK_SKIN := Color("#f7c39c")

## kind -> Array of ImageTexture, one per cell in cell order (the marks row's first cell,
## "none", is the bare skin or the faded face).
var textures: Dictionary = {}

## kind -> Array of Image at ICON_PX: each cell's tile layer.
var _crops: Dictionary = {}
## in-context kind -> other kind -> Array of Image at ICON_PX: the other kind's cells in
## that kind's crop.
var _context: Dictionary = {}
var _skin := Color(0, 0, 0, 0)
var _face: Dictionary = {}


## Icons for `kit`'s face sheet, painted on `skin` with `face` as the other picks; an
## instance with no textures when the kit has no sheet.
static func create(kit: AvatarKit, skin: Color, face: Dictionary) -> AvatarFaceIcons:
	var icons := AvatarFaceIcons.new()
	var cells := _cells(kit)
	if cells.is_empty():
		return icons
	var side: int = (cells.values()[0][0] as Image).get_width()
	for kind in cells:
		var crops: Array = []
		var tex: Array = []
		var region := Rect2i()
		if CONTEXT.has(kind):
			region = _square_round(_used(cells, CONTEXT[kind]), side, FACE_AIR)
			var others := {}
			for other in cells:
				if other != kind:
					others[other] = _scaled(cells[other], region)
			icons._context[kind] = others
		for image: Image in cells[kind]:
			var crop := (
				region if CONTEXT.has(kind) else _square_round(image.get_used_rect(), side, AIR)
			)
			crops.append(_scale(image.get_region(crop)))
			var blank := Image.create(ICON_PX, ICON_PX, false, Image.FORMAT_RGBA8)
			tex.append(ImageTexture.create_from_image(blank))
		icons._crops[kind] = crops
		icons.textures[kind] = tex
	icons.update(skin, face)
	return icons


## The base colour of the skin swatch `recipe` picks (the swatch triple's first entry).
static func skin_colour(kit: AvatarKit, recipe: Dictionary) -> Color:
	if kit == null:
		return FALLBACK_SKIN
	var skins: Array = (kit.manifest.get("colour_sets", {}) as Dictionary).get("skin", [])
	var index := int((recipe.get("colours", {}) as Dictionary).get("skin", 0))
	if index >= 0 and index < skins.size():
		return Color.html(String(skins[index][0]))
	return FALLBACK_SKIN


## Repaints the tiles for `skin` and the other picks in `face` (kind -> cell index); only
## what those change.
func update(skin: Color, face: Dictionary) -> void:
	var skin_changed := skin != _skin
	var face_changed := false
	for kind in AvatarRecipe.FACE_KINDS:
		face_changed = face_changed or int(face.get(kind, 0)) != int(_face.get(kind, -1))
	_skin = skin
	_face = face.duplicate()
	for kind in textures:
		var in_context := CONTEXT.has(kind)
		if not skin_changed and not (in_context and face_changed):
			continue
		var tex: Array = textures[kind]
		for i in tex.size():
			(tex[i] as ImageTexture).update(_paint(kind, i, in_context))


## One tile: the skin, then (in-context kinds) the other picks under a skin-coloured veil
## that leaves CONTEXT_ALPHA of them showing, then the cell itself.
func _paint(kind: String, index: int, in_context: bool) -> Image:
	var image := Image.create(ICON_PX, ICON_PX, false, Image.FORMAT_RGBA8)
	image.fill(_skin)
	var whole := Rect2i(0, 0, ICON_PX, ICON_PX)
	if in_context:
		var others: Dictionary = _context[kind]
		for other in AvatarKit.FACE_ORDER:
			var cells: Array = others.get(other, [])
			if not cells.is_empty():
				var pick := clampi(int(_face.get(other, 0)), 0, cells.size() - 1)
				image.blend_rect(cells[pick], whole, Vector2i.ZERO)
		var veil := Image.create(ICON_PX, ICON_PX, false, Image.FORMAT_RGBA8)
		veil.fill(Color(_skin, 1.0 - CONTEXT_ALPHA))
		image.blend_rect(veil, whole, Vector2i.ZERO)
	image.blend_rect(_crops[kind][index], whole, Vector2i.ZERO)
	return image


## kind -> Array of the sheet's cells (RGBA8, transparent pixels coloured like their
## neighbours); empty when the kit has no sheet.
static func _cells(kit: AvatarKit) -> Dictionary:
	var out := {}
	if kit == null or kit.face_sheet == null:
		return out
	var sheet := kit.face_sheet.get_image()
	if sheet == null:
		return out
	if sheet.is_compressed():
		sheet.decompress()
	sheet.convert(Image.FORMAT_RGBA8)
	var faces: Dictionary = kit.manifest.get("face_sheet", {})
	var cell := int(faces.get("cell_px", 128))
	var rows: Array = faces.get("row_order", AvatarRecipe.FACE_KINDS)
	var counts := kit.face_counts()
	for kind in AvatarRecipe.FACE_KINDS:
		var row := rows.find(kind)
		if row < 0 or int(counts.get(kind, 0)) == 0:
			continue
		var images: Array = []
		for i in int(counts.get(kind, 0)):
			var image := sheet.get_region(Rect2i(i * cell, row * cell, cell, cell))
			image.fix_alpha_edges()
			images.append(image)
		out[kind] = images
	return out


## The union of the painted marks of every cell of `kinds`.
static func _used(cells: Dictionary, kinds: Array) -> Rect2i:
	var region := Rect2i()
	for kind in kinds:
		for image: Image in cells.get(kind, []):
			var used := image.get_used_rect()
			if used.has_area():
				region = used if not region.has_area() else region.merge(used)
	return region


static func _scaled(images: Array, region: Rect2i) -> Array:
	var out: Array = []
	for image: Image in images:
		out.append(_scale(image.get_region(region)))
	return out


static func _scale(image: Image) -> Image:
	image.resize(ICON_PX, ICON_PX, Image.INTERPOLATE_LANCZOS)
	return image


## A square inside a `side`-pixel cell round `used`, `air` of its longer side wider, and no
## smaller than MIN_CROP of the cell; the whole cell when `used` is empty.
static func _square_round(used: Rect2i, side: int, air: float) -> Rect2i:
	if not used.has_area():
		return Rect2i(0, 0, side, side)
	var longest := maxi(used.size.x, used.size.y)
	var crop := clampi(int(longest * (1.0 + 2.0 * air)), int(side * MIN_CROP), side)
	var centre := used.position + used.size / 2
	var origin := (centre - Vector2i(crop, crop) / 2).clamp(
		Vector2i.ZERO, Vector2i(side - crop, side - crop)
	)
	return Rect2i(origin, Vector2i(crop, crop))
