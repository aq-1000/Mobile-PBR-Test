// Upgrade NOTE: replaced '_World2Object' with 'unity_WorldToObject'
// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

// MatCap Shader, (c) 2015 Jean Moreno

Shader "AQTest/MatCap"
{
	Properties
	{
		_Color ("Main Color", Color) = (0.5,0.5,0.5,1)
		_MatCap ("MatCap (RGB)", 2D) = "white" {}
	}
	
	Subshader
	{
		Tags { "RenderType"="Opaque" }
		
		Pass
		{
			Tags { "LightMode" = "Always" }
			
			CGPROGRAM
				#pragma vertex vert
				#pragma fragment frag
				#pragma fragmentoption ARB_precision_hint_fastest
				#include "UnityCG.cginc"
				
				struct v2f
				{
					float4 pos	: SV_POSITION;
					float2 cap	: TEXCOORD0;
				};
				
				v2f vert (appdata_base v)
				{
					v2f o;
					o.pos = UnityObjectToClipPos (v.vertex);
					
					float3 worldNorm = normalize(unity_WorldToObject[0].xyz * v.normal.x + unity_WorldToObject[1].xyz * v.normal.y + unity_WorldToObject[2].xyz * v.normal.z);
					worldNorm = mul((float3x3)UNITY_MATRIX_V, worldNorm);
					o.cap.xy = worldNorm.xy * 0.5 + 0.5;

					float3 e = normalize(mul(UNITY_MATRIX_MV, v.vertex));
					float3 n = normalize(mul(UNITY_MATRIX_MV, float4(v.normal, 0.)));

					float3 r = reflect(e, n);
//					float m = 2. * sqrt(pow(r.x, 2.) + pow(r.y, 2.) + pow(r.z + 1., 2.));
					float m = 2.82842712474619 * sqrt(r.z + 1.0);
					half2 capCoord = r.xy / m + 0.5;
					o.cap.xy = capCoord;
//					o.cap.xy = n * 0.5 + 0.5;
					return o;
				}
				
				uniform float4 _Color;
				uniform sampler2D _MatCap;
				
				float4 frag (v2f i) : COLOR
				{
					float4 mc = tex2D(_MatCap, i.cap);
					return _Color * mc * 2.0;
				}
			ENDCG
		}
	}
}