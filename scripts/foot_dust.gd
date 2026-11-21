extends Node2D
## Ash dust kicked up by the hero's feet. Sits at the feet (the player's origin).
## The player calls set_running() every physics frame and puff() on landing.
## Particles stay in the world (not attached to the hero), so the dust is left behind.

## Pale ash (like the smoke), so it reads against the dark ground and tree bases.
const DUST_LIGHT := Color("a0948f")
const DUST_DARK := Color("6b6262")

## Dust puffs alive at once while running. More = thicker trail.
@export_range(1, 40, 1) var run_amount := 8
## How long a running dust puff lives (s).
@export_range(0.1, 2.0, 0.05, "suffix:s") var run_lifetime := 0.45
## Kick-back speed of running dust (px/s); sprinting multiplies it by sprint_kick.
@export_range(0.0, 100.0, 1.0, "suffix:px/s") var run_kick := 22.0
## Extra kick while sprinting.
@export_range(1.0, 3.0, 0.05) var sprint_kick := 1.6
## Puffs in a jump / landing burst.
@export_range(1, 40, 1) var burst_amount := 5
## Running-trail opacity (kept low so it's just a hint).
@export_range(0.0, 1.0, 0.05) var run_opacity := 0.35
## Jump / landing puff opacity.
@export_range(0.0, 1.0, 0.05) var opacity := 0.85

var _run: CPUParticles2D
var _burst: CPUParticles2D


func _ready() -> void:
	var tex := _make_texture()
	_run = _make_emitter(tex, run_amount, run_lifetime, run_opacity)
	_run.emission_rect_extents = Vector2(4, 2)
	_run.spread = 40.0
	_run.gravity = Vector2(0, 25)
	_run.damping_min = 30.0
	_run.damping_max = 50.0
	_run.emitting = false
	add_child(_run)

	_burst = _make_emitter(tex, burst_amount, 0.5, opacity)
	_burst.one_shot = true
	_burst.explosiveness = 1.0
	_burst.emission_rect_extents = Vector2(8, 1)
	_burst.direction = Vector2(0, -1)
	_burst.spread = 80.0  # fans out to both sides
	_burst.initial_velocity_min = 40.0
	_burst.initial_velocity_max = 70.0
	_burst.gravity = Vector2(0, 40)
	_burst.damping_min = 40.0
	_burst.damping_max = 60.0
	_burst.emitting = false
	add_child(_burst)


## Turn the running trail on/off. facing = 1 right / -1 left; dust flies backwards.
func set_running(on: bool, facing: int, sprinting: bool) -> void:
	if on:
		_run.direction = Vector2(-facing, -1.0)
		var kick := run_kick * (sprint_kick if sprinting else 1.0)
		_run.initial_velocity_min = kick * 0.6
		_run.initial_velocity_max = kick
	_run.emitting = on


## One burst of dust at the feet (landing).
func puff() -> void:
	_burst.restart()


func _make_emitter(tex: Texture2D, amount: int, lifetime: float, alpha: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.amount = amount
	p.lifetime = lifetime
	p.randomness = 0.5
	p.local_coords = false  # dust stays where it was kicked up
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	p.scale_amount_curve = _grow_curve()
	p.color_ramp = _fade_gradient(alpha)
	return p


## 7x7 pixel dust puff: solid diamond core with dithered rim, hard alpha.
func _make_texture() -> ImageTexture:
	var img := Image.create(7, 7, false, Image.FORMAT_RGBA8)
	for y in 7:
		for x in 7:
			var d := absi(x - 3) + absi(y - 3)
			if d <= 3 or (d == 4 and (x + y) % 2 == 0):
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)


## Puffs swell a little as they settle.
func _grow_curve() -> Curve:
	var c := Curve.new()
	c.max_value = 3.0
	c.add_point(Vector2(0.0, 0.7))
	c.add_point(Vector2(1.0, 1.6))
	return c


func _fade_gradient(alpha: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(DUST_LIGHT, alpha))
	g.set_color(1, Color(DUST_DARK, 0.0))
	g.add_point(0.5, Color(DUST_LIGHT.lerp(DUST_DARK, 0.5), alpha * 0.6))
	return g
