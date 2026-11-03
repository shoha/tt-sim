extends SceneTree

## Triangle budget of the eye-level window variants (card eyewindows, WIP probe). Headless:
##   godot --headless --path <tt-sim worktree> --script <this file>
## Builds a few styled houses with procgen's own recipes under each ProcgenGlazing.eye_variant
## ("" today, A geometry, B pane flag, C geometry plus flag) and prints, per house, the whole
## triangle count, the window count, and the glazing node's triangles by piece (pane, bars, frame
## and sill, shutters, curtain), then per window. Writes the text to user://eye_windows_tris.txt.

const HOUSES := [
	["thatched_cottage", 9, 6.0, 4.0],
	["slate_house", 7, 7.0, 5.0],
	["canal_house", 4, 5.0, 8.0],
	["brick_terrace", 4, 5.0, 7.0],
	["barn", 2, 9.0, 6.0],
]
const VARIANTS := ["", "A", "B", "C"]

var _lines: Array[String] = []


func _init() -> void:
	for h in HOUSES:
		_lines.append("== %s (seed %d, %.0f x %.0f m)" % [h[0], h[1], h[2], h[3]])
		for v in VARIANTS:
			ProcgenGlazing.eye_variant = v
			_report(h, v)
	ProcgenGlazing.eye_variant = ""
	var f := FileAccess.open("user://eye_windows_tris.txt", FileAccess.WRITE)
	for l in _lines:
		print(l)
		f.store_line(l)
	quit()


func _report(h: Array, variant: String) -> void:
	var reg := ProcgenStructureRegistry.new()
	var doc: PlantGraphDocument = ProcgenBuildingStyles.document(h[0], int(h[1]))
	doc.registry = reg
	var inputs := ProcgenStructureInputs.new()
	var w: float = h[2]
	var d: float = h[3]
	inputs.guide = ProcgenGuide.polyline(
		PackedVector3Array(
			[Vector3(0, 0, 0), Vector3(w, 0, 0), Vector3(w, 0, d), Vector3(0, 0, d)]
		),
		true
	)
	inputs.env = ProcgenEnvironment.new()
	inputs.params = {"glazing": 1.0}
	inputs.seed_value = 5
	var evaluator := PlantGraphEvaluator.new(reg)
	var plant: Variant = evaluator.evaluate_structure(doc, inputs)
	if plant == null:
		_lines.append("  %-2s none %s" % [variant, str(evaluator.errors)])
		return
	var g: PlantGeometry = plant["lods"][0]
	var by := {"pane": 0, "bars": 0, "frame_sill": 0, "shutter": 0, "curtain": 0, "other": 0}
	var panes := {}
	for s in g.surfaces:
		for t in s.indices.size() / 3:
			var path := g.tag_at(g.surfaces.find(s), t)
			if not path.contains("glazing_"):
				continue
			var key := "other"
			if path.contains("/pane"):
				key = "pane"
				panes[path] = true
			elif path.contains("/muntin"):
				key = "bars"
			elif path.contains("/frame/") or path.ends_with("/sill"):
				key = "frame_sill"
			elif path.contains("/shutter"):
				key = "shutter"
			elif path.contains("/curtain"):
				key = "curtain"
			by[key] += 1
	var n := maxi(panes.size(), 1)
	var win := (
		int(by.pane) + int(by.bars) + int(by.frame_sill) + int(by.shutter) + int(by.curtain)
	)
	_lines.append(
		(
			"  %-2s house %5d tris | windows %2d | glazing tris: pane %3d bars %3d frame+sill %3d"
			+ " shutters %3d curtain %3d | per window %.1f (pane %.1f)"
		)
		% [
			variant if variant != "" else "-",
			g.triangle_count(),
			panes.size(),
			by.pane,
			by.bars,
			by.frame_sill,
			by.shutter,
			by.curtain,
			float(win) / n,
			float(by.pane) / n,
		]
	)
