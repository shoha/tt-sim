extends RefCounted

## Render-job probe (`call` op) for water shader A/Bs (P4-5), on the shared water material
## every water mesh uses (WaterGlbUtils). Fields, all optional:
##   params {uniform: value}   sets shader uniforms; logs each one's previous value.
##   shader "current"          puts res://shaders/water.gdshader back.
##   shader "<zip path>"       swaps in shaders/water.gdshader read from a zip made with
##                             `git archive --format=zip --output=<zip path> <commit>
##                             shaders/water.gdshader` (an older shader, same uniforms).
##   glow (bool)               the world environment's glow on or off.
##   sun_pitch (degrees)       the first DirectionalLight3D's X rotation (its elevation).
## A level load re-applies the level's water settings, so call this after the load.

const ENTRY := "shaders/water.gdshader"


static func run(base: Node, step: Dictionary) -> String:
	var material := WaterGlbUtils._get_water_material()
	var out := PackedStringArray()
	if step.has("glow"):
		for node in base.get_tree().root.find_children("*", "WorldEnvironment", true, false):
			var env := (node as WorldEnvironment).environment
			if env != null:
				out.append("glow %s -> %s" % [str(env.glow_enabled), str(step.glow)])
				env.glow_enabled = bool(step.glow)
	if step.has("sun_pitch"):
		var suns := base.get_tree().root.find_children("*", "DirectionalLight3D", true, false)
		if not suns.is_empty():
			var sun := suns[0] as DirectionalLight3D
			out.append("sun pitch %.1f -> %.1f" % [sun.rotation_degrees.x, float(step.sun_pitch)])
			sun.rotation_degrees.x = float(step.sun_pitch)
	var which := String(step.get("shader", ""))
	if which == "current":
		material.shader = load("res://shaders/water.gdshader")
		out.append("shader current")
	elif which != "":
		var zip := ZIPReader.new()
		if zip.open(which) != OK:
			return "cannot open %s" % which
		var code := zip.read_file(ENTRY).get_string_from_utf8()
		zip.close()
		var shader := Shader.new()
		shader.code = code
		material.shader = shader
		out.append("shader from %s (%d chars)" % [which, code.length()])
	var params: Dictionary = step.get("params", {})
	for key: String in params:
		var before: Variant = material.get_shader_parameter(key)
		material.set_shader_parameter(key, params[key])
		out.append("%s %s -> %s" % [key, str(before), str(params[key])])
	return "; ".join(out) if not out.is_empty() else "nothing to do"
