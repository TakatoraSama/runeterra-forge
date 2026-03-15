shader_type canvas_item;

uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform float edge_width : hint_range(0.0, 0.15) = 0.06;
uniform vec4 edge_color : source_color = vec4(1.0, 0.5, 0.0, 1.0);
uniform float gradient_weight : hint_range(0.0, 1.0) = 0.5;
uniform float noise_seed = 0.0;  // randomised per card from GDScript
uniform float gray_amount : hint_range(0.0, 1.0) = 0.0;  // 0 = normal, 1 = unaffordable dim

float hash(vec2 p) {
	p += noise_seed;
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void fragment() {
	vec4 original = texture(TEXTURE, UV);

	float n = noise(UV * 6.0);
	float gradient = UV.y;
	float dissolve_value = mix(n, gradient, gradient_weight);

	float threshold = dissolve_amount * (1.0 + edge_width);

	if (dissolve_value < threshold - edge_width) {
		discard;
	}

	float edge_factor = 1.0 - smoothstep(0.0, edge_width, dissolve_value - (threshold - edge_width));
	vec3 final_color = mix(original.rgb, edge_color.rgb, edge_factor * edge_color.a);
	final_color += edge_color.rgb * 1.5 * edge_factor * edge_factor;

	final_color *= mix(1.0, 0.5, gray_amount);
	COLOR = vec4(final_color, original.a);
}
