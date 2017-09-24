"use strict";

function fillArray(array, type, num) {
  for (let i = 0; i < num; i++) {
    array[i] = new type();
  }
  return array;
}

Number.prototype.clamp = function (min, max) {
  return Math.min(Math.max(this, min), max);
};

function vec4array_to_f32Array(array) {
  let i = 0;
  let j = 0;
  let f32 = new Float32Array(array.length * 4);
  while (i < array.length) {
    let v = array[i];
    f32[j] = v.x;
    f32[j + 1] = v.y;
    f32[j + 2] = v.z;
    f32[j + 3] = v.w;
    i = i + 1;
    j = j + 4;
  }
  return f32;
}

function vec3array_to_f32Array(array) {
  let i = 0;
  let j = 0;
  let f32 = new Float32Array(array.length * 3);
  while (i < array.length) {
    let v = array[i];
    f32[j] = v.x;
    f32[j + 1] = v.y;
    f32[j + 2] = v.z;
    i = i + 1;
    j = j + 3;
  }
  return f32;
}

function vec2array_to_f32Array(array) {
  let i = 0;
  let j = 0;
  let f32 = new Float32Array(array.length * 2);
  while (i < array.length) {
    let v = array[i];
    f32[j] = v.x;
    f32[j + 1] = v.y;
    i = i + 1;
    j = j + 2;
  }
  return f32;
}

function sgn(v) {
  if (v > 0.0) {
    return 1.0;
  } else {
    return -1.0;
  }
}

function fetchHTTP(url) {
  let request = new XMLHttpRequest();
  let response;

  request.onreadystatechange = function () {
    if (request.readyState === 4 && request.status === 200) {
      response = request.responseText;
    }
  }
  request.open('GET', url, false);
  request.overrideMimeType("text/plain");
  request.send(null);
  return response;
}

function parseShader(filepath, sandbox) {
  let constants = sandbox.constants;
  let defines = sandbox.defines;
  let scene = sandbox.scene;
  let sdf_meshes = sandbox.sdf_meshes;

  if (!filepath) return console.error("You got to give a filepath");

  let string = fetchHTTP(filepath);
  let line = string.split("\n");

  for (let i = 0; i < line.length; i++) {
    if (line[i].charAt(0) == "#") {
      if (line[i].slice(0, 8) == "#include") {
        let index = line[i].indexOf("'")
        if (index == -1) index = line[i].indexOf('"');
        if (index == -1) return console.error();
        filepath = line[i].slice(index + 1);

        index = filepath.indexOf("'")
        if (index == -1) index = filepath.indexOf('"');
        if (index == -1) return console.error();
        filepath = filepath.slice(0, index);

        line[i] = parseShader(filepath);
      } else if (defines && constants && line[i].slice(0, 10) == "#constants") {
        line[i] = defines.concat(constants).join("\n");
      } else if (scene && line[i].slice(0, 6) == "#scene") {
        line[i] = scene;
      } else if (sdf_meshes && line[i].slice(0, 11) == "#sdf_meshes") {
        line[i] = sdf_meshes.join("\n");
      } else {
        console.error();
      }
    }
  }

  let result = line.join("\n");
  return result;
}

function parseSDF(filepath) {
  if (!filepath) return console.error("You got to give a filepath");

  let string = fetchHTTP(filepath);
  let line = string.split("\n");

  let dimensions = line[0].split(" ");
  let bb_min = line[1].split(" ");
  let bb_max = line[2].split(" ");

  if (true) {
    return {
      "dimensions": dimensions,
      "bb_min": bb_min,
      "bb_max": bb_max,
      "values": new Float32Array(line.slice(3))
    };
  } else {
    return new Float32Array(dimensions.concat(bb_min).concat(bb_max).concat(line.slice(3)));
  }
}

function elementInViewport(el) {
  let top = el.offsetTop;
  let left = el.offsetLeft;
  let width = el.offsetWidth;
  let height = el.offsetHeight;
  while (el.offsetParent) {
    el = el.offsetParent;
    top += el.offsetTop;
    left += el.offsetLeft;
  }
  return (top < (window.pageYOffset + window.innerHeight) && left < (window.pageXOffset + window.innerWidth) && (top + height) > window.pageYOffset && (left + width) > window.pageXOffset);
}

window.requestAnimFrame = window.requestAnimationFrame || window.webkitRequestAnimationFrame || window.mozRequestAnimationFrame || window.oRequestAnimationFrame || window.msRequestAnimationFrame || function (callback) {
  window.setTimeout(callback, 1e3 / 60);
};

window.cancelAnimFrame = window.cancelAnimationFrame || window.mozCancelAnimationFrame;
