shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec3 albedo : source_color;
uniform sampler2D water_texture1;
uniform sampler2D water_texture2;
uniform sampler2D noise_texture;
uniform vec2 scroll_speed1 = vec2(0.05, 0.0);
uniform vec2 scroll_speed2 = vec2(-0.03, 0.0);
uniform float blend_factor = 0.5;
uniform vec2 scale1 = vec2(1.0, 1.0);
uniform vec2 scale2 = vec2(1.0, 1.0);
uniform float wave_strength = 0.025;
uniform float wave_scale = 0.1;
uniform int pixelation_level = 32;
uniform float FoamSize = 0.5;
uniform sampler2D DepthTexture : hint_depth_texture; 
uniform float WaterOpacity = 0.8;
uniform float FoamGlowIntensity = 0.5;

// New uniforms for wobble effect
uniform float wobble_speed = 1.0;
uniform float wobble_strength = 0.02;

void vertex() {
    vec2 global_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
    float noise_value = texture(noise_texture, global_position * wave_scale).r;

    // Multiple wave frequencies
    float wave1 = sin(global_position.x * 2.0 + global_position.y * 2.0 + TIME * 2.0 + noise_value * 10.0) * wave_strength;
    float wave2 = cos(global_position.x * 3.0 - global_position.y * 1.5 + TIME * 1.5 + noise_value * 8.0) * wave_strength * 0.7;
    float wave3 = sin(global_position.x * 1.5 - global_position.y * 2.5 + TIME * 1.8 + noise_value * 12.0) * wave_strength * 0.5;

    VERTEX.y += wave1 + wave2 + wave3;
}

void fragment() {
    // Apply wobble effect to UV coordinates
    vec2 wobble_uv = UV;
    wobble_uv.x += sin(wobble_uv.y * 10.0 + TIME * wobble_speed) * wobble_strength;
    wobble_uv.y += cos(wobble_uv.x * 10.0 + TIME * wobble_speed) * wobble_strength;

    vec2 scaledUV1 = wobble_uv * scale1 * 1.0;
    vec2 scaledUV2 = wobble_uv * scale2 * 1.0;
    vec2 scrolledUV1 = scaledUV1 + scroll_speed1 * TIME;
    vec2 scrolledUV2 = scaledUV2 + scroll_speed2 * TIME;
    scrolledUV1 = mod(scrolledUV1, vec2(1.0, 1.0));
    scrolledUV2 = mod(scrolledUV2, vec2(1.0, 1.0));
    scrolledUV1 = floor(scrolledUV1 * float(pixelation_level)) / float(pixelation_level);
    scrolledUV2 = floor(scrolledUV2 * float(pixelation_level)) / float(pixelation_level);

    vec4 water_color1 = texture(water_texture1, scrolledUV1);
    vec4 water_color2 = texture(water_texture2, scrolledUV2);
    vec4 blended_water_color = mix(water_color1, water_color2, blend_factor);

    float depthValue = texture(DepthTexture, SCREEN_UV).r;
    vec4 worldPosition = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depthValue, 1.0);
    worldPosition.xyz /= worldPosition.w;
    float foamEffect = clamp(1.0 - smoothstep(worldPosition.z + FoamSize, worldPosition.z, VERTEX.z), 0.0, 1.0);
    float foamOpacity = 1.0 - foamEffect;
    float foamEffectRounded = round(foamOpacity);
    float finalOpacity = foamEffectRounded + WaterOpacity;

    ALBEDO = blended_water_color.rgb * albedo;
    ALPHA = finalOpacity;
    EMISSION = vec3(foamEffectRounded) * FoamGlowIntensity;
    METALLIC = 0.0;
    ROUGHNESS = 1.0;
}