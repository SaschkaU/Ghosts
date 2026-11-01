// One ghost, drawn procedurally.
// The body is a real piece of simulated cloth: scripts/ghost.gd runs a
// mass-spring grid (ROWS x COLS particles) hanging off the head, and this
// shader draws the outline of that grid (left edge, hem, right edge) as a
// smooth shape, with a scalloped hem, a dissolve for appearing/vanishing,
// and the face on the head.
// One ghost can be a rainbow ghost (see `rainbow`), one a violet
// Valkyries ghost with a bold V on its body (see `valkyrie`), and one
// covered in rainbow sequins that flash as the cloth moves (see `sequin`).
// Look: chalky cream body, pink chalk rim, black oval eyes, scribbled blush.
shader_type canvas_item;

const int ROWS = 10;
const int COLS = 5;
const int NB = 2 * ROWS + COLS - 2;   // outline points
uniform vec2 cloth[50];                // grid points (row-major) in ghost-length units, relative to the head centre = quad centre
uniform vec4 box = vec4(-1.2, -1.2, 2.4, 2.4); // drawn rect (x, y, w, h) in ghost-length units, relative to the head centre
uniform float head_angle = -1.5708;    // direction the head is facing (screen space, radians)
uniform float phase = 0.0;             // per-ghost time offset
uniform float look = 0.0;              // -1..1, face glance left/right
uniform float blink = 0.0;             // 0 open, 1 closed
uniform float presence = 1.0;          // 0 = gone, 1 = fully here (dissolve)
uniform float body_width = 1.0;
uniform float cloth_amount = 1.0;      // strength of the extra cloth ripples
uniform float cloth_speed = 0.3;       // < 1 = slow motion (underwater feel)
uniform float scallops = 3.0;          // number of lobes on the hem
uniform float opacity = 0.92;
uniform float tail_fade = 0.45;        // hem fades into the dark
uniform float glow = 0.55;             // soft halo around the body
uniform float flicker = 0.08;
uniform float eye_size = 1.0;
uniform float blush_amount = 0.9;
uniform float outline = 1.0;           // pink chalk outline strength (0 = none)
uniform float rainbow = 0.0;           // 0 = normal ghost, 1 = rainbow ghost
uniform float rainbow_speed = 1.0;     // colour cycles per second
uniform float rainbow_bands = 0.5;     // rainbows from head to hem
uniform float rainbow_saturation = 0.89; // 0 = cream, 1 = full colour
uniform float valkyrie = 0.0;          // 0 = normal ghost, 1 = violet ghost with a V
uniform float valkyrie_v_size = 0.19;  // V height, in ghost lengths
uniform float valkyrie_v_y = 0.39;     // V centre along the body: 0 = head, 1 = hem
uniform float valkyrie_v_width = 1.0;  // how wide the V opens
uniform float valkyrie_v_thickness = 0.9; // stroke weight, fraction of the V height
uniform float sequin = 0.0;            // 0 = normal ghost, 1 = covered in rainbow sequins
uniform float sequin_size = 0.032;     // distance between sequins, ghost lengths
uniform float sequin_bands = 1.2;      // rainbows per ghost length, head to hem
uniform float sequin_shuffle = 0.35;   // 0 = neat rainbow bands, 1 = random confetti colours
uniform float sequin_speed = 0.15;     // colour drift, cycles per second
uniform float sequin_saturation = 0.85; // 0 = silver, 1 = full colour
uniform float sequin_sparkle = 1.0;    // brightness of the flashes
uniform float sequin_glint = 24.0;     // higher = shorter, rarer flashes
uniform float sequin_flip = 6.0;       // how much the sequins tilt when the cloth swings and turns
uniform float sequin_shimmer = 1.2;    // how fast they wobble on their own

uniform vec4 body_color : source_color = vec4(0.96, 0.93, 0.85, 1.0);
uniform vec4 rim_color : source_color = vec4(0.82, 0.38, 0.55, 1.0);
uniform vec4 blush_color : source_color = vec4(0.93, 0.55, 0.66, 1.0);
uniform vec4 eye_color : source_color = vec4(0.04, 0.03, 0.04, 1.0);
uniform vec4 glow_color : source_color = vec4(0.80, 0.78, 0.95, 1.0);
uniform vec4 valkyrie_color : source_color = vec4(0.43, 0.34, 0.88, 1.0);
uniform vec4 valkyrie_v_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 valkyrie_v_edge : source_color = vec4(0.79, 0.80, 0.84, 1.0);
uniform vec4 sequin_gap : source_color = vec4(0.12, 0.08, 0.16, 1.0);

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

// Hue 0..1 to a pure rainbow colour.
vec3 hue_rgb(float h) {
	return clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

float ellipse(vec2 p, vec2 c, vec2 r) {
	return length((p - c) / r) - 1.0;
}

void fragment() {
	float t = TIME * cloth_speed + phase;
	float R = 0.13 * body_width;
	vec2 p = box.xy + UV * box.zw;

	// Slow ripples in the cloth, nothing at the head, strongest at the hem.
	float far = clamp(length(p) / 0.8, 0.0, 1.0);
	vec2 q = p + cloth_amount * far * far * 0.13 *
			(vec2(fbm(p * 1.6 + vec2(-t * 0.45, t * 0.2)), fbm(p * 1.6 + vec2(5.2, -t * 0.4))) - 0.5);

	// Outline of the cloth grid as a polygon (signed distance, negative inside).
	float d2 = 1e5;
	float sgn = 1.0;
	vec2 vj = cloth[(ROWS - 1) * COLS + COLS - 2];   // last outline point (hem, next to the right corner)
	for (int k = 0; k < NB; k++) {
		int idx;
		if (k < ROWS) idx = (ROWS - 1 - k) * COLS + COLS - 1;               // right edge, hem up to head
		else if (k < 2 * ROWS) idx = (k - ROWS) * COLS;                      // left edge, head down to hem
		else idx = (ROWS - 1) * COLS + (k - 2 * ROWS + 1);                   // hem, left to right
		vec2 vi = cloth[idx];
		vec2 e = vj - vi;
		vec2 w = q - vi;
		vec2 b = w - e * clamp(dot(w, e) / max(dot(e, e), 1e-8), 0.0, 1.0);
		d2 = min(d2, dot(b, b));
		bvec3 c = bvec3(q.y >= vi.y, q.y < vj.y, e.x * w.y > e.y * w.x);
		if (all(c) || all(not(c))) sgn = -sgn;
		vj = vi;
	}
	float d_poly = sgn * sqrt(d2) - 0.006;

	// Where along / across the body this pixel is, from the middle column.
	float d_mid = 1e5;
	float s_body = 0.0;      // 0 at head centre, 1 at the hem
	float x_body = 0.0;      // -1..1 across the body
	float hw_mid = 0.1;      // half body width there, ghost lengths
	float mid_len = 0.0;     // length of the middle column, ghost lengths
	int mc = COLS / 2;
	int r_mid = 0;           // nearest middle-column segment, and where along it
	float h_mid = 0.0;
	for (int r = 0; r < ROWS - 1; r++) {
		vec2 a = cloth[r * COLS + mc];
		vec2 ab = cloth[(r + 1) * COLS + mc] - a;
		float h = clamp(dot(q - a, ab) / max(dot(ab, ab), 1e-8), 0.0, 1.0);
		vec2 c = a + ab * h;
		float dm = length(q - c);
		mid_len += length(ab);
		if (dm < d_mid) {
			d_mid = dm;
			r_mid = r;
			h_mid = h;
			s_body = (float(r) + h) / float(ROWS - 1);
			float hw0 = 0.5 * length(cloth[r * COLS + COLS - 1] - cloth[r * COLS]);
			float hw1 = 0.5 * length(cloth[(r + 1) * COLS + COLS - 1] - cloth[(r + 1) * COLS]);
			vec2 tn = normalize(ab + vec2(1e-6));
			hw_mid = max(mix(hw0, hw1, h), 1e-3);
			x_body = dot(q - c, vec2(-tn.y, tn.x)) / hw_mid;
		}
	}

	// Scalloped hem: lobes along the bottom row, notches between them.
	float d_hem = 1e5;
	float u_hem = 0.0;
	for (int c = 0; c < COLS - 1; c++) {
		vec2 a = cloth[(ROWS - 1) * COLS + c];
		vec2 ab = cloth[(ROWS - 1) * COLS + c + 1] - a;
		float h = clamp(dot(q - a, ab) / max(dot(ab, ab), 1e-8), 0.0, 1.0);
		float dh = length(q - a - ab * h);
		if (dh < d_hem) { d_hem = dh; u_hem = (float(c) + h) / float(COLS - 1); }
	}
	float lobe_x = scallops * 3.14159 * u_hem + 0.45 * sin(t * 0.7 + u_hem * 4.0) * cloth_amount;
	float lobe = pow(abs(sin(lobe_x)), 0.45);
	float hem = 0.03 - 0.045 * (1.0 - lobe) + cloth_amount * 0.015 * sin(t * 1.2 + u_hem * 6.0);
	float hem_w = (1.0 - smoothstep(0.03, 0.09, d_hem)) * smoothstep(0.75, 0.95, s_body);
	float d_body = d_poly - hem * hem_w;
	s_body = clamp(s_body, 0.0, 1.0);
	x_body = clamp(x_body, -1.5, 1.5);

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
	// Rainbow ghost: colour bands from head to hem that roll along the body over time.
	vec3 rb = mix(vec3(1.0), hue_rgb(s_body * rainbow_bands + x_body * 0.06 - TIME * rainbow_speed + phase), rainbow_saturation);
	vec3 base = mix(body_color.rgb, rb, rainbow);
	vec3 glow_c = mix(glow_color.rgb, rb, rainbow);
	// Valkyries ghost: violet body (and halo) with a V that rides on the cloth.
	base = mix(base, valkyrie_color.rgb, valkyrie);
	glow_c = mix(glow_c, mix(valkyrie_color.rgb, vec3(1.0), 0.35), valkyrie);
	vec3 col = base * (chalk - speck);
	if (valkyrie > 0.0) {
		// Body coordinates in ghost lengths (x across, y from head to hem), so the
		// emblem bends and sways with the cloth. A winged V in the Valkyries'
		// style: wings rising outward, cut by bridge cables fanning out from the
		// top, and a sword down the middle.
		vec2 vp = vec2(x_body * hw_mid, (s_body - valkyrie_v_y) * mid_len);
		float vh = valkyrie_v_size;
		float ax = abs(vp.x);
		float vw = 0.5 * vh * valkyrie_v_width;
		vec2 n = normalize(vec2(vh, vw));
		float edge = dot(vec2(ax, vp.y) - vec2(vw, -0.5 * vh), n);
		float tk = valkyrie_v_thickness * vh * 0.5;
		float arms = max(max(-0.5 * vh - 0.35 * ax - vp.y, edge), -(edge + tk));
		// Cables: thin cuts fanning out from above the sword.
		vec2 co = vec2(ax, vp.y + 0.75 * vh);
		float cstep = 0.227;    // 13 degrees
		float ck = atan(co.x, co.y) / cstep;
		float cable = abs(fract(ck + 0.5) - 0.5) * cstep * length(co) - 0.016 * vh;
		float arms_solid = arms;
		arms = max(arms, -cable);
		// Sword: pommel, crossguard and a blade that tapers to a point.
		float blade = max(ax - 0.045 * vh * clamp((0.22 * vh - vp.y) / (0.2 * vh), 0.0, 1.0),
				max(-0.62 * vh - vp.y, vp.y - 0.22 * vh));
		float guard = max(ax - 0.16 * vh, abs(vp.y + 0.5 * vh) - 0.022 * vh);
		float pommel = length(vp - vec2(0.0, -0.68 * vh)) - 0.04 * vh;
		float sword = min(min(blade, guard), pommel);
		arms = max(arms, -(sword - 0.035 * vh));
		float chalk_v = (vnoise(vp * 90.0) - 0.5) * 0.002;   // chalky edge, like the body
		float d_v = min(arms, sword) + chalk_v;
		float d_sil = min(arms_solid, sword) + chalk_v;      // outline without the inner cuts
		float v_aa = max(fwidth(d_v), 0.0012);
		float v_in = 1.0 - smoothstep(-v_aa, v_aa, d_v);
		float v_ring = smoothstep(-v_aa, v_aa, d_sil) * (1.0 - smoothstep(-v_aa, v_aa, d_sil - 0.005));
		col = mix(col, valkyrie_v_edge.rgb, v_ring * valkyrie);
		col = mix(col, valkyrie_v_color.rgb * (0.9 + 0.1 * grain), v_in * valkyrie);
	}
	float seq_flash = 0.0;
	if (sequin > 0.0) {
		// Rainbow sequins sewn onto the cloth: a hex grid in body coordinates
		// (the head's own frame on the head), so they ride and sway with the fabric.
		// Along the nearest middle-column segment, extended past the head and
		// the hem so the grid carries on smoothly there instead of smearing.
		vec2 sa = cloth[r_mid * COLS + mc];
		vec2 sab = cloth[(r_mid + 1) * COLS + mc] - sa;
		float hu = dot(q - sa, sab) / max(dot(sab, sab), 1e-8);
		hu = clamp(hu, r_mid == 0 ? -4.0 : 0.0, r_mid == ROWS - 2 ? 4.0 : 1.0);
		vec2 sn = normalize(sab + 1e-6);
		float across_d = dot(q - sa - sab * hu, vec2(-sn.y, sn.x));
		vec2 sp = vec2(across_d, (float(r_mid) + hu) / float(ROWS - 1) * mid_len) / sequin_size;
		vec2 hx = vec2(1.0, 1.7320508);
		vec2 ga = mod(sp, hx) - 0.5 * hx;
		vec2 gb = mod(sp - 0.5 * hx, hx) - 0.5 * hx;
		vec2 gv = dot(ga, ga) < dot(gb, gb) ? ga : gb;   // offset from the sequin centre
		vec2 id = floor((sp - gv) / (0.5 * hx) + 0.5);
		float h1 = hash(id * 0.0731 + 0.17);
		float h2 = hash(id * 0.0519 + 3.7);
		float h3 = hash(id * 0.0913 + 7.1);

		// Direction the cloth runs here, smoothed across the grid rows.
		vec2 t1 = cloth[(r_mid + 1) * COLS + mc] - cloth[r_mid * COLS + mc];
		vec2 t0 = r_mid > 0 ? cloth[r_mid * COLS + mc] - cloth[(r_mid - 1) * COLS + mc] : t1;
		vec2 t2 = r_mid < ROWS - 2 ? cloth[(r_mid + 2) * COLS + mc] - cloth[(r_mid + 1) * COLS + mc] : t1;
		t0 = normalize(t0 + 1e-6); t1 = normalize(t1 + 1e-6); t2 = normalize(t2 + 1e-6);
		vec2 bt = h_mid < 0.5 ? mix(normalize(t0 + t1 + 1e-6), t1, h_mid * 2.0)
				: mix(t1, normalize(t1 + t2 + 1e-6), h_mid * 2.0 - 1.0);
		vec2 sf = vec2(cos(head_angle), sin(head_angle));
		float bend = atan(-sf.x * bt.y + sf.y * bt.x, -dot(sf, bt));   // swing away from hanging straight
		float across = across_d / hw_mid;                              // round body: sides face away

		// Each sequin hangs at its own tilt; when the cloth swings, bends or turns
		// they flip through the light one after another, and wobble a little.
		float ang = h1 * 6.2832 + sequin_flip * (bend + 0.35 * head_angle) + 1.2 * across
				+ 0.5 * sin(TIME * sequin_shimmer * (0.6 + 0.8 * h2) + h3 * 6.2832);
		float glint = pow(max(cos(ang), 0.0), sequin_glint) * sequin_sparkle;

		float rr = length(gv);
		float s_aa = max(fwidth(rr), 0.02);
		float disc = 1.0 - smoothstep(0.46 - s_aa, 0.46 + s_aa, rr);
		float hue = (sp.y - gv.y) * sequin_size * sequin_bands + sequin_shuffle * h2 - TIME * sequin_speed + phase;
		vec3 sc = mix(vec3(1.0), hue_rgb(hue), sequin_saturation);
		// Metallic: brighter or darker as it tilts, a little darker towards the edge.
		vec3 seq = sc * (0.45 + 0.35 * (0.5 + 0.5 * cos(ang - 1.3))) * (1.0 - 0.3 * smoothstep(0.15, 0.46, rr));
		seq = mix(seq, vec3(1.0), clamp(glint, 0.0, 1.0) * 0.7) + sc * glint * 0.4;
		// A tiny four-point star on the strongest flashes.
		float star = (exp(-abs(gv.x) * 40.0 - abs(gv.y) * 5.0) + exp(-abs(gv.y) * 40.0 - abs(gv.x) * 5.0))
				* smoothstep(0.5, 1.0, glint);
		vec3 gap = sequin_gap.rgb * (0.7 + 0.3 * grain);
		col = mix(col, mix(gap, seq, disc) + star, sequin);
		seq_flash = clamp(glint * disc + star, 0.0, 1.0) * sequin;
		glow_c = mix(glow_c, mix(hue_rgb(-TIME * sequin_speed + phase), vec3(1.0), 0.45), sequin);
	}

	// Soft pink shading inside the edge, then the chalk rim itself.
	col = mix(col, rim_color.rgb, smoothstep(-0.05, -0.012, d) * 0.18 * outline);
	float rim_w = 0.010 + 0.004 * vnoise(p * 30.0);
	float rim = smoothstep(-rim_w - aa, -rim_w + aa, d);
	col = mix(col, rim_color.rgb * (0.85 + 0.25 * vnoise(p * 200.0)), rim * outline);

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
	// Sequin ghost: a pale ring round each eye so the face reads on the sparkle.
	col = mix(col, body_color.rgb, (1.0 - smoothstep(0.2, 0.38, eyes)) * sequin);
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
	a_in = max(a_in, inside * pres * seq_flash);   // flashes stay bright even where the ghost is see-through
	col = mix(col, glow_c * 1.2, ecto * 0.7);

	// Halo outside the body.
	float halo = exp(-max(d, 0.0) * 38.0) * glow * 0.35 * (1.0 - inside);
	halo *= (1.0 - 0.6 * s_body) * (pres + ecto * 0.5);

	float out_a = a_in + halo * (1.0 - a_in);
	vec3 premul = col * a_in + glow_c * halo * (1.0 - a_in);
	COLOR = vec4(premul / max(out_a, 0.0001), out_a * COLOR.a);
}
