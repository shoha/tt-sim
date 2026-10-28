class_name LibraryHash
extends RefCounted

## The short content hash of a library: the identity a map records for it (`libraries: [{id,
## version, hash}]`) and a partial library keeps from its source. SHA-256 over the library's JSON
## texts in a fixed order, cut to `length` hex characters. Pure over LibraryReader's sources.


## The hash of `sources` (LibraryReader's input): library.json, the catalog, the biome-defs, the
## surfaces' info files, the lock files, then the structures index and recipes. A part a library
## does not have adds nothing, so a library hashes as it did before that part existed.
static func of(sources: Dictionary, length: int) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	for text: String in [String(sources.get("library", "")), String(sources.get("catalog", ""))]:
		_feed(hashing, text)
	_feed_all(hashing, sources.get("biomes", {}))
	_feed_all(hashing, sources.get("surfaces", {}))
	# Lock files change what a query selects.
	_feed_all(hashing, sources.get("locks", {}))
	# Structures change what a map built from them looks like.
	var structures: Dictionary = sources.get("structures", {})
	_feed(hashing, String(structures.get("index", "")))
	_feed_all(hashing, structures.get("recipes", {}))
	return hashing.finish().hex_encode().substr(0, length)


## Adds the texts of `texts` ({name: text}) in name order.
static func _feed_all(hashing: HashingContext, texts: Dictionary) -> void:
	var names: Array = texts.keys()
	names.sort()
	for file_name: String in names:
		_feed(hashing, String(texts[file_name]))


## Adds `text` to the hash; an empty text adds nothing (HashingContext rejects empty input).
static func _feed(hashing: HashingContext, text: String) -> void:
	if text != "":
		hashing.update(text.to_utf8_buffer())
