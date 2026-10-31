// Road-damage scan laid on the asphalt as a decal: the scan's own albedo and normal map, a border that fades
// into the surrounding road (no hard patch outline), and the same wet response as road.gdshader.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool has_normal = false;
uniform vec3 centre = vec3(0.0);   // patch centre in mesh space
uniform float radius = 1.0;        // fade reaches zero at this distance (metres, mesh space)
uniform float wet = 0.0;
uniform vec3 colour_match = vec3(1.0);   // road average / scan average, so the patch takes the city's asphalt colour

varying vec3 mesh_pos;

void vertex() {
	mesh_pos = VERTEX;
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	ALBEDO = c * colour_match * mix(1.0, 0.55, wet);
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	ROUGHNESS = mix(0.88, 0.32, wet);
	float r = length(mesh_pos.xz - centre.xz) / radius;
	ALPHA = 1.0 - smoothstep(0.4, 0.84, r);   // starts early: the scans' own borders are lighter than the road
}
