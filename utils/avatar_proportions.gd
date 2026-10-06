class_name AvatarProportions
extends RefCounted

## Avatar proportions (docs/ASSET_PIPELINE.md section 10 "Skeleton"), a port of figurine's
## `proportions.py`: per-bone length and girth factors applied through a duplicated Skin's
## bind matrices, never through pose scale (Skeleton3D has no inherit-scale switch, so a
## scaled pose shears the children).
##
## A recipe sets each control (`height`, `build`, `head`) between 0 and 1; the kit's
## `proportions` block lists, per control, bones with a [low, high] range for their `length`
## and/or `girth`, and a `default`. The value maps linearly onto each range, a `Left` bone
## implies its `Right` mirror, and factors from several controls multiply. A helper bone
## (`helper: true` in the `skeleton` block) is in no control and takes its driver's factors.
##
## For bone b with rest head H_b, unit axis a_b (head to tail, from the kit's `skeleton`
## block), length factor f_b and girth factor g_b: R_b = f_b a a^T + g_b (I - a a^T). New
## heads chain from the root, H'_c = H'_p + R_p (H_c - H_p), then one vertical shift s puts
## the sole (the point under the left ankle at ground height, carried by LeftFoot's map) back
## on y = 0. Each bone maps a rest-pose point by M_b(v) = H'_b + s + R_b (v - H_b); the
## skeleton's rest origins move to H'_b + s with orientations unchanged, and each bind becomes
## inverse(Rest'_b) M_b Rest_b Bind_b, so the rest pose shows the reshaped figure and stances,
## which are local rotations, stay valid. All positions are in glTF / Skeleton3D space
## (+Y up), where figurine's shift along Blender Z is a shift along Y.


## The mirror of a Left / Right bone name; any other name is its own mirror.
static func mirror_name(bone: String) -> String:
	if bone.begins_with("Left"):
		return "Right" + bone.substr(4)
	if bone.begins_with("Right"):
		return "Left" + bone.substr(5)
	return bone


## Every control at a value in 0..1: the recipe's, clamped, or the control's default.
static func control_values(controls: Dictionary, values: Dictionary) -> Dictionary:
	var out := {}
	for control in controls:
		var spec: Dictionary = controls[control]
		out[control] = clampf(float(values.get(control, spec.get("default", 0.5))), 0.0, 1.0)
	return out


## [length, girth]: a factor per bone of `bones` (bone name -> anything) for control values.
static func bone_factors(controls: Dictionary, values: Dictionary, bones: Array) -> Array:
	var length := {}
	var girth := {}
	for bone in bones:
		length[bone] = 1.0
		girth[bone] = 1.0
	var resolved := control_values(controls, values)
	for control in controls:
		var spec: Dictionary = controls[control]
		var value: float = resolved[control]
		for kind in ["length", "girth"]:
			var table: Dictionary = length if kind == "length" else girth
			var ranges: Dictionary = spec.get(kind, {})
			for bone in ranges:
				var lo := float(ranges[bone][0])
				var hi := float(ranges[bone][1])
				var factor := lo + (hi - lo) * value
				var names := {String(bone): true, mirror_name(String(bone)): true}
				for name in names:
					if table.has(name):
						table[name] = float(table[name]) * factor
	return [length, girth]


static func _vec(value: Variant) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


## R = f a a^T + g (I - a a^T) for a unit axis a.
static func stretch(axis: Vector3, f: float, g: float) -> Basis:
	var a := axis.normalized()
	var outer := Basis(a * a.x, a * a.y, a * a.z)  # columns a * a_i: the outer product a a^T
	var rest := Basis.IDENTITY
	return Basis(
		outer.x * f + (rest.x - outer.x) * g,
		outer.y * f + (rest.y - outer.y) * g,
		outer.z * f + (rest.z - outer.z) * g,
	)


## Per bone {"head": H_b, "new_head": H'_b + s, "r": R_b} for the kit's `skeleton` block
## (bone -> {parent, head, tail}, glTF space) and `proportions` block at control `values`.
static func bone_maps(skeleton: Dictionary, controls: Dictionary, values: Dictionary) -> Dictionary:
	var names := skeleton.keys()
	var factors := bone_factors(controls, values, names)
	var length: Dictionary = factors[0]
	var girth: Dictionary = factors[1]
	# A helper bone takes its driver's factors (so its map is exactly its driver's).
	for name in names:
		var entry: Dictionary = skeleton[name]
		if bool(entry.get("helper", false)) and skeleton.has(String(entry.get("driver", ""))):
			length[name] = length[String(entry.driver)]
			girth[name] = girth[String(entry.driver)]
	var heads := {}
	var rmat := {}
	for name in names:
		var spec: Dictionary = skeleton[name]
		var head := _vec(spec["head"])
		heads[name] = head
		var axis := _vec(spec["tail"]) - head
		rmat[name] = stretch(axis, float(length[name]), float(girth[name]))
	var new_heads := {}
	for name in names:
		_chain(name, skeleton, heads, rmat, new_heads)
	var shift := Vector3.ZERO
	if heads.has("LeftFoot"):
		var ankle: Vector3 = heads["LeftFoot"]
		var sole := Vector3(ankle.x, 0.0, ankle.z)
		var sole_new: Vector3 = new_heads["LeftFoot"] + rmat["LeftFoot"] * (sole - ankle)
		shift = Vector3(0.0, -sole_new.y, 0.0)
	var out := {}
	for name in names:
		out[name] = {"head": heads[name], "new_head": new_heads[name] + shift, "r": rmat[name]}
	return out


static func _chain(
	name: String, skeleton: Dictionary, heads: Dictionary, rmat: Dictionary, out: Dictionary
) -> Vector3:
	if out.has(name):
		return out[name]
	var parent: Variant = skeleton[name].get("parent")
	if parent == null or not skeleton.has(String(parent)):
		out[name] = heads[name]
	else:
		var p := String(parent)
		var parent_new := _chain(p, skeleton, heads, rmat, out)
		out[name] = parent_new + (rmat[p] as Basis) * (heads[name] - heads[p])
	return out[name]


## The bone's map M_b as a transform: v -> H'_b + s + R_b (v - H_b).
static func bone_map_transform(entry: Dictionary) -> Transform3D:
	var r: Basis = entry["r"]
	var head: Vector3 = entry["head"]
	return Transform3D(r, entry["new_head"] - r * head)


## Moves `skeleton`'s rest origins to the maps' new heads (orientations unchanged) and resets
## its pose to the new rest. Bones the maps do not name keep their rest.
static func apply_rests(skeleton: Skeleton3D, maps: Dictionary) -> void:
	var globals := {}
	for b in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(b)
		var rest := skeleton.get_bone_global_rest(b)
		if maps.has(name):
			rest.origin = maps[name]["new_head"]
		globals[b] = rest
	for b in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(b)
		var global_rest: Transform3D = globals[b]
		var local := (
			global_rest
			if parent < 0
			else (globals[parent] as Transform3D).affine_inverse() * global_rest
		)
		skeleton.set_bone_rest(b, local)
	skeleton.reset_bone_poses()


## A copy of `skin` whose binds carry the maps, for a part bound to a skeleton whose rests
## `apply_rests` moved. `old_rests` holds each bone's global rest before the move (by name);
## `new_rests` after it. Bind names stay; a bind whose bone has no map is copied as is.
static func reshaped_skin(
	skin: Skin, maps: Dictionary, old_rests: Dictionary, new_rests: Dictionary
) -> Skin:
	var out := skin.duplicate() as Skin
	for i in out.get_bind_count():
		var name := String(out.get_bind_name(i))
		if not maps.has(name) or not old_rests.has(name) or not new_rests.has(name):
			continue
		var old_rest: Transform3D = old_rests[name]
		var new_rest: Transform3D = new_rests[name]
		var bind := skin.get_bind_pose(i)
		out.set_bind_pose(
			i, new_rest.affine_inverse() * bone_map_transform(maps[name]) * old_rest * bind
		)
	return out


## Global rests of every bone by name.
static func global_rests(skeleton: Skeleton3D) -> Dictionary:
	var out := {}
	for b in skeleton.get_bone_count():
		out[skeleton.get_bone_name(b)] = skeleton.get_bone_global_rest(b)
	return out
