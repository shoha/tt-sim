class_name LibraryReasons
extends RefCounted

## Why a collection is unavailable, in a player's words (review UX-3). The registry and the reader
## say it for developers ("library.json is not valid JSON (line 0: ...)", "needs library 'core'
## ^9.0, but 1.0.0-dev is installed", a user:// path); this turns each into
##
##   message   one plain sentence, the first thing the player reads, with no path, no sha256 and
##             no JSON in it;
##   action    what to do about it, one sentence ("Update the game or remove it.");
##   details   the original technical text, kept behind a "Details" fold;
##   kind      one of the KIND_ constants, so a card can offer the matching action (a duplicate
##             offers Remove first).
##
## Pure: it reads the registry only to name a dependency by its title. Every word that names the
## content goes through LibraryNames.

const KIND_DEPENDENCY := "dependency"
const KIND_DUPLICATE := "duplicate"
const KIND_FOLDER := "folder"
const KIND_DAMAGED := "damaged"
const KIND_OTHER := "other"
const GENERIC_ACTION := "Ask its author for a fixed copy, or remove it."


## The explanation of one raw `reason`. {message, action, details, kind}.
static func explain(reason: String) -> Dictionary:
	var out := {"message": "", "action": "", "details": reason, "kind": KIND_OTHER}
	var found := _dependency(reason, out)
	if found:
		return out
	if reason.begins_with("duplicate library id"):
		out["kind"] = KIND_DUPLICATE
		out["message"] = "Two folders hold the same %s id." % LibraryNames.lower()
		out["action"] = "Keep one: remove this copy, or remove the other."
		return out
	if reason.begins_with("folder '") and "must be named after" in reason:
		out["kind"] = KIND_FOLDER
		var folder_line := "This %s's folder is not named the way the game expects."
		out["message"] = folder_line % LibraryNames.lower()
		out["action"] = "Remove it and add it again from its original file."
		return out
	if _is_damage(reason):
		out["kind"] = KIND_DAMAGED
		out["message"] = "This %s's files are damaged or incomplete." % LibraryNames.lower()
		out["action"] = "Add it again from a fresh copy, or remove it."
		return out
	if reason.begins_with("dependency cycle") or reason.begins_with("dependencies are nested"):
		var loop_line := "This %s needs others in a loop the game cannot sort out."
		out["message"] = loop_line % LibraryNames.lower()
		out["action"] = "Remove it, or ask its author for a fixed copy."
		return out
	if reason.begins_with("more than") and "active" in reason:
		out["message"] = "Too many %s are turned on at once." % LibraryNames.lower(2)
		out["action"] = "Turn some off."
		return out
	out["message"] = "This %s has a problem and cannot be used." % LibraryNames.lower()
	out["action"] = GENERIC_ACTION
	return out


## The explanations of every reason of `info`, in order.
static func explain_all(info: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for reason: Variant in info.get("reasons", []) as Array:
		var explained := explain(String(reason))
		# The duplicate says what to do (keep one) and leads: the folder's name is its symptom.
		if explained["kind"] == KIND_DUPLICATE:
			out.push_front(explained)
		else:
			out.append(explained)
	return out


## The plain first line of a row or card for `info`: the first reason's message, with its action.
static func headline(info: Dictionary) -> String:
	var all := explain_all(info)
	if all.is_empty():
		return ""
	return sentence(all[0])


## "message action" as one string.
static func sentence(explained: Dictionary) -> String:
	var action := String(explained["action"])
	return String(explained["message"]) + ((" " + action) if action != "" else "")


## True when the technical text of `reason` points at a file that did not read.
static func _is_damage(reason: String) -> bool:
	for needle in ["is not valid JSON", "is missing or empty", "is not a JSON object"]:
		if needle in reason:
			return true
	for start in ["library.json", "catalog.json", "file ", "biomes/", "assets/"]:
		if reason.begins_with(start):
			return true
	return false


## Fills `out` for the "needs library ..." reasons; true when `reason` is one.
static func _dependency(reason: String, out: Dictionary) -> bool:
	var pattern := RegEx.create_from_string(
		(
			"^needs library '([^']+)'(?: (.+?))?"
			+ "(?:, which is (not installed|disabled|unavailable)|, but (.+) is installed)$"
		)
	)
	var found := pattern.search(reason)
	if found == null:
		return false
	var need := found.get_string(1)
	var wanted := found.get_string(2)
	var state := found.get_string(3)
	var have := found.get_string(4)
	var shown := dependency_title(need)
	var is_core := need == LibraryContracts.CORE_ID
	out["kind"] = KIND_DEPENDENCY
	if state == "disabled":
		out["message"] = "This %s needs %s, which is turned off." % [LibraryNames.lower(), shown]
		out["action"] = "Turn %s on." % shown
	elif state == "unavailable":
		var own_line := "This %s needs %s, which has a problem of its own."
		out["message"] = own_line % [LibraryNames.lower(), shown]
		out["action"] = "Fix %s first, or remove this one." % shown
	elif state == "not installed":
		out["message"] = (
			"This %s needs %s%s, which is not installed."
			% [LibraryNames.lower(), shown, _range_words(wanted, true)]
		)
		out["action"] = "Add %s, or remove this one." % shown
	else:
		var low := _lower_bound(wanted)
		var older := low != "" and LibraryVersions.compare(have, low) < 0
		var held := _short(have, 2)
		var where := "this game has %s" % held if is_core else "you have %s" % held
		if older or low == "":
			out["message"] = (
				"This %s needs %s%s; %s."
				% [LibraryNames.lower(), shown, _range_words(wanted, true), where]
			)
			out["action"] = "Update the game or remove it."
			if not is_core:
				out["action"] = "Update %s or remove this one." % shown
		else:
			out["message"] = (
				"This %s was made for %s%s; %s."
				% [LibraryNames.lower(), shown, _range_words(wanted, false), where]
			)
			out["action"] = "Ask its author for a newer copy, or remove it."
	return true


## The title of dependency `id`: "Core" for the game's own, else the installed name, else the id.
static func dependency_title(id: String) -> String:
	if id == LibraryContracts.CORE_ID:
		return "Core"
	var found := LibraryRegistry.info(id)
	return String(found.get("name", id)) if not found.is_empty() else id


## The version a dependency range asks for, in words: "version 1.0 or newer" for "^1.0" or
## ">=1.0", "version <range>" for any other range, "" for any version. No leading space.
static func version_words(range_text: String) -> String:
	var text := range_text.strip_edges()
	if text == "" or text == "*" or text == "any version":
		return ""
	var low := _lower_bound(text)
	return ("version %s or newer" % low) if low != "" else "version " + text


## " 9 or newer" for a caret or at-least range ("^9.0", ">=9.0"), " 9" when `needing` is false;
## any other range reads as " version <range>"; "" for any version. Starts with a space.
static func _range_words(range_text: String, needing: bool) -> String:
	var text := range_text.strip_edges()
	if text == "" or text == "*" or text == "any version":
		return ""
	var low := _lower_bound(text)
	if low != "":
		var short := _short(low)
		return (" %s or newer" % short) if needing else (" %s" % short)
	return " version " + text


## The lowest version a range names ("^9.0" -> "9.0", ">=1.2.0 <2" -> "1.2.0"), "" when none.
static func _lower_bound(range_text: String) -> String:
	for token in range_text.strip_edges().split(" ", false):
		for prefix in ["^", "~", ">=", "="]:
			if token.begins_with(prefix):
				return token.substr(prefix.length())
		if token.length() > 0 and token[0].is_valid_int():
			return token
	return ""


## A version as a player says it: "9.0.0" and "9.0" are "9", "1.2.0" is "1.2", "1.0.0-dev" is
## "1": trailing zero parts and a pre-release tag are not said.
static func _short(version: String, keep: int = 1) -> String:
	var parts := Array(version.split("-")[0].split("."))
	while parts.size() > keep and String(parts.back()) == "0":
		parts.pop_back()
	return ".".join(parts)
