extends Control
## The ending: after the FINAL level is won, a full-screen dim overlay asks for
## the choice, WIND THE CLOCK or LET IT BURN, then shows a short epilogue and
## only "Press R to play again". Neither choice is labelled good or bad.
##
## Select with arrows + Enter, by mouse, or with keys 1 and 2 (main.gd turns
## those into EventBus.ending_chosen). Every path ends in one signal,
## EventBus.ending_chosen(choice), which this screen also listens to, so the
## epilogue always follows the signal. Cinder's own ending lines (a3_wind_*,
## a3_burnend_*) arrive through the dialogue box on that same signal.
## WIND uses the cold indigo; LET IT BURN is the one place ember is the main accent.

const UiTheme := preload("res://ui/ui_theme.gd")

## Everything the player reads here, in one place so it is easy to edit.
const TEXTS := {
	"title": "THE CENTER OF THE DIAL",
	"setup": [
		"You stand where every hour begins. The dial is bare, and the wick is still warm.",
		"Your order built this tower around her, and you have carried her fire all the way up.",
		"Wind the clock, and the day goes on. Let it burn, and she does.",
	],
	"hint": "Left / Right to choose, Enter to confirm, or press 1 or 2",
	"choices": {
		"wind": {"label": "WIND THE CLOCK", "sub": "Duty. The day goes on."},
		"burn": {"label": "LET IT BURN", "sub": "Her. The hours end."},
	},
	"again": "Press R to play again",
}
const EPILOGUES := {
	"wind": {
		"title": "THE CLOCK WINDS",
		"lines": [
			"The key turns, and every gear remembers its work.",
			"The day goes on, bell by bell, as though nothing had ever asked it not to.",
			"Far below, a flame is bound again and put out, gently, the way a lamp is.",
			"The shadows lift from the hours and fade into ordinary dusk.",
			"You are the Clockkeeper. The tower is saved. It is very quiet.",
		],
	},
	"burn": {
		"title": "THE HOURS BURN",
		"lines": [
			"You let the last hour fall, and the Pyre does the rest.",
			"The fire climbs out of the clock, free at last, and does not look back.",
			"Twelve, two, four, six, eight, ten: each hour goes out like a lit wick.",
			"The dial is ash. The bells are gone, and so is the day.",
			"Somewhere in the warm dark, someone is laughing, and it is not a trick.",
		],
	},
}

const CHOICES := ["wind", "burn"]
const STATE_HIDDEN := "hidden"
const STATE_CHOICE := "choice"
const STATE_EPILOGUE := "epilogue"
## Seconds the win stays on screen before the choice appears, and between epilogue lines.
const SHOW_DELAY := 1.4
const EPILOGUE_LINE_TIME := 1.8
const EPILOGUE_FADE := 0.8
## Keys the overlay swallows while the choice is open, so they cannot move the player.
const SWALLOWED_KEYS := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_W, KEY_A, KEY_S, KEY_D,
	KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E, KEY_B]

var bus: Node = null
var state := STATE_HIDDEN
var selected := 0
var choice := ""

var buttons: Dictionary = {}  # choice -> Button
var epilogue_title: Label
var epilogue_labels: Array[Label] = []
var again_label: Label
var _choice_box: Control
var _epilogue_box: Control
var _tween: Tween
var _token := 0  # bumps on hide so a late timer does nothing


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	visible = false


func setup(new_bus: Node) -> void:
	bus = new_bus
	bus.ending_choice_requested.connect(func(_id): request_choice())
	bus.ending_chosen.connect(_on_ending_chosen)
	for signal_name in ["undo_done", "level_loaded"]:
		bus.connect(signal_name, func(_arg): hide_screen())
	bus.level_restarted.connect(hide_screen)


# --- Pure functions (tested without a window) ----------------------------------

## Moves the selection by `step` (-1 or 1), staying inside the choices.
static func move_selection(index: int, step: int) -> int:
	return clampi(index + step, 0, CHOICES.size() - 1)


static func choice_at(index: int) -> String:
	return CHOICES[clampi(index, 0, CHOICES.size() - 1)]


## Keys 1 and 2 pick directly; "" for any other key.
static func choice_for_key(keycode: int) -> String:
	match keycode:
		KEY_1, KEY_KP_1:
			return "wind"
		KEY_2, KEY_KP_2:
			return "burn"
	return ""


## What a key does in the choice state: {"move": -1/1}, {"confirm": true}, or {}.
static func key_action(keycode: int) -> Dictionary:
	match keycode:
		KEY_LEFT, KEY_UP:
			return {"move": -1}
		KEY_RIGHT, KEY_DOWN:
			return {"move": 1}
		KEY_ENTER, KEY_KP_ENTER:
			return {"confirm": true}
	return {}


static func epilogue_lines(chosen: String) -> Array:
	return EPILOGUES.get(chosen, {}).get("lines", [])


# --- Flow ---------------------------------------------------------------------------

## The final level was won: show the choice after a short beat.
func request_choice() -> void:
	_token += 1
	var mine := _token
	if not is_inside_tree():
		show_choice()
		return
	get_tree().create_timer(SHOW_DELAY).timeout.connect(func():
		if mine == _token and state == STATE_HIDDEN:
			show_choice())


func show_choice() -> void:
	state = STATE_CHOICE
	choice = ""
	selected = 0
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_choice_box.visible = true
	_epilogue_box.visible = false
	_restyle()


func hide_screen() -> void:
	_token += 1
	if _tween != null:
		_tween.kill()
		_tween = null
	state = STATE_HIDDEN
	choice = ""
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Makes the choice (mouse, Enter): everything goes through the bus signal.
func confirm(chosen: String) -> void:
	if state != STATE_CHOICE or not (chosen in CHOICES):
		return
	if bus != null:
		bus.ending_chosen.emit(chosen)
	else:
		show_epilogue(chosen)


func _on_ending_chosen(chosen: String) -> void:
	if state == STATE_CHOICE and chosen in CHOICES:
		show_epilogue(chosen)


func show_epilogue(chosen: String) -> void:
	state = STATE_EPILOGUE
	choice = chosen
	visible = true
	_choice_box.visible = false
	_epilogue_box.visible = true
	var data: Dictionary = EPILOGUES[chosen]
	var burning := chosen == "burn"
	epilogue_title.text = data["title"]
	epilogue_title.add_theme_color_override("font_color", UiTheme.color("ember") if burning else UiTheme.color("text"))
	for i in epilogue_labels.size():
		var l := epilogue_labels[i]
		var lines: Array = data["lines"]
		l.text = lines[i] if i < lines.size() else ""
		l.visible = l.text != ""
		l.modulate.a = 0.0
	again_label.modulate.a = 0.0
	if _tween != null:
		_tween.kill()
	if not is_inside_tree():
		_reveal_all()
		return
	_tween = create_tween()
	for l in epilogue_labels:
		if l.visible:
			_tween.tween_property(l, "modulate:a", 1.0, EPILOGUE_FADE)
			_tween.tween_interval(EPILOGUE_LINE_TIME - EPILOGUE_FADE)
	_tween.tween_property(again_label, "modulate:a", 1.0, EPILOGUE_FADE)


func _reveal_all() -> void:
	for l in epilogue_labels:
		l.modulate.a = 1.0
	again_label.modulate.a = 1.0


# --- Input ----------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or state != STATE_CHOICE:
		return
	var action := key_action(key.keycode)
	if action.has("move"):
		selected = move_selection(selected, int(action["move"]))
		_restyle()
	elif action.has("confirm"):
		confirm(choice_at(selected))
	elif key.keycode in SWALLOWED_KEYS:
		pass
	else:
		return  # 1 / 2 / Z / R / Escape go on to main.gd and the controller
	get_viewport().set_input_as_handled()


# --- Build ----------------------------------------------------------------------------

func _restyle() -> void:
	for i in CHOICES.size():
		var id: String = CHOICES[i]
		var button: Button = buttons[id]
		var chosen_now := i == selected
		var burn := id == "burn"
		var accent := UiTheme.color("ember") if burn else UiTheme.color("shadow_light")
		var fill := UiTheme.color("panel")
		if chosen_now:
			fill = UiTheme.color("ember_dark") if burn else UiTheme.color("shadow_dark")
		var border := accent if chosen_now else (UiTheme.color("ember").darkened(0.45) if burn else UiTheme.color("shadow_dark"))
		var box := UiTheme.panel_box(fill, border, 20, 4.0 if chosen_now else 1.5)
		for style in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(style, box)
		var text_color := UiTheme.color("ember") if burn else UiTheme.color("text")
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(c, text_color)


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.color("background"), 0.95)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	add_child(UiTheme.vignette(0.6))

	# Content sits above the bottom band, where Cinder's dialogue box shows.
	var area := MarginContainer.new()
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	area.add_theme_constant_override("margin_left", 260)
	area.add_theme_constant_override("margin_right", 260)
	area.add_theme_constant_override("margin_top", 40)
	area.add_theme_constant_override("margin_bottom", 440)
	add_child(area)

	_choice_box = VBoxContainer.new()
	_choice_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_choice_box.add_theme_constant_override("separation", 14)
	area.add_child(_choice_box)
	_choice_box.add_child(UiTheme.label(TEXTS["title"], "heading", 60, UiTheme.NONE, HORIZONTAL_ALIGNMENT_CENTER))
	_choice_box.add_child(_gap(10))
	for line in TEXTS["setup"]:
		var l := UiTheme.label(line, "body", 36, UiTheme.NONE, HORIZONTAL_ALIGNMENT_CENTER)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_choice_box.add_child(l)
	_choice_box.add_child(_gap(18))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	_choice_box.add_child(row)
	for id in CHOICES:
		var spec: Dictionary = TEXTS["choices"][id]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(540, 150)
		b.text = spec["label"]
		b.add_theme_font_override("font", UiTheme.font("heading"))
		b.add_theme_font_size_override("font_size", 44)
		var sub := UiTheme.label(spec["sub"], "emphasis", 28, UiTheme.color("text_dim"), HORIZONTAL_ALIGNMENT_CENTER)
		sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
		sub.grow_vertical = Control.GROW_DIRECTION_BEGIN
		sub.offset_bottom = -18
		b.add_child(sub)
		b.mouse_entered.connect(func(): selected = CHOICES.find(id); _restyle())
		b.pressed.connect(func(): confirm(id))
		buttons[id] = b
		row.add_child(b)
	_choice_box.add_child(UiTheme.label(TEXTS["hint"], "body", 26, UiTheme.color("text_dim"), HORIZONTAL_ALIGNMENT_CENTER))

	_epilogue_box = VBoxContainer.new()
	_epilogue_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(_epilogue_box as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	(_epilogue_box as VBoxContainer).add_theme_constant_override("separation", 16)
	area.add_child(_epilogue_box)
	epilogue_title = UiTheme.label("", "heading", 56, UiTheme.NONE, HORIZONTAL_ALIGNMENT_CENTER)
	_epilogue_box.add_child(epilogue_title)
	_epilogue_box.add_child(_gap(10))
	for i in 6:  # up to six lines; EPILOGUES uses 4 to 6
		var l := UiTheme.label("", "body", 36, UiTheme.NONE, HORIZONTAL_ALIGNMENT_CENTER)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		epilogue_labels.append(l)
		_epilogue_box.add_child(l)
	_epilogue_box.add_child(_gap(16))
	again_label = UiTheme.label(TEXTS["again"], "button", 34, UiTheme.color("text_dim"), HORIZONTAL_ALIGNMENT_CENTER)
	_epilogue_box.add_child(again_label)
	_epilogue_box.visible = false


func _gap(height: float) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(0, height)
	return c
