extends CanvasLayer
## Debug overlay: shows the keys / buttons being pressed in the top-right corner, in every scene.
## Line 1: everything held right now. Line 2: the last thing pressed and the game action(s) it triggers.
## Below: the controls of the current screen. The open inventory / map, or else the scene (main menu,
## hero), lists them in a help() function; key names are read from the Input Map, for the device
## used last (keyboard + mouse, or controller).
## To turn it off: Project > Project Settings > Globals > Autoload, untick InputDisplay.

## PS5 names for Godot's controller button numbers.
const PAD_NAMES := {
	0: "Cross", 1: "Circle", 2: "Square", 3: "Triangle", 4: "Create", 5: "PS", 6: "Options",
	7: "L3", 8: "R3", 9: "L1", 10: "R1", 11: "D-pad Up", 12: "D-pad Down", 13: "D-pad Left",
	14: "D-pad Right", 15: "Mute", 20: "Touchpad",
}
const AXIS_NAMES := {0: "Left stick X", 1: "Left stick Y", 2: "Right stick X", 3: "Right stick Y", 4: "L2", 5: "R2"}
const MOUSE_NAMES := {1: "Mouse left", 2: "Mouse right", 3: "Mouse middle", 4: "Wheel up", 5: "Wheel down"}
## A stick / trigger counts as pressed past this much.
const AXIS_PRESS := 0.5

## How often the controls list is checked for a change of screen (s).
const HELP_REFRESH := 0.2
const ARROWS := {"Left": "←", "Right": "→", "Up": "↑", "Down": "↓"}
const STICK_NAMES := {0: "L stick", 1: "L stick", 2: "R stick", 3: "R stick", 4: "L2", 5: "R2"}

var _held := {}  # what's held now: id -> label (keeps press order)
var _last := ""
var _label: Label
var _help: Label
var _pad := false  # last input came from a controller
var _help_t := 0.0


func _ready() -> void:
	layer = 100  # above the inventory and the map
	process_mode = Node.PROCESS_MODE_ALWAYS  # also while the game is paused
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color("f2e2b0"))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_label.offset_left = -480
	_label.offset_right = -8
	_label.offset_top = 6
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(_label)

	_help = Label.new()
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.add_theme_font_size_override("font_size", 11)
	_help.add_theme_color_override("font_color", Color("d8cfb4"))
	_help.add_theme_color_override("font_outline_color", Color.BLACK)
	_help.add_theme_constant_override("outline_size", 4)
	_help.add_theme_constant_override("line_spacing", -2)
	_help.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_help.offset_left = -480
	_help.offset_right = -8
	_help.offset_top = 46  # under the two key lines
	_help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(_help)
	_pad = not Input.get_connected_joypads().is_empty()
	_refresh()


func _process(delta: float) -> void:
	_help_t += delta
	if _help_t >= HELP_REFRESH:
		_help_t = 0.0
		_refresh_help()


func _input(event: InputEvent) -> void:
	var id := ""
	var name := ""
	var down := false
	if event is InputEventKey:
		if event.echo:
			return
		id = "key%d" % event.physical_keycode
		name = OS.get_keycode_string(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
		down = event.pressed
	elif event is InputEventJoypadButton:
		id = "pad%d" % event.button_index
		name = "%s (pad %d)" % [PAD_NAMES.get(event.button_index, "Button"), event.button_index]
		down = event.pressed
	elif event is InputEventJoypadMotion:
		id = "axis%d" % event.axis
		down = absf(event.axis_value) > AXIS_PRESS
		var dir := ""
		if event.axis <= 3:
			dir = ["←", "→"][int(event.axis_value > 0)] if event.axis % 2 == 0 else ["↑", "↓"][int(event.axis_value > 0)]
		name = "%s %s" % [AXIS_NAMES.get(event.axis, "Axis %d" % event.axis), dir]
		if down == _held.has(id) and (not down or _held[id] == name.strip_edges()):
			return  # stick moved but nothing changed (still held / still released)
	elif event is InputEventMouseButton:
		id = "mouse%d" % event.button_index
		name = MOUSE_NAMES.get(event.button_index, "Mouse %d" % event.button_index)
		down = event.pressed
	else:
		return
	var pad := event is InputEventJoypadButton or event is InputEventJoypadMotion
	if down and pad != _pad:
		_pad = pad  # show the controls of the device being used
		_refresh_help()
	name = name.strip_edges()
	if down:
		_held[id] = name
		var actions := _actions(event)
		_last = name + ("  →  " + ", ".join(actions) if not actions.is_empty() else "")
	else:
		_held.erase(id)
	_refresh()


## Game actions this event triggers (built-in ui_* actions left out, except accept / cancel).
func _actions(event: InputEvent) -> PackedStringArray:
	var out := PackedStringArray()
	for a in InputMap.get_actions():
		if a.begins_with("ui_") and a not in [&"ui_accept", &"ui_cancel"]:
			continue
		if InputMap.event_is_action(event, a):
			out.append(a)
	return out


func _refresh() -> void:
	var held := ", ".join(PackedStringArray(_held.values()))
	_label.text = "held: %s\nlast: %s" % [held if held != "" else "—", _last if _last != "" else "—"]


# ---------------------------------------------------------------- controls of the current screen

## help() of the open inventory / map, else of the main menu or hero.
## Each entry: [keys, what it does]. keys = Array of action names (named from the Input Map),
## or {"kb": "...", "pad": "..."} written out (either may be missing = not on that device).
func _refresh_help() -> void:
	var source: Node = null
	for o in get_tree().get_nodes_in_group("pause_overlay"):
		if o.is_open():
			source = o
	if source == null:
		var helpers := get_tree().get_nodes_in_group("help")
		if not helpers.is_empty():
			source = helpers[0]
	var lines := PackedStringArray()
	if source != null and source.has_method("help"):
		for entry in source.help():
			var keys := ""
			if entry[0] is Array:
				keys = _keys_for(entry[0])
			else:
				keys = entry[0].get("pad" if _pad else "kb", "")
			if keys != "":
				lines.append("%s  —  %s" % [keys, entry[1]])
	_help.text = "\n".join(lines)


## Names of the keys (or controller buttons) bound to these actions, e.g. "A/D/←/→".
func _keys_for(actions: Array) -> String:
	var out := PackedStringArray()
	var dpad := 0
	for a in actions:
		for e in InputMap.action_get_events(a):
			var n := ""
			if not _pad and e is InputEventKey:
				var code: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
				if code in [KEY_KP_ENTER]:
					continue
				n = OS.get_keycode_string(code)
				n = ARROWS.get(n, "Esc" if n == "Escape" else n)
			elif not _pad and e is InputEventMouseButton:
				n = MOUSE_NAMES.get(e.button_index, "Mouse")
			elif _pad and e is InputEventJoypadButton:
				n = PAD_NAMES.get(e.button_index, "pad %d" % e.button_index)
				if n.begins_with("D-pad "):
					n = "D-pad " + ARROWS.get(n.trim_prefix("D-pad "), "")
					dpad += 1
			elif _pad and e is InputEventJoypadMotion:
				n = STICK_NAMES.get(e.axis, "axis %d" % e.axis)
			if n != "" and n not in out:
				out.append(n)
	if dpad > 1:  # several D-pad directions: just "D-pad"
		var merged := PackedStringArray()
		for n in out:
			n = "D-pad" if n.begins_with("D-pad") else n
			if n not in merged:
				merged.append(n)
		out = merged
	return "/".join(out)
