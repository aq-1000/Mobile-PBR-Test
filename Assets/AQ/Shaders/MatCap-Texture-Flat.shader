// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "SGame/MatCap-Texture-Flat" {
	Properties {
		_MainColor ("Main Color", Color) = (0.5,0.5,0.5,1)
		_MainTex("Base (RGB)", 2D) = "white" {}
		_AlphaTex("Alpha [R:MatCap_1(r),MatCap_2(1-r); G:流光; B:MatCap权重]", 2D) = "white" {}

		// Material Capture纹理
		_MatCap1("MatCap1", 2D) = "white" {}
		_MatCap2("MatCap2", 2D) = "white" {}
		_NormalMap("Normal Map(RGB)", 2D) = "bump" {}

        _RimColor ("Rim Color", Color) = (1, 1, 1, 1)  
        _RimPower ("Rim Power", Range(0.01, 10.0)) = 2.0

		_FlowTex("Flow Texture(RGB)", 2D) = "black" {} // 流光贴图
		_FlowColor("Flow Color", Color) = (1,1,1,1)
		_FlowSpeedU("Flow SpeedU", float) = 0.0 // 流光改变速度
		_FlowSpeedV("Flow SpeedV", float) = 0.0
	}
	
	Subshader {
		Tags { "Queue"="Transparent-1" "IgnoreProjector"="True" "RenderType"="Model"}
		
		Pass {
			Name "BASE"	
			CGPROGRAM
				#pragma vertex vert
				#pragma fragment frag
				#pragma shader_feature MATCAP2_OFF MATCAP2_ON
				#pragma shader_feature NORMALMAP_OFF NORMALMAP_ON
				#pragma shader_feature RIMLIGHT_OFF RIMLIGHT_ON
				#pragma multi_compile FLOW_OFF FLOW_ON
				#pragma multi_compile SHADOWMAP_OFF SHADOWMAP_ON
				#include "UnityCG.cginc"
				
				fixed4 _MainColor;
				sampler2D _MainTex;	float4 _MainTex_ST;
				sampler2D _AlphaTex;
			#if NORMALMAP_ON
				sampler2D _NormalMap;
			#endif
				sampler2D _MatCap1;
			#if MATCAP2_ON
				sampler2D _MatCap2;
			#endif
			#if RIMLIGHT_ON
                uniform fixed4 _RimColor;  
                float _RimPower;
			#endif
			#if FLOW_ON
				sampler2D _FlowTex; float4 _FlowTex_ST;
				uniform fixed4 _FlowColor;  
				uniform half _FlowSpeedU;
				uniform half _FlowSpeedV;
			#endif

			// ShadowMap
				sampler2D _LightDepthTex;
				float4x4 _LightProjection;

				struct v2f { 
					float4 pos : SV_POSITION;
					float2 uv : TEXCOORD0;
				#if NORMALMAP_ON
					fixed3 tSpace0 : TEXCOORD1;
					fixed3 tSpace1 : TEXCOORD2;
					fixed3 tSpace2 : TEXCOORD3;
					float4 worldPos: TEXCOORD4;
				#else
					float3 worldNormal : NORMAL;
					float4 worldPos: TEXCOORD1;
				#endif
				#if RIMLIGHT_ON
					fixed3 rimColor : COLOR;
				#endif
				};
				
			#if NORMALMAP_ON
				v2f vert(appdata_tan v)
			#else
				struct appdata_t 
				{
					float4 vertex : POSITION;
					float3 normal : NORMAL;
					float2 texcoord : TEXCOORD0;
				};
				v2f vert(appdata_t v)
			#endif
				{
					v2f o;
					o.pos = UnityObjectToClipPos(v.vertex);
					o.uv.xy = TRANSFORM_TEX(v.texcoord, _MainTex);
					float3 worldNormal = UnityObjectToWorldNormal(v.normal);
				#if NORMALMAP_ON
					// Accurate bump calculation: calculate tangent space matrix and pass it to fragment shader
					fixed3 worldTangent = UnityObjectToWorldDir(v.tangent.xyz);
					fixed3 worldBinormal = cross(worldNormal, worldTangent) * v.tangent.w;
					o.tSpace0 = fixed3(worldTangent.x, worldBinormal.x, worldNormal.x);
					o.tSpace1 = fixed3(worldTangent.y, worldBinormal.y, worldNormal.y);
					o.tSpace2 = fixed3(worldTangent.z, worldBinormal.z, worldNormal.z);
				#else
					o.worldNormal = normalize(worldNormal);
				#endif

				#if RIMLIGHT_ON
                    float3 viewDir = normalize(ObjSpaceViewDir(v.vertex));
                    float rim = 1.0 - saturate(dot(v.normal, viewDir));
					o.rimColor = _RimColor.rgb * pow(rim, _RimPower) * saturate(worldNormal.y);	// saturate(worldNormal.y) 是为了模拟边缘光从头顶往下照的效果
				#endif

					o.worldPos = mul(UNITY_MATRIX_M, v.vertex);
//					o.worldPos.w = 1;
					float3 e = normalize(mul(UNITY_MATRIX_MV, v.vertex));
//					float3 n = normalize(mul(UNITY_MATRIX_MV, float4(v.normal, 0.)));

//					float3 r = reflect(e, n);
//					float m = 2.82842712474619 * sqrt(r.z + 1.0);

					// MatCap坐标准备：将法线从世界空间转换到观察空间
//					float2 vn = r.xy / m + 0.5;
					o.worldPos.xyz = e;
					return o;
				}
				
				float GetShadowBias(float3 lightDir, float3 normal, float maxBias, float baseBias)
				{
					float cos_val = saturate(dot(lightDir, normal));
					float sin_val = sqrt(1 - cos_val * cos_val); // sin(acos(L·N))
					float tan_val = sin_val / cos_val;    // tan(acos(L·N))
					float bias = baseBias + clamp(tan_val, 0, maxBias) ;
					return bias;
				}

				fixed GetShadowFactor(fixed shadow, float objDepth, float bias, float2 depthUV)
				{
					float4 depthRGBA = tex2D(_LightDepthTex, depthUV);
					float sceneDepth = DecodeFloatRGBA(depthRGBA);
				#if SHADER_API_D3D9 || SHADER_API_GLES || SHADER_API_GLES3 || SHADER_API_GLCORE
					shadow = objDepth - bias > sceneDepth ? 0.6 : 1.0;
				#else	// D3D11 Metal
					shadow = objDepth + bias < sceneDepth ? 0.6 : 1.0;
				#endif
					return shadow;
				}

				float4 frag (v2f i) : COLOR
				{
					fixed4 texColor = tex2D(_MainTex, i.uv);
					fixed3 channel = tex2D(_AlphaTex, i.uv).rgb;
					texColor = texColor * _MainColor * 2.0;
					texColor.a = channel.r;
					
					float3 worldNormal;
				#if NORMALMAP_ON
					//Rotate normals from tangent space to world space
					float3 normal = UnpackNormal(tex2D(_NormalMap, i.uv));
					worldNormal.x = dot(i.tSpace0.xyz, normal);
					worldNormal.y = dot(i.tSpace1.xyz, normal);
					worldNormal.z = dot(i.tSpace2.xyz, normal);
				#else
					worldNormal = i.worldNormal;
				#endif

					float3 e = i.worldPos.xyz;
					float3 n = mul((float3x3)UNITY_MATRIX_V, worldNormal);

					float3 r = reflect(e, n);
//					float m = 2. * sqrt(pow(r.x, 2.) + pow(r.y, 2.) + pow(r.z + 1., 2.));
					float m = 2.82842712474619 * sqrt(r.z + 1.0);
					half2 vn = r.xy / m + 0.5;

					// MatCap坐标准备：将法线从世界空间转换到观察空间
//					float2 vn = i.worldPos.xy;

					// 从提供的MatCap纹理中，提取出对应光照信息
					fixed3 matCap1 = tex2D(_MatCap1, vn).rgb * channel.r;
				#if MATCAP2_ON
					fixed3 matCap2 = tex2D(_MatCap2, vn).rgb;
					fixed3 blendColor = matCap1 + matCap2 * (1.0 - channel.r);
				#else
					fixed3 blendColor = matCap1;
				#endif

					// 最终颜色
					fixed4 finalColor = lerp(texColor, float4(texColor.rgb * blendColor * 2.0, 1.0), channel.b);
				#if RIMLIGHT_ON
					finalColor.rgb += i.rimColor;
				#endif

				#if FLOW_ON
					float2 flowUV = i.uv * _FlowTex_ST.xy; // 计算流光uv
					flowUV.x = flowUV.x + _Time.x * _FlowSpeedU;
					flowUV.y = flowUV.y + _Time.x * _FlowSpeedV;
					fixed3 flowColor = tex2D(_FlowTex, flowUV).rgb;
					finalColor.rgb = finalColor.rgb + flowColor * channel.g * _FlowColor; // 取流光亮度,g通道控制流光
				#endif

				#if SHADOWMAP_ON
					// convert to light camera space
					float4 lightClipPos = mul(_LightProjection , i.worldPos);
					lightClipPos.xyz = lightClipPos.xyz / lightClipPos.w;
					float objDepth = lightClipPos.z;
				#if SHADER_API_GLES || SHADER_API_GLES3 || SHADER_API_GLCORE
					objDepth = objDepth * 0.5 + 0.5;
				#endif
					float3 pos = lightClipPos * 0.5 + 0.5;

					// 20：-0.3, -0.3, 0.9
					// 25：-0.3, -0.4, 0.9
					// 30：-0.3, -0.5, 0.8
					float3 lightDir = float3(-0.3, -0.3, 0.9);
//					float bias = max(0.01 * (1.0 - dot(worldNormal, lightDir)), 0.001);
					float bias = GetShadowBias(lightDir, worldNormal, 0.03, 0.006);
					fixed shadow = 0;
					shadow = GetShadowFactor(shadow, objDepth, bias, pos.xy);	// No Filter

					// PCF
//					for (int x = -1; x <= 1; ++x)
//					{
//						for(int y = -1; y <= 1; ++y)
//						{
//							shadow += GetShadowFactor(shadow, objDepth, bias, pos.xy + float2(x, y) * 0.0009766);	// 0.0009766 -- 1/1024
//						}   
//					}
//					shadow /= 9.0;
					finalColor.rgb *= shadow;
					//return fixed4(sceneDepth,sceneDepth,sceneDepth,1);
				#endif
					finalColor.xyz = matCap1;
					return finalColor;
				}
			ENDCG
		}
	}
	FallBack "SGame/Texture"
	CustomEditor "MatCapToggle"
}