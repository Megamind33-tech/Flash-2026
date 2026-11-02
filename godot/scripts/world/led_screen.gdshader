// Digital billboard (GRINDLINE 27): an LED screen that cycles through the sponsor atlas (4 x 4 cells). Each panel's
// UVs cover one atlas cell's size; its vertex colour red channel holds its phase (cell offset / 16) so screens
// around the circuit do not all change at once. Self-lit like a real screen, with a faint glass sheen on top.
shader_type spatial;
render_mode cull_back;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float period = 7.0;          // seconds per advert
uniform float brightness = 1.15;     // screen emission (daylight-readable)

void fragment() {
	float idx = mod(floor(TIME / period) + floor(COLOR.r * 16.0 + 0.5), 16.0);
	vec2 cell = vec2(mod(idx, 4.0), floor(idx / 4.0)) * 0.25;
	vec2 uv = cell + clamp(UV, vec2(0.002), vec2(0.248));
	vec3 c = texture(atlas, uv).rgb;
	// fine LED row structure, faded out with distance so it never shimmers
	float rows = 0.92 + 0.08 * step(0.35, fract(UV.y * 4.0 * 107.0));
	float fade = clamp(length(VERTEX) / 40.0, 0.0, 1.0);
	c *= mix(rows, 1.0, fade);
	ALBEDO = c * 0.08;
	EMISSION = c * brightness;
	ROUGHNESS = 0.22;
	SPECULAR = 0.5;
}
