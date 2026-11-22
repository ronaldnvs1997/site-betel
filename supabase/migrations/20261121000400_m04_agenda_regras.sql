-- =====================================================================
-- M04 — Agenda: regras no banco
--  * Prevenção de conflitos de espaço e horário (eventos × reservas), no servidor
--  * Ficha bloqueada (manual ou data passada): fora da coordenação, só fotos e vídeos
--  * Autoria (criado_por / atualizado_por) e histórico das alterações
-- Reproduz exatamente a regra de conflito da Agenda original (mesmo dia, espaço em
-- comum e faixas de horário que se sobrepõem; sem horário definido não há conflito).
-- =====================================================================
begin;

-- Converte "19:30", "19h", "19h30", "19:30:00" em minutos (igual a horaParaMinutos do front)
create function public.agenda_minutos(p text) returns integer
language plpgsql immutable set search_path = '' as $$
declare s text := regexp_replace(btrim(coalesce(p, '')), 'h', ':'); partes text[];
begin
  if s = '' then return null; end if;
  partes := string_to_array(s, ':');
  if array_length(partes, 1) < 2 or partes[1] !~ '^\s*\d+' then return null; end if;
  return substring(partes[1] from '^\s*(\d+)')::int * 60 + coalesce(nullif(substring(partes[2] from '^(\d+)'), '')::int, 0);
end $$;

-- Faixa do evento: início/fim estruturados ou, nos registros antigos, o texto "horario"
create function public.agenda_faixa_evento(p_ini text, p_fim text, p_horario text, out inicio integer, out fim integer)
language plpgsql immutable set search_path = '' as $$
declare m text[];
begin
  if nullif(btrim(coalesce(p_ini, '')), '') is not null and nullif(btrim(coalesce(p_fim, '')), '') is not null then
    inicio := public.agenda_minutos(p_ini); fim := public.agenda_minutos(p_fim); return;
  end if;
  if p_horario is not null then
    select array_agg(x[1]) into m from regexp_matches(p_horario, '(\d{1,2}[:h](?:\d{2})?)', 'g') as x;
    if array_length(m, 1) >= 2 then inicio := public.agenda_minutos(m[1]); fim := public.agenda_minutos(m[2]); end if;
  end if;
end $$;

create function public.agenda_espacos(p text) returns text[]
language sql immutable set search_path = '' as $$
  select coalesce(array_agg(btrim(x)) filter (where btrim(x) <> ''), '{}') from unnest(string_to_array(coalesce(p, ''), ',')) x
$$;

-- Lista os conflitos de uma ocupação (mesmo formato do modal da Agenda)
create function public.agenda_conflitos(p_data text, p_espacos text[], p_ini integer, p_fim integer,
                                        p_ignorar_evento text default null, p_ignorar_reserva text default null) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(c), '[]'::jsonb) from (
    select jsonb_build_object('tipo', 'Evento Oficial', 'titulo', e.titulo,
             'dataFmt', to_char(p_data::date, 'DD/MM/YYYY'),
             'espacos', array_to_string(array(select unnest(public.agenda_espacos(e.local)) intersect select unnest(p_espacos)), ', '),
             'horario', case when nullif(btrim(coalesce(e.horario_inicio::text,'')),'') is not null and nullif(btrim(coalesce(e.horario_fim::text,'')),'') is not null
                             then left(e.horario_inicio::text, 5) || ' às ' || left(e.horario_fim::text, 5) else coalesce(e.horario, '') end) as c
    from public.eventos e, lateral public.agenda_faixa_evento(e.horario_inicio::text, e.horario_fim::text, e.horario) f
    where e.data::text = p_data and (p_ignorar_evento is null or e.id::text <> p_ignorar_evento)
      and public.agenda_espacos(e.local) && p_espacos
      and p_ini is not null and p_fim is not null and f.inicio is not null and f.fim is not null
      and p_ini < f.fim and p_fim > f.inicio
    union all
    select jsonb_build_object('tipo', 'Reserva de Espaço', 'titulo', coalesce(r.ministerio, '') || ' (' || coalesce(r.motivo, '') || ')',
             'dataFmt', to_char(p_data::date, 'DD/MM/YYYY'),
             'espacos', array_to_string(array(select unnest(public.agenda_espacos(r.espacos)) intersect select unnest(p_espacos)), ', '),
             'horario', left(r.horario_inicio::text, 5) || ' às ' || left(r.horario_fim::text, 5))
    from public.reservas r
    where r.data::text = p_data and (p_ignorar_reserva is null or r.id::text <> p_ignorar_reserva)
      and public.agenda_espacos(r.espacos) && p_espacos
      and p_ini is not null and p_fim is not null
      and public.agenda_minutos(r.horario_inicio::text) is not null and public.agenda_minutos(r.horario_fim::text) is not null
      and p_ini < public.agenda_minutos(r.horario_fim::text) and p_fim > public.agenda_minutos(r.horario_inicio::text)
  ) t
$$;

-- Gatilho: eventos
create function public.tg_agenda_evento() returns trigger
language plpgsql security definer set search_path = '' as $$
declare f record; v_conf jsonb; v_coord boolean; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  v_coord := public.agenda_coordenador();

  -- Regras da ficha para quem não é da coordenação (chamadas do site: papel anon/authenticated no token)
  if tg_op = 'UPDATE' and coalesce(auth.role(), '') in ('anon', 'authenticated') and not v_coord then
    if new.titulo is distinct from old.titulo or new.data is distinct from old.data or new.bloqueado is distinct from old.bloqueado
       or new.ministerio_id is distinct from old.ministerio_id or new.criado_por is distinct from old.criado_por then
      raise exception 'Somente a coordenação altera nome, data, ministério responsável e bloqueio do evento.' using errcode = '42501';
    end if;
    if coalesce(old.bloqueado, false) or old.data::text::date < v_hoje then
      if (to_jsonb(new) - array['link_fotos','link_videos','atualizado_em','atualizado_por'])
         is distinct from (to_jsonb(old) - array['link_fotos','link_videos','atualizado_em','atualizado_por']) then
        raise exception 'Ficha bloqueada: agora só os links de Fotos e Vídeos podem ser alterados.' using errcode = '42501';
      end if;
    end if;
  end if;

  -- Autoria e vínculo com o ministério
  if tg_op = 'INSERT' then
    new.criado_por := coalesce(new.criado_por, auth.uid());
    if new.ministerio_id is null then new.ministerio_id := public.agenda_ministerio_por_nome(new.ministerio); end if;
  elsif v_coord and new.ministerio is distinct from old.ministerio and new.ministerio_id is not distinct from old.ministerio_id then
    new.ministerio_id := coalesce(public.agenda_ministerio_por_nome(new.ministerio), old.ministerio_id);
  end if;
  if auth.uid() is not null then new.atualizado_por := auth.uid(); end if;

  -- Conflito de espaço e horário (só quando data, local ou horário mudam)
  if tg_op = 'INSERT' or new.data is distinct from old.data or new.local is distinct from old.local
     or new.horario_inicio is distinct from old.horario_inicio or new.horario_fim is distinct from old.horario_fim
     or new.horario is distinct from old.horario then
    f := public.agenda_faixa_evento(new.horario_inicio::text, new.horario_fim::text, new.horario);
    if f.inicio is not null and f.fim is not null and nullif(btrim(coalesce(new.horario_inicio::text, '')), '') is not null
       and f.fim <= f.inicio then
      raise exception 'O horário de término deve ser posterior ao horário de início.' using errcode = '22023';
    end if;
    if new.data is not null and cardinality(public.agenda_espacos(new.local)) > 0 then
      perform pg_advisory_xact_lock(hashtext('betel-agenda-' || new.data::text));
      v_conf := public.agenda_conflitos(new.data::text, public.agenda_espacos(new.local), f.inicio, f.fim,
                                        case when tg_op = 'UPDATE' then old.id::text end, null);
      if jsonb_array_length(v_conf) > 0 then
        raise exception 'Conflito de espaço e horário com % registro(s).', jsonb_array_length(v_conf)
          using errcode = '23P01', detail = v_conf::text;
      end if;
    end if;
  end if;
  return new;
end $$;

-- Gatilho: reservas
create function public.tg_agenda_reserva() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_ini integer; v_fim integer; v_conf jsonb;
begin
  if tg_op = 'INSERT' then
    new.criado_por := coalesce(new.criado_por, auth.uid());
    new.criado_em := coalesce(new.criado_em, now());
    if new.ministerio_id is null then new.ministerio_id := public.agenda_ministerio_por_nome(new.ministerio); end if;
  end if;
  if tg_op = 'INSERT' or new.data is distinct from old.data or new.espacos is distinct from old.espacos
     or new.horario_inicio is distinct from old.horario_inicio or new.horario_fim is distinct from old.horario_fim then
    if cardinality(public.agenda_espacos(new.espacos)) = 0 then
      raise exception 'Selecione pelo menos um espaço (Templo, Salão de Festas ou Quadra).' using errcode = '22023';
    end if;
    v_ini := public.agenda_minutos(new.horario_inicio::text); v_fim := public.agenda_minutos(new.horario_fim::text);
    if v_ini is null or v_fim is null or v_fim <= v_ini then
      raise exception 'O horário de término deve ser posterior ao horário de início.' using errcode = '22023';
    end if;
    perform pg_advisory_xact_lock(hashtext('betel-agenda-' || new.data::text));
    v_conf := public.agenda_conflitos(new.data::text, public.agenda_espacos(new.espacos), v_ini, v_fim,
                                      null, case when tg_op = 'UPDATE' then old.id::text end);
    if jsonb_array_length(v_conf) > 0 then
      raise exception 'Conflito de espaço e horário em %: % registro(s).', to_char(new.data::text::date, 'DD/MM/YYYY'), jsonb_array_length(v_conf)
        using errcode = '23P01', detail = v_conf::text;
    end if;
  end if;
  return new;
end $$;

create trigger agenda_evento_regras before insert or update on public.eventos
  for each row execute function public.tg_agenda_evento();
create trigger agenda_reserva_regras before insert or update on public.reservas
  for each row execute function public.tg_agenda_reserva();

-- Histórico: a auditoria nunca guarda senhas (inclusive a senha antiga dos coordenadores)
create or replace function public.tg_auditar() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_antes jsonb; v_depois jsonb; v_id text;
begin
  if tg_op in ('UPDATE','DELETE') then v_antes := to_jsonb(old) - 'senha'; end if;
  if tg_op in ('INSERT','UPDATE') then v_depois := to_jsonb(new) - 'senha'; end if;
  if tg_op = 'UPDATE' and v_antes - 'atualizado_em' = v_depois - 'atualizado_em' then return new; end if;
  v_id := coalesce(v_depois ->> 'id', v_antes ->> 'id', v_depois ->> 'chave', v_antes ->> 'chave');
  insert into public.auditoria (ator, acao, tabela, registro, antes, depois)
  values (public.ator_atual(), lower(tg_op), tg_table_name, v_id, v_antes, v_depois);
  return coalesce(new, old);
end $$;
create trigger eventos_auditoria after insert or update or delete on public.eventos
  for each row execute function public.tg_auditar();
create trigger reservas_auditoria after insert or update or delete on public.reservas
  for each row execute function public.tg_auditar();
create trigger coordenadores_auditoria after insert or update or delete on public.coordenadores
  for each row execute function public.tg_auditar();

revoke execute on function public.agenda_minutos(text), public.agenda_faixa_evento(text, text, text), public.agenda_espacos(text),
  public.agenda_conflitos(text, text[], integer, integer, text, text), public.tg_agenda_evento(), public.tg_agenda_reserva()
  from public, anon, authenticated;

commit;
