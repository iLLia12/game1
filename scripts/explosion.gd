extends Node2D
## Pixel-art explosion: plays the 12-frame fireball -> smoke animation once, then frees itself.
## Hurts only the hero: while the fireball is burning, touching it deals `damage` (once per
## explosion). The hurt zone follows the fireball's size frame by frame; the smoke is harmless.
## Created in code (drone_bomb.gd, drone.gd): EXPLOSION.new().
## Art: assets/sprites/enemies/drone_bomb_explosion.png (6x2 grid of 64px frames, from
## art_raw/enemies/air_craftbomb1_explosion.png).

const TEXTURE := preload("res://assets/sprites/enemies/drone_bomb_explosion.png")
const HFRAMES := 6
const VFRAMES := 2
## Blast radius the art is drawn for; other radii scale the sprite.
const ART_RADIUS := 30.0
const HURT_MASK := 2  # player only
## Fireball radius per frame as a share of `radius` (measured from the art); 0 = smoke only.
const FIRE_SIZE := [0.28, 0.44, 0.6, 0.77, 0.85, 0.9, 0.93, 0.8, 0.0, 0.0, 0.0, 0.0]

@export_range(0, 20, 1) var damage := 2
@export_range(4.0, 100.0, 1.0, "suffix:px") var radius := 30.0
@export_range(0.2, 3.0, 0.05, "suffix:s") var duration := 0.9

var _t := 0.0
var _sprite: Sprite2D
var _hit_done := false


func _ready() -> void:
	z_index = 5
	_sprite = Sprite2D.new()
	_sprite.texture = TEXTURE
	_sprite.hframes = HFRAMES
	_sprite.vframes = VFRAMES
	_sprite.scale = Vector2.ONE * (radius / ART_RADIUS)
	_sprite.flip_h = randf() < 0.5  # a bit of variety between blasts
	add_child(_sprite)


func _physics_process(_delta: float) -> void:
	if damage <= 0 or _hit_done:
		return
	var fire: float = FIRE_SIZE[_sprite.frame]
	if fire > 0.0:
		_hurt(radius * fire)


func _hurt(r: float) -> void:
	var circle := CircleShape2D.new()
	circle.radius = r
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = circle
	q.transform = Transform2D(0.0, global_position)
	q.collision_mask = HURT_MASK
	for hit in get_world_2d().direct_space_state.intersect_shape(q, 4):
		var body: Object = hit.collider
		if body == null or not body.has_method("take_damage"):
			continue
		_hit_done = true
		var dx: float = (body as Node2D).global_position.x - global_position.x
		body.take_damage(damage, Vector2(signf(dx) if dx != 0.0 else 1.0, -1.0))  # blown away from the blast
		return


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	_sprite.frame = mini(int(_t / duration * HFRAMES * VFRAMES), HFRAMES * VFRAMES - 1)
