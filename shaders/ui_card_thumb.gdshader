shader_type canvas_item;

// A level card's thumbnail (scenes/ui/primitives/level_card.gd). Thumbnails rendered before
// the painted theme show a pure-black void where the map ends; the card keys that black out
// so its paper-inset wash shows through instead of a hole. Only near-pure black goes: the
// darkest shadow on a map stays well above the key.

uniform float key_below = 0.02;

void fragment() {
	float peak = max(COLOR.r, max(COLOR.g, COLOR.b));
	COLOR.a *= smoothstep(0.5 * key_below, key_below, peak);
}
