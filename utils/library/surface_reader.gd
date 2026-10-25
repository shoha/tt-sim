class_name SurfaceReader
extends RefCounted

## Validates the `surfaces/` folder of a library (design doc 2.7.1), for LibraryReader. Pure: it
## is handed the library's file list, the text of each surface.json and the PNG headers
## LibraryRegistry read, and returns the surface sets that are usable. Everything is untrusted:
## names are grammar-checked, a stray file is a warning, a hostile PNG header (wrong signature,
## over 2048 pixels, odd bit depth) or surface.json is an error, and nothing raises.

## The files a surface folder may hold besides the four maps.
const INFO_FILE := "surface.json"


## read(files, texts, headers, errors, warnings) -> {"surfaces": {name: {info, maps}}, "order":
## [names]}. `files` are library-relative paths, `texts` {name: surface.json text}, `headers`
## {library-relative png path: png_header result}. Errors block the library; a set with an error
## is left out of the result.
static func read(
	files: Array,
	texts: Dictionary,
	headers: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> Dictionary:
	var out := {"surfaces": {}, "order": [] as Array[String]}
	var names: Array[String] = []
	var present := {}
	for raw: Variant in files:
		var path := String(raw)
		if not path.begins_with(LibraryReader.SURFACE_DIR):
			continue
		var parts := path.split("/")
		if parts.size() != 3:
			warnings.append("file %s: surfaces/ holds one folder per surface (ignored)" % path)
			continue
		var name := parts[1]
		if not name in names:
			names.append(name)
		present[path] = true
	names.sort()
	if names.size() > SurfaceBake.MAX_SURFACES:
		errors.append(
			"surfaces: %d folders over the cap of %d" % [names.size(), SurfaceBake.MAX_SURFACES]
		)
		return out
	for name in names:
		_read_one(name, present, texts, headers, errors, warnings, out)
	return out


static func _read_one(
	name: String,
	present: Dictionary,
	texts: Dictionary,
	headers: Dictionary,
	errors: Array[String],
	warnings: Array[String],
	out: Dictionary
) -> void:
	var label := "surface %s" % name
	var before := errors.size()
	for problem in LibraryIds.surface_problems(name):
		errors.append("%s: %s" % [label, problem])
	var folder := LibraryReader.SURFACE_DIR + name + "/"
	var checked := SurfaceBake.check_info(String(texts.get(name, "")), name)
	(errors).append_array(checked["errors"])
	(warnings).append_array(checked["warnings"])
	var maps: Array[String] = []
	for kind in SurfaceBake.KINDS:
		var path := "%s%s.png" % [folder, kind]
		if not present.has(path):
			continue
		maps.append(kind)
		SurfaceBake.check_png(headers.get(path, {}), kind, label, errors, warnings)
	for path: String in present:
		if path.begins_with(folder):
			var file := path.get_file()
			if file != INFO_FILE and not (file.get_basename() in SurfaceBake.KINDS):
				warnings.append("%s: unexpected file '%s' (ignored)" % [label, file])
			elif file != INFO_FILE and file.get_extension().to_lower() != "png":
				warnings.append("%s: map '%s' must be a .png (ignored)" % [label, file])
	if not "albedo" in maps:
		errors.append("%s: albedo.png is missing" % label)
	for kind in ["normal", "orm", "height"]:
		if not kind in maps:
			warnings.append("%s: %s.png is missing (drawn as a flat stand-in)" % [label, kind])
	if errors.size() == before and checked["ok"]:
		out["surfaces"][name] = {"info": checked["info"], "maps": maps}
		(out["order"] as Array[String]).append(name)
