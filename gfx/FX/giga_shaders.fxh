Includes = {
	"constants.fxh"
	"vertex_structs.fxh"
	"standardfuncsgfx.fxh"
	"shadow.fxh"
	"tiled_pointlights.fxh"
	"pdxmesh_samplers.fxh"
	"pdxmesh_ship.fxh"
}

#//Omni Shaders (EHOF/Kreitani)
MainCode PixelOmniMeshShip
		ConstantBuffers = { Common, ShipConstants, Shadow, TiledPointLight }
	[[
		float4 main( VS_OUTPUT_PDXMESHSTANDARD In ) : PDX_COLOR
		{
			const float  DMG_START		= 0.5f;
			const float  DMG_END		= 1.0f;
			const float  DMG_TILING		= 3.5f;
			const float  DMG_EDGE		= 0.0f;
			const float3 DMG_EDGE_COLOR	= float3( 10.0f, 6.6f, 0.1f );

			float4 vDiffuse = tex2D( DiffuseMap, In.vUV0 + vUVAnimationDir * vUVAnimationTime );

			#ifndef ANIMATE_NORMAL
				float4 vNormalMap = tex2D( NormalMap, In.vUV0 );
			#else
				float4 vNormalMap = tex2D( NormalMap, In.vUV0 + vUVAnimationDir * vUVAnimationTime );
			#endif

			#ifndef ANIMATE_SPECULAR
				float4 vProperties = tex2D( SpecularMap, In.vUV0 );
			#else
				float4 vProperties = tex2D( SpecularMap, In.vUV0 + vUVAnimationDir * vUVAnimationTime );
			#endif

			#ifdef COLORED_PATTERNS
				float vColorMask = tex2D( CustomTexture, In.vUV1 + vUVAnimationDir * vUVAnimationTime ).r;
				vDiffuse.rgb = lerp( vDiffuse.rgb, ( vDiffuse.rgb ) * normalize( PrimaryColor.rgb ) * 15, vColorMask );
			#endif

			float3 vPos = In.vPos.xyz / In.vPos.w;

			float3 vInNormal = normalize( In.vNormal );

			//Fade in damage texture
			float4 vDamageTex = tex2D( CustomTexture2, In.vUV0 * DMG_TILING );
			//float vDmgTemp = 1.0f;
			float vDmgTemp = ShipVars.b;
			//float vDmgTemp = saturate( mod( HdrRange_Time_ClipHeight.y * 0.25f, 1.25f ) );
			vDmgTemp = 1.0f - saturate( ( vDmgTemp - DMG_START ) / ( DMG_END - DMG_START ) );
			float vDamageValue = ( vDamageTex.a - vDmgTemp ) * 5.0f;
			if( vDamageTex.a <= 0.001f )
			{
				vDamageValue = 0.f;
			}
			float vDamageEdge = DMG_EDGE * saturate( 1.0f - abs( ( vDamageValue - 0.5 ) * 2 ) );
			vDamageValue = saturate( vDamageValue );
			vDiffuse.rgb = lerp( vDiffuse.rgb, vDamageTex.rgb, vDamageValue );
			vProperties = lerp( vProperties, vec4( 0.f ), vDamageValue );

			vDiffuse.rgb *= lerp( vec3( 1.f ), DMG_EDGE_COLOR, saturate( vDamageEdge ) );


			LightingProperties lightingProperties;
			lightingProperties._WorldSpacePos = vPos;
			lightingProperties._ToCameraDir = normalize(vCamPos - vPos);


			float vEmissive = vNormalMap.b;
			float3 vNormalSample =  UnpackRRxGNormal(vNormalMap);

			lightingProperties._Glossiness = vProperties.a;
			lightingProperties._NonLinearGlossiness = GetNonLinearGlossiness(lightingProperties._Glossiness);

			 #ifndef RECOLOR_EMISSIVE
                vDiffuse.rgb = lerp( vDiffuse.rgb, vec3( max( vDiffuse.r, max( vDiffuse.g, vDiffuse.b ) ) ) * PrimaryColor.rgb + ( PrimaryColor.rgb * 0.02 ), saturate( vEmissive ) );
            #else
                vDiffuse.rgb = lerp( vDiffuse.rgb, vec3( max( vDiffuse.r, max( vDiffuse.g, vDiffuse.b ) ) ) * PrimaryColor.rgb + ( PrimaryColor.rgb * 0.02 ), saturate( vEmissive * ShipVars.r ) );
            #endif

			vEmissive *= 1.f - vDamageValue;
			vEmissive += vDamageEdge;

			float3 vColor = vDiffuse.rgb;

			float vCubemapIntensity = CubemapIntensity;

			 // Gamma - Linear ping pong
			 // All content is already created for gamma space math, so we do this in gamma space
			vColor = ToGamma(vColor);
			vColor = ToLinear(lerp( vColor, vColor * ( vProperties.r * PrimaryColor.rgb ), vProperties.r ));

			float3x3 TBN = Create3x3( normalize( In.vTangent ), normalize( In.vBitangent ), vInNormal );
			float3 vNormal = normalize(mul( vNormalSample, TBN ));

			float fShadowTerm = 1.0f;
			lightingProperties._Normal = vNormal;
			float SpecRemapped = vProperties.g * vProperties.g * 0.4;
			float vMetalness = vProperties.b;

			float MetalnessRemapped = 1.0 - (1.0 - vMetalness) * (1.0 - vMetalness);

			lightingProperties._Diffuse = MetalnessToDiffuse(MetalnessRemapped, vColor);
			lightingProperties._SpecularColor = MetalnessToSpec(MetalnessRemapped, vColor, SpecRemapped);

			float3 diffuseLight = vec3(0.0);
			float3 specularLight = vec3(0.0);
			//CalculateSunLight(lightingProperties, fShadowTerm, diffuseLight, specularLight);
			CalculateSystemPointLight(lightingProperties, 1.0f, diffuseLight, specularLight);
			CalculateShipCameraLights(lightingProperties, 1.0f, diffuseLight, specularLight);
			CalculatePointLights(lightingProperties, LightDataMap, LightIndexMap, diffuseLight, specularLight);

			float3 vEyeDir = normalize( vPos - vCamPos.xyz );
			float3 reflection = reflect( vEyeDir, vNormal );
			float MipmapIndex = GetEnvmapMipLevel(lightingProperties._Glossiness);
			float3 reflectiveColor = texCUBElod( EnvironmentMap, float4(reflection, MipmapIndex) ).rgb * vCubemapIntensity;
			specularLight += reflectiveColor * FresnelGlossy(lightingProperties._SpecularColor, -vEyeDir, lightingProperties._Normal, lightingProperties._Glossiness);

			float vCamDistance = length( vPos - vCamPos );
			float vCamDistFadeValue = saturate( ( vCamDistance - CamLightFadeStartStop.x ) / ( CamLightFadeStartStop.y - CamLightFadeStartStop.x ) );
			float vAmbientIntensity = lerp( AmbientIntensityNearFar.x, AmbientIntensityNearFar.y, vCamDistFadeValue );

			vColor = ComposeLight(lightingProperties, vAmbientIntensity, diffuseLight, specularLight);
			vColor = lerp( vColor, vDiffuse.rgb, vEmissive );

			float alpha = vDiffuse.a;
			#ifndef GUI_ICON
			#ifndef NO_ALPHA_MULTIPLIED_EMISSIVE
				alpha *= vEmissive;
			#endif
			#endif

		#ifdef RIM_LIGHT
			float vRimStart = lerp( RimLightStartNearFar.x, RimLightStartNearFar.y, vCamDistFadeValue );
			float vRimStop = lerp( RimLightStopNearFar.x, RimLightStopNearFar.y, vCamDistFadeValue );

			float vRim = smoothstep( vRimStart, vRimStop, 1.0f - dot( vNormal, lightingProperties._ToCameraDir ) );

			vColor.rgb = lerp( vColor.rgb, RimLightDiffuse.rgb, saturate( vRim ) );
		#endif

			DebugReturn(vColor, lightingProperties, fShadowTerm);

			vColor = ApplyDissolve( PrimaryColor.rgb, ShipVars.b, vColor.rgb, vDiffuse.rgb, In.vUV0 );

			return float4(vColor, alpha  );
		}

	]]

	MainCode PixelOmniMeshWhiteHole
		ConstantBuffers = { Common, FourthKind, Shadow }
	[[
		float4 main( VS_OUTPUT_PDXMESHSTANDARD In ) : PDX_COLOR
		{
			float3 p = vCamRightDir * dot( In.vNormal, vCamRightDir );
			float3 vInvertedNormal = In.vNormal + ( p - In.vNormal ) * 2.f;
			float3 vEyeDir = normalize( In.vPos.xyz - vCamPos.xyz );
			float3 reflection = reflect( vEyeDir, vInvertedNormal );

			float3 Color = texCUBElod( EnvironmentMap, float4(reflection, 1) ).rgb - 1;

			float vDot = dot( -vEyeDir, In.vNormal );
			Color = saturate( Color * pow( 1.05f - vDot, 7.f ) +0.2 );
			Color += (StarAtmosphereColor.rgb + 1) * smoothstep( 0.15f, 0.11f, vDot ) * 0.25f * StarAtmosphereColor.a;

			return float4( Color * vBloomFactor, 1.0f );
		}
	]]

	MainCode PixelOmniMeshED
		ConstantBuffers = { Common, ShipConstants, Shadow }
	[[
		float4 main( VS_OUTPUT_PDXMESHSTANDARD In ) : PDX_COLOR
		{
			float3 RimColor = PrimaryColor.rbg;
			const float RimAlpha = 0.9f;
			const float vRimStart = 0.11f;
			const float vRimStop = 0.1f;

			// Normal
			float3 vInNormal = normalize( In.vNormal );
			float4 vNormalMap = tex2D( NormalMap, In.vUV0 );
			float3 vNormalSample = UnpackRRxGNormal(vNormalMap);

			float3x3 TBN = Create3x3( normalize( In.vTangent ), normalize( In.vBitangent ), vInNormal );
			float3 vNormal = normalize(mul( vNormalSample, TBN ));

			float vDot = dot( vNormal, -vCamLookAtDir );

			float4 vProperties = tex2D( SpecularMap, In.vUV0 );
			float vRim = smoothstep( vRimStart, vRimStop, abs( vDot ) );
			float4 vColor = vRim * float4( PrimaryColor.rbg, RimAlpha );

			vColor.rgb = vColor.rgb * 0.5f;
			vColor.rgb += PrimaryColor.rgb * vProperties.r;

			if( vDot > 0.f )
			{
				float vTime = ( vUVAnimationTime + HdrRange_Time_ClipHeight.y ) * 0.15f;
				vColor += tex2D( DiffuseMap, In.vUV0 + vUVAnimationDir * vTime );
				vColor += tex2D( DiffuseMap, ( In.vUV0 + float2( 0.20f, -0.13f ) * vTime * 0.27f ) );
			}

			float3 vEyeDir = normalize( In.vPos.xyz - vCamPos.xyz );
			float3 reflection = reflect( vEyeDir, In.vNormal );
			//  float pulse = ( 0.9f + 0.1f * sin( 3.141f * length( texCUBElod( EnvironmentMap, float4(reflection, 0) ).rgb ) + HdrRange_Time_ClipHeight.y * 1.f - 1.f * In.vSphere.y * 0.125f ) );
			float pulse = ( 0.9f + 0.1f * sin( 3.141f * length( texCUBElod( EnvironmentMap, float4(reflection, 0) ).rgb ) + 0 ) );
			vColor += pow( pulse, 40.0f ) * 0.1f;

			vColor.rgb = ApplyDissolve( PrimaryColor.rgb, ShipVars.b, vColor.rgb, RimColor, In.vUV0 );
			vColor.rgb *= PrimaryColor.rgb;
			vColor.rgb *= vBloomFactor;
			return vColor;
		}
	]]

	MainCode PixelOmniMeshEDSphere
		ConstantBuffers = { Common, ShipConstants, Shadow }
	[[
		float4 main( VS_OUTPUT_PDXMESHSTANDARD In ) : PDX_COLOR
		{
			float3 RimColor = HSVtoRGB( float3( 0.2f, 1.1f, 0.3f ) );
			const float RimAlpha = 0.9f;
			const float vRimStart = 0.11f;
			const float vRimStop = 0.1f;

			// Normal
			float3 vInNormal = normalize( In.vNormal );
			float4 vNormalMap = tex2D( NormalMap, In.vUV0 );
			float3 vNormalSample = UnpackRRxGNormal(vNormalMap);

			float3x3 TBN = Create3x3( normalize( In.vTangent ), normalize( In.vBitangent ), vInNormal );
			float3 vNormal = normalize(mul( vNormalSample, TBN ));

			float vDot = dot( vNormal, -vCamLookAtDir );

			float4 vProperties = tex2D( SpecularMap, In.vUV0 );
			float vRim = smoothstep( vRimStart, vRimStop, abs( vDot ) );
			float4 vColor = vRim * float4( RimColor.rbg, RimAlpha );

			vColor.rgb = vColor.rgb * 0.5f;
			vColor.rgb += RimColor.rgb * vProperties.r;

			if( vDot > 0.f )
			{
				float vTime = ( vUVAnimationTime + HdrRange_Time_ClipHeight.y ) * 0.15f;
				vColor += tex2D( DiffuseMap, In.vUV0 + vUVAnimationDir * vTime );
				vColor += tex2D( DiffuseMap, ( In.vUV0 + float2( 0.20f, -0.13f ) * vTime * 0.27f ) );
			}

			float3 vEyeDir = normalize( In.vPos.xyz - vCamPos.xyz );
			float3 reflection = reflect( vEyeDir, In.vNormal );
			float pulse = ( 0.9f + 0.1f * sin( 3.141f * length( texCUBElod( EnvironmentMap, float4(reflection, 0) ).rgb ) + HdrRange_Time_ClipHeight.y * 1.f - 1.f * In.vSphere.y * 0.125f ) );
			// float pulse = ( 0.9f + 0.1f * sin( 3.141f * length( texCUBElod( EnvironmentMap, float4(reflection, 0) ).rgb ) + 0 ) );
			vColor += pow( pulse, 40.0f ) * 0.1f;

			vColor.rgb = ApplyDissolve( RimColor.rbg, ShipVars.b, vColor.rgb, RimColor, In.vUV0 );
			vColor.rgb *= RimColor.rgb;
			vColor.rgb *= vBloomFactor;
			return vColor;
		}
	]]

	MainCode PixelPdxMeshAdditiveRS
		ConstantBuffers = { Common, ShipConstants, Shadow }
	[[
		float4 main( VS_OUTPUT_PDXMESHSTANDARD In ) : PDX_COLOR
		{
			float2 vUV = In.vUV0;
			vUV += vUVAnimationDir * vUVAnimationTime;

			float4 vDiffuse = tex2D( DiffuseMap, vUV );

		#ifdef ANIMATE_UV
			#ifndef ANIMATE_UV_ALPHA
				vDiffuse.a = tex2D( DiffuseMap, In.vUV0 ).a;
			#endif
		#endif

		#ifdef ALPHA_TEST
			clip(vDiffuse.a - 1.0);
		#endif

			#ifdef ADD_COLOR
				vDiffuse.rgb *= PrimaryColor.rgb;
			#endif

			#ifdef ALPHA_OVERRIDE
				vDiffuse *= vAlphaOverrideMult;
			#endif

			vDiffuse.rgb *= vDiffuse.a;
			vDiffuse.a *= vBloomFactor;
			#ifdef GUI_ICON
				float vLen = length( vDiffuse.rgb );
				vDiffuse.rgb /= vLen;
				vDiffuse.a = saturate( vLen * 1.5f );
			#endif

			#ifdef BLACK_HOLE
				vDiffuse.rgb *= pow( 1.f - abs( dot( vCamLookAtDir, float3( 0.f, 1.f, 0.f ) ) ), 1.5f );
			#endif

			#ifdef DISSOLVE
			vDiffuse.rgb = ApplyDissolve( PrimaryColor.rgb, ShipVars.b, vDiffuse.rgb, vDiffuse.rgb, In.vUV0 );
			#endif

			return vDiffuse;
		}

	]]

#// rainbow blokkat
PixelShader = {
	MainCode PixelRainbowBlokkat
		ConstantBuffers = { PortraitCommon, TwelthKind, Shadow }
	[[
		float3 ApplyHue(float3 col, float hueAdjust)
		{
			const float3 k = float3(0.57735, 0.57735, 0.57735);
			half cosAngle = cos(hueAdjust);
			return col * cosAngle + cross(k, col) * sin(hueAdjust) + k * dot(k, col) * (1.0 - cosAngle);
		}

		float4 main( VS_OUTPUT_PDXMESHSTANDARD In ) : PDX_COLOR
		{
			float4 UVLod = float4( (In.vUV0), 0.0, PortraitMipLevel * 0.35 );

			float shift = (In.vPos.x * 0.0065) % 1;

			shift = shift * 0.2 + 0.8; // convert to gradient U coord (0.8 to 1.0)
			float4 UVGrad = float4( shift, 0.95, 0.0, 0.0 );

			float4 vDiffuse;
			float4 vGradient;
			if( CustomDiffuseTexture > 0.5f ) {
				vDiffuse = tex2Dlod( PortraitCharacter, UVLod );
				vGradient = tex2Dlod( PortraitCharacter, UVGrad );
			} else {
				vDiffuse = tex2Dlod( DiffuseMap, UVLod );
				vGradient = tex2Dlod( DiffuseMap, UVGrad );
			}

			vDiffuse.rgb = max(vGradient.rgb * vDiffuse.r, vDiffuse.ggg);

			//float shift = (In.vPos.x * 0.005) % 1;
			//vDiffuse.rgb = ApplyHue(vDiffuse.rgb, shift * 2 * 3.14159);

			return float4( ToGamma( vDiffuse.rgb ), vDiffuse.a );
		}

	]]
}

#// experimental marched portrait stuff
VertexShader = {
	MainCode GigaMarchedVertex
		ConstantBuffers = { PortraitCommon, TwelthKind }
	[[
		static const float twoPi = 6.2831853;

		VS_OUTPUT_PDXMESHSTANDARD main( const VS_INPUT_PDXMESHSTANDARD v )
		{
		  	VS_OUTPUT_PDXMESHSTANDARD Out;

			float3x3 rotFix = float3x3(1.0, 0.0, 0.0,  0.0, 0.0, -1.0,  0.0, 1.0, 0.0); // +90X

			float4 vPosition = float4( mul( v.vPosition.xyz, rotFix), 1.0 );
			//float4 vPosition = float4( v.vPosition.xyz, 1.0 );

			Out.vNormal = normalize(v.vNormal);
			Out.vTangent = normalize(v.vTangent.xyz);
			Out.vBitangent = normalize( cross( Out.vNormal, Out.vTangent ) * v.vTangent.w );

			float3 scale = float3(0.0,0.0,0.0);
			scale.x = sqrt(WorldMatrix._m00 * WorldMatrix._m00 + WorldMatrix._m01 * WorldMatrix._m01 + WorldMatrix._m02 * WorldMatrix._m02);
			scale.y = sqrt(WorldMatrix._m10 * WorldMatrix._m10 + WorldMatrix._m11 * WorldMatrix._m11 + WorldMatrix._m12 * WorldMatrix._m12);
			scale.z = sqrt(WorldMatrix._m20 * WorldMatrix._m20 + WorldMatrix._m21 * WorldMatrix._m21 + WorldMatrix._m22 * WorldMatrix._m22);

			// this will be our rotations
			Out.vSphere = float4( 0.0, 0.f, 0.0, 1.0 );

			// origin point as defined by asset
			float4 vOrigin = mul( WorldMatrix, float4(0.0,0.0,0.0,1.0));
			
			// x = right, y = up, z = forward
			float3 forward = normalize((mul( WorldMatrix, float4(0.0,0.0,1.0,0.0)).xyz - vOrigin.xyz) / scale);
			float3 up 	   = normalize((mul( WorldMatrix, float4(0.0,1.0,0.0,0.0)).xyz - vOrigin.xyz) / scale);
			float3 left    = normalize((mul( WorldMatrix, float4(1.0,0.0,0.0,0.0)).xyz - vOrigin.xyz) / scale);

			Out.vSphere.x = fmod(0.5 + asin(forward.y) / twoPi * 4, 1.0);
			Out.vSphere.y = fmod(0.5 - atan2(forward.z, forward.x) / twoPi, 1.0);

			Out.vPosition = vOrigin; // specified position for model
			Out.vPosition.xyz += vPosition.xyz * scale; // plus model coordinates facing camera
			//Out.vPosition.xyz += forward * 20; // plus debug offset to show motion

			Out.vPos = Out.vPosition;
			Out.vPosition = mul( ViewProjectionMatrix, Out.vPosition ); // apply view matrix

			Out.vUV0 = v.vUV0;
			Out.vUV1 = v.vUV0;

			return Out;
		}

	]]
}

PixelShader = {
	MainCode GigaMarchedPixel
		ConstantBuffers = { PortraitCommon, TwelthKind, Shadow }
	[[
		static const float twoPi = 6.2831853;

		static const float boundingSize = 1.5; //1.05 in the example

		float gmod(float x, float y)
		{
			return x - y * floor(x/y);
		}

		// max of vector
		float maxcomp(in float3 p ) { return max(p.x,max(p.y,p.z));}

		// box SDF
		float sdBox( float3 p, float3 b )
		{
			float3  di = abs(p) - b;
			float mc = maxcomp(di);
			return min(mc,length(max(di,0.0)));
		}

		// outer bounding box for tracing
		float2 iBox( in float3 ro, in float3 rd, in float3 rad ) 
		{
			float3 m = 1.0/rd;
			float3 n = m*ro;
			float3 k = abs(m)*rad;
			float3 t1 = -n - k;
			float3 t2 = -n + k;
			return float2( max( max( t1.x, t1.y ), t1.z ),
						min( min( t2.x, t2.y ), t2.z ) );
		}

		static const float3x3 ma = float3x3( 0.60, 0.00,  0.80,
							0.00, 1.00,  0.00,
							-0.80, 0.00,  0.60 );

		// function for the actual shapes
		float4 map( in float3 p, float time1, float time2 )
		{
			float3 bp = mul(p, ma);

			float d = sdBox(p,float3(1.0,1.0,1.0));
			float4 res = float4( d, 1.0, 0.0, 0.0 );

			float ani = time2; //smoothstep( -0.2, 0.2, -cos(0.5*iTime) );
			float off = 0.0; //1.5*sin( 0.01*iTime );
			
			float s = 1.0;
			for( int m=0; m<4; m++ )
			{
				p = lerp( p, mul(ma, (p+off)), float3(ani,ani,ani) );
			
				float3 a = abs(fmod( p*s, 2.0 ))-1.0;
				s *= 3.0;
				float3 r = abs(1.0 - 3.0*abs(a));
				float da = max(r.x,r.y);
				float db = max(r.y,r.z);
				float dc = max(r.z,r.x);
				float c = (min(da,min(db,dc))-1.0)/s;

				if( c>d )
				{
					d = c;
					res = float4( d, min(res.y,0.2*da*db*dc), (1.0+float(m))/4.0, 0.0 );
				}
			}

			return res;
		}

		// tracing
		float4 intersect( in float3 ro, in float3 rd, float time1, float time2)
		{
			float2 bb = iBox( ro, rd, float3(boundingSize,boundingSize,boundingSize) );
			if( bb.y<bb.x ) return float4(-1.0,-1.0,-1.0,-1.0);
			
			float tmin = bb.x;
			float tmax = bb.y;
			
			float t = tmin;
			float4 res = float4(-1.0,-1.0,-1.0,-1.0);
			for( int i=0; i<64; i++ )
			{
				float4 h = map(ro + rd*t, time1, time2);
				if( h.x<0.002 || t>tmax ) break;
				res = float4(t,h.y,h.z,h.w);
				t += h.x;
			}
			if( t>tmax ) res=float4(-1.0,-1.0,-1.0,-1.0);
			return res;
		}

		// calculate shadows
		float softshadow( in float3 ro, in float3 rd, float mint, float k, float time1, float time2 )
		{
			float2 bb = iBox( ro, rd, float3(boundingSize,boundingSize,boundingSize) );
			float tmax = bb.y;
			
			float res = 1.0;
			float t = mint;
			for( int i=0; i<64; i++ )
			{
				float h = map(ro + rd*t, time1, time2).x;
				res = min( res, k*h/t );
				if( res<0.001 ) break;
				t += clamp( h, 0.005, 0.1 );
				if( t>tmax ) break;
			}
			return clamp(res,0.0,1.0);
		}

		// get normal of point on shape
		float3 calcNormal(in float3 pos, float time1, float time2)
		{
			float3 eps = float3(.001,0.0,0.0);
			return normalize(float3(
			map(pos+eps.xyy, time1, time2).x - map(pos-eps.xyy, time1, time2).x,
			map(pos+eps.yxy, time1, time2).x - map(pos-eps.yxy, time1, time2).x,
			map(pos+eps.yyx, time1, time2).x - map(pos-eps.yyx, time1, time2).x ));
		}

		// render scene
		float4 render( float3 rayOrigin, float3 rayDirection, float time1, float time2 ) {
			//float3 col = lerp( float3(0.3,0.2,0.1)*0.5, float3(0.7, 0.9, 1.0), float3(0.5 + 0.5*rayDirection.y,0.5 + 0.5*rayDirection.y,0.5 + 0.5*rayDirection.y) );
			float4 col = float4(0,0,0,0);

			float4 tmat = intersect(rayOrigin, rayDirection, time1, time2);
			if (tmat.x > 0.0) {
				
				float3 position = rayOrigin + tmat.x * rayDirection;
				float3 normal = calcNormal(position, time1, time2);

				float3 materialColour = 0.5 + 0.5 * cos(float3(0,1,2) + 2.0 * tmat.z);

				float occlusion = tmat.y;

				// light vector
				float3 light = normalize(float3(1.0,0.9,0.3));

				// diffuse light
				float diffuse = dot(normal, light);

				// shadow term
				float shadow = 1.0;
				if (diffuse > 0.0) {
					shadow = softshadow(position, light, 0.01, 64.0, time1, time2);
				}

				// cap diffuse
				diffuse = max(diffuse, 0.0);

				// half vector for specular term
				float3 half = normalize(light - rayDirection);

				// specular term
				float specular = diffuse * shadow * pow( clamp(dot(half, normal), 0.0,1.0), 16.0) * (0.04 + 0.96 * pow( clamp(1.0 - dot(half, light), 0.0,1.0), 5.0));

				// ambient sky term
				float sky = 0.5 + 0.5 * normal.y;

				// fill light
				float backLight = max(0.4 + 0.6 * dot(normal, float3(-light.x, light.y, -light.z)), 0.0);

				// total up the lighting terms
				float3 lighting = float3(0,0,0);

				// + intensity * colour * other terms
				lighting += 1.0 * diffuse * float3(1.10, 0.85, 0.60) * shadow;
				lighting += 0.5 * sky * float3(0.1, 0.2, 0.4) * occlusion;
				lighting += 0.1 * backLight * float3(1.0,1.0,1.0) * (0.5 + 0.5 * occlusion);
				lighting += 0.25 * occlusion * float3(0.15,0.17,0.20);

				col.rgb = materialColour * lighting + specular * 128.0;
				col.a = 1.0;
			}

			// I don't know what this does but it appears to desaturate things a bit?
			col.rgb = 1.5 * col.rgb / (1.0+col.rgb);
			col.rgb = sqrt(col.rgb);

			return col;
		}

		float4 main( VS_OUTPUT_PDXMESHSTANDARD In ) : PDX_COLOR
		{
			float time1 = In.vSphere.x;
			float time2 = In.vSphere.y;

			float4 colour = float4(0,0,0,0);

			// camera
			//float3 rayOrigin = 1.1 * float3( 2.5*sin(time1*twoPi), 1.0+1.0*cos(time1 * 2*twoPi), 2.5*cos(time1 * 4*twoPi) );
			float3 rayOrigin = 13.0 * normalize(float3( 0.5, 0.125, 1.0 ));

			// prevent unroll
			#define ZERO (min(In.vSphere.z, 0))
			int AA = 2;

			//for (int aax = ZERO; aax<AA; aax++) {
				//for (int aay = ZERO; aay<AA; aay++) {
					
					//float2 offset = float2(float(aax), float(aay)) / float(AA) - 0.5;

					float2 pixel = In.vUV0 * 2.0 - 1.0;

					//colour.rg = 0.5 + pixel * 0.5;
					//colour.a = 1.0;

					// this is apparently a projection, but I don't know how or why
					float3 ww = normalize(float3(0,0,0) - rayOrigin);
					float3 uu = normalize(cross( float3(0.0,1.0,0.0), ww ));
					float3 vv = normalize(cross(ww,uu));
					float3 rayDirection = normalize( pixel.x*uu + pixel.y*vv + 5.5*ww );

					colour += render( rayOrigin, rayDirection, time1, time2 );
				//}
			//}

			//float2 edge = abs(In.vUV0 - 0.5);
			//if (max(edge.x,edge.y) > 0.495) {
			//	colour = float4(1,1,1,1);
			//}

			return colour;
		}

	]]
}

#// #########################################################################################################################################
#// BEES

PixelShader = {
	MainCode PixelMCPortrait
	ConstantBuffers = { PortraitCommon, TwelthKind, Shadow }
	[[
		float2 nearestSampleUV_AA (in float2 uv, float resolution, float sharpness) {
			float2 tileUv = uv * resolution;
			float2 dx = float2(ddx(tileUv.x), ddy(tileUv.x));
			float2 dy = float2(ddx(tileUv.y), ddy(tileUv.y));
			
			float2 dxdy = float2(max(abs(dx.x), abs(dx.y)), max(abs(dy.x), abs(dy.y)));
				
			float2 texelDelta = frac(tileUv) - float2(0.5, 0.5);
			float2 distFromEdge = float2(0.5, 0.5) - abs(texelDelta);
			float2 aa_factor = distFromEdge * sharpness / dxdy;
				
			return uv - texelDelta * clamp(aa_factor, float2(0.0, 0.0), float2(1.0, 1.0)) / resolution;
		}

		float4 main( VS_OUTPUT_PDXMESHSTANDARD In ) : PDX_COLOR
		{
			float2 uv = In.vUV0;

			uv = nearestSampleUV_AA(uv, 64.0, 1.5);

			float4 UVLod = float4( uv, 0.0, PortraitMipLevel * 0.35 );

			float4 vDiffuse;
			if( CustomDiffuseTexture > 0.5f ) {
				vDiffuse = tex2Dlod( PortraitCharacter, UVLod );
			} else {
				vDiffuse = tex2Dlod( DiffuseMap, UVLod );
			}

			if (vDiffuse.a < 0.5) {
				discard;
			}

			return float4( ToGamma( vDiffuse.rgb ), 1.0 );
		}

	]]
}