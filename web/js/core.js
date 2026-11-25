/* BP.core - libretro bridge for the Genesis Plus GX WASM core.
 *
 * Owns: module instantiation, the C callback surface (environment / video /
 * audio / input), game loading, timing info, work-RAM access, save states,
 * SRAM, cheats and core options. Everything the enhancement layer needs
 * hangs off this object.
 *
 * libretro API reference: https://www.libretro.com/api/  (constants below)
 */
window.BP = window.BP || {};

BP.core = (function () {
  const LR = {
    API_VERSION: 1,
    DEVICE_NONE: 0, DEVICE_JOYPAD: 1,
    JOYPAD_B: 0, JOYPAD_Y: 1, JOYPAD_SELECT: 2, JOYPAD_START: 3,
    JOYPAD_UP: 4, JOYPAD_DOWN: 5, JOYPAD_LEFT: 6, JOYPAD_RIGHT: 7,
    JOYPAD_A: 8, JOYPAD_X: 9, JOYPAD_L: 10, JOYPAD_R: 11,
    JOYPAD_L2: 12, JOYPAD_R2: 13, JOYPAD_L3: 14, JOYPAD_R3: 15,
    DEVICE_MDPAD_3B: (2 << 8) | 1, DEVICE_MDPAD_6B: (3 << 8) | 1,
    REGION_NTSC: 0, REGION_PAL: 1,
    MEMORY_SAVE_RAM: 0, MEMORY_SYSTEM_RAM: 2,
    PF_0RGB1555: 0, PF_XRGB8888: 1, PF_RGB565: 2,
    ENV_SET_ROTATION: 1, ENV_GET_OVERSCAN: 2, ENV_GET_CAN_DUPE: 3,
    ENV_SET_MESSAGE: 6, ENV_SHUTDOWN: 7, ENV_SET_PERFORMANCE_LEVEL: 8,
    ENV_GET_SYSTEM_DIRECTORY: 9, ENV_SET_PIXEL_FORMAT: 10,
    ENV_SET_INPUT_DESCRIPTORS: 11, ENV_SET_KEYBOARD_CALLBACK: 12,
    ENV_SET_DISK_CONTROL_INTERFACE: 13, ENV_SET_HW_RENDER: 14,
    ENV_GET_VARIABLE: 15, ENV_SET_VARIABLES: 16, ENV_GET_VARIABLE_UPDATE: 17,
    ENV_SET_SUPPORT_NO_GAME: 18, ENV_GET_LIBRETRO_PATH: 19,
    ENV_SET_FRAME_TIME_CALLBACK: 21, ENV_SET_AUDIO_CALLBACK: 22,
    ENV_GET_RUMBLE_INTERFACE: 23, ENV_GET_INPUT_DEVICE_CAPABILITIES: 24,
    ENV_GET_LOG_INTERFACE: 27, ENV_GET_CORE_ASSETS_DIRECTORY: 30,
    ENV_GET_SAVE_DIRECTORY: 31, ENV_SET_SYSTEM_AV_INFO: 32,
    ENV_SET_CONTROLLER_INFO: 35, ENV_SET_GEOMETRY: 37,
    ENV_GET_USERNAME: 38, ENV_GET_LANGUAGE: 39,
    ENV_GET_CURRENT_SOFTWARE_FRAMEBUFFER: 40,
    ENV_SET_SUPPORT_ACHIEVEMENTS: 42, ENV_SET_SERIALIZATION_QUIRKS: 44,
    ENV_GET_AUDIO_VIDEO_ENABLE: 47, ENV_GET_FASTFORWARDING: 49,
    ENV_GET_TARGET_REFRESH_RATE: 50, ENV_GET_INPUT_BITMASKS: 51,
    ENV_GET_CORE_OPTIONS_VERSION: 52, ENV_SET_CORE_OPTIONS: 53,
    ENV_SET_CORE_OPTIONS_INTL: 54, ENV_SET_CORE_OPTIONS_DISPLAY: 55,
    ENV_GET_PREFERRED_HW_RENDER: 56,
    ENV_GET_DISK_CONTROL_INTERFACE_VERSION: 57,
    ENV_SET_DISK_CONTROL_EXT_INTERFACE: 58,
    ENV_GET_MESSAGE_INTERFACE_VERSION: 59, ENV_GET_INPUT_MAX_USERS: 61
  };

  let M = null;               // Emscripten module
  const api = {};             // wrapped retro_* functions
  let pixelFormat = LR.PF_0RGB1555;
  let av = null;              // {baseWidth, baseHeight, maxWidth, maxHeight, aspect, fps, sampleRate}
  let loaded = false;
  let romAlloc = 0, romDataAlloc = 0, pathAlloc = 0;
  let ramPtr = 0, ramSize = 0, sramPtr = 0, sramSize = 0;
  let variables = {};         // key -> {label, values:[], current}
  let variableUpdate = false;
  let optionsListener = null;
  let messageListener = null;
  let fastForward = false;
  let sixButton = false;

  const stats = { framesRun: 0, videoFrames: 0, audioSamples: 0, nullVideo: 0 };
  const lastVideo = { ptr: 0, width: 0, height: 0, pitch: 0 };

  /* ---- memory views (refreshed if wasm memory grows) ---- */
  let vbuf = null, U8, U32, I16, F32, F64;
  function views() {
    const b = M.HEAPU8.buffer;
    if (b !== vbuf) {
      vbuf = b;
      U8 = new Uint8Array(b);
      U32 = new Uint32Array(b);
      I16 = new Int16Array(b);
      F32 = new Float32Array(b);
      F64 = new Float64Array(b);
    }
  }
  const u32 = (p) => { views(); return U32[p >> 2]; };
  const setU32 = (p, v) => { views(); U32[p >> 2] = v >>> 0; };
  const u8 = (p) => { views(); return U8[p]; };
  const setU8 = (p, v) => { views(); U8[p] = v & 0xFF; };

  const strCache = new Map();
  function cstr(s) {
    if (strCache.has(s)) return strCache.get(s);
    views();
    const bytes = new TextEncoder().encode(s + '\0');
    const ptr = M._malloc(bytes.length);
    U8.set(bytes, ptr);
    strCache.set(s, ptr);
    return ptr;
  }
  function readCstr(p) {
    if (!p) return '';
    views();
    let e = p;
    while (U8[e] && e - p < 4096) e++;
    return new TextDecoder().decode(U8.subarray(p, e));
  }

  /* ---- environment callback ---- */
  function environment(cmd, data) {
    switch (cmd) {
      case LR.ENV_SET_PIXEL_FORMAT: {
        const fmt = u32(data);
        if (fmt === LR.PF_0RGB1555 || fmt === LR.PF_XRGB8888 || fmt === LR.PF_RGB565) {
          pixelFormat = fmt;
          return 1;
        }
        return 0;
      }
      case LR.ENV_GET_VARIABLE: {
        const key = readCstr(u32(data));
        const v = variables[key];
        if (!v) return 0;
        setU32(data + 4, cstr(v.current));
        return 1;
      }
      case LR.ENV_SET_VARIABLES: {
        let p = data;
        variables = {};
        for (;;) {
          const keyPtr = u32(p);
          if (!keyPtr) break;
          const key = readCstr(keyPtr);
          const desc = readCstr(u32(p + 4));
          const semi = desc.indexOf(';');
          const label = semi >= 0 ? desc.slice(0, semi).trim() : key;
          const values = (semi >= 0 ? desc.slice(semi + 1) : desc).split('|').map(s => s.trim()).filter(Boolean);
          const prev = variables[key];
          variables[key] = { label, values, current: (prev && values.includes(prev.current)) ? prev.current : values[0] };
          p += 8;
        }
        /* re-apply persisted user overrides */
        const saved = BP.util.store.get('coreOptions', {});
        for (const k of Object.keys(saved)) {
          if (variables[k] && variables[k].values.includes(saved[k])) variables[k].current = saved[k];
        }
        variableUpdate = true;
        if (optionsListener) optionsListener(variables);
        return 1;
      }
      case LR.ENV_GET_VARIABLE_UPDATE:
        setU8(data, variableUpdate ? 1 : 0);
        variableUpdate = false;
        return 1;
      case LR.ENV_GET_SYSTEM_DIRECTORY:
        setU32(data, cstr('/system'));
        return 1;
      case LR.ENV_GET_SAVE_DIRECTORY:
        setU32(data, cstr('/save'));
        return 1;
      case LR.ENV_GET_CORE_ASSETS_DIRECTORY:
        setU32(data, cstr('/assets'));
        return 1;
      case LR.ENV_SET_SUPPORT_NO_GAME:
        return 1;
      case LR.ENV_GET_CAN_DUPE:
        setU8(data, 1);
        return 1;
      case LR.ENV_GET_OVERSCAN:
        setU8(data, 0);
        return 1;
      case LR.ENV_SET_MESSAGE: {
        const msg = readCstr(u32(data + 4));
        if (messageListener) messageListener(msg);
        return 1;
      }
      case LR.ENV_SET_INPUT_DESCRIPTORS:
        return 1;
      case LR.ENV_SET_CONTROLLER_INFO:
        return 1;
      case LR.ENV_GET_INPUT_BITMASKS:
        return 0; /* per-id queries */
      case LR.ENV_GET_CORE_OPTIONS_VERSION:
        return 0; /* legacy SET_VARIABLES path */
      case LR.ENV_SET_CORE_OPTIONS:
      case LR.ENV_SET_CORE_OPTIONS_INTL:
        return 0;
      case LR.ENV_GET_LANGUAGE:
        setU32(data, 0); /* RETRO_LANGUAGE_ENGLISH */
        return 1;
      case LR.ENV_GET_USERNAME:
        setU32(data, cstr('Player'));
        return 1;
      case LR.ENV_GET_LOG_INTERFACE:
        return 0;
      case LR.ENV_SET_FRAME_TIME_CALLBACK:
      case LR.ENV_SET_AUDIO_CALLBACK:
        return 0; /* frontend drives timing */
      case LR.ENV_GET_FASTFORWARDING:
        setU8(data, fastForward ? 1 : 0);
        return 1;
      case LR.ENV_SET_SYSTEM_AV_INFO:
        readAvInfo(data);
        return 1;
      case LR.ENV_SET_GEOMETRY:
        av.baseWidth = u32(data); av.baseHeight = u32(data + 4);
        av.maxWidth = u32(data + 8); av.maxHeight = u32(data + 12);
        av.aspect = F32[(data + 16) >> 2];
        return 1;
      case LR.ENV_SET_ROTATION:
        return 1;
      case LR.ENV_SET_PERFORMANCE_LEVEL:
        return 1;
      case LR.ENV_GET_INPUT_MAX_USERS:
        setU32(data, 2);
        return 1;
      case LR.ENV_SET_SERIALIZATION_QUIRKS:
        return 1;
      case LR.ENV_GET_AUDIO_VIDEO_ENABLE:
        return 0;
      case LR.ENV_SET_HW_RENDER:
      case LR.ENV_GET_PREFERRED_HW_RENDER:
      case LR.ENV_GET_CURRENT_SOFTWARE_FRAMEBUFFER:
      case LR.ENV_SET_KEYBOARD_CALLBACK:
      case LR.ENV_SET_DISK_CONTROL_INTERFACE:
      case LR.ENV_GET_RUMBLE_INTERFACE:
      case LR.ENV_GET_INPUT_DEVICE_CAPABILITIES:
      case LR.ENV_SHUTDOWN:
        return 0;
      default:
        return 0;
    }
  }

  /* ---- AV callbacks ---- */
  function videoRefresh(data, width, height, pitch) {
    stats.videoFrames++;
    if (!data) { stats.nullVideo++; return; }
    lastVideo.ptr = data; lastVideo.width = width; lastVideo.height = height; lastVideo.pitch = pitch;
    if (BP.video) BP.video.onFrame(data, width, height, pitch, pixelFormat);
  }

  function audioSampleBatch(data, frames) {
    if (!frames) return 0;
    stats.audioSamples += frames;
    views();
    /* copy out before the core reuses its buffer */
    const samples = I16.slice(data >> 1, (data >> 1) + frames * 2);
    if (BP.audio) BP.audio.push(samples, frames);
    if (BP.hooks) BP.hooks.emitAudio({ samples, frames, rate: av ? av.sampleRate : 44100 });
    return frames;
  }

  function audioSample(left, right) {
    /* single-sample fallback: pack into a 1-frame batch */
    views();
    const tmp = new Int16Array(2);
    tmp[0] = left; tmp[1] = right;
    if (BP.audio) BP.audio.push(tmp, 1);
  }

  function inputPoll() {
    if (BP.input) BP.input.poll();
  }

  function inputState(port, device, index, id) {
    if (device !== LR.DEVICE_JOYPAD || port > 1) return 0;
    if (BP.input) return BP.input.state(port, id) ? 1 : 0;
    return 0;
  }

  function readAvInfo(ptr) {
    views();
    av = {
      baseWidth: u32(ptr), baseHeight: u32(ptr + 4),
      maxWidth: u32(ptr + 8), maxHeight: u32(ptr + 12),
      aspect: F32[(ptr + 16) >> 2],
      fps: F64[(ptr + 24) >> 3],
      sampleRate: F64[(ptr + 32) >> 3]
    };
  }

  /* ---- public surface ---- */
  async function init(opts) {
    opts = opts || {};
    if (typeof window.create_genesis_plus_gx !== 'function') {
      throw new Error('Core glue missing (vendor/gpgx/gpgx.web.js not loaded)');
    }
    const wasmBinary = opts.wasmBinary || BP.util.b64ToBytes(window.BP_WASM_B64);
    M = await window.create_genesis_plus_gx({
      wasmBinary,
      noInitialRun: true,
      print: (m) => { if (!opts.silent) console.log('[core]', m); },
      printErr: (m) => { console.warn('[core]', m); },
      canvas: opts.canvas || undefined
    });
    if (typeof M.addFunction !== 'function') throw new Error('Core build lacks addFunction (table growth)');

    const wrap = (name, sig) => {
      const f = M['_' + name];
      if (typeof f !== 'function') throw new Error('Missing export: ' + name);
      return f;
    };
    [
      'retro_api_version', 'retro_get_system_info', 'retro_get_system_av_info',
      'retro_set_environment', 'retro_set_video_refresh', 'retro_set_audio_sample',
      'retro_set_audio_sample_batch', 'retro_set_input_poll', 'retro_set_input_state',
      'retro_set_controller_port_device', 'retro_init', 'retro_deinit', 'retro_reset',
      'retro_run', 'retro_serialize_size', 'retro_serialize', 'retro_unserialize',
      'retro_cheat_reset', 'retro_cheat_set', 'retro_load_game', 'retro_unload_game',
      'retro_get_region', 'retro_get_memory_data', 'retro_get_memory_size'
    ].forEach(n => { api[n] = wrap(n); });

    const ptrs = {
      env: M.addFunction(environment, 'iii'),
      video: M.addFunction(videoRefresh, 'viiii'),
      audioBatch: M.addFunction(audioSampleBatch, 'iii'),
      audioSingle: M.addFunction(audioSample, 'vii'),
      inputPoll: M.addFunction(inputPoll, 'v'),
      inputState: M.addFunction(inputState, 'iiiii')
    };

    if (api.retro_api_version() !== LR.API_VERSION) throw new Error('libretro API version mismatch');

    /* system info */
    const infoPtr = M._malloc(20);
    api.retro_get_system_info(infoPtr);
    const sysInfo = {
      name: readCstr(u32(infoPtr)),
      version: readCstr(u32(infoPtr + 4)),
      extensions: readCstr(u32(infoPtr + 8)),
      needFullpath: u8(infoPtr + 12) !== 0
    };
    M._free(infoPtr);

    api.retro_set_environment(ptrs.env);
    api.retro_set_video_refresh(ptrs.video);
    api.retro_set_audio_sample(ptrs.audioSingle);
    api.retro_set_audio_sample_batch(ptrs.audioBatch);
    api.retro_set_input_poll(ptrs.inputPoll);
    api.retro_set_input_state(ptrs.inputState);
    api.retro_init();

    return { module: M, sysInfo };
  }

  function loadGame(romBytes, pathName) {
    if (loaded) unloadGame();
    views();
    /* The core loads content through its VFS from info->path, so stage the
     * ROM in the Emscripten filesystem and hand it that path. */
    const FS = M.FS;
    const fname = (pathName || 'game.gen').replace(/[\\/:*?"<>|]/g, '_');
    const vpath = '/roms/' + fname;
    try { FS.mkdir('/roms'); } catch (e) { /* exists */ }
    FS.writeFile(vpath, romBytes);

    romDataAlloc = M._malloc(romBytes.length);
    U8.set(romBytes, romDataAlloc);
    pathAlloc = cstr(vpath);
    romAlloc = M._malloc(16);
    setU32(romAlloc, pathAlloc);
    setU32(romAlloc + 4, romDataAlloc);
    setU32(romAlloc + 8, romBytes.length);
    setU32(romAlloc + 12, 0);
    const ok = api.retro_load_game(romAlloc);
    if (!ok) {
      M._free(romDataAlloc); romDataAlloc = 0;
      throw new Error('retro_load_game failed');
    }
    loaded = true;

    const avPtr = M._malloc(40);
    api.retro_get_system_av_info(avPtr);
    readAvInfo(avPtr);
    M._free(avPtr);

    api.retro_set_controller_port_device(0, sixButton ? LR.DEVICE_MDPAD_6B : LR.DEVICE_MDPAD_3B);
    api.retro_set_controller_port_device(1, LR.DEVICE_NONE);

    ramPtr = api.retro_get_memory_data(LR.MEMORY_SYSTEM_RAM);
    ramSize = api.retro_get_memory_size(LR.MEMORY_SYSTEM_RAM);
    sramPtr = api.retro_get_memory_data(LR.MEMORY_SAVE_RAM);
    sramSize = api.retro_get_memory_size(LR.MEMORY_SAVE_RAM);

    stats.framesRun = 0; stats.videoFrames = 0; stats.audioSamples = 0; stats.nullVideo = 0;
    return av;
  }

  function unloadGame() {
    if (!loaded) return;
    api.retro_unload_game();
    loaded = false;
    if (romDataAlloc) { M._free(romDataAlloc); romDataAlloc = 0; }
    if (romAlloc) { M._free(romAlloc); romAlloc = 0; }
    ramPtr = ramSize = sramPtr = sramSize = 0;
  }

  function run() {
    if (!loaded) return;
    api.retro_run();
    stats.framesRun++;
    if (BP.hooks) BP.hooks.emitFrame(frameApi());
  }

  function reset() { if (loaded) api.retro_reset(); }

  /* ---- work RAM (68000 RAM, big-endian, 64KB at 0xFF0000) ---- */
  function ram() {
    if (!ramPtr || !ramSize) return null;
    views();
    return U8.subarray(ramPtr, ramPtr + ramSize);
  }
  const ramRead8 = (a) => { const r = ram(); return r ? r[a & 0xFFFF] : 0; };
  const ramRead16 = (a) => { const r = ram(); if (!r) return 0; a &= 0xFFFF; return (r[a] << 8) | r[(a + 1) & 0xFFFF]; };
  const ramRead32 = (a) => (ramRead16(a) << 16 | ramRead16(a + 2)) >>> 0;
  const ramWrite8 = (a, v) => { const r = ram(); if (r) r[a & 0xFFFF] = v & 0xFF; };
  const ramWrite16 = (a, v) => { const r = ram(); if (!r) return; a &= 0xFFFF; r[a] = (v >> 8) & 0xFF; r[(a + 1) & 0xFFFF] = v & 0xFF; };
  const ramWrite32 = (a, v) => { ramWrite16(a, (v >>> 16) & 0xFFFF); ramWrite16(a + 2, v & 0xFFFF); };

  /* ---- save states ---- */
  function stateSize() { return loaded ? api.retro_serialize_size() : 0; }
  function saveState() {
    const n = stateSize();
    if (!n) return null;
    const ptr = M._malloc(n);
    const ok = api.retro_serialize(ptr, n);
    let out = null;
    if (ok) { views(); out = U8.slice(ptr, ptr + n); }
    M._free(ptr);
    return out;
  }
  function loadState(bytes) {
    if (!loaded || !bytes) return false;
    const ptr = M._malloc(bytes.length);
    views();
    U8.set(bytes, ptr);
    const ok = api.retro_unserialize(ptr, bytes.length);
    M._free(ptr);
    if (ok && BP.hooks) BP.hooks.emitState({ loaded: true });
    return !!ok;
  }

  /* ---- SRAM (battery saves; Boogerman has none, kept generic) ---- */
  function sram() {
    if (!sramPtr || !sramSize) return null;
    views();
    return U8.subarray(sramPtr, sramPtr + sramSize);
  }

  /* ---- cheats (core decodes Game Genie "XXXX-XXXX" and PAR "AAAAAA:DDDD") ---- */
  function cheatSet(index, enabled, code) {
    api.retro_cheat_set(index, enabled ? 1 : 0, cstr(code));
  }
  function cheatReset() { api.retro_cheat_reset(); }

  /* ---- core options ---- */
  function setOption(key, value) {
    const v = variables[key];
    if (!v || !v.values.includes(value)) return false;
    v.current = value;
    variableUpdate = true;
    const saved = BP.util.store.get('coreOptions', {});
    saved[key] = value;
    BP.util.store.set('coreOptions', saved);
    return true;
  }

  function frameApi() {
    return {
      frame: stats.framesRun,
      fps: av ? av.fps : 0,
      region: loaded ? (api.retro_get_region() === LR.REGION_PAL ? 'PAL' : 'NTSC') : '?',
      ram: { read8: ramRead8, read16: ramRead16, read32: ramRead32, write8: ramWrite8, write16: ramWrite16, write32: ramWrite32, bytes: ram },
      input: BP.input,
      video: BP.video,
      audio: BP.audio,
      core: publicApi
    };
  }

  const publicApi = {
    LR, init, loadGame, unloadGame, run, reset,
    get loaded() { return loaded; },
    get av() { return av; },
    get stats() { return stats; },
    get lastVideo() { return lastVideo; },
    get pixelFormat() { return pixelFormat; },
    get variables() { return variables; },
    get sysInfo() { return sysInfoCache; },
    get region() { return loaded ? (api.retro_get_region() === LR.REGION_PAL ? 'PAL' : 'NTSC') : '?'; },
    get fastForward() { return fastForward; },
    set fastForward(v) { fastForward = !!v; },
    get sixButton() { return sixButton; },
    set sixButton(v) {
      sixButton = !!v;
      if (loaded) api.retro_set_controller_port_device(0, sixButton ? LR.DEVICE_MDPAD_6B : LR.DEVICE_MDPAD_3B);
    },
    ram, ramRead8, ramRead16, ramRead32, ramWrite8, ramWrite16, ramWrite32,
    heapU8: () => { views(); return U8; },
    stateSize, saveState, loadState,
    sram, sramSize: () => sramSize,
    cheatSet, cheatReset,
    setOption,
    onOptions(fn) { optionsListener = fn; if (Object.keys(variables).length) fn(variables); },
    onMessage(fn) { messageListener = fn; },
    frameApi,
    /* Experimental romdev debugger extensions (present in this core build;
     * signatures per romdev docs - exposed raw for future gameplay tooling). */
    get romdev() {
      if (!M) return null;
      const names = ['romdev_setreg', 'romdev_getreg', 'romdev_vramwatch_set', 'romdev_vramwatch_get',
        'romdev_dmawatch_set', 'romdev_dmawatch_get', 'romdev_watchpoint_set', 'romdev_watchpoint_get',
        'romdev_readwatch_set', 'romdev_readwatch_get', 'romdev_cheat_set', 'romdev_cheat_get',
        'romdev_cheat_read', 'romdev_range_set', 'romdev_range_get', 'romdev_pcbreak_set',
        'romdev_pcbreak_get', 'romdev_watchdog_set', 'romdev_regsnap_get', 'romdev_trace_set',
        'romdev_trace_info', 'romdev_trace_regs', 'romdev_run_pure'];
      const out = {};
      let any = false;
      for (const n of names) {
        if (typeof M['_' + n] === 'function') { out[n.replace('romdev_', '')] = M['_' + n]; any = true; }
      }
      return any ? out : null;
    }
  };
  let sysInfoCache = null;
  const origInit = init;
  /* capture sysInfo for the UI */
  async function initAndCache(opts) {
    const r = await origInit(opts);
    sysInfoCache = r.sysInfo;
    return r;
  }
  publicApi.init = initAndCache;

  return publicApi;
})();
