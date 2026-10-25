class_name LibraryLayer
extends RefCounted

## The merge rule that lays a compiled library over the palette cache (step S10 moved it here from
## the treecube-era PaletteOverlay). `lay` takes a palette.json-shaped Dictionary (the compiler's
## output for one library), validates it and returns the palette `base` with its biomes laid over:
## each library biome replaces the base's biome of the same runtime id (or is appended), together
## with all of that biome's `<runtime id>/...` assets. A library also brings its own surfaces; the
## compiled table holds the base's too, unchanged, so the merge adds only what is new.
##
## No GLB is read here: a library's assets are registered with AssetStore, which parses each one on
## first use. `lay` reads no file and touches no cache; PaletteLibrary.install_overlay caches a
## report that is ok.


## `raw` (a compiled library's palette) laid over the validated palette `base`. Returns {ok, error,
## palette (a new Dictionary; `base` is left as it was), dropped (every asset id whose cached mesh
## is now stale: the replaced biomes' old and new ids), biomes (runtime ids laid), warnings (the
## validator's), msec}. A library with no biome that validates is not ok and returns `base`.
static func lay(raw: Dictionary, base: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var report := {
		"ok": false,
		"error": "",
		"palette": base,
		"dropped": [],
		"biomes": [],
		"warnings": [],
		"msec": 0.0,
	}
	var result := PaletteLibrary.validate_palette(raw)
	report["warnings"] = result["warnings"]
	var pkg: Dictionary = result["palette"]
	var biomes: Array = (base["biomes"] as Array).duplicate()
	var assets: Dictionary = (base["assets"] as Dictionary).duplicate()
	for biome: Dictionary in pkg["biomes"]:
		var id := String(biome["id"])
		var at := biomes.find_custom(func(b: Dictionary) -> bool: return b["id"] == id)
		if at < 0:
			biomes.append(biome)
		else:
			biomes[at] = biome
		report["biomes"].append(id)
		for key: String in assets.keys():
			if key.begins_with(id + "/"):
				assets.erase(key)
				report["dropped"].append(key)
		for key: String in pkg["assets"]:
			if key.begins_with(id + "/"):
				assets[key] = pkg["assets"][key]
				if not (report["dropped"] as Array).has(key):
					report["dropped"].append(key)
	if (report["biomes"] as Array).is_empty():
		report["error"] = "the library has no biome that validates"
		return report
	var palette := base.duplicate()
	palette["biomes"] = biomes
	palette["assets"] = assets
	var surfaces: Dictionary = (base["surfaces"] as Dictionary).duplicate()
	surfaces.merge(pkg["surfaces"], true)
	palette["surfaces"] = surfaces
	report["palette"] = palette
	report["ok"] = true
	report["msec"] = (Time.get_ticks_usec() - started) / 1000.0
	return report
