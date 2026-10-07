class_name AvatarBuilderFraming
extends RefCounted

## Framing for the avatar builder's preview (AvatarBuilderPreview). A built figure's skinned
## meshes keep their rest-pose bounds whatever the stance, so the posed figure is measured
## from its skeleton instead: every bone's posed origin (AvatarKit.posed_global, from the pose
## the kit left on the skeleton) gives the figure's height and its reach from the turntable's
## axis, and the head and hair parts' rest bounds, carried by the Head bone's posed
## transform, give the top of the head and the box the Face pane zooms to. A stance change
## costs one walk of the bones.
##
## fit() then sizes an orthographic view so the figure, turning about its axis, stays whole:
## a cylinder of the figure's reach from its soles to its crown, seen from `pitch` above the
## horizon, is (top - bottom) * cos(pitch) + 2 * reach * sin(pitch) tall on screen and
## 2 * reach wide.

## Flesh and cloth round the bones, sideways and above the crown, in metres.
const REACH_PAD_M := 0.1
const TOP_PAD_M := 0.02
## Air round the fitted figure, as a share of the view on each side.
const MARGIN := 0.05
## How far below the crown's middle the portrait centres, as a share of the view.
const FACE_DROP := 0.05
## Slots whose parts ride the Head bone.
const HEAD_SLOTS := ["head", "hair"]
const HEAD_BONE := "Head"


## The posed `figure`'s extent in its own space: {"bottom", "top" (metres), "reach" (the
## farthest bone from the vertical axis), "head" (AABB of the head part), "crown" (AABB of
## the head and hair parts)}. Empty for a figure without a skeleton.
static func measure(figure: Node3D) -> Dictionary:
	var sk := figure.get_node_or_null("Skeleton3D") as Skeleton3D if figure != null else null
	if sk == null:
		return {}
	var pose: Dictionary = sk.get_meta("avatar_pose", {})
	var offsets: Dictionary = sk.get_meta("avatar_offsets", {})
	var globals := {}
	var bottom := 0.0
	var top := 0.0
	var reach := 0.0
	for b in sk.get_bone_count():
		var p := AvatarKit.posed_global(sk, b, pose, offsets, globals).origin
		bottom = minf(bottom, p.y)
		top = maxf(top, p.y)
		reach = maxf(reach, Vector2(p.x, p.z).length())
	var head := AABB()
	var crown := AABB()
	var head_bone := sk.find_bone(HEAD_BONE)
	var parts: Dictionary = (figure.get_meta("avatar_recipe", {}) as Dictionary).get("parts", {})
	if head_bone >= 0:
		var bone_pose := AvatarKit.posed_global(sk, head_bone, pose, offsets, globals)
		for slot in HEAD_SLOTS:
			var mi := sk.get_node_or_null(String(parts.get(slot, ""))) as MeshInstance3D
			var box := _posed_box(mi, bone_pose)
			if not box.has_volume():
				continue
			crown = box if not crown.has_volume() else crown.merge(box)
			if slot == "head":
				head = box
	if crown.has_volume():
		top = maxf(top, crown.end.y)
		for i in 8:
			var corner := crown.get_endpoint(i)
			reach = maxf(reach, Vector2(corner.x, corner.z).length() - REACH_PAD_M)
	if not head.has_volume():
		head = crown
	return {"bottom": bottom, "top": top, "reach": reach, "head": head, "crown": crown}


## A part's rest bounds carried by the Head bone's posed transform (its bind pose for that
## bone, then the pose); an empty AABB when the part is missing or not bound to the head.
static func _posed_box(mi: MeshInstance3D, bone_pose: Transform3D) -> AABB:
	if mi == null or mi.mesh == null or mi.skin == null:
		return AABB()
	for i in mi.skin.get_bind_count():
		if String(mi.skin.get_bind_name(i)) == HEAD_BONE:
			return bone_pose * mi.skin.get_bind_pose(i) * mi.mesh.get_aabb()
	return AABB()


## The orthographic view that keeps the measured figure whole while it turns, from `pitch_rad`
## above the horizon in a view `aspect` (width / height) wide: Vector2(view height, focus
## height above the soles).
static func fit(bounds: Dictionary, pitch_rad: float, aspect: float) -> Vector2:
	if bounds.is_empty():
		return Vector2(2.25, 0.95)
	var bottom := float(bounds.bottom)
	var top := float(bounds.top) + TOP_PAD_M
	var reach := float(bounds.reach) + REACH_PAD_M
	var tall := (top - bottom) * cos(pitch_rad) + 2.0 * reach * sin(pitch_rad)
	var wide := 2.0 * reach / maxf(aspect, 0.1)
	return Vector2(maxf(tall, wide) / (1.0 - 2.0 * MARGIN), (top + bottom) * 0.5)


## The portrait of the head: {"size" (view height), "focus" (figure space)} with the head
## and hair `crown_share` of the view's height (or of its width, in a view `aspect` wide,
## for wide hair), centred a little below the crown's middle so a hair bun keeps its air
## above and the chin its air below. Empty without a head.
static func face_view(bounds: Dictionary, crown_share: float, aspect: float) -> Dictionary:
	var crown: AABB = bounds.get("crown", AABB())
	if not crown.has_volume():
		return {}
	var wide := maxf(crown.size.x, crown.size.z) / maxf(aspect, 0.1)
	var size := maxf(crown.size.y, wide) / clampf(crown_share, 0.1, 1.0)
	return {"size": size, "focus": crown.get_center() - Vector3(0.0, size * FACE_DROP, 0.0)}
