extends PanelContainer
## The small win / fail panel: a title and buttons for Next level (N), Retry (R)
## and Undo (Z). Retry and Undo go through the controller's key handler, so they
## obey the same blockers as the keyboard; Next level raises next_requested
## (main.gd loads the next level). Cold colors only.

const UiTheme := preload("res://ui/ui_theme.gd")

signal next_requested

const WON_TITLE := "Level cleared"
const FAILED_TITLE := "The dial ran out"

var controller: Node = null
var title_label: Label
var detail_label: Label
var next_button: Button
var retry_button: Button
var undo_button: Button


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.color("panel"), UiTheme.color("shadow_dark"), 20))
	# In the empty hub between the rooms (the one spot no room covers), buttons stacked.
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_top = 40
	offset_bottom = 40
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	title_label = UiTheme.label("", "heading", 36, UiTheme.NONE, HORIZONTAL_ALIGNMENT_CENTER)
	detail_label = UiTheme.label("", "body", 28, UiTheme.color("text_dim"), HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(title_label)
	col.add_child(detail_label)
	var row := VBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	next_button = _button("Next level  N")
	retry_button = _button("Retry  R")
	undo_button = _button("Undo  Z")
	for b in [next_button, retry_button, undo_button]:
		row.add_child(b)
	next_button.pressed.connect(func(): next_requested.emit())
	retry_button.pressed.connect(func(): _key(KEY_R))
	undo_button.pressed.connect(func(): _key(KEY_Z))
	visible = false


## The buttons a result offers: Next level only after a win with a level after it.
static func button_ids(won: bool, has_next: bool) -> Array:
	var ids: Array = []
	if won and has_next:
		ids.append("next")
	ids.append("retry")
	ids.append("undo")
	return ids


func show_result(won: bool, has_next: bool, detail: String = "") -> void:
	title_label.text = WON_TITLE if won else FAILED_TITLE
	detail_label.text = detail
	detail_label.visible = detail != ""
	var ids := button_ids(won, has_next)
	next_button.visible = "next" in ids
	retry_button.visible = "retry" in ids
	undo_button.visible = "undo" in ids
	visible = true


func hide_panel() -> void:
	visible = false


func _key(keycode: int) -> void:
	if controller != null:
		controller.handle_key(keycode)


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(320, 56)
	UiTheme.style_button(b, UiTheme.color("shadow_light"))
	b.add_theme_font_size_override("font_size", 28)
	return b
