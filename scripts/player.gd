extends CharacterBody2D
## Contra-style player: run (default), sprint (hold Shift), sneak (hold S / Down while moving), jump, 8-way aim, shoot.
## Every tunable value is in the Inspector. Hover a property to see what it does.
## Tip: while the game runs, select Player in the Scene dock's "Remote" tab to tweak values live.

const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const MUZZLE_SMOKE := preload("res://scripts/muzzle_smoke.gd")

@export_group("Speed")
## Default movement speed (px/s).
@export_range(0.0, 400.0, 1.0, "or_greater", "suffix:px/s") var run_speed := 143.0
## Speed while holddding Shift (px/s).
@export_range(0.0, 600.0, 1.0, "or_greater", "suffix:px/s") var sprint_speed := 165.0
## Speed while sneaking: S / Down held while moving on the ground (px/s). Keep it well below run_speed.
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

@export_group("Dust")
## Landings faster than this (px/s) kick up a puff of dust. Lower = dust on small drops too.
@export_range(0.0, 600.0, 10.0, "suffix:px/s") var landing_dust_speed := 100.0

@export_group("Shooting")
@export_subgroup("Shotgun")
## Time between shots while holding fire (s). Shotgun = slow and heavy.
@export_range(0.02, 2.0, 0.01, "suffix:s") var fire_interval := 0.55
## Pellets per shot.
@export_range(1, 20, 1) var pellet_count := 7
## Total width of the pellet cone (degrees).
@export_range(0.0, 60.0, 1.0, "suffix:°") var pellet_spread := 14.0
## How far pellets fly before vanishing (px); each pellet varies by +-pellet_range_jitter.
@export_range(16.0, 400.0, 4.0, "suffix:px") var pellet_range := 96.0
@export_range(0.0, 0.5, 0.05) var pellet_range_jitter := 0.2
## Pellet speed (px/s); each pellet varies by +-15%.
@export_range(100.0, 1000.0, 10.0, "suffix:px/s") var pellet_speed := 420.0

@export_subgroup("Vintorez")
## Time between shots while holding fire (s). Suppressed rifle: one accurate round, faster follow-up.
@export_range(0.02, 2.0, 0.01, "suffix:s") var vintorez_fire_interval := 0.3
## How far a round flies before vanishing (px).
@export_range(16.0, 1000.0, 8.0, "suffix:px") var vintorez_range := 400.0
## Round speed (px/s).
@export_range(100.0, 2000.0, 10.0, "suffix:px/s") var vintorez_speed := 800.0
## Muzzle smoke size compared to the shotgun (it's suppressed: just a wisp).
@export_range(0.0, 1.0, 0.05) var vintorez_smoke := 0.3

@export_group("Animation")
## Draws the hero this many px lower than the collision box, so the boots sink slightly
## into the ground surface instead of looking like they hover on it. Visual only.
@export_range(0, 4, 1, "suffix:px") var feet_sink := 1
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
## Sneak (S / Down) legs: distance moved per frame of states/sneaking/sneaking.png.
@export_range(0.5, 40.0, 0.5, "suffix:px") var sneak_px_per_frame := 4.0
## Sneak frames to play, in order (0-11 = frames of states/sneaking/sneaking.png).
@export var sneak_sequence: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
## Sneak frame held while S / Down is held standing still (0 = lowest crouch, both feet down).
@export_range(0, 11) var sneak_stand_frame := 0
## Idle (breathing) animation speed.
@export_range(0.5, 30.0, 0.5, "suffix:fps") var idle_fps := 6.0
## Idle frames to play, in order (0-7 = frames of states/idle/idle1.png and idle2.png).
@export var idle_sequence: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
## Idle speed with a weapon in hand (states/idle/idle_with_no_weapon.png, all frames in order).
@export_range(0.5, 30.0, 0.5, "suffix:fps") var armed_idle_fps := 8.0

@export_subgroup("Slide")
## Letting go of the direction keys while sprinting skids to a stop with
## states/sliding/feet_braking.png (frames 0-8) instead of stopping dead.
@export var slide_enabled := true
## How far the skid carries the hero (px) before he comes to a halt.
@export_range(0.0, 200.0, 1.0, "suffix:px") var slide_distance := 40.0
## Slide animation speed. The whole sequence plays once.
@export_range(1.0, 30.0, 0.5, "suffix:fps") var slide_fps := 15.0
## Slide frames to play, in order (0-8).
@export var slide_sequence: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8]

@export_subgroup("Jump")
## Space jump plays states/jump/jump-up.png (frames 0-8: 0-3 crouch, 4 push-off,
## 5 full stretch, 6-8 feet leaving the ground).
## These frames are spread over the rise, from take-off to the top of the jump.
@export var jump_up_sequence: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8]
## jump-up frame held from the top of a Space jump until landing.
@export_range(0, 8) var jump_up_fall_frame := 8
## Walking/running off a ledge uses states/jump/jump-off.png (frames 0-8: 0 stand,
## 1-2 crouch, 3 push-off, 4 tuck, 5 reach, 6 legs down, 7 touchdown, 8 recover).
## jump-off frame while dropping off a ledge.
@export_range(0, 8) var jump_off_fall_frame := 5
## jump-off frame once falling faster than fall_fast_speed.
@export_range(0, 8) var jump_off_fall_fast_frame := 6
## Falling faster than this (px/s) after leaving a ledge shows the fast-fall frame.
@export_range(0.0, 400.0, 5.0, "suffix:px/s") var fall_fast_speed := 200.0
## jump-off frames shown, in order, on touchdown (after either kind of jump).
@export var jump_land_frames: Array[int] = [7, 8]
## How long the landing frames show (s), split evenly between them. Running cuts it short.
@export_range(0.0, 0.5, 0.01, "suffix:s") var landing_pose_time := 0.1

# hero/states/<state>/*.png sheets, 5 columns wide. Sprite origin is at the feet.
# idle/run: 68x68 cells, 2 rows, 8 frames. sneaking: 68x68, 3 rows, 12 frames.
# sprint (run_x1.5_faster): 80x80, 2 rows, 8 frames.
# jump-up: 68x68, 2 rows, 9 frames. jump-off: 80x80, 2 rows, 9 frames.
# offset puts the cell's foot line on the origin and its centre on x = 0.
# Each time the hero enters idle from another state, one idle variant is picked at random.
const IDLE_SHEETS := [
	{"tex": preload("res://assets/sprites/hero/states/idle/idle1.png"), "rows": 2, "frames": 8, "offset": Vector2(-34, -57)},
	{"tex": preload("res://assets/sprites/hero/states/idle/idle2.png"), "rows": 2, "frames": 8, "offset": Vector2(-34, -57)},
]
const RUN_SHEET := {"tex": preload("res://assets/sprites/hero/states/run/run.png"), "rows": 2, "frames": 8, "offset": Vector2(-34, -57)}
const SPRINT_SHEET := {"tex": preload("res://assets/sprites/hero/states/run/run_x1.5_faster.png"), "rows": 2, "frames": 8, "offset": Vector2(-40, -64)}
const SLIDE_SHEET := {"tex": preload("res://assets/sprites/hero/states/sliding/feet_braking.png"), "rows": 2, "frames": 9, "offset": Vector2(-34, -56)}
const SNEAK_SHEET := {"tex": preload("res://assets/sprites/hero/states/sneaking/sneaking.png"), "rows": 3, "frames": 12, "offset": Vector2(-34, -57)}
const JUMP_UP_SHEET := {"tex": preload("res://assets/sprites/hero/states/jump/jump-up.png"), "rows": 2, "frames": 9, "offset": Vector2(-34, -57)}
const JUMP_OFF_SHEET := {"tex": preload("res://assets/sprites/hero/states/jump/jump-off.png"), "rows": 2, "frames": 9, "offset": Vector2(-40, -64)}
const SHEET_COLUMNS := 5
## With the gun, each sheet is swapped for <name>-with-gun.png (or <name>_with_gun.png) found
## anywhere under this folder (trailing digits ignored, so idle_with_gun covers idle1 and idle2).
## No such file = default sheet.
const STATES_DIR := "res://assets/sprites/hero/states"
const GUN_SUFFIXES := ["-with-gun", "_with_gun"]

## Weapons the hero can carry. Idle with a weapon = ARMED_IDLE (hands ready, no weapon drawn)
## with the weapon picture put in the front hand of every frame, built when it's picked up.
##   art: weapon picture (any size/angle; it's laid flat and shrunk to `length` px)
##   grip: where the front hand holds it, 0 = stock end, 1 = muzzle
##   gun_sheets: other animations use the *_with_gun sheets (they're drawn with the shotgun)
##   name / icon: how it shows in the inventory
const WEAPON_ART := preload("res://scripts/weapon_art.gd")
const ARMED_IDLE := preload("res://assets/sprites/hero/states/idle/idle_with_no_weapon.png")
const WEAPONS := {
	"shotgun": {"art": "res://assets/sprites/hero/states/idle/weapons/shotgun.png", "length": 26, "grip": 0.62, "gun_sheets": true,
		"name": "Shotgun", "icon": "res://assets/sprites/objects/pickable/weapons/shotgun_pickup.png"},
	"vintorez": {"art": "res://assets/sprites/hero/states/idle/weapons/vintorez.png", "length": 34, "grip": 0.55, "gun_sheets": false,
		"name": "Vintorez", "icon": "res://assets/sprites/objects/pickable/weapons/vintorez_pickup.png"},
}

## Weapons collected so far, in pickup order (shown in the inventory).
var weapons: Array[String] = []

var facing := 1
var aim := Vector2.RIGHT
var _coyote := 0.0
var _jump_buffer := 0.0
var _fire_cooldown := 0.0

var _moving := false
var _cycle_pos := 0.0  # position in the leg cycle, 0..1 (shared by sneak/run/sprint)
var _idle_time := 0.0
var _idle_sheet = null  # idle variant picked for the current idle stretch (null = pick on entry)
var _space_jump := false  # true from a Space jump until landing; false = dropped off a ledge
var _jump_launch_speed := 1.0  # upward speed at take-off, to track progress through the rise
var _land_timer := 0.0
var _was_on_floor := true
var _slide_timer := 0.0  # > 0 while the sprint-stop slide plays
var _slide_decel := 0.0  # px/s² that brings the skid to a halt over slide_distance
var _was_sprint_moving := false  # last frame: sprinting on the ground and actually moving
var _last_speed_x := 0.0  # last frame's real horizontal speed

## Weapon in hand (a key of WEAPONS), "" = unarmed.
var weapon := ""
## True once a weapon pickup is collected.
var has_gun: bool:
	get:
		return weapon != ""
var _armed_idle := {}   # weapon -> idle sheet Dictionary with that weapon in hand
var _muzzle_forward := Vector2(22, -22)  # barrel tip for straight shots, relative to the feet
var _gun_files := {}    # sheet name -> res:// path of its -with-gun.png
var _gun_sheets := {}   # default texture -> gun sheet Dictionary ({} = no gun version)

@onready var muzzle: Marker2D = $Muzzle
@onready var sprite: Sprite2D = $Sprite2D
@onready var dust = $FootDust


func _ready() -> void:
	add_to_group("help")  # controls list in the top-right corner (input_display.gd)
	_scan_gun_sheets(STATES_DIR)


## Called by a weapon pickup. Picking up another weapon swaps to it.
func pick_up_gun(id := "shotgun") -> void:
	if not WEAPONS.has(id):
		push_warning("Unknown weapon '%s'" % id)
		return
	if id not in weapons:
		weapons.append(id)
	equip(id)


## Take a collected weapon in hand (used by pickups and the inventory).
func equip(id: String) -> void:
	if id not in weapons or id == weapon:
		return
	weapon = id
	_muzzle_forward = _armed_idle_sheet().muzzle
	_idle_sheet = null  # restart idle with the new weapon
	sprite.texture = null  # force _show to switch sheets
	# Redraw now: from the inventory the game is paused, so there's no next frame to do it
	_update_animation(_current_gait(), 0.0)


## Idle sheet for the current weapon (built on first use, then cached).
func _armed_idle_sheet() -> Dictionary:
	if not _armed_idle.has(weapon):
		var w: Dictionary = WEAPONS[weapon]
		var held := WEAPON_ART.held_sprite(load(w.art).get_image(), w.length)
		var built: Dictionary = WEAPON_ART.armed_sheet(ARMED_IDLE.get_image(), held, w.grip, SHEET_COLUMNS)
		var sheet := _measure_sheet(ImageTexture.create_from_image(built.image))
		sheet.muzzle = Vector2(built.muzzle) + sheet.offset + Vector2(0, feet_sink)
		_armed_idle[weapon] = sheet
	return _armed_idle[weapon]


func _physics_process(delta: float) -> void:
	# signf: an analog stick past the deadzone counts as fully pressed (digital, like the keys/D-pad)
	var move_x := signf(Input.get_axis("move_left", "move_right"))
	var aim_y := signf(Input.get_axis("aim_up", "aim_down"))
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
		_space_jump = true
		_jump_launch_speed = -velocity.y
	# Variable jump height
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut_multiplier

	# Sprint stop: letting go of the direction while sprinting starts a skid
	if slide_enabled and _was_sprint_moving and move_x == 0.0 and is_on_floor() \
			and velocity.y >= 0.0 and not slide_sequence.is_empty():
		_slide_timer = slide_sequence.size() / slide_fps
		velocity.x = _last_speed_x
		_slide_decel = _last_speed_x * _last_speed_x / (2.0 * maxf(slide_distance, 1.0))
	# Steering, jumping or leaving the ground cancels the skid
	if _slide_timer > 0.0 and (move_x != 0.0 or velocity.y < 0.0 or not is_on_floor()):
		_slide_timer = 0.0
	_slide_timer -= delta

	# Contra rule: holding down on the ground = prone, no running
	var prone := is_on_floor() and aim_y > 0.0 and move_x == 0.0
	var target_x := move_x * _gait_speed(gait)
	var rate := acceleration if move_x != 0.0 else deceleration
	if _slide_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, _slide_decel * delta)
	else:
		velocity.x = target_x if rate <= 0.0 else move_toward(velocity.x, target_x, rate * delta)
	var fall_speed := velocity.y
	move_and_slide()
	_last_speed_x = get_real_velocity().x
	_was_sprint_moving = is_on_floor() and gait == "sprint" and move_x != 0.0 \
			and absf(_last_speed_x) > run_speed * 0.5

	if is_on_floor() and not _was_on_floor:
		_land_timer = landing_pose_time
		_space_jump = false
		if fall_speed > landing_dust_speed:
			dust.puff()
	_was_on_floor = is_on_floor()
	# Running / sprinting kicks up dust; sneaking is quiet
	var running := is_on_floor() and absf(get_real_velocity().x) > 1.0 and gait != "walk"
	dust.set_running(running, facing, gait == "sprint")

	_update_aim(move_x, aim_y, prone)
	_fire_cooldown -= delta
	if has_gun and Input.is_action_pressed("shoot") and _fire_cooldown <= 0.0:
		_shoot()
		_fire_cooldown = vintorez_fire_interval if weapon == "vintorez" else fire_interval
	_update_animation(gait, delta)


## Launch speed that peaks at exactly jump_height, accounting for the fixed physics step
## (the plain sqrt(2gh) formula overshoots by ~3 px at 60 Hz).
func _jump_speed(delta: float) -> float:
	var half_step := gravity * delta * 0.5
	return sqrt(2.0 * gravity * jump_height + half_step * half_step) - half_step


## Run is the default; holding S / Down sneaks, holding Shift sprints (sneak wins if both are held).
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
	elif aim_y < 0.0 or (aim_y > 0.0 and not is_on_floor()):
		# Diagonals: up while moving, or down while moving in the air.
		# (Down while moving on the ground is sneaking, which shoots straight ahead.)
		aim = Vector2(facing, aim_y).normalized()
	else:
		aim = Vector2(facing, 0)
	# Forward shots leave from the barrel tip of the held weapon; other angles from around the chest
	if aim.y == 0.0:
		muzzle.position = Vector2(_muzzle_forward.x * facing, _muzzle_forward.y)
	else:
		muzzle.position = Vector2(0, -24) + aim * 14.0


func _shoot() -> void:
	if weapon == "vintorez":
		_shoot_vintorez()
	else:
		_shoot_shotgun()


## One suppressed round: straight, fast and long, with only a wisp of smoke.
func _shoot_vintorez() -> void:
	var b := BULLET_SCENE.instantiate()
	b.global_position = muzzle.global_position
	b.direction = aim
	b.speed = vintorez_speed
	b.max_range = vintorez_range
	b.fade_portion = 0.15
	get_parent().add_child(b)
	if vintorez_smoke > 0.0:
		var smoke := MUZZLE_SMOKE.new()
		smoke.direction = aim
		smoke.amount = maxi(1, roundi(smoke.amount * vintorez_smoke))
		smoke.lifetime *= 0.6
		smoke.opacity *= 0.6
		smoke.global_position = muzzle.global_position
		get_parent().add_child(smoke)


## One shotgun blast: a cone of short-range pellets plus a puff of smoke at the muzzle.
func _shoot_shotgun() -> void:
	for i in pellet_count:
		var b := BULLET_SCENE.instantiate()
		var t := 0.5 if pellet_count == 1 else float(i) / (pellet_count - 1)
		var angle := deg_to_rad(lerpf(-pellet_spread, pellet_spread, t) * 0.5 + randf_range(-1.5, 1.5))
		b.global_position = muzzle.global_position
		b.direction = aim.rotated(angle)
		b.speed = pellet_speed * randf_range(0.85, 1.15)
		b.max_range = pellet_range * randf_range(1.0 - pellet_range_jitter, 1.0 + pellet_range_jitter)
		get_parent().add_child(b)
	var smoke := MUZZLE_SMOKE.new()
	smoke.direction = aim
	smoke.global_position = muzzle.global_position
	get_parent().add_child(smoke)


func _update_animation(gait: String, delta: float) -> void:
	sprite.scale.x = facing
	sprite.position.y = feet_sink
	_land_timer -= delta

	if not is_on_floor():
		_moving = false
		_idle_sheet = null
		if _space_jump:
			# Space jump: spread jump-up over the rise, then hold its last pose on the way down
			if velocity.y < 0.0 and not jump_up_sequence.is_empty():
				var rise := clampf(1.0 + velocity.y / _jump_launch_speed, 0.0, 1.0)
				_show(JUMP_UP_SHEET, _pick(jump_up_sequence, rise))
			else:
				_show(JUMP_UP_SHEET, jump_up_fall_frame)
		else:
			# Dropped off a ledge
			_show(JUMP_OFF_SHEET, jump_off_fall_fast_frame if velocity.y > fall_fast_speed else jump_off_fall_frame)
		return

	if _slide_timer > 0.0:
		# Sprint-stop skid: play the slide once over its duration
		_moving = false
		_idle_sheet = null
		var total := slide_sequence.size() / slide_fps
		_show(SLIDE_SHEET, _pick(slide_sequence, 1.0 - _slide_timer / total))
		return

	# Use the real movement so pushing against a wall shows idle, not running on the spot
	var speed_x := absf(get_real_velocity().x)
	if speed_x > 1.0:
		_land_timer = 0.0  # running away cancels the landing pose
		if not _moving:
			_moving = true
			_cycle_pos = 0.125  # start mid-stride so the first step reads immediately
		# Shift = sprint, S / Down = sneak, otherwise run. Phase carries over when switching.
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
		_show(JUMP_OFF_SHEET, _pick(jump_land_frames, 1.0 - _land_timer / landing_pose_time))
		return

	if gait == "walk":
		# S / Down held standing still: stay in the sneak crouch instead of idling
		_idle_sheet = null
		_show(SNEAK_SHEET, sneak_stand_frame)
		return

	if _idle_sheet == null:
		# Just came from another state: pick an idle variant and start it from frame 0
		_idle_sheet = IDLE_SHEETS.pick_random()
		_idle_time = 0.0
	_idle_time += delta
	if has_gun:
		# Weapon in hand: the ready-stance idle with the weapon, all its frames in order
		var armed := _armed_idle_sheet()
		_show(armed, int(_idle_time * armed_idle_fps) % armed.frames)
		return
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
	if has_gun and WEAPONS[weapon].gun_sheets:
		var gun := _gun_sheet(sheet)
		if not gun.is_empty():
			# Gun sheets may have a different frame count: keep the same place in the animation
			frame = int(float(frame) * gun.frames / sheet.frames)
			sheet = gun
	if sprite.texture != sheet.tex:
		sprite.texture = sheet.tex
		sprite.hframes = SHEET_COLUMNS
		sprite.vframes = sheet.rows
		sprite.offset = sheet.offset
	sprite.frame = clampi(frame, 0, sheet.frames - 1)


## Collect every *-with-gun.png / *_with_gun.png under dir, keyed by the sheet name it replaces.
func _scan_gun_sheets(dir: String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_scan_gun_sheets(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		f = f.trim_suffix(".import").trim_suffix(".remap")  # exported builds list these instead
		if f.get_extension() != "png":
			continue
		for suffix in GUN_SUFFIXES:
			if f.get_basename().ends_with(suffix):
				_gun_files[f.get_basename().trim_suffix(suffix)] = dir.path_join(f)


## Gun version of a default sheet ({} if there isn't one). Built once per sheet and cached.
func _gun_sheet(sheet: Dictionary) -> Dictionary:
	var tex: Texture2D = sheet.tex
	if _gun_sheets.has(tex):
		return _gun_sheets[tex]
	var gun := {}
	var name := tex.resource_path.get_file().get_basename()
	var bare := name
	while bare.length() > 0 and bare[-1].is_valid_int():
		bare = bare.left(-1)  # idle1 -> idle
	var path: String = _gun_files.get(name, _gun_files.get(bare, ""))
	if path != "":
		gun = _measure_sheet(_match_hero_size(load(path).get_image(), tex.get_image(), sheet.rows))
		if gun.tex.get_size() == tex.get_size():
			gun.offset = sheet.offset  # same grid as the default sheet: keep its hand-tuned feet line
	_gun_sheets[tex] = gun
	return gun


## If the hero in `img` is drawn at a different size than in the default sheet `ref`,
## shrink/grow every cell (nearest pixel) so the heights match. Returns the texture to use.
func _match_hero_size(img: Image, ref: Image, ref_rows: int) -> Texture2D:
	img.convert(Image.FORMAT_RGBA8)
	var cell := img.get_width() / SHEET_COLUMNS
	var rows := maxi(1, img.get_height() / cell)
	var ref_cell := ref.get_width() / SHEET_COLUMNS
	var ref_h := _hero_height(ref, ref_cell, ref_rows)
	var h := _hero_height(img, cell, rows)
	# Up to 15% is the same art in a lower pose (e.g. running crouched with the gun): keep 1:1
	if ref_h <= 0 or h <= 0 or absi(h - ref_h) <= maxi(1, int(ref_h * 0.15)):
		return ImageTexture.create_from_image(img)
	var new_cell := roundi(cell * float(ref_h) / h)
	var out := Image.create(new_cell * SHEET_COLUMNS, new_cell * rows, false, Image.FORMAT_RGBA8)
	for i in SHEET_COLUMNS * rows:
		var c := img.get_region(Rect2i(i % SHEET_COLUMNS * cell, i / SHEET_COLUMNS * cell, cell, cell))
		c.resize(new_cell, new_cell, Image.INTERPOLATE_NEAREST)
		out.blit_rect(c, Rect2i(0, 0, new_cell, new_cell), Vector2i(i % SHEET_COLUMNS * new_cell, i / SHEET_COLUMNS * new_cell))
	return ImageTexture.create_from_image(out)


## Tallest opaque span in any cell of a 5-column sheet = how tall the hero is drawn (px).
func _hero_height(img: Image, cell: int, rows: int) -> int:
	var h := 0
	for i in SHEET_COLUMNS * rows:
		h = maxi(h, img.get_region(Rect2i(i % SHEET_COLUMNS * cell, i / SHEET_COLUMNS * cell, cell, cell)).get_used_rect().size.y)
	return h


## Grid, frame count and feet offset of a 5-column sheet with square cells, read from its pixels:
## the origin goes on the lowest opaque row (the feet) and the cell's horizontal centre.
func _measure_sheet(tex: Texture2D) -> Dictionary:
	var img := tex.get_image()
	var cell := img.get_width() / SHEET_COLUMNS
	var rows := maxi(1, img.get_height() / cell)
	var frames := 0
	var foot := 0
	for i in SHEET_COLUMNS * rows:
		var r := img.get_region(Rect2i(i % SHEET_COLUMNS * cell, i / SHEET_COLUMNS * cell, cell, cell)).get_used_rect()
		if r.size != Vector2i.ZERO:
			frames = i + 1
			foot = maxi(foot, r.end.y - 1)
	return {"tex": tex, "rows": rows, "frames": maxi(frames, 1), "offset": Vector2(-cell / 2, -(foot + 1))}


## Controls while playing, for the top-right list (input_display.gd).
func help() -> Array:
	return [
		[["move_left", "move_right"], "run"],
		[["sprint"], "sprint (hold)"],
		[["walk"], "sneak (hold) / aim down in the air"],
		[["aim_up"], "aim up"],
		[["jump"], "jump (hold = higher)"],
		[["shoot"], ("shoot " + WEAPONS[weapon].name) if has_gun else "shoot (pick up a weapon first)"],
		[["inventory"], "inventory"],
		[["map"], "world map"],
	]
