// The global wind (autoloads/wind.gd, docs/systems/wind.md) for the shaders that are not
// plants or cloth: the persistent fire's smoke (fire_smoke_book.gdshader), its flames
// (fire_flames.gdshader) and the water's chop (water.gdshader). The Wind autoload publishes the
// three vec4s only when they change; no TIME is involved, so every peer reads one wind.
// The plant include (wind_foliage_include.gdshaderinc) and the cloth (structure_ornament)
// declare the same globals themselves; a shader includes this file or one of those, never both.
//
// wind_dir: xy the unit direction the wind blows toward in world XZ (veered), z its mean speed
// in m/s, w the preset's sway scale.
global uniform vec4 wind_dir;
// wind_phase: the three front phases (12 m, 19 m, 7 m), already wrapped to 0..TAU.
global uniform vec4 wind_phase;
// wind_gust: x gust amplitude (0.35 at calm), y storm ripple 0..1, z the seed's phase, w the
// player's motion scale (0 is reduce-motion or Wind motion off: every consumer looks as it
// did before the wind).
global uniform vec4 wind_gust;

// WindDrift.CALM_SPEED and STORM_SPEED: wind_strength01 runs 0 at calm to 1 at a storm.
const float WIND_CALM_SPEED = 1.5;
const float WIND_STORM_SPEED = 14.0;

// The gust envelope in 0..1 at a world XZ position, term for term
// wind_foliage_include.gdshaderinc's wind_gust_field and WindModel.gust_at: fronts that travel
// downwind, softly thresholded into bursts with lulls between them.
float wind_global_gust(vec2 world_xz) {
	vec2 dir = wind_dir.xy;
	float along = dot(world_xz, dir);
	float across = dot(world_xz, vec2(-dir.y, dir.x));
	float k1 = 6.2831853 / 12.0;
	float k2 = 6.2831853 / 19.0;
	float k3 = 6.2831853 / 7.0;
	float sp = wind_gust.z;
	float wave = 0.55 * sin(along * k1 - wind_phase.x + sp)
		+ 0.45 * sin(along * k2 + across * 0.25 - wind_phase.y + 1.7 + sp * 1.618);
	wave += wind_gust.y * 0.3 * sin(along * k3 + across * 0.35 - wind_phase.z + 0.6 + sp * 2.414);
	return smoothstep(-0.2, 0.9, wave);
}

// WindDrift.strength01 of the mean speed.
float wind_strength01() {
	return clamp((wind_dir.z - WIND_CALM_SPEED) / (WIND_STORM_SPEED - WIND_CALM_SPEED), 0.0, 1.0);
}

// The player's motion scale, 0..1.
float wind_motion() {
	return clamp(wind_gust.w, 0.0, 1.0);
}
