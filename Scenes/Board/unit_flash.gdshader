// The hit flash of a rigged UnitFigure: blends what UV.x marks (the
// figure's pieces, 1) toward white by `flash`; the weapon trail and the
// glow (UV.x 0) keep their colours, like the sketch's tint.
shader_type canvas_item;

uniform float flash = 0.0;

void fragment() {
	COLOR.rgb = mix(COLOR.rgb, vec3(1.0), flash * UV.x);
}
