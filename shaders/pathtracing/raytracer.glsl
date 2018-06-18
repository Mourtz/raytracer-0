#version 300 es

/*
 *@highp - 16-bit, floating point range: -2^62 to 2^62, integer range: -2^16 to 2^16
 *@mediump - 10 bit, floating point range: -2^14 to 2^14, integer range: -2^10 to 2^10
 *@lowp - 8 bit, floating point range: -2 to 2, integer range: -2^8 to 2^8
 */

precision highp float;
precision mediump int;
precision mediump sampler3D;
precision mediump sampler2DArray;
precision mediump usampler2D;

layout(location = 0) out highp vec4 FragColor;

//------------------------------- UNIFORMS --------------------------------------

// canvas resolution
uniform vec2 u_resolution;
// curremt time
uniform float u_time;
// current frame
uniform uint u_frame;
// sdf meshes sample on grid
/*uniform sampler3D u_sdf0;*/
// backbuffer, tex0, tex1, tex2, tex3, random tex, keyboard LUT
uniform sampler2D u_bufferA, u_tex0, u_tex1, u_tex2, u_tex3, u_rnd_tex/*, u_keyboard*/;
// enviroment cubemap
uniform samplerCube u_cubemap;
// camera attributes
uniform vec3 u_camPos, u_camLookAt, u_camParams;

//------------------------------- CONSTANTS -------------------------------------

#constants

// epsilon & infinity
const float EPSILON = 0.0001;
const float INFINITY = 1e4;

// Index of Refraction
const lowp float ior_vacuum       =   1.0;
const lowp float ior_air          =   1.00029;
const lowp float ior_ice          =   1.31;
const lowp float ior_water        =   1.33;
const lowp float ior_coat         =   1.4;
const lowp float ior_glass        =   1.53;
const lowp float ior_sapphire     =   1.77;
const mediump float ior_diamond   =   2.417;

// PI & E consts
const float PI                =   3.1415926535897932384626433832795;
const float ONE_OVER_PI       =   1.5707963267948966192313216916398;
const float TWO_PI            =   6.283185307179586476925286766559;
const float FOUR_PI           =   12.566370614359172953850573533118;
const float RAD               =   0.01745329251994329576923690768489;
const float E                 =   2.71828182845904523536028747135266;

const lowp int NULL =  -1;

//-------------------------------

const struct Ray {
  vec3 o, d;       //origin, direction
};

//-------------------------------

const struct AABB{
  vec3 b1;	       //bottom-left vertex
  vec3 tr;	       //top-right vertex
};
//uniform u_sdf0_aabb{ AABB aabb; } sdf0_aabb;

//-------------------------------

const struct Hit{
  vec3 n, pos;    // hitpoint normal, position
  lowp int index; // index of mesh
  vec2 uv;        // texture uv
  vec4 texel;     // texture element
};
const Hit HIT_MISS = Hit(vec3(0.0), vec3(0.0), 0, vec2(-1.0), vec4(0.0));

//===============================================================================
//----------------------------------- TEXTURES ----------------------------------
//===============================================================================

//texture types
const lowp int TEXTURE0             =   0;
const lowp int TEXTURE1             =   1;
const lowp int TEXTURE2             =   2;
const lowp int TEXTURE3             =   3;
const lowp int VORONOI              =   4;
const lowp int GRADIENT_NOISE       =   5;
const lowp int VALUE_NOISE          =   6;
const lowp int CHECK                =   7;
const lowp int RIPPLE               =   8;
const lowp int METAL                =   9;


const struct Texture{
  vec3 c_mask, e_mask;  //color, emission/specular mask
  vec4 params;          //generator parameters
  int t;                //texture type
};
//----- EMPTY TEXTURE -----
const Texture NULL_TEX = Texture(vec3(1.0), vec3(1.0), vec4(0.0), NULL);

//----- TEXTURES 0-3 ------
const Texture TEX_0 = Texture(vec3(1.0), vec3(1.0), vec4(0.0, 0.0, 0.0, 1.0), TEXTURE0);
const Texture TEX_1 = Texture(vec3(1.0), vec3(1.0), vec4(0.0, 0.0, 0.0, 1.0), TEXTURE1);
const Texture TEX_2 = Texture(vec3(1.0), vec3(1.0), vec4(0.0, 0.0, 0.0, 1.0), TEXTURE2);
const Texture TEX_3 = Texture(vec3(1.0), vec3(1.0), vec4(0.0, 0.0, 0.0, 1.0), TEXTURE3);

//----- NOISE TEXTURES -----
const Texture TEX_VALUE_NOISE = Texture(vec3(1.0), vec3(1.0), vec4(16.0), VALUE_NOISE);
const Texture TEX_CHECK = Texture(vec3(1.0), vec3(0.0), vec4(5.0, 5.0, 2.0, 0.0), CHECK);
const Texture TEX_METAL = Texture(vec3(0.7,0.25,0.055), vec3(0.6, 0.2, 0.6), vec4(16.0,10.0,16.0,0.0), METAL);

//===============================================================================
//-------------------------------- MATERIALS ------------------------------------
//===============================================================================

// material types
const lowp int LIGHT          =   0;
const lowp int DIR_LIGHT      =   1;
const lowp int DIFF           =   2;
const lowp int SPEC           =   3;
const lowp int REFR_FRESNEL   =   4;
const lowp int REFR_SCHLICK   =   5;
const lowp int COAT           =   6;


const struct Material{
  vec3 c, e;       //color, emission/glossiness
  float nt;        //index of refraction
  lowp int t;      //type
  Texture tex;     //assigned texture
  bvec4 opts;      //color texture, emission/glossiness texture, bump texture, backface culling on/off
};
//----- EMPTY MATERIAL -----
const Material NULL_MAT = Material(vec3(0.0), vec3(0.0), 0.0, -1, NULL_TEX, bvec4(false));

//----- GLASS MATERIALS -----
const Material MAT_REFR_CLEAR = Material(vec3(1.,0.5,0.), vec3(0.0), ior_glass, REFR_FRESNEL, NULL_TEX, bvec4(false));
const Material MAT_REFR_CLEAR_2 = Material(vec3(1.), vec3(0.0),ior_glass, REFR_SCHLICK, NULL_TEX, bvec4(false));
const Material MAT_REFR_SAPPHIRE = Material(vec3(1.), vec3(0.0), ior_sapphire, REFR_FRESNEL, NULL_TEX, bvec4(false));
const Material MAT_REFR_WATER = Material(vec3(0.25,0.64,0.88), vec3(0.0), ior_water, REFR_FRESNEL, NULL_TEX, bvec4(false));

const Material MAT_REFR_TEST = Material(vec3(1.0), vec3(0.0), ior_glass, REFR_FRESNEL, TEX_1, bvec4(true,false,false,false));

//----- LIGHT MATERIALS -----
const Material MAT_LIGHT_4 = Material(vec3(1.0), vec3(4.0), 0.0, LIGHT, NULL_TEX, bvec4(false));
const Material MAT_LIGHT_CANDLE_4 = Material(vec3(1.0, 0.57647058823, 0.16078431372), vec3(4.0), 0.0, LIGHT, NULL_TEX, bvec4(false));
const Material MAT_LIGHT_HALOGEN_4 = Material(vec3(1.0, 0.94509803921, 0.87843137254), vec3(4.0), 0.0, LIGHT, NULL_TEX, bvec4(false));

//----- EMISSIVE TEXTURE MATERIALS -----
const Material MAT_LIGHT_4_TEX = Material(vec3(1.0), vec3(1.0), 0.0, LIGHT, TEX_1, bvec4(true,false,false,false));

//----- SKY MATERIALS -----
const Material MAT_CLEAR_SKY = Material(vec3(0.25098039215, 0.61176470588, 1.0), vec3(1.0), 0.0, DIR_LIGHT, NULL_TEX, bvec4(false));
const Material MAT_OVERCAST_SKY = Material(vec3(0.78823529411, 0.8862745098, 1.0), vec3(1.0), 0.0, DIR_LIGHT, NULL_TEX, bvec4(false));
const Material MAT_DIRECT_SUNLIGHT = Material(vec3(1.0), vec3(1.0), 0.0, DIR_LIGHT, NULL_TEX, bvec4(false));

//----- SPECULAR MATERIALS -----
const Material MAT_MIRROR = Material(vec3(1.0), vec3(0.0), 0.0, SPEC, NULL_TEX, bvec4(false));
const Material MAT_METAL  = Material(vec3(0.6), vec3(0.0), 0.0, SPEC, TEX_METAL, bvec4(false,true,false,false));

//----- DIFFUSE MATERIALS -----
const Material MAT_BLACK    =   Material(vec3(0.0, 0.0, 0.0), vec3(0.0), 0.0, DIFF, NULL_TEX, bvec4(false));
const Material MAT_WHITE    =   Material(vec3(1.0, 1.0, 1.0), vec3(0.0), 0.0, DIFF, NULL_TEX, bvec4(false));
const Material MAT_RED      =   Material(vec3(1.0, 0.0, 0.0), vec3(0.0), 0.0, DIFF, NULL_TEX, bvec4(false));
const Material MAT_GREEN    =   Material(vec3(0.0, 1.0, 0.0), vec3(0.0), 0.0, DIFF, NULL_TEX, bvec4(false));
const Material MAT_BLUE     =   Material(vec3(0.0, 0.0, 1.0), vec3(0.0), 0.0, DIFF, NULL_TEX, bvec4(false));

const Material MAT_CORNELL_WHITE    =   Material(vec3(1.0, 1.0, 1.0), vec3(0.0), 0.0, DIFF, NULL_TEX, bvec4(false));
const Material MAT_CORNELL_RED      =   Material(vec3(0.7, 0.12,0.05), vec3(0.0), 0.0, DIFF, NULL_TEX, bvec4(false));
const Material MAT_CORNELL_GREEN    =   Material(vec3(0.2, 0.4, 0.36), vec3(0.0), 0.0, DIFF, NULL_TEX, bvec4(false));

const Material MAT_YELLOW   =   Material(vec3(1.0, 1.0, 0.0), vec3(0.0), 0.0, DIFF, NULL_TEX, bvec4(false));
const Material MAT_PURPLE   =   Material(vec3(0.50196078431, 0.0, 0.50196078431), vec3(0.0), 0.0, DIFF, NULL_TEX, bvec4(false));

//----- CHECKERED MATERIALS -----
const Material MAT_CHECK_WHITE = Material(vec3(0.0), vec3(0.0), 0.0, DIFF, TEX_CHECK, bvec4(true,false,false,false));

//----- COAT MATERIALS -----
const Material MAT_COAT_NAVY   = Material(vec3(0.0, 0.0, 0.50196078431), vec3(1.0), ior_coat, COAT, NULL_TEX, bvec4(false));
const Material MAT_COAT_PURPLE = Material(vec3(0.50196078431, 0.0, 0.50196078431), vec3(0.0), ior_coat, COAT, NULL_TEX, bvec4(false));
const Material MAT_COAT_WAX    = Material(vec3(0.9333, 0.6666, 0.6), vec3(0.005), ior_coat, COAT, NULL_TEX, bvec4(false));

//----- TEST -----
const Material MAT_TEST        = Material(vec3(1.0), vec3(0.0), 0.0, DIFF, TEX_1, bvec4(true,false,false,false));

//===============================================================================
//---------------------------------- MESH ---------------------------------------
//===============================================================================

// mesh types
const lowp int SPHERE   =   0;
const lowp int PLANE    =   1;
const lowp int BOX      =   2;
const lowp int SDF      =   3;
const lowp int GRID_SDF =   4;//@ToDo
const lowp int TRIANGLE =   5;


const struct Mesh{
  Material mat;    //material
  lowp int t;      //type
  vec3 pos;        //position
  vec4 joker;      //multi-functional data
};
const Mesh empty_Mesh = Mesh(NULL_MAT, NULL, vec3(0.0), vec4(0.0));

//------------------------------ ACTIVE SCENE -----------------------------------

#scene

const struct LightPathNode{
  vec3 c, p, n;     //color, position, normal
};
const LightPathNode NULL_LightPathNode = LightPathNode(vec3(0.0), vec3(0.0), vec3(0.0));

// light path nodes
//LightPathNode lpNodes[light_index.length()*LIGHT_PATH_LENGTH];
//const bool h_lights = light_index.length() >= 0;

//=========================== RNG ===============================

float hash(float seed){return fract(sin(seed)*43758.5453123);}
vec2 hash2(vec2 seed){return fract(sin(seed)*vec2(43758.5453123,22578.1459123));}
vec3 hash3(vec3 seed){return fract(sin(seed)*vec3(43758.5453123,22578.1459123,19642.3490423));}

//===================== NOISE FUNCTIONS =========================

vec3 gradient_hash( vec3 p ){
	p = vec3( dot(p,vec3(127.1,311.7, 74.7)),
			  dot(p,vec3(269.5,183.3,246.1)),
			  dot(p,vec3(113.5,271.9,124.6)));

	return -1.0 + 2.0*fract(sin(p)*43758.5453123);
}

// https://www.shadertoy.com/view/Xsl3Dl by @iq
float gradient_noise( in vec3 p ){
    vec3 i = floor( p );
    vec3 f = fract( p );

	vec3 u = f*f*(3.0-2.0*f);

    return mix( mix( mix( dot( gradient_hash( i + vec3(0.0,0.0,0.0) ), f - vec3(0.0,0.0,0.0) ),
                          dot( gradient_hash( i + vec3(1.0,0.0,0.0) ), f - vec3(1.0,0.0,0.0) ), u.x),
                     mix( dot( gradient_hash( i + vec3(0.0,1.0,0.0) ), f - vec3(0.0,1.0,0.0) ),
                          dot( gradient_hash( i + vec3(1.0,1.0,0.0) ), f - vec3(1.0,1.0,0.0) ), u.x), u.y),
                mix( mix( dot( gradient_hash( i + vec3(0.0,0.0,1.0) ), f - vec3(0.0,0.0,1.0) ),
                          dot( gradient_hash( i + vec3(1.0,0.0,1.0) ), f - vec3(1.0,0.0,1.0) ), u.x),
                     mix( dot( gradient_hash( i + vec3(0.0,1.0,1.0) ), f - vec3(0.0,1.0,1.0) ),
                          dot( gradient_hash( i + vec3(1.0,1.0,1.0) ), f - vec3(1.0,1.0,1.0) ), u.x), u.y), u.z );
}

float value_hash(vec3 p){
    p  = fract( p*0.3183099+.1 );
	  p *= 17.0;
    return fract( p.x*p.y*p.z*(p.x+p.y+p.z) );
}

// https://www.shadertoy.com/view/4sfGzS by @iq
float value_noise( in vec3 x ){

  vec3 p = floor(x);
  vec3 f = fract(x);
  f = f*f*(3.0-2.0*f);

#if 1

  vec2 uv = (p.xy+vec2(37.0,17.0)*p.z) + f.xy;
  vec2 rg = textureLod( u_rnd_tex, (uv+0.5)/256.0, 0.0).yx;
  return mix( rg.x, rg.y, f.z );
#else

  return mix(mix(mix( value_hash(p+vec3(0,0,0)),
                      value_hash(p+vec3(1,0,0)),f.x),
                 mix( value_hash(p+vec3(0,1,0)),
                      value_hash(p+vec3(1,1,0)),f.x),f.y),
             mix(mix( value_hash(p+vec3(0,0,1)),
                      value_hash(p+vec3(1,0,1)),f.x),
                 mix( value_hash(p+vec3(0,1,1)),
                      value_hash(p+vec3(1,1,1)),f.x),f.y),f.z);

#endif
}

// https://www.shadertoy.com/view/ldl3Dl by @iq
vec3 voronoi( in vec3 x ){
    vec3 p = floor( x );
    vec3 f = fract( x );

	float id = 0.0;
    vec2 res = vec2( 100.0 );
    for( int k=-1; k<=1; ++k )
    for( int j=-1; j<=1; ++j )
    for( int i=-1; i<=1; ++i )
    {
        vec3 b = vec3( float(i), float(j), float(k) );

#if 1

        vec3 hx = p + b ;
        vec3 r = vec3( b ) - f + texture( u_rnd_tex, (hx.xy+vec2(3.0,1.0)*hx.z+0.5)/256.0, -100.0 ).xyz;
#else

        vec3 r = vec3( b ) - f + gradient_hash( p + b );
#endif

        float d = dot( r, r );

        if( d < res.x )
        {
          id = dot( p+b, vec3(1.0,57.0,113.0 ) );
          res = vec2( d, res.x );
        }
        else if( d < res.y )
        {
            res.y = d;
        }
    }

    return vec3( sqrt( res ), abs(id) );
}

lowp int DIFF_BOUNCES         = 0;
lowp int SPEC_BOUNCES         = 0;
lowp int TRANS_BOUNCES        = 0;
lowp int SCATTERING_EVENTS    = 0;

//-------------------------------------------------------------------------------

mat3 scaleMatrix(float scale){
    return mat3(scale,0.0,0.0,
                0.0,scale,0.0,
                0.0,0.0,scale);
}

mat3 scaleMatrix(vec3 scale){
    return mat3(scale.x,0.0,0.0,
                0.0,scale.y,0.0,
                0.0,0.0,scale.z);
}

mat3 rotationMatrix(vec3 axis, float angle){
    float s = sin(angle);
    float c = cos(angle);
    float oc = 1.0 - c;

    return mat3(oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,
                oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,
                oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c );
}

//-------------------------------------------------------------------------------

void cartesianToSpherical( in vec3 xyz, out float rho, out float phi, out float theta ) {
  rho = sqrt((xyz.x * xyz.x) + (xyz.y * xyz.y) + (xyz.z * xyz.z));
  phi = asin(xyz.y / rho);
  theta = atan( xyz.z, xyz.x );
}

vec3 sphericalToCartesian( in float rho, in float phi, in float theta ) {
  float sinTheta = sin(theta);
  return vec3( sinTheta*cos(phi), sinTheta*sin(phi), cos(theta) )*rho;
}

//-------------------------------------------------------------------------------

float schlick(Ray r, vec3 n, float nc, float nt){
  float R0 = pow((nc - nt) / (nc + nt), 2.);
  return R0 + (1. - R0) * pow(1. + dot(n, r.d), 5.);
}

float fresnel(Ray r, vec3 n, float nc, float nt, vec3 refr){
  float cosI = dot(r.d, n);
  float costT = dot(n, refr);

  float Rs = pow((nc * cosI - nt * costT) / (nc * cosI + nt * costT), 2.);
  float Rp = pow((nc * costT - nt * cosI) / (nc * costT + nt * cosI), 2.);
  return (Rs + Rp) * 0.5;
}

//=============================== SDF FUNCTIONS =================================

float sdBoxCheap( in vec3 p, in vec3 b){
    vec3 d = abs(p) - b;
    return max(max(d.x, d.y), d.z);
}

float sdBox( in vec3 p, in vec3 b ){
    vec3 d = abs(p) - b;
    return min(max(d.x,max(d.y,d.z)),0.0) + length(max(d,0.0));
}

float sdSphere( in vec3 p, in float s ){
    return length(p)-s;
}

float sdPlane( vec3 p, vec4 n ){
    return dot(p,n.xyz) + n.w;
}

float sdCone( in vec3 p, in vec3 c )
{
    vec2 q = vec2( length(p.xz), p.y );
    float d1 = -q.y-c.z;
    float d2 = max( dot(q,c.xy), q.y);
    return length(max(vec2(d1,d2),0.0)) + min(max(d1,d2), 0.);
}

float sdTriPrism( vec3 p, vec2 h ){
    vec3 q = abs(p);
    return max(q.z-h.y,max(q.x*0.866025+p.y*0.5,-p.y)-h.x*0.5);
}

float sdEllipsoid( in vec3 p, in vec3 r ){
    return (length( p/r ) - 1.0) * min(min(r.x,r.y),r.z);
}

float udRoundBox( in vec3 p, in vec3 b, in float r ){
    return length(max(abs(p)-b,0.0))-r;
}

float sdCapsule( vec3 p, vec3 a, vec3 b, float r ){
    vec3 pa = p - a, ba = b - a;
    float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
    return length( pa - ba*h ) - r;
}

float dot2( in vec3 v ) { return dot(v,v); }
float udTriangle( vec3 p, vec3 a, vec3 b, vec3 c ){
    vec3 ba = b - a; vec3 pa = p - a;
    vec3 cb = c - b; vec3 pb = p - b;
    vec3 ac = a - c; vec3 pc = p - c;
    vec3 nor = cross( ba, ac );

    return sqrt(
    (sign(dot(cross(ba,nor),pa)) +
     sign(dot(cross(cb,nor),pb)) +
     sign(dot(cross(ac,nor),pc))<2.0)
     ?
     min( min(
     dot2(ba*clamp(dot(ba,pa)/dot2(ba),0.0,1.0)-pa),
     dot2(cb*clamp(dot(cb,pb)/dot2(cb),0.0,1.0)-pb) ),
     dot2(ac*clamp(dot(ac,pc)/dot2(ac),0.0,1.0)-pc) )
     :
     dot(nor,pa)*dot(nor,pa)/dot2(nor) );
}

float udQuad( vec3 p, vec3 a, vec3 b, vec3 c, vec3 d ){
    vec3 ba = b - a; vec3 pa = p - a;
    vec3 cb = c - b; vec3 pb = p - b;
    vec3 dc = d - c; vec3 pc = p - c;
    vec3 ad = a - d; vec3 pd = p - d;
    vec3 nor = cross( ba, ad );

    return sqrt(
    (sign(dot(cross(ba,nor),pa)) +
     sign(dot(cross(cb,nor),pb)) +
     sign(dot(cross(dc,nor),pc)) +
     sign(dot(cross(ad,nor),pd))<3.0)
     ?
     min( min( min(
     dot2(ba*clamp(dot(ba,pa)/dot2(ba),0.0,1.0)-pa),
     dot2(cb*clamp(dot(cb,pb)/dot2(cb),0.0,1.0)-pb) ),
     dot2(dc*clamp(dot(dc,pc)/dot2(dc),0.0,1.0)-pc) ),
     dot2(ad*clamp(dot(ad,pd)/dot2(ad),0.0,1.0)-pd) )
     :
     dot(nor,pa)*dot(nor,pa)/dot2(nor) );
}

//-----------------------------------------------------
// SDF operations
//-----------------------------------------------------

float opS( float d1, float d2 ){
  return max(-d2,d1);
}

float opU( float d1, float d2 ){
  return min(d1,d2);
}

float opI( float d1, float d2 ){
  return max(d1,d2);
}

vec3 opRep( vec3 p, vec3 c ){
    return mod(p,c)-0.5*c;
}

vec3 opTwist( vec3 p ){
    float c = cos(20.0*p.y);
    float s = sin(20.0*p.y);
    mat2  m = mat2(c,-s,s,c);
    return vec3(m*p.xz,p.y);
}

vec3 opCheapBend( vec3 p ){
    float c = cos(20.0*p.y);
    float s = sin(20.0*p.y);
    mat2  m = mat2(c,-s,s,c);
    return vec3(m*p.xy,p.z);
}

float disp( vec3 p, const float phase, const float power){
	return pow( 0.5 + 0.5*cos( p.x + 1.5*phase )*
                          sin( p.y + 2.0*phase )*
                          sin( p.z + 1.0*phase ), power);
}

float Snowball( vec3 p, float s ){
  return sdSphere(p, s)-value_noise(p*8.0)*0.04;
}

float sdSeaBox( in vec3 p, in vec3 b, in float level ){
    return opS(sdBox(p, b), sdPlane(p, vec4(0.,-1.,0.,level)) - disp(10.*p, 2.5, 1.0)*0.07-disp(15.*p, 4.5, 1.0)*0.03);
}

float sea(vec3 p, float turbulence){
  return 0.0;//@ToDo
}

// by @iq
float siggraph_obj( vec3 p ){
	vec3 ax = vec3(-2.0,2.0,1.0)/3.0;
	vec3 ce = vec3(0.0,-0.2,-0.2);

	float d1 = dot(p,ax) - 0.1;
    float d2 = length(p) - 1.0;
	float d3 = length( p-ce - ax*dot(p-ce,ax)) - 1.0;

	return max( max( d1, d2 ), -d3 );
}

// by @iq
float MengerSponge( vec3 p, vec3 scale){
    float d = sdBox(p, scale);

    float s = 1.0;
    for( int m=0; m<4; ++m )
    {
        vec3 a = mod( p*s, 2.0 )-1.0;
        s *= 3.0;
        vec3 r = abs(1.0 - 3.0*abs(a));
        float da = max(r.x,r.y);
        float db = max(r.y,r.z);
        float dc = max(r.z,r.x);
        float c = (min(da,min(db,dc))-1.0)/s;

        d = max(c, d);
    }

    return d;
}

// by @iq
float Mandelbulb( vec3 p ){
    vec3 w = p;
    float m = dot(w,w);

    vec4 trap = vec4(abs(w),m);
	float dz = 1.0;


	for( int i=0; i<4; ++i )
  {
#if 1
        float m2 = m*m;
        float m4 = m2*m2;
		dz = 8.0*sqrt(m4*m2*m)*dz + 1.0;

        float x = w.x; float x2 = x*x; float x4 = x2*x2;
        float y = w.y; float y2 = y*y; float y4 = y2*y2;
        float z = w.z; float z2 = z*z; float z4 = z2*z2;

        float k3 = x2 + z2;
        float k2 = inversesqrt( k3*k3*k3*k3*k3*k3*k3 );
        float k1 = x4 + y4 + z4 - 6.0*y2*z2 - 6.0*x2*y2 + 2.0*z2*x2;
        float k4 = x2 - y2 + z2;

        w.x = p.x +  64.0*x*y*z*(x2-z2)*k4*(x4-6.0*x2*z2+z4)*k1*k2;
        w.y = p.y + -16.0*y2*k3*k4*k4 + k1*k1;
        w.z = p.z +  -8.0*y*k4*(x4*x4 - 28.0*x4*x2*z2 + 70.0*x4*z4 - 28.0*x2*z2*z4 + z4*z4)*k1*k2;
#else
		dz = 8.0*pow(m,3.5)*dz + 1.0;

        float r = length(w);
        float b = 8.0*acos( clamp(w.y/r, -1.0, 1.0));
        float a = 8.0*atan( w.x, w.z );
        w = p + pow(r,8.0) * vec3( sin(b)*sin(a), cos(b), sin(b)*cos(a) );
#endif

        trap = min( trap, vec4(abs(w),m) );

        m = dot(w,w);
		if( m > 4.0 )
            break;
    }
    trap.x = m;

    return 0.25*log(m)*sqrt(m)/dz;
}

vec2 map( vec3 p ){
    vec2 sdf_meshes[max(NUM_SDFS, 1)];

  //      meshes[NUM_MESHES+0].data = vec4(udRoundBox(opRot(p-vec3(0.75, -0.5, -0.8), vec3(0.0, 1.0, 0.0), 35.), vec3(0.5,0.5,0.5), 0.1));
#sdf_meshes

    vec2 res = sdf_meshes[0];
    for(int i=1; i< NUM_SDFS; ++i){
      res = mix( sdf_meshes[i], res, float(res.x < sdf_meshes[i].x) );
    }

    return res;
}

vec3 calcNormal( in vec3 pos ){
    vec3 eps = vec3(EPSILON*2.0,0.0,0.0);

    return normalize( vec3(
      map( pos+eps.xyy ).x - map( pos-eps.xyy ).x,
      map( pos+eps.yxy ).x - map( pos-eps.yxy ).x,
      map( pos+eps.yyx ).x - map( pos-eps.yyx ).x ) );
}

//-------------------------------------------------------------------------------

vec4 getTexel(const Material mat, in Hit hit, in float t){

    if(mat.tex.t == TEXTURE0 || mat.tex.t == TEXTURE1 || mat.tex.t == TEXTURE2 || mat.tex.t == TEXTURE3
       || mat.tex.t == CHECK || mat.tex.t == RIPPLE){

        if(mat.tex.t == TEXTURE0 )
        {
            return textureLod( u_tex0, hit.uv, 0. );
        }
        else if(mat.tex.t == TEXTURE1 )
        {
            return textureLod( u_tex1, hit.uv, 0. );
        }
        else if(mat.tex.t == TEXTURE2 )
        {
            return textureLod( u_tex2, hit.uv, 0. );
        }
        else if(mat.tex.t == TEXTURE3 )
        {
            return textureLod( u_tex3, hit.uv, 0. );
        }
        else if(mat.tex.t == CHECK )
        {
            return vec4( mod( floor(mat.tex.params.x*hit.uv.x) + floor(mat.tex.params.y*hit.uv.y), mat.tex.params.z) );
        }
        else if(mat.tex.t == RIPPLE )
        {
            return vec4( mod( ceil(distance(hit.uv, mat.tex.params.xy)*mat.tex.params.z),mat.tex.params.w) );
        }
    }
    else if(mat.tex.t == VORONOI )
    {
        return vec4( voronoi( mat.tex.params.xyz*hit.pos ), 0. );
    }
    else if(mat.tex.t == GRADIENT_NOISE )
    {
        float f = gradient_noise( mat.tex.params.xyz*hit.pos );
        return vec4(smoothstep( -0.7, 0.7, f ));
    }
    else if(mat.tex.t == VALUE_NOISE )
    {
        return vec4( value_noise( mat.tex.params.xyz*hit.pos ) );
    }
    else if(mat.tex.t == METAL)
    {
        const vec3 m = vec3(-1.2,1.99,-1.6);

        vec3 q = mat.tex.params.xyz*hit.pos;
        float f = 0.5000*value_noise( q ); q = m*q*2.01;
        f += 0.2500*value_noise( q ); q = m*q*2.02;
        f += 0.1250*value_noise( q ); q = m*q*2.03;
        f += 0.0625*value_noise( q ); q = m*q*2.01;

        return vec4(f);
    }
    else
    {
        return vec4(0.0);
    }

}

//-----------------------------------------------------
// Intersection functions
//-----------------------------------------------------

//> quadric equation solver
bool solveQuadratic(float A, float B, float C, out float t0, out float t1) {
  float discrim = B*B-4.0*A*C;

  if ( discrim <= 0.0 ) return false;

  float rootDiscrim = sqrt( discrim );

  float t_0 = (-B-rootDiscrim)/(2.0*A);
  float t_1 = (-B+rootDiscrim)/(2.0*A);

  t0 = min( t_0, t_1 );
  t1 = max( t_0, t_1 );

  return true;
}

//> aabb intersection
bool iAABB(in AABB aabb, in Ray r){
	vec3 tx1 = (aabb.b1 - r.o)*(1.0 / r.d);
	vec3 tx2 = (aabb.tr - r.o)*(1.0 / r.d);

	float tmin = min(tx1.x, tx2.x);
	tmin = min(tmin, min(tx1.y, tx2.y));
	tmin = min(tmin, min(tx1.z, tx2.z));

	float tmax = max(tx1.x, tx2.x);
	tmax = max(tmax, max(tx1.y, tx2.y));
	tmax = max(tmax, max(tx1.z, tx2.z));

	return tmax >= tmin;
}

//> plane intersection
bool iPlane(const Mesh plane, in Ray r, in float tmin, out float t){
	t = (-plane.joker.x - dot(plane.pos, r.o)) / dot(plane.pos, r.d);
	return (t > EPSILON) && (t < tmin);
}

//> sphere intersection
bool iSphere(const Mesh sphere, in Ray r, in float tmin, out float t){
	vec3 op = sphere.pos - r.o;
	float b = dot(op, r.d);
	float det = b * b - dot(op, op) + sphere.joker.x * sphere.joker.x;

	if(det < 0.0) return false;

	det = sqrt(det);

	t = b - det;
	if(t > EPSILON && t < tmin) return true;

	t = b + det;
	if(t > EPSILON && t < tmin) return true;

	return false;
}

//> box intersection
bool iBox(const Mesh box, in Ray r, in float tmin, out float t, out vec3 n){
  vec3 minCorner = box.pos - box.joker.x * 0.5;
  vec3 maxCorner = box.pos + box.joker.x * 0.5;

	vec3 invDir = 1.0 / r.d;
	vec3 dmin = (minCorner - r.o) * invDir;
	vec3 dmax = (maxCorner - r.o) * invDir;

	vec3 real_min = min(dmin, dmax);
	vec3 real_max = max(dmin, dmax);

	float minmax = min( min(real_max.x, real_max.y), real_max.z);
	float maxmin = max( max(real_min.x, real_min.y), real_min.z);

	if (minmax > maxmin)
	{

		if (maxmin > 0.0) // if we are outside the box
		{
			n = -sign(r.d) * step(real_min.yzx, real_min) * step(real_min.zxy, real_min);
			t = maxmin;
		}
		else if (minmax > 0.0) // else if we are inside the box
		{
			n = -sign(r.d) * step(real_max, real_max.yzx) * step(real_max, real_max.zxy);
			t = minmax;
		}

	}

	return (t > EPSILON) && (t < tmin);
}

/*//-----------------------------------------------------------------------------------------

//> triangle intersection
bool iTriangle(in vec3 v1, in vec3 v2, in vec3 v3, in Mesh mesh, in Ray r, in float tmin, in bool forShadowTest, out float t, out Hit hit){
	vec3 e0 = v2 - v1;
	vec3 e1 = v3 - v1;

	vec3  h = cross(r.d, e1);
	float a = dot(e0, h);

	if(mesh.mat.opts[3] && a < EPSILON)	// backface culling on
		return false;
	else if(!mesh.mat.opts[3] && a > -EPSILON && a < EPSILON) // backface culling off
		return false;

	float f = 1.0 / a;

	vec3  s = r.o - v1;
	float u = f * dot(s, h);

	if(u < 0.0 || u > 1.0) return false;

	vec3  q = cross(s, e0);
	float v = f * dot(r.d, q);

	if(v < 0.0 || u + v > 1.0)
		return false;

	t = f * dot(e1, q);

	return (t > EPSILON) && (t < tmin);
}

//> cylinder intersection
bool iCylinder(in Ray r, in Mesh mesh, in bool forShadowTest, out float t, out Hit hit){

  // Compute quadratic cylinder coefficients
  float a = r.d.x*r.d.x + r.d.y*r.d.y;
  float b = 2.0 * (r.d.x*r.o.x + r.d.y*r.o.y);
  float c = r.o.x*r.o.x + r.o.y*r.o.y - mesh.joker.x*mesh.joker.x;

  // Solve quadratic equation for _t_ values
  float t0, t1;
  if (!solveQuadratic( a, b, c, t0, t1))
  	return false;

  if ( t1 < 0.0 )
    return false;

  t = t0;

  if (t0 < 0.0)
    t = t1;

  // Compute cylinder hit point and $\phi$
  vec3 phit = r.o + r.d*t;
  float phi = atan(phit.y,phit.x) + PI;

  if (phi < 0.0)
    phi += TWO_PI;

  // Test cylinder intersection against clipping parameters
  if ( (phit.z < mesh.joker.y) || (phit.z > mesh.joker.z) || (phi > mesh.joker.w) ) {
  	if (t == t1)
      return false;

  	t = t1;
  	// Compute cylinder hit point and $\phi$
  	phit = r.o + r.d*t;
  	phi = atan(phit.y,phit.x);
    phi += PI;

  	if ( (phit.z < mesh.joker.y) || (phit.z > mesh.joker.z) || (phi > mesh.joker.w) )
  		return false;
  }

  if( !forShadowTest ) {
      hit.pos = phit;
      hit.uv.x = (phit.z - mesh.joker.y)/(mesh.joker.z - mesh.joker.y);
      hit.uv.y = phi/mesh.joker.w;
      hit.n = normalize( vec3( phit.xy, 0.0 ) );
      //hit.tangent = vec3( 0.0, 0.0, 1.0 );
  }

  return true;
}

//> GRID SDF intersection
bool iGRID_SDF(in Ray r, in float tmin, out float t, out Mesh mesh){
  t = EPSILON*10.;

  if(!iAABB(sdf0_aabb.aabb, r)) return false;

  for(int i=0; i<MARCHING_STEPS; i++ )
  {
    mesh = map(r.o+r.d*t);

    float h = abs(mesh.joker.x);
    if( h<EPSILON )break;

    t += h*FUDGE_FACTOR;
    if( t>tmin ) return false;
  }

  // assign normal
  mesh.mat.n = calcNormal(r.o+r.d*t);

  return true;
}

//-----------------------------------------------------------------------------------------*/

//> SDF intersection
bool iSDF(in Ray r, in float tmin, out float t, out vec3 n, out int index){
    t = EPSILON*10.;

    vec2 res;

    for(int i=0; i<MARCHING_STEPS; ++i){
        res = map(r.o+r.d*t);
        float h = abs(res.x);
        if( h<EPSILON || t>tmin ) break;
        t += h*FUDGE_FACTOR;
    }

    if( t>tmin ) return false;

    // assign normal
    n = calcNormal(r.o+r.d*t);
    index = NUM_MESHES + int(res.y);

    return true;
}

//--------------- Main Intersection function ---------------//

float intersection(in Ray r, out Hit hit){
    hit = HIT_MISS;

    int type = NULL;
    float tt = INFINITY;
    float tmin = INFINITY;

	//-------- Mesh Intersection --------
    if(U_EUCLIDEAN){
      for(int i = 0; i < NUM_MESHES; ++i)
      {
        if(meshes[i].joker.x == 0.0) continue;// continue if not def

        if(U_SPHERE && meshes[i].t == SPHERE){
          if(iSphere(meshes[i], r, tmin, tt))
          {
            tmin = tt;
            type = SPHERE;
            hit.index = i;
          }
        } else if(U_PLANE && meshes[i].t == PLANE){
          if(iPlane(meshes[i], r, tmin, tt))
          {
            tmin = tt;
            type = PLANE;
            hit.index = i;
          }
        } else if(U_BOX && meshes[i].t == BOX){
          if(iBox(meshes[i], r, tmin, tt, hit.n))
          {
            tmin = tt;
            type = BOX;
            hit.index = i;
          }
        }
      }
    }


  	//-------- SDF Intersection --------
    if(U_SDF){
      if(iSDF(r, tmin, tt, hit.n, hit.index))
      {
        tmin = tt;
        type = SDF;
      }
    }

    //----------------------- DATA PARSER -----------------------
	if(bool(type+1))
	{
      hit.pos = r.d * tmin + r.o;

      if(U_EUCLIDEAN && ( U_SPHERE && type == SPHERE || U_PLANE && type == PLANE || U_BOX && type == BOX )){// Sphere

        if(U_SPHERE && type == SPHERE) {
          float rho, phi, theta;
          cartesianToSpherical( hit.pos, rho, phi, theta );

          hit.uv = vec2(phi/PI, theta/TWO_PI);
          hit.n =  normalize(hit.pos - meshes[hit.index].pos);
          // hit.n = (x - spheres[ss[1]].data.xyz)/spheres[ss[1]].data.w;
        }
        else if(U_PLANE && type == PLANE) {
          hit.n =  normalize(meshes[hit.index].pos);
        }

      }

      if(!bool(hit.uv.x+1.0)){
        vec3 nl = abs(hit.n);

        hit.uv = nl.x > nl.y && nl.x > nl.z ? -hit.pos.zy:
                  nl.y > nl.x && nl.y > nl.z ? hit.pos.xz:
                               vec2(hit.pos.x, -hit.pos.y);
      }

      if(meshes[hit.index].mat.tex.t != NULL) hit.texel = getTexel(meshes[hit.index].mat, hit, tmin);
    }

    return tmin;
}

// orthogonal vector
vec3 ortho(vec3 v){
#if 1
  return mix(vec3(-v.y, v.x, 0.0), vec3(0.0, -v.z, v.y), step(abs(v.x), abs(v.z)));
#else
  return mix(vec3(-v.z, 0.0, v.x), vec3(0.0, v.z, -v.y), step(abs(v.x), abs(v.y)));
#endif
}

void calc_binormals(vec3 normal, out vec3 tangent, out vec3 binormal){
    tangent = normalize(ortho(normal));
//    tangent = normalize(cross(normal, vec3(0.0,1.0,1.0)));
//    tangent = normalize( cross( abs(normal.x) > 0.1 ? vec3(0, 1, 0) : vec3(1, 0, 0), normal ) );
    binormal = cross(normal, tangent);
}

vec3 getSampleBiased(vec3 w, float power, float seed){
    vec3 u, v;
    calc_binormals(w, u ,v);

	// Convert to spherical coords aligned to dir
	vec2 r = hash2(vec2(seed));
	r.x = r.x * TWO_PI;
	r.y = pow(r.y, 1.0 / (power + 1.0));

	float oneminus = sqrt(1.0 - r.y * r.y);
	return normalize(cos(r.x) * oneminus * u + sin(r.x) * oneminus * v + r.y * w);
}

vec3 getConeSample(vec3 w, float extent, float seed){
    vec3 u, v;
    calc_binormals(w, u ,v);

	// Convert to spherical coords aligned to dir
	vec2 r = hash2(vec2(seed));
	r.x = r.x * TWO_PI;
	r.y = 1.0 - r.y * extent;

	float oneminus = sqrt(1.0 - r.y * r.y);
	return normalize(cos(r.x) * oneminus * u + sin(r.x) * oneminus * v + r.y * w);
}

vec3 getRandomDirection(vec3 n, float seed){
#ifdef USE_BIASED_SAMPLING
  return getSampleBiased(n, 1.0, seed);
#else
  return getConeSample(n, 1.0, seed);
#endif
}

// thanks to @reinder
vec3 randomSphereDirection(float seed){
	vec2 r = hash2(vec2(seed))*TWO_PI;
    return vec3(sin(r.x)*vec2(sin(r.y),cos(r.y)),cos(r.x));
}

vec3 randomHemisphereDirection(vec3 n, float seed){
	vec3 dr = randomSphereDirection(seed);
	return dot(dr,n) * dr;
}

vec3 calcDirectLighting(const Mesh light, vec3 x, vec3 nl, float seed){

  Hit hit;
  vec3 dirLight = vec3(0.0);

  // Light source with geometry
  if(light.mat.t == LIGHT){

    if(U_SPHERE && light.t == SPHERE){

      vec3 ld = light.pos + (randomSphereDirection(seed + 23.1656) * light.joker.x);
      vec3 srDir = normalize(ld - x);

      // cast shadow ray from intersection point
      float t = intersection(Ray(x, srDir), hit);
      Mesh mesh = meshes[hit.index];

      if( mesh.mat.t == LIGHT ){
          float r2 = mesh.joker.x * mesh.joker.x;
          vec3 d = mesh.pos - x;
          float d2 = dot(d,d);
          float cos_a_max = sqrt(1. - clamp( r2 / d2, 0., 1.));
          float weight = 2. * (1. - cos_a_max);
          dirLight += max(mix(mesh.mat.c, hit.texel.rgb, hit.texel.a), 0.001) * mesh.mat.e * weight * max(0.001, dot(srDir, nl));
      }
    } else if(U_SDF && light.t == SDF){

      vec3 ld = light.pos + (randomSphereDirection(seed + 78.2358) * light.joker.xyz);
      vec3 srDir = normalize(ld - x);

      // cast shadow ray from intersection point
      float t = intersection(Ray(x, srDir), hit);
      Mesh mesh = meshes[hit.index];

      if( mesh.mat.t == LIGHT ){
        dirLight += max(mix(mesh.mat.c, hit.texel.rgb, hit.texel.a), 0.001) * mesh.mat.e * max(0.001, dot(srDir, nl));
      }
    }
  }
  // Directional Light source
  else if(light.mat.t == DIR_LIGHT){

    float t = intersection(Ray(x, light.pos), hit);

    if(t == INFINITY){
      dirLight += light.mat.c * light.mat.e * max(0.001, dot(light.pos, nl));
    }
  }

  return dirLight;
}

float getWeightForPath( int e, int l ) {
    return float(e + l + 2);
}

void brdf(in Hit hit, in vec3 f, in vec3 e, in float t, in float inside, inout Ray r, inout vec3 mask, inout vec3 acc, inout bool bounceIsSpecular, in float seed, in float bounce){

  vec3 x = hit.pos;
  vec3 n = hit.n;
  vec3 nl = hit.n * inside;

  vec3 _randomDir = getRandomDirection(nl, seed + 7.1*float(u_frame) + 5681.123 + bounce*92.13);
//  vec3 _randomSphereDirection = randomSphereDirection(seed + 12.456*u_time + bounce*136.045);

  // material e is also used as a glossiness factor
  vec3 _roughness = e * _randomDir;
//  vec3 _reflDirection = normalize(_roughness + reflect(r.d, nl));

  float nc = ior_air;                   // IOR of air
  float nt = meshes[hit.index].mat.nt;  // IOR of mesh

  if(meshes[hit.index].mat.t == DIFF){ // DIFFUSE
    r = Ray(x + nl*EPSILON, _randomDir);
    mask *= f;

    ++DIFF_BOUNCES;
    bounceIsSpecular = false;
  } else if(meshes[hit.index].mat.t == SPEC){
    r = Ray(x + nl*EPSILON, normalize(_roughness + reflect(r.d, nl)));
    ++SPEC_BOUNCES;
    bounceIsSpecular = true;
  } else if(meshes[hit.index].mat.t == REFR_FRESNEL || meshes[hit.index].mat.t == REFR_SCHLICK){ // REFRACTIVE
    float nnt = inside < 0. ? nt/nc : nc/nt;
    vec3 tdir = normalize(_roughness + refract(r.d, nl, nnt));

    r.o = x;

    // total internal reflection
    if(dot(tdir, tdir) == 0.0) {
      r.o += nl*EPSILON;
      r.d = normalize(_roughness + reflect(r.d, nl));
      ++SPEC_BOUNCES;
      return;
    }

    // select either schlick or fresnel approximation
    float Re = mix(schlick(r, nl, nc, nt), fresnel(r, nl, nc, nt, tdir), meshes[hit.index].mat.t == REFR_FRESNEL);

    if( hash(seed) < Re){
      r.o += nl*EPSILON;
      r.d = normalize(_roughness + reflect(r.d, nl));
      ++SPEC_BOUNCES;
    } else {
      r.o -= nl*EPSILON;
      mask *= f;
      r.d = tdir;
      ++SCATTERING_EVENTS;
    }
    bounceIsSpecular = true;
  } else if(meshes[hit.index].mat.t == COAT){  // COAT
    r.o = x + nl*EPSILON;

    // choose either specular reflection or diffuse
    if( hash(seed) < schlick(r, nl, nc, nt) ){
      r.d = normalize(_roughness + reflect(r.d, nl));
      ++SPEC_BOUNCES;
      bounceIsSpecular = true;
    } else {
      r.d  =_randomDir;
      mask *= f;

      ++DIFF_BOUNCES;
      bounceIsSpecular = false;
    }
  }

  if(!bounceIsSpecular){

#ifdef USE_CUBEMAP
    vec3 srDir = getRandomDirection(nl, seed + bounce*965.325);

    float t = intersection(Ray(x, srDir), hit);
    if(t == INFINITY){
      acc += mask * texture(u_cubemap, srDir).rgb * max(0.001, dot(srDir, nl));
    }
#endif

    if(sample_lights){
      for(int i = 0; i < light_index.length(); ++i){
        acc += calcDirectLighting(meshes[light_index[i]], x, nl, seed + 8652.1*float(u_frame) + 5681.123 + bounce*7895.13)*mask;
      }
    }
  }

  // mask *= max(0.001, dot(r.d, n)); // cosine weighted importance sampling
}

//-----------------------------------------------------
// Radiance
//-----------------------------------------------------

vec3 radiance(Ray r, float seed){

  vec3 acc = vec3(0.);
  vec3 mask = vec3(1.);

  bool bounceIsSpecular = true;

  for (int depth = 0; depth < MAX_BOUNCES; ++depth){

    Hit hit;
    float t = intersection(r, hit);

    if(t == INFINITY){

      if(!bounceIsSpecular && sample_lights) break;

#ifdef USE_CUBEMAP
        acc += mask * texture(u_cubemap, r.d).rgb;
#elif defined (USE_PROCEDURAL_SKY)
        acc += mask * vec3(0.5) + vec3(0.5) * cos(TWO_PI * (vec3(0.525, 0.408, 0.409) + vec3(0.9, 0.97, 0.8) * clamp(r.d.y * 0.6 + 0.5, 0.3, 1.0)));
#endif

      break;
    }

    Mesh mesh = meshes[hit.index];

    // color
    vec3 c = max(mix(mesh.mat.c, hit.texel.rgb * mesh.mat.tex.c_mask, float(mesh.mat.opts[0])*hit.texel.a), 0.001);

    // 1 if outside
    float inside = -sign(dot(r.d, hit.n));

    // emission
    vec3 e = max(mix(mesh.mat.e, hit.texel.rgb * mesh.mat.tex.e_mask, float(mesh.mat.opts[1])*hit.texel.a), 0.001);

    if(mesh.mat.t == LIGHT){
      if(bounceIsSpecular || !sample_lights){
        mask *= c;
        acc += mask*e;
      }

      break;
    }

    brdf(hit, c, e, t, inside, r, mask, acc, bounceIsSpecular, seed, float(depth));

    // terminate if necessary
    if( DIFF_BOUNCES      >= MAX_DIFF_BOUNCES   || SPEC_BOUNCES      >= MAX_SPEC_BOUNCES   ||
        TRANS_BOUNCES     >= MAX_TRANS_BOUNCES  || SCATTERING_EVENTS >= MAX_SCATTERING_EVENTS ) break;
  }

  return acc;
}

//-----------------------------------------------------
// main
//-----------------------------------------------------

void main(void){
    vec2 st = 2.0 * gl_FragCoord.xy / u_resolution - 1.;
    float aspect = u_resolution.x/u_resolution.y;

    float seed = hash(dot( gl_FragCoord.xy, vec2(12.9898, 78.233) ) + 1113.1*float(u_frame));

	//camera setup
    float theta = u_camParams.x*RAD;
    float uVLen = tan(theta/2.);
    float uULen = aspect * uVLen;

  	vec3 w = normalize(u_camLookAt);
  	vec3 u = normalize(cross(w,vec3(0.0, 1.0, 0.0)));
  	vec3 v = cross(u, w);

    float r1 = 2.0 * hash(seed+13.271);
    float r2 = 2.0 * hash(seed+63.216);

    // AA offset
    vec2 d = vec2(
      r1 < 1.0 ? sqrt(r1) - 1.0 : 1.0 - sqrt(2.0 - r1),
      r2 < 1.0 ? sqrt(r2) - 1.0 : 1.0 - sqrt(2.0 - r2)
    );
    d /= (u_resolution * 0.5);
    d += st;

    vec3 focalPoint = normalize(d.x * u * uULen + d.y * v * uVLen  + w) * u_camParams.z;

    // random point on aperture
    float randomAngle = hash(seed+496.4562) * TWO_PI;
    float randomRadius = hash(seed+249.1686) * u_camParams.y;
    vec3 randomAperturePos = ( cos(randomAngle) * u + sin(randomAngle) * v ) * randomRadius;

    // primary ray
    Ray r = Ray(u_camPos + randomAperturePos, normalize(focalPoint - randomAperturePos));
    FragColor.rgb = texelFetch(u_bufferA, ivec2(gl_FragCoord.xy), 0).rgb + radiance(r, seed);
}
