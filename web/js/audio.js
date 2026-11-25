/* BP.audio - WebAudio output for the core's 44.1kHz stereo sample batches.
 * Buffer-source scheduling with drift correction; created on first user
 * gesture (autoplay policy). No audio assets - everything comes from the core.
 */
window.BP = window.BP || {};

BP.audio = (function () {
  let ctx = null, gainNode = null;
  let nextTime = 0;
  let volume = BP.util.store.get('volume', 0.8);
  let muted = BP.util.store.get('muted', false);
  let rate = 44100;
  let pushedFrames = 0;

  function start(sampleRate) {
    if (ctx) { if (ctx.state === 'suspended') ctx.resume(); return; }
    rate = sampleRate || 44100;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    try {
      ctx = new AC({ sampleRate: rate, latencyHint: 'interactive' });
    } catch (e) {
      ctx = new AC();
    }
    gainNode = ctx.createGain();
    gainNode.gain.value = muted ? 0 : volume;
    gainNode.connect(ctx.destination);
    nextTime = 0;
    if (ctx.state === 'suspended') ctx.resume();
  }

  /* samples: Int16Array interleaved stereo, frames: sample pair count */
  function push(samples, frames) {
    if (!ctx || ctx.state !== 'running' || muted) return;
    pushedFrames += frames;
    const buf = ctx.createBuffer(2, frames, rate);
    const L = buf.getChannelData(0), R = buf.getChannelData(1);
    for (let i = 0; i < frames; i++) {
      L[i] = samples[i * 2] / 32768;
      R[i] = samples[i * 2 + 1] / 32768;
    }
    const src = ctx.createBufferSource();
    src.buffer = buf;
    src.connect(gainNode);
    const now = ctx.currentTime;
    if (nextTime < now + 0.005) nextTime = now + 0.03;
    if (nextTime > now + 0.25) nextTime = now + 0.05; /* drift correction */
    src.start(nextTime);
    nextTime += frames / rate;
  }

  function setVolume(v) {
    volume = BP.util.clamp(v, 0, 1);
    BP.util.store.set('volume', volume);
    if (gainNode) gainNode.gain.value = muted ? 0 : volume;
  }
  function setMuted(m) {
    muted = !!m;
    BP.util.store.set('muted', muted);
    if (gainNode) gainNode.gain.value = muted ? 0 : volume;
  }

  return {
    start, push, setVolume, setMuted,
    get volume() { return volume; },
    get muted() { return muted; },
    get running() { return !!ctx && ctx.state === 'running'; },
    get pushedFrames() { return pushedFrames; },
    get context() { return ctx; }
  };
})();
