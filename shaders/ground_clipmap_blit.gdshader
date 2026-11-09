// The ground clipmap's strip copy (GroundClipmap): draws a baked strip into a level's window
// as it is, alpha included, over whatever the window held (blending off, no modulate).
shader_type canvas_item;
render_mode blend_disabled, unshaded;

void fragment() {
	COLOR = texture(TEXTURE, UV);
}
