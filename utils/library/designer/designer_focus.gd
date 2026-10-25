class_name DesignerFocus
extends RefCounted

## "Show only this rule" in the biome designer (step S9): hides the scatter nodes of every asset
## the chosen rule does not place, so one rule's plants can be judged alone on the proving ground.
## It only toggles `visible` of the scatter's MultiMesh nodes (settled and growing); no row, no
## cell and no picking changes, and clearing the focus shows everything again. Nodes made by a
## later regeneration are visible, so the session applies the focus again after each one. Static
## functions over an AuthoredScatter, like ScatterRefresh.


## Shows only the nodes of the assets in `shown` ({asset id: true}); null shows every node.
## Returns how many nodes it hid.
static func apply(scatter: AuthoredScatter, shown: Variant) -> int:
	var hidden := 0
	for cell: Vector2i in scatter._cells:
		var held: Dictionary = scatter._cells[cell]
		for asset_id: String in held:
			var visible: bool = shown == null or (shown as Dictionary).has(asset_id)
			var node := scatter.get_cell_node(cell, asset_id)
			if node != null:
				node.visible = visible
				hidden += 0 if visible else 1
			for growing in scatter.get_growing_nodes(cell, asset_id):
				growing.visible = visible
				hidden += 0 if visible else 1
	return hidden


## The asset ids of palette biome `biome_id`'s rule `key` ({asset id: true}); {} for no such rule.
static func assets_of_rule(biome_id: String, key: String) -> Dictionary:
	var out := {}
	for rule: Dictionary in PaletteLibrary.species(biome_id):
		if String(rule["key"]) == key:
			for asset_id: String in rule.get("assets", []):
				out[asset_id] = true
	return out
