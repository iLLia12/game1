extends CharacterBody2D
## Contra-style player: run (default), sprint (hold Shift), sneak (hold P), jump, 8-way aim, shoot.
## Every tunable value is in the Inspector. Hover a property to see what it does.
## Tip: while the game runs, select Player in the Scene dock's "Remote" tab to tweak values live.

const BULLET_SCENE := preload("res://scenes/bullet.tscn")

@export_group("Speed")
## Default movement speed (px/s).
@export_range(0.0, 400.0, 1.0, "or_greater", "suffix:px/s") var run_speed := 110.0
## Speed while holding Shift (px/s).
@export_range(0.0, 600.0, 1.0, "or_greater", "suffix:px/s") var sprint_speed := 165.0
## Speed while holding P to sneak (px/s). Keep it well below run_speed.
@export_range(0.0, 400.0, 1.0, "or_greater", "suffix:px/s") var sneak_speed := 45.0
## How fast the hero speeds up (px/s²). 0 = reaches full speed instantly.
@export_range(0.0, 5000.0, 10.0, "or_greater", "suffix:px/s²") var acceleration := 0.0
## How fast the hero slows down when you let go (px/s²). 0 = stops instantly.
@export_range(0.0, 5000.0, 10.0, "or_greater", "suffix:px/s²") var deceleration := 0.0

@export_group("Jump")
## Jump height when the button is held (px). One tile is 16 px.
@export_range(0.0, 200.0, 0.5, "or_greater", "suffix:px") var jump_height := 49.0
## Downward pull (px/s²). Higher = snappier, shorter jumps.
@export_range(100.0, 3000.0, 10.0, "or_greater", "suffix:px/s²") var gravity := 900.0
## Extra gravity while falling. 1 = same as rising; 1.5-2 = heavier, punchier landings.
@export_range(1.0, 4.0, 0.05) var fall_gravity_multiplier := 1.0
## Maximum falling speed (px/s).
@export_range(50.0, 1000.0, 10.0, "or_greater", "suffix:px/s") var max_fall_speed := 400.0
## Upward speed kept when jump is released early. 0.5 = short hops on a tap; 1 = always full jump.
@export_range(0.0, 1.0, 0.05) var jump_cut_multiplier := 0.5
## Grace time to still jump after walking off a ledge (s).
@export_range(0.0, 0.3, 0.01, "suffix:s") var coyote_time := 0.08
## A jump pressed this long before landing still counts (s).
@export_range(0.0, 0.3, 0.01, "suffix:s") var jump_buffer_time := 0.1

@export_group("Shooting")
## Time between shots while holding fire (s).
@export_range(0.02, 1.0, 0.01, "suffix:s") var fire_interval := 0.12

@export_group("Animation")
## Legs advance by distance, so they keep pace with the ground. Each *_px_per_frame is the
## distance moved per sheet frame (whole cycle = frame count x this).
## Bigger = slower legs (feet may slide).
@export_range(0.5, 40.0, 0.5, "suffix:px") var run_px_per_frame := 6.0
## Run frames to play, in order (0-7 = frames of states/run/run.png, left-to-right, top-to-bottom).
@export var run_sequence: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
## Sprint (Shift) legs: distance moved per frame of states/run/run_x1.5_faster.png.
## At the same value as run, the 1.5x faster sprint plays the cycle 1.5x faster.
@export_range(0.5, 40.0, 0.5, "suffix:px") var sprint_px_per_frame := 6.0
## Sprint frames to play, in order (0-7 = frames of states/run/run_x1.5_faster.png).
@export var sprint_sequence: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
## Sneak (P) legs: distance moved per frame of states/sneaking/sneaking.png.
@export_range(0.5, 40.0, 0.5, "suffix:px") var sneak_px_per_frame := 4.0
## Sneak frames to play, in order (0-11 = frames of states/sneaking/sneaking.png).
@export var sneak_sequence: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
## Idle (breathing) animation speed.
@export_range(0.5, 30.0, 0.5, "suffix:fps") var idle_fps := 6.0
## Idle frames to play, in order (0-7 = frames of states/idel/idel1.png and idel2.png).
@export var idle_sequence: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]

@export_subgroup("Jump")
## Jump frames are 0-8 of states/jump/jump1.png (left-to-right, top-to-bottom):
## 0 stand, 1-2 crouch, 3 push-off, 4 tuck, 5 reach, 6 legs down, 7 touchdown, 8 recover.
## Frames shown, in order, right as the hero leaves the ground.
@export var jump_takeoff_frames: Array[int] = [2, 3]
## How long the take-off frames show (s), split evenly between them.
@export_range(0.0, 0.3, 0.01, "suffix:s") var takeoff_pose_time := 0.08
## Frame while going up.
@export_range(0, 8) var jump_rise_frame := 3
## Frame around the top of the jump.
@export_range(0, 8) var jump_peak_frame := 4
## Frame while falling.
@export_range(0, 8) var jump_fall_frame := 5
## Frame while falling fast (also when dropping off a ledge for a while).
@export_range(0, 8) var jump_fall_fast_frame := 6
## Rising faster than this (px/s) shows the rise frame; slower shows the peak frame.
@export_range(0.0, 400.0, 5.0, "suffix:px/s") var peak_speed := 60.0
## Falling faster than this (px/s) shows the fast-fall frame.
@export_range(0.0, 400.0, 5.0, "suffix:px/s") var fall_fast_speed := 200.0
## Frames shown, in order, on touchdown.
@export var jump_land_frames: Array[int] = [7, 8]
## How long the landing frames show (s), split evenly between them. Running cuts it short.
@export_range(0.0, 0.5, 0.01, "suffix:s") var landing_pose_time := 0.1

# hero/states/<state>/*.png sheets, 5 columns wide. Sprite origin is at the feet.
# idle/run: 68x68 cells, 2 rows, 8 frames. sneaking: 68x68, 3 rows, 12 frames.
# sprint (run_x1.5_faster): 80x80, 2 rows, 8 frames. jump: 80x80, 2 rows, 9 frames.
# offset puts the cell's foot line on the origin and its centre on x = 0.
# Each time the hero enters idle from another state, one idle variant is picked at random.
const IDLE_SHEETS := [
	{"tex": preload("res://assets/sprites/hero/states/idel/idel1.png"), "rows": 2, "frames": 8, "offset": Vector2(-34, -57)},
	{"tex": preload("res://assets/sprites/hero/states/idel/idel2.png"), "rows": 2, "frames": 8, "offset": Vector2(-34, -57)},
]
const RUN_SHEET := {"tex": preload("res://assets/sprites/hero/states/run/run.png"), "rows": 2, "frames": 8, "offset": Vector2(-34, -57)}
const SPRINT_SHEET := {"tex": preload("res://assets/sprites/hero/states/run/run_x1.5_faster.png"), "rows": 2, "frames": 8, "offset": Vector2(-40, -64)}
const SNEAK_SHEET := {"tex": preload("res://assets/sprites/hero/states/sneaking/sneaking.png"), "rows": 3, "frames": 12, "offset": Vector2(-34, -57)}
const JUMP_SHEET := {"tex": preload("res://assets/sprites/hero/states/jump/jump1.png"), "rows": 2, "frames": 9, "offset": Vector2(-40, -64)}
const SHEET_COLUMNS := 5

var facing := 1
var aim := Vector2.RIGHT
var _coyote := 0.0
var _jump_buffer := 0.0
var _fire_cooldown := 0.0

var _moving := false
var _cycle_pos := 0.0  # position in the leg cycle, 0..1 (shared by sneak/run/sprint)
var _idle_time := 0.0
var _idle_sheet = null  # idle variant picked for the current idle stretch (null = pick on entry)
var _takeoff_timer := 0.0
var _land_timer := 0.0
var _was_on_floor := true

@onready var muzzle: Marker2D = $Muzzle
@onready var sprite: Sprite2D = $Sprite2D


func _physics_process(delta: float) -> void:
	var move_x := Input.get_axis("move_left", "move_right")
	var aim_y := Input.get_axis("aim_up", "aim_down")
	var gait := _current_gait()

	if move_x != 0.0:
		facing = int(signf(move_x))

	# Gravity (optionally heavier on the way down)
	var g := gravity * (fall_gravity_multiplier if velocity.y > 0.0 else 1.0)
	velocity.y = minf(velocity.y + g * delta, max_fall_speed)

	# Coyote time + jump buffer
	_coyote = coyote_time if is_on_floor() else _coyote - delta
	_jump_buffer = jump_buffer_time if Input.is_action_just_pressed("jump") else _jump_buffer - delta
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = -_jump_speed(delta)
		_jump_buffer = 0.0
		_coyote = 0.0
		_takeoff_timer = takeoff_pose_time
	# Variable jump height
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut_multiplier

	# Contra rule: holding down on the ground = prone, no running
	var prone := is_on_floor() and aim_y > 0.0 and move_x == 0.0
	var target_x := move_x * _gait_speed(gait)
	var rate := acceleration if move_x != 0.0 else deceleration
	velocity.x = target_x if rate <= 0.0 else move_toward(velocity.x, target_x, rate * delta)
	move_and_slide()

	if is_on_floor() and not _was_on_floor:
		_land_timer = landing_pose_time
	_was_on_floor = is_on_floor()

	_update_aim(move_x, aim_y, prone)
	_fire_cooldown -= delta
	if Input.is_action_pressed("shoot") and _fire_cooldown <= 0.0:
		_shoot()
		_fire_cooldown = fire_interval
	_update_animation(gait, delta)


## Launch speed that peaks at exactly jump_height, accounting for the fixed physics step
## (the plain sqrt(2gh) formula overshoots by ~3 px at 60 Hz).
func _jump_speed(delta: float) -> float:
	var half_step := gravity * delta * 0.5
	return sqrt(2.0 * gravity * jump_height + half_step * half_step) - half_step


## Run is the default; holding P walks, holding Shift sprints (P wins if both are held).
func _current_gait() -> String:
	if Input.is_action_pressed("walk"):
		return "walk"
	if Input.is_action_pressed("sprint"):
		return "sprint"
	return "run"


func _gait_speed(gait: String) -> float:
	match gait:
		"sprint":
			return sprint_speed
		"walk":
			return sneak_speed
	return run_speed


func _update_aim(move_x: float, aim_y: float, prone: bool) -> void:
	if prone:
		aim = Vector2(facing, 0)
	elif aim_y != 0.0 and move_x == 0.0:
		# Straight up / straight down (down only in the air)
		aim = Vector2(0, aim_y) if (aim_y < 0.0 or not is_on_floor()) else Vector2(facing, 0)
	elif aim_y != 0.0:
		aim = Vector2(facing, aim_y).normalized()
	else:
		aim = Vector2(facing, 0)
	# Forward shots leave from the front hand; other angles from around the chest
	muzzle.position = Vector2(10 * facing, -20) if aim.y == 0.0 else Vector2(0, -24) + aim * 14.0


func _shoot() -> void:
	var b := BULLET_SCENE.instantiate()
	b.global_position = muzzle.global_position
	b.direction = aim
	get_parent().add_child(b)


func _update_animation(gait: String, delta: float) -> void:
	sprite.scale.x = facing
	_takeoff_timer -= delta
	_land_timer -= delta

	if not is_on_floor():
		_moving = false
		_idle_sheet = null
		var f := jump_fall_frame
		if _takeoff_timer > 0.0 and not jump_takeoff_frames.is_empty():
			f = _pick(jump_takeoff_frames, 1.0 - _takeoff_timer / takeoff_pose_time)
		elif velocity.y < -peak_speed:
			f = jump_rise_frame
		elif velocity.y < peak_speed:
			f = jump_peak_frame
		elif velocity.y > fall_fast_speed:
			f = jump_fall_fast_frame
		_show(JUMP_SHEET, f)
		return

	# Use the real movement so pushing against a wall shows idle, not running on the spot
	var speed_x := absf(get_real_velocity().x)
	if speed_x > 1.0:
		_land_timer = 0.0  # running away cancels the landing pose
		if not _moving:
			_moving = true
			_cycle_pos = 0.125  # start mid-stride so the first step reads immediately
		# Shift = sprint, P = sneak, otherwise run. Phase carries over when switching.
		var sheet: Dictionary = RUN_SHEET
		var px := run_px_per_frame
		var seq := run_sequence
		if gait == "sprint":
			sheet = SPRINT_SHEET
			px = sprint_px_per_frame
			seq = sprint_sequence
		elif gait == "walk":
			sheet = SNEAK_SHEET
			px = sneak_px_per_frame
			seq = sneak_sequence
		var cycle_len: float = px * (sheet.frames if seq.is_empty() else seq.size())
		_cycle_pos = fposmod(_cycle_pos + speed_x * delta / cycle_len, 1.0)
		_idle_sheet = null
		_show(sheet, int(_cycle_pos * sheet.frames) if seq.is_empty() else _pick(seq, _cycle_pos))
		return

	_moving = false
	if _land_timer > 0.0 and not jump_land_frames.is_empty():
		_idle_sheet = null
		_show(JUMP_SHEET, _pick(jump_land_frames, 1.0 - _land_timer / landing_pose_time))
		return

	if _idle_sheet == null:
		# Just came from another state: pick an idle variant and start it from frame 0
		_idle_sheet = IDLE_SHEETS.pick_random()
		_idle_time = 0.0
	_idle_time += delta
	if idle_sequence.is_empty():
		_show(_idle_sheet, 0)
	else:
		var n := idle_sequence.size()
		_show(_idle_sheet, _pick(idle_sequence, fmod(_idle_time * idle_fps, n) / n))


## Entry of seq at position t (0..1).
func _pick(seq: Array[int], t: float) -> int:
	return seq[clampi(int(t * seq.size()), 0, seq.size() - 1)]


## Show frame `frame` of the given sheet, switching texture/grid/offset when the sheet changes.
func _show(sheet: Dictionary, frame: int) -> void:
	if sprite.texture != sheet.tex:
		sprite.texture = sheet.tex
		sprite.hframes = SHEET_COLUMNS
		sprite.vframes = sheet.rows
		sprite.offset = sheet.offset
	sprite.frame = clampi(frame, 0, sheet.frames - 1)
