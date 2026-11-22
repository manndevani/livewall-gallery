// reference.hlsl - the gallery's yardstick for how heavy a shader may be.
// A shared shader may take at most 15 times the work of this one, measured
// on the same machine in the same run (see check.ps1). Do not change it:
// that would move the limit for everyone.

void mainImage(out float4 fragColor, in float2 fragCoord)
{
    float2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    float t = iTime * 0.15;

    float v = sin(uv.x * 3.0 + t)
            + sin((uv.y * 3.0 + t) * 0.8)
            + sin((uv.x + uv.y) * 2.5 + t * 1.3)
            + sin(length(uv * 4.0) - t * 2.0);

    float3 col = 0.5 + 0.5 * cos(v * 1.2 + float3(0.0, 2.1, 4.2));
    col *= 0.35; // keep it calm behind desktop icons

    fragColor = float4(col, 1.0);
}
