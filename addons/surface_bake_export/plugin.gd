@tool
extends EditorPlugin

## Adds the official libraries' compressed surface maps to every export (card exportbake): see
## surface_ship.gd. Editor only; the presets exclude this folder from the pack.

const Ship := preload("res://addons/surface_bake_export/surface_ship.gd")

var _exporter: EditorExportPlugin = null


func _enter_tree() -> void:
	_exporter = Exporter.new()
	add_export_plugin(_exporter)


func _exit_tree() -> void:
	if _exporter != null:
		remove_export_plugin(_exporter)
	_exporter = null


## Bakes (or takes from the editor's cache) each map Ship.entries() lists and adds it to the pack.
class Exporter:
	extends EditorExportPlugin

	func _get_name() -> String:
		return "SurfaceBakeExport"

	func _export_begin(
		_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int
	) -> void:
		var started := Time.get_ticks_msec()
		var added := 0
		var total := 0
		var failed := PackedStringArray()
		for entry in Ship.entries():
			var data := Ship.bytes_for(entry)
			if data.is_empty():
				failed.append(String(entry["file"]))
				continue
			add_file(String(entry["path"]), data, false)
			added += 1
			total += data.size()
		print(
			(
				"SurfaceBakeExport: %d maps, %.1f MB, in %d ms"
				% [added, total / 1048576.0, Time.get_ticks_msec() - started]
			)
		)
		if not failed.is_empty():
			push_error(
				"SurfaceBakeExport: %d maps not baked, the game will draw them uncompressed: %s"
				% [failed.size(), ", ".join(failed)]
			)
