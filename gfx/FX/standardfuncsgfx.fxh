Includes = {
	"giga_debug.fxh"
}

ConstantBuffer( Common, 0, 0 )
{
	float4x4	ViewProjectionMatrix;
	float3 		vCamPos;
	float3 		vCamRightDir;
	float3 		vCamLookAtDir;
	float3 		vCamUpDir;
	float3 		HdrRange_Time_ClipHeight;
	float4 		SystemLightPosRadius;
	float4 		SystemLightColorFalloff;
	float3		SystemBackLightDiffuse;
	float3		AmbientDiffuse;
	float		CubemapIntensity;
	float3		CamLightDiffuse[3];
	float3		RimLightDiffuse;
}

#float4x4 ViewProjectionMatrix		: register( c0 );
#float4x4 ViewMatrix				: register( c4 );
#float4x4 InvViewMatrix				: register( c8 );
#float4x4 InvViewProjMatrix			: register( c12 );
#float3 vLightDir					: register( c16 );
#float3 vCamPos						: register( c17 );
#float3 vCamRightDir				: register( c18 );
#float3 vCamLookAtDir				: register( c19 );
#float3 vCamUpDir					: register( c20 );
#float2 HdrRange_Time_ClipHeight	: register( c21 );

Code
[[
float3 ToGamma(float3 aLinear)
{
	return pow(abs(aLinear), vec3(1.0/2.2));
}

float3 ToLinear(float3 aGamma)
{
	return pow(abs(aGamma), vec3(2.2));
}

float4 ToLinear(float4 aGamma)
{
	return float4(ToLinear(aGamma.rgb), aGamma.a);
}

float Rand2DTo1D(float2 value, float2 dir)
{
    float2 smallValue = sin(value);
    float rand = dot(smallValue, dir);
    rand = frac(sin(rand) * 143745.3413f);
    return rand;
}

float Rand2DTo1D(float2 value)
{
	return Rand2DTo1D(value, float2(15.42f, 81.344f));
}

float2 Rand2DTo2D(float2 value)
{
    return float2(Rand2DTo1D(value, float2(13.251f, 76.129f)), Rand2DTo1D(value, float2(51.117f, 81.524f) ) );
}

float2 VoronoiNoise2D(float3 worldPos, float cellSize, float2 offsetPos)
{
    float2 value = worldPos.xy / cellSize ;
    value += offsetPos;
    float2 baseCell = floor(value);
    float minDistToCell = 200.0f;
    float2 closestCell;
	
    for (int x = -1; x <= 1; x++)
    {
        for (int y = -1; y <= 1; y++)
        {
            float2 cell = baseCell + float2(x, y);
			float2 cellPos = cell + Rand2DTo2D(cell);
            float distToCell = length(cellPos - value);
            if (distToCell < minDistToCell)
            {
                minDistToCell = distToCell;
                closestCell = cell;
            }
        }
    }
    return float2(minDistToCell, Rand2DTo1D(closestCell) );
}

float2 VoronoiNoise2D(float3 worldPos, float cellSize)
{
	return VoronoiNoise2D(worldPos, cellSize, float2(0.0f, 0.0f));
}

]]

PixelShader =
{
	Code
	[[
	// Photoshop filters, kinda...
	float3 Hue( float H )
	{
		float X = 1 - abs( ( mod( H, 2 ) ) - 1 );
		if ( H < 1.0f )			return float3( 1.0f,    X, 0.0f );
		else if ( H < 2.0f )	return float3(    X, 1.0f, 0.0f );
		else if ( H < 3.0f )	return float3( 0.0f, 1.0f,    X );
		else if ( H < 4.0f )	return float3( 0.0f,    X, 1.0f );
		else if ( H < 5.0f )	return float3(    X, 0.0f, 1.0f );
		else					return float3( 1.0f, 0.0f,    X );
	}

	float3 HSVtoRGB( in float3 aHSV )
	{
		float3 rgb;
		if ( aHSV.y != 0.0f )
		{
			float C = aHSV.y * aHSV.z;
			rgb = clamp( Hue( aHSV.x ) * C + ( aHSV.z - C ), 0.0f, 1.0f );
		}
		else
		{
			rgb = saturate( aHSV.zzz );
		}
		
		return rgb;
	}

	float3 RGBtoHSV( in float3 RGB )
	{
		float Cmax = max( RGB.r, max( RGB.g, RGB.b ) );
		float Cmin = min( RGB.r, min( RGB.g, RGB.b ) );
		float diff = Cmax - Cmin;

		float H = 0.0;
		float S = 0.0;
		if (diff != 0.0)
		{
			S = diff / Cmax;

			if (Cmax == RGB.r)
				H = (RGB.g - RGB.b) / diff + 6.0;
			else if (Cmax == RGB.g)
				H = (RGB.b - RGB.r) / diff + 2.0;
			else
				H = (RGB.r - RGB.g) / diff + 4.0;
		}

		return float3(H, S, Cmax);
	}


	float3 GetOverlay( float3 vColor, float3 vOverlay, float vOverlayPercent )
	{
		float3 res;
		res.r = vOverlay.r < .5 ? (2 * vOverlay.r * vColor.r) : (1 - 2 * (1 - vOverlay.r) * (1 - vColor.r));
		res.g = vOverlay.g < .5 ? (2 * vOverlay.g * vColor.g) : (1 - 2 * (1 - vOverlay.g) * (1 - vColor.g));
		res.b = vOverlay.b < .5 ? (2 * vOverlay.b * vColor.b) : (1 - 2 * (1 - vOverlay.b) * (1 - vColor.b));

		return lerp( vColor, res, vOverlayPercent );
	}

	float3 Levels( float3 vInColor, float vMinInput, float vMaxInput )
	{
		float3 vRet = saturate( vInColor - vMinInput );
		vRet /= vMaxInput - vMinInput;
		return saturate( vRet );
	}
	]]

	Code
		ConstantBuffers = { Common }
	[[

	static const float3 STANDARD_vDiffuseLight = float3( 1.4f, 1.2f, 1.0f );
	static const float  STANDARD_vIntensity    = 1.f;
	static const float STANDARD_HDR_RANGE 	= 0.9f;
	static const float MAX_SPECULAR_NORMALIZATION_FACTOR = 5.f;

	const static float SNOW_RIDGE_START_HEIGHT 	= 22.0f;
	const static float SNOW_NORMAL_START 	= 0.3f;
	const static float3 SNOW_COLOR = float3( 0.7f, 0.7f, 0.8f );

	float3 ApplySnow( float3 vColor, float3 vPos, inout float3 vNormal, inout float vSpecular, inout float vSpecularPower, float vIsSnow, in sampler2D SnowDiffuse )
	{
		float vNormalFade = saturate( 0.2f + saturate( ( vNormal.y - SNOW_NORMAL_START ) * 1.0f ) );

		float vNoise = tex2D( SnowDiffuse, ( vPos.xz + 0.5f ) / 30.0f  ).r;
		float vSnowTexture = tex2D( SnowDiffuse, ( vPos.xz + 0.5f ) / 10.0f  ).r;


		//Increase snow on ridges
		//vNoise -= saturate( vPos.y - SNOW_RIDGE_START_HEIGHT )*( saturate( (vNormal.y-0.9f) * 20.0f )*vIsSnow );
		//vNoise = saturate( vNoise );

		float vSnow = saturate( ( vIsSnow - vNoise ) * 2.0f ) * vNormalFade;
		float vFrost = saturate( vIsSnow - saturate( vNoise - 0.5f ) );

		vColor = lerp( vColor, SNOW_COLOR * ( 0.9f + 0.1f * vSnowTexture), saturate( vSnow + vFrost * 0.5f ) );

		vSpecular += vSnow * 0.2f;
		vSpecularPower *= 1.f - vFrost * 0.9f;
		return vColor;
	}

	float3 UnpackNormal( in sampler2D NormalTex, float2 uv )
	{
		float3 vNormalSample = normalize( tex2D( NormalTex, uv ).rgb - 0.5f );
		vNormalSample.g = -vNormalSample.g;
		return vNormalSample;
	}

	float3 GetCloudColor( float3 vPosition, float vTime, in sampler2D CloudTexture )
	{
		float2 vCloudUV = vPosition.xz * 0.002f;
		vCloudUV.x += vTime * 0.0011f;
		vCloudUV.y += vTime * 0.0031f;
		float3 vCloud = tex2D( CloudTexture, vCloudUV ).rgb;
		vCloudUV *= 1.1f;
		vCloudUV.x -= vTime * 0.0007f;
		return min( vCloud, tex2D( CloudTexture, vCloudUV ).rgb );
	}

	struct PointLight
	{
		float3 _Position;
		float _Radius;
		float3 _Color;
		float _Falloff;
	};

	PointLight GetPointLight(float4 PositionAndRadius, float4 ColorAndFalloff)
	{
		PointLight pointLight;
		pointLight._Position = PositionAndRadius.xyz;
		pointLight._Radius = PositionAndRadius.w;
		pointLight._Color = ColorAndFalloff.xyz;
		pointLight._Falloff = ColorAndFalloff.w;
		return pointLight;
	}

	struct LightingProperties
	{
		float3 _WorldSpacePos;
		float3 _ToCameraDir;
		float3 _Normal;
		float3 _Diffuse;

		float3 _SpecularColor;
		float _Glossiness;
		float _NonLinearGlossiness;
	};
	// Direct lighting
	float3 FresnelSchlick(float3 SpecularColor, float3 E, float3 H)
	{
		return SpecularColor + (vec3(1.0f) - SpecularColor) * pow(1.0 - saturate(dot(E, H)), 5.0);
	}

	// Indirect lighting
	float3 FresnelGlossy(float3 SpecularColor, float3 E, float3 N, float Smoothness)
	{
		return SpecularColor + (max(vec3(Smoothness), SpecularColor) - SpecularColor) * pow(1.0 - saturate(dot(E, N)), 5.0);
	}

	float3 MetalnessToDiffuse(float MetalnessIn, float3 DiffuseIn)
	{
		return lerp(DiffuseIn, vec3(0.0), MetalnessIn);
	}

	float3 MetalnessToSpec(float MetalnessIn, float3 DiffuseIn, float SpecIn)
	{
		return lerp(vec3(SpecIn), DiffuseIn, MetalnessIn);
	}

	//------------------------------
	// Phong -----------------------
	//------------------------------
	float3 CalculatePBRSpecularPower( float3 vPos, float3 vNormal, float3 vMaterialSpecularColor, float vSpecularPower, float3 vLightColor, float3 vLightDirIn )
	{
		float3 H = normalize( normalize( vCamPos - vPos ) + -vLightDirIn );
		float NdotH = saturate( dot( H, vNormal ) );
		float NdotL = saturate( dot( -vLightDirIn, vNormal ) );
		float3 vSpecularColor = vLightColor * saturate( pow( NdotH, vSpecularPower ) * SPECULAR_MULTIPLIER ) * vMaterialSpecularColor;
		vSpecularColor = FresnelSchlick( vMaterialSpecularColor * SPECULAR_MULTIPLIER, -vLightDirIn, H) * ((vSpecularPower + 2) / 8 ) * saturate( pow( NdotH, vSpecularPower ) ) * NdotL * vLightColor;
		return vSpecularColor;
	}

	float3 CalculateLight( float3 vNormal, float3 vLightDirection, float3 vLightIntensity )
	{
		float NdotL = dot( vNormal, -vLightDirection );
		return max(NdotL, 0.0) * vLightIntensity;
	}

	void PhongPointLight(PointLight aPointlight, LightingProperties aProperties, inout float3 aDiffuseLightOut, inout float3 aSpecularLightOut)
	{
		float3 lightdir = aProperties._WorldSpacePos - aPointlight._Position;
		float lightdist = length(lightdir);

		float vLightIntensity = saturate((aPointlight._Radius - lightdist) / aPointlight._Falloff);
		if (vLightIntensity > 0)
		{
			lightdir /= lightdist;
			aDiffuseLightOut += CalculateLight(aProperties._Normal, lightdir, aPointlight._Color * vLightIntensity);
			aSpecularLightOut += CalculatePBRSpecularPower(aProperties._WorldSpacePos, aProperties._Normal, aProperties._SpecularColor, aProperties._Glossiness, aPointlight._Color * vLightIntensity, lightdir);
		}
	}



	//------------------------------
	// Blinn-Phong -----------------
	//------------------------------
	float GetNonLinearGlossiness(float aGlossiness)
	{
		return exp2(11.0 * aGlossiness); //exp2(GlossScale * Gloss + GlossBias)
	}

	float GetEnvmapMipLevel(float aGlossiness)
	{
		return (1.0 - aGlossiness) * (8.0);
	}

	void ImprovedBlinnPhong(float3 aLightColor, float3 aToLightDir, LightingProperties aProperties, out float3 aDiffuseLightOut, out float3 aSpecularLightOut)
	{
		float3 H = normalize(aProperties._ToCameraDir + aToLightDir);
		float NdotL = saturate(dot(aProperties._Normal, aToLightDir));
		float NdotH = saturate(dot(aProperties._Normal, H));

		float normalization = (aProperties._NonLinearGlossiness + 2.0) / 8.0;

		//Hack for Stellaris to avoid super-bright specularity that causes bloom
		normalization = min( normalization, MAX_SPECULAR_NORMALIZATION_FACTOR );

		float3 specColor = normalization * pow(NdotH, aProperties._NonLinearGlossiness) * FresnelSchlick(aProperties._SpecularColor, aToLightDir, H);

		aDiffuseLightOut = aLightColor * NdotL;
		aSpecularLightOut = specColor * aLightColor * NdotL;

		//hack to fix unwanted specularity when glossiness == 0
		aSpecularLightOut *= saturate( smoothstep( aProperties._Glossiness, 0.f, 0.05f ) );
	}

	// TODO other, square, falloff?
	void ImprovedBlinnPhongPointLight(PointLight aPointlight, LightingProperties aProperties, inout float3 aDiffuseLightOut, inout float3 aSpecularLightOut)
	{
		float3 posToLight = aPointlight._Position - aProperties._WorldSpacePos;
		float lightDistance = length(posToLight);

		float lightIntensity = saturate((aPointlight._Radius - lightDistance) / aPointlight._Falloff);
		if (lightIntensity > 0)
		{
			float3 toLightDir = posToLight / lightDistance;
			float3 diffLight;
			float3 specLight;
			ImprovedBlinnPhong(aPointlight._Color * lightIntensity, toLightDir, aProperties, diffLight, specLight);
			aDiffuseLightOut += diffLight;
			aSpecularLightOut += specLight;
		}
	}



	//-------------------------------
	// Common lighting functions ----
	//-------------------------------
	void CalculatePointLight(PointLight aPointlight, LightingProperties aProperties, inout float3 aDiffuseLightOut, inout float3 aSpecularLightOut)
	{
	#ifdef PDX_LEGACY_BLINN_PHONG
		PhongPointLight(aPointlight, aProperties, aDiffuseLightOut, aSpecularLightOut);
	#else
		ImprovedBlinnPhongPointLight(aPointlight, aProperties, aDiffuseLightOut, aSpecularLightOut);
	#endif
	}

	void CalculateSystemPointLight(LightingProperties aProperties, float aShadowFactor, inout float3 aDiffuseLightOut, inout float3 aSpecularLightOut)
	{
		PointLight systemPointlight = GetPointLight(SystemLightPosRadius, SystemLightColorFalloff);
		float3 diffLight = vec3(0.0);
		float3 specLight = vec3(0.0);
		CalculatePointLight(systemPointlight, aProperties, diffLight, specLight);
		aDiffuseLightOut += diffLight * aShadowFactor;
		aSpecularLightOut += specLight * aShadowFactor;

		#ifdef IS_PLANET
			float3 vLightDir = normalize( systemPointlight._Position - aProperties._WorldSpacePos );
			diffLight = CalculateLight( aProperties._Normal, vLightDir, SystemBackLightDiffuse );
			aDiffuseLightOut += diffLight * aShadowFactor;
		#endif
	}

	float3 ComposeLight(LightingProperties aProperties, float aAmbientIntensity, float3 aDiffuseLight, float3 aSpecularLight)
	{
		float3 diffuse = ( ( (AmbientDiffuse * aAmbientIntensity) + aDiffuseLight) * aProperties._Diffuse) * HdrRange_Time_ClipHeight.x;
		float3 specular = aSpecularLight;
		return (diffuse + specular);
	}


	//-------------------------------
	// Debugging --------------------
	//-------------------------------
	//#define PDX_DEBUG_NORMAL
	//#define PDX_DEBUG_DIFFUSE
	//#define PDX_DEBUG_SPEC
	//#define PDX_DEBUG_GLOSSINESS
	//#define PDX_DEBUG_SHADOW
	//#define PDX_DEBUG_SUN_LIGHT
	//#define PDX_DEBUG_SUN_LIGHT_WITH_SHADOW
	//#define PDX_DEBUG_SYSTEM_LIGHT
	//#define PDX_DEBUG_AMBIENT

	void DebugReturn(inout float3 aReturn, LightingProperties aProperties, float aShadowTerm)
	{
	#ifdef PDX_DEBUG_NORMAL
		aReturn = saturate(aProperties._Normal);
	#endif

	#ifdef PDX_DEBUG_DIFFUSE
		aReturn = aProperties._Diffuse;
	#endif

	#ifdef PDX_DEBUG_SPEC
		aReturn = aProperties._SpecularColor;
	#endif

	#ifdef PDX_DEBUG_GLOSSINESS
		aReturn = vec3(aProperties._Glossiness);
	#endif

	#ifdef PDX_DEBUG_SHADOW
		aReturn = vec3(aShadowTerm * 0.5f);
	#endif

	#if defined(PDX_DEBUG_SUN_LIGHT) || defined (PDX_DEBUG_SUN_LIGHT_WITH_SHADOW)
		float3 diffuseLight = vec3(0.0);
		float3 specularLight = vec3(0.0);
		aProperties._Diffuse = vec3(0.5);

		#ifdef PDX_DEBUG_SUN_LIGHT_WITH_SHADOW
			CalculateSunLight(aProperties, aShadowTerm, diffuseLight, specularLight);
		#else
			CalculateSunLight(aProperties, 1.0, diffuseLight, specularLight);
		#endif

		aReturn = ComposeLight(aProperties, 1.0f, diffuseLight, specularLight);
	#endif

	#ifdef PDX_DEBUG_SYSTEM_LIGHT
		float3 diffuseLight = vec3(0.0);
		float3 specularLight = vec3(0.0);
		aProperties._Diffuse = vec3(1.0);
		CalculateSystemPointLight(aProperties, 1.0, diffuseLight, specularLight);
		aReturn = ComposeLight(aProperties, 1.0f, diffuseLight, specularLight);
	#endif

	#ifdef PDX_DEBUG_AMBIENT
		aReturn = AmbientDiffuse * aProperties._Diffuse;
	#endif

	#ifdef PDX_DEBUG_CAMERA_LIGHTS
		float3 diffuseLight = vec3(0.0);
		float3 specularLight = vec3(0.0);
		aProperties._Diffuse = vec3(1.0);
		CalculateCameraLights( aProperties, 1.0f, diffuseLight, specularLight );
		aReturn = ComposeLight( aProperties, 1.0f, diffuseLight, specularLight );
	#endif
	}

	]]

	Code
	[[
	float3 UnpackRRxGNormal(float4 NormalMapSample)
	{
		float x = NormalMapSample.g * 2.0 - 1.0;
		float y = NormalMapSample.a * 2.0 - 1.0;
		y = -y;
		float z = sqrt(saturate(1.0 - x * x - y * y));
		return float3(x, y, z);
	}
	]]
}

VertexShader =
{
	Code
	[[
	float4x4 CreateScaleMatrix(float3 scale)
	{
		return float4x4(
				scale.x, 0.0, 0.0f, 0.0f, 
				0.0f, scale.y, 0.0f, 0.0f, 
				0.0f, 0.0f, scale.z, 0.0f, 
				0.0f, 0.0f, 0.0f, 1.0f 
			);
	}
	]]
}
