extends Node2D
## Now and then a loose flock of crows crosses the sky. Put this node inside a Parallax2D
## (between the far hills and the near trees) so the birds have their own depth.
## Uses assets/sprites/crow/flying.png: 40x40 cells, 5 columns x 2 rows, 9 frames, facing right.

const SHEET := preload("res://assets/sprites/crow/flying.png")
const FRAMES := 9

@export_group("Timing")
## Seconds before the first flock appears.
@export_range(0.0, 60.0, 0.5, "suffix:s") var first_delay := 4.0
## Random pause between flocks (s).
@export_range(1.0, 120.0, 1.0, "suffix:s") var interval_min := 20.0
@export_range(1.0, 120.0, 1.0, "suffix:s") var interval_max := 40.0

@export_group("Flock")
## Birds per flock (random between min and max).
@export_range(1, 20, 1) var birds_min := 2
@export_range(1, 20, 1) var birds_max := 3
## How spread out the flock is (px): length along the flight path and height.
@export var spread := Vector2(140, 50)
## Flight speed (px/s), each bird varies a little around it.
@export_range(10.0, 300.0, 1.0, "suffix:px/s") var speed := 110.0
## Flight height band as a fraction of the screen (0 = top, 1 = bottom).
@export_range(0.0, 1.0, 0.01) var height_min := 0.12
@export_range(0.0, 1.0, 0.01) var height_max := 0.4

@export_group("Look")
## Wing-flap speed (frames per second).
@export_range(1.0, 30.0, 0.5, "suffix:fps") var flap_fps := 14.0
## Frame held while a bird glides (wings spread).
@export_range(0, 8) var glide_frame := 2
## Chance per second that a bird starts a short glide.
@export_range(0.0, 1.0, 0.05) var glide_chance := 0.15
## Up to this much haze colour mixed into far-looking birds (0 = all solid black).
@export_range(0.0, 1.0, 0.05) var max_haze := 0.4
## Sky haze colour that distant birds fade towards.
@export var haze_color := Color("6b6262")

var _birds: Array[Dictionary] = []
var _timer := 0.0


func _ready() -> void:
	_timer = first_delay


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0 and _birds.is_empty():
		spawn_flock()
		_timer = randf_range(interval_min, interval_max)

	var view := _visible_rect()
	for i in range(_birds.size() - 1, -1, -1):
		var b: Dictionary = _birds[i]
		var s: Sprite2D = b.sprite
		b.t += delta
		b.x += b.dir * b.speed * delta
		s.position = Vector2(b.x, b.y + sin(b.t * b.bob_freq) * b.bob_amp)
		# Flap, with the occasional glide
		if b.glide > 0.0:
			b.glide -= delta
			s.frame = glide_frame
		else:
			b.flap += delta * flap_fps * b.flap_mul
			s.frame = int(b.flap) % FRAMES
			if randf() < glide_chance * delta:
				b.glide = randf_range(0.4, 1.2)
		# Gone past the far edge
		if (b.dir > 0 and b.x > view.end.x + 60) or (b.dir < 0 and b.x < view.position.x - 60):
			s.queue_free()
			_birds.remove_at(i)


## Sends a flock across the screen now (also handy for testing).
func spawn_flock() -> void:
	var view := _visible_rect()
	var dir := 1 if randf() < 0.5 else -1
	var start_x := view.position.x - 40.0 if dir > 0 else view.end.x + 40.0
	var base_y := lerpf(view.position.y, view.end.y, randf_range(height_min, height_max))
	var flock_speed := speed * randf_range(0.85, 1.15)
	for n in randi_range(birds_min, maxi(birds_min, birds_max)):
		var depth := randf()  # 0 = near/solid, 1 = far/hazy
		var s := Sprite2D.new()
		s.texture = SHEET
		s.hframes = 5
		s.vframes = 2
		s.scale.x = dir  # sheet faces right
		s.modulate = Color.WHITE.lerp(haze_color, depth * max_haze)
		add_child(s)
		_birds.append({
			"sprite": s,
			"dir": dir,
			# Trailing birds start further back, scattered up and down
			"x": start_x - dir * randf_range(0.0, spread.x),
			"y": base_y + randf_range(-spread.y, spread.y) * 0.5,
			"speed": flock_speed * randf_range(0.92, 1.08) * lerpf(1.0, 0.85, depth),
			"t": randf() * TAU,
			"bob_freq": randf_range(2.0, 4.0),
			"bob_amp": randf_range(1.5, 3.5),
			"flap": randf() * FRAMES,
			"flap_mul": randf_range(0.85, 1.15),
			"glide": 0.0,
		})


## The part of this node's space currently on screen (accounts for the parallax offset).
func _visible_rect() -> Rect2:
	var to_local := get_global_transform_with_canvas().affine_inverse()
	return to_local * get_viewport_rect()
