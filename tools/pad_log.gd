extends SceneTree
## Prints every controller button / stick event for 20 seconds (to find out what a button sends).
## Run: /Applications/Godot.app/Contents/MacOS/Godot --path . -s tools/pad_log.gd

const SECONDS := 180.0
var _t := 0.0
var _listed := false


func _initialize() -> void:
	root.title = "Press controller buttons (%d s)" % SECONDS
	root.window_input.connect(_on_input)


func _process(delta: float) -> bool:
	_t += delta
	if not _listed and _t > 0.5:  # controllers show up a moment after start
		_listed = true
		for d in Input.get_connected_joypads():
			print("controller #", d, ": ", Input.get_joy_name(d))
		print("Press buttons now (%d s)..." % SECONDS)
	return _t > SECONDS


func _on_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		print("button ", event.button_index, "  (", event.as_text(), ")")
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.3:
		print("axis ", event.axis, " = ", snappedf(event.axis_value, 0.1))
