class_name DesignerPickerHint
extends VBoxContainer

## The asset picker's empty state (step S9): when the filters match no group, what to relax (each
## picked tag, category, the search text or the slot's role, with how many groups the picker would
## then show; DesignerCatalog.relax), and "Request asset", which puts a line describing the plant
## that is missing on the clipboard (the game has no network to send it with). Clicking a
## suggestion relaxes that condition. Hidden while the picker has tiles.

## A suggestion was clicked: (kind, value), as DesignerCatalog.relax names them.
signal relax_requested(kind: String, value: String)

const MAX_SUGGESTIONS := 3

var _words: Label
var _suggestions: HFlowContainer
var _request: Button
var _request_text: String = ""


func _init() -> void:
	name = "EmptyHint"
	visible = false
	_words = DesignerRows.caption("HintWords", "")
	add_child(_words)
	_suggestions = HFlowContainer.new()
	_suggestions.name = "Suggestions"
	add_child(_suggestions)
	_request = Button.new()
	_request.name = "RequestAsset"
	_request.text = "Request asset"
	_request.tooltip_text = (
		"Copy a line describing the plant you did not find, to send to whoever makes plants."
	)
	_request.pressed.connect(_on_request)
	add_child(_request)


## Shows the hint for filters that found nothing in `all`.
func show_for(
	all: Array[Dictionary], search: String, categories: Array, tags: Array, role: String
) -> void:
	for child in _suggestions.get_children():
		_suggestions.remove_child(child)
		child.queue_free()
	var found := DesignerCatalog.relax(all, search, categories, tags, role)
	if found.is_empty():
		_words.text = "The catalog has nothing like this."
	else:
		_words.text = "Nothing matches all of that. Try dropping one:"
	for item in found.slice(0, MAX_SUGGESTIONS):
		var chip := DesignerRows.chip(
			"Relax_%s_%s" % [item["kind"], String(item["value"]).validate_node_name()],
			"%s (%d)" % [_phrase(item), int(item["count"])],
			"Drop this condition and show %d group%s." % [item["count"], "" if item["count"] == 1 else "s"]
		)
		chip.pressed.connect(
			func() -> void: relax_requested.emit(String(item["kind"]), String(item["value"]))
		)
		_suggestions.add_child(chip)
	_request_text = DesignerCatalog.request_text(search, categories, tags, role)
	visible = true


func clear() -> void:
	visible = false


## The line "Request asset" copies.
func request_text() -> String:
	return _request_text


func _phrase(item: Dictionary) -> String:
	match String(item["kind"]):
		"tag":
			return "without the tag %s" % item["value"]
		"category":
			return "without the category %s" % item["value"]
		"search":
			return "without '%s'" % item["value"]
	return "for any role"


func _on_request() -> void:
	DisplayServer.clipboard_set(_request_text)
	UIManager.show_toast("Copied: %s" % _request_text, UIManager.TOAST_INFO, 5.0)
