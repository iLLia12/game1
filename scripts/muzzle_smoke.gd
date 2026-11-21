extends Node2D
## One puff of gun smoke at the muzzle. Spawned into the world (not on the hero), so the
## smoke hangs where the shot was fired, drifts up and fades. Frees itself when done.

const SMOKE_LIGHT := Color("b8b0aa")
const SMOKE_DARK := Color("6b6262")

## Direction the shot went; the smoke is pushed that way first.
var direction := Vector2.RIGHT

@export_range(1, 40, 1) var amount := 14
@export_range(0.1, 3.0, 0.05, "suffix:s") var lifetime := 0.8
@export_range(0.0, 1.0, 0.05) var opacity := 0.8


func _ready() -> void:
	var p := CPUParticles2D.new()
	p.texture = _make_texture()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.85
	p.randomness = 0.5
	p.direction = direction
	p.spread = 25.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 240.0
	p.damping_min = 960.0
	p.damping_max = 1320.0
	p.gravity = Vector2(0, -6)  # smoke rises once the push dies down
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.1
	p.scale_amount_curve = _grow_curve()
	p.color_ramp = _fade_gradient()
	add_child(p)
	p.emitting = true
	p.finished.connect(queue_free)


## 7x7 pixel puff: solid diamond core with dithered rim (same look as the foot dust).
func _make_texture() -> ImageTexture:
	var img := Image.create(7, 7, false, Image.FORMAT_RGBA8)
	for y in 7:
		for x in 7:
			var d := absi(x - 3) + absi(y - 3)
			if d <= 3 or (d == 4 and (x + y) % 2 == 0):
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)


func _grow_curve() -> Curve:
	var c := Curve.new()
	c.max_value = 3.0
	c.add_point(Vector2(0.0, 0.6))
	c.add_point(Vector2(1.0, 1.8))
	return c


func _fade_gradient() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(SMOKE_LIGHT, opacity))
	g.set_color(1, Color(SMOKE_DARK, 0.0))
	g.add_point(0.4, Color(SMOKE_LIGHT.lerp(SMOKE_DARK, 0.4), opacity * 0.7))
	return g
