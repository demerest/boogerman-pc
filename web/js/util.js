/* BP.util - shared helpers. Classic script, file:// friendly. */
window.BP = window.BP || {};

BP.util = {
  b64ToBytes(b64) {
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  },

  bytesToB64(bytes) {
    let s = '';
    const CH = 0x8000;
    for (let i = 0; i < bytes.length; i += CH) {
      s += String.fromCharCode.apply(null, bytes.subarray(i, i + CH));
    }
    return btoa(s);
  },

  hex(n, w) {
    return '0x' + (n >>> 0).toString(16).toUpperCase().padStart(w || 2, '0');
  },

  clamp(v, a, b) { return v < a ? a : (v > b ? b : v); },

  download(name, bytes, mime) {
    const blob = new Blob([bytes], { type: mime || 'application/octet-stream' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = name;
    document.body.appendChild(a);
    a.click();
    setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
  },

  store: {
    get(k, dflt) {
      try {
        const v = localStorage.getItem('bp.' + k);
        return v == null ? dflt : JSON.parse(v);
      } catch (e) { return dflt; }
    },
    set(k, v) {
      try { localStorage.setItem('bp.' + k, JSON.stringify(v)); return true; }
      catch (e) { return false; }
    },
    del(k) { try { localStorage.removeItem('bp.' + k); } catch (e) {} }
  },

  el(id) { return document.getElementById(id); },

  toast(msg, ms) {
    let box = BP.util.el('bp-toasts');
    if (!box) {
      box = document.createElement('div');
      box.id = 'bp-toasts';
      document.body.appendChild(box);
    }
    const t = document.createElement('div');
    t.className = 'bp-toast';
    t.textContent = msg;
    box.appendChild(t);
    setTimeout(() => { t.classList.add('out'); setTimeout(() => t.remove(), 400); }, ms || 2600);
  },

  /* Format bytes as a hex dump row string. */
  hexRow(bytes, off, n) {
    let s = '';
    for (let i = 0; i < n; i++) {
      s += (off + i < bytes.length ? bytes[off + i].toString(16).padStart(2, '0') : '  ') + ' ';
    }
    return s;
  }
};
