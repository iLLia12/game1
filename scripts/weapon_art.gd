extends RefCounted
## Builds weapon sprites at runtime from any weapon PNG, whatever its size or angle:
##   held_sprite()  -> the weapon lying horizontally (muzzle right), shrunk to `length` px
##   armed_sheet()  -> a 5-column hero sheet with that weapon placed in the front hand of every frame
## So a new weapon only needs its picture; the hero animations are never redrawn per weapon.

const SOLID := 40  # alpha above this counts as part of the sprite
const SUPERSAMPLE := 4


## Weapon image turned to horizontal (muzzle to the right) and scaled so it is `length` px long.
## The gun's long axis is found from its pixels; the muzzle is assumed to be the end pointing right.
static func held_sprite(src: Image, length: int) -> Image:
	src = src.duplicate()
	src.convert(Image.FORMAT_RGBA8)
	# long axis of the opaque pixels (principal axis)
	var n := 0.0
	var mx := 0.0
	var my := 0.0
	for y in src.get_height():
		for x in src.get_width():
			if src.get_pixel(x, y).a8 > 128:
				mx += x
				my += y
				n += 1.0
	if n == 0.0:
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	mx /= n
	my /= n
	var sxx := 0.0
	var sxy := 0.0
	var syy := 0.0
	for y in src.get_height():
		for x in src.get_width():
			if src.get_pixel(x, y).a8 > 128:
				sxx += (x - mx) * (x - mx)
				sxy += (x - mx) * (y - my)
				syy += (y - my) * (y - my)
	var angle := 0.5 * atan2(2.0 * sxy, sxx - syy)
	var axis := Vector2.from_angle(angle)
	if axis.x < 0.0:
		axis = -axis
	var perp := Vector2(-axis.y, axis.x)  # "down" across the gun

	# extent along / across the axis
	var u0 := INF
	var u1 := -INF
	var v0 := INF
	var v1 := -INF
	for y in src.get_height():
		for x in src.get_width():
			if src.get_pixel(x, y).a8 > SOLID:
				var p := Vector2(x + 0.5 - mx, y + 0.5 - my)
				u0 = minf(u0, p.dot(axis))
				u1 = maxf(u1, p.dot(axis))
				v0 = minf(v0, p.dot(perp))
				v1 = maxf(v1, p.dot(perp))
	var s := length / maxf(u1 - u0, 1.0)  # output px per source px
	var w := maxi(1, roundi((u1 - u0) * s))
	var h := maxi(1, ceili((v1 - v0) * s))

	# resample: each output pixel averages SUPERSAMPLE² points of the rotated source
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var step := 1.0 / SUPERSAMPLE
	for oy in h:
		for ox in w:
			var r := 0.0
			var g := 0.0
			var b := 0.0
			var a := 0.0
			for sy in SUPERSAMPLE:
				for sx in SUPERSAMPLE:
					var u := u0 + (ox + (sx + 0.5) * step) / s
					var v := v0 + (oy + (sy + 0.5) * step) / s
					var p := Vector2(mx, my) + axis * u + perp * v
					var px := int(floor(p.x))
					var py := int(floor(p.y))
					if px < 0 or py < 0 or px >= src.get_width() or py >= src.get_height():
						continue
					var c := src.get_pixel(px, py)
					r += c.r * c.a
					g += c.g * c.a
					b += c.b * c.a
					a += c.a
			if a <= 0.0:
				continue
			out.set_pixel(ox, oy, Color(r / a, g / a, b / a, a / (SUPERSAMPLE * SUPERSAMPLE)))
	_harden(out, _darkest(out))
	var used := out.get_used_rect()
	return out.get_region(used) if used.size != Vector2i.ZERO else out


## Copy of a 5-column `body` sheet with `weapon` (from held_sprite) in the front hand of every frame.
## grip = where along the weapon the hand holds it (0 = stock end, 1 = muzzle).
## The front hand is found per frame as the right-most pixel of the hero at arm height, and is
## drawn again on top of the weapon so the gun sits in the hand instead of over it.
## Returns {image, muzzle} where muzzle is the muzzle tip in cell pixels (frame 0).
static func armed_sheet(body: Image, weapon: Image, grip: float, columns := 5) -> Dictionary:
	body = body.duplicate()
	body.convert(Image.FORMAT_RGBA8)
	var out := body.duplicate()
	var cell := body.get_width() / columns
	var rows := maxi(1, body.get_height() / cell)
	var muzzle := Vector2i(-1, -1)
	var grip_px := Vector2i(roundi(grip * (weapon.get_width() - 1)), weapon.get_height() / 2)
	for i in columns * rows:
		var o := Vector2i(i % columns * cell, i / columns * cell)
		var frame := body.get_region(Rect2i(o, Vector2i(cell, cell)))
		if frame.get_used_rect().size == Vector2i.ZERO:
			continue
		var tip := _front_tip(frame)  # outer edge of the front hand
		var hand := tip + Vector2i(-3, 1)  # middle of the fist
		var at := hand - grip_px
		out.blend_rect(weapon, Rect2i(Vector2i.ZERO, weapon.get_size()), o + at)
		# fist over the weapon
		var fist := Rect2i(hand.x - 2, hand.y - 2, tip.x - hand.x + 3, 5)
		for y in range(fist.position.y, fist.end.y):
			for x in range(fist.position.x, fist.end.x):
				if x < 0 or y < 0 or x >= cell or y >= cell:
					continue
				var c := frame.get_pixel(x, y)
				if c.a8 > SOLID:
					out.set_pixel(o.x + x, o.y + y, c)
		if muzzle.x < 0:
			muzzle = at + Vector2i(weapon.get_width() - 1, weapon.get_height() / 2)
	return {"image": out, "muzzle": muzzle}


## Right-most opaque pixel in the arm band of a frame (38%..68% of the cell height, below the
## mask's filter and above the coat hem).
static func _front_tip(frame: Image) -> Vector2i:
	var best := Vector2i(-1, -1)
	var cell := frame.get_height()
	for y in range(int(cell * 0.38), int(cell * 0.68)):
		for x in range(frame.get_width() - 1, -1, -1):
			if frame.get_pixel(x, y).a8 > SOLID:
				if x > best.x:
					best = Vector2i(x, y)
				break
	return best


## Weapon image for a pickup: images bigger than max_size px are laid flat and shrunk to
## max_size px long; smaller ones (already game-sized) come back unchanged.
static func fit(src: Image, max_size: int) -> Image:
	if maxi(src.get_width(), src.get_height()) <= max_size:
		return src
	return held_sprite(src, max_size)


## Alpha becomes 0 or 1; the soft edge left by shrinking becomes outline colour.
static func _harden(img: Image, edge: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a8 <= SOLID:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif c.a8 < 200:
				img.set_pixel(x, y, edge)
			else:
				img.set_pixel(x, y, Color(c, 1.0))


static func _darkest(img: Image) -> Color:
	var best := Color(0.08, 0.07, 0.07)
	var lum := 9.0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a8 > 200 and c.get_luminance() < lum:
				lum = c.get_luminance()
				best = Color(c, 1.0)
	return best
