class_name GameTheme
extends RefCounted
## Builds the game's Theme in code so every colour comes from Palette.
## Buttons use the default type or the `PrimaryButton` variation; labels use
## `TitleLabel` and `DimLabel` for the large and quiet styles.
## [codeblock]
## screen.theme = GameTheme.create()
## fight_button.theme_type_variation = &"PrimaryButton"
## [/codeblock]

const FONT_SIZE: int = 26
const TITLE_FONT_SIZE: int = 40
const SMALL_FONT_SIZE: int = 22
const CORNER_RADIUS_PX: int = 18


static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE
	theme.set_color(&"font_color", &"Label", Palette.TEXT)
	_add_button(theme, &"Button", Palette.PANEL, Palette.TEXT)
	_add_button(theme, &"PrimaryButton", Palette.VERMILION, Palette.CREAM)
	theme.set_type_variation(&"PrimaryButton", &"Button")
	theme.set_font_size(&"font_size", &"PrimaryButton", 34)
	theme.set_type_variation(&"TitleLabel", &"Label")
	theme.set_font_size(&"font_size", &"TitleLabel", TITLE_FONT_SIZE)
	theme.set_color(&"font_color", &"TitleLabel", Palette.CREAM)
	theme.set_color(&"font_outline_color", &"TitleLabel", Palette.INK)
	theme.set_constant(&"outline_size", &"TitleLabel", 6)
	theme.set_type_variation(&"DimLabel", &"Label")
	theme.set_font_size(&"font_size", &"DimLabel", SMALL_FONT_SIZE)
	theme.set_color(&"font_color", &"DimLabel", Palette.TEXT_DIM)
	return theme


## A flat rounded panel with an ink outline and a darker bottom edge, so it
## reads as a raised paper tile.
static func make_panel(fill: Color, radius_px: int = CORNER_RADIUS_PX, bottom_px: int = 6) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius_px)
	box.set_border_width_all(3)
	box.border_width_bottom = bottom_px
	box.border_color = Palette.INK
	box.anti_aliasing = true
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


static func _add_button(theme: Theme, type: StringName, fill: Color, text: Color) -> void:
	var normal := make_panel(fill)
	var hover := make_panel(fill.lightened(0.08))
	# Pressed: the thick bottom edge shrinks, so the face looks pushed in.
	var pressed := make_panel(fill.darkened(0.12), CORNER_RADIUS_PX, 3)
	pressed.content_margin_top = 11
	var disabled := make_panel(fill.lerp(Palette.BACKDROP, 0.55))
	disabled.border_color = Palette.INK_SOFT
	theme.set_stylebox(&"normal", type, normal)
	theme.set_stylebox(&"hover", type, hover)
	theme.set_stylebox(&"pressed", type, pressed)
	theme.set_stylebox(&"hover_pressed", type, pressed)
	theme.set_stylebox(&"disabled", type, disabled)
	theme.set_stylebox(&"focus", type, StyleBoxEmpty.new())
	for state: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		theme.set_color(state, type, text)
	theme.set_color(&"font_disabled_color", type, text.darkened(0.45))
	theme.set_color(&"font_outline_color", type, Palette.INK)
	theme.set_constant(&"outline_size", type, 4)
