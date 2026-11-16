class_name CursorTints
extends RefCounted

## The tint of a brush's ring for what it paints: a biome's or a palette surface's mean picture
## colour, lifted toward white so the ring reads on dark ground too. AuthoringController tints the
## Biome and Paint brushes with these; PlayEvents does the same for the GM's live brushes.


## The cursor tint of a biome: its thumbnail's mean colour, lifted toward white so the ring
## reads on dark ground too.
static func biome_tint(biome_id: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> Color:
	var thumbnail: Variant = PaletteLibrary.biome(biome_id, root).get("thumbnail", "")
	var texture := SwatchTextures.palette_thumbnail(thumbnail, 8, root)
	if texture == null:
		return Color(0.7, 0.9, 0.6)
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Color(0.7, 0.9, 0.6)
	image.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	var mean := image.get_pixel(0, 0)
	mean.a = 1.0
	return mean.lerp(Color.WHITE, 0.4)


## The cursor tint of a palette surface: its swatch's mean colour, lifted toward white like
## biome_tint so the ring reads on dark ground.
static func surface_tint(surface: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> Color:
	var albedo: Variant = PaletteLibrary.surfaces(root).get(surface, {}).get("albedo", "")
	var texture := SwatchTextures.palette_thumbnail(
		String(albedo), AuthoringPanel.PAINT_THUMB_PX, root
	)
	var image := texture.get_image() if texture else null
	if image == null or image.is_empty():
		return Color(0.9, 0.82, 0.66)
	image = image.duplicate() as Image
	image.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	var mean := image.get_pixel(0, 0)
	mean.a = 1.0
	return mean.lerp(Color.WHITE, 0.4)
