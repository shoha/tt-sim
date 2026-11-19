class_name PainterStateReset
extends RefCounted

## Puts every piece of painter-related process-wide state back to what a fresh process holds (cards
## painter-default-flip and painter-test-reset). Painted is the default look, so any script that
## applies a level environment without clearing it leaves the two shared water materials on the
## painter's shaders, a painted ground in FireLook.glow_mirrors and the painted flags of the fire
## variants and the token ghost set; which scripts ran before another depends on the shard count
## (CI runs 2 shards, the local gate 8) and on the order. The guarantee is structural: the GUT
## pre-run hook (tests/gut_pre_run.gd, named by every tests/.gutconfig*.json) calls classic() before
## every test script, so a new or reordered script starts from the fresh state whatever ran before
## it. A test that wants Painted sets it itself; one that wants Classic needs nothing.
##
## The inventory (what a test can leave behind that the painter reads or writes), each with its
## fresh value:
##   - the shared water and fall materials (WaterGlbUtils.water_material and
##     AuthoredWater.fall_material): the Classic shaders, none of PainterWater's marks and none of
##     its tone uniforms;
##   - FireLook.glow_mirrors (a painted ground mirrors the fire bake): empty;
##   - FireVariants.painted and TokenGhost.painted (set by LevelEnvironmentManager): false;
##   - TokenToon.painted (the Settings token shading): TokenToon.DEFAULT_PAINTED;
##   - RenderStyle.choice (the Settings look): RenderStyle.DEFAULT_CHOICE;
##   - FoliageLight.last_sun (the published sun every light gate reads): LAST_SUN_FRESH;
##   - FoliageDensityController.fraction (the ground-cover thinning a zoomed-out level camera sets,
##     found by the reverse 2-shard run: test_authored_scatter saw 14 of 20 drawn): 1.0;
##   - the painter's A/B flags (PainterBuildings, PainterVillage, PainterMannerHost,
##     PainterMannerSnow, PainterMannerBlanket, PainterTreeBush): their declared defaults;
##   - PainterSheet's parsed-sheet cache: emptied;
##   - SunShadowQuality's last tier (it skips a set to the same tier, which would race the warm-up):
##     forgotten, so it reads the project setting again.
## Not here: PainterWarmup (a no-op while headless, `available()`), PainterSurfaces and
## PainterScene (instances a level environment manager owns, freed with it), RenderingServer's
## global shader parameters (no test reads them back) and the settings statics a test pins and
## restores itself (ShadowCascades.current and the like).

const CLASSIC_WATER := "res://shaders/water.gdshader"
const CLASSIC_FALL := "res://shaders/waterfall.gdshader"
## FoliageLight.last_sun in a process that has published no sun.
const LAST_SUN_FRESH := Vector4(0.0, 1.0, 0.0, 1.0)


## Every item of the inventory back to its fresh value. Idempotent and cheap (a few property
## writes; the two materials are made on first use, as any test that reads them would).
static func classic() -> void:
	_restore(WaterGlbUtils.water_material(), load(CLASSIC_WATER) as Shader)
	_restore(AuthoredWater.fall_material(), load(CLASSIC_FALL) as Shader)
	FireLook.glow_mirrors.clear()
	FireVariants.painted = false
	TokenGhost.painted = false
	TokenToon.painted = TokenToon.DEFAULT_PAINTED
	RenderStyle.choice = RenderStyle.DEFAULT_CHOICE
	FoliageLight.last_sun = LAST_SUN_FRESH
	FoliageDensityController.fraction = 1.0
	PainterBuildings.hand_drawn = true
	PainterBuildings.paint_yard = true
	PainterVillage.furnishings = true
	PainterVillage.decor_plants = true
	PainterVillage.field_plants = true
	PainterIvyContact.enabled = true
	PainterMannerHost.snow_body = true
	PainterMannerHost.hand = true
	PainterMannerSnow.blanket = true
	PainterStreetSnow.bodied = true
	PainterMannerBlanket.step_s = PainterMannerBlanket.FIELD_STEP_S_M
	PainterTreeBush.clump_roots = PainterTreeBush.ROOTS_PAD
	PainterSheet.clear_cache()
	PainterFields.reset()
	PainterFields.enabled = true
	SunShadowQuality.reset()


## The items of the inventory that are not at their fresh value, by name (empty when the state is
## fresh). The pre-run hook logs it before it resets, so a script that leaks shows up in the run.
static func dirty() -> PackedStringArray:
	var out := PackedStringArray()
	_note(out, "water material", _material_dirty(WaterGlbUtils.water_material(), CLASSIC_WATER))
	_note(out, "fall material", _material_dirty(AuthoredWater.fall_material(), CLASSIC_FALL))
	_note(out, "FireLook.glow_mirrors", not FireLook.glow_mirrors.is_empty())
	_note(out, "FireVariants.painted", FireVariants.painted)
	_note(out, "TokenGhost.painted", TokenGhost.painted)
	_note(out, "TokenToon.painted", TokenToon.painted != TokenToon.DEFAULT_PAINTED)
	_note(out, "RenderStyle.choice", RenderStyle.choice != RenderStyle.DEFAULT_CHOICE)
	_note(out, "FoliageLight.last_sun", FoliageLight.last_sun != LAST_SUN_FRESH)
	_note(out, "FoliageDensityController.fraction", FoliageDensityController.fraction != 1.0)
	_note(
		out,
		"SunShadowQuality",
		SunShadowQuality.current() != int(ProjectSettings.get_setting(SunShadowQuality.SETTING))
	)
	_note(
		out,
		"painter A/B flags",
		(
			not (PainterBuildings.hand_drawn and PainterBuildings.paint_yard)
			or not (
				PainterVillage.furnishings
				and PainterVillage.decor_plants
				and PainterVillage.field_plants
				and PainterIvyContact.enabled
			)
				or not (PainterMannerHost.snow_body and PainterMannerHost.hand)
			or not PainterMannerSnow.blanket
			or not PainterStreetSnow.bodied
			or PainterMannerBlanket.step_s != PainterMannerBlanket.FIELD_STEP_S_M
			or PainterTreeBush.clump_roots != PainterTreeBush.ROOTS_PAD
			or not PainterFields.enabled
		)
	)
	return out


static func _note(out: PackedStringArray, name: String, is_dirty: bool) -> void:
	if is_dirty:
		out.append(name)


static func _material_dirty(material: ShaderMaterial, classic_path: String) -> bool:
	if material.shader == null or material.shader.resource_path != classic_path:
		return true
	if material.has_meta(PainterWater.META):
		return true
	for uniform in PainterWater.tone_uniforms():
		if material.get_shader_parameter(uniform) != null:
			return true
	return false


static func _restore(material: ShaderMaterial, classic_shader: Shader) -> void:
	material.shader = classic_shader
	material.remove_meta(PainterWater.META)
	for uniform in PainterWater.tone_uniforms():
		material.set_shader_parameter(uniform, null)
