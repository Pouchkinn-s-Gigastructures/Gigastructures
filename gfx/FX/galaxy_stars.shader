Includes = {
	"terra_incognita.fxh"
	"giga_functions.fxh"
	#// "giga_debug.fxh"
	"giga_star_shader_consts.fxh"
}

PixelShader =
{
	Samplers = 
	{
		DiffuseTexture = 
		{
			Index = 0;
			MagFilter = "Linear";
			MinFilter = "Linear";
			AddressU = "Wrap";
			AddressV = "Wrap";
		}
		
		TerraIncognitaTexture = 
		{
			Index = 1;
			MagFilter = "Linear";
			MinFilter = "Linear";
			AddressU = "Clamp"
			AddressV = "Clamp"
		}
	}
}

VertexStruct VS_INPUT
{
    float2 vPosition  		: POSITION;
	float2 vUV				: TEXCOORD0;
	float3 vPos				: TEXCOORD1;
};

VertexStruct VS_OUTPUT
{
    float4 vPosition 		: PDX_POSITION;
    float2 vUV				: TEXCOORD0;
	float4 vPos				: TEXCOORD1;

	float vDrawRing         : TEXCOORD2;
    float vCameraDistance   : TEXCOORD4;
};

ConstantBuffer( Common, 0, 0 )
{
	float4x4 	ViewProjectionMatrix;
	float4		Right;
	float4		Up;
	float 		Scale;
};

VertexShader =
{
	MainCode VertexShader
		ConstantBuffers = { Common }
	[[
	    float getStarIconScaleForZoomLevel(float zoom) {
            float zoomRange = (GALAXY_ZOOM_MAXIMUM - GALAXY_ZOOM_MINIMUM);
            float zoomFraction = (zoom - GALAXY_ZOOM_MINIMUM) / zoomRange;

            return clamp(zoomFraction * GALAXY_STAR_ICON_MAX_SCALE * GALAXY_SPACE_SCALE_MULT + 1, 1, GALAXY_STAR_ICON_MAX_SCALE * GALAXY_SPACE_SCALE_MULT) * GALAXY_STAR_ICON_SCALE;
        }

		VS_OUTPUT main(const VS_INPUT In )
		{
			VS_OUTPUT Out;
            float4 vPos;

			if (Scale >= 1000) {
			    // do our stuff

			    //float localScale = Scale - 1000.0;


                // calculate camera distance

                float4x4 inverseMat = inverse(ViewProjectionMatrix);
                float4 cameraPos = mul(inverseMat, float4(0,0,-1,0));
                cameraPos /= cameraPos.w;

                float3 forward = cross(Up.xyz, Right.xyz);

                float times = 0;

                if (forward.y > 0.001) {
                    times = cameraPos.y / forward.y;
                }

                float3 intercept = float3( cameraPos.x + forward.x * times, 0, cameraPos.z + forward.z * times );

                float3 diff = cameraPos.xyz - intercept;

                float distance = sqrt(dot(diff,diff));

                // set up model

                float3 forwardFlat = normalize(float3(forward.x,0,forward.z));

                float localScale = distance * 0.05;

                vPos                = float4( In.vPos.xyz, 1.0 );
                // flat to the galaxy plane, but facing the camera
                float3 vOffset 		= In.vPosition.x * ( Right.xyz + In.vPosition.y * -forwardFlat.xyz ) * GIGA_GALAXY_SIZE;
                vPos.xyz 			+= float3( vOffset.x, vOffset.y, vOffset.z );


			    Out.vDrawRing = (Scale / getStarIconScaleForZoomLevel(distance)) - 1000;

			    Out.vCameraDistance = distance;
			} else {
			    // default billboard

                vPos                = float4( In.vPos.xyz, 1.0 );
                float3 vOffset 		= In.vPosition.x * ( Right.xyz + In.vPosition.y * Up.xyz ) * Scale * 1.5; //Billboard
                vPos.xyz 			+= float3( vOffset.x, vOffset.y, vOffset.z );

                Out.vDrawRing = 0.0;
            }

            Out.vPos			= vPos;
            Out.vPosition		= mul( ViewProjectionMatrix, vPos );
            Out.vUV				= In.vUV;

			return Out;
		}
		
	]]
}

PixelShader =
{
	MainCode PixelShader
	[[
	    static const float PI = 3.14159265359f;
	    static const float INNER_FIELD_FRACTION = 0.5;

		float4 main( VS_OUTPUT In ) : PDX_COLOR
		{
		    if (In.vDrawRing > 0.001) {

                float drawRadius = In.vDrawRing;
		        float2 centredUV = (In.vUV - 0.5) * 2.0;
		        float angle = atan2(centredUV.y, centredUV.x) + PI;
                float radiusSquared = dot(centredUV,centredUV);

                float radius = sqrt(radiusSquared) * GIGA_GALAXY_SIZE * 0.5;
                float circumference = PI * drawRadius * 2;
                float dashCount = ceil(circumference / 10.0);

                float vCamDistFactor = saturate( In.vCameraDistance / GALAXY_ZOOM_MAXIMUM );
                float sharpness = 12 - 6 * vCamDistFactor;
                float thickness = 0.1 + 0.65 * vCamDistFactor;

                float4 vColor = float4(0,0,0,1);

                float outerDist = radius - drawRadius;
                float innerDist = radius - drawRadius * INNER_FIELD_FRACTION;

                float outerBorder = smoothstep(1.0,0.0, (abs(outerDist)-thickness) * sharpness);
                float innerBorder = smoothstep(1.0,0.0, (abs(innerDist)-thickness) * sharpness);


                if (radius < drawRadius * INNER_FIELD_FRACTION) {
                    vColor = float4(0.1,0,0,0.2);
                } else if (radius < drawRadius) {
                    vColor = float4(0.1,0,0,0.05);
                }

                vColor = vColor * (1-innerBorder) + float4(0.3,0,0,1) * innerBorder;

                if ( mod( (angle * dashCount), (PI*2) ) > PI) {
                    vColor = vColor * (1-outerBorder) + float4(0.3,0,0,1) * outerBorder;
                }



                //vColor.rgb += float3(0.1,0,0) * innerBorder;


//                 if (radius < drawRadius && radius > drawRadius-2) {
//                     vColor.rgb += float3(0.1,0,0);
//                 }

                // apply (not quite full TI)
                float4 greyed = ApplyTerraIncognita( vColor, In.vPos.xz, 1.f, TerraIncognitaTexture );
                vColor = vColor * 0.1 + greyed * 0.9;

                return vColor;
		    } else {
                float4 vColor = tex2D( DiffuseTexture, In.vUV );
                vColor = ApplyTerraIncognita( vColor, In.vPos.xz, 1.f, TerraIncognitaTexture );
                return vColor;
			}
		}
		
	]]
}

DepthStencilState DepthStencilState
{
	DepthEnable = no
}

BlendState BlendState
{
	BlendEnable = yes
	SourceBlend = "SRC_ALPHA"
	DestBlend = "ONE"
	WriteMask = "RED|GREEN|BLUE"
}

RasterizerState RasterizerState
{
	FillMode = "FILL_SOLID"
	CullMode = "CULL_NONE"
	FrontCCW = no
}


Effect GalaxyStars
{
	VertexShader = "VertexShader";
	PixelShader = "PixelShader";
}