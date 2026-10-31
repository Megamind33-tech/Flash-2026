// Crowd animation without skeletons: the Rocketbox spectators are static posed meshes (cheer, clap, idle), so
// the motion is done here in the vertex stage, per instance, at the cost of a few ALU ops per vertex.
//   cheer: bounce on the toes, arms pumping above the shoulders
//   clap:  hands meeting in front of the chest, a small bob
//   idle:  breathing and a slow weight shift (pedestrians)
// Every fan has their own phase and tempo (hashed from their world position), and fans near a passing car get
// louder: they jump higher and pump faster (`cars` holds the race cars' positions, updated every frame).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform bool use_alpha = false;          // the hair/eyelash "opacity" surface is alpha-tested
uniform int pose = 0;                    // 0 cheer, 1 clap, 2 idle
uniform vec4 cars[8];                    // xyz world position, w = 1 if used
uniform float roughness_value = 0.8;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = hash(origin.xz);
	float phase = h * 6.2831;
	float tempo = 0.85 + 0.3 * hash(origin.zx + 7.1);
	// Excitement: a car within ~40 m sets the crowd off.
	float near = 1000.0;
	for (int i = 0; i < 8; i++) {
		if (cars[i].w > 0.5) {
			near = min(near, distance(origin.xz, cars[i].xz));
		}
	}
	float hype = 0.25 + 0.75 * (1.0 - smoothstep(8.0, 45.0, near));
	float t = TIME * tempo;
	vec3 v = VERTEX;
	float up = clamp(v.y / 1.75, 0.0, 1.0);
	if (pose == 0) {
		// arms: everything above the shoulders and outside the torso pumps up and down
		float arm = smoothstep(1.15, 1.45, v.y) * smoothstep(0.14, 0.26, abs(v.x));
		float pump = sin(t * mix(5.0, 9.0, hype) + phase);
		v.y += arm * pump * 0.09 * hype;
		v.x += arm * sign(v.x) * pump * 0.03 * hype;
		// bounce: a little hop on each beat
		float hop = max(0.0, sin(t * mix(4.0, 7.0, hype) + phase * 1.7));
		v.y += hop * hop * 0.07 * hype;
	} else if (pose == 1) {
		// hands in front of the chest close and open
		float hands = smoothstep(0.1, 0.22, abs(v.z)) * smoothstep(0.85, 1.05, v.y) * (1.0 - smoothstep(1.45, 1.6, v.y));
		float clap = 0.5 + 0.5 * sin(t * mix(7.0, 11.0, hype) + phase);
		v.x *= 1.0 - hands * clap * 0.55;
		v.y += abs(sin(t * 3.5 + phase)) * 0.025 * hype;
	} else {
		// breathing and a slow shift from one foot to the other
		v.x += sin(TIME * 0.35 + phase) * 0.025 * up;
		v.y += sin(TIME * 1.6 + phase) * 0.004 * smoothstep(1.0, 1.4, v.y);
	}
	// everyone sways a little, more when excited
	v.x += sin(t * 1.3 + phase * 2.3) * (0.015 + 0.03 * hype) * up;
	VERTEX = v;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb;
	ROUGHNESS = roughness_value;
	if (use_alpha) {
		ALPHA = c.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
}
