/*! wave-gradient (MIT) https://github.com/sa3dany/wave-gradient — Copyright (c) 2022 Mohamed ElSaadany */
"use strict";
var WaveGradientModule = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // src/wave-gradient.js
  var wave_gradient_exports = {};
  __export(wave_gradient_exports, {
    WaveGradient: () => WaveGradient
  });

  // src/shaders.js
  var vert = `#version 300 es
vec3 o(vec3 i,vec3 c,float r){return c*r+i*(1.-r);}vec3 o(vec3 n){return n-floor(n*(1./289.))*289.;}vec4 o(vec4 n){return n-floor(n*(1./289.))*289.;}vec4 e(vec4 n){return o((n*34.+1.)*n);}vec4 v(vec4 y){return 1.79284291400159-.85373472095314*y;}float t(vec3 l){const vec2 s=vec2(1./6.,1./3.);const vec4 u=vec4(0.,.5,1.,2.);vec3 a=floor(l+dot(l,s.yyy)),x=l-a+dot(a,s.xxx),d=step(x.yzx,x.xyz),f=1.-d,z=min(d.xyz,f.zxy),w=max(d.xyz,f.zxy),m=x-z+s.xxx,C=x-w+s.yyy,p=x-u.yyy;a=o(a);vec4 P=e(e(e(a.z+vec4(0.,z.z,w.z,1.))+a.y+vec4(0.,z.y,w.y,1.))+a.x+vec4(0.,z.x,w.x,1.));vec3 S=.142857142857*u.wyz-u.xzx;vec4 L=P-49.*floor(P*S.z*S.z),F=floor(L*S.z),R=floor(L-7.*F),n=F*S.x+S.yyyy,W=R*S.x+S.yyyy,b=1.-abs(n)-abs(W),G=vec4(n.xy,W.xy),q=vec4(n.zw,W.zw),h=floor(G)*2.+1.,g=floor(q)*2.+1.,O=-step(b,vec4(0.)),B=G.xzyw+h.xzyw*O.xxyy,A=q.xzyw+g.xzyw*O.zzww;vec3 E=vec3(B.xy,b.x),Z=vec3(B.zw,b.y),Y=vec3(A.xy,b.z),X=vec3(A.zw,b.w);vec4 V=v(vec4(dot(E,E),dot(Z,Z),dot(Y,Y),dot(X,X)));E*=V.x;Z*=V.y;Y*=V.z;X*=V.w;vec4 U=max(.6-vec4(dot(x,x),dot(m,m),dot(C,C),dot(p,p)),0.);U=U*U;return 42.*dot(U*U,vec4(dot(E,x),dot(Z,m),dot(Y,C),dot(X,p)));}uniform mediump vec2 u_Resolution;uniform float u_Amplitude,u_Realtime,u_Seed;uniform vec3 u_BaseColor;uniform int u_LayerCount;uniform struct WaveLayers{float noiseCeil;float noiseFloor;float noiseFlow;float noiseSeed;float noiseSpeed;vec2 noiseFreq;vec3 color;} u_WaveLayers[9];in vec3 a_Position;out vec3 v_Color;void main(){float T=u_Realtime*5e-6;vec2 Q=vec2(.00014,.00029),N=u_Resolution*a_Position.xy*Q;float M=u_Amplitude*(2./u_Resolution.y),K=t(vec3(N.x*3.+T*3.,N.y*4.,T*10.+u_Seed));K*=1.-pow(abs(a_Position.y),2.);K=max(0.,K);gl_Position=vec4(a_Position.x,a_Position.y+K*M,a_Position.z,1.);v_Color=u_BaseColor;for(int a=0;a<u_LayerCount;a++){WaveLayers J=u_WaveLayers[a];float K=t(vec3(N.x*J.noiseFreq.x+T*J.noiseFlow,N.y*J.noiseFreq.y,T*J.noiseSpeed+J.noiseSeed));K=K/2.+.5;K=smoothstep(J.noiseFloor,J.noiseCeil,K);v_Color=o(v_Color,J.color,pow(K,4.));}}
`;
  var frag = `#version 300 es
precision mediump float;uniform vec2 u_Resolution;uniform float u_ShadowPower;in vec3 v_Color;out vec4 color;void main(){vec2 I=gl_FragCoord.xy/u_Resolution.xy;color=vec4(v_Color,1.);color.y-=pow(I.y+sin(-12.)*I.x,u_ShadowPower)*.4;}
`;

  // src/wave-gradient.js
  function parseRGB(hex) {
    const result = hex.match(/^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i) || hex.match(/^#?([a-f\d])([a-f\d])([a-f\d])$/i);
    return result ? result.slice(1, 4).map((c) => {
      return parseInt(c.length < 2 ? c + c : c, 16) / 255;
    }) : null;
  }
  var ClipSpace = class {
    static createPlaneGeometry(widthSegments, depthSegments) {
      const gridX = Math.ceil(widthSegments);
      const gridZ = Math.ceil(depthSegments);
      const vertexCount = 3 * (gridX + 1) * (gridZ + 1);
      const indexCount = 3 * 2 * gridX * gridZ;
      const positions = new ArrayBuffer(4 * vertexCount);
      const indices = new ArrayBuffer(4 * indexCount);
      for (let z = gridZ, i = 0, view = new DataView(positions); z >= 0; z--) {
        const v = z / gridZ;
        const clipY = v * 2 - 1;
        for (let x = gridX; x >= 0; x--, i += 3) {
          const clipX = x / gridX * 2 - 1;
          view.setFloat32((i + 0) * 4, clipX, true);
          view.setFloat32((i + 1) * 4, clipY, true);
          view.setFloat32((i + 2) * 4, v, true);
        }
      }
      const verticesAcross = gridX + 1;
      for (let z = 0, i = 0, view = new DataView(indices); z < gridZ; z++) {
        for (let x = 0; x < gridX; x++, i += 6) {
          view.setUint32((i + 0) * 4, (z + 0) * verticesAcross + x, true);
          view.setUint32((i + 1) * 4, (z + 0) * verticesAcross + x + 1, true);
          view.setUint32((i + 2) * 4, (z + 1) * verticesAcross + x, true);
          view.setUint32((i + 3) * 4, (z + 0) * verticesAcross + x + 1, true);
          view.setUint32((i + 4) * 4, (z + 1) * verticesAcross + x + 1, true);
          view.setUint32((i + 5) * 4, (z + 1) * verticesAcross + x, true);
        }
      }
      return { positions, indices, count: indexCount };
    }
    static prefixName(name, prefix) {
      return `${prefix}${name[0].toUpperCase()}${name.slice(1)}`;
    }
    constructor(config) {
      this.gl = config.gl;
      this.program = this.createProgram(config.shaders);
      this._attributes = {};
      this.setupAttributes(config.attributes);
      this._elementBuffer;
      this.setElements(config.elements);
      this._uniforms = {};
      this.setupUniforms(config.uniforms);
    }
    compileShader(type, source) {
      const { gl } = this;
      let shader = gl.createShader(type);
      if (!shader)
        throw new Error("can't create shader");
      gl.shaderSource(shader, source);
      gl.compileShader(shader);
      return shader;
    }
    debugProgram(program) {
      const { gl } = this;
      const [vs, fs] = gl.getAttachedShaders(program) ?? [];
      if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
        throw new Error(
          `can't link WebGL program.
    ${gl.getProgramInfoLog(program)}
    ${gl.getShaderInfoLog(vs)}
    ${gl.getShaderInfoLog(fs)}`
        );
      }
    }
    createProgram(shaders) {
      const { gl } = this;
      const [vs, fs] = [
        this.compileShader(gl.VERTEX_SHADER, shaders[0]),
        this.compileShader(gl.FRAGMENT_SHADER, shaders[1])
      ];
      const program = gl.createProgram();
      if (!program)
        throw new Error("can't create WebGL program");
      gl.attachShader(program, vs);
      gl.attachShader(program, fs);
      try {
        gl.linkProgram(program);
        this.debugProgram(program);
      } catch (linkError) {
        gl.deleteProgram(program);
        throw linkError;
      } finally {
        gl.deleteShader(vs);
        gl.deleteShader(fs);
      }
      gl.useProgram(program);
      return program;
    }
    createBuffer() {
      const { gl } = this;
      const buffer = gl.createBuffer();
      if (!buffer)
        throw new Error("can't create buffer");
      return buffer;
    }
    setupAttributes(attributes) {
      const { gl, program } = this;
      for (const [name, dataBuffer] of Object.entries(attributes)) {
        const prefixedName = ClipSpace.prefixName(name, "a_");
        const buffer = this.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
        gl.bufferData(gl.ARRAY_BUFFER, dataBuffer, gl.STATIC_DRAW);
        const location = gl.getAttribLocation(program, prefixedName);
        gl.enableVertexAttribArray(location);
        gl.vertexAttribPointer(location, 3, gl.FLOAT, false, 0, 0);
        this._attributes[name] = { buffer, location };
      }
    }
    setAttribute(attributeName, dataBuffer) {
      const { gl } = this;
      gl.bufferData(gl.ARRAY_BUFFER, dataBuffer, gl.STATIC_DRAW);
    }
    setElements(elements) {
      const { gl } = this;
      if (!this._elementBuffer) {
        const buffer = this.createBuffer();
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, buffer);
        this._elementBuffer = buffer;
      }
      gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, elements, gl.STATIC_DRAW);
    }
    createUniformSetter(name, type, initialValue) {
      const { gl, program } = this;
      const uniformX = `uniform${type}`;
      const location = gl.getUniformLocation(program, name);
      const setter = (value) => {
        Array.isArray(value) ? gl[uniformX](location, ...value) : gl[uniformX](location, value);
      };
      if (initialValue)
        setter(initialValue);
      return setter;
    }
    setupUniforms(uniforms) {
      for (const [name, uniform] of Object.entries(uniforms)) {
        const prefixedName = ClipSpace.prefixName(name, "u_");
        switch (uniform.type) {
          case void 0:
            Array.isArray(uniform.value) && uniform.value.forEach(
              (member, i) => {
                const structName = name;
                const prefixedStructName = prefixedName;
                for (const [name2, uniform2] of Object.entries(member)) {
                  const key = `${structName}[${i}].${name2}`;
                  const prefixedKey = `${prefixedStructName}[${i}].${name2}`;
                  this._uniforms[key] = this.createUniformSetter(
                    prefixedKey,
                    uniform2.type,
                    uniform2.value
                  );
                }
              }
            );
            break;
          default:
            this._uniforms[name] = this.createUniformSetter(
              prefixedName,
              uniform.type,
              uniform.value
            );
        }
      }
    }
    setUniform(uniformName, newValue) {
      this._uniforms[uniformName](newValue);
    }
    delete() {
      const { gl } = this;
      gl.deleteProgram(this.program);
      for (const [, attribute] of Object.entries(this._attributes)) {
        this.gl.deleteBuffer(attribute.buffer);
      }
    }
  };
  var WaveGradient = class {
    constructor(canvas, options) {
      const gl = canvas.getContext("webgl2", {
        antialias: true,
        depth: false,
        powerPreference: "low-power"
      });
      if (!gl)
        throw new Error("can't get WebGL2 context");
      const {
        amplitude = 320,
        colors = ["#ef008f", "#6ec3f4", "#7038ff", "#ffba27"],
        density = [0.06, 0.16],
        fps = 24,
        seed = 0,
        speed = 1.25,
        time = 0,
        wireframe = false
      } = options ?? {};
      const { clientWidth, clientHeight } = canvas;
      canvas.width = clientWidth;
      canvas.height = clientHeight;
      gl.viewport(0, 0, clientWidth, clientHeight);
      gl.enable(gl.CULL_FACE);
      gl.disable(gl.DITHER);
      gl.disable(gl.DEPTH_TEST);
      const geometry = ClipSpace.createPlaneGeometry(
        clientWidth * density[0],
        clientHeight * density[1]
      );
      const clipSpace = new ClipSpace({
        gl,
        shaders: [vert, frag],
        attributes: { position: geometry.positions },
        elements: geometry.indices,
        uniforms: {
          amplitude: { value: amplitude, type: "1f" },
          baseColor: { value: parseRGB(colors[0]), type: "3f" },
          realtime: { value: time, type: "1f" },
          resolution: { value: [clientWidth, clientHeight], type: "2f" },
          seed: { value: seed, type: "1f" },
          shadowPower: { value: 6, type: "1f" },
          layerCount: { value: colors.length - 1, type: "1i" },
          waveLayers: {
            value: colors.slice(1).map((color, i, array) => {
              const r = (i + 1) / array.length + 1;
              return {
                noiseCeil: { value: 0.63 + 0.07 * (i + 1), type: "1f" },
                noiseFloor: { value: 0.1, type: "1f" },
                noiseFlow: { value: 6.5 + 0.3 * (i + 1), type: "1f" },
                noiseSeed: { value: seed + 10 * (i + 1), type: "1f" },
                noiseSpeed: { value: 11 + 0.3 * (i + 1), type: "1f" },
                noiseFreq: { value: [2 + r, 3 + r], type: "2f" },
                color: { value: parseRGB(color), type: "3f" }
              };
            })
          }
        }
      });
      this.gl = gl;
      this.clipSpace = clipSpace;
      this.density = density;
      this.speed = speed;
      this.frameInterval = 1e3 / fps;
      this.lastFrameTime = 0;
      this.shouldRender = true;
      this.drawMode = wireframe ? this.gl.LINES : this.gl.TRIANGLES;
      this.drawCount = geometry.count;
      this.time = time;
      requestAnimationFrame((now) => {
        this.render(now);
      });
    }
    resize() {
      const { gl, gl: { canvas }, clipSpace } = this;
      const { width, clientWidth, height, clientHeight } = canvas;
      const resized = width !== clientWidth || height !== clientHeight;
      if (resized) {
        canvas.width = clientWidth;
        canvas.height = clientHeight;
        gl.viewport(0, 0, clientWidth, clientHeight);
        this.clipSpace.setUniform("resolution", [clientWidth, clientHeight]);
        const geometry = ClipSpace.createPlaneGeometry(
          clientWidth * this.density[0],
          clientHeight * this.density[1]
        );
        clipSpace.setAttribute("position", geometry.positions);
        clipSpace.setElements(geometry.indices);
        this.drawCount = geometry.count;
      }
    }
    render(now) {
      if (this.shouldRender) {
        requestAnimationFrame((now2) => {
          this.render(now2);
        });
      } else {
        return;
      }
      const delta = now - this.lastFrameTime;
      if (delta < this.frameInterval) {
        if (Math.random() > 0.75 === true)
          this.resize();
        return;
      }
      this.lastFrameTime = now - delta % this.frameInterval;
      this.time += Math.min(delta, this.frameInterval) * this.speed;
      this.clipSpace.setUniform("realtime", this.time);
      this.gl.drawElements(
        this.drawMode,
        this.drawCount,
        this.gl.UNSIGNED_INT,
        0
      );
    }
    destroy() {
      this.clipSpace.delete();
      delete this.gl;
      this.shouldRender = false;
    }
  };
  return __toCommonJS(wave_gradient_exports);
})();

window.WaveGradient = WaveGradientModule.WaveGradient;
