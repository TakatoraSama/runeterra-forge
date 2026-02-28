shader_type canvas_item;
render_mode blend_add;

uniform vec4 glow_color : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 5.0) = 2.0;
uniform float pulse_speed : hint_range(0.0, 5.0) = 1.5;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float pulse = 0.75 + 0.25 * sin(TIME * pulse_speed * 3.14159);
	COLOR = glow_color * tex.a * intensity * pulse;
}
