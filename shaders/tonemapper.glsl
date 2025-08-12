#version 300 es

precision mediump float;

layout(location = 0) out highp vec4 FragColor;

uniform sampler2D u_bufferA;
uniform float u_cont;

// gamma correction
const vec3 gamma = vec3(1./2.2);
// image exposure
const float exposure = 1.5;
// tonemapping whitepoint
const float whitepoint = exposure*(gamma.x * 2.0);

vec3 ACESFilm( vec3 x )
{
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;

    return (x*(a*x+b))/(x*(c*x+d)+e);
}

void main(){

  vec3 col = texelFetch( u_bufferA, ivec2(gl_FragCoord.xy), 0 ).rgb * u_cont;

  FragColor = vec4(pow(col, gamma), 1.0);
}
