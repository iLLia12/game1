extends Area2D
## Weapon lying in the world. Bobs gently; when the hero touches it they get that weapon
## (player.pick_up_gun(weapon)) and the pickup disappears.

const WEAPON_ART := preload("res://scripts/weapon_art.gd")

## Which weapon this gives (a key of WEAPONS in player.gd: "shotgun", "vintorez").
@export var weapon := "shotgun"
## Picture shown on the ground. Big pictures are laid flat and shrunk to icon_size px long.
## Empty = the scene's default picture.
@export var icon: Texture2D
@export_range(8, 64, 1, "suffix:px") var icon_size := 34
## Bob height (px) and period (s).
@export_range(0.0, 8.0, 0.5, "suffix:px") var bob_height := 2.0
@export_range(0.2, 5.0, 0.1, "suffix:s") var bob_period := 1.6
## Brightness pulse so the pickup catches the eye (0 = off).
@export_range(0.0, 1.0, 0.05) var pulse := 0.35

@onready var _sprite: Sprite2D = $Sprite2D
var _t := 0.0
var _base_y := 0.0


func _ready() -> void:
	if icon != null:
		_sprite.texture = ImageTexture.create_from_image(WEAPON_ART.fit(icon.get_image(), icon_size))
	if _sprite.texture != null:
		_sprite.position.y = -ceilf(_sprite.texture.get_height() / 2.0)  # resting on the ground
	_base_y = _sprite.position.y
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	var wave := sin(_t * TAU / bob_period) * 0.5 + 0.5
	_sprite.position.y = _base_y - round(wave * bob_height)
	var b := 1.0 + wave * pulse
	_sprite.modulate = Color(b, b, b)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("pick_up_gun"):
		body.pick_up_gun(weapon)
		queue_free()
