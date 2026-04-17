Shader "Custom/PM Cloud"
{
    Properties
    {
        [Main(Setting,_,off,off)] _Setting("Setting", Float) = 0
        [Sub(Setting)] _BaseMap("Base Map", 2D) = "white" {}
        [Sub(Setting)] _BaseColor("Base Color", Color) = (1,1,1,1)
        [Sub(Setting)] _kh("kh", Float) = 0.01
        [Sub(Setting)] _FlowSpeed("Flow Speed", Vector) = (1,1,1,1)
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float2 uv           : TEXCOORD0;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
            };

            struct Varyings
            {
                float4 positionHCS  : SV_POSITION;
                float2 uv           : TEXCOORD0;
                float3 normalWS     : TEXCOORD1;
                float3 tangentWS    : TEXCOORD2;
                float3 bitangentWS  : TEXCOORD3;
                float3 positionWS   : TEXCOORD4;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BaseColor;
                float _kh;
                float4 _FlowSpeed;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                float3 normalWS = TransformObjectToWorldNormal(IN.normalOS);
                float3 tangentWS = TransformObjectToWorldDir(IN.tangentOS.xyz);
                float tangentSign = IN.tangentOS.w * GetOddNegativeScale();
                float2 baseUV = TRANSFORM_TEX(IN.uv, _BaseMap);

                OUT.uv = baseUV;

                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.normalWS = normalWS;
                OUT.tangentWS = tangentWS;
                OUT.bitangentWS = cross(normalWS, tangentWS) * tangentSign;
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                
                return OUT;
            }
            
            float2 ParallaxOcclusionMapping(float2 baseUV, float3 positionWS, half3x3 transitionMatrix, float kh)
            {
                float3 viewDirWS = normalize(_WorldSpaceCameraPos - positionWS);
                float3 viewDirTS = normalize(mul(transitionMatrix,viewDirWS));
                
                //分层步近搜索交点
                const int LAYER = 32;
                
                float deltaH = 1.0 / LAYER;
                float2 totalOffset = float2(viewDirTS.x,viewDirTS.y)/max(viewDirTS.z,0.001) * kh;
                float2 deltaOffset = totalOffset / LAYER;
                
                float2 offset = 0;
                float layerH = 0;
                float preDiff = SAMPLE_TEXTURE2D(_BaseMap,sampler_BaseMap,baseUV).r;
                
                UNITY_LOOP
                for (int i=0;i<LAYER;i++)
                {
                    layerH += deltaH;
                    offset+=deltaOffset;
                    
                    float sampleH = SAMPLE_TEXTURE2D_LOD(_BaseMap,sampler_BaseMap,baseUV+offset,0).r;
                    if (layerH > sampleH)
                    {
                        //搜索后再插值细化交点
                        float currDiff = sampleH - layerH;
                        float weight = preDiff / (preDiff - currDiff);
                        offset = lerp(offset - deltaOffset, offset, weight);
                        break;
                    }
                    
                    preDiff = sampleH - layerH;
                }
                
                return offset;
            }


            half4 frag(Varyings IN) : SV_Target
            {
                half3x3 tbn = half3x3(
                    normalize(IN.tangentWS),
                    normalize(IN.bitangentWS),
                    normalize(IN.normalWS)
                );   
                
                //纹理动画
                float2 flowUV = IN.uv + frac(_Time.y * _FlowSpeed.xy * 0.01);
                float2 heightUV = IN.uv * 0.5 + frac(_Time.y * _FlowSpeed.zw * 0.01);
                
                //高度扰动
                float kh = _kh * SAMPLE_TEXTURE2D(_BaseMap,sampler_BaseMap,heightUV).r;
                
                //视差效果
                float2 parallaxUV = flowUV + ParallaxOcclusionMapping(flowUV,IN.positionWS,tbn,kh);
                half3 color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, parallaxUV).rgb;
                return half4(color,1.0);
            }
            ENDHLSL
        }
    }

    CustomEditor "LWGUI.LWGUI"
}