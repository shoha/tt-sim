extends RefCounted

## Render-job probe (`call` op) for the Sculpt tool (phase 3, P3-5): the ground height of
## the open authoring map along a line, read from the document on the terrain's triangles
## (AuthoringEditor.ground_height_at), so a look pass can check a stroke numerically (a tier
## top exactly on k * tier_height_m, a face's width, a ramp's slope, a pit's floor).
## Fields: `from`, `to` ([x, z] world metres), `n` (points, default 21). Returns
## "profile (x, z) -> (x, z): h0 h1 ..." with heights in metres, plus the steepest slope
## between neighbouring points in degrees.


static func run(root: Node, step: Dictionary) -> String:
	var ctrl := root.get("_authoring_controller") as AuthoringController
	if ctrl == null or ctrl.editor == null:
		return "no authoring map"
	var from := _vec(step.get("from"), Vector2.ZERO)
	var to := _vec(step.get("to"), Vector2(1, 0))
	var n := maxi(2, int(step.get("n", 21)))
	var heights := PackedStringArray()
	var last := NAN
	var steepest := 0.0
	var spacing := from.distance_to(to) / float(n - 1)
	for i in n:
		var p := from.lerp(to, float(i) / float(n - 1))
		var h := ctrl.editor.ground_height_at(Vector3(p.x, 0.0, p.y))
		heights.append("%.3f" % h)
		if not is_nan(last) and spacing > 0.0:
			steepest = maxf(steepest, rad_to_deg(atan(absf(h - last) / spacing)))
		last = h
	return (
		"profile %s -> %s: %s | steepest %.0f deg over %.2f m"
		% [from, to, " ".join(heights), steepest, spacing]
	)


static func _vec(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback
