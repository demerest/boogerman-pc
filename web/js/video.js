/* BP.video - WebGL presentation pipeline.
 * Core framebuffer -> source texture -> normalize pass -> user shader chain
 * -> color grade -> screen. Plus a 2D overlay canvas for mod HUDs.
 */
window.BP = window.BP || {};

BP.video = (function () {
  let canvas, overlay, gl, isGL2 = false;
  let srcTex = null, srcW = 0, srcH = 0, srcFmt = -1;
  let scratch = null;
  let pending = null;           // {ptr,width,height,pitch,fmt}
  let fbos = [], fboTexs = [], fboW = 0, fboH = 0;
  let programs = new Map();     // frag source -> {prog, uniforms}
  let quadBuf = null;
  let scaleMode = BP.util.store.get('scaleMode', 'fit');
  let container = null;
  let displayW = 320, displayH = 224;
  let overlayCtx = null;
  let fps = 0, fpsCount = 0, fpsLast = performance.now();
  let grade = { uBrightness: 0, uContrast: 1, uSaturation: 1 };

  function init(glCanvas, overlayCanvas, stageEl) {
    canvas = glCanvas;
    overlay = overlayCanvas;
    container = stageEl;
    gl = canvas.getContext('webgl2', { alpha: false, antialias: false, preserveDrawingBuffer: true });
    isGL2 = !!gl;
    if (!gl) gl = canvas.getContext('webgl', { alpha: false, antialias: false, preserveDrawingBuffer: true });
    if (!gl) throw new Error('WebGL unavailable');
    overlayCtx = overlay.getContext('2d');

    quadBuf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, quadBuf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
    gl.disable(gl.DEPTH_TEST);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);

    srcTex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, srcTex);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

    window.addEventListener('resize', resize);
    if (window.ResizeObserver) new ResizeObserver(resize).observe(container);
    resize();
  }

  function compile(fragSrc) {
    if (programs.has(fragSrc)) return programs.get(fragSrc);
    const mk = (type, src) => {
      const s = gl.createShader(type);
      gl.shaderSource(s, src);
      gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
        const log = gl.getShaderInfoLog(s);
        gl.deleteShader(s);
        throw new Error('Shader compile error: ' + log);
      }
      return s;
    };
    const prog = gl.createProgram();
    gl.attachShader(prog, mk(gl.VERTEX_SHADER, BP.shaders.VERT));
    gl.attachShader(prog, mk(gl.FRAGMENT_SHADER, fragSrc));
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
      throw new Error('Program link error: ' + gl.getProgramInfoLog(prog));
    }
    const entry = { prog, aPos: gl.getAttribLocation(prog, 'aPos'), uniforms: {} };
    const n = gl.getProgramParameter(prog, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < n; i++) {
      const info = gl.getActiveUniform(prog, i);
      entry.uniforms[info.name] = gl.getUniformLocation(prog, info.name);
    }
    programs.set(fragSrc, entry);
    return entry;
  }

  function drawPass(entry, target, tex, swizzle, extra) {
    gl.bindFramebuffer(gl.FRAMEBUFFER, target);
    gl.useProgram(entry.prog);
    gl.bindBuffer(gl.ARRAY_BUFFER, quadBuf);
    gl.enableVertexAttribArray(entry.aPos);
    gl.vertexAttribPointer(entry.aPos, 2, gl.FLOAT, false, 0, 0);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, tex);
    const u = entry.uniforms;
    if (u.uTex !== undefined) gl.uniform1i(u.uTex, 0);
    if (u.uSourceSize !== undefined) gl.uniform2f(u.uSourceSize, srcW, srcH);
    if (u.uOutputSize !== undefined) gl.uniform2f(u.uOutputSize, canvas.width, canvas.height);
    if (u.uTime !== undefined) gl.uniform1f(u.uTime, performance.now() / 1000);
    if (u.uSwizzle !== undefined) gl.uniform1f(u.uSwizzle, swizzle ? 1 : 0);
    if (extra) {
      for (const k of Object.keys(extra)) {
        if (u[k] !== undefined) gl.uniform1f(u[k], extra[k]);
      }
    }
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    const derr = gl.getError();
    if (derr) console.warn('[video] draw error', derr, target ? 'fbo' : 'screen');
  }

  function ensureFbos(w, h) {
    if (fboW === w && fboH === h && fbos.length === 2) return;
    fbos.forEach(f => gl.deleteFramebuffer(f));
    fboTexs.forEach(t => gl.deleteTexture(t));
    fbos = []; fboTexs = [];
    for (let i = 0; i < 2; i++) {
      const t = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, t);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      const f = gl.createFramebuffer();
      gl.bindFramebuffer(gl.FRAMEBUFFER, f);
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t, 0);
      fbos.push(f); fboTexs.push(t);
    }
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    fboW = w; fboH = h;
  }

  /* Called from the core's video_refresh callback. */
  function onFrame(ptr, width, height, pitch, fmt) {
    pending = { ptr, width, height, pitch, fmt };
  }

  function upload() {
    if (!pending) return;
    const { ptr, width, height, pitch, fmt } = pending;
    pending = null;
    const U8 = BP.core.heapU8();

    gl.bindTexture(gl.TEXTURE_2D, srcTex);
    if (width !== srcW || height !== srcH || fmt !== srcFmt) {
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
      srcW = width; srcH = height; srcFmt = fmt;
      scratch = new Uint8Array(width * height * 4);
      ensureFbos(width, height);
      resize();
      /* ensureFbos leaves an FBO texture bound - reclaim the source unit */
      gl.bindTexture(gl.TEXTURE_2D, srcTex);
    }
    const filter = firstPassFilter();
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter);

    /* Normalize every core pixel format to RGBA8 in JS: packed 16-bit texture
     * uploads (565/5551) are rejected by some WebGL2 drivers (SwiftShader).
     * Rows are written bottom-first so texture v=0 matches GL window bottom. */
    const S = scratch;
    if (fmt === BP.core.LR.PF_RGB565) {
      for (let y = 0; y < height; y++) {
        let s = ptr + (height - 1 - y) * pitch;
        let d = y * width * 4;
        for (let x = 0; x < width; x++) {
          const v = U8[s] | (U8[s + 1] << 8); s += 2;
          const r = (v >> 11) & 31, g = (v >> 5) & 63, b = v & 31;
          S[d] = (r << 3) | (r >> 2);
          S[d + 1] = (g << 2) | (g >> 4);
          S[d + 2] = (b << 3) | (b >> 2);
          S[d + 3] = 255;
          d += 4;
        }
      }
    } else if (fmt === BP.core.LR.PF_0RGB1555) {
      for (let y = 0; y < height; y++) {
        let s = ptr + (height - 1 - y) * pitch;
        let d = y * width * 4;
        for (let x = 0; x < width; x++) {
          const v = U8[s] | (U8[s + 1] << 8); s += 2;
          const r = (v >> 10) & 31, g = (v >> 5) & 31, b = v & 31;
          S[d] = (r << 3) | (r >> 2);
          S[d + 1] = (g << 3) | (g >> 2);
          S[d + 2] = (b << 3) | (b >> 2);
          S[d + 3] = 255;
          d += 4;
        }
      }
    } else { /* XRGB8888: little-endian bytes are B,G,R,X */
      for (let y = 0; y < height; y++) {
        let s = ptr + (height - 1 - y) * pitch;
        let d = y * width * 4;
        for (let x = 0; x < width; x++) {
          S[d] = U8[s + 2];
          S[d + 1] = U8[s + 1];
          S[d + 2] = U8[s];
          S[d + 3] = 255;
          s += 4; d += 4;
        }
      }
    }
    gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, width, height, gl.RGBA, gl.UNSIGNED_BYTE, S);
    const uerr = gl.getError();
    if (uerr) console.warn('[video] upload error', uerr, 'fmt', fmt, 'pitch', pitch);
  }

  function firstPassFilter() {
    const chain = BP.shaders.chain;
    if (chain.length && BP.shaders.get(chain[0].name).filter === 'linear') return gl.LINEAR;
    return gl.NEAREST;
  }

  function present() {
    if (!gl) return;
    upload();
    if (!srcW || !srcH) {
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      gl.viewport(0, 0, canvas.width, canvas.height);
      gl.clearColor(0, 0, 0, 1);
      gl.clear(gl.COLOR_BUFFER_BIT);
      return;
    }
    const chain = BP.shaders.chain;
    const swizzle = false; /* upload() already normalizes to RGBA8 */

    /* normalize into fbo 0 */
    gl.viewport(0, 0, srcW, srcH);
    drawPass(compile(BP.shaders.NORMALIZE), fbos[0], srcTex, swizzle, null);

    /* user chain ping-pong (all passes at source resolution) */
    let read = 0;
    for (let i = 0; i < chain.length; i++) {
      const def = BP.shaders.get(chain[i].name);
      if (!def) continue;
      gl.viewport(0, 0, srcW, srcH);
      try {
        drawPass(compile(def.frag), fbos[1 - read], fboTexs[read], false, chain[i].params || {});
      } catch (e) {
        console.error('[BP.video] shader pass failed:', chain[i].name, e);
        BP.util.toast('Shader error: ' + chain[i].name);
        BP.shaders.setChain(chain.filter(p => p.name !== chain[i].name));
        return present();
      }
      read = 1 - read;
    }

    /* color grade to screen */
    gl.viewport(0, 0, canvas.width, canvas.height);
    drawPass(compile(BP.shaders.GRADE), null, fboTexs[read], false, BP.shaders.grade);

    fpsCount++;
    const now = performance.now();
    if (now - fpsLast >= 1000) {
      fps = fpsCount * 1000 / (now - fpsLast);
      fpsCount = 0; fpsLast = now;
    }
  }

  /* ---- layout / scaling ---- */
  function resize() {
    if (!container || !BP.core.av) return;
    const av = BP.core.av;
    const aspect = av.aspect > 0 ? av.aspect : av.baseWidth / av.baseHeight;
    const cw = container.clientWidth, ch = container.clientHeight;
    if (cw <= 0 || ch <= 0) return;
    let dw, dh;
    if (scaleMode === 'stretch') {
      dw = cw; dh = ch;
    } else if (scaleMode === 'integer') {
      let s = Math.max(1, Math.floor(Math.min(cw / av.baseWidth, ch / av.baseHeight)));
      dh = av.baseHeight * s;
      dw = Math.round(dh * aspect);
      while (dw > cw && s > 1) { s--; dh = av.baseHeight * s; dw = Math.round(dh * aspect); }
    } else { /* fit */
      if (cw / ch > aspect) { dh = ch; dw = Math.round(ch * aspect); }
      else { dw = cw; dh = Math.round(cw / aspect); }
    }
    displayW = dw; displayH = dh;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.style.width = dw + 'px';
    canvas.style.height = dh + 'px';
    canvas.width = Math.max(2, Math.round(dw * dpr));
    canvas.height = Math.max(2, Math.round(dh * dpr));
    overlay.style.width = dw + 'px';
    overlay.style.height = dh + 'px';
    overlay.width = av.baseWidth;
    overlay.height = av.baseHeight;
    overlayCtx.imageSmoothingEnabled = false;
  }

  function setScaleMode(m) {
    scaleMode = m;
    BP.util.store.set('scaleMode', m);
    resize();
  }

  function screenshot() {
    present();
    return canvas.toDataURL('image/png');
  }

  return {
    init, onFrame, present, resize, setScaleMode, screenshot,
    get scaleMode() { return scaleMode; },
    get fps() { return fps; },
    get size() { return { w: srcW, h: srcH }; },
    get displaySize() { return { w: displayW, h: displayH }; },
    get overlayCtx() { return overlayCtx; },
    clearOverlay() { if (overlayCtx) overlayCtx.clearRect(0, 0, overlay.width, overlay.height); },
    get gl() { return gl; },
    get _dbg() { return { fbos, fboTexs, srcTex, srcW, srcH, canvas, container, scratch }; }
  };
})();
