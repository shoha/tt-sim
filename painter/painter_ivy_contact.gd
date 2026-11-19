class_name PainterIvyContact
extends RefCounted

## The painted ivy's contact shade (card painter-walls-round3; owner on the ivy, 2026-11-19: "any
## kind of AO or similar we could add or fake to make them feel more grounded on the building?").
## A structure's baked wall leaves (PainterVillage's decor stand-ins, kind wall leaf) get a second
## pass (painter/shaders/painter_ivy_contact.gdshader) hung on the stand-in's next_pass: the leaf
## cards drawn again, multiplied over the wall behind them, so a soft cool shade falls just under
## and round each clump. A faked occlusion: no shadow map, no wall data, only the cards' own
## cutout.
##
## The pass is part of the stand-in (a material PainterVillage made and owns), so releasing the
## stand-in releases it; the Classic material is never touched. It copies the stand-in's texture,
## cutout and wind uniforms once, when it is made.

const SHADER := "res://painter/shaders/painter_ivy_contact.gdshader"
## Metadata on every contact material.
const META := &"painter_ivy_contact"

## False leaves the ivy without its contact shade (an A/B switch for measurements). Read when a
## stand-in is made: change it, then release() and paint() again.
static var enabled := true


## The contact pass for the decor stand-in `stand_in`: the contact shader with every uniform the
## two share (the leaf texture, the cutout threshold, the wind's) copied from it. Pure apart from
## loading the shader.
static func make(stand_in: ShaderMaterial) -> ShaderMaterial:
	var contact := ShaderMaterial.new()
	contact.shader = load(SHADER) as Shader
	contact.set_meta(META, true)
	for entry: Dictionary in contact.shader.get_shader_uniform_list():
		var uniform_name := StringName(entry.get("name", ""))
		var value: Variant = stand_in.get_shader_parameter(uniform_name)
		if value != null:
			contact.set_shader_parameter(uniform_name, value)
	return contact


## Hangs the contact pass on `stand_in` (a wall-leaf stand-in) unless the switch is off or it has a
## next pass already (its own contact pass, returned; another pass, kept: null). Returns the pass,
## or null when none hangs there.
static func attach(stand_in: ShaderMaterial) -> ShaderMaterial:
	if not enabled or stand_in == null:
		return null
	if stand_in.next_pass != null:
		return stand_in.next_pass as ShaderMaterial if stand_in.next_pass.has_meta(META) else null
	var contact := make(stand_in)
	stand_in.next_pass = contact
	return contact
