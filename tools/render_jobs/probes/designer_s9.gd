extends RefCounted

## Render-job probe (`call` op) for the biome designer's step S9: seasons, the A/B view, the
## ground look editor and the locks (tools/render_jobs/probes/designer.gd holds the S8a actions;
## the designer must be open, `wait_ready` after the call that opens it).
## step.action:
##   add_season {id}                   adds a season to the biome (DesignerSeasonEdits).
##   season {id}                       the map shows that season (session.set_season).
##   season_rule {rule, season, field, value}   a rule's change in a season (null clears it).
##   season_hide {rule, season, on}    the rule leaves (on false) or returns to a season.
##   season_ground {season, field, surface}   a season's ground field (null: same as the biome).
##   season_density {season, size_class, scale}   a season's class density scale.
##   target {season}                   where the ground strip and the look editor write.
##   look {season, group, key, value}  one ground look field (number or JSON array text).
##   look_color {season, index, hex}   a zone colour from sRGB hex text.
##   look_add                          gives the biome a default ground look.
##   look_open {on}                    shows the look editor in the inspector's place.
##   compare {kind, season, library, biome}   the A/B view against saved / season / biome.
##   compare_off                       the A/B view off.
##   divider {frac}                    the divider at that share (0..1) of the map's width.
##   lock_all {on}, lock {rule, on}, focus {rule}   the locks and "show only this".
##   state                             logs the season, the compare, the painted split, the bakes.
##   share {rules}                     logs how many instances each painted biome holds.


static func run(base: Node, step: Dictionary) -> String:
	var controller: AuthoringController = base.get("_authoring_controller")
	if controller == null or controller.designer == null:
		return "no designer open"
	var designer := controller.designer
	var session := designer.session
	var model := session.model
	var action := String(step.get("action", ""))
	match action:
		"add_season":
			return str(DesignerSeasonEdits.add_season(model, String(step.id)))
		"season":
			var at := model.season_ids().find(String(step.id))
			session.set_season(at)
			return "season %s index %d runtime %s" % [step.id, at, session.runtime_biome_id()]
		"season_rule":
			var value: Variant = step.get("value")
			return str(
				DesignerSeasonEdits.set_rule_field(
					model, String(step.rule), String(step.season), String(step.field), value
				)
			)
		"season_hide":
			return str(
				DesignerSeasonEdits.set_present(
					model, String(step.rule), String(step.season), bool(step.get("on", false))
				)
			)
		"season_ground":
			return str(
				DesignerSeasonEdits.set_ground(
					model, String(step.season), String(step.field), step.get("surface")
				)
			)
		"season_density":
			return str(
				DesignerSeasonEdits.set_density_scale(
					model, String(step.season), String(step.size_class), step.get("scale")
				)
			)
		"target":
			session.set_edit_season(String(step.get("season", "")))
			return "target '%s'" % session.edit_season
		"look":
			return _look(model, step)
		"look_color":
			var color := Color.html(String(step.hex))
			return str(
				DesignerLookEdits.set_zone_color(
					model, String(step.get("season", "")), int(step.index), color
				)
			)
		"look_add":
			return str(DesignerLookEdits.add_look(model))
		"look_open":
			designer.ui.show_look(bool(step.get("on", true)))
			return "look editor %s" % designer.ui.look_open()
		"compare":
			var made := session.compare.start(step)
			return "compare %s" % JSON.stringify(made)
		"compare_off":
			session.compare.stop()
			return "compare off"
		"divider":
			return _divider(session, step)
		"section":
			var wanted := String(step.name)
			var panel: Node = designer.ui.look_editor if step.get("in") == "look" else designer.ui.inspector
			for foldout in panel.find_children("*", "Foldout", true, false):
				(foldout as Foldout).expanded = foldout.name == wanted
			return "section %s open" % wanted
		"inspector_scroll":
			var scroll := designer.ui.find_child("InspectorScroll", true, false) as ScrollContainer
			scroll.scroll_vertical = int(step.get("to", 100000))
			return "inspector scrolled to %d" % scroll.scroll_vertical
		"query":
			var field_value: Variant = step.get("value")
			var changed := model.set_query_field(String(step.rule), String(step.field), field_value)
			return "query %s.%s = %s: %s" % [step.rule, step.field, str(field_value), changed]
		"search":
			designer.ui.picker.search_for(String(step.get("text", "")))
			return "search '%s', %d tiles" % [step.get("text", ""), designer.ui.picker.shown_count()]
		"lock_all":
			return str(DesignerLocks.set_all(model, bool(step.get("on", true))))
		"lock":
			return str(model.set_locked(String(step.rule), bool(step.get("on", true))))
		"focus":
			session.set_focus(String(step.get("rule", "")))
			return "focus '%s'" % session.focus_rule
		"state":
			return _state(controller, session)
		"rebake":
			controller.editor.terrain.refresh_ground_look()
			return "rebaked"
		"surfaces":
			return "ground %s\nrules %s" % [
				str(PaletteLibrary.surfaces_with_role("ground")), str(model.rule_keys())
			]
		"share":
			return _share(controller, session)
	return "unknown action"


static func _look(model: BiomeDesignerModel, step: Dictionary) -> String:
	var value: Variant = step.get("value")
	if value is String and String(value).begins_with("["):
		value = JSON.parse_string(String(value))
	elif value is String and String(value).is_valid_float():
		value = String(value).to_float()
	var ok := DesignerLookEdits.set_value(
		model, String(step.get("season", "")), String(step.group), String(step.key), value
	)
	return "%s %s.%s = %s" % ["ok" if ok else "no change", step.group, step.key, str(value)]


static func _divider(session: BiomeDesignerSession, step: Dictionary) -> String:
	var compare := session.compare
	if not compare.active:
		return "compare is off"
	var span := DesignerSplit.span(session.controller.document, compare.right)
	var t := lerpf(span.x, span.y, float(step.get("frac", 0.5)))
	compare.move_divider(t, false)
	return "divider t %.2f of %s, screen x %.0f" % [t, str(span), compare.viewport_x()]


static func _state(controller: AuthoringController, session: BiomeDesignerSession) -> String:
	var doc := controller.document
	var lines := PackedStringArray()
	lines.append(
		(
			"season %s (%d of %d) runtime %s laid %s"
			% [
				session.season_id(),
				session.season_index + 1,
				session.model.season_ids().size(),
				session.runtime_biome_id(),
				str(doc.biome_ids)
			]
		)
	)
	var biome := PaletteLibrary.biome(session.runtime_biome_id())
	lines.append(
		(
			"palette ground %s accents %d, doc base surface %s, def seasons %s"
			% [
				biome.get("ground_surface"),
				(biome.get("ground_accents", []) as Array).size(),
				doc.base_surface,
				JSON.stringify(session.model.season_list())
			]
		)
	)
	var look := PaletteLibrary.ground_look(session.runtime_biome_id())
	if not look.is_empty():
		lines.append("palette look colours %s" % JSON.stringify(look["zones"]["colors_linear"]))
	var slots := {}
	for value in doc.biome_slots:
		slots[value] = int(slots.get(value, 0)) + 1
	lines.append("painted samples by slot: %s of %d" % [str(slots), doc.sample_count()])
	if session.compare.active:
		lines.append(
			(
				"compare: %s vs %s, divider t %.2f, draft share %.2f"
				% [
					session.compare.reference.get("kind"),
					session.compare.reference_runtime(),
					session.compare.divider_t,
					session.compare.draft_share()
				]
			)
		)
	var terrain := controller.editor.terrain if controller.editor != null else null
	if is_instance_valid(terrain) and terrain.ground_look() != null:
		var bake := terrain.ground_look()
		lines.append(
			"look bakes %d, biomes %s, last cpu %d us" % [bake.bakes, str(bake.biomes()), bake.last_bake_usec]
		)
	lines.append("stats " + JSON.stringify(session.stats))
	return "\n".join(lines)


static func _share(controller: AuthoringController, session: BiomeDesignerSession) -> String:
	var held := ScatterRefresh.counts(controller.scatter)
	var by_biome := {}
	for asset_id: String in held["counts"]:
		var biome := String(asset_id.get_slice("/", 0))
		by_biome[biome] = int(by_biome.get(biome, 0)) + int(held["counts"][asset_id])
	return "instances by biome %s (draft %s)" % [str(by_biome), session.runtime_biome_id()]
