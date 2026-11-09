extends SceneTree

## Trims the grey window margin off sheet JPGs, limits them to 1600 px wide and writes them to
## one or more folders (headless). Pairs are `source=name.jpg`, separated by `;`.
##
##   godot --headless --path <project> --script res://tools/texture_ab/jpg_fit.gd -- \
##       "--pairs=a.jpg=textures_a.jpg;b.jpg=textures_b.jpg" --dirs=<folder>,<folder>

const MAX_WIDTH := 1600


func _initialize() -> void:
	var pairs: PackedStringArray = []
	var dirs: PackedStringArray = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pairs="):
			pairs = arg.trim_prefix("--pairs=").split(";")
		elif arg.begins_with("--dirs="):
			dirs = arg.trim_prefix("--dirs=").split(",")
	for dir in dirs:
		DirAccess.make_dir_recursive_absolute(dir)
	for pair in pairs:
		var at := pair.rfind("=")
		var image := Image.load_from_file(pair.substr(0, at))
		if image == null or image.is_empty():
			push_error("cannot read " + pair)
			continue
		image = _trim(image)
		if image.get_width() > MAX_WIDTH:
			var h := roundi(image.get_height() * float(MAX_WIDTH) / image.get_width())
			image.resize(MAX_WIDTH, h, Image.INTERPOLATE_LANCZOS)
		for dir in dirs:
			image.save_jpg(dir.path_join(pair.substr(at + 1)), 0.92)
		print("fit ", pair.substr(at + 1), " ", image.get_size())
	quit(0)


## The image without the flat grey margin at its right and bottom (the window was larger than the
## sheet): the last column or row that differs from the corner colour.
func _trim(image: Image) -> Image:
	var corner := image.get_pixel(image.get_width() - 1, image.get_height() - 1)
	var right := image.get_width() - 1
	var y := image.get_height() / 2
	while right > 0 and _near(image.get_pixel(right, y), corner):
		right -= 1
	var bottom := image.get_height() - 1
	var x := image.get_width() / 2
	while bottom > 0 and _near(image.get_pixel(x, bottom), corner):
		bottom -= 1
	var width := mini(right + 6, image.get_width())
	var height := mini(bottom + 6, image.get_height())
	return image.get_region(Rect2i(0, 0, width, height))


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.06
