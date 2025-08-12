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
layout(location = 1) out highp vec4 ReSTIRData;
layout(location = 2) out highp vec4 ReSTIRAux;

//------------------------------- UNIFORMS --------------------------------------

// canvas resolution
uniform vec2 u_resolution;
// curremt time
uniform float u_time;
// current frame
uniform uint u_frame;
// backbuffer, tex0, tex1, tex2, tex3, random tex
uniform sampler2D u_bufferA, u_tex0, u_tex1, u_tex2, u_tex3, u_rnd_tex;
uniform sampler2D u_restir_buffer;
uniform sampler2D u_restir_aux;
uniform sampler2D u_restir_history1;
uniform sampler2D u_restir_history1_aux;
uniform sampler2D u_restir_history2;
uniform sampler2D u_restir_history2_aux;
// enviroment cubemap
uniform samplerCube u_cubemap;
// camera attributes
uniform vec3 u_camPos, u_camLookAt, u_camParams;
// temporal accumulation frames for animated scenes
uniform int u_temporalFrames;

//------------------------------- CONSTANTS -------------------------------------

#constants

// epsilon & infinity
const float EPSILON = 0.001;
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
const float PI                =   3.14159265;
const float ONE_OVER_PI       =   0.31830989;
const float TWO_PI            =   6.28318531;
const float FOUR_PI           =   12.5663706;
const float RAD               =   0.01745329;
const float E                 =   2.71828183;

// Performance constants for light sampling
const float kImportanceThreshold = 0.001;
const float kSeedA = 8652.1;
const float kSeedB = 5681.123;
const float kSeedC = 7895.13;
const float kSeedD = 123.456;

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

//------------------------------- ANIMATION -------------------------------------

// Get animated position for lights and objects
vec3 getAnimatedPosition(const vec3 basePos, const int meshIndex, const float time) {
    if (RENDER_MODE != 1) return basePos;
    
    vec3 animatedPos = basePos;
    float t = time * 0.001; // Convert to seconds
    
    if (meshIndex >= 6 && meshIndex <= 14) {
        float radius = 0.6;
        float speed = 1.0 + float(meshIndex - 6) * 0.2;
        float phase = float(meshIndex - 6) * 0.7;

        animatedPos.x = basePos.x + cos(t * speed + phase) * radius * 0.3;
        animatedPos.z = basePos.z + sin(t * speed + phase) * radius * 0.3;
        animatedPos.y = basePos.y + sin(t * speed * 2.0 + phase) * 0.1;
    }
    
    bool hasSDF = (NUM_SDFS > 0);
    if (meshIndex >= NUM_MESHES && hasSDF) { // SDF objects
        float rotSpeed = 0.5;
        float angle = t * rotSpeed;
        float cosA = cos(angle);
        float sinA = sin(angle);
        
        vec3 rotatedPos = vec3(
            animatedPos.x * cosA - animatedPos.z * sinA,
            animatedPos.y,
            animatedPos.x * sinA + animatedPos.z * cosA
        );
        
        rotatedPos.y += sin(t * 1.5) * 0.05;
        
        return rotatedPos;
    }
    
    return animatedPos;
}

//=========================== RNG ===============================

float hash(float seed){
    return fract(sin(seed) * 43758.5453);
}

vec2 hash2(vec2 seed){
    seed = fract(seed * vec2(0.1031, 0.1030));
    seed += dot(seed, seed.yx + 19.19);
    return fract((seed.xx + seed.yy) * seed.xy);
}

vec3 hash3(vec3 seed){
    seed = fract(seed * vec3(0.1031, 0.1030, 0.0973));
    seed += dot(seed, seed.yxz + 19.19);
    return fract((seed.xxy + seed.yxx) * seed.zyx);
}

//===================== NOISE FUNCTIONS =========================

vec3 gradient_hash( vec3 p ){
    p = vec3( dot(p,vec3(127.1,311.7, 74.7)),
              dot(p,vec3(269.5,183.3,246.1)),
              dot(p,vec3(113.5,271.9,124.6)));
    return -1.0 + 2.0*fract(sin(p)*43758.5453);
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

float value_noise( in vec3 x ){
    vec3 p = floor(x);
    vec3 f = fract(x);
    f = f*f*(3.0-2.0*f);

    vec2 uv = (p.xy+vec2(37.0,17.0)*p.z) + f.xy;
    vec2 rg = textureLod( u_rnd_tex, (uv+0.5)/256.0, 0.0).yx;
    return mix( rg.x, rg.y, f.z );
}

// Optimized voronoi with early exit
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
        vec3 hx = p + b ;
        vec3 r = vec3( b ) - f + texture( u_rnd_tex, (hx.xy+vec2(3.0,1.0)*hx.z+0.5)/256.0, -100.0 ).xyz;

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

float sdBox( in vec3 p, in vec3 b ){
    vec3 d = abs(p) - b;
    return length(max(d,0.0)) + min(max(d.x,max(d.y,d.z)),0.0);
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

// Optimized Mandelbulb with fewer iterations
float Mandelbulb( vec3 p ){
    vec3 w = p;
    float m = dot(w,w);

    vec4 trap = vec4(abs(w),m);
    float dz = 1.0;

    for( int i=0; i<3; ++i ) // Reduced from 4 to 3 iterations
    {
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
    const vec2 eps = vec2(EPSILON, 0.0);
    
    return normalize( vec3(
        map(pos + eps.xyy).x - map(pos - eps.xyy).x,
        map(pos + eps.yxy).x - map(pos - eps.yxy).x,
        map(pos + eps.yyx).x - map(pos - eps.yyx).x ) );
}

//-------------------------------------------------------------------------------

vec4 getTexel(const Material mat, in Hit hit, in float t){
    int tex_type = mat.tex.t;
    
    // Handle simple texture types first
    if(tex_type <= TEXTURE3) {
        if(tex_type == TEXTURE0) return textureLod( u_tex0, hit.uv, 0. );
        if(tex_type == TEXTURE1) return textureLod( u_tex1, hit.uv, 0. );
        if(tex_type == TEXTURE2) return textureLod( u_tex2, hit.uv, 0. );
        if(tex_type == TEXTURE3) return textureLod( u_tex3, hit.uv, 0. );
    }
    
    // Handle procedural patterns
    if(tex_type == CHECK) {
        return vec4( mod( floor(mat.tex.params.x*hit.uv.x) + floor(mat.tex.params.y*hit.uv.y), mat.tex.params.z) );
    }
    
    if(tex_type == RIPPLE) {
        return vec4( mod( ceil(distance(hit.uv, mat.tex.params.xy)*mat.tex.params.z),mat.tex.params.w) );
    }
    
    // Handle 3D noise functions
    vec3 scaled_pos = mat.tex.params.xyz * hit.pos;
    
    if(tex_type == VORONOI) {
        return vec4( voronoi( scaled_pos ), 0. );
    }
    
    if(tex_type == GRADIENT_NOISE) {
        float f = gradient_noise( scaled_pos );
        return vec4(smoothstep( -0.7, 0.7, f ));
    }
    
    if(tex_type == VALUE_NOISE) {
        return vec4( value_noise( scaled_pos ) );
    }
    
    if(tex_type == METAL) {
        const vec3 m = vec3(-1.2,1.99,-1.6);
        vec3 q = scaled_pos;
        float f = 0.5000*value_noise( q ); q = m*q*2.01;
        f += 0.2500*value_noise( q ); q = m*q*2.02;
        f += 0.1250*value_noise( q );
        return vec4(f);
    }
    
    return vec4(0.0);
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
bool iSphere(const Mesh sphere, const Ray r, const float tmin, out float t, const int meshIndex){
    vec3 oc = r.o - ((RENDER_MODE != 1) ? sphere.pos : getAnimatedPosition(sphere.pos, meshIndex, u_time));
    float b = dot(oc, r.d);
    float c = dot(oc, oc) - sphere.joker.x * sphere.joker.x;
    float discriminant = b * b - c;

    if(discriminant < 0.0) return false;

    float sqrt_d = sqrt(discriminant);
    t = -b - sqrt_d;
    
    if(t > EPSILON && t < tmin) return true;
    
    t = -b + sqrt_d;
    return (t > EPSILON && t < tmin);
}

//> box intersection - optimized
bool iBox(const Mesh box, in Ray r, in float tmin, out float t, out vec3 n){
    vec3 m = 1.0 / r.d; // can precompute if needed
    vec3 n_vec = m * (box.pos - r.o);
    vec3 k = abs(m) * box.joker.x * 0.5;
    
    vec3 t1 = n_vec - k;
    vec3 t2 = n_vec + k;
    
    float tN = max(max(t1.x, t1.y), t1.z);
    float tF = min(min(t2.x, t2.y), t2.z);
    
    if(tN > tF || tF < 0.0) return false;
    
    t = (tN > 0.0) ? tN : tF;
    
    if(t < EPSILON || t >= tmin) return false;
    
    // Calculate normal
    vec3 hit_point = r.o + r.d * t - box.pos;
    vec3 d = abs(hit_point) - box.joker.x * 0.5;
    n = normalize(sign(hit_point) * step(d.yzx, d) * step(d.zxy, d));
    
    return true;
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

//> SDF intersection - optimized with early termination
bool iSDF(in Ray r, in float tmin, out float t, out vec3 n, out int index){
    t = EPSILON*4.0;

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
        // Early exit for undefined meshes
        if(meshes[i].joker.x == 0.0) continue;

        int mesh_type = meshes[i].t;
        
        if(U_SPHERE && mesh_type == SPHERE){
          if(iSphere(meshes[i], r, tmin, tt, i))
          {
            tmin = tt;
            type = SPHERE;
            hit.index = i;
          }
        } else if(U_PLANE && mesh_type == PLANE){
          if(iPlane(meshes[i], r, tmin, tt))
          {
            tmin = tt;
            type = PLANE;
            hit.index = i;
          }
        } else if(U_BOX && mesh_type == BOX){
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
          hit.n =  normalize(hit.pos - ((RENDER_MODE != 1) ? meshes[hit.index].pos : getAnimatedPosition(meshes[hit.index].pos, hit.index, u_time)));
          // hit.n = (x - spheres[ss[1]].data.xyz)/spheres[ss[1]].data.w;
        }
        else if(U_PLANE && type == PLANE) {
          hit.n =  normalize(meshes[hit.index].pos);
        }

      }

      // Generate UV coordinates if not already set
      if(hit.uv.x < 0.0){
        vec3 nl = abs(hit.n);

        hit.uv = nl.x > nl.y && nl.x > nl.z ? -hit.pos.zy:
                  nl.y > nl.x && nl.y > nl.z ? hit.pos.xz:
                               vec2(hit.pos.x, -hit.pos.y);
      }

      if(meshes[hit.index].mat.tex.t != NULL) hit.texel = getTexel(meshes[hit.index].mat, hit, tmin);
    }

    return tmin;
}

/*
SOURCE: 
	"Building an Orthonormal Basis from a 3D Unit Vector Without Normalization"
		http://orbit.dtu.dk/files/126824972/onb_frisvad_jgt2012_v2.pdf
		
	"Building an Orthonormal Basis, Revisited" 
		http://jcgt.org/published/0006/01/01/
*/
void calc_binormals(vec3 n, out vec3 ox, out vec3 oz){
	float sig = n.z < 0.0 ? -1.0 : 1.0;
	
	// Handle the degenerate case when n.z is close to ±1
	if(abs(n.z) > 0.99999) {
		ox = vec3(1.0, 0.0, 0.0);
		oz = vec3(0.0, sig, 0.0);
		return;
	}
	
	float a = 1.0 / (sig - n.z);
	float b = n.x * n.y * a;
	
	ox = vec3(1.0 + sig * n.x * n.x * a, sig * b, -sig * n.x);
	oz = vec3(b, sig + n.y * n.y * a, -n.y);
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

vec3 randomSphereDirection(const float seed){
	vec2 r = hash2(vec2(seed))*TWO_PI;
  vec2 sincos_y = vec2(sin(r.y), cos(r.y));
  return vec3(sin(r.x) * sincos_y, cos(r.x));
}

vec3 randomHemisphereDirection(vec3 n, float seed){
  vec3 dr = randomSphereDirection(seed);
  return dot(dr,n) < 0.0 ? -dr : dr;
}

vec3 calcDirectLighting(const Mesh light, const vec3 x, const vec3 nl, const float seed, const int lightIndex){

  Hit hit;
  vec3 dirLight = vec3(0.0);

  // Light source with geometry
  if(light.mat.t == LIGHT){

    if(U_SPHERE && light.t == SPHERE){

      vec3 ld = ((RENDER_MODE != 1) ? light.pos : getAnimatedPosition(light.pos, lightIndex, u_time)) + (randomSphereDirection(seed + 23.1656) * light.joker.x);
      vec3 srDir = normalize(ld - x);

      // cast shadow ray from intersection point with epsilon offset
      float t = intersection(Ray(x + nl*EPSILON, srDir), hit);
      Mesh mesh = meshes[hit.index];

      if( mesh.mat.t == LIGHT ){
          float r2 = mesh.joker.x * mesh.joker.x;
          vec3 d = ((RENDER_MODE != 1) ? mesh.pos : getAnimatedPosition(mesh.pos, hit.index, u_time)) - x;
          float d2 = dot(d,d);
          float cos_a_max = sqrt(1. - clamp( r2 / d2, 0., 1.));
          float weight = 2. * (1. - cos_a_max);
          dirLight += max(mix(mesh.mat.c, hit.texel.rgb, hit.texel.a), 0.001) * mesh.mat.e * weight * max(0.001, dot(srDir, nl));
      }
    } else if(U_SDF && light.t == SDF){

      vec3 ld = ((RENDER_MODE != 1) ? light.pos : getAnimatedPosition(light.pos, lightIndex, u_time)) + (randomSphereDirection(seed + 78.2358) * light.joker.xyz);
      vec3 srDir = normalize(ld - x);

      // cast shadow ray from intersection point with epsilon offset
      float t = intersection(Ray(x + nl*EPSILON, srDir), hit);
      Mesh mesh = meshes[hit.index];

      if( mesh.mat.t == LIGHT ){
        dirLight += max(mix(mesh.mat.c, hit.texel.rgb, hit.texel.a), 0.001) * mesh.mat.e * max(0.001, dot(srDir, nl));
      }
    }
  }
  // Directional Light source
  else if(light.mat.t == DIR_LIGHT){

    float t = intersection(Ray(x + nl*EPSILON, light.pos), hit);

    if(t == INFINITY){
      dirLight += light.mat.c * light.mat.e * max(0.001, dot(light.pos, nl));
    }
  }

  return dirLight;
}

// Power heuristic for MIS
float powerHeuristic(float nf, float fPdf, float ng, float gPdf) {
    float f = nf * fPdf;
    float g = ng * gPdf;
    return (f * f) / (f * f + g * g);
}

// Calculate PDF for cosine-weighted hemisphere sampling
float cosineHemispherePdf(vec3 wi, vec3 n) {
    return max(0.0, dot(wi, n)) * ONE_OVER_PI;
}

// Calculate PDF for light sampling
float lightSamplingPdf(const Mesh light, vec3 x, vec3 wi) {
    if(light.mat.t != LIGHT) return 0.0;
    
    if(U_SPHERE && light.t == SPHERE) {
        vec3 d = light.pos - x;
        float d2 = dot(d, d);
        float r2 = light.joker.x * light.joker.x;
        if(d2 <= r2) return 0.0; // Inside sphere
        
        float cos_theta_max = sqrt(max(0.0, 1.0 - r2 / d2));
        return 1.0 / (TWO_PI * (1.0 - cos_theta_max));
    }
    
    return 1.0 / FOUR_PI; // Uniform sphere sampling fallback
}

//=========================== ReSTIR ===============================

#ifdef USE_RESTIR
const int RESTIR_SPATIAL_SAMPLES = 8;
const float SPATIAL_RADIUS = 16.0;
const float TEMPORAL_ALPHA = 0.95;
const int MAX_RESERVOIR_AGE = 30;
const float NORMAL_THRESHOLD = 0.9;
const float HISTORY_DECAY_RATE = 0.90; 
const int MAX_TEMPORAL_SAMPLES = 2;

struct Reservoir {
    vec3 light_pos;
    vec3 light_color;
    float weight_sum;
    float M;
    float W;
    float age;
    int light_index;
};

const Reservoir EMPTY_RESERVOIR = Reservoir(vec3(0.0), vec3(0.0), 0.0, 0.0, 0.0, 0.0, -1);

// Optimized Poisson disk samples for better spatial distribution
const vec2 POISSON_DISK[8] = vec2[](
    vec2(-0.4706, 0.4706),
    vec2(0.8090, 0.2628),
    vec2(-0.2628, -0.8090),
    vec2(0.6882, -0.5000),
    vec2(-0.9511, -0.1625),
    vec2(0.1625, 0.9511),
    vec2(0.5000, -0.6882),
    vec2(-0.6882, 0.5000)
);
#endif // USE_RESTIR

#ifdef USE_RESTIR
Reservoir initReservoir() {
    return EMPTY_RESERVOIR;
}

void updateReservoir(inout Reservoir r, vec3 light_pos, vec3 light_color, int light_idx, float weight, float rand) {
    weight = clamp(weight, 0.0, 50.0); // Reduced max weight for stability
    
    if (weight <= 0.0) return;
    
    r.weight_sum += weight;
    r.M += 1.0;
    
    // Prevent excessive accumulation with better bounds
    if (r.M > 60.0) {
        r.weight_sum *= 0.95;
        r.M *= 0.95;
    }
    
    // Use proper reservoir sampling with normalized probability
    if (r.weight_sum > 0.0) {
        float selection_prob = weight / r.weight_sum;
        if (rand < selection_prob) {
            r.light_pos = light_pos;
            r.light_color = light_color;
            r.light_index = light_idx;
        }
    }
}

#ifdef USE_RESTIR
bool isValidNeighbor(const vec3 center_pos, const vec3 center_normal, const vec3 neighbor_pos, const vec3 neighbor_normal) {
    float normal_similarity = dot(center_normal, neighbor_normal);
    if (normal_similarity < NORMAL_THRESHOLD) return false;
    
    float position_diff = length(center_pos - neighbor_pos);
    if (position_diff > 2.0) return false;
    
    return true;
}

// Validate reservoir data with improved checks
bool isValidReservoir(const Reservoir r) {
    if (isnan(r.M) || isinf(r.M) || isnan(r.weight_sum) || isinf(r.weight_sum) || 
        isnan(r.W) || isinf(r.W) || isnan(r.age) || isinf(r.age)) {
        return false;
    }
    
    if (r.M <= 0.0 || r.M > 200.0) return false;
    if (r.weight_sum <= 0.0 || r.weight_sum > 1000.0) return false;
    if (r.W < 0.0 || r.W > 20.0) return false;
    if (r.age < 0.0 || r.age > float(MAX_RESERVOIR_AGE + 5)) return false;
    
    if (length(r.light_color) < 0.001 || length(r.light_color) > 100.0) return false;
    
    if (r.light_index >= int(light_index.length()) && r.light_index != -1) return false;
    
    if (length(r.light_pos) < EPSILON && r.light_index >= 0) return false;
    
    return true;
}

// Enhanced target function evaluation with better BRDF handling
float evaluateTargetFunction(const vec3 light_pos, const vec3 light_color, const vec3 hit_pos, const vec3 hit_normal, const Material mat) {
    vec3 light_vec = light_pos - hit_pos;
    float distance_sq = dot(light_vec, light_vec);
    
    // Avoid division by zero and very close lights
    if (distance_sq < EPSILON * EPSILON) return 0.0;
    
    vec3 light_dir = normalize(light_vec);
    float cos_theta = max(0.0, dot(hit_normal, light_dir));
    
    if (cos_theta <= 0.0) return 0.0;
    
    // Improved BRDF evaluation with proper material handling
    float brdf_value = 1.0;
    if (mat.t == DIFF) {
        brdf_value = ONE_OVER_PI;
    } else if (mat.t == SPEC) {
        // Simple Phong-like specular approximation
        vec3 view_dir = normalize(-hit_pos); // Assuming camera at origin
        vec3 reflect_dir = reflect(-light_dir, hit_normal);
        float spec_factor = max(0.0, dot(view_dir, reflect_dir));
        brdf_value = pow(spec_factor, 8.0) * 0.3; // Reduced exponent for broader specular lobe
    } else if (mat.t == REFR_FRESNEL || mat.t == REFR_SCHLICK) {
        // Simplified transmission/reflection
        brdf_value = 0.4;
    } else if (mat.t == COAT) {
        // Coat material combines diffuse and specular
        brdf_value = ONE_OVER_PI * 0.7 + 0.3;
    }
    
    // Light intensity with better color weighting for ReSTIR
    float light_intensity = length(light_color); // Use magnitude instead of luminance
    light_intensity = clamp(light_intensity, 0.1, 20.0); // Prevent extreme values
    
    // Improved geometric term with better distance falloff for ReSTIR
    float distance = sqrt(distance_sq);
    float attenuation = 1.0 / (0.1 + distance * 0.05 + distance_sq * 0.001); // Gentler falloff
    float geometric_term = cos_theta * attenuation;
    
    // Final target function value (no arbitrary scaling)
    float target_value = brdf_value * light_intensity * geometric_term;
    
    // Apply physically-based normalization
    target_value *= PI; // Account for hemisphere integration
    
    // Clamp to prevent extreme values while maintaining physical meaning
    return clamp(target_value, 0.001, 50.0);
}
// Optimized visibility test using shadow ray tracing
bool isVisible(const vec3 from_pos, const vec3 to_pos) {
    vec3 shadow_dir = to_pos - from_pos;
    float shadow_distance = length(shadow_dir);
    
    // Avoid self-intersection and very close lights
    if (shadow_distance < EPSILON * 10.0) return true;
    
    shadow_dir = normalize(shadow_dir);
    
    // Create shadow ray with appropriate offset
    Ray shadow_ray = Ray(from_pos + shadow_dir * EPSILON * 2.0, shadow_dir);
    
    Hit shadow_hit;
    float t = intersection(shadow_ray, shadow_hit);
    
    // If we hit something before reaching the light, check if it's occluding
    if (t < shadow_distance - EPSILON * 2.0) {
        // Allow light sources to be visible through themselves
        if (shadow_hit.index >= 0 && shadow_hit.index < NUM_MESHES + NUM_SDFS) {
            return meshes[shadow_hit.index].mat.t == LIGHT;
        }
        return false;
    }
    
    return true;
}
#endif // USE_RESTIR

// Pack reservoir data into two RGBA textures (enhanced packing)
vec4 packReservoirMain(const Reservoir r) {
    // Main buffer: light_pos.xyz in RGB, W in A
    return vec4(r.light_pos, r.W);
}

vec4 packReservoirAux(const Reservoir r) {
    // Auxiliary buffer: light_color.xyz in RGB, packed data in A
    float normalized_age = clamp(r.age / float(MAX_RESERVOIR_AGE), 0.0, 1.0);
    float normalized_M = clamp(r.M / 100.0, 0.0, 1.0); // Assume M is typically 0-100
    float normalized_light_index = float(r.light_index + 1) / float(max(light_index.length(), 1)); // +1 to handle -1 case
    
    // Pack age, M, and light_index into alpha
    float packed_alpha = normalized_age * 0.33 + normalized_M * 0.33 + normalized_light_index * 0.34;
    
    return vec4(r.light_color, packed_alpha);
}

// Unpack reservoir data from RGBA texture
// Enhanced unpacking using two buffers
Reservoir unpackReservoirEnhanced(const vec4 main_data, const vec4 aux_data) {
    Reservoir r = EMPTY_RESERVOIR;
    
    if (main_data.w > 0.0) {
        // Unpack main buffer
        r.light_pos = main_data.xyz;
        r.W = main_data.w;
        
        // Unpack auxiliary buffer
        r.light_color = aux_data.xyz;
        
        float packed_alpha = aux_data.w;
        float normalized_light_index = fract(packed_alpha * 2.94); // Extract light_index
        float temp = packed_alpha - normalized_light_index * 0.34;
        float normalized_M = fract(temp * 3.03); // Extract M
        float normalized_age = (temp - normalized_M * 0.33) * 3.03; // Extract age
        
        // Denormalize values
        r.age = normalized_age * float(MAX_RESERVOIR_AGE);
        r.M = normalized_M * 100.0;
        r.light_index = int(normalized_light_index * float(max(light_index.length(), 1))) - 1;
        
        // Clamp values
        r.light_index = clamp(r.light_index, -1, int(light_index.length()) - 1);
        r.M = max(1.0, r.M);
        
        // Reconstruct weight_sum
        r.weight_sum = r.W * r.M;
    }
    
    return r;
}

#ifdef USE_RESTIR
// Sample reservoir from neighboring pixel (spatial reuse)
Reservoir sampleSpatialReservoir(const vec2 neighbor_coord, const vec3 center_pos, const vec3 center_normal) {
    // Clamp to screen bounds
    if (neighbor_coord.x < 0.0 || neighbor_coord.x > 1.0 || neighbor_coord.y < 0.0 || neighbor_coord.y > 1.0) {
        return EMPTY_RESERVOIR;
    }
    
    // Sample from ReSTIR buffers (current frame spatial neighbors)
    vec4 main_data = textureLod(u_restir_buffer, neighbor_coord, 0.0);
    vec4 aux_data = textureLod(u_restir_aux, neighbor_coord, 0.0);
    return unpackReservoirEnhanced(main_data, aux_data);
}

// Enhanced multi-frame temporal sampling
Reservoir sampleTemporalHistory(const vec2 screen_coord, const vec3 current_pos, const vec3 current_normal, const int history_level) {
    // Improved motion vector calculation based on camera movement
    vec3 prev_cam_pos = u_camPos; // In a full implementation, this would be previous frame's camera position
    vec3 motion_3d = current_pos - prev_cam_pos;
    
    // Project motion to screen space with level-dependent scaling
    float motion_scale = 0.001 * float(history_level + 1);
    vec2 motion_vector = motion_3d.xy * motion_scale;
    
    // Add temporal jitter for better sampling distribution
    vec2 temporal_jitter = (hash2(screen_coord + float(uint(history_level) + u_frame) * 0.1) - 0.5) * 0.002;
    vec2 prev_coord = screen_coord + motion_vector + temporal_jitter;
    
    // Clamp to screen bounds with margin
    if (prev_coord.x < 0.01 || prev_coord.x > 0.99 || prev_coord.y < 0.01 || prev_coord.y > 0.99) {
        return EMPTY_RESERVOIR;
    }
    
    vec4 main_data, aux_data;
    
    // Sample from appropriate history buffer based on level (fixed to use proper 2-frame history)
    if (history_level == 0) {
        // Most recent frame (1 frame ago) - use history1
        main_data = textureLod(u_restir_history1, prev_coord, 0.0);
        aux_data = textureLod(u_restir_history1_aux, prev_coord, 0.0);
    } else {
        // Second frame back (2 frames ago) - use history2
        main_data = textureLod(u_restir_history2, prev_coord, 0.0);
        aux_data = textureLod(u_restir_history2_aux, prev_coord, 0.0);
    }
    
    Reservoir temporal_reservoir = unpackReservoirEnhanced(main_data, aux_data);
    
    // Apply age-based decay for older history
    if (isValidReservoir(temporal_reservoir)) {
        float decay_factor = pow(HISTORY_DECAY_RATE, float(history_level + 1));
        temporal_reservoir.M *= decay_factor;
        temporal_reservoir.weight_sum *= decay_factor;
        temporal_reservoir.age += float(history_level + 1);
    }
    
    return temporal_reservoir;
}

void finalizeReservoir(inout Reservoir r, const vec3 hit_pos, const vec3 hit_normal, const Material mat) {
    if (r.weight_sum <= 0.0 || r.M <= 0.0) {
        r.W = 0.0;
        return;
    }
    
    float target_pdf = evaluateTargetFunction(r.light_pos, r.light_color, hit_pos, hit_normal, mat);
    
    if (target_pdf <= 0.0) {
        r.W = 0.0;
        return;
    }
    
    // Visibility test early to avoid computing invalid weights
    bool is_visible = isVisible(hit_pos, r.light_pos);
    if (!is_visible) {
        r.W = 0.0;
        return;
    }
    
    // Clamp M to prevent numerical issues
    float clamped_M = clamp(r.M, 1.0, 40.0);
    
    // Basic ReSTIR weight calculation: w_sum / (p * M)
    float raw_weight = r.weight_sum / (target_pdf * clamped_M);
    
    // Simplified bias correction for better stability
    float bias_correction = 1.0;
    
    // Age-based correction (more balanced)
    if (r.age > 0.0) {
        float normalized_age = clamp(r.age / float(MAX_RESERVOIR_AGE), 0.0, 1.0);
        // Less aggressive age correction
        bias_correction *= mix(0.85, 1.0, 1.0 - normalized_age * 0.3);
    }
    
    // M-based correction (less aggressive)
    if (clamped_M > 16.0) {
        bias_correction *= sqrt(16.0 / clamped_M);
    }
    
    // Apply correction and compute final weight
    r.W = bias_correction * raw_weight;
    
    // Clamp to prevent fireflies but allow reasonable dynamic range
    r.W = clamp(r.W, 0.0, 12.0);
    
    // Additional safety check for NaN/Inf
    if (isnan(r.W) || isinf(r.W)) {
        r.W = 0.0;
    }
}

// Combine reservoirs using weighted reservoir sampling
void combineReservoirs(inout Reservoir target, const Reservoir source, const vec3 hit_pos, const vec3 hit_normal, const Material mat, const float rand) {
    if (!isValidReservoir(source)) return;
    
    // Early visibility check to avoid unnecessary computation
    if (!isVisible(hit_pos, source.light_pos)) return;
    
    // Evaluate target function for source reservoir at current shading point
    float target_weight = evaluateTargetFunction(source.light_pos, source.light_color, hit_pos, hit_normal, mat);
    
    if (target_weight <= 0.0) return;
    
    // Calculate contribution with improved numerical stability
    float source_contribution = target_weight * max(source.W, 0.0) * max(source.M, 1.0);
    
    // Prevent overflow and invalid values with tighter bounds
    source_contribution = clamp(source_contribution, 0.0, 200.0);
    if (isnan(source_contribution) || isinf(source_contribution)) return;
    
    // Update reservoir state
    float old_weight_sum = target.weight_sum;
    target.weight_sum += source_contribution;
    target.M += source.M;
    
    // Apply exponential decay instead of hard clamping for better bias-variance tradeoff
    if (target.M > 40.0) {
        float decay_factor = exp(-0.1 * (target.M - 40.0));
        target.M *= decay_factor;
        target.weight_sum *= decay_factor;
    }
    
    // Update selected sample with probability proportional to contribution
    if (target.weight_sum > 0.0) {
        float selection_probability = source_contribution / target.weight_sum;
        if (rand < selection_probability) {
            target.light_pos = source.light_pos;
            target.light_color = source.light_color;
            target.light_index = source.light_index;
            // Inherit age but add some decay (smaller increment)
            target.age = min(source.age + 0.25, float(MAX_RESERVOIR_AGE));
        }
    }
}
#endif // USE_RESTIR

#ifdef USE_RESTIR
// Global variable to store the final reservoir for output
Reservoir g_final_reservoir;
#endif

vec3 sampleLightsReSTIR(const vec3 hit_pos, const vec3 hit_normal, const Material mat, const vec2 rand_seed) {
    if (!use_restir) {
        return vec3(0.0);
    }
    
    if (light_index.length() == 0 || int(light_index[0]) < 0) {
        return vec3(0.0);
    }
    
    vec2 screen_coord = gl_FragCoord.xy / u_resolution;
    
    // Phase 1: Initial Candidate Sampling
    Reservoir initial_reservoir = initReservoir();
    
    int effective_samples = min(int(RESTIR_SAMPLES), max(int(4), int(light_index.length())));
    
    for (int i = 0; i < effective_samples; i++) {
        vec2 rand_val = hash2(rand_seed + vec2(float(i) * 0.1, float(i) * 0.2));
        
        // Select a random light from the light_index array
        int light_array_idx = int(rand_val.x * float(light_index.length()));
        light_array_idx = clamp(light_array_idx, int(0), int(light_index.length()) - 1);
        
        int light_idx = int(light_index[light_array_idx]);
        if (light_idx < 0 || light_idx >= NUM_MESHES + NUM_SDFS) continue;
        
        vec3 light_pos = (RENDER_MODE != 1) ? meshes[light_idx].pos : getAnimatedPosition(meshes[light_idx].pos, light_idx, u_time);
        vec3 light_color = meshes[light_idx].mat.c * meshes[light_idx].mat.e;
        
        // Evaluate target function
        float target_value = evaluateTargetFunction(light_pos, light_color, hit_pos, hit_normal, mat);
        
        if (target_value > 0.0) {
            updateReservoir(initial_reservoir, light_pos, light_color, light_idx, target_value, rand_val.y);
        }
    }
    
    // Phase 2: Enhanced 2-Frame Temporal Reuse
    Reservoir temporal_reservoir = initial_reservoir;
    
    // Use temporal reuse for both animated (RENDER_MODE == 1) and static scenes when frame count allows
    if (u_frame > uint(MAX_TEMPORAL_SAMPLES)) {
        // Sample from 2 temporal history levels only
        int temporal_samples_used = 0;
        
        for (int history_level = 0; history_level < MAX_TEMPORAL_SAMPLES; history_level++) {
            Reservoir history_reservoir = sampleTemporalHistory(screen_coord, hit_pos, hit_normal, history_level);
            
            if (isValidReservoir(history_reservoir) && history_reservoir.M > 0.0 && history_reservoir.age < float(MAX_RESERVOIR_AGE)) {
                // For animated scenes, update light positions for history
                if (RENDER_MODE == 1 && history_reservoir.light_index >= 0 && history_reservoir.light_index < int(light_index.length())) {
                    int actual_light_idx = int(light_index[history_reservoir.light_index]);
                    if (actual_light_idx >= 0 && actual_light_idx < NUM_MESHES + NUM_SDFS) {
                        vec3 current_light_pos = getAnimatedPosition(meshes[actual_light_idx].pos, actual_light_idx, u_time);
                        history_reservoir.light_pos = current_light_pos;
                        history_reservoir.light_color = meshes[actual_light_idx].mat.c * meshes[actual_light_idx].mat.e;
                    }
                }
                
                // Age the reservoir based on history level
                history_reservoir.age += float(history_level + 1);
                float temporal_alpha = TEMPORAL_ALPHA;
                
                // Apply decay based on history level (stronger decay for older frames)
                if (history_level == 1) {
                    temporal_alpha *= 0.80; // Stronger decay for 2nd frame back
                }
                
                // Additional reduction for animated scenes to prevent lag artifacts
                if (RENDER_MODE == 1) {
                    temporal_alpha *= 0.85;
                }
                
                // Apply temporal decay
                history_reservoir.M *= temporal_alpha;
                history_reservoir.weight_sum *= temporal_alpha;
                
                // Combine with temporal reservoir using proper random value
                float temporal_rand = hash(rand_seed.x + 789.123 + float(history_level) * 456.789);
                combineReservoirs(temporal_reservoir, history_reservoir, hit_pos, hit_normal, mat, temporal_rand);
                
                temporal_samples_used++;
            }
        }
        
        // Normalize contribution if multiple temporal samples were used
        if (temporal_samples_used > 1) {
            // Use square root normalization for better bias vs variance tradeoff
            float normalization_factor = sqrt(float(temporal_samples_used));
            temporal_reservoir.M /= normalization_factor;
            temporal_reservoir.weight_sum /= normalization_factor;
        }
        
        // Additional validation after temporal combination
        if (temporal_reservoir.M > 100.0) {
            temporal_reservoir.M = min(temporal_reservoir.M, 80.0);
            temporal_reservoir.weight_sum *= 0.9; // Slight reduction to prevent bias
        }
    }
    
    // Phase 3: Spatial Reuse
    Reservoir final_reservoir = temporal_reservoir;
    
    // Adaptive spatial sample count based on light count and frame number
    int adaptive_spatial_samples = int(RESTIR_SPATIAL_SAMPLES);
    if (light_index.length() > 10) {
        adaptive_spatial_samples = max(4, int(RESTIR_SPATIAL_SAMPLES) / 2);
    }
    
    // Reduce spatial samples for first few frames to improve convergence
    if (u_frame < 10u) {
        adaptive_spatial_samples = max(2, adaptive_spatial_samples / 2);
    }
    
    for (int i = 0; i < adaptive_spatial_samples; i++) {
        vec2 spatial_rand = hash2(rand_seed + vec2(float(i) * 0.3, float(i) * 0.4));
        
        // Generate neighbor coordinate using Poisson disk
        vec2 neighbor_offset = POISSON_DISK[i] * SPATIAL_RADIUS / u_resolution;
        vec2 neighbor_coord = screen_coord + neighbor_offset;
        
        // Sample neighbor reservoir
        Reservoir neighbor_reservoir = sampleSpatialReservoir(neighbor_coord, hit_pos, hit_normal);
        
        if (neighbor_reservoir.M > 0.0) {
            // Optimized spatial validation with early exits
            bool is_valid = true;
            
            // Early bounds check
            if (any(lessThan(neighbor_coord, vec2(0.0))) || any(greaterThan(neighbor_coord, vec2(1.0)))) {
                is_valid = false;
            }
            
            if (is_valid) {
                // Distance-based coherence check
                vec2 coord_diff = neighbor_coord - screen_coord;
                float coord_distance_sq = dot(coord_diff, coord_diff);
                float max_distance_sq = pow(SPATIAL_RADIUS / min(u_resolution.x, u_resolution.y), 2.0);
                
                if (coord_distance_sq > max_distance_sq) {
                    is_valid = false;
                }
            }
            
            if (is_valid && neighbor_reservoir.light_index >= 0) {
                // Light distance check with squared distance for efficiency
                vec3 light_diff = neighbor_reservoir.light_pos - hit_pos;
                float light_distance_sq = dot(light_diff, light_diff);
                if (light_distance_sq > 225.0) { // 15.0^2
                    is_valid = false;
                }
            }
            
            if (is_valid) {
                // Age and quality checks
                float age_threshold = RENDER_MODE == 1 ? 2.0 : float(MAX_RESERVOIR_AGE) * 0.8;
                if (neighbor_reservoir.age > age_threshold || spatial_rand.x < 0.03) {
                    is_valid = false;
                }
            }
            
            if (is_valid) {
                combineReservoirs(final_reservoir, neighbor_reservoir, hit_pos, hit_normal, mat, spatial_rand.y);
            }
        }
    }
    
    // Phase 4: Final Weight Calculation
    finalizeReservoir(final_reservoir, hit_pos, hit_normal, mat);
    
    // Clamp reservoir age and validate
    final_reservoir.age = min(final_reservoir.age, float(MAX_RESERVOIR_AGE));
    
    // Store final reservoir for output to buffer
    g_final_reservoir = final_reservoir;
    
    if (final_reservoir.W > 0.0 && final_reservoir.light_index >= 0 && final_reservoir.light_index < int(light_index.length())) {
        // Validate light index bounds
        int light_array_idx = clamp(final_reservoir.light_index, 0, int(light_index.length()) - 1);
        int actual_light_idx = int(light_index[light_array_idx]);
        
        if (actual_light_idx >= 0 && actual_light_idx < NUM_MESHES + NUM_SDFS) {
            // For animated scenes, use current light position, not the reservoir's stored position
            vec3 current_light_pos;
            if (RENDER_MODE == 1) {
                current_light_pos = getAnimatedPosition(meshes[actual_light_idx].pos, actual_light_idx, u_time);
                // Update reservoir with current position for consistency
                final_reservoir.light_pos = current_light_pos;
                final_reservoir.light_color = meshes[actual_light_idx].mat.c * meshes[actual_light_idx].mat.e;
            } else {
                current_light_pos = final_reservoir.light_pos;
            }
            
            // Final visibility test with current light position
            if (isVisible(hit_pos, current_light_pos)) {
                // Calculate final lighting contribution using updated mesh data
                vec3 light_contribution = calcDirectLighting(meshes[actual_light_idx], hit_pos, hit_normal, rand_seed.x + 456.789, actual_light_idx);
                
                // Apply ReSTIR weight with proper scaling and additional validation
                float effective_weight = clamp(final_reservoir.W, 0.0, 8.0);
                
                // Additional bias correction for high sample counts
                if (final_reservoir.M > 30.0) {
                    effective_weight *= sqrt(30.0 / final_reservoir.M);
                }
                
                // Prevent NaN/infinity in final result
                vec3 final_contribution = light_contribution * effective_weight;
                if (any(isnan(final_contribution)) || any(isinf(final_contribution))) {
                    return vec3(0.0);
                }
                
                return final_contribution;
            }
        }
    }
    
    return vec3(0.0);
}
#endif // USE_RESTIR

void brdf(in Hit hit, in vec3 f, in vec3 e, in float t, in float inside, inout Ray r, inout vec3 mask, inout vec3 acc, inout bool bounceIsSpecular, in float seed, in float bounce){

  vec3 x = hit.pos;
  vec3 n = hit.n;
  vec3 nl = hit.n * inside;

  vec3 _randomDir = getRandomDirection(nl, seed + 7.1*float(u_frame) + 5681.123 + bounce*92.13);

  // material e is also used as a glossiness factor
  vec3 _roughness = e * _randomDir;

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
    vec3 tdir = refract(r.d, nl, nnt);

    r.o = x;

    // total internal reflection - check if refraction failed
    if(length(tdir) == 0.0) {
      r.o += nl*EPSILON;
      r.d = normalize(_roughness + reflect(r.d, nl));
      ++SPEC_BOUNCES;
      bounceIsSpecular = true;
      return;
    }

    // Apply roughness after successful refraction
    tdir = normalize(_roughness + tdir);

    // select either schlick or fresnel approximation
    float Re = mix(schlick(r, nl, nc, nt), fresnel(r, nl, nc, nt, tdir), float(meshes[hit.index].mat.t == REFR_FRESNEL));

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

    float t = intersection(Ray(x + nl*EPSILON, srDir), hit);
    if(t == INFINITY){
      acc += mask * texture(u_cubemap, srDir).rgb * max(0.001, dot(srDir, nl));
    }
#endif

    if(sample_lights){
      if(use_restir && use_mis){
#ifdef USE_RESTIR
        vec3 totalContribution = vec3(0.0);
        float totalWeight = 0.0;
        
        // Determine sampling strategy based on light count
        int num_lights = int(light_index.length());
        bool use_stratified = num_lights > int(8);
        
        if (use_stratified) {
          vec2 restir_seed = vec2(seed + 8652.1*float(u_frame) + bounce*7895.13, seed + 1234.567*float(u_frame) + bounce*9876.54);
          vec3 restirContribution = sampleLightsReSTIR(x, nl, meshes[hit.index].mat, restir_seed);
          
          vec3 misContribution = vec3(0.0);
          int high_importance_lights = min(int(6), num_lights); 
          
          for(int i = 0; i < high_importance_lights; ++i){
            int idx = int(light_index[i]);
            if(idx < 0) continue;
            Mesh light = meshes[idx];
            if(light.mat.t != LIGHT) continue;

            vec3 light_vec = light.pos - x;
            vec3 light_dir = normalize(light_vec);
            float distance_sq = dot(light_vec, light_vec);
            float cos_theta = max(0.0, dot(nl, light_dir));
            float importance = cos_theta * length(light.mat.e) * inversesqrt(distance_sq + 1.0);

            float impStep = step(kImportanceThreshold, importance);
            vec3 lightSample = calcDirectLighting(light, x, nl, seed + kSeedA*float(u_frame) + kSeedB + bounce*kSeedC + float(i)*kSeedD, idx);
            float sampleLen = length(lightSample);
            float sampleStep = step(kImportanceThreshold, sampleLen);
            float valid = impStep * sampleStep;
            float lightPdf = lightSamplingPdf(light, x, light_dir);
            float brdfPdf = cosineHemispherePdf(light_dir, nl);
            float misWeight = powerHeuristic(1.0, lightPdf, 1.0, brdfPdf);
            misContribution += lightSample * misWeight * importance * valid;
          }
          
          if (high_importance_lights > int(0)) {
            misContribution /= float(high_importance_lights);
          }
          
          totalContribution = restirContribution * 0.7 + misContribution * 0.3;
        } else {
          vec3 enhancedMisContribution = vec3(0.0);
          float totalImportance = 0.0;
          
          for(int i = 0; i < num_lights; ++i){
            int idx = int(light_index[i]);
            if(idx < 0) continue;
            Mesh light = meshes[idx];
            if(light.mat.t != LIGHT) continue;

            vec3 light_vec = light.pos - x;
            vec3 light_dir = normalize(light_vec);
            float distance_sq = dot(light_vec, light_vec);
            float cos_theta = max(0.0, dot(nl, light_dir));
            float importance = cos_theta * length(light.mat.e) * inversesqrt(distance_sq + 1.0);
            totalImportance += importance;
          }
          
          for(int i = 0; i < num_lights; ++i){
            int idx = int(light_index[i]);
            if(idx < 0) continue;
            Mesh light = meshes[idx];
            if(light.mat.t != LIGHT) continue;

            vec3 light_vec = light.pos - x;
            vec3 light_dir = normalize(light_vec);
            float distance_sq = dot(light_vec, light_vec);
            float cos_theta = max(0.0, dot(nl, light_dir));
            float importance = cos_theta * length(light.mat.e) * inversesqrt(distance_sq + 1.0);

            float impStep = step(kImportanceThreshold, importance);
            float totalImpStep = step(0.0, totalImportance);
            vec3 lightSample = calcDirectLighting(light, x, nl, seed + kSeedA*float(u_frame) + kSeedB + bounce*kSeedC + float(i)*kSeedD, idx);
            float sampleLen = length(lightSample);
            float sampleStep = step(kImportanceThreshold, sampleLen);
            float valid = impStep * totalImpStep * sampleStep;
            float lightPdf = lightSamplingPdf(light, x, light_dir);
            float brdfPdf = cosineHemispherePdf(light_dir, nl);
            float misWeight = powerHeuristic(1.0, lightPdf, 1.0, brdfPdf);
            float enhancedWeight = misWeight * (importance / max(totalImportance, 1e-6));
            vec2 reservoir_rand = hash2(vec2(seed + float(i) * kSeedD, bounce * 789.123));
            bool is_first = (i == int(0));
            float reservoirValid = mix(float(reservoir_rand.x < enhancedWeight), 1.0, float(is_first));
            enhancedMisContribution += lightSample * enhancedWeight * valid * reservoirValid;
          }
          
          totalContribution = enhancedMisContribution;
        }
        
        acc += totalContribution * mask;
#endif // USE_RESTIR
      } else if(use_restir){
#ifdef USE_RESTIR
        vec2 restir_seed = vec2(seed + 8652.1*float(u_frame) + bounce*7895.13, seed + 1234.567*float(u_frame) + bounce*9876.54);
        vec3 restirContribution = sampleLightsReSTIR(x, nl, meshes[hit.index].mat, restir_seed);
        acc += restirContribution * mask;
#endif // USE_RESTIR
      } else if(use_mis && light_index.length() > 0){
        vec3 misContribution = vec3(0.0);
        
        for(int i = 0; i < int(light_index.length()); ++i){
          if(int(light_index[i]) < 0) continue;
          
          Mesh light = meshes[int(light_index[i])];
          if(light.mat.t != LIGHT) continue;
          
          vec3 lightSample = calcDirectLighting(light, x, nl, seed + 8652.1*float(u_frame) + 5681.123 + bounce*7895.13 + float(i)*123.456, int(light_index[i]));
          
          if(length(lightSample) > 0.001) {
            vec3 lightDir = normalize(((RENDER_MODE != 1) ? light.pos : getAnimatedPosition(light.pos, int(light_index[i]), u_time)) - x);
            float lightPdf = lightSamplingPdf(light, x, lightDir);
            float brdfPdf = cosineHemispherePdf(lightDir, nl);
            float misWeight = powerHeuristic(1.0, lightPdf, 1.0, brdfPdf);
            
            misContribution += lightSample * misWeight;
          }
        }
        
        acc += misContribution * mask;
      } else {
        for(int i = 0; i < int(light_index.length()); ++i){
          if(int(light_index[i]) >= 0) {
            acc += calcDirectLighting(meshes[int(light_index[i])], x, nl, seed + 8652.1*float(u_frame) + 5681.123 + bounce*7895.13, int(light_index[i]))*mask;
          }
        }
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
      } else if(use_mis && depth > 0) {
        // BRDF sampling contribution for MIS
        vec3 lightDir = normalize(hit.pos - r.o);
        float lightPdf = lightSamplingPdf(mesh, r.o, lightDir);
        float brdfPdf = cosineHemispherePdf(lightDir, hit.n);
        
        // MIS weight for BRDF sampling
        float misWeight = powerHeuristic(1.0, brdfPdf, 1.0, lightPdf);
        
        mask *= c;
        acc += mask * e * misWeight;
      } else {
        mask *= c;
        acc += mask*e;
      }
      break;
    }

    brdf(hit, c, e, t, inside, r, mask, acc, bounceIsSpecular, seed, float(depth));

    // Early termination for low contribution
    if(max(mask.x, max(mask.y, mask.z)) < 0.01) break;

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
#ifdef USE_RESTIR
    // Initialize global reservoir
    g_final_reservoir = EMPTY_RESERVOIR;
#endif
    
    vec2 st = 2.0 * gl_FragCoord.xy / u_resolution - 1.;
    float aspect = u_resolution.x/u_resolution.y;

    float seed = hash(dot( gl_FragCoord.xy, vec2(12.9898, 78.233) ) + 1113.1*float(u_frame));

    //camera setup
    float theta = u_camParams.x*RAD;
    float uVLen = tan(theta*0.5);
    float uULen = aspect * uVLen;

    vec3 w = normalize(u_camLookAt);
    vec3 u = normalize(cross(w,vec3(0.0, 1.0, 0.0)));
    vec3 v = cross(u, w);

    // Optimized AA offset calculation
    float r1 = hash(seed+13.271);
    float r2 = hash(seed+63.216);
    
    vec2 d = vec2(
      r1 < 0.5 ? sqrt(r1*2.0) - 1.0 : 1.0 - sqrt(2.0 - r1*2.0),
      r2 < 0.5 ? sqrt(r2*2.0) - 1.0 : 1.0 - sqrt(2.0 - r2*2.0)
    ) / (u_resolution * 0.5) + st;

    vec3 focalPoint = normalize(d.x * u * uULen + d.y * v * uVLen  + w) * u_camParams.z;

    // random point on aperture
    float randomAngle = hash(seed+496.4562) * TWO_PI;
    float randomRadius = hash(seed+249.1686) * u_camParams.y;
    vec3 randomAperturePos = ( cos(randomAngle) * u + sin(randomAngle) * v ) * randomRadius;

    // primary ray
    Ray r = Ray(u_camPos + randomAperturePos, normalize(focalPoint - randomAperturePos));
    
    // Get current frame radiance
    vec3 currentFrame = radiance(r, seed);
    
    // For animated scenes (real-time mode), use temporal accumulation
    // For static scenes, accumulate with previous frames
    if (RENDER_MODE == 1) {
        // Real-time mode with temporal accumulation
        vec3 previousFrame = texelFetch(u_bufferA, ivec2(gl_FragCoord.xy), 0).rgb;
        
        // Exponential moving average for temporal accumulation
        float alpha = 1.0 / float(u_temporalFrames);
        FragColor.rgb = mix(previousFrame, currentFrame, alpha);
    } else {
        // Accumulation mode: add to previous frames
        FragColor.rgb = texelFetch(u_bufferA, ivec2(gl_FragCoord.xy), 0).rgb + currentFrame;
    }
    
#ifdef USE_RESTIR
    // Output ReSTIR reservoir data to multiple render targets
    ReSTIRData = packReservoirMain(g_final_reservoir);
    ReSTIRAux = packReservoirAux(g_final_reservoir);
#else
    // Output empty data when ReSTIR is disabled
    ReSTIRData = vec4(0.0);
    ReSTIRAux = vec4(0.0);
#endif
}
