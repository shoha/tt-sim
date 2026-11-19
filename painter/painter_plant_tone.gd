class_name PainterPlantTone
extends RefCounted

## Tones a plant stand-in (the ShaderMaterial PainterSurfaces.stand_in_of makes): its ramp, accents
## and numbers from the sheet for one mood and sun elevation. Pure statics, split out of
## PainterSurfaces to keep it under the file cap; the scatter's species, the village's baked decor
## (PainterVillage) and a GLB map's props and plants (PainterGlbMap) all tone through it.


## Sets a stand-in's ramp, accents and numbers for `entry` (PainterPlantRoles.of()).
static func tone(
	material: ShaderMaterial, entry: Dictionary, sheet: Dictionary, mood: String, elevation: float
) -> void:
	var low := int(entry["kind"]) in [PainterPlantRoles.KIND_GRASS, PainterPlantRoles.KIND_FLOWER]
	# Logs and stumps shade like the painted stems, to their own brown (painter-trees-polish: the
	# mood's full violet pull read maroon on a log's shaded side at a lower sun).
	var wood := str(entry["role"]) in ["bark", PainterPlantRoles.CHARCOAL_ROLE]
	var prefix := "grass-" if low else ("bark-" if wood else "")
	var tone_role := str(entry["role"])
	var derived := Vector3(-1.0, 0.0, 0.0)
	if PainterGroundRoles.DERIVED.has(tone_role):
		derived = PainterGroundRoles.derived(sheet, mood, tone_role, elevation)
		tone_role = str(PainterGroundRoles.DERIVED[tone_role][0])
	var colors := PainterTones.ramp(sheet, mood, tone_role, elevation, prefix, derived)
	if int(entry["kind"]) == PainterPlantRoles.KIND_CROWN:
		# A bush takes the crowns' ramp (painter-trees-polish2).
		var tones := load(PainterPlantRoles.CROWN_TONES) as GDScript
		colors.assign(tones.call("bush_ramp", sheet, mood, elevation))
	var ramp := PainterTones.linear_ramp(colors)
	var names := [&"c_shade0", &"c_mid0", &"c_lit0", &"c_shade1", &"c_mid1", &"c_lit1"]
	for i in names.size():
		material.set_shader_parameter(names[i], ramp[i])
	var accents := PackedVector3Array()
	for role in ["flower-gold", "flower-rose", "flower-violet", "flower-white"]:
		accents.append(PainterTones.linear(PainterSheet.tone(sheet, mood, role, elevation)))
	material.set_shader_parameter(&"accent", accents)
	material.set_shader_parameter(
		&"tone_lo", PainterSheet.number(sheet, mood, "tone-lo", elevation)
	)
	material.set_shader_parameter(
		&"tone_hi", PainterSheet.number(sheet, mood, "tone-hi", elevation)
	)
	material.set_shader_parameter(
		&"group_freq", PainterSheet.number(sheet, mood, "flower-mix", elevation)
	)
	var keep := 1.0
	var freq := 0.2
	match int(entry["kind"]):
		PainterPlantRoles.KIND_GRASS:
			keep = PainterSheet.number(sheet, mood, "keep-grass", elevation)
			freq = PainterSheet.number(sheet, mood, "keep-freq-grass", elevation)
		PainterPlantRoles.KIND_FLOWER:
			keep = PainterSheet.number(sheet, mood, "keep-flower", elevation)
			freq = PainterSheet.number(sheet, mood, "keep-freq-flower", elevation)
	material.set_shader_parameter(&"keep", keep)
	material.set_shader_parameter(&"keep_freq", freq)
	# Snow on the plants when the crowns take it (winter), in the snow's own colours (the drift
	# role on the ground's ramp), so a tuft's cap is the snow round its foot.
	var snow := PainterTones.ramp(sheet, mood, "drift", elevation, "ground-")
	material.set_shader_parameter(
		&"frost", PainterSheet.number(sheet, mood, "crown-deposit", elevation)
	)
	material.set_shader_parameter(&"c_frost_lit", PainterTones.linear(snow[2]))
	material.set_shader_parameter(&"c_frost_shd", PainterTones.linear(snow[0]))
