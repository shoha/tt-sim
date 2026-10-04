extends RefCounted

## Render-job probe (`call` op) for waterfalls (phase 4c, P4c-2): the falls the open document
## derives (WaterFalls.falls) and the ground the carve shaped under each, read numerically
## beside the captures. Positions are map XZ metres. step.action:
##   falls                 every fall: its reaches, lip, direction, drop, half-width, the face
##                         foot and plunge pool the carve shaped (WaterCarve.fall_shape), the
##                         steepest slope found, and the carved ground along the lower course
##                         from the lip every quarter metre; names "found:fall<k>_lip",
##                         "found:fall<k>_foot" (the face's foot) and "found:fall<k>_plunge"
##                         (the middle of the plunge pool) for `look` and any point field.
##   look {at}             pans so the screen centre looks at `at` ([x, z] or found:).
## P4c-4 (the falls shader):
##   falls_visible {visible} shows or hides every AuthoredWater-falls mesh alone (the water
##                         stays), for an in-run GPU A/B of the falls.
##   quality {low}         sets the Water Quality globals (water_quality_skip_fine_detail and
##                         water_quality_skip_refraction) to `low`, as Settings > Graphics Low
##                         does; the shader drops its second octave and the mist.
##   clock {scale}         Engine.time_scale: 0 freezes the shader clock (TIME) for a capture
##                         whose PNG save would otherwise advance it; 1 resumes. The driver's
##                         `wait` runs on scaled time, so set 1 before any wait.
##   palette {name}        applies a WaterPresets palette (lagoon, lake, river, swamp, ocean,
##                         glacial) to the water and the falls, as the Water pane's tile does.

const WATER := preload("res://tools/render_jobs/probes/water.gd")

static var _found: Dictionary = {}


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"falls":
			return _falls(base)
		"look":
			return WATER.run(base, {"action": "look", "at": _resolve(step.get("at"))})
		"falls_visible":
			return _falls_visible(base, bool(step.get("visible", true)))
		"quality":
			return _quality(bool(step.get("low", false)))
		"clock":
			Engine.time_scale = float(step.get("scale", 1.0))
			return "time scale %.3f" % Engine.time_scale
		"palette":
			return _palette(String(step.get("name", "lagoon")))
	return "unknown action %s" % step.get("action", "")


static func _falls_visible(base: Node, on: bool) -> String:
	var gm := base.get("_game_map") as GameMap
	if gm == null or gm.map_container == null:
		return "no map"
	var root := gm.map_container.get_node_or_null(^"LevelMap") as Node3D
	if root == null:
		return "no map"
	var count := 0
	for node in root.find_children(WaterFallMesh.MESH_NAME, "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = on
		count += 1
	return "%d falls meshes visible %s" % [count, str(on)]


static func _quality(low: bool) -> String:
	RenderingServer.global_shader_parameter_set("water_quality_skip_fine_detail", low)
	RenderingServer.global_shader_parameter_set("water_quality_skip_refraction", low)
	return "water quality low %s" % str(low)


static func _palette(name: String) -> String:
	if not WaterPresets.PALETTES.has(name):
		return "no palette %s" % name
	WaterGlbUtils.apply_water_settings(WaterPresets.PALETTES[name])
	var material := AuthoredWater.fall_material()
	return (
		"palette %s: falls foam %s water %s"
		% [
			name,
			str(material.get_shader_parameter("foam_color")),
			str(material.get_shader_parameter("water_color")),
		]
	)


static func _resolve(value: Variant) -> Variant:
	if value is String and String(value).begins_with("found:"):
		var p: Vector2 = _found.get(String(value).trim_prefix("found:"), Vector2.ZERO)
		return [p.x, p.y]
	return value


## The falls of the open document and the carved ground under each (see the header).
static func _falls(base: Node) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	ctrl.editor.finish_height_work()
	var doc := ctrl.document
	var out := PackedStringArray()
	var k := 0
	for fall in WaterFalls.falls(doc):
		k += 1
		var lip: Vector2 = fall.lip
		var direction: Vector2 = fall.dir
		var drop := float(fall.top) - float(fall.bottom)
		var lower: WaterBody = doc.water_bodies[fall.lower_index]
		var plunge := WaterFalls.plunge_depth(drop)
		var foot := WaterCarve.fall_foot(drop, lower.depth_m())
		var basin := WaterFalls.plunge_length(drop)
		_found["fall%d_lip" % k] = lip
		_found["fall%d_foot" % k] = lip + direction * foot
		_found["fall%d_plunge" % k] = lip + direction * (foot + 0.5 * basin)
		var profile := PackedStringArray()
		var steepest := 0.0
		var previous := WaterGeometry.ground_at(doc, lip)
		var s := 0.0
		while s <= foot + basin + 1e-6:
			var g := WaterGeometry.ground_at(doc, lip + direction * s)
			profile.append("%.2f:%.2f" % [s, g])
			steepest = maxf(steepest, (previous - g) / 0.25)
			previous = g
			s += 0.25
		(
			out
			. append(
				(
					(
						"fall %d: %d -> %d lip %s dir %s drop %.2f hw %.2f foot %.2f m plunge %.2f m"
						+ " deep %.2f m | steepest %.1f deg | ground %s"
					)
					% [
						k,
						int(fall.upper_index),
						int(fall.lower_index),
						str(lip.snapped(Vector2.ONE * 0.01)),
						str(direction.snapped(Vector2.ONE * 0.01)),
						drop,
						float(fall.half_width),
						foot,
						basin,
						plunge,
						rad_to_deg(atan(steepest)),
						" ".join(profile),
					]
				)
			)
		)
	if out.is_empty():
		return "no falls (%d bodies)" % doc.water_bodies.size()
	return " || ".join(out)
