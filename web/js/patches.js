/* BP.patches - IPS and BPS ROM patch appliers (pure functions, unit-testable).
 * Used by the mod system to apply gameplay/visual ROM enhancements at load time. */
window.BP = window.BP || {};

BP.patches = (function () {
  const CRC_TABLE = (function () {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      t[n] = c >>> 0;
    }
    return t;
  })();

  function crc32(bytes) {
    let c = 0xFFFFFFFF;
    for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
    return (c ^ 0xFFFFFFFF) >>> 0;
  }

  /* IPS: "PATCH" + records (offset:3, size:2, data) ... "EOF" [truncate:3] */
  function applyIPS(rom, patch) {
    if (patch.length < 8 || String.fromCharCode(patch[0], patch[1], patch[2], patch[3], patch[4]) !== 'PATCH') {
      throw new Error('Not an IPS patch (bad magic)');
    }
    let out = rom.slice();
    let p = 5;
    const ensure = (end) => {
      if (end > out.length) {
        const grown = new Uint8Array(end);
        grown.set(out);
        out = grown;
      }
    };
    while (p + 3 <= patch.length) {
      if (patch[p] === 0x45 && patch[p + 1] === 0x4F && patch[p + 2] === 0x46) { // "EOF"
        if (p + 6 <= patch.length) { // optional truncation extension
          const t = (patch[p + 3] << 16) | (patch[p + 4] << 8) | patch[p + 5];
          if (t < out.length) out = out.slice(0, t);
        }
        return out;
      }
      const off = (patch[p] << 16) | (patch[p + 1] << 8) | patch[p + 2]; p += 3;
      if (p + 2 > patch.length) throw new Error('Truncated IPS record');
      const size = (patch[p] << 8) | patch[p + 1]; p += 2;
      if (size === 0) { // RLE record
        if (p + 3 > patch.length) throw new Error('Truncated IPS RLE record');
        const count = (patch[p] << 8) | patch[p + 1]; p += 2;
        const val = patch[p++];
        ensure(off + count);
        for (let i = 0; i < count; i++) out[off + i] = val;
      } else {
        if (p + size > patch.length) throw new Error('Truncated IPS data');
        ensure(off + size);
        out.set(patch.subarray(p, p + size), off);
        p += size;
      }
    }
    throw new Error('IPS patch missing EOF marker');
  }

  /* BPS: "BPS1" + varints + actions + footer(sourceCRC, targetCRC, patchCRC). */
  function applyBPS(rom, patch) {
    if (patch.length < 16 || String.fromCharCode(patch[0], patch[1], patch[2], patch[3]) !== 'BPS1') {
      throw new Error('Not a BPS patch (bad magic)');
    }
    let p = 4;
    const varint = () => {
      let v = 0, shift = 0;
      for (;;) {
        if (p >= patch.length) throw new Error('Truncated BPS varint');
        const b = patch[p++];
        v += (b & 0x7F) * Math.pow(2, shift);
        if (b & 0x80) break;
        shift += 7;
      }
      return v;
    };
    const svarint = () => {
      const v = varint();
      return (v & 1) ? -(Math.floor(v / 2)) : Math.floor(v / 2);
    };
    const sourceSize = varint();
    const targetSize = varint();
    const metaSize = varint();
    p += metaSize;
    if (sourceSize !== rom.length) throw new Error('BPS source size mismatch (patch targets a different ROM)');

    const end = patch.length - 12;
    const dv = new DataView(patch.buffer, patch.byteOffset, patch.byteLength);
    const sourceCRC = dv.getUint32(end, true);
    const targetCRC = dv.getUint32(end + 4, true);
    const patchCRC = dv.getUint32(end + 8, true);
    if (crc32(patch.subarray(0, end)) !== patchCRC) throw new Error('BPS patch CRC mismatch');
    if (crc32(rom) !== sourceCRC) throw new Error('BPS source CRC mismatch (wrong ROM version/region)');

    const out = new Uint8Array(targetSize);
    let outOff = 0, srcRel = 0, tgtRel = 0;
    while (p < end) {
      const data = varint();
      const cmd = data & 3;
      const len = Math.floor(data / 4) + 1;
      if (cmd === 0) { // SourceRead
        for (let i = 0; i < len; i++) { out[outOff] = rom[outOff]; outOff++; }
      } else if (cmd === 1) { // TargetRead
        if (p + len > end) throw new Error('Truncated BPS TargetRead');
        out.set(patch.subarray(p, p + len), outOff);
        p += len; outOff += len;
      } else if (cmd === 2) { // SourceCopy
        srcRel += svarint();
        for (let i = 0; i < len; i++) { out[outOff++] = rom[srcRel++]; }
      } else { // TargetCopy
        tgtRel += svarint();
        for (let i = 0; i < len; i++) { out[outOff++] = out[tgtRel++]; }
      }
      if (outOff > targetSize) throw new Error('BPS output overflow');
    }
    if (outOff !== targetSize) throw new Error('BPS output size mismatch');
    if (crc32(out) !== targetCRC) throw new Error('BPS target CRC mismatch');
    return out;
  }

  function apply(rom, patch) {
    if (patch.length >= 5 && patch[0] === 0x50 && patch[1] === 0x41) return applyIPS(rom, patch); // "PA"
    if (patch.length >= 4 && patch[0] === 0x42 && patch[1] === 0x50) return applyBPS(rom, patch); // "BP"
    throw new Error('Unknown patch format (expected IPS or BPS)');
  }

  return { crc32, applyIPS, applyBPS, apply };
})();
