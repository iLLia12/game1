extends SceneTree
## Turns a raw animation export (e.g. from PixelLab) into a game-ready hero sheet that matches
## the existing ones:
##   1. removes a baked-in background (white / checkerboard) if the PNG has no transparency
##   2. finds the frames (by the empty space between them, or a fixed grid with --grid)
##   3. scales them to the hero's real size (upscaled exports are shrunk, edges get the dark outline back)
##   4. snaps colours that are close to the reference palette onto it (same greens/browns everywhere)
##   5. lines every frame up: head on the same column, feet on the same ground line (no jitter)
##   6. writes a 5-column sheet of square cells, the layout player.gd expects
##
## Usage (from the project folder):
##   tools/normalize.sh <input.png> <output.png> [options]
## Options:
##   --ref <png>       reference sheet for size, ground line, head position and palette
##                     (default assets/sprites/hero/states/idle/idle1.png)
##   --grid CxR        cut the input as a C x R grid instead of finding the frames by empty space
##   --frames N        keep only the first N frames
##   --scale S         force the scale (e.g. 0.5); default: shrink/grow to the reference height when the
##                     tallest frame is more than 15% off. Use it for crouched/low animations.
##   --keep-y          keep the vertical movement between frames (jumps); default puts the feet on the ground
##   --no-palette      don't snap colours to the reference palette
##   --palette-tol N   how close a colour must be to get snapped (default 40)
##   --no-outline      don't darken the soft edge pixels left by shrinking

const COLUMNS := 5
const SOLID := 40  # alpha above this counts as part of the sprite

var opts := {
	"ref": "assets/sprites/hero/states/idle/idle1.png",
	"grid": Vector2i.ZERO,
	"frames": 0,
	"scale": 0.0,
	"keep_y": false,
	"palette": true,
	"palette_tol": 40.0,
	"outline": true,
}


func _initialize() -> void:
	var code := _run(OS.get_cmdline_user_args())
	quit(code)


func _run(args: PackedStringArray) -> int:
	var files: Array[String] = []
	var i := 0
	while i < args.size():
		var a := args[i]
		match a:
			"--ref": i += 1; opts.ref = args[i]
			"--grid":
				i += 1
				var p := args[i].to_lower().split("x")
				opts.grid = Vector2i(int(p[0]), int(p[1]))
			"--frames": i += 1; opts.frames = int(args[i])
			"--scale": i += 1; opts.scale = float(args[i])
			"--keep-y": opts.keep_y = true
			"--no-palette": opts.palette = false
			"--palette-tol": i += 1; opts.palette_tol = float(args[i])
			"--no-outline": opts.outline = false
			_:
				if a.begins_with("--"):
					printerr("Unknown option ", a)
					return 1
				files.append(a)
		i += 1
	if files.size() != 2:
		printerr("Usage: tools/normalize.sh <input.png> <output.png> [options]  (see tools/normalize_sheet.gd)")
		return 1

	var src := _load(files[0])
	var ref := _load(opts.ref)
	if src == null or ref == null:
		return 1

	# --- reference: size, ground line, head column, palette, outline colour
	var ref_cell := ref.get_width() / COLUMNS
	var ref_rows := maxi(1, ref.get_height() / ref_cell)
	var ref_h := 0
	var ref_feet := 0
	var ref_head := -1.0
	for c in COLUMNS * ref_rows:
		var cell := ref.get_region(Rect2i(c % COLUMNS * ref_cell, c / COLUMNS * ref_cell, ref_cell, ref_cell))
		var r := cell.get_used_rect()
		if r.size.y == 0:
			continue
		ref_h = maxi(ref_h, r.size.y)
		ref_feet = maxi(ref_feet, r.end.y)
		if ref_head < 0.0:
			ref_head = _head_x(cell)
	var palette := _palette(ref)
	var outline_col := _darkest(palette)

	# --- 1. background
	var removed := _remove_background(src)

	# --- 2. frames
	var frames := _find_frames(src)
	if opts.frames > 0 and frames.size() > opts.frames:
		frames.resize(opts.frames)
	if frames.is_empty():
		printerr("No frames found in ", files[0])
		return 1

	# --- 3. scale
	var tallest := 0
	for f in frames:
		tallest = maxi(tallest, f.rect.size.y)
	var scale: float = opts.scale
	if scale <= 0.0:
		scale = 1.0 if absf(tallest - ref_h) <= ref_h * 0.15 else float(ref_h) / tallest

	var imgs: Array[Image] = []
	for f in frames:
		var img := src.get_region(f.rect)
		img = _rescale(img, scale, outline_col if opts.outline else Color(0, 0, 0, 0))
		# --- 4. palette
		if opts.palette:
			_snap_palette(img, palette, opts.palette_tol)
		imgs.append(img)

	# --- 5. alignment
	var cell := ref_cell
	var head_x := ref_head
	var feet := ref_feet
	var places: Array[Vector2i] = []
	for n in imgs.size():
		var img := imgs[n]
		var lift := roundi(frames[n].lift * scale) if opts.keep_y else 0
		places.append(Vector2i(roundi(head_x - _head_x(img)), feet - lift - img.get_height()))
	# grow the cell if something sticks out (keeps it square, head column centred the same way)
	var grow := 0
	for n in imgs.size():
		var p := places[n]
		grow = maxi(grow, maxi(2 * maxi(-p.x, p.x + imgs[n].get_width() - cell), -p.y))
	if grow > 0:
		grow += grow % 2
		cell += grow
		for n in places.size():
			places[n] += Vector2i(grow / 2, grow)

	# --- 6. sheet
	var rows := ceili(imgs.size() / float(COLUMNS))
	var out := Image.create(cell * COLUMNS, cell * rows, false, Image.FORMAT_RGBA8)
	for n in imgs.size():
		var at := Vector2i(n % COLUMNS * cell, n / COLUMNS * cell) + places[n]
		out.blend_rect(imgs[n], Rect2i(Vector2i.ZERO, imgs[n].get_size()), at)
	var out_path := _abs(files[1])
	var err := out.save_png(out_path)
	if err != OK:
		printerr("Can't write ", out_path, " (error ", err, ")")
		return 1

	var heights: Array[int] = []
	for img in imgs:
		heights.append(img.get_height())
	print("%s -> %s" % [files[0], files[1]])
	print("  background removed: %s | frames: %d | scale: %.4f | cell: %dpx | hero height %d-%d px (reference %d)"
		% ["yes" if removed else "no", imgs.size(), scale, cell, heights.min(), heights.max(), ref_h])
	return 0


# ---------------------------------------------------------------- loading

func _abs(path: String) -> String:
	if path.begins_with("res://") or path.is_relative_path():
		return ProjectSettings.globalize_path(path if path.begins_with("res://") else "res://" + path)
	return path


func _load(path: String) -> Image:
	var img := Image.load_from_file(_abs(path))
	if img == null or img.is_empty():
		printerr("Can't read image ", path)
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


# ---------------------------------------------------------------- 1. background

## If the border isn't transparent, flood-fill the background colours in from the edges.
## The dark outline stops the fill, so light pixels inside the sprite (eyes, metal) survive.
func _remove_background(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	var d := img.get_data()
	var border := PackedInt32Array()
	for x in w:
		border.append(x)
		border.append((h - 1) * w + x)
	for y in h:
		border.append(y * w)
		border.append(y * w + w - 1)
	var see_through := 0
	for i in border:
		if d[i * 4 + 3] < 128:
			see_through += 1
	if see_through > border.size() / 2:
		return false

	# background colours = the common colours on the border (2 for a checkerboard)
	var counts := {}
	for i in border:
		var key := (d[i * 4] >> 3) << 10 | (d[i * 4 + 1] >> 3) << 5 | (d[i * 4 + 2] >> 3)
		counts[key] = counts.get(key, 0) + 1
	var bg := PackedInt32Array()
	for key in counts:
		if counts[key] >= border.size() * 0.02:
			bg.append(((key >> 10) & 31) * 8 + 4)
			bg.append(((key >> 5) & 31) * 8 + 4)
			bg.append((key & 31) * 8 + 4)

	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack := PackedInt32Array()
	stack.resize(w * h)
	var top := 0
	for i in border:
		if seen[i] == 0 and _is_bg(d, i, bg, 28):
			seen[i] = 1
			stack[top] = i
			top += 1
	while top > 0:
		top -= 1
		var i := stack[top]
		d[i * 4 + 3] = 0
		var x := i % w
		for j in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w, i + w]:
			if j >= 0 and j < w * h and seen[j] == 0 and _is_bg(d, j, bg, 28):
				seen[j] = 1
				stack[top] = j
				top += 1
	# soft halo between the outline and the old background
	for _pass in 2:
		var kill := PackedInt32Array()
		for y in range(1, h - 1):
			for x in range(1, w - 1):
				var i := y * w + x
				if d[i * 4 + 3] != 0 and _is_bg(d, i, bg, 60) and (d[(i - 1) * 4 + 3] == 0
						or d[(i + 1) * 4 + 3] == 0 or d[(i - w) * 4 + 3] == 0 or d[(i + w) * 4 + 3] == 0):
					kill.append(i)
		for i in kill:
			d[i * 4 + 3] = 0
	for i in w * h:
		if d[i * 4 + 3] == 0:
			d[i * 4] = 0
			d[i * 4 + 1] = 0
			d[i * 4 + 2] = 0
	img.set_data(w, h, false, Image.FORMAT_RGBA8, d)
	return true


func _is_bg(d: PackedByteArray, i: int, bg: PackedInt32Array, tol: int) -> bool:
	var r := d[i * 4]
	var g := d[i * 4 + 1]
	var b := d[i * 4 + 2]
	for k in range(0, bg.size(), 3):
		if absi(r - bg[k]) <= tol and absi(g - bg[k + 1]) <= tol and absi(b - bg[k + 2]) <= tol:
			return true
	return false


# ---------------------------------------------------------------- 2. frames

## Frames in reading order: {rect = tight Rect2i in the source, lift = px above the frame's ground line}.
func _find_frames(img: Image) -> Array:
	var frames := []
	if opts.grid != Vector2i.ZERO:
		var cw := img.get_width() / float(opts.grid.x)
		var ch := img.get_height() / float(opts.grid.y)
		var lowest := 0
		for c in opts.grid.x * opts.grid.y:
			var cr := Rect2i(roundi(c % opts.grid.x * cw), roundi(c / opts.grid.x * ch), int(cw), int(ch))
			var r := _solid_rect(img, cr)
			if r.size.y == 0:
				continue
			frames.append({rect = r, bottom = r.end.y - cr.position.y})
			lowest = maxi(lowest, r.end.y - cr.position.y)
		for f in frames:
			f.lift = lowest - f.bottom
		return frames

	var full := Rect2i(Vector2i.ZERO, img.get_size())
	for band in _runs(img, full, true, maxi(2, int(img.get_height() * 0.02))):
		var row := []
		var lowest := 0
		for col in _runs(img, band, false, maxi(2, int(band.size.y * 0.06))):
			var r := _solid_rect(img, col)
			if r.size.y < band.size.y * 0.3:
				continue  # specks, not a frame
			row.append({rect = r})
			lowest = maxi(lowest, r.end.y)
		for f in row:
			f.lift = lowest - f.rect.end.y
		frames.append_array(row)
	return frames


## Spans of rows (horizontal=true) or columns inside `area` that contain sprite pixels,
## with gaps narrower than `min_gap` bridged.
func _runs(img: Image, area: Rect2i, horizontal: bool, min_gap: int) -> Array[Rect2i]:
	var n := area.size.y if horizontal else area.size.x
	var m := area.size.x if horizontal else area.size.y
	var has := PackedByteArray()
	has.resize(n)
	for a in n:
		for b in m:
			var p := area.position + (Vector2i(b, a) if horizontal else Vector2i(a, b))
			if img.get_pixelv(p).a8 > SOLID:
				has[a] = 1
				break
	var out: Array[Rect2i] = []
	var start := -1
	var last := -1
	for a in n:
		if has[a] == 0:
			continue
		if start >= 0 and a - last > min_gap:
			out.append(_span(area, horizontal, start, last))
			start = -1
		if start < 0:
			start = a
		last = a
	if start >= 0:
		out.append(_span(area, horizontal, start, last))
	return out


func _span(area: Rect2i, horizontal: bool, a0: int, a1: int) -> Rect2i:
	if horizontal:
		return Rect2i(area.position.x, area.position.y + a0, area.size.x, a1 - a0 + 1)
	return Rect2i(area.position.x + a0, area.position.y, a1 - a0 + 1, area.size.y)


func _solid_rect(img: Image, area: Rect2i) -> Rect2i:
	var r := Rect2i()
	var found := false
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if img.get_pixel(x, y).a8 > SOLID:
				if found:
					r = r.expand(Vector2i(x, y))
				else:
					r = Rect2i(x, y, 0, 0)
					found = true
	return Rect2i(r.position, r.size + Vector2i.ONE) if found else Rect2i()


# ---------------------------------------------------------------- 3. scale

## Shrinking averages each block (colour weighted by alpha), then makes alpha hard again;
## the half-covered edge pixels become outline colour so the silhouette keeps its dark line.
func _rescale(img: Image, s: float, outline: Color) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	if s > 1.05:
		img.resize(roundi(w * s), roundi(h * s), Image.INTERPOLATE_NEAREST)
		_harden(img, 128, Color(0, 0, 0, 0))
		return img
	if s >= 0.95:
		_harden(img, 128, Color(0, 0, 0, 0))
		return img
	var ow := maxi(1, ceili(w * s))
	var oh := maxi(1, ceili(h * s))
	var acc := PackedFloat32Array()
	acc.resize(ow * oh * 4)
	var cnt := PackedInt32Array()
	cnt.resize(ow * oh)
	var d := img.get_data()
	for y in h:
		var oy := mini(int(y * s), oh - 1)
		for x in w:
			var o := oy * ow + mini(int(x * s), ow - 1)
			var i := (y * w + x) * 4
			var a := d[i + 3] / 255.0
			acc[o * 4] += d[i] * a
			acc[o * 4 + 1] += d[i + 1] * a
			acc[o * 4 + 2] += d[i + 2] * a
			acc[o * 4 + 3] += a
			cnt[o] += 1
	var out := Image.create(ow, oh, false, Image.FORMAT_RGBA8)
	for o in ow * oh:
		var a := acc[o * 4 + 3]
		if a <= 0.0:
			continue
		out.set_pixel(o % ow, o / ow, Color(acc[o * 4] / a / 255.0, acc[o * 4 + 1] / a / 255.0,
			acc[o * 4 + 2] / a / 255.0, a / cnt[o]))
	_harden(out, SOLID, outline)
	return _crop(out)


## Alpha becomes 0 or 1. Pixels between `cut` and ~80% alpha get `edge` colour when given.
func _harden(img: Image, cut: int, edge: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a8 <= cut:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif c.a8 < 200 and edge.a > 0.0:
				img.set_pixel(x, y, edge)
			else:
				c.a = 1.0
				img.set_pixel(x, y, c)


func _crop(img: Image) -> Image:
	var r := img.get_used_rect()
	return img.get_region(r) if r.size != Vector2i.ZERO else img


# ---------------------------------------------------------------- 4. palette

func _palette(img: Image) -> PackedColorArray:
	var seen := {}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a8 > 128:
				seen[Color(c, 1.0).to_rgba32()] = true
	var out := PackedColorArray()
	for k in seen:
		out.append(Color.hex(k))
	return out


func _darkest(pal: PackedColorArray) -> Color:
	var best := Color.BLACK
	var lum := 9.0
	for c in pal:
		if c.get_luminance() < lum:
			lum = c.get_luminance()
			best = c
	return best


func _snap_palette(img: Image, pal: PackedColorArray, tol: float) -> void:
	var tol2 := (tol / 255.0) * (tol / 255.0)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a8 == 0:
				continue
			var best := c
			var bd := tol2
			for p in pal:
				var dist := (c.r - p.r) * (c.r - p.r) + (c.g - p.g) * (c.g - p.g) + (c.b - p.b) * (c.b - p.b)
				if dist < bd:
					bd = dist
					best = p
			img.set_pixel(x, y, best)


# ---------------------------------------------------------------- 5. alignment

## Horizontal centre of the head (top 20% of the figure). The head barely moves between frames,
## unlike arms, legs or a gun, so lining it up removes side-to-side jitter.
func _head_x(img: Image) -> float:
	var r := img.get_used_rect()
	var band := maxi(3, int(r.size.y * 0.2))
	var sum := 0.0
	var n := 0
	for y in range(r.position.y, r.position.y + band):
		for x in range(r.position.x, r.end.x):
			if img.get_pixel(x, y).a8 > SOLID:
				sum += x
				n += 1
	return sum / n if n > 0 else r.get_center().x
