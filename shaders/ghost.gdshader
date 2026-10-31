// One ghost, drawn procedurally.
// The body is a tapered tube around a chain of points (spine[]) that
// scripts/ghost.gd simulates like a piece of cloth: the head leads, the body
// trails behind it with follow-through. On top of that the shader adds slow
// ripples, a fluttering scalloped hem, and a dissolve for appearing/vanishing.
// Look: chalky cream body, pink chalk rim, black oval eyes, scribbled blush.
shader_type canvas_item;

const int N = 10;
uniform vec2 spine[10];                // chain points in ghost-length units, spine[0] = head centre = quad centre
uniform float quad_size = 2.4;         // quad side in ghost-length units
uniform float head_angle = -1.5708;    // direction the head is facing (screen space, radians)
uniform float phase = 0.0;             // per-ghost time offset
uniform float look = 0.0;              // -1..1, face glance left/right
uniform float blink = 0.0;             // 0 open, 1 closed
uniform float presence = 1.0;          // 0 = gone, 1 = fully here (dissolve)
uniform float body_width = 1.0;
uniform float flare = 0.35;            // how much the cloth widens towards the hem
uniform float cloth_amount = 1.0;      // strength of the extra cloth ripples
uniform float cloth_speed = 0.3;       // < 1 = slow motion (underwater feel)
uniform float scallops = 3.0;          // number of lobes on the hem
uniform float opacity = 0.92;
uniform float tail_fade = 0.45;        // hem fades into the dark
uniform float glow = 0.55;             // soft halo around the body
uniform float flicker = 0.08;
uniform float eye_size = 1.0;
uniform float blush_amount = 0.9;

uniform vec4 body_color : source_color = vec4(0.96, 0.93, 0.85, 1.0);
uniform vec4 rim_color : source_color = vec4(0.82, 0.38, 0.55, 1.0);
uniform vec4 blush_color : source_color = vec4(0.93, 0.55, 0.66, 1.0);
uniform vec4 eye_color : source_color = vec4(0.04, 0.03, 0.04, 1.0);
uniform vec4 glow_color : source_color = vec4(0.80, 0.78, 0.95, 1.0);

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

float ellipse(vec2 p, vec2 c, vec2 r) {
	return length((p - c) / r) - 1.0;
}

void fragment() {
	float t = TIME * cloth_speed + phase;
	float R = 0.13 * body_width;
	vec2 p = (UV - 0.5) * quad_size;

	// Slow ripples in the cloth, nothing at the head, strongest at the hem.
	float far = clamp(length(p) / 0.8, 0.0, 1.0);
	vec2 q = p + cloth_amount * far * far * 0.13 *
			(vec2(fbm(p * 1.6 + vec2(-t * 0.45, t * 0.2)), fbm(p * 1.6 + vec2(5.2, -t * 0.4))) - 0.5);

	// Tapered tube around the spine chain.
	float d_tube = 1e5;
	float s_body = 0.0;      // 0 at head centre, 1 at the hem
	float x_body = 0.0;      // -1..1 across the body
	for (int i = 0; i < N - 1; i++) {
		vec2 a = spine[i];
		vec2 ab = spine[i + 1] - a;
		float h = clamp(dot(q - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
		vec2 c = a + ab * h;
		float s = (float(i) + h) / float(N - 1);
		float hw = R * (1.0 + flare * s + 0.14 * sin(s * 4.0 - t * 0.8) * s * cloth_amount);
		float di = length(q - c) - hw;
		if (di < d_tube) {
			d_tube = di;
			s_body = s;
			vec2 tn = normalize(ab + vec2(1e-6));
			x_body = dot(q - c, vec2(-tn.y, tn.x)) / hw;
		}
	}

	// Square off the tail end and give it a scalloped, fluttering hem.
	vec2 tail_end = spine[N - 1];
	vec2 te = normalize(tail_end - spine[N - 3] + vec2(1e-6));   // smoothed tail direction
	vec2 tp = vec2(-te.y, te.x);
	float hw_end = R * (1.0 + flare);
	float along = dot(q - tail_end, te);
	float xl = dot(q - tail_end, tp) / hw_end;
	float d_ext = max(abs(dot(q - tail_end, tp)) - hw_end, -along);
	float lobe_x = scallops * 1.5708 * (xl + 1.0) + 0.45 * sin(t * 0.7 + xl * 2.0) * cloth_amount;
	float lobe = pow(abs(sin(lobe_x)), 0.45);
	float hem = 0.035 - 0.04 * (1.0 - lobe)
			  + cloth_amount * (0.03 * sin(t * 1.2 + xl * 3.0) + 0.02 * sin(t * 0.7 - xl * 2.0));
	// Only cut the hem near the tail end, so a body curling back on itself
	// doesn't get sliced by the hem line.
	float near_end = step(length(q - tail_end), hw_end * 1.8);
	float d_body = mix(d_tube, max(min(d_tube, d_ext), along - hem), near_end);
	if (near_end > 0.5 && along > 0.0 && d_ext < d_tube) { s_body = 1.0; x_body = xl; }

	float d_head = length(q) - R;
	float d = smin(d_head, d_body, 0.04);

	// Hand-drawn, chalky edge.
	d += (vnoise(p * 70.0) - 0.5) * 0.005 + (vnoise(p * 14.0 + t * 0.1) - 0.5) * 0.006;

	float aa = max(fwidth(d), 0.0015);
	float inside = 1.0 - smoothstep(-aa, aa, d);

	// Chalk fill: grain, streaks along the body and dark paper specks.
	float grain = vnoise(p * vec2(160.0, 60.0));
	float streak = vnoise(vec2(x_body * 9.0, s_body * 90.0));
	float chalk = 0.86 + 0.08 * grain + 0.06 * streak;
	float speck = step(0.985, hash(floor(p * 380.0))) * 0.25;
	vec3 col = body_color.rgb * (chalk - speck);

	// Soft pink shading inside the edge, then the chalk rim itself.
	col = mix(col, rim_color.rgb, smoothstep(-0.05, -0.012, d) * 0.18);
	float rim_w = 0.010 + 0.004 * vnoise(p * 30.0);
	float rim = smoothstep(-rim_w - aa, -rim_w + aa, d);
	col = mix(col, rim_color.rgb * (0.85 + 0.25 * vnoise(p * 200.0)), rim);

	// Face, in the head's own frame (x = right, y = towards the back).
	vec2 fwd = vec2(cos(head_angle), sin(head_angle));
	vec2 right = vec2(-fwd.y, fwd.x);
	vec2 hq = vec2(dot(q, right), -dot(q, fwd));
	vec2 face = vec2(look * 0.045 * body_width, 0.015);
	float eye_open = mix(1.0, 0.06, blink);
	vec2 eye_r = vec2(0.014, 0.021 * eye_open) * body_width * eye_size;
	float ex = 0.043 * body_width;
	float eyes = min(ellipse(hq, face + vec2(-ex, 0.0), eye_r),
					 ellipse(hq, face + vec2(ex, 0.0), eye_r));
	col = mix(col, eye_color.rgb, 1.0 - smoothstep(-0.15, 0.15, eyes));

	vec2 bl_r = vec2(0.026, 0.017) * body_width;
	float bx = 0.07 * body_width;
	float blush = min(ellipse(hq, face + vec2(-bx, 0.042 * body_width), bl_r),
					  ellipse(hq, face + vec2(bx, 0.042 * body_width), bl_r));
	float scribble = 0.55 + 0.45 * sin((hq.x + hq.y) * 900.0 + vnoise(hq * 80.0) * 6.0);
	col = mix(col, blush_color.rgb, (1.0 - smoothstep(-0.3, 0.1, blush)) * scribble * blush_amount);

	// Appear / vanish: a smoky dissolve, head first, hem last, with a glowing edge.
	float n = fbm(p * 4.0 + phase * 3.1 + vec2(0.0, TIME * 0.15)) * 0.4 + s_body * 0.7;
	float pres = smoothstep(n - 0.16, n + 0.16, presence * 1.4 - 0.2);
	float ecto = pres * (1.0 - pres) * 4.0 * step(0.001, presence) * step(presence, 0.999);

	// Spooky: translucent, fading hem, subtle shimmer and flicker.
	float alpha = opacity;
	alpha *= 1.0 - tail_fade * smoothstep(0.35, 1.05, s_body);
	alpha *= 0.86 + 0.14 * fbm(p * 5.0 + vec2(0.0, -t * 0.4));
	alpha *= 1.0 - flicker * vnoise(vec2(TIME * 4.0 + phase * 13.0, phase));
	float a_in = inside * alpha * pres;
	col = mix(col, glow_color.rgb * 1.2, ecto * 0.7);

	// Halo outside the body.
	float halo = exp(-max(d, 0.0) * 38.0) * glow * 0.35 * (1.0 - inside);
	halo *= (1.0 - 0.6 * s_body) * (pres + ecto * 0.5);

	float out_a = a_in + halo * (1.0 - a_in);
	vec3 premul = col * a_in + glow_color.rgb * halo * (1.0 - a_in);
	COLOR = vec4(premul / max(out_a, 0.0001), out_a * COLOR.a);
}
