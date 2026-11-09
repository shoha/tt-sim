extends SceneTree

## Runs the game's boot N times with the boot trace on and prints the median and range of every
## mark (perf audit boot, 2026-11-09). The trace itself is utils/boot_trace.gd; each child run
## appends one line to user://boot_trace.jsonl, and this reads back the lines its rounds wrote.
##
##   godot --headless --path <project> --script res://tools/boot_rounds.gd -- --rounds=5
##   godot --headless --path <project> --script res://tools/boot_rounds.gd -- --pack=<game.pck>
##   ... -- --pack=<before.pck> --pack_b=<after.pck>   (alternated, reported apart)
##   ... -- --window   (a real 1920x1080 window)
## Timing runs take the Godot lane first.
##
## A pack run uses this same binary with --main-pack; export one with
##   godot --headless --path <project> --export-pack "Windows Desktop" <dir>/ttsim.pck
## and copy addons/godotsteam/win64 and native/bin beside it (the GDExtension DLLs are not in the
## pack; without them network_manager fails to compile and the run is invalid). The pack's user
## folder is the project's, so a worktree with its own user folder keeps the runs apart.

const LOG_PATH := "user://boot_trace.jsonl"


func _initialize() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	var rounds := int(args.get("rounds", "5"))
	# `--pack_b=<other.pck>` alternates the two packs round by round (A B A B ...), so a machine
	# that gets busier during the run shifts both alike: the in-run A/B of docs/PERFORMANCE.md.
	# `--args=a,b` adds trace flags to every run (e.g. --boot-trace-map); `--args_b=c` alternates
	# a second set of flags with the same pack when there is no --pack_b.
	var packs: Array[String] = [String(args.get("pack", ""))]
	var extras: Array[String] = [String(args.get("args", ""))]
	if args.has("pack_b") or args.has("args_b"):
		packs.append(String(args.get("pack_b", packs[0])))
		extras.append(String(args.get("args_b", extras[0])))
	var lines_by_pack: Array[Array] = [[], []]
	for i in rounds * packs.size():
		var which := i % packs.size()
		var cmd := _command(args, packs[which])
		for flag in extras[which].split(",", false):
			cmd.append(flag)
		if i < packs.size():
			print("boot_rounds: %s %s" % [OS.get_executable_path(), " ".join(cmd)])
		var before := _lines().size()
		var t0 := Time.get_ticks_msec()
		var code := OS.execute(OS.get_executable_path(), cmd)
		print("boot_rounds: round %d (%s) exit %d, %d ms wall" % [
			i / packs.size() + 1, "AB"[which], code, Time.get_ticks_msec() - t0])
		lines_by_pack[which].append_array(_lines().slice(before))
	for which in packs.size():
		print("boot_rounds: == %s %s %s" % ["AB"[which], packs[which], extras[which]])
		_report(lines_by_pack[which])
	quit(0)


func _command(args: Dictionary, pack: String) -> PackedStringArray:
	var cmd: PackedStringArray = []
	if not args.has("window"):
		cmd.append("--headless")
	else:
		cmd.append_array(["--windowed", "--resolution", "1920x1080", "--position", "320,120"])
	if not pack.is_empty():
		cmd.append_array(["--path", pack.get_base_dir(), "--main-pack", pack])
	else:
		cmd.append_array(["--path", ProjectSettings.globalize_path("res://")])
	cmd.append_array(["--", "--boot-trace", "--boot-trace-quit"])
	return cmd


func _lines() -> Array:
	var out: Array = []
	if not FileAccess.file_exists(LOG_PATH):
		return out
	for line in FileAccess.get_file_as_string(LOG_PATH).split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			out.append(parsed)
	return out


func _report(runs: Array) -> void:
	if runs.is_empty():
		print("boot_rounds: no trace lines were written")
		return
	var labels: Array[String] = []
	var values: Dictionary = {}
	var worst: Array[float] = []
	for run: Dictionary in runs:
		worst.append(float(run.get("worst_frame_ms", 0.0)))
		# Spans the trace measured itself (first_map_ms, second_map_ms) are summarised as marks.
		for key: String in run:
			if key.ends_with("_ms") and key != "worst_frame_ms":
				run["marks"].append({"label": "span " + key, "ms": run[key]})
		for mark: Dictionary in run["marks"]:
			var label := String(mark["label"])
			if not values.has(label):
				labels.append(label)
				values[label] = []
			values[label].append(float(mark["ms"]))
	print("boot_rounds: %d runs (pack %s, %s)" % [runs.size(), runs[0]["pack"], runs[0]["display"]])
	for label in labels:
		var v: Array = values[label]
		v.sort()
		print("boot_rounds: %-44s median %8.1f  range %8.1f - %8.1f  (n %d)" % [
			label, _median(v), v[0], v[-1], v.size()])
	worst.sort()
	print(
		"boot_rounds: worst frame after the title: median %.1f, max %.1f" % [_median(worst), worst[-1]]
	)


func _median(v: Array) -> float:
	var n := v.size()
	return float(v[n / 2]) if n % 2 == 1 else (float(v[n / 2 - 1]) + float(v[n / 2])) / 2.0
