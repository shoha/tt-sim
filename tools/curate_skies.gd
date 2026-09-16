extends SceneTree

## Curates the shipped HDRI skies from tools/skies_manifest.json. For each entry it
## writes assets/skies/<key>.exr (1024x512, Lanczos) with a VRAM-compressed import
## sidecar, <key>_tile.png (24x24, sky band over ground band, matching the painted
## gradient tiles), <key>_preview.png (280x70, the full horizon band, tone-mapped),
## measures the sun azimuth (brightest column above the horizon) and an exposure
## multiplier that brings the sky band's mean luminance to the clear-day gradient's,
## then writes assets/skies/curation_report.json and prints SKY_PRESETS entries and
## licence rows to paste. Tile and preview PNGs are tone-mapped with a display exposure
## normalised per sky, independent of the engine energy, so thumbnails stay readable
## whatever energy is tuned to later. Idempotent; only touches assets/skies/.
## Run: godot --headless --editor --path . --script res://tools/curate_skies.gd --quit-after 3
## (--editor is required for Image.save_exr; --quit-after ends the editor process.)

const MANIFEST_PATH := "res://tools/skies_manifest.json"
const OUT_DIR := "res://assets/skies/"
const REPORT_PATH := "res://assets/skies/curation_report.json"
const PANORAMA_WIDTH := 1024
const TILE_SIZE := 24
const TILE_HORIZON_ROW := 16
const PREVIEW_WIDTH := 280
const PREVIEW_HEIGHT := 70
const PREVIEW_TOP := 0.20
const PREVIEW_BOTTOM := 0.60
const TILE_SKY_TOP := 0.15
const TILE_GROUND_BOTTOM := 0.75
const SUN_BAND := 0.45
const ENERGY_BAND := 0.5
const ENERGY_MIN := 0.05
const ENERGY_MAX := 4.0
const PREVIEW_TARGET_LUMINANCE := 0.35
## Only the params Godot needs to see before its first import; the editor rewrites the
## sidecar with uid, dest paths and every remaining param on import.
const IMPORT_SIDECAR := """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


func _init() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if manifest == null or not manifest is Array:
		push_error("curate_skies: cannot read %s" % MANIFEST_PATH)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var reference := _gradient_reference_luminance()
	var report := {}
	var skipped := 0
	for entry in manifest:
		var row := _curate(entry, reference)
		if row.is_empty():
			skipped += 1
			continue
		report[entry["key"]] = row
	var report_file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if report_file == null:
		push_error("curate_skies: cannot write %s" % REPORT_PATH)
		quit(1)
		return
	report_file.store_string(JSON.stringify(report, "\t"))
	report_file.close()
	_print_entries(manifest, report)
	if skipped > 0:
		push_error("curate_skies: %d entr%s skipped" % [skipped, "y" if skipped == 1 else "ies"])
		quit(1)
	else:
		quit()


func _curate(entry: Dictionary, reference: float) -> Dictionary:
	var key: String = entry["key"]
	var source: String = entry["source"]
	var image := Image.load_from_file(source)
	if image == null:
		push_error("curate_skies: cannot load %s" % source)
		return {}
	image.resize(PANORAMA_WIDTH, PANORAMA_WIDTH / 2, Image.INTERPOLATE_LANCZOS)
	var width := image.get_width()
	var height := image.get_height()

	var energy: float
	if entry.get("energy") != null:
		energy = float(entry["energy"])
	else:
		var mean := _mean_luminance(image, 0, int(height * ENERGY_BAND))
		energy = clampf(reference / maxf(mean, 0.000001), ENERGY_MIN, ENERGY_MAX)
	var sun_azimuth := _sun_azimuth(image)

	var panorama_path := OUT_DIR + key + ".exr"
	if image.save_exr(panorama_path, false) != OK:
		push_error("curate_skies: cannot write %s" % panorama_path)
		return {}
	var sidecar_path := panorama_path + ".import"
	if not FileAccess.file_exists(sidecar_path):
		var sidecar := FileAccess.open(sidecar_path, FileAccess.WRITE)
		if sidecar == null:
			push_error("curate_skies: cannot write %s" % sidecar_path)
			return {}
		sidecar.store_string(IMPORT_SIDECAR)
		sidecar.close()

	var display := _display_exposure(image)
	var tile_path := OUT_DIR + key + "_tile.png"
	var preview_path := OUT_DIR + key + "_preview.png"
	if _tile(image, display).save_png(tile_path) != OK:
		push_error("curate_skies: cannot write %s" % tile_path)
		return {}
	if _preview(image, display).save_png(preview_path) != OK:
		push_error("curate_skies: cannot write %s" % preview_path)
		return {}

	print("%s: %dx%d azimuth %.1f energy %.3f" % [key, width, height, sun_azimuth, energy])
	return {
		"panorama": panorama_path,
		"tile": tile_path,
		"preview": preview_path,
		"sun_azimuth_deg": snappedf(sun_azimuth, 0.1),
		"energy": snappedf(energy, 0.001),
		"description": entry["description"],
		"source_name": entry["source_name"],
		"source_site": entry["source_site"],
		"source_url": entry["source_url"],
	}


static func _luminance(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


static func _mean_luminance(image: Image, row_from: int, row_to: int) -> float:
	var total := 0.0
	var count := 0
	for y in range(row_from, row_to):
		for x in range(image.get_width()):
			total += _luminance(image.get_pixel(x, y))
			count += 1
	return total / maxf(float(count), 1.0)


## Exposure multiplier for tile/preview tone-mapping only, normalised so the sky band's
## mean luminance lands at a fixed, readable target. Independent of the engine energy
## written to the report, so thumbnails stay legible whatever energy is tuned to later.
static func _display_exposure(image: Image) -> float:
	var mean := _mean_luminance(image, 0, int(image.get_height() * ENERGY_BAND))
	return clampf(PREVIEW_TARGET_LUMINANCE / maxf(mean, 0.000001), ENERGY_MIN, ENERGY_MAX)


## Brightest column over the sky band, as degrees of the panorama's own frame.
static func _sun_azimuth(image: Image) -> float:
	var rows := int(image.get_height() * SUN_BAND)
	var best_x := 0
	var best := -1.0
	for x in range(image.get_width()):
		var column := 0.0
		for y in range(rows):
			column += _luminance(image.get_pixel(x, y))
		if column > best:
			best = column
			best_x = x
	return float(best_x) / float(image.get_width()) * 360.0


## Mean luminance of the clear-day gradient's sky half: the exposure every HDRI
## is normalised to so the lighting presets' ambient values keep working. The gradient
## colours are sRGB material colours; convert to linear first so the comparison is in
## the same space as the EXR's linear radiance.
static func _gradient_reference_luminance() -> float:
	var sky: Dictionary = EnvironmentPresets.SKY_PRESETS["clear_day"]
	var top: Color = (sky["sky_top_color"] as Color).srgb_to_linear()
	var horizon: Color = (sky["sky_horizon_color"] as Color).srgb_to_linear()
	return (_luminance(top) + _luminance(horizon)) / 2.0


static func _tone_map(image: Image, energy: float) -> Image:
	var out := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var c := image.get_pixel(x, y) * energy
			c = Color(clampf(c.r, 0.0, 1.0), clampf(c.g, 0.0, 1.0), clampf(c.b, 0.0, 1.0), 1.0)
			out.set_pixel(x, y, c.linear_to_srgb())
	return out


static func _band(
	image: Image, top_fraction: float, bottom_fraction: float, w: int, h: int
) -> Image:
	var height := image.get_height()
	var y0 := int(height * top_fraction)
	var y1 := int(height * bottom_fraction)
	var band := image.get_region(Rect2i(0, y0, image.get_width(), y1 - y0))
	band.resize(w, h, Image.INTERPOLATE_LANCZOS)
	return band


## Sky band over ground band, the same layout SwatchTextures paints for gradients.
static func _tile(image: Image, energy: float) -> Image:
	# Same format as the bands: blit_rect requires matching formats.
	var tile := Image.create(TILE_SIZE, TILE_SIZE, false, image.get_format())
	var sky := _band(image, TILE_SKY_TOP, 0.5, TILE_SIZE, TILE_HORIZON_ROW)
	var ground := _band(image, 0.5, TILE_GROUND_BOTTOM, TILE_SIZE, TILE_SIZE - TILE_HORIZON_ROW)
	tile.blit_rect(sky, Rect2i(0, 0, TILE_SIZE, TILE_HORIZON_ROW), Vector2i.ZERO)
	tile.blit_rect(
		ground, Rect2i(0, 0, TILE_SIZE, TILE_SIZE - TILE_HORIZON_ROW), Vector2i(0, TILE_HORIZON_ROW)
	)
	return _tone_map(tile, energy)


static func _preview(image: Image, energy: float) -> Image:
	return _tone_map(
		_band(image, PREVIEW_TOP, PREVIEW_BOTTOM, PREVIEW_WIDTH, PREVIEW_HEIGHT), energy
	)


func _print_entries(manifest: Array, report: Dictionary) -> void:
	print("\n# SKY_PRESETS entries (add the gradient colours yourself):")
	for entry in manifest:
		var row: Dictionary = report.get(entry["key"], {})
		if row.is_empty():
			continue
		print('\t"%s":' % entry["key"])
		print("\t{")
		print('\t\t"description": "%s",' % row["description"])
		print('\t\t"panorama": "%s",' % row["panorama"])
		print('\t\t"tile": "%s",' % row["tile"])
		print('\t\t"preview": "%s",' % row["preview"])
		print('\t\t"sun_azimuth_deg": %.1f,' % row["sun_azimuth_deg"])
		print('\t\t"energy": %.3f,' % row["energy"])
		print("\t},")
	print("\n# Licence rows:")
	for entry in manifest:
		print(
			(
				"| `assets/skies/%s.exr` | %s | %s | %s |"
				% [entry["key"], entry["source_name"], entry["source_site"], entry["source_url"]]
			)
		)
