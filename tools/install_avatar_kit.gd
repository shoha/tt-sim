extends SceneTree

## Installs figurine's avatar kit (docs/ASSET_PIPELINE.md section 10) under
## res://assets/avatar_kit/, the way section 9 installs treecube's palette:
##
##     godot --headless --path D:/dev/tt-sim --script res://tools/install_avatar_kit.gd
##
## takes an optional kit dir after `--`; it defaults to D:/dev/figurine/out/kit. Every file is
## copied over the installed one (kit.json, build_report.json, skeleton.glb, parts, faces,
## thumbnails); committed `.import` sidecars are kept. A GLB or PNG without a sidecar gets one
## written before Godot first imports it, so its settings never start from Godot's defaults:
## GLBs embed their textures (GLB_SIDECAR), the face sheet and mask keep their exact texels
## with mipmaps (FACE_SIDECAR).
## Only a shippable kit installs: one whose build_report.json says `"check": "full"` (or has no
## `check`, as builds before the field did). An iteration build (`fast`, `incremental`) is
## refused before anything is copied (refusal()).
## Run `godot --headless --import --path D:/dev/tt-sim` afterwards.

const DEFAULT_SOURCE := "D:/dev/figurine/out/kit"
const DEST := "res://assets/avatar_kit"

const GLB_SIDECAR := """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[params]

meshes/generate_lods=false
meshes/create_shadow_meshes=false
gltf/embedded_image_handling=3
"""

const FACE_SIDECAR := """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=0
mipmaps/generate=true
process/fix_alpha_border=true
detect_3d/compress_to=0
"""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var source := String(args[0]) if args.size() > 0 else DEFAULT_SOURCE
	if not FileAccess.file_exists(source.path_join("kit.json")):
		printerr("install_avatar_kit: no kit.json in %s" % source)
		quit(1)
		return
	var report_path := source.path_join("build_report.json")
	var report_text := ""
	if FileAccess.file_exists(report_path):
		report_text = FileAccess.get_file_as_string(report_path)
	var refused := refusal(report_text)
	if not refused.is_empty():
		printerr("install_avatar_kit: %s; nothing copied from %s" % [refused, source])
		quit(1)
		return
	var copied := _copy_tree(source, ProjectSettings.globalize_path(DEST))
	print("install_avatar_kit: copied %d files from %s" % [copied, source])
	quit(0)


## Why a kit with this build_report.json text must not install, or "" when it may: a `check`
## other than "full" is an iteration build; no report (empty text) or no `check` field is an
## older full build. A report that is not a JSON object is refused, since its check is unknown.
static func refusal(report_text: String) -> String:
	if report_text.is_empty():
		return ""
	var json := JSON.new()
	var report: Variant = json.data if json.parse(report_text) == OK else null
	if not report is Dictionary:
		return "build_report.json is not a JSON object"
	if not (report as Dictionary).has("check"):
		return ""
	var check := str(report["check"])
	if check == "full":
		return ""
	return 'build_report.json says "check": "%s" (an iteration build; ship only "full")' % check


func _copy_tree(from: String, to: String) -> int:
	DirAccess.make_dir_recursive_absolute(to)
	var dir := DirAccess.open(from)
	if dir == null:
		return 0
	var count := 0
	for file in dir.get_files():
		var target := to.path_join(file)
		if DirAccess.copy_absolute(from.path_join(file), target) != OK:
			printerr("install_avatar_kit: could not copy %s" % file)
			continue
		count += 1
		_write_sidecar(target)
	for sub in dir.get_directories():
		count += _copy_tree(from.path_join(sub), to.path_join(sub))
	return count


## A sidecar for a new GLB or face PNG; an existing one is left as committed.
func _write_sidecar(target: String) -> void:
	var sidecar := target + ".import"
	if FileAccess.file_exists(sidecar):
		return
	var text := ""
	if target.ends_with(".glb"):
		text = GLB_SIDECAR
	elif target.get_base_dir().ends_with("faces") and target.ends_with(".png"):
		text = FACE_SIDECAR
	if text.is_empty():
		return
	var f := FileAccess.open(sidecar, FileAccess.WRITE)
	f.store_string(text)
	f.close()
