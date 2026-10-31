// Full-screen "spooky" filter applied on top of everything.
// Keeps pure black at pure black (important for a projector), and only
// touches the light coming from the ghosts: bloom, film grain, a hint of
// chromatic fringing, slow flicker and a vignette.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float bloom = 0.7;
uniform float bloom_radius = 14.0;     // in pixels
uniform float grain = 0.10;
uniform float aberration = 2.0;        // in pixels at the screen edge
uniform float flicker = 0.05;
uniform float vignette = 0.55;
uniform float black_floor = 0.012;     // anything darker becomes true black

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 dir = uv - 0.5;

	vec3 c;
	vec2 off = dir * 2.0 * aberration * px;
	c.r = texture(screen_tex, uv + off).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - off).b;

	// Cheap bloom: two rings of taps.
	vec3 b = vec3(0.0);
	for (int i = 0; i < 12; i++) {
		float ang = float(i) * 0.5236;
		vec2 o = vec2(cos(ang), sin(ang)) * px * bloom_radius;
		b += texture(screen_tex, uv + o).rgb;
		b += texture(screen_tex, uv + o * 2.3).rgb * 0.6;
	}
	b /= 19.2;
	c += b * b * bloom;

	// Film grain on the lit parts only (multiplicative, so black stays black).
	float n = hash(floor(uv / px) + fract(TIME * 7.13) * 91.7);
	c *= 1.0 + (n - 0.5) * 2.0 * grain;

	// Slow, uneven flicker like an old projector bulb.
	float f = sin(TIME * 2.1) * 0.5 + sin(TIME * 5.3 + 1.7) * 0.3 + sin(TIME * 13.7) * 0.2;
	c *= 1.0 - flicker * (0.5 + 0.5 * f);

	c *= mix(1.0, smoothstep(0.95, 0.25, length(dir * vec2(1.0, 0.8))), vignette);

	c = max(c - black_floor, 0.0) / (1.0 - black_floor);
	COLOR = vec4(c, 1.0);
}
