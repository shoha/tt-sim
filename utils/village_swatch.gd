class_name VillageSwatch
extends RefCounted

## The picture on a Village tool kit tile: the kit's road surface and its plaza surface in one
## square, split along the diagonal (road to the upper left, plaza to the lower right), so the
## author sees what the ground of a village will look like before picking it. The surfaces'
## thumbnails come from SwatchTextures (the Paint tiles' own); the split is a pure image function.


## `road` and `plaza` (square images of one size) joined along the anti-diagonal: the upper left
## triangle is the road, the rest the plaza, with a one pixel paper-light seam between them.
static func split(road: Image, plaza: Image) -> Image:
	var side := road.get_width()
	var out := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var seam := Color(1.0, 0.97, 0.88, 0.95)
	for y in side:
		for x in side:
			var along := x + y
			if along == side - 1:
				out.set_pixel(x, y, seam)
			elif along < side - 1:
				out.set_pixel(x, y, road.get_pixel(x, y))
			else:
				out.set_pixel(x, y, plaza.get_pixel(x, y))
	return out


## The tile picture of kit `kit` at `size` pixels, from the surfaces of palette `root`; a surface
## the palette lacks is drawn as the swatch fallback grey (SwatchTextures).
static func kit_texture(kit: String, root: String, size: int) -> Texture2D:
	var ground := VillagePlazas.ground_of(kit)
	var surfaces := PaletteLibrary.surfaces(root)
	var road := _image(str(ground.get("road", "")), surfaces, root, size)
	var plaza := _image(str(ground.get("plaza", "")), surfaces, root, size)
	return ImageTexture.create_from_image(split(road, plaza))


static func _image(surface: String, surfaces: Dictionary, root: String, size: int) -> Image:
	var albedo := str(surfaces.get(surface, {}).get("albedo", ""))
	var image := SwatchTextures.palette_thumbnail(albedo, size, root).get_image()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image
