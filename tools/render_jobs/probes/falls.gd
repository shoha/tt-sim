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

const WATER := preload("res://tools/render_jobs/probes/water.gd")

static var _found: Dictionary = {}


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"falls":
			return _falls(base)
		"look":
			return WATER.run(base, {"action": "look", "at": _resolve(step.get("at"))})
	return "unknown action %s" % step.get("action", "")


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
