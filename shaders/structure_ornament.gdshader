// The soft and small parts a player adds to a building (StructureOrnaments): ivy and flower-box
// foliage, awning and banner cloth, a vane's metal, the small wooden parts of a sign. Each keeps the
// colour procgen painted into its vertices (a stripe, a jewel tone, a leaf green) and takes the
// suite's painterly light (structure_painterly.gdshaderinc): a warm lit side, a soft cool shade, a
// faint rim. Seen from both sides, since a leaf, a pennant and an awning are single sheets. COLOR.a
// is the height above the building's foot in sixteenths of a metre (StructurePaint), which cools
// and darkens the first half metre the way a wall's foot is, so ivy sits in the ground.
shader_type spatial;
render_mode specular_disabled, diffuse_burley, cull_disabled;

// A slow sideways sway of the whole piece, metres (a treehouse crown); 0 keeps a part still.
#define S_SWAY
uniform float sway : hint_range(0.0, 0.3) = 0.0;

// Cloth in the wind (topic wind_c): banner, pennant and awning cloth lean downwind and flutter in the
// gusts. The Wind autoload publishes the three global vec4s (autoloads/wind.gd); the gust field below
// mirrors wind_foliage_include.gdshaderinc's wind_gust_field term for term. The per-vertex reach comes
// from StructureCloth in the second UV set: x the metres from the cloth's attachment, grown with the
// distance (0 at the pole side or the wall, the free edge or hem biggest), y how far the piece leans
// downwind (a pennant 1, a hanging banner 0.6, an awning 0 and a flap instead). Every displacement is a
// function of the world position and the weight alone (never the normal), so the two faces of a sheet
// and its edges move together and never split. `cloth_wind` is 0 for every other ornament kind.
#define S_WIND
global uniform vec4 wind_dir;
global uniform vec4 wind_phase;
global uniform vec4 wind_gust;
uniform float cloth_wind : hint_range(0.0, 2.0) = 0.0;

float s_gust_field(vec2 world_xz) {
	vec2 dir = wind_dir.xy;
	float along = dot(world_xz, dir);
	float across = dot(world_xz, vec2(-dir.y, dir.x));
	float sp = wind_gust.z;
	float wave = 0.55 * sin(along * (6.2831853 / 12.0) - wind_phase.x + sp)
		+ 0.45 * sin(along * (6.2831853 / 19.0) + across * 0.25 - wind_phase.y + 1.7 + sp * 1.618);
	wave += wind_gust.y * 0.3 * sin(along * (6.2831853 / 7.0) + across * 0.35 - wind_phase.z + 0.6 + sp * 2.414);
	return smoothstep(-0.2, 0.9, wave);
}

vec3 s_cloth_wind(vec3 vertex, vec2 weight, mat4 model) {
	float motion = wind_gust.w * cloth_wind;
	if (motion <= 0.0 || weight.x <= 0.0) {
		return vec3(0.0);
	}
	vec3 w = (model * vec4(vertex, 1.0)).xyz;
	float g = s_gust_field(w.xz);
	// Wind strength: a calm day stirs the cloth (0.4), windy fills it (1.05), a storm snaps it (1.6).
	float strength = clamp(0.25 + wind_dir.z / 10.0, 0.0, 1.6);
	vec3 down = vec3(wind_dir.x, 0.0, wind_dir.y);
	vec3 across = vec3(-wind_dir.y, 0.0, wind_dir.x);
	float lean = strength * (0.24 + 0.68 * g) * weight.y;
	float ph = TIME * (2.0 + strength * 2.5) + dot(w.xz, vec2(1.7, 2.3)) + weight.x * 3.0;
	float f1 = sin(ph);
	float f2 = sin(ph * 1.7 + 1.3);
	float amp = strength * (0.08 + 0.24 * g);
	// A flag flutters across the wind and along it; an awning (lean 0) flaps up and down.
	vec3 flutter = across * f1 * amp + down * f2 * amp * 0.5 * weight.y + vec3(0.0, 1.0, 0.0) * f2 * amp * (0.75 - weight.y * 0.45);
	return weight.x * motion * (down * lean + flutter);
}

#include "res://shaders/structure_painterly.gdshaderinc"

// A multiplier on the painted colour: metal is lifted a little warm so it reads as gold and iron,
// not as a dark lump; cloth and foliage keep their colour.
uniform vec3 tone = vec3(1.0);
// Procgen paints these parts in lit colours (a leaf green near 0.5, a cream stripe near 0.9) and the
// painterly light adds its own gain on top, which blew a first render out to pale cream: the paint is
// brought down to the albedo the crowns' foliage has before the light is applied.
uniform float exposure : hint_range(0.2, 1.0) = 0.66;
// A broad hue/value shift in soft blotches, so a clump of leaves is never one flat green.
uniform float blotch : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.92;

void fragment() {
	vec3 col = COLOR.rgb * tone * exposure;
	float metres = COLOR.a * 16.0;
	col *= s_break(s_noise(s_pos * 1.7 + 3.0), blotch, 0.3);
	float foot = 1.0 - smoothstep(0.0, 0.5, metres);
	col *= mix(vec3(1.0), vec3(0.78, 0.86, 0.80), foot * 0.6);
	vec3 painted = s_ramp(col, NORMAL, INV_VIEW_MATRIX);
	ALBEDO = painted;
	AO = s_ambient();
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = roughness_amount;
	EMISSION = s_rim(painted, NORMAL, VIEW);
}
