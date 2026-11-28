extends Node2D
## Bomb dropped by a drone (drone.gd). Falls nose first and explodes (explosion.gd) when it
## hits the level or the hero.
## Art: assets/sprites/enemies/drone_bomb.png (frame 0 of art_raw/enemies/air_craftbomb1.gif, half size).

const TEXTURE := preload("res://assets/sprites/enemies/drone_bomb.png")
const EXPLOSION := preload("res://scripts/explosion.gd")
const GRAVITY := 520.0
## Share of the drone's sideways speed the bomb keeps when dropped.
const INHERIT := 0.6
const HIT_MASK := 1 | 2  # level + player
## Hits are checked this far ahead of the bomb (px), so it never tunnels through thin platforms.
const LOOKAHEAD := 8.0

@export_range(0, 20, 1) var damage := 2
@export_range(4.0, 100.0, 1.0, "suffix:px") var blast_radius := 30.0

var velocity := Vector2.ZERO
var _life := 0.0


func _ready() -> void:
	var s := Sprite2D.new()
	s.texture = TEXTURE
	add_child(s)


func _physics_process(delta: float) -> void:
	_life += delta
	velocity.y += GRAVITY * delta
	var motion := velocity * delta
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + motion + motion.normalized() * LOOKAHEAD, HIT_MASK)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit:
		_explode(hit.position)
		return
	position += motion
	rotation = velocity.angle() - PI / 2.0  # the art points down
	if _life > 8.0:
		queue_free()


func _explode(at: Vector2) -> void:
	var e := EXPLOSION.new()
	e.global_position = at
	e.damage = damage
	e.radius = blast_radius
	get_parent().add_child(e)
	queue_free()
