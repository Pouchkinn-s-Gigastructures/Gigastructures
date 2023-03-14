Includes = {
	"constants.fxh"
	"standardfuncsgfx.fxh"
	"tiled_pointlights.fxh"
}

PixelShader =
{
	Samplers =
	{
		DiffuseMap = 
		{
			Index = 0;
			MinFilter = "Linear"
			MagFilter = "Linear"
			MipFilter = "Linear"
			AddressU = "Wrap"
			AddressV = "Wrap"
		}
		
		SpecularMap = 
		{
			Index = 1
			MinFilter = "Linear"
			MagFilter = "Linear"
			MipFilter = "Linear"
			AddressU = "Wrap"
			AddressV = "Wrap"
		}
		
		NormalMap = 
		{
			Index = 2
			MinFilter = "Linear"
			MagFilter = "Linear"
			MipFilter = "Linear"
			AddressU = "Wrap"
			AddressV = "Wrap"
		}
		
		EnvironmentMap =
		{
			Index = 4
			MagFilter = "Linear"
			MinFilter = "Linear"
			MipFilter = "Linear"
			AddressU = "Clamp"
			AddressV = "Clamp"
			Type = "Cube"
		}
		LightIndexMap =
		{
			Index = 5
			MagFilter = "Point"
			MinFilter = "Point"
			MipFilter = "Point"
			AddressU = "Clamp"
			AddressV = "Clamp"
		}
		LightDataMap =
		{
			Index = 6
			MagFilter = "Point"
			MinFilter = "Point"
			MipFilter = "Point"
			AddressU = "Clamp"
			AddressV = "Clamp"
		}
	}
}

VertexStruct VS_INPUT
{
    float3 	vPosition				: POSITION;
	float3 	vNormal      			: TEXCOORD0;
	float4 	vTangent				: TEXCOORD1;
	float2 	vUV0					: TEXCOORD2;
@ifdef PDX_MESH_UV1
	float2 	vUV1					: TEXCOORD3;
@endif
	float3 	vInstanceOffset 		: TEXCOORD4;
	float4 	vInstanceRotationSize	: TEXCOORD5;
};

VertexStruct VS_OUTPUT
{
    float4 vPosition	: PDX_POSITION;
	float3 vNormal		: TEXCOORD0;
	float3 vTangent		: TEXCOORD1;
	float3 vBitangent	: TEXCOORD2;
	float2 vUV0			: TEXCOORD3;
	float2 vUV1			: TEXCOORD4;
	float4 vPos			: TEXCOORD5;
};

ConstantBuffer( Animation, 3, 50 )
{
	float	 TimeRot;
};

VertexShader =
{
	MainCode AsteroidVertexShader
		ConstantBuffers = { Common, Animation, TiledPointLight }
	[[
		VS_OUTPUT main(const VS_INPUT v )
		{
			VS_OUTPUT Out;
					
			float4 vPosition = float4( v.vPosition.xyz, 1.0f );
			
			float3 vRotationDir = v.vInstanceRotationSize.xyz;
			
			float randSin = sin( TimeRot );
			float randCos = cos( TimeRot );
			
			vRotationDir.xz = float2( 
			vRotationDir.x * randCos - vRotationDir.z * randSin, 
			vRotationDir.x * randSin + vRotationDir.z * randCos );		
			
			// Calculate rotation matrix from rotation direction
			float3 vUp 				= normalize( float3( 0.0f, 1.0f, 0.0f ) );
			float3 zaxis 			= normalize( vRotationDir ); //Dir
			float3 xaxis 			= normalize( cross( vUp, zaxis ) );
			float3 yaxis 			= normalize( cross( zaxis, xaxis ) );
			float3x3 RotationMatrix = Create3x3( xaxis, yaxis, zaxis );		
			vPosition.xyz 			= mul( RotationMatrix, vPosition.xyz ); //Do rotation	
			
			vPosition.xyz *= v.vInstanceRotationSize.w; //Scale
			vPosition.xyz += v.vInstanceOffset.xyz; //Position offset
			
			Out.vNormal = normalize( mul( RotationMatrix, v.vNormal ) );
			Out.vTangent = normalize( mul( RotationMatrix, v.vTangent.xyz ) );
			Out.vBitangent = normalize( cross( Out.vNormal, Out.vTangent ) * v.vTangent.w );
			
			Out.vPosition = vPosition;
			Out.vPos = Out.vPosition;
			Out.vPosition = mul( ViewProjectionMatrix, Out.vPosition );
			
			Out.vUV0 = v.vUV0;
#ifdef PDX_MESH_UV1
			Out.vUV1 = v.vUV1;
#else
			Out.vUV1 = v.vUV0;
#endif
			return Out;
		}
		
	]]
}

VertexShader =
{
	MainCode GigaSlowAsteroidVertexShader
		ConstantBuffers = { Common, Animation, TiledPointLight }
	[[
		VS_OUTPUT main(const VS_INPUT v )
		{
			VS_OUTPUT Out;
					
			float4 vPosition = float4( v.vPosition.xyz, 1.0f );
			
			float3 vRotationDir = v.vInstanceRotationSize.xyz;
			
			//float factor = 1.0/6.0;

			float randSin = 1.0; //sin( TimeRot * factor );
			float randCos = 0.0; //cos( TimeRot * factor );
			
			vRotationDir.xz = float2( 
			vRotationDir.x * randCos - vRotationDir.z * randSin, 
			vRotationDir.x * randSin + vRotationDir.z * randCos );		
			
			// Calculate rotation matrix from rotation direction
			float3 vUp 				= normalize( float3( 0.0f, 1.0f, 0.0f ) );
			float3 zaxis 			= normalize( vRotationDir ); //Dir
			float3 xaxis 			= normalize( cross( vUp, zaxis ) );
			float3 yaxis 			= normalize( cross( zaxis, xaxis ) );
			float3x3 RotationMatrix = Create3x3( xaxis, yaxis, zaxis );		
			vPosition.xyz 			= mul( RotationMatrix, vPosition.xyz ); //Do rotation	
			
			vPosition.xyz *= v.vInstanceRotationSize.w; //Scale
			vPosition.xyz += v.vInstanceOffset.xyz; //Position offset
			
			Out.vNormal = normalize( mul( RotationMatrix, v.vNormal ) );
			Out.vTangent = normalize( mul( RotationMatrix, v.vTangent.xyz ) );
			Out.vBitangent = normalize( cross( Out.vNormal, Out.vTangent ) * v.vTangent.w );
			
			Out.vPosition = vPosition;
			Out.vPos = Out.vPosition;
			Out.vPosition = mul( ViewProjectionMatrix, Out.vPosition );
			
			Out.vUV0 = v.vUV0;
#ifdef PDX_MESH_UV1
			Out.vUV1 = v.vUV1;
#else
			Out.vUV1 = v.vUV0;
#endif
			return Out;
		}
		
	]]
}

PixelShader =
{
	MainCode AsteroidPixelShader
		ConstantBuffers = { Common, TiledPointLight }
	[[
		float4 main( VS_OUTPUT In ) : PDX_COLOR
		{
			float4 vDiffuse = tex2D( DiffuseMap, In.vUV0 );
			float alpha = vDiffuse.a;
			
			float3 vPos = In.vPos.xyz / In.vPos.w;
		
			float3 vColor = vDiffuse.rgb;
			float3 vInNormal = normalize( In.vNormal );
			float4 vProperties = tex2D( SpecularMap, In.vUV0 );
			
			LightingProperties lightingProperties;
			float vEmissive = 0.0f;
			
			float4 vNormalMap = tex2D( NormalMap, In.vUV0 );
			float3 vNormalSample =  UnpackRRxGNormal(vNormalMap);
			
			lightingProperties._Glossiness = vProperties.a;
			
			#ifdef EMISSIVE
				vEmissive = vNormalMap.b;
			#endif
		
			lightingProperties._NonLinearGlossiness = GetNonLinearGlossiness(lightingProperties._Glossiness);

			float3x3 TBN = Create3x3( normalize( In.vTangent ), normalize( In.vBitangent ), vInNormal );
			float3 vNormal = normalize(mul( vNormalSample, TBN ));
		
			lightingProperties._WorldSpacePos = vPos;
			lightingProperties._ToCameraDir = normalize(vCamPos - vPos);
			lightingProperties._Normal = vNormal;

			float SpecRemapped = vProperties.g * vProperties.g * 0.4;
			float MetalnessRemapped = 1.0 - (1.0 - vProperties.b) * (1.0 - vProperties.b);
			lightingProperties._Diffuse = MetalnessToDiffuse(MetalnessRemapped, vColor);
			lightingProperties._SpecularColor = MetalnessToSpec(MetalnessRemapped, vColor, SpecRemapped);
			
			float3 diffuseLight = vec3(0.0);
			float3 specularLight = vec3(0.0);
			CalculateSystemPointLight(lightingProperties, 1.0f, diffuseLight, specularLight);
			CalculatePointLights(lightingProperties, LightDataMap, LightIndexMap, diffuseLight, specularLight);

			float3 vEyeDir = normalize( vPos - vCamPos.xyz );
			float3 reflection = reflect( vEyeDir, vNormal );
			float MipmapIndex = GetEnvmapMipLevel(lightingProperties._Glossiness); 

			float3 reflectiveColor = texCUBElod( EnvironmentMap, float4(reflection, MipmapIndex) ).rgb * CubemapIntensity;
			specularLight += reflectiveColor * FresnelGlossy(lightingProperties._SpecularColor, -vEyeDir, lightingProperties._Normal, lightingProperties._Glossiness);

			vColor = ComposeLight(lightingProperties, 1.0f, diffuseLight, specularLight);

			#ifdef EMISSIVE
				vColor = lerp( vColor, vDiffuse.rgb, vEmissive );
				alpha *= vEmissive;
			#endif
		
			return float4(vColor, alpha );
		}	
	]]
}

BlendState BlendState
{
	BlendEnable = no
	WriteMask = "RED|GREEN|BLUE|ALPHA"
}

Effect Asteroid
{
	VertexShader = "AsteroidVertexShader"
	PixelShader = "AsteroidPixelShader"
}

Effect AsteroidEmissive
{
	VertexShader = "AsteroidVertexShader"
	PixelShader = "AsteroidPixelShader"
	Defines = { "EMISSIVE" }
}

Effect GigaSlowAsteroid
{
	VertexShader = "GigaSlowAsteroidVertexShader"
	PixelShader = "AsteroidPixelShader"
}

Effect GigaSlowAsteroidEmissive
{
	VertexShader = "GigaSlowAsteroidVertexShader"
	PixelShader = "AsteroidPixelShader"
	Defines = { "EMISSIVE" }
}