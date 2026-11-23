/* ============ Gymnós · Retos: conexión con el servidor ============
   Con GYMNOS_SERVIDOR.url y .anon llenos habla con Supabase (servidor/retos.sql).
   Vacíos: modo demostración, todo en este navegador (sirve para probar panel y app en el mismo equipo). */
const GYMNOS_SERVIDOR = {url: "", anon: ""};
const Retos = (() => {
  const SV = GYMNOS_SERVIDOR, live = !!(SV.url && SV.anon), SES = "gymnos-retos-sesion", DEMO = "gymnos-retos-demo";
  const get = k => { try { return JSON.parse(localStorage.getItem(k) || "null"); } catch (e) { return null; } };
  const put = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} };
  const ERR = {codigo_invalido: "Ese código ya cambió o no es válido. Escanea o escribe el que se ve ahora en la recepción.", demasiados_intentos: "Demasiados intentos fallidos. Espera 10 minutos y vuelve a intentarlo.",
    no_inscrito: "Primero únete a un reto de este gimnasio.", reto_no_existe: "No encontramos un reto activo con ese código.", reto_terminado: "Ese reto ya terminó.",
    cupo_lleno: "El gimnasio llegó al límite de personas de su plan. Avísale en la recepción.", alias_invalido: "Escribe un nombre o apodo de 2 a 30 letras.",
    fuera_del_gimnasio: "Tu ubicación está lejos del gimnasio. La asistencia solo se registra estando allí.", falta_ubicacion: "Este reto pide tu ubicación para confirmar que estás en el gimnasio.",
    licencia_invalida: "Esa licencia no existe o ya se usó.", clave_invalida: "Esa clave del panel no es correcta.", falta_ubicacion_gym: "Primero guarda la ubicación del gimnasio en Ajustes.",
    sin_sesion: "No pudimos crear tu sesión. Revisa tu conexión.", red: "Sin conexión con el servidor. Revisa tu internet e inténtalo de nuevo."};
  const fail = code => { const e = new Error(ERR[code] || code); e.code = code; throw e; };
  /* --- Código que cambia cada 30 s (igual que en el servidor) --- */
  async function codigo(secreto, ventana){
    const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(secreto), {name: "HMAC", hash: "SHA-256"}, false, ["sign"]);
    const h = new Uint8Array(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(String(ventana))));
    return String((((h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3]) & 0x7fffffff) % 1000000).padStart(6, "0");
  }
  const qrTexto = (gym, cod) => `GYMNOS1|${gym}|${cod}`;
  const leerQR = t => { const m = /^GYMNOS1\|([0-9a-f-]{36})\|(\d{6})$/.exec(String(t || "").trim()); return m ? {gimnasio: m[1], codigo: m[2]} : null; };
  /* --- Supabase (REST) --- */
  async function sesion(){
    let s = get(SES);
    if (s && s.exp > Date.now() + 60000) return s.token;
    try {
      const r = s && s.refresh ? await fetch(`${SV.url}/auth/v1/token?grant_type=refresh_token`, {method: "POST", headers: {apikey: SV.anon, "Content-Type": "application/json"}, body: JSON.stringify({refresh_token: s.refresh})}) : null;
      let j = r && r.ok ? await r.json() : null;
      if (!j) { const r2 = await fetch(`${SV.url}/auth/v1/signup`, {method: "POST", headers: {apikey: SV.anon, "Content-Type": "application/json"}, body: JSON.stringify({data: {}})}); j = r2.ok ? await r2.json() : null; }
      if (!j || !j.access_token) fail("sin_sesion");
      put(SES, {token: j.access_token, refresh: j.refresh_token, exp: Date.now() + (j.expires_in || 3600) * 1000});
      return j.access_token;
    } catch (e) { if (e.code) throw e; fail("red"); }
  }
  async function rpc(fn, args, conUsuario){
    const tok = conUsuario ? await sesion() : SV.anon; let r;
    try { r = await fetch(`${SV.url}/rest/v1/rpc/${fn}`, {method: "POST", headers: {apikey: SV.anon, Authorization: "Bearer " + tok, "Content-Type": "application/json"}, body: JSON.stringify(args || {})}); }
    catch (e) { fail("red"); }
    const j = await r.json().catch(() => null);
    if (!r.ok) fail((j && (j.message || j.hint)) || "red");
    return j;
  }
  /* --- Demostración: misma lógica, guardada en este navegador --- */
  const D = () => get(DEMO) || {lic: {"DEMO-GYM": {cupo: 300, usada: null}}, gym: {}, reto: {}, miembro: [], insc: [], asis: [], intento: [], seq: 1};
  const W = d => put(DEMO, d);
  const rnd = n => Array.from(crypto.getRandomValues(new Uint8Array(n)), b => b.toString(16).padStart(2, "0")).join("");
  const hoyEn = () => new Date(Date.now() - 5 * 3600e3).toISOString().slice(0, 10);
  const yo = () => { let s = get(SES); if (!s || !s.demo) { s = {demo: rnd(8)}; put(SES, s); } return s.demo; };
  const adminDe = (d, clave) => { const g = Object.values(d.gym).find(x => x.clave === clave); if (!g) fail("clave_invalida"); return g; };
  const cuenta = (d, gid, u, r) => d.asis.filter(a => a.gimnasio_id === gid && a.usuario === u && !a.anulada && a.dia >= r.inicio && a.dia <= r.fin).length;
  const aliasDe = (d, gid, u) => (d.miembro.find(m => m.gimnasio_id === gid && m.usuario === u) || {}).alias || "—";
  const demo = {
    hora_servidor: () => Date.now(),
    crear_gimnasio({p_licencia, p_nombre, p_zona}){ const d = D(), k = String(p_licencia || "").trim().toUpperCase(), l = d.lic[k]; if (!l || l.usada) fail("licencia_invalida");
      const id = crypto.randomUUID(), clave = rnd(12); d.gym[id] = {id, nombre: String(p_nombre).trim(), zona: p_zona || "America/Bogota", lat: null, lng: null, radio: 200, cupo: l.cupo, secreto: rnd(32), clave}; l.usada = id; W(d);
      return {gimnasio_id: id, clave_admin: clave, cupo: l.cupo}; },
    datos_gimnasio({p_clave}){ const d = D(), g = adminDe(d, p_clave); return {id: g.id, nombre: g.nombre, zona: g.zona, lat: g.lat, lng: g.lng, radio: g.radio, cupo: g.cupo, miembros: d.miembro.filter(m => m.gimnasio_id === g.id).length, secreto: g.secreto, ahora_ms: Date.now()}; },
    ubicar_gimnasio({p_clave, p_lat, p_lng, p_radio}){ const d = D(), g = adminDe(d, p_clave); Object.assign(d.gym[g.id], {lat: p_lat, lng: p_lng, radio: Math.max(50, Math.min(2000, p_radio || 200))}); W(d); return {ok: true}; },
    crear_reto({p_clave, p_titulo, p_meta, p_inicio, p_fin, p_premio, p_reglas, p_geocerca}){ const d = D(), g = adminDe(d, p_clave); if (p_geocerca && g.lat == null) fail("falta_ubicacion_gym");
      const abc = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"; let cod; do { cod = Array.from(crypto.getRandomValues(new Uint8Array(6)), b => abc[b % abc.length]).join(""); } while (Object.values(d.reto).some(r => r.codigo === cod));
      const id = crypto.randomUUID(); d.reto[id] = {id, gimnasio_id: g.id, codigo: cod, titulo: p_titulo.trim(), meta: +p_meta, inicio: p_inicio, fin: p_fin, premio: p_premio || null, reglas: p_reglas || null, geocerca: !!p_geocerca, activo: true}; W(d); return {id, codigo: cod}; },
    retos_gimnasio({p_clave}){ const d = D(), g = adminDe(d, p_clave); return Object.values(d.reto).filter(r => r.gimnasio_id === g.id).sort((a, b) => a.inicio < b.inicio ? 1 : -1).map(r => { const ins = d.insc.filter(i => i.reto_id === r.id);
      return {...r, inscritos: ins.length, cumplieron: ins.filter(i => cuenta(d, g.id, i.usuario, r) >= r.meta).length}; }); },
    cerrar_reto({p_clave, p_reto}){ const d = D(), g = adminDe(d, p_clave), r = d.reto[p_reto]; if (r && r.gimnasio_id === g.id) { r.activo = false; W(d); } return {ok: !!r}; },
    tabla_reto_admin({p_clave, p_reto}){ const d = D(), g = adminDe(d, p_clave), r = d.reto[p_reto]; if (!r || r.gimnasio_id !== g.id) fail("reto_no_existe");
      return d.insc.filter(i => i.reto_id === r.id).map(i => { const xs = d.asis.filter(a => a.gimnasio_id === g.id && a.usuario === i.usuario && !a.anulada && a.dia >= r.inicio && a.dia <= r.fin);
        return {alias: aliasDe(d, g.id, i.usuario), unido: i.unido, asistencias: xs.length, ultima: xs.length ? xs.at(-1).hora : null}; }).sort((a, b) => b.asistencias - a.asistencias || String(a.ultima).localeCompare(String(b.ultima))); },
    asistencias_gimnasio({p_clave}){ const d = D(), g = adminDe(d, p_clave); return d.asis.filter(a => a.gimnasio_id === g.id).sort((a, b) => a.hora < b.hora ? 1 : -1).map(a => ({id: a.id, alias: aliasDe(d, g.id, a.usuario), dia: a.dia, hora: a.hora, distancia_m: a.distancia_m, anulada: a.anulada, motivo: a.motivo})); },
    anular_asistencia({p_clave, p_id, p_motivo, p_anular}){ const d = D(), g = adminDe(d, p_clave), a = d.asis.find(x => x.id === p_id && x.gimnasio_id === g.id); if (a) { a.anulada = p_anular !== false; a.motivo = a.anulada ? (p_motivo || null) : null; W(d); } return {ok: !!a}; },
    unirse_reto({p_codigo, p_alias}){ const d = D(), u = yo(), al = String(p_alias || "").trim(); if (al.length < 2 || al.length > 30) fail("alias_invalido");
      const r = Object.values(d.reto).find(x => x.codigo === String(p_codigo || "").trim().toUpperCase()); if (!r || !r.activo) fail("reto_no_existe"); if (hoyEn() > r.fin) fail("reto_terminado");
      const g = d.gym[r.gimnasio_id], m = d.miembro.find(x => x.gimnasio_id === g.id && x.usuario === u);
      if (!m) { if (d.miembro.filter(x => x.gimnasio_id === g.id).length >= g.cupo) fail("cupo_lleno"); d.miembro.push({gimnasio_id: g.id, usuario: u, alias: al}); } else m.alias = al;
      if (!d.insc.some(i => i.reto_id === r.id && i.usuario === u)) d.insc.push({reto_id: r.id, usuario: u, unido: new Date().toISOString()}); W(d);
      return {reto_id: r.id, gimnasio_id: g.id, gimnasio: g.nombre, titulo: r.titulo}; },
    salir_reto({p_reto}){ const d = D(), u = yo(); d.insc = d.insc.filter(i => !(i.reto_id === p_reto && i.usuario === u)); W(d); return {ok: true}; },
    mis_retos(){ const d = D(), u = yo(), hoy = hoyEn(); return d.insc.filter(i => i.usuario === u).map(i => { const r = d.reto[i.reto_id], g = d.gym[r.gimnasio_id];
      return {...r, gimnasio: g.nombre, hoy, mias: cuenta(d, g.id, u, r), hoy_ok: d.asis.some(a => a.gimnasio_id === g.id && a.usuario === u && a.dia === hoy && !a.anulada), inscritos: d.insc.filter(x => x.reto_id === r.id).length}; }).sort((a, b) => a.fin < b.fin ? -1 : 1); },
    tabla_reto({p_reto}){ const d = D(), u = yo(), r = d.reto[p_reto]; if (!r || !d.insc.some(i => i.reto_id === p_reto && i.usuario === u)) fail("no_inscrito");
      return d.insc.filter(i => i.reto_id === r.id).map(i => { const xs = d.asis.filter(a => a.gimnasio_id === r.gimnasio_id && a.usuario === i.usuario && !a.anulada && a.dia >= r.inicio && a.dia <= r.fin);
        return {alias: aliasDe(d, r.gimnasio_id, i.usuario), yo: i.usuario === u, asistencias: xs.length, ultima: xs.length ? xs.at(-1).hora : null}; }).sort((a, b) => b.asistencias - a.asistencias || String(a.ultima).localeCompare(String(b.ultima))); },
    async registrar_asistencia({p_gimnasio, p_codigo, p_lat, p_lng}){ const d = D(), u = yo(), g = d.gym[p_gimnasio];
      if (!g || !d.miembro.some(m => m.gimnasio_id === g.id && m.usuario === u)) fail("no_inscrito");
      if (d.intento.filter(t => t.usuario === u && !t.ok && t.hora > Date.now() - 600000).length >= 5) fail("demasiados_intentos");
      const v = Math.floor(Date.now() / 30000), c = String(p_codigo || "").trim();
      if (c !== await codigo(g.secreto, v) && c !== await codigo(g.secreto, v - 1)) { d.intento.push({usuario: u, ok: false, hora: Date.now()}); W(d); return {ok: false, error: "codigo_invalido"}; }
      const hoy = hoyEn(); let dist = null;
      if (p_lat != null && p_lng != null && g.lat != null) { const R = 6371000, rad = x => x * Math.PI / 180, a = Math.sin(rad(p_lat - g.lat) / 2) ** 2 + Math.cos(rad(g.lat)) * Math.cos(rad(p_lat)) * Math.sin(rad(p_lng - g.lng) / 2) ** 2; dist = Math.round(2 * R * Math.asin(Math.sqrt(a))); }
      const cerca = d.insc.some(i => i.usuario === u && d.reto[i.reto_id].gimnasio_id === g.id && d.reto[i.reto_id].activo && d.reto[i.reto_id].geocerca && hoy >= d.reto[i.reto_id].inicio && hoy <= d.reto[i.reto_id].fin);
      if (cerca && g.lat != null && (dist == null || dist > g.radio)) { d.intento.push({usuario: u, ok: false, hora: Date.now()}); W(d); return {ok: false, error: dist == null ? "falta_ubicacion" : "fuera_del_gimnasio", distancia_m: dist}; }
      d.intento.push({usuario: u, ok: true, hora: Date.now()}); const ya = d.asis.some(a => a.gimnasio_id === g.id && a.usuario === u && a.dia === hoy);
      if (!ya) d.asis.push({id: d.seq++, gimnasio_id: g.id, usuario: u, dia: hoy, hora: new Date().toISOString(), distancia_m: dist, anulada: false, motivo: null});
      d.intento = d.intento.filter(t => t.hora > Date.now() - 864e5); W(d); return {ok: true, ya_registrada: ya, dia: hoy, gimnasio: g.nombre}; }
  };
  const USR = new Set(["unirse_reto", "salir_reto", "mis_retos", "tabla_reto", "registrar_asistencia"]);
  async function call(fn, args){ if (live) return rpc(fn, args, USR.has(fn)); try { return await demo[fn](args || {}); } catch (e) { if (e.code) throw e; throw e; } }
  return {live, call, codigo, qrTexto, leerQR, ERR, msg: e => (e && (ERR[e.code] || e.message)) || ERR.red};
})();
