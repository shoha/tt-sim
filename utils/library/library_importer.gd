class_name LibraryImporter
extends RefCounted

## How a library gets from a `.ttlib` zip or a folder onto the user's disk without trusting it
## (design doc 5.5; docs/systems/library.md "Importing"). No scene tree, no UI: the manager calls
## these in order, and the tests call them with generated zips.
##
##   inspect(path)      a read-only look at the zip's central directory (or the folder's file
##                      list) against the caps, BEFORE anything is extracted or copied: entries,
##                      total uncompressed size, expansion ratio, allowed extensions, portable
##                      names, symlinks, encrypted entries, absolute or `..` paths, backslashes,
##                      case-insensitive twins, device names, a library.json at the root;
##   stage(plan)        extract or copy the inspected files into the quarantine folder
##                      `<libraries>/.incoming/<random>/` (a dot folder the registry never scans);
##
## What happens next (describing the staged folder, installing, removing) is LibraryInstall.
##
## A library holds data only: the allowed extensions are `LibraryContracts.EXTENSIONS`, nothing
## here ever loads a library file as a resource or runs it, and `official` is a property of where
## a library lives, so an import can never claim it. A zip made by zipping the library's folder
## (one top folder holding library.json) is accepted and unwrapped. Junk some zip tools add
## (`__MACOSX`, `.DS_Store`, `Thumbs.db`, `desktop.ini`, a `.git` folder) is left out, said so,
## rather than refused.

const ZIP_EXTENSIONS: Array[String] = ["ttlib", "zip"]
const INCOMING := ".incoming"
const LIBRARY_FILE := "library.json"
const KIB := 1024
const MIB := 1024 * 1024
## Names a zip tool or a file manager adds by itself; left out of the import with a note.
const JUNK_NAMES: Array[String] = [".ds_store", "thumbs.db", "desktop.ini"]
const JUNK_FOLDERS: Array[String] = ["__macosx", ".git", ".github", ".svn", ".hg"]
## The most error lines one answer carries (the rest are counted).
const MAX_LINES := 12

## The limits, overridable by a test (reset with default_limits()).
static var limits: Dictionary = default_limits()
## The incoming folder; empty means under LibraryRegistry.user_root.
static var incoming_override: String = ""


## The hard limits of design 2.10: a zip of at most 20,000 entries, 1 GiB uncompressed, expanding
## at most 200 times; a library of at most 512 MiB on disk (150 MiB is only a warning).
static func default_limits() -> Dictionary:
	return {
		"entries": 20000,
		"uncompressed_bytes": 1024 * MIB,
		"archive_bytes": 1024 * MIB,
		"directory_bytes": 8 * MIB,
		"ratio": 200,
		"ratio_min_bytes": MIB,
		"library_bytes": 512 * MIB,
		"library_soft_bytes": 150 * MIB,
		"json_bytes": MIB,
		"catalog_bytes": int(LibraryContracts.CAPS["catalog_bytes"]),
		"glb_bytes": int(LibraryContracts.CAPS["glb_bytes"]),
		"image_bytes": 48 * MIB,
		"text_bytes": MIB,
	}


## Progress of a stage() running on another thread: the thread writes, the UI reads.
class Progress:
	extends RefCounted
	var done: int = 0
	var total: int = 0
	var cancelled: bool = false
	var phase: String = ""


# ---- the quarantine ----


## `<libraries>/.incoming/`: where an import waits until the user says install.
static func incoming_root() -> String:
	if incoming_override != "":
		return incoming_override
	return LibraryRegistry.user_root.path_join(INCOMING)


## True when `path` is somewhere stage() may write or discard() may delete: inside the incoming
## folder, no `..`.
static func is_quarantined(path: String) -> bool:
	var root := incoming_root().simplify_path()
	var clean := path.simplify_path()
	return clean.begins_with(root + "/") and ".." not in clean.split("/")


## Deletes quarantine folders except `keep` (a staged folder still in use). Returns how many.
static func sweep_incoming(keep: String = "") -> int:
	var removed := 0
	var root := incoming_root()
	if not DirAccess.dir_exists_absolute(root):
		return 0
	for entry in DirAccess.get_directories_at(root):
		var folder := root.path_join(entry)
		if keep != "" and folder.simplify_path() == keep.simplify_path():
			continue
		if remove_tree(folder):
			removed += 1
	return removed


## Deletes a staged folder (a no-op for anything outside the quarantine).
static func discard(staged: String) -> void:
	if staged != "" and is_quarantined(staged):
		remove_tree(staged)


# ---- sniffing (drop routing) ----


## True when `path` looks like a library: a folder holding library.json (or one folder holding
## it), or a zip whose central directory lists a library.json at its root (or under one top
## folder). Cheap (a directory listing, or the zip's directory), reads no entry.
static func is_candidate(path: String) -> bool:
	if DirAccess.dir_exists_absolute(path):
		return not _folder_root(path).is_empty()
	if path.get_extension().to_lower() not in ZIP_EXTENSIONS or not FileAccess.file_exists(path):
		return false
	var found := ZipEntrySizes.read(
		path, int(limits["archive_bytes"]), int(limits["entries"]), int(limits["directory_bytes"])
	)
	if found["sizes"] == null:
		return false
	var names: Array = (found["sizes"] as Dictionary).keys()
	return _prefix_of(names) != null


# ---- inspecting ----


## What importing `path` (a zip or a folder) would extract, judged without extracting anything:
## {ok, errors, warnings, kind ("zip" or "folder"), source, prefix (the top folder the library
## sits in, "" for the root), files ([{name (library-relative), raw (the entry name), size,
## compressed}]), total_bytes, archive_bytes, ignored (the junk left out)}. `ok` is false with
## `errors` (plain sentences) for any breach of the rules above; nothing is written.
static func inspect(path: String) -> Dictionary:
	var plan := _plan(path)
	if DirAccess.dir_exists_absolute(path):
		plan["kind"] = "folder"
		_inspect_folder(path, plan)
	elif FileAccess.file_exists(path):
		plan["kind"] = "zip"
		_inspect_zip(path, plan)
	else:
		_fail(plan, "%s is not a file or a folder." % path.get_file())
	plan["ok"] = (plan["errors"] as Array).is_empty()
	return plan


static func _plan(path: String) -> Dictionary:
	return {
		"ok": false,
		"errors": [] as Array[String],
		"warnings": [] as Array[String],
		"kind": "",
		"source": path,
		"prefix": "",
		"files": [] as Array[Dictionary],
		"total_bytes": 0,
		"archive_bytes": 0,
		"ignored": [] as Array[String],
	}


static func _inspect_zip(path: String, plan: Dictionary) -> void:
	if path.get_extension().to_lower() not in ZIP_EXTENSIONS:
		_fail(plan, "'%s' is not a .ttlib or .zip file." % path.get_file())
		return
	var found := ZipEntrySizes.read_directory(
		path, int(limits["archive_bytes"]), int(limits["entries"]), int(limits["directory_bytes"])
	)
	if found["error"] != "":
		_fail(plan, _friendly_zip_error(String(found["error"]), path))
		return
	var records: Variant = ZipEntrySizes.parse_central_records(
		found["directory"], int(found["count"])
	)
	if records == null:
		_fail(plan, "'%s' has a damaged directory and cannot be read." % path.get_file())
		return
	plan["archive_bytes"] = int(found["length"])
	_inspect_records(records, plan)


static func _friendly_zip_error(raw: String, path: String) -> String:
	var name := path.get_file()
	if "over the cap" in raw:
		return (
			"'%s' is larger than the %s %s archive may be."
			% [name, size_text(limit_of("archive_bytes")), LibraryNames.article()]
		)
	if "oversized ZIP directory" in raw:
		return "'%s' holds more than %d files." % [name, limit_of("entries")]
	if "not a ZIP archive" in raw:
		return "'%s' is not a readable zip file (it may be cut short)." % name
	if "Zip64" in raw:
		return "'%s' uses Zip64, which is not supported." % name
	return "'%s' cannot be read: %s" % [name, raw]


## The entry-level rules over a zip's central-directory records (ZipEntrySizes.
## parse_central_records), shared with the tests, which build records of their own. Fills
## plan.files, plan.prefix, plan.ignored and plan.errors.
static func _inspect_records(records: Array, plan: Dictionary) -> void:
	var errors: Array = plan["errors"]
	var kept: Array[Dictionary] = []
	var names: Array[String] = []
	for record: Dictionary in records:
		var raw := String(record["name"])
		var problem := _raw_name_problem(raw)
		if problem != "":
			_note(errors, problem)
			continue
		var is_dir := raw.ends_with("/")
		var clean := raw.trim_suffix("/")
		if _is_junk(clean):
			(plan["ignored"] as Array).append(clean)
			continue
		var mode_problem := _mode_problem(record)
		if mode_problem != "":
			_note(errors, "'%s' %s." % [_short(clean), mode_problem])
			continue
		if is_dir:
			names.append(clean)
			continue
		if int(record["flags"]) & 1:
			_note(errors, "'%s' is encrypted." % _short(clean))
			continue
		if int(record["method"]) not in [0, 8]:
			_note(errors, "'%s' uses a compression method that is not supported." % _short(clean))
			continue
		names.append(clean)
		kept.append(record)
	var prefix: Variant = _prefix_of(names)
	if prefix == null:
		_note(errors, "There is no %s at the top of the archive." % LIBRARY_FILE)
		prefix = ""
	plan["prefix"] = prefix
	_collect_files(kept, String(prefix), plan)
	_check_totals(plan)


static func _collect_files(kept: Array[Dictionary], prefix: String, plan: Dictionary) -> void:
	var errors: Array = plan["errors"]
	var files: Array = plan["files"]
	var lower := {}
	var total := 0
	var count_limit := limit_of("entries")
	for record in kept:
		var raw := String(record["name"])
		if prefix != "" and not raw.begins_with(prefix + "/"):
			_note(errors, "'%s' is outside the %s folder." % [_short(raw), prefix])
			continue
		var name := raw.substr(prefix.length() + 1) if prefix != "" else raw
		var problems := _file_problems(name, int(record["size"]))
		if not problems.is_empty():
			for line in problems:
				_note(errors, line)
			continue
		var folded := name.to_lower()
		if lower.has(folded):
			var twin := String(lower[folded])
			var text := (
				"'%s' appears twice." % _short(name)
				if twin == name
				else (
					"'%s' and '%s' differ only by case, which Windows treats as one file."
					% [_short(twin), _short(name)]
				)
			)
			_note(errors, text)
			continue
		lower[folded] = name
		var size := int(record["size"])
		var packed := int(record["compressed"])
		if int(record["method"]) == 0 and packed != size:
			_note(errors, "'%s' is stored with sizes that disagree." % _short(name))
			continue
		var ratio_limit := limit_of("ratio")
		if size > limit_of("ratio_min_bytes") and packed > 0 and size / packed > ratio_limit:
			_note(errors, "'%s' expands more than %d times." % [_short(name), ratio_limit])
			continue
		total += size
		files.append({"name": name, "raw": raw, "size": size, "compressed": packed})
		if files.size() > count_limit:
			_note(errors, "The archive holds more than %d files." % count_limit)
			break
	plan["total_bytes"] = total


## The totals rules: bytes over the cap, expansion over the ratio, a library over its size cap.
static func _check_totals(plan: Dictionary) -> void:
	var errors: Array = plan["errors"]
	var total := int(plan["total_bytes"])
	if total > limit_of("uncompressed_bytes"):
		_note(
			errors,
			(
				"The archive expands to %s, over the %s limit."
				% [size_text(total), size_text(limit_of("uncompressed_bytes"))]
			)
		)
	var archive := int(plan["archive_bytes"])
	if archive > 0 and total / archive > limit_of("ratio"):
		_note(
			errors,
			(
				"The archive expands %d times over its own size, which looks like a zip bomb."
				% [total / archive]
			)
		)
	if total > limit_of("library_bytes"):
		_note(
			errors,
			(
				"%s may be at most %s on disk; this one is %s."
				% [LibraryNames.article(true), size_text(limit_of("library_bytes")), size_text(total)]
			)
		)
	elif total > limit_of("library_soft_bytes"):
		(plan["warnings"] as Array).append(
			(
				"This is a large %s (%s); loading it will take a while."
				% [LibraryNames.lower(), size_text(total)]
			)
		)
	if (plan["files"] as Array).is_empty() and (plan["errors"] as Array).is_empty():
		_note(errors, "There are no files to import.")


static func _inspect_folder(path: String, plan: Dictionary) -> void:
	var root := _folder_root(path)
	if root.is_empty():
		_fail(plan, "There is no %s in '%s'." % [LIBRARY_FILE, path.get_file()])
		return
	plan["prefix"] = "" if root == path else root.get_file()
	var files: Array = plan["files"]
	var found: Array[Dictionary] = []
	var counter := {"count": 0, "stop": false}
	_walk(root, "", 0, found, plan, counter)
	var lower := {}
	var total := 0
	for item in found:
		var folded := String(item["name"]).to_lower()
		if lower.has(folded):
			_note(
				plan["errors"],
				(
					"'%s' and '%s' differ only by case."
					% [_short(String(lower[folded])), _short(String(item["name"]))]
				)
			)
			continue
		lower[folded] = item["name"]
		total += int(item["size"])
		files.append(item)
	plan["total_bytes"] = total
	_check_totals(plan)


## Collects the files under `root` (relative `prefix`) into `out`: every file within the rules,
## the problems into plan.errors; folders starting with a dot that are known junk are skipped.
static func _walk(
	root: String,
	prefix: String,
	depth: int,
	out: Array[Dictionary],
	plan: Dictionary,
	counter: Dictionary
) -> void:
	if counter["stop"]:
		return
	if depth > LibraryRegistry.MAX_DEPTH:
		_note(plan["errors"], "Folders nest deeper than %d levels." % LibraryRegistry.MAX_DEPTH)
		counter["stop"] = true
		return
	var here := root if prefix == "" else root.path_join(prefix)
	var names := Array(DirAccess.get_files_at(here))
	names.sort()
	for file_name: String in names:
		var relative := file_name if prefix == "" else prefix + "/" + file_name
		if _is_junk(relative):
			(plan["ignored"] as Array).append(relative)
			continue
		counter["count"] = int(counter["count"]) + 1
		if int(counter["count"]) > limit_of("entries"):
			_note(plan["errors"], "The folder holds more than %d files." % limit_of("entries"))
			counter["stop"] = true
			return
		var absolute := here.path_join(file_name)
		if _is_link(absolute):
			_note(
				plan["errors"],
				"'%s' is a link, which %s may not contain." % [_short(relative), LibraryNames.article()]
			)
			continue
		var size := file_length(absolute)
		var problems := _file_problems(relative, size)
		if not problems.is_empty():
			for line in problems:
				_note(plan["errors"], line)
			continue
		out.append({"name": relative, "raw": absolute, "size": size, "compressed": size})
	var folders := Array(DirAccess.get_directories_at(here))
	folders.sort()
	for folder_name: String in folders:
		var relative := folder_name if prefix == "" else prefix + "/" + folder_name
		if _is_junk(relative):
			(plan["ignored"] as Array).append(relative)
			continue
		var segment := LibraryIds.segment_problems(folder_name)
		if not segment.is_empty():
			_note(plan["errors"], "Folder %s" % segment[0])
			continue
		if _is_link(here.path_join(folder_name)):
			_note(
				plan["errors"],
				"'%s' is a link, which %s may not contain." % [_short(relative), LibraryNames.article()]
			)
			continue
		_walk(root, relative, depth + 1, out, plan, counter)


## The folder that holds library.json: `path` itself, or its one subfolder; "" when neither.
static func _folder_root(path: String) -> String:
	if FileAccess.file_exists(path.path_join(LIBRARY_FILE)):
		return path
	var subs := DirAccess.get_directories_at(path)
	var wrapped := ""
	for sub in subs:
		if sub.to_lower() in JUNK_FOLDERS:
			continue
		if wrapped != "":
			return ""
		wrapped = sub
	# Loose files beside the one folder are not part of the library: they are never copied.
	if wrapped != "" and FileAccess.file_exists(path.path_join(wrapped).path_join(LIBRARY_FILE)):
		return path.path_join(wrapped)
	return ""


## The top folder holding library.json among entry `names`: "" for the root, the folder's name
## when every entry sits in one top folder that holds it, null when there is no library.json
## there at all.
static func _prefix_of(names: Array) -> Variant:
	var clean: Array[String] = []
	for item: Variant in names:
		var text := String(item).trim_suffix("/")
		if not _is_junk(text):
			clean.append(text)
	if LIBRARY_FILE in clean:
		return ""
	var tops := {}
	for text in clean:
		tops[text.get_slice("/", 0)] = true
	if tops.size() != 1:
		return null
	var wrapper: String = tops.keys()[0]
	return wrapper if (wrapper + "/" + LIBRARY_FILE) in clean else null


# ---- name rules ----


## A problem with an archive entry's raw name, or "". Structural only: the length cap applies to
## the name inside the library.
static func _raw_name_problem(raw: String) -> String:
	if raw == "":
		return "The archive has an entry with no name."
	var name := raw.trim_suffix("/")
	if raw.begins_with("/") or ":" in raw:
		return "'%s' is an absolute path or names a drive." % _short(raw)
	if "\\" in raw:
		return "'%s' uses a backslash in its path." % _short(raw)
	for segment in name.split("/"):
		if segment == "..":
			return "'%s' climbs out of the %s's folder." % [_short(raw), LibraryNames.lower()]
		if _is_junk_segment(segment):
			continue
		var problems := LibraryIds.segment_problems(segment)
		if not problems.is_empty():
			return "In '%s': %s" % [_short(raw), problems[0]]
	return ""


## Problems with a file inside the library: its path, extension and size.
static func _file_problems(name: String, size: int) -> Array[String]:
	var out: Array[String] = []
	for line in LibraryIds.path_problems(name):
		out.append(line)
	if not out.is_empty():
		return out
	if name.count("/") > LibraryRegistry.MAX_DEPTH:
		out.append(
			"'%s' is nested deeper than %d folders." % [_short(name), LibraryRegistry.MAX_DEPTH]
		)
		return out
	var extension := "." + name.get_extension().to_lower()
	if extension not in LibraryContracts.EXTENSIONS:
		out.append(
			(
				"'%s' is not allowed: %s holds only %s files."
				% [_short(name), LibraryNames.article(), ", ".join(LibraryContracts.EXTENSIONS)]
			)
		)
		return out
	var cap := extension_cap(name)
	if size > cap:
		out.append(
			(
				"'%s' is %s, over the %s limit for that file."
				% [_short(name), size_text(size), size_text(cap)]
			)
		)
	return out


## The most bytes the file at library-relative `name` may hold.
static func extension_cap(name: String) -> int:
	var extension := name.get_extension().to_lower()
	match extension:
		"glb":
			return limit_of("glb_bytes")
		"png", "jpg":
			return limit_of("image_bytes")
		"json":
			if name == "assets/catalog.json":
				return limit_of("catalog_bytes")
			return limit_of("json_bytes")
		_:
			return limit_of("text_bytes")


## A problem with an entry's mode (a symlink, a device), or "". Unix zips carry the file mode in
## the high half of the external attributes; DOS ones the reparse-point bit (a Windows link).
static func _mode_problem(record: Dictionary) -> String:
	var external := int(record["external"])
	if int(record["made_by_host"]) == 3:
		var kind := (external >> 16) & 0xF000
		if kind == 0xA000:
			return "is a symbolic link, which %s may not contain" % LibraryNames.article()
		if kind != 0 and kind != 0x8000 and kind != 0x4000:
			return "is not an ordinary file"
	if external & 0x400:
		return "is a link, which %s may not contain" % LibraryNames.article()
	return ""


static func _is_junk(relative: String) -> bool:
	for segment in relative.split("/"):
		if _is_junk_segment(segment):
			return true
	return false


static func _is_junk_segment(segment: String) -> bool:
	var lower := segment.to_lower()
	return lower in JUNK_NAMES or lower in JUNK_FOLDERS


# ---- staging ----


## Extracts or copies the files of an ok `plan` into a fresh quarantine folder:
## {ok, folder, error}. On any problem (a damaged entry, a size that disagrees with its
## directory, a full disk, a cancel) the folder is deleted and `error` says why. `progress`
## (optional) is updated as bytes are written; set progress.cancelled to stop. Safe to call from
## a worker thread: it touches no scene, autoload or registry state.
static func stage(plan: Dictionary, progress: Progress = null) -> Dictionary:
	if not bool(plan.get("ok", false)):
		return {"ok": false, "folder": "", "error": "The import was not checked."}
	var folder := incoming_root().path_join(token())
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return {"ok": false, "folder": "", "error": "The incoming folder cannot be created."}
	if progress != null:
		progress.total = int(plan["total_bytes"])
		progress.done = 0
		progress.phase = "Reading"
	var zip: ZIPReader = null
	if String(plan["kind"]) == "zip":
		zip = ZIPReader.new()
		if zip.open(String(plan["source"])) != OK:
			remove_tree(folder)
			return {"ok": false, "folder": "", "error": "The archive cannot be opened."}
	var problem := ""
	for item: Dictionary in plan["files"]:
		if progress != null and progress.cancelled:
			problem = "Cancelled."
			break
		problem = _write_one(item, folder, zip)
		if problem != "":
			break
		if progress != null:
			progress.done += int(item["size"])
	if zip != null:
		zip.close()
	if problem != "":
		remove_tree(folder)
		return {"ok": false, "folder": "", "error": problem}
	return {"ok": true, "folder": folder, "error": ""}


static func _write_one(item: Dictionary, folder: String, zip: ZIPReader) -> String:
	var name := String(item["name"])
	var target := folder.path_join(name)
	# Belt and braces: the name passed inspect(), and the target must still sit in the folder.
	if not target.simplify_path().begins_with(folder.simplify_path() + "/"):
		return "'%s' would be written outside the %s." % [_short(name), LibraryNames.lower()]
	var bytes := PackedByteArray()
	if zip != null:
		if not zip.file_exists(String(item["raw"])):
			return "'%s' is missing from the archive." % _short(name)
		bytes = zip.read_file(String(item["raw"]))
	else:
		bytes = FileAccess.get_file_as_bytes(String(item["raw"]))
	if bytes.size() != int(item["size"]):
		return (
			"'%s' is damaged (it is %d bytes, not %d)."
			% [_short(name), bytes.size(), int(item["size"])]
		)
	if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK:
		return "A folder for '%s' cannot be created." % _short(name)
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return "'%s' cannot be written." % _short(name)
	file.store_buffer(bytes)
	var failed := file.get_error() != OK
	file.close()
	return "'%s' cannot be written (is the disk full?)." % _short(name) if failed else ""


## Recursively deletes `path` (a file or a folder); true when it is gone. Never follows a link
## out of the tree: a link is removed as itself.
static func remove_tree(path: String) -> bool:
	if DirAccess.dir_exists_absolute(path):
		if not _is_link(path):
			for sub in DirAccess.get_directories_at(path):
				remove_tree(path.path_join(sub))
			for file_name in DirAccess.get_files_at(path):
				DirAccess.remove_absolute(path.path_join(file_name))
		DirAccess.remove_absolute(path)
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return not DirAccess.dir_exists_absolute(path) and not FileAccess.file_exists(path)


# ---- small helpers ----


static func limit_of(key: String) -> int:
	return int(limits.get(key, default_limits()[key]))


static func token() -> String:
	return Crypto.new().generate_random_bytes(8).hex_encode()


static func _is_link(path: String) -> bool:
	var dir := DirAccess.open(path.get_base_dir())
	return dir != null and dir.is_link(path)


static func file_length(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := file.get_length()
	file.close()
	return length


static func _fail(plan: Dictionary, text: String) -> void:
	(plan["errors"] as Array).append(text)


## Appends `text` to `lines` unless MAX_LINES are there already (then one count of the rest).
static func _note(lines: Array, text: String) -> void:
	if lines.size() < MAX_LINES:
		lines.append(text)
	elif lines.size() == MAX_LINES:
		lines.append("... and more.")


static func size_text(bytes: int) -> String:
	if bytes >= MIB:
		return "%.1f MB" % (float(bytes) / MIB)
	return "%d KB" % maxi(1, int(ceil(float(bytes) / KIB)))


static func _short(text: String) -> String:
	return text if text.length() <= 48 else text.substr(0, 45) + "..."
