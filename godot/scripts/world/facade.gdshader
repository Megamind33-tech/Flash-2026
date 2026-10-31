// City facade: real CC0 wall texture (plaster, concrete, brick) + procedural window grid, frames, sills,
// rain-streak staining, ground-floor shopfronts with signs/shutters, lit windows at night, wet/dust weather.
// UV is in metres (x along the wall from its corner, y up). Vertex colour: r = building seed,
// g = building height / 150 m, b = wall length / 200 m.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D wall_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float wall_tile = 4.0;
uniform vec3 tint_a : source_color = vec3(0.85);
uniform vec3 tint_b : source_color = vec3(0.75);
uniform vec3 tint_c : source_color = vec3(0.9);
uniform vec3 frame_col : source_color = vec3(0.2);
uniform vec3 sign_a : source_color = vec3(0.1, 0.4, 0.8);
uniform vec3 sign_b : source_color = vec3(0.8, 0.2, 0.15);
uniform vec3 dust_col : source_color = vec3(0.8, 0.65, 0.45);
uniform float bay = 3.4;
uniform float floor_h = 3.2;
uniform vec2 win = vec2(0.56, 0.52);
uniform float frame_w = 0.05;
uniform float shop = 1.0;
uniform float stains = 0.6;
uniform float night = 0.0;
uniform float wet = 0.0;
uniform float dust = 0.0;

float h1(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 m = UV;
	float seed = COLOR.r * 97.0;
	float bh = COLOR.g * 150.0;
	float wl = COLOR.b * 200.0;
	float pick = h1(seed);
	vec3 tint = pick < 0.34 ? tint_a : (pick < 0.67 ? tint_b : tint_c);
	tint *= 0.88 + 0.22 * h1(seed + 3.1);
	vec3 wall = texture(wall_tex, m / wall_tile).rgb * tint;
	vec3 nrm = texture(wall_nrm, m / wall_tile).rgb;
	// Weathering: streaks under each floor line and from the parapet, grime at street level.
	float colh = h2(vec2(floor(m.x * 2.5), seed));
	float fl = fract(m.y / floor_h);
	float streak = (1.0 - fl) * (1.0 - fl) * step(0.5, colh);
	float top = smoothstep(3.0, 0.0, bh - m.y) * (0.4 + 0.6 * colh);
	wall *= 1.0 - stains * (0.2 * streak + 0.35 * top);
	wall *= mix(0.72, 1.0, smoothstep(0.0, 1.4, m.y));

	vec2 cell = vec2(m.x / bay, m.y / floor_h);
	vec2 id = floor(cell);
	vec2 f = fract(cell);
	float ground = 1.0 - step(1.0, id.y);
	float edge_ok = step(bay * 0.45, m.x) * step(m.x, wl - bay * 0.45);
	float roof_ok = step(m.y, bh - 1.4);
	float wsel = (1.0 - ground) * edge_ok * roof_ok;
	float inner = step(abs(f.x - 0.5), win.x * 0.5) * step(abs(f.y - 0.52), win.y * 0.5) * wsel;
	float outer = step(abs(f.x - 0.5), win.x * 0.5 + frame_w) * step(abs(f.y - 0.52), win.y * 0.5 + frame_w) * wsel;
	float r = h2(id + seed);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 sky = mix(vec3(0.42, 0.47, 0.52), vec3(0.78, 0.82, 0.86), f.y);
	vec3 interior = mix(vec3(0.04, 0.045, 0.05), vec3(0.3, 0.24, 0.17), r * r);
	vec3 glass = mix(interior, sky, 0.3 + 0.6 * fres);
	float mull = clamp(step(abs(f.x - 0.5), 0.012) + step(abs(f.y - 0.64), 0.012), 0.0, 1.0);
	vec3 col = mix(wall, frame_col, outer);
	col = mix(col, glass, inner * (1.0 - mull));
	float rough = mix(0.93, 0.06, inner);
	float sill = step(abs(f.x - 0.5), win.x * 0.5 + frame_w * 2.0) *
		step(abs(f.y - (0.52 - win.y * 0.5 - frame_w - 0.03)), 0.03) * wsel;
	col = mix(col, wall * 1.2, sill);
	vec3 emit = vec3(0.0);
	float lit = step(0.5, h2(id + seed + 7.0)) * night;
	emit += inner * (1.0 - mull) * lit * mix(vec3(1.0, 0.72, 0.42), vec3(0.85, 0.9, 1.0), h2(id + seed + 9.0)) * 1.8;

	if (shop > 0.0 && ground > 0.5 && edge_ok > 0.5) {
		float sr = h2(vec2(id.x, seed + 11.0));
		float front = step(abs(f.x - 0.5), 0.45) * step(0.05, f.y) * step(f.y, 0.76) * step(sr, shop);
		float band = step(0.79, f.y) * step(f.y, 0.97) * step(abs(f.x - 0.5), 0.49) * step(sr, shop);
		float sp = h2(vec2(id.x, seed + 5.0));
		vec3 sign_col = (sp < 0.4 ? sign_a : (sp < 0.75 ? sign_b : vec3(0.92, 0.9, 0.85))) * (0.55 + 0.35 * h2(vec2(id.x, seed + 6.0)));
		band *= step(0.25, h2(vec2(id.x, seed + 8.0)));
		if (sr < 0.3) {
			float rib = 0.82 + 0.18 * step(0.5, fract(m.y * 9.0));
			col = mix(col, vec3(0.45, 0.46, 0.47) * rib, front);
			rough = mix(rough, 0.45, front);
		} else {
			vec3 goods = mix(vec3(0.75, 0.25, 0.15), vec3(0.2, 0.35, 0.7), h2(vec2(floor(f.x * 6.0), id.x + seed)));
			vec3 inside = mix(vec3(0.16, 0.15, 0.14), goods * 0.6, step(0.5, fract(f.y * 6.0)) * step(0.15, f.y));
			col = mix(col, mix(inside, sky * 0.6, 0.35 * fres + 0.12), front);
			rough = mix(rough, 0.06, front);
			emit += front * (inside + vec3(0.25, 0.24, 0.22)) * (0.08 + night * 1.2);
		}
		col = mix(col, sign_col, band);
		emit += band * sign_col * night * 0.9;
	}
	col *= mix(1.0, 0.6, wet * (1.0 - inner));
	rough = mix(rough, rough * 0.4, wet);
	col = mix(col, dust_col, dust * 0.25);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = mix(0.3, 0.6, inner);
	NORMAL_MAP = mix(nrm, vec3(0.5, 0.5, 1.0), inner);
	EMISSION = emit;
}
