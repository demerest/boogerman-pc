/* Example script mod: overlay HUD.
 * Demonstrates the per-frame hook API: overlay drawing + live RAM reads.
 * Enable it in the Mods tab. */
(function () {
  let sessionStart = 0;

  BP.mods.register({
    id: 'overlay-demo',
    name: 'Overlay demo (frame HUD)',
    version: '1.0',
    author: 'port framework',
    description: 'Example script mod: draws frame counter, session clock and a live RAM word on the overlay canvas. Template for gameplay enhancements.',
    enabledByDefault: false,
    hooks: {
      boot(api) {
        sessionStart = performance.now();
      },
      frame(api) {
        const ctx = BP.video.overlayCtx;
        if (!ctx) return;
        BP.video.clearOverlay();
        ctx.font = '8px monospace';
        ctx.fillStyle = '#8fd14f';
        ctx.fillText('FRAME ' + api.frame, 4, 10);
        const secs = Math.floor((performance.now() - sessionStart) / 1000);
        ctx.fillText('SESSION ' + Math.floor(secs / 60) + ':' + String(secs % 60).padStart(2, '0'), 4, 20);
        ctx.fillStyle = '#e8c547';
        ctx.fillText('RAM[FF0000]=' + BP.util.hex(api.ram.read16(0), 4), 4, api.video.size.h - 6);
      }
    }
  });
})();
