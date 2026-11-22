class_name WaterCourseFit
extends RefCounted

## The course half of the water-conditioning spike (WaterConditioner has the levels): pure static
## functions that turn a drawn river line into a clean one without moving it further than a
## fraction of its own width, so the author still feels it as their gesture.
##
## condition(): drop points closer than MIN_POINT_GAP_M; Douglas-Peucker thin (eps
## DP_PER_HALF_WIDTH x the narrowest half-width); trim self-loops (keep the first pass); resample
## every FIT_STEP_M; one penalised-least-squares smoothing solve ((W + sum lambda_i d_i d_i^T) x =
## W y, d the second difference, a pentadiagonal Cholesky, ends pinned), with lambda raised x4 at
## bends tighter than MIN_BEND_PER_WIDTH channel widths (up to four re-solves) and every point
## finally held within MAX_DISP_PER_HALF_WIDTH x its half-width of where it was drawn; widths
## median-of-3 filtered and slope-limited (WIDTH_SLOPE m per m); resample every
## WaterEdit.RESAMPLE_M; last, the cap is enforced on the result itself, stations and the chords
## between them (hold_cap), so the stored course NEVER strays further than the cap from the drawn
## polyline, whatever the stages before moved (deviation() measures it). A line the smoothing
## would move less than the clean tolerance is
## returned unchanged bit for bit, so condition() of its own output is the identity in practice
## (measured in tests/unit/test_water_conditioner.gd).
##
## Cost. The cap checks (hold_cap(), max_excess(), deviation()) sample the result every few cm and
## ask for the nearest point of the DRAWN line, a few hundred pointer samples: measured against
## every drawn segment that was 0.5 M segment tests for a 90 m bent river and 188.6 ms of its
## release frame (card painter-river-release; a straight line, which the smoothing leaves alone,
## never reaches them). nearest_from() answers the same query bit for bit from the few segments
## near the point (an arc-length bound skips the rest), so the fit costs in proportion to the
## stroke's length.

const MIN_POINT_GAP_M := 0.1
const DP_PER_HALF_WIDTH := 0.15
const MAX_DISP_PER_HALF_WIDTH := 0.5
## Radius of curvature floor, in channel widths (04-input-conditioning 2.4: natural modal 2 to 3).
const MIN_BEND_PER_WIDTH := 1.5
const FIT_STEP_M := 0.5
## The smoothing length: lambda is (SMOOTH_M / FIT_STEP_M)^4 / 16, so the filter's half-power
## wavelength is about pi x SMOOTH_M (6 m): shorter wobble is mostly removed.
const SMOOTH_M := 2.0
const CLEAN_FLOOR_M := 0.05
const CLEAN_PER_HALF_WIDTH := 0.1
const WIDTH_SLOPE := 0.25
## A self-loop no point of which lies further than this many half-widths from its crossing is a
## pointer curl and is trimmed (trim_loops()): under two channel widths across, the loop's two
## passes leave no dry ground inside it, so the channel could not show it. A larger one is kept.
const CURL_PER_HALF_WIDTH := 4.0
const _PIN := 1.0e6
## hold_cap(): rounds, the sampling along a chord (finer than deviation()'s 0.25 m, so what it
## accepts also passes there), the slack over the cap it tolerates and how far inside the cap an
## added station lands.
const HOLD_PASSES := 40
## An excess over the cap above this after the rounds sends the stroke back as drawn.
const HOLD_TOLERANCE_M := 0.005
const HOLD_SAMPLE_M := 0.05
const HOLD_SLACK_M := 0.002
const HOLD_PULL := 0.95
## nearest_from()'s allowance for rounding in its arc-length bound (map coordinates are float32:
## about 1e-5 m at a 100 m map's edge).
const ARC_SLACK_M := 1.0e-3


## `points` (map XZ, upstream first, one half-width per point in `widths`) conditioned (see the
## header). `opts`: "smooth_m", "max_disp" (per half-width), "bend" (min radius per width),
## "min_hw" (floor of the half-widths). Returns {"points", "widths" (2 m stations), "changed",
## "max_disp" (largest distance either way between the result and the drawn line), "loops"
## (self-loops trimmed), "bends_before", "bends_after" (stations tighter than the bend floor),
## "thinned" (points DP dropped)}.
static func condition(
	points: PackedVector2Array, widths: PackedFloat32Array, opts: Dictionary = {}
) -> Dictionary:
	var out := {
		"points": points,
		"widths": widths,
		"changed": false,
		"max_disp": 0.0,
		"loops": 0,
		"bends_before": 0,
		"bends_after": 0,
		"thinned": 0,
	}
	if points.size() < 3 or widths.size() != points.size():
		return out
	var smooth_m: float = opts.get("smooth_m", SMOOTH_M)
	var disp_k: float = opts.get("max_disp", MAX_DISP_PER_HALF_WIDTH)
	var bend: float = opts.get("bend", MIN_BEND_PER_WIDTH)
	var pts := PackedVector2Array([points[0]])
	var hws := PackedFloat32Array([widths[0]])
	var narrow := widths[0]
	for i in range(1, points.size()):
		narrow = minf(narrow, widths[i])
		if points[i].distance_to(pts[-1]) >= MIN_POINT_GAP_M or i == points.size() - 1:
			pts.append(points[i])
			hws.append(widths[i])
	if pts.size() < 3:
		return out
	var kept := douglas_peucker(pts, DP_PER_HALF_WIDTH * narrow)
	out.thinned = pts.size() - kept.size()
	var thin := PackedVector2Array()
	var thin_w := PackedFloat32Array()
	for i in kept:
		thin.append(pts[i])
		thin_w.append(hws[i])
	var trimmed := trim_loops(thin, thin_w)
	out.loops = trimmed.loops
	var fine: Array = WaterEdit.resample(trimmed.points, trimmed.widths, FIT_STEP_M)
	var raw: PackedVector2Array = fine[0]
	var raw_w: PackedFloat32Array = fine[1]
	var n := raw.size()
	if n < 3:
		return out
	var h := FIT_STEP_M
	var lam_base := pow(smooth_m / h, 4.0) / 16.0
	var lam := PackedFloat64Array()
	lam.resize(n)
	lam.fill(lam_base)
	var fit := solve(raw, lam)
	out.bends_before = _bends(raw, raw_w, bend)
	for _pass in 4:
		var hit := false
		for i in range(1, n - 1):
			if _kappa(fit[i - 1], fit[i], fit[i + 1]) * 2.0 * raw_w[i] > 1.0 / bend:
				lam[i] *= 4.0
				hit = true
		if not hit:
			break
		fit = solve(raw, lam)
	fit[0] = raw[0]
	fit[n - 1] = raw[n - 1]
	var moved := 0.0
	for i in n:
		var d := fit[i] - raw[i]
		var cap := disp_k * raw_w[i]
		if d.length() > cap:
			fit[i] = raw[i] + d.normalized() * cap
		moved = maxf(moved, fit[i].distance_to(raw[i]))
	var clean := maxf(CLEAN_FLOOR_M, CLEAN_PER_HALF_WIDTH * narrow)
	if moved < clean and out.loops == 0:
		out.bends_after = out.bends_before
		return out
	var floor_hw: float = opts.get("min_hw", WaterBody.MIN_HALF_WIDTH_M)
	var smooth_w := limit_widths(raw_w, h, floor_hw)
	var line: Array = WaterEdit.resample(fit, smooth_w, WaterEdit.RESAMPLE_M)
	var stations: PackedVector2Array = line[0]
	# The ends are the drawn ends (a join into other water), exactly.
	stations[0] = points[0]
	stations[stations.size() - 1] = points[points.size() - 1]
	# The cap is on the TOTAL displacement from the drawn line (the author must feel the course as
	# their own gesture), not on the smoothing step alone: thinning, loop trimming and the final
	# resample each move the line too. A station further than the cap from the drawn polyline is
	# pulled back onto the cap.
	out.widths = line[1]
	# Holding the stations is not enough: a chord between two of them can cut a corner of the drawn
	# line further than the cap (a hard zigzag at a 2 m station step), so the polyline itself is
	# held, stations added where it strays (hold_cap).
	var held := hold_cap(stations, out.widths, points, disp_k)
	if max_excess(held[0], held[1], points, disp_k) > HOLD_TOLERANCE_M:
		# Still strays after HOLD_PASSES rounds (a line far noisier than its own width): the
		# guarantee wins over the cleaning, the stroke is kept as drawn.
		out.bends_after = out.bends_before
		return out
	out.points = held[0]
	out.widths = held[1]
	out.changed = true
	out.bends_after = _bends(out.points, out.widths, bend)
	out.max_disp = deviation(out.points, points)
	return out


## The largest distance from the polyline `a` (sampled every 0.25 m) to the polyline `b`: how far
## `a` strays from `b`. One-sided: the jitter of `b` that `a` smooths away does not count, only
## how far the clean line leaves the drawn one.
static func deviation(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var worst := 0.0
	var arc := arc_lengths(b)
	var hint := -1
	for i in a.size() - 1:
		var count := maxi(1, ceili(a[i].distance_to(a[i + 1]) / 0.25))
		for s in count + 1:
			var p := a[i].lerp(a[i + 1], float(s) / count)
			var near := nearest_from(b, arc, p, hint)
			hint = int(near.y)
			worst = maxf(worst, near.x)
	return worst


## `stations` (with `widths`) as a polyline that never strays further than `per_width` x its
## half-width from the polyline `drawn`, whole chords included, not only the stations: where a chord
## does, the worst point on it is added as a station pulled to 95 percent of the cap, until none
## does (at most HOLD_PASSES rounds; each round halves what is left). The stations that hold keep
## their places bit for bit, so a line that already held comes back unchanged. Returns
## [points, widths].
static func hold_cap(
	stations: PackedVector2Array,
	widths: PackedFloat32Array,
	drawn: PackedVector2Array,
	per_width: float
) -> Array:
	var pts := stations.duplicate()
	var ws := widths
	var arc := arc_lengths(drawn)
	_clamp_to_drawn(pts, drawn, ws, per_width)
	var hint := -1
	for _pass in HOLD_PASSES:
		var next_pts := PackedVector2Array([pts[0]])
		var next_ws := PackedFloat32Array([ws[0]])
		var added := false
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var count := maxi(1, ceili(a.distance_to(b) / HOLD_SAMPLE_M))
			var worst := HOLD_SLACK_M
			var at := Vector2.ZERO
			var at_w := 0.0
			for s in range(1, count):
				var t := float(s) / count
				var p := a.lerp(b, t)
				var near := nearest_from(drawn, arc, p, hint)
				hint = int(near.y)
				var cap := per_width * lerpf(ws[i], ws[i + 1], t)
				if near.y < 0.0 or near.x - cap <= worst:
					continue
				worst = near.x - cap
				var foot := drawn[int(near.y)].lerp(drawn[int(near.y) + 1], near.z)
				at = foot + (p - foot).normalized() * cap * HOLD_PULL
				at_w = lerpf(ws[i], ws[i + 1], t)
			if at_w > 0.0:
				next_pts.append(at)
				next_ws.append(at_w)
				added = true
			next_pts.append(b)
			next_ws.append(ws[i + 1])
		pts = next_pts
		ws = next_ws
		if not added:
			break
	return [pts, ws]


## How far the polyline `pts` (with `ws`) leaves the cap of `per_width` x half-width around the
## polyline `drawn`, at its worst (0 when it holds): the measure hold_cap() works to.
static func max_excess(
	pts: PackedVector2Array,
	ws: PackedFloat32Array,
	drawn: PackedVector2Array,
	per_width: float
) -> float:
	var worst := 0.0
	var arc := arc_lengths(drawn)
	var hint := -1
	for i in pts.size() - 1:
		var count := maxi(1, ceili(pts[i].distance_to(pts[i + 1]) / HOLD_SAMPLE_M))
		for s in count + 1:
			var t := float(s) / count
			var near := nearest_from(drawn, arc, pts[i].lerp(pts[i + 1], t), hint)
			hint = int(near.y)
			worst = maxf(worst, near.x - per_width * lerpf(ws[i], ws[i + 1], t))
	return worst


## Moves each station of `stations` that is more than `per_width` x its half-width from the
## polyline `drawn` back to that distance, on the line from its nearest drawn point.
static func _clamp_to_drawn(
	stations: PackedVector2Array,
	drawn: PackedVector2Array,
	widths: PackedFloat32Array,
	per_width: float
) -> void:
	var arc := arc_lengths(drawn)
	var hint := -1
	for i in stations.size():
		var near := nearest_from(drawn, arc, stations[i], hint)
		hint = int(near.y)
		var cap := per_width * widths[i]
		if near.y < 0.0 or near.x <= cap:
			continue
		var segment := int(near.y)
		var foot := drawn[segment].lerp(drawn[segment + 1], near.z)
		stations[i] = foot + (stations[i] - foot).normalized() * cap


## The arc length of the polyline `points` at each of its points, from the first (nearest_from()).
static func arc_lengths(points: PackedVector2Array) -> PackedFloat64Array:
	var arc := PackedFloat64Array()
	arc.resize(points.size())
	for i in range(1, points.size()):
		arc[i] = arc[i - 1] + points[i - 1].distance_to(points[i])
	return arc


## WaterGeometry.nearest_on_polyline(`points`, `p`), the same Vector3 bit for bit, from the segments
## that can hold it: `arc` is arc_lengths(`points`), `hint` a segment likely near `p` (the last
## answer, or -1). The scan runs in segment order as the full one does, but from a point at
## distance d of `p` every segment that ends less than d - `bound` further along the line lies more
## than `bound` from `p` (a polyline cannot get closer than its length allows), so it jumps past
## them; `bound` is the hint's distance or the best so far. A skipped segment is further than the
## answer, so it could never have been the first strict minimum the full scan keeps. The hint only
## speeds the scan; the answer does not depend on it.
static func nearest_from(
	points: PackedVector2Array, arc: PackedFloat64Array, p: Vector2, hint: int
) -> Vector3:
	var best := Vector3(INF, -1, 0)
	var n := points.size()
	var bound := INF
	if hint >= 0 and hint < n - 1:
		var ha := points[hint]
		var hseg := points[hint + 1] - ha
		var hlen := hseg.length_squared()
		if hlen > 1e-12:
			bound = p.distance_to(ha + hseg * clampf((p - ha).dot(hseg) / hlen, 0.0, 1.0))
	var s := 0
	while s < n - 1:
		var a := points[s]
		var reach := p.distance_to(a) - minf(bound, best.x) - ARC_SLACK_M
		if reach > arc[s + 1] - arc[s]:
			# Every segment from s that ends before arc[s] + reach is further than the bound.
			s = maxi(s + 1, arc.bsearch(arc[s] + reach) - 1)
			continue
		# The full scan's arithmetic, unchanged (WaterGeometry.nearest_on_polyline).
		var segment := points[s + 1] - a
		var length_sq := segment.length_squared()
		if length_sq > 1e-12:
			var t := clampf((p - a).dot(segment) / length_sq, 0.0, 1.0)
			var distance := p.distance_to(a + segment * t)
			if distance < best.x:
				best = Vector3(distance, s, t)
		s += 1
	return best


## Indices of the points Douglas-Peucker keeps of `points` at tolerance `eps` (both ends always).
static func douglas_peucker(points: PackedVector2Array, eps: float) -> PackedInt32Array:
	var n := points.size()
	var keep := PackedByteArray()
	keep.resize(n)
	keep[0] = 1
	keep[n - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, n - 1)]
	while not stack.is_empty():
		var span: Vector2i = stack.pop_back()
		var worst := -1.0
		var at := -1
		for i in range(span.x + 1, span.y):
			var d := _line_distance(points[i], points[span.x], points[span.y])
			if d > worst:
				worst = d
				at = i
		if at >= 0 and worst > eps:
			keep[at] = 1
			stack.append(Vector2i(span.x, at))
			stack.append(Vector2i(at, span.y))
	var out := PackedInt32Array()
	for i in n:
		if keep[i] != 0:
			out.append(i)
	return out


## `points` with every pointer curl cut out (the first pass is kept, the loop's far side rejoins
## at the crossing): {"points", "widths", "loops"}. A curl is a self-loop that stays within
## CURL_PER_HALF_WIDTH half-widths of its own crossing: too small to enclose dry ground, so the
## channel could not show it. A larger loop is the author's (card painter-water-paths: a 32 m
## stroke that crossed itself once was stored as its first 8 m) and is kept whole: it crosses,
## one body, one bed.
static func trim_loops(points: PackedVector2Array, widths: PackedFloat32Array) -> Dictionary:
	var pts := points.duplicate()
	var hws := widths.duplicate()
	var loops := 0
	var again := true
	while again and loops < 8:
		again = false
		var n := pts.size()
		for i in n - 1:
			for j in range(i + 2, n - 1):
				var hit: Variant = Geometry2D.segment_intersects_segment(
					pts[i], pts[i + 1], pts[j], pts[j + 1]
				)
				if hit == null:
					continue
				var at: Vector2 = hit
				var t := clampf(
					pts[i].distance_to(at) / maxf(pts[i].distance_to(pts[i + 1]), 1e-9), 0.0, 1.0
				)
				var width := lerpf(hws[i], hws[i + 1], t)
				var extent := 0.0
				for k in range(i + 1, j + 1):
					extent = maxf(extent, pts[k].distance_to(at))
				if extent > CURL_PER_HALF_WIDTH * width:
					continue
				var np := pts.slice(0, i + 1)
				var nw := hws.slice(0, i + 1)
				np.append(at)
				nw.append(width)
				np.append_array(pts.slice(j + 1))
				nw.append_array(hws.slice(j + 1))
				pts = np
				hws = nw
				loops += 1
				again = true
				break
			if again:
				break
	return {"points": pts, "widths": hws, "loops": loops}


## The smoothed `y` (penalised least squares, see the header) with per-row weights `lam`; the
## first and last point are pinned.
static func solve(y: PackedVector2Array, lam: PackedFloat64Array) -> PackedVector2Array:
	var n := y.size()
	var a0 := PackedFloat64Array()
	var a1 := PackedFloat64Array()
	var a2 := PackedFloat64Array()
	a0.resize(n)
	a1.resize(n)
	a2.resize(n)
	a0.fill(1.0)
	a0[0] = _PIN
	a0[n - 1] = _PIN
	for i in range(1, n - 1):
		var l := lam[i]
		a0[i - 1] += l
		a0[i] += 4.0 * l
		a0[i + 1] += l
		a1[i - 1] -= 2.0 * l
		a1[i] -= 2.0 * l
		a2[i - 1] += l
	var l0 := PackedFloat64Array()
	var l1 := PackedFloat64Array()
	var l2 := PackedFloat64Array()
	l0.resize(n)
	l1.resize(n)
	l2.resize(n)
	for i in n:
		var d := a0[i]
		if i >= 1:
			d -= l1[i - 1] * l1[i - 1]
		if i >= 2:
			d -= l2[i - 2] * l2[i - 2]
		l0[i] = sqrt(maxf(d, 1e-12))
		if i + 1 < n:
			var v := a1[i]
			if i >= 1:
				v -= l2[i - 1] * l1[i - 1]
			l1[i] = v / l0[i]
		if i + 2 < n:
			l2[i] = a2[i] / l0[i]
	var out := PackedVector2Array()
	out.resize(n)
	for axis in 2:
		var z := PackedFloat64Array()
		z.resize(n)
		for i in n:
			var b := y[i][axis] * (_PIN if i == 0 or i == n - 1 else 1.0)
			if i >= 1:
				b -= l1[i - 1] * z[i - 1]
			if i >= 2:
				b -= l2[i - 2] * z[i - 2]
			z[i] = b / l0[i]
		var x := PackedFloat64Array()
		x.resize(n)
		for i in range(n - 1, -1, -1):
			var v := z[i]
			if i + 1 < n:
				v -= l1[i] * x[i + 1]
			if i + 2 < n:
				v -= l2[i] * x[i + 2]
			x[i] = v / l0[i]
		for i in n:
			out[i][axis] = x[i]
	return out


## Half-widths filtered: median of three, then limited to WIDTH_SLOPE m per m of arc (`step` apart),
## at least `floor_hw`. Ends keep their value.
static func limit_widths(
	widths: PackedFloat32Array, step: float, floor_hw: float
) -> PackedFloat32Array:
	var n := widths.size()
	var out := widths.duplicate()
	for i in range(1, n - 1):
		out[i] = maxf(minf(widths[i - 1], widths[i]), minf(maxf(widths[i - 1], widths[i]), widths[i + 1]))
	var allow := WIDTH_SLOPE * step
	for i in range(1, n):
		out[i] = clampf(out[i], out[i - 1] - allow, out[i - 1] + allow)
	for i in range(n - 2, -1, -1):
		out[i] = clampf(out[i], out[i + 1] - allow, out[i + 1] + allow)
	for i in n:
		out[i] = maxf(out[i], floor_hw)
	return out


## The largest distance from a vertex of either polyline to the other.
static func hausdorff(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var worst := 0.0
	for p in a:
		worst = maxf(worst, WaterGeometry.nearest_on_polyline(b, p).x)
	for p in b:
		worst = maxf(worst, WaterGeometry.nearest_on_polyline(a, p).x)
	return worst


## Stations whose radius of curvature is under `bend` channel widths (2 x half-width).
static func _bends(points: PackedVector2Array, widths: PackedFloat32Array, bend: float) -> int:
	var count := 0
	for i in range(1, points.size() - 1):
		if _kappa(points[i - 1], points[i], points[i + 1]) * 2.0 * widths[i] > 1.0 / bend:
			count += 1
	return count


## The Menger curvature of three points (1 / radius of their circle).
static func _kappa(a: Vector2, b: Vector2, c: Vector2) -> float:
	var ab := a.distance_to(b)
	var bc := b.distance_to(c)
	var ca := c.distance_to(a)
	var denom := ab * bc * ca
	if denom < 1e-12:
		return 0.0
	return 2.0 * absf((b - a).cross(c - b)) / denom


static func _line_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < 1e-12:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / length_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)
