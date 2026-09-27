extends RefCounted

## Render-job probe (`call` op). Sets ground shader parameters in-run for an A/B.
## step.params: {name: value}; step.broad_factor: rebuild the broad texture at that many
## samples per texel.


static func run(base: Node, step: Dictionary) -> String:
	var terrain: Node = base.get("_authoring_controller").editor.terrain
	var mat: ShaderMaterial = terrain.get_material()
	var params: Dictionary = step.get("params", {})
	for key in params:
		mat.set_shader_parameter(String(key), params[key])
	if step.has("broad_factor"):
		var w: Image = terrain.get_biome_weights()
		var f := int(step.broad_factor)
		var img := w.duplicate() as Image
		img.resize(
			maxi(1, ceili(float(w.get_width()) / f)),
			maxi(1, ceili(float(w.get_height()) / f)),
			Image.INTERPOLATE_TRILINEAR
		)
		mat.set_shader_parameter("biome_broad", ImageTexture.create_from_image(img))
	return "ok %s" % str(params)
