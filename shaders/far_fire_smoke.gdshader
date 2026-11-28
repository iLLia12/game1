shader_type canvas_item;
// Brings the wildfire in level1_far.png to life:
//  - smoke churns and rolls upward (pixels pushed around by a slowly rising noise field,
//    always by whole pixels, so the pixel art stays crisp)
//  - fire flickers (orange flame pixels brighten and dim in rising tongues)
//  - fire smoke: every fire in the picture sends up smoke, blown by the same wind (a sky
//    pixel is smoky only if there is fire upwind of it, so smoke only comes from fire)
// fx_mask says where: red = painted smoke, green = fire, blue = sky above the hills
// (made by tools/make_far_fx_mask.gd).

uniform sampler2D fx_mask : filter_nearest;
// Where the fires' smoke starts (white = fire, blurred; made by tools/make_far_fx_mask.gd).
uniform sampler2D smoke_source : filter_linear, hint_default_black;
// Slows down / speeds up all of the motion below (1 = the speeds as set; lower = calmer).
uniform float animation_speed : hint_range(0.1, 2.0, 0.05) = 0.6;

group_uniforms smoke;
// Smoke's own speed on top of animation_speed (lower = slower, lazier smoke).
uniform float smoke_speed : hint_range(0.05, 2.0, 0.05) = 0.5;
// Most pixels a smoke pixel can be pushed (in the thickest smoke).
uniform float smoke_strength : hint_range(0.0, 8.0, 0.5) = 5.0;
// How fast the churn rises (px/s).
uniform float smoke_rise : hint_range(0.0, 40.0, 0.5) = 12.0;
// Sideways speed (px/s, + = right). Equal to smoke_rise = blown at 45 degrees.
uniform float smoke_wind : hint_range(-40.0, 40.0, 0.5) = 12.0;
// Size of the billows: lower = bigger, slower-looking swirls.
uniform float smoke_scale : hint_range(0.005, 0.1, 0.005) = 0.02;
// The moving smoke is shaded in bands that roll along with the wind: the thinnest part
// of a band is brightened by smoke_light, the densest part darkened by smoke_dark.
uniform float smoke_light : hint_range(0.0, 0.5, 0.01) = 0.04;
uniform float smoke_dark : hint_range(0.0, 0.6, 0.01) = 0.45;
// Number of shading steps in the bands (pixel-art posterize).
uniform int smoke_shade_steps : hint_range(2, 8) = 4;
group_uniforms;

group_uniforms fire_smoke;
// How thick the smoke rising from the fires is (0 = none).
uniform float plume_amount : hint_range(0.0, 3.0, 0.05) = 1.5;
// Width added on each side of the fire right above it, and how much the smoke widens per
// px it travels.
uniform float plume_width : hint_range(0.0, 60.0, 1.0) = 14.0;
uniform float plume_spread : hint_range(0.0, 1.0, 0.01) = 0.3;
// How far the smoke travels from its fire before it thins out (px).
uniform float plume_length : hint_range(50.0, 1000.0, 10.0) = 420.0;
// Look of the smoke rising from the fires: 0 = wispy streaks, 1 = round billowing puffs.
uniform int fire_smoke_style : hint_range(0, 1) = 1;
// Size of the billowing puffs (lower = bigger puffs).
uniform float billow_scale : hint_range(0.01, 0.2, 0.005) = 0.07;
// Colour and maximum opacity of the smoke (billows: core colour; edges get lighter).
uniform vec4 extra_smoke_color : source_color = vec4(0.30, 0.27, 0.29, 1.0);
uniform float extra_smoke_opacity : hint_range(0.0, 1.0, 0.05) = 0.85;
group_uniforms;

group_uniforms fire;
// How much brighter the flames get at their peak.
uniform float fire_flicker : hint_range(0.0, 1.0, 0.05) = 0.45;
// How fast the flame tongues rise (px/s).
uniform float fire_speed : hint_range(0.0, 60.0, 1.0) = 18.0;
group_uniforms;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.65 + vnoise(p * 2.03 + 17.0) * 0.35;
}

// Smoke push (-1..1 per axis) at image pixel p: a noise field drifting with the wind.
vec2 push_at(vec2 p, float ts) {
	vec2 q = (p + vec2(-smoke_wind, smoke_rise) * ts) * smoke_scale;
	return vec2(fbm(q), fbm(q + vec2(5.2, 1.3))) * 2.0 - 1.0;
}

// Wisp density (0..1) at image pixel p: noise carried along the wind direction, with
// streaks stretched across it.
float roll_at(vec2 p, float ts) {
	vec2 flow = vec2(smoke_wind, -smoke_rise);  // px/s on screen (y points down)
	float flow_len = length(flow);
	vec2 along = flow_len > 0.0 ? flow / flow_len : vec2(0.0, -1.0);
	vec2 across = vec2(-along.y, along.x);
	vec2 carried = p - flow * 1.5 * ts;
	return fbm(vec2(dot(carried, across) * smoke_scale * 1.4, dot(carried, along) * smoke_scale * 2.2) + 9.0);
}

// Draws `tone` with opacity `alpha` over `col`, also where `col` is transparent (the sky is
// cut out of this layer: smoke over it must still show, over the sky layer behind).
vec4 over(vec4 col, vec3 tone, float alpha) {
	float a = col.a + alpha * (1.0 - col.a);
	if (a <= 0.0) {
		return col;
	}
	return vec4((col.rgb * col.a * (1.0 - alpha) + tone * alpha) / a, a);
}

float tongues_at(vec2 p, float t) {
	return vnoise(vec2(p.x * 0.3, p.y * 0.2 + t * fire_speed * 0.2));
}

// Fire amount (0..1) at image pixel q; none outside the picture (the far layer never
// scrolls far enough to show a second copy, so smoke must not wrap around from the
// other edge).
float fire_at(vec2 q, vec2 size) {
	if (q.y < 0.0 || q.y >= size.y || q.x < 0.0 || q.x >= size.x) {
		return 0.0;
	}
	return texture(smoke_source, (q + 0.5) / size).r;
}

// Smoke (0..1) at image pixel p from the fires upwind of it: walks back against the wind
// (dir), and at each step checks a widening band across it for fire. Nearer fire counts
// more; the result is how much fire is "behind" this pixel.
float fire_smoke_at(vec2 p, vec2 dir, vec2 size) {
	const int STEPS = 22;
	vec2 across = vec2(-dir.y, dir.x);
	float step_len = plume_length * 1.3 / float(STEPS);
	float acc = 0.0;
	for (int i = 1; i <= STEPS; i++) {
		float d = float(i) * step_len;
		vec2 q = p - dir * d;
		float half_width = plume_width + d * plume_spread;
		float f = fire_at(q, size) * 0.4
				+ (fire_at(q + across * half_width * 0.5, size) + fire_at(q - across * half_width * 0.5, size)) * 0.2
				+ (fire_at(q + across * half_width, size) + fire_at(q - across * half_width, size)) * 0.1;
		acc += f * exp(-d / plume_length);
	}
	return 1.0 - exp(-acc * plume_amount * 1.8);
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

// Round puffs (0..1, 1 = middle of a puff): 1 - distance to the nearest random point.
float billow(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			d = min(d, length(g + hash2(i + g) - f));
		}
	}
	return 1.0 - clamp(d, 0.0, 1.0);
}

void fragment() {
	float t = TIME * animation_speed;
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 px = floor(UV * size);
	vec4 m = texture(fx_mask, (px + 0.5) / size);

	// The background repeats sideways, so every noise is blended with its copy one image
	// width to the left: the right edge then matches the next copy's left edge (no seam).
	// norm keeps the contrast the same in the middle, where the two copies are mixed.
	vec2 wrap = vec2(size.x, 0.0);
	float w = px.x / size.x;
	float norm = 1.0 / sqrt((1.0 - w) * (1.0 - w) + w * w);

	// smoke: pixels pushed around by the drifting noise (whole pixels only)
	float ts = t * smoke_speed;
	vec2 push = (push_at(px, ts) * (1.0 - w) + push_at(px - wrap, ts) * w) * norm;
	vec2 offset = round(push * smoke_strength * m.r);
	vec2 src = px + offset;
	src.x = mod(src.x, size.x);  // pushed past an edge: read from the other side (it repeats)
	src.y = clamp(src.y, 0.0, size.y - 1.0);
	vec4 col = texture(TEXTURE, (src + 0.5) / size);

	// rolling bands, posterized with a 2x2 ordered dither so the steps look hand-dithered
	// like the art
	float roll = ((roll_at(px, ts) - 0.5) * (1.0 - w) + (roll_at(px - wrap, ts) - 0.5) * w) * norm + 0.5;
	float bayer = mod(px.x + 2.0 * px.y, 4.0) / 4.0 - 0.375;  // -0.375..0.375
	float steps = float(smoke_shade_steps);
	float band = clamp(floor(roll * steps + bayer) / (steps - 1.0), 0.0, 1.0);
	col.rgb *= 1.0 + mix(smoke_light, -smoke_dark, band) * m.r;

	// fire smoke: only where there is fire upwind, broken up by the moving wisp noise and
	// drawn in dithered opacity steps (pixel-art look); only in the sky above the hills
	vec2 wind_dir = normalize(vec2(smoke_wind, -smoke_rise) + vec2(0.0, -0.0001));
	float plume = m.b > 0.0 ? fire_smoke_at(px, wind_dir, size) : 0.0;
	if (fire_smoke_style == 0) {
		float density = clamp(plume * (0.55 + roll), 0.0, 1.0) * m.b;
		float opacity_step = clamp(floor(density * 3.0 + bayer + 0.25) / 3.0, 0.0, 1.0);
		col = over(col, extra_smoke_color.rgb, opacity_step * extra_smoke_opacity);
	} else if (plume > 0.0) {
		// billows: puffs carried along the wind; denser where there's more smoke. Three
		// tones (light edge, mid, dark core), dithered only where one tone meets the next.
		vec2 bq = (px - vec2(smoke_wind, -smoke_rise) * 1.2 * ts) * billow_scale;
		float puff = billow(bq) * 0.65 + billow(bq * 2.1 + 3.7) * 0.35;
		float density = clamp(plume * (0.25 + puff * 1.1), 0.0, 1.0) * m.b;
		float level = clamp(floor(density * 4.0 + bayer * 0.6), 0.0, 3.0);  // 0 = none
		if (level > 0.0) {
			vec3 edge = extra_smoke_color.rgb * 1.45;
			vec3 mid = extra_smoke_color.rgb * 1.15;
			vec3 core = extra_smoke_color.rgb * 0.8;
			vec3 tone = level < 1.5 ? edge : (level < 2.5 ? mid : core);
			float alpha = (level < 1.5 ? 0.6 : (level < 2.5 ? 0.85 : 1.0)) * extra_smoke_opacity;
			col = over(col, tone, alpha);
		}
	}

	// fire: rising tongues of brightness, plus a quick overall pulse
	float tongues = clamp(((tongues_at(px, t) - 0.5) * (1.0 - w) + (tongues_at(px - wrap, t) - 0.5) * w) * norm + 0.5, 0.0, 1.0);
	float pulse = 0.8 + 0.2 * sin(t * 9.0 + px.x * 0.07);
	float heat = m.g * smoothstep(0.35, 0.9, tongues) * pulse;
	col.rgb = mix(col.rgb, col.rgb * vec3(1.45, 1.2, 0.85), heat * fire_flicker * 2.0);
	col.rgb *= 1.0 - m.g * (1.0 - tongues) * 0.15 * fire_flicker;  // dim between tongues

	COLOR = col;
}
