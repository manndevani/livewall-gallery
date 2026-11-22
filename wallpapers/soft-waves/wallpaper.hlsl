// Soft Waves - layered ribbons of light moving slowly across a dark sky.
void mainImage(out float4 fragColor, in float2 fragCoord)
{
    float2 uv = fragCoord / iResolution.xy;
    float t = iTime * 0.12;
    float3 col = lerp(float3(0.02, 0.03, 0.07), float3(0.05, 0.04, 0.10), uv.y);

    for (int i = 0; i < 5; i++) {
        float fi = (float)i;
        float y = 0.30 + 0.10 * fi
                + 0.06 * sin(uv.x * (2.0 + fi * 0.7) + t * (1.0 + 0.3 * fi) + fi * 1.7)
                + 0.03 * sin(uv.x * 5.0 - t * 1.3 + fi);
        float d = abs(uv.y - y);
        float glow = 0.004 / (d + 0.004) * (0.35 - 0.05 * fi);
        float3 tint = 0.5 + 0.5 * cos(fi * 0.9 + float3(0.0, 1.8, 3.6) + t * 0.3);
        col += tint * glow * 0.6;
    }
    fragColor = float4(col, 1.0);
}
