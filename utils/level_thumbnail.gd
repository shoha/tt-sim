class_name LevelThumbnail
extends RefCounted

## Fits a captured frame into the level thumbnail size (see LevelManager).


static func fit(image: Image) -> Image:
	var out := image.duplicate() as Image
	out.resize(
		LevelManager.THUMBNAIL_SIZE.x, LevelManager.THUMBNAIL_SIZE.y, Image.INTERPOLATE_LANCZOS
	)
	if out.get_format() != Image.FORMAT_RGB8:
		out.convert(Image.FORMAT_RGB8)
	return out
