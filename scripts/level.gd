extends Node2D
## Placeholder level: solid blocks defined in tile units (16x16).
## Replace with a TileMapLayer once a tileset exists in assets/sprites.

const TILE := 16

# Rect2i(x, y, w, h) in tiles. Viewport is 30x16.875 tiles.
@export var blocks: Array[Rect2i] = [
	Rect2i(0, 15, 60, 2),   # ground
	Rect2i(8, 12, 5, 1),
	Rect2i(16, 9, 6, 1),
	Rect2i(26, 11, 4, 4),
	Rect2i(34, 13, 8, 2),
	Rect2i(46, 10, 5, 1),
	Rect2i(-1, 0, 1, 17),   # left wall
	Rect2i(60, 0, 1, 17),   # right wall
]


func _ready() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for b in blocks:
		var shape := RectangleShape2D.new()
		shape.size = Vector2(b.size * TILE)
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = Vector2(b.position * TILE) + shape.size / 2.0
		# 1-tile-thick blocks are jump-through platforms: solid only from above
		col.one_way_collision = b.size.y == 1
		body.add_child(col)


func _draw() -> void:
	for b in blocks:
		var r := Rect2(b.position * TILE, b.size * TILE)
		draw_rect(r, Color("5a4632"))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color("6dab3c"))
