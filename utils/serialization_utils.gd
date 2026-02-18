class_name SerializationUtils

## Shared serialization helpers for converting engine types to/from
## JSON-compatible dictionaries.  Used by resources (TokenPlacement,
## TokenState, LevelData) and network code to avoid duplicating
## Vector3 ↔ Dictionary conversions everywhere.


## Convert a Vector3 to a JSON-friendly dictionary.
static func vec3_to_dict(v: Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}


## Convert a dictionary back to a Vector3.
## Missing keys fall back to the corresponding component of [param default].
## Values are explicitly cast to float for robustness against integer JSON data.
static func dict_to_vec3(d: Dictionary, default: Vector3 = Vector3.ZERO) -> Vector3:
	return Vector3(
		float(d.get("x", default.x)),
		float(d.get("y", default.y)),
		float(d.get("z", default.z)),
	)


## Convert a Color to a JSON-friendly dictionary.
static func color_to_dict(c: Color) -> Dictionary:
	return {"r": c.r, "g": c.g, "b": c.b, "a": c.a}


## Convert a dictionary back to a Color.
## Values are explicitly cast to float for robustness against integer JSON data.
static func dict_to_color(d: Dictionary, default: Color = Color.WHITE) -> Color:
	return Color(
		float(d.get("r", default.r)),
		float(d.get("g", default.g)),
		float(d.get("b", default.b)),
		float(d.get("a", default.a)),
	)
