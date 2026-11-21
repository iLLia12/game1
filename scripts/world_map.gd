extends CanvasLayer
## World map screen (assets/ui/map/map.png), filling the whole screen, with zoom and panning.
## Open / close: touchpad or Create (PS5), M. Esc / Circle also closes. The game pauses while it's open.
## Zoom: R1 / L1, R2 / L2 (analog), E / Q, + / -, mouse wheel (towards the cursor).
## Move: left stick, D-pad, WASD / arrows, drag with the mouse.
## The map always covers the screen: it can't be zoomed out or moved past its edges.

const MAP := preload("res://assets/ui/map/map.png")
const HINT_COLOR := Color("f2e2b0")

## Most zoomed in, compared to fully zoomed out (where the map just fills the screen).
@export_range(1.0, 10.0, 0.5) var max_zoom := 4.0
## Zoom speed while a zoom button is held (x per second, exponential).
@export_range(0.2, 5.0, 0.1) var zoom_speed := 1.6
## How much one mouse-wheel notch zooms.
@export_range(1.02, 2.0, 0.01) var wheel_step := 1.15
## Panning speed with stick / keys (screen px per second).
@export_range(50.0, 2000.0, 10.0, "suffix:px/s") var pan_speed := 500.0
## Show the controls along the bottom.
@export var show_hint := true

var _root: Control
var _map: TextureRect
var _screen: Vector2
var _cover := 1.0  # map px -> screen px when fully zoomed out (fills the screen)
var _zoom := 1.0   # 1 = fully zoomed out .. max_zoom
var _center := Vector2.ZERO  # map pixel shown in the middle of the screen
var _dragging := false


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps working while the game is paused
	add_to_group("pause_overlay")
	_screen = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	_cover = maxf(_screen.x / MAP.get_width(), _screen.y / MAP.get_height())
	_center = Vector2(MAP.get_size()) / 2.0

	_root = Control.new()
	_root.size = _screen
	_root.clip_contents = true
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_gui_input)
	add_child(_root)

	var back := ColorRect.new()
	back.color = Color.BLACK
	back.size = _screen
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(back)

	_map = TextureRect.new()
	_map.texture = MAP
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_SCALE
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_map)

	if show_hint:
		var hint := Label.new()
		hint.text = "R1/L1  E/Q  wheel: zoom      stick  WASD  drag: move      Circle / M: close"
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", HINT_COLOR)
		hint.add_theme_color_override("font_outline_color", Color.BLACK)
		hint.add_theme_constant_override("outline_size", 4)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.size = Vector2(_screen.x, 16)
		hint.position = Vector2(0, _screen.y - 20)
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(hint)

	_apply()
	_root.hide()


func is_open() -> bool:
	return _root.visible


func open() -> void:
	for other in get_tree().get_nodes_in_group("pause_overlay"):
		if other != self and other.is_open():
			other.close()
	_root.show()
	get_tree().paused = true


func close() -> void:
	_root.hide()
	_dragging = false
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		close() if is_open() else open()
	elif is_open() and event.is_action_pressed("ui_cancel"):
		close()
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_open():
		return
	# zoom: buttons / keys held, plus the analog triggers
	var z := 0.0
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
		z += 1.0
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
		z -= 1.0
	for d in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER):
			z += 1.0
		if Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_SHOULDER):
			z -= 1.0
		z += Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT)
	z = clampf(z, -1.0, 1.0)
	if absf(z) > 0.05:
		_zoom_at(exp(z * zoom_speed * delta), _screen / 2.0)

	# pan: the game's move / aim actions (WASD, arrows, D-pad, left stick)
	var pan := Input.get_vector("move_left", "move_right", "aim_up", "aim_down")
	if pan != Vector2.ZERO:
		_center += pan * pan_speed * delta / _scale()
		_apply()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(wheel_step, event.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(1.0 / wheel_step, event.position)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_center -= event.relative / _scale()
		_apply()


## Zoom by `factor`, keeping the map point under `at` (screen px) where it is.
func _zoom_at(factor: float, at: Vector2) -> void:
	var under := _center + (at - _screen / 2.0) / _scale()
	_zoom = clampf(_zoom * factor, 1.0, max_zoom)
	_center = under - (at - _screen / 2.0) / _scale()
	_apply()


func _scale() -> float:
	return _cover * _zoom


## Keep the screen covered, then place the map.
func _apply() -> void:
	var s := _scale()
	var half := _screen / 2.0 / s
	var size := Vector2(MAP.get_size())
	_center.x = clampf(_center.x, half.x, size.x - half.x) if size.x > half.x * 2.0 else size.x / 2.0
	_center.y = clampf(_center.y, half.y, size.y - half.y) if size.y > half.y * 2.0 else size.y / 2.0
	_map.size = size * s
	_map.position = (_screen / 2.0 - _center * s).round()
	# shrunk: smooth; blown up past 1:1: crisp pixels
	_map.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if s < 1.0 else CanvasItem.TEXTURE_FILTER_NEAREST


## Controls while the map is open, for the top-right list (input_display.gd).
func help() -> Array:
	return [
		[{"kb": "E/Q  +/-  wheel", "pad": "R1/L1  R2/L2"}, "zoom in / out"],
		[["move_left", "move_right", "aim_up", "aim_down"], "move around"],
		[{"kb": "drag"}, "move around"],
		[["map", "ui_cancel"], "close"],
	]
