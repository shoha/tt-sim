/*
 * Texel Copy Blit
 * ===============
 *
 * Copies a source texture into a DrawableTexture2D rectangle byte for byte: nearest
 * filtering and blending disabled. The default blit mixes by source alpha, which would
 * corrupt data textures whose alpha channel is a value of its own (AuthoredTerrain's biome
 * ground weights keep the fourth layer's weight in alpha). The destination rectangle must
 * be the source's size, so each destination texel reads exactly one source texel.
 */

shader_type texture_blit;
render_mode blend_disabled;

uniform sampler2D source_texture : hint_blit_source0, filter_nearest;

void blit() {
	COLOR0 = texture(source_texture, UV);
}
