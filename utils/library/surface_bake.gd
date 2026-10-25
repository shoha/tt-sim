class_name SurfaceBake
extends RefCounted

## The pure half of the content library's surfaces (design doc 2.7): what a surface set is, how
## its files are checked, and how a PNG becomes the texture the editor import would have made.
## No files and no scene tree: the registry hands over text and PNG header bytes, SurfaceStore
## and SurfaceCache do the I/O.
##
## A set is `surfaces/<name>/{albedo,normal,orm,height}.png` plus `surface.json`. The bake gives
## each map the format and mip chain the editor import gives the installed palette's surfaces
## (measured 2026-10-24 on Godot 4.7.2 against ash, cliff and grass_savanna): albedo BPTC
## (BC7, format 22) from sRGB, normal RGTC (BC5, format 21) renormalised on the mips, ORM S3TC
## (BC1, format 17) from RGB, height L8; every map with a full mip chain. Normal, ORM and height
## are byte-identical to the import; albedo is the same format with a handful of block bytes
## different (the import's BC7 encoder and ours disagree on a few ties), decoding to the same
## 8-bit colours. S0 had ORM at GENERIC source, which picks RGTC for an ORM whose blue is empty
## (format 21): the source must be sRGB (or channels RGB) to match the import.

const KINDS: Array[String] = ["albedo", "normal", "orm", "height"]
const INFO_KEYS: Array[String] = ["label", "kind", "role", "tile_m", "albedo_mean_linear"]
const ROLES: Array[String] = ["ground", "cliff", "built"]
## Image side caps: a map is at least one block and at most this many pixels a side.
const MIN_SIZE := 4
const MAX_SIZE := 2048
## The size the palette contract gives every map (an array holds one size per kind).
const EXPECTED_SIZE := 1024
const MAX_SURFACES := 64
const MAX_INFO_BYTES := 16384
const PNG_HEADER_BYTES := 33
const PNG_SIGNATURE: PackedByteArray = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
const MAX_TEXT := 128
const MIN_TILE_M := 0.001
const MAX_TILE_M := 10000.0

## PNG colour types that carry at least a red and a green channel (a normal map needs both).
const _COLOUR_TYPES: Array[int] = [2, 3, 6]


## {ok, width, height, bit_depth, color_type, interlace} of the first PNG_HEADER_BYTES bytes of
## a file, or {ok: false, error}. Never raises.
static func png_header(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < PNG_HEADER_BYTES:
		return {"ok": false, "error": "not a PNG (too short)"}
	if bytes.slice(0, 8) != PNG_SIGNATURE:
		return {"ok": false, "error": "not a PNG (bad signature)"}
	if bytes.slice(12, 16).get_string_from_ascii() != "IHDR":
		return {"ok": false, "error": "not a PNG (no IHDR)"}
	return {
		"ok": true,
		"width": _be32(bytes, 16),
		"height": _be32(bytes, 20),
		"bit_depth": int(bytes[24]),
		"color_type": int(bytes[25]),
		"interlace": int(bytes[28]),
	}


static func _be32(bytes: PackedByteArray, at: int) -> int:
	return (
		(int(bytes[at]) << 24)
		| (int(bytes[at + 1]) << 16)
		| (int(bytes[at + 2]) << 8)
		| bytes[at + 3]
	)


## Problems with one map's PNG header (`header` from png_header, or absent: `{}` for a missing
## file). `errors` block the set, `warnings` do not.
static func check_png(
	header: Dictionary, kind: String, label: String, errors: Array[String], warnings: Array[String]
) -> void:
	if header.is_empty():
		return
	if not header.get("ok", false):
		errors.append("%s %s: %s" % [label, kind, String(header.get("error", "unreadable"))])
		return
	var width := int(header["width"])
	var height := int(header["height"])
	if width < MIN_SIZE or height < MIN_SIZE or width > MAX_SIZE or height > MAX_SIZE:
		errors.append(
			(
				"%s %s: %dx%d is outside %d to %d pixels a side"
				% [label, kind, width, height, MIN_SIZE, MAX_SIZE]
			)
		)
	var depth := int(header["bit_depth"])
	if depth != 8 and depth != 16:
		errors.append("%s %s: bit depth %d (8 or 16 expected)" % [label, kind, depth])
	if kind == "normal" and not int(header["color_type"]) in _COLOUR_TYPES:
		errors.append(
			"%s normal: a normal map needs colour channels (PNG colour type 2 or 6)" % label
		)
	if width != EXPECTED_SIZE or height != EXPECTED_SIZE:
		warnings.append(
			(
				"%s %s: %dx%d is not %d; the ground arrays draw a mismatched kind uncompressed"
				% [label, kind, width, height, EXPECTED_SIZE]
			)
		)


## {ok, info, errors, warnings} for the text of a surface.json. `info` is {label, kind, role,
## tile_m} plus albedo_mean_linear (three 0..1 numbers) when given. A missing tile_m is an error
## (the validator needs it); an absent or unknown role is a warning and reads as ground.
static func check_info(text: String, name: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var out := {"ok": false, "info": {}, "errors": errors, "warnings": warnings}
	var where := "surfaces/%s/surface.json" % name
	if text == "":
		errors.append("%s is missing or empty" % where)
		return out
	if text.to_utf8_buffer().size() > MAX_INFO_BYTES:
		errors.append("%s is over %d bytes" % [where, MAX_INFO_BYTES])
		return out
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		errors.append("%s is not a valid JSON object" % where)
		return out
	var data: Dictionary = json.data
	for key: Variant in data:
		if not String(key) in INFO_KEYS:
			warnings.append("%s: unknown key '%s' (ignored)" % [where, _short(String(key))])
	var info := {}
	info["label"] = _text(data.get("label"), pretty_name(name))
	info["kind"] = _text(data.get("kind"), "")
	var role: Variant = data.get("role")
	if role is String and role in ROLES:
		info["role"] = role
	else:
		warnings.append("%s: role is missing or unknown; treated as ground" % where)
		info["role"] = "ground"
	var tile: Variant = data.get("tile_m")
	if not (tile is int or tile is float) or not is_finite(float(tile)):
		errors.append("%s: tile_m must be a number" % where)
	elif float(tile) < MIN_TILE_M or float(tile) > MAX_TILE_M:
		errors.append("%s: tile_m must be from %s to %s" % [where, MIN_TILE_M, MAX_TILE_M])
	else:
		info["tile_m"] = float(tile)
	var mean: Variant = data.get("albedo_mean_linear")
	if mean is Array and (mean as Array).size() == 3 and (mean as Array).all(_is_unit):
		info["albedo_mean_linear"] = (mean as Array).map(func(v: Variant) -> float: return float(v))
	elif mean != null:
		warnings.append(
			"%s: albedo_mean_linear must be three numbers from 0 to 1 (ignored)" % where
		)
	out["info"] = info
	out["ok"] = errors.is_empty()
	return out


static func _is_unit(value: Variant) -> bool:
	return (
		(value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= 1
	)


static func _text(value: Variant, fallback: String) -> String:
	if value is String and String(value).length() <= MAX_TEXT:
		return String(value)
	return fallback


## "crystal_sand" -> "Crystal sand".
static func pretty_name(name: String) -> String:
	var words := name.replace("_", " ").strip_edges()
	return words.substr(0, 1).to_upper() + words.substr(1) if words != "" else name


## The palette surface entry of a library surface: the four map paths relative to the palette
## root (SurfaceStore resolves them: they are unique per runtime name, so two libraries'
## surfaces of one local name never collide), tile_m, kind, role and the optional mean.
## `maps` lists the kinds whose PNG exists.
static func palette_entry(runtime_name: String, info: Dictionary, maps: Array) -> Dictionary:
	var entry := {
		"tile_m": float(info.get("tile_m", 1.0)),
		"kind": String(info.get("kind", "")),
		"role": String(info.get("role", "ground")),
	}
	for kind in KINDS:
		entry[kind] = relative_path(runtime_name, kind) if kind in maps else ""
	if info.has("albedo_mean_linear"):
		entry["albedo_mean_linear"] = (info["albedo_mean_linear"] as Array).duplicate()
	return entry


static func relative_path(runtime_name: String, kind: String) -> String:
	return "surfaces/%s/%s.png" % [runtime_name, kind]


## `image` (a decoded PNG) as the imported texture of `kind` would be, or null when it is
## empty or over the size cap. A new Image; `image` is left as it was.
static func bake(image: Image, kind: String) -> Image:
	if image == null or image.is_empty() or image.is_compressed():
		return null
	if maxi(image.get_width(), image.get_height()) > MAX_SIZE:
		return null
	var out := image.duplicate() as Image
	out.clear_mipmaps()
	match kind:
		"albedo":
			_to_colour(out)
			out.generate_mipmaps()
			out.compress(Image.COMPRESS_BPTC, Image.COMPRESS_SOURCE_SRGB)
		"normal":
			_to_colour(out)
			out.generate_mipmaps(true)
			out.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_NORMAL)
		"orm":
			_to_colour(out)
			out.generate_mipmaps()
			out.compress_from_channels(Image.COMPRESS_S3TC, Image.USED_CHANNELS_RGB)
		"height":
			if out.get_format() != Image.FORMAT_L8:
				out.convert(Image.FORMAT_L8)
			out.generate_mipmaps()
		_:
			return null
	return out


## RGB8, or RGBA8 when the PNG carries alpha: what the import compresses from.
static func _to_colour(image: Image) -> void:
	var format := image.get_format()
	if format != Image.FORMAT_RGB8 and format != Image.FORMAT_RGBA8:
		image.convert(
			Image.FORMAT_RGBA8 if image.detect_alpha() != Image.ALPHA_NONE else Image.FORMAT_RGB8
		)


## The format a baked map of `kind` has.
static func format_of(kind: String) -> int:
	match kind:
		"albedo":
			return Image.FORMAT_BPTC_RGBA
		"normal":
			return Image.FORMAT_RGTC_RG
		"orm":
			return Image.FORMAT_DXT1
		_:
			return Image.FORMAT_L8


## The byte size of a `width` x `height` image of `format` with a full mip chain, or -1 for a
## format the bake does not produce. Block formats cost one block per 4x4 pixels, at least one
## block per mip.
static func data_size(format: int, width: int, height: int) -> int:
	var block := 0
	match format:
		Image.FORMAT_L8:
			block = 0
		Image.FORMAT_DXT1:
			block = 8
		Image.FORMAT_RGTC_RG, Image.FORMAT_BPTC_RGBA:
			block = 16
		_:
			return -1
	var total := 0
	var w := width
	var h := height
	while true:
		if block == 0:
			total += w * h
		else:
			total += maxi(1, (w + 3) / 4) * maxi(1, (h + 3) / 4) * block
		if w == 1 and h == 1:
			break
		w = maxi(1, w / 2)
		h = maxi(1, h / 2)
	return total


## The mean colour (linear) of a baked or imported albedo image: its last mip, decoded. Black
## when the image cannot be read.
static func mean_albedo_linear(albedo: Image) -> Color:
	if albedo == null or albedo.is_empty():
		return Color(0, 0, 0)
	var image := albedo.duplicate() as Image
	if image.is_compressed() and image.decompress() != OK:
		return Color(0, 0, 0)
	image.convert(Image.FORMAT_RGBA8)
	if not image.has_mipmaps():
		image.generate_mipmaps()
	var offset := image.get_mipmap_offset(image.get_mipmap_count())
	var data := image.get_data()
	return (
		Color(data[offset] / 255.0, data[offset + 1] / 255.0, data[offset + 2] / 255.0)
		. srgb_to_linear()
	)


static func _short(text: String) -> String:
	return text if text.length() <= 48 else text.substr(0, 45) + "..."
