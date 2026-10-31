// Race road: real asphalt texture plus procedural wear - repair patches, crack lines, a rubbered-in racing
// line and tyre marks under braking, and standing water that turns mirror-like in the rain.
// UV: x = metres across the road (0 at the centreline), y = metres along the lap.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D asphalt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.6);
uniform float tile = 7.0;
uniform float wear = 0.6;      // older, patchier roads in hotter cities
uniform float wet = 0.0;
uniform float half_width = 6.5;

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 m = UV;
	vec3 base = texture(asphalt, m / tile).rgb * tint;
	base *= 0.85 + 0.3 * vnoise(m * 0.08);
	// repair patches: rectangles of fresher (darker) or older (lighter) asphalt
	vec2 pc = floor(vec2(m.x / 3.0, m.y / 9.0));
	float pr = h2(pc + 3.7);
	vec2 pf = fract(vec2(m.x / 3.0, m.y / 9.0));
	float patch = step(1.0 - 0.18 * wear, pr) * step(0.1, pf.x) * step(pf.x, 0.9) * step(0.15, pf.y) * step(pf.y, 0.85);
	base *= mix(1.0, pr > 0.95 ? 0.72 : 1.18, patch);
	// cracks: thin dark meandering lines
	float cr = abs(vnoise(m * vec2(0.6, 0.25)) - 0.5);
	base *= 1.0 - wear * 0.45 * (1.0 - smoothstep(0.0, 0.012, cr)) * step(0.55, vnoise(m * 0.05));
	// rubbered racing line and tyre marks (two dark bands that wander across the road)
	float line = 0.55 * half_width * sin(m.y * 0.011 + 1.3) * sin(m.y * 0.0047);
	float lane = exp(-pow((m.x - line) / 1.6, 2.0));
	base *= 1.0 - 0.18 * lane;
	float marks = step(0.82, vnoise(vec2(m.x * 3.0, m.y * 0.04))) * (1.0 - smoothstep(0.0, 0.6, abs(abs(m.x - line) - 0.8)));
	base *= 1.0 - 0.35 * marks * step(0.6, vnoise(vec2(m.y * 0.02, 7.0)));
	// rain: everything darkens; dips hold water that reflects like a mirror
	float puddle = smoothstep(0.62, 0.72, vnoise(m * 0.09 + 11.0)) * wet;
	vec3 col = base * mix(1.0, 0.55, wet);
	float rough = mix(0.86, 0.32, wet);
	rough = mix(rough, 0.03, puddle);
	col = mix(col, col * 0.4, puddle);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = mix(0.5, 0.9, puddle);
	NORMAL_MAP = mix(texture(asphalt_nrm, m / tile).rgb, vec3(0.5, 0.5, 1.0), puddle * 0.9 + wet * 0.3);
}
