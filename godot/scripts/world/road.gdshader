// Road surface (plan gate G4): Poly Haven CC0 PBR asphalt (albedo, GL normal, roughness, height).
// - Roughness follows the real height map: worn high spots are smoother and lighter.
// - Rain: puddles are smooth, road-elongated blobs (two octaves of value noise) that gather toward the
//   gutters and avoid the rubbered racing line; their ragged rims come from the asphalt height map. Inside a
//   puddle the surface is a dark, mirror-smooth, flat film with expanding raindrop ripple rings, so it reads
//   as standing water against the merely damp road around it.
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
uniform float crack_fade = 0.0;      // 0 = the scan as is; 1 = cracks lifted to the surrounding tone (resurfaced race venue)
uniform float anti_tile = 1.0;
uniform float detail_soften = 0.45;  // pulls the aggregate's pixel-scale contrast toward the local tone: no salt-and-pepper speckle
uniform float rough_floor = 0.55;    // dry asphalt is never glossy at pixel scale: stops specular sparkle on the aggregate       // blends a second, rotated, differently scaled sample so the 4 m tile never repeats visibly

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 m = UV;
	vec2 t = m / tile;
	// anti-tiling: a second sample, rotated ~37 degrees and 1.37x the scale, mixed in by low-frequency noise
	vec2 t2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * (m / (tile * 1.37)) + vec2(0.37, 0.71);
	float mixw = anti_tile * smoothstep(0.3, 0.7, vnoise(m * 0.09));
	vec3 base = mix(texture(albedo_tex, t).rgb, texture(albedo_tex, t2).rgb, mixw) * tint;
	float rough = mix(texture(rough_tex, t).r, texture(rough_tex, t2).r, mixw);
	float h = mix(texture(height_tex, t).r, texture(height_tex, t2).r, mixw);
	// local tone (a coarse mip of both samples): the reference for softening speckle and lifting cracks
	vec3 local = mix(textureLod(albedo_tex, t, 4.0).rgb, textureLod(albedo_tex, t2, 4.0).rgb, mixw) * tint;
	// Soften only where the texture is minified (more than ~1.5 texels per pixel, i.e. far away or at grazing
	// angles, where aggregate detail is finer than a pixel and would shimmer). Close to the camera, where the
	// scan is resolved, the real aggregate detail stays: the old constant blend blurred the near road too.
	vec2 texels = fwidth(t) * vec2(textureSize(albedo_tex, 0));
	float footprint = max(texels.x, texels.y);
	float soften = detail_soften * smoothstep(1.2, 4.0, footprint);
	base = mix(base, local, soften);
	// crack fade: pixels much darker than their neighbourhood (the cracks in the scan) are lifted toward it
	if (crack_fade > 0.0) {
		float dark = clamp((dot(local, vec3(0.333)) - dot(base, vec3(0.333))) * 16.0, 0.0, 1.0);
		base = mix(base, local, dark * crack_fade);
	}
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
	// rain: the whole road darkens and goes satin; puddles stand in shallow dips toward the gutters
	vec3 nm = mix(texture(normal_tex, t).rgb, texture(normal_tex, t2).rgb, mixw);
	nm = mix(nm, vec3(0.5, 0.5, 1.0), 0.6);   // gentler normal detail on every road: the scan's pixel-scale normals sparkle in the sun
	float puddle = 0.0;
	vec2 ripple = vec2(0.0);
	if (wet > 0.0) {
		float field = vnoise(m * vec2(0.55, 0.22)) * 0.6 + vnoise(m * vec2(1.4, 0.9) + 7.3) * 0.4;
		float gutter = smoothstep(0.6, 0.95, abs(m.x) / road_half);
		field += gutter * 0.14 - mask.r * 0.3 + (0.5 - h) * 0.12;
		float thr = mix(0.80, 0.66, wet);   // ~11 % of the road in rain, ~15 % in a storm
		puddle = smoothstep(thr, thr + 0.035, field);
		// raindrop rings: one drop per 0.6 m cell, random phase, ring expanding over its cycle
		vec2 cell = floor(m / 0.6);
		vec2 f = fract(m / 0.6) - 0.5;
		float ph = fract(TIME * 0.9 + hash(cell));
		vec2 off = vec2(hash(cell + 3.1), hash(cell + 5.7)) - 0.5;
		vec2 d = f - off * 0.5;
		float r = length(d);
		float ring = sin((r - ph * 0.45) * 60.0) * smoothstep(0.09, 0.0, abs(r - ph * 0.45)) * (1.0 - ph);
		ripple = d / max(r, 1e-3) * ring * 0.35 * puddle * wet;
	}
	vec3 col = base * mix(1.0, 0.45, wet);
	rough = max(rough, rough_floor * (1.0 - wet));
	rough = mix(rough, max(rough * 0.6, 0.35), wet);   // damp but still rough, so puddles read as mirrors against it
	rough = mix(rough, 0.03, puddle);
	col = mix(col, base * 0.12, puddle);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = mix(0.5, 0.6, puddle);
	nm = mix(nm, vec3(0.5, 0.5, 1.0), clamp(puddle * 0.97 + wet * 0.25, 0.0, 1.0));
	nm.xy += ripple;
	NORMAL_MAP = nm;
}
