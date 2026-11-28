extends CharacterBody2D
## Robot dog.
## Patrol: walks back and forth on the ground ("walk"). At a wall or ledge it stops,
## plays "idle" for idle_time, then turns around.
## Chase: when shot (from any side, up to alert_range away), or when the player is in front of it, within sight_range and not hidden behind a
## block, it runs at them ("run"). It won't run off ledges or through walls: there it stands
## ("idle") facing the player. It gives up after losing them for lose_time seconds.
## Attack: once the player is within attack_range it stops and head-butts ("attack"); the
## hit lands when the head is fully forward (attack_hit_time) and deals attack_damage.
## Bullets call take_damage(); at 0 health it collapses ("dying"), lies on the ground for
## corpse_time, then fades out and is removed.
## The sheets (assets/sprites/enemies/enemy1_*.png) face right.

enum State { PATROL, PAUSE, CHASE, ATTACK }

@export_group("Patrol")
@export_range(0.0, 200.0, 1.0, "suffix:px/s") var speed := 30.0
## Seconds it stands idle at each end of its patrol before turning back.
@export_range(0.0, 10.0, 0.1, "suffix:s") var idle_time := 1.6
## Starting direction: -1 = left, 1 = right.
@export_enum("Left:-1", "Right:1") var start_direction := -1

@export_group("Chase")
## Faster than the player runs (143), slower than they sprint (165): sprint to escape.
@export_range(0.0, 400.0, 1.0, "suffix:px/s") var run_speed := 150.0
## How far ahead it notices the player.
@export_range(16.0, 800.0, 8.0, "suffix:px") var sight_range := 176.0
## How far above/below its own height it notices the player.
@export_range(8.0, 200.0, 4.0, "suffix:px") var sight_height := 40.0
## Chasing stops once the player is this far away...
@export_range(16.0, 1000.0, 8.0, "suffix:px") var lose_range := 280.0
## ...or out of sight for this long.
@export_range(0.0, 10.0, 0.1, "suffix:s") var lose_time := 1.2
## Stops running when this close to the player (horizontally).
@export_range(0.0, 64.0, 1.0, "suffix:px") var stop_distance := 14.0
## When shot, it finds the shooter within this distance (any direction) and chases them,
## and keeps chasing until they get this far away (instead of lose_range).
@export_range(16.0, 2000.0, 8.0, "suffix:px") var alert_range := 480.0

@export_group("Attack")
## Starts a head-butt when the player is this close (horizontally, origin to origin).
@export_range(8.0, 80.0, 1.0, "suffix:px") var attack_range := 30.0
@export_range(0, 20, 1) var attack_damage := 1
## When in the attack the head hits: frame 3 of 9 at 10 fps = 0.3 s.
@export_range(0.0, 0.9, 0.05, "suffix:s") var attack_hit_time := 0.3
## Pause after a head-butt before the next one.
@export_range(0.0, 5.0, 0.05, "suffix:s") var attack_cooldown := 0.5

@export_group("Health")
@export_range(1, 100, 1) var max_health := 8
## Seconds the wreck stays on the ground after the dying animation, before fading out.
@export_range(0.0, 60.0, 0.5, "suffix:s") var corpse_time := 4.0

@export_group("Physics")
@export_range(100.0, 3000.0, 10.0, "suffix:px/s²") var gravity := 900.0

const WORLD_MASK := 1   # layer 1 "world"
const PLAYER_MASK := 2  # layer 2 "player"
## run_speed the "run" animation is drawn for; faster running plays it faster so the feet don't slide.
const RUN_ANIM_SPEED := 95.0
const HEALTH_BAR := preload("res://scripts/health_bar.gd")
## Where the health bar sits: centred above the head (feet = 0).
const HEALTH_BAR_POS := Vector2(0, -42)
const ATTACK_LENGTH := 0.9  # the "attack" animation's length
const DYING_LENGTH := 0.9   # the "dying" animation's length
## Head hitbox during the head-butt, relative to the feet, for a dog facing right.
const HEAD_BOX := Rect2(10, -36, 28, 26)
const EYE := Vector2(0, -30)  # its eye height, for line-of-sight checks
## Points on the player (from their feet) it tries to see: chest and head.
const TARGET_POINTS := [Vector2(0, -24), Vector2(0, -40)]

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _anim: AnimationPlayer = $AnimationPlayer

var health := 0
var state := State.PATROL
var _dir := -1
var _dead := false
var _pause_left := 0.0
var _target: Node2D = null
var _unseen := 0.0
var _provoked := false  # chasing because it was shot: uses alert_range to give up
var _sight_shape := RectangleShape2D.new()
var _health_bar: Node2D
var _attack_t := 0.0
var _attack_hit_done := false
var _attack_cooldown_left := 0.0


func _ready() -> void:
	health = max_health
	_health_bar = HEALTH_BAR.new()
	_health_bar.position = HEALTH_BAR_POS
	add_child(_health_bar)
	_set_dir(start_direction)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	velocity.y = minf(velocity.y + gravity * delta, 400.0)
	_attack_cooldown_left -= delta
	if state == State.PATROL or state == State.PAUSE:
		var seen := _look_for_player()
		if seen:
			_target = seen
			_unseen = 0.0
			state = State.CHASE
	match state:
		State.PATROL:
			if is_on_floor() and (is_on_wall() or _ledge_ahead()):
				state = State.PAUSE
				_pause_left = idle_time
				velocity.x = 0.0
			else:
				velocity.x = _dir * speed
		State.PAUSE:
			velocity.x = 0.0
			_pause_left -= delta
			if _pause_left <= 0.0:
				_set_dir(-_dir)
				state = State.PATROL
		State.CHASE:
			_chase(delta)
		State.ATTACK:
			_attack(delta)
	_play(_wanted_anim())
	move_and_slide()


func _chase(delta: float) -> void:
	var give_up_range := alert_range if _provoked else lose_range
	if not is_instance_valid(_target) or global_position.distance_to(_target.global_position) > give_up_range:
		_stop_chase()
		return
	_unseen = 0.0 if _can_see(_target) else _unseen + delta
	if _unseen > lose_time:
		_stop_chase()
		return
	var dx := _target.global_position.x - global_position.x
	if absf(dx) > 2.0:
		_set_dir(signf(dx))
	var dy := _target.global_position.y - global_position.y
	if absf(dx) <= attack_range and absf(dy) < 24.0 and is_on_floor():
		velocity.x = 0.0
		if _attack_cooldown_left <= 0.0:
			_start_attack()
		return
	if absf(dx) <= stop_distance or (is_on_floor() and _ledge_ahead()) or _wall_ahead():
		velocity.x = 0.0  # reached them, or can't go further: stand and face them
	else:
		velocity.x = _dir * run_speed


func _start_attack() -> void:
	state = State.ATTACK
	_attack_t = 0.0
	_attack_hit_done = false
	_anim.play("attack")


func _attack(delta: float) -> void:
	velocity.x = 0.0
	_attack_t += delta
	if not _attack_hit_done and _attack_t >= attack_hit_time:
		_attack_hit_done = true
		_head_hit()
	if _attack_t >= ATTACK_LENGTH:
		_attack_cooldown_left = attack_cooldown
		state = State.CHASE
		_unseen = 0.0


## Damages whatever player body is in the head hitbox.
func _head_hit() -> void:
	var box := RectangleShape2D.new()
	box.size = HEAD_BOX.size
	var center := HEAD_BOX.get_center()
	center.x *= _dir
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = box
	q.collision_mask = PLAYER_MASK
	q.transform = Transform2D(0.0, global_position + center)
	q.exclude = [get_rid()]
	for hit in get_world_2d().direct_space_state.intersect_shape(q, 4):
		if hit.collider.has_method("take_damage"):
			hit.collider.take_damage(attack_damage, Vector2(_dir, 0))


func _stop_chase() -> void:
	_target = null
	_provoked = false
	state = State.PATROL
	velocity.x = 0.0


func _wanted_anim() -> String:
	if state == State.ATTACK:
		return "attack"
	if state == State.CHASE and velocity.x != 0.0:
		return "run"
	if velocity.x != 0.0:
		return "walk"
	return "idle"


func _play(anim_name: String) -> void:
	if _anim.current_animation != anim_name:
		var rate := run_speed / RUN_ANIM_SPEED if anim_name == "run" else 1.0
		_anim.play(anim_name, -1, rate)


func _set_dir(d: float) -> void:
	_dir = 1 if d > 0 else -1
	_sprite.flip_h = _dir < 0


## The player body inside the box in front of it, if it has a clear line of sight to it.
func _look_for_player() -> Node2D:
	_sight_shape.size = Vector2(sight_range, sight_height * 2.0)
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = _sight_shape
	q.collision_mask = PLAYER_MASK
	q.transform = Transform2D(0.0, global_position + Vector2(_dir * sight_range / 2.0, EYE.y))
	q.exclude = [get_rid()]
	for hit in get_world_2d().direct_space_state.intersect_shape(q, 4):
		var body = hit.collider
		if body is Node2D and _can_see(body):
			return body
	return null


## True when no world block hides the target's chest or head from its eyes.
func _can_see(target: Node2D) -> bool:
	var space := get_world_2d().direct_space_state
	for point in TARGET_POINTS:
		var q := PhysicsRayQueryParameters2D.create(global_position + EYE, target.global_position + point, WORLD_MASK)
		if space.intersect_ray(q).is_empty():
			return true
	return false


## True when there's no ground just past the front of the body.
func _ledge_ahead() -> bool:
	var ahead := global_transform.translated(Vector2(_dir * 20.0, 0.0))
	return not test_move(ahead, Vector2(0.0, 4.0))


## True when a wall is right in front of it.
func _wall_ahead() -> bool:
	return test_move(global_transform, Vector2(_dir * 2.0, 0.0))


## from_direction: the bullet's flight direction (so the shooter is the opposite way).
func take_damage(amount: int, from_direction := Vector2.ZERO) -> void:
	if _dead:
		return
	health -= amount
	_health_bar.set_ratio(float(health) / max_health)
	_sprite.modulate = Color(3, 3, 3)  # white flash
	create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.1)
	if health <= 0:
		_die()
		return
	_provoke(from_direction)


## Shot: turn toward the shooter and chase them, even from behind or out of sight range.
func _provoke(from_direction: Vector2) -> void:
	if state == State.ATTACK:
		return  # finish the head-butt first
	if from_direction.x != 0.0:
		_set_dir(-signf(from_direction.x))
	var shooter := _find_player_near(alert_range)
	if shooter == null:
		return
	_target = shooter
	_unseen = 0.0
	_provoked = true
	state = State.CHASE
	_set_dir(signf(shooter.global_position.x - global_position.x))


## The nearest player body within radius, in any direction.
func _find_player_near(radius: float) -> Node2D:
	var circle := CircleShape2D.new()
	circle.radius = radius
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = circle
	q.collision_mask = PLAYER_MASK
	q.transform = Transform2D(0.0, global_position + Vector2(0, EYE.y))
	q.exclude = [get_rid()]
	var best: Node2D = null
	for hit in get_world_2d().direct_space_state.intersect_shape(q, 4):
		var body = hit.collider
		if body is Node2D and (best == null or global_position.distance_to(body.global_position) < global_position.distance_to(best.global_position)):
			best = body
	return best


func _die() -> void:
	_dead = true
	collision_layer = 0  # bullets pass through the wreck, nothing collides with it
	velocity = Vector2.ZERO
	_anim.play("dying")
	_health_bar.hide_after(0.4)  # show it hit empty, then fade
	var t := create_tween()
	t.tween_interval(DYING_LENGTH + corpse_time)
	t.tween_property(_sprite, "modulate:a", 0.0, 0.6)
	t.tween_callback(queue_free)
