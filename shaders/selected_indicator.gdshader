shader_type spatial;
render_mode unshaded;
uniform sampler2D TEXTURE; // The texture from your MeshInstance
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0); // Default white

void fragment(){
    // Sample the original texture color
    vec4 tex_color = texture(TEXTURE, UV);

    vec4 final_color = tint_color;
	final_color.a = tex_color.a;

    ALBEDO = final_color.rgb; // Set the final color
    ALPHA = final_color.a;    // Set the alpha
}