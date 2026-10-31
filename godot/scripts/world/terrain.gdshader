// Terrain: grass / forest floor, bare earth and rock blended by vertex colour (r = rock by slope/height,
// g = dirt verge near the road). World-space UVs in metres; wet and dust follow the weather.
shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 grass_tint : source_color = vec3(0.8, 0.9, 0.7);
uniform vec3 dirt_tint : source_color = vec3(0.8, 0.6, 0.45);
uniform vec3 rock_tint : source_color = vec3(0.75);
uniform float wet = 0.0;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz;
	vec3 g = texture(grass_tex, uv / 5.0).rgb * grass_tint;
	// break up tiling with a second, larger sample
	g *= 0.75 + 0.5 * texture(grass_tex, uv / 61.0).g;
	vec3 d = texture(dirt_tex, uv / 4.0).rgb * dirt_tint;
	vec3 r = texture(rock_tex, vec2(uv.x + wpos.y, uv.y - wpos.y) / 9.0).rgb * rock_tint;
	vec3 c = mix(g, d, COLOR.g);
	c = mix(c, r, COLOR.r);
	ALBEDO = c * mix(1.0, 0.65, wet);
	ROUGHNESS = mix(0.95, 0.5, wet);
}
