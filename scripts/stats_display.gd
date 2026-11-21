extends CanvasLayer
## Debug overlay: performance stats in the top-left corner, in every scene.
## To turn it off: Project > Project Settings > Globals > Autoload, untick StatsDisplay.

## How often the numbers refresh (s).
const REFRESH := 0.25

var _label: Label
var _t := 0.0


func _ready() -> void:
	layer = 100  # above the inventory and the map
	process_mode = Node.PROCESS_MODE_ALWAYS  # also while the game is paused
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color("f2e2b0"))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.position = Vector2(8, 6)
	add_child(_label)
	_refresh()


func _process(delta: float) -> void:
	_t += delta
	if _t >= REFRESH:
		_t = 0.0
		_refresh()


func _refresh() -> void:
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var mem_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var vram_mb := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	_label.text = "FPS %d\nprocess %.1f ms  physics %.1f ms\ndraw calls %d  nodes %d\nRAM %.0f MB  VRAM %.0f MB" \
		% [fps, frame_ms, physics_ms, draws, nodes, mem_mb, vram_mb]
