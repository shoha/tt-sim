extends "res://tests/gut_pre_run.gd"

## The pre-run hook of tests/.gutconfig_terra_on.json (phase 2's gate run with the terraforming core
## on; docs/systems/terraform.md "Tests"): the usual hook, and the project setting
## tt_sim/terrain/core set true for the run, so every test that leaves TerraCore.switch_override
## null (as after_each restores it) runs with the switch on. Not saved: the setting is set in memory
## only. The engine meta `gut_terra_on` marks the run (test_terra_session reads the setting's
## default off everywhere else).


func run() -> void:
	super.run()
	ProjectSettings.set_setting(TerraCore.SWITCH_SETTING, true)
	Engine.set_meta(&"gut_terra_on", true)
