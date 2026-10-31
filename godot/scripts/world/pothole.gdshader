// Pothole decal: irregular crater with a broken, lighter rim, a dark sunken bowl with gravel showing, a
// fake depth gradient and standing water when the road is wet. Discard outside the rim (alpha scissor),
// so it costs one quad per pothole.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D gravel : source_color, filter_linear_mipmap, repeat_enable;
uniform float wet = 0.0;
varying vec3 wpos;

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float ang = atan(p.y, p.x);
	float seed = floor(wpos.x * 3.1) + floor(wpos.z * 1.7);
	float edge = 0.78 + 0.14 * sin(ang * 3.0 + seed) + 0.1 * (vn(vec2(ang * 2.5, seed)) - 0.5);
	float r = length(p) / edge;
	if (r > 1.0) discard;
	float depth = smoothstep(1.0, 0.55, r);                 // 0 at the rim, 1 in the bowl
	vec3 g = texture(gravel, wpos.xz * 1.6).rgb;
	vec3 bowl = mix(vec3(0.16, 0.155, 0.15), g * 0.55, 0.6) * mix(1.0, 0.55, depth);
	vec3 rim = vec3(0.42, 0.41, 0.39) * (0.8 + 0.4 * vn(p * 9.0));
	float rim_w = smoothstep(0.8, 0.98, r);
	vec3 c = mix(bowl, rim, rim_w);
	float water = wet * smoothstep(0.85, 0.5, r);
	c = mix(c, vec3(0.05, 0.06, 0.07), water * 0.7);
	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.03, water);
	SPECULAR = mix(0.3, 0.9, water);
}
