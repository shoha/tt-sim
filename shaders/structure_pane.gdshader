// Panes and door leaves of built structures: the vertex colour as a flat painted tone, unshaded (a
// pane in the shade of its own reveal went black when lit) and seen from both sides. A cool, pale
// pane (procgen's glass tints and its sky-pale head, values near 1 that came out as white
// stickers) is settled into the scene: scaled down and pulled toward one sky teal, with a breath of
// warm reflected light, so panes stay light and varied but read as glass holding the sky. The
// numbers are in linear light (ALBEDO). Warm panes (lit windows, a door's leaf, a catch of sun) are
// left as painted.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 pane_tone = vec3(0.34, 0.50, 0.58);
uniform vec3 sky_teal = vec3(0.17, 0.38, 0.46);
uniform vec3 warm_reflect = vec3(0.45, 0.28, 0.12);
uniform float sky_share : hint_range(0.0, 1.0) = 0.4;
uniform float warm_share : hint_range(0.0, 0.5) = 0.12;
uniform float settle : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec3 col = COLOR.rgb;
	// 1 for a cool pane (blue at least as strong as red), 0 for amber glow and wooden leaves.
	float cool = 1.0 - smoothstep(0.02, 0.2, col.r - col.b);
	vec3 deep = mix(col * pane_tone, sky_teal, sky_share);
	deep = mix(deep, warm_reflect, warm_share);
	ALBEDO = mix(col, deep, cool * settle);
}
