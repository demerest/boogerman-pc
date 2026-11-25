/* BP.mods - the enhancement pack system.
 *
 * A mod is a plain object registered via BP.mods.register():
 * {
 *   id, name, version, author, description,
 *   patches: [{ format:'ips'|'bps', b64:'...' }],   // applied to ROM at boot
 *   cheats:  [{ code:'XXXX-XXXX', label:'...' }],    // added to cheat list
 *   shaders: [{ name, label, frag, params }],        // registered in BP.shaders
 *   hooks:   { frame(api){...}, boot(api){...} },    // live gameplay scripting
 *   enabledByDefault: false
 * }
 *
 * Built-in mods are <script> tags in index.html (mods/*.js). Users can drop
 * .json / .js / .ips / .bps files onto the page or use the Mods tab loader.
 */
window.BP = window.BP || {};

BP.mods = (function () {
  const registry = new Map();
  let enabled = BP.util.store.get('modsEnabled', {});
  let listeners = [];
  let hookDisposers = new Map();

  function notify() { listeners.forEach(fn => { try { fn([...registry.values()]); } catch (e) { console.error(e); } }); }

  function register(def) {
    if (!def || !def.id) throw new Error('Mod needs an id');
    if (registry.has(def.id)) {
      console.warn('[BP.mods] replacing mod', def.id);
      unregister(def.id);
    }
    registry.set(def.id, def);
    if (!(def.id in enabled)) enabled[def.id] = !!def.enabledByDefault;

    /* shaders are available regardless of enabled state (chain decides) */
    if (def.shaders) {
      for (const s of def.shaders) BP.shaders.register(s.name, s);
    }
    if (isEnabled(def.id)) attachHooks(def);
    notify();
    return def;
  }

  function attachHooks(def) {
    if (!def.hooks || hookDisposers.has(def.id)) return;
    const disposers = [];
    if (def.hooks.frame) disposers.push(BP.hooks.onFrame(def.hooks.frame));
    if (def.hooks.boot) disposers.push(BP.hooks.onBoot(def.hooks.boot));
    if (def.hooks.audio) disposers.push(BP.hooks.onAudio(def.hooks.audio));
    hookDisposers.set(def.id, disposers);
  }

  function detachHooks(id) {
    const d = hookDisposers.get(id);
    if (d) { d.forEach(fn => fn()); hookDisposers.delete(id); }
  }

  function unregister(id) {
    detachHooks(id);
    registry.delete(id);
    notify();
  }

  function isEnabled(id) { return !!enabled[id]; }

  function setEnabled(id, on) {
    enabled[id] = !!on;
    BP.util.store.set('modsEnabled', enabled);
    const def = registry.get(id);
    if (def) { if (on) attachHooks(def); else detachHooks(id); }
    notify();
  }

  function hasPatches(id) {
    const def = registry.get(id);
    return !!(def && def.patches && def.patches.length);
  }

  function anyPatchEnabled() {
    for (const [id, def] of registry) {
      if (isEnabled(id) && def.patches && def.patches.length) return true;
    }
    return false;
  }

  /* Apply all enabled patch mods to the base ROM, in registration order. */
  function applyPatches(romBytes) {
    let out = romBytes;
    const applied = [];
    for (const [id, def] of registry) {
      if (!isEnabled(id) || !def.patches) continue;
      for (const p of def.patches) {
        const bytes = BP.util.b64ToBytes(p.b64);
        out = BP.patches.apply(out, bytes);
        applied.push(def.name + ' (' + (p.format || 'patch').toUpperCase() + ')');
      }
    }
    return { bytes: out, applied };
  }

  /* Add mod cheats to the cheat list (once). */
  function syncCheats() {
    for (const [id, def] of registry) {
      if (!def.cheats) continue;
      for (const c of def.cheats) {
        if (!BP.cheats.list.some(x => x.code === c.code.toUpperCase())) {
          const r = BP.cheats.add(c.code, '[' + def.name + '] ' + (c.label || ''));
          if (!r.ok) console.warn('[BP.mods] cheat rejected:', c.code, r.error);
        }
      }
    }
  }

  /* ---- user mod files ---- */
  function loadFile(file) {
    return new Promise((resolve) => {
      const reader = new FileReader();
      reader.onload = () => {
        const name = file.name;
        const lower = name.toLowerCase();
        try {
          if (lower.endsWith('.ips') || lower.endsWith('.bps')) {
            const bytes = new Uint8Array(reader.result);
            const format = lower.endsWith('.ips') ? 'ips' : 'bps';
            register({
              id: 'user:' + name,
              name: name,
              description: 'User-supplied ' + format.toUpperCase() + ' ROM patch',
              patches: [{ format, b64: BP.util.bytesToB64(bytes) }]
            });
            resolve({ ok: true, kind: format, needsReboot: true });
          } else if (lower.endsWith('.json')) {
            const def = JSON.parse(reader.result);
            def.id = def.id || 'user:' + name;
            def.name = def.name || name;
            register(def);
            syncCheats();
            resolve({ ok: true, kind: 'json', needsReboot: !!(def.patches && def.patches.length) });
          } else if (lower.endsWith('.js')) {
            /* user's own script, executed in page scope with BP available */
            const fn = new Function(reader.result);
            fn();
            resolve({ ok: true, kind: 'js', needsReboot: anyPatchEnabled() });
          } else {
            resolve({ ok: false, error: 'Unsupported mod file: ' + name });
          }
        } catch (e) {
          resolve({ ok: false, error: e.message });
        }
      };
      reader.onerror = () => resolve({ ok: false, error: 'Read failed' });
      if (lower.endsWith('.json') || lower.endsWith('.js')) reader.readAsText(file);
      else reader.readAsArrayBuffer(file);
    });
  }

  return {
    register, unregister, setEnabled, isEnabled, hasPatches, anyPatchEnabled,
    applyPatches, syncCheats, loadFile,
    get all() { return [...registry.values()]; },
    onChange(fn) { listeners.push(fn); fn([...registry.values()]); }
  };
})();
