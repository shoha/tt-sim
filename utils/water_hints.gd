class_name WaterHints
extends RefCounted

## The structured authoring hints of the water conditioner (card painter-water-condition): what a
## committed river stroke asked of the author that the plan did not fix by itself, as records
##   {"kind": StringName, "pos": Vector2 (map XZ), "fixes": Array[StringName], "detail": Dictionary}
## so a tool can show them, a test can count them, and nothing blocks the stroke: a hint is only
## ever said, never required. The plan puts them in the `report` dictionary of WaterEdit.plan_river
## ("hints"); WaterEditor.last_hints keeps the last stroke's, and the Water tool toasts the first
## one worth saying (toast_text()) through BrushTool.refused.
##
## Kinds, with what the plan did:
##  - rise_removed: the drawn levels climbed downstream and were lowered to run downhill (said
##    quietly: a note, not worth a toast);
##  - reversed_run: re_fit reversed a stored river that ran uphill;
##  - blocked_cut: conditioning would have cut deeper than WaterConditioner.CUT_LIMIT_M into the
##    drawn ground, so the stroke was kept as drawn;
##  - over_hill: the same, with the deep cut in the middle of the stroke (a stroke over a ridge);
##  - stopped_at_rise: a blocked stroke that would climb as drawn (water standing higher than the
##    water upstream of it) was split where it rises: each part between a crest and a trough
##    lands as its own stream running downhill, a climbing part turned round (card
##    painter-water-climb; `detail.rise_m`, `detail.rises`; WaterEditor.last_report says how
##    many parts landed, `pieces`, and the metres of parts too short to hold water,
##    `dropped_m`). It replaces that stroke's over_hill or blocked_cut hint;
##  - climb: a STORED stroke climbs (WaterField's `climb` event; a map saved before the rule, or a
##    document that was never conditioned): re-fit the water;
##  - perched_head: the stroke's head stands above a lower pond or river within snap reach; it was
##    kept (the water would otherwise be cut down to the pond's level);
##  - end_below_water, end_near_water_below: a stroke end at or short of other water at another
##    level, kept as drawn;
##  - end_snapped: a stroke end was moved into the water it stopped short of (join, inflow, fall
##    into, outlet), by `detail.displacement` metres;
##  - undermined_run: water that its banks cannot hold at the stored levels (the dig refit);
##  - too_short: the one hint that refuses (card painter-water-paths): the line is shorter than
##    its tapered ends need for its depth (WaterEdit.min_river_length), so it would carve ground
##    and land a sliver of water or none; nothing was made (`detail.length_m`, `detail.need_m`).
##  - no_room: a pond would have joined a stream end beside it, but the document holds as many
##    river reaches as it can (MapDocument.MAX_RIVERS, `detail.cap`), so the end was left as
##    drawn (card painter-water-junctions; it was skipped silently).
## Loaded by path from WaterEdit (naming it there would join the start-up script graph,
## test_boot_graph).

## Kinds that are worth a toast (the author may want to act on them), the most telling first: a
## head above a lower pond is why a stroke near it was blocked.
const SAID: Array[StringName] = [
	&"too_short",
	&"perched_head",
	&"stopped_at_rise",
	&"over_hill",
	&"blocked_cut",
	&"end_below_water",
	&"end_near_water_below",
	&"no_room",
	&"undermined_run",
]

## The sentence per kind.
const KIND_TEXT := {
	&"rise_removed": "Part of the river ran uphill; it now runs downhill.",
	&"reversed_run": "A river that ran uphill was turned around to run downhill.",
	&"blocked_cut": "The river was kept as drawn: levelling it would cut a deep gorge.",
	&"over_hill": "The river crosses a hill and was kept as drawn: levelling it would cut a gorge.",
	&"stopped_at_rise": "Water cannot climb: the line was split so each part runs downhill.",
	&"climb": "Part of the river stands higher than the water upstream of it.",
	&"perched_head": "The river starts high above a lower pond and was kept as drawn.",
	&"end_below_water": "The river ends below water of another level and was kept as drawn.",
	&"end_near_water_below": "The river stops short of lower water and was kept as drawn.",
	&"end_snapped": "The end of the river was joined to the water beside it.",
	&"undermined_run": "Part of the river sits above its banks.",
	&"too_short": "That line is too short to hold water this deep, so nothing was made.",
	&"no_room": "The map is full of rivers, so the stream beside the pond was not joined.",
}

## The words of a fix action.
const FIX_TEXT := {
	&"carve_fall": "carve a fall",
	&"move_head": "move the head",
	&"keep_spring": "keep it as a spring",
	&"raise_end": "raise the end",
	&"make_outlet": "make it the pond's outlet",
	&"keep": "keep it as drawn",
	&"extend_to_water": "extend the end into the water",
	&"cut_ridge": "cut the ridge with the Sculpt tool",
	&"draw_from_top": "draw the rest from the top of the rise",
	&"reroute": "route the line around the hill",
	&"re_fit": "re-fit the water",
	&"lower_ground": "lower the banks",
	&"draw_longer": "draw a longer line",
	&"shallower": "pick a shallower depth",
	&"paint_pond": "paint a pond",
	&"erase_water": "erase a river you do not need",
}


## One hint record.
static func make(
	kind: StringName, pos: Vector2, fixes: Array[StringName] = [], detail: Dictionary = {}
) -> Dictionary:
	return {"kind": kind, "pos": pos, "fixes": fixes, "detail": detail}


## The hints a conditioned plan of a river along `course` (reach levels `fit`, from
## WaterConditioner.condition_ranges(); `head` and `tail` the end decisions of WaterPorts) raises.
static func plan_hints(
	course: PackedVector2Array, fit: Dictionary, head: Dictionary, tail: Dictionary
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var at := _at(course, int(fit.get("cut_at", 0)))
	if bool(fit.get("blocked", false)):
		var cut_at := int(fit.get("cut_at", 0))
		var inside := cut_at > 1 and cut_at < course.size() - 2
		var kind := &"over_hill" if inside else &"blocked_cut"
		var fixes: Array[StringName] = []
		fixes.assign(
			[&"cut_ridge", &"reroute", &"keep"] if inside else [&"carve_fall", &"move_head", &"keep"]
		)
		out.append(make(kind, at, fixes, {"cut_m": float(fit.get("max_cut", 0.0))}))
	elif int(fit.get("rises", 0)) > 0:
		var keep: Array[StringName] = [&"keep"]
		out.append(
			make(
				&"rise_removed",
				_at(course, int(fit.get("rise_at", 0))),
				keep,
				{"rises": int(fit.rises), "rise_m": float(fit.rise_m)}
			)
		)
	for end: Dictionary in [head, tail]:
		var action: StringName = end.get("action", &"none")
		if action == &"flag":
			var kind: StringName = end.kind
			kind = &"perched_head" if kind == &"head_above_water" else kind
			out.append(make(kind, end.target, _typed(end.fixes), {"gap_m": float(end.gap)}))
		elif action != &"none":
			out.append(
				make(
					&"end_snapped",
					end.target,
					[],
					{"action": action, "displacement": float(end.displacement)}
				)
			)
	return out


## True when `hints` holds a kind worth a toast.
static func worth_saying(hints: Array) -> bool:
	for hint: Dictionary in hints:
		if SAID.has(hint.kind):
			return true
	return false


## The toast for `hints`: the first hint worth saying, its sentence and the fixes as text
## ("... You can carve a fall, move the head or keep it as drawn."); "" when none is.
static func toast_text(hints: Array) -> String:
	for kind in SAID:
		for hint: Dictionary in hints:
			if hint.kind == kind:
				return describe(hint)
	return ""


## One hint as text: its sentence and, when it has fixes, "You can a, b or c."
static func describe(hint: Dictionary) -> String:
	var text: String = KIND_TEXT.get(hint.kind, String(hint.kind))
	var names: Array[String] = []
	for fix: StringName in hint.fixes:
		names.append(String(FIX_TEXT.get(fix, fix)))
	if names.is_empty():
		return text
	var list := names[0]
	if names.size() > 1:
		list = ", ".join(names.slice(0, names.size() - 1)) + " or " + names[-1]
	return "%s You can %s." % [text, list]


static func _at(course: PackedVector2Array, i: int) -> Vector2:
	return course[clampi(i, 0, course.size() - 1)] if not course.is_empty() else Vector2.ZERO


static func _typed(fixes: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for fix in fixes:
		out.append(fix)
	return out
