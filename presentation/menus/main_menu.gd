extends Control
## Main menu, built in code. Emits chosen(action) with one of
## "continue", "new_game", "level_select", "credits", "quit".
## Arrow keys + Enter move between buttons (Godot focus); the mouse works too.

const Style := preload("res://presentation/menus/menu_style.gd")

signal chosen(action: String)

const TITLE := "Pyre of the Hours"
const SUBTITLE := "a burnt clock tower, six hours, one fire"

## Set before adding: show Continue only when there is progress.
var show_continue := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scale := Style.scale_for(get_viewport_rect().size.y)
	theme = Style.theme(scale)
	add_child(Style.backdrop())
	var col := Style.column(scale)
	add_child(col)
	col.add_child(Style.label(TITLE, Style.TITLE_SIZE, scale))
	col.add_child(Style.label(SUBTITLE, Style.BODY_SIZE, scale, Style.TEXT_DIM))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18 * scale)
	col.add_child(spacer)
	var first: Button = null
	for entry in buttons(show_continue):
		var b := Style.button(entry[1], scale)
		b.pressed.connect(func(): chosen.emit(entry[0]))
		col.add_child(b)
		if first == null:
			first = b
	first.grab_focus.call_deferred()


## [action, label] pairs, in order. Continue only with progress.
static func buttons(with_continue: bool) -> Array:
	var list: Array = []
	if with_continue:
		list.append(["continue", "Continue"])
	list += [["new_game", "New Game"], ["level_select", "Level Select"], ["credits", "Credits"], ["quit", "Quit"]]
	return list
