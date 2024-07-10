Shader "Custom/Water"
{
    Properties
    {
        [HideInInspector]_MainTex ("Texture", 2D) = "white" {}
        _RefractTex("RefractNormalTex",2D) = "white"{}
        [Toggle(REFRACT_ON)] _isRefract ("isRefract", Float) = 0.0
        _RefractFactor("RefractFactor",Range(0,1)) = 0.5
        _NormalFactor("NormalFactor",Range(0,1)) = 0.5
        _ShallowColor("ShallowColor",Color) = (1,1,1,1)
        _DeepColor("DeepColor",Color) = (0,0,0,1)
        _DepthMin("DepthMin",Range(0,1)) = 1
        _DepthMax("DepthMax",Range(0,1)) = 1
        _FoamTex("泡沫形状纹理",2D) = "white"{}
        _FoamRange("泡沫范围",Range(0,3)) = 0.1
        _FoamSmooth("泡沫平滑度",Range(0,10)) = 0.1
        _CubeMap("CubeMap",Cube) = "white"{}
        _CausticsTex("焦散贴图",2D) = "white"{}
        _CausticsIntensity("焦散强度",Range(0,1)) = 0.5
        _SpecularPower("SpecularPower",Range(0,100)) = 16
        _FreshnelPower("FreshnelPower",Range(0,100)) = 16
    }
    SubShader
    {
        Tags
        {
            "Queue" = "Transparent"
            "RenderType" = "Opaque"
        }
        LOD 100
        Cull Off
        ZWrite Off
        Pass
        {
            Tags {
                "LightMode" = "UniversalForward"
            }
            Blend SrcAlpha OneMinusSrcAlpha
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local_fragment REFRACT_ON
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
                float3 tangentOS : TANGENT;
                
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 posWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float3 posVS : TEXCOORD3;
                float4 ScreenUV : TEXCOORD4;
                float3 tangentWS : TEXCOORD5;
                float3 binormalWS : TEXCOORD6;
               
                
            };
            
            CBUFFER_START(UnityPerMaterial)
            sampler2D _MainTex;
            float4 _MainTex_ST;
            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);
            TEXTURE2D(_CameraOpaqueTexture);
            SAMPLER(sampler_CameraOpaqueTexture);
            TEXTURE2D(_FoamTex);
            SAMPLER(sampler_FoamTex);
            TEXTURE2D(_RefractTex);
            SAMPLER(sampler_RefractTex);
            float4 _RefractTex_ST;
            float4 _FoamTex_ST;
            float _RefractFactor;
            //sampler2D _CameraDepthTexture;
            float _FoamRange;
            float4 _ShallowColor;
            float _NormalFactor;
            float4 _DeepColor;
            float _DepthMin;
            float _DepthMax;
            float _FoamSmooth;
            float _SpecularPower;
            TEXTURECUBE(_CubeMap);
            SAMPLER(sampler_CubeMap);
            TEXTURE2D(_CausticsTex);
            SAMPLER(sampler_CausticsTex);
            float4 _CausticsTex_ST;
            float _CausticsIntensity;
            float _FreshnelPower;
            //float _isRefract;
            CBUFFER_END
            
            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.posWS = TransformObjectToWorld(v.vertex).xyz;
                o.posVS = TransformWorldToView(o.posWS);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.tangentWS = TransformObjectToWorldNormal(v.tangentOS);
                o.binormalWS = cross(o.normalWS,o.tangentWS);
                o.ScreenUV.xy = o.vertex.xy * float2(0.5, -0.5) +  o.vertex.w*0.5f;
                o.ScreenUV.zw = o.vertex.zw;
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                //获取屏幕UV，_ScreenParams.xy是屏幕的宽高
                float2 ScreenUVOrigin = i.vertex.xy / _ScreenParams.xy;
                //float2 ScreenUVOrigin = i.ScreenUV.xy/i.ScreenUV.w;
                float2 OriginScreenUV = ScreenUVOrigin;
                
                //采样扰动的折射纹理
                float3 NormalMap = SAMPLE_TEXTURE2D(_RefractTex, sampler_RefractTex, i.uv*_RefractTex_ST.xy+_RefractTex_ST.zw+_SinTime);
                float3 Normal = UnpackNormal(float4(NormalMap,1)).rgb;
                float3x3 TBN = float3x3(i.tangentWS, i.binormalWS, i.normalWS);
                Normal = mul(TBN, Normal);//法线
                Normal.b *= 0.5;//重新计算法线B分量
                float2 RefractUV =  Normal.xy;//折射UV
                
                //对屏幕UV进行扰动
                //#ifdef REFRACT_ON
                float2 ScreenUV = lerp(OriginScreenUV,RefractUV,_RefractFactor);
                //#endif

                //使用不同的UV采样深度图
                float depth;float depthRefract;
                depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, OriginScreenUV);
                depthRefract = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, ScreenUV);
                
                //修正后的线性深度
                depth = LinearEyeDepth(depth, _ZBufferParams);
                depthRefract = LinearEyeDepth(depthRefract, _ZBufferParams);
                //float4 col = tex2D(_MainTex, i.uv);

                
                //计算Height（水底到水面的高度）用于颜色插值
                //如果是没有水底的水面，depthZ是无穷大的
                float depthZ =   i.posVS.z+ depth;
                float depthZR = i.posVS.z+ depthRefract;

                
                float FoamRange;
                FoamRange = depthZR*_FoamRange;
                
                if(depthZR < 0 )//高度<0说明是水面上方
                {
                    ScreenUV = OriginScreenUV;//水面上方没有折射，所以使用未扰动的UV
                    FoamRange = depthZ*_FoamRange;//水面上方没有折射，所以使用未扰动的UV采样的深度图
                }
                
                //根据屏幕UV采样抓屏纹理
                float3 RefractColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, ScreenUV).rgb;
                
                
                //采样泡沫纹理
                float3 Foam = SAMPLE_TEXTURE2D(_FoamTex, sampler_FoamTex, i.uv*_FoamTex_ST.xy+_FoamTex_ST.zw*_SinTime).r;
                //泡沫平滑
                Foam = pow(Foam,_FoamSmooth);
                Foam = step(FoamRange,Foam);
                //Foam = lerp(float3(0,0,0),Foam,step(FoamRange,Foam));

                //高光
                float3 lightDir = GetMainLight().direction;
                float3 normal = lerp(i.normalWS,normalize(Normal),_NormalFactor);
                normal = normalize(normal);
                float3 viewDir = normalize(_WorldSpaceCameraPos - i.posWS);
                float3 halfDir = normalize(lightDir + viewDir);
                float spec = pow(saturate(dot(normal, halfDir)), _SpecularPower);
                
                //采样天空盒
                float3 reflectV = reflect(-viewDir, normal);
                //float3 skyColor = SAMPLE_TEXTURECUBE(unity_SpecCube0,samplerunity_SpecCube0, reflectV);
                //实时环境反射（反射探针）
                float3 skyColor = SAMPLE_TEXTURECUBE(_CubeMap, sampler_CubeMap, reflectV);
                
                //菲涅尔
                float fresnel = pow(1 - saturate(dot(lightDir, reflectV)),_FreshnelPower);

                //焦散
                float4 objPosVS = 1;
                objPosVS.xy = - depthRefract/i.posVS.z*i.posVS.xy;
                objPosVS.z = depthRefract;
                float3 objPosWS = mul(unity_CameraToWorld,objPosVS).xyz;
                float2 CausticsUV1 = (objPosWS.xz+objPosWS.y)*_CausticsTex_ST.xy+_CausticsTex_ST.zw+_SinTime*0.2+0.5;
                float2 CausticsUV2 = (objPosWS.xz+objPosWS.y)*_CausticsTex_ST.xy+_CausticsTex_ST.zw+_CosTime*0.2+0.5;
                float3 Caustics1 = SAMPLE_TEXTURE2D(_CausticsTex, sampler_CausticsTex,CausticsUV1).rgb;
                float3 Caustics2 = SAMPLE_TEXTURE2D(_CausticsTex, sampler_CausticsTex,CausticsUV2).rgb;
                float3 Caustics = lerp(Caustics1,Caustics2,_RefractFactor)*_CausticsIntensity;
                
                
                //No Refuse
                float3 Color = lerp(_ShallowColor.xyz,_DeepColor.xyz,FoamRange)*(RefractColor)+Foam+skyColor*(spec+fresnel)+Caustics ;
                return float4(Color,1);
            }
            ENDHLSL
        }
    }
}
