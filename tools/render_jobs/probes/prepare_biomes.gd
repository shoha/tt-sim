extends RefCounted

## Render-job probe (`call` op). step.all = true: prepare every palette biome on the
## authoring scatter (threaded loads, resolved one species per frame). Otherwise reports
## whether that preparation has finished, how long it took, and the species and mesh
## pipeline counts.


static func run(base: Node, step: Dictionary) -> String:
	var c: AuthoringController = base.get("_authoring_controller")
	if bool(step.get("all", false)):
		var ids: Array = []
		for biome: Dictionary in PaletteLibrary.biomes():
			var id: String = biome.get("id", "")
			if id != "":
				ids.append(id)
				c.scatter.prepare_biome(id)
		c.scatter.set_meta("render_job_prep_start", Time.get_ticks_msec())
		return "preparing %d biomes: %s" % [ids.size(), str(ids)]
	var start: int = c.scatter.get_meta("render_job_prep_start", 0)
	return (
		"prepared %s after %d ms, species %d, mesh pipelines %d"
		% [
			str(not c.scatter.has_prepared_species()),
			Time.get_ticks_msec() - start,
			(c.scatter.get("_species") as Dictionary).size(),
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH)
		]
	)
