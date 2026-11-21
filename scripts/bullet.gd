extends Area2D
## Shotgun pellet: a tiny streak that flies straight, fades out near the end of its range
## and disappears. The player fires several per shot (see player.gd, Shooting).

const COLOR_HOT := Color("f2e2b0")
const COLOR_COOL := Color("b09a78")

@export var speed := 420.0
## Distance (px) the pellet travels before it's gone. The player sets this per pellet.
@export var max_range := 96.0
## Last part of the range (0..1) over which the pellet fades out.
@export_range(0.0, 1.0, 0.05) var fade_portion := 0.35

var direction := Vector2.RIGHT
var _travelled := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	rotation = direction.angle()


func _physics_process(delta: float) -> void:
	var step := speed * delta
	position += direction * step
	_travelled += step
	if _travelled >= max_range:
		queue_free()
		return
	queue_redraw()


func _on_body_entered(_body: Node) -> void:
	queue_free()


func _draw() -> void:
	var t := _travelled / max_range
	var fade_start := 1.0 - fade_portion
	var a := 1.0 if t < fade_start else clampf((1.0 - t) / maxf(fade_portion, 0.001), 0.0, 1.0)
	# 2 px streak (drawn along +x, the node is rotated to the flight direction)
	draw_rect(Rect2(-1, 0, 1, 1), Color(COLOR_COOL, a))
	draw_rect(Rect2(0, 0, 1, 1), Color(COLOR_HOT, a))
