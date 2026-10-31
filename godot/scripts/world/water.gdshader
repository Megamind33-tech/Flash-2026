// Gate G6 — rivers and lakes. Gerstner wave normals summed analytically per pixel (no tessellation, so
// it stays cheap on phones). Fresnel blends a deep body colour with the sky reflection (the scene's
// radiance), and the surface roughens with the weather's wind and rain.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 deep : source_color = vec3(0.04, 0.09, 0.11);
uniform vec3 shallow : source_color = vec3(0.12, 0.2, 0.2);
uniform float choppy = 0.35;     // 0 calm .. 1 storm
uniform float rain = 0.0;
varying vec3 wpos;

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

vec3 gerstner_normal(vec2 p, float t) {
	// four waves: direction, wavelength, steepness
	vec4 waves[4] = { vec4(1.0, 0.3, 9.0, 0.25), vec4(-0.4, 1.0, 5.5, 0.2), vec4(0.7, -0.6, 3.1, 0.15), vec4(-0.9, -0.2, 1.7, 0.1) };
	vec3 n = vec3(0.0, 1.0, 0.0);
	for (int i = 0; i < 4; i++) {
		vec2 d = normalize(waves[i].xy);
		float k = 6.2831 / waves[i].z;
		float c = sqrt(9.81 / k);
		float f = k * (dot(d, p) - c * t);
		float a = waves[i].w * choppy / k;
		n.x -= d.x * k * a * cos(f);
		n.z -= d.y * k * a * cos(f);
		n.y -= waves[i].w * choppy * sin(f);
	}
	return normalize(n);
}

void fragment() {
	vec3 n = gerstner_normal(wpos.xz, TIME);
	// raindrop rings: fine high-frequency ripple
	n.xz += rain * 0.08 * vec2(sin(wpos.x * 9.0 + TIME * 7.0), cos(wpos.z * 9.0 - TIME * 6.0));
	n = normalize(n);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(deep, shallow, 0.3 + 0.2 * n.y) * (1.0 - fres * 0.7);
	ROUGHNESS = mix(0.03, 0.12, choppy + rain * 0.5);
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 1.0, fres);
}
