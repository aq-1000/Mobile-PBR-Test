Shader "AQTest/AQPBR-MatCap-Bunmped"
{
	Properties
	{
		_Tint("Tint", Color) = (1 ,1 ,1 ,1)
		_MainTex("Texture", 2D) = "white" {}
		_NormalMap("Normal Map(RGB)", 2D) = "bump" {}
		_MaskMap("Metallic,AO,-,Smoothness", 2D) = "white" {}
//		_Smoothness("Smoothness", Range(0, 1)) = 0.5

		_LUT("LUT", 2D) = "white" {}

		_MatCapD("MatCap Diffuse", 2D) = "white" {}
		_MatCapS("MatCap Specular", 2D) = "white" {}
//		_CubeMap("CubeMap", CUBE) = ""{}
	}

	SubShader
	{
		Tags { "RenderType" = "Opaque" }
		LOD 100

		Pass
		{
			Tags {
				"LightMode" = "ForwardBase"
			}
			CGPROGRAM


			#pragma target 3.0

			#pragma vertex vert
			#pragma fragment frag

			#include "UnityStandardBRDF.cginc" 

			struct v2f
			{
				float4 vertex : SV_POSITION;
				float2 uv : TEXCOORD0;
				fixed3 TtoW0 : TEXCOORD1;
				fixed3 TtoW1 : TEXCOORD2;
				fixed3 TtoW2 : TEXCOORD3;
				float3 worldPos : TEXCOORD4;
			};

			float4 _Tint;
			sampler2D _MainTex; float4 _MainTex_ST;
			sampler2D _NormalMap;
			sampler2D _MaskMap;
			sampler2D _LUT;
			sampler2D _MatCapD;
			sampler2D _MatCapS;
	//		samplerCUBE _CubeMap;

			v2f vert(appdata_tan v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.worldPos = mul(unity_ObjectToWorld, v.vertex);
				o.uv = TRANSFORM_TEX(v.texcoord, _MainTex);

				// Accurate bump calculation: calculate tangent space matrix and pass it to fragment shader
				float3 worldNormal = UnityObjectToWorldNormal(v.normal);
				fixed3 worldTangent = UnityObjectToWorldDir(v.tangent.xyz);
				fixed3 worldBinormal = cross(worldNormal, worldTangent) * v.tangent.w;
				o.TtoW0 = fixed3(worldTangent.x, worldBinormal.x, worldNormal.x);
				o.TtoW1 = fixed3(worldTangent.y, worldBinormal.y, worldNormal.y);
				o.TtoW2 = fixed3(worldTangent.z, worldBinormal.z, worldNormal.z);

//				float3 e = normalize(mul(UNITY_MATRIX_MV, v.vertex));
//				float3 n = normalize(mul(UNITY_MATRIX_MV, float4(v.normal, 0.)));
//				float3 r = reflect(e, n);
//				float m = 2.82842712474619 * sqrt(r.z + 1.0);
//				half2 capCoord = r.xy / m + 0.5;
				return o;
			}

			float3 fresnelSchlickRoughness(float cosTheta, float3 F0, float roughness)
			{
				return F0 + (max(float3(1 ,1, 1) * (1 - roughness), F0) - F0) * pow(1.0 - cosTheta, 5.0);
			}

			fixed4 frag(v2f i) : SV_Target
			{
				//Rotate normals from tangent space to world space
				float3 normal = UnpackNormal(tex2D(_NormalMap, i.uv));
				float3 worldNormal;
				worldNormal.x = dot(i.TtoW0.xyz, normal);
				worldNormal.y = dot(i.TtoW1.xyz, normal);
				worldNormal.z = dot(i.TtoW2.xyz, normal);

				worldNormal = normalize(worldNormal);
				float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);
				float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.worldPos.xyz);
				float3 lightColor = _LightColor0.rgb;
				float3 halfVector = normalize(lightDir + viewDir);  //半角向量

				float4 Mask = tex2D(_MaskMap, i.uv);
				float _Metallic = Mask.r;
				float _Occlusion = Mask.g;
				float _Emission = Mask.b;
				float _Smoothness = Mask.a;

				float perceptualRoughness = 1 - _Smoothness;

				float roughness = perceptualRoughness * perceptualRoughness;
				float squareRoughness = roughness * roughness;

				float nl = max(saturate(dot(worldNormal, lightDir)), 0.000001);//防止除0
				float nv = max(saturate(dot(worldNormal, viewDir)), 0.000001);
				float vh = max(saturate(dot(viewDir, halfVector)), 0.000001);
				float lh = max(saturate(dot(lightDir, halfVector)), 0.000001);
				float nh = max(saturate(dot(worldNormal, halfVector)), 0.000001);

				float3 Albedo = _Tint * tex2D(_MainTex, i.uv);

				float lerpSquareRoughness = pow(lerp(0.002, 1, roughness), 2);//Unity把roughness lerp到了0.002
				float D = lerpSquareRoughness / (pow((pow(nh, 2) * (lerpSquareRoughness - 1) + 1), 2) * UNITY_PI);

				float kInDirectLight = pow(squareRoughness + 1, 2) / 8;
				float kInIBL = pow(squareRoughness, 2) / 8;
				float GLeft = nl / lerp(nl, 1, kInDirectLight);
				float GRight = nv / lerp(nv, 1, kInDirectLight);
				float G = GLeft * GRight;

				float3 F0 = lerp(unity_ColorSpaceDielectricSpec.rgb, Albedo, _Metallic);
				float3 F = F0 + (1 - F0) * exp2((-5.55473 * vh - 6.98316) * vh);

				float3 SpecularResult = (D * G * F * 0.25) / (nv * nl);

				//漫反射系数
				float3 kd = (1 - F)*(1 - _Metallic);

				//直接光照部分结果
				float3 specColor = SpecularResult * lightColor * nl * UNITY_PI;
				float3 diffColor = kd * Albedo * lightColor * nl;
				float3 DirectLightResult = diffColor + specColor;

				half3 ambient_contrib = ShadeSH9(float4(worldNormal, 1));

				float3 ambient = 0.03 * Albedo;

				float3 iblDiffuse = max(half3(0, 0, 0), ambient.rgb + ambient_contrib);

				float mip_roughness = perceptualRoughness * (1.7 - 0.7 * perceptualRoughness);
				float3 reflectVec = reflect(-viewDir, worldNormal);

				half mip = mip_roughness * UNITY_SPECCUBE_LOD_STEPS;
				half4 rgbm = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflectVec, mip); //根据粗糙度生成lod级别对贴图进行三线性采样

				float3 iblSpecular = DecodeHDR(rgbm, unity_SpecCube0_HDR);

				float2 envBDRF = tex2D(_LUT, float2(lerp(0, 0.99, nv), lerp(0, 0.99, roughness))).rg; // LUT采样

				float3 Flast = fresnelSchlickRoughness(max(nv, 0.0), F0, roughness);
				float kdLast = (1 - Flast) * (1 - _Metallic);

				float3 iblDiffuseResult = iblDiffuse * kdLast * Albedo;
				float3 iblSpecularResult = iblSpecular * (Flast * envBDRF.r + envBDRF.g);
				float3 IndirectResult = iblDiffuseResult + iblSpecularResult;

//				float4 result = float4(DirectLightResult + IndirectResult, 1);
//				return result;







				// AQTest MapCat IndirectLight
				float3 e = normalize(i.worldPos.xyz - _WorldSpaceCameraPos.xyz);
				float3 n = worldNormal;
				float3 r = reflect(e, n);
				float3 vr = mul(UNITY_MATRIX_V, r); 
				float m = 2.82842712474619 * sqrt(vr.z + 1.0);
				half2 capCoord = vr.xy / m + 0.5;

				// 从提供的MatCap纹理中，提取出对应光照信息
				fixed3 matCapD = tex2D(_MatCapD, capCoord).rgb;
				fixed3 matCapS = tex2D(_MatCapS, capCoord).rgb;
//				matCapS = texCUBE(_CubeMap, reflectVec).rgb;
				
				fixed3 iblD = matCapD * kdLast * Albedo;
//				fixed3 iblS = matCapS * (Flast * envBDRF.r + envBDRF.g);
				fixed3 iblS = matCapS * Flast;

				fixed3 iResult = (iblD + iblS) * _Occlusion;
				float4 result = float4(DirectLightResult + iResult, 1);

				return result;
			}

			ENDCG
		}
	}
}
