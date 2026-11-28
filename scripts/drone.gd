extends CharacterBody2D
## Bomber drone. Called in by security cameras (camera_beam.gd) when they spot the hero.
## Comes in from off-screen, chases the hero at hover_height above him, drops one bomb
## (aimed where he'll be when it lands), then flies away off-screen and is removed.
## Leads a moving hero: it flies ahead of him by how far he'll run while the bomb falls
## (minus the drift the bomb inherits from the drone), so the bomb meets him.
## Bullets can shoot it down (collision layer 5 "drones"; bullets have it in their mask).
## Builds its own sprite and collision shape, so it needs no scene: DRONE.new().
## Art: assets/sprites/enemies/drone1.png, facing right. Carries its bomb (drone_bomb.png) under
## the belly until it drops it. The rotor discs painted in the art are faded to a motion
## blur and spinning blades are drawn over them in code (_draw_rotors).

signal destroyed

const TEXTURE := preload("res://assets/sprites/enemies/drone1.png")
const BOMB := preload("res://scripts/drone_bomb.gd")
const EXPLOSION := preload("res://scripts/explosion.gd")
const LAYER_DRONES := 16  # physics layer 5
## Where the carried bomb hangs (its center), relative to the drone sprite facing right.
const BOMB_MOUNT := Vector2(4, 17)

## Rotors in drone1.png pixel coords: hub center, blade radius, motor rect kept fully opaque.
const ROTORS := [
	{"hub": Vector2(15, 4), "radius": 14.0, "motor": Rect2i(12, 3, 7, 5)},
	{"hub": Vector2(51, 4), "radius": 13.0, "motor": Rect2i(47, 5, 8, 3)},
]
const ROTOR_ROWS := 8  # rows 0..7 of the art hold the rotor discs
const ROTOR_BLUR_ALPHA := 0.35  # how much of the painted disc stays as motion blur
const ROTOR_TILT := 0.25  # disc seen from slightly above: height / width
const BLADE_LIGHT := Color("a4a6ad")
const BLADE_DARK := Color("26262c")
@export_range(0.0, 80.0, 1.0, "suffix:rad/s") var rotor_speed := 38.0

static var _body_tex: Texture2D

enum State { CHASE, LEAVE, FALL }

@export_range(20.0, 600.0, 5.0, "suffix:px/s") var speed := 150.0
@export_range(50.0, 2000.0, 10.0, "suffix:px/s²") var acceleration := 320.0
## Height above the hero's feet it hovers at (a random value in this range per drone).
@export var hover_height := Vector2(105, 135)
## Seconds of chasing before it can drop (so it doesn't bomb the moment it arrives).
@export_range(0.0, 5.0, 0.1, "suffix:s") var min_chase_time := 0.8
## Gives up and leaves after this long without a good drop.
@export_range(1.0, 60.0, 1.0, "suffix:s") var chase_timeout := 14.0
## Drops when the bomb would land within this distance of the hero.
@export_range(2.0, 40.0, 1.0, "suffix:px") var drop_accuracy := 10.0
@export_range(1, 20, 1) var health := 2
## Small red health bar (health_bar.gd) above the drone, shown for a few seconds after a hit.
const HEALTH_BAR := preload("res://scripts/health_bar.gd")
const HEALTH_BAR_POS := Vector2(0, -20)
## Damage of the blast when the shot-down drone crashes.
@export_range(0, 20, 1) var crash_damage := 1
@export var hero_aim_offset := Vector2(0, -22)
## How quickly the measured hero speed follows his real speed (higher = twitchier aim).
@export_range(1.0, 30.0, 0.5) var hero_speed_smoothing := 6.0

var state := State.CHASE

var _sprite: Sprite2D
var _held_bomb: Sprite2D
var _rotor_node: Node2D
var _rotor_angle := 0.0
var _rotor_spin := 0.0  # current speed; spins down when shot
var _t := 0.0
var _hover := 120.0
var _leave_dir := 1.0
var _spin := 0.0
var _max_health := 1
var _health_bar: Node2D
var _hero_vx := 0.0  # smoothed sideways speed of the hero, measured from his movement
var _hero_last_x := NAN


func _ready() -> void:
	add_to_group("drones")
	collision_layer = LAYER_DRONES
	collision_mask = 0  # flies through everything; only bullets hit it
	_sprite = Sprite2D.new()
	_sprite.texture = _body_texture()
	add_child(_sprite)
	_rotor_node = Node2D.new()
	_rotor_node.draw.connect(_draw_rotors)
	_sprite.add_child(_rotor_node)  # bobs, leans and flips with the drone
	_rotor_angle = randf() * TAU
	_rotor_spin = rotor_speed
	_held_bomb = Sprite2D.new()
	_held_bomb.texture = BOMB.TEXTURE
	_held_bomb.position = BOMB_MOUNT
	_held_bomb.show_behind_parent = true  # top tucked behind the belly
	_sprite.add_child(_held_bomb)  # bobs, leans and flips with the drone
	var shape := RectangleShape2D.new()
	shape.size = Vector2(TEXTURE.get_width() - 10, TEXTURE.get_height() - 6)
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
	_hover = randf_range(hover_height.x, hover_height.y)
	_max_health = health
	_health_bar = HEALTH_BAR.new()
	_health_bar.width = 20
	_health_bar.position = HEALTH_BAR_POS
	add_child(_health_bar)  # on the body, not the sprite: stays level while the drone leans
	_t = randf() * 10.0


func _physics_process(delta: float) -> void:
	_t += delta
	var hero := _hero()
	match state:
		State.CHASE:
			if hero == null:
				_leave(null)
			else:
				_chase(hero, delta)
		State.LEAVE:
			velocity = velocity.move_toward(Vector2(_leave_dir * speed * 1.4, -speed * 0.55), acceleration * delta)
			if _off_screen(96.0):
				queue_free()
		State.FALL:
			velocity.y += 500.0 * delta
			_spin += delta * 9.0
			_sprite.rotation = _spin
			if _hits_level(velocity * delta) or _off_screen(200.0):
				_boom(position, crash_damage)
				queue_free()
				return
	position += velocity * delta
	if state == State.FALL:
		_rotor_spin = move_toward(_rotor_spin, 0.0, rotor_speed * 0.7 * delta)
	_rotor_angle = fmod(_rotor_angle + _rotor_spin * delta, TAU)
	_update_rotor_node()
	if state != State.FALL:
		_sprite.position.y = sin(_t * 5.0) * 1.5  # hover bob
		_sprite.rotation = clampf(velocity.x / speed, -1.0, 1.0) * 0.18  # lean into the flight
		if absf(velocity.x) > 8.0:
			_sprite.flip_h = velocity.x < 0.0
			_held_bomb.position.x = -BOMB_MOUNT.x if _sprite.flip_h else BOMB_MOUNT.x


func _chase(hero: Node2D, delta: float) -> void:
	var feet := hero.global_position
	_track_hero(feet.x, delta)
	# Lead the hero: be where a bomb dropped now would land on him.
	var fall := _fall_time(maxf(_hover, feet.y - _held_bomb.global_position.y))
	var lead := (_hero_vx - velocity.x * BOMB.INHERIT) * fall
	var target := feet + Vector2(lead, -_hover)
	var to := target - global_position
	# Steer to the target while matching the hero's pace, so it doesn't lag behind a runner.
	var want := (to * 3.0 + Vector2(_hero_vx, 0.0)).limit_length(speed)
	velocity = velocity.move_toward(want, acceleration * delta)
	if _t >= min_chase_time and _good_drop(hero):
		_drop(hero)
	elif _t >= chase_timeout:
		_leave(hero)


## Smoothed hero speed from how his position changes: follows his current running
## direction, ignores one-frame jitters, and reads 0 when he's pushing against a wall.
func _track_hero(x: float, delta: float) -> void:
	if not is_nan(_hero_last_x) and delta > 0.0:
		var vx := (x - _hero_last_x) / delta
		_hero_vx = lerpf(_hero_vx, vx, 1.0 - exp(-hero_speed_smoothing * delta))
	_hero_last_x = x


## Seconds a dropped bomb takes to fall `height` px (it starts with no vertical speed).
static func _fall_time(height: float) -> float:
	return sqrt(2.0 * maxf(height, 0.0) / BOMB.GRAVITY)


## Would a bomb dropped now land on (near) the hero, where his current movement takes him?
## Traces the bomb's fall through the level (not the hero: he'll have moved by then), so it
## doesn't waste bombs on platforms / blocks shielding him.
func _good_drop(hero: Node2D) -> bool:
	var feet := hero.global_position
	if feet.y - global_position.y < 50.0:
		return false
	var space := get_world_2d().direct_space_state
	var p := _held_bomb.global_position
	var v := Vector2(velocity.x * BOMB.INHERIT, 0.0)
	var t := 0.0
	var step := 1.0 / 30.0
	while t < 3.0:
		v.y += BOMB.GRAVITY * step  # same order as drone_bomb.gd
		var next := p + v * step
		t += step
		var q := PhysicsRayQueryParameters2D.create(p, next + (next - p).normalized() * BOMB.LOOKAHEAD, 1)  # level only
		var hit := space.intersect_ray(q)
		if hit:
			var hero_then := feet + Vector2(_hero_vx * t, 0)
			return absf(hit.position.x - hero_then.x) <= drop_accuracy and absf(hit.position.y - feet.y) <= 30.0
		p = next
	return false


func _drop(hero: Node2D) -> void:
	var bomb := BOMB.new()
	bomb.velocity = Vector2(velocity.x * BOMB.INHERIT, 0.0)
	get_parent().add_child(bomb)
	bomb.global_position = _held_bomb.global_position  # exactly where the carried one hung
	bomb.global_rotation = _held_bomb.global_rotation
	_held_bomb.hide()
	_leave(hero)


func _leave(hero: Node2D) -> void:
	state = State.LEAVE
	# away from the hero, towards the nearer side of the screen
	var view := _view_rect()
	_leave_dir = -1.0 if global_position.x < view.get_center().x else 1.0
	if hero and absf(hero.global_position.x - global_position.x) < 40.0:
		_leave_dir = signf(global_position.x - hero.global_position.x) if global_position.x != hero.global_position.x else _leave_dir


func take_damage(amount: int, from_direction := Vector2.ZERO) -> void:
	if state == State.FALL:
		return
	health -= amount
	_health_bar.set_ratio(float(maxi(health, 0)) / _max_health)
	_sprite.modulate = Color(1.0, 0.35, 0.35)
	create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.15)
	if health <= 0:
		state = State.FALL
		collision_layer = 0
		_health_bar.hide_after(0.4)  # show it hit empty, then fade
		velocity = Vector2(from_direction.x * 60.0, -40.0)
		destroyed.emit()


## drone1.png with the painted rotor discs faded to a motion blur (motors kept solid).
## Built once and shared by all drones.
static func _body_texture() -> Texture2D:
	if _body_tex:
		return _body_tex
	var img := TEXTURE.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in mini(ROTOR_ROWS, img.get_height()):
		for x in img.get_width():
			var keep := false
			for rotor in ROTORS:
				if (rotor.motor as Rect2i).has_point(Vector2i(x, y)):
					keep = true
			if x >= 30 and x < 37:  # the arm between the rotors
				keep = true
			if not keep:
				var c := img.get_pixel(x, y)
				c.a *= ROTOR_BLUR_ALPHA
				img.set_pixel(x, y, c)
	_body_tex = ImageTexture.create_from_image(img)
	return _body_tex


## Rotor overlay draws in texture pixel coords; mirror it when the sprite is flipped.
func _update_rotor_node() -> void:
	var half := Vector2(TEXTURE.get_width(), TEXTURE.get_height()) / 2.0
	_rotor_node.scale.x = -1.0 if _sprite.flip_h else 1.0
	_rotor_node.position = Vector2(half.x if _sprite.flip_h else -half.x, -half.y)
	_rotor_node.queue_redraw()


func _draw_rotors() -> void:
	for i in ROTORS.size():
		var rotor: Dictionary = ROTORS[i]
		var a := _rotor_angle * (1.0 if i == 0 else -1.0) + i * 1.3  # counter-rotating pair
		# faint trailing blade = motion blur, then the blade itself
		_draw_blade(rotor.hub, rotor.radius, a - 0.35 * signf(_rotor_spin) * (1.0 if i == 0 else -1.0), 0.35)
		_draw_blade(rotor.hub, rotor.radius, a, 1.0)


## A two-blade propeller seen from the side: a bar through the hub whose ends trace an ellipse.
func _draw_blade(hub: Vector2, radius: float, a: float, alpha: float) -> void:
	var tip := Vector2(cos(a) * radius, sin(a) * radius * ROTOR_TILT)
	var steps := maxi(int(ceilf(absf(tip.x))), 1)
	var pixels := {}
	for s in range(-steps, steps + 1):
		pixels[(hub + tip * (float(s) / steps)).floor()] = true
	for p: Vector2 in pixels:  # outline underneath first, so it never covers the blade
		_rotor_node.draw_rect(Rect2(p + Vector2(0, 1), Vector2.ONE), Color(BLADE_DARK, alpha))
	for p: Vector2 in pixels:
		_rotor_node.draw_rect(Rect2(p, Vector2.ONE), Color(BLADE_LIGHT, alpha))


func _boom(at: Vector2, damage: int) -> void:
	var e := EXPLOSION.new()
	e.position = at
	e.damage = damage
	e.radius = 22.0
	get_parent().add_child(e)


func _hits_level(motion: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + motion, 1)
	return not get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _hero() -> Node2D:
	var heroes := get_tree().get_nodes_in_group("player")
	return heroes[0] as Node2D if not heroes.is_empty() else null


## The part of the world the screen shows now.
func _view_rect() -> Rect2:
	var vp := get_viewport()
	return vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()


func _off_screen(margin: float) -> bool:
	return not _view_rect().grow(margin).has_point(global_position)
