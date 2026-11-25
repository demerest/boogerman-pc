/* BP.main - boot sequence, run loop, and UI wiring. */
window.BP = window.BP || {};

BP.main = (function () {
  const $ = BP.util.el;
  let baseRom = null;
  let romName = window.BP_ROM_NAME || 'game.gen';
  let running = false, paused = false;
  let raf = 0, acc = 0, last = 0;
  let autotest = false, shotMode = false, shotPressed = false, shotSnapped = false;
  let selectedSlot = 0;
  let devRefresh = false;
  let watchAddr = 0xFF0000, watchSize = 16;
  const params = new URLSearchParams(location.search);

  /* ================= boot ================= */

  async function boot() {
    autotest = params.get('autotest') === '1';
    shotMode = params.get('shot') === '1';
    try {
      baseRom = BP.util.b64ToBytes(window.BP_ROM_B64);
      BP.input.attach();
      const info = await BP.core.init({ canvas: $('bp-canvas'), silent: autotest || shotMode });
      BP.video.init($('bp-canvas'), $('bp-overlay'), $('bp-stage'));
      BP.core.onOptions(buildOptionsUI);
      BP.core.onMessage(m => BP.util.toast(m));
      BP.mods.syncCheats();
      buildStaticUI();
      $('bp-core-ver').textContent = info.sysInfo.name + ' ' + info.sysInfo.version;

      if (autotest || shotMode) {
        startGame(true);
        if (autotest) runAutotest();
        const pressAt = parseInt(params.get('pressStart') || '0', 10);
        if (pressAt > 0) setTimeout(pressStart, pressAt);
      } else {
        $('bp-boot').classList.remove('hidden');
        $('bp-boot-btn').addEventListener('click', () => {
          $('bp-boot').classList.add('hidden');
          startGame(false);
        });
      }
    } catch (e) {
      console.error(e);
      const box = $('bp-error');
      box.classList.remove('hidden');
      box.textContent = 'Boot failed: ' + (e && e.message ? e.message : e);
    }
  }

  function pressStart() {
    window.dispatchEvent(new KeyboardEvent('keydown', { code: 'Enter', key: 'Enter', bubbles: true }));
    setTimeout(() => window.dispatchEvent(new KeyboardEvent('keyup', { code: 'Enter', key: 'Enter', bubbles: true })), 120);
    const chip = $('bp-stat-frame');
    if (chip) chip.dataset.pressed = '1';
  }

  function startGame(noAudio) {
    const { bytes, applied } = BP.mods.applyPatches(baseRom);
    const av = BP.core.loadGame(bytes, romName);
    BP.states.sramLoad();
    BP.cheats.reapplyAll();
    if (!noAudio) BP.audio.start(av.sampleRate);
    BP.video.resize();
    BP.hooks.emitBoot(BP.core.frameApi());
    running = true; paused = false;
    last = performance.now(); acc = 0;
    if (shotMode) {
      /* timer-driven so headless virtual time can fast-forward the game */
      const shotLoop = () => {
        if (!paused) BP.core.run();
        BP.video.present();
        throttledStatus();
        const pf = parseInt(params.get('pressFrame') || '0', 10);
        if (pf > 0 && BP.core.stats.framesRun >= pf && !shotPressed) {
          shotPressed = true;
          pressStart();
        }
        const sf = parseInt(params.get('snapFrame') || '0', 10);
        if (sf > 0 && BP.core.stats.framesRun >= sf && !shotSnapped) {
          shotSnapped = true;
          /* embed a compositor-independent PNG snapshot in the DOM */
          const img = document.createElement('img');
          img.id = 'bp-snap';
          img.src = BP.video.screenshot();
          img.style.cssText = 'position:fixed;left:0;top:0;z-index:99;image-rendering:pixelated;';
          document.body.appendChild(img);
        }
        const fastLimit = Math.max(1200, sf + 50);
        setTimeout(shotLoop, BP.core.stats.framesRun < fastLimit ? 0 : 100);
      };
      setTimeout(shotLoop, 0);
      const shotRepaint = () => { BP.video.present(); requestAnimationFrame(shotRepaint); };
      requestAnimationFrame(shotRepaint);
    } else if (!autotest) {
      cancelAnimationFrame(raf); raf = requestAnimationFrame(loop);
    }
    if (applied.length) BP.util.toast('Patches applied: ' + applied.join(', '));
    updateStatus();
    $('bp-pause-btn').textContent = 'Pause';
  }

  function reboot() {
    if (!running) return;
    BP.states.sramSave();
    BP.core.unloadGame();
    startGame(!BP.audio.running);
    BP.util.toast('Rebooted');
  }

  /* ================= run loop ================= */

  function loop(now) {
    raf = requestAnimationFrame(loop);
    if (!running) return;
    let dt = (now - last) / 1000;
    last = now;
    if (dt > 0.25) dt = 0.25;
    if (!paused) {
      acc += dt;
      const fps = BP.core.av.fps || 50;
      const step = 1 / fps;
      const maxSteps = BP.core.fastForward ? 10 : 3;
      let n = 0;
      while (acc >= step && n < maxSteps) { BP.core.run(); acc -= step; n++; }
      if (acc > step * 4) acc = 0; /* never spiral */
    }
    BP.video.present();
    if (devRefresh) renderDev();
    throttledStatus();
  }

  /* autotest: setTimeout-driven so headless virtual time can exercise it */
  function runAutotest() {
    const TARGET = 180;
    function step() {
      if (!BP.core.loaded) return finish(false, 'core not loaded');
      BP.core.run();
      BP.video.present();
      if (BP.core.stats.framesRun >= TARGET) return finish(true, '');
      setTimeout(step, 0);
    }
    function finish(ok, err) {
      const s = BP.core.stats;
      const result = {
        ok, err,
        frames: s.framesRun, videoFrames: s.videoFrames, nullVideo: s.nullVideo,
        audioSamples: s.audioSamples,
        region: BP.core.region, fps: BP.core.av.fps, sampleRate: BP.core.av.sampleRate,
        baseWidth: BP.core.av.baseWidth, baseHeight: BP.core.av.baseHeight,
        ramSize: BP.core.ram() ? BP.core.ram().length : 0,
        stateSize: BP.core.stateSize(),
        pixelFormat: BP.core.pixelFormat
      };
      const el = $('bp-autotest-status');
      el.textContent = 'AUTOTEST ' + (ok ? 'PASS' : 'FAIL') + ' ' + JSON.stringify(result);
      document.title = 'AUTOTEST ' + (ok ? 'PASS' : 'FAIL');
    }
    setTimeout(step, 0);
  }

  let statusLast = 0;
  function throttledStatus() {
    const now = performance.now();
    if (now - statusLast > 500) { statusLast = now; updateStatus(); }
  }

  function updateStatus() {
    if (!BP.core.av) return;
    const av = BP.core.av;
    $('bp-stat-region').textContent = BP.core.region;
    $('bp-stat-res').textContent = av.baseWidth + '\u00D7' + av.baseHeight;
    $('bp-stat-fps').textContent = (running && !paused ? BP.video.fps.toFixed(1) : '0.0') + ' fps';
    $('bp-stat-frame').textContent = 'f' + BP.core.stats.framesRun;
    $('bp-stat-audio').textContent = BP.audio.running ? (BP.audio.muted ? 'muted' : '44.1kHz') : 'off';
  }

  /* ================= UI ================= */

  function buildStaticUI() {
    /* tabs */
    document.querySelectorAll('.bp-tab').forEach(btn => {
      btn.addEventListener('click', () => {
        document.querySelectorAll('.bp-tab').forEach(b => b.classList.remove('active'));
        document.querySelectorAll('.bp-panel').forEach(p => p.classList.remove('active'));
        btn.classList.add('active');
        $('panel-' + btn.dataset.tab).classList.add('active');
        if (btn.dataset.tab === 'dev') renderDev();
      });
    });

    /* header buttons */
    $('bp-pause-btn').addEventListener('click', togglePause);
    $('bp-ff-btn').addEventListener('click', () => {
      BP.core.fastForward = !BP.core.fastForward;
      $('bp-ff-btn').classList.toggle('on', BP.core.fastForward);
    });
    $('bp-reset-btn').addEventListener('click', () => { BP.core.reset(); BP.util.toast('Console reset'); });
    $('bp-shot-btn').addEventListener('click', takeScreenshot);
    $('bp-full-btn').addEventListener('click', () => {
      const el = $('bp-stage');
      if (document.fullscreenElement) document.exitFullscreen();
      else el.requestFullscreen().catch(() => {});
    });
    $('bp-help-btn').addEventListener('click', () => $('bp-help').classList.toggle('hidden'));
    $('bp-panel-toggle').addEventListener('click', () => $('bp-aside').classList.toggle('open'));

    /* video panel */
    const scaleSel = $('bp-scale');
    scaleSel.value = BP.video.scaleMode;
    scaleSel.addEventListener('change', () => BP.video.setScaleMode(scaleSel.value));
    buildShaderUI();
    buildGradeUI();

    /* input panel */
    buildInputUI();

    /* cheats panel */
    buildCheatsUI();

    /* states panel */
    buildStatesUI();

    /* mods panel */
    buildModsUI();

    /* system panel */
    $('bp-volume').value = BP.audio.volume;
    $('bp-volume').addEventListener('input', e => BP.audio.setVolume(parseFloat(e.target.value)));
    $('bp-mute').checked = BP.audio.muted;
    $('bp-mute').addEventListener('change', e => { BP.audio.setMuted(e.target.checked); updateStatus(); });
    $('bp-rom-file').addEventListener('change', e => {
      const f = e.target.files[0];
      if (!f) return;
      const rd = new FileReader();
      rd.onload = () => {
        baseRom = new Uint8Array(rd.result);
        romName = f.name;
        BP.util.toast('Loaded ROM: ' + f.name);
        if (running) reboot(); else startGame(false);
      };
      rd.readAsArrayBuffer(f);
      e.target.value = '';
    });

    /* dev panel */
    buildDevUI();

    /* touch controls */
    if (window.matchMedia('(pointer: coarse)').matches || 'ontouchstart' in window) {
      $('bp-touch').classList.remove('hidden');
    }
    document.querySelectorAll('#bp-touch [data-retro]').forEach(btn => {
      const id = parseInt(btn.dataset.retro, 10);
      const down = (e) => { e.preventDefault(); BP.input.setVirtual(0, id, true); btn.classList.add('held'); };
      const up = (e) => { e.preventDefault(); BP.input.setVirtual(0, id, false); btn.classList.remove('held'); };
      btn.addEventListener('pointerdown', down);
      btn.addEventListener('pointerup', up);
      btn.addEventListener('pointercancel', up);
      btn.addEventListener('pointerleave', up);
    });

    /* drag & drop */
    window.addEventListener('dragover', e => e.preventDefault());
    window.addEventListener('drop', async e => {
      e.preventDefault();
      for (const f of e.dataTransfer.files) {
        const lower = f.name.toLowerCase();
        if (/\.(gen|md|bin|smd|sms|gg)$/.test(lower)) {
          const buf = await f.arrayBuffer();
          baseRom = new Uint8Array(buf);
          romName = f.name;
          BP.util.toast('Loaded ROM: ' + f.name);
          if (running) reboot();
        } else if (lower.endsWith('.state')) {
          const buf = await f.arrayBuffer();
          const r = BP.states.importSlot(selectedSlot, new Uint8Array(buf));
          BP.util.toast(r.ok ? 'State imported to slot ' + (selectedSlot + 1) : r.error);
        } else if (/\.(ips|bps|json|js)$/.test(lower)) {
          const r = await BP.mods.loadFile(f);
          BP.util.toast(r.ok ? 'Mod loaded: ' + f.name + (r.needsReboot ? ' (reboot to apply patches)' : '') : r.error);
          if (r.ok && r.needsReboot && running) reboot();
        } else {
          BP.util.toast('Unsupported file: ' + f.name);
        }
      }
    });

    /* global shortcuts */
    window.addEventListener('keydown', e => {
      const a = document.activeElement;
      if (a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA' || a.tagName === 'SELECT')) return;
      switch (e.code) {
        case 'KeyP': togglePause(); break;
        case 'KeyM': BP.audio.setMuted(!BP.audio.muted); $('bp-mute').checked = BP.audio.muted; updateStatus(); break;
        case 'KeyH': $('bp-help').classList.toggle('hidden'); break;
        case 'F5': e.preventDefault(); if (BP.states.save(selectedSlot)) BP.util.toast('Saved slot ' + (selectedSlot + 1)); break;
        case 'F8': e.preventDefault(); if (BP.states.load(selectedSlot)) BP.util.toast('Loaded slot ' + (selectedSlot + 1)); break;
        case 'F9': e.preventDefault(); takeScreenshot(); break;
        case 'Period': if (paused && running) { BP.core.run(); BP.video.present(); } break;
        case 'Escape': BP.input.cancelRemap(); $('bp-help').classList.add('hidden'); break;
      }
    });

    BP.states.onChange(renderStates);
    BP.cheats.onChange(renderCheats);
    BP.mods.onChange(renderMods);
  }

  function togglePause() {
    if (!running) return;
    paused = !paused;
    $('bp-pause-btn').textContent = paused ? 'Resume' : 'Pause';
    $('bp-pause-btn').classList.toggle('on', paused);
    if (!paused) { last = performance.now(); acc = 0; }
    updateStatus();
  }

  function takeScreenshot() {
    try {
      const url = BP.video.screenshot();
      const a = document.createElement('a');
      a.href = url;
      a.download = 'boogerman-' + Date.now() + '.png';
      a.click();
      BP.util.toast('Screenshot saved');
    } catch (e) { BP.util.toast('Screenshot failed: ' + e.message); }
  }

  /* ---- video panel ---- */
  function buildShaderUI() {
    const sel = $('bp-shader-add');
    sel.innerHTML = '';
    for (const def of BP.shaders.all()) {
      const o = document.createElement('option');
      o.value = def.name;
      o.textContent = def.label;
      sel.appendChild(o);
    }
    $('bp-shader-add-btn').onclick = () => {
      const name = sel.value;
      const def = BP.shaders.get(name);
      if (!def) return;
      const params = {};
      def.params.forEach(p => { params[p.name] = p.def; });
      BP.shaders.setChain([...BP.shaders.chain, { name, params }]);
      renderShaderChain();
    };
    renderShaderChain();
  }

  function renderShaderChain() {
    const box = $('bp-shader-chain');
    box.innerHTML = '';
    const chain = BP.shaders.chain;
    if (!chain.length) {
      box.innerHTML = '<div class="bp-hint">No post passes - raw pixels (nearest).</div>';
    }
    chain.forEach((pass, i) => {
      const def = BP.shaders.get(pass.name);
      const card = document.createElement('div');
      card.className = 'bp-card';
      const head = document.createElement('div');
      head.className = 'bp-card-head';
      head.innerHTML = '<strong>' + (def ? def.label : pass.name) + '</strong>';
      const up = document.createElement('button'); up.textContent = '\u2191'; up.title = 'Move up';
      up.onclick = () => { if (i > 0) { const c = [...chain]; [c[i - 1], c[i]] = [c[i], c[i - 1]]; BP.shaders.setChain(c); renderShaderChain(); } };
      const down = document.createElement('button'); down.textContent = '\u2193'; down.title = 'Move down';
      down.onclick = () => { if (i < chain.length - 1) { const c = [...chain]; [c[i + 1], c[i]] = [c[i], c[i + 1]]; BP.shaders.setChain(c); renderShaderChain(); } };
      const rm = document.createElement('button'); rm.textContent = '\u00D7'; rm.title = 'Remove';
      rm.onclick = () => { BP.shaders.setChain(chain.filter((_, j) => j !== i)); renderShaderChain(); };
      head.append(up, down, rm);
      card.appendChild(head);
      if (def) def.params.forEach(p => {
        const row = document.createElement('label');
        row.className = 'bp-slider';
        const val = pass.params[p.name] !== undefined ? pass.params[p.name] : p.def;
        row.innerHTML = '<span>' + p.label + '</span><input type="range" min="' + p.min + '" max="' + p.max + '" step="' + p.step + '" value="' + val + '"><output>' + val + '</output>';
        const input = row.querySelector('input');
        const out = row.querySelector('output');
        input.addEventListener('input', () => {
          pass.params[p.name] = parseFloat(input.value);
          out.textContent = input.value;
          BP.shaders.setChain([...BP.shaders.chain]);
        });
        card.appendChild(row);
      });
      box.appendChild(card);
    });
  }

  function buildGradeUI() {
    const box = $('bp-grade');
    box.innerHTML = '';
    const defs = [
      { name: 'uBrightness', label: 'Brightness', min: -0.5, max: 0.5, step: 0.01 },
      { name: 'uContrast', label: 'Contrast', min: 0.5, max: 1.5, step: 0.01 },
      { name: 'uSaturation', label: 'Saturation', min: 0, max: 2, step: 0.01 }
    ];
    defs.forEach(d => {
      const row = document.createElement('label');
      row.className = 'bp-slider';
      const v = BP.shaders.grade[d.name];
      row.innerHTML = '<span>' + d.label + '</span><input type="range" min="' + d.min + '" max="' + d.max + '" step="' + d.step + '" value="' + v + '"><output>' + v + '</output>';
      const input = row.querySelector('input');
      const out = row.querySelector('output');
      input.addEventListener('input', () => {
        BP.shaders.setGrade({ [d.name]: parseFloat(input.value) });
        out.textContent = input.value;
      });
      box.appendChild(row);
    });
  }

  /* ---- input panel ---- */
  function buildInputUI() {
    const presetSel = $('bp-input-preset');
    presetSel.innerHTML = '';
    for (const key of Object.keys(BP.input.PRESETS)) {
      const o = document.createElement('option');
      o.value = key; o.textContent = BP.input.PRESETS[key].label;
      presetSel.appendChild(o);
    }
    const custom = document.createElement('option');
    custom.value = 'custom'; custom.textContent = 'Custom';
    presetSel.appendChild(custom);
    presetSel.value = BP.input.presetName;
    presetSel.addEventListener('change', () => {
      if (presetSel.value !== 'custom') { BP.input.applyPreset(presetSel.value); renderInputMap(); }
    });
    $('bp-6btn').addEventListener('change', e => { BP.core.sixButton = e.target.checked; });
    renderInputMap();
  }

  function renderInputMap() {
    const box = $('bp-input-map');
    box.innerHTML = '';
    const ids = [BP.input.LR.UP, BP.input.LR.DOWN, BP.input.LR.LEFT, BP.input.LR.RIGHT,
      BP.input.LR.Y, BP.input.LR.B, BP.input.LR.A, BP.input.LR.L, BP.input.LR.X, BP.input.LR.R,
      BP.input.LR.START, BP.input.LR.SELECT];
    ids.forEach(id => {
      const row = document.createElement('div');
      row.className = 'bp-input-row';
      const label = document.createElement('span');
      label.textContent = BP.input.BUTTON_LABELS[id];
      const key = document.createElement('button');
      key.className = 'bp-key';
      key.textContent = prettyKey(BP.input.map[id]);
      key.onclick = () => {
        key.textContent = 'press a key...';
        BP.input.startRemap(id, () => { renderInputMap(); $('bp-input-preset').value = 'custom'; });
      };
      const turbo = document.createElement('label');
      turbo.className = 'bp-turbo';
      turbo.innerHTML = '<input type="checkbox"' + (BP.input.turbo.has(id) ? ' checked' : '') + '> turbo';
      turbo.querySelector('input').addEventListener('change', e => BP.input.setTurbo(id, e.target.checked));
      row.append(label, key, turbo);
      box.appendChild(row);
    });
  }

  function prettyKey(code) {
    if (!code) return '-';
    return code.replace('Key', '').replace('Arrow', '').replace('ShiftRight', 'RShift').replace('ShiftLeft', 'LShift');
  }

  /* ---- cheats panel ---- */
  function buildCheatsUI() {
    $('bp-cheat-add-btn').addEventListener('click', () => {
      const code = $('bp-cheat-code').value;
      const label = $('bp-cheat-label').value;
      const r = BP.cheats.add(code, label);
      if (r.ok) {
        $('bp-cheat-code').value = '';
        $('bp-cheat-label').value = '';
        BP.util.toast(r.kind + ' code added' + (r.decoded ? ' (addr ' + BP.util.hex(r.decoded.address, 6) + ')' : ''));
      } else BP.util.toast(r.error);
    });
    renderCheats();
  }

  function renderCheats() {
    const box = $('bp-cheat-list');
    if (!box) return;
    box.innerHTML = '';
    BP.cheats.list.forEach((c, i) => {
      const row = document.createElement('div');
      row.className = 'bp-cheat-row';
      const cb = document.createElement('input');
      cb.type = 'checkbox'; cb.checked = c.enabled;
      cb.addEventListener('change', () => BP.cheats.setEnabled(i, cb.checked));
      const txt = document.createElement('div');
      const v = BP.cheats.validate(c.code);
      txt.innerHTML = '<strong>' + c.code + '</strong> <span class="bp-hint">' + (c.label || '') + '</span>' +
        (v && v.decoded ? '<br><span class="bp-hint">addr ' + BP.util.hex(v.decoded.address, 6) + ' data ' + BP.util.hex(v.decoded.data, 4) + '</span>' : '');
      const rm = document.createElement('button');
      rm.textContent = '\u00D7';
      rm.onclick = () => BP.cheats.remove(i);
      row.append(cb, txt, rm);
      box.appendChild(row);
    });
    if (!BP.cheats.list.length) box.innerHTML = '<div class="bp-hint">No cheats. Add a Game Genie (XXXX-XXXX) or PAR (AAAAAA:DDDD) code above, or enable a cheat mod.</div>';
  }

  /* ---- states panel ---- */
  function buildStatesUI() {
    $('bp-state-import').addEventListener('change', async e => {
      const f = e.target.files[0];
      if (!f) return;
      const buf = await f.arrayBuffer();
      const r = BP.states.importSlot(selectedSlot, new Uint8Array(buf));
      BP.util.toast(r.ok ? 'Imported to slot ' + (selectedSlot + 1) : r.error);
      e.target.value = '';
    });
    renderStates();
  }

  function renderStates() {
    const box = $('bp-states');
    if (!box) return;
    box.innerHTML = '';
    BP.states.slots.forEach((s, i) => {
      const card = document.createElement('div');
      card.className = 'bp-state-card' + (i === selectedSlot ? ' selected' : '');
      card.addEventListener('click', () => { selectedSlot = i; renderStates(); });
      const thumb = document.createElement('div');
      thumb.className = 'bp-state-thumb';
      if (s && s.thumb) thumb.style.backgroundImage = 'url(' + s.thumb + ')';
      else thumb.textContent = s ? 'STATE' : 'EMPTY';
      const num = document.createElement('div');
      num.className = 'bp-state-num';
      num.textContent = 'Slot ' + (i + 1) + (s ? ' \u00B7 ' + new Date(s.time).toLocaleTimeString() : '');
      const btns = document.createElement('div');
      btns.className = 'bp-state-btns';
      const save = document.createElement('button'); save.textContent = 'Save';
      save.onclick = (e) => { e.stopPropagation(); if (BP.states.save(i)) BP.util.toast('Saved slot ' + (i + 1)); };
      const load = document.createElement('button'); load.textContent = 'Load'; load.disabled = !s;
      load.onclick = (e) => { e.stopPropagation(); if (BP.states.load(i)) BP.util.toast('Loaded slot ' + (i + 1)); };
      const exp = document.createElement('button'); exp.textContent = '\u2913'; exp.title = 'Export .state'; exp.disabled = !s;
      exp.onclick = (e) => { e.stopPropagation(); BP.states.exportSlot(i); };
      const clr = document.createElement('button'); clr.textContent = '\u00D7'; clr.title = 'Clear'; clr.disabled = !s;
      clr.onclick = (e) => { e.stopPropagation(); BP.states.clear(i); };
      btns.append(save, load, exp, clr);
      card.append(thumb, num, btns);
      box.appendChild(card);
    });
  }

  /* ---- mods panel ---- */
  function buildModsUI() {
    $('bp-mod-file').addEventListener('change', async e => {
      const f = e.target.files[0];
      if (!f) return;
      const r = await BP.mods.loadFile(f);
      BP.util.toast(r.ok ? 'Mod loaded: ' + f.name : r.error);
      if (r.ok && r.needsReboot && running) reboot();
      e.target.value = '';
    });
    $('bp-mod-reboot').addEventListener('click', reboot);
    renderMods();
  }

  function renderMods() {
    const box = $('bp-mod-list');
    if (!box) return;
    box.innerHTML = '';
    const mods = BP.mods.all;
    if (!mods.length) box.innerHTML = '<div class="bp-hint">No mods registered. Drop a .js/.json/.ips/.bps file anywhere on this page.</div>';
    mods.forEach(def => {
      const row = document.createElement('div');
      row.className = 'bp-mod-row';
      const cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.checked = BP.mods.isEnabled(def.id);
      cb.addEventListener('change', () => {
        BP.mods.setEnabled(def.id, cb.checked);
        if (def.patches && def.patches.length) BP.util.toast('Patch mod toggled - reboot to apply');
      });
      const txt = document.createElement('div');
      const badges = [];
      if (def.patches && def.patches.length) badges.push('ROM patch');
      if (def.cheats) badges.push('cheats');
      if (def.shaders) badges.push('shaders');
      if (def.hooks) badges.push('script');
      txt.innerHTML = '<strong>' + def.name + '</strong> <span class="bp-hint">' + badges.join(' \u00B7 ') + '</span>' +
        '<br><span class="bp-hint">' + (def.description || '') + '</span>';
      row.append(cb, txt);
      box.appendChild(row);
    });
    $('bp-mod-reboot').classList.toggle('hidden', !BP.mods.anyPatchEnabled());
  }

  /* ---- system panel: core options ---- */
  function buildOptionsUI(vars) {
    const box = $('bp-core-options');
    if (!box) return;
    box.innerHTML = '';
    const keys = Object.keys(vars).sort();
    keys.forEach(key => {
      const v = vars[key];
      if (!v.values.length) return;
      const row = document.createElement('label');
      row.className = 'bp-option-row';
      const span = document.createElement('span');
      span.textContent = v.label;
      span.title = key;
      const sel = document.createElement('select');
      v.values.forEach(val => {
        const o = document.createElement('option');
        o.value = val; o.textContent = val;
        sel.appendChild(o);
      });
      sel.value = v.current;
      sel.addEventListener('change', () => {
        BP.core.setOption(key, sel.value);
        BP.util.toast(v.label + ' = ' + sel.value + ' (live)');
        setTimeout(updateStatus, 300);
      });
      row.append(span, sel);
      box.appendChild(row);
    });
  }

  /* ---- dev panel: RAM workbench ---- */
  function buildDevUI() {
    $('bp-dev-refresh').addEventListener('change', e => { devRefresh = e.target.checked; });
    $('bp-dev-page-prev').addEventListener('click', () => { devPage = Math.max(0, devPage - 256); renderDev(); });
    $('bp-dev-page-next').addEventListener('click', () => { devPage = Math.min(0xFFFF - 255, devPage + 256); renderDev(); });
    $('bp-dev-page-input').addEventListener('change', e => {
      const v = parseInt(e.target.value, 16);
      if (!isNaN(v)) { devPage = BP.util.clamp(v, 0, 0xFFFF) & 0xFF00; renderDev(); }
    });
    $('bp-dev-watch-addr').addEventListener('change', e => {
      const v = parseInt(e.target.value, 16);
      if (!isNaN(v)) watchAddr = v & 0xFFFF;
    });
    $('bp-dev-watch-size').addEventListener('change', e => { watchSize = parseInt(e.target.value, 10); });
    $('bp-dev-poke-btn').addEventListener('click', () => {
      const a = parseInt($('bp-dev-poke-addr').value, 16);
      const v = parseInt($('bp-dev-poke-value').value, 16);
      const size = parseInt($('bp-dev-poke-size').value, 10);
      if (isNaN(a) || isNaN(v)) { BP.util.toast('Enter hex address and value'); return; }
      if (!BP.core.ram()) { BP.util.toast('No RAM - game not loaded'); return; }
      if (size === 8) BP.core.ramWrite8(a, v);
      else if (size === 16) BP.core.ramWrite16(a, v);
      else BP.core.ramWrite32(a, v);
      BP.util.toast('Wrote ' + BP.util.hex(v) + ' -> ' + BP.util.hex(a, 6));
      renderDev();
    });
    const rd = BP.core.romdev;
    $('bp-dev-romdev').textContent = rd
      ? 'romdev debugger extensions PRESENT (' + Object.keys(rd).length + ' functions: ' + Object.keys(rd).slice(0, 8).join(', ') + ', ...). Experimental - see PORTING.md.'
      : 'romdev debugger extensions not present in this core build.';
  }

  let devPage = 0xFF00;
  function renderDev() {
    const ram = BP.core.ram();
    const hexBox = $('bp-dev-hex');
    if (!ram) { hexBox.textContent = 'game not loaded'; return; }
    $('bp-dev-page-input').value = BP.util.hex(devPage, 4).slice(2);
    let out = '';
    for (let row = 0; row < 16; row++) {
      const off = devPage + row * 16;
      if (off > 0xFFFF) break;
      let ascii = '';
      let hexs = '';
      for (let i = 0; i < 16; i++) {
        const b = ram[(off + i) & 0xFFFF];
        hexs += b.toString(16).padStart(2, '0') + ' ';
        ascii += (b >= 32 && b <= 126) ? String.fromCharCode(b) : '.';
      }
      out += BP.util.hex(off, 4).slice(2) + '  ' + hexs + ' ' + ascii + '\n';
    }
    hexBox.textContent = out;
    const w = watchSize === 8 ? BP.core.ramRead8(watchAddr)
      : watchSize === 16 ? BP.core.ramRead16(watchAddr)
      : BP.core.ramRead32(watchAddr);
    $('bp-dev-watch-value').textContent = BP.util.hex(w, watchSize / 4);
  }

  return { boot, reboot, startGame, get running() { return running; }, get paused() { return paused; } };
})();

document.addEventListener('DOMContentLoaded', () => BP.main.boot());
