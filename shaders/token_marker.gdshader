shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled;

// The top-down token marker (scenes/board_token/token_markers.gd): a map pin drawn on top of
// the board above a token. A round head holding the token's own picture (a cell of the portrait
// atlas, scenes/board_token/token_portraits.gd) and a short tail whose tip touches the token.
// One quad per token in a MultiMesh, turned to face the camera:
//   COLOR           the pin's body colour (the token's vivid colour) and, in alpha, the strength
//                   (the fade-in with pitch, and the GM's dimmed view of a hidden token);
//   INSTANCE_CUSTOM xy = the picture's top-left in the atlas (UV), z = 1 when the picture is in
//                   the atlas (0 draws the plain coloured disc).
// The quad is QUAD_W by QUAD_H head diameters, its bottom edge at v = 0; the head's size is set
// by the quad's scale. The constants below mirror TokenMarkers (QUAD_W, QUAD_H, TIP_Y).

uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
// The picture's side in atlas UV.
uniform float picture_uv = 0.0546875;
// The thin pale edge, in head diameters (about 1.3 px on a 24 px head), and the cream it is.
uniform float rim = 0.055;
uniform vec3 rim_colour : source_color = vec3(1.0, 0.96, 0.86);
uniform vec3 shadow_colour : source_color = vec3(0.16, 0.08, 0.26);
uniform float shadow_strength = 0.30;

const float QUAD_W = 1.3;
const float QUAD_H = 1.65;
const float TIP_Y = 0.14;
const float HEAD_R = 0.5;
const float TIP_R = 0.03;
const float TAIL_H = 0.80;

varying vec4 body_colour;
varying vec4 cell;

void vertex() {
	body_colour = COLOR;
	cell = INSTANCE_CUSTOM;
}

// iq's uneven capsule: a circle of r1 at the origin and one of r2 at (0, h); a map pin when the
// big one is the head.
float sd_pin(vec2 p, float r1, float r2, float h) {
	p.x = abs(p.x);
	float b = (r1 - r2) / h;
	float a = sqrt(1.0 - b * b);
	float k = dot(p, vec2(-b, a));
	if (k < 0.0) {
		return length(p) - r1;
	}
	if (k > a * h) {
		return length(p - vec2(0.0, h)) - r2;
	}
	return dot(p, vec2(a, b)) - r1;
}

// The pin's signed distance (head diameters) at q: x across, y up from the quad's bottom edge.
float pin_sd(vec2 q) {
	float tip_c = TIP_Y + TIP_R;
	float head_c = tip_c + TAIL_H;
	return sd_pin(vec2(q.x, head_c - q.y), HEAD_R, TIP_R, TAIL_H);
}

void fragment() {
	vec2 q = vec2((UV.x - 0.5) * QUAD_W, (1.0 - UV.y) * QUAD_H);
	float head_c = TIP_Y + TIP_R + TAIL_H;
	float sd = pin_sd(q);
	float aa = max(fwidth(sd), 0.002);
	float cover = 1.0 - smoothstep(-aa, aa, sd);
	// A soft shadow beneath and to the right, so the pin lifts off the board without an ink line.
	float sd_shadow = pin_sd(q - vec2(0.035, -0.05));
	float shadow = (1.0 - smoothstep(-0.02, 0.13, sd_shadow)) * shadow_strength;

	// The head's picture: the unit disc inside the rim, mapped onto the atlas cell.
	vec2 local = (q - vec2(0.0, head_c)) / (HEAD_R - rim);
	vec2 uv = cell.xy + (local * vec2(0.5, -0.5) + 0.5) * picture_uv;
	vec2 du = dFdx(uv) * 0.3;
	vec2 dv = dFdy(uv) * 0.3;
	vec4 pic = texture(atlas, uv + du + dv) + texture(atlas, uv - du + dv)
			+ texture(atlas, uv + du - dv) + texture(atlas, uv - du - dv);
	pic *= 0.25;
	// The body colour is a little lighter at the top: a hint of light on a painted button.
	// The instance colour arrives as the sRGB colour it was written as; ALBEDO is linear.
	vec3 body = pow(body_colour.rgb, vec3(2.2)) * (0.88 + 0.22 * clamp(local.y * 0.5 + 0.5, 0.0, 1.0));
	// The picture is premultiplied in the atlas, so it lays straight over the body colour.
	vec3 inner = mix(body, pic.rgb + body * (1.0 - pic.a), cell.z);
	float in_picture = 1.0 - smoothstep(-aa, aa, length(q - vec2(0.0, head_c)) - (HEAD_R - rim));
	vec3 fill = mix(body, inner, in_picture);
	// The pale rim is whatever of the pin lies within `rim` of its outline.
	float rim_mix = smoothstep(-rim - aa, -rim + aa, sd);
	vec3 pin = mix(fill, rim_colour, rim_mix);

	float alpha = cover + shadow * (1.0 - cover);
	vec3 colour = (pin * cover + shadow_colour * shadow * (1.0 - cover)) / max(alpha, 0.0001);
	ALBEDO = colour;
	ALPHA = alpha * body_colour.a;
}
