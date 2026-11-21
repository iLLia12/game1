extends Sprite2D
## Idle head motion for the tied-up robot: a slow, slightly uneven sway, and now and then
## a quick servo twitch to a new angle (as if it's looking around), held for a moment.
## The node's position is the neck pivot; the head texture hangs above it via `offset`.

## Slow sway amplitude (degrees).
@export_range(0.0, 10.0, 0.1, "suffix:°") var sway := 1.5
## Sway period (s).
@export_range(0.5, 20.0, 0.1, "suffix:s") var sway_period := 5.0
## Max angle of a "look" twitch (degrees), random either way.
@export_range(0.0, 15.0, 0.5, "suffix:°") var look_angle := 5.0
## Random wait between looks (s).
@export_range(0.5, 30.0, 0.5, "suffix:s") var look_every_min := 3.0
@export_range(0.5, 30.0, 0.5, "suffix:s") var look_every_max := 8.0
## How fast the head snaps to a new look (degrees per second) - high = jerky, robotic.
@export_range(1.0, 200.0, 1.0, "suffix:°/s") var snap_speed := 40.0

var _t := 0.0
var _look := 0.0         # current look angle (deg)
var _look_target := 0.0
var _next_look := 0.0


func _ready() -> void:
	_t = randf() * sway_period
	_next_look = randf_range(look_every_min, look_every_max)


func _process(delta: float) -> void:
	_t += delta
	_next_look -= delta
	if _next_look <= 0.0:
		# Mostly glance somewhere, sometimes go back to looking straight ahead
		_look_target = 0.0 if randf() < 0.35 else randf_range(-look_angle, look_angle)
		_next_look = randf_range(look_every_min, look_every_max)
	_look = move_toward(_look, _look_target, snap_speed * delta)
	# Two mismatched sines so the sway never looks perfectly mechanical
	var w := TAU / sway_period
	var s := sin(_t * w) * 0.75 + sin(_t * w * 2.3 + 1.0) * 0.25
	rotation_degrees = _look + s * sway
