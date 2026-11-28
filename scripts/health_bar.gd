extends Node2D
## Small pixel-art health bar for enemies, drawn centred on this node (put it above the
## head). Hidden at full health; set_ratio() shows it, and it fades out show_time seconds
## after the last change. The part just lost shows as a pale chunk that drains after a
## moment, so each hit reads clearly.

@export_range(8, 64, 1, "suffix:px") var width := 24
@export_range(2, 8, 1, "suffix:px") var height := 3
## Seconds the bar stays after the last hit before fading out.
@export_range(0.5, 10.0, 0.5, "suffix:s") var show_time := 3.0
@export_range(0.05, 2.0, 0.05, "suffix:s") var fade_time := 0.4

const OUTLINE := Color("1a1416")
const EMPTY := Color("3d2a2a")
const FILL := Color("c23a2a")
const FILL_TOP := Color("e0603f")  # 1 px highlight along the top of the fill
const LOST := Color("f2d8a0")      # the chunk just lost, before it drains

var ratio := 1.0
var _lag := 1.0          # where the pale "just lost" chunk ends
var _lag_wait := 0.0     # seconds before the chunk starts draining
var _show_left := 0.0


func _ready() -> void:
	z_index = 20  # above the enemy, the player and their effects
	modulate.a = 0.0
	visible = false


## Health fraction 0..1. Shows the bar (it fades out again after show_time).
func set_ratio(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if value < ratio:
		_lag = maxf(_lag, ratio)
		_lag_wait = 0.3
	ratio = value
	_show_left = show_time
	modulate.a = 1.0
	visible = true
	queue_redraw()


## Fade out after `seconds` (e.g. when the enemy dies).
func hide_after(seconds: float) -> void:
	_show_left = minf(_show_left, seconds)


func _process(delta: float) -> void:
	if not visible:
		return
	if _lag_wait > 0.0:
		_lag_wait -= delta
	elif _lag > ratio:
		_lag = maxf(ratio, _lag - delta * 1.2)
	_show_left -= delta
	if _show_left <= 0.0:
		modulate.a = maxf(0.0, modulate.a - delta / fade_time)
		visible = modulate.a > 0.0
	queue_redraw()


func _draw() -> void:
	var left := -width / 2
	var fill_w := roundi(width * ratio)
	var lag_w := roundi(width * _lag)
	draw_rect(Rect2(left - 1, -1, width + 2, height + 2), OUTLINE)
	draw_rect(Rect2(left, 0, width, height), EMPTY)
	if lag_w > fill_w:
		draw_rect(Rect2(left + fill_w, 0, lag_w - fill_w, height), LOST)
	if fill_w > 0:
		draw_rect(Rect2(left, 0, fill_w, height), FILL)
		draw_rect(Rect2(left, 0, fill_w, 1), FILL_TOP)
