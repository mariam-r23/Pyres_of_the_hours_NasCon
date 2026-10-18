extends Control
## Vector glyphs drawn in code (no image files): burn, wait, undo, interact,
## restart and the sun marker. Use as a node (set `kind`) or call
## draw_glyph() from any CanvasItem's _draw().

const KINDS := ["burn", "wait", "undo", "interact", "restart", "sun"]

var kind := "burn":
	set(value):
		kind = value
		queue_redraw()
var color := Color("E6E8EB"):
	set(value):
		color = value
		queue_redraw()
var line_width := 3.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(32, 32)


func _draw() -> void:
	draw_glyph(self, kind, Rect2(Vector2.ZERO, size), color, line_width)


## Draws glyph `glyph_kind` centered in `rect`. An unknown kind draws nothing.
static func draw_glyph(canvas: CanvasItem, glyph_kind: String, rect: Rect2, tint: Color, width: float = 3.0) -> void:
	var c := rect.get_center()
	var h := minf(rect.size.x, rect.size.y) * 0.5 * 0.9
	match glyph_kind:
		"burn":
			_closed(canvas, _map([Vector2(0, -1), Vector2(0.42, -0.45), Vector2(0.75, 0.1), Vector2(0.62, 0.65),
				Vector2(0.25, 0.95), Vector2(-0.25, 0.95), Vector2(-0.62, 0.65), Vector2(-0.72, 0.15),
				Vector2(-0.38, -0.05), Vector2(-0.3, -0.5)], c, h), tint, width)
			_closed(canvas, _map([Vector2(0, 0.25), Vector2(0.26, 0.62), Vector2(0, 0.86), Vector2(-0.26, 0.62)], c, h), tint, width)
		"wait":
			_closed(canvas, _map([Vector2(-0.55, -0.9), Vector2(0.55, -0.9), Vector2(0.55, -0.7), Vector2(0, 0),
				Vector2(0.55, 0.7), Vector2(0.55, 0.9), Vector2(-0.55, 0.9), Vector2(-0.55, 0.7), Vector2(0, 0),
				Vector2(-0.55, -0.7)], c, h), tint, width)
		"undo":
			_arrow_arc(canvas, c + Vector2(0, h * 0.1), h * 0.62, 0.2 * PI, -1.05 * PI, tint, width, h)
		"restart":
			_arrow_arc(canvas, c, h * 0.62, -0.4 * PI, 1.35 * PI, tint, width, h)
		"interact":
			canvas.draw_polyline(_map([Vector2(-0.9, 0.85), Vector2(-0.9, 0.4), Vector2(-0.3, 0.4), Vector2(-0.3, -0.05),
				Vector2(0.3, -0.05), Vector2(0.3, -0.5), Vector2(0.9, -0.5), Vector2(0.9, -0.95)], c, h), tint, width, true)
		"sun":
			canvas.draw_arc(c, h * 0.38, 0.0, TAU, 32, tint, width, true)
			for i in 8:
				var a := i * TAU / 8.0
				canvas.draw_line(c + Vector2(cos(a), sin(a)) * h * 0.62, c + Vector2(cos(a), sin(a)) * h * 0.95, tint, width, true)


static func _map(points: Array, center: Vector2, half: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(center + (p as Vector2) * half)
	return out


static func _closed(canvas: CanvasItem, points: PackedVector2Array, tint: Color, width: float) -> void:
	var loop := points.duplicate()
	loop.append(points[0])
	canvas.draw_polyline(loop, tint, width, true)


## An arc from angle a0 to a1 (radians, screen coordinates) with an arrowhead at a1.
static func _arrow_arc(canvas: CanvasItem, center: Vector2, radius: float, a0: float, a1: float, tint: Color, width: float, h: float) -> void:
	canvas.draw_arc(center, radius, a0, a1, 32, tint, width, true)
	var end := center + Vector2(cos(a1), sin(a1)) * radius
	var dir := signf(a1 - a0)
	var tangent := Vector2(-sin(a1), cos(a1)) * dir
	var back := -tangent * h * 0.5
	canvas.draw_line(end, end + back.rotated(0.6), tint, width, true)
	canvas.draw_line(end, end + back.rotated(-0.6), tint, width, true)
