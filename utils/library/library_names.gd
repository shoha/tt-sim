class_name LibraryNames
extends RefCounted

## The words a player sees for a content library, in ONE place so a rename is a one-line change.
## Internals keep "library" (folders, ids, classes, settings keys, docs): the word is also taken in
## the title screen, where the library is the list of maps, so the interface says "Collection" for
## the data-only folder of plants and ground this module manages. Change TITLE_SINGULAR and
## TITLE_PLURAL below and every label, caption, tooltip, toast and dialog follows (the
## manager, the install card, the New map dialog's link, the title's tool); nothing else names the
## word. User decision 2026-10-24: the final name is undecided.

const TITLE_SINGULAR := "Collection"
const TITLE_PLURAL := "Collections"


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
