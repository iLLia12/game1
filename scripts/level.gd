extends Node2D
## Placeholder level: solid blocks defined in tile units (16x16).
## Replace with a TileMapLayer once a tileset exists in assets/sprites.

const TILE := 16

# Rect2i(x, y, w, h) in tiles. Viewport is 60x33.75 tiles (960x540); the camera shows
# y = -268..272, so the ground (rows 15-16) sits at the bottom of the screen.
# The level is 120 tiles (1920 px) wide; the second half repeats the first half's layout.
@export var blocks: Array[Rect2i] = [
	Rect2i(0, 15, 120, 2),  # ground
	Rect2i(8, 12, 5, 1),
	Rect2i(16, 9, 6, 1),
	Rect2i(26, 11, 4, 4),
	Rect2i(34, 13, 8, 2),
	Rect2i(46, 10, 5, 1),
	Rect2i(68, 12, 5, 1),
	Rect2i(76, 9, 6, 1),
	Rect2i(86, 11, 4, 4),
	Rect2i(94, 13, 8, 2),
	Rect2i(106, 10, 5, 1),
	Rect2i(-1, 0, 1, 17),   # left wall
	Rect2i(120, 0, 1, 17),  # right wall
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


# --- Look: burned-forest ground, generated once into a texture at startup ---------------
# Colours sampled from the level1 background so the platforms match it.
# The crust stays darker than the background haze; a bright band here reads as a gap
# and makes characters look like they hover above the ground.
const ASH_HI := Color("6b6262")     # occasional light ash fleck on the top edge
const ASH_TOP := Color("524747")    # top edge
const ASH := [Color("473d3d"), Color("3d3333"), Color("433939")]
const CRUST_SHADOW := Color("1f1a1c")
const EARTH := [Color("2a2326"), Color("241e21"), Color("302729")]
const EARTH_DEEP := [Color("1f1a1c"), Color("1a1618"), Color("241e21")]
const CHARCOAL := Color("141414")
const PEBBLE := Color("473d3d")
const EMBER := Color("8f3d14")
const EMBER_HOT := Color("c2561e")
const BARK := [Color("292929"), Color("2e2a2a"), Color("333333")]
const BARK_GRAIN := Color("1f1f1f")
const BARK_TOP := [Color("524747"), Color("473d3d")]
const LOG_END := [Color("3d3333"), Color("473d3d")]

var _tex: ImageTexture
var _origin := Vector2i.ZERO


func _draw() -> void:
	if _tex == null:
		_build_texture()
	draw_texture(_tex, _origin)


## Paints every block into one image: thick blocks are charred earth with an ash crust,
## 1-tile-thick (jump-through) blocks are fallen burned logs.
func _build_texture() -> void:
	var bounds := Rect2i()
	for b in blocks:
		var r := Rect2i(b.position * TILE, b.size * TILE)
		bounds = r if bounds.size == Vector2i.ZERO else bounds.merge(r)
	_origin = bounds.position
	var img := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	# Solid map, so outlines only appear where a block meets empty space
	var solid := {}
	for b in blocks:
		if b.size.y > 1:
			for ty in range(b.position.y, b.end.y):
				for tx in range(b.position.x, b.end.x):
					solid[Vector2i(tx, ty)] = true
	for b in blocks:
		var r := Rect2i(b.position * TILE, b.size * TILE)
		for wy in range(r.position.y, r.end.y):
			for wx in range(r.position.x, r.end.x):
				var c := _log_pixel(r, wx, wy) if b.size.y == 1 else _earth_pixel(r, wx, wy, solid)
				if c.a > 0.0:
					img.set_pixel(wx - _origin.x, wy - _origin.y, c)
	_tex = ImageTexture.create_from_image(img)


func _earth_pixel(r: Rect2i, wx: int, wy: int, solid: Dictionary) -> Color:
	var ly := wy - r.position.y
	var open_above := not solid.has(Vector2i(floori(wx / float(TILE)), floori((r.position.y - 1) / float(TILE))))
	var crust := 2 + _hash(wx >> 1, 7) % 2  # ash layer 2-3 px, wavy
	if open_above and ly < crust:
		if ly == 0:
			return ASH_HI if _hash(wx, 11) % 6 == 0 else ASH_TOP
		if _hash(wx, wy) % 71 == 0:
			return EMBER  # ember still glowing in the ash
		return ASH[_hash(wx, wy + 3) % ASH.size()]
	if open_above and ly == crust:
		return CRUST_SHADOW
	# Outline where the block meets open air on the sides / bottom
	var tx := floori(wx / float(TILE))
	var ty := floori(wy / float(TILE))
	if (wx == r.position.x and not solid.has(Vector2i(tx - 1, ty))) \
			or (wx == r.end.x - 1 and not solid.has(Vector2i(tx + 1, ty))) \
			or (wy == r.end.y - 1 and not solid.has(Vector2i(tx, ty + 1))):
		return CHARCOAL
	var n := _hash(wx, wy)
	# Embers: rare, and only in the top layer of soil (it cools further down)
	if ly < 14 and n % 1201 == 0:
		return EMBER_HOT
	if ly < 14 and n % 307 == 0:
		return EMBER
	if n % 41 == 0:
		return PEBBLE
	# Charcoal chunks in 3x3 clumps, earth elsewhere; a little darker deeper down
	if _hash(wx / 3, wy / 3 + 1000) % 9 == 0:
		return CHARCOAL
	var pal: Array = EARTH_DEEP if ly > 16 + _hash(wx, wy + 77) % 9 else EARTH  # ragged boundary
	return pal[_hash(wx / 2, wy / 2 + 500) % pal.size()]


func _log_pixel(r: Rect2i, wx: int, wy: int) -> Color:
	var lx := wx - r.position.x
	var ly := wy - r.position.y
	var w := r.size.x
	var end_dist := mini(lx, w - 1 - lx)
	# Rounded ends: trim corners
	if end_dist == 0 and (ly < 2 or ly > 13):
		return Color(0, 0, 0, 0)
	if end_dist == 1 and (ly == 0 or ly == 15):
		return Color(0, 0, 0, 0)
	if ly == 0 or ly == 15 or end_dist == 0:
		return CHARCOAL
	# Burnt cross-section at the ends, with a glowing core
	if end_dist <= 2:
		if ly >= 6 and ly <= 9 and end_dist == 2:
			return EMBER
		return LOG_END[(ly + end_dist) % 2]
	if ly == 1:
		return BARK_TOP[_hash(wx, 21) % 2]  # ash dusting on top
	if ly == 14:
		return BARK_GRAIN
	# Dark splits in the bark of varying length; some still glow in the middle
	var ch := _hash(wx / 2, 77)
	if ch % 17 == 0:
		var top := 3 + (ch >> 4) % 4
		var bottom := top + 2 + (ch >> 6) % 6
		if ly >= top and ly <= mini(bottom, 12):
			var glowing := (ch >> 9) % 3 == 0
			var mid := (top + bottom) / 2
			if glowing and absi(ly - mid) <= 1:
				return EMBER_HOT if ly == mid else EMBER
			return CHARCOAL
	# Horizontal bark grain, shifted per stretch so it doesn't look ruled
	if (ly + _hash(wx / 6, 33) % 3) % 4 == 0:
		return BARK_GRAIN
	return BARK[_hash(wx / 2, wy + 900) % BARK.size()]


## Small deterministic integer hash, so the texture is identical every run.
func _hash(x: int, y: int) -> int:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))
