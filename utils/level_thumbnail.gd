class_name LevelThumbnail
extends RefCounted

## Fits a captured frame into the level thumbnail size (LevelManager.THUMBNAIL_SIZE):
## scale so the frame covers 320x180, then crop the overflow evenly on both
## sides, so the centre of the capture is the centre of the card.


static func fit(image: Image) -> Image:
	var target := LevelManager.THUMBNAIL_SIZE
	var source := image.duplicate() as Image
	var scale := maxf(
		float(target.x) / float(source.get_width()), float(target.y) / float(source.get_height())
	)
	var scaled_w := maxi(target.x, int(round(source.get_width() * scale)))
	var scaled_h := maxi(target.y, int(round(source.get_height() * scale)))
	source.resize(scaled_w, scaled_h, Image.INTERPOLATE_LANCZOS)
	var origin := Vector2i((scaled_w - target.x) / 2, (scaled_h - target.y) / 2)
	var out := source.get_region(Rect2i(origin, target))
	if out.get_format() != Image.FORMAT_RGB8:
		out.convert(Image.FORMAT_RGB8)
	return out
