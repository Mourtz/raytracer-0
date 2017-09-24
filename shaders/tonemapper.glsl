#version 300 es

precision mediump float;

layout(location = 0) out highp vec4 FragColor;

uniform sampler2D u_bufferA;
uniform int u_frame;


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

  vec3 col = texelFetch( u_bufferA, ivec2(gl_FragCoord.xy), 0 ).rgb / float(u_frame);

#if 0

  col *= exposure;
  float sum = col.x + col.y + col.z;
  float x = col.x / sum;
  float y = col.y / sum;

  // compute Reinhard tonemapping scale factor
  float scale = (1.0 + col.y/(whitepoint*whitepoint)) / (1.0 + col.y);
  col.y *= scale;
  col.x = x * col.y / y;
  col.z = (1.0 - x - y) * (col.y / y);

#endif

  FragColor = vec4(pow(col, gamma), 1.0);
}
