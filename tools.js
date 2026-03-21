"use strict";

Number.prototype.clamp = function (min, max) {
  return Math.min(Math.max(this, min), max);
};

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
