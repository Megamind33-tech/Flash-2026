// Waving flag: travelling sine waves along the fly, pinned at the hoist (UV.x = 0), stronger with
// weather wind. Two-sided, chequered GRIDLINE colours; no texture fetch.
shader_type spatial;
render_mode cull_disabled;

uniform float wind = 1.0;

void vertex() {
	float x = UV.x;
	float w = sin(x * 9.0 - TIME * 6.0 * wind + VERTEX.y * 2.0) * 0.12 * x * wind
		+ sin(x * 17.0 - TIME * 9.0) * 0.04 * x;
	VERTEX.z += w;
	NORMAL = normalize(NORMAL + vec3(0.0, 0.0, -cos(x * 9.0 - TIME * 6.0) * 0.5 * x));
}

void fragment() {
	vec2 c = floor(UV * vec2(6.0, 4.0));
	float chk = mod(c.x + c.y, 2.0);
	ALBEDO = mix(vec3(0.05), vec3(0.95), chk);
	ROUGHNESS = 0.85;
}
