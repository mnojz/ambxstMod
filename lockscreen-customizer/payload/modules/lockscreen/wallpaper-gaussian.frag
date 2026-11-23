#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 texelStep;
    float sigma;
};

layout(binding = 1) uniform sampler2D source;

void main()
{
    float width = clamp(sigma, 0.05, 8.5);
    float cutoff = ceil(3.0 * width);

    // Generate successive weights for adjacent texels. Starting at weight 1,
    // each step multiplies by exp(-(2*i - 1) / (2*sigma*sigma)).
    float ratio = exp(-0.5 / (width * width));
    float ratioStep = ratio * ratio;
    float weight = 1.0;
    float total = 1.0;
    vec4 value = texture(source, qt_TexCoord0);

    for (int i = 1; i <= 25; i += 2) {
        if (float(i) > cutoff)
            break;

        float first = weight * ratio;
        ratio *= ratioStep;
        weight = first * ratio;
        ratio *= ratioStep;
        float second = float(i + 1) <= cutoff ? weight : 0.0;
        float pairWeight = first + second;
        if (pairWeight < 0.000001)
            break;

        // Linear filtering combines two neighboring taps in one fetch.
        vec2 offset = texelStep * (float(i) + second / pairWeight);
        value += pairWeight * (texture(source, qt_TexCoord0 - offset)
                             + texture(source, qt_TexCoord0 + offset));
        total += 2.0 * pairWeight;
    }
    fragColor = value * (qt_Opacity / total);
}
