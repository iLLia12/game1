extends Node2D
## Blinking red alarm light on top of the security camera's pole.
## Created by camera_beam.gd as a child of the camera; blinks while `active` is true
## (the camera is following the hero). When not active the sprite's own light shows.

## Blinks per second.
@export_range(0.5, 20.0, 0.5) var rate := 4.0
## The light's 4x4 pixels on camera1.png, relative to the camera's base.
@export var light_rect := Rect2(-2, -151, 4, 4)
@export var on_color := Color("ff6a4a")
@export var on_core := Color("fff0d8")
@export var off_color := Color("3a0a0a")
## Glow around the light when it's on.
@export var glow_color := Color(1.0, 0.15, 0.1, 0.35)
@export_range(0.0, 40.0, 1.0, "suffix:px") var glow_radius := 12.0

var active := false:
	set(v):
		if v != active:
			active = v
			_t = 0.0
			queue_redraw()

var _t := 0.0
var _on := false
var _glow: Node2D


func _ready() -> void:
	z_index = 1  # over the camera sprite and its beam
	_glow = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	_glow.draw.connect(_draw_glow)
	add_child(_glow)


func _process(delta: float) -> void:
	if not active:
		if _on:
			_on = false
			queue_redraw()
			_glow.queue_redraw()
		return
	_t += delta
	var on := fmod(_t * rate, 1.0) < 0.5
	if on != _on:
		_on = on
		queue_redraw()
		_glow.queue_redraw()


func _draw() -> void:
	if not active:
		return
	var r := light_rect
	if _on:
		draw_rect(r, on_color)
		draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(2, 1)), on_core)  # hot spot
	else:
		draw_rect(r, off_color)


func _draw_glow() -> void:
	if not (active and _on):
		return
	var c := light_rect.get_center()
	for i in 3:  # stepped rings for a pixel-art glow
		var k := 1.0 - i / 3.0
		_glow.draw_circle(c, glow_radius * (0.4 + 0.3 * i), Color(glow_color, glow_color.a * k))
