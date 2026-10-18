extends Control
## The sun dial: a ring of the six hours (12, 2, 4, 6, 8, 10) with three ticks
## between each hour and the next. One tick lights per action; the current
## hour is highlighted. Cold indigo and pale text only (no ember: this is not fire).
## The geometry is in static functions so tests need no window.

const UiTheme := preload("res://ui/ui_theme.gd")
const Icons := preload("res://ui/icons.gd")

const HOURS := [12, 2, 4, 6, 8, 10]
const DEFAULT_TICKS_PER_HOUR := 3

var sun_index := 0
var lit := 0
var ticks_per_hour := DEFAULT_TICKS_PER_HOUR
var actions_to_next := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(248, 248)


## Angle of an hour marker, clockwise from the top. Hour index 0..5.
static func hour_angle(hour_index: int) -> float:
	return hour_index * TAU / HOURS.size()


## Angle of tick `tick` (0-based) in the stretch after hour `hour_index`: evenly
## spaced between this hour marker and the next, never on a marker.
static func tick_angle(hour_index: int, tick: int, ticks_per_hour_count: int = DEFAULT_TICKS_PER_HOUR) -> float:
	return hour_angle(hour_index) + (tick + 1) * (TAU / HOURS.size()) / (ticks_per_hour_count + 1)


static func tick_count(ticks_per_hour_count: int = DEFAULT_TICKS_PER_HOUR) -> int:
	return HOURS.size() * ticks_per_hour_count


## How many ticks are lit: one per action since the day began (the sun's start
## offset counts, so a day that starts later is partly lit).
static func lit_ticks(sun_start_index: int, action_count: int, ticks_per_hour_count: int = DEFAULT_TICKS_PER_HOUR) -> int:
	return clampi(sun_start_index * ticks_per_hour_count + action_count, 0, tick_count(ticks_per_hour_count))


## The hour index to highlight (0..5); -1 once the dial is complete.
static func highlight_index(sun_index_value: int) -> int:
	return sun_index_value if sun_index_value >= 0 and sun_index_value < HOURS.size() else -1


## A point on a circle: angle clockwise from the top (12 o'clock).
static func ring_point(center: Vector2, radius: float, angle: float) -> Vector2:
	return center + Vector2(sin(angle), -cos(angle)) * radius


## Which tick (hour index, tick index) is the n-th lit tick (0-based).
static func tick_of(n: int, ticks_per_hour_count: int = DEFAULT_TICKS_PER_HOUR) -> Vector2i:
	return Vector2i(floori(n / float(ticks_per_hour_count)), n % ticks_per_hour_count)


## Updates what the dial shows and redraws.
func show_state(new_sun_index: int, new_lit: int, new_ticks_per_hour: int, new_actions_to_next: int) -> void:
	sun_index = new_sun_index
	lit = new_lit
	ticks_per_hour = maxi(new_ticks_per_hour, 1)
	actions_to_next = new_actions_to_next
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - 32.0
	var dim := UiTheme.color("text_dim")
	var pale := UiTheme.color("text")
	var dark := UiTheme.color("shadow_dark")
	var light := UiTheme.color("shadow_light")
	var current := highlight_index(sun_index)
	draw_arc(center, radius, 0.0, TAU, 96, dark, 2.0, true)
	# Ticks: lit ones are pale, the rest dim.
	for h in HOURS.size():
		for t in ticks_per_hour:
			var a := tick_angle(h, t, ticks_per_hour)
			var is_lit := h * ticks_per_hour + t < lit
			draw_line(ring_point(center, radius - 9.0, a), ring_point(center, radius + 9.0, a),
				pale if is_lit else dim.darkened(0.35), 3.0 if is_lit else 2.0, true)
	# Hour markers with their numbers.
	var font := UiTheme.font("heading")
	for h in HOURS.size():
		var p := ring_point(center, radius, hour_angle(h))
		var passed := current == -1 or h < current
		if h == current:
			draw_circle(p, 24.0, light)
			draw_arc(p, 24.0, 0.0, TAU, 32, pale, 2.0, true)
		else:
			draw_circle(p, 20.0, dark if passed else UiTheme.color("panel"))
			draw_arc(p, 20.0, 0.0, TAU, 32, dark if passed else dim.darkened(0.3), 1.5, true)
		var text := str(HOURS[h])
		var fs := 22 if h == current else 19
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, p + Vector2(-w.x / 2.0, w.y * 0.28), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			pale if (h == current or passed) else dim)
	# Center: the sun marker and how long until it moves.
	Icons.draw_glyph(self, "sun", Rect2(center - Vector2(20, 34), Vector2(40, 40)), pale, 2.5)
	var body := UiTheme.font("body")
	var caption := "dial complete" if current == -1 else "moves on in %d" % actions_to_next
	# Small and just under the sun, so it stays between the 8 and 4 markers.
	var cw := body.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 19)
	draw_string(body, center + Vector2(-cw.x / 2.0, 24.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, dim)
