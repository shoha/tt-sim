class_name DesignerAssetTile
extends Control

## One catalog asset (or one group of variants) in the designer's asset picker: a picture (the
## catalog's thumbnail when the library ships one, else the category's icon on a plain tile), its
## name, its triangle count tinted by the asset budget, and a badge counting the rules that
## already use it. Click selects, double-click adds it to the selected rule, and a drag carries
## {"type": "library_asset", "ref"} to a rule chip or a slot (the slot list accepts it). Drawn by
## hand from the theme's roles: nothing here sets a colour or a size of its own.

signal activated(ref: String)
signal selected_by_click(ref: String)

const TILE_SIZE := Vector2(104.0, 108.0)
const ICON_SIZE := 36.0
const PAD := 6.0
const BADGE_RADIUS := 10.0
const RING_WIDTH := 3.0
const CATEGORY_ICONS := {
	"tree": "trees",
	"bush": "leaf",
	"ground_cover": "grain",
	"flower": "sparkles",
	"deadwood": "tree-falling",
	"rock": "mountain",
	"prop": "home",
	"structure": "home",
	"other": "target",
}
const DRAG_TYPE := "library_asset"

## What the tile stands for: {ref (the id to put in a query: an asset id, or a group key for a
## tile of variants), name, category, subtype, tags, size_class, triangles, variants, library,
## thumb (an absolute file or "")}.
var info: Dictionary = {}
var used_by: int = 0
var chosen: bool = false

var _hover: bool = false
var _icon: Texture2D = null
var _thumb: Texture2D = null


func _init() -> void:
	custom_minimum_size = TILE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE


func setup(tile_info: Dictionary, uses: int = 0) -> void:
	info = tile_info
	used_by = uses
	_icon = IconButton.load_icon(
		String(CATEGORY_ICONS.get(info.get("category", "other"), "target"))
	)
	var thumb := String(info.get("thumb", ""))
	if thumb != "" and FileAccess.file_exists(thumb):
		var image := Image.load_from_file(thumb)
		if image != null and not image.is_empty():
			_thumb = ImageTexture.create_from_image(image)
	tooltip_text = _tooltip()
	queue_redraw()


func set_used_by(count: int) -> void:
	if count != used_by:
		used_by = count
		queue_redraw()


func set_chosen(on: bool) -> void:
	if on != chosen:
		chosen = on
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			selected_by_click.emit(String(info.get("ref", "")))
			if button.double_click:
				activated.emit(String(info.get("ref", "")))
			accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	selected_by_click.emit(String(info.get("ref", "")))
	var preview := Label.new()
	preview.text = String(info.get("name", ""))
	preview.theme_type_variation = &"Chip"
	if get_viewport() != null and get_viewport().gui_is_dragging():
		set_drag_preview(preview)
	else:
		preview.free()
	return {"type": DRAG_TYPE, "ref": info.get("ref", ""), "name": info.get("name", "")}


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hover = true
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hover = false
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var fill_role := ThemeColors.SURFACE_HOVER if _hover else ThemeColors.SURFACE_INSET
	draw_rect(rect, ThemeColors.of(self, fill_role))
	if chosen:
		draw_rect(
			rect.grow(-RING_WIDTH * 0.5), ThemeColors.of(self, ThemeColors.STATE), false, RING_WIDTH
		)
	var soft := ThemeColors.of(self, ThemeColors.TEXT_SOFT)
	var picture := Rect2(PAD, PAD, size.x - 2.0 * PAD, size.y - 52.0)
	if _thumb != null:
		draw_texture_rect(_thumb, picture, false)
	elif _icon != null:
		var at := picture.get_center() - Vector2(ICON_SIZE, ICON_SIZE) * 0.5
		draw_texture_rect(_icon, Rect2(at, Vector2(ICON_SIZE, ICON_SIZE)), false, soft)
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size() - 2
	var text := ThemeColors.of(self, ThemeColors.TEXT)
	var label := _fit(font, font_size, String(info.get("name", "")), size.x - 2.0 * PAD)
	draw_string(font, Vector2(PAD, size.y - 30.0), label, 0, -1, font_size, text)
	var triangles := int(info.get("triangles", 0))
	var level := DesignerBudget.asset_level(String(info.get("category", "")), triangles)
	var role := {
		"ok": ThemeColors.TEXT_SOFT, "amber": ThemeColors.WARNING, "red": ThemeColors.DANGER
	}
	var variants := int(info.get("variants", 1))
	var detail := "%s tris" % DesignerBudget.short(float(triangles))
	if variants > 1:
		detail += "  x%d" % variants
	draw_string(
		font,
		Vector2(PAD, size.y - 10.0),
		detail,
		0,
		-1,
		font_size,
		ThemeColors.of(self, role[level])
	)
	if used_by > 0:
		var centre := Vector2(size.x - PAD - BADGE_RADIUS, PAD + BADGE_RADIUS)
		draw_circle(centre, BADGE_RADIUS, ThemeColors.of(self, ThemeColors.STATE))
		var count := str(used_by)
		var width := font.get_string_size(count, 0, -1, font_size).x
		var on_state := ThemeColors.of(self, ThemeColors.ON_STATE)
		draw_string(
			font,
			centre + Vector2(-width * 0.5, font_size * 0.36),
			count,
			0,
			-1,
			font_size,
			on_state
		)


func _tooltip() -> String:
	var lines: Array[String] = [String(info.get("name", ""))]
	var category := DesignerSlots.category_label(String(info.get("category", "")))
	var kind := "%s / %s, %s class" % [category, info.get("subtype", ""), info.get("size_class", "")]
	lines.append(kind)
	var tags: Array = info.get("tags", [])
	if not tags.is_empty():
		lines.append("tags: " + ", ".join(PackedStringArray(tags)))
	lines.append(
		(
			"%d triangles (LOD0), %d variant(s)"
			% [int(info.get("triangles", 0)), int(info.get("variants", 1))]
		)
	)
	lines.append("from " + String(info.get("library", "")))
	lines.append("Click to select, double-click to add to the selected rule, drag onto a rule.")
	return "\n".join(PackedStringArray(lines))


static func _fit(font: Font, font_size: int, text: String, width: float) -> String:
	if font.get_string_size(text, 0, -1, font_size).x <= width:
		return text
	var cut := text
	while cut.length() > 1 and font.get_string_size(cut + "...", 0, -1, font_size).x > width:
		cut = cut.substr(0, cut.length() - 1)
	return cut + "..."
