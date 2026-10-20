// How a wind foliage instance arrives and leaves under a brush (ScatterArrival,
// utils/scatter_arrival.gd; docs/systems/scatter.md "Arrival motion"). Included after
// wind_foliage_include.gdshaderinc by wind_foliage_main.gdshaderinc (the four real variants) and
// by the three debug variants, never by wind_foliage_burn.gdshader, so the burn variant gains no
// uniform.
//
// A growing or shrinking node sets two per-node instance uniforms and each instance works out its
// own size from them, so the ripple costs no per-instance work on the CPU:
//   grow_wave   xy the brush centre (world x, z), z seconds of delay per metre from it, w the
//               longest delay.
//   grow_clock  x seconds since the node's animation began; negative (the default) is off, and
//               the per-node `grow` applies as it always has. y the seconds one instance takes,
//               negative when shrinking out.
// Growing, an instance follows a back-out ease (about 10 percent past full size, then 1);
// shrinking, the same curve backwards (a swell, then the collapse).
instance uniform vec4 grow_wave = vec4(0.0);
instance uniform vec2 grow_clock = vec2(-1.0, 1.0);
// The back ease's constant (ScatterArrival.BACK).
const float GROW_BACK = 1.70158;


// The factor a vertex of the instance at world `origin` is scaled by about its origin.
float grow_scale(vec3 origin) {
	if (grow_clock.x < 0.0) {
		return grow;
	}
	float delay = min(distance(origin.xz, grow_wave.xy) * grow_wave.z, grow_wave.w);
	float t = clamp((grow_clock.x - delay) / max(abs(grow_clock.y), 1e-3), 0.0, 1.0);
	float u = (grow_clock.y >= 0.0 ? t : 1.0 - t) - 1.0;
	return 1.0 + (GROW_BACK + 1.0) * u * u * u + GROW_BACK * u * u;
}
