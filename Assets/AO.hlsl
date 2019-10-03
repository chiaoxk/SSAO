#ifndef _AMBIENT_OCCLUSION_INCLUDE
#define _AMBIENT_OCCLUSION_INCLUDE

//https://blog.csdn.net/gy373499700/article/details/79111091

sampler2D _MainTex;
float4 _MainTex_TexelSize;

sampler2D _SSAOTex;
sampler2D _CameraDepthTexture;
sampler2D _CameraDepthNormalsTexture;

sampler2D _NoiseTex;
float4x4 _InvViewProj;
float4x4 _CameraModelView;

float2 _Direction;
float _BilateralThreshold;
float4 _OcclusionColor;
half4 _Params1;
half4 _Params2;

#define _NoiseSize          _Params1.x
#define _SampleRadius       _Params1.y
#define _Intensity          _Params1.z
#define _Distance           _Params1.w
#define _Bias               _Params2.x
#define _LumContrib         _Params2.y
#define _DistanceCutoff     _Params2.z
#define _CutoffFalloff      _Params2.w



inline half compare(half3 n1, half3 n2)
{
	return pow((dot(n1, n2) + 1.0)*0.5, _BilateralThreshold);
}

inline half lerp(half from, half to, half value)
{
	return (1 - value)*from + value * to;
}

inline half invlerp(half from, half to, half value)
{
	return (value - from) / (to - from);
}


half SampleDepth(half2 uv)
{
	half depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv);
	return LinearEyeDepth(depth);
}

half3 GetWSPos(half2 uv, half depth)
{
	//compute worldpos from view space
#if defined(UNITY_REVERSED_Z)
	half4 pos = half4(uv.xy * 2.0 - 1.0, 1.0 - depth, 1.0);
#else
	half4 pos = half4(uv.xy * 2.0 - 1.0, depth, 1.0);
#endif
	half4 worldPos = mul(_InvViewProj, pos);
	return worldPos.xyz / worldPos.w;
}

half3 GetNormal(half2 uv)
{
	half4 normal = tex2D(_CameraDepthNormalsTexture,uv);
	return DecodeViewNormalStereo(normal);
}
half3 GetWSNormal(half2 uv)
{
	half3 vsNormal = GetNormal(uv);
	half3 wsNormal = mul((float3x3)_CameraModelView, vsNormal);
	return wsNormal;
}

///计算ao贡献//偏移uv 获取邻近的采样点
half CalculateAO(half2 coord, half2 uv, half3 pos, half3 normal)
{
	half2 t = coord + uv;

	//视图空间深度
	half depth = SampleDepth(t);

	half3 diff = GetWSPos(t, depth) - pos;

	half3 v = normalize(diff);

	half dis = length(diff)*_Distance;
	//基于法线方向
	return max(0.0, dot(normal, v) - _Bias) *(1 / (1.0 + dis))*_Intensity;


}


half ssao(half2 uv)
{

	half2 CROSS[4] = { half2(1.0,0.0),half2(-1.0,0.0),half2(0.0,1.0),half2(0.0,-1.0) };

	half depth = SampleDepth(uv);

	half eyeDepth = LinearEyeDepth(depth);

	half3 wsPos = GetWSPos(uv, depth);

	half3 wsNormal = GetWSNormal(uv);

#if defined(SAMPLE_NOISE)
	//half2 scale = _ScreenParams.xy / _NoiseSize;
	half2 uvrandom = normalize(tex2D(_NoiseTex, _ScreenParams.xy*uv / _NoiseSize).rg * 2.0 - 1.0);
#endif
	half radius = max(_SampleRadius / eyeDepth, 0.005);
	clip(_DistanceCutoff - eyeDepth);

	half ao = 0.0;


	for (int i = 0; i < 4; i++)
	{
		half2 coord1;

#if defined(SAMPLE_NOISE)
		coord1 = reflect(CROSS[i], uvrandom)*radius;
#else
		coord1 = CROSS[i] * radius;
#endif

#if !SAMPLE_VERY_LOW
		half2 coord2 = coord1 * 0.707;
		coord2 = half2(coord2.x - coord2.y, coord2.x + coord2.y);
#endif
		//#elif SAMPLES_HIGH          // 16
		ao += CalculateAO(uv, coord1 * 0.25, wsPos, wsNormal);
		ao += CalculateAO(uv, coord2 * 0.50, wsPos, wsNormal);
		ao += CalculateAO(uv, coord1 * 0.75, wsPos, wsNormal);
		ao += CalculateAO(uv, coord2, wsPos, wsNormal);

	}


	ao /= 16;
	ao = lerp(1.0 - ao, 1.0, saturate(invlerp(_DistanceCutoff - _CutoffFalloff, _DistanceCutoff, eyeDepth)));
	return ao;
}



//-----------------------SSAO-----------------------

struct appdata_ssao {

	float4 pos:SV_POSITION;
	float2 uv:TEXCOORD0;
#if UNITY_UV_STARTS_AT_TOP
	float2 uv2:TEXCOORD1;
#endif
};

appdata_ssao vert_ssao(appdata_img v)
{
	appdata_ssao o;
	o.pos = UnityObjectToClipPos(v.vertex);
	o.uv = v.texcoord;
#if UNITY_UV_STARTS_AT_TOP
	o.uv2 = v.texcoord;
	if (_MainTex_TexelSize.y < 0.0)//d3d 平台下开启multi sample anti-alasing 这个值为负
		o.uv2.y = 1.0 - o.uv2.y;
#endif
	return o;
}

half4 GetAOColor(half ao, half2 uv)
{
#if defined(LIGHTING_CONTRIBUTION)
	//Luminace for the current pixel,used to reduce the ao amount in bright areas
	//Could potentially be repalced by the lgihting pass in deferred...
	half3 color = tex2D(_MainTex, uv).rgb;
	half luminance = dot(color, half3(0.2126, 0.7152, 0.0722));
	half aofinal = lerp(ao, 1.0, luminance*_LumContrib);
	return half4(aofinal.xxx, 1.0);

#else
	return half4(ao.xxx, 1.0);
#endif

}


half4 frag_ssao(appdata_ssao i) :SV_Target
{
#if UNITY_UV_STARTS_AT_TOP
	return saturate(GetAOColor(ssao(i.uv), i.uv2) + _OcclusionColor);
#else
	return saturate(GetAOColor(ssao(i.uv),i.uv) + _OcclusionColor);
#endif
}

//--------------------------------------------------


//--------------------------Gaussian Blur-----------

struct appdata_blur {

	float4 pos:SV_POSITION;
	float2 uv:TEXCOORD0;
	float4 uv1:TEXCOORD1;
	float4 uv2:TEXCOORD2;
};

appdata_blur vert_gaussian(appdata_img v)
{

	appdata_blur o;
	o.pos = UnityObjectToClipPos(v.vertex);
	o.uv = MultiplyUV(UNITY_MATRIX_TEXTURE0, v.texcoord);//类似于模型视图矩阵，*scale + tilling
	/*
	返回将当前眼睛的比例和偏差应用到uv中的纹理坐标的结果。
	只有在UNITY_SINGLE_PASS_STEREO被定义时才会发生这种情况，否则纹理坐标将返回不变。
	*/
	o.uv = UnityStereoTransformScreenSpaceTex(o.uv);

	float2 d1 = 1.3846153846 * _Direction;
	float2 d2 = 3.2307692308 * _Direction;
	o.uv1 = float4(o.uv + d1, o.uv - d1);
	o.uv2 = float4(o.uv + d2, o.uv - d2);
	return o;
}

//float[5] weights = { 0.2270270270 , 0.3162162162,0.3162162162,0.0702702703,0.0702702703 };
half4 frag_gaussian(appdata_blur i) :SV_Target
{
	half3 c = tex2D(_MainTex,i.uv).rgb*0.2270270270;
	c += tex2D(_MainTex,i.uv1.xy).rgb*0.3162162162;
	c += tex2D(_MainTex, i.uv1.zw).rgb*0.3162162162;
	c += tex2D(_MainTex, i.uv2.xy).rgb*0.0702702703;
	c += tex2D(_MainTex, i.uv2.zw).rgb*0.0702702703;

	return half4(c, 1.0);
}
//---------------------------------------------------




//------------------------Hight Quality Bilateral Blur---------------------------


appdata_blur vert_hqbilateral(appdata_img v)
{
	appdata_blur o;
	o.pos = UnityObjectToClipPos(v.vertex);
	o.uv = MultiplyUV(UNITY_MATRIX_TEXTURE0, v.texcoord);
	float2 d1 = 1.3846153846 * _Direction;
	float2 d2 = 3.2307692308 * _Direction;
	o.uv1 = float4(o.uv + d1, o.uv - d1);
	o.uv2 = float4(o.uv + d2, o.uv - d2);
	return o;

}

half4 frag_hqbliteral(appdata_blur i) :SV_Target
{
	//解码法线信息
	half3 n0 = GetNormal(i.uv);

	half w0 = 0.2270270270;
	half w1 = compare(n0,GetNormal(i.uv1.zw))*0.3162162162;
	half w2 = compare(n0, GetNormal(i.uv1.xy)) * 0.3162162162;
	half w3 = compare(n0, GetNormal(i.uv2.zw)) * 0.0702702703;
	half w4 = compare(n0, GetNormal(i.uv2.xy)) * 0.0702702703;
	half accumWeight = w0 + w1 + w2 + w3 + w4;

	half3 accum = tex2D(_MainTex, i.uv).rgb*w0;
	accum += tex2D(_MainTex,i.uv1.zw).rgb * w1;
	accum += tex2D(_MainTex,i.uv1.xy).rgb * w2;
	accum += tex2D(_MainTex,i.uv2.zw).rgb * w3;
	accum += tex2D(_MainTex,i.uv2.xy).rgb * w4;

	return half4(accum / accumWeight,1.0);
}

//------------------------Hight Quality Bilateral Blur---------------------------

// -------------------------------- Composite------------------------------------

appdata_ssao vert_composite(appdata_img v)
{
	appdata_ssao o;
	o.pos = UnityObjectToClipPos(v.vertex);
	o.uv = UnityStereoTransformScreenSpaceTex(v.texcoord);

#if UNITY_UV_STARTS_AT_TOP
	o.uv2 = UnityStereoTransformScreenSpaceTex(v.texcoord);
	if (_MainTex_TexelSize.y < 0.0)
		o.uv.y = 1.0 - o.uv.y;
#endif

	return o;
}

half4 frag_composite(appdata_ssao i) : SV_Target
{
	#if UNITY_UV_STARTS_AT_TOP
	half4 color = tex2D(_MainTex, i.uv2).rgba;
	#else
	half4 color = tex2D(_MainTex, i.uv).rgba;
	#endif

	return half4(color.rgb * tex2D(_SSAOTex, i.uv).rgb, color.a);
}
// -------------------------------- Composite------------------------------------

#endif// _AMBIENT_OCCLUSION_INCLUDE