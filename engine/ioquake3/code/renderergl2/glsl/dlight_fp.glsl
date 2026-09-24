uniform sampler2D u_DiffuseMap;
uniform sampler2D u_LightMap;
varying vec2 var_DiffuseTex;

uniform int       u_AlphaTest;

uniform vec4      u_Dk3FogColor;
uniform vec4      u_Dk3FogRange;

varying vec2      var_Tex1;
varying vec4      var_Color;


void main()
{
	vec4 color = texture2D(u_DiffuseMap, var_Tex1);

	float alpha = color.a * var_Color.a;
	if (u_AlphaTest == 1)
	{
		if (alpha == 0.0)
			discard;
	}
	else if (u_AlphaTest == 2)
	{
		if (alpha >= 0.5)
			discard;
	}
	else if (u_AlphaTest == 3)
	{
		if (alpha < 0.5)
			discard;
	}
	
	gl_FragColor.rgb = color.rgb * var_Color.rgb * texture2D(u_LightMap, var_DiffuseTex).rgb;
	gl_FragColor.a = alpha;

	if (u_Dk3FogColor.a > 0.0)
	{
		float fog = (u_Dk3FogRange.y - 1.0 / gl_FragCoord.w) / (u_Dk3FogRange.y - u_Dk3FogRange.x);
		gl_FragColor.rgb = mix(u_Dk3FogColor.rgb, gl_FragColor.rgb, clamp(fog, 0.0, 1.0));
	}
}
