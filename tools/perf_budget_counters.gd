extends RefCounted

## The performance budget (topic perfguard): deterministic counters that hold the wins of the
## 2026-11 performance audit (docs/PERFORMANCE.md "Performance audit 2026-11") without a GPU and
## without timing, so they run in the gate and on CI's runners alike. Each counter is a quantity
## the audit found to drive a cost (bytes a client receives, mesh surfaces a token draws, nodes a
## token adds, collision tiles a stroke rebuilds, what a shader writes or fetches) or a setting a
## win depends on, read from the real code paths with no window.
##
## A row is {"id", "counter", "value", "limit", "op" ("max" or "min"), "unit", "measured" (the
## value this counter read when the guard was set, and the audit's before and after), "finding"}.
## Limits sit at about 1.5 times the measured value where a count can grow a little without
## undoing a win, and at the measured value where any growth is the regression (a write the
## pre-pass must not run, a fetch the lean shader dropped). tests/unit/test_perf_budget.gd asserts
## every row; tools/perf_budget.gd prints the table.
##
## What this cannot guard: GPU and CPU milliseconds (a headless run draws nothing, and timings on
## a shared or CI machine are noise), so a shader that got dearer without writing a new output, or
## a frame that got slower by work these counters do not see, passes here. The pinned procedure in
## docs/PERFORMANCE.md "How to measure without fooling yourself" stays the judge of those.

const LIMITS := {
	"net_add_bytes": 600.0,
	"net_full_bytes": 5100.0,
	"net_idle_bytes": 0.0,
	"net_drag_bytes": 90.0,
	"avatar_surfaces": 4.0,
	"avatar_nodes": 21.0,
	"pack_nodes": 31.0,
	"token_scene_bytes": 375.0,
	"spawn_budget_ms": 4.0,
	"pop_in_span_s": 1.5,
	"fade_token_cap": 256.0,
	"covered_max_fps": 240.0,
	"stroke_tiles": 12.0,
	"dab_tiles": 6.0,
	"ground_prepass_writes": 0.0,
	"ground_blend_roughness": 0.0,
	"skirt_shadowed": 0.0,
	"ground_cover_fetches": 0.0,
	"ground_priority": 1.0,
	"global_uniform_slots": 262144.0,
	"default_shadow_tier": float(RenderingServer.SHADOW_QUALITY_SOFT_HIGH),
	"default_shadow_cascades": float(ShadowCascades.BLENDED),
	"default_foliage_edges": float(FoliageEdges.SMOOTH),
}

## Tokens on the table for the net counters, laid out on the perfaudit net harness's 1.25 m grid.
const NET_TOKENS := 200
## The avatar the token counters build (test_avatar_figure_bake's figure: three parts).
const AVATAR_RECIPE := {
	"format": 1,
	"parts": {"body": "body_a", "head": "head_round", "hair": "hair_bun"},
	"colours": {"skin": 1, "hair": 0, "eyes": 0, "primary": 0, "secondary": 1, "accent": 2},
	"face": {"eyes": 1, "brows": 1, "mouths": 0, "marks": 0},
	"proportions": {"height": 0.5, "build": 0.45, "head": 0.55},
	"stance": "stance_ready",
}
## A 320 ft map, the largest the audit measured: 391 x 391 height samples, 169 collision tiles.
const MAP_CELLS := Vector2i(64, 64)
## The shipped ground shaders (play and authoring, map and skirt) and the ground-cover shaders.
const GROUND_SHADERS: Array[String] = [
	"res://shaders/authored_ground.gdshader",
	"res://shaders/authored_ground_looked.gdshader",
	"res://shaders/authored_ground_skirt.gdshader",
	"res://shaders/authored_ground_skirt_looked.gdshader",
]
const SKIRT_SHADERS: Array[String] = [
	"res://shaders/authored_ground_skirt.gdshader",
	"res://shaders/authored_ground_skirt_looked.gdshader",
]
const GROUND_COVER_SHADERS: Array[String] = [
	"res://shaders/wind_foliage_ground.gdshader",
	"res://shaders/wind_foliage_ground_no_aa.gdshader",
]
## Fragment outputs that make Forward+'s normal-roughness pre-pass run the code feeding them
## (docs/PERFORMANCE.md "Ground pre-pass": NORMAL, ROUGHNESS and NORMAL_MAP each 0.43 ms of a
## probe loop's pre-pass, ALBEDO and the light() varyings nothing).
const PREPASS_OUTPUTS := ["NORMAL", "NORMAL_MAP"]


## Every row, in table order. `parent` is a node in the tree the token counters build under
## (an avatar token waits on the current scene when it enters the tree).
static func rows(parent: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(net_rows())
	out.append_array(token_rows(parent))
	out.append_array(authoring_rows())
	out.append_array(render_rows())
	return out


## True when the row's value is within its limit.
static func ok(row: Dictionary) -> bool:
	if row.op == "min":
		return float(row.value) >= float(row.limit)
	return float(row.value) <= float(row.limit)


## The failure message for a row: what it counts, the value against the budget, where the
## number came from.
static func message(row: Dictionary) -> String:
	return (
		"%s: %s %s against a budget of %s %s %s (%s; %s)"
		% [
			row.counter,
			_num(row.value),
			row.unit,
			"at most" if row.op == "max" else "at least",
			_num(row.limit),
			row.unit,
			row.measured,
			row.finding,
		]
	)


## The rows as a plain-text table for people.
static func table(table_rows: Array[Dictionary]) -> String:
	var lines := PackedStringArray()
	lines.append("%-58s %8s %12s  %s" % ["counter", "value", "limit", "ok   finding"])
	for row in table_rows:
		var bound: String = ("<= " if row.op == "max" else ">= ") + _num(row.limit)
		lines.append(
			(
				"%-58s %8s %12s  %-4s %s"
				% [row.counter, _num(row.value), bound, "ok" if ok(row) else "OVER", row.finding]
			)
		)
	return "\n".join(lines)


# =============================================================================
# NET (F-net-1, F-net-2, F-net-7; docs/PERFORMANCE.md "Token sync bytes")
# =============================================================================


## Bytes of a placement's message, the table state, an idle reconciliation and one drag update.
static func net_rows() -> Array[Dictionary]:
	var state := _net_state(NET_TOKENS)
	var tokens: Dictionary = state.tokens
	var last_id: String = tokens.keys()[-1]
	var add := {"tokens": {last_id: tokens[last_id]}, "permissions": {}, "drag_locks": {}}
	var add_bytes := TokenStateWire.encode(add, TokenStateWire.Kind.ADD).size()
	var full_bytes := TokenStateWire.encode(state, TokenStateWire.Kind.FULL).size()
	var transforms := {}
	var index := 0
	for network_id: String in tokens:
		transforms[network_id] = TokenTransformPack.floats_of(
			_grid_position(index), Vector3.ZERO, Vector3.ONE
		)
		index += 1
	var dirty := TokenTransformPack.DirtySet.new()
	dirty.mark_sent(transforms)
	var idle_bytes := 0
	for message_bytes in TokenTransformPack.encode(dirty.take_changed(transforms)):
		idle_bytes += message_bytes.size()
	var one := {last_id: transforms[last_id]}
	var drag := TokenTransformPack.encode(one, TokenTransformPack.UNRELIABLE_BYTES)
	return [
		_row(
			"net_add_bytes",
			"One placement's message, 200 tokens on the table",
			add_bytes,
			"B",
			(
				"set at 395 B (pack token, no RPC header); the whole state per placement was"
				+ " 96,448 B, harness 423 B after"
			),
			"F-net-1, 7dd96e6c"
		),
		_row(
			"net_full_bytes",
			"Table state at 200 tokens (late join, heartbeat)",
			full_bytes,
			"B",
			"set at 3,399 B (pack tokens); harness 153,664 -> 4,715 B (avatars)",
			"F-net-1, 7dd96e6c"
		),
		_row(
			"net_idle_bytes",
			"Reconciliation bytes for a table at rest",
			idle_bytes,
			"B",
			"200 tokens: 128,000 B per 10 s per client before, 0 after",
			"F-net-2, 7a96ccd4"
		),
		_row(
			"net_drag_bytes",
			"One token's drag update",
			drag[0].size() if drag.size() == 1 else 1 << 20,
			"B",
			"set at 60 B (63 B with the RPC header); the Variant RPC was 128 B",
			"F-net-7, 835d75b7"
		),
	]


# =============================================================================
# TOKENS (F-tokens-2, -4, -8, -1; F-system-3)
# =============================================================================


## Mesh surfaces and nodes an avatar and a pack token add, the token scene's size, and the spawn
## queue, pop-in and fade bounds.
static func token_rows(parent: Node) -> Array[Dictionary]:
	var avatar := AvatarTokenFactory.create(AVATAR_RECIPE, "Plum")
	parent.add_child(avatar)
	var avatar_surfaces := draw_surfaces(avatar)
	var avatar_nodes := node_count(avatar)
	avatar.free()
	var pack_nodes := -1
	var path: String = AssetManager.resolve_model_path("beasts", "cow", "default")
	if path != "":
		var pack := BoardTokenFactory._create_from_model_path(path, "beasts", "cow")
		parent.add_child(pack)
		pack_nodes = node_count(pack)
		pack.free()
	var scene_path := BoardTokenFactory.BoardTokenScene.resource_path
	var scene_bytes := FileAccess.get_file_as_bytes(scene_path).size()
	return [
		_row(
			"avatar_surfaces",
			"Mesh surfaces an avatar token draws",
			avatar_surfaces,
			"",
			(
				"set at 3 (one baked mesh, a surface per part); skinned about 15 draws per avatar"
				+ " (500: 8,124 -> 449 draws)"
			),
			"F-tokens-2, 663b7c33"
		),
		_row(
			"avatar_nodes",
			"Nodes an avatar token adds to the tree",
			avatar_nodes,
			"",
			"set at 14; the skinned rig stays off the tree",
			"F-tokens-2, 663b7c33"
		),
		_row(
			"pack_nodes",
			"Nodes a pack token (beasts/cow) adds to the tree",
			pack_nodes if pack_nodes >= 0 else 1 << 20,
			"",
			"set at 21 (the tokens stream's census, which counts more, read 29.2 per pack token)",
			"F-tokens-8, 71ba9a9e"
		),
		_row(
			"token_scene_bytes",
			"board_token.tscn on disk",
			scene_bytes,
			"B",
			"set at 250 B; the placeholder scene was 6.1 MB (uncached load 481 -> 0.4 ms)",
			"F-tokens-8, 71ba9a9e"
		),
		_row(
			"spawn_budget_ms",
			"TokenSpawnQueue frame budget",
			TokenSpawnQueue.FRAME_BUDGET_MS,
			"ms",
			"4 ms; 500 tokens placed at once: worst frame 2.7 s -> 33 ms",
			"F-tokens-4, 3355e42c"
		),
		_row(
			"pop_in_span_s",
			"Last pop-in delay of a 500-token load",
			TokenSpawnQueue.pop_in_delay(499, 500),
			"s",
			"1.5 s; it was 0.05 s per index (25 s at 500)",
			"F-tokens-4, 3355e42c"
		),
		_row(
			"fade_token_cap",
			"Occlusion fade token cap (collect and publish CPU)",
			OcclusionFadeManager.MAX_TOKENS,
			"",
			"256; publish 2.4 ms at 500 uncapped, about 1.2 ms at the cap (inferred)",
			"F-tokens-1, 823f69a0"
		),
		_row(
			"covered_max_fps",
			"Frame cap while the loading sheet covers the table",
			LoadPacing.COVERED_MAX_FPS,
			"fps",
			"240; uncapped, the cover spun 3,500 frames of 0.5 ms",
			"F-system-3, 42a1dfe9"
		),
	]


# =============================================================================
# AUTHORING (F-authoring-4)
# =============================================================================


## Collision tiles a stroke and a dab rebuild on a 320 ft map.
static func authoring_rows() -> Array[Dictionary]:
	var doc := MapDocument.create_flat(MAP_CELLS, "grass", "perf_budget", 7)
	var collision := TerrainCollision.new()
	collision.build(doc)
	var centre := Vector2i(doc.samples_x(), doc.samples_z()) / 2
	# A 20 m x 8 m stroke (80 x 32 samples at the 0.25 m step) and a 4 m dab, at the centre.
	collision.mark(Rect2i(centre - Vector2i(40, 16), Vector2i(80, 32)))
	var stroke_tiles := collision.flush(doc)
	collision.mark(Rect2i(centre - Vector2i(8, 8), Vector2i(16, 16)))
	var dab_tiles := collision.flush(doc)
	var total := collision.tile_count()
	collision.free()
	return [
		_row(
			"stroke_tiles",
			"Collision tiles a 20 m x 8 m stroke rebuilds (320 ft)",
			stroke_tiles,
			"",
			"set at 8 of %d; the whole 391 x 391 shape was rebuilt (6.9 ms -> 0.6 ms)" % total,
			"F-authoring-4, 0ebb674c"
		),
		_row(
			"dab_tiles",
			"Collision tiles a 4 m dab rebuilds (320 ft)",
			dab_tiles,
			"",
			"set at 4 of %d" % total,
			"F-authoring-4, 0ebb674c"
		),
	]


# =============================================================================
# RENDER (F-gpu-2, groundskirt, F-foliage-1, F-foliage-5, shadowtier)
# =============================================================================


## What the ground, skirt and ground-cover shaders write and fetch, and the settings the frame
## budget leans on.
static func render_rows() -> Array[Dictionary]:
	var prepass_writes := 0
	var blend_roughness := 0
	for path in GROUND_SHADERS:
		var body := function_body(active_code(path), "fragment")
		for output: String in PREPASS_OUTPUTS:
			prepass_writes += assignments(body, output).size()
		for rhs in assignments(body, "ROUGHNESS"):
			if RegEx.create_from_string("\\broughness\\b").search(rhs) != null:
				blend_roughness += 1
	var shadowed := 0
	for path in SKIRT_SHADERS:
		if not render_modes(active_code(path)).has("shadows_disabled"):
			shadowed += 1
	var fetches := 0
	for path in GROUND_COVER_SHADERS:
		fetches += sampler_fetches(active_code(path), ["orm_texture", "normal_texture"])
	var slots: int = ProjectSettings.get_setting(
		"rendering/limits/global_shader_variables/buffer_size", 0
	)
	return [
		_row(
			"ground_prepass_writes",
			"NORMAL / NORMAL_MAP writes in the ground's fragment()",
			prepass_writes,
			"",
			"0; writing them ran the layer blend in the pre-pass: 1.41 -> 0.72 ms at home",
			"F-gpu-2, 23805b34"
		),
		_row(
			"ground_blend_roughness",
			"ROUGHNESS writes from the ground's layer blend",
			blend_roughness,
			"",
			"0; the pre-pass gets the wet line only, light() the blended roughness",
			"F-gpu-2, 23805b34"
		),
		_row(
			"skirt_shadowed",
			"Skirt shaders that receive shadows",
			shadowed,
			"",
			"0; shadows_disabled saves 0.49 ms at full zoom-out, 0.13 at home",
			"groundskirt, 33647fd0"
		),
		_row(
			"ground_cover_fetches",
			"ORM / normal-map fetches in the ground-cover shaders",
			fetches,
			"",
			"0; the lean light saves 0.18 ms at home, 0.54 at zoom 20 (320 ft)",
			"F-foliage-1, 304bf738"
		),
		_row(
			"ground_priority",
			"Ground and skirt render_priority (after the foliage's 0)",
			AuthoredTerrain.GROUND_RENDER_PRIORITY,
			"",
			"1; the pre-pass shades the ground only where no card covers it: -0.33 ms",
			"F-gpu-2, 23805b34",
			"min"
		),
		_row(
			"global_uniform_slots",
			"Global shader uniform buffer slots",
			slots,
			"",
			"262,144; 65,536 overflowed at 4,000-4,500 wind instances",
			"F-foliage-5, aa499807",
			"min"
		),
		_row(
			"default_shadow_tier",
			"Default shadow quality tier (High = 4)",
			SettingsMenu.DEFAULT_SHADOW_QUALITY,
			"",
			"High; Ultra costs 0.53-0.63 ms more for no visible gain",
			"shadowtier"
		),
		_row(
			"default_shadow_cascades",
			"Default shadow cascades (Blended = 0)",
			ShadowCascades.DEFAULT,
			"",
			"Blended, the shipped look; Unblended saves 0.4-0.5 ms, Single 0.5-1.0, board first",
			"gpuoptions"
		),
		_row(
			"default_foliage_edges",
			"Default foliage edges under MSAA (Smooth = 0)",
			FoliageEdges.DEFAULT,
			"",
			"Smooth, the shipped look; Fast saves about 0.6 ms with MSAA on, board first",
			"gpuoptions"
		),
	]


# =============================================================================
# HELPERS
# =============================================================================


## Mesh surfaces `root`'s visible geometry draws: each surface of a MeshInstance3D is a draw,
## any other GeometryInstance3D (a label, a sprite) one.
static func draw_surfaces(root: Node) -> int:
	var count := 0
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if not geometry.is_visible_in_tree():
			continue
		if geometry is MeshInstance3D:
			var mesh := (geometry as MeshInstance3D).mesh
			count += mesh.get_surface_count() if mesh != null else 0
		else:
			count += 1
	return count


## Nodes in `root`'s subtree, `root` included.
static func node_count(root: Node) -> int:
	return root.find_children("*", "", true, false).size() + 1


## The shader at `path` as the compiler sees it: includes inlined, #ifdef / #ifndef / #else
## blocks resolved against `defines` and the #defines met on the way, comments removed. Enough
## for the project's shaders, which use no #if expressions.
static func active_code(path: String, defines: Dictionary = {}) -> String:
	var out := PackedStringArray()
	_preprocess(path, defines.duplicate(), out, 0)
	return "\n".join(out)


## The body of `name`() in `code`, braces matched; "" when there is none.
static func function_body(code: String, name: String) -> String:
	var found := RegEx.create_from_string("void\\s+%s\\s*\\(\\s*\\)\\s*\\{" % name).search(code)
	if found == null:
		return ""
	var depth := 1
	var at := found.get_end()
	while at < code.length() and depth > 0:
		var c := code[at]
		if c == "{":
			depth += 1
		elif c == "}":
			depth -= 1
		at += 1
	return code.substr(found.get_end(), at - found.get_end() - 1)


## The right-hand sides of every assignment to `output` (`=`, `+=`, `*=`, ...) in `code`.
static func assignments(code: String, output: String) -> PackedStringArray:
	var out := PackedStringArray()
	var pattern := RegEx.create_from_string("\\b%s\\s*[-+*/]?=(?!=)([^;]*);" % output)
	for found in pattern.search_all(code):
		out.append(found.get_string(1))
	return out


## Calls of texture(), textureLod() or texelFetch() on any of `samplers` in `code`.
static func sampler_fetches(code: String, samplers: Array) -> int:
	var pattern := RegEx.create_from_string(
		"\\b(texture|textureLod|texelFetch)\\s*\\(\\s*(%s)\\b" % "|".join(samplers)
	)
	return pattern.search_all(code).size()


## The render modes `code` declares.
static func render_modes(code: String) -> PackedStringArray:
	var out := PackedStringArray()
	for found in RegEx.create_from_string("render_mode\\s+([^;]*);").search_all(code):
		for mode in found.get_string(1).split(","):
			out.append(mode.strip_edges())
	return out


static func _preprocess(
	path: String, defines: Dictionary, out: PackedStringArray, depth: int
) -> void:
	if depth > 8:
		return
	var stack: Array[bool] = []
	var in_block := false
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line := raw
		if in_block:
			var close := line.find("*/")
			if close < 0:
				continue
			line = line.substr(close + 2)
			in_block = false
		var open := line.find("/*")
		if open >= 0:
			var close := line.find("*/", open + 2)
			in_block = close < 0
			line = line.substr(0, open) + ("" if close < 0 else line.substr(close + 2))
		# An include's path holds "res://", so its line keeps everything.
		var comment := line.find("//")
		if comment >= 0 and not line.strip_edges().begins_with("#include"):
			line = line.substr(0, comment)
		var directive := line.strip_edges()
		var active := not stack.has(false)
		if directive.begins_with("#ifdef"):
			stack.append(defines.has(_argument(directive)))
		elif directive.begins_with("#ifndef"):
			stack.append(not defines.has(_argument(directive)))
		elif directive.begins_with("#else"):
			stack[-1] = not stack[-1]
		elif directive.begins_with("#endif"):
			stack.pop_back()
		elif not active:
			continue
		elif directive.begins_with("#define"):
			defines[_argument(directive)] = true
		elif directive.begins_with("#include"):
			_preprocess(directive.get_slice("\"", 1), defines, out, depth + 1)
		else:
			out.append(line)


static func _argument(directive: String) -> String:
	var parts := directive.split(" ", false)
	return parts[1] if parts.size() > 1 else ""


static func _net_state(count: int) -> Dictionary:
	var tokens := {}
	for i in count:
		var state := TokenState.new()
		state.network_id = "1762650000.%d_%d" % [100 + i, (i * 7919) % 100000]
		state.pack_id = "beasts"
		state.asset_id = "cow"
		state.token_name = "Cow %d" % (i + 1)
		state.position = _grid_position(i)
		tokens[state.network_id] = state.to_dict()
	return {"tokens": tokens, "permissions": {}, "drag_locks": {}}


## Token `i`'s place on a 20-wide grid of 1.25 m cells.
static func _grid_position(i: int) -> Vector3:
	return Vector3((i % 20) * 1.25, 0.0, floorf(i / 20.0) * 1.25)


static func _row(
	id: String,
	counter: String,
	value: float,
	unit: String,
	measured: String,
	finding: String,
	op: String = "max"
) -> Dictionary:
	return {
		"id": id,
		"counter": counter,
		"value": value,
		"limit": float(LIMITS[id]),
		"op": op,
		"unit": unit,
		"measured": measured,
		"finding": finding,
	}


static func _num(value: Variant) -> String:
	var f := float(value)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else "%.2f" % f
