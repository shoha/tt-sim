class_name BaseScatterEraser
extends RefCounted

## Live erase-mask filtering of a dressed Blender map's own scatter while authoring. At
## play time the loader drops a GLB scatter row whose origin falls on an erased sample
## (MapDocument.erase_filter, threaded into ScatterGlbUtils.build_scatter); here the same
## rule is re-applied to the already built chunk nodes as the brush paints the mask, so
## what the author sees is exactly what a player's load builds.
##
## Source of truth. The GLB's full row list is still on the map root as scene extras
## (GlbUtils.SCENE_EXTRAS_META, "tt_scatter_instances"), unfiltered, so the index is built
## from it rather than read back from MultiMeshes (which also cannot be read back headless).
## Each species' rows are converted and bucketed by 10 m cell exactly as build_scatter does,
## and each (species, cell) is matched to the chunk node the loader built:
## `<stem>_MultiMesh<suffix>`, suffixed with the cell unless the species filled one cell.
## A chunk the loader did not build (all its rows were already erased when the level was
## opened) is skipped: nothing the brush does can bring back more than the session opened
## with, and undo only returns to states the session had.
##
## refresh(doc, rect) re-filters the chunks of every cell `rect` touches: the kept
## instances are rebuilt in the loader's order (FoliageBudget.shuffled_order seeded by the
## species key plus the node's suffix), the density budget's visible fraction of the chunk
## is kept, and instances that just went away shrink out (ScatterShrink). Instances that
## come back (undo) reappear at once.

const EXTRAS_KEY := "tt_scatter_instances"

## Seconds removed instances take to shrink; 0 removes them at once (tests).
var shrink_seconds: float = ScatterShrink.SECONDS

var _root: Node3D = null
## cell -> Array of {"node", "key", "stem", "suffix", "transforms": Array[Transform3D],
## "kept": PackedByteArray (1 per transform)}.
var _cells: Dictionary = {}


## An eraser for `map_root` (the LevelMap a GLB loaded as, with `doc`'s erase filter
## already applied by the loader), or null when the map carries no scatter rows.
static func create(map_root: Node3D, doc: MapDocument) -> BaseScatterEraser:
	var extras: Dictionary = map_root.get_meta(GlbUtils.SCENE_EXTRAS_META, {})
	var groups: Variant = extras.get(EXTRAS_KEY)
	if not groups is Dictionary or (groups as Dictionary).is_empty():
		return null
	var eraser := BaseScatterEraser.new()
	eraser._root = map_root
	eraser._index(groups, doc.erase_filter())
	return eraser


## The transforms of `transforms` whose origin `keep` returns true for (all of them when
## `keep` is not valid): the loader's rule, as a keep flag per transform.
static func keep_flags(transforms: Array[Transform3D], keep: Callable) -> PackedByteArray:
	var flags := PackedByteArray()
	flags.resize(transforms.size())
	for i in transforms.size():
		flags[i] = 1 if not keep.is_valid() or keep.call(transforms[i].origin) else 0
	return flags


## Indexes every species' rows the way build_scatter built them: converted by the loader's
## own conversion, bucketed by cell, filtered by the erase filter the level opened with
## (`keep`). The loader names a species' chunks without a cell suffix when the filtered
## rows fill one cell, so that is decided from the filtered buckets here too.
func _index(groups: Dictionary, keep: Callable) -> void:
	var chunk := ScatterChunker.CHUNK_SIZE_WORLD_UNITS
	for source_name in groups:
		var rows: Variant = groups[source_name]
		if not rows is Array:
			continue
		var key := String(source_name)
		var valid := ScatterGlbUtils._collect_valid_transforms(rows)
		if valid.is_empty():
			continue
		var buckets := ScatterChunker.bucket_by_cell(valid, chunk)
		var flags := {}
		var live := 0
		for cell in buckets:
			flags[cell] = keep_flags(buckets[cell], keep)
			if (flags[cell] as PackedByteArray).has(1):
				live += 1
		for cell in buckets:
			if not (flags[cell] as PackedByteArray).has(1):
				continue  # The loader built no chunk here, and nothing can bring one back.
			var suffix := "" if live == 1 else ScatterChunker.cell_suffix(cell)
			var found := _find_chunk(key, suffix)
			if found == null:
				continue
			if not _cells.has(cell):
				_cells[cell] = []
			(
				_cells[cell]
				. append(
					{
						"node": found,
						"key": key,
						"stem": String(found.name).trim_suffix("_MultiMesh" + suffix),
						"suffix": suffix,
						"transforms": buckets[cell],
						"kept": flags[cell],
					}
				)
			)


## The chunk node the loader named for species `key` with `suffix`, or null.
func _find_chunk(key: String, suffix: String) -> MultiMeshInstance3D:
	for stem in [key.validate_node_name(), key]:
		var node := _root.get_node_or_null(NodePath(stem + "_MultiMesh" + suffix))
		if node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh:
			return node
	return null


## Re-filters every indexed chunk in the cells `rect` (document-local XZ, the GLB-root
## frame) touches against `doc`'s erase mask. Returns how many instances it removed and
## restored, as Vector2i(removed, restored).
func refresh(doc: MapDocument, rect: Rect2) -> Vector2i:
	var keep := doc.erase_filter()
	var removed := 0
	var restored := 0
	for cell in ScatterGenerator.cells_in_bounds(rect.grow(0.01)):
		for entry in _cells.get(cell, []):
			var counts := _refresh_entry(entry, keep)
			removed += counts.x
			restored += counts.y
	return Vector2i(removed, restored)


## Re-filters every indexed chunk (after an undo that may span anything).
func refresh_all(doc: MapDocument) -> Vector2i:
	var total := Vector2i.ZERO
	var keep := doc.erase_filter()
	for cell in _cells:
		for entry in _cells[cell]:
			total += _refresh_entry(entry, keep)
	return total


func _refresh_entry(entry: Dictionary, keep: Callable) -> Vector2i:
	var node: MultiMeshInstance3D = entry.node
	if not is_instance_valid(node):
		return Vector2i.ZERO
	var transforms: Array[Transform3D] = entry.transforms
	var flags := keep_flags(transforms, keep)
	var before: PackedByteArray = entry.kept
	if flags == before:
		return Vector2i.ZERO
	var kept: Array[Transform3D] = []
	var gone: Array[Transform3D] = []
	var restored := 0
	for i in transforms.size():
		if flags[i] != 0:
			kept.append(transforms[i])
			if before[i] == 0:
				restored += 1
		elif before[i] != 0:
			gone.append(transforms[i])
	entry.kept = flags
	var old := node.multimesh
	var fraction := 1.0
	if old.visible_instance_count >= 0 and old.instance_count > 0:
		fraction = float(old.visible_instance_count) / float(old.instance_count)
	var order := FoliageBudget.shuffled_order(kept.size(), String(entry.key) + entry.suffix)
	var ordered: Array[Transform3D] = []
	for index in order:
		ordered.append(kept[index])
	node.multimesh = ScatterGlbUtils.build_multimesh(old.mesh, ordered)
	if fraction < 1.0:
		node.multimesh.visible_instance_count = roundi(fraction * ordered.size())
	var category := String(node.get_meta("wind_foliage_category", ""))
	ScatterShrink.start(
		_root,
		old.mesh,
		entry.stem,
		entry.suffix,
		gone,
		category,
		ScatterShrink.sink_depth_for(old.mesh, gone),
		shrink_seconds
	)
	return Vector2i(gone.size(), restored)


## Instances currently kept across every indexed chunk (for tests and measurement).
func kept_count() -> int:
	var total := 0
	for cell in _cells:
		for entry in _cells[cell]:
			for flag in entry.kept:
				total += flag
	return total
