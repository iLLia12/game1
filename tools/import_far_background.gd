extends SceneTree
## Turns the painted far background into two game-ready layers:
##   level1_sky.png  (GRID size)        sky + sun, for the static SkyLayer
##   level1_far.png  (GRID + EXTEND px) hills, trees and fires, sky cut out (transparent),
##                                      for FarLayer, which scrolls at 1/4 of the camera
## Steps:
##  1. shrink the painting back to its pixel grid (it is pixel art at 960x540, enlarged
##     ~1.74x), sampling the middle of each enlarged pixel so edges stay hard;
##  2. add EXTEND px on the right: a mirror image of the last EXTEND columns. The camera
##     travels 960 px, so FarLayer shows up to 240 px past the painting's right edge; the
##     painting's edges don't match, so a mirrored strip is used (it joins without a seam);
##  3. split sky from hills: per row the clean sky colour is estimated (median of sky
##     pixels away from the sun); above the hills' ridge line, pixels close to it are sky,
##     the rest (dead trees, flames) stay with the hills. The sun and its glow are sky.
##     The fires' orange glow on the sky goes with the hills (soft edged), so it moves with
##     its fire. Where the hills hid the sky, the sky layer gets that row's sky colour.
## Then re-run tools/make_far_fx_mask.gd (fire/sky mask and smoke source for the shader).
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/import_far_background.gd
## FarLayer's repeat_size in scenes/main.tscn must equal the far layer's width (1200).

const SRC := "res://art_raw/backgrounds/level1/level1_bg_layer1.png"
const OUT_FAR := "res://assets/sprites/backgrounds/level1/level1_far.png"
const OUT_SKY := "res://assets/sprites/backgrounds/level1/level1_sky.png"
const GRID := Vector2i(960, 540)
const EXTEND := 240

# ridge line (same rule as tools/make_far_fx_mask.gd)
const RIDGE_SEARCH := Vector2i(220, 330)
const HILL_RUN := 6
const HILL_MAX_WARMTH := 50.0
const HILL_MAX_LUMA := 135.0
# sky / hills split
const SUN_ZONE := 150.0         # px around the sun that always counts as sky (unless dark)
const SKY_NEAR := 14.0          # colour distance from the row's sky colour: below = sky...
const SKY_FAR := 34.0           # ...above = hills; soft in between
const GLOW_WARMER := 8.0        # this much more orange than the sky = fire glow (hills)


func _initialize() -> void:
	var img := _unzoom_and_extend()
	var w := img.get_width()
	var h := img.get_height()

	var rgb := PackedVector3Array()
	rgb.resize(w * h)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			rgb[y * w + x] = Vector3(c.r, c.g, c.b) * 255.0

	var ridge := _ridge(rgb, w, h)
	var sun := _find_sun(rgb, w)
	var sun2 := Vector2(GRID.x * 2 - 1 - sun.x, sun.y)  # its copy in the mirrored strip
	var sky_row := _sky_rows(rgb, w, h, ridge, sun, sun2)

	var alpha := PackedFloat32Array()
	alpha.resize(w * h)
	var dist := PackedFloat32Array()
	dist.resize(w * h)
	for y in h:
		var sky_c := sky_row[y]
		var sky_warm := sky_c.x - sky_c.z
		var sky_luma := (sky_c.x + sky_c.y + sky_c.z) / 3.0
		for x in w:
			var i := y * w + x
			var c := rgb[i]
			var d := c.distance_to(sky_c)
			dist[i] = d
			var a := clampf((d - SKY_NEAR) / (SKY_FAR - SKY_NEAR), 0.0, 1.0)
			var to_sun := minf(Vector2(x, y).distance_to(sun), Vector2(x, y).distance_to(sun2))
			var darker := sky_luma - (c.x + c.y + c.z) / 3.0 > 20.0
			if to_sun < SUN_ZONE and not darker:
				a = 0.0
			if y >= ridge[x]:
				a = 1.0
			a = 1.0 if a > 0.85 else (0.0 if a < 0.15 else a)
			if (c.x - c.z) - sky_warm > GLOW_WARMER and to_sun >= SUN_ZONE and y > 180:
				a = maxf(a, clampf((d - 5.0) / 20.0, 0.0, 1.0))
			alpha[i] = a

	var far := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var sky := Image.create(GRID.x, GRID.y, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var i := y * w + x
			var c := img.get_pixel(x, y)
			far.set_pixel(x, y, Color(c, alpha[i]))
			if x < GRID.x:
				var to_sun := Vector2(x, y).distance_to(sun)
				var clean := alpha[i] < 0.01 and (dist[i] < 10.0 or to_sun < SUN_ZONE)
				var s := sky_row[y] / 255.0
				sky.set_pixel(x, y, Color(c, 1.0) if clean else Color(s.x, s.y, s.z, 1.0))
	far.save_png(ProjectSettings.globalize_path(OUT_FAR))
	sky.save_png(ProjectSettings.globalize_path(OUT_SKY))
	print("wrote ", OUT_FAR, " ", far.get_size(), " and ", OUT_SKY, " ", sky.get_size(), "; sun at ", sun)
	quit()


func _unzoom_and_extend() -> Image:
	var src := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	src.convert(Image.FORMAT_RGBA8)
	var sw := src.get_width()
	var sh := src.get_height()
	var out := Image.create(GRID.x + EXTEND, GRID.y, false, Image.FORMAT_RGBA8)
	for y in GRID.y:
		var sy := int((y + 0.5) * sh / GRID.y)
		for x in GRID.x:
			var c := src.get_pixel(int((x + 0.5) * sw / GRID.x), sy)
			c.a = 1.0
			out.set_pixel(x, y, c)
		for x in EXTEND:
			out.set_pixel(GRID.x + x, y, out.get_pixel(GRID.x - 1 - x, y))
	return out


## Per column, the top of the farthest hills (never above a detected hilltop).
func _ridge(rgb: PackedVector3Array, w: int, h: int) -> PackedInt32Array:
	var raw := PackedInt32Array()
	raw.resize(w)
	for x in w:
		raw[x] = RIDGE_SEARCH.y
		for y in range(RIDGE_SEARCH.x, RIDGE_SEARCH.y):
			var run := true
			for k in HILL_RUN:
				var c := rgb[mini(y + k, h - 1) * w + x]
				if not (c.x - c.z < HILL_MAX_WARMTH and (c.x + c.y + c.z) / 3.0 < HILL_MAX_LUMA):
					run = false
					break
			if run:
				raw[x] = y
				break
	var med := PackedFloat32Array()
	med.resize(w)
	for x in w:
		var win: Array[int] = []
		for k in range(maxi(x - 12, 0), mini(x + 13, w)):
			win.append(raw[k])
		win.sort()
		med[x] = win[win.size() / 2]
	var out := PackedInt32Array()
	out.resize(w)
	for x in w:
		var acc := 0.0
		var n := 0
		for k in range(maxi(x - 16, 0), mini(x + 17, w)):
			acc += med[k]
			n += 1
		out[x] = mini(raw[x], int(acc / n))
	return out


## Centre of the brightest blob in the upper sky of the painting.
func _find_sun(rgb: PackedVector3Array, w: int) -> Vector2:
	var top := 0.0
	for y in 250:
		for x in GRID.x:
			var c := rgb[y * w + x]
			top = maxf(top, (c.x + c.y + c.z) / 3.0)
	var sum := Vector2.ZERO
	var n := 0.0
	for y in 250:
		for x in GRID.x:
			var c := rgb[y * w + x]
			if (c.x + c.y + c.z) / 3.0 > top - 25.0:
				sum += Vector2(x, y)
				n += 1.0
	return sum / maxf(n, 1.0)


## Clean sky colour per row: per-channel median of sky pixels away from the sun.
## Rows without enough sky (behind the hills) take the nearest rows' colour.
func _sky_rows(rgb: PackedVector3Array, w: int, h: int, ridge: PackedInt32Array, sun: Vector2, sun2: Vector2) -> PackedVector3Array:
	var rows := PackedVector3Array()
	rows.resize(h)
	var valid: Array[int] = []
	for y in h:
		var rs := PackedFloat32Array()
		var gs := PackedFloat32Array()
		var bs := PackedFloat32Array()
		for x in w:
			if y >= ridge[x] - 3:
				continue
			var c := rgb[y * w + x]
			var luma := (c.x + c.y + c.z) / 3.0
			var to_sun := minf(Vector2(x, y).distance_to(sun), Vector2(x, y).distance_to(sun2))
			if luma > 95.0 and c.x - c.z < 120.0 and to_sun > SUN_ZONE:
				rs.append(c.x)
				gs.append(c.y)
				bs.append(c.z)
		if rs.size() > 40:
			rs.sort()
			gs.sort()
			bs.sort()
			var m := rs.size() / 2
			rows[y] = Vector3(rs[m], gs[m], bs[m])
			valid.append(y)
	for y in h:
		if valid.has(y):
			continue
		var above := -1
		var below := -1
		for v in valid:
			if v < y:
				above = v
			elif below < 0:
				below = v
		if above >= 0 and below >= 0:
			rows[y] = rows[above].lerp(rows[below], float(y - above) / float(below - above))
		else:
			rows[y] = rows[above if above >= 0 else below]
	return rows
