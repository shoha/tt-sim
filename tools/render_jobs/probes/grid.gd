extends RefCounted

## Render-job probe (`call` op). Reports the grid overlay's visibility and, with
## step.visible, sets it directly for a capture (bypassing GameMap's grid policy, which is
## fine for a throwaway render session and wrong anywhere else).


static func run(base: Node, step: Dictionary) -> String:
	var out := ""
	for node in base.get_tree().root.find_children("*GridOverlay*", "", true, false):
		if node is Node3D:
			out += "%s visible %s -> " % [node.name, str((node as Node3D).visible)]
			if step.has("visible"):
				(node as Node3D).visible = bool(step.visible)
			out += str((node as Node3D).visible) + " "
	return out if out != "" else "no grid overlay"
