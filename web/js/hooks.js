/* BP.hooks - the enhancement event bus.
 * Mods subscribe here; the core emits events every emulated frame.
 * This is the primary gameplay-enhancement surface of the port. */
window.BP = window.BP || {};

BP.hooks = (function () {
  const lists = { frame: [], boot: [], audio: [], state: [], shutdown: [] };

  function on(kind, fn) {
    if (!lists[kind]) throw new Error('Unknown hook kind: ' + kind);
    lists[kind].push(fn);
    return () => {
      const i = lists[kind].indexOf(fn);
      if (i >= 0) lists[kind].splice(i, 1);
    };
  }

  function emit(kind, api) {
    const l = lists[kind];
    for (let i = 0; i < l.length; i++) {
      try { l[i](api); }
      catch (e) { console.error('[BP.hooks] mod error in ' + kind + ' hook:', e); }
    }
  }

  return {
    onFrame: (fn) => on('frame', fn),
    onBoot: (fn) => on('boot', fn),
    onAudio: (fn) => on('audio', fn),
    onState: (fn) => on('state', fn),
    onShutdown: (fn) => on('shutdown', fn),
    emitFrame: (api) => emit('frame', api),
    emitBoot: (api) => emit('boot', api),
    emitAudio: (api) => emit('audio', api),
    emitState: (api) => emit('state', api),
    emitShutdown: () => emit('shutdown', {}),
    counts: () => Object.fromEntries(Object.entries(lists).map(([k, v]) => [k, v.length]))
  };
})();
