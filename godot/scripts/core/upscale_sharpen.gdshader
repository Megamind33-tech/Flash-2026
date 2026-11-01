// Contrast-adaptive sharpening after the Mobile renderer's bilinear 3D upscale (Godot 4.7 offers FSR 1 only on
// Forward+). Same principle as the RCAS stage of FSR 1 / AMD CAS (MIT): each pixel is sharpened against its four
// neighbours with a weight limited by the local min/max, so edges regain contrast lost to the stretch without
// ringing halos, and flat or already high-contrast areas are left alone. One full-screen pass, 5 taps.
// Written for GRIDLINE from the published algorithm; no AMD source code is included.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float sharpness : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	vec3 n = texture(screen_tex, SCREEN_UV + vec2(0.0, -px.y)).rgb;
	vec3 s = texture(screen_tex, SCREEN_UV + vec2(0.0, px.y)).rgb;
	vec3 w = texture(screen_tex, SCREEN_UV + vec2(-px.x, 0.0)).rgb;
	vec3 e = texture(screen_tex, SCREEN_UV + vec2(px.x, 0.0)).rgb;
	vec3 mn = min(c, min(min(n, s), min(w, e)));
	vec3 mx = max(c, max(max(n, s), max(w, e)));
	// headroom to black and white limits the lobe: no clipping, no halo
	vec3 amp = sqrt(clamp(min(mn, 1.0 - mx) / max(mx, vec3(1e-4)), 0.0, 1.0));
	vec3 lobe = amp * (-1.0 / mix(8.0, 4.5, sharpness));
	vec3 col = (c + (n + s + w + e) * lobe) / (1.0 + 4.0 * lobe);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
