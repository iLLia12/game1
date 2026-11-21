extends Control
## Main menu: background art + the buttons cut from assets/ui/main_menu/buttons.png.
## Mouse, keyboard (arrows + Enter) and gamepad (D-pad + Cross) all work.

const GAME_SCENE := "res://scenes/main.tscn"
const BACKGROUND := preload("res://assets/ui/main_menu/background.png")
const BUTTONS := preload("res://assets/ui/main_menu/buttons.png")
## Each button's area inside buttons.png, top to bottom.
const BUTTON_RECTS := {
	"one_player": Rect2(96, 144, 81, 21),
	"two_players": Rect2(96, 168, 81, 21),
	"online": Rect2(96, 192, 81, 21),
	"quit": Rect2(96, 216, 81, 21),
}
## Buttons that do something yet; the others are shown dimmed.
const ENABLED := ["one_player", "quit"]

## Buttons are drawn this many times bigger than in buttons.png.
@export_range(1, 4, 1) var button_scale := 2
## Centre of the button column on the 960x540 screen.
@export var buttons_center := Vector2(200, 290)
@export_range(0, 40, 1, "suffix:px") var button_gap := 10
## Moves the background up/down (it's taller than the screen once it fills the width).
@export_range(-200.0, 0.0, 1.0, "suffix:px") var background_offset_y := -60.0
## Brightness of the highlighted button.
@export_range(1.0, 2.0, 0.05) var highlight := 1.3

var _buttons := {}


func _ready() -> void:
	add_to_group("help")  # controls list in the top-right corner (input_display.gd)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var screen := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))

	var bg := TextureRect.new()
	bg.texture = BACKGROUND
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # big art shrunk: smooth, not jagged
	bg.size = Vector2(screen.x, screen.x * BACKGROUND.get_height() / BACKGROUND.get_width())
	bg.position = Vector2(0, background_offset_y)
	add_child(bg)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", button_gap)
	add_child(column)
	for id in BUTTON_RECTS:
		var b := _make_button(id)
		column.add_child(b)
		_buttons[id] = b
	column.reset_size()
	column.position = (buttons_center - column.size / 2).round()

	_buttons.one_player.pressed.connect(_on_one_player)
	_buttons.quit.pressed.connect(get_tree().quit)
	_buttons.one_player.grab_focus()


func _make_button(id: String) -> TextureButton:
	var rect: Rect2 = BUTTON_RECTS[id]
	var art := AtlasTexture.new()
	art.atlas = BUTTONS
	art.region = rect
	var b := TextureButton.new()
	b.name = id
	b.texture_normal = art
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.custom_minimum_size = rect.size * button_scale
	if id in ENABLED:
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# Mouse and keyboard/gamepad share one highlight: hovering moves the focus
		b.mouse_entered.connect(b.grab_focus)
		b.focus_entered.connect(func(): b.modulate = Color(highlight, highlight, highlight))
		b.focus_exited.connect(func(): b.modulate = Color.WHITE)
		b.button_down.connect(func(): b.modulate = Color(0.85, 0.85, 0.85))
	else:
		b.disabled = true
		b.focus_mode = Control.FOCUS_NONE
		b.modulate = Color(0.55, 0.55, 0.55)
	return b


func _on_one_player() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


## Controls of this screen, for the top-right list (input_display.gd).
func help() -> Array:
	return [
		[["ui_up", "ui_down"], "choose an option"],
		[["ui_accept"], "select"],
		[{"kb": "Mouse left"}, "click an option"],
	]
