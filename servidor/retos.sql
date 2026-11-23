-- =====================================================================
-- Gymnós · Retos del gimnasio con asistencia verificada
-- Para Supabase (Postgres 15+). Pegar completo en: SQL Editor → New query → Run.
-- Se puede volver a ejecutar sin perder datos.
--
-- Cómo evita la trampa:
--  * La recepción del gimnasio muestra un código QR y un número de 6 dígitos
--    que cambian cada 30 segundos (firmados con un secreto del gimnasio).
--  * El servidor solo acepta el código vigente o el inmediatamente anterior
--    (máximo 60 s), una asistencia por persona y por día, y como máximo
--    5 intentos fallidos cada 10 minutos.
--  * Si el reto tiene geocerca, además exige estar a menos de X metros del gimnasio.
--  * El gimnasio ve todas las asistencias con hora y distancia y puede anular las dudosas.
--  * Las tablas no se pueden leer ni escribir directamente: todo pasa por estas funciones.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- Tablas ----------
create table if not exists public.licencias (
  codigo text primary key,
  cupo int not null default 300 check (cupo between 1 and 100000),
  nota text,
  usada_por uuid,
  creada timestamptz not null default now()
);

create table if not exists public.gimnasios (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (char_length(nombre) between 2 and 80),
  zona_horaria text not null default 'America/Bogota',
  lat double precision,
  lng double precision,
  radio_m int not null default 200 check (radio_m between 50 and 2000),
  cupo int not null default 300,
  secreto text not null,
  clave_admin_hash text not null,
  creado timestamptz not null default now()
);

create table if not exists public.retos (
  id uuid primary key default gen_random_uuid(),
  gimnasio_id uuid not null references public.gimnasios(id) on delete cascade,
  codigo text not null unique,
  titulo text not null check (char_length(titulo) between 3 and 80),
  meta int not null check (meta between 1 and 200),
  inicio date not null,
  fin date not null,
  premio text,
  reglas text,
  geocerca boolean not null default false,
  activo boolean not null default true,
  creado timestamptz not null default now(),
  check (fin >= inicio)
);

create table if not exists public.miembros (
  gimnasio_id uuid not null references public.gimnasios(id) on delete cascade,
  usuario uuid not null,
  alias text not null,
  unido timestamptz not null default now(),
  primary key (gimnasio_id, usuario)
);

create table if not exists public.inscripciones (
  reto_id uuid not null references public.retos(id) on delete cascade,
  usuario uuid not null,
  unido timestamptz not null default now(),
  primary key (reto_id, usuario)
);

create table if not exists public.asistencias (
  id bigint generated always as identity primary key,
  gimnasio_id uuid not null references public.gimnasios(id) on delete cascade,
  usuario uuid not null,
  dia date not null,
  hora timestamptz not null default now(),
  distancia_m int,
  anulada boolean not null default false,
  motivo text,
  unique (gimnasio_id, usuario, dia)
);

create table if not exists public.intentos (
  usuario uuid not null,
  gimnasio_id uuid,
  hora timestamptz not null default now(),
  ok boolean not null
);
create index if not exists intentos_usuario_hora on public.intentos (usuario, hora);

alter table public.licencias enable row level security;
alter table public.gimnasios enable row level security;
alter table public.retos enable row level security;
alter table public.miembros enable row level security;
alter table public.inscripciones enable row level security;
alter table public.asistencias enable row level security;
alter table public.intentos enable row level security;
-- Sin políticas: nadie lee ni escribe las tablas directamente.

-- ---------- Utilidades internas ----------
create or replace function public._codigo(p_secreto text, p_ventana bigint)
returns text language sql immutable set search_path = public, extensions as $$
  select lpad(((('x' || substr(encode(hmac(p_ventana::text, p_secreto, 'sha256'), 'hex'), 1, 8))::bit(32)::int::bigint & 2147483647) % 1000000)::text, 6, '0');
$$;

create or replace function public._uid() returns uuid language plpgsql stable set search_path = public as $$
declare u uuid;
begin
  u := auth.uid();
  if u is null then raise exception 'sin_sesion'; end if;
  return u;
end $$;

create or replace function public._admin(p_clave text) returns public.gimnasios
language plpgsql stable security definer set search_path = public, extensions as $$
declare g public.gimnasios;
begin
  select * into g from public.gimnasios where clave_admin_hash = encode(digest(coalesce(p_clave, ''), 'sha256'), 'hex');
  if not found then raise exception 'clave_invalida'; end if;
  return g;
end $$;

create or replace function public._distancia(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
returns int language sql immutable as $$
  select round(2 * 6371000 * asin(sqrt(power(sin(radians(lat2 - lat1) / 2), 2) + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2))))::int;
$$;

-- ---------- Para todos ----------
create or replace function public.hora_servidor() returns bigint language sql stable as $$
  select (extract(epoch from now()) * 1000)::bigint;
$$;

-- ---------- Gimnasio (con su clave de administración) ----------
create or replace function public.crear_gimnasio(p_licencia text, p_nombre text, p_zona text default 'America/Bogota',
  p_lat double precision default null, p_lng double precision default null, p_radio int default 200)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare lic public.licencias; clave text; g uuid;
begin
  select * into lic from public.licencias where codigo = upper(trim(p_licencia)) for update;
  if not found or lic.usada_por is not null then raise exception 'licencia_invalida'; end if;
  clave := encode(gen_random_bytes(18), 'base64');
  clave := translate(clave, '+/=', 'xyz');
  insert into public.gimnasios (nombre, zona_horaria, lat, lng, radio_m, cupo, secreto, clave_admin_hash)
  values (trim(p_nombre), coalesce(p_zona, 'America/Bogota'), p_lat, p_lng, coalesce(p_radio, 200), lic.cupo,
          encode(gen_random_bytes(32), 'hex'), encode(digest(clave, 'sha256'), 'hex'))
  returning id into g;
  update public.licencias set usada_por = g where codigo = lic.codigo;
  return json_build_object('gimnasio_id', g, 'clave_admin', clave, 'cupo', lic.cupo);
end $$;

create or replace function public.datos_gimnasio(p_clave text) returns json
language plpgsql stable security definer set search_path = public, extensions as $$
declare g public.gimnasios;
begin
  g := public._admin(p_clave);
  return json_build_object('id', g.id, 'nombre', g.nombre, 'zona', g.zona_horaria, 'lat', g.lat, 'lng', g.lng, 'radio', g.radio_m,
    'cupo', g.cupo, 'miembros', (select count(*) from public.miembros m where m.gimnasio_id = g.id),
    'secreto', g.secreto, 'ahora_ms', public.hora_servidor());
end $$;

create or replace function public.ubicar_gimnasio(p_clave text, p_lat double precision, p_lng double precision, p_radio int)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare g public.gimnasios;
begin
  g := public._admin(p_clave);
  update public.gimnasios set lat = p_lat, lng = p_lng, radio_m = greatest(50, least(2000, coalesce(p_radio, 200))) where id = g.id;
  return json_build_object('ok', true);
end $$;

create or replace function public.crear_reto(p_clave text, p_titulo text, p_meta int, p_inicio date, p_fin date,
  p_premio text default null, p_reglas text default null, p_geocerca boolean default false)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare g public.gimnasios; cod text; r uuid; abc text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; i int;
begin
  g := public._admin(p_clave);
  if p_geocerca and g.lat is null then raise exception 'falta_ubicacion'; end if;
  loop
    cod := '';
    for i in 1..6 loop cod := cod || substr(abc, 1 + (get_byte(gen_random_bytes(1), 0) % length(abc)), 1); end loop;
    exit when not exists (select 1 from public.retos where codigo = cod);
  end loop;
  insert into public.retos (gimnasio_id, codigo, titulo, meta, inicio, fin, premio, reglas, geocerca)
  values (g.id, cod, trim(p_titulo), p_meta, p_inicio, p_fin, nullif(trim(p_premio), ''), nullif(trim(p_reglas), ''), coalesce(p_geocerca, false))
  returning id into r;
  return json_build_object('id', r, 'codigo', cod);
end $$;

create or replace function public.retos_gimnasio(p_clave text) returns json
language plpgsql stable security definer set search_path = public, extensions as $$
declare g public.gimnasios;
begin
  g := public._admin(p_clave);
  return coalesce((select json_agg(x order by x.inicio desc) from (
    select r.id, r.codigo, r.titulo, r.meta, r.inicio, r.fin, r.premio, r.reglas, r.geocerca, r.activo,
      (select count(*) from public.inscripciones i where i.reto_id = r.id) as inscritos,
      (select count(*) from public.inscripciones i where i.reto_id = r.id and
        (select count(*) from public.asistencias a where a.gimnasio_id = g.id and a.usuario = i.usuario and not a.anulada and a.dia between r.inicio and r.fin) >= r.meta) as cumplieron
    from public.retos r where r.gimnasio_id = g.id) x), '[]'::json);
end $$;

create or replace function public.cerrar_reto(p_clave text, p_reto uuid) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare g public.gimnasios;
begin
  g := public._admin(p_clave);
  update public.retos set activo = false where id = p_reto and gimnasio_id = g.id;
  return json_build_object('ok', found);
end $$;

create or replace function public.tabla_reto_admin(p_clave text, p_reto uuid) returns json
language plpgsql stable security definer set search_path = public, extensions as $$
declare g public.gimnasios; r public.retos;
begin
  g := public._admin(p_clave);
  select * into r from public.retos where id = p_reto and gimnasio_id = g.id;
  if not found then raise exception 'reto_no_existe'; end if;
  return coalesce((select json_agg(x order by x.asistencias desc, x.ultima asc) from (
    select m.alias, i.unido,
      (select count(*) from public.asistencias a where a.gimnasio_id = g.id and a.usuario = i.usuario and not a.anulada and a.dia between r.inicio and r.fin) as asistencias,
      (select max(a.hora) from public.asistencias a where a.gimnasio_id = g.id and a.usuario = i.usuario and not a.anulada and a.dia between r.inicio and r.fin) as ultima
    from public.inscripciones i join public.miembros m on m.gimnasio_id = g.id and m.usuario = i.usuario
    where i.reto_id = r.id) x), '[]'::json);
end $$;

create or replace function public.asistencias_gimnasio(p_clave text, p_desde date default null) returns json
language plpgsql stable security definer set search_path = public, extensions as $$
declare g public.gimnasios;
begin
  g := public._admin(p_clave);
  return coalesce((select json_agg(x order by x.hora desc) from (
    select a.id, m.alias, a.dia, a.hora, a.distancia_m, a.anulada, a.motivo
    from public.asistencias a join public.miembros m on m.gimnasio_id = a.gimnasio_id and m.usuario = a.usuario
    where a.gimnasio_id = g.id and a.dia >= coalesce(p_desde, (now() at time zone g.zona_horaria)::date - 30)
    limit 2000) x), '[]'::json);
end $$;

create or replace function public.anular_asistencia(p_clave text, p_id bigint, p_motivo text default null, p_anular boolean default true)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare g public.gimnasios;
begin
  g := public._admin(p_clave);
  update public.asistencias set anulada = coalesce(p_anular, true), motivo = case when coalesce(p_anular, true) then nullif(trim(p_motivo), '') end
  where id = p_id and gimnasio_id = g.id;
  return json_build_object('ok', found);
end $$;

-- ---------- Afiliado (sesión anónima de Supabase en su celular) ----------
create or replace function public.unirse_reto(p_codigo text, p_alias text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare u uuid := public._uid(); r public.retos; g public.gimnasios; al text := trim(coalesce(p_alias, ''));
begin
  if char_length(al) < 2 or char_length(al) > 30 then raise exception 'alias_invalido'; end if;
  select * into r from public.retos where codigo = upper(trim(p_codigo));
  if not found or not r.activo then raise exception 'reto_no_existe'; end if;
  select * into g from public.gimnasios where id = r.gimnasio_id;
  if (now() at time zone g.zona_horaria)::date > r.fin then raise exception 'reto_terminado'; end if;
  if not exists (select 1 from public.miembros where gimnasio_id = g.id and usuario = u) then
    if (select count(*) from public.miembros where gimnasio_id = g.id) >= g.cupo then raise exception 'cupo_lleno'; end if;
    insert into public.miembros (gimnasio_id, usuario, alias) values (g.id, u, al);
  else
    update public.miembros set alias = al where gimnasio_id = g.id and usuario = u;
  end if;
  insert into public.inscripciones (reto_id, usuario) values (r.id, u) on conflict do nothing;
  return json_build_object('reto_id', r.id, 'gimnasio_id', g.id, 'gimnasio', g.nombre, 'titulo', r.titulo);
end $$;

create or replace function public.salir_reto(p_reto uuid) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare u uuid := public._uid();
begin
  delete from public.inscripciones where reto_id = p_reto and usuario = u;
  return json_build_object('ok', found);
end $$;

create or replace function public.mis_retos() returns json
language plpgsql stable security definer set search_path = public, extensions as $$
declare u uuid := public._uid();
begin
  return coalesce((select json_agg(x order by x.fin) from (
    select r.id, r.titulo, r.meta, r.inicio, r.fin, r.premio, r.reglas, r.geocerca, r.activo, g.id as gimnasio_id, g.nombre as gimnasio,
      (now() at time zone g.zona_horaria)::date as hoy,
      (select count(*) from public.asistencias a where a.gimnasio_id = g.id and a.usuario = u and not a.anulada and a.dia between r.inicio and r.fin) as mias,
      exists (select 1 from public.asistencias a where a.gimnasio_id = g.id and a.usuario = u and a.dia = (now() at time zone g.zona_horaria)::date and not a.anulada) as hoy_ok,
      (select count(*) from public.inscripciones i where i.reto_id = r.id) as inscritos
    from public.inscripciones i join public.retos r on r.id = i.reto_id join public.gimnasios g on g.id = r.gimnasio_id
    where i.usuario = u) x), '[]'::json);
end $$;

create or replace function public.tabla_reto(p_reto uuid) returns json
language plpgsql stable security definer set search_path = public, extensions as $$
declare u uuid := public._uid(); r public.retos;
begin
  select * into r from public.retos where id = p_reto;
  if not found or not exists (select 1 from public.inscripciones where reto_id = p_reto and usuario = u) then raise exception 'no_inscrito'; end if;
  return coalesce((select json_agg(x order by x.asistencias desc, x.ultima asc nulls last) from (
    select m.alias, (i.usuario = u) as yo,
      (select count(*) from public.asistencias a where a.gimnasio_id = r.gimnasio_id and a.usuario = i.usuario and not a.anulada and a.dia between r.inicio and r.fin) as asistencias,
      (select max(a.hora) from public.asistencias a where a.gimnasio_id = r.gimnasio_id and a.usuario = i.usuario and not a.anulada and a.dia between r.inicio and r.fin) as ultima
    from public.inscripciones i join public.miembros m on m.gimnasio_id = r.gimnasio_id and m.usuario = i.usuario
    where i.reto_id = p_reto) x), '[]'::json);
end $$;

create or replace function public.registrar_asistencia(p_gimnasio uuid, p_codigo text,
  p_lat double precision default null, p_lng double precision default null)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare u uuid := public._uid(); g public.gimnasios; v bigint; valido boolean; dist int; hoy date; nuevo bigint; cerca boolean;
begin
  select * into g from public.gimnasios where id = p_gimnasio;
  if not found or not exists (select 1 from public.miembros where gimnasio_id = g.id and usuario = u) then raise exception 'no_inscrito'; end if;
  if (select count(*) from public.intentos t where t.usuario = u and not t.ok and t.hora > now() - interval '10 minutes') >= 5 then
    raise exception 'demasiados_intentos';
  end if;
  v := floor(extract(epoch from now()) / 30)::bigint;
  valido := trim(coalesce(p_codigo, '')) in (public._codigo(g.secreto, v), public._codigo(g.secreto, v - 1));
  if not valido then
    insert into public.intentos (usuario, gimnasio_id, ok) values (u, g.id, false);
    return json_build_object('ok', false, 'error', 'codigo_invalido');
  end if;
  if p_lat is not null and p_lng is not null and g.lat is not null then dist := public._distancia(g.lat, g.lng, p_lat, p_lng); end if;
  hoy := (now() at time zone g.zona_horaria)::date;
  cerca := exists (select 1 from public.inscripciones i join public.retos r on r.id = i.reto_id
                   where i.usuario = u and r.gimnasio_id = g.id and r.activo and r.geocerca and hoy between r.inicio and r.fin);
  if cerca and g.lat is not null and (dist is null or dist > g.radio_m) then
    insert into public.intentos (usuario, gimnasio_id, ok) values (u, g.id, false);
    return json_build_object('ok', false, 'error', case when dist is null then 'falta_ubicacion' else 'fuera_del_gimnasio' end, 'distancia_m', dist);
  end if;
  insert into public.intentos (usuario, gimnasio_id, ok) values (u, g.id, true);
  insert into public.asistencias (gimnasio_id, usuario, dia, distancia_m) values (g.id, u, hoy, dist)
  on conflict (gimnasio_id, usuario, dia) do nothing returning id into nuevo;
  delete from public.intentos where hora < now() - interval '1 day';
  return json_build_object('ok', true, 'ya_registrada', nuevo is null, 'dia', hoy, 'gimnasio', g.nombre);
end $$;

-- ---------- Permisos ----------
revoke all on all tables in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.hora_servidor() to anon, authenticated;
grant execute on function public.crear_gimnasio(text, text, text, double precision, double precision, int) to anon, authenticated;
grant execute on function public.datos_gimnasio(text) to anon, authenticated;
grant execute on function public.ubicar_gimnasio(text, double precision, double precision, int) to anon, authenticated;
grant execute on function public.crear_reto(text, text, int, date, date, text, text, boolean) to anon, authenticated;
grant execute on function public.retos_gimnasio(text) to anon, authenticated;
grant execute on function public.cerrar_reto(text, uuid) to anon, authenticated;
grant execute on function public.tabla_reto_admin(text, uuid) to anon, authenticated;
grant execute on function public.asistencias_gimnasio(text, date) to anon, authenticated;
grant execute on function public.anular_asistencia(text, bigint, text, boolean) to anon, authenticated;
grant execute on function public.unirse_reto(text, text) to authenticated;
grant execute on function public.salir_reto(uuid) to authenticated;
grant execute on function public.mis_retos() to authenticated;
grant execute on function public.tabla_reto(uuid) to authenticated;
grant execute on function public.registrar_asistencia(uuid, text, double precision, double precision) to authenticated;

-- ---------- Licencias para tus gimnasios clientes ----------
-- Crea una por cada gimnasio que contrate Gymnós (el cupo es el máximo de afiliados en sus retos):
--   insert into public.licencias (codigo, cupo, nota) values ('TUGYM-2026', 300, 'Tu Gimnasio, plan 300');
