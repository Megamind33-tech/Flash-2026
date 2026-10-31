// Road surface (plan gate G4): Poly Haven CC0 PBR asphalt (albedo, GL normal, roughness, height).
// - Roughness follows the real height map: worn high spots are smoother and lighter.
// - Rain: water collects in the genuine low spots of the height map, at a large scale, so puddles sit in
//   real dips, go mirror-smooth and flatten the normal.
// - Racing-line rubber and brake marks come from a per-track mask baked from the AI racing line and the
//   braking zones of the speed profile (CityWorld.bake_lap_mask), not from noise.
// UV: x = metres across the road (0 = centreline), y = metres along the lap.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_gray, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D lap_mask : filter_linear, repeat_enable;   // R rubber line, G brake marks
uniform vec3 tint : source_color = vec3(1.0);
uniform float tile = 4.0;            // metres per texture repeat
uniform float road_half = 7.1;       // half width covered by the mesh (to the barrier)
uniform float lap_length = 3000.0;
uniform float wear = 0.6;
uniform float wet = 0.0;

void fragment() {
	vec2 m = UV;
	vec2 t = m / tile;
	vec3 base = texture(albedo_tex, t).rgb * tint;
	float rough = texture(rough_tex, t).r;
	float h = texture(height_tex, t).r;
	// large-scale tonal variation from the same height map (resurfacing / sun-bleached lanes)
	float big = texture(height_tex, m / 37.0 + vec2(0.31, 0.17)).r;
	base *= mix(1.0, 0.82 + 0.36 * big, wear);
	// worn high spots polish: lighter and smoother
	base *= 0.92 + 0.16 * h;
	rough = clamp(rough * mix(1.05, 0.85, h), 0.05, 1.0);
	// baked racing line + brake marks
	vec4 mask = texture(lap_mask, vec2(clamp(m.x / (2.0 * road_half) + 0.5, 0.0, 1.0), m.y / lap_length));
	base *= 1.0 - 0.22 * mask.r * wear - 0.35 * mask.g;
	rough = mix(rough, rough * 0.8, mask.r);
	// rain: darken everything, water fills the real low spots
	float low = 1.0 - texture(height_tex, m / 23.0).r;
	float puddle = wet * smoothstep(0.48, 0.56, low) * (1.0 - mask.r * 0.5);
	vec3 col = base * mix(1.0, 0.4, wet);
	rough = mix(rough, max(rough * 0.6, 0.35), wet);   // wet but still rough: puddles must read as mirrors against it
	rough = mix(rough, 0.02, puddle);
	col = mix(col, col * 0.45, puddle);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = mix(0.5, 0.95, puddle);
	NORMAL_MAP = mix(texture(normal_tex, t).rgb, vec3(0.5, 0.5, 1.0), puddle * 0.95 + wet * 0.25);
}
