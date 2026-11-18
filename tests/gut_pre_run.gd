extends GutHookScript

## GUT's pre-run hook, named by every tests/.gutconfig*.json beside the post-run one. GUT has no
## per-script hook, but its `start_script` signal fires before each script's instance is made (and
## before its before_all), and this hook, which GUT runs once before the first script, connects to
## it. Each script therefore starts from the fresh painter state (PainterStateReset.classic) no
## matter which scripts ran before it in the process: shard count, order and a leaking test do not
## matter, and a script written tomorrow is covered without being touched. When the state was not
## fresh at a script's start, the previous script leaked it: a line says which items, so the leak
## can be fixed at its source (the reset is a safety net, not a licence to leak).


func run() -> void:
	PainterStateReset.classic()
	gut.start_script.connect(_on_start_script)


func _on_start_script(script) -> void:
	var leaked := PainterStateReset.dirty()
	if not leaked.is_empty():
		# print, not gut.logger.info: GUT's own info lines are off at the runs' log level.
		print(
			"[gut_pre_run] painter state left by the script before %s: %s"
			% [script.get_filename_and_inner(), ", ".join(leaked)]
		)
	PainterStateReset.classic()
