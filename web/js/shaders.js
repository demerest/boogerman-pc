/* BP.shaders - post-processing shader registry + chain state.
 * Built-ins ship here; mods register more via BP.shaders.register().
 * All shaders are GLSL ES 1.00 (WebGL1/2 compatible).
 *
 * Pass contract:
 *   uniforms: uTex (sampler2D), uSourceSize (vec2), uOutputSize (vec2), uTime (float)
 *   plus any declared params (float). Varying: vUv (0..1, GL orientation).
 */
window.BP = window.BP || {};

BP.shaders = (function () {
  const registry = new Map();

  const VERT = [
    'attribute vec2 aPos;',
    'varying vec2 vUv;',
    'void main() {',
    '  vUv = aPos * 0.5 + 0.5;',
    '  gl_Position = vec4(aPos, 0.0, 1.0);',
    '}'
  ].join('\n');

  const HEAD = 'precision mediump float;\nvarying vec2 vUv;\nuniform sampler2D uTex;\nuniform vec2 uSourceSize;\nuniform vec2 uOutputSize;\nuniform float uTime;\n';

  function register(name, def) {
    registry.set(name, {
      name,
      label: def.label || name,
      frag: def.frag,
      filter: def.filter || 'nearest',
      params: def.params || [],
      builtin: !!def.builtin
    });
  }

  /* ---- built-ins ---- */

  register('sharp-bilinear', {
    label: 'Sharp bilinear (crisp upscale)',
    filter: 'linear',
    builtin: true,
    frag: HEAD + [
      'void main() {',
      '  vec2 scale = max(uOutputSize / uSourceSize, vec2(1.0));',
      '  vec2 texel = vUv * uSourceSize;',
      '  vec2 floored = floor(texel);',
      '  vec2 s = fract(texel);',
      '  vec2 region = 0.5 - 0.5 / scale;',
      '  vec2 dist = s - 0.5;',
      '  vec2 f = (dist - clamp(dist, -region, region)) * scale + 0.5;',
      '  gl_FragColor = vec4(texture2D(uTex, (floored + f) / uSourceSize).rgb, 1.0);',
      '}'
    ].join('\n')
  });

  register('scanlines', {
    label: 'Scanlines',
    filter: 'linear',
    builtin: true,
    params: [{ name: 'uIntensity', label: 'Intensity', min: 0, max: 1, step: 0.05, def: 0.35 }],
    frag: HEAD + [
      'uniform float uIntensity;',
      'void main() {',
      '  vec3 c = texture2D(uTex, vUv).rgb;',
      '  float f = fract(vUv.y * uSourceSize.y);',
      '  float scan = 1.0 - uIntensity * (0.5 + 0.5 * cos(6.2831853 * f));',
      '  c *= scan * (1.0 + uIntensity * 0.35);',
      '  gl_FragColor = vec4(c, 1.0);',
      '}'
    ].join('\n')
  });

  register('crt', {
    label: 'CRT (curvature + mask + vignette)',
    filter: 'linear',
    builtin: true,
    params: [
      { name: 'uCurvature', label: 'Curvature', min: 0, max: 0.25, step: 0.01, def: 0.06 },
      { name: 'uScanline', label: 'Scanlines', min: 0, max: 1, step: 0.05, def: 0.30 },
      { name: 'uMask', label: 'Aperture mask', min: 0, max: 1, step: 0.05, def: 0.25 },
      { name: 'uVignette', label: 'Vignette', min: 0, max: 1, step: 0.05, def: 0.30 }
    ],
    frag: HEAD + [
      'uniform float uCurvature; uniform float uScanline; uniform float uMask; uniform float uVignette;',
      'void main() {',
      '  vec2 c = vUv - 0.5;',
      '  float r2 = dot(c, c);',
      '  vec2 uv = 0.5 + c * (1.0 + uCurvature * r2);',
      '  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0); return; }',
      '  vec3 col = texture2D(uTex, uv).rgb;',
      '  float f = fract(uv.y * uSourceSize.y);',
      '  col *= 1.0 - uScanline * (0.5 + 0.5 * cos(6.2831853 * f));',
      '  float ph = gl_FragCoord.x * 2.0943951;',
      '  vec3 mask = 1.0 - uMask * vec3(0.5 + 0.5 * cos(ph), 0.5 + 0.5 * cos(ph + 2.0943951), 0.5 + 0.5 * cos(ph + 4.1887902));',
      '  col *= mask;',
      '  col *= 1.0 + uScanline * 0.4 + uMask * 0.5;',
      '  col *= clamp(1.0 - uVignette * r2 * 2.4, 0.0, 1.0);',
      '  gl_FragColor = vec4(col, 1.0);',
      '}'
    ].join('\n')
  });

  register('lcd', {
    label: 'LCD grid (handheld look)',
    filter: 'nearest',
    builtin: true,
    params: [{ name: 'uGrid', label: 'Grid strength', min: 0, max: 1, step: 0.05, def: 0.35 }],
    frag: HEAD + [
      'uniform float uGrid;',
      'void main() {',
      '  vec3 c = texture2D(uTex, vUv).rgb;',
      '  vec2 f = fract(vUv * uSourceSize);',
      '  float line = max(step(f.x, 0.09), step(f.y, 0.09));',
      '  c *= 1.0 - uGrid * line;',
      '  gl_FragColor = vec4(c, 1.0);',
      '}'
    ].join('\n')
  });

  /* Internal passes (not user-selectable) */
  const NORMALIZE = HEAD + [
    'uniform float uSwizzle;',
    'void main() {',
    '  vec4 c = texture2D(uTex, vUv);',
    '  c = mix(c, vec4(c.b, c.g, c.r, 1.0), uSwizzle);',
    '  gl_FragColor = vec4(c.rgb, 1.0);',
    '}'
  ].join('\n');

  const GRADE = HEAD + [
    'uniform float uBrightness; uniform float uContrast; uniform float uSaturation;',
    'void main() {',
    '  vec3 c = texture2D(uTex, vUv).rgb;',
    '  c += uBrightness;',
    '  c = (c - 0.5) * uContrast + 0.5;',
    '  float l = dot(c, vec3(0.299, 0.587, 0.114));',
    '  c = mix(vec3(l), c, uSaturation);',
    '  gl_FragColor = vec4(clamp(c, 0.0, 1.0), 1.0);',
    '}'
  ].join('\n');

  /* ---- chain state ---- */
  let chain = BP.util.store.get('shaderChain', [{ name: 'sharp-bilinear', params: {} }]);
  let grade = BP.util.store.get('grade', { uBrightness: 0, uContrast: 1, uSaturation: 1 });

  function setChain(list) {
    chain = list.filter(p => registry.has(p.name));
    BP.util.store.set('shaderChain', chain);
  }
  function setGrade(g) { grade = Object.assign({}, grade, g); BP.util.store.set('grade', grade); }

  return {
    VERT, NORMALIZE, GRADE,
    register,
    get: (name) => registry.get(name),
    names: () => [...registry.keys()],
    all: () => [...registry.values()],
    get chain() { return chain; },
    setChain,
    get grade() { return grade; },
    setGrade
  };
})();
