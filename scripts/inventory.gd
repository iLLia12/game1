extends CanvasLayer
## Inventory screen (assets/ui/inventory/invetory.png).
## I / Tab / Triangle opens and closes it; Esc / Circle also closes. The game pauses while it's open.
## Collected weapons fill the slots in pickup order. Arrows / D-pad / mouse pick a slot,
## Enter / Cross / click takes that weapon in hand.

## invetory.png with the black around the slots made transparent.
const PANEL := preload("res://assets/ui/inventory/invetory_slots.png")
const COLUMNS := 4
const ROWS := 4
## Slot centres and inner size, in invetory.png pixels.
const SLOT_X := [290, 615, 931, 1251]
const SLOT_Y := [142, 387, 628, 871]
const SLOT_SIZE := Vector2(300, 222)
const GOLD := Color("f2e2b0")

@export var player_path: NodePath = ^"../Player"
## Panel width as a part of the screen width (0.25 = a quarter); its height follows the picture.
@export_range(0.1, 1.0, 0.05) var screen_fraction := 0.25
## Gap between the panel and the right edge of the screen.
@export_range(0, 100, 1, "suffix:px") var right_margin := 0
## Darkening over the game behind the panel.
@export var shade := Color(0, 0, 0, 0.3)

var panel_scale := 0.25  # invetory.png px -> screen px, set from screen_fraction

var _selected := 0
var _root: Control
var _panel: TextureRect
var _overlay: Control
var _icons := {}  # weapon id -> Texture2D


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps working while the game is paused
	add_to_group("pause_overlay")  # only one of inventory / map is open at a time
	var screen := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))

	_root = Control.new()
	_root.size = screen
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # nothing behind it gets clicks
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = shade
	dim.size = screen
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	_panel = TextureRect.new()
	_panel.texture = PANEL
	_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_panel.stretch_mode = TextureRect.STRETCH_SCALE
	_panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # big art shrunk: smooth
	panel_scale = screen.x * screen_fraction / PANEL.get_width()
	_panel.size = (PANEL.get_size() * panel_scale).round()
	_panel.position = Vector2(screen.x - _panel.size.x - right_margin, (screen.y - _panel.size.y) / 2).round()
	_panel.gui_input.connect(_on_panel_input)
	_root.add_child(_panel)

	# icons + highlight on top, drawn crisp (nearest)
	_overlay = Control.new()
	_overlay.size = _panel.size
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overlay.draw.connect(_draw_overlay)
	_panel.add_child(_overlay)

	_root.hide()


func is_open() -> bool:
	return _root.visible


func open() -> void:
	for other in get_tree().get_nodes_in_group("pause_overlay"):
		if other != self and other.is_open():
			other.close()
	_root.show()
	get_tree().paused = true
	var p := _player()
	if p != null and p.weapon in p.weapons:
		_selected = p.weapons.find(p.weapon)
	_overlay.queue_redraw()


func close() -> void:
	_root.hide()
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		close() if is_open() else open()
	elif not is_open():
		return
	elif event.is_action_pressed("ui_cancel"):
		close()
	# the game's own controls work here too: WASD / stick to move, jump or shoot to pick
	elif _pressed(event, ["ui_left", "move_left"]):
		_move(-1, 0)
	elif _pressed(event, ["ui_right", "move_right"]):
		_move(1, 0)
	elif _pressed(event, ["ui_up", "aim_up"]):
		_move(0, -1)
	elif _pressed(event, ["ui_down", "aim_down"]):
		_move(0, 1)
	elif _pressed(event, ["ui_accept", "jump", "shoot"]):
		_use(_selected)
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		# number keys: 1 = first slot, 2 = second...
		_selected = event.keycode - KEY_1
		_use(_selected)
	else:
		return
	get_viewport().set_input_as_handled()


func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		var slot := _slot_at(event.position)
		if slot < 0:
			return
		if slot != _selected:
			_selected = slot
			_overlay.queue_redraw()
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_use(slot)


func _pressed(event: InputEvent, actions: Array) -> bool:
	for a in actions:
		if event.is_action_pressed(a):
			return true
	return false


func _move(dx: int, dy: int) -> void:
	var c := posmod(_selected % COLUMNS + dx, COLUMNS)
	var r := posmod(_selected / COLUMNS + dy, ROWS)
	_selected = r * COLUMNS + c
	_overlay.queue_redraw()


## Take the weapon in that slot in hand (empty slot = nothing happens).
func _use(slot: int) -> void:
	var p := _player()
	if p != null and slot < p.weapons.size():
		p.equip(p.weapons[slot])
		_overlay.queue_redraw()


func _player() -> Node:
	return get_node_or_null(player_path)


func _slot_rect(slot: int) -> Rect2:
	var centre := Vector2(SLOT_X[slot % COLUMNS], SLOT_Y[slot / COLUMNS]) * panel_scale
	var size := SLOT_SIZE * panel_scale
	return Rect2((centre - size / 2).round(), size.round())


func _slot_at(pos: Vector2) -> int:
	for i in COLUMNS * ROWS:
		if _slot_rect(i).has_point(pos):
			return i
	return -1


func _icon(id: String) -> Texture2D:
	if not _icons.has(id):
		_icons[id] = load(_player().WEAPONS[id].icon)
	return _icons[id]


func _draw_overlay() -> void:
	var p := _player()
	var font := ThemeDB.fallback_font
	var weapons: Array = p.weapons if p != null else []
	for i in COLUMNS * ROWS:
		var r := _slot_rect(i)
		if i < weapons.size():
			var id: String = weapons[i]
			if id == p.weapon:
				_overlay.draw_rect(r.grow(-2), Color(GOLD, 0.18))  # weapon in hand
			var tex := _icon(id)
			# whole-number scale so the pixels stay crisp; shrink smoothly only if it can't fit at 1x
			var fit := minf((r.size.x - 4) / tex.get_width(), (r.size.y - 4) / tex.get_height())
			var k := floorf(fit) if fit >= 1.0 else fit
			var size := (tex.get_size() * k).round()
			_overlay.draw_texture_rect(tex, Rect2((r.get_center() - size / 2).round(), size), false)
		if i == _selected:
			_overlay.draw_rect(r.grow(-1), GOLD, false, 1.0)
	# name of the selected weapon under the panel
	if _selected < weapons.size():
		var id: String = weapons[_selected]
		var label: String = p.WEAPONS[id].name + ("  (in hand)" if id == p.weapon else "")
		_overlay.draw_string(font, Vector2(0, _overlay.size.y + 14), label,
			HORIZONTAL_ALIGNMENT_CENTER, _overlay.size.x, 11, GOLD)


## Controls while the inventory is open, for the top-right list (input_display.gd).
func help() -> Array:
	return [
		[["move_left", "move_right", "aim_up", "aim_down"], "choose a slot"],
		[["ui_accept", "jump", "shoot"], "take the weapon in hand"],
		[{"kb": "1-9"}, "take the weapon in that slot"],
		[{"kb": "Mouse left"}, "click a slot"],
		[["inventory", "ui_cancel"], "close"],
	]
