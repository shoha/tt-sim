class_name AvatarFaceIcons
extends RefCounted

## Tile icons for the builder's Face pane, made from the kit's face sheet: each cell is
## cropped to the painted mark with a little air round it and laid over a skin-coloured
## square, so an eye fills its tile instead of floating small in a 128 px cell and a brow,
## a mouth or a blush (painted for skin, invisible on the panel's dark surface) reads at a
## glance. Built once per builder from the sheet's image (the kit imports it lossless).

## The square's side in pixels (the tile draws it at this size).
const ICON_PX := 44
## Air round the painted mark, as a share of its longer side.
const AIR := 0.35
## The least crop, as a share of the cell, so a tiny mark is not blown up to a blur.
const MIN_CROP := 0.4
## Skin behind every cell: the kit's second skin (a mid tone that shows ink and blush).
const SKIN_INDEX := 1
const FALLBACK_SKIN := Color("#f7c39c")


## kind -> Array of Texture2D, one per cell of the sheet, in cell order; the marks row's
## first cell ("none") is the bare skin square.
static func build(kit: AvatarKit) -> Dictionary:
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
	var skin := _skin(kit)
	for kind in AvatarRecipe.FACE_KINDS:
		var row := rows.find(kind)
		if row < 0:
			continue
		var icons: Array = []
		for i in int(counts.get(kind, 0)):
			icons.append(_icon(sheet, Rect2i(i * cell, row * cell, cell, cell), skin))
		out[kind] = icons
	return out


static func _skin(kit: AvatarKit) -> Color:
	var skins: Array = (kit.manifest.get("colour_sets", {}) as Dictionary).get("skin", [])
	if skins.size() > SKIN_INDEX:
		return Color.html(String(skins[SKIN_INDEX][0]))
	return FALLBACK_SKIN


static func _icon(sheet: Image, cell_rect: Rect2i, skin: Color) -> ImageTexture:
	var cell := sheet.get_region(cell_rect)
	var side := cell_rect.size.x
	var used := cell.get_used_rect()
	var crop := side
	var origin := Vector2i.ZERO
	if used.size.x > 0 and used.size.y > 0:
		var longest := maxi(used.size.x, used.size.y)
		crop = clampi(int(longest * (1.0 + 2.0 * AIR)), int(side * MIN_CROP), side)
		var centre := used.position + used.size / 2
		origin = (centre - Vector2i(crop, crop) / 2).clamp(
			Vector2i.ZERO, Vector2i(side - crop, side - crop)
		)
	var icon := Image.create(crop, crop, false, Image.FORMAT_RGBA8)
	icon.fill(skin)
	icon.blend_rect(cell, Rect2i(origin, Vector2i(crop, crop)), Vector2i.ZERO)
	icon.resize(ICON_PX, ICON_PX, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(icon)
