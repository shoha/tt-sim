class_name PainterPlantTone
extends RefCounted

## Tones a plant stand-in (the ShaderMaterial PainterSurfaces.stand_in_of makes): its ramp, accents
## and numbers from the sheet for one mood and sun elevation. Pure statics, split out of
## PainterSurfaces to keep it under the file cap; the scatter's species, the village's baked decor
## (PainterVillage) and a GLB map's props and plants (PainterGlbMap) all tone through it.


## The instance uniform that keeps a node's plants from the sheet's thinning (painter_plant).
const PLACED := &"painter_placed"
## The tone role of the ground's litter scatter (PainterPlantRoles: leaves, twigs, needles), thinned
## by the sheet's keep-litter.
const LITTER_ROLE := "litter"


## Marks every drawn node of the hand-placed props' layer (the scatter named
## MapSourceLoader.PROPS_NODE among `scatters`) so the painted plant shader never thins it: what an
## author places stands (painter-flowers). Classic's materials do not read the mark. Idempotent; run
## whenever the painted species are looked at, so cells built later are marked too.
static func mark_placed(scatters: Array) -> void:
	for scatter: Variant in scatters:
		if not is_instance_valid(scatter) or str(scatter.name) != MapSourceLoader.PROPS_NODE:
			continue
		for node in (scatter as Node).find_children("*", "GeometryInstance3D", true, false):
			var geometry := node as GeometryInstance3D
			if geometry.get_instance_shader_parameter(PLACED) == null:
				geometry.set_instance_shader_parameter(PLACED, 1.0)


## Sets the flower marks' numbers (painter_flower_marks.gdshaderinc: the sheet's flower-* numbers).
static func _tone_marks(
	material: ShaderMaterial, sheet: Dictionary, mood: String, elevation: float
) -> void:
	var number := func(prop: String) -> float:
		return PainterSheet.number(sheet, mood, prop, elevation)
	material.set_shader_parameter(&"fl_head", number.call("flower-head"))
	material.set_shader_parameter(&"fl_floor", number.call("flower-floor"))
	material.set_shader_parameter(
		&"fl_clump",
		Vector3(number.call("flower-thin"), number.call("flower-bud"), number.call("flower-own"))
	)
	material.set_shader_parameter(
		&"fl_far", Vector2(number.call("flower-far-lo"), number.call("flower-far-hi"))
	)


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
	# A village field's crop (PainterFields): the grass moved to the plant's own colour, so its rows
	# read as their crop; never thinned, and cut by its texture's blades, not the meadow's dabs.
	var crop := bool(entry.get("crop", false)) and int(entry["kind"]) == PainterPlantRoles.KIND_GRASS
	if crop:
		tone_role = "grass"
		derived = PainterFields.crop_lch(sheet, mood, elevation, entry.get("own", Vector3(-1, 0, 0)))
	material.set_shader_parameter(&"tuft_blades", crop)
	var colors := PainterTones.ramp(sheet, mood, tone_role, elevation, prefix, derived)
	if int(entry["kind"]) in [PainterPlantRoles.KIND_CROWN, PainterPlantRoles.KIND_WALL_LEAF]:
		# A bush takes the crowns' ramp (painter-trees-polish2), and so does a wall's ivy, so it
		# is the same green as the bushes at its foot (card painter-roofs-ivy).
		var tones := load(PainterPlantRoles.CROWN_TONES) as GDScript
		colors.assign(tones.call("bush_ramp", sheet, mood, elevation))
	var ramp := PainterTones.linear_ramp(colors)
	var names := [&"c_shade0", &"c_mid0", &"c_lit0", &"c_shade1", &"c_mid1", &"c_lit1"]
	for i in names.size():
		material.set_shader_parameter(names[i], ramp[i])
	var accents := PackedVector3Array()
	for role in PainterFlowerHue.ROLES:
		accents.append(PainterTones.linear(PainterSheet.tone(sheet, mood, role, elevation)))
	material.set_shader_parameter(&"accent", accents)
	# A flower's bloom (PainterFlowerHue.for_surface): its role, whether the surface is dabs, the
	# dab's box and the cards' centres (none: the cards stay as they are).
	material.set_shader_parameter(&"petal_role", int(entry.get("petal", -1)))
	material.set_shader_parameter(&"petal_dab", bool(entry.get("dab", false)))
	material.set_shader_parameter(&"dab_box", entry.get("dab_box", Vector4(0.5, 0.5, 0.5, 0.5)))
	material.set_shader_parameter(&"bloom_centres", entry.get("centres"))
	_tone_marks(material, sheet, mood, elevation)
	material.set_shader_parameter(
		&"tone_lo", PainterSheet.number(sheet, mood, "tone-lo", elevation)
	)
	material.set_shader_parameter(
		&"tone_hi", PainterSheet.number(sheet, mood, "tone-hi", elevation)
	)
	# A rock's shade (painter_solid): half way from the mood's full shade pull to the cliff stone's
	# share of it (the sheet's cliff-pull), so a boulder's shade side is one family with the cliff
	# it lies under and still leans to the mood's shade hue. Wood keeps its bark- ramp as it is.
	var cliff_pull := PainterSheet.number(sheet, mood, "cliff-pull", elevation)
	material.set_shader_parameter(&"solid_pull", 1.0 if wood else 0.5 * (1.0 + cliff_pull))
	# The frequency of the slow field that steps a drift of blooms lighter or darker.
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
	# Fallen leaves and twigs lie under the snow (card painter-winter-ground): winter keeps none.
	if str(entry["role"]) == LITTER_ROLE:
		keep = PainterSheet.number(sheet, mood, "keep-litter", elevation)
		freq = PainterSheet.number(sheet, mood, "keep-freq-grass", elevation)
	if bool(entry.get("crop", false)):
		keep = 1.0
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
