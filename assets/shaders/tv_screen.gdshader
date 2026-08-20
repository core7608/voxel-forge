shader_type canvas_item;

// Animated "on-air" TV screen: scrolling colour bars + static noise + scanline roll.
// Used by the interactive Television furniture (Section 8.2, stage 1).
uniform float speed : source_range = 1.0;

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;

	// scrolling colour bars
	float bar = floor(uv.x * 8.0 + t * 0.4);
	vec3 barcol = vec3(
		0.5 + 0.5 * sin(bar * 1.3),
		0.5 + 0.5 * sin(bar * 1.7 + 2.0),
		0.5 + 0.5 * sin(bar * 2.1 + 4.0));

	// static noise
	vec2 seed = vec2(12.9898, 78.233);
	float n = fract(sin(dot(uv * vec2(400.0, 300.0) + t * 12.0, seed)) * 43758.5453);

	// slow scanline roll + flicker
	float roll = step(0.985, fract(uv.y * 2.0 - t * 0.5));
	float flicker = 0.92 + 0.08 * sin(t * 55.0);

	vec3 col = mix(barcol, vec3(n), 0.35);
	col += vec3(roll) * 0.6;
	col *= flicker;
	// slight vignette
	float vig = smoothstep(1.2, 0.4, length(uv - 0.5) * 1.6);
	col *= 0.5 + 0.5 * vig;

	COLOR = vec4(col, 1.0);
}
