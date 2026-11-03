// Panes and door leaves of built structures: the vertex colour as a flat painted tone, unshaded (a
// pane in the shade of its own reveal went black when lit) and seen from both sides. A cool, pale
// pane (procgen's glass tints and its sky-pale head, values near 1 that came out as white
// stickers) is settled into the scene: scaled down and pulled toward one sky teal, with a breath of
// warm reflected light, so panes stay light and varied but read as glass holding the sky. The
// numbers are in linear light (ALBEDO). Warm panes (lit windows, a catch of sun) are left as
// painted; a door's dark paint is converted from sRGB to linear (see fragment()).
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 pane_tone = vec3(0.34, 0.50, 0.58);
uniform vec3 sky_teal = vec3(0.17, 0.38, 0.46);
uniform vec3 warm_reflect = vec3(0.45, 0.28, 0.12);
uniform float sky_share : hint_range(0.0, 1.0) = 0.4;
uniform float warm_share : hint_range(0.0, 0.5) = 0.12;
uniform float settle : hint_range(0.0, 1.0) = 1.0;

// Eye-level interior (card eyewindows, probe variants B and C; WIP). A window pane flagged by
// procgen's glazing (vertex alpha 0.3 + 0.5 * a per-window draw; every other piece is opaque) draws
// a small room behind the glass: the view ray is continued `interior_depth` metres past the pane to
// a back wall (interior mapping, the pane's UV gradient turns the lateral shift into UV), which gets
// a vignette of the reveal, a dark floor at the sill, a lamp pool (strong when the window is lit,
// faint otherwise), a furniture blot, and, nearer the glass than the room, curtains whose folds are
// a soft sine; the glass holds the sky over all of it (more at the head, more at grazing angles)
// with one pale diagonal streak.
uniform float interior_depth : hint_range(0.2, 3.0) = 1.3;
uniform vec3 room_warm = vec3(0.62, 0.36, 0.17);
uniform vec3 room_dark = vec3(0.08, 0.075, 0.115);
uniform vec3 lamp_glow = vec3(1.0, 0.72, 0.32);
uniform float glass_share : hint_range(0.0, 1.0) = 0.3;
uniform float curtain_chance : hint_range(0.0, 1.0) = 0.55;

vec3 curtain_cloth(float k) {
	vec3 cream = vec3(0.9, 0.75, 0.5);
	vec3 rose = vec3(0.8, 0.28, 0.3);
	vec3 ochre = vec3(0.85, 0.5, 0.1);
	vec3 plum = vec3(0.4, 0.15, 0.3);
	vec3 c = mix(cream, rose, smoothstep(0.2, 0.3, k));
	c = mix(c, ochre, smoothstep(0.45, 0.55, k));
	return mix(c, plum, smoothstep(0.75, 0.85, k));
}

vec3 interior_pane(vec3 col, float flag, vec3 deep, vec3 normal, vec3 vtx, vec2 uvc) {
	float id = clamp((flag - 0.3) / 0.5, 0.0, 1.0);
	vec3 n = normalize(normal);
	if (dot(n, vtx) > 0.0) {
		n = -n;
	}
	vec3 dir = normalize(vtx);
	float s = (dot(n, vtx) - interior_depth) / min(dot(n, dir), -0.02);
	vec3 delta = dir * s - vtx;
	vec3 dp1 = dFdx(vtx);
	vec3 dp2 = dFdy(vtx);
	vec2 duv1 = dFdx(uvc);
	vec2 duv2 = dFdy(uvc);
	vec3 dp2perp = cross(dp2, n);
	vec3 dp1perp = cross(n, dp1);
	float det = dot(dp1, dp2perp);
	det = abs(det) < 1e-12 ? 1e-12 : det;
	vec3 gu = (dp2perp * duv1.x + dp1perp * duv2.x) / det;
	vec3 gv = (dp2perp * duv1.y + dp1perp * duv2.y) / det;
	vec2 b = uvc + clamp(vec2(dot(gu, delta), dot(gv, delta)), vec2(-1.2), vec2(1.2));

	float lit = smoothstep(0.7, 0.9, col.r);
	float edge = min(min(b.x, 1.0 - b.x), min(b.y, 1.0 - b.y));
	float vig = smoothstep(-0.15, 0.3, edge);
	// A broad soft lamp pool, wider than the window: a narrower one read as a head and shoulders.
	float pool = 1.0 - smoothstep(0.0, 1.3, length((b - vec2(0.5, 0.7)) * vec2(0.8, 1.0)));
	float amount = mix(0.28 + 0.3 * id, 0.55 + 0.45 * pool, lit) * (0.45 + 0.55 * pool);
	vec3 room = mix(room_dark, room_warm * (0.7 + 0.5 * fract(id * 5.3)), clamp(amount, 0.0, 1.0));
	room += lamp_glow * pool * pool * lit * 0.55;
	room *= 1.0 - 0.5 * smoothstep(0.5, 0.0, b.y);
	// A paler band across the back wall at about mantel height, so the room has a horizon.
	room *= 1.0 + 0.25 * smoothstep(0.08, 0.0, abs(b.y - 0.5));
	room *= vig;

	float sky = glass_share * (1.0 - 0.55 * lit) + 0.3 * smoothstep(0.35, 1.0, uvc.y) * (1.0 - lit);
	vec3 pale = vec3(0.55, 0.72, 0.85);
	float streak = smoothstep(0.05, 0.0, abs(uvc.x * 0.7 + uvc.y * 0.5 - 0.62 - 0.12 * id));
	vec3 pane = mix(room, deep, clamp(sky, 0.0, 0.8)) + pale * streak * 0.12 * (1.0 - lit);

	// Curtains hang in the pane's own plane: side drapes with a soft sine fold, a valance at the head.
	if (id > 1.0 - curtain_chance) {
		float k = fract(id * 11.7);
		vec3 cloth = curtain_cloth(k);
		float wd = 0.13 + 0.1 * fract(id * 7.1);
		// Straight drapes with a slight wave (a tie-back pinch made the open gap read as a figure).
		float tie = 1.0 + 0.08 * sin(uvc.y * 8.0 + id * 6.0);
		float left = smoothstep(wd * tie + 0.025, wd * tie - 0.025, uvc.x);
		float right = smoothstep(wd * tie + 0.025, wd * tie - 0.025, 1.0 - uvc.x);
		float side = mix(left, max(left, right), step(0.5, fract(id * 17.3)));
		float valance = smoothstep(0.84, 0.87, uvc.y);
		float mask = max(side * step(0.12, uvc.y + 0.2), valance);
		float fold = 0.8 + 0.2 * sin(uvc.x * 60.0 + id * 6.0);
		vec3 drape = cloth * fold * (0.75 + 0.25 * uvc.y);
		pane = mix(pane, drape, mask);
	}
	return pane;
}

void fragment() {
	vec3 col = COLOR.rgb;
	// 1 for a cool pane (blue at least as strong as red), 0 for amber glow and wooden leaves.
	float cool = 1.0 - smoothstep(0.02, 0.2, col.r - col.b);
	// A violet tint (blue over red, but green under red) is not sky glass: it keeps its hue, as the
	// warm and rose tints do (GlazingNode.tone, range_look 2026-10-30). Teal, sea and cool blues
	// have green at least level with red.
	cool *= smoothstep(-0.08, -0.01, col.g - col.r);
	vec3 deep = mix(col * pane_tone, sky_teal, sky_share);
	deep = mix(deep, warm_reflect, warm_share);
	// A door leaf's paint is sRGB like every other vertex colour, but ALBEDO is linear: unconverted,
	// brown and red leaves came out salmon and pink. Dark tones are converted; the bright glow of a
	// lit window (red above 0.8) stays as it was judged.
	vec3 linear_paint = pow(col, vec3(2.2));
	float is_paint = 1.0 - smoothstep(0.55, 0.8, col.r);
	vec3 warm = mix(col, linear_paint, is_paint);
	ALBEDO = mix(warm, deep, cool * settle);
	if (COLOR.a < 0.9) {
		ALBEDO = interior_pane(col, COLOR.a, mix(deep, warm, 1.0 - cool), NORMAL, VERTEX, UV);
	}
}
