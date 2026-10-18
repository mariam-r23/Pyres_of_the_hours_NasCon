extends Control
## Pause menu over the game, built in code. Emits chosen(action) with one of
## "resume", "restart", "level_select", "main_menu". Escape (handled by
## main.gd) resumes.

const Style := preload("res://presentation/menus/menu_style.gd")

signal chosen(action: String)

const BUTTONS := [["resume", "Resume"], ["restart", "Restart"], ["level_select", "Level Select"], ["main_menu", "Main Menu"]]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scale := Style.scale_for(get_viewport_rect().size.y)
	theme = Style.theme(scale)
	add_child(Style.backdrop())
	var col := Style.column(scale)
	add_child(col)
	col.add_child(Style.label("Paused", Style.HEADING_SIZE, scale))
	var first: Button = null
	for entry in BUTTONS:
		var b := Style.button(entry[1], scale)
		b.pressed.connect(func(): chosen.emit(entry[0]))
		col.add_child(b)
		if first == null:
			first = b
	col.add_child(Style.label("Escape: resume", Style.BODY_SIZE, scale, Style.TEXT_DIM))
	first.grab_focus.call_deferred()
