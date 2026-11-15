extends SceneTree

## Draws the painted look's generated textures and saves them under res://painter/baked/
## (PainterBaked): run after a change to PainterBrushes, PainterTreeBrushes or PainterTuftAtlas.
##   godot --headless --path D:/dev/tabletop/tt-sim --script res://tools/bake_painter.gd


func _initialize() -> void:
	var written := PainterBaked.bake_all()
	if written.is_empty():
		printerr("bake_painter: saving failed")
		quit(1)
		return
	print("bake_painter: wrote %s" % ", ".join(written))
	quit(0)
