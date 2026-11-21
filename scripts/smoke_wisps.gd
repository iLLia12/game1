extends Node2D
## Thin smoke wisps rising from smouldering stumps. Put this node inside a parallax layer
## so the smoke scrolls (and repeats) with the trees it comes from.
## Each entry in `sources` is one wisp. Give this node the same position as the tree image,
## and sources are then plain pixel coordinates in that image.

## Where smoke rises from (px in level1_near.png): smouldering stumps and one trunk crack.
@export var sources: Array[Vector2] = [
	Vector2(228, 470), Vector2(515, 488), Vector2(684, 480),
	Vector2(760, 330), Vector2(1500, 470), Vector2(2230, 470),
]
## Puffs alive per wisp at once. Low = thin, wispy; high = thick column.
@export_range(1, 30, 1) var puffs_per_wisp := 12
## How long one puff lives (s); together with rise_speed sets how high the smoke goes.
@export_range(1.0, 15.0, 0.5, "suffix:s") var lifetime := 6.0
## Upward speed of a fresh puff (px/s).
@export_range(0.0, 60.0, 0.5, "suffix:px/s") var rise_speed := 10.0
## Sideways drift (px/s², + = right).
@export_range(-20.0, 20.0, 0.5, "suffix:px/s²") var wind := 2.5
## Overall smoke opacity.
@export_range(0.0, 1.0, 0.05) var opacity := 0.35


func _ready() -> void:
	var tex := _make_puff_texture()
	for i in sources.size():
		var p := CPUParticles2D.new()
		p.position = sources[i]
		p.texture = tex
		p.amount = puffs_per_wisp
		p.lifetime = lifetime
		p.preprocess = lifetime  # already smoking when the level starts
		p.randomness = 0.5
		p.local_coords = true
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(3, 1)
		p.direction = Vector2(0, -1)
		p.spread = 10.0
		p.initial_velocity_min = rise_speed * 0.7
		p.initial_velocity_max = rise_speed * 1.3
		p.gravity = Vector2(wind, -1.0)
		p.damping_min = 0.5
		p.damping_max = 1.5
		p.angle_min = -180.0
		p.angle_max = 180.0
		p.angular_velocity_min = -8.0
		p.angular_velocity_max = 8.0
		p.scale_amount_min = 0.8
		p.scale_amount_max = 1.2
		p.scale_amount_curve = _grow_curve()
		p.color_ramp = _fade_gradient()
		add_child(p)


## 12x12 pixel-art puff: solid core with a dithered rim, hard alpha (opacity comes from the
## colour ramp), so it stays crisp under nearest filtering.
func _make_puff_texture() -> ImageTexture:
	var size := 12
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size - 1, size - 1) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(c)
			if d <= 3.5 or (d <= 5.5 and (x + y) % 2 == 0):
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)


## Puffs start small and spread out as they rise.
func _grow_curve() -> Curve:
	var curve := Curve.new()
	curve.max_value = 3.0
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(1.0, 2.6))
	return curve


## Pale ash-grey smouldering smoke (lighter than the background haze so it reads),
## fading out as it rises.
func _fade_gradient() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(Color("8a7f7c"), 0.0))
	g.set_color(1, Color(Color("b0a49e"), 0.0))
	g.add_point(0.1, Color(Color("918582"), opacity))
	g.add_point(0.5, Color(Color("a0948f"), opacity * 0.6))
	return g
