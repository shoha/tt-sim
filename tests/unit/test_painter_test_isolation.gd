extends GutTest

## The guarantee that painter state does not leak between test scripts (card painter-test-reset):
## PainterStateReset names and restores every item, and the GUT pre-run hook runs it before each
## script. The second half is proven for real, not by reading the hook: a child GUT process runs
## fixtures/state_isolation/leaker.gd (which leaves the state painted) and then checker.gd (which
## assumes it fresh), once with the repo's pre-run hook, where it passes, and once without, where
## it must fail (else the leaker would prove nothing). A script written later is covered by the
## same hook, so it needs no change of its own.

const FIXTURES := "res://tests/fixtures/state_isolation/"
const PRE_RUN_HOOK := "res://tests/gut_pre_run.gd"
const POST_RUN_HOOK := "res://tests/gut_post_run.gd"
const SCRATCH := "user://painter_isolation_probe/"


func after_each() -> void:
	PainterStateReset.classic()


func test_classic_restores_every_item_it_names() -> void:
	WaterGlbUtils.water_material().shader = load("res://painter/shaders/painter_water.gdshader")
	AuthoredWater.fall_material().set_meta(PainterWater.META, true)
	FireLook.glow_mirrors.append(ShaderMaterial.new())
	FireVariants.painted = true
	TokenGhost.painted = true
	TokenToon.painted = not TokenToon.DEFAULT_PAINTED
	RenderStyle.choice = RenderStyle.CHOICE_CLASSIC
	FoliageLight.last_sun = Vector4(1.0, 0.0, 0.0, 0.3)
	FoliageDensityController.fraction = 0.5
	PainterMannerHost.hand = false
	PainterMannerBlanket.step_s = 9.0
	PainterTreeBush.clump_roots = 99
	SunShadowQuality.set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	var leaked := PainterStateReset.dirty()
	for item in [
		"water material",
		"fall material",
		"FireLook.glow_mirrors",
		"FireVariants.painted",
		"TokenGhost.painted",
		"TokenToon.painted",
		"RenderStyle.choice",
		"FoliageLight.last_sun",
		"FoliageDensityController.fraction",
		"SunShadowQuality",
		"painter A/B flags"
	]:
		assert_has(leaked, item, "dirty() names %s" % item)
	PainterStateReset.classic()
	assert_eq(PainterStateReset.dirty(), PackedStringArray(), "fresh after classic()")
	PainterStateReset.classic()
	assert_eq(PainterStateReset.dirty(), PackedStringArray(), "and again: idempotent")


func test_a_leaking_script_does_not_reach_the_next_one_with_the_hook() -> void:
	var run := _run_pair(true)
	assert_eq(run.code, 0, "leaker then checker passes with the pre-run hook:\n%s" % run.output)
	assert_true(run.output.contains("painter state left by the script before"), "the leak is named")


func test_the_same_pair_fails_without_the_hook() -> void:
	var run := _run_pair(false)
	assert_ne(run.code, 0, "without the hook the checker sees the leak:\n%s" % run.output)


## Runs leaker.gd then checker.gd in one child GUT process; {code, output}.
func _run_pair(with_hook: bool) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	var config := {
		"dirs": [],
		"tests": [FIXTURES + "leaker.gd", FIXTURES + "checker.gd"],
		"post_run_script": POST_RUN_HOOK,
		"log_level": 1,
		"should_exit": true,
		"should_exit_on_success": true,
	}
	if with_hook:
		config["pre_run_script"] = PRE_RUN_HOOK
	var path := SCRATCH + ("hook.json" if with_hook else "no_hook.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(config))
	file.close()
	var output := []
	var args := PackedStringArray(
		[
			"--headless",
			"--path",
			ProjectSettings.globalize_path("res://"),
			"--script",
			"res://addons/gut/gut_cmdln.gd",
			"--",
			"-gconfig=" + ProjectSettings.globalize_path(path),
		]
	)
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	return {"code": code, "output": "".join(output)}
