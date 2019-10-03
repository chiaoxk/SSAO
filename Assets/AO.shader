
Shader "MyTest/AO"
{

	Properties
	{
	_MainTex("",2D) = "white"{}
	_SSAOTex("",2D) = "white"{}
	_NoiseTex("",2D) = "white"{}
	}
		HLSLINCLUDE
#pragma fragmentoption ARB_precision_hint_fastest
#pragma exclude_renderers flash
#pragma target 3.0
#include "UnityCG.cginc"

		ENDHLSL
		SubShader
	{
		ZWrite Off
		ZTest Always
		Cull Off

	Pass//(0) clear Pass
	{
		HLSLPROGRAM
		 #pragma vertex vert
		 #pragma fragment frag

				struct v_data
				{
					float4 pos : SV_POSITION;
					float2 uv : TEXCOORD0;
				};

				v_data vert(appdata_img v)
				{
					v_data o;
					o.pos = UnityObjectToClipPos(v.vertex);
					o.uv = v.texcoord;
					return o;
				}

				float4 frag(v_data i) : SV_Target
				{
					return (1.0).xxxx;
				}
					ENDHLSL
	}
	 Pass//(1）
	 {

		HLSLPROGRAM
		 #pragma vertex vert_ssao
		 #pragma fragment frag_ssao
		 #pragma multi_compile __  SAMPLES_LOW  SAMPLES_MEDIUM  SAMPLES_HIGH  SAMPLES_ULTRA

		#define SAMPLE_NOISE
		//#define LIGHTING_CONTRIBUTION
		//#include "AO.hlsl"
#include "TestAO.hlsl"
		ENDHLSL
	 }

					//----------------------Gaussian Blur------------------------

	Pass//(2)
	{
			HLSLPROGRAM

				#pragma vertex vert_gaussian
				#pragma fragment frag_gaussian

			//#include "AO.hlsl"
		#include "TestAO.hlsl"

		ENDHLSL

}
//-----------------------------------------------------------


//------------------------High Quality Bilateral Blur-----------------------------------
Pass //(3)
{
	HLSLPROGRAM

	#pragma vertex vert_hqbilateral
	#pragma fragment frag_hqbilateral
	//#include "AO.hlsl"
	#include "TestAO.hlsl"
	ENDHLSL
}
//------------------------High Quality Bilateral Blur-----------------------------------

Pass//(4)
{

 HLSLPROGRAM

#pragma vertex vert_composite
#pragma fragment frag_composite
 //#include "AO.hlsl"
  #include "TestAO.hlsl"

 ENDHLSL
 }

	}
		Fallback off
}