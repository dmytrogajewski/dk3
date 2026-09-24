attribute vec3 attr_Position;
attribute vec4 attr_TexCoord0;
attribute vec3 attr_Normal;

uniform vec4   u_DlightInfo;

#if defined(USE_DEFORM_VERTEXES)
uniform int    u_DeformGen;
uniform float  u_DeformParams[5];
uniform float  u_Time;
#endif

uniform vec4   u_Color;
uniform mat4   u_ModelViewProjectionMatrix;

uniform vec4 u_DiffuseTexMatrix0;
uniform vec4 u_DiffuseTexMatrix1;
uniform vec4 u_DiffuseTexMatrix2;
uniform vec4 u_DiffuseTexMatrix3;
uniform vec4 u_DiffuseTexMatrix4;
uniform vec4 u_DiffuseTexMatrix5;
uniform vec4 u_DiffuseTexMatrix6;
uniform vec4 u_DiffuseTexMatrix7;

varying vec2 var_DiffuseTex;
varying vec2   var_Tex1;
varying vec4   var_Color;

#if defined(USE_DEFORM_VERTEXES)
vec3 DeformPosition(const vec3 pos, const vec3 normal, const vec2 st)
{
	if (u_DeformGen == 0)
	{
		return pos;
	}

	float base =      u_DeformParams[0];
	float amplitude = u_DeformParams[1];
	float phase =     u_DeformParams[2];
	float frequency = u_DeformParams[3];
	float spread =    u_DeformParams[4];

	if (u_DeformGen == DGEN_BULGE)
	{
		phase *= st.x;
	}
	else // if (u_DeformGen <= DGEN_WAVE_INVERSE_SAWTOOTH)
	{
		phase += dot(pos.xyz, vec3(spread));
	}

	float value = phase + (u_Time * frequency);
	float func;

	if (u_DeformGen == DGEN_WAVE_SIN)
	{
		func = sin(value * 2.0 * M_PI);
	}
	else if (u_DeformGen == DGEN_WAVE_SQUARE)
	{
		func = sign(0.5 - fract(value));
	}
	else if (u_DeformGen == DGEN_WAVE_TRIANGLE)
	{
		func = abs(fract(value + 0.75) - 0.5) * 4.0 - 1.0;
	}
	else if (u_DeformGen == DGEN_WAVE_SAWTOOTH)
	{
		func = fract(value);
	}
	else if (u_DeformGen == DGEN_WAVE_INVERSE_SAWTOOTH)
	{
		func = (1.0 - fract(value));
	}
	else // if (u_DeformGen == DGEN_BULGE)
	{
		func = sin(value);
	}

	return pos + normal * (base + func * amplitude);
}
#endif

vec2 ModTexCoords(vec2 st, vec3 position, vec4 texMatrix[8])
{
	vec2 st2 = st;
	vec2 offsetPos = vec2(position.x + position.z, position.y);

	st2 = vec2(st2.x * texMatrix[0].x + st2.y * texMatrix[0].y + texMatrix[0].z,
	           st2.x * texMatrix[1].x + st2.y * texMatrix[1].y + texMatrix[1].z);
	st2 += texMatrix[0].w * sin(offsetPos * (2.0 * M_PI / 1024.0) + vec2(texMatrix[1].w * 2.0 * M_PI));

	st2 = vec2(st2.x * texMatrix[2].x + st2.y * texMatrix[2].y + texMatrix[2].z,
	           st2.x * texMatrix[3].x + st2.y * texMatrix[3].y + texMatrix[3].z);
	st2 += texMatrix[2].w * sin(offsetPos * (2.0 * M_PI / 1024.0) + vec2(texMatrix[3].w * 2.0 * M_PI));

	st2 = vec2(st2.x * texMatrix[4].x + st2.y * texMatrix[4].y + texMatrix[4].z,
	           st2.x * texMatrix[5].x + st2.y * texMatrix[5].y + texMatrix[5].z);
	st2 += texMatrix[4].w * sin(offsetPos * (2.0 * M_PI / 1024.0) + vec2(texMatrix[5].w * 2.0 * M_PI));

	st2 = vec2(st2.x * texMatrix[6].x + st2.y * texMatrix[6].y + texMatrix[6].z,
	           st2.x * texMatrix[7].x + st2.y * texMatrix[7].y + texMatrix[7].z);
	st2 += texMatrix[6].w * sin(offsetPos * (2.0 * M_PI / 1024.0) + vec2(texMatrix[7].w * 2.0 * M_PI));

	return st2;
}

void main()
{
	vec3 position = attr_Position;
	vec3 normal = attr_Normal;

#if defined(USE_DEFORM_VERTEXES)
	position = DeformPosition(position, normal, attr_TexCoord0.st);
#endif

	gl_Position = u_ModelViewProjectionMatrix * vec4(position, 1.0);
		
	vec3 dist = u_DlightInfo.xyz - position;

	var_Tex1 = dist.xy * u_DlightInfo.a + vec2(0.5);
	float dlightmod = step(0.0, dot(dist, normal));
	dlightmod *= clamp(2.0 * (1.0 - abs(dist.z) * u_DlightInfo.a), 0.0, 1.0);
	
	var_Color = u_Color * dlightmod;
	vec4 texMatrix[8];
	texMatrix[0] = u_DiffuseTexMatrix0;
	texMatrix[1] = u_DiffuseTexMatrix1;
	texMatrix[2] = u_DiffuseTexMatrix2;
	texMatrix[3] = u_DiffuseTexMatrix3;
	texMatrix[4] = u_DiffuseTexMatrix4;
	texMatrix[5] = u_DiffuseTexMatrix5;
	texMatrix[6] = u_DiffuseTexMatrix6;
	texMatrix[7] = u_DiffuseTexMatrix7;
	var_DiffuseTex = ModTexCoords(attr_TexCoord0.st, position, texMatrix);
}
