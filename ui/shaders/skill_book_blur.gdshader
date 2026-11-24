shader_type canvas_item;

// Reuse the rendered scene as a gently defocused backdrop for the level-up book.
// The screen texture's mipmaps provide an inexpensive approximate blur.
uniform sampler2D background_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur_lod : hint_range(0.0, 5.0, 0.1) = 2.4;
uniform vec4 warm_veil : source_color = vec4(0.12, 0.073, 0.047, 0.35);

void fragment() {
    vec3 scene_color = textureLod(background_texture, SCREEN_UV, blur_lod).rgb;
    COLOR = vec4(mix(scene_color, warm_veil.rgb, warm_veil.a), 1.0);
}
