extends Node2D
## Light-green scanning beam from a security camera. Child of the camera Sprite2D
## (sheet_anim.gd): follows the camera's turn, from looking down-left (frame 0)
## through straight down (middle frames) to down-right (last frame). The beam turns
## smoothly between the sprite's frames (sheet_anim.progress).
## Drawn in front of the pole. The beam stops where it hits the level (ground, blocks, platforms: collision layer 1).
##
## Spotting: when the hero (group "player") steps into the beam, the camera stops sweeping
## and turns to follow him. It keeps following while he is in view (within max_length,
## inside the camera's turning range, not hidden behind the level), then goes back to sweeping.
## While following, the red alarm light on top of the pole blinks (alert_light.gd), and
## bomber drones (drone.gd) are called in from off-screen: a wave when the hero is spotted,
## another every drone_interval while he stays exposed (at most max_drones at once).

## Emitted when the camera spots the hero / loses him.
signal spotted(hero: Node2D)
signal lost

@export var color := Color(0.55, 1.0, 0.55)
## Opacity at the lens and at the far end.
@export_range(0.0, 1.0, 0.01) var alpha_near := 0.45
@export_range(0.0, 1.0, 0.01) var alpha_far := 0.08
## Beam direction on the first / last frame (degrees: 0 = right, 90 = straight down).
@export_range(0.0, 180.0, 1.0) var angle_first := 145.0
@export_range(0.0, 180.0, 1.0) var angle_last := 40.0
## Half the opening of the cone (degrees).
@export_range(1.0, 45.0, 0.5) var spread := 9.0
@export_range(20.0, 1000.0, 5.0, "suffix:px") var max_length := 420.0
## Physics layers that stop the beam (1 = level).
@export_flags_2d_physics var stop_mask := 1

@export_group("Following the hero")
@export var follow_hero := true
## Fastest the camera turns while following (degrees per second).
@export_range(10.0, 720.0, 5.0) var turn_speed := 120.0
## How softly it catches up with the hero (higher = snappier).
@export_range(0.5, 30.0, 0.5) var follow_ease := 5.0
## The point on the hero the camera looks at (from his feet).
@export var hero_aim_offset := Vector2(0, -22)
## How long the hero must be out of view before the camera gives up (s).
@export_range(0.0, 5.0, 0.1, "suffix:s") var lose_delay := 0.6
## Beam opacity multiplier while following (brighter = locked on).
@export_range(1.0, 3.0, 0.05) var locked_boost := 1.4
## Blink the red light on top of the pole while following.
@export var alarm_light := true

@export_group("Drones")
@export var call_drones := true
## Drones per wave.
@export_range(1, 10, 1) var drones_per_wave := 1
## While the hero stays exposed, another wave after this long (s).
@export_range(1.0, 60.0, 0.5, "suffix:s") var drone_interval := 2.0
## No more waves while this many drones are already out (from all cameras).
@export_range(1, 20, 1) var max_drones := 6
## How far outside the screen edge they appear (px), and how high above the hero's feet.
@export var drone_spawn_margin := 48.0
@export var drone_spawn_height := Vector2(110, 170)

const ALERT_LIGHT := preload("res://scripts/alert_light.gd")
const DRONE := preload("res://scripts/drone.gd")

## Lens position per frame of camera1.png, relative to the camera's base.
const LENS := [
	Vector2(-22, -117), Vector2(-22, -117), Vector2(-21, -117), Vector2(-20, -117), Vector2(-16, -117),
	Vector2(-16, -117), Vector2(-11, -117), Vector2(-10, -117), Vector2(-9, -117), Vector2(-9, -117),
]
const RAYS := 10

var tracking := false

var _cam: Sprite2D
var _light: Node2D
var _drawn := Vector3(INF, INF, INF)  # aim + lens the beam was last built for
var _aim := 0.0  # current beam direction (degrees)
var _unseen := 0.0
var _drone_wait := 0.0  # time until the next wave may come
var _points := PackedVector2Array()
var _colors := PackedColorArray()


func _ready() -> void:
	_cam = get_parent() as Sprite2D
	show_behind_parent = false  # in front of the pole
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD  # glows over the background
	material = mat
	if alarm_light and _cam:
		_light = ALERT_LIGHT.new()
		_light.name = "AlertLight"
		_cam.add_child.call_deferred(_light)


func _physics_process(delta: float) -> void:
	if _cam == null:
		return
	if not tracking:
		_aim = _progress_angle(_progress())
	var hero := _hero()
	var seen := hero != null and _sees(hero)
	if not tracking:
		if seen and absf(_hero_angle(hero) - _aim) <= spread:
			tracking = true
			_unseen = 0.0
			if "manual" in _cam:
				_cam.manual = true
			if _light:
				_light.active = true
			_drone_wait = 0.0  # a wave right away
			spotted.emit(hero)
	else:
		if seen:
			_unseen = 0.0
			_drone_wait -= delta
			if call_drones and _drone_wait <= 0.0:
				_drone_wait = drone_interval
				_call_drones()
			var want := clampf(_hero_angle(hero), minf(angle_first, angle_last), maxf(angle_first, angle_last))
			var step := (want - _aim) * (1.0 - exp(-follow_ease * delta))  # eases in as it catches up
			_aim += clampf(step, -turn_speed * delta, turn_speed * delta)
			var p := _angle_progress(_aim)
			if "progress" in _cam:
				_cam.progress = p
			_cam.frame = clampi(roundi(p), 0, _frames() - 1)
		else:
			_unseen += delta
			if _unseen >= lose_delay:
				tracking = false
				if _cam.has_method("resume_from"):
					_cam.resume_from(_progress())
				if _light:
					_light.active = false
				lost.emit()
	var lens := _lens()
	var now := Vector3(_aim, lens.x, lens.y)
	if tracking or not now.is_equal_approx(_drawn):
		_drawn = now
		_build()
		queue_redraw()


func _draw() -> void:
	if _points.size() >= 3:
		draw_polygon(_points, _colors)


func _build() -> void:
	var lens := _lens()
	var aim := deg_to_rad(_aim)
	var boost := locked_boost if tracking else 1.0
	var points := PackedVector2Array([lens])
	var colors := PackedColorArray([Color(color, minf(alpha_near * boost, 1.0))])
	var space := get_world_2d().direct_space_state
	for i in RAYS + 1:
		var a := aim + deg_to_rad(spread) * (2.0 * i / RAYS - 1.0)
		var end := _hit(space, lens, Vector2.from_angle(a))
		points.append(end.round())
		var k := clampf(lens.distance_to(end) / max_length, 0.0, 1.0)
		colors.append(Color(color, minf(lerpf(alpha_near, alpha_far, 0.4 + 0.6 * k) * boost, 1.0)))
	_points = points
	_colors = colors


## Where a ray from `from` (local) going `dir` stops: the first level shape it hits, or max_length.
func _hit(space: PhysicsDirectSpaceState2D, from: Vector2, dir: Vector2) -> Vector2:
	var q := PhysicsRayQueryParameters2D.create(to_global(from), to_global(from + dir * max_length), stop_mask)
	var hit := space.intersect_ray(q)
	return to_local(hit.position) if hit else from + dir * max_length


# ------------------------------------------------------------------ drones

func _call_drones() -> void:
	var parent := _cam.get_parent()
	var vp := get_viewport()
	var view := vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()
	for i in drones_per_wave:
		if get_tree().get_nodes_in_group("drones").size() >= max_drones:
			return
		var d := DRONE.new()
		var left := randf() < 0.5
		var x := view.position.x - drone_spawn_margin if left else view.end.x + drone_spawn_margin
		var hero := _hero()
		var feet_y := hero.global_position.y if hero else view.end.y
		var y := maxf(feet_y - randf_range(drone_spawn_height.x, drone_spawn_height.y), view.position.y + 16.0)
		d.global_position = Vector2(x, y)
		d.velocity = Vector2(DRONE_ENTRY_SPEED if left else -DRONE_ENTRY_SPEED, 0)
		parent.add_child(d)
		d.add_to_group("drones")  # counted right away (before its _ready)


const DRONE_ENTRY_SPEED := 120.0


# ------------------------------------------------------------------ hero

func _hero() -> Node2D:
	if not follow_hero:
		return null
	var heroes := get_tree().get_nodes_in_group("player")
	return heroes[0] as Node2D if not heroes.is_empty() else null


## Lens position, slid between the frames' positions as the camera turns.
func _lens() -> Vector2:
	var p := clampf(_progress(), 0.0, LENS.size() - 1)
	var i := mini(int(p), LENS.size() - 2)
	return (LENS[i] as Vector2).lerp(LENS[i + 1], p - i)


func _progress() -> float:
	var p = _cam.get("progress")
	return p if p != null else float(_cam.frame)


## Direction from the lens to the hero (degrees, same scale as the beam).
func _hero_angle(hero: Node2D) -> float:
	return rad_to_deg((to_local(hero.global_position + hero_aim_offset) - _lens()).angle())


## Within reach, inside the camera's turning range (+ the beam's width), not behind the level.
func _sees(hero: Node2D) -> bool:
	var target := hero.global_position + hero_aim_offset
	if _lens().distance_to(to_local(target)) > max_length:
		return false
	var a := _hero_angle(hero)
	if a < minf(angle_first, angle_last) - spread or a > maxf(angle_first, angle_last) + spread:
		return false
	var q := PhysicsRayQueryParameters2D.create(to_global(_lens()), target, stop_mask)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _progress_angle(p: float) -> float:
	return lerpf(angle_first, angle_last, clampf(p / maxf(_frames() - 1, 1), 0.0, 1.0))


func _angle_progress(angle: float) -> float:
	return clampf(inverse_lerp(angle_first, angle_last, angle), 0.0, 1.0) * (_frames() - 1)


func _frames() -> int:
	var n = _cam.get("frames")
	return n if n != null else LENS.size()
