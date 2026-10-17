extends Node3D
## Root of the game. Builds everything in code at runtime: camera, light,
## environment, the GameController, the clock of six rooms, and a minimal
## text overlay. Redraws from the session's state after every change.
## Holds no game rules.

const ControllerScript := preload("res://presentation/game_controller.gd")
const ClockLayoutScript := preload("res://presentation/clock_layout.gd")
const EventBusScript := preload("res://presentation/event_bus.gd")
const RoomViewScript := preload("res://presentation/room_view.gd")

const LEVEL_PATH := "res://levels/data/L01_first_crate.json"

const WON_TEXT := "You reached the exit.\nPress R to restart."
const FAILED_TEXT := "The dial completed.\nPress R to restart."
const CONTROLS_TEXT := "Arrows / WASD: move    B then a direction: burn    E: interact\nSpace: wait    Z: undo    R: restart"
const BURN_MODE_TEXT := "BURN: press a direction (B or Esc cancels)"

## Cold, dark world (see room_view.gd COLORS for the color rule).
const BACKGROUND := Color(0.035, 0.045, 0.065)
const AMBIENT := Color(0.45, 0.52, 0.62)
const FOG := Color(0.10, 0.12, 0.16)
const LIGHT := Color(0.80, 0.86, 0.95)

var controller: Node
var clock: Node3D
var bus: Node
var _message: Label
var _hint: Label


func _ready() -> void:
	_build_world()
	clock = ClockLayoutScript.new()
	clock.name = "Clock"
	add_child(clock)

	controller = ControllerScript.new()
	controller.name = "GameController"
	add_child(controller)
	bus = get_node_or_null("/root/EventBus")
	if bus == null:
		push_warning("main: EventBus autoload is not registered; using a private bus")
		bus = EventBusScript.new()
		add_child(bus)
	controller.bus = bus

	_build_ui()
	for type in ["action_applied", "action_rejected", "undo_done"]:
		bus.connect(type, func(_event): _refresh())
	bus.level_loaded.connect(func(_meta): _refresh())
	bus.level_restarted.connect(_refresh)
	bus.level_won.connect(func(_event): _show_message(WON_TEXT))
	bus.level_failed.connect(func(_event): _show_message(FAILED_TEXT))
	bus.level_load_failed.connect(_on_load_failed)
	controller.burn_mode_changed.connect(_on_burn_mode_changed)

	controller.load_level(LEVEL_PATH)


func _refresh() -> void:
	var state = controller.current_state()
	if state == null:
		return
	clock.refresh_all(state)
	if state.status == "playing":
		_show_message("")


func _show_message(text: String) -> void:
	_message.text = text
	_message.visible = text != ""


func _on_load_failed(errors: Array) -> void:
	_show_message("Could not load %s:\n%s" % [LEVEL_PATH, "\n".join(PackedStringArray(errors))])


func _on_burn_mode_changed(active: bool) -> void:
	_hint.text = (BURN_MODE_TEXT + "\n" if active else "") + CONTROLS_TEXT


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = FOG
	env.fog_density = 0.012
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.1
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	var sun_light := DirectionalLight3D.new()
	sun_light.light_color = LIGHT
	sun_light.light_energy = 1.1
	sun_light.shadow_enabled = true
	sun_light.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun_light)

	# Looks down at the clock from the 6 o'clock side so all six rooms fit.
	var camera := Camera3D.new()
	camera.fov = 40.0
	add_child(camera)
	camera.position = Vector3(0, 30, 17)
	camera.look_at(Vector3(0, 0, 1.2))
	camera.current = true


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_message = Label.new()
	# Centered over the dial hub, the one empty spot between the rooms.
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message.grow_vertical = Control.GROW_DIRECTION_BOTH
	_message.add_theme_constant_override("outline_size", 8)
	_message.add_theme_color_override("font_outline_color", BACKGROUND)
	_message.add_theme_font_size_override("font_size", 28)
	_message.add_theme_color_override("font_color", RoomViewScript.COLORS["sun_marker"])
	_message.visible = false
	layer.add_child(_message)

	_hint = Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 16
	_hint.offset_bottom = -12
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color(0.65, 0.70, 0.78))
	_hint.text = CONTROLS_TEXT
	layer.add_child(_hint)
