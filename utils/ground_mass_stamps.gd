class_name GroundMassStamps
extends RefCounted

## The ground under each grass mass (ground ship card 3b, ground look `mass.shade` and
## `mass.lift`; round 20's probe `_mass_shade`): a soft shade on the mass's sun-away side and a
## faint underpaint lift on its sunward side, stamped into the look's bake (GroundLookBake) so
## they cost nothing per frame.
##
## The masses come from the anchored grass instances (MultiMesh custom data .w = 1, .yz the
## offset to the mass anchor: ScatterMass), grouped by anchor; each is an ellipse of two standard
## deviations of its tufts. The shade is a radial soft ellipse of the mass's own shape,
## shade_size times its size, pushed shade_push of its extent away from the sun (so the anchor,
## where the mass's tufts read their colour, stays out of it), multiplying the baked texel by
## down to 1 - shade at its centre (the bake holds square roots: sqrt(1 - shade) per channel).
## The lift is an additive soft ellipse lift_size times the mass, pushed lift_push toward the
## sun, adding `lift` to the square-rooted texel at its centre.

const SHADE_NODE := "MassShade"
const LIFT_NODE := "MassLift"
## A group of fewer tufts is not a mass.
const MIN_TUFTS := 6
## Anchors are grouped on a grid this fine (1 / metres).
const ANCHOR_GRID := 20.0
const GRADIENT_PX := 64

## The stamps' materials, one per blend mode, kept for the life of the app. A CanvasItemMaterial
## shares one shader per blend mode only while a material of it lives, so making them anew on
## every restamp compiled two canvas pipelines each time: one 19 ms frame per brush stroke
## (docs/PERFORMANCE.md "Ground look and grass masses").
static var _materials: Dictionary = {}


## Per mass anchor the moments of its tufts' world XZ positions (count, sum x, sum z, sum xx,
## sum zz, sum xz), from every anchored MultiMesh under `root`.
static func collect(root: Node) -> Dictionary:
	var sums := {}
	if root == null:
		return sums
	for node in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm == null or mm.mesh == null or not mm.use_custom_data:
			continue
		var xf := mmi.global_transform
		for i in mm.instance_count:
			var cd := mm.get_instance_custom_data(i)
			if cd.a < 0.5:
				continue
			var o := mm.get_instance_transform(i).origin
			var w := xf * o
			var a := xf * Vector3(o.x + cd.g, o.y, o.z + cd.b)
			var key := Vector2i(roundi(a.x * ANCHOR_GRID), roundi(a.z * ANCHOR_GRID))
			var s: PackedFloat64Array = sums.get(key, PackedFloat64Array([0, 0, 0, 0, 0, 0]))
			s[0] += 1.0
			s[1] += w.x
			s[2] += w.z
			s[3] += w.x * w.x
			s[4] += w.z * w.z
			s[5] += w.x * w.z
			sums[key] = s
	return sums


## Replaces the stamps in bake viewport `vp` (rect `rect_m`, `px` texels) with those of `sums`
## (collect()) under `mass` (a merged look's mass group), toward sun direction `sun` (unit world
## XZ). Returns how many masses were drawn.
static func draw(
	vp: SubViewport, sums: Dictionary, rect_m: Vector4, px: Vector2i, mass: Dictionary, sun: Vector2
) -> int:
	var strength := clampf(float(mass.shade), 0.0, 0.9)
	var lift_amount := clampf(float(mass.lift), 0.0, 0.2)
	var shade := _stamp_node(vp, SHADE_NODE, CanvasItemMaterial.BLEND_MODE_MUL, strength)
	var lift := _stamp_node(vp, LIFT_NODE, CanvasItemMaterial.BLEND_MODE_ADD, -1.0)
	var ci := shade.get_canvas_item()
	var lift_ci := lift.get_canvas_item()
	RenderingServer.canvas_item_clear(ci)
	RenderingServer.canvas_item_clear(lift_ci)
	shade.set_meta("masses", 0)
	if (strength <= 0.0 and lift_amount <= 0.0) or sums.is_empty():
		return 0
	var size := float(mass.shade_size)
	var push := float(mass.shade_push)
	var lift_size := float(mass.lift_size)
	var lift_push := float(mass.lift_push)
	var tex_rid: RID = (shade.get_meta("texture") as Texture2D).get_rid()
	var lift_rid: RID = (lift.get_meta("texture") as Texture2D).get_rid()
	var per_m := Vector2(px.x / rect_m.z, px.y / rect_m.w)
	var origin := Vector2(rect_m.x, rect_m.y)
	var drawn := 0
	for key in sums:
		var s: PackedFloat64Array = sums[key]
		if s[0] < MIN_TUFTS:
			continue
		var c := Vector2(s[1], s[2]) / s[0]
		var cxx := s[3] / s[0] - c.x * c.x
		var czz := s[4] / s[0] - c.y * c.y
		var cxz := s[5] / s[0] - c.x * c.y
		var angle := 0.5 * atan2(2.0 * cxz, cxx - czz)
		var mid := 0.5 * (cxx + czz)
		var spread := sqrt(maxf(0.25 * (cxx - czz) * (cxx - czz) + cxz * cxz, 0.0))
		var axes := Vector2(
			2.0 * sqrt(maxf(mid + spread, 1e-4)), 2.0 * sqrt(maxf(mid - spread, 1e-4))
		)
		# The mass's extent toward the sun: its ellipse's support along `sun`.
		var u := Vector2(cos(angle), sin(angle))
		var reach := sqrt(
			pow(axes.x * u.dot(sun), 2.0) + pow(axes.y * u.orthogonal().dot(sun), 2.0)
		)
		if strength > 0.0:
			var at := (c - sun * reach * push - origin) * per_m
			RenderingServer.canvas_item_add_set_transform(
				ci, Transform2D(angle, axes * size * per_m, 0.0, at)
			)
			RenderingServer.canvas_item_add_texture_rect(
				ci, Rect2(-1.0, -1.0, 2.0, 2.0), tex_rid, false, Color(1, 1, 1, 1)
			)
		if lift_amount > 0.0:
			var lift_at := (c + sun * reach * lift_push - origin) * per_m
			RenderingServer.canvas_item_add_set_transform(
				lift_ci, Transform2D(angle, axes * lift_size * per_m, 0.0, lift_at)
			)
			RenderingServer.canvas_item_add_texture_rect(
				lift_ci, Rect2(-1.0, -1.0, 2.0, 2.0), lift_rid, false, Color(1, 1, 1, lift_amount)
			)
		drawn += 1
	shade.set_meta("masses", drawn)
	return drawn


## The Node2D child of `vp` named `node_name`, drawing with `blend`, holding a radial texture (as
## meta "texture", so it lives as long as the node): the shade's for `strength`, the lift's when
## `strength` is negative, re-made only when that changes. The node is made on the slot's first
## stamp and kept: a restamp only clears and refills its canvas item. A restamp that freed the
## nodes and added new ones drew none of its masses in the bake's next render every other time
## (on fresh and reopened maps alike; a re-render showed them, and new textures on kept nodes did
## not do it), so the first brush dab on a reopened level dropped every mass's shade and lift
## (docs/systems/authored_terrain.md "Ground look").
static func _stamp_node(
	vp: SubViewport, node_name: String, blend: CanvasItemMaterial.BlendMode, strength: float
) -> Node2D:
	var node := vp.get_node_or_null(node_name) as Node2D
	if node == null:
		node = Node2D.new()
		node.name = node_name
		node.material = material(blend)
		vp.add_child(node)
	if node.get_meta("strength", NAN) == strength:
		return node
	var tex := GradientTexture2D.new()
	tex.gradient = _lift_gradient() if strength < 0.0 else _shade_gradient(strength)
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = GRADIENT_PX
	tex.height = GRADIENT_PX
	node.set_meta("texture", tex)
	node.set_meta("strength", strength)
	return node


## The shade's falloff: the texel multiplied by sqrt(1 - strength) at the centre, 1 at the rim.
static func _shade_gradient(strength: float) -> Gradient:
	var k := sqrt(1.0 - strength)
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(k, k, k, k))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(1, 1, 1, 1))
	var k_mid := lerpf(k, 1.0, 0.25)
	gradient.add_point(0.45, Color(k_mid, k_mid, k_mid, k_mid))
	return gradient


## The lift's falloff: full at the centre, none at the rim (its amount is the draw's alpha).
static func _lift_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.55, Color(1, 1, 1, 0.75))
	return gradient


## The stamps' shared material drawing with `blend` (made on first use, then kept).
static func material(blend: CanvasItemMaterial.BlendMode) -> CanvasItemMaterial:
	if not _materials.has(blend):
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = blend
		_materials[blend] = mat
	return _materials[blend]
