// Advertising screen: shows one creative (a region of the shared sponsor atlas) and cross-fades to the next.
// LED look: a fine pixel grid that fades out with distance (fwidth) so it never shimmers or moirés on phones.
// Emission is capped and scaled by time of day so screens stay legible without blooming at night.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 region_a = vec4(0.0, 0.0, 0.25, 0.25);   // x, y, w, h in atlas UV
uniform vec4 region_b = vec4(0.0, 0.0, 0.25, 0.25);
uniform float blend = 0.0;
uniform float glow = 0.4;          // emission strength (time-of-day scaled by the manager)
uniform float led = 1.0;           // 0 = printed/static panel, 1 = LED screen
uniform float grid_density = 160.0;
uniform float wet = 0.0;

void fragment() {
	vec3 a = texture(atlas, region_a.xy + UV * region_a.zw).rgb;
	vec3 b = texture(atlas, region_b.xy + UV * region_b.zw).rgb;
	vec3 c = mix(a, b, smoothstep(0.0, 1.0, blend));
	vec2 g = UV * vec2(grid_density * 4.0, grid_density);
	float fw = max(fwidth(g.x), fwidth(g.y));
	float cells = smoothstep(0.42, 0.5, max(abs(fract(g.x) - 0.5), abs(fract(g.y) - 0.5)));
	float grid = led * cells * (1.0 - smoothstep(0.25, 0.6, fw)) * 0.45;
	c *= 1.0 - grid;
	ALBEDO = c * mix(0.35, 1.0, 1.0 - led);
	ROUGHNESS = mix(0.5, 0.18, max(led, wet));
	SPECULAR = 0.4;
	EMISSION = c * glow * led * (1.0 - grid * 0.5);
}
