shader_type canvas_item;

// Procedural "confused" symbol drawn over a stunned card: a spinning two-arm
// spiral with small sparkle stars orbiting it. Applied to a ColorRect (UV 0..1).

uniform float alpha : hint_range(0.0, 1.0) = 0.0;  // faded in/out from Card.gd
uniform vec4 swirl_color : source_color = vec4(0.78, 0.55, 1.0, 1.0);
uniform vec4 star_color : source_color = vec4(1.0, 0.92, 0.45, 1.0);
uniform float spin_speed = 2.5;
uniform float star_speed = 1.6;

float sparkle(vec2 p, float size) {
	p /= size;
	float core = 1.0 - smoothstep(0.0, 0.35, length(p));
	float ray_x = (1.0 - smoothstep(0.0, 0.08, abs(p.y))) * (1.0 - smoothstep(0.3, 1.0, abs(p.x)));
	float ray_y = (1.0 - smoothstep(0.0, 0.08, abs(p.x))) * (1.0 - smoothstep(0.3, 1.0, abs(p.y)));
	return clamp(core + ray_x + ray_y, 0.0, 1.0);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;  // -1..1, centred
	float r = length(p);
	float a = atan(p.y, p.x);

	// Two-arm spiral rotating over time, masked to a ring
	float arm = sin(2.0 * (a + TIME * spin_speed) - r * 12.0);
	float swirl = smoothstep(0.55, 0.9, arm);
	swirl *= smoothstep(0.05, 0.15, r) * (1.0 - smoothstep(0.5, 0.65, r));

	// Three stars on a flattened orbit (cartoon "dizzy" halo)
	float stars = 0.0;
	for (int i = 0; i < 3; i++) {
		float ang = TIME * star_speed + float(i) * 2.094;
		vec2 pos = vec2(cos(ang), sin(ang) * 0.45) * 0.8;
		float twinkle = 0.75 + 0.25 * sin(TIME * 6.0 + float(i) * 1.7);
		stars = max(stars, sparkle(p - pos, 0.14 * twinkle));
	}

	vec3 col = swirl_color.rgb * swirl + star_color.rgb * stars;
	float mask = max(swirl, stars);
	COLOR = vec4(col / max(mask, 0.001), mask * alpha);
}
