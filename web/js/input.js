/* BP.input - keyboard + gamepad + virtual (touch/mod) input -> libretro joypad.
 *
 * Mega Drive button <-> libretro id mapping (from the core's input descriptors):
 *   retro Y = MD A | retro B = MD B | retro A = MD C
 *   retro L = MD X | retro X = MD Y | retro R = MD Z
 *   retro START = Start | retro SELECT = Mode
 */
window.BP = window.BP || {};

BP.input = (function () {
  const LR = { B: 0, Y: 1, SELECT: 2, START: 3, UP: 4, DOWN: 5, LEFT: 6, RIGHT: 7, A: 8, X: 9, L: 10, R: 11 };

  const PRESETS = {
    'arrows-zxc': {
      label: 'Arrows + Z/X/C (default)',
      map: {
        [LR.UP]: 'ArrowUp', [LR.DOWN]: 'ArrowDown', [LR.LEFT]: 'ArrowLeft', [LR.RIGHT]: 'ArrowRight',
        [LR.Y]: 'KeyZ', [LR.B]: 'KeyX', [LR.A]: 'KeyC',
        [LR.L]: 'KeyA', [LR.X]: 'KeyS', [LR.R]: 'KeyD',
        [LR.START]: 'Enter', [LR.SELECT]: 'ShiftRight'
      }
    },
    'wasd-jkl': {
      label: 'WASD + J/K/L',
      map: {
        [LR.UP]: 'KeyW', [LR.DOWN]: 'KeyS', [LR.LEFT]: 'KeyA', [LR.RIGHT]: 'KeyD',
        [LR.Y]: 'KeyJ', [LR.B]: 'KeyK', [LR.A]: 'KeyL',
        [LR.L]: 'KeyU', [LR.X]: 'KeyI', [LR.R]: 'KeyO',
        [LR.START]: 'Enter', [LR.SELECT]: 'ShiftRight'
      }
    }
  };

  const BUTTON_LABELS = {
    [LR.UP]: 'D-Up', [LR.DOWN]: 'D-Down', [LR.LEFT]: 'D-Left', [LR.RIGHT]: 'D-Right',
    [LR.Y]: 'A', [LR.B]: 'B', [LR.A]: 'C', [LR.L]: 'X', [LR.X]: 'Y', [LR.R]: 'Z',
    [LR.START]: 'Start', [LR.SELECT]: 'Mode'
  };

  let map = Object.assign({}, PRESETS['arrows-zxc'].map, BP.util.store.get('inputMap', {}));
  let presetName = BP.util.store.get('inputPreset', 'arrows-zxc');
  const keys = new Set();
  const virtual = [{}, {}];
  const turbo = new Set(BP.util.store.get('turbo', []));
  let gpState = {};
  let remapTarget = null;   // retro id awaiting a key press
  let remapCallback = null;
  let attached = false;

  const GAMEPAD_MAP = { 2: LR.Y, 0: LR.B, 1: LR.A, 3: LR.L, 4: LR.X, 5: LR.R, 9: LR.START, 8: LR.SELECT, 12: LR.UP, 13: LR.DOWN, 14: LR.LEFT, 15: LR.RIGHT };

  function isTyping() {
    const a = document.activeElement;
    return a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA' || a.tagName === 'SELECT' || a.isContentEditable);
  }

  function attach() {
    if (attached) return;
    attached = true;
    window.addEventListener('keydown', (e) => {
      if (isTyping()) return;
      if (remapTarget !== null) {
        e.preventDefault();
        const id = remapTarget;
        remapTarget = null;
        map[id] = e.code;
        BP.util.store.set('inputMap', map);
        presetName = 'custom';
        BP.util.store.set('inputPreset', presetName);
        if (remapCallback) remapCallback(id, e.code);
        return;
      }
      const mapped = Object.values(map).includes(e.code);
      if (mapped) e.preventDefault();
      keys.add(e.code);
    });
    window.addEventListener('keyup', (e) => { keys.delete(e.code); });
    window.addEventListener('blur', () => { keys.clear(); virtual[0] = {}; virtual[1] = {}; });
  }

  function poll() {
    gpState = {};
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    for (const gp of pads) {
      if (!gp || !gp.connected) continue;
      for (const bi of Object.keys(GAMEPAD_MAP)) {
        const b = gp.buttons[bi];
        if (b && (b.pressed || b.value > 0.5)) gpState[GAMEPAD_MAP[bi]] = true;
      }
      if (gp.axes.length >= 2) {
        if (gp.axes[0] < -0.5) gpState[LR.LEFT] = true;
        if (gp.axes[0] > 0.5) gpState[LR.RIGHT] = true;
        if (gp.axes[1] < -0.5) gpState[LR.UP] = true;
        if (gp.axes[1] > 0.5) gpState[LR.DOWN] = true;
      }
      break; /* first connected pad -> port 0 */
    }
  }

  function state(port, id) {
    let down = false;
    if (port === 0) {
      if (map[id] && keys.has(map[id])) down = true;
      if (gpState[id]) down = true;
    }
    if (virtual[port] && virtual[port][id]) down = true;
    if (down && turbo.has(id)) {
      const f = BP.core.stats.framesRun;
      down = ((f >> 2) & 1) === 0;
    }
    return down;
  }

  function setVirtual(port, id, down) {
    if (!virtual[port]) virtual[port] = {};
    virtual[port][id] = !!down;
  }

  function applyPreset(name) {
    if (!PRESETS[name]) return;
    presetName = name;
    map = Object.assign({}, PRESETS[name].map);
    BP.util.store.set('inputMap', map);
    BP.util.store.set('inputPreset', name);
  }

  function startRemap(id, cb) { remapTarget = id; remapCallback = cb || null; }
  function cancelRemap() { remapTarget = null; remapCallback = null; }

  function setTurbo(id, on) {
    if (on) turbo.add(id); else turbo.delete(id);
    BP.util.store.set('turbo', [...turbo]);
  }

  return {
    LR, PRESETS, BUTTON_LABELS, attach, poll, state, setVirtual,
    applyPreset, startRemap, cancelRemap, setTurbo,
    get map() { return map; },
    get presetName() { return presetName; },
    get turbo() { return turbo; },
    get remapping() { return remapTarget; },
    get gamepadConnected() { return Object.keys(gpState).length > 0 || (navigator.getGamepads && [...navigator.getGamepads()].some(g => g && g.connected)); }
  };
})();
