#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 texelStep;
};

layout(binding = 1) uniform sampler2D source;

// Symmetric, normalized weights for one axis of the Gaussian kernel.
const float weights[8] = float[8](0.134598348, 0.127324582, 0.107777932, 0.081638025, 0.055335035, 0.033562395, 0.018215906, 0.008846951);

void main()
{
    vec4 value = texture(source, qt_TexCoord0) * weights[0];
    for (int i = 1; i < 8; ++i) {
        vec2 offset = texelStep * float(i);
        value += weights[i] * (texture(source, qt_TexCoord0 - offset)
                              + texture(source, qt_TexCoord0 + offset));
    }
    fragColor = value * qt_Opacity;
}
