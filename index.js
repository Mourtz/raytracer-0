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
      "//#define USE_BIDIRECTIONAL"
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
      "const lowp int LIGHT_PATH_LENGTH = 2;"
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
      "sdf_meshes[0] = vec2(sdBox(p-meshes[NUM_MESHES + 0].pos, meshes[NUM_MESHES + 0].joker.xyz), 0.0);",
      "sdf_meshes[1] = vec2(sdBox(p-meshes[NUM_MESHES + 1].pos, meshes[NUM_MESHES + 1].joker.xyz), 1.0);"
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
    //    this.debug_shader = gl.getExtension('WEBGL_debug_shaders');

    this.gl = gl; // GL Instance
    this.loadTime = performance.now(); // load time

    this.shaders = {}; // compiled shaders
    this.images = {}; // loadded iamges
    this.textures = {
      length: 0
    }; // loaded gl textures

    this.frontTarget = {
      framebuffer: this.createFramebuffer({
        name: "front_target_tex",
        width: this.canvas.width,
        height: this.canvas.height,
        color: [gl.RGBA32F, gl.RGBA],
        type: gl.FLOAT
      }),
      uniforms: {
        "backbuffer": 0,
        "tex0": 1,
        "tex1": 2,
        "tex2": 3,
        "tex3": 4,
        "rng_tex": 5,
        "cubemap": 6
      }
    }; // front render target

    this.createTexture({
      name: "back_target_tex",
      width: this.canvas.width,
      height: this.canvas.height,
      color: [gl.RGBA32F, gl.RGBA],
      type: gl.FLOAT
    });

    this.display = {}; // display program

    this.paused = opts.paused || false; // is render loop paused
    this.passes = 0; // current passes
    this.max_passes = opts.max_passes || Infinity; // max passes

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

    //    this.genRandomTexture();
    //    gl.activeTexture(gl.TEXTURE0);

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

    if (this.tile_rendering) gl.viewport(0, 0, this.tile_size[0], this.tile_size[1]);

    //------------ EVENTS ------------
    let mouse = {
      x: 0,
      y: 0
    }; // mouse position

    //------------------------------- KEYBOARD --------------------------------
    //    this.keyboardTexVal = new Uint8Array(256);
    //    this.keyboardTex = this.createTexture({
    //      name: "keyboard_tex",
    //      width: 256,
    //      height: 1,
    //      color: [gl.R8, gl.RED],
    //      ch: 1,
    //      pixels: this.keyboardTexVal
    //    });
    //    let keyboardTexPos = this.textures["keyboard_tex"]["pos"];
    //    gl.uniform1i(this.frontTarget.keyboardID, keyboardTexPos);

    //    document.addEventListener("keyup", function (evt) {
    //      sandbox.keyboardTexVal[evt.keyCode] = 0;
    //
    //      gl.activeTexture(gl.TEXTURE0 + keyboardTexPos);
    //      gl.bindTexture(gl.TEXTURE_2D, sandbox.textures["keyboard_tex"]["tex"]);
    //      gl.texImage2D(gl.TEXTURE_2D, 0, gl.R8, 256, 1, 0, gl.RED, gl.UNSIGNED_BYTE, sandbox.keyboardTexVal);
    //
    //    });

    //------------------------- SDF SAMPLED ON A GRID -------------------------

    //    let sdf0 = parseSDF("models/armadilo.sdf");
    //    console.log(sdf0);
    //    this.sdfTex = this.createTexture({
    //      name: "sdf0",
    //      width: sdf0.dimensions[0],
    //      height: sdf0.dimensions[1],
    //      depth: sdf0.dimensions[2],
    //      color: [gl.R32F, gl.RED],
    //      type: gl.FLOAT,
    //      ch: 1,
    //      pixels: sdf0.values
    //    });
    //    gl.uniform1i(this.frontTarget.sdf0_texID, this.textures["sdf0"]["pos"]);
    //
    //    // create sdf0 AABB Buffer
    //    let sdf0_aabb = new Float32Array([
    //      sdf0.bb_min[0], sdf0.bb_min[1], sdf0.bb_min[2], 0.0,
    //      sdf0.bb_max[0], sdf0.bb_max[1], sdf0.bb_max[2], 0.0,
    //    ]);
    //
    //    let sdf0_aabbBuffer = gl.createBuffer();
    //    gl.bindBuffer(gl.UNIFORM_BUFFER, sdf0_aabbBuffer);
    //    gl.bufferData(gl.UNIFORM_BUFFER, sdf0_aabb, gl.STATIC_DRAW);
    //    gl.bufferSubData(gl.UNIFORM_BUFFER, 0, sdf0_aabb);
    //    gl.bindBuffer(gl.UNIFORM_BUFFER, null);
    //
    //    gl.uniformBlockBinding(this.frontTarget.program, this.frontTarget.sdf0_aabbID, 0);
    //    gl.bindBufferBase(gl.UNIFORM_BUFFER, 0, sdf0_aabbBuffer);

    //--------------------------------- MOUSE ---------------------------------

    // mouse events
    //    this.canvas.onmouseup = function () {
    //      gl.uniform1i(sandbox.frontTarget.mouse_downID, 0);
    //    };
    //    this.canvas.onmousedown = function () {
    //      gl.uniform1i(sandbox.frontTarget.mouse_downID, 1);
    //    };
    //    document.addEventListener('mousemove', (e) => {
    //      mouse.x = e.clientX || e.pageX;
    //      mouse.y = e.clientY || e.pageY;
    //    }, false);

    // on GL context lost
    this.canvas.addEventListener("webglcontextlost", function (e) {
      alert("Your gpu cant bear this buddy ;(");
      EXT.restoreContext();
    }, false);

    //    this.setMouse(mouse);

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

    //    this.frontTarget.mouseID = gl.getUniformLocation(this.frontTarget.program, "u_mouse"); // mouse position
    //    this.frontTarget.mouse_downID = gl.getUniformLocation(this.frontTarget.program, "u_mouse_down"); // is LMB down
    //    this.frontTarget.keyboardID = gl.getUniformLocation(this.frontTarget.program, "u_keyboard"); // is LMB down

    //    this.frontTarget.sdf0_texID = gl.getUniformLocation(this.frontTarget.program, "u_sdf0"); // canvas resolution
    //    this.frontTarget.sdf0_aabbID = gl.getUniformBlockIndex(this.frontTarget.program, "u_sdf0_aabb"); // sdf0 AABB

    this.frontTarget.bufferA_ID = gl.getUniformLocation(this.frontTarget.program, "u_bufferA"); // bufferA texture2D

    this.frontTarget.rnd_tex_ID = gl.getUniformLocation(this.frontTarget.program, "u_rnd_tex"); // random texture

    this.frontTarget.tex0_ID = gl.getUniformLocation(this.frontTarget.program, "u_tex0"); // tex0
    this.frontTarget.tex1_ID = gl.getUniformLocation(this.frontTarget.program, "u_tex1"); // tex1
    this.frontTarget.tex2_ID = gl.getUniformLocation(this.frontTarget.program, "u_tex2"); // tex2
    this.frontTarget.tex3_ID = gl.getUniformLocation(this.frontTarget.program, "u_tex3"); // tex3

    this.frontTarget.cubemap_ID = gl.getUniformLocation(this.frontTarget.program, "u_cubemap"); // cubemap

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

    gl.activeTexture(gl.TEXTURE0 + this.frontTarget["uniforms"]["rngData"]);
    this.loadTexture({
      name: "rngData",
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
    gl.bindTexture(gl.TEXTURE_2D, null);

    gl.clear(gl.COLOR_BUFFER_BIT);

    gl.useProgram(this.frontTarget.program);
    gl.uniform2f(this.frontTarget.resolutionID, this.canvas.width, this.canvas.height);

    gl.useProgram(this.display.program);
    gl.uniform2f(this.display.resolutionID, this.canvas.width, this.canvas.height);

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

  setScene() {
    let gl = this.gl;

    let models = [];

    models[0] = models[1] = models[2] = newModel(JSON.parse(fetchHTTP('/models/null.json')));

    models[0] = newModel(JSON.parse(fetchHTTP('/models/gem.json')), {
      color: [1., 1., 1.],
      position: [0., -.5, 0.],
      backface_culling: 1,
      type: 4
    });

    //        let mesh = parseMesh(JSON.parse(fetchHTTP('/models/gem2.json')));
    //        let bvh = new BVH();
    //        bvh.Build(mesh);
    //        console.log(bvh);

    let sandbox = this;
    models.forEach(function (model, i) {
      //------------------------------------------------------------------------
      //> model Texture
      //------------------------------------------------------------------------
      let modelTexture = gl.createTexture();
      gl.activeTexture(gl.TEXTURE0 + sandbox.textures.length);
      gl.bindTexture(gl.TEXTURE_2D_ARRAY, modelTexture);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
      gl.texImage3D(
        gl.TEXTURE_2D_ARRAY,
        0,
        gl.RGB32F,
        model.buffer_s,
        model.buffer_s,
        4,
        0,
        gl.RGB,
        gl.FLOAT,
        model.buffer);
      gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.uniform1i(gl.getUniformLocation(sandbox.frontTarget.program, "u_model" + i), sandbox.textures.length);

      sandbox.pushNewTexture("model" + i, modelTexture);

      //------------------------------------------------------------------------
      //> indices
      //------------------------------------------------------------------------
      let indicesTexture = gl.createTexture();
      gl.activeTexture(gl.TEXTURE0 + sandbox.textures.length);
      gl.bindTexture(gl.TEXTURE_2D, indicesTexture);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB32UI, model.indices_s, model.indices_s, 0, gl.RGB_INTEGER, gl.UNSIGNED_INT, model.indices);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.uniform1i(gl.getUniformLocation(sandbox.frontTarget.program, "u_indices" + i), sandbox.textures.length);

      sandbox.pushNewTexture("indices" + i, indicesTexture);
    });

  }

  setMouse(mouse) {
    let rect = this.canvas.getBoundingClientRect();
    if (mouse &&
      mouse.x && mouse.x >= rect.left && mouse.x <= rect.right &&
      mouse.y && mouse.y >= rect.top && mouse.y <= rect.bottom) {

      this.gl.uniform2f(this.frontTarget.mouseID, mouse.x - rect.left, this.canvas.height - (mouse.y - rect.top));
    }
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

    gl.clear(gl.COLOR_BUFFER_BIT);
  }

  // RENDER FUNCTION
  render() {
    let time = performance.now() - this.loadTime;
    let gl = this.gl;

    //------------------ CUSTOM SHADER (RAYTRACER) ----------------------
    gl.useProgram(this.frontTarget.program);

    gl.uniform1ui(this.frontTarget.frameID, ++this.passes);
    gl.uniform1f(this.frontTarget.timeID, time);

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.textures["back_target_tex"]);

    // Render custom shader to front buffer
    gl.bindFramebuffer(gl.FRAMEBUFFER, this.frontTarget.framebuffer);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, this.textures["front_target_tex"], 0);
    gl.drawArrays(gl.TRIANGLES, 0, 6);

    //------------------ SCREEN SHADER (DISPLAY) ------------------------

    gl.useProgram(this.display.program);

    gl.uniform1f(this.display.contributionID, 1.0 / this.passes);

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.textures["front_target_tex"]);

    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.drawArrays(gl.TRIANGLES, 0, 6);

    // texture ping pong
    let tmp = this.textures["back_target_tex"];
    this.textures["back_target_tex"] = this.textures["front_target_tex"];
    this.textures["front_target_tex"] = tmp;
  }
}
