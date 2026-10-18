extends Control
## The in-game HUD, built in code for a 1920x1080 canvas: level title and id,
## actions vs par, the sun dial, a bottom action bar (icons, key hints,
## clickable Undo and Restart), the rejection line and the stair / burn hints.
##
## It listens to EventBus signals and reads state through the controller. It
## makes up no game rules: rejection texts and the context hint come from
## main.gd (REJECTION_MESSAGES, context_hint) through setup().

const UiTheme := preload("res://ui/ui_theme.gd")
const Icons := preload("res://ui/icons.gd")
const SunDial := preload("res://ui/sun_dial.gd")
const Sun := preload("res://core/sun.gd")

## Seconds the rejection line stays fully visible, then fades.
const FEEDBACK_HOLD := 2.0
const FEEDBACK_FADE := 0.5

## The action bar: glyph, label, key hint, key the click sends ("" = display only).
const ACTIONS := [
	{"id": "burn", "glyph": "burn", "label": "Burn", "key_hint": "B", "keycode": KEY_NONE},
	{"id": "wait", "glyph": "wait", "label": "Wait", "key_hint": "Space", "keycode": KEY_NONE},
	{"id": "undo", "glyph": "undo", "label": "Undo", "key_hint": "Z", "keycode": KEY_Z},
	{"id": "interact", "glyph": "interact", "label": "Interact", "key_hint": "E", "keycode": KEY_NONE},
	{"id": "restart", "glyph": "restart", "label": "Restart", "key_hint": "R", "keycode": KEY_R},
]

var bus: Node = null
var controller: Node = null
## reason -> friendly text (main.gd REJECTION_MESSAGES).
var messages: Dictionary = {}
## Callable(state, burn_mode) -> String: the stair / burn-mode hint (main.gd context_hint).
var context_hint: Callable = Callable()

var title_label: Label
var id_label: Label
var actions_label: Label
var dial: Control
var feedback_panel: PanelContainer
var feedback_label: Label
var hint_panel: PanelContainer
var hint_label: Label
var action_items: Dictionary = {}  # id -> Button

var _feedback_tween: Tween
var _fade_tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


## Connects to the bus and the controller (call once, after adding the node or before).
func setup(new_bus: Node, new_controller: Node, new_messages: Dictionary, new_context_hint: Callable) -> void:
	bus = new_bus
	controller = new_controller
	messages = new_messages
	context_hint = new_context_hint
	bus.hud_changed.connect(_on_hud_changed)
	bus.sun_advanced.connect(func(_event): update_dial())
	bus.action_rejected.connect(func(event): show_feedback(rejection_text(event.get("reason", ""))))
	for signal_name in ["action_applied", "undo_done", "level_loaded"]:
		bus.connect(signal_name, func(_arg): hide_feedback())
	bus.level_restarted.connect(hide_feedback)
	controller.burn_mode_changed.connect(func(_active): update_hint())


# --- Pure helpers -------------------------------------------------------------

## "Actions 3 / par 10" ("par -" when the level has none).
static func actions_text(used: int, par: int) -> String:
	return "Actions  %d / par %s" % [used, str(par) if par >= 0 else "-"]


## Friendly text for a rejection reason; the raw reason if it is not mapped.
static func rejection_text_for(table: Dictionary, reason: String) -> String:
	return str(table.get(reason, reason))


func rejection_text(reason: String) -> String:
	return rejection_text_for(messages, reason)


# --- Updates ------------------------------------------------------------------

func _on_hud_changed(info: Dictionary) -> void:
	title_label.text = str(info.get("title", ""))
	id_label.text = str(info.get("level_id", ""))
	actions_label.text = actions_text(int(info.get("actions_used", 0)), int(info.get("par", -1)))
	update_dial()
	update_hint()


## Redraws the dial from the controller's state.
func update_dial() -> void:
	var state = controller.current_state() if controller != null else null
	if state == null:
		return
	var per_hour: int = state.actions_per_hour
	var index: int = Sun.sun_index(state)
	var to_next: int = per_hour - (state.action_count % per_hour)
	dial.show_state(index, SunDial.lit_ticks(state.sun_start_index, state.action_count, per_hour), per_hour, to_next)


## Burn-mode and stair hints. Burn mode is a fire moment, so it is ember.
func update_hint() -> void:
	var state = controller.current_state() if controller != null else null
	var text := ""
	if state != null and context_hint.is_valid():
		text = str(context_hint.call(state, controller.burn_mode))
	hint_label.text = text
	hint_panel.visible = text != ""
	var burning: bool = controller != null and controller.burn_mode
	hint_label.add_theme_color_override("font_color", UiTheme.color("ember") if burning else UiTheme.color("text"))
	hint_panel.add_theme_stylebox_override("panel",
		UiTheme.panel_box(UiTheme.color("panel"), UiTheme.color("ember") if burning else UiTheme.color("shadow_dark"), 12))
	_set_item_hot("burn", burning)


func show_feedback(text: String) -> void:
	if _feedback_tween != null:
		_feedback_tween.kill()
	feedback_label.text = text
	feedback_panel.modulate.a = 1.0
	feedback_panel.visible = true
	if not is_inside_tree():
		return
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(FEEDBACK_HOLD)
	_feedback_tween.tween_property(feedback_panel, "modulate:a", 0.0, FEEDBACK_FADE)
	_feedback_tween.tween_callback(func(): feedback_panel.visible = false)


func hide_feedback() -> void:
	if _feedback_tween != null:
		_feedback_tween.kill()
		_feedback_tween = null
	feedback_panel.visible = false


## Fades the whole HUD (the ripple shot hides it). seconds = 0 is immediate.
func fade_to(alpha: float, seconds: float) -> void:
	if _fade_tween != null:
		_fade_tween.kill()
		_fade_tween = null
	if seconds <= 0.0 or not is_inside_tree():
		modulate.a = alpha
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", alpha, seconds)


func _set_item_hot(id: String, hot: bool) -> void:
	var item: Button = action_items.get(id)
	if item == null:
		return
	var accent := UiTheme.color("ember") if hot else UiTheme.color("shadow_dark")
	item.add_theme_stylebox_override("normal", _item_box(accent))
	item.get_node("Glyph").color = UiTheme.color("ember") if hot else UiTheme.color("text")
	item.add_theme_color_override("font_color", UiTheme.color("ember") if hot else UiTheme.color("text"))


# --- Build --------------------------------------------------------------------

func _build() -> void:
	# Top left: title, id, actions.
	var info_panel := PanelContainer.new()
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_panel.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.color("panel"), UiTheme.color("shadow_dark"), 18))
	info_panel.position = Vector2(24, 24)
	info_panel.custom_minimum_size = Vector2(460, 0)
	add_child(info_panel)
	var info_col := VBoxContainer.new()
	info_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_col.add_theme_constant_override("separation", 2)
	info_panel.add_child(info_col)
	title_label = UiTheme.label("", "heading", 34)
	id_label = UiTheme.label("", "body", 22, UiTheme.color("text_dim"))
	actions_label = UiTheme.label(actions_text(0, -1), "body", 32)
	for l in [title_label, id_label, actions_label]:
		info_col.add_child(l)

	# Top right: the sun dial.
	var dial_panel := PanelContainer.new()
	dial_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dial_panel.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.color("panel"), UiTheme.color("shadow_dark"), 8))
	dial_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	dial_panel.offset_left = -24 - 300
	dial_panel.offset_right = -24
	dial_panel.offset_top = 24
	dial_panel.offset_bottom = 24 + 300
	add_child(dial_panel)
	dial = SunDial.new()
	dial_panel.add_child(dial)

	# Top center: the rejection line, and under it the stair / burn hint.
	feedback_panel = _toast_panel(24)
	feedback_label = feedback_panel.get_child(0)
	hint_panel = _toast_panel(96)
	hint_label = hint_panel.get_child(0)
	feedback_panel.visible = false
	hint_panel.visible = false

	# Bottom center: the action bar.
	var bar := PanelContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.color("panel"), UiTheme.color("shadow_dark"), 10))
	# Bottom right, so the bottom left stays free for Cinder's dialogue box.
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_right = -24
	bar.offset_bottom = -24
	add_child(bar)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	for spec in ACTIONS:
		var item := _action_item(spec)
		action_items[spec["id"]] = item
		row.add_child(item)


func _toast_panel(top: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.color("panel"), UiTheme.color("shadow_dark"), 12))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = top
	add_child(panel)
	var label := UiTheme.label("", "body", 32, UiTheme.NONE, HORIZONTAL_ALIGNMENT_CENTER)
	panel.add_child(label)
	return panel


## An action-bar item's look: room on the left for the glyph and on the right for the key.
func _item_box(border: Color) -> StyleBoxFlat:
	var box := UiTheme.panel_box(UiTheme.color("panel"), border, 8)
	box.content_margin_left = 62
	box.content_margin_right = 12
	return box


func _action_item(spec: Dictionary) -> Button:
	var item := Button.new()
	item.text = spec["label"]
	item.focus_mode = Control.FOCUS_NONE  # Space / Enter must never click it
	item.custom_minimum_size = Vector2(196, 68)
	item.alignment = HORIZONTAL_ALIGNMENT_LEFT
	UiTheme.style_button(item, UiTheme.color("shadow_light"))
	item.add_theme_stylebox_override("normal", _item_box(UiTheme.color("shadow_dark")))
	item.add_theme_font_size_override("font_size", 28)
	var glyph := Icons.new()
	glyph.name = "Glyph"
	glyph.kind = spec["glyph"]
	glyph.line_width = 3.0
	glyph.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	glyph.offset_left = 14
	glyph.offset_right = 54
	glyph.offset_top = -20
	glyph.offset_bottom = 20
	item.add_child(glyph)
	var key := UiTheme.label(spec["key_hint"], "body", 22, UiTheme.color("text_dim"), HORIZONTAL_ALIGNMENT_RIGHT)
	key.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	key.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	key.offset_right = -12
	item.add_child(key)
	if int(spec["keycode"]) == KEY_NONE:
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE  # a hint, not a button
	else:
		item.pressed.connect(_on_item_pressed.bind(int(spec["keycode"])))
	return item


## Clicks go through the controller's key handler, so they obey the same
## blockers as the keyboard (menus, the ripple shot).
func _on_item_pressed(keycode: int) -> void:
	if controller != null:
		controller.handle_key(keycode)
