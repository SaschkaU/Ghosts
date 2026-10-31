// One ghost, drawn procedurally on a quad (head at the top, cloth hem at the bottom).
// Look: chalky cream body, pink chalk rim, black oval eyes, scribbled blush.
// The lower body behaves like slow-motion cloth: it trails, ripples and flutters,
// and the motion grows from nothing at the head to full at the hem.
shader_type canvas_item;

uniform float aspect = 0.8;            // quad width / height
uniform float phase = 0.0;             // per-ghost time offset
uniform float bend = 0.0;              // -1..1, tail curve from turning (set by script)
uniform float look = 0.0;              // -1..1, face glance left/right
uniform float blink = 0.0;             // 0 open, 1 closed
uniform float body_width = 1.0;        // fatter / thinner ghost
uniform float flare = 0.35;            // how much the cloth widens towards the hem
uniform float cloth_amount = 1.0;      // strength of the cloth motion
uniform float cloth_speed = 0.55;      // < 1 = slow motion
uniform float scallops = 3.0;          // number of lobes on the hem
uniform float opacity = 0.92;
uniform float tail_fade = 0.45;        // hem fades into the dark
uniform float glow = 0.55;             // soft halo around the body
uniform float flicker = 0.08;

uniform vec4 body_color : source_color = vec4(0.96, 0.93, 0.85, 1.0);
uniform vec4 rim_color : source_color = vec4(0.82, 0.38, 0.55, 1.0);
uniform vec4 blush_color : source_color = vec4(0.93, 0.55, 0.66, 1.0);
uniform vec4 eye_color : source_color = vec4(0.04, 0.03, 0.04, 1.0);
uniform vec4 glow_color : source_color = vec4(0.80, 0.78, 0.95, 1.0);

// Optional: use a painted ghost image instead of the procedural body.
// The image should be a single upright ghost (head on top) on transparency.
uniform bool use_texture = false;
uniform sampler2D ghost_texture : filter_linear, repeat_disable;

const float TOP = 0.05;
const float HEM = 0.93;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// 0 at the head centre, 1 at the hem.
float cloth_t(float y, float R) {
	return clamp((y - TOP - R) / (HEM - TOP - R), 0.0, 1.0);
}

// Horizontal offset of the body's centre line: tail trails behind turns and
// slow waves travel down the cloth.
float spine(float y, float R, float t) {
	float s = cloth_t(y, R);
	float wave = 0.055 * sin(t * 1.1 - s * 3.2) * pow(s, 1.5)
			   + 0.02 * sin(t * 2.3 - s * 7.0 + 1.3) * s * s;
	return bend * 0.17 * s * s + cloth_amount * wave;
}

float ellipse(vec2 p, vec2 c, vec2 r) {
	return length((p - c) / r) - 1.0;
}

void fragment() {
	float t = TIME * cloth_speed + phase;
	float R = 0.13 * body_width;
	vec2 p = vec2((UV.x - 0.5) * aspect, UV.y);
	float s = cloth_t(p.y, R);

	// Domain warp: organic ripples in the cloth, stronger towards the hem.
	vec2 q = p;
	q.x += cloth_amount * s * s * (fbm(vec2(p.y * 3.0 - t * 0.45, t * 0.21 + phase)) - 0.5) * 0.09;
	q.y += cloth_amount * s * s * (fbm(vec2(p.x * 4.0 + t * 0.3, p.y * 2.0 - t * 0.35)) - 0.5) * 0.03;

	float sp = spine(q.y, R, t);
	float hw = R * (1.0 + flare * s + 0.07 * sin(s * 6.0 - t * 0.8) * s * cloth_amount);
	float xl = (q.x - sp) / max(hw, 0.001);       // -1..1 across the body

	// Scalloped hem: rounded lobes hanging down, small notches between them,
	// slowly fluttering like fabric in a breeze.
	float lobe_x = scallops * 1.5708 * (xl + 1.0) + 0.25 * sin(t * 0.7 + xl * 2.0) * cloth_amount;
	float lobe = pow(abs(sin(lobe_x)), 0.45);
	float hem_y = HEM - 0.04 * (1.0 - lobe)
				+ cloth_amount * (0.016 * sin(t * 1.6 + xl * 4.0) + 0.01 * sin(t * 0.9 - xl * 2.0));

	vec2 head_c = vec2(spine(TOP + R, R, t), TOP + R);
	float d_head = length(q - head_c) - R;
	float d_body = max(max(abs(q.x - sp) - hw, q.y - hem_y), head_c.y - q.y);
	float d = smin(d_head, d_body, 0.04);

	// Hand-drawn, chalky edge.
	d += (vnoise(p * 70.0) - 0.5) * 0.005 + (vnoise(p * 14.0 + t * 0.1) - 0.5) * 0.006;

	float aa = max(fwidth(d), 0.0015);
	float inside;
	vec3 col;

	if (use_texture) {
		vec2 tuv = vec2((q.x - sp) / aspect + 0.5, q.y);
		vec4 tex = texture(ghost_texture, tuv);
		inside = tex.a;
		col = tex.rgb;
		d = mix(0.02, -0.02, tex.a);
	} else {
		inside = 1.0 - smoothstep(-aa, aa, d);

		// Chalk fill: grain, streaks along the body and dark paper specks.
		float grain = vnoise(p * vec2(160.0, 60.0));
		float streak = vnoise(vec2(xl * 9.0, q.y * 140.0));
		float chalk = 0.86 + 0.08 * grain + 0.06 * streak;
		float speck = step(0.985, hash(floor(p * 380.0))) * 0.25;
		col = body_color.rgb * (chalk - speck);

		// Soft pink shading inside the edge, then the chalk rim itself.
		col = mix(col, rim_color.rgb, smoothstep(-0.05, -0.012, d) * 0.18);
		float rim_w = 0.010 + 0.004 * vnoise(p * 30.0);
		float rim = smoothstep(-rim_w - aa, -rim_w + aa, d);
		col = mix(col, rim_color.rgb * (0.85 + 0.25 * vnoise(p * 200.0)), rim);

		// Face.
		vec2 face = head_c + vec2(look * 0.045 * body_width, 0.015);
		float eye_open = mix(1.0, 0.12, blink);
		vec2 eye_r = vec2(0.014, 0.021 * eye_open) * body_width;
		float ex = 0.043 * body_width;
		float eyes = min(ellipse(q, face + vec2(-ex, 0.0), eye_r),
						 ellipse(q, face + vec2(ex, 0.0), eye_r));
		col = mix(col, eye_color.rgb, 1.0 - smoothstep(-0.15, 0.15, eyes));

		vec2 bl_r = vec2(0.026, 0.017) * body_width;
		float bx = 0.07 * body_width;
		float blush = min(ellipse(q, face + vec2(-bx, 0.042 * body_width), bl_r),
						  ellipse(q, face + vec2(bx, 0.042 * body_width), bl_r));
		float scribble = 0.55 + 0.45 * sin((q.x + q.y) * 900.0 + vnoise(q * 80.0) * 6.0);
		col = mix(col, blush_color.rgb, (1.0 - smoothstep(-0.3, 0.1, blush)) * scribble * 0.9);
	}

	// Spooky: translucent, fading hem, subtle shimmer and flicker.
	float alpha = opacity;
	alpha *= 1.0 - tail_fade * smoothstep(0.35, 1.05, s);
	alpha *= 0.86 + 0.14 * fbm(p * 5.0 + vec2(0.0, -t * 0.4));
	alpha *= 1.0 - flicker * vnoise(vec2(TIME * 4.0 + phase * 13.0, phase));
	float a_in = inside * alpha;

	// Halo outside the body.
	float halo = exp(-max(d, 0.0) * 38.0) * glow * 0.35 * (1.0 - inside);
	halo *= 1.0 - 0.6 * s;

	float out_a = a_in + halo * (1.0 - a_in);
	vec3 premul = col * a_in + glow_color.rgb * halo * (1.0 - a_in);
	COLOR = vec4(premul / max(out_a, 0.0001), out_a * COLOR.a);
}
