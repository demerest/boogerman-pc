/* BP.cheats - Game Genie / Pro Action Replay cheat management.
 * The core decodes codes natively (retro_cheat_set); this module validates,
 * decodes for display (same algorithm as the core), persists and applies.
 */
window.BP = window.BP || {};

BP.cheats = (function () {
  const GG_ALPHABET = 'ABCDEFGHJKLMNPRSTVWXYZ0123456789';
  let list = BP.util.store.get('cheats', []);
  let listeners = [];

  /* Decode a Genesis Game Genie code exactly like the core's decode_cheat(). */
  function decodeGG(code) {
    const c = code.toUpperCase().replace('-', '');
    if (c.length !== 8) return null;
    let data = 0, address = 0;
    for (let i = 0; i < 8; i++) {
      const n = GG_ALPHABET.indexOf(c[i]);
      if (n < 0) return null;
      switch (i) {
        case 0: data |= n << 3; break;
        case 1: data |= n >> 2; address |= (n & 3) << 14; break;
        case 2: address |= n << 9; break;
        case 3: address |= (n & 0xF) << 20 | (n >> 4) << 8; break;
        case 4: data |= (n & 1) << 12; address |= (n >> 1) << 16; break;
        case 5: data |= (n & 1) << 15 | (n >> 1) << 8; break;
        case 6: data |= (n >> 3) << 13; address |= (n & 7) << 5; break;
        case 7: address |= n; break;
      }
    }
    return { address: address >>> 0, data: data & 0xFFFF };
  }

  function validate(code) {
    const s = code.trim().toUpperCase();
    if (/^[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(s)) {
      const letters = s.replace('-', '');
      for (const ch of letters) if (!GG_ALPHABET.includes(ch)) return null;
      return { code: s, kind: 'Game Genie', decoded: decodeGG(s) };
    }
    if (/^[0-9A-F]{6}:[0-9A-F]{4}$/.test(s)) {
      return {
        code: s, kind: 'PAR',
        decoded: { address: parseInt(s.slice(0, 6), 16), data: parseInt(s.slice(7), 16) }
      };
    }
    return null;
  }

  function notify() { listeners.forEach(fn => { try { fn(list); } catch (e) { console.error(e); } }); }

  function add(code, label) {
    const v = validate(code);
    if (!v) return { ok: false, error: 'Invalid code. Use Game Genie XXXX-XXXX or PAR AAAAAA:DDDD.' };
    if (list.some(c => c.code === v.code)) return { ok: false, error: 'Code already in list.' };
    list.push({ code: v.code, label: label || v.kind + ' cheat', enabled: false });
    BP.util.store.set('cheats', list);
    notify();
    return { ok: true, decoded: v.decoded, kind: v.kind };
  }

  function remove(i) {
    if (BP.core.loaded) BP.core.cheatSet(i, false, list[i].code);
    list.splice(i, 1);
    BP.util.store.set('cheats', list);
    reapplyAll();
    notify();
  }

  function setEnabled(i, on) {
    list[i].enabled = !!on;
    BP.util.store.set('cheats', list);
    if (BP.core.loaded) BP.core.cheatSet(i, list[i].enabled, list[i].code);
    notify();
  }

  /* Cheat indices shift when entries are removed; reset + reapply keeps them stable. */
  function reapplyAll() {
    if (!BP.core.loaded) return;
    BP.core.cheatReset();
    list.forEach((c, i) => { if (c.enabled) BP.core.cheatSet(i, true, c.code); });
  }

  return {
    decodeGG, validate, add, remove, setEnabled, reapplyAll,
    get list() { return list; },
    onChange(fn) { listeners.push(fn); fn(list); }
  };
})();
