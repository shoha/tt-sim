extends RefCounted

## Render-job probe (`call` op). Shows or hides the level reflection probe (step.visible,
## default true) and logs its box plus the environment's main effect switches.


static func run(base: Node, step: Dictionary) -> String:
	var out := ""
	for node in base.get_tree().root.find_children(
		"LevelReflectionProbe", "ReflectionProbe", true, false
	):
		var probe := node as ReflectionProbe
		probe.visible = bool(step.get("visible", true))
		out += (
			"probe at %s size %s blend %.2f visible %s "
			% [
				str(probe.global_position),
				str(probe.size),
				probe.blend_distance,
				str(probe.visible)
			]
		)
	for node in base.get_tree().root.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (node as WorldEnvironment).environment
		if env != null:
			out += (
				"ssil %s sdfgi %s glow %s fog %s vfog %s tonemap %d "
				% [
					str(env.ssil_enabled),
					str(env.sdfgi_enabled),
					str(env.glow_enabled),
					str(env.fog_enabled),
					str(env.volumetric_fog_enabled),
					env.tonemap_mode
				]
			)
	return out
