extends Control
## Mounts the whole in-game UI on a 1920x1080 canvas and wires it to the bus:
## vignette, HUD, win / fail panel, ending screen, and Cinder's dialogue box on
## top (so her lines still show over the ending overlay). main.gd only adds this
## node and calls setup(); the UI listens to EventBus and reads state through
## the controller. It makes up no game rules.

const UiTheme := preload("res://ui/ui_theme.gd")
const HudScript := preload("res://ui/hud.gd")
const DialogueBoxScript := preload("res://ui/dialogue_box.gd")
const EndingScreenScript := preload("res://ui/ending_screen.gd")
const ResultPanelScript := preload("res://ui/result_panel.gd")

## The canvas the UI is designed for (main.gd sets the content scale to this).
const DESIGN_SIZE := Vector2i(1920, 1080)
const HUD_FADE_TIME := 0.15

signal next_requested

var bus: Node = null
var controller: Node = null
var hud: Control
var result_panel: PanelContainer
var ending_screen: Control
var dialogue_box: Control
## Callable() -> bool: is there a level after the current one? (main.gd)
var has_next_level: Callable = Callable()
## True from ending_choice_requested until the next undo / restart / load.
var ending_requested := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiTheme.vignette(0.45))
	hud = HudScript.new()
	add_child(hud)
	result_panel = ResultPanelScript.new()
	add_child(result_panel)
	ending_screen = EndingScreenScript.new()
	add_child(ending_screen)
	dialogue_box = DialogueBoxScript.new()
	add_child(dialogue_box)


## new_messages: main.gd REJECTION_MESSAGES. new_context_hint: Callable(state, burn_mode) -> String.
## new_has_next: Callable() -> bool.
func setup(new_bus: Node, new_controller: Node, new_messages: Dictionary, new_context_hint: Callable, new_has_next: Callable) -> void:
	bus = new_bus
	controller = new_controller
	has_next_level = new_has_next
	hud.setup(bus, controller, new_messages, new_context_hint)
	result_panel.controller = controller
	result_panel.next_requested.connect(func(): next_requested.emit())
	ending_screen.setup(bus)
	dialogue_box.setup(bus)

	bus.level_won.connect(func(event): _on_level_won.call_deferred(event))
	bus.level_failed.connect(func(_event): result_panel.show_result(false, false))
	bus.ending_choice_requested.connect(func(_id):
		ending_requested = true
		result_panel.hide_panel())
	for signal_name in ["undo_done", "level_loaded"]:
		bus.connect(signal_name, func(_arg): _reset())
	bus.level_restarted.connect(_reset)
	# The ripple shot hides the HUD, like the old status text.
	bus.ripple_started.connect(func(): hud.fade_to(0.0, HUD_FADE_TIME))
	bus.ripple_finished.connect(func(): hud.fade_to(1.0, 0.0))


func _on_level_won(event: Dictionary) -> void:
	if ending_requested:
		return  # the final level: the ending screen takes over
	var used := int(event.get("actions_used", -1))
	result_panel.show_result(true, has_next_level.is_valid() and has_next_level.call(),
		"%d action%s" % [used, "" if used == 1 else "s"] if used >= 0 else "")


func _reset() -> void:
	ending_requested = false
	result_panel.hide_panel()
