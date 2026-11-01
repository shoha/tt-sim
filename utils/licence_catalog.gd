class_name LicenceCatalog
extends RefCounted

## The notices the Licences page (Settings, About, Licences) lists, as plain data.
##
## The built-in token packs (res://builtin_packs/) add one entry each, generated from their
## manifests (`pack_entries`). Otherwise two sources, one shape. The shipped items come from
## `data/third_party.json`: one entry per third-party item that ships in an export, each with
## the licence text inline or in a file that ships beside it (the export presets'
## `include_filter` carries those files).
## The Godot engine's own notices come from the engine at run time (`Engine.get_license_text`,
## `get_copyright_info`, `get_license_info`), so they are always those of the build in the
## player's hands. `tests/unit/test_third_party_licences.gd` keeps the data file in step with
## `THIRD_PARTY_LICENSES.md`.
##
## An entry is a Dictionary: `id`, `group` (the page's list heading), `name`, `what` (one line),
## `licence` (the short name), `credit` (a line the licence asks to be shown, or ""), and `text`
## (the whole notice, resolved).

const DATA_PATH := "res://data/third_party.json"
const GROUP_ENGINE := "Godot engine"
const GROUP_TOKENS := "Token packs"

## Shown in place of a notice whose file cannot be read; the drift test makes this a failure.
const MISSING_TEXT := "The licence text for this item could not be read."

static var _list_number: RegEx = RegEx.create_from_string("^\\d+[).]\\s")


## Every entry in page order: the game's own and shipped items, the built-in token packs, then
## the engine's.
static func entries() -> Array[Dictionary]:
	var list: Array[Dictionary] = shipped_entries()
	list.append_array(pack_entries())
	list.append_array(engine_entries())
	return list


## One entry per built-in token pack under `root` (BuiltinPacks.ROOT), read from the pack's own
## manifest so the credit that ships is the credit shown and nothing is kept in step by hand. The
## `credit` is the pack's credit line; the text gives author, licence, source and date obtained.
static func pack_entries(root: String = BuiltinPacks.ROOT) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pack in BuiltinPacks.load_all(root):
		out.append(
			_make(
				"tokens_" + pack.pack_id,
				GROUP_TOKENS,
				pack.display_name,
				"Built-in token pack, %d models." % pack.assets.size(),
				pack.license if pack.license != "" else "See source",
				pack_notice(pack),
				pack.credit_line(),
			)
		)
	return out


## The notice text of a token pack: its credit line, then each provenance field it declares.
static func pack_notice(pack: AssetPack) -> String:
	var lines := PackedStringArray()
	if pack.credit_line() != "":
		lines.append(pack.credit_line())
	var fields := [
		["Author", pack.author],
		["Licence", pack.license],
		["Licence text", pack.license_url],
		["Source", pack.source_url],
		["Obtained", pack.obtained],
	]
	for field in fields:
		if str(field[1]) != "":
			lines.append("%s: %s" % [field[0], field[1]])
	return "\n".join(lines)


## The entries of the data file, texts resolved, in file order.
static func shipped_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw in raw_entries():
		out.append(_resolve(raw))
	return out


## The data file's entries as written (a missing or unreadable file gives none).
static func raw_entries() -> Array[Dictionary]:
	return _dictionaries(read_data().get("entries", []))


## The data file's `not_shipped` records: addons the export filter leaves out.
static func not_shipped() -> Array[Dictionary]:
	return _dictionaries(read_data().get("not_shipped", []))


## The parsed data file, or an empty Dictionary when it cannot be read.
static func read_data() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return parsed if parsed is Dictionary else {}


## The engine's notices: its licence, the components it is built from, and their licence texts.
static func engine_entries() -> Array[Dictionary]:
	var version := str(Engine.get_version_info().get("string", ""))
	var out: Array[Dictionary] = [
		_make(
			"godot",
			GROUP_ENGINE,
			"Godot Engine",
			"The engine this game runs on, version %s." % version if version != "" else "The engine.",
			"MIT",
			reflow(Engine.get_license_text().strip_edges()),
		),
		_make(
			"godot_components",
			GROUP_ENGINE,
			"Engine components",
			"The libraries built into the engine, with their copyright holders.",
			"Various",
			components_text(Engine.get_copyright_info()),
		),
		_make(
			"godot_licences",
			GROUP_ENGINE,
			"Engine licence texts",
			"The full text of every licence the engine's components use.",
			"Various",
			licence_texts(Engine.get_license_info()),
		),
	]
	return out


## One block per engine component: its name, then each part's copyright lines and licence.
## `info` is `Engine.get_copyright_info()`; the file lists are left out (they run to hundreds).
static func components_text(info: Array[Dictionary]) -> String:
	var blocks := PackedStringArray()
	for component in info:
		var lines := PackedStringArray([str(component.get("name", "")).strip_edges()])
		for part in _dictionaries(component.get("parts", [])):
			for notice in part.get("copyright", []):
				lines.append("    Copyright %s" % str(notice).strip_edges())
			lines.append("    Licence: %s" % str(part.get("license", "")).strip_edges())
		blocks.append("\n".join(lines))
	return "\n\n".join(blocks)


## Every licence text of `info` (`Engine.get_license_info()`: id to text), sorted by id, each
## under its id.
static func licence_texts(info: Dictionary) -> String:
	var ids: Array = info.keys()
	ids.sort()
	var blocks := PackedStringArray()
	for id in ids:
		blocks.append("%s\n\n%s" % [str(id), str(info[id]).strip_edges()])
	return "\n\n________________\n\n".join(blocks)


## Joins the hard-wrapped lines of each paragraph of `text`, so the page wraps it to its own
## width: a line continues the one above unless it is blank, indented, or opens a list item
## (`-`, `*`, `#`, `1)`, `Copyright`); an indented line continues a list item. Markdown marks
## (`#` headings, backticks) are dropped.
static func reflow(text: String) -> String:
	var out := PackedStringArray()
	for line in text.replace("\r", "").replace("`", "").split("\n"):
		var in_list := not out.is_empty() and (out[-1].begins_with("- ") or out[-1].begins_with("* "))
		var indented := line.begins_with(" ") or line.begins_with("\t")
		var starts_item := (
			(indented and not in_list)
			or line.begins_with("-")
			or line.begins_with("*")
			or line.begins_with("Copyright")
			or _list_number.search(line) != null
		)
		var heading := line.begins_with("#")
		var item := line.lstrip("# ") if heading else line
		if indented and in_list:
			item = line.strip_edges()
		if (
			out.is_empty()
			or line == ""
			or out[-1] == ""
			or starts_item
			or heading
			or _is_caps(line)
			or _is_caps(out[-1])
		):
			out.append(item)
		else:
			out[-1] = "%s %s" % [out[-1], item]
	return "\n".join(out)


## True for a short line in capitals with no full stop (OFL's PREAMBLE, DEFINITIONS): a heading.
static func _is_caps(line: String) -> bool:
	return (
		line.length() < 40
		and not line.ends_with(".")
		and line != line.to_lower()
		and line == line.to_upper()
	)


static func _resolve(raw: Dictionary) -> Dictionary:
	var text := str(raw.get("text", ""))
	var path := str(raw.get("text_path", ""))
	if path != "":
		text = FileAccess.get_file_as_string(path).strip_edges()
		if text == "":
			push_warning("LicenceCatalog: cannot read %s" % path)
			text = MISSING_TEXT
	if bool(raw.get("reflow", false)):
		text = reflow(text)
	return _make(
		str(raw.get("id", "")),
		str(raw.get("group", "")),
		str(raw.get("name", "")),
		str(raw.get("what", "")),
		str(raw.get("licence", "")),
		text,
		str(raw.get("credit", "")),
	)


static func _make(
	id: String,
	group: String,
	title: String,
	what: String,
	licence: String,
	text: String,
	credit: String = "",
) -> Dictionary:
	return {
		"id": id,
		"group": group,
		"name": title,
		"what": what,
		"licence": licence,
		"credit": credit,
		"text": text,
	}


static func _dictionaries(values: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if values is Array:
		for value in values:
			if value is Dictionary:
				out.append(value)
	return out
