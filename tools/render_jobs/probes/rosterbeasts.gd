extends RefCounted

## Render-job probe (`call` op) for the Beasts pack's idle animation (jobs/rosterbeasts_look.json).
## `action: "idle"` prints, for each board token with a rigged model, the animation tree's current
## state, its play position and the idle clip's length and loop mode, plus the sum of the
## skeleton's bone rotations (a pose fingerprint: it changes while the idle plays). Calling it
## twice a few seconds apart shows the clip advancing and, past the clip's length, wrapping.
## `only` limits it to the token of that name (the render log cuts a long line).


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	if String(step.get("action", "idle")) != "idle":
		return "unknown action"
	var out := PackedStringArray()
	for node in gm.get_tree().get_nodes_in_group(BoardToken.GROUP_NAME):
		var token := node as BoardToken
		if step.has("only") and token.token_name != String(step["only"]):
			continue
		var trees := token.find_children("*", "BoardTokenAnimationTree", true, false)
		if trees.is_empty():
			out.append("%s: no animation tree" % token.token_name)
			continue
		var tree := trees[0] as BoardTokenAnimationTree
		var playback := tree.tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		var idle := tree.anim_player.get_animation(BoardTokenAnimationTree.IDLE)
		var fingerprint := 0.0
		for skeleton: Skeleton3D in token.find_children("*", "Skeleton3D", true, false):
			for bone in skeleton.get_bone_count():
				var q := skeleton.get_bone_pose_rotation(bone)
				fingerprint += q.x + 2.0 * q.y + 3.0 * q.z + 4.0 * q.w
		out.append(
			(
				"%s: node=%s pos=%.2f len=%.2f loop=%d pose=%.3f"
				% [
					token.token_name,
					playback.get_current_node(),
					playback.get_current_play_position(),
					idle.length,
					idle.loop_mode,
					fingerprint
				]
			)
		)
	return "; ".join(out)
