extends SceneTree

## Map-size helper (see README.md): which grassland valley seeds give a river and a
## crossing. Pure document build (NewMap.from_spec), no rendering.


func _init() -> void:
	for s in range(1, 25):
		var doc := NewMap.from_spec(
			{"size_ft": 200, "biome_id": "grassland_meadow_summer_s1", "seed": s, "landform": "valley"}
		)
		var rivers := 0
		for body in doc.water_bodies:
			if body.get("kind") != null:
				pass
			rivers += 1
		print("MS| seed %d water_bodies %d crossings %d" % [s, doc.water_bodies.size(), doc.crossings.size()])
	quit()
