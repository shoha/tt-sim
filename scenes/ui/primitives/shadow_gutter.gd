class_name ShadowGutter
extends RefCounted

## Room for the shadow and the focus ring of a button inside a container that clips.
##
## ROOT CAUSE of the clipped button shadows (owner, 2026-10-25: Verify in the collections
## detail panel lost its shadow on the left; "it happens in other places too"): the theme draws a
## raised button with a StyleBoxFlat shadow (paper: size 10, offset 0,4; a Card lifts to 18, 8)
## and a focus ring 4 px outside it (8 on glass, with its halo), and all of that lies OUTSIDE the
## button's rect. A ScrollContainer (also any control with clip_contents or clip_children, which
## ScrollFade sets) clips its children to its own rect, and a container with no margin puts its
## first and last row, and every row at its left and right edge, flush with that rect, so the
## part of the shadow that falls outside is cut. The theme already did it for two grids (the
## CardGrid and LibraryGrid variants carry margins); every other scroll that hosts buttons did
## not. This class is the cure in ONE place, and the audit that finds the rest:
##
##   ShadowGutter.wrap(scroll, kind)   gives a ScrollContainer content margins of the kind's room
##                                     (RING for rows whose only overhang is the focus ring,
##                                     GLASS_RING for the same on glass, BUTTON for raised
##                                     buttons, CARD for cards that lift on hover), so a button
##                                     at any edge of its content keeps its whole shadow;
##   ShadowGutter.violations(node)     walks the nodes under `node` and names every button whose
##                                     shadow or ring a clipping ancestor would cut. The tests
##                                     (test_shadow_gutter.gd) instantiate the screens and sheets
##                                     and call it, so a new panel that forgets to wrap fails
##                                     there, not in a player's hands.
##
## The constants are the largest extents over every theme's buttons in every state, no more,
## pinned by test_shadow_gutter.gd against the themes themselves: a theme change that grows a
## shadow fails there and names the new number.

enum Kind { RING, GLASS_RING, BUTTON, CARD }

## The focus ring: 4 px outside a button on paper, 8 with its halo on glass.
const RING_PX := 4
const GLASS_RING_PX := 8
## A raised button (Secondary, Primary, Danger, Framed): shadow size 10, dropped 4. Left and
## right 10, below 14, above 6 (8, so a glass focus ring is whole there too).
const SIDE := 10
const TOP := 8
const BOTTOM := 14
## A card lifted by the pointer: shadow size 18, dropped 8 (paper) or 12 all round (glass). Left
## and right 18, above 12, below 26.
const CARD_SIDE := 18
const CARD_TOP := 12
const CARD_BOTTOM := 26


## `scroll` with its content held in from every edge by the room of `kind`. Returns `scroll`. The
## content gets narrower by the sides and the scroll needs the top and bottom more height: a
## caller that sized the scroll to its content adds `extra_height(kind)`.
static func wrap(scroll: ScrollContainer, kind: Kind = Kind.BUTTON) -> ScrollContainer:
	var room := margins(kind)
	var box := StyleBoxEmpty.new()
	box.content_margin_left = room.x
	box.content_margin_top = room.y
	box.content_margin_right = room.z
	box.content_margin_bottom = room.w
	scroll.add_theme_stylebox_override(&"panel", box)
	scroll.set_meta(&"shadow_gutter", int(kind))
	return scroll


## `scroll`, wrapped, inside a holder whose negative margins reach out by the room of `kind`: the
## holder takes the place of a scroll that must keep its content exactly where it was (rows that
## line up with their neighbours), while the clip is wider by the room. Add the holder to the
## container in place of the scroll; the scroll stays reachable as the holder's child. The
## holder expands as the scroll does.
static func outset(scroll: ScrollContainer, kind: Kind = Kind.RING) -> MarginContainer:
	ShadowGutter.wrap(scroll, kind)
	var room := margins(kind)
	var holder := MarginContainer.new()
	holder.name = scroll.name + "Outset"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_horizontal = scroll.size_flags_horizontal
	holder.size_flags_vertical = scroll.size_flags_vertical
	holder.add_theme_constant_override(&"margin_left", -int(room.x))
	holder.add_theme_constant_override(&"margin_top", -int(room.y))
	holder.add_theme_constant_override(&"margin_right", -int(room.z))
	holder.add_theme_constant_override(&"margin_bottom", -int(room.w))
	holder.add_child(scroll)
	return holder


## The room of `kind` as (left, top, right, bottom).
static func margins(kind: Kind) -> Vector4:
	match kind:
		Kind.RING:
			return Vector4(RING_PX, RING_PX, RING_PX, RING_PX)
		Kind.GLASS_RING:
			return Vector4(GLASS_RING_PX, GLASS_RING_PX, GLASS_RING_PX, GLASS_RING_PX)
		Kind.CARD:
			return Vector4(CARD_SIDE, CARD_TOP, CARD_SIDE, CARD_BOTTOM)
	return Vector4(SIDE, TOP, SIDE, BOTTOM)


## The height `wrap` adds to a scroll's content.
static func extra_height(kind: Kind = Kind.BUTTON) -> float:
	var room := margins(kind)
	return room.y + room.w


## How far past its rect a Button of `theme` draws, in each state: {left, top, right, bottom}.
## `variation` is its theme_type_variation (a variation without a style of its own takes
## Button's). Covers the normal, hover, pressed, hover_pressed and focus boxes; a disabled
## button is drawn flat.
static func extents_in_theme(theme: Theme, variation: StringName = &"Button") -> Dictionary:
	var out := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus"]:
		var box: StyleBox = null
		if theme.has_stylebox(state, variation):
			box = theme.get_stylebox(state, variation)
		elif theme.has_stylebox(state, &"Button"):
			box = theme.get_stylebox(state, &"Button")
		_grow(out, box)
	return out


## How far past its rect `control` (a Button) draws in each state, from the theme it is under.
static func extents_of(control: Control) -> Dictionary:
	var out := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus"]:
		_grow(out, control.get_theme_stylebox(state))
	return out


static func _grow(out: Dictionary, box: StyleBox) -> void:
	var flat := box as StyleBoxFlat
	if flat == null:
		return
	var size := float(flat.shadow_size) if flat.shadow_color.a > 0.0 else 0.0
	var off := flat.shadow_offset
	out["left"] = maxf(out["left"], flat.expand_margin_left + maxf(size - off.x, 0.0))
	out["top"] = maxf(out["top"], flat.expand_margin_top + maxf(size - off.y, 0.0))
	out["right"] = maxf(out["right"], flat.expand_margin_right + maxf(size + off.x, 0.0))
	out["bottom"] = maxf(out["bottom"], flat.expand_margin_bottom + maxf(size + off.y, 0.0))


## True when `control` clips its children to its rect.
static func clips(control: Control) -> bool:
	return (
		control is ScrollContainer
		or control.clip_contents
		or control.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED
	)


## Every Button under `root` (visible in the tree) whose shadow a clipping ancestor would cut,
## as one sentence each. Positions are compared as laid out now, with each scroll taken at its
## top (and at its end for the lower edge), so the answer does not depend on where the player
## has scrolled. A clipping ancestor that is `root` itself or above it is not examined.
static func violations(root: Node) -> Array[String]:
	var out: Array[String] = []
	for node in root.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if not button.is_visible_in_tree() or button.size.x <= 0.0:
			continue
		var need := extents_of(button)
		var parent := button.get_parent()
		while parent != null and parent != root.get_parent():
			if parent is Control and clips(parent as Control):
				var gap := _gaps(button, parent as Control)
				for side: String in ["left", "top", "right", "bottom"]:
					if float(gap[side]) + 0.01 < float(need[side]):
						out.append(
							(
								"%s: %s needs %.0f px, %s leaves %.0f"
								% [button.get_path(), side, need[side], parent.name, gap[side]]
							)
						)
			parent = parent.get_parent()
	return out


## The room between `button` and each edge of the clip `holder`, scroll at its start for the
## top and left and at its end for the bottom and right.
static func _gaps(button: Control, holder: Control) -> Dictionary:
	var rect := button.get_global_rect()
	var area := holder.get_global_rect()
	var shift := Vector2.ZERO
	var full := area.size
	if holder is ScrollContainer:
		var scroll := holder as ScrollContainer
		shift = Vector2(scroll.scroll_horizontal, scroll.scroll_vertical)
		var panel := scroll.get_theme_stylebox(&"panel")
		var margins_size := panel.get_minimum_size() if panel != null else Vector2.ZERO
		for child in scroll.get_children():
			if child is Control and (child as Control).visible and not child is ScrollBar:
				var wanted := (child as Control).size + margins_size
				full = Vector2(maxf(full.x, wanted.x), maxf(full.y, wanted.y))
	var local := rect.position - area.position + shift
	return {
		"left": local.x,
		"top": local.y,
		"right": full.x - (local.x + rect.size.x),
		"bottom": full.y - (local.y + rect.size.y),
	}
