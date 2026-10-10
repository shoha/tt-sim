extends SceneTree

## Writes tests/ui_bypass_baseline.json, the theme-bypass ratchet's baseline
## (bypass_audit.gd). Run it after a migration lowered counts:
##   godot --headless --path D:/dev/tt-sim --script res://tools/ui_audit/bypass_baseline.gd
## It only lowers: each entry becomes the smaller of its baseline and today's count, and
## files at zero drop out. A count above its baseline is printed and left as it was; a rise
## is a decision for a person (edit the JSON by hand, with the reason in the commit message).
## With `-- --init`, or when there is no baseline yet, it writes today's counts as they are.

const Audit := preload("res://tools/ui_audit/bypass_audit.gd")


func _initialize() -> void:
	var current := Audit.scan()
	var init := (
		OS.get_cmdline_user_args().has("--init")
		or not FileAccess.file_exists(Audit.BASELINE_PATH)
	)
	var files := current
	if not init:
		var baseline := Audit.load_baseline()
		for line in Audit.rises(current, baseline):
			print("not raised: " + line)
		files = Audit.lowered(current, baseline)
	var out := FileAccess.open(Audit.BASELINE_PATH, FileAccess.WRITE)
	if out == null:
		print("could not write %s" % Audit.BASELINE_PATH)
		quit(1)
		return
	out.store_string(Audit.to_json(files))
	out.close()
	print("%s %s: %s" % ["wrote" if init else "lowered", Audit.BASELINE_PATH, Audit.totals(files)])
	quit()
