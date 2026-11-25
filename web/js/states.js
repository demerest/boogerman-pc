/* BP.states - save state slots + SRAM persistence.
 * States live in memory and (best-effort) localStorage; export/import as files.
 */
window.BP = window.BP || {};

BP.states = (function () {
  const SLOTS = 8;
  let slots = new Array(SLOTS).fill(null);
  let listeners = [];

  /* restore persisted slots */
  const persisted = BP.util.store.get('states', []);
  for (let i = 0; i < SLOTS; i++) {
    if (persisted[i] && persisted[i].b64) {
      try {
        slots[i] = {
          data: BP.util.b64ToBytes(persisted[i].b64),
          thumb: persisted[i].thumb || null,
          time: persisted[i].time || 0
        };
      } catch (e) { /* corrupt entry - drop */ }
    }
  }

  function notify() { listeners.forEach(fn => { try { fn(slots); } catch (e) { console.error(e); } }); }

  function persist() {
    const out = slots.map(s => s ? { b64: BP.util.bytesToB64(s.data), thumb: s.thumb, time: s.time } : null);
    if (!BP.util.store.set('states', out)) {
      /* quota exceeded - keep thumbnails only, states stay in memory */
      const lite = slots.map(s => s ? { thumb: s.thumb, time: s.time } : null);
      BP.util.store.set('states', lite);
    }
  }

  function save(i) {
    if (!BP.core.loaded) return false;
    const data = BP.core.saveState();
    if (!data) return false;
    let thumb = null;
    try { thumb = BP.video.screenshot(); } catch (e) { /* canvas unavailable */ }
    slots[i] = { data, thumb, time: Date.now() };
    persist();
    notify();
    return true;
  }

  function load(i) {
    if (!slots[i] || !BP.core.loaded) return false;
    const ok = BP.core.loadState(slots[i].data);
    if (ok) notify();
    return ok;
  }

  function exportSlot(i) {
    if (!slots[i]) return;
    BP.util.download('boogerman-slot' + (i + 1) + '.state', slots[i].data);
  }

  function importSlot(i, bytes) {
    /* validate by size against the core's serialization size when loaded */
    if (BP.core.loaded && BP.core.stateSize() && bytes.length !== BP.core.stateSize()) {
      return { ok: false, error: 'State size mismatch (' + bytes.length + ' vs ' + BP.core.stateSize() + ') - wrong core/version?' };
    }
    slots[i] = { data: bytes, thumb: null, time: Date.now() };
    persist();
    notify();
    return { ok: true };
  }

  function clear(i) { slots[i] = null; persist(); notify(); }

  /* ---- SRAM (battery save RAM; generic - Boogerman has none) ---- */
  function sramLoad() {
    const s = BP.core.sram();
    if (!s) return;
    const b64 = BP.util.store.get('sram', null);
    if (b64) {
      try {
        const bytes = BP.util.b64ToBytes(b64);
        s.set(bytes.subarray(0, s.length));
      } catch (e) { /* ignore */ }
    }
  }
  function sramSave() {
    const s = BP.core.sram();
    if (!s) return;
    BP.util.store.set('sram', BP.util.bytesToB64(s));
  }

  return {
    SLOTS, save, load, exportSlot, importSlot, clear, sramLoad, sramSave,
    get slots() { return slots; },
    onChange(fn) { listeners.push(fn); fn(slots); }
  };
})();
