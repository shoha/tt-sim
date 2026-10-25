class_name LibraryNames
extends RefCounted

## The words a player sees for a content library, in ONE place so a rename is a one-line change.
## Internals keep "library" (folders, ids, classes, settings keys, docs): the word is also taken in
## the title screen, where the library is the list of maps, so the interface says "Collection" for
## the data-only folder of plants and ground this module manages. Change TITLE_SINGULAR and
## TITLE_PLURAL below and every label, caption, tooltip, toast and dialog follows (the
## manager, the install card, the New map dialog's link, the title's tool, the mismatch and the
## transfer dialogs); nothing else names the word. User decision 2026-10-24: the final name is
## undecided. User decision 2026-10-25: no dialog says "plants" (a collection also holds rocks and
## ground): they say the collection word, through the helpers below, and "Built in" is the one
## term for what the game ships.

const TITLE_SINGULAR := "Collection"
const TITLE_PLURAL := "Collections"
## The one term for a collection that comes with the game (the list chip, the card, the facts).
const BUILT_IN := "Built in"
## What the placeholder licence of the game's own collection reads as to a player.
const LICENSE_INCLUDED := "Included with the game"
## The link of the "Find collections" button in the manager. Empty hides the button: the owner has
## not named a catalogue yet (2026-10-25); set the URL here and the link appears.
const CATALOG_URL := ""
## The states a row and a card can be in, as the words a player reads (a state is never colour
## alone: each also has an icon).
const NEEDS_ATTENTION := "Needs attention"


## "Collection" or "Collections" (capitalised), by count when `count` is given and not 1.
static func title(count: int = 1) -> String:
	return TITLE_SINGULAR if count == 1 else TITLE_PLURAL


## The same word in lower case, for the middle of a sentence.
static func lower(count: int = 1) -> String:
	return title(count).to_lower()


## "1 collection", "3 collections", "no collections".
static func counted(count: int) -> String:
	if count == 0:
		return "no " + lower(2)
	return "%d %s" % [count, lower(count)]


## "1 asset", "3 assets": `count` and the noun, pluralised by adding an s unless `many` is given.
## The one helper for every counted noun in a dialog (a "(1 assets)" slip is a test failure).
static func count_of(count: int, noun: String, many: String = "") -> String:
	var word := noun if count == 1 else (many if many != "" else noun + "s")
	return "%d %s" % [count, word]


## "a collection" (or "an ..." when the word starts with a vowel), for sentences; `capital` for
## the start of one ("A collection").
static func article(capital: bool = false) -> String:
	var word := lower(1)
	var vowel := word.substr(0, 1) in ["a", "e", "i", "o", "u"]
	var text := ("an " if vowel else "a ") + word
	return text.substr(0, 1).to_upper() + text.substr(1) if capital else text


## The line every install card carries: the promise that makes importing safe to say yes to.
static func only_art_and_settings() -> String:
	return "This %s only contains art and settings, never programs." % lower(1)


## The manager's one-line explanation under its title.
static func manager_caption() -> String:
	return (
		"Add plants, rocks and ground that start new places. %s hold art and settings, never programs."
		% title(2)
	)


## The persistent one-line hint at the foot of the list: the two ways in.
static func drop_hint() -> String:
	return "Drop a .ttlib or .zip here, or use Import."


## The summary at the top of the list: "1 collection needs attention", "2 collections need
## attention". Empty when none does.
static func attention_summary(count: int) -> String:
	if count <= 0:
		return ""
	return "%s %s attention" % [counted(count), "needs" if count == 1 else "need"]


## The licence as a player reads it: the game's own placeholder ("TBD (...)", the owner chooses
## later) reads "Included with the game"; an empty one stays empty.
static func license_text(raw: String) -> String:
	if raw.strip_edges().to_upper().begins_with("TBD"):
		return LICENSE_INCLUDED
	return raw


# ---- the dialogs that name collections the player lacks (map mismatch, host transfer, remove) ----


## The mismatch dialog's title: "This map needs collections you do not have".
static func mismatch_title() -> String:
	return "This map needs %s you do not have" % lower(2)


## The mismatch dialog's first choice: "Open without those collections".
static func open_without() -> String:
	return "Open without those %s" % lower(2)


## The consent question's title: "The host uses collections you do not have".
static func host_uses_title() -> String:
	return "The host uses %s you do not have" % lower(2)


## What a removed collection does to the maps that use it, after "Alien World is deleted ...".
static func remove_tail(map_count: int) -> String:
	if map_count == 0:
		return " No saved map uses it."
	var maps := "1 saved map uses" if map_count == 1 else "%d saved maps use" % map_count
	return " %s it; opening one will ask whether to open it without those %s." % [maps, lower(2)]


## "Receiving collections from the host: 2 KB of 4 KB (39%)" starts with this.
static func receiving_from_host() -> String:
	return "Receiving %s from the host" % lower(2)
