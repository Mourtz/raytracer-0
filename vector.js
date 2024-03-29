let Vector2 = /** @class */ (function () {
  function Vector2(x, y) {
    if (x === void 0) {
      x = 0.0;
    }
    if (y === void 0) {
      y = 0.0;
    }
    this.x = x;
    this.y = y;
  }

  Vector2.prototype.get = function (axis) {
    switch (axis) {
      case 1:
        return this.x;
      case 2:
        return this.y;
    }
  };

  Object.defineProperty(Vector2.prototype, "glData", {
    get: function () {
      return new Float32Array([this.x, this.y]);
    },
    enumerable: true,
    configurable: true
  });

  return Vector2;
}());

let Vector4 = /** @class */ (function () {
  function Vector4(x, y, z, w) {
    if (x === void 0) {
      x = 0.0;
    }
    if (y === void 0) {
      y = 0.0;
    }
    if (z === void 0) {
      z = 0.0;
    }
    if (w === void 0) {
      w = 0.0;
    }
    this.x = x;
    this.y = y;
    this.z = z;
    this.w = w;
  }

  Vector4.prototype.get = function (axis) {
    switch (axis) {
      case 1:
        return this.x;
      case 2:
        return this.y;
      case 3:
        return this.z;
      case 4:
        return this.w;
    }
  };

  Object.defineProperty(Vector4.prototype, "glData", {
    get: function () {
      return new Float32Array([this.x, this.y, this.z, this.w]);
    },
    enumerable: true,
    configurable: true
  });

  return Vector4;
}());

let Vector3 = (function () {
  function Vector3(x, y, z) {
    if (x === void 0) {
      x = 0.0;
    }
    if (y === void 0) {
      y = 0.0;
    }
    if (z === void 0) {
      z = 0.0;
    }
    this.x = x;
    this.y = y;
    this.z = z;
  }

  Object.defineProperty(Vector3.prototype, "glData", {
    get: function () {
      return new Float32Array([this.x, this.y, this.z]);
    },
    enumerable: true,
    configurable: true
  });

  Vector3.prototype.add = function (b) {
    return new Vector3(this.x + b.x, this.y + b.y, this.z + b.z);
  };

  Vector3.prototype.addScalar = function (f) {
    return new Vector3(this.x + f, this.y + f, this.z + f);
  };

  Vector3.prototype.sub = function (b) {
    return new Vector3(this.x - b.x, this.y - b.y, this.z - b.z);
  };

  Vector3.prototype.subScalar = function (f) {
    return new Vector3(this.x - f, this.y - f, this.z - f);
  };

  Vector3.prototype.mul = function (b) {
    return new Vector3(this.x * b.x, this.y * b.y, this.z * b.z);
  };

  Vector3.prototype.mulScalar = function (f) {
    return new Vector3(this.x * f, this.y * f, this.z * f);
  };

  Vector3.prototype.div = function (b) {
    return new Vector3(this.x / b.x, this.y / b.y, this.z / b.z);
  };

  Vector3.prototype.divScalar = function (f) {
    return new Vector3(this.x / f, this.y / f, this.z / f);
  };

  Vector3.prototype.dot = function (b) {
    return (this.x * b.x) + (this.y * b.y) + (this.z * b.z);
  };

  Vector3.prototype.length = function () {
    return Math.sqrt((this.x * this.x) + (this.y * this.y) + (this.z * this.z));
  };

  Vector3.prototype.normalize = function () {
    let d = this.length();
    return new Vector3(this.x / d, this.y / d, this.z / d);
  };

  Vector3.prototype.op_remainder = function (b) {
    return new Vector3(this.y * b.z - this.z * b.y, this.z * b.x - this.x * b.z, this.x * b.y - this.y * b.x);
  };

  Vector3.prototype.maximize = function (b) {
    return new Vector3(this.x > b.x ? this.x : b.x, this.y > b.y ? this.y : b.y, this.z > b.z ? this.z : b.z);
  };

  Vector3.prototype.minimize = function (b) {
    return new Vector3(this.x < b.x ? this.x : b.x, this.y < b.y ? this.y : b.y, this.z < b.z ? this.z : b.z);
  };

  Vector3.prototype.get = function (axis) {
    switch (axis) {
      case 1:
        return this.x;
      case 2:
        return this.y;
      case 3:
        return this.z;
    }
  };

  return Vector3;
}());

//let tes = new Vector3(1,2,3);
//let tes1 = new Vector3(4,5,6);
