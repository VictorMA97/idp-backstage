// crypto.randomUUID solo existe en "contextos seguros" (HTTPS o localhost). Aquí se sirve por
// HTTP en backstage.localtest.me, que no lo es, y el cliente de señales (plugin-signals) lo exige.
// getRandomValues sí está disponible en contextos no seguros, así que se genera el UUID v4 con él.
const c = globalThis.crypto as Crypto | undefined;
if (c && typeof c.randomUUID !== 'function') {
  Object.defineProperty(c, 'randomUUID', {
    configurable: true,
    writable: true,
    value: (): `${string}-${string}-${string}-${string}-${string}` => {
      const b = c.getRandomValues(new Uint8Array(16));
      b[6] = (b[6] & 0x0f) | 0x40;
      b[8] = (b[8] & 0x3f) | 0x80;
      const h = Array.from(b, x => x.toString(16).padStart(2, '0')).join('');
      return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
    },
  });
}
