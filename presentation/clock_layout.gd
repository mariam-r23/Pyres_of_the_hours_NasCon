extends Node3D
## The clock face: six RoomViews around a circle at 12, 2, 4, 6, 8 and 10
## o'clock, plus a dial hand (the sun marker) pointing at the current sun hour.
## 12 o'clock is toward -Z (the top of the screen), hours run clockwise.

const GameStateScript := preload("res://core/game_state.gd")
const Sun := preload("res://core/sun.gd")
const RoomViewScript := preload("res://presentation/room_view.gd")

## Neighbouring rooms are 60 degrees apart, so their centers are RADIUS
## apart (chord = 2 R sin 30 deg). 9 units leaves a 4-unit gap between 5x5 rooms.
const RADIUS := 9.0
const HAND_LENGTH := 3.2
const HAND_TIP_LENGTH := 0.7

var _rooms := {}  # hour -> RoomView
var _hand_pivot: Node3D = null


## Room center for an hour on the clock face.
static func hour_to_room_position(hour: int) -> Vector3:
	var angle := hour_angle(hour)
	return Vector3(RADIUS * sin(angle), 0.0, -RADIUS * cos(angle))


## Clockwise angle from 12 o'clock, in radians (12 -> 0, 3 -> PI/2).
static func hour_angle(hour: int) -> float:
	return (hour % 12) / 12.0 * TAU


## The hour the dial hand points at: the first hour the sun has not passed
## yet, or 12 again once the dial is complete.
static func sun_hour(state: GameStateScript) -> int:
	var index := Sun.sun_index(state)
	if index >= GameStateScript.HOUR_ORDER.size():
		return GameStateScript.HOUR_ORDER[0]
	return GameStateScript.HOUR_ORDER[maxi(index, 0)]


func _ready() -> void:
	for hour in GameStateScript.HOUR_ORDER:
		var room: Node3D = RoomViewScript.new()
		room.name = "Room_%d" % hour
		room.position = hour_to_room_position(hour)
		add_child(room)
		_rooms[hour] = room
	_build_dial()


func room_for_hour(hour: int) -> Node3D:
	return _rooms.get(hour)


## Pops in the object on `slot` in the room for `hour`.
func pop_slot(hour: int, slot: Vector2i) -> void:
	var room := room_for_hour(hour)
	if room != null:
		room.pop_slot(slot)


## Unit vector (XZ plane) the dial hand points along, in this node's space.
func hand_direction() -> Vector3:
	if _hand_pivot == null:
		return Vector3.ZERO
	return (_hand_pivot.transform.basis * Vector3(0, 0, -1)).normalized()


## Redraws every room and points the dial hand at the sun hour.
## `hidden` maps hour -> Array of slots whose objects are not drawn yet.
func refresh_all(state: GameStateScript, hidden: Dictionary = {}) -> void:
	for hour in _rooms:
		_rooms[hour].refresh(state, hour, hidden.get(hour, []))
	if _hand_pivot != null:
		# rotation.y turns -Z toward -X for positive angles, so negate for clockwise.
		_hand_pivot.rotation.y = -hour_angle(sun_hour(state))


func _build_dial() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = RoomViewScript.COLORS["dial"]
	mat.metallic = 0.6
	mat.roughness = 0.5
	var hub := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.8
	disc.bottom_radius = 0.8
	disc.height = 0.15
	hub.mesh = disc
	hub.material_override = mat
	add_child(hub)

	var hand_mat := StandardMaterial3D.new()
	hand_mat.albedo_color = RoomViewScript.COLORS["sun_marker"]
	hand_mat.emission_enabled = true
	hand_mat.emission = RoomViewScript.COLORS["sun_marker"]
	hand_mat.emission_energy_multiplier = 0.6
	_hand_pivot = Node3D.new()
	_hand_pivot.name = "SunMarker"
	_hand_pivot.position = Vector3(0, 0.15, 0)
	add_child(_hand_pivot)
	var hand := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(0.18, 0.08, HAND_LENGTH)
	hand.mesh = bar
	hand.material_override = hand_mat
	hand.position = Vector3(0, 0, -HAND_LENGTH / 2.0)  # extends from the hub toward -Z
	_hand_pivot.add_child(hand)
	# An arrowhead at the far end and a pale cap on the hub, so it is always
	# clear which end of the hand points at the sun hour.
	var tip := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.32
	cone.height = HAND_TIP_LENGTH
	tip.mesh = cone
	tip.material_override = hand_mat
	tip.rotation_degrees = Vector3(-90, 0, 0)  # the cone's point turns toward -Z
	tip.position = Vector3(0, 0, -HAND_LENGTH - HAND_TIP_LENGTH / 2.0)
	_hand_pivot.add_child(tip)
	var cap := MeshInstance3D.new()
	var cap_disc := CylinderMesh.new()
	cap_disc.top_radius = 0.28
	cap_disc.bottom_radius = 0.28
	cap_disc.height = 0.1
	cap.mesh = cap_disc
	cap.material_override = hand_mat
	_hand_pivot.add_child(cap)
