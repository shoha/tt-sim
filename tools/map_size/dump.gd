extends RefCounted

## Render-job probe for the map-size measurement (see README.md): writes the open authoring document
## (scatter and props synced from the scene, as a save does) to user://_msize_/<name>.ttmap
## through MapDocumentIO.write, the same path a level save takes. Never touches
## user://levels/.

const OUT_DIR := "user://_msize_"


static func run(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null:
		return "no authoring controller"
	if String(step.get("action", "dump")) == "fill":
		return _fill(ctrl)
	ctrl.call("_sync_document")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var name := String(step.get("name", "map"))
	var path := "%s/%s.ttmap" % [OUT_DIR, name]
	var err := MapDocumentIO.write(ctrl.document, path)
	var doc: MapDocument = ctrl.document
	return (
		"dumped %s err %d scatter rows %d (%d assets) props %d water %d crossings %d"
		% [
			path,
			err,
			MapDocument.row_count(doc.scatter),
			doc.scatter.size(),
			MapDocument.row_count(doc.props),
			doc.water_bodies.size(),
			doc.crossings.size(),
		]
	)


## Paints the open map's first biome at full density over every sample (as the perf pass's
## "painted at full density over a whole 200 ft map") and regenerates the whole scatter.
static func _fill(ctrl: AuthoringController) -> String:
	var doc: MapDocument = ctrl.document
	var count := doc.sample_count()
	for i in count:
		doc.biome_slots[i] = 1
		doc.biome_density[i] = 255
	var scatter: AuthoredScatter = ctrl.scatter
	var half := doc.extent_m() * 0.5
	scatter.request_region(Rect2(-half, doc.extent_m()))
	return "filled %d samples with %s at 255" % [count, doc.biome_ids[0]]
