extends Sprite2D
## Plays a sprite sheet (hframes x vframes) on its own, e.g. a level prop.
## Ping-pong: plays forwards then backwards (the camera pans left -> right -> left),
## holding the first and last frame for `hold` seconds.
## `progress` is the position between frames (e.g. 3.4); other scripts can use it for
## smooth motion (camera_beam.gd turns the beam with it), while `frame` steps through the sheet.

## Number of frames in the sheet (the last row may be partly empty).
@export var frames := 12
@export_range(1.0, 30.0, 0.5, "suffix:fps") var fps := 6.0
## Play forwards then backwards instead of looping back to frame 0.
@export var ping_pong := true
## Pause on the first / last frame (s).
@export_range(0.0, 5.0, 0.1, "suffix:s") var hold := 1.0
## Ping-pong only: start and stop each pass gently instead of at full speed.
@export var ease_in_out := true

## Set by another script (e.g. camera_beam.gd) to drive `frame` / `progress` itself; the animation waits.
var manual := false
## Position between frames, 0 .. frames - 1.
var progress := 0.0

var _t := 0.0


func _ready() -> void:
	_t = randf() * _cycle()  # props of the same kind don't move in sync


func _process(delta: float) -> void:
	if manual:
		return
	_t = fmod(_t + delta, _cycle())
	progress = _progress_at(_t)
	frame = clampi(roundi(progress) if ping_pong else int(progress), 0, frames - 1)


## Go back to playing on its own, carrying on from `at` (a progress value) towards the end of the sheet.
func resume_from(at: float) -> void:
	manual = false
	var f := clampf(at, 0.0, frames - 1)
	if not ping_pong:
		_t = f / fps
		return
	# find the point of the forward pass that is at `f`
	var target := f / maxf(frames - 1, 1)
	var lo := 0.0
	var hi := 1.0
	for i in 20:
		var mid := (lo + hi) / 2.0
		if _ease(mid) < target:
			lo = mid
		else:
			hi = mid
	_t = hold + lo * _run()


func _run() -> float:
	return (frames - 1) / fps


func _cycle() -> float:
	return (_run() + hold) * 2.0 if ping_pong else frames / fps + hold


func _ease(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u) if ease_in_out else u


func _progress_at(t: float) -> float:
	var last := float(frames - 1)
	if not ping_pong:
		return minf(t * fps, last)
	var run := _run()
	if t < hold:
		return 0.0
	t -= hold
	if t < run:
		return _ease(t / run) * last
	t -= run
	if t < hold:
		return last
	return (1.0 - _ease((t - hold) / run)) * last
