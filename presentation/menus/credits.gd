extends Control
## Credits, built in code from presentation/menus/credits.txt in a scrolling
## panel. Emits chosen("back"). Escape (handled by main.gd) goes back.

const Style := preload("res://presentation/menus/menu_style.gd")

signal chosen(action: String)

const CREDITS_PATH := "res://presentation/menus/credits.txt"
const MISSING_TEXT := "Credits are on their way."
## Pixels per arrow-key press (times the font scale).
const SCROLL_STEP := 40

var _scroll: ScrollContainer = null
var _scale := 1.0


## The credits text, or a short placeholder if the file is missing.
static func read_credits(path: String = CREDITS_PATH) -> String:
	if not FileAccess.file_exists(path):
		return MISSING_TEXT
	var text := FileAccess.get_file_as_string(path).strip_edges()
	return text if text != "" else MISSING_TEXT


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scale := Style.scale_for(get_viewport_rect().size.y)
	_scale = scale
	theme = Style.theme(scale)
	add_child(Style.backdrop())
	var col := Style.column(scale)
	add_child(col)
	col.add_child(Style.label("Credits", Style.HEADING_SIZE, scale))
	var panel := PanelContainer.new()
	col.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(680, 420) * scale
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_scroll = scroll
	var body := Label.new()
	body.text = read_credits()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("font_size", int(Style.BODY_SIZE * scale))
	scroll.add_child(body)
	var back := Style.button("Back", scale)
	back.pressed.connect(func(): chosen.emit("back"))
	col.add_child(back)
	col.add_child(Style.label("Arrows / mouse wheel: scroll    Escape: back", Style.BODY_SIZE, scale, Style.TEXT_DIM))
	back.grab_focus.call_deferred()


## Up / down arrows scroll the text (the Back button keeps focus).
func _input(event: InputEvent) -> void:
	if _scroll == null:
		return
	var step := 0
	if event.is_action_pressed("ui_down", true):
		step = 1
	elif event.is_action_pressed("ui_up", true):
		step = -1
	if step != 0:
		_scroll.scroll_vertical += int(step * SCROLL_STEP * _scale)
		get_viewport().set_input_as_handled()
