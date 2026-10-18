extends RefCounted
## One place for the UI look (frozen by Noor): every color and font path is in
## THEME. Fonts load at runtime with FontFile; a missing file prints a warning
## once and falls back to the default font, so the UI never fails on an asset.
##
## Ember orange is ONLY for fire moments: the burn action, the LET IT BURN
## choice and Cinder's emphasis. Never for ordinary text or buttons.

const THEME := {
	"colors": {
		"background": Color("0E1116"),
		"panel": Color("1A1E24"),
		"text": Color("E6E8EB"),
		"text_dim": Color("9AA1AB"),
		"shadow_dark": Color("2C224D"),   # cold accent, also the panel border
		"shadow_light": Color("4B3D8C"),
		"ember": Color("FF6A13"),         # warm accent, fire moments only
		"ember_dark": Color("2A1408"),    # a fire panel's fill (ember at ~10%)
	},
	"fonts": {
		"heading": "res://ui/fonts/Cinzel-Bold.ttf",
		"body": "res://ui/fonts/CormorantGaramond-Regular.ttf",
		"emphasis": "res://ui/fonts/CormorantGaramond-Italic.ttf",
		"button": "res://ui/fonts/CormorantGaramond-SemiBold.ttf",
	},
}

const BORDER_WIDTH := 1.5
## "Not given": the default for optional colors (Color() is opaque black, so it cannot mean that).
const NONE := Color(0, 0, 0, 0)
## Cormorant's default numerals are old-style (a 0 looks like an o); lining ones read better in a HUD.
const LINING_NUMERALS := {"lnum": 1}

static var _font_cache: Dictionary = {}
static var _warned: Dictionary = {}


static func color(name: String) -> Color:
	return THEME["colors"][name]


## The font for a kind ("heading", "body", "emphasis", "button"); the default
## font (with a printed warning) when the file is missing or unreadable.
static func font(kind: String) -> Font:
	if _font_cache.has(kind):
		return _font_cache[kind]
	var loaded: Font = _load_font(kind, str(THEME["fonts"].get(kind, "")))
	if loaded == null:
		if not _warned.has(kind):
			_warned[kind] = true
			push_warning("ui_theme: font '%s' (%s) is missing; using the default font" % [kind, THEME["fonts"].get(kind, "?")])
		loaded = ThemeDB.fallback_font
	_font_cache[kind] = loaded
	return loaded


static func _load_font(kind: String, path: String) -> Font:
	if path == "":
		return null
	var base: Font = null
	if ResourceLoader.exists(path):  # imported (editor and exported games)
		var res = load(path)
		if res is Font:
			base = res
	if base == null and FileAccess.file_exists(path):  # not imported yet: read the .ttf directly
		var bytes := FileAccess.get_file_as_bytes(path)
		if not bytes.is_empty():
			var f := FontFile.new()
			f.data = bytes
			base = f
	if base == null or kind == "heading":
		return base
	var variation := FontVariation.new()
	variation.base_font = base
	variation.opentype_features = LINING_NUMERALS
	return variation


## Flat panel: fill, a 1.5px border (shadow indigo by default), square corners.
static func panel_box(fill: Color = NONE, border: Color = NONE, margin: int = 16, border_width: float = BORDER_WIDTH) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill if fill.a > 0.0 else color("panel")
	box.border_color = border if border.a > 0.0 else color("shadow_dark")
	box.set_border_width_all(int(ceil(border_width)))
	box.set_corner_radius_all(2)
	box.set_content_margin_all(margin)
	box.anti_aliasing = true
	return box


## A button look: flat, same border rule. `accent` is the border/focus color.
static func button_styles(accent: Color, fill: Color = NONE) -> Dictionary:
	var base := fill if fill.a > 0.0 else color("panel")
	return {
		"normal": panel_box(base, color("shadow_dark"), 10),
		"hover": panel_box(base.lerp(accent, 0.18), accent, 10),
		"pressed": panel_box(base.lerp(accent, 0.32), accent, 10),
		"focus": panel_box(Color(0, 0, 0, 0.001), accent, 10),
	}


static func style_button(button: Button, accent: Color, fill: Color = NONE) -> void:
	var styles := button_styles(accent, fill)
	for key in styles:
		button.add_theme_stylebox_override(key, styles[key])
	button.add_theme_font_override("font", font("button"))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, color("text"))


static func label(text: String, kind: String, size: int, tint: Color = NONE, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	style_label(l, kind, size, tint)
	return l


static func style_label(l: Label, kind: String, size: int, tint: Color = NONE) -> void:
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", tint if tint.a > 0.0 else color("text"))


## A slight dark vignette over the whole screen (transparent in the middle).
static func vignette(strength: float = 0.5) -> TextureRect:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	gradient.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, strength)])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect
