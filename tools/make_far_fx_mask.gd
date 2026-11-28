extends SceneTree
## Builds the effect mask for the far background (shaders/far_fire_smoke.gdshader):
##   red   = painted smoke (how strongly that pixel churns), soft-edged
##   green = fire          (how strongly that pixel flickers)
##   blue  = sky           (where extra smoke may be drawn: everything above the hills)
## Re-run after changing the background (tools/import_far_background.gd writes it):
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/make_far_fx_mask.gd
##
## Ridge line (top of the farthest hills) is found per column: the first spot, going down
## from RIDGE_SEARCH.x, where HILL_RUN pixels in a row are hill-coloured (not orange sky,
## not bright); a median across neighbouring columns ignores the thin dead trees.
## Fire = strongly orange, bright-red pixels around the ridge (the sun is higher up).
## Painted smoke: the current picture has a clean sky, so DETECT_PAINTED_SMOKE is off and
## all smoke comes from the shader. Turn it on for a picture with smoke painted in
## (grey, un-orange pixels above the ridge; thresholds may need tuning to its colours).

const SRC := "res://assets/sprites/backgrounds/level1/level1_far.png"
const OUT := "res://assets/sprites/backgrounds/level1/level1_far_fx.png"
## Where the fires' smoke starts: the fire, blurred (white = fire), so smoke spreads
## from it softly instead of copying the flames' hard edges.
const OUT_SMOKE_SOURCE := "res://assets/sprites/backgrounds/level1/level1_far_smoke_source.png"
const SMOKE_SOURCE_BLUR := 8    # box-blur radius, applied twice

const RIDGE_SEARCH := Vector2i(220, 330)  # rows where the ridge can be
const HILL_RUN := 6
const HILL_MAX_WARMTH := 50.0   # r - b; sky near the horizon is 70-130
const HILL_MAX_LUMA := 135.0    # sky near the horizon is ~140-155
const RIDGE_MEDIAN := 12        # px each side
const RIDGE_SMOOTH := 16        # px each side: averaging after the median, so the line has
                                # no sudden steps (e.g. where fire hides the hilltop)
const RIDGE_CLEAR := 10         # px above the ridge with no smoke at all
const RIDGE_FADE := 24          # px over which the sky (and smoke) fades in above that

const FIRE_BAND := Vector2i(250, 330)
const FIRE_MIN_WARMTH := 115.0
const FIRE_MIN_RED := 180.0

const DETECT_PAINTED_SMOKE := false
const SMOKE_MAX_WARMTH := 22.0
const SMOKE_MAX_LUMA := 135.0
const SMOKE_BLUR := 5


func _initialize() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()

	# 1. ridge line, one y per column
	var raw := PackedInt32Array()
	raw.resize(w)
	for x in w:
		raw[x] = RIDGE_SEARCH.y
		for y in range(RIDGE_SEARCH.x, RIDGE_SEARCH.y):
			var run := true
			for k in HILL_RUN:
				if not _is_hill(img.get_pixel(x, mini(y + k, h - 1))):
					run = false
					break
			if run:
				raw[x] = y
				break
	var ridge := PackedInt32Array()
	ridge.resize(w)
	for x in w:
		var win: Array[int] = []
		for k in range(maxi(x - RIDGE_MEDIAN, 0), mini(x + RIDGE_MEDIAN + 1, w)):
			win.append(raw[k])
		win.sort()
		ridge[x] = win[win.size() / 2]
	var smooth := PackedInt32Array()
	smooth.resize(w)
	for x in w:
		var acc := 0.0
		var n := 0
		for k in range(maxi(x - RIDGE_SMOOTH, 0), mini(x + RIDGE_SMOOTH + 1, w)):
			acc += ridge[k]
			n += 1
		smooth[x] = roundi(acc / n)
	ridge = smooth

	# 2. scores
	var smoke := PackedFloat32Array()
	var fire := PackedFloat32Array()
	var sky := PackedFloat32Array()
	smoke.resize(w * h)
	fire.resize(w * h)
	sky.resize(w * h)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var warm := _warmth(c)
			var above := float(ridge[x] - RIDGE_CLEAR - y)
			var sky_amount := clampf(above / RIDGE_FADE, 0.0, 1.0)
			sky[y * w + x] = sky_amount
			if DETECT_PAINTED_SMOKE and above > 0.0:
				var luma := (c.r + c.g + c.b) / 3.0 * 255.0
				var s := clampf((SMOKE_MAX_WARMTH - warm) / 10.0, 0.0, 1.0)
				s *= clampf((SMOKE_MAX_LUMA - luma) / 15.0, 0.0, 1.0)
				smoke[y * w + x] = s * sky_amount
			if y >= FIRE_BAND.x and y <= FIRE_BAND.y and c.r * 255.0 >= FIRE_MIN_RED:
				fire[y * w + x] = clampf((warm - FIRE_MIN_WARMTH) / 40.0, 0.0, 1.0)

	# 3. soften
	if DETECT_PAINTED_SMOKE:
		smoke = _blur(_blur(smoke, w, h, SMOKE_BLUR), w, h, SMOKE_BLUR)
	fire = _blur(fire, w, h, 1)

	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var s := smoothstep(0.15, 0.7, smoke[y * w + x]) if DETECT_PAINTED_SMOKE else 0.0
			out.set_pixel(x, y, Color(s, minf(fire[y * w + x] * 1.5, 1.0), sky[y * w + x], 1.0))
	out.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT, " ", out.get_size())

	var soft := _blur(_blur(fire, w, h, SMOKE_SOURCE_BLUR), w, h, SMOKE_SOURCE_BLUR)
	var peak := 0.0
	for v in soft:
		peak = maxf(peak, v)
	var src_img := Image.create(w, h, false, Image.FORMAT_L8)
	for y in h:
		for x in w:
			src_img.set_pixel(x, y, Color.from_hsv(0.0, 0.0, clampf(soft[y * w + x] / maxf(peak, 0.001) * 1.6, 0.0, 1.0)))
	src_img.save_png(ProjectSettings.globalize_path(OUT_SMOKE_SOURCE))
	print("wrote ", OUT_SMOKE_SOURCE)
	quit()


func _is_hill(c: Color) -> bool:
	return _warmth(c) < HILL_MAX_WARMTH and (c.r + c.g + c.b) / 3.0 * 255.0 < HILL_MAX_LUMA


func _warmth(c: Color) -> float:
	return (c.r - c.b) * 255.0


## Separable box blur.
func _blur(src: PackedFloat32Array, w: int, h: int, r: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(w * h)
	var dst := PackedFloat32Array()
	dst.resize(w * h)
	var n := 2 * r + 1
	for y in h:
		for x in w:
			var acc := 0.0
			for k in range(-r, r + 1):
				acc += src[y * w + clampi(x + k, 0, w - 1)]
			tmp[y * w + x] = acc / n
	for y in h:
		for x in w:
			var acc := 0.0
			for k in range(-r, r + 1):
				acc += tmp[clampi(y + k, 0, h - 1) * w + x]
			dst[y * w + x] = acc / n
	return dst
