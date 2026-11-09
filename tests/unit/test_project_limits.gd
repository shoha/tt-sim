extends GutTest

## Rendering limits the project raises above Godot's defaults (docs/PERFORMANCE.md
## "Ground-cover lighting"). Every instance whose material has an instance uniform (the wind
## shaders' `grow`) takes 16 slots of the global shader uniform buffer; at the default 65,536 a
## map past about 4,000 scatter nodes overflowed ("Too many instances using shader instance
## variables") and later nodes lost their per-node uniforms silently.


func test_global_shader_uniform_buffer_is_raised() -> void:
	var size: Variant = ProjectSettings.get_setting(
		"rendering/limits/global_shader_variables/buffer_size"
	)
	assert_eq(int(size), 262144, "16,384 instances with instance uniforms, 4 MB of VRAM")
