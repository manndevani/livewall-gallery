// Drifting Lights - soft, out-of-focus lights rising slowly in the dark.
float hash(float2 p) { return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

void mainImage(out float4 fragColor, in float2 fragCoord)
{
    float2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float3 col = float3(0.015, 0.02, 0.035) + 0.03 * float3(0.2, 0.3, 0.5) * (1.0 - length(uv));

    for (int layer = 0; layer < 3; layer++) {
        float fl = (float)layer;
        float scale = 4.0 + fl * 3.0;
        float2 p = uv * scale + float2(fl * 7.3, iTime * (0.05 + 0.03 * fl));
        float2 cell = floor(p);
        float2 f = frac(p) - 0.5;
        float h = hash(cell + fl * 13.0);
        if (h > 0.55) {
            float2 off = float2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5;
            float r = 0.12 + 0.18 * hash(cell + 5.3);
            float d = length(f - off * 0.5);
            float a = smoothstep(r, r * 0.6, d) * (0.6 + 0.4 * sin(iTime * 0.5 + h * 30.0));
            float3 tint = lerp(float3(0.9, 0.6, 0.3), float3(0.4, 0.6, 1.0), hash(cell + 9.1));
            col += tint * a * (0.18 - 0.04 * fl);
        }
    }
    fragColor = float4(col, 1.0);
}
