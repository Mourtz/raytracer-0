'use strict';

class GlslViewport {
  constructor(canvas, opts) {
    opts = opts || {};
    this.canvas = canvas || document.createElement('canvas'); // canvas element
    this.canvas.width = opts.width || 600; // canvas width
    this.canvas.height = opts.height || 600; // canvas height
    this.tile_rendering = opts.tile_rendering || false;

    this.defines = [
      "#define USE_CUBEMAP",
      "//#define USE_PROCEDURAL_SKY",
      "#define USE_BIASED_SAMPLING",
      "//#define USE_BIDIRECTIONAL",
      "//#define USE_RESTIR"
    ];

    this.constants = [
      "const lowp int MAX_BOUNCES = 12;",
      "const lowp int MAX_DIFF_BOUNCES = 4;",
      "const lowp int MAX_SPEC_BOUNCES = 4;",
      "const lowp int MAX_TRANS_BOUNCES = 12;",
      "const lowp int MAX_SCATTERING_EVENTS = 12;",
      "const mediump int MARCHING_STEPS = 128;",
      "const lowp float FUDGE_FACTOR = 0.9;",
      "const bool sample_lights = true;",
      "const bool use_mis = false;",
      "const bool use_restir = false;",
      "const lowp int LIGHT_PATH_LENGTH = 2;",
      "const lowp int RESTIR_SAMPLES = 16;",
      "const lowp int RENDER_MODE = 0;"
    ];

    // Optimized constants for animated scenes
    this.animatedConstants = [
      "const lowp int MAX_BOUNCES = 6;",
      "const lowp int MAX_DIFF_BOUNCES = 2;",
      "const lowp int MAX_SPEC_BOUNCES = 2;",
      "const lowp int MAX_TRANS_BOUNCES = 4;",
      "const lowp int MAX_SCATTERING_EVENTS = 4;",
      "const mediump int MARCHING_STEPS = 64;",
      "const lowp float FUDGE_FACTOR = 0.9;",
      "const bool sample_lights = true;",
      "const bool use_mis = false;",
      "const bool use_restir = true;",
      "const lowp int LIGHT_PATH_LENGTH = 1;",
      "const lowp int RESTIR_SAMPLES = 8;",
      "const lowp int RENDER_MODE = 1;"
    ];

    this.scene = `//--------------------- EUCLIDEAN/QUADRIC PARAMS --------------------------------

const bool U_EUCLIDEAN = false;    // using Euclidean meshes?
const bool U_SPHERE = true;       // using Euclidean sphere?
const bool U_PLANE = true;        // using Euclidean plane?
const bool U_BOX = false;         // using Non-Euclidean box?
const bool U_SDF = true;          // using SDF meshes?

const lowp int NUM_MESHES = 0;
const lowp int NUM_SDFS   = 2;
const lowp int NUM_MODELS = 0;

const Mesh meshes[NUM_MESHES + NUM_SDFS + NUM_MODELS] = Mesh[](
    Mesh(MAT_METAL, SDF, vec3(0.0, -0.49, 0.0), vec4(1.0)),
    Mesh(MAT_WHITE, SDF, vec3(0.0, -1.6, -0.2), vec4(1.5,0.1,1.5,0.0))
);

// light index
const lowp int light_index[1] = int[](-1);`;

    this.sdf_meshes = [
      "sdf_meshes[0] = vec2(sdBox(p-getAnimatedPosition(meshes[NUM_MESHES + 0].pos, NUM_MESHES + 0, u_time), meshes[NUM_MESHES + 0].joker.xyz), 0.0);",
      "sdf_meshes[1] = vec2(sdBox(p-getAnimatedPosition(meshes[NUM_MESHES + 1].pos, NUM_MESHES + 1, u_time), meshes[NUM_MESHES + 1].joker.xyz), 1.0);"
    ];

    this.camera = {
      "origin": new Vector3(0.0, 0.0, 3.0),
      "lookat": new Vector3(0.0, 0.0, -1.0),
      "fov": 90.0,
      "aperture": 0.01,
      "focalLength": 10.0
    };

    // tile opts
    this.tile = [0, 0];
    this.tile_size = [32, 32];
    this.total_tiles = [
      Math.ceil(this.canvas.width / this.tile_size[0]) - 1,
      Math.ceil(this.canvas.height / this.tile_size[1]) - 1
    ];

    console.log("%cInitialiazing GL...", 'color: #00b1ff');
    let gl = this.create3DContext(opts);

    if (!gl) {
      return;
    }

    gl.getExtension('WEBGL_lose_context');
    gl.getExtension('EXT_color_buffer_float');
    gl.getExtension('OES_texture_float_linear');

    this.gl = gl; // GL Instance
    this.loadTime = performance.now(); // load time

    this.shaders = {}; // compiled shaders
    this.images = {}; // loadded iamges
    this.textures = {
      length: 0
    }; // loaded gl textures

    this.frontTarget = {
      framebuffer: this.createFramebuffer([
        {
          name: "front_target_tex",
          width: this.canvas.width,
          height: this.canvas.height,
          color: [gl.RGBA32F, gl.RGBA],
          type: gl.FLOAT
        },
        {
          name: "restir_buffer_tex",
          width: this.canvas.width,
          height: this.canvas.height,
          color: [gl.RGBA32F, gl.RGBA],
          type: gl.FLOAT
        },
        {
          name: "restir_aux_tex",
          width: this.canvas.width,
          height: this.canvas.height,
          color: [gl.RGBA32F, gl.RGBA],
          type: gl.FLOAT
        }
      ]),
      uniforms: {
        "backbuffer": 0,
        "tex0": 1,
        "tex1": 2,
        "tex2": 3,
        "tex3": 4,
        "rng_tex": 5,
        "cubemap": 6,
        "restir_buffer": 7,
        "restir_aux": 8,
        "restir_history1": 9,
        "restir_history1_aux": 10
      }
    }; // front render target

    this.createTexture({
      name: "back_target_tex",
      width: this.canvas.width,
      height: this.canvas.height,
      color: [gl.RGBA32F, gl.RGBA],
      type: gl.FLOAT
    });

    // ReSTIR back buffers for ping-pong
    this.createTexture({
      name: "restir_buffer_back_tex",
      width: this.canvas.width,
      height: this.canvas.height,
      color: [gl.RGBA32F, gl.RGBA],
      type: gl.FLOAT
    });

    this.createTexture({
      name: "restir_aux_tex",
      width: this.canvas.width,
      height: this.canvas.height,
      color: [gl.RGBA32F, gl.RGBA],
      type: gl.FLOAT
    });

    this.createTexture({
      name: "restir_aux_back_tex",
      width: this.canvas.width,
      height: this.canvas.height,
      color: [gl.RGBA32F, gl.RGBA],
      type: gl.FLOAT
    });

    // Enhanced temporal history buffers for better ReSTIR temporal reuse (reduced to 2 levels)
    // History buffer 1 (previous frame)
    this.createTexture({
      name: "restir_history1_tex",
      width: this.canvas.width,
      height: this.canvas.height,
      color: [gl.RGBA32F, gl.RGBA],
      type: gl.FLOAT
    });

    this.createTexture({
      name: "restir_history1_aux_tex",
      width: this.canvas.width,
      height: this.canvas.height,
      color: [gl.RGBA32F, gl.RGBA],
      type: gl.FLOAT
    });

    this.display = {}; // display program
    this.debugDisplay = {}; // debug display program for showing all buffers
    this.showAllBuffers = false; // flag to toggle multi-buffer view
    this.debugDividerPos = [0.5, 0.5]; // divider position for debug view (x, y)

    this.paused = opts.paused || false; // is render loop paused
    this.passes = 0; // current passes
    this.max_passes = opts.max_passes || Infinity; // max passes

    // Animation properties
    this.animatedScene = false; // is current scene animated
    this.animationStartTime = 0; // animation start time
    this.lastAnimationUpdate = 0; // last animation update time
    this.temporalFrames = 5; // number of frames to accumulate for animated scenes

    let vertexbuffer = gl.createBuffer(); // vertex buffer
    gl.bindBuffer(gl.ARRAY_BUFFER, vertexbuffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1.0, -1.0, 1.0, -1.0, -1.0, 1.0, -1.0, 1.0, 1.0, -1.0, 1.0, 1.0]), gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);

    // compile & load shaders
    for (let i = 0; i < opts.shaders.length; i++) {
      opts.shaders[i].string = parseShader(opts.shaders[i].filepath, this);
      this.createShader(opts.shaders[i]);
    }

    //---------------------------- FRONT TARGET PROGRAM

    this.frontTarget.program = this.createProgram([this.shaders["vertex_shader"], this.shaders["raytracing_shader"]]);
    this.updateFrontTarget();

    let sandbox = this;

    // RGBA noise image
    (function () {
      let image = new Image();

      image.onload = function () {
        createImageBitmap(image).then(function (bitmap) {
          sandbox.images["rnd_img"] = bitmap;

          gl.activeTexture(gl.TEXTURE0 + sandbox.frontTarget["uniforms"]["rng_tex"]);
          sandbox.loadTexture({
            name: "rnd_tex"
          }, bitmap);
        });
      };

      image.src = "textures/rgba_noise/rgba_noise256.png";
    })();

    // Images Loader
    let load_images = new Promise(function (resolve, reject) {
      console.log("Loading Images...");
      for (let i = 0; i < opts.textures.length; i++) {
        let image = new Image();

        image.onload = function () {
          createImageBitmap(image).then(function (bitmap) {
            sandbox.images["img" + i] = bitmap;

            gl.activeTexture(gl.TEXTURE0 + sandbox.frontTarget["uniforms"]["tex" + i]);
            sandbox.loadTexture({
              name: "tex" + i
            }, bitmap);

            if (i === opts.textures.length - 1) {
              resolve();
            }
          });
        };

        image.src = opts.textures[i];
      }
    });



    let load_cubemap = new Promise(function (resolve, reject) {
      const targets = [gl.TEXTURE_CUBE_MAP_NEGATIVE_X, gl.TEXTURE_CUBE_MAP_NEGATIVE_Y, gl.TEXTURE_CUBE_MAP_NEGATIVE_Z,
      gl.TEXTURE_CUBE_MAP_POSITIVE_X, gl.TEXTURE_CUBE_MAP_POSITIVE_Y, gl.TEXTURE_CUBE_MAP_POSITIVE_Z];

      let texture = gl.createTexture();

      console.log("Loading Cubemap Images...");
      for (let i = 0; i < opts.cubemap.length; i++) {
        let image = new Image();

        image.onload = function () {
          createImageBitmap(image).then(function (bitmap) {
            sandbox.images["cubemap_img" + i] = bitmap;

            gl.activeTexture(gl.TEXTURE0 + sandbox.frontTarget["uniforms"]["cubemap"]);
            gl.bindTexture(gl.TEXTURE_CUBE_MAP, texture);

            gl.texImage2D(targets[i], 0, gl.RGB, gl.RGB, gl.UNSIGNED_BYTE, bitmap);

            if (i === opts.cubemap.length - 1) {
              gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
              sandbox.pushNewTexture("cubemap", texture);
              resolve();
            }
          });
        };

        image.src = opts.cubemap[i];
      }
    });

    load_images.then(function () {
      console.log("%cLoaded Images...", 'color: #27ff00');
    }).then(load_cubemap).then(function () {
      console.log("%cLoaded Cubemap...", 'color: #27ff00');
    }).then(function () {
      console.log("%cLoaded All Textures...", 'color: #27ff00');
      document.dispatchEvent(new Event('textures_loaded'));
    });

    //---------------------------- DISPLAY PROGRAM

    this.display.program = this.createProgram([this.shaders["vertex_shader"], this.shaders["display_shader"]]);
    gl.useProgram(this.display.program);

    this.display.bufferA_ID = gl.getUniformLocation(this.display.program, "u_bufferA"); // bufferA texture2D
    this.display.contributionID = gl.getUniformLocation(this.display.program, "u_cont"); // current frame

    gl.uniform1i(this.display.bufferA_ID, this.frontTarget["uniforms"]["backbuffer"]);

    //---------------------------- DEBUG DISPLAY PROGRAM

    this.debugDisplay.program = this.createProgram([this.shaders["vertex_shader"], this.shaders["debug_display_shader"]]);
    gl.useProgram(this.debugDisplay.program);

    this.debugDisplay.bufferA_ID = gl.getUniformLocation(this.debugDisplay.program, "u_bufferA");
    this.debugDisplay.restir_buffer_ID = gl.getUniformLocation(this.debugDisplay.program, "u_restir_buffer");
    this.debugDisplay.restir_aux_ID = gl.getUniformLocation(this.debugDisplay.program, "u_restir_aux");
    // Enhanced temporal history buffers for debug display
    this.debugDisplay.restir_history1_ID = gl.getUniformLocation(this.debugDisplay.program, "u_restir_history1");
    this.debugDisplay.restir_history1_aux_ID = gl.getUniformLocation(this.debugDisplay.program, "u_restir_history1_aux");
    this.debugDisplay.restir_history2_ID = gl.getUniformLocation(this.debugDisplay.program, "u_restir_history2");
    this.debugDisplay.restir_history2_aux_ID = gl.getUniformLocation(this.debugDisplay.program, "u_restir_history2_aux");
    this.debugDisplay.contributionID = gl.getUniformLocation(this.debugDisplay.program, "u_cont");
    this.debugDisplay.resolutionID = gl.getUniformLocation(this.debugDisplay.program, "u_resolution");
    this.debugDisplay.frameID = gl.getUniformLocation(this.debugDisplay.program, "u_frame");

    gl.uniform1i(this.debugDisplay.bufferA_ID, this.frontTarget["uniforms"]["backbuffer"]);
    gl.uniform1i(this.debugDisplay.restir_buffer_ID, this.frontTarget["uniforms"]["restir_buffer"]);
    gl.uniform1i(this.debugDisplay.restir_aux_ID, this.frontTarget["uniforms"]["restir_aux"]);
    // Bind enhanced temporal history buffers for debug display
    gl.uniform1i(this.debugDisplay.restir_history1_ID, this.frontTarget["uniforms"]["restir_history1"]);
    gl.uniform1i(this.debugDisplay.restir_history1_aux_ID, this.frontTarget["uniforms"]["restir_history1_aux"]);
    gl.uniform1i(this.debugDisplay.restir_history2_ID, this.frontTarget["uniforms"]["restir_history2"]);
    gl.uniform1i(this.debugDisplay.restir_history2_aux_ID, this.frontTarget["uniforms"]["restir_history2_aux"]);
    gl.uniform2f(this.debugDisplay.resolutionID, this.canvas.width, this.canvas.height);

    if (this.tile_rendering) gl.viewport(0, 0, this.tile_size[0], this.tile_size[1]);

    return this;
  }

  updateFrontTarget() {
    let gl = this.gl;

    gl.useProgram(this.frontTarget.program);

    this.frontTarget.timeID = gl.getUniformLocation(this.frontTarget.program, "u_time"); // time elapsed
    this.frontTarget.frameID = gl.getUniformLocation(this.frontTarget.program, "u_frame");
    this.frontTarget.resolutionID = gl.getUniformLocation(this.frontTarget.program, "u_resolution"); // canvas resolution

    this.frontTarget.camPosID = gl.getUniformLocation(this.frontTarget.program, "u_camPos"); // position
    this.frontTarget.camLookAtID = gl.getUniformLocation(this.frontTarget.program, "u_camLookAt"); // facing position
    this.frontTarget.camParamsID = gl.getUniformLocation(this.frontTarget.program, "u_camParams"); // parameters
    this.frontTarget.temporalFramesID = gl.getUniformLocation(this.frontTarget.program, "u_temporalFrames"); // temporal frames



    this.frontTarget.bufferA_ID = gl.getUniformLocation(this.frontTarget.program, "u_bufferA"); // bufferA texture2D

    this.frontTarget.rnd_tex_ID = gl.getUniformLocation(this.frontTarget.program, "u_rnd_tex"); // random texture

    this.frontTarget.tex0_ID = gl.getUniformLocation(this.frontTarget.program, "u_tex0"); // tex0
    this.frontTarget.tex1_ID = gl.getUniformLocation(this.frontTarget.program, "u_tex1"); // tex1
    this.frontTarget.tex2_ID = gl.getUniformLocation(this.frontTarget.program, "u_tex2"); // tex2
    this.frontTarget.tex3_ID = gl.getUniformLocation(this.frontTarget.program, "u_tex3"); // tex3

    this.frontTarget.cubemap_ID = gl.getUniformLocation(this.frontTarget.program, "u_cubemap"); // cubemap
    this.frontTarget.restir_buffer_ID = gl.getUniformLocation(this.frontTarget.program, "u_restir_buffer"); // ReSTIR buffer
    this.frontTarget.restir_aux_ID = gl.getUniformLocation(this.frontTarget.program, "u_restir_aux"); // ReSTIR auxiliary buffer
    
    // Enhanced temporal history buffers
    this.frontTarget.restir_history1_ID = gl.getUniformLocation(this.frontTarget.program, "u_restir_history1"); // ReSTIR history 1
    this.frontTarget.restir_history1_aux_ID = gl.getUniformLocation(this.frontTarget.program, "u_restir_history1_aux"); // ReSTIR history 1 aux
    this.frontTarget.restir_history2_ID = gl.getUniformLocation(this.frontTarget.program, "u_restir_history2"); // ReSTIR history 2
    this.frontTarget.restir_history2_aux_ID = gl.getUniformLocation(this.frontTarget.program, "u_restir_history2_aux"); // ReSTIR history 2 aux

    gl.uniform2f(this.frontTarget.resolutionID, this.canvas.width, this.canvas.height);

    gl.uniform3f(this.frontTarget.camPosID, this.camera.origin.x, this.camera.origin.y, this.camera.origin.z);
    gl.uniform3f(this.frontTarget.camLookAtID, this.camera.lookat.x, this.camera.lookat.y, this.camera.lookat.z);
    gl.uniform3f(this.frontTarget.camParamsID, this.camera.fov, this.camera.aperture, this.camera.focalLength);

    gl.uniform1i(this.frontTarget.bufferA_ID, this.frontTarget["uniforms"]["backbuffer"]);
    gl.uniform1i(this.frontTarget.rnd_tex_ID, this.frontTarget["uniforms"]["rng_tex"]);
    gl.uniform1i(this.frontTarget.tex0_ID, this.frontTarget["uniforms"]["tex0"]);
    gl.uniform1i(this.frontTarget.tex1_ID, this.frontTarget["uniforms"]["tex1"]);
    gl.uniform1i(this.frontTarget.tex2_ID, this.frontTarget["uniforms"]["tex2"]);
    gl.uniform1i(this.frontTarget.tex3_ID, this.frontTarget["uniforms"]["tex3"]);
    gl.uniform1i(this.frontTarget.cubemap_ID, this.frontTarget["uniforms"]["cubemap"]);
    gl.uniform1i(this.frontTarget.restir_buffer_ID, this.frontTarget["uniforms"]["restir_buffer"]);
    gl.uniform1i(this.frontTarget.restir_aux_ID, this.frontTarget["uniforms"]["restir_aux"]);
    
    // Bind enhanced temporal history buffers
    gl.uniform1i(this.frontTarget.restir_history1_ID, this.frontTarget["uniforms"]["restir_history1"]);
    gl.uniform1i(this.frontTarget.restir_history1_aux_ID, this.frontTarget["uniforms"]["restir_history1_aux"]);
    gl.uniform1i(this.frontTarget.restir_history2_ID, this.frontTarget["uniforms"]["restir_history2"]);
    gl.uniform1i(this.frontTarget.restir_history2_aux_ID, this.frontTarget["uniforms"]["restir_history2_aux"]);
  }

  genRandomTexture() {
    let gl = this.gl;
    let rngData = new Float32Array(this.canvas.width * this.canvas.height * 4);

    for (let i = 0; i < this.canvas.width * this.canvas.height; i++) {
      rngData[i * 4 + 0] = Math.random() * 4194167.0;
      rngData[i * 4 + 1] = Math.random() * 4194167.0;
      rngData[i * 4 + 2] = Math.random() * 4194167.0;
      rngData[i * 4 + 3] = Math.random() * 4194167.0;
    }

    gl.activeTexture(gl.TEXTURE0 + this.frontTarget["uniforms"]["rng_tex"]);
    this.loadTexture({
      name: "rnd_tex",
      width: this.canvas.width,
      height: this.canvas.height,
      color: [gl.RGBA32F, gl.RGBA],
      type: gl.FLOAT
    }, rngData);
  }

  create3DContext(optAttribs) {
    let context = undefined;
    try {
      context = this.canvas.getContext('webgl2', optAttribs);
    } catch (e) { }
    return context;
  }

  resize(value) {
    let gl = this.gl;

    switch (value) {
      case 0:
        this.canvas.width = this.canvas.height = 256 * window.devicePixelRatio;
        break;
      case 1:
        this.canvas.width = this.canvas.height = 512 * window.devicePixelRatio;
        break;
      case 2:
        this.canvas.width = this.canvas.height = 1024 * window.devicePixelRatio;
        break;
      case 3:
        this.canvas.width = this.canvas.height = 2048 * window.devicePixelRatio;
        break;
      case 4:
        this.canvas.width = this.canvas.height = 4096 * window.devicePixelRatio;
        break;
      case 5:
        this.canvas.width = this.canvas.height = 8192 * window.devicePixelRatio;
        break;
      default:
        break;
    }

    this.total_tiles = [
      Math.ceil(this.canvas.width / this.tile_size[0]) - 1,
      Math.ceil(this.canvas.height / this.tile_size[1]) - 1
    ];

    this.createTexture({
      name: "front_target_tex",
      width: this.canvas.width,
      height: this.canvas.height,
      color: [gl.RGBA32F, gl.RGBA],
      type: gl.FLOAT
    });

    this.createTexture({
      name: "back_target_tex",
      width: this.canvas.width,
      height: this.canvas.height,
      color: [gl.RGBA32F, gl.RGBA],
      type: gl.FLOAT
    });

    // Recreate ReSTIR buffers with new size
    this.createTexture({
      name: "restir_buffer_tex",
      width: this.canvas.width,
      height: this.canvas.height,
      color: [gl.RGBA32F, gl.RGBA],
      type: gl.FLOAT
    });

    this.createTexture({
      name: "restir_buffer_back_tex",
      width: this.canvas.width,
      height: this.canvas.height,
      color: [gl.RGBA32F, gl.RGBA],
      type: gl.FLOAT
    });

    this.createTexture({
      name: "restir_aux_tex",
      width: this.canvas.width,
      height: this.canvas.height,
      color: [gl.RGBA32F, gl.RGBA],
      type: gl.FLOAT
    });

    this.createTexture({
      name: "restir_aux_back_tex",
      width: this.canvas.width,
      height: this.canvas.height,
      color: [gl.RGBA32F, gl.RGBA],
      type: gl.FLOAT
    });

    // Recreate enhanced temporal history buffers with new size
    this.createTexture({
      name: "restir_history1_tex",
      width: this.canvas.width,
      height: this.canvas.height,
      color: [gl.RGBA32F, gl.RGBA],
      type: gl.FLOAT
    });

    this.createTexture({
      name: "restir_history1_aux_tex",
      width: this.canvas.width,
      height: this.canvas.height,
      color: [gl.RGBA32F, gl.RGBA],
      type: gl.FLOAT
    });

    this.createTexture({
      name: "restir_history2_tex",
      width: this.canvas.width,
      height: this.canvas.height,
      color: [gl.RGBA32F, gl.RGBA],
      type: gl.FLOAT
    });

    this.createTexture({
      name: "restir_history2_aux_tex",
      width: this.canvas.width,
      height: this.canvas.height,
      color: [gl.RGBA32F, gl.RGBA],
      type: gl.FLOAT
    });

    gl.bindTexture(gl.TEXTURE_2D, null);

    gl.clear(gl.COLOR_BUFFER_BIT);

    gl.useProgram(this.frontTarget.program);
    gl.uniform2f(this.frontTarget.resolutionID, this.canvas.width, this.canvas.height);

    // Update debug display resolution
    gl.useProgram(this.debugDisplay.program);
    gl.uniform2f(this.debugDisplay.resolutionID, this.canvas.width, this.canvas.height);

    if (!this.tile_rendering) gl.viewport(0, 0, this.canvas.width, this.canvas.height);
  }

  createShader(opts) {
    let gl = this.gl;

    let shader = gl.createShader(opts.type == "vert" ? gl.VERTEX_SHADER : gl.FRAGMENT_SHADER);

    gl.shaderSource(shader, opts.string);
    gl.compileShader(shader);

    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw ("could not compile shader: \n" + gl.getShaderInfoLog(shader));

    this.shaders[opts.name] = shader;
    return shader;
  }

  createProgram(shaders) {
    let gl = this.gl;

    let program = gl.createProgram();
    for (let i = 0; i < shaders.length; i++)
      gl.attachShader(program, shaders[i]);

    gl.linkProgram(program);

    if (!gl.getProgramParameter(program, gl.LINK_STATUS))
      throw "Unable to initialize the shader program: \n" + gl.getProgramInfoLog(program);

    return program;
  }

  pushNewTexture(name, texture) {
    if (!this.textures[name]) {
      this.textures.length++;
    }
    this.textures[name] = texture;
  }

  createTexture(opts) {
    let gl = this.gl;
    opts = opts || {};

    if (!(opts.width && opts.height)) throw "Can't create a texture without giving a size !";

    let is3D = opts.depth != undefined;
    opts.depth = opts.depth || 1;

    // color components
    opts.color = opts.color || [];
    let color = [opts.color[0] || gl.RGBA, opts.color[1] || gl.RGBA];

    // data type
    let type = opts.type || gl.UNSIGNED_BYTE;

    // color channels
    let ch = opts.ch || 4;

    let pixels = opts.pixels;
    if (pixels == undefined) pixels = type == gl.UNSIGNED_BYTE ? new Uint8Array(opts.width * opts.height * opts.depth * ch) :
      new Float32Array(opts.width * opts.height * opts.depth * ch);

    let texture = gl.createTexture();
    if (!is3D) {
      gl.bindTexture(gl.TEXTURE_2D, texture);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);

      gl.texImage2D(
        gl.TEXTURE_2D, // target
        0, // level
        color[0], // internal format
        opts.width, // width
        opts.height, // height
        0, // border
        color[1], // format
        type, // type
        pixels // pixels
      );

      if (opts.genMIP) gl.generateMipmap(gl.TEXTURE_2D);
    } else {
      gl.bindTexture(gl.TEXTURE_3D, texture);

      gl.texImage3D(
        gl.TEXTURE_3D, // target
        0, // level
        color[0], // internal format
        opts.width, // width
        opts.height, // height
        opts.depth, // depth
        0, // border
        color[1], // format
        type, // type
        pixels // pixels
      );
    }

    this.pushNewTexture(opts.name || ("tex" + this.textures.length), texture)
    return texture;
  }

  loadTexture(opts, img) {
    let gl = this.gl;
    opts = opts || {};

    let hs = opts.width && opts.height;

    // color components
    opts.color = opts.color || [];
    let color = [opts.color[0] || gl.RGBA, opts.color[1] || gl.RGBA];

    // data type
    let type = opts.type || gl.UNSIGNED_BYTE;

    let texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);

    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);

    if (hs) {
      gl.texImage2D(gl.TEXTURE_2D, 0, color[0], opts.width, opts.height, 0, color[1], type, img);
    } else {
      gl.texImage2D(gl.TEXTURE_2D, 0, color[0], color[1], type, img);
      gl.generateMipmap(gl.TEXTURE_2D);
    }

    this.pushNewTexture(opts.name || ("tex" + this.textures.length), texture);
  }

  createFramebuffer(opts) {
    let gl = this.gl;

    let framebuffer = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);

    if (Array.isArray(opts)) {
      let drawBuffers = [];

      for (let i = 0; i < opts.length; i++) {
        drawBuffers.push(gl.COLOR_ATTACHMENT0 + i);
        gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0 + i, gl.TEXTURE_2D, this.createTexture(opts[i]), 0);
      }

      gl.drawBuffers(drawBuffers);
    } else {
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, this.createTexture(opts), 0);
    }

    let status = gl.checkFramebufferStatus(gl.DRAW_FRAMEBUFFER);
    if (status != gl.FRAMEBUFFER_COMPLETE) {
      console.error('fb status: ' + status.toString(16));
      return;
    }

    gl.bindFramebuffer(gl.FRAMEBUFFER, null);

    return framebuffer;
  }



  updateTile() {
    let gl = this.gl;
    let tile_max = this.tile_size;

    this.passes = 0;

    if (this.tile[0] < this.total_tiles[0]) {
      this.tile[0] += 1;

      if (this.tile[0] == this.total_tiles[0] - 1)
        tile_max[0] = Math.abs(this.canvas.width - (this.total_tiles[0]) * this.tile_size[0]);
    } else {
      this.tile[0] = 0;

      if (this.tile[1] < this.total_tiles[1]) {
        this.tile[1] += 1;

        if (this.tile[1] == this.total_tiles[1] - 1)
          tile_max[1] = Math.abs(this.canvas.height - (this.total_tiles[1]) * this.tile_size[1]);
      } else {
        this.paused = true;
        this.tile[1] = 0;
      }
    }

    let tile_min = [
      this.tile[0] * this.tile_size[0],
      this.tile[1] * this.tile_size[1]
    ];

    gl.viewport(tile_min[0], tile_min[1], tile_max[0], tile_max[1]);
  }

  swapReSTIRBuffers() {
    // Enhanced ReSTIR buffer management with proper 2-frame temporal history
    // History chain: Current -> History1 -> History2 -> (discard)
    
    // Store current history1 as history2 (move older frame further back)
    let temp_history2 = this.textures["restir_history2_tex"];
    let temp_history2_aux = this.textures["restir_history2_aux_tex"];
    
    // History1 becomes History2
    this.textures["restir_history2_tex"] = this.textures["restir_history1_tex"];
    this.textures["restir_history2_aux_tex"] = this.textures["restir_history1_aux_tex"];
    
    // Current back buffer becomes History1
    this.textures["restir_history1_tex"] = this.textures["restir_buffer_back_tex"];
    this.textures["restir_history1_aux_tex"] = this.textures["restir_aux_back_tex"];
    
    // Reuse old history2 buffers as new back buffers (efficient recycling)
    this.textures["restir_buffer_back_tex"] = temp_history2;
    this.textures["restir_aux_back_tex"] = temp_history2_aux;
    
    // Standard front/back swap for current frame
    let temp_restir = this.textures["restir_buffer_tex"];
    let temp_aux = this.textures["restir_aux_tex"];

    this.textures["restir_buffer_tex"] = this.textures["restir_buffer_back_tex"];
    this.textures["restir_aux_tex"] = this.textures["restir_aux_back_tex"];

    this.textures["restir_buffer_back_tex"] = temp_restir;
    this.textures["restir_aux_back_tex"] = temp_aux;
  }

  clear() {
    let gl = this.gl;

    let empty_tex = new Float32Array(this.canvas.width * this.canvas.height * 4);

    gl.bindTexture(gl.TEXTURE_2D, this.textures["back_target_tex"]);
    gl.texImage2D(
      gl.TEXTURE_2D, // target
      0, // level
      gl.RGBA32F, // internal format
      this.canvas.width, // width
      this.canvas.height, // height
      0, // border
      gl.RGBA, // format
      gl.FLOAT, // type
      empty_tex // pixels
    );

    gl.bindTexture(gl.TEXTURE_2D, this.textures["front_target_tex"]);
    gl.texImage2D(
      gl.TEXTURE_2D, // target
      0, // level
      gl.RGBA32F, // internal format
      this.canvas.width, // width
      this.canvas.height, // height
      0, // border
      gl.RGBA, // format
      gl.FLOAT, // type
      empty_tex // pixels
    );

    // Clear ReSTIR buffers as well
    gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_buffer_tex"]);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, this.canvas.width, this.canvas.height, 0, gl.RGBA, gl.FLOAT, empty_tex);

    gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_buffer_back_tex"]);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, this.canvas.width, this.canvas.height, 0, gl.RGBA, gl.FLOAT, empty_tex);

    gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_aux_tex"]);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, this.canvas.width, this.canvas.height, 0, gl.RGBA, gl.FLOAT, empty_tex);

    gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_aux_back_tex"]);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, this.canvas.width, this.canvas.height, 0, gl.RGBA, gl.FLOAT, empty_tex);

    // Clear enhanced temporal history buffers
    gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_history1_tex"]);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, this.canvas.width, this.canvas.height, 0, gl.RGBA, gl.FLOAT, empty_tex);

    gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_history1_aux_tex"]);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, this.canvas.width, this.canvas.height, 0, gl.RGBA, gl.FLOAT, empty_tex);

    gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_history2_tex"]);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, this.canvas.width, this.canvas.height, 0, gl.RGBA, gl.FLOAT, empty_tex);

    gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_history2_aux_tex"]);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, this.canvas.width, this.canvas.height, 0, gl.RGBA, gl.FLOAT, empty_tex);

    gl.clear(gl.COLOR_BUFFER_BIT);
  }

  toggleBufferDisplay() {
    this.showAllBuffers = !this.showAllBuffers;
  }

  updateDividerPosition(x, y) {
    this.debugDividerPos[0] = x;
    this.debugDividerPos[1] = y;
    
    // Update the uniform if debug display is active
    if (this.showAllBuffers) {
      let gl = this.gl;
      gl.useProgram(this.debugDisplay.program);
      // Note: u_divider uniform removed - divider functionality disabled
    }
  }

  resetDebugDivider() {
    this.debugDividerPos[0] = 0.5;
    this.debugDividerPos[1] = 0.5;
    
    // Update the uniform if debug display is active
    if (this.showAllBuffers) {
      let gl = this.gl;
      gl.useProgram(this.debugDisplay.program);
      // Note: u_divider uniform removed - divider functionality disabled
    }
  }

  // Method to help debug ReSTIR by toggling it on/off
  toggleReSTIR() {
    // Force enable ReSTIR for debugging
    this.defines[4] = "#define USE_RESTIR";
    this.constants[9] = "const bool use_restir = true;";
    this.constants[7] = "const bool sample_lights = true;";
    
    console.log("%cForced ReSTIR enabled for debugging", 'color: #ff6b35; font-weight: bold');
    
    // Update UI to reflect forced state
    $("#use_restir").prop('checked', true);
    $("#sample_lights").prop('checked', true);
    
    // Mark for recompilation
    $("#compileBtn").css("background", "linear-gradient(135deg, #dc2626, #ef4444)");
    
    console.log("%cNote: You need to recompile the shader and restart rendering to see changes", 'color: #ff6b35; font-weight: bold');
  }

  // Get ReSTIR debugging info for the UI
  getReSTIRDebugInfo() {
    return {
      isReSTIREnabled: this.animatedScene, // ReSTIR is more active in animated mode
      temporalFrames: this.temporalFrames,
      passes: this.passes,
      animatedMode: this.animatedScene,
      debugViewActive: this.showAllBuffers
    };
  }

  setAnimatedMode(isAnimated) {
    this.animatedScene = isAnimated;
    
    if (isAnimated) {
      // Apply animated constants for optimized performance
      this.constants = [...this.animatedConstants];
      
      // Enable ReSTIR define for animated scenes
      this.defines[4] = "#define USE_RESTIR";
      
      this.animationStartTime = performance.now();
      this.lastAnimationUpdate = this.animationStartTime;
      console.log("%cAnimated mode enabled - using optimized ReSTIR settings", 'color: #00b1ff');
      console.log("%cReduced bounces and samples for real-time performance", 'color: #00b1ff');
      console.log("%cReSTIR temporal accumulation active", 'color: #00b1ff');
      console.log("%cApplied animated constants:", 'color: #00b1ff', this.constants);
    } else {
      // Restore default constants for high-quality static rendering
      this.constants = [
        "const lowp int MAX_BOUNCES = 12;",
        "const lowp int MAX_DIFF_BOUNCES = 4;",
        "const lowp int MAX_SPEC_BOUNCES = 4;",
        "const lowp int MAX_TRANS_BOUNCES = 12;",
        "const lowp int MAX_SCATTERING_EVENTS = 12;",
        "const mediump int MARCHING_STEPS = 128;",
        "const lowp float FUDGE_FACTOR = 0.9;",
        "const bool sample_lights = true;",
        "const bool use_mis = false;",
        "const bool use_restir = false;",
        "const lowp int LIGHT_PATH_LENGTH = 2;",
        "const lowp int RESTIR_SAMPLES = 16;",
        "const lowp int RENDER_MODE = 0;"
      ];
      
      // Disable ReSTIR for static scenes by default
      this.defines[4] = "//#define USE_RESTIR";
      
      console.log("%cStatic mode enabled - using high-quality settings", 'color: #00b1ff');
      console.log("%cProgressive accumulation for noise reduction", 'color: #00b1ff');
    }
    
    // Reset the accumulation when switching modes
    this.clear();
  }

  // RENDER FUNCTION
  render() {
    let time = performance.now() - this.loadTime;
    let gl = this.gl;

    // Handle animation for animated scenes
    if (this.animatedScene) {
      let currentTime = performance.now();

      // For real-time rendering, we don't accumulate color but we still need
      // frame counting for ReSTIR temporal reuse
      if (currentTime - this.lastAnimationUpdate > 16) { // ~60 FPS
        this.lastAnimationUpdate = currentTime;
      }

      // Keep passes reasonable for ReSTIR temporal history
      // Use fewer passes for animated scenes to maintain performance
      if (this.passes > this.temporalFrames * 2) {
        this.passes = this.temporalFrames; // Reset based on temporal accumulation setting
      }
    }

    //------------------ CUSTOM SHADER (RAYTRACER) ----------------------
    gl.useProgram(this.frontTarget.program);

    gl.uniform1ui(this.frontTarget.frameID, ++this.passes);
    gl.uniform1f(this.frontTarget.timeID, time);


    // Set temporal accumulation frames for animated scenes
    gl.uniform1i(this.frontTarget.temporalFramesID, this.temporalFrames);

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.textures["back_target_tex"]);

    // Bind ReSTIR buffers (read from back buffers to avoid feedback loop)
    gl.activeTexture(gl.TEXTURE0 + this.frontTarget["uniforms"]["restir_buffer"]);
    gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_buffer_back_tex"] || this.textures["restir_buffer_tex"]);

    gl.activeTexture(gl.TEXTURE0 + this.frontTarget["uniforms"]["restir_aux"]);
    gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_aux_back_tex"] || this.textures["restir_aux_tex"]);

    // Bind enhanced temporal history buffers for multi-frame ReSTIR
    gl.activeTexture(gl.TEXTURE0 + this.frontTarget["uniforms"]["restir_history1"]);
    gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_history1_tex"]);

    gl.activeTexture(gl.TEXTURE0 + this.frontTarget["uniforms"]["restir_history1_aux"]);
    gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_history1_aux_tex"]);

    gl.activeTexture(gl.TEXTURE0 + this.frontTarget["uniforms"]["restir_history2"]);
    gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_history2_tex"]);

    gl.activeTexture(gl.TEXTURE0 + this.frontTarget["uniforms"]["restir_history2_aux"]);
    gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_history2_aux_tex"]);

    // Render custom shader to front buffer (MRT: color + ReSTIR + ReSTIR aux)
    gl.bindFramebuffer(gl.FRAMEBUFFER, this.frontTarget.framebuffer);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, this.textures["front_target_tex"], 0);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT1, gl.TEXTURE_2D, this.textures["restir_buffer_tex"], 0);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT2, gl.TEXTURE_2D, this.textures["restir_aux_tex"], 0);
    gl.drawArrays(gl.TRIANGLES, 0, 6);

    //------------------ SCREEN SHADER (DISPLAY) ------------------------

    if (this.showAllBuffers) {
      gl.useProgram(this.debugDisplay.program);

      let contribution = this.animatedScene ? 1.0 : 1.0 / this.passes;
      gl.uniform1f(this.debugDisplay.contributionID, contribution);

      gl.uniform1ui(this.debugDisplay.frameID, this.passes);

      gl.activeTexture(gl.TEXTURE0 + this.frontTarget["uniforms"]["backbuffer"]);
      gl.bindTexture(gl.TEXTURE_2D, this.textures["front_target_tex"]);

      gl.activeTexture(gl.TEXTURE0 + this.frontTarget["uniforms"]["restir_buffer"]);
      gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_buffer_tex"]);

      gl.activeTexture(gl.TEXTURE0 + this.frontTarget["uniforms"]["restir_aux"]);
      gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_aux_tex"]);

      // Bind enhanced temporal history buffers for debug display
      gl.activeTexture(gl.TEXTURE0 + this.frontTarget["uniforms"]["restir_history1"]);
      gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_history1_tex"]);

      gl.activeTexture(gl.TEXTURE0 + this.frontTarget["uniforms"]["restir_history1_aux"]);
      gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_history1_aux_tex"]);

      gl.activeTexture(gl.TEXTURE0 + this.frontTarget["uniforms"]["restir_history2"]);
      gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_history2_tex"]);

      gl.activeTexture(gl.TEXTURE0 + this.frontTarget["uniforms"]["restir_history2_aux"]);
      gl.bindTexture(gl.TEXTURE_2D, this.textures["restir_history2_aux_tex"]);

    } else {
      gl.useProgram(this.display.program);

      if (this.animatedScene) {
        gl.uniform1f(this.display.contributionID, 1.0);

        // Bind the temporally accumulated result (front target)
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, this.textures["front_target_tex"]);
      } else {
        gl.uniform1f(this.display.contributionID, 1.0 / this.passes);

        // Bind the progressively accumulated result (front target)
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, this.textures["front_target_tex"]);
      }
    }

    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.drawArrays(gl.TRIANGLES, 0, 6);

    this.swapReSTIRBuffers();

    let tmp = this.textures["back_target_tex"];
    this.textures["back_target_tex"] = this.textures["front_target_tex"];
    this.textures["front_target_tex"] = tmp;
  }
}
