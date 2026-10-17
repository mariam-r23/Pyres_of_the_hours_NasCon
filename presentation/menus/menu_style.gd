extends RefCounted
## Shared look for all menus, built in code: dark, cold blue-grey panels,
## pale text, a pale focus edge. Nothing warm or saturated (that is for fire).
## Font sizes scale with the window height so text reads at 720p and 1080p.

const PANEL_BG := Color(0.035, 0.045, 0.065, 0.86)   # dims the clock behind
const BUTTON_BG := Color(0.11, 0.14, 0.19)
const BUTTON_HOVER := Color(0.17, 0.22, 0.29)
const BUTTON_PRESSED := Color(0.08, 0.10, 0.14)
const BUTTON_DISABLED := Color(0.08, 0.09, 0.12)
const FOCUS_EDGE := Color(0.75, 0.85, 0.95)
const TEXT := Color(0.85, 0.90, 0.96)
const TEXT_DIM := Color(0.55, 0.61, 0.69)
const TEXT_DISABLED := Color(0.36, 0.41, 0.48)

const BASE_HEIGHT := 720.0
const TITLE_SIZE := 52
const HEADING_SIZE := 30
const BUTTON_SIZE := 22
const BODY_SIZE := 17


## Font scale for a window height: 1.0 at 720p, 1.5 at 1080p.
static func scale_for(height: float) -> float:
	return clampf(height / BASE_HEIGHT, 1.0, 2.0)


static func _box(bg: Color, edge: Color = Color(0, 0, 0, 0), edge_width: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = edge
	box.set_border_width_all(edge_width)
	box.set_corner_radius_all(4)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


## A Theme for one menu at a given font scale.
static func theme(scale: float) -> Theme:
	var t := Theme.new()
	t.set_stylebox("normal", "Button", _box(BUTTON_BG))
	t.set_stylebox("hover", "Button", _box(BUTTON_HOVER))
	t.set_stylebox("pressed", "Button", _box(BUTTON_PRESSED))
	t.set_stylebox("disabled", "Button", _box(BUTTON_DISABLED))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), FOCUS_EDGE, 2))
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color", "font_pressed_color"]:
		t.set_color(state, "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_DISABLED)
	t.set_font_size("font_size", "Button", int(BUTTON_SIZE * scale))
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", int(BODY_SIZE * scale))
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.06, 0.075, 0.1, 0.95), Color(0.2, 0.25, 0.32), 1))
	return t


## A full-screen dimming backdrop.
static func backdrop() -> ColorRect:
	var rect := ColorRect.new()
	rect.color = PANEL_BG
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	return rect


static func label(text: String, size: int, scale: float, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(size * scale))
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, scale: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 0) * scale
	b.focus_mode = Control.FOCUS_ALL
	return b


## A centered column for a menu's contents.
static func column(scale: float) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", int(12 * scale))
	return col
