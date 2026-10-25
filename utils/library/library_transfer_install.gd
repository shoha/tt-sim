class_name LibraryTransferInstall
extends RefCounted

## The last step of LibraryTransfer.verify_and_install: a bundle that passed every check becomes
## from-host collections (LibraryFromHost) in the user's libraries folder. For each library of
## the bundle (docs/systems/library.md "The cache of downloaded collections"):
##   - no folder yet: it is installed as it came;
##   - a from-host copy of the same version and source hash: the bundle is a DELTA and is merged
##     into the kept files (LibraryPartialMerge), then the MERGED library is inspected again as
##     hard as a fresh one;
##   - a from-host copy of another version or hash: the host's library changed, the kept copy is
##     replaced by the bundle;
##   - the player's OWN copy: never written. For the library that was asked for that is an error
##     (the plan never asks while the player has a full copy; this is the race), for a dependency
##     the player's copy is used as it is.
## Nothing is written unless every library passes; the write itself is all or nothing
## (LibraryFromHost.commit).


## `split` {id: files}, `reads` {id: LibraryPartial.inspect's result}, `expect` the inspect
## context (official_ids, surfaces, dependencies), `ctx` as LibraryTransfer.verify_and_install's,
## `out` its result dictionary. Returns `out` with ok, libraries, merged, bytes, files.
static func run(
	split: Dictionary, reads: Dictionary, expect: Dictionary, ctx: Dictionary, out: Dictionary
) -> Dictionary:
	var errors: Array = out["errors"]
	var requested := String(ctx.get("library", ""))
	var plans: Array = []
	var merged: Array[String] = []
	var order: Array = split.keys()
	order.sort()
	for id: String in order:
		var read: Dictionary = reads[id]
		var library: Dictionary = read["library"]
		var decision := LibraryFromHost.decide(
			id, read["partial"], String(library.get("version", ""))
		)
		var mode := String(decision["mode"])
		if mode == "unsafe":
			errors.append({"code": "io", "text": "'%s' cannot be kept" % id})
			return out
		if mode == "own":
			if id == requested:
				errors.append({"code": "own_copy", "text": own_copy_text(id)})
				return out
			continue
		var files: Dictionary = split[id]
		if mode == "merge":
			var united := LibraryPartialMerge.merge(LibraryFromHost.read_folder_files(id), files)
			if not united["ok"]:
				errors.append({"code": united["code"], "text": "%s: %s" % [id, united["error"]]})
				return out
			var again := expect.duplicate()
			again["id"] = id
			again["wanted_version"] = ""
			var checked := LibraryPartial.inspect(united["files"], again)
			if not checked["ok"]:
				for error: Dictionary in checked["errors"]:
					errors.append({"code": error["code"], "text": "%s: %s" % [id, error["text"]]})
				return out
			files = united["files"]
			library = checked["library"]
			merged.append(id)
		(
			plans
			. append(
				{
					"id": id,
					"files": files,
					"library": library,
					"mode": mode,
					"record": decision["record"],
				}
			)
		)
	var made := (
		LibraryFromHost
		. commit(
			plans,
			{
				"host": String(ctx.get("host", "")),
				"now": int(ctx.get("now", Time.get_unix_time_from_system())),
				"cap": int(ctx.get("cap", -1)),
			}
		)
	)
	if not bool(made["ok"]):
		errors.append({"code": "io", "text": String(made["error"])})
		return out
	var count := 0
	for plan: Dictionary in plans:
		count += (plan["files"] as Dictionary).size()
	out["libraries"] = made["written"]
	out["merged"] = merged
	out["evicted"] = made["evicted"]
	out["bytes"] = int(made["bytes"])
	out["files"] = count
	out["ok"] = true
	return out


static func own_copy_text(id: String) -> String:
	var shown := String(LibraryRegistry.info(id).get("name", id))
	return (
		"you already have your own copy of %s, which the host's is never allowed to replace" % shown
	)
