// Digital screen panel: a creative (still or video frame) shown as an emissive display with a glass front.
// - cross-fade between two creatives (rotation)
// - optional LED pixel pitch (LED walls / outdoor boards), faded out with distance via fwidth so it never moirés
// - viewing-angle falloff: brightness and contrast drop at grazing angles like a real LCD/LED panel
// - a faint glossy front so room lights still reflect on it; emission is capped to avoid bloom blow-out
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform sampler2D tex_a : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D tex_b : source_color, filter_linear_mipmap, repeat_disable;
uniform float blend = 0.0;
uniform float brightness = 1.0;
uniform float pixel_pitch = 0.0;   // LED cells per metre-ish across the panel width (0 = LCD)
uniform float aspect = 1.7778;

void fragment() {
	vec3 a = texture(tex_a, UV).rgb;
	vec3 b = texture(tex_b, UV).rgb;
	vec3 c = mix(a, b, smoothstep(0.0, 1.0, blend));
	float grid = 0.0;
	if (pixel_pitch > 0.0) {
		vec2 g = UV * vec2(pixel_pitch * aspect, pixel_pitch);
		float fw = max(fwidth(g.x), fwidth(g.y));
		float cell = smoothstep(0.38, 0.5, max(abs(fract(g.x) - 0.5), abs(fract(g.y) - 0.5)));
		grid = cell * (1.0 - smoothstep(0.2, 0.55, fw)) * 0.5;
	}
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float angle = mix(0.35, 1.0, smoothstep(0.05, 0.6, facing));
	c *= 1.0 - grid;
	ALBEDO = c * 0.06;
	ROUGHNESS = 0.12;
	SPECULAR = 0.35;
	EMISSION = min(c * brightness * angle * 1.15, vec3(2.4));
}
