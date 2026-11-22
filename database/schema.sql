-- =====================================================================
-- Sistema Betel — ESTRUTURA COMPLETA DO BANCO (somente leitura / referência)
--
-- Gerado com pg_dump --schema-only a partir de um banco instalado pelas
-- migrações deste repositório (database/plataforma + database/migrations,
-- até a M12). Não contém dados.
--
-- NÃO rode este arquivo num banco que já tem o sistema: as tabelas já
-- existem e a instalação oficial é feita pelas migrações (npm run migrate
-- ou o próprio servidor ao iniciar), que registram o que foi aplicado em
-- sistema.migracoes. Use este arquivo para consultar a estrutura, comparar
-- ambientes (diff) ou recriar a estrutura num banco VAZIO de análise.
-- Num banco vazio, crie antes os papéis anon, authenticated e service_role.
-- =====================================================================
--
--
-- PostgreSQL database dump
--


-- Dumped from database version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: armazenamento; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA armazenamento;


--
-- Name: auth; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA auth;


--
-- Name: sistema; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA sistema;


--
-- Name: jwt(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.jwt() RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  select coalesce(nullif(current_setting('request.jwt.claim', true), ''), nullif(current_setting('request.jwt.claims', true), ''))::jsonb $$;


--
-- Name: role(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.role() RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'))::text $$;


--
-- Name: uid(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.uid() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid $$;


--
-- Name: admin_atualizar_usuario(uuid, text, text[], jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_atualizar_usuario(p_usuario uuid, p_perfil text, p_atribuicoes text[], p_ministerios jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_pessoa uuid; v_item jsonb; v_ids uuid[];
begin
  if not public.e_master() then raise exception 'Somente o MASTER pode alterar perfis e permissões.' using errcode = '42501'; end if;
  if p_perfil not in ('MASTER','LIDER','VOLUNTARIO') then raise exception 'Perfil inválido.' using errcode = '22023'; end if;
  select pessoa_id into v_pessoa from public.perfis where id = p_usuario;
  if v_pessoa is null then raise exception 'Usuário não encontrado.' using errcode = 'P0002'; end if;
  update public.perfis set perfil = p_perfil, atribuicoes = coalesce(p_atribuicoes, '{}') where id = p_usuario;
  -- Vínculos: atualiza ou inclui; os que saíram ficam inativos (não são apagados)
  select coalesce(array_agg((e ->> 'ministerio_id')::uuid), '{}') into v_ids
    from jsonb_array_elements(coalesce(p_ministerios, '[]'::jsonb)) e;
  update public.ministerio_membros set ativo = false where pessoa_id = v_pessoa and ativo and not (ministerio_id = any(v_ids));
  for v_item in select * from jsonb_array_elements(coalesce(p_ministerios, '[]'::jsonb)) loop
    insert into public.ministerio_membros (pessoa_id, ministerio_id, funcao)
    values (v_pessoa, (v_item ->> 'ministerio_id')::uuid, v_item ->> 'funcao')
    on conflict (pessoa_id, ministerio_id) do update set funcao = excluded.funcao, ativo = true;
  end loop;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: admin_remover_foto(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_remover_foto(p_usuario uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_antiga text;
begin
  if not public.e_master() then raise exception 'Somente o MASTER.' using errcode = '42501'; end if;
  select foto_caminho into v_antiga from public.perfis where id = p_usuario;
  update public.perfis set foto_caminho = null where id = p_usuario;
  if v_antiga is not null then delete from armazenamento.objetos where espaco = 'perfis' and caminho = v_antiga; end if;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: admin_salvar_ministerio(uuid, text, text, integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_salvar_ministerio(p_id uuid, p_nome text, p_descricao text, p_ordem integer, p_ativo boolean) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_id uuid; v_nome text := regexp_replace(btrim(coalesce(p_nome,'')), '\s+', ' ', 'g');
begin
  if not public.e_master() then raise exception 'Somente o MASTER pode gerenciar ministérios.' using errcode = '42501'; end if;
  if char_length(v_nome) < 2 then raise exception 'Informe o nome do ministério.' using errcode = '22023'; end if;
  if p_id is null then
    insert into public.ministerios (nome, slug, descricao, ordem, ativo)
    values (v_nome, public.slugify(v_nome), nullif(btrim(p_descricao), ''), coalesce(p_ordem, 0), coalesce(p_ativo, true))
    returning id into v_id;
  else
    update public.ministerios set nome = v_nome, descricao = nullif(btrim(p_descricao), ''),
           ordem = coalesce(p_ordem, ordem), ativo = coalesce(p_ativo, ativo)
     where id = p_id returning id into v_id;
    if v_id is null then raise exception 'Ministério não encontrado.' using errcode = 'P0002'; end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
exception when unique_violation then
  raise exception 'Já existe um ministério com esse nome.' using errcode = '23505';
end $$;


--
-- Name: agenda_conflitos(text, text[], integer, integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_conflitos(p_data text, p_espacos text[], p_ini integer, p_fim integer, p_ignorar_evento text DEFAULT NULL::text, p_ignorar_reserva text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: agenda_coordenador(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_coordenador() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select public.perfil_ativo() and (public.e_master() or exists (
    select 1 from public.coordenadores c where c.usuario_id = auth.uid() and c.ativo))
$$;


--
-- Name: agenda_definir_coordenador(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_definir_coordenador(p_usuario uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_nome text; v_email text; v_id text;
begin
  if not public.e_master() then raise exception 'Somente o MASTER gerencia coordenadores.' using errcode = '42501'; end if;
  select pe.nome, pe.email into v_nome, v_email from public.perfis pf join public.pessoas pe on pe.id = pf.pessoa_id
   where pf.id = p_usuario and pf.ativo;
  if v_nome is null then raise exception 'Escolha uma conta ativa da equipe.' using errcode = '22023'; end if;
  update public.coordenadores set ativo = true where usuario_id = p_usuario returning id::text into v_id;
  if v_id is null then
    insert into public.coordenadores (nome, login, senha, ativo, usuario_id, migrado_em)
    values (v_nome, v_email, '', true, p_usuario, now()) returning id::text into v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
exception when unique_violation then
  raise exception 'Já existe um coordenador com o login %. Use "Ligar à conta" nesse coordenador.', v_email using errcode = '23505';
end $$;


--
-- Name: agenda_envio_decidir(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_envio_decidir(p_envio uuid, p_decisao text, p_motivo text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_e public.agenda_envios; v_id bigint; d jsonb;
begin
  if not public.agenda_coordenador() then raise exception 'Somente a coordenação da Agenda analisa os envios.' using errcode = '42501'; end if;
  select * into v_e from public.agenda_envios where id = p_envio for update;
  if v_e.id is null then raise exception 'Envio não encontrado.' using errcode = 'P0002'; end if;
  if v_e.status <> 'aguardando_analise' then raise exception 'Este envio já foi analisado.' using errcode = '22023'; end if;
  if p_decisao = 'recusar' then
    if public.texto_limpo(p_motivo, 500) is null then raise exception 'Informe o motivo da recusa.' using errcode = '22023'; end if;
    update public.agenda_envios set status = 'recusado', motivo = public.texto_limpo(p_motivo, 500), decidido_por = auth.uid(), decidido_em = now(), atualizado_em = now() where id = p_envio;
    insert into public.agenda_envios_historico (envio_id, acao, motivo, ator) values (p_envio, 'recusado', public.texto_limpo(p_motivo, 500), auth.uid());
  elsif p_decisao = 'aprovar' then
    d := v_e.dados;
    insert into public.eventos (titulo, data, ministerio, lider, horario, horario_inicio, horario_fim, local, necessita_midia, necessita_louvor,
                                necessita_diaconia, midia_tema, midia_arte, midia_banner, midia_inscricao, midia_link_inscricao, midia_info, observacoes)
    select r.titulo, r.data, r.ministerio, r.lider, r.horario, r.horario_inicio, r.horario_fim, r.local, r.necessita_midia, r.necessita_louvor,
           r.necessita_diaconia, r.midia_tema, r.midia_arte, r.midia_banner, r.midia_inscricao, r.midia_link_inscricao, r.midia_info,
           btrim(coalesce(r.observacoes, '') || case when d->>'contato_nome' is not null or d->>'contato_telefone' is not null
             then E'\n\nEnviado pelo formulário privado por ' || coalesce(d->>'contato_nome', '') || coalesce(' · ' || (d->>'contato_telefone'), '') else '' end)
      from jsonb_populate_record(null::public.eventos, d) r
    returning id into v_id;
    update public.agenda_envios set status = 'aprovado', evento_id = v_id, motivo = public.texto_limpo(p_motivo, 500),
           decidido_por = auth.uid(), decidido_em = now(), atualizado_em = now() where id = p_envio;
    insert into public.agenda_envios_historico (envio_id, acao, motivo, ator) values (p_envio, 'aprovado', public.texto_limpo(p_motivo, 500), auth.uid());
  else
    raise exception 'Decisão inválida.' using errcode = '22023';
  end if;
  return jsonb_build_object('ok', true, 'evento_id', v_id);
end $$;


--
-- Name: agenda_envios_listar(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_envios_listar(p_status text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.agenda_coordenador() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'link', l.rotulo, 'status', e.status, 'dados', e.dados, 'versao', e.versao,
       'enviado_em', e.enviado_em, 'atualizado_em', e.atualizado_em, 'decidido_em', e.decidido_em, 'motivo', e.motivo, 'evento_id', e.evento_id,
       'decidido_por', (select pe.nome from public.perfis p join public.pessoas pe on pe.id = p.pessoa_id where p.id = e.decidido_por),
       'historico', (select jsonb_agg(jsonb_build_object('quando', h.quando, 'acao', h.acao, 'motivo', h.motivo) order by h.id) from public.agenda_envios_historico h where h.envio_id = e.id))
       order by e.atualizado_em desc)
     from public.agenda_envios e join public.agenda_links l on l.id = e.link_id
     where p_status is null or e.status = p_status), '[]'::jsonb);
end $$;


--
-- Name: agenda_espacos(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_espacos(p text) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select coalesce(array_agg(btrim(x)) filter (where btrim(x) <> ''), '{}') from unnest(string_to_array(coalesce(p, ''), ',')) x
$$;


--
-- Name: agenda_evento_periodo(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_evento_periodo(p_evento bigint, OUT inicio timestamp with time zone, OUT fim timestamp with time zone) RETURNS record
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare e public.eventos; f record; d date;
begin
  select * into e from public.eventos where id = p_evento;
  if not found then return; end if;
  begin d := (e.data::text)::date; exception when others then return; end;
  select * into f from public.agenda_faixa_evento(e.horario_inicio::text, e.horario_fim::text, e.horario);
  if f.inicio is null then return; end if;
  inicio := (d + make_interval(mins => f.inicio)) at time zone 'America/Sao_Paulo';
  fim := (d + make_interval(mins => coalesce(nullif(f.fim, f.inicio), f.inicio + 120))) at time zone 'America/Sao_Paulo';
  if fim <= inicio then fim := fim + interval '1 day'; end if;
end $$;


--
-- Name: agenda_faixa_evento(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_faixa_evento(p_ini text, p_fim text, p_horario text, OUT inicio integer, OUT fim integer) RETURNS record
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $$
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


--
-- Name: agenda_link_abrir(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_link_abrir(p_token text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v record; v_e public.agenda_envios; v_min text;
begin
  select * into v from public.agenda_link_valido(p_token);
  if v.link is null or (v.link).id is null then return jsonb_build_object('ok', false, 'motivo', v.motivo); end if;
  insert into public.agenda_link_acessos (link_id, acao) values ((v.link).id, 'aberto');
  update public.agenda_links set usos = usos + 1, ultimo_uso_em = now() where id = (v.link).id;
  select * into v_e from public.agenda_envios where link_id = (v.link).id;
  select nome into v_min from public.ministerios where id = (v.link).ministerio_id;
  return jsonb_build_object('ok', true, 'rotulo', (v.link).rotulo, 'ministerio_fixo', v_min, 'titulo_sugerido', (v.link).titulo_sugerido,
    'expira_em', (v.link).expira_em, 'permite_complemento', (v.link).permite_complemento,
    'ministerios', case when v_min is null then (select jsonb_agg(nome order by ordem, nome) from public.ministerios where ativo) end,
    'envio', case when v_e.id is not null then jsonb_build_object('status', v_e.status, 'enviado_em', v_e.enviado_em, 'atualizado_em', v_e.atualizado_em,
       'versao', v_e.versao, 'dados', case when v_e.status = 'aguardando_analise' and (v.link).permite_complemento then v_e.dados end) end,
    'pode_enviar', v_e.id is null or (v_e.status = 'aguardando_analise' and (v.link).permite_complemento));
end $$;


--
-- Name: agenda_link_criar(text, uuid, text, integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_link_criar(p_rotulo text, p_ministerio uuid, p_titulo text, p_dias integer, p_permite_complemento boolean) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_token text := public.agenda_novo_token(); v_id uuid;
begin
  if not public.agenda_coordenador() then raise exception 'Somente a coordenação da Agenda gera links.' using errcode = '42501'; end if;
  if public.texto_limpo(p_rotulo, 120) is null then raise exception 'Dê um nome ao link (ex.: Retiro de Casais).' using errcode = '22023'; end if;
  if coalesce(p_dias, 0) not between 1 and 180 then raise exception 'A validade deve ser de 1 a 180 dias.' using errcode = '22023'; end if;
  if p_ministerio is not null and not exists (select 1 from public.ministerios where id = p_ministerio and ativo) then
    raise exception 'Ministério inválido.' using errcode = '22023'; end if;
  insert into public.agenda_links (token_hash, rotulo, ministerio_id, titulo_sugerido, expira_em, permite_complemento, criado_por)
  values (public.agenda_token_hash(v_token), public.texto_limpo(p_rotulo, 120), p_ministerio, public.texto_limpo(p_titulo, 120),
          now() + make_interval(days => p_dias), coalesce(p_permite_complemento, true), auth.uid())
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'token', v_token);   -- o token só aparece agora; no banco fica só o hash
end $$;


--
-- Name: agenda_link_enviar(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_link_enviar(p_token text, p_dados jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v record; v_e public.agenda_envios; v_d jsonb; v_min text;
begin
  select * into v from public.agenda_link_valido(p_token);
  if v.link is null or (v.link).id is null then
    raise exception '%', case v.motivo when 'expirado' then 'Este link expirou. Peça um novo à coordenação da Agenda.'
      when 'revogado' then 'Este link foi desativado. Peça um novo à coordenação da Agenda.'
      when 'bloqueado' then 'Muitas tentativas em pouco tempo. Aguarde alguns minutos.' else 'Link inválido.' end using errcode = '42501';
  end if;
  if pg_column_size(p_dados) > 20000 then raise exception 'Dados grandes demais.' using errcode = '22023'; end if;
  select nome into v_min from public.ministerios where id = (v.link).ministerio_id;
  begin
    v_d := public.agenda_validar_ficha(p_dados, v_min);
  exception when sqlstate '22023' then
    insert into public.agenda_link_acessos (link_id, acao) values ((v.link).id, 'recusado_dados'); raise;
  end;
  select * into v_e from public.agenda_envios where link_id = (v.link).id for update;
  if v_e.id is null then
    insert into public.agenda_envios (link_id, dados) values ((v.link).id, v_d) returning * into v_e;
    insert into public.agenda_envios_historico (envio_id, acao, dados) values (v_e.id, 'enviado', v_d);
    insert into public.agenda_link_acessos (link_id, acao) values ((v.link).id, 'enviado');
  elsif v_e.status = 'aguardando_analise' and (v.link).permite_complemento then
    update public.agenda_envios set dados = v_d, versao = versao + 1, atualizado_em = now() where id = v_e.id returning * into v_e;
    insert into public.agenda_envios_historico (envio_id, acao, dados) values (v_e.id, 'complementado', v_d);
    insert into public.agenda_link_acessos (link_id, acao) values ((v.link).id, 'complementado');
  else
    raise exception 'Estas informações já foram enviadas e estão em análise ou já foram analisadas.' using errcode = '42501';
  end if;
  return jsonb_build_object('ok', true, 'status', v_e.status, 'versao', v_e.versao, 'enviado_em', v_e.enviado_em);
end $$;


--
-- Name: agenda_link_novo_token(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_link_novo_token(p_link uuid, p_dias integer) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_token text := public.agenda_novo_token();
begin
  if not public.agenda_coordenador() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  if p_dias is not null and p_dias not between 1 and 180 then raise exception 'A validade deve ser de 1 a 180 dias.' using errcode = '22023'; end if;
  update public.agenda_links set token_hash = public.agenda_token_hash(v_token), token_trocado_em = now(), revogado_em = null, revogado_por = null,
         expira_em = case when p_dias is not null then now() + make_interval(days => p_dias) else greatest(expira_em, now() + interval '7 days') end
   where id = p_link;
  if not found then raise exception 'Link não encontrado.' using errcode = 'P0002'; end if;
  return jsonb_build_object('id', p_link, 'token', v_token);
end $$;


--
-- Name: agenda_link_revogar(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_link_revogar(p_link uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.agenda_coordenador() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  update public.agenda_links set revogado_em = now(), revogado_por = auth.uid() where id = p_link and revogado_em is null;
  if not found then raise exception 'Link não encontrado ou já revogado.' using errcode = 'P0002'; end if;
  return jsonb_build_object('ok', true);
end $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: agenda_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agenda_links (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    token_hash text NOT NULL,
    rotulo text NOT NULL,
    ministerio_id uuid,
    titulo_sugerido text,
    expira_em timestamp with time zone NOT NULL,
    permite_complemento boolean DEFAULT true NOT NULL,
    revogado_em timestamp with time zone,
    revogado_por uuid,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    token_trocado_em timestamp with time zone,
    usos integer DEFAULT 0 NOT NULL,
    ultimo_uso_em timestamp with time zone,
    CONSTRAINT agenda_links_rotulo_check CHECK (((char_length(btrim(rotulo)) >= 2) AND (char_length(btrim(rotulo)) <= 120))),
    CONSTRAINT agenda_links_titulo_sugerido_check CHECK ((char_length(titulo_sugerido) <= 120)),
    CONSTRAINT agenda_links_token_hash_check CHECK ((token_hash ~ '^[0-9a-f]{64}$'::text))
);


--
-- Name: agenda_link_valido(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_link_valido(p_token text, OUT link public.agenda_links, OUT motivo text) RETURNS record
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
begin
  if coalesce(p_token, '') !~ '^[0-9a-f]{64}$' then motivo := 'invalido'; return; end if;
  select * into link from public.agenda_links where token_hash = public.agenda_token_hash(p_token);
  if link.id is null then motivo := 'invalido'; return; end if;
  if link.revogado_em is not null then motivo := 'revogado'; insert into public.agenda_link_acessos (link_id, acao) values (link.id, 'recusado_revogado'); link := null; return; end if;
  if link.expira_em < now() then motivo := 'expirado'; insert into public.agenda_link_acessos (link_id, acao) values (link.id, 'recusado_expirado'); link := null; return; end if;
  -- proteção contra uso abusivo do mesmo link
  if (select count(*) from public.agenda_link_acessos where link_id = link.id and quando > now() - interval '10 minutes') >= 60 then
    motivo := 'bloqueado'; insert into public.agenda_link_acessos (link_id, acao) values (link.id, 'recusado_bloqueado'); link := null; return;
  end if;
end $_$;


--
-- Name: agenda_links_listar(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_links_listar() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.agenda_coordenador() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'rotulo', l.rotulo, 'ministerio', m.nome, 'ministerio_id', l.ministerio_id,
       'titulo_sugerido', l.titulo_sugerido, 'expira_em', l.expira_em, 'permite_complemento', l.permite_complemento,
       'revogado_em', l.revogado_em, 'criado_em', l.criado_em, 'usos', l.usos, 'ultimo_uso_em', l.ultimo_uso_em,
       'situacao', case when l.revogado_em is not null then 'revogado' when l.expira_em < now() then 'expirado' else 'ativo' end,
       'envio', (select jsonb_build_object('id', e.id, 'status', e.status, 'enviado_em', e.enviado_em, 'versao', e.versao) from public.agenda_envios e where e.link_id = l.id))
       order by l.criado_em desc)
     from public.agenda_links l left join public.ministerios m on m.id = l.ministerio_id), '[]'::jsonb);
end $$;


--
-- Name: agenda_listar_coordenadores(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_listar_coordenadores() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_master() then raise exception 'Somente o MASTER gerencia coordenadores.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id::text, 'nome', c.nome, 'login', c.login, 'ativo', c.ativo, 'usuario_id', c.usuario_id, 'migrado_em', c.migrado_em,
      'usuario_nome', pe.nome, 'usuario_email', pe.email, 'eu', c.usuario_id = auth.uid()) order by c.id)
    from public.coordenadores c left join public.perfis pf on pf.id = c.usuario_id left join public.pessoas pe on pe.id = pf.pessoa_id), '[]'::jsonb);
end $$;


--
-- Name: agenda_minhas_permissoes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_minhas_permissoes() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_p public.perfis; v_nome text;
begin
  if auth.uid() is null then return jsonb_build_object('status', 'anonimo'); end if;
  select * into v_p from public.perfis where id = auth.uid();
  if not found then return jsonb_build_object('status', 'sem_perfil'); end if;
  if not v_p.ativo then return jsonb_build_object('status', 'inativo'); end if;
  if v_p.deve_trocar_senha then return jsonb_build_object('status', 'trocar_senha'); end if;
  select nome into v_nome from public.pessoas where id = v_p.pessoa_id;
  return jsonb_build_object('status', 'ok', 'nome', v_nome, 'perfil', v_p.perfil,
    'master', v_p.perfil = 'MASTER', 'coordenador', public.agenda_coordenador(),
    'ministerios_lider', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'nome', m.nome) order by m.ordem)
       from public.ministerio_membros mm join public.ministerios m on m.id = mm.ministerio_id
       where mm.pessoa_id = v_p.pessoa_id and mm.funcao = 'lider' and mm.ativo and m.ativo and v_p.perfil in ('MASTER','LIDER')), '[]'::jsonb));
end $$;


--
-- Name: agenda_ministerio_por_nome(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_ministerio_por_nome(p_nome text) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  with alvo as (select public.slugify(p_nome) as s)
  select coalesce(
    (select m.id from public.ministerios m, alvo where m.slug = alvo.s and alvo.s <> ''),
    (select min(m.id::text)::uuid from public.ministerios m, alvo
      where alvo.s <> '' and m.slug like alvo.s || '-%'
      having count(*) = 1))
$$;


--
-- Name: agenda_minutos(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_minutos(p text) RETURNS integer
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $$
declare s text := regexp_replace(btrim(coalesce(p, '')), 'h', ':'); partes text[];
begin
  if s = '' then return null; end if;
  partes := string_to_array(s, ':');
  if array_length(partes, 1) < 2 or partes[1] !~ '^\s*\d+' then return null; end if;
  return substring(partes[1] from '^\s*(\d+)')::int * 60 + coalesce(nullif(substring(partes[2] from '^(\d+)'), '')::int, 0);
end $$;


--
-- Name: agenda_novo_token(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_novo_token() RETURNS text
    LANGUAGE sql
    SET search_path TO ''
    AS $$
  -- 2 UUIDs aleatórios (gerador criptográfico do PostgreSQL) = 244 bits; nada sequencial
  select replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')
$$;


--
-- Name: agenda_pode_editar_ficha(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_pode_editar_ficha(p_ministerio uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select public.agenda_coordenador() or (p_ministerio is not null and public.lider_de(p_ministerio))
$$;


--
-- Name: agenda_status_coordenador(text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_status_coordenador(p_coordenador text, p_ativo boolean) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_master() then raise exception 'Somente o MASTER gerencia coordenadores.' using errcode = '42501'; end if;
  update public.coordenadores set ativo = p_ativo where id::text = p_coordenador;
  if not found then raise exception 'Coordenador não encontrado.' using errcode = 'P0002'; end if;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: agenda_token_hash(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_token_hash(p_token text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$ select encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex') $$;


--
-- Name: agenda_validar_ficha(jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_validar_ficha(p jsonb, p_ministerio_fixo text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare v_data date; v_ini text := p->>'horario_inicio'; v_fim text := p->>'horario_fim'; v_locais text[]; v_min text;
        v_midia text := p->>'necessita_midia'; v_insc text := coalesce(p->>'midia_inscricao', ''); v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        sn text[] := array['Sim','Não'];
begin
  if public.texto_limpo(p->>'titulo', 120) is null or char_length(public.texto_limpo(p->>'titulo', 120)) < 3 then raise exception 'Informe o nome do evento.' using errcode = '22023'; end if;
  begin v_data := (p->>'data')::date; exception when others then raise exception 'Data inválida.' using errcode = '22023'; end;
  if v_data is null or v_data < v_hoje or v_data > v_hoje + 730 then raise exception 'Informe uma data a partir de hoje (até 2 anos).' using errcode = '22023'; end if;
  if public.texto_limpo(p->>'lider', 120) is null then raise exception 'Informe o líder responsável.' using errcode = '22023'; end if;
  v_min := coalesce(p_ministerio_fixo, public.texto_limpo(p->>'ministerio', 80));
  if v_min is null or not exists (select 1 from public.ministerios where nome = v_min and ativo) then raise exception 'Escolha o ministério na lista.' using errcode = '22023'; end if;
  if coalesce(v_ini, '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or coalesce(v_fim, '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Informe os horários de início e término.' using errcode = '22023'; end if;
  if v_fim <= v_ini then raise exception 'O horário de término deve ser depois do início.' using errcode = '22023'; end if;
  select array_agg(distinct x) into v_locais from jsonb_array_elements_text(coalesce(p->'locais', '[]')) x;
  if coalesce(cardinality(v_locais), 0) = 0 or not (v_locais <@ array['Templo','Salão de Festas','Quadra']) then raise exception 'Marque pelo menos um espaço.' using errcode = '22023'; end if;
  if not (v_midia = any(sn) and p->>'necessita_louvor' = any(sn) and p->>'necessita_diaconia' = any(sn)) then
    raise exception 'Responda se precisa de Mídia, Louvor e Diaconia.' using errcode = '22023'; end if;
  if v_midia = 'Sim' and public.texto_limpo(p->>'midia_tema', 160) is null then raise exception 'Informe o tema do evento para a Mídia.' using errcode = '22023'; end if;
  if v_midia = 'Sim' and v_insc = 'Sim' and coalesce(p->>'midia_link_inscricao', '') <> '' and p->>'midia_link_inscricao' !~ '^https://[^\s<>"]+$' then
    raise exception 'O link de inscrição deve começar com https://' using errcode = '22023'; end if;
  return jsonb_build_object('titulo', upper(public.texto_limpo(p->>'titulo', 120)), 'data', v_data::text, 'ministerio', v_min,
    'lider', public.texto_limpo(p->>'lider', 120), 'horario_inicio', v_ini, 'horario_fim', v_fim, 'horario', v_ini || ' às ' || v_fim,
    'local', array_to_string(array(select x from unnest(array['Templo','Salão de Festas','Quadra']) x where x = any(v_locais)), ', '),
    'necessita_midia', v_midia, 'necessita_louvor', p->>'necessita_louvor', 'necessita_diaconia', p->>'necessita_diaconia',
    'midia_tema', case when v_midia = 'Sim' then public.texto_limpo(p->>'midia_tema', 160) else '' end,
    'midia_arte', case when v_midia = 'Sim' and p->>'midia_arte' = any(sn) then p->>'midia_arte' else '' end,
    'midia_banner', case when v_midia = 'Sim' and p->>'midia_banner' = any(sn) then p->>'midia_banner' else '' end,
    'midia_inscricao', case when v_midia = 'Sim' and v_insc = any(sn) then v_insc else '' end,
    'midia_link_inscricao', case when v_midia = 'Sim' and v_insc = 'Sim' then coalesce(public.texto_limpo(p->>'midia_link_inscricao', 500), '') else '' end,
    'midia_info', case when v_midia = 'Sim' then coalesce(public.texto_limpo(p->>'midia_info', 1500), '') else '' end,
    'observacoes', coalesce(public.texto_limpo(p->>'observacoes', 2000), ''),
    'contato_nome', public.texto_limpo(p->>'contato_nome', 120), 'contato_telefone', public.texto_limpo(regexp_replace(coalesce(p->>'contato_telefone', ''), '[^0-9() +-]', '', 'g'), 20));
end $_$;


--
-- Name: agenda_vincular_coordenador(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.agenda_vincular_coordenador(p_coordenador text, p_usuario uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_master() then raise exception 'Somente o MASTER gerencia coordenadores.' using errcode = '42501'; end if;
  if not exists (select 1 from public.perfis where id = p_usuario and ativo) then
    raise exception 'Escolha uma conta ativa da equipe.' using errcode = '22023'; end if;
  update public.coordenadores set usuario_id = p_usuario, migrado_em = now() where id::text = p_coordenador;
  if not found then raise exception 'Coordenador não encontrado.' using errcode = 'P0002'; end if;
  return jsonb_build_object('ok', true);
exception when unique_violation then
  raise exception 'Esta conta já está ligada a outro coordenador.' using errcode = '23505';
end $$;


--
-- Name: apoio_cancelar(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apoio_cancelar(p_solicitacao uuid, p_motivo text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare s public.apoio_solicitacoes;
begin
  select * into s from public.apoio_solicitacoes where id = p_solicitacao for update;
  if not found or not (public.perfil_ativo() and (s.solicitado_por = auth.uid() or public.lider_de(s.ministerio_solicitante) or public.e_master())) then
    raise exception 'Acesso negado.' using errcode = '42501'; end if;
  if s.status in ('recusada','cancelada') then raise exception 'Solicitação já encerrada.' using errcode = '22023'; end if;
  if exists (select 1 from public.escala_eventos where solicitacao_id = s.id and status = 'publicada') then
    raise exception 'A escala já foi publicada: fale com a liderança de Mídia para cancelar.' using errcode = '22023'; end if;
  update public.apoio_solicitacoes set status = 'cancelada', motivo = nullif(btrim(p_motivo), '') where id = s.id;
  perform public.notificar_gestao(s.ministerio_alvo, 'solcanc:' || s.id, 'apoio_cancelada', 'Solicitação cancelada', s.titulo || coalesce(': ' || nullif(btrim(p_motivo), ''), ''), jsonb_build_object('solicitacao', s.id));
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: apoio_mensagem(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apoio_mensagem(p_solicitacao uuid, p_tipo text, p_texto text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare s public.apoio_solicitacoes; v_gestao boolean; v_solic boolean; u uuid;
begin
  select * into s from public.apoio_solicitacoes where id = p_solicitacao for update;
  if not found then raise exception 'Solicitação não encontrada.' using errcode = 'P0002'; end if;
  v_gestao := public.escala_gestor(s.ministerio_alvo);
  v_solic := public.perfil_ativo() and (s.solicitado_por = auth.uid() or public.lider_de(s.ministerio_solicitante));
  if not (v_gestao or v_solic) then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  if p_tipo in ('pedido_informacao','nota_interna') and not v_gestao then raise exception 'Somente a liderança de Mídia.' using errcode = '42501'; end if;
  if p_tipo not in ('mensagem','pedido_informacao','resposta','nota_interna') then raise exception 'Tipo inválido.' using errcode = '22023'; end if;
  if s.status in ('recusada','cancelada') then raise exception 'Solicitação encerrada.' using errcode = '22023'; end if;
  insert into public.apoio_solicitacao_mensagens (solicitacao_id, autor, tipo, texto) values (s.id, auth.uid(), p_tipo, btrim(p_texto));
  if p_tipo = 'pedido_informacao' then
    update public.apoio_solicitacoes set status = 'aguardando_informacoes' where id = s.id and status in ('enviada','em_analise','aguardando_informacoes');
    perform public.notificar_unico('solinfo:' || s.id || ':' || (select count(*) from public.apoio_solicitacao_mensagens where solicitacao_id = s.id), s.solicitado_por,
            'apoio_informacoes', 'A Mídia pediu informações', s.titulo || ': ' || btrim(p_texto), jsonb_build_object('solicitacao', s.id));
  elsif v_solic and not v_gestao and p_tipo in ('mensagem','resposta') then
    update public.apoio_solicitacoes set status = 'em_analise' where id = s.id and status = 'aguardando_informacoes';
    perform public.notificar_gestao(s.ministerio_alvo, 'solresp:' || s.id || ':' || (select count(*) from public.apoio_solicitacao_mensagens where solicitacao_id = s.id),
            'apoio_resposta', 'Resposta na solicitação', s.titulo || ': ' || left(btrim(p_texto), 200), jsonb_build_object('solicitacao', s.id));
  end if;
  return jsonb_build_object('ok', true);
exception when check_violation then raise exception 'Escreva a mensagem.' using errcode = '22023';
end $$;


--
-- Name: apoio_minhas_solicitacoes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apoio_minhas_solicitacoes() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'ministerios', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'nome', m.nome) order by m.nome) from public.ministerios m
        where m.ativo and public.pode_solicitar_apoio(m.id) and m.id <> public.midia_ministerio_id()), '[]'::jsonb),
    'solicitacoes', coalesce((select jsonb_agg(public.apoio_solicitacao_json(s.id, false) order by s.inicio desc) from public.apoio_solicitacoes s
        where s.solicitado_por = auth.uid() or public.lider_de(s.ministerio_solicitante)), '[]'::jsonb));
end $$;


--
-- Name: apoio_servicos_listar(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apoio_servicos_listar(p_ministerio uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.nome, 'descricao', s.descricao) order by s.ordem, s.nome)
    from public.apoio_servicos s where s.ministerio_id = coalesce(p_ministerio, public.midia_ministerio_id()) and s.ativo), '[]'::jsonb);
end $$;


--
-- Name: apoio_solicitacao_json(uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apoio_solicitacao_json(p_id uuid, p_interno boolean) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select jsonb_build_object('id', s.id, 'titulo', s.titulo, 'tipo_evento', s.tipo_evento, 'inicio', s.inicio, 'fim', s.fim, 'local', s.local, 'objetivo', s.objetivo,
    'descricao', s.descricao, 'informacoes', s.informacoes, 'prazo_retorno', s.prazo_retorno, 'status', s.status, 'motivo', s.motivo, 'criado_em', s.criado_em,
    'decidido_em', s.decidido_em, 'evento_id', s.evento_id, 'responsavel_nome', s.responsavel_nome, 'responsavel_contato', s.responsavel_contato,
    'ministerio_solicitante', (select nome from public.ministerios where id = s.ministerio_solicitante), 'ministerio_solicitante_id', s.ministerio_solicitante,
    'solicitado_por', (select x.nome from public.perfis pf join public.pessoas x on x.id = pf.pessoa_id where pf.id = s.solicitado_por),
    'decidido_por', (select x.nome from public.perfis pf join public.pessoas x on x.id = pf.pessoa_id where pf.id = s.decidido_por),
    'escala', (select jsonb_build_object('id', e.id, 'status', e.status) from public.escala_eventos e where e.solicitacao_id = s.id and e.status <> 'cancelada' limit 1),
    'servicos', coalesce((select jsonb_agg(jsonb_build_object('id', ss.id, 'servico_id', ss.servico_id, 'nome', sv.nome, 'detalhe', ss.detalhe, 'origem', ss.origem,
        'decisao', ss.decisao, 'motivo', ss.motivo) order by sv.ordem, sv.nome)
      from public.apoio_solicitacao_servicos ss join public.apoio_servicos sv on sv.id = ss.servico_id where ss.solicitacao_id = s.id), '[]'::jsonb),
    'mensagens', coalesce((select jsonb_agg(jsonb_build_object('tipo', m.tipo, 'texto', m.texto, 'criado_em', m.criado_em,
        'autor', (select x.nome from public.perfis pf join public.pessoas x on x.id = pf.pessoa_id where pf.id = m.autor)) order by m.criado_em)
      from public.apoio_solicitacao_mensagens m where m.solicitacao_id = s.id and (p_interno or m.tipo <> 'nota_interna')), '[]'::jsonb))
  from public.apoio_solicitacoes s where s.id = p_id
$$;


--
-- Name: apoio_solicitar(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apoio_solicitar(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_alvo uuid := coalesce(nullif(p->>'ministerio_alvo', '')::uuid, public.midia_ministerio_id()); v_sol uuid := (p->>'ministerio_solicitante')::uuid;
        v_ev bigint := nullif(p->>'evento_id', '')::bigint; ev public.eventos; per record; v_ini timestamptz; v_fim timestamptz; v_id uuid; x jsonb; n int := 0; mn text;
begin
  if v_sol is null or not public.pode_solicitar_apoio(v_sol) then
    raise exception 'Somente a liderança do ministério, a Secretaria ou a coordenação da Agenda solicitam apoio.' using errcode = '42501'; end if;
  v_ini := nullif(p->>'inicio', '')::timestamptz; v_fim := nullif(p->>'fim', '')::timestamptz;
  if v_ev is not null then
    select * into ev from public.eventos where id = v_ev;
    if not found then raise exception 'Evento da Agenda não encontrado.' using errcode = 'P0002'; end if;
    select * into per from public.agenda_evento_periodo(v_ev);
    v_ini := coalesce(per.inicio, v_ini); v_fim := coalesce(per.fim, v_fim);
  end if;
  if v_ini is null or v_fim is null then raise exception 'Informe data e horário de início e de término.' using errcode = '22023'; end if;
  if v_fim <= v_ini then raise exception 'O término precisa ser depois do início.' using errcode = '22023'; end if;
  if jsonb_array_length(coalesce(p->'servicos', '[]'::jsonb)) = 0 then raise exception 'Marque ao menos um serviço.' using errcode = '22023'; end if;
  insert into public.apoio_solicitacoes (ministerio_alvo, ministerio_solicitante, solicitado_por, responsavel_nome, responsavel_contato, evento_id, titulo, tipo_evento,
         inicio, fim, local, objetivo, descricao, informacoes, prazo_retorno)
  values (v_alvo, v_sol, auth.uid(), btrim(coalesce(p->>'responsavel_nome', '')), nullif(btrim(p->>'responsavel_contato'), ''), v_ev,
          btrim(coalesce(nullif(p->>'titulo', ''), ev.titulo, '')), coalesce(p->>'tipo_evento', 'outro'), v_ini, v_fim,
          btrim(coalesce(nullif(p->>'local', ''), ev.local, '')), nullif(btrim(p->>'objetivo'), ''), nullif(btrim(p->>'descricao'), ''),
          nullif(btrim(p->>'informacoes'), ''), nullif(p->>'prazo_retorno', '')::date) returning id into v_id;
  for x in select * from jsonb_array_elements(p->'servicos') loop
    if not exists (select 1 from public.apoio_servicos where id = (x->>'servico_id')::uuid and ministerio_id = v_alvo and ativo) then
      raise exception 'Serviço inválido.' using errcode = '22023'; end if;
    insert into public.apoio_solicitacao_servicos (solicitacao_id, servico_id, detalhe) values (v_id, (x->>'servico_id')::uuid, nullif(btrim(x->>'detalhe'), '')) on conflict do nothing;
    n := n + 1;
  end loop;
  select nome into mn from public.ministerios where id = v_sol;
  perform public.notificar_gestao(v_alvo, 'sol:' || v_id, 'apoio_nova', 'Nova solicitação de cobertura', mn || ' pediu apoio para "' || btrim(coalesce(nullif(p->>'titulo', ''), ev.titulo)) || '".', jsonb_build_object('solicitacao', v_id));
  return jsonb_build_object('ok', true, 'id', v_id, 'servicos', n);
exception
  when check_violation then raise exception 'Confira os campos: título (mínimo 3 letras), responsável, local e tipo de evento.' using errcode = '22023';
  when not_null_violation then raise exception 'Preencha os campos obrigatórios.' using errcode = '22023';
end $$;


--
-- Name: arquivo_autorizado(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.arquivo_autorizado(p_tipo text, p_id uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v text;
begin
  if p_tipo = 'comprovante' and public.e_tesouraria() then   -- comprovantes: só a Tesouraria abre os arquivos
    select arquivo_path into v from public.comprovantes where id = p_id;
  elsif p_tipo = 'documento' and public.e_secretaria() then
    select arquivo_path into v from public.documentos where id = p_id;
  end if;
  if v is not null then
    insert into public.auditoria (ator, acao, tabela, registro) values (auth.uid(), 'arquivo_consultado', case p_tipo when 'comprovante' then 'comprovantes' else 'documentos' end, p_id::text);
  end if;
  return v;
end $$;


--
-- Name: ator_atual(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ator_atual() RETURNS uuid
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select coalesce(auth.uid(), nullif(current_setting('app.ator', true), '')::uuid)
$$;


--
-- Name: autorizar_imagem_link(text, text, uuid, text, jsonb, jsonb, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.autorizar_imagem_link(p_protocolo text, p_chave text, p_termo uuid, p_decisao text, p_escopo jsonb, p_responsavel jsonb, p_data_nascimento date) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.inscricoes := public.link_inscricao(p_protocolo, p_chave); v_id uuid;
begin
  if p_data_nascimento is not null then
    update public.pessoas set data_nascimento = p_data_nascimento where id = i.pessoa_id and data_nascimento is null;
  end if;
  v_id := public.registrar_consentimento(i.pessoa_id, 'imagem_voz', p_termo, p_decisao, p_escopo, p_responsavel, 'link', 'inscricao', i.id);
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;


--
-- Name: cancelar_minha_inscricao_curso(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancelar_minha_inscricao_curso(p_protocolo text, p_chave text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.inscricoes;
begin
  select * into i from public.inscricoes where protocolo = upper(btrim(p_protocolo))
     and chave_hash = encode(sha256(convert_to(coalesce(p_chave, ''), 'UTF8')), 'hex') for update;
  if not found then raise exception 'Inscrição não encontrada.' using errcode = 'P0002'; end if;
  if i.status not in ('confirmada','aguardando_pagamento','lista_espera') then raise exception 'Esta inscrição não pode mais ser cancelada pelo link.' using errcode = '22023'; end if;
  update public.inscricoes set status = 'cancelada', cancelada_em = now(), motivo_cancelamento = 'Cancelada pelo participante' where id = i.id;
  perform public.cursos_promover_fila(i.turma_id);
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: candidatura_json(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.candidatura_json(p_cand uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select jsonb_build_object('id', c.id, 'status', c.status, 'criado_em', c.criado_em, 'observacao', c.observacao,
    'pessoa_id', pe.id, 'nome', pe.nome, 'telefone', pe.telefone, 'email', pe.email,
    'requisitos', public.voluntariado_requisitos(pe.id),
    'indicacoes', coalesce((select jsonb_agg(jsonb_build_object('id', vi.id, 'ministerio_id', vi.ministerio_id, 'ministerio', m.nome, 'ordem', vi.ordem,
        'status', vi.status, 'motivo', vi.motivo, 'analisado_em', vi.analisado_em,
        'analisado_por', (select x.nome from public.perfis pf join public.pessoas x on x.id = pf.pessoa_id where pf.id = vi.analisado_por)) order by vi.ordem)
        from public.voluntariado_indicacoes vi join public.ministerios m on m.id = vi.ministerio_id where vi.candidatura_id = c.id), '[]'::jsonb))
  from public.voluntariado_candidaturas c join public.pessoas pe on pe.id = c.pessoa_id where c.id = p_cand
$$;


--
-- Name: certificado_impressao_json(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.certificado_impressao_json(p_cert uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select jsonb_build_object('id', ce.id, 'codigo', ce.codigo, 'nome', pe.nome, 'curso', c.titulo, 'carga_horaria', c.carga_horaria, 'modalidade', c.modalidade,
         'concluida_em', i.concluida_em, 'turma', t.nome, 'cerimonia', cm.titulo, 'cerimonia_data', cm.data, 'cerimonia_local', cm.local,
         'modelo', coalesce((select valor from public.configuracoes where chave = 'certificado_modelo'), '{}'::jsonb))
    from public.certificados ce join public.inscricoes i on i.id = ce.inscricao_id join public.pessoas pe on pe.id = i.pessoa_id
    join public.turmas t on t.id = i.turma_id join public.cursos c on c.id = t.curso_id left join public.cerimonias cm on cm.id = ce.cerimonia_id where ce.id = p_cert
$$;


--
-- Name: certificado_validador(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.certificado_validador(p_turma uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select public.perfil_ativo() and (
    public.e_master()
    or exists (select 1 from public.turma_responsaveis r where r.turma_id = p_turma and r.ativo and r.perfil_id = auth.uid())
    or exists (select 1 from public.turmas t join public.cursos c on c.id = t.curso_id where t.id = p_turma and c.ministerio_id is not null and public.lider_de(c.ministerio_id)))
$$;


--
-- Name: certificado_validador_uid(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.certificado_validador_uid(p_turma uuid, p_uid uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select p_uid is not null and (
    public.e_master_uid(p_uid)
    or exists (select 1 from public.turma_responsaveis r where r.turma_id = p_turma and r.ativo and r.perfil_id = p_uid)
    or exists (select 1 from public.turmas t join public.cursos c on c.id = t.curso_id join public.ministerio_membros mm on mm.ministerio_id = c.ministerio_id
                join public.perfis pf on pf.pessoa_id = mm.pessoa_id where t.id = p_turma and pf.id = p_uid and mm.funcao = 'lider' and mm.ativo and pf.ativo))
$$;


--
-- Name: colegio_etapa_salvar(uuid, jsonb, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.colegio_etapa_salvar(p_id uuid, p_dados jsonb, p_validado boolean) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare v_e public.colegio_etapas; v_foto text := nullif(btrim(coalesce(p_dados->>'foto', '')), '');
        v_obj text[]; v_dif text[];
begin
  if not public.e_master() then raise exception 'Somente o MASTER altera as etapas do Colégio.' using errcode = '42501'; end if;
  select * into v_e from public.colegio_etapas where id = p_id for update;
  if v_e.id is null then raise exception 'Etapa não encontrada.' using errcode = 'P0002'; end if;
  if v_foto is not null and not (v_foto ~ '^img/[a-z0-9._/-]+$' or (v_foto ~ '^site/colegio/[0-9a-f-]{36}\.(jpg|png|webp)$' and public.imagem_existe('site', substr(v_foto, 6)))) then
    raise exception 'Imagem inválida.' using errcode = '22023'; end if;
  select coalesce(array_agg(public.texto_limpo(x, 240)) filter (where public.texto_limpo(x, 240) is not null), '{}') into v_obj from jsonb_array_elements_text(coalesce(p_dados->'objetivos', '[]')) x;
  select coalesce(array_agg(public.texto_limpo(x, 240)) filter (where public.texto_limpo(x, 240) is not null), '{}') into v_dif from jsonb_array_elements_text(coalesce(p_dados->'diferenciais', '[]')) x;
  if public.texto_limpo(p_dados->>'descricao', 4000) is null then raise exception 'A descrição é obrigatória.' using errcode = '22023'; end if;
  update public.colegio_etapas set titulo = coalesce(public.texto_limpo(p_dados->>'titulo', 80), titulo),
    subtitulo = public.texto_limpo(p_dados->>'subtitulo', 160), descricao = public.texto_limpo(p_dados->>'descricao', 4000),
    objetivos = v_obj, diferenciais = v_dif, faixa_etaria = public.texto_limpo(p_dados->>'faixa_etaria', 120),
    foto = v_foto, foto_alt = public.texto_limpo(p_dados->>'foto_alt', 200),
    ativo = coalesce((p_dados->>'ativo')::boolean, ativo),
    validado = coalesce(p_validado, false), validado_em = case when p_validado then now() end, validado_por = case when p_validado then auth.uid() end
  where id = p_id;
  if v_e.foto is distinct from v_foto then perform public.site_apagar_imagem(v_e.foto); end if;
  return public.colegio_etapas_admin();
end $_$;


--
-- Name: colegio_etapas_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.colegio_etapas_admin() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_master() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(e) - 'criado_em' order by e.ordem) from public.colegio_etapas e), '[]'::jsonb);
end $$;


--
-- Name: consentimentos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.consentimentos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pessoa_id uuid NOT NULL,
    termo_id uuid NOT NULL,
    tipo text NOT NULL,
    decisao text NOT NULL,
    escopo jsonb DEFAULT '{}'::jsonb NOT NULL,
    dado_por text NOT NULL,
    menor_na_data boolean DEFAULT false NOT NULL,
    responsavel jsonb,
    origem text NOT NULL,
    contexto_tipo text,
    contexto_id uuid,
    documento_id uuid,
    texto_hash text NOT NULL,
    registrado_por uuid,
    registrado_em timestamp with time zone DEFAULT now() NOT NULL,
    revogado_em timestamp with time zone,
    revogado_via text,
    revogado_por uuid,
    motivo_revogacao text,
    CONSTRAINT consentimentos_check CHECK (((dado_por = 'titular'::text) OR ((responsavel ? 'nome'::text) AND (responsavel ? 'parentesco'::text)))),
    CONSTRAINT consentimentos_check1 CHECK (((NOT menor_na_data) OR (dado_por = 'responsavel'::text))),
    CONSTRAINT consentimentos_check2 CHECK (((tipo <> 'imagem_voz'::text) OR (decisao = 'recusado'::text) OR (escopo ?| ARRAY['fotos'::text, 'videos'::text, 'voz'::text]))),
    CONSTRAINT consentimentos_contexto_tipo_check CHECK ((contexto_tipo = ANY (ARRAY['inscricao'::text, 'candidatura'::text, 'avulso'::text]))),
    CONSTRAINT consentimentos_dado_por_check CHECK ((dado_por = ANY (ARRAY['titular'::text, 'responsavel'::text]))),
    CONSTRAINT consentimentos_decisao_check CHECK ((decisao = ANY (ARRAY['aceito'::text, 'recusado'::text]))),
    CONSTRAINT consentimentos_motivo_revogacao_check CHECK ((char_length(motivo_revogacao) <= 600)),
    CONSTRAINT consentimentos_origem_check CHECK ((origem = ANY (ARRAY['site'::text, 'link'::text, 'secretaria'::text]))),
    CONSTRAINT consentimentos_revogado_via_check CHECK ((revogado_via = ANY (ARRAY['titular'::text, 'responsavel'::text, 'secretaria'::text]))),
    CONSTRAINT consentimentos_tipo_check CHECK ((tipo = ANY (ARRAY['participacao_curso'::text, 'imagem_voz'::text, 'voluntariado'::text])))
);


--
-- Name: consentimento_atual(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.consentimento_atual(p_pessoa uuid, p_tipo text) RETURNS public.consentimentos
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select c.* from public.consentimentos c join public.termos t on t.id = c.termo_id
   where c.pessoa_id = p_pessoa and c.tipo = p_tipo and c.revogado_em is null
     and not exists (select 1 from public.termos n where n.tipo = p_tipo and n.status = 'vigente'
                      and n.versao > t.versao and n.exige_novo_aceite)
   order by c.registrado_em desc limit 1
$$;


--
-- Name: consentimentos_json(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.consentimentos_json(p_pessoa uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'tipo', c.tipo, 'decisao', c.decisao, 'escopo', c.escopo, 'versao', t.versao,
           'titulo', t.titulo, 'dado_por', c.dado_por, 'responsavel', c.responsavel->>'nome', 'origem', c.origem, 'registrado_em', c.registrado_em,
           'revogado_em', c.revogado_em, 'revogado_via', c.revogado_via, 'motivo_revogacao', c.motivo_revogacao,
           'em_vigor', c.id = (public.consentimento_atual(c.pessoa_id, c.tipo)).id,
           'versao_desatualizada', exists (select 1 from public.termos n where n.tipo = c.tipo and n.status = 'vigente' and n.versao > t.versao))
         order by c.registrado_em desc), '[]'::jsonb)
    from public.consentimentos c join public.termos t on t.id = c.termo_id where c.pessoa_id = p_pessoa
$$;


--
-- Name: curso_concluido(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.curso_concluido(p_pessoa uuid, p_curso uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (select 1 from public.inscricoes i join public.turmas t on t.id = i.turma_id
                  where i.pessoa_id = p_pessoa and t.curso_id = p_curso and i.status = 'concluida')
      or exists (select 1 from public.cursos_conclusoes_anteriores c
                  where c.pessoa_id = p_pessoa and c.curso_id = p_curso and c.cancelado_em is null)
$$;


--
-- Name: curso_id_por_slug(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.curso_id_por_slug(p_slug text) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$ select id from public.cursos where slug = p_slug $$;


--
-- Name: curso_publico(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.curso_publico(p_slug text) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select public.cursos_json_curso(c, true) from public.cursos c where c.slug = p_slug and c.publicado
$$;


--
-- Name: cursos_admin_listar(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cursos_admin_listar() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.cursos_gestor() then raise exception 'Somente a Secretaria ou o MASTER gerenciam cursos.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'categorias', (select coalesce(jsonb_agg(to_jsonb(cat) order by cat.ordem, cat.nome), '[]') from public.categorias_curso cat),
    'cursos', (select coalesce(jsonb_agg(public.cursos_json_curso(c, false) order by c.ordem, c.titulo), '[]') from public.cursos c));
end $$;


--
-- Name: cursos_alterar_inscricao(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cursos_alterar_inscricao(p_inscricao uuid, p_acao text, p_motivo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.inscricoes; t public.turmas;
begin
  if not public.cursos_gestor() then raise exception 'Somente a Secretaria ou o MASTER alteram inscrições.' using errcode = '42501'; end if;
  select * into i from public.inscricoes where id = p_inscricao for update;
  if not found then raise exception 'Inscrição não encontrada.' using errcode = 'P0002'; end if;
  select * into t from public.turmas where id = i.turma_id;
  if p_acao = 'cancelar' then
    if i.status in ('cancelada','concluida') then raise exception 'Esta inscrição não pode ser cancelada.' using errcode = '22023'; end if;
    if char_length(btrim(coalesce(p_motivo, ''))) < 3 then raise exception 'Informe o motivo do cancelamento.' using errcode = '22023'; end if;
    update public.inscricoes set status = 'cancelada', cancelada_em = now(), motivo_cancelamento = btrim(p_motivo) where id = i.id;
    perform public.cursos_promover_fila(i.turma_id);
  elsif p_acao = 'promover' then
    if i.status <> 'lista_espera' then raise exception 'Só inscrições na lista de espera podem ser promovidas.' using errcode = '22023'; end if;
    update public.inscricoes set status = case when coalesce(t.valor, 0) > 0 then 'aguardando_pagamento' else 'confirmada' end, promovida_em = now() where id = i.id;
  elsif p_acao = 'concluir' then
    if i.status <> 'confirmada' then raise exception 'Só inscrições confirmadas podem ser marcadas como concluídas.' using errcode = '22023'; end if;
    update public.inscricoes set status = 'concluida', concluida_em = now(), concluida_por = auth.uid() where id = i.id;
  elsif p_acao = 'reabrir_conclusao' then
    if i.status <> 'concluida' then raise exception 'A inscrição não está concluída.' using errcode = '22023'; end if;
    update public.inscricoes set status = 'confirmada', concluida_em = null, concluida_por = null where id = i.id;
  else
    raise exception 'Ação inválida.' using errcode = '22023';
  end if;
  return jsonb_build_object('ok', true);
exception when check_violation then raise exception 'Turma sem vagas.' using errcode = '22023';
end $$;


--
-- Name: cursos_atualizar_participante(uuid, text, text, text, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cursos_atualizar_participante(p_pessoa uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.cursos_gestor() then raise exception 'Somente a Secretaria ou o MASTER editam participantes.' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p_nome, ''))) < 3 or btrim(p_nome) !~ '\s' then raise exception 'Informe o nome completo.' using errcode = '22023'; end if;
  update public.pessoas set nome = regexp_replace(btrim(p_nome), '\s+', ' ', 'g'), telefone = nullif(public.so_digitos(p_telefone), ''),
         email = nullif(lower(btrim(p_email)), ''), data_nascimento = p_data_nascimento where id = p_pessoa;
  if not found then raise exception 'Participante não encontrado.' using errcode = 'P0002'; end if;
  return jsonb_build_object('ok', true);
exception
  when unique_violation then raise exception 'Já existe outro cadastro com este e-mail.' using errcode = '23505';
  when check_violation then raise exception 'Confira o telefone (com DDD) e o e-mail.' using errcode = '22023';
end $$;


--
-- Name: cursos_definir_responsaveis(uuid, uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cursos_definir_responsaveis(p_turma uuid, p_perfis uuid[]) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.cursos_gestor() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  if not exists (select 1 from public.turmas where id = p_turma) then raise exception 'Turma não encontrada.' using errcode = 'P0002'; end if;
  if exists (select 1 from unnest(coalesce(p_perfis, '{}')) x where not exists (select 1 from public.perfis pf where pf.id = x and pf.ativo and pf.perfil in ('MASTER','LIDER'))) then
    raise exception 'Responsável inválido: escolha líderes com conta ativa.' using errcode = '22023'; end if;
  update public.turma_responsaveis set ativo = false where turma_id = p_turma and ativo and not (perfil_id = any(coalesce(p_perfis, '{}')));
  insert into public.turma_responsaveis (turma_id, perfil_id, criado_por) select p_turma, x, auth.uid() from unnest(coalesce(p_perfis, '{}')) x
  on conflict (turma_id, perfil_id) do update set ativo = true;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: cursos_gestor(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cursos_gestor() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select public.e_master() or public.tem_atribuicao('SECRETARIA')
$$;


--
-- Name: cursos_historico_participante(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cursos_historico_participante(p_pessoa uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.cursos_gestor() then raise exception 'Somente a Secretaria ou o MASTER veem o histórico.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'pessoa', (select to_jsonb(pe) - 'usuario_id' from public.pessoas pe where pe.id = p_pessoa),
    'inscricoes', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'protocolo', i.protocolo, 'status', i.status, 'curso', c.titulo, 'turma', t.nome,
        'criado_em', i.criado_em, 'origem', i.origem, 'promovida_em', i.promovida_em, 'cancelada_em', i.cancelada_em,
        'motivo_cancelamento', i.motivo_cancelamento, 'concluida_em', i.concluida_em,
        'eventos', (select coalesce(jsonb_agg(jsonb_build_object('quando', a.quando, 'acao', a.acao,
                       'de', a.antes->>'status', 'para', a.depois->>'status',
                       'por', coalesce((select pe2.nome from public.perfis pf join public.pessoas pe2 on pe2.id = pf.pessoa_id where pf.id = a.ator), 'Site / sistema'))
                       order by a.id), '[]')
                    from public.auditoria a where a.tabela = 'inscricoes' and a.registro = i.id::text
                      and (a.acao = 'insert' or a.antes->>'status' is distinct from a.depois->>'status')))
        order by i.criado_em desc)
      from public.inscricoes i join public.turmas t on t.id = i.turma_id join public.cursos c on c.id = t.curso_id where i.pessoa_id = p_pessoa), '[]'::jsonb));
end $$;


--
-- Name: cursos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cursos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    categoria_id uuid NOT NULL,
    ministerio_id uuid,
    titulo text NOT NULL,
    slug text NOT NULL,
    resumo text,
    descricao text,
    publico_alvo text,
    imagem_url text,
    carga_horaria text,
    modalidade text DEFAULT 'presencial'::text NOT NULL,
    plataforma_url text,
    exige_membro boolean DEFAULT false NOT NULL,
    cursos_exigidos uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    termos_exigidos text[] DEFAULT '{}'::text[] NOT NULL,
    publicado boolean DEFAULT false NOT NULL,
    ordem integer DEFAULT 0 NOT NULL,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT cursos_carga_horaria_check CHECK ((char_length(carga_horaria) <= 60)),
    CONSTRAINT cursos_descricao_check CHECK ((char_length(descricao) <= 6000)),
    CONSTRAINT cursos_imagem_url_check CHECK (((imagem_url IS NULL) OR (imagem_url ~ '^(https?://|/|img/)'::text))),
    CONSTRAINT cursos_modalidade_check CHECK ((modalidade = ANY (ARRAY['presencial'::text, 'online'::text, 'hibrido'::text]))),
    CONSTRAINT cursos_plataforma_url_check CHECK (((plataforma_url IS NULL) OR (plataforma_url ~ '^https://'::text))),
    CONSTRAINT cursos_publico_alvo_check CHECK ((char_length(publico_alvo) <= 600)),
    CONSTRAINT cursos_resumo_check CHECK ((char_length(resumo) <= 300)),
    CONSTRAINT cursos_slug_check CHECK ((slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::text)),
    CONSTRAINT cursos_titulo_check CHECK (((char_length(btrim(titulo)) >= 2) AND (char_length(btrim(titulo)) <= 140)))
);


--
-- Name: cursos_json_curso(public.cursos, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cursos_json_curso(c public.cursos, p_turmas_publicas boolean) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select jsonb_build_object('id', c.id, 'titulo', c.titulo, 'slug', c.slug, 'resumo', c.resumo, 'descricao', c.descricao,
    'publico_alvo', c.publico_alvo, 'imagem_url', c.imagem_url, 'carga_horaria', c.carga_horaria, 'modalidade', c.modalidade,
    'exige_membro', c.exige_membro, 'publicado', c.publicado, 'ordem', c.ordem,
    'categoria_id', c.categoria_id, 'categoria', (select nome from public.categorias_curso where id = c.categoria_id),
    'ministerio_id', c.ministerio_id, 'cursos_exigidos', to_jsonb(c.cursos_exigidos),
    'exigidos_nomes', (select coalesce(jsonb_agg(x.titulo), '[]') from public.cursos x where x.id = any(c.cursos_exigidos)),
    'turmas', coalesce((select jsonb_agg(public.cursos_json_turma(t) order by t.data_inicio nulls last, t.criado_em)
                        from public.turmas t where t.curso_id = c.id
                          and (not p_turmas_publicas or t.status in ('inscricoes_abertas','inscricoes_encerradas','em_andamento'))), '[]'::jsonb))
$$;


--
-- Name: turmas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.turmas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    curso_id uuid NOT NULL,
    nome text NOT NULL,
    data_inicio date,
    data_fim date,
    dias_horario text,
    local text,
    professores text,
    vagas integer,
    lista_espera boolean DEFAULT true NOT NULL,
    valor numeric(10,2),
    inscricao_abre_em timestamp with time zone,
    inscricao_fecha_em timestamp with time zone,
    status text DEFAULT 'rascunho'::text NOT NULL,
    link_online text,
    lote_reserva text,
    observacoes text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT turmas_check CHECK (((data_fim IS NULL) OR (data_inicio IS NULL) OR (data_fim >= data_inicio))),
    CONSTRAINT turmas_check1 CHECK (((inscricao_fecha_em IS NULL) OR (inscricao_abre_em IS NULL) OR (inscricao_fecha_em > inscricao_abre_em))),
    CONSTRAINT turmas_dias_horario_check CHECK ((char_length(dias_horario) <= 200)),
    CONSTRAINT turmas_link_online_check CHECK (((link_online IS NULL) OR (link_online ~ '^https://'::text))),
    CONSTRAINT turmas_local_check CHECK ((char_length(local) <= 200)),
    CONSTRAINT turmas_nome_check CHECK (((char_length(btrim(nome)) >= 2) AND (char_length(btrim(nome)) <= 120))),
    CONSTRAINT turmas_observacoes_check CHECK ((char_length(observacoes) <= 1000)),
    CONSTRAINT turmas_professores_check CHECK ((char_length(professores) <= 300)),
    CONSTRAINT turmas_status_check CHECK ((status = ANY (ARRAY['rascunho'::text, 'inscricoes_abertas'::text, 'inscricoes_encerradas'::text, 'em_andamento'::text, 'concluida'::text, 'cancelada'::text]))),
    CONSTRAINT turmas_vagas_check CHECK (((vagas IS NULL) OR ((vagas >= 1) AND (vagas <= 5000)))),
    CONSTRAINT turmas_valor_check CHECK (((valor IS NULL) OR (valor >= (0)::numeric)))
);


--
-- Name: cursos_json_turma(public.turmas); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cursos_json_turma(t public.turmas) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select jsonb_build_object('id', t.id, 'nome', t.nome, 'data_inicio', t.data_inicio, 'data_fim', t.data_fim,
    'dias_horario', t.dias_horario, 'local', t.local, 'professores', t.professores, 'vagas', t.vagas,
    'lista_espera', t.lista_espera, 'valor', t.valor, 'inscricao_abre_em', t.inscricao_abre_em, 'inscricao_fecha_em', t.inscricao_fecha_em,
    'status', t.status, 'aberta', public.turma_aberta(t),
    'vagas_restantes', case when t.vagas is null then null else greatest(t.vagas - (public.cursos_vagas_turma(t.id)->>'ocupadas')::int, 0) end,
    'na_espera', (public.cursos_vagas_turma(t.id)->>'espera')::int)
$$;


--
-- Name: cursos_listar_inscricoes(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cursos_listar_inscricoes(p_turma uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.cursos_gestor() then raise exception 'Somente a Secretaria ou o MASTER veem as inscrições.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'protocolo', i.protocolo, 'status', i.status, 'origem', i.origem,
      'criado_em', i.criado_em, 'promovida_em', i.promovida_em, 'cancelada_em', i.cancelada_em, 'motivo_cancelamento', i.motivo_cancelamento,
      'concluida_em', i.concluida_em, 'valor_final', i.valor_final, 'observacao', i.observacao,
      'pessoa_id', pe.id, 'nome', pe.nome, 'email', pe.email, 'telefone', pe.telefone, 'data_nascimento', pe.data_nascimento)
      order by case i.status when 'lista_espera' then 2 when 'cancelada' then 3 else 1 end, i.criado_em)
    from public.inscricoes i join public.pessoas pe on pe.id = i.pessoa_id where i.turma_id = p_turma), '[]'::jsonb);
end $$;


--
-- Name: cursos_participantes(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cursos_participantes(p_busca text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v text := '%' || lower(btrim(coalesce(p_busca, ''))) || '%';
begin
  if not public.cursos_gestor() then raise exception 'Somente a Secretaria ou o MASTER veem participantes.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(x order by x->>'nome') from (
    select jsonb_build_object('id', pe.id, 'nome', pe.nome, 'email', pe.email, 'telefone', pe.telefone, 'data_nascimento', pe.data_nascimento,
             'situacao_membresia', pe.situacao_membresia,
             'inscricoes', (select count(*) from public.inscricoes i where i.pessoa_id = pe.id),
             'ativas', (select count(*) from public.inscricoes i where i.pessoa_id = pe.id and i.status not in ('cancelada','concluida')),
             'concluidas', (select count(*) from public.inscricoes i where i.pessoa_id = pe.id and i.status = 'concluida')) as x
    from public.pessoas pe
    where pe.arquivado_em is null and exists (select 1 from public.inscricoes i where i.pessoa_id = pe.id)
      and (lower(pe.nome) like v or lower(coalesce(pe.email, '')) like v or (coalesce(public.so_digitos(p_busca), '') <> '' and coalesce(pe.telefone, '') like '%' || public.so_digitos(p_busca) || '%'))
    limit 300) t), '[]'::jsonb);
end $$;


--
-- Name: cursos_promover_fila(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cursos_promover_fila(p_turma uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare t public.turmas; v_livres integer; v_n integer := 0; v_id uuid;
begin
  select * into t from public.turmas where id = p_turma for update;
  if t.status in ('cancelada','concluida') then return 0; end if;
  loop
    if t.vagas is not null then
      v_livres := t.vagas - (public.cursos_vagas_turma(p_turma)->>'ocupadas')::int;
      exit when v_livres <= 0;
    end if;
    select id into v_id from public.inscricoes where turma_id = p_turma and status = 'lista_espera' order by criado_em, protocolo limit 1;
    exit when v_id is null;
    update public.inscricoes set status = case when coalesce(t.valor, 0) > 0 then 'aguardando_pagamento' else 'confirmada' end,
           promovida_em = now() where id = v_id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;


--
-- Name: cursos_publicos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cursos_publicos() RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(jsonb_agg(jsonb_build_object('id', cat.id, 'nome', cat.nome, 'descricao', cat.descricao,
           'cursos', (select coalesce(jsonb_agg(public.cursos_json_curso(c, true) order by c.ordem, c.titulo), '[]')
                      from public.cursos c where c.categoria_id = cat.id and c.publicado)) order by cat.ordem, cat.nome), '[]'::jsonb)
  from public.categorias_curso cat where cat.ativo
$$;


--
-- Name: cursos_responsaveis_turma(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cursos_responsaveis_turma(p_turma uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.cursos_gestor() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('perfil_id', r.perfil_id, 'nome', pe.nome, 'papel', r.papel) order by pe.nome)
    from public.turma_responsaveis r join public.perfis pf on pf.id = r.perfil_id join public.pessoas pe on pe.id = pf.pessoa_id where r.turma_id = p_turma and r.ativo), '[]'::jsonb);
end $$;


--
-- Name: cursos_salvar_categoria(uuid, text, text, integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cursos_salvar_categoria(p_id uuid, p_nome text, p_descricao text, p_ordem integer, p_ativo boolean) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_id uuid;
begin
  if not public.cursos_gestor() then raise exception 'Somente a Secretaria ou o MASTER gerenciam cursos.' using errcode = '42501'; end if;
  if p_id is null then
    insert into public.categorias_curso (nome, descricao, ordem, ativo) values (btrim(p_nome), nullif(btrim(p_descricao), ''), coalesce(p_ordem, 0), coalesce(p_ativo, true)) returning id into v_id;
  else
    update public.categorias_curso set nome = btrim(p_nome), descricao = nullif(btrim(p_descricao), ''), ordem = coalesce(p_ordem, ordem), ativo = coalesce(p_ativo, ativo)
     where id = p_id returning id into v_id;
    if v_id is null then raise exception 'Categoria não encontrada.' using errcode = 'P0002'; end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
exception when unique_violation then raise exception 'Já existe uma categoria com esse nome.' using errcode = '23505';
end $$;


--
-- Name: cursos_salvar_curso(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cursos_salvar_curso(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_titulo text := regexp_replace(btrim(coalesce(p->>'titulo', '')), '\s+', ' ', 'g');
        v_slug text; v_exig uuid[];
begin
  if not public.cursos_gestor() then raise exception 'Somente a Secretaria ou o MASTER gerenciam cursos.' using errcode = '42501'; end if;
  if char_length(v_titulo) < 2 then raise exception 'Informe o nome do curso.' using errcode = '22023'; end if;
  v_slug := coalesce(nullif(public.slugify(p->>'slug'), ''), public.slugify(v_titulo));
  select coalesce(array_agg(x::uuid), '{}') into v_exig from jsonb_array_elements_text(coalesce(p->'cursos_exigidos', '[]')) x;
  if v_id is not null and v_id = any(v_exig) then raise exception 'Um curso não pode exigir ele mesmo.' using errcode = '22023'; end if;
  if v_id is null then
    insert into public.cursos (categoria_id, ministerio_id, titulo, slug, resumo, descricao, publico_alvo, imagem_url, carga_horaria, modalidade,
                               plataforma_url, exige_membro, cursos_exigidos, publicado, ordem, criado_por)
    values ((p->>'categoria_id')::uuid, nullif(p->>'ministerio_id', '')::uuid, v_titulo, v_slug, nullif(btrim(p->>'resumo'), ''), nullif(btrim(p->>'descricao'), ''),
            nullif(btrim(p->>'publico_alvo'), ''), nullif(btrim(p->>'imagem_url'), ''), nullif(btrim(p->>'carga_horaria'), ''), coalesce(nullif(p->>'modalidade', ''), 'presencial'),
            nullif(btrim(p->>'plataforma_url'), ''), coalesce((p->>'exige_membro')::boolean, false), v_exig, coalesce((p->>'publicado')::boolean, false),
            coalesce((p->>'ordem')::int, 0), auth.uid())
    returning id into v_id;
  else
    update public.cursos set categoria_id = (p->>'categoria_id')::uuid, ministerio_id = nullif(p->>'ministerio_id', '')::uuid, titulo = v_titulo, slug = v_slug,
           resumo = nullif(btrim(p->>'resumo'), ''), descricao = nullif(btrim(p->>'descricao'), ''), publico_alvo = nullif(btrim(p->>'publico_alvo'), ''),
           imagem_url = nullif(btrim(p->>'imagem_url'), ''), carga_horaria = nullif(btrim(p->>'carga_horaria'), ''),
           modalidade = coalesce(nullif(p->>'modalidade', ''), 'presencial'), plataforma_url = nullif(btrim(p->>'plataforma_url'), ''),
           exige_membro = coalesce((p->>'exige_membro')::boolean, false), cursos_exigidos = v_exig,
           publicado = coalesce((p->>'publicado')::boolean, false), ordem = coalesce((p->>'ordem')::int, ordem)
     where id = v_id;
    if not found then raise exception 'Curso não encontrado.' using errcode = 'P0002'; end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'slug', v_slug);
exception
  when unique_violation then raise exception 'Já existe um curso com esse endereço (%). Mude o nome ou o endereço.', v_slug using errcode = '23505';
  when check_violation then raise exception 'Confira os campos: imagem e plataforma precisam ser endereços válidos (https://).' using errcode = '22023';
end $$;


--
-- Name: cursos_salvar_turma(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cursos_salvar_turma(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_vagas integer := nullif(p->>'vagas', '')::int; v_ocup integer; v_prom integer := 0;
begin
  if not public.cursos_gestor() then raise exception 'Somente a Secretaria ou o MASTER gerenciam cursos.' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p->>'nome', ''))) < 2 then raise exception 'Informe o nome da turma (ex.: Turma 1).' using errcode = '22023'; end if;
  if v_id is not null then
    perform 1 from public.turmas where id = v_id for update;
    v_ocup := (public.cursos_vagas_turma(v_id)->>'ocupadas')::int;
    if v_vagas is not null and v_vagas < v_ocup then
      raise exception 'Esta turma já tem % inscrição(ões) ocupando vaga. O número de vagas não pode ser menor que isso.', v_ocup using errcode = '22023';
    end if;
  end if;
  if v_id is null then
    insert into public.turmas (curso_id, nome, data_inicio, data_fim, dias_horario, local, professores, vagas, lista_espera, valor,
                               inscricao_abre_em, inscricao_fecha_em, status, link_online, lote_reserva, observacoes)
    values ((p->>'curso_id')::uuid, btrim(p->>'nome'), nullif(p->>'data_inicio', '')::date, nullif(p->>'data_fim', '')::date, nullif(btrim(p->>'dias_horario'), ''),
            nullif(btrim(p->>'local'), ''), nullif(btrim(p->>'professores'), ''), v_vagas, coalesce((p->>'lista_espera')::boolean, true), nullif(p->>'valor', '')::numeric,
            nullif(p->>'inscricao_abre_em', '')::timestamptz, nullif(p->>'inscricao_fecha_em', '')::timestamptz, coalesce(nullif(p->>'status', ''), 'rascunho'),
            nullif(btrim(p->>'link_online'), ''), nullif(btrim(p->>'lote_reserva'), ''), nullif(btrim(p->>'observacoes'), ''))
    returning id into v_id;
  else
    update public.turmas set nome = btrim(p->>'nome'), data_inicio = nullif(p->>'data_inicio', '')::date, data_fim = nullif(p->>'data_fim', '')::date,
           dias_horario = nullif(btrim(p->>'dias_horario'), ''), local = nullif(btrim(p->>'local'), ''), professores = nullif(btrim(p->>'professores'), ''),
           vagas = v_vagas, lista_espera = coalesce((p->>'lista_espera')::boolean, true), valor = nullif(p->>'valor', '')::numeric,
           inscricao_abre_em = nullif(p->>'inscricao_abre_em', '')::timestamptz, inscricao_fecha_em = nullif(p->>'inscricao_fecha_em', '')::timestamptz,
           status = coalesce(nullif(p->>'status', ''), status), link_online = nullif(btrim(p->>'link_online'), ''),
           lote_reserva = nullif(btrim(p->>'lote_reserva'), ''), observacoes = nullif(btrim(p->>'observacoes'), '')
     where id = v_id;
    -- mais vagas: chama a lista de espera automaticamente
    v_prom := public.cursos_promover_fila(v_id);
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'promovidos', v_prom);
exception when check_violation then
  raise exception 'Confira as datas (término depois do início; encerramento depois da abertura) e os valores.' using errcode = '22023';
end $$;


--
-- Name: cursos_vagas_turma(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cursos_vagas_turma(p_turma uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select jsonb_build_object(
    'ocupadas', count(*) filter (where i.status in ('confirmada','aguardando_pagamento','concluida')),
    'espera',   count(*) filter (where i.status = 'lista_espera'))
  from public.inscricoes i where i.turma_id = p_turma
$$;


--
-- Name: cursos_validadores_disponiveis(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cursos_validadores_disponiveis() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.cursos_gestor() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', pf.id, 'nome', pe.nome, 'perfil', pf.perfil) order by pe.nome)
    from public.perfis pf join public.pessoas pe on pe.id = pf.pessoa_id where pf.ativo and pf.perfil in ('MASTER','LIDER')), '[]'::jsonb);
end $$;


--
-- Name: e_master(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.e_master() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select public.e_master_uid(auth.uid())
$$;


--
-- Name: e_master_uid(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.e_master_uid(p_uid uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce((select p.ativo and not p.deve_trocar_senha and p.perfil = 'MASTER'
                   from public.perfis p where p.id = p_uid), false)
$$;


--
-- Name: e_secretaria(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.e_secretaria() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$ select public.e_master() or public.tem_atribuicao('SECRETARIA') $$;


--
-- Name: e_tesouraria(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.e_tesouraria() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$ select public.tem_atribuicao('TESOURARIA') $$;


--
-- Name: escala_adicionar(uuid, uuid, jsonb, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_adicionar(p_evento_funcao uuid, p_pessoa uuid, p jsonb, p_ciente boolean) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare ef public.escala_evento_funcoes; e public.escala_eventos; fu public.escala_funcoes; v_ini timestamptz; v_fim timestamptz; al jsonb; v uuid; v_sub uuid := nullif(p->>'substitui_id', '')::uuid;
begin
  select * into ef from public.escala_evento_funcoes where id = p_evento_funcao;
  if not found or ef.removida_em is not null then raise exception 'Função não encontrada neste evento.' using errcode = 'P0002'; end if;
  select * into e from public.escala_eventos where id = ef.escala_evento_id for update;
  select * into fu from public.escala_funcoes where id = ef.funcao_id;
  if not public.escala_gestor(e.ministerio_id, fu.area_id) then raise exception 'Sem permissão para esta equipe.' using errcode = '42501'; end if;
  if e.status in ('concluida','cancelada') then raise exception 'Escala encerrada.' using errcode = '22023'; end if;
  -- bloqueios primeiro (sempre recusados); alertas depois (o líder decide)
  if exists (select 1 from public.escala_participacoes where evento_funcao_id = ef.id and pessoa_id = p_pessoa and status in ('rascunho','aguardando','confirmado','substituicao_necessaria')) then
    raise exception 'Esta pessoa já está nesta função do evento.' using errcode = '23505'; end if;
  perform public.escala_validar_bloqueios(ef.id, p_pessoa, coalesce(nullif(p->>'papel', ''), 'auxiliar'));
  v_ini := coalesce(nullif(p->>'inicio', '')::timestamptz, ef.hora_inicio, e.inicio); v_fim := coalesce(nullif(p->>'fim', '')::timestamptz, ef.hora_fim, e.fim);
  al := public.escala_alertas(p_pessoa, v_ini, v_fim, fu.id, null);
  if jsonb_array_length(al) > 0 and not coalesce(p_ciente, false) then
    return jsonb_build_object('ok', false, 'precisa_ciencia', true, 'alertas', al);
  end if;
  if v_sub is not null then perform set_config('app.escala_acao', 'substituto_escalado', true); end if;
  insert into public.escala_participacoes (escala_evento_id, evento_funcao_id, pessoa_id, papel, atividade, inicio, fim, orientacoes_individuais, observacao_lider,
         status, solicitado_em, prazo, substitui_id, alertas_cientes, criado_por)
  values (e.id, ef.id, p_pessoa, coalesce(nullif(p->>'papel', ''), 'auxiliar'), nullif(btrim(p->>'atividade'), ''), nullif(p->>'inicio', '')::timestamptz, nullif(p->>'fim', '')::timestamptz,
          nullif(btrim(p->>'orientacoes_individuais'), ''), nullif(btrim(p->>'observacao_lider'), ''),
          case when e.status = 'publicada' then 'aguardando' else 'rascunho' end, case when e.status = 'publicada' then now() end,
          case when e.status = 'publicada' then public.escala_prazo(e) end, v_sub, case when jsonb_array_length(al) > 0 then al end, auth.uid())
  returning id into v;
  perform set_config('app.escala_acao', '', true);
  if e.status = 'publicada' then perform public.escala_avisar(v, 'escala_nova', 'nova:' || v || ':1'); end if;
  return jsonb_build_object('ok', true, 'id', v, 'alertas', al);
exception when unique_violation then raise exception 'Esta pessoa já está nesta função do evento.' using errcode = '23505';
end $$;


--
-- Name: escala_alertas(uuid, timestamp with time zone, timestamp with time zone, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_alertas(p_pessoa uuid, p_inicio timestamp with time zone, p_fim timestamp with time zone, p_funcao uuid, p_ignorar uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v jsonb := '[]'::jsonb; r record; li timestamp := p_inicio at time zone 'America/Sao_Paulo'; lf timestamp := p_fim at time zone 'America/Sao_Paulo';
begin
  for r in select e.titulo, coalesce(p.inicio, ef.hora_inicio, e.inicio) i, coalesce(p.fim, ef.hora_fim, e.fim) f
             from public.escala_participacoes p join public.escala_eventos e on e.id = p.escala_evento_id join public.escala_evento_funcoes ef on ef.id = p.evento_funcao_id
            where p.pessoa_id = p_pessoa and p.status in ('rascunho','aguardando','confirmado') and e.status in ('planejamento','publicada')
              and p.id is distinct from p_ignorar and tstzrange(coalesce(p.inicio, ef.hora_inicio, e.inicio), coalesce(p.fim, ef.hora_fim, e.fim)) && tstzrange(p_inicio, p_fim) loop
    v := v || jsonb_build_object('tipo', 'conflito', 'texto', 'Já escalado(a) em "' || r.titulo || '" no mesmo período');
  end loop;
  for r in select * from public.voluntario_indisponibilidades i where i.pessoa_id = p_pessoa and daterange(i.inicio, i.fim, '[]') && daterange(li::date, lf::date, '[]') loop
    v := v || jsonb_build_object('tipo', 'indisponivel', 'texto', 'Marcou indisponibilidade (' || r.tipo || ') de ' || to_char(r.inicio, 'DD/MM') || ' a ' || to_char(r.fim, 'DD/MM'));
  end loop;
  if exists (select 1 from public.voluntario_disponibilidade d where d.pessoa_id = p_pessoa)
     and not exists (select 1 from public.voluntario_disponibilidade d where d.pessoa_id = p_pessoa and d.dia_semana = extract(dow from li)
                       and d.hora_inicio <= li::time and (d.hora_fim >= lf::time or lf::date > li::date)) then
    v := v || jsonb_build_object('tipo', 'fora_disponibilidade', 'texto', 'Fora dos dias e horários que informou');
  end if;
  if exists (select 1 from public.voluntario_habilitacoes h where h.pessoa_id = p_pessoa and h.funcao_id = p_funcao and h.status = 'em_treinamento') then
    v := v || jsonb_build_object('tipo', 'em_treinamento', 'texto', 'Em treinamento nesta função');
  end if;
  return v;
end $$;


--
-- Name: escala_alterar(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_alterar(p_escala uuid, p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare e public.escala_eventos;
begin
  select * into e from public.escala_eventos where id = p_escala;
  if not found then raise exception 'Escala não encontrada.' using errcode = 'P0002'; end if;
  if not public.escala_gestor(e.ministerio_id) then raise exception 'Sem permissão.' using errcode = '42501'; end if;
  if e.status in ('concluida','cancelada') then raise exception 'Escala encerrada.' using errcode = '22023'; end if;
  if e.evento_id is not null and (p ? 'inicio' or p ? 'fim') and (select inicio from public.agenda_evento_periodo(e.evento_id)) is not null
     and (nullif(p->>'inicio', '')::timestamptz is distinct from e.inicio or nullif(p->>'fim', '')::timestamptz is distinct from e.fim) then
    raise exception 'Este evento vem da Agenda: mude a data e o horário na Agenda (a escala acompanha).' using errcode = '22023'; end if;
  return public.escala_aplicar_mudanca(p_escala, p, 'lider');
end $$;


--
-- Name: escala_alterar_participacao(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_alterar_participacao(p_part uuid, p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare q public.escala_participacoes; e public.escala_eventos; a uuid; relevante boolean; novo_ef uuid := coalesce(nullif(p->>'evento_funcao_id', '')::uuid, null); v_ef uuid;
begin
  select * into q from public.escala_participacoes where id = p_part for update;
  if not found then raise exception 'Participação não encontrada.' using errcode = 'P0002'; end if;
  select * into e from public.escala_eventos where id = q.escala_evento_id;
  select f.area_id into a from public.escala_evento_funcoes ef join public.escala_funcoes f on f.id = ef.funcao_id where ef.id = q.evento_funcao_id;
  if not public.escala_gestor(e.ministerio_id, a) then raise exception 'Sem permissão para esta equipe.' using errcode = '42501'; end if;
  if q.status not in ('rascunho','aguardando','confirmado') then raise exception 'Esta participação não pode ser alterada.' using errcode = '22023'; end if;
  v_ef := coalesce(novo_ef, q.evento_funcao_id);
  relevante := v_ef <> q.evento_funcao_id
    or (p ? 'inicio' and nullif(p->>'inicio', '')::timestamptz is distinct from q.inicio) or (p ? 'fim' and nullif(p->>'fim', '')::timestamptz is distinct from q.fim)
    or (p ? 'atividade' and nullif(btrim(p->>'atividade'), '') is distinct from q.atividade) or (p ? 'papel' and p->>'papel' is distinct from q.papel)
    or coalesce((p->>'exigir_confirmacao')::boolean, false);
  update public.escala_participacoes set evento_funcao_id = v_ef, papel = coalesce(nullif(p->>'papel', ''), papel),
         atividade = case when p ? 'atividade' then nullif(btrim(p->>'atividade'), '') else atividade end,
         inicio = case when p ? 'inicio' then nullif(p->>'inicio', '')::timestamptz else inicio end,
         fim = case when p ? 'fim' then nullif(p->>'fim', '')::timestamptz else fim end,
         orientacoes_individuais = case when p ? 'orientacoes_individuais' then nullif(btrim(p->>'orientacoes_individuais'), '') else orientacoes_individuais end,
         observacao_lider = case when p ? 'observacao_lider' then nullif(btrim(p->>'observacao_lider'), '') else observacao_lider end where id = q.id;
  if q.status in ('aguardando','confirmado') then
    if relevante then perform public.escala_pedir_reconfirmacao(q.id, 'Participação alterada');
    elsif p ? 'orientacoes_individuais' and nullif(btrim(p->>'orientacoes_individuais'), '') is distinct from q.orientacoes_individuais then
      perform public.escala_avisar(q.id, 'escala_orientacoes', 'orienti:' || q.id || ':' || md5(coalesce(p->>'orientacoes_individuais', '')));
    end if;
  end if;
  return jsonb_build_object('ok', true, 'nova_confirmacao', relevante and q.status in ('aguardando','confirmado'));
exception when unique_violation then raise exception 'Esta pessoa já está nessa função do evento.' using errcode = '23505';
end $$;


--
-- Name: escala_aplicar_mudanca(uuid, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_aplicar_mudanca(p_escala uuid, p jsonb, p_origem text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare e public.escala_eventos; v_ini timestamptz; v_fim timestamptz; v_loc text; relevante boolean; orient boolean; q uuid; n int := 0;
begin
  select * into e from public.escala_eventos where id = p_escala for update;
  v_ini := coalesce(nullif(p->>'inicio', '')::timestamptz, e.inicio); v_fim := coalesce(nullif(p->>'fim', '')::timestamptz, e.fim);
  v_loc := coalesce(nullif(btrim(p->>'local'), ''), e.local);
  relevante := v_ini is distinct from e.inicio or v_fim is distinct from e.fim or v_loc is distinct from e.local or coalesce((p->>'exigir_confirmacao')::boolean, false);
  orient := p ? 'orientacoes_gerais' and nullif(btrim(p->>'orientacoes_gerais'), '') is distinct from e.orientacoes_gerais;
  perform set_config('app.escala_acao', case when p_origem = 'agenda' then 'alterada_pela_agenda' else 'escala_alterada' end, true);
  update public.escala_eventos set inicio = v_ini, fim = v_fim, local = v_loc, titulo = coalesce(nullif(btrim(p->>'titulo'), ''), titulo),
         prazo_confirmacao = case when p ? 'prazo_confirmacao' then nullif(p->>'prazo_confirmacao', '')::timestamptz else prazo_confirmacao end,
         orientacoes_gerais = case when p ? 'orientacoes_gerais' then nullif(btrim(p->>'orientacoes_gerais'), '') else orientacoes_gerais end,
         versao = versao + case when relevante then 1 else 0 end, versao_orientacoes = versao_orientacoes + case when orient then 1 else 0 end where id = e.id;
  perform set_config('app.escala_acao', '', true);
  if e.status = 'publicada' then
    for q in select id from public.escala_participacoes where escala_evento_id = e.id and status in ('aguardando','confirmado') loop
      if relevante then perform public.escala_pedir_reconfirmacao(q, 'Data, horário ou local mudaram'); n := n + 1;
      elsif orient then perform public.escala_avisar(q, 'escala_orientacoes', 'orientg:' || q || ':' || (e.versao_orientacoes + 1)); end if;
    end loop;
  end if;
  return jsonb_build_object('ok', true, 'nova_confirmacao', n, 'relevante', relevante);
end $$;


--
-- Name: escala_avisar(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_avisar(p_part uuid, p_tipo text, p_chave text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare p public.escala_participacoes; e public.escala_eventos; fu text; mn text; resp text; u uuid; per record; v_tit text; v_msg text;
begin
  select * into p from public.escala_participacoes where id = p_part;
  select * into e from public.escala_eventos where id = p.escala_evento_id;
  select f.nome into fu from public.escala_evento_funcoes ef join public.escala_funcoes f on f.id = ef.funcao_id where ef.id = p.evento_funcao_id;
  select nome into mn from public.ministerios where id = e.ministerio_id;
  select x.nome into resp from public.perfis pf join public.pessoas x on x.id = pf.pessoa_id where pf.id = coalesce(p.criado_por, e.criado_por);
  select pf.id into u from public.perfis pf where pf.pessoa_id = p.pessoa_id and pf.ativo;
  if u is null then return; end if;
  select * into per from public.participacao_periodo(p);
  v_tit := case p_tipo when 'escala_nova' then 'Você foi escalado(a)' when 'escala_reconfirmar' then 'Sua escala mudou: confirme de novo'
             when 'escala_orientacoes' then 'Orientações atualizadas' when 'escala_cancelada' then 'Escala cancelada'
             when 'escala_lembrete' then 'Falta confirmar a sua escala' when 'escala_atrasada' then 'O prazo para confirmar venceu'
             when 'escala_substituicao' then 'Você será substituído(a) nesta escala' else 'Escala' end;
  v_msg := e.titulo || ' · ' || to_char(per.inicio at time zone 'America/Sao_Paulo', 'DD/MM/YYYY "às" HH24:MI') || ' a ' || to_char(per.fim at time zone 'America/Sao_Paulo', 'HH24:MI')
        || ' · ' || e.local || ' · ' || coalesce(mn, '') || ' · função: ' || fu || case when p.papel = 'principal' then ' (responsável principal)' else '' end
        || coalesce(' · ' || p.atividade, '') || coalesce(' · orientações: ' || p.orientacoes_individuais, '')
        || coalesce(' · escala de ' || resp, '') || case when p.status = 'aguardando' and p.prazo is not null then ' · responda até ' || to_char(p.prazo at time zone 'America/Sao_Paulo', 'DD/MM "às" HH24:MI') else '' end;
  perform public.notificar_unico(p_chave, u, p_tipo, v_tit, v_msg, jsonb_build_object('participacao', p.id, 'escala', e.id));
end $$;


--
-- Name: escala_cancelar_interno(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_cancelar_interno(p_escala uuid, p_motivo text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare q record;
begin
  update public.escala_eventos set status = 'cancelada', motivo_cancelamento = p_motivo where id = p_escala and status in ('planejamento','publicada');
  for q in select id, status from public.escala_participacoes where escala_evento_id = p_escala and status in ('rascunho','aguardando','confirmado','substituicao_necessaria') loop
    update public.escala_participacoes set status = 'cancelado', vaga_aberta = false, motivo_cancelamento = p_motivo where id = q.id;
    if q.status <> 'rascunho' then perform public.escala_avisar(q.id, 'escala_cancelada', 'canc:' || q.id); end if;
  end loop;
end $$;


--
-- Name: escala_encerrar(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_encerrar(p_escala uuid, p_acao text, p_motivo text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare e public.escala_eventos; q uuid; n int := 0;
begin
  select * into e from public.escala_eventos where id = p_escala for update;
  if not found then raise exception 'Escala não encontrada.' using errcode = 'P0002'; end if;
  if not public.escala_gestor(e.ministerio_id) then raise exception 'Sem permissão.' using errcode = '42501'; end if;
  if e.status in ('concluida','cancelada') then raise exception 'Escala já encerrada.' using errcode = '22023'; end if;
  if p_acao = 'cancelar' then
    if char_length(btrim(coalesce(p_motivo, ''))) < 3 then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
    perform public.escala_cancelar_interno(e.id, btrim(p_motivo));
  elsif p_acao = 'concluir' then
    if e.fim > now() then raise exception 'O evento ainda não terminou.' using errcode = '22023'; end if;
    update public.escala_eventos set status = 'concluida' where id = e.id;
  else raise exception 'Ação inválida.' using errcode = '22023';
  end if;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: escala_funcao(uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_funcao(p_escala uuid, p_acao text, p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare e public.escala_eventos; ef public.escala_evento_funcoes; v uuid; a uuid; mudou_hora boolean; q record;
begin
  select * into e from public.escala_eventos where id = p_escala for update;
  if not found then raise exception 'Escala não encontrada.' using errcode = 'P0002'; end if;
  select f.area_id into a from public.escala_funcoes f where f.id = coalesce(nullif(p->>'funcao_id', '')::uuid, (select funcao_id from public.escala_evento_funcoes where id = nullif(p->>'id', '')::uuid));
  if not public.escala_gestor(e.ministerio_id, a) then raise exception 'Sem permissão para esta equipe.' using errcode = '42501'; end if;
  if e.status in ('concluida','cancelada') then raise exception 'Escala encerrada.' using errcode = '22023'; end if;
  if p_acao = 'incluir' then
    v := public.escala_incluir_funcao_interno(e.id, (p->>'funcao_id')::uuid, nullif(p->>'quantidade_referencia', '')::int, p->>'orientacoes',
                                              nullif(p->>'hora_inicio', '')::timestamptz, nullif(p->>'hora_fim', '')::timestamptz);
    return jsonb_build_object('ok', true, 'id', v);
  end if;
  select * into ef from public.escala_evento_funcoes where id = (p->>'id')::uuid and escala_evento_id = e.id for update;
  if not found then raise exception 'Função não está nesta escala.' using errcode = 'P0002'; end if;
  if p_acao = 'remover' then
    if exists (select 1 from public.escala_participacoes where evento_funcao_id = ef.id and status in ('rascunho','aguardando','confirmado','substituicao_necessaria')) then
      raise exception 'Há voluntários nesta função: cancele as participações antes de retirá-la.' using errcode = '22023'; end if;
    update public.escala_evento_funcoes set removida_em = now() where id = ef.id;
  elsif p_acao = 'alterar' then
    mudou_hora := (nullif(p->>'hora_inicio', '')::timestamptz is distinct from ef.hora_inicio) or (nullif(p->>'hora_fim', '')::timestamptz is distinct from ef.hora_fim);
    update public.escala_evento_funcoes set quantidade_referencia = nullif(p->>'quantidade_referencia', '')::int, orientacoes = nullif(btrim(p->>'orientacoes'), ''),
           hora_inicio = nullif(p->>'hora_inicio', '')::timestamptz, hora_fim = nullif(p->>'hora_fim', '')::timestamptz where id = ef.id;
    if e.status = 'publicada' then
      for q in select * from public.escala_participacoes where evento_funcao_id = ef.id and status in ('aguardando','confirmado') loop
        if mudou_hora and q.inicio is null or coalesce((p->>'exigir_confirmacao')::boolean, false) then
          perform public.escala_pedir_reconfirmacao(q.id, 'Horário ou orientações da função mudaram');
        elsif (p->>'orientacoes') is distinct from ef.orientacoes then
          perform public.escala_avisar(q.id, 'escala_orientacoes', 'orient:' || q.id || ':' || md5(coalesce(p->>'orientacoes', '')));
        end if;
      end loop;
    end if;
  else raise exception 'Ação inválida.' using errcode = '22023';
  end if;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: escala_gestor(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_gestor(p_ministerio uuid, p_area uuid DEFAULT NULL::uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select public.escala_lider(p_ministerio) or (public.perfil_ativo() and exists (
    select 1 from public.escala_gestores g where g.ministerio_id = p_ministerio and g.perfil_id = auth.uid() and g.ativo
      and (g.areas = '{}' or p_area is null or p_area = any(g.areas))))
$$;


--
-- Name: escala_historico_listar(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_historico_listar(p_escala uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare e public.escala_eventos;
begin
  select * into e from public.escala_eventos where id = p_escala;
  if not found or not public.escala_gestor(e.ministerio_id) then raise exception 'Acesso restrito à liderança.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('acao', h.acao, 'em', h.em,
      'pessoa', (select x.nome from public.escala_participacoes p join public.pessoas x on x.id = p.pessoa_id where p.id = h.participacao_id),
      'antes', case when h.participacao_id is null then jsonb_build_object('inicio', h.antes->'inicio', 'fim', h.antes->'fim', 'local', h.antes->'local', 'status', h.antes->'status') else jsonb_build_object('status', h.antes->'status', 'versao', h.antes->'versao') end,
      'depois', case when h.participacao_id is null then jsonb_build_object('inicio', h.depois->'inicio', 'fim', h.depois->'fim', 'local', h.depois->'local', 'status', h.depois->'status') else jsonb_build_object('status', h.depois->'status', 'versao', h.depois->'versao') end,
      'ator', (select x.nome from public.perfis pf join public.pessoas x on x.id = pf.pessoa_id where pf.id = h.ator)) order by h.em, h.id)
    from public.escala_historico h where h.escala_evento_id = p_escala), '[]'::jsonb);
end $$;


--
-- Name: escala_incluir_funcao_interno(uuid, uuid, integer, text, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_incluir_funcao_interno(p_escala uuid, p_funcao uuid, p_qtd integer, p_orient text, p_ini timestamp with time zone, p_fim timestamp with time zone) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare fu public.escala_funcoes; e public.escala_eventos; v uuid;
begin
  select * into e from public.escala_eventos where id = p_escala;
  select f.* into fu from public.escala_funcoes f join public.escala_areas a on a.id = f.area_id where f.id = p_funcao and a.ministerio_id = e.ministerio_id and f.ativo;
  if fu.id is null then raise exception 'Função inválida.' using errcode = '22023'; end if;
  insert into public.escala_evento_funcoes (escala_evento_id, funcao_id, quantidade_referencia, orientacoes, hora_inicio, hora_fim)
  values (p_escala, p_funcao, coalesce(p_qtd, fu.quantidade_referencia), coalesce(nullif(btrim(p_orient), ''), fu.orientacao_padrao), p_ini, p_fim)
  on conflict (escala_evento_id, funcao_id) do update set removida_em = null returning id into v;
  return v;
end $$;


--
-- Name: escala_lider(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_lider(p_ministerio uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select public.perfil_ativo() and (public.e_master() or public.lider_de(p_ministerio))
$$;


--
-- Name: escala_participacao_acao(uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_participacao_acao(p_part uuid, p_acao text, p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare q public.escala_participacoes; e public.escala_eventos; a uuid; r jsonb; v_motivo text := nullif(btrim(p->>'motivo'), '');
begin
  select * into q from public.escala_participacoes where id = p_part for update;
  if not found then raise exception 'Participação não encontrada.' using errcode = 'P0002'; end if;
  select * into e from public.escala_eventos where id = q.escala_evento_id;
  select f.area_id into a from public.escala_evento_funcoes ef join public.escala_funcoes f on f.id = ef.funcao_id where ef.id = q.evento_funcao_id;
  if not public.escala_gestor(e.ministerio_id, a) then raise exception 'Sem permissão para esta equipe.' using errcode = '42501'; end if;
  if p_acao = 'substituir' then
    if q.status not in ('recusado','aguardando','substituicao_necessaria','confirmado') then raise exception 'Não há o que substituir nesta participação.' using errcode = '22023'; end if;
    r := public.escala_adicionar(q.evento_funcao_id, (p->>'pessoa_id')::uuid,
           jsonb_build_object('papel', q.papel, 'atividade', q.atividade, 'inicio', q.inicio, 'fim', q.fim, 'orientacoes_individuais', q.orientacoes_individuais, 'substitui_id', q.id),
           coalesce((p->>'ciente')::boolean, false));
    if not (r->>'ok')::boolean then return r; end if;
    update public.escala_participacoes set status = 'substituido', vaga_aberta = false where id = q.id;
    if q.status in ('aguardando','confirmado','substituicao_necessaria') then perform public.escala_avisar(q.id, 'escala_cancelada', 'subst:' || q.id); end if;
    return r;
  elsif p_acao = 'marcar_substituicao' then
    if q.status not in ('aguardando','confirmado') then raise exception 'Só confirmados ou aguardando podem ser marcados para substituição.' using errcode = '22023'; end if;
    if char_length(coalesce(v_motivo, '')) < 3 then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
    update public.escala_participacoes set status = 'substituicao_necessaria', vaga_aberta = true, motivo_cancelamento = v_motivo where id = q.id;
    perform public.escala_avisar(q.id, 'escala_substituicao', 'marcasub:' || q.id);
  elsif p_acao = 'dispensar_vaga' then
    if not q.vaga_aberta then raise exception 'Não há vaga aberta aqui.' using errcode = '22023'; end if;
    update public.escala_participacoes set vaga_aberta = false, status = case when status = 'substituicao_necessaria' then 'cancelado' else status end,
           motivo_cancelamento = coalesce(v_motivo, motivo_cancelamento) where id = q.id;
  elsif p_acao = 'cancelar' then
    if q.status not in ('rascunho','aguardando','confirmado','substituicao_necessaria') then raise exception 'Esta participação já está encerrada.' using errcode = '22023'; end if;
    if char_length(coalesce(v_motivo, '')) < 3 then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
    update public.escala_participacoes set status = 'cancelado', vaga_aberta = false, motivo_cancelamento = v_motivo where id = q.id;
    if q.status <> 'rascunho' then perform public.escala_avisar(q.id, 'escala_cancelada', 'canc:' || q.id); end if;
  elsif p_acao = 'presenca' then
    if now() < e.inicio then raise exception 'A presença só é registrada depois do início do evento.' using errcode = '22023'; end if;
    if q.status in ('rascunho','substituido','cancelado') then raise exception 'Esta pessoa não estava escalada.' using errcode = '22023'; end if;
    if coalesce(p->>'presenca', '') not in ('presente','ausente','parcial') then raise exception 'Informe presente, ausente ou parcial.' using errcode = '22023'; end if;
    update public.escala_participacoes set presenca = p->>'presenca', presenca_obs = nullif(btrim(p->>'obs'), ''), presenca_por = auth.uid(), presenca_em = now() where id = q.id;
  else raise exception 'Ação inválida.' using errcode = '22023';
  end if;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: escala_pedir_reconfirmacao(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_pedir_reconfirmacao(p_part uuid, p_motivo text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare p public.escala_participacoes; e public.escala_eventos;
begin
  select * into p from public.escala_participacoes where id = p_part for update;
  select * into e from public.escala_eventos where id = p.escala_evento_id;
  perform set_config('app.escala_acao', 'nova_confirmacao_pedida', true);
  update public.escala_participacoes set status = 'aguardando', versao = versao + 1, respondido_em = null, solicitado_em = now(),
         prazo = public.escala_prazo(e), observacao_lider = coalesce(observacao_lider, null) where id = p.id;
  perform set_config('app.escala_acao', '', true);
  perform public.escala_avisar(p.id, 'escala_reconfirmar', 'reconf:' || p.id || ':' || (p.versao + 1));
end $$;


--
-- Name: escala_eventos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.escala_eventos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ministerio_id uuid NOT NULL,
    solicitacao_id uuid,
    evento_id bigint,
    titulo text NOT NULL,
    inicio timestamp with time zone NOT NULL,
    fim timestamp with time zone NOT NULL,
    local text NOT NULL,
    status text DEFAULT 'planejamento'::text NOT NULL,
    prazo_confirmacao timestamp with time zone,
    orientacoes_gerais text,
    versao integer DEFAULT 1 NOT NULL,
    versao_orientacoes integer DEFAULT 1 NOT NULL,
    motivo_cancelamento text,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT escala_eventos_check CHECK ((fim > inicio)),
    CONSTRAINT escala_eventos_local_check CHECK (((char_length(btrim(local)) >= 2) AND (char_length(btrim(local)) <= 200))),
    CONSTRAINT escala_eventos_motivo_cancelamento_check CHECK ((char_length(motivo_cancelamento) <= 600)),
    CONSTRAINT escala_eventos_orientacoes_gerais_check CHECK ((char_length(orientacoes_gerais) <= 2000)),
    CONSTRAINT escala_eventos_status_check CHECK ((status = ANY (ARRAY['planejamento'::text, 'publicada'::text, 'concluida'::text, 'cancelada'::text]))),
    CONSTRAINT escala_eventos_titulo_check CHECK (((char_length(btrim(titulo)) >= 3) AND (char_length(btrim(titulo)) <= 140)))
);


--
-- Name: escala_prazo(public.escala_eventos); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_prazo(e public.escala_eventos) RETURNS timestamp with time zone
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select least(e.inicio, greatest(coalesce(e.prazo_confirmacao, e.inicio - interval '48 hours'), now() + interval '12 hours'))
$$;


--
-- Name: escala_publicar(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_publicar(p_escala uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare e public.escala_eventos; q uuid; n int := 0;
begin
  select * into e from public.escala_eventos where id = p_escala for update;
  if not found then raise exception 'Escala não encontrada.' using errcode = 'P0002'; end if;
  if not public.escala_gestor(e.ministerio_id) then raise exception 'Sem permissão.' using errcode = '42501'; end if;
  if e.status <> 'planejamento' then raise exception 'A escala já foi publicada ou está encerrada.' using errcode = '22023'; end if;
  if e.fim < now() then raise exception 'O evento já passou.' using errcode = '22023'; end if;
  update public.escala_eventos set status = 'publicada' where id = e.id;
  select * into e from public.escala_eventos where id = p_escala;
  for q in select id from public.escala_participacoes where escala_evento_id = e.id and status = 'rascunho' loop
    update public.escala_participacoes set status = 'aguardando', solicitado_em = now(), prazo = public.escala_prazo(e) where id = q;
    perform public.escala_avisar(q, 'escala_nova', 'nova:' || q || ':1'); n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'avisados', n);
end $$;


--
-- Name: escala_responder(uuid, text, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_responder(p_participacao uuid, p_resposta text, p_versao integer, p_motivo text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare p public.escala_participacoes; e public.escala_eventos; fu text; nm text; a uuid;
begin
  select * into p from public.escala_participacoes where id = p_participacao for update;
  if not found or p.pessoa_id is distinct from public.minha_pessoa_id() or not public.perfil_ativo() then
    raise exception 'Escala não encontrada.' using errcode = '42501'; end if;
  select * into e from public.escala_eventos where id = p.escala_evento_id;
  if e.status <> 'publicada' then raise exception 'Esta escala não está aberta para resposta.' using errcode = '22023'; end if;
  if p_versao is distinct from p.versao then raise exception 'A escala mudou desde que você abriu. Atualize a página e responda de novo.' using errcode = '22023'; end if;
  if e.fim < now() then raise exception 'O evento já terminou.' using errcode = '22023'; end if;
  select f.nome, f.area_id into fu, a from public.escala_evento_funcoes ef join public.escala_funcoes f on f.id = ef.funcao_id where ef.id = p.evento_funcao_id;
  select nome into nm from public.pessoas where id = p.pessoa_id;
  if p_resposta = 'confirmar' then
    if p.status <> 'aguardando' then raise exception 'Não há confirmação pendente nesta escala.' using errcode = '22023'; end if;
    perform set_config('app.escala_acao', 'confirmou', true);
    update public.escala_participacoes set status = 'confirmado', versao_respondida = p.versao, respondido_em = now(), motivo_recusa = null where id = p.id;
    perform public.notificar_gestao(e.ministerio_id, 'resp:' || p.id || ':' || p.versao, 'escala_confirmada', 'Presença confirmada', nm || ' confirmou ' || fu || ' em ' || e.titulo || '.', jsonb_build_object('escala', e.id), a);
  elsif p_resposta = 'recusar' then
    if p.status not in ('aguardando','confirmado') then raise exception 'Esta escala não pode ser recusada agora.' using errcode = '22023'; end if;
    perform set_config('app.escala_acao', 'recusou', true);
    update public.escala_participacoes set status = 'recusado', vaga_aberta = true, versao_respondida = p.versao, respondido_em = now(), motivo_recusa = nullif(btrim(p_motivo), '') where id = p.id;
    perform public.notificar_gestao(e.ministerio_id, 'resp:' || p.id || ':' || p.versao || ':recusa', 'escala_recusada', 'Substituição necessária',
            nm || ' não poderá participar (' || fu || ') em ' || e.titulo || coalesce(': ' || nullif(btrim(p_motivo), ''), '') || '.', jsonb_build_object('escala', e.id), a);
  else raise exception 'Resposta inválida.' using errcode = '22023';
  end if;
  perform set_config('app.escala_acao', '', true);
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: escala_sugerir(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_sugerir(p_evento_funcao uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare ef public.escala_evento_funcoes; e public.escala_eventos; fu public.escala_funcoes; v_ini timestamptz; v_fim timestamptz;
begin
  select * into ef from public.escala_evento_funcoes where id = p_evento_funcao;
  select * into e from public.escala_eventos where id = ef.escala_evento_id;
  select * into fu from public.escala_funcoes where id = ef.funcao_id;
  if not public.escala_gestor(e.ministerio_id, fu.area_id) then raise exception 'Sem permissão.' using errcode = '42501'; end if;
  v_ini := coalesce(ef.hora_inicio, e.inicio); v_fim := coalesce(ef.hora_fim, e.fim);
  return coalesce((select jsonb_agg(x order by (x->>'ordem')::numeric, x->>'nome') from (
    select jsonb_build_object('pessoa_id', pe.id, 'nome', pe.nome, 'habilitacao', coalesce(h.status, 'nao_exige'),
      'alertas', al, 'preferida', coalesce(fu.id = any(vp.funcoes), false), 'escalas_60_dias', n60, 'ultima', ult, 'tem_conta', conta,
      'ordem', (case when jsonb_array_length(al) = 0 then 0 else 1000 end) + (case when coalesce(fu.id = any(vp.funcoes), false) then 0 else 100 end) + n60 * 10
               - least(coalesce(extract(day from now() - ult), 365), 365) / 100.0) as x
    from public.ministerio_membros mm join public.pessoas pe on pe.id = mm.pessoa_id
    join lateral (select exists (select 1 from public.perfis pf where pf.pessoa_id = pe.id and pf.ativo) conta) c1 on true
    left join public.voluntario_habilitacoes h on h.pessoa_id = pe.id and h.funcao_id = fu.id
    left join public.voluntario_preferencias vp on vp.pessoa_id = pe.id
    join lateral (select public.escala_alertas(pe.id, v_ini, v_fim, fu.id, null) al) c2 on true
    join lateral (select count(*) n60 from public.escala_participacoes p join public.escala_eventos x2 on x2.id = p.escala_evento_id
                   where p.pessoa_id = pe.id and p.status in ('aguardando','confirmado') and x2.inicio > now() - interval '60 days' and x2.status <> 'cancelada') c3 on true
    join lateral (select max(x3.inicio) ult from public.escala_participacoes p join public.escala_eventos x3 on x3.id = p.escala_evento_id
                   where p.pessoa_id = pe.id and p.status = 'confirmado' and x3.inicio < now()) c4 on true
    where mm.ministerio_id = e.ministerio_id and mm.ativo and pe.arquivado_em is null and conta
      and (not fu.exige_habilitacao or h.status = 'habilitado' or (h.status = 'em_treinamento' and fu.aceita_em_treinamento))
      and not exists (select 1 from public.escala_participacoes p where p.evento_funcao_id = ef.id and p.pessoa_id = pe.id and p.status in ('rascunho','aguardando','confirmado','substituicao_necessaria'))
  ) s), '[]'::jsonb);
end $$;


--
-- Name: escala_validar_bloqueios(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escala_validar_bloqueios(p_evento_funcao uuid, p_pessoa uuid, p_papel text) RETURNS void
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare ef public.escala_evento_funcoes; fu public.escala_funcoes; v_min uuid; hb public.voluntario_habilitacoes;
begin
  select * into ef from public.escala_evento_funcoes where id = p_evento_funcao;
  if ef.removida_em is not null then raise exception 'Esta função foi retirada do evento.' using errcode = '22023'; end if;
  select * into fu from public.escala_funcoes where id = ef.funcao_id;
  select a.ministerio_id into v_min from public.escala_areas a where a.id = fu.area_id;
  if not exists (select 1 from public.ministerio_membros mm where mm.pessoa_id = p_pessoa and mm.ministerio_id = v_min and mm.ativo) then
    raise exception 'Só podem ser escalados voluntários ativos do ministério.' using errcode = '23514'; end if;
  if not exists (select 1 from public.perfis pf where pf.pessoa_id = p_pessoa and pf.ativo) then
    raise exception 'Esta pessoa ainda não tem conta ativa: sem conta não há como confirmar a escala. Peça o acesso ao MASTER.' using errcode = '23514'; end if;
  if fu.exige_habilitacao then
    select * into hb from public.voluntario_habilitacoes where pessoa_id = p_pessoa and funcao_id = fu.id;
    if hb.id is null or hb.status = 'suspenso' then
      raise exception 'Sem habilitação ativa para a função "%".', fu.nome using errcode = '23514'; end if;
    if hb.status = 'em_treinamento' and (coalesce(p_papel, 'auxiliar') <> 'auxiliar' or not fu.aceita_em_treinamento) then
      raise exception 'Em treinamento na função "%": só pode ser escalado(a) como auxiliar, se a função permitir.', fu.nome using errcode = '23514'; end if;
  end if;
end $$;


--
-- Name: escalas_processar_prazos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.escalas_processar_prazos() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare q record; n_lem int := 0; n_atr int := 0; nm text; ev public.escala_eventos;
begin
  for q in select p.* from public.escala_participacoes p join public.escala_eventos e on e.id = p.escala_evento_id
            where e.status = 'publicada' and p.status = 'aguardando' and p.prazo is not null and e.fim > now() loop
    if q.prazo < now() then
      select * into ev from public.escala_eventos where id = q.escala_evento_id;
      select nome into nm from public.pessoas where id = q.pessoa_id;
      perform public.escala_avisar(q.id, 'escala_atrasada', 'atrasada:' || q.id || ':' || q.versao);
      perform public.notificar_gestao(ev.ministerio_id, 'atrasada:' || q.id || ':' || q.versao, 'escala_atrasada_lider', 'Confirmação atrasada',
              nm || ' ainda não respondeu à escala de ' || ev.titulo || '. Entre em contato ou substitua.', jsonb_build_object('escala', ev.id));
      n_atr := n_atr + 1;
    elsif q.prazo - interval '24 hours' <= now() then
      perform public.escala_avisar(q.id, 'escala_lembrete', 'lembrete:' || q.id || ':' || q.versao);
      n_lem := n_lem + 1;
    end if;
  end loop;
  return jsonb_build_object('lembretes', n_lem, 'atrasadas', n_atr);
end $$;


--
-- Name: financeiro_inscricao(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.financeiro_inscricao(p_inscricao uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select jsonb_build_object(
    'valor_bruto', i.valor_bruto, 'valor_desconto', i.valor_desconto, 'valor_final', i.valor_final,
    'aprovado', coalesce((select sum(p.valor) from public.pagamentos p where p.inscricao_id = i.id and p.status = 'aprovado'), 0),
    'em_analise', coalesce((select sum(p.valor) from public.pagamentos p where p.inscricao_id = i.id and p.status = 'em_analise'), 0),
    'reembolsado', coalesce((select sum(r.valor) from public.reembolsos r where r.inscricao_id = i.id), 0),
    'liquido', coalesce((select sum(p.valor) from public.pagamentos p where p.inscricao_id = i.id and p.status = 'aprovado'), 0)
               - coalesce((select sum(r.valor) from public.reembolsos r where r.inscricao_id = i.id), 0),
    'situacao', case
       when i.valor_final = 0 and i.valor_bruto > 0 then 'isento'
       when i.valor_final = 0 then 'gratuito'
       when coalesce((select sum(p.valor) from public.pagamentos p where p.inscricao_id = i.id and p.status = 'aprovado'), 0)
            - coalesce((select sum(r.valor) from public.reembolsos r where r.inscricao_id = i.id), 0) >= i.valor_final then 'quitado'
       when exists (select 1 from public.pagamentos p where p.inscricao_id = i.id and p.status = 'em_analise') then 'em_analise'
       when exists (select 1 from public.pagamentos p where p.inscricao_id = i.id and p.status = 'novo_comprovante_solicitado') then 'novo_comprovante_solicitado'
       else 'pendente' end)
  from public.inscricoes i where i.id = p_inscricao
$$;


--
-- Name: financeiro_minhas_permissoes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.financeiro_minhas_permissoes() RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select jsonb_build_object('secretaria', public.e_secretaria(), 'tesouraria', public.e_tesouraria(), 'usuario', auth.uid()) $$;


--
-- Name: financeiro_reavaliar(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.financeiro_reavaliar(p_inscricao uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.inscricoes; f jsonb;
begin
  select * into i from public.inscricoes where id = p_inscricao for update;
  f := public.financeiro_inscricao(p_inscricao);
  if i.status = 'aguardando_pagamento' and (i.valor_final = 0 or (f->>'liquido')::numeric >= i.valor_final) then
    update public.inscricoes set status = 'confirmada' where id = p_inscricao;
    return 'confirmada';
  end if;
  return i.status;
end $$;


--
-- Name: foto_url_publica(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.foto_url_publica(p_foto text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$ select p_foto $$;


--
-- Name: idade_em(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.idade_em(p_nascimento date, p_data date DEFAULT CURRENT_DATE) RETURNS integer
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$ select extract(year from age(p_data, p_nascimento))::integer $$;


--
-- Name: imagem_consultar(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.imagem_consultar(p_busca text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_b text := btrim(coalesce(p_busca, ''));
begin
  if not (public.e_secretaria() or exists (select 1 from public.ministerio_membros mm join public.ministerios m on m.id = mm.ministerio_id
                                             where m.slug = 'midia' and mm.ativo and mm.pessoa_id = public.minha_pessoa_id())) then
    raise exception 'Consulta restrita à Secretaria e ao ministério de Mídia.' using errcode = '42501'; end if;
  if char_length(v_b) < 3 then raise exception 'Digite ao menos 3 letras do nome.' using errcode = '22023'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('nome', q.nome,
      'situacao', case when q.cid is null then 'sem_autorizacao' when q.decisao = 'recusado' then 'nao_autorizado' else 'autorizado' end,
      'escopo', q.escopo, 'menor', q.menor, 'desde', q.registrado_em) order by q.nome)
    from (select pe.nome, c.id as cid, c.decisao, c.escopo, c.registrado_em,
                 case when pe.data_nascimento is not null then public.idade_em(pe.data_nascimento) < 18 end as menor
            from public.pessoas pe left join lateral (select * from public.consentimento_atual(pe.id, 'imagem_voz') x where x.id is not null) c on true
           where pe.arquivado_em is null and pe.nome ilike '%' || v_b || '%' order by pe.nome limit 30) q), '[]'::jsonb);
end $$;


--
-- Name: imagem_existe(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.imagem_existe(p_espaco text, p_caminho text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (select 1 from armazenamento.objetos where espaco = p_espaco and caminho = p_caminho and tipo in ('image/jpeg','image/png','image/webp'))
$$;


--
-- Name: inscrever_curso(uuid, text, text, text, date, text, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inscrever_curso(p_turma uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date, p_observacao text, p_aceite_privacidade boolean, p_origem text DEFAULT 'site'::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare t public.turmas; c public.cursos; v_email text := lower(btrim(coalesce(p_email, '')));
        v_tel text := public.so_digitos(p_telefone); v_nome text := regexp_replace(btrim(coalesce(p_nome, '')), '\s+', ' ', 'g');
        v_pessoa uuid; v_existente public.inscricoes; v_status text; v_chave text; v_prot text; v_ocup integer; v_pos integer; v_falta text;
        v_secretaria boolean := p_origem = 'secretaria';
begin
  if coalesce(current_setting('app.inscricao_com_termos', true), '') <> '1' then
    raise exception 'Use a inscrição com os termos (inscrever_curso_com_termos).' using errcode = '42501'; end if;
  if v_secretaria and not public.cursos_gestor() then raise exception 'Somente a Secretaria pode inscrever pelo painel.' using errcode = '42501'; end if;
  if p_origem not in ('site','secretaria') then raise exception 'Origem inválida.' using errcode = '22023'; end if;
  if char_length(v_nome) < 3 or v_nome !~ '\s' then raise exception 'Informe o nome completo.' using errcode = '22023'; end if;
  if v_tel !~ '^[0-9]{10,13}$' then raise exception 'Informe um telefone válido, com DDD.' using errcode = '22023'; end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Informe um e-mail válido.' using errcode = '22023'; end if;
  if p_data_nascimento is not null and (p_data_nascimento > current_date or p_data_nascimento < date '1900-01-01') then
    raise exception 'Data de nascimento inválida.' using errcode = '22023'; end if;
  if not coalesce(p_aceite_privacidade, false) then raise exception 'É preciso concordar com o uso dos dados para a inscrição.' using errcode = '22023'; end if;

  -- trava a turma: inscrições simultâneas entram uma de cada vez
  select * into t from public.turmas where id = p_turma for update;
  if not found then raise exception 'Turma não encontrada.' using errcode = 'P0002'; end if;
  select * into c from public.cursos where id = t.curso_id;
  if not c.publicado and not v_secretaria then raise exception 'Curso indisponível.' using errcode = 'P0002'; end if;
  if not v_secretaria and not public.turma_aberta(t) then raise exception 'As inscrições desta turma não estão abertas.' using errcode = '22023'; end if;
  if v_secretaria and t.status in ('rascunho','cancelada','concluida') then raise exception 'Esta turma não aceita inscrições (situação: %).', t.status using errcode = '22023'; end if;

  -- pessoa: reaproveita o cadastro pelo e-mail (sem duplicar)
  select id into v_pessoa from public.pessoas where email = v_email and arquivado_em is null;
  -- duplicidade: mesmo e-mail OU mesmo telefone já inscrito nesta turma
  select i.* into v_existente from public.inscricoes i join public.pessoas pe on pe.id = i.pessoa_id
   where i.turma_id = p_turma and i.status <> 'cancelada' and (pe.email = v_email or pe.telefone = v_tel) limit 1;
  if found then
    return jsonb_build_object('ok', true, 'duplicada', true, 'protocolo', v_existente.protocolo, 'status', v_existente.status,
      'mensagem', 'Já existe uma inscrição ativa nesta turma com este e-mail ou telefone (protocolo ' || v_existente.protocolo || ').');
  end if;

  -- pré-requisitos (ex.: Formação de Voluntários)
  if c.exige_membro and not public.membresia_validada(v_pessoa) then
    raise exception 'Este curso é para membros com a membresia validada pela Secretaria. Fale com a Secretaria.' using errcode = '22023';
  end if;
  select string_agg(x.titulo, ', ') into v_falta from public.cursos x
   where x.id = any(c.cursos_exigidos) and not public.curso_concluido(v_pessoa, x.id);
  if v_falta is not null then
    raise exception 'Antes deste curso é preciso concluir: %.', v_falta using errcode = '22023';
  end if;

  if v_pessoa is null then
    insert into public.pessoas (nome, telefone, email, data_nascimento, origem)
    values (v_nome, v_tel, v_email, p_data_nascimento, case when v_secretaria then 'secretaria' else 'site' end)
    returning id into v_pessoa;
  else
    update public.pessoas set telefone = coalesce(telefone, v_tel), data_nascimento = coalesce(data_nascimento, p_data_nascimento) where id = v_pessoa;
  end if;

  v_ocup := (public.cursos_vagas_turma(p_turma)->>'ocupadas')::int;
  if t.vagas is not null and v_ocup >= t.vagas then
    if not t.lista_espera then raise exception 'As vagas desta turma estão esgotadas.' using errcode = '22023'; end if;
    v_status := 'lista_espera';
  else
    v_status := case when coalesce(t.valor, 0) > 0 then 'aguardando_pagamento' else 'confirmada' end;
  end if;

  v_chave := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  v_prot := 'CUR-' || to_char(now() at time zone 'America/Sao_Paulo', 'YYYY') || '-' || lpad(nextval('public.inscricoes_protocolo_seq')::text, 6, '0');
  insert into public.inscricoes (protocolo, pessoa_id, turma_id, status, valor_bruto, valor_final, observacao, aceite_privacidade_em,
                                 chave_hash, origem, criado_por)
  values (v_prot, v_pessoa, p_turma, v_status, coalesce(t.valor, 0), coalesce(t.valor, 0), nullif(btrim(p_observacao), ''), now(),
          encode(sha256(convert_to(v_chave, 'UTF8')), 'hex'), p_origem, auth.uid());

  if v_status = 'lista_espera' then
    select count(*) into v_pos from public.inscricoes where turma_id = p_turma and status = 'lista_espera';
  end if;
  return jsonb_build_object('ok', true, 'duplicada', false, 'protocolo', v_prot, 'chave', v_chave, 'status', v_status,
    'posicao_espera', v_pos, 'curso', c.titulo, 'turma', t.nome, 'valor', t.valor);
exception when unique_violation then
  raise exception 'Já existe uma inscrição ativa desta pessoa nesta turma.' using errcode = '23505';
end $_$;


--
-- Name: inscrever_curso_com_termos(uuid, text, text, text, date, text, boolean, uuid, jsonb, jsonb, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inscrever_curso_com_termos(p_turma uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date, p_observacao text, p_aceite_privacidade boolean, p_termo_participacao uuid, p_imagem jsonb, p_responsavel jsonb, p_origem text DEFAULT 'site'::text, p_termo_presencial boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r jsonb; v_ins public.inscricoes; v_menor boolean; v_origem_c text;
begin
  if p_data_nascimento is null then raise exception 'Informe a data de nascimento.' using errcode = '22023'; end if;
  if p_origem = 'secretaria' and not coalesce(p_termo_presencial, false) then
    raise exception 'Confirme que o termo de participação foi assinado pela pessoa (ou pelo responsável).' using errcode = '22023'; end if;
  if p_termo_participacao is null or not exists (select 1 from public.termos where id = p_termo_participacao and tipo = 'participacao_curso' and status = 'vigente') then
    if not exists (select 1 from public.termos where tipo = 'participacao_curso' and status = 'vigente') then
      raise exception 'As inscrições estão temporariamente fechadas: o termo de participação ainda não foi publicado.' using errcode = '22023'; end if;
    raise exception 'É preciso ler e aceitar o termo de participação em vigor.' using errcode = '22023';
  end if;
  if public.idade_em(p_data_nascimento) < 18 then perform public.responsavel_valido(p_responsavel); end if;

  perform set_config('app.inscricao_com_termos', '1', true);
  r := public.inscrever_curso(p_turma, p_nome, p_telefone, p_email, p_data_nascimento, p_observacao, p_aceite_privacidade, p_origem);
  perform set_config('app.inscricao_com_termos', '', true);
  if (r->>'duplicada')::boolean then return r; end if;

  select * into v_ins from public.inscricoes where protocolo = r->>'protocolo';
  -- vale a data já cadastrada (uma inscrição não altera o cadastro de outra pessoa)
  v_menor := public.idade_em((select data_nascimento from public.pessoas where id = v_ins.pessoa_id)) < 18;
  v_origem_c := case when p_origem = 'secretaria' then 'secretaria' else 'site' end;
  perform public.registrar_consentimento(v_ins.pessoa_id, 'participacao_curso', p_termo_participacao, 'aceito', null,
          case when v_menor then p_responsavel end, v_origem_c, 'inscricao', v_ins.id);
  -- imagem e voz: opcional e nunca condição para participar
  if p_imagem is not null and coalesce(p_imagem->>'decisao', '') in ('aceito','recusado') then
    perform public.registrar_consentimento(v_ins.pessoa_id, 'imagem_voz', (p_imagem->>'termo_id')::uuid, p_imagem->>'decisao',
            p_imagem->'escopo', case when v_menor then p_responsavel end, v_origem_c, 'inscricao', v_ins.id);
  end if;
  return r || jsonb_build_object('menor', v_menor);
end $$;


--
-- Name: institucional_permissoes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.institucional_permissoes() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.perfil_ativo() then return jsonb_build_object('ativo', false); end if;
  return jsonb_build_object('ativo', true, 'master', public.e_master(),
    'agenda_coordenador', public.agenda_coordenador(),
    'ministerios_lider', coalesce((select jsonb_agg(mm.ministerio_id) from public.ministerio_membros mm
       join public.perfis p on p.pessoa_id = mm.pessoa_id
       where p.id = auth.uid() and mm.funcao = 'lider' and mm.ativo and p.perfil in ('MASTER','LIDER')), '[]'::jsonb));
end $$;


--
-- Name: lider_candidaturas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.lider_candidaturas() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(public.candidatura_json(c.id)
      || jsonb_build_object('para_mim', (select jsonb_agg(jsonb_build_object('indicacao_id', vi.id, 'ministerio', m.nome, 'status', vi.status, 'ordem', vi.ordem))
                                        from public.voluntariado_indicacoes vi join public.ministerios m on m.id = vi.ministerio_id
                                        where vi.candidatura_id = c.id and (public.lider_de(vi.ministerio_id) or public.e_master())))
      order by c.criado_em)
    from public.voluntariado_candidaturas c
    where c.status in ('em_analise','aprovada','nao_aprovada')
      and exists (select 1 from public.voluntariado_indicacoes vi where vi.candidatura_id = c.id and (public.lider_de(vi.ministerio_id) or public.e_master())
                    and (vi.status = 'pendente' or vi.analisado_em > now() - interval '60 days'))), '[]'::jsonb);
end $$;


--
-- Name: lider_concluir_validar(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.lider_concluir_validar(p_inscricao uuid, p_observacao text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.inscricoes;
begin
  select * into i from public.inscricoes where id = p_inscricao for update;
  if not found then raise exception 'Inscrição não encontrada.' using errcode = 'P0002'; end if;
  if not public.certificado_validador(i.turma_id) then raise exception 'Somente a liderança responsável pela turma valida a conclusão.' using errcode = '42501'; end if;
  if i.status <> 'confirmada' then raise exception 'Só inscrições confirmadas podem ser concluídas.' using errcode = '22023'; end if;
  update public.inscricoes set status = 'concluida', concluida_em = now(), concluida_por = auth.uid() where id = i.id;
  if nullif(btrim(p_observacao), '') is not null then
    update public.certificados set observacao_validacao = btrim(p_observacao) where inscricao_id = i.id;
  end if;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: lider_de(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.lider_de(p_ministerio uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select public.perfil_ativo() and exists (
    select 1 from public.perfis p
    join public.ministerio_membros mm on mm.pessoa_id = p.pessoa_id
    where p.id = auth.uid() and p.perfil in ('MASTER','LIDER')
      and mm.ministerio_id = p_ministerio and mm.funcao = 'lider' and mm.ativo)
$$;


--
-- Name: lider_decidir_indicacao(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.lider_decidir_indicacao(p_indicacao uuid, p_acao text, p_motivo text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare vi public.voluntariado_indicacoes; c public.voluntariado_candidaturas; pe public.pessoas; r jsonb; v_min text;
begin
  select * into vi from public.voluntariado_indicacoes where id = p_indicacao for update;
  if not found then raise exception 'Indicação não encontrada.' using errcode = 'P0002'; end if;
  if not (public.lider_de(vi.ministerio_id) or public.e_master()) then
    raise exception 'Somente a liderança deste ministério decide.' using errcode = '42501'; end if;
  if vi.status <> 'pendente' then raise exception 'Esta indicação já foi analisada.' using errcode = '22023'; end if;
  select * into c from public.voluntariado_candidaturas where id = vi.candidatura_id for update;
  select * into pe from public.pessoas where id = c.pessoa_id;
  select nome into v_min from public.ministerios where id = vi.ministerio_id;
  if p_acao = 'aprovar' then
    r := public.voluntariado_requisitos(c.pessoa_id);
    if not (r->>'pode_ser_aprovado')::boolean then
      raise exception 'A pessoa ainda não cumpre todos os requisitos (membresia validada, Novos Membros, Formação de Voluntários e termo de adesão).' using errcode = '22023'; end if;
    insert into public.ministerio_membros (pessoa_id, ministerio_id, funcao) values (c.pessoa_id, vi.ministerio_id, 'voluntario')
    on conflict (pessoa_id, ministerio_id) do update set ativo = true, funcao = case when public.ministerio_membros.funcao = 'lider' then 'lider' else 'voluntario' end;
    update public.voluntariado_indicacoes set status = 'aprovada', analisado_por = auth.uid(), analisado_em = now(), motivo = nullif(btrim(p_motivo), '') where id = vi.id;
    update public.voluntariado_candidaturas set status = 'aprovada', encerrada_em = coalesce(encerrada_em, now()) where id = c.id;
    -- acesso à Área da Equipe: vai para o MASTER aprovar pelo fluxo normal (senha temporária)
    if not exists (select 1 from public.perfis where pessoa_id = c.pessoa_id) and pe.email is not null and pe.telefone is not null then
      insert into public.solicitacoes (tipo, nome, telefone, email, ministerio_id, funcao_pretendida, mensagem, pessoa_id)
      values ('acesso', pe.nome, pe.telefone, pe.email, vi.ministerio_id, 'voluntario', 'Aprovado(a) como voluntário(a) em ' || v_min || ' pela liderança.', c.pessoa_id)
      on conflict do nothing;
    end if;
    perform public.notificar('SECRETARIA', null, 'voluntario_aprovado', 'Voluntário aprovado', pe.nome || ' foi aprovado(a) no ministério ' || v_min || '.', jsonb_build_object('candidatura', c.id));
  elsif p_acao = 'recusar' then
    if char_length(btrim(coalesce(p_motivo, ''))) < 5 then raise exception 'Explique o motivo (a Secretaria fará o retorno à pessoa).' using errcode = '22023'; end if;
    update public.voluntariado_indicacoes set status = 'recusada', analisado_por = auth.uid(), analisado_em = now(), motivo = btrim(p_motivo) where id = vi.id;
    if c.status = 'em_analise' and not exists (select 1 from public.voluntariado_indicacoes where candidatura_id = c.id and status in ('pendente','aprovada')) then
      update public.voluntariado_candidaturas set status = 'nao_aprovada', encerrada_em = now() where id = c.id;
      perform public.notificar('SECRETARIA', null, 'candidatura_nao_aprovada', 'Candidatura sem aprovação', 'Nenhum dos ministérios indicados por ' || pe.nome || ' aprovou. Faça o retorno à pessoa.', jsonb_build_object('candidatura', c.id));
    end if;
  else raise exception 'Ação inválida.' using errcode = '22023';
  end if;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: lider_turmas_validacao(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.lider_turmas_validacao() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('turma_id', t.id, 'turma', t.nome, 'curso', c.titulo, 'modalidade', c.modalidade, 'status', t.status,
      'inscricoes', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'protocolo', i.protocolo, 'nome', pe.nome, 'status', i.status, 'concluida_em', i.concluida_em,
           'certificado', (select jsonb_build_object('id', ce.id, 'status', ce.status, 'validado_em', ce.validado_em) from public.certificados ce where ce.inscricao_id = i.id))
           order by pe.nome)
         from public.inscricoes i join public.pessoas pe on pe.id = i.pessoa_id where i.turma_id = t.id and i.status in ('confirmada','concluida')), '[]'::jsonb))
      order by c.titulo, t.nome)
    from public.turmas t join public.cursos c on c.id = t.curso_id
    where t.status not in ('rascunho','cancelada') and public.certificado_validador(t.id)
      and (not public.e_master() or exists (select 1 from public.inscricoes i where i.turma_id = t.id and i.status in ('confirmada','concluida')))), '[]'::jsonb);
end $$;


--
-- Name: lider_validar_certificado(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.lider_validar_certificado(p_certificado uuid, p_acao text, p_observacao text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare ce public.certificados; i public.inscricoes;
begin
  select * into ce from public.certificados where id = p_certificado for update;
  if not found then raise exception 'Certificado não encontrado.' using errcode = 'P0002'; end if;
  select * into i from public.inscricoes where id = ce.inscricao_id;
  if not public.certificado_validador(i.turma_id) then raise exception 'Somente a liderança responsável pela turma valida a conclusão.' using errcode = '42501'; end if;
  if ce.status <> 'aguardando_validacao' then raise exception 'Este certificado não está aguardando validação.' using errcode = '22023'; end if;
  if p_acao = 'validar' then
    update public.certificados set status = 'aguardando_autorizacao', validado_por = auth.uid(), validado_em = now(),
           observacao_validacao = nullif(btrim(p_observacao), '') where id = ce.id;
    perform public.notificar('SECRETARIA', null, 'certificado_autorizar', 'Certificado para autorizar', 'Conclusão da inscrição ' || i.protocolo || ' validada pela liderança. Autorize a emissão.', jsonb_build_object('inscricao_id', i.id));
  elsif p_acao = 'nao_validar' then
    if char_length(btrim(coalesce(p_observacao, ''))) < 5 then raise exception 'Explique por que a conclusão não foi validada.' using errcode = '22023'; end if;
    perform set_config('app.cert_detalhe', jsonb_build_object('motivo', 'Conclusão não validada: ' || btrim(p_observacao))::text, true);
    update public.certificados set motivo_cancelamento = 'Conclusão não validada: ' || btrim(p_observacao) where id = ce.id;
    -- a inscrição volta a "confirmada" (volta a cursar); o gatilho cancela o certificado
    update public.inscricoes set status = 'confirmada', concluida_em = null, concluida_por = null where id = i.id;
    update public.certificados set motivo_cancelamento = 'Conclusão não validada: ' || btrim(p_observacao) where id = ce.id;
    perform set_config('app.cert_detalhe', '', true);
    perform public.notificar('SECRETARIA', null, 'certificado_nao_validado', 'Conclusão não validada', 'A liderança não validou a conclusão da inscrição ' || i.protocolo || ': ' || btrim(p_observacao), jsonb_build_object('inscricao_id', i.id));
  else raise exception 'Ação inválida.' using errcode = '22023';
  end if;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: limite_publico(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.limite_publico(p_chave text, p_padrao integer) RETURNS integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce((select (valor->>p_chave)::int from public.configuracoes where chave = 'limites_publicos'), p_padrao)
$$;


--
-- Name: inscricoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inscricoes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    protocolo text NOT NULL,
    pessoa_id uuid NOT NULL,
    turma_id uuid NOT NULL,
    status text NOT NULL,
    valor_bruto numeric(10,2) DEFAULT 0 NOT NULL,
    valor_desconto numeric(10,2) DEFAULT 0 NOT NULL,
    valor_final numeric(10,2) DEFAULT 0 NOT NULL,
    observacao text,
    aceite_privacidade_em timestamp with time zone NOT NULL,
    chave_hash text NOT NULL,
    origem text NOT NULL,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    promovida_em timestamp with time zone,
    cancelada_em timestamp with time zone,
    motivo_cancelamento text,
    concluida_em timestamp with time zone,
    concluida_por uuid,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT inscricoes_motivo_cancelamento_check CHECK ((char_length(motivo_cancelamento) <= 300)),
    CONSTRAINT inscricoes_observacao_check CHECK ((char_length(observacao) <= 600)),
    CONSTRAINT inscricoes_origem_check CHECK ((origem = ANY (ARRAY['site'::text, 'secretaria'::text]))),
    CONSTRAINT inscricoes_status_check CHECK ((status = ANY (ARRAY['confirmada'::text, 'aguardando_pagamento'::text, 'lista_espera'::text, 'cancelada'::text, 'concluida'::text])))
);


--
-- Name: link_inscricao(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.link_inscricao(p_protocolo text, p_chave text) RETURNS public.inscricoes
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.inscricoes;
begin
  select * into i from public.inscricoes where protocolo = upper(btrim(p_protocolo))
     and chave_hash = encode(sha256(convert_to(coalesce(p_chave, ''), 'UTF8')), 'hex');
  if not found then raise exception 'Inscrição não encontrada. Confira o link recebido.' using errcode = 'P0002'; end if;
  return i;
end $$;


--
-- Name: listar_auditoria(integer, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.listar_auditoria(p_limite integer DEFAULT 100, p_antes_de bigint DEFAULT NULL::bigint) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_master() then raise exception 'Somente o MASTER pode ver o histórico.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(x order by (x ->> 'id')::bigint desc) from (
    select jsonb_build_object('id', a.id, 'quando', a.quando, 'acao', a.acao, 'tabela', a.tabela, 'registro', a.registro,
             'ator', coalesce((select pe.nome from public.perfis pf join public.pessoas pe on pe.id = pf.pessoa_id where pf.id = a.ator), case when a.ator is null then 'Sistema' else 'Usuário removido' end),
             'alvo', case a.tabela
                when 'perfis' then (select pe.nome from public.perfis pf join public.pessoas pe on pe.id = pf.pessoa_id where pf.id::text = a.registro)
                when 'pessoas' then (select pe.nome from public.pessoas pe where pe.id::text = a.registro)
                when 'ministerios' then (select m.nome from public.ministerios m where m.id::text = a.registro)
                when 'solicitacoes' then (select s.nome from public.solicitacoes s where s.id::text = a.registro)
                when 'ministerio_membros' then (select pe.nome || ' · ' || m.nome from public.ministerio_membros mm
                   join public.pessoas pe on pe.id = mm.pessoa_id join public.ministerios m on m.id = mm.ministerio_id where mm.id::text = a.registro)
                else a.registro end,
             'antes', a.antes, 'depois', a.depois, 'detalhes', a.detalhes) as x
    from public.auditoria a
    where p_antes_de is null or a.id < p_antes_de
    order by a.id desc limit least(greatest(coalesce(p_limite, 100), 1), 500)) t), '[]'::jsonb);
end $$;


--
-- Name: listar_solicitacoes(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.listar_solicitacoes(p_status text DEFAULT 'pendente'::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_master() then raise exception 'Somente o MASTER pode ver as solicitações.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', s.id, 'nome', s.nome, 'telefone', s.telefone, 'email', s.email,
      'ministerio_id', s.ministerio_id, 'ministerio', m.nome, 'funcao', s.funcao_pretendida,
      'status', s.status, 'criado_em', s.criado_em, 'analisado_em', s.analisado_em, 'motivo', s.motivo,
      'analisado_por', (select pe.nome from public.perfis pf join public.pessoas pe on pe.id = pf.pessoa_id where pf.id = s.analisado_por))
      order by s.criado_em desc)
    from public.solicitacoes s left join public.ministerios m on m.id = s.ministerio_id
    where s.tipo = 'acesso' and (p_status is null or s.status = p_status)), '[]'::jsonb);
end $$;


--
-- Name: listar_usuarios(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.listar_usuarios() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_master() then raise exception 'Somente o MASTER pode ver os usuários.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', pf.id, 'nome', pe.nome, 'email', pe.email, 'telefone', pe.telefone,
      'perfil', pf.perfil, 'atribuicoes', to_jsonb(pf.atribuicoes), 'ativo', pf.ativo,
      'deve_trocar_senha', pf.deve_trocar_senha, 'aprovado_em', pf.aprovado_em, 'eu', pf.id = auth.uid(),
      'ministerios', coalesce((select jsonb_agg(jsonb_build_object('ministerio_id', mm.ministerio_id, 'nome', m.nome, 'funcao', mm.funcao) order by m.ordem, m.nome)
                               from public.ministerio_membros mm join public.ministerios m on m.id = mm.ministerio_id
                               where mm.pessoa_id = pf.pessoa_id and mm.ativo), '[]'::jsonb))
      order by pf.ativo desc, pe.nome)
    from public.perfis pf join public.pessoas pe on pe.id = pf.pessoa_id), '[]'::jsonb);
end $$;


--
-- Name: marcar_notificacoes_lidas(bigint[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marcar_notificacoes_lidas(p_ids bigint[]) RETURNS jsonb
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  update public.notificacoes n set lida_por = array_append(n.lida_por, auth.uid())
   where n.id = any(p_ids) and not (auth.uid() = any(n.lida_por)) and public.perfil_ativo()
     and (n.para_usuario = auth.uid() or (n.para_atribuicao = 'SECRETARIA' and public.e_secretaria()) or (n.para_atribuicao = 'TESOURARIA' and public.e_tesouraria()))
  returning jsonb_build_object('ok', true)
$$;


--
-- Name: membresia_interesse(text, text, text, date, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.membresia_interesse(p_nome text, p_telefone text, p_email text, p_data_nascimento date, p_mensagem text, p_aceite_privacidade boolean) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare v_nome text := regexp_replace(btrim(coalesce(p_nome, '')), '\s+', ' ', 'g'); v_tel text := public.so_digitos(p_telefone);
        v_email text := lower(btrim(coalesce(p_email, ''))); v_pessoa uuid; v_proc uuid;
begin
  if char_length(v_nome) < 5 or v_nome !~ '\s' then raise exception 'Informe o nome completo.' using errcode = '22023'; end if;
  if v_tel !~ '^[0-9]{10,13}$' then raise exception 'Informe um telefone válido, com DDD.' using errcode = '22023'; end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Informe um e-mail válido.' using errcode = '22023'; end if;
  if p_data_nascimento is null or p_data_nascimento > current_date or p_data_nascimento < date '1900-01-01' then raise exception 'Informe a data de nascimento.' using errcode = '22023'; end if;
  if not coalesce(p_aceite_privacidade, false) then raise exception 'É preciso concordar com o uso dos dados para o contato da Secretaria.' using errcode = '22023'; end if;
  select id into v_pessoa from public.pessoas where email = v_email and arquivado_em is null;
  if v_pessoa is null then
    insert into public.pessoas (nome, telefone, email, data_nascimento, origem) values (v_nome, v_tel, v_email, p_data_nascimento, 'site') returning id into v_pessoa;
  else
    -- a manifestação de interesse NUNCA altera a situação de membresia
    update public.pessoas set telefone = coalesce(telefone, v_tel), data_nascimento = coalesce(data_nascimento, p_data_nascimento) where id = v_pessoa;
    if public.membresia_validada(v_pessoa) then
      return jsonb_build_object('ok', true, 'mensagem', 'Recebemos o seu contato. A Secretaria vai falar com você.');
    end if;
  end if;
  select id into v_proc from public.membresia_processos where pessoa_id = v_pessoa and status not in ('validado','encerrado');
  if v_proc is null then
    insert into public.membresia_processos (pessoa_id, origem, mensagem) values (v_pessoa, 'site', nullif(btrim(p_mensagem), '')) returning id into v_proc;
    perform public.notificar('SECRETARIA', null, 'interesse_membresia', 'Novo interesse em membresia', v_nome || ' quer se tornar membro.', jsonb_build_object('processo', v_proc));
  end if;
  return jsonb_build_object('ok', true, 'mensagem', 'Recebemos o seu interesse. A Secretaria vai entrar em contato para o Curso de Novos Membros.');
end $_$;


--
-- Name: membresia_validada(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.membresia_validada(p_pessoa uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (select 1 from public.pessoas where id = p_pessoa and situacao_membresia = 'membro'
                  and membresia_validada_em is not null and membresia_validada_por is not null and arquivado_em is null)
$$;


--
-- Name: membro_de(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.membro_de(p_ministerio uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select public.perfil_ativo() and exists (
    select 1 from public.perfis p
    join public.ministerio_membros mm on mm.pessoa_id = p.pessoa_id
    where p.id = auth.uid() and mm.ministerio_id = p_ministerio and mm.ativo)
$$;


--
-- Name: meu_painel(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.meu_painel() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_p public.perfis; v_pe public.pessoas; v_res jsonb;
begin
  select * into v_p from public.perfis where id = auth.uid();
  if not found then return jsonb_build_object('status','sem_perfil'); end if;
  if not v_p.ativo then return jsonb_build_object('status','inativo'); end if;
  select * into v_pe from public.pessoas where id = v_p.pessoa_id;
  if v_p.deve_trocar_senha then
    return jsonb_build_object('status','trocar_senha', 'nome', v_pe.nome);
  end if;
  v_res := jsonb_build_object(
    'status','ok', 'nome', v_pe.nome, 'email', v_pe.email, 'telefone', v_pe.telefone,
    'perfil', v_p.perfil, 'atribuicoes', to_jsonb(v_p.atribuicoes),
    'senha_alterada_em', v_p.senha_alterada_em,
    'ministerios', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'nome', m.nome, 'funcao', mm.funcao) order by m.ordem, m.nome)
                            from public.ministerio_membros mm join public.ministerios m on m.id = mm.ministerio_id
                            where mm.pessoa_id = v_p.pessoa_id and mm.ativo), '[]'::jsonb));
  if v_p.perfil = 'MASTER' then
    v_res := v_res || jsonb_build_object('resumo', jsonb_build_object(
      'solicitacoes_pendentes', (select count(*) from public.solicitacoes where tipo = 'acesso' and status = 'pendente'),
      'usuarios_ativos', (select count(*) from public.perfis where ativo),
      'ministerios_ativos', (select count(*) from public.ministerios where ativo)));
  end if;
  return v_res;
end $$;


--
-- Name: meu_perfil(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.meu_perfil() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_p public.perfis; v_pe public.pessoas;
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  select * into v_p from public.perfis where id = auth.uid();
  select * into v_pe from public.pessoas where id = v_p.pessoa_id;
  return jsonb_build_object(
    'nome', v_pe.nome, 'email', v_pe.email, 'telefone', v_pe.telefone,
    'perfil', v_p.perfil, 'atribuicoes', to_jsonb(v_p.atribuicoes),
    'conta_criada_em', v_p.criado_em, 'aprovado_em', v_p.aprovado_em,
    'senha_alterada_em', v_p.senha_alterada_em,
    'foto', v_p.foto_caminho, 'foto_no_organograma', v_p.foto_no_organograma,
    'ministerios', coalesce((select jsonb_agg(jsonb_build_object('nome', m.nome, 'funcao', mm.funcao, 'cargo', mm.cargo, 'desde', mm.desde) order by m.ordem, m.nome)
                             from public.ministerio_membros mm join public.ministerios m on m.id = mm.ministerio_id
                             where mm.pessoa_id = v_p.pessoa_id and mm.ativo), '[]'::jsonb),
    'editaveis', jsonb_build_array('telefone', 'foto'));
end $$;


--
-- Name: meu_perfil_atualizar(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.meu_perfil_atualizar(p_telefone text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare v_tel text := public.so_digitos(p_telefone); v_pessoa uuid;
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  if v_tel !~ '^[0-9]{10,11}$' then
    raise exception 'Informe um telefone válido, com DDD.' using errcode = '22023'; end if;
  select pessoa_id into v_pessoa from public.perfis where id = auth.uid();
  update public.pessoas set telefone = v_tel, atualizado_em = now() where id = v_pessoa;
  return public.meu_perfil();
end $_$;


--
-- Name: meu_perfil_foto(text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.meu_perfil_foto(p_caminho text, p_no_organograma boolean) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare v_antiga text;
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  select foto_caminho into v_antiga from public.perfis where id = auth.uid();
  if p_caminho is not null then
    if p_caminho !~ ('^' || auth.uid()::text || '/[0-9a-f-]{36}\.(jpg|png|webp)$') or not public.imagem_existe('perfis', p_caminho) then
      raise exception 'Foto inválida. Envie a imagem de novo.' using errcode = '22023'; end if;
    update public.perfis set foto_caminho = p_caminho, foto_no_organograma = coalesce(p_no_organograma, foto_no_organograma) where id = auth.uid();
    if v_antiga is not null and v_antiga <> p_caminho then delete from armazenamento.objetos where espaco = 'perfis' and caminho = v_antiga; end if;
  else
    update public.perfis set foto_no_organograma = coalesce(p_no_organograma, foto_no_organograma) where id = auth.uid();
  end if;
  return public.meu_perfil();
end $_$;


--
-- Name: meu_perfil_foto_remover(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.meu_perfil_foto_remover() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_antiga text;
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  select foto_caminho into v_antiga from public.perfis where id = auth.uid();
  update public.perfis set foto_caminho = null where id = auth.uid();
  if v_antiga is not null then delete from armazenamento.objetos where espaco = 'perfis' and caminho = v_antiga; end if;
  return public.meu_perfil();
end $$;


--
-- Name: meus_termos(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.meus_termos(p_protocolo text, p_chave text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.inscricoes := public.link_inscricao(p_protocolo, p_chave); pe public.pessoas;
begin
  select * into pe from public.pessoas where id = i.pessoa_id;
  return jsonb_build_object('consentimentos', public.consentimentos_json(i.pessoa_id),
    'menor', case when pe.data_nascimento is null then null else public.idade_em(pe.data_nascimento) < 18 end,
    'tem_nascimento', pe.data_nascimento is not null, 'vigentes', public.termos_vigentes());
end $$;


--
-- Name: midia_agenda_pendentes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.midia_agenda_pendentes() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare m uuid := public.midia_ministerio_id();
begin
  if not public.escala_gestor(m) then raise exception 'Acesso restrito à liderança de Mídia.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'titulo', e.titulo, 'data', e.data::text, 'horario', coalesce(e.horario_inicio::text, e.horario), 'local', e.local, 'ministerio', e.ministerio) order by e.data::text)
    from public.eventos e where coalesce(e.necessita_midia, '') = 'Sim' and e.data::text >= to_char(current_date, 'YYYY-MM-DD')
      and not exists (select 1 from public.apoio_solicitacoes s where s.evento_id = e.id and s.status <> 'cancelada')
      and not exists (select 1 from public.escala_eventos x where x.evento_id = e.id and x.status <> 'cancelada')), '[]'::jsonb);
end $$;


--
-- Name: midia_catalogo(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.midia_catalogo(p_ministerio uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare m uuid := coalesce(p_ministerio, public.midia_ministerio_id());
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  return jsonb_build_object('ministerio_id', m, 'pode_gerir', public.escala_lider(m), 'pode_escalar', public.escala_gestor(m),
    'servicos', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.nome, 'descricao', s.descricao, 'ativo', s.ativo,
        'funcoes', coalesce((select jsonb_agg(sf.funcao_id) from public.apoio_servico_funcoes sf where sf.servico_id = s.id), '[]'::jsonb)) order by s.ordem, s.nome)
      from public.apoio_servicos s where s.ministerio_id = m), '[]'::jsonb),
    'areas', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'nome', a.nome, 'ativo', a.ativo,
        'funcoes', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'nome', f.nome, 'exige_habilitacao', f.exige_habilitacao, 'aceita_em_treinamento', f.aceita_em_treinamento,
            'quantidade_referencia', f.quantidade_referencia, 'orientacao_padrao', f.orientacao_padrao, 'ativo', f.ativo) order by f.ordem, f.nome)
          from public.escala_funcoes f where f.area_id = a.id), '[]'::jsonb)) order by a.ordem, a.nome)
      from public.escala_areas a where a.ministerio_id = m), '[]'::jsonb),
    'gestores', case when public.escala_lider(m) then coalesce((select jsonb_agg(jsonb_build_object('perfil_id', g.perfil_id, 'nome', x.nome, 'areas', g.areas, 'ativo', g.ativo))
        from public.escala_gestores g join public.perfis pf on pf.id = g.perfil_id join public.pessoas x on x.id = pf.pessoa_id where g.ministerio_id = m), '[]'::jsonb) else '[]'::jsonb end);
end $$;


--
-- Name: midia_criar_escala(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.midia_criar_escala(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare m uuid := coalesce(nullif(p->>'ministerio_id', '')::uuid, public.midia_ministerio_id()); s public.apoio_solicitacoes; v_ev bigint := nullif(p->>'evento_id', '')::bigint;
        per record; ev public.eventos; v_id uuid; f uuid; v_tit text; v_ini timestamptz; v_fim timestamptz; v_loc text;
begin
  if not public.escala_gestor(m) then raise exception 'Somente a liderança de Mídia monta escalas.' using errcode = '42501'; end if;
  if nullif(p->>'solicitacao_id', '') is not null then
    select * into s from public.apoio_solicitacoes where id = (p->>'solicitacao_id')::uuid;
    if not found or s.ministerio_alvo <> m then raise exception 'Solicitação não encontrada.' using errcode = 'P0002'; end if;
    if s.status not in ('aprovada','aprovada_parcial') then raise exception 'Aprove a solicitação antes de montar a escala.' using errcode = '22023'; end if;
    v_ev := coalesce(v_ev, s.evento_id); v_tit := s.titulo; v_ini := s.inicio; v_fim := s.fim; v_loc := s.local;
  end if;
  if v_ev is not null then
    select * into ev from public.eventos where id = v_ev;
    if not found then raise exception 'Evento da Agenda não encontrado.' using errcode = 'P0002'; end if;
    select * into per from public.agenda_evento_periodo(v_ev);
    v_tit := coalesce(v_tit, ev.titulo); v_ini := coalesce(per.inicio, v_ini); v_fim := coalesce(per.fim, v_fim); v_loc := coalesce(nullif(ev.local, ''), v_loc);
  end if;
  v_tit := coalesce(nullif(btrim(p->>'titulo'), ''), v_tit); v_ini := coalesce(nullif(p->>'inicio', '')::timestamptz, v_ini);
  v_fim := coalesce(nullif(p->>'fim', '')::timestamptz, v_fim); v_loc := coalesce(nullif(btrim(p->>'local'), ''), v_loc);
  if v_ini is null or v_fim is null or v_loc is null or v_tit is null then raise exception 'Informe título, início, término e local.' using errcode = '22023'; end if;
  insert into public.escala_eventos (ministerio_id, solicitacao_id, evento_id, titulo, inicio, fim, local, prazo_confirmacao, orientacoes_gerais, criado_por)
  values (m, s.id, v_ev, v_tit, v_ini, v_fim, v_loc, nullif(p->>'prazo_confirmacao', '')::timestamptz, nullif(btrim(p->>'orientacoes_gerais'), ''), auth.uid()) returning id into v_id;
  -- funções: as escolhidas pelo líder; sem escolha, as sugeridas pelos serviços aprovados
  for f in select distinct x from (
      select (jsonb_array_elements_text(p->'funcoes'))::uuid x where p ? 'funcoes'
      union select sf.funcao_id from public.apoio_solicitacao_servicos ss join public.apoio_servico_funcoes sf on sf.servico_id = ss.servico_id
             where not (p ? 'funcoes') and ss.solicitacao_id = s.id and ss.decisao = 'atender') q loop
    perform public.escala_incluir_funcao_interno(v_id, f, null, null, null, null);
  end loop;
  return jsonb_build_object('ok', true, 'id', v_id);
exception when unique_violation then raise exception 'Já existe uma escala para este evento.' using errcode = '23505';
end $$;


--
-- Name: midia_decidir_servico(uuid, uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.midia_decidir_servico(p_solicitacao uuid, p_servico uuid, p_decisao text, p_detalhe text, p_motivo text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare s public.apoio_solicitacoes;
begin
  select * into s from public.apoio_solicitacoes where id = p_solicitacao for update;
  if not found then raise exception 'Solicitação não encontrada.' using errcode = 'P0002'; end if;
  if not public.escala_lider(s.ministerio_alvo) then raise exception 'Somente a liderança de Mídia decide os serviços.' using errcode = '42501'; end if;
  if s.status in ('recusada','cancelada') then raise exception 'Solicitação encerrada.' using errcode = '22023'; end if;
  if p_decisao = 'nao_atender' and char_length(btrim(coalesce(p_motivo, ''))) < 5 then
    raise exception 'Explique por que o serviço não será atendido.' using errcode = '22023'; end if;
  if p_decisao = 'acrescentar' then
    if not exists (select 1 from public.apoio_servicos where id = p_servico and ministerio_id = s.ministerio_alvo and ativo) then raise exception 'Serviço inválido.' using errcode = '22023'; end if;
    insert into public.apoio_solicitacao_servicos (solicitacao_id, servico_id, detalhe, origem, decisao, motivo, decidido_por, decidido_em)
    values (s.id, p_servico, nullif(btrim(p_detalhe), ''), 'acrescentado', 'atender', nullif(btrim(p_motivo), ''), auth.uid(), now())
    on conflict (solicitacao_id, servico_id) do update set decisao = 'atender', decidido_por = auth.uid(), decidido_em = now();
  elsif p_decisao in ('atender','nao_atender') then
    update public.apoio_solicitacao_servicos set decisao = p_decisao, motivo = nullif(btrim(p_motivo), ''), decidido_por = auth.uid(), decidido_em = now()
     where solicitacao_id = s.id and servico_id = p_servico;
    if not found then raise exception 'Serviço não está na solicitação.' using errcode = 'P0002'; end if;
  else raise exception 'Decisão inválida.' using errcode = '22023';
  end if;
  update public.apoio_solicitacoes set status = 'em_analise' where id = s.id and status = 'enviada';
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: midia_decidir_solicitacao(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.midia_decidir_solicitacao(p_solicitacao uuid, p_acao text, p_motivo text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare s public.apoio_solicitacoes; v_status text; v_txt text;
begin
  select * into s from public.apoio_solicitacoes where id = p_solicitacao for update;
  if not found then raise exception 'Solicitação não encontrada.' using errcode = 'P0002'; end if;
  if not public.escala_lider(s.ministerio_alvo) then raise exception 'Somente a liderança de Mídia decide solicitações.' using errcode = '42501'; end if;
  if s.status in ('recusada','cancelada') then raise exception 'Solicitação encerrada.' using errcode = '22023'; end if;
  if p_acao = 'aprovar' then
    -- o que ficou sem decisão é atendido
    update public.apoio_solicitacao_servicos set decisao = 'atender', decidido_por = auth.uid(), decidido_em = now() where solicitacao_id = s.id and decisao is null;
    if not exists (select 1 from public.apoio_solicitacao_servicos where solicitacao_id = s.id and decisao = 'atender') then
      raise exception 'Nenhum serviço será atendido: recuse a solicitação, com o motivo.' using errcode = '22023'; end if;
    v_status := case when exists (select 1 from public.apoio_solicitacao_servicos where solicitacao_id = s.id and decisao = 'nao_atender') then 'aprovada_parcial' else 'aprovada' end;
  elsif p_acao = 'recusar' then
    if char_length(btrim(coalesce(p_motivo, ''))) < 5 then raise exception 'Informe o motivo da recusa.' using errcode = '22023'; end if;
    if exists (select 1 from public.escala_eventos where solicitacao_id = s.id and status = 'publicada') then raise exception 'Cancele a escala publicada antes.' using errcode = '22023'; end if;
    v_status := 'recusada';
  elsif p_acao = 'em_analise' then v_status := 'em_analise';
  else raise exception 'Ação inválida.' using errcode = '22023';
  end if;
  update public.apoio_solicitacoes set status = v_status, decidido_por = case when p_acao <> 'em_analise' then auth.uid() else decidido_por end,
         decidido_em = case when p_acao <> 'em_analise' then now() else decidido_em end, motivo = coalesce(nullif(btrim(p_motivo), ''), motivo) where id = s.id;
  if p_acao <> 'em_analise' then
    v_txt := case v_status when 'aprovada' then 'aprovada' when 'aprovada_parcial' then 'aprovada em parte (veja os serviços)' else 'recusada' end;
    perform public.notificar_unico('soldec:' || s.id || ':' || v_status, s.solicitado_por, 'apoio_decisao', 'Solicitação ' || v_txt,
            s.titulo || coalesce(': ' || nullif(btrim(p_motivo), ''), ''), jsonb_build_object('solicitacao', s.id));
  end if;
  return jsonb_build_object('ok', true, 'status', v_status);
end $$;


--
-- Name: midia_definir_gestor(uuid, uuid, uuid[], boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.midia_definir_gestor(p_ministerio uuid, p_perfil uuid, p_areas uuid[], p_ativo boolean) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare m uuid := coalesce(p_ministerio, public.midia_ministerio_id());
begin
  if not public.escala_lider(m) then raise exception 'Somente a liderança do ministério delega a montagem de escalas.' using errcode = '42501'; end if;
  if not exists (select 1 from public.perfis pf join public.ministerio_membros mm on mm.pessoa_id = pf.pessoa_id where pf.id = p_perfil and pf.ativo and mm.ministerio_id = m and mm.ativo) then
    raise exception 'O gestor precisa ser integrante ativo do ministério, com conta.' using errcode = '22023'; end if;
  insert into public.escala_gestores (ministerio_id, perfil_id, areas, ativo, criado_por) values (m, p_perfil, coalesce(p_areas, '{}'), coalesce(p_ativo, true), auth.uid())
  on conflict (ministerio_id, perfil_id) do update set areas = excluded.areas, ativo = excluded.ativo;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: midia_evento(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.midia_evento(p_escala uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare e public.escala_eventos;
begin
  select * into e from public.escala_eventos where id = p_escala;
  if not found then raise exception 'Escala não encontrada.' using errcode = 'P0002'; end if;
  if not public.escala_gestor(e.ministerio_id) then raise exception 'Acesso restrito à liderança.' using errcode = '42501'; end if;
  return jsonb_build_object('id', e.id, 'titulo', e.titulo, 'inicio', e.inicio, 'fim', e.fim, 'local', e.local, 'status', e.status, 'versao', e.versao,
    'prazo_confirmacao', coalesce(e.prazo_confirmacao, e.inicio - interval '48 hours'), 'orientacoes_gerais', e.orientacoes_gerais, 'evento_id', e.evento_id,
    'solicitacao', case when e.solicitacao_id is not null then public.apoio_solicitacao_json(e.solicitacao_id, true) end,
    'areas', coalesce((select jsonb_agg(jsonb_build_object('area_id', a.id, 'area', a.nome,
        'funcoes', coalesce((select jsonb_agg(jsonb_build_object('id', ef.id, 'funcao_id', f.id, 'funcao', f.nome, 'quantidade_referencia', ef.quantidade_referencia,
            'orientacoes', ef.orientacoes, 'hora_inicio', ef.hora_inicio, 'hora_fim', ef.hora_fim,
            'ativos', (select count(*) from public.escala_participacoes p where p.evento_funcao_id = ef.id and p.status in ('rascunho','aguardando','confirmado')),
            'confirmados', (select count(*) from public.escala_participacoes p where p.evento_funcao_id = ef.id and p.status = 'confirmado'),
            'vagas_abertas', (select count(*) from public.escala_participacoes p where p.evento_funcao_id = ef.id and p.vaga_aberta),
            'participacoes', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'pessoa_id', p.pessoa_id, 'nome', x.nome, 'status', p.status, 'papel', p.papel,
                'atividade', p.atividade, 'inicio', p.inicio, 'fim', p.fim, 'orientacoes_individuais', p.orientacoes_individuais, 'observacao_lider', p.observacao_lider,
                'versao', p.versao, 'prazo', p.prazo, 'respondido_em', p.respondido_em, 'motivo_recusa', p.motivo_recusa, 'vaga_aberta', p.vaga_aberta,
                'atrasada', p.status = 'aguardando' and p.prazo < now(), 'presenca', p.presenca, 'alertas_cientes', p.alertas_cientes, 'substitui_id', p.substitui_id,
                'motivo_cancelamento', p.motivo_cancelamento) order by case p.status when 'confirmado' then 0 when 'aguardando' then 1 when 'rascunho' then 2 else 3 end, x.nome)
              from public.escala_participacoes p join public.pessoas x on x.id = p.pessoa_id where p.evento_funcao_id = ef.id), '[]'::jsonb)) order by f.ordem, f.nome)
          from public.escala_evento_funcoes ef join public.escala_funcoes f on f.id = ef.funcao_id where ef.escala_evento_id = e.id and ef.removida_em is null and f.area_id = a.id), '[]'::jsonb),
        'usada', exists (select 1 from public.escala_evento_funcoes ef join public.escala_funcoes f on f.id = ef.funcao_id where ef.escala_evento_id = e.id and ef.removida_em is null and f.area_id = a.id))
        order by a.ordem, a.nome)
      from public.escala_areas a where a.ministerio_id = e.ministerio_id and a.ativo), '[]'::jsonb));
end $$;


--
-- Name: midia_habilitar(uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.midia_habilitar(p_pessoa uuid, p_funcao uuid, p_status text, p_observacao text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare m uuid;
begin
  select a.ministerio_id into m from public.escala_funcoes f join public.escala_areas a on a.id = f.area_id where f.id = p_funcao;
  if m is null then raise exception 'Função não encontrada.' using errcode = 'P0002'; end if;
  if not public.escala_lider(m) then raise exception 'Somente a liderança do ministério habilita voluntários.' using errcode = '42501'; end if;
  if p_status not in ('habilitado','em_treinamento','suspenso') then raise exception 'Situação inválida.' using errcode = '22023'; end if;
  if not exists (select 1 from public.ministerio_membros where pessoa_id = p_pessoa and ministerio_id = m and ativo) then
    raise exception 'A pessoa precisa ser integrante ativa do ministério.' using errcode = '22023'; end if;
  insert into public.voluntario_habilitacoes (pessoa_id, funcao_id, status, autorizado_por, observacao)
  values (p_pessoa, p_funcao, p_status, auth.uid(), nullif(btrim(p_observacao), ''))
  on conflict (pessoa_id, funcao_id) do update set status = excluded.status, autorizado_por = excluded.autorizado_por, observacao = excluded.observacao,
    desde = case when public.voluntario_habilitacoes.status = excluded.status then public.voluntario_habilitacoes.desde else current_date end, atualizado_em = now();
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: midia_ministerio_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.midia_ministerio_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$ select id from public.ministerios where slug = 'midia' $$;


--
-- Name: midia_painel(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.midia_painel(p_filtros jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare m uuid := coalesce(nullif(p_filtros->>'ministerio_id', '')::uuid, public.midia_ministerio_id());
        de timestamptz := coalesce(nullif(p_filtros->>'de', '')::date, current_date - 7)::timestamp at time zone 'America/Sao_Paulo';
        ate timestamptz := (coalesce(nullif(p_filtros->>'ate', '')::date, current_date + 60) + 1)::timestamp at time zone 'America/Sao_Paulo';
begin
  if not public.escala_gestor(m) then raise exception 'Acesso restrito à liderança de Mídia.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'resumo', jsonb_build_object(
      'solicitacoes_abertas', (select count(*) from public.apoio_solicitacoes where ministerio_alvo = m and status in ('enviada','em_analise','aguardando_informacoes')),
      'aguardando_confirmacao', (select count(*) from public.escala_participacoes p join public.escala_eventos e on e.id = p.escala_evento_id where e.ministerio_id = m and e.status = 'publicada' and p.status = 'aguardando'),
      'atrasadas', (select count(*) from public.escala_participacoes p join public.escala_eventos e on e.id = p.escala_evento_id where e.ministerio_id = m and e.status = 'publicada' and p.status = 'aguardando' and p.prazo < now()),
      'confirmados', (select count(*) from public.escala_participacoes p join public.escala_eventos e on e.id = p.escala_evento_id where e.ministerio_id = m and e.status = 'publicada' and p.status = 'confirmado' and e.fim > now()),
      'recusas', (select count(*) from public.escala_participacoes p join public.escala_eventos e on e.id = p.escala_evento_id where e.ministerio_id = m and e.status = 'publicada' and p.status = 'recusado' and e.fim > now()),
      'substituicoes', (select count(*) from public.escala_participacoes p join public.escala_eventos e on e.id = p.escala_evento_id where e.ministerio_id = m and e.status in ('planejamento','publicada') and p.vaga_aberta),
      'indisponiveis_semana', (select count(distinct i.pessoa_id) from public.voluntario_indisponibilidades i join public.ministerio_membros mm on mm.pessoa_id = i.pessoa_id and mm.ministerio_id = m and mm.ativo
                                where daterange(i.inicio, i.fim, '[]') && daterange(current_date, current_date + 7, '[]'))),
    'eventos', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'titulo', e.titulo, 'inicio', e.inicio, 'fim', e.fim, 'local', e.local, 'status', e.status,
        'solicitante', (select mi.nome from public.apoio_solicitacoes s join public.ministerios mi on mi.id = s.ministerio_solicitante where s.id = e.solicitacao_id),
        'funcoes', (select count(*) from public.escala_evento_funcoes ef where ef.escala_evento_id = e.id and ef.removida_em is null),
        'escalados', (select count(*) from public.escala_participacoes p where p.escala_evento_id = e.id and p.status in ('rascunho','aguardando','confirmado')),
        'confirmados', (select count(*) from public.escala_participacoes p where p.escala_evento_id = e.id and p.status = 'confirmado'),
        'aguardando', (select count(*) from public.escala_participacoes p where p.escala_evento_id = e.id and p.status = 'aguardando'),
        'vagas_abertas', (select count(*) from public.escala_participacoes p where p.escala_evento_id = e.id and p.vaga_aberta),
        'funcoes_vazias', (select count(*) from public.escala_evento_funcoes ef where ef.escala_evento_id = e.id and ef.removida_em is null
                            and not exists (select 1 from public.escala_participacoes p where p.evento_funcao_id = ef.id and p.status in ('rascunho','aguardando','confirmado'))),
        'abaixo_referencia', (select count(*) from public.escala_evento_funcoes ef where ef.escala_evento_id = e.id and ef.removida_em is null and ef.quantidade_referencia is not null
                            and ef.quantidade_referencia > (select count(*) from public.escala_participacoes p where p.evento_funcao_id = ef.id and p.status in ('rascunho','aguardando','confirmado')))) order by e.inicio)
      from public.escala_eventos e where e.ministerio_id = m and e.inicio < ate and e.fim >= de
        and (p_filtros->>'status' is null or e.status = p_filtros->>'status')
        and (p_filtros->>'busca' is null or e.titulo ilike '%' || (p_filtros->>'busca') || '%')
        and (p_filtros->>'funcao_id' is null or exists (select 1 from public.escala_evento_funcoes ef where ef.escala_evento_id = e.id and ef.funcao_id = (p_filtros->>'funcao_id')::uuid and ef.removida_em is null))
        and (p_filtros->>'pessoa_id' is null or exists (select 1 from public.escala_participacoes p where p.escala_evento_id = e.id and p.pessoa_id = (p_filtros->>'pessoa_id')::uuid))
        and (p_filtros->>'confirmacao' is null or exists (select 1 from public.escala_participacoes p where p.escala_evento_id = e.id and p.status = p_filtros->>'confirmacao'))
        and (p_filtros->>'solicitante' is null or exists (select 1 from public.apoio_solicitacoes s where s.id = e.solicitacao_id and s.ministerio_solicitante = (p_filtros->>'solicitante')::uuid))), '[]'::jsonb),
    'agenda_pendentes', public.midia_agenda_pendentes());
end $$;


--
-- Name: midia_registrar_capacitacao(uuid, uuid, text, date, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.midia_registrar_capacitacao(p_pessoa uuid, p_funcao uuid, p_titulo text, p_data date, p_carga text, p_observacao text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare m uuid := public.midia_ministerio_id();
begin
  if p_funcao is not null then select a.ministerio_id into m from public.escala_funcoes f join public.escala_areas a on a.id = f.area_id where f.id = p_funcao; end if;
  if not public.escala_lider(m) then raise exception 'Somente a liderança do ministério registra capacitações.' using errcode = '42501'; end if;
  insert into public.voluntario_capacitacoes (pessoa_id, funcao_id, titulo, realizada_em, carga, observacao, registrado_por)
  values (p_pessoa, p_funcao, btrim(p_titulo), p_data, nullif(btrim(p_carga), ''), nullif(btrim(p_observacao), ''), auth.uid());
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: midia_relatorio(date, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.midia_relatorio(p_de date, p_ate date, p_agrupar text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare m uuid := public.midia_ministerio_id();
begin
  if not public.escala_gestor(m) then raise exception 'Acesso restrito à liderança de Mídia.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('chave', chave, 'escalados', esc, 'confirmaram', conf, 'recusaram', rec, 'serviram', serv, 'faltaram', falt) order by esc desc, chave)
    from (select case p_agrupar when 'funcao' then f.nome when 'evento' then e.titulo || ' · ' || to_char(e.inicio at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') else x.nome end chave,
                 count(*) esc,
                 count(*) filter (where exists (select 1 from public.escala_historico h where h.participacao_id = p.id and h.acao = 'confirmou')) conf,
                 count(*) filter (where exists (select 1 from public.escala_historico h where h.participacao_id = p.id and h.acao = 'recusou')) rec,
                 count(*) filter (where p.presenca in ('presente','parcial')) serv,
                 count(*) filter (where p.presenca = 'ausente') falt
            from public.escala_participacoes p join public.escala_eventos e on e.id = p.escala_evento_id join public.pessoas x on x.id = p.pessoa_id
            join public.escala_evento_funcoes ef on ef.id = p.evento_funcao_id join public.escala_funcoes f on f.id = ef.funcao_id
           where e.ministerio_id = m and e.status <> 'cancelada' and p.status <> 'rascunho'
             and e.inicio >= p_de::timestamp at time zone 'America/Sao_Paulo' and e.inicio < (p_ate + 1)::timestamp at time zone 'America/Sao_Paulo'
           group by 1) r), '[]'::jsonb);
end $$;


--
-- Name: midia_salvar_catalogo(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.midia_salvar_catalogo(p_tipo text, p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare m uuid := coalesce(nullif(p->>'ministerio_id', '')::uuid, public.midia_ministerio_id()); v_id uuid := nullif(p->>'id', '')::uuid; a public.escala_areas;
begin
  if p_tipo = 'funcao' then
    select * into a from public.escala_areas where id = (p->>'area_id')::uuid;
    if not found then raise exception 'Equipe não encontrada.' using errcode = 'P0002'; end if;
    m := a.ministerio_id;
  end if;
  if not public.escala_lider(m) then raise exception 'Somente a liderança do ministério gerencia o catálogo.' using errcode = '42501'; end if;
  if p_tipo = 'servico' then
    if v_id is null then insert into public.apoio_servicos (ministerio_id, nome, descricao, ativo, ordem) values (m, btrim(p->>'nome'), nullif(btrim(p->>'descricao'), ''), coalesce((p->>'ativo')::boolean, true), coalesce((p->>'ordem')::int, 99)) returning id into v_id;
    else update public.apoio_servicos set nome = btrim(p->>'nome'), descricao = nullif(btrim(p->>'descricao'), ''), ativo = coalesce((p->>'ativo')::boolean, ativo) where id = v_id and ministerio_id = m; end if;
    if p ? 'funcoes' then
      delete from public.apoio_servico_funcoes where servico_id = v_id;
      insert into public.apoio_servico_funcoes select v_id, x::uuid from jsonb_array_elements_text(p->'funcoes') x on conflict do nothing;
    end if;
  elsif p_tipo = 'area' then
    if v_id is null then insert into public.escala_areas (ministerio_id, nome, ativo, ordem) values (m, btrim(p->>'nome'), coalesce((p->>'ativo')::boolean, true), coalesce((p->>'ordem')::int, 99)) returning id into v_id;
    else update public.escala_areas set nome = btrim(p->>'nome'), ativo = coalesce((p->>'ativo')::boolean, ativo) where id = v_id and ministerio_id = m; end if;
  elsif p_tipo = 'funcao' then
    if v_id is null then
      insert into public.escala_funcoes (area_id, nome, exige_habilitacao, aceita_em_treinamento, quantidade_referencia, orientacao_padrao, ativo, ordem)
      values (a.id, btrim(p->>'nome'), coalesce((p->>'exige_habilitacao')::boolean, true), coalesce((p->>'aceita_em_treinamento')::boolean, true),
              nullif(p->>'quantidade_referencia', '')::int, nullif(btrim(p->>'orientacao_padrao'), ''), coalesce((p->>'ativo')::boolean, true), coalesce((p->>'ordem')::int, 99)) returning id into v_id;
    else
      update public.escala_funcoes set nome = btrim(p->>'nome'), exige_habilitacao = coalesce((p->>'exige_habilitacao')::boolean, exige_habilitacao),
        aceita_em_treinamento = coalesce((p->>'aceita_em_treinamento')::boolean, aceita_em_treinamento), quantidade_referencia = nullif(p->>'quantidade_referencia', '')::int,
        orientacao_padrao = nullif(btrim(p->>'orientacao_padrao'), ''), ativo = coalesce((p->>'ativo')::boolean, ativo), area_id = a.id where id = v_id;
    end if;
  else raise exception 'Tipo inválido.' using errcode = '22023';
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
exception when unique_violation then raise exception 'Já existe um item com esse nome.' using errcode = '23505';
end $$;


--
-- Name: midia_solicitacoes(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.midia_solicitacoes(p_filtros jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare m uuid := coalesce(nullif(p_filtros->>'ministerio_id', '')::uuid, public.midia_ministerio_id());
begin
  if not public.escala_gestor(m) then raise exception 'Acesso restrito à liderança de Mídia.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(public.apoio_solicitacao_json(s.id, true) order by s.inicio) from public.apoio_solicitacoes s
    where s.ministerio_alvo = m
      and (p_filtros->>'status' is null or s.status = p_filtros->>'status' or (p_filtros->>'status' = 'abertas' and s.status in ('enviada','em_analise','aguardando_informacoes')))
      and (p_filtros->>'de' is null or s.fim >= (p_filtros->>'de')::date) and (p_filtros->>'ate' is null or s.inicio < (p_filtros->>'ate')::date + 1)
      and (p_filtros->>'solicitante' is null or s.ministerio_solicitante = (p_filtros->>'solicitante')::uuid)), '[]'::jsonb);
end $$;


--
-- Name: midia_voluntarios(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.midia_voluntarios(p_ministerio uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare m uuid := coalesce(p_ministerio, public.midia_ministerio_id());
begin
  if not public.escala_gestor(m) then raise exception 'Acesso restrito à liderança do ministério.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('pessoa_id', pe.id, 'nome', pe.nome, 'telefone', pe.telefone, 'funcao_ministerio', mm.funcao,
      'tem_conta', exists (select 1 from public.perfis pf where pf.pessoa_id = pe.id and pf.ativo),
      'habilitacoes', coalesce((select jsonb_agg(jsonb_build_object('funcao_id', h.funcao_id, 'funcao', f.nome, 'status', h.status, 'desde', h.desde, 'observacao', h.observacao) order by f.nome)
          from public.voluntario_habilitacoes h join public.escala_funcoes f on f.id = h.funcao_id where h.pessoa_id = pe.id), '[]'::jsonb),
      'capacitacoes', coalesce((select jsonb_agg(jsonb_build_object('titulo', c.titulo, 'realizada_em', c.realizada_em, 'carga', c.carga) order by c.realizada_em desc)
          from public.voluntario_capacitacoes c where c.pessoa_id = pe.id), '[]'::jsonb),
      'disponibilidade', coalesce((select jsonb_agg(jsonb_build_object('dia', d.dia_semana, 'de', to_char(d.hora_inicio, 'HH24:MI'), 'ate', to_char(d.hora_fim, 'HH24:MI')) order by d.dia_semana, d.hora_inicio)
          from public.voluntario_disponibilidade d where d.pessoa_id = pe.id), '[]'::jsonb),
      'indisponibilidades', coalesce((select jsonb_agg(jsonb_build_object('inicio', i.inicio, 'fim', i.fim, 'tipo', i.tipo, 'motivo', i.motivo) order by i.inicio)
          from public.voluntario_indisponibilidades i where i.pessoa_id = pe.id and i.fim >= current_date), '[]'::jsonb),
      'preferencias', (select jsonb_build_object('funcoes', vp.funcoes, 'observacoes', vp.observacoes) from public.voluntario_preferencias vp where vp.pessoa_id = pe.id),
      'escalas_60_dias', (select count(*) from public.escala_participacoes p join public.escala_eventos e on e.id = p.escala_evento_id
          where p.pessoa_id = pe.id and p.status in ('aguardando','confirmado') and e.inicio > now() - interval '60 days' and e.status <> 'cancelada'),
      'serviu_total', (select count(*) from public.escala_participacoes p where p.pessoa_id = pe.id and p.presenca in ('presente','parcial'))) order by pe.nome)
    from public.ministerio_membros mm join public.pessoas pe on pe.id = mm.pessoa_id where mm.ministerio_id = m and mm.ativo and pe.arquivado_em is null), '[]'::jsonb);
end $$;


--
-- Name: minha_candidatura(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.minha_candidatura(p_protocolo text, p_chave text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.inscricoes := public.link_inscricao(p_protocolo, p_chave); v uuid;
begin
  select id into v from public.voluntariado_candidaturas where pessoa_id = i.pessoa_id order by criado_em desc limit 1;
  if v is null then return null; end if;
  return (public.candidatura_json(v) - 'telefone' - 'email' - 'pessoa_id')
    || jsonb_build_object('ministerios', (select jsonb_agg(jsonb_build_object('id', id, 'nome', nome) order by ordem, nome) from public.ministerios where ativo),
                          'termo', public.termos_vigentes()->'voluntariado');
end $$;


--
-- Name: minha_disponibilidade(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.minha_disponibilidade() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare me uuid := public.minha_pessoa_id();
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'semana', coalesce((select jsonb_agg(jsonb_build_object('dia', d.dia_semana, 'de', to_char(d.hora_inicio, 'HH24:MI'), 'ate', to_char(d.hora_fim, 'HH24:MI')) order by d.dia_semana, d.hora_inicio)
        from public.voluntario_disponibilidade d where d.pessoa_id = me), '[]'::jsonb),
    'indisponibilidades', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'inicio', i.inicio, 'fim', i.fim, 'tipo', i.tipo, 'motivo', i.motivo) order by i.inicio)
        from public.voluntario_indisponibilidades i where i.pessoa_id = me and i.fim >= current_date), '[]'::jsonb),
    'preferencias', coalesce((select jsonb_build_object('funcoes', vp.funcoes, 'observacoes', vp.observacoes) from public.voluntario_preferencias vp where vp.pessoa_id = me), '{"funcoes":[]}'::jsonb),
    'habilitacoes', coalesce((select jsonb_agg(jsonb_build_object('funcao_id', f.id, 'funcao', f.nome, 'area', a.nome, 'status', h.status, 'desde', h.desde) order by a.ordem, f.ordem)
        from public.voluntario_habilitacoes h join public.escala_funcoes f on f.id = h.funcao_id join public.escala_areas a on a.id = f.area_id where h.pessoa_id = me), '[]'::jsonb),
    'capacitacoes', coalesce((select jsonb_agg(jsonb_build_object('titulo', c.titulo, 'realizada_em', c.realizada_em, 'carga', c.carga) order by c.realizada_em desc)
        from public.voluntario_capacitacoes c where c.pessoa_id = me), '[]'::jsonb),
    'funcoes_disponiveis', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'nome', f.nome, 'area', a.nome) order by a.ordem, f.ordem)
        from public.escala_funcoes f join public.escala_areas a on a.id = f.area_id join public.ministerio_membros mm on mm.ministerio_id = a.ministerio_id
        where mm.pessoa_id = me and mm.ativo and f.ativo and a.ativo), '[]'::jsonb));
end $$;


--
-- Name: minha_equipe(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.minha_equipe() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'ministerio_id', m.id, 'ministerio', m.nome, 'sou_lider', public.lider_de(m.id),
      'membros', (select coalesce(jsonb_agg(jsonb_build_object(
                    'nome', pe.nome, 'funcao', mm2.funcao,
                    'telefone', case when public.lider_de(m.id) then pe.telefone end,
                    'email', case when public.lider_de(m.id) then pe.email end) order by mm2.funcao, pe.nome), '[]'::jsonb)
                  from public.ministerio_membros mm2 join public.pessoas pe on pe.id = mm2.pessoa_id
                  where mm2.ministerio_id = m.id and mm2.ativo and pe.arquivado_em is null)) order by m.ordem, m.nome)
    from public.ministerio_membros mm join public.ministerios m on m.id = mm.ministerio_id
    where mm.pessoa_id = public.minha_pessoa_id() and mm.ativo and m.ativo), '[]'::jsonb);
end $$;


--
-- Name: minha_indisponibilidade(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.minha_indisponibilidade(p_acao text, p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare me uuid := public.minha_pessoa_id(); v uuid;
begin
  if not public.perfil_ativo() or me is null then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  if p_acao = 'incluir' then
    if (p->>'fim')::date < current_date then raise exception 'O período já passou.' using errcode = '22023'; end if;
    insert into public.voluntario_indisponibilidades (pessoa_id, inicio, fim, tipo, motivo)
    values (me, (p->>'inicio')::date, coalesce(nullif(p->>'fim', '')::date, (p->>'inicio')::date), coalesce(p->>'tipo', 'data'), nullif(btrim(p->>'motivo'), '')) returning id into v;
    return jsonb_build_object('ok', true, 'id', v);
  elsif p_acao = 'remover' then
    delete from public.voluntario_indisponibilidades where id = (p->>'id')::uuid and pessoa_id = me;
    if not found then raise exception 'Não encontrada.' using errcode = 'P0002'; end if;
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'Ação inválida.' using errcode = '22023';
exception when check_violation then raise exception 'Período inválido.' using errcode = '22023';
end $$;


--
-- Name: minha_inscricao_curso(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.minha_inscricao_curso(p_protocolo text, p_chave text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.inscricoes; v_pos integer;
begin
  select * into i from public.inscricoes where id = public.servico_validar_link(p_protocolo, p_chave);
  if not found then raise exception 'Inscrição não encontrada. Confira o link recebido.' using errcode = 'P0002'; end if;
  if i.status = 'lista_espera' then
    select count(*) into v_pos from public.inscricoes where turma_id = i.turma_id and status = 'lista_espera' and (criado_em, protocolo) <= (i.criado_em, i.protocolo);
  end if;
  return (select jsonb_build_object('protocolo', i.protocolo, 'status', i.status, 'posicao_espera', v_pos,
      'nome', pe.nome, 'curso', c.titulo, 'curso_slug', c.slug, 'turma', public.cursos_json_turma(t), 'criado_em', i.criado_em, 'valor_final', i.valor_final,
      'financeiro', public.financeiro_inscricao(i.id),
      'pagamentos', coalesce((select jsonb_agg(jsonb_build_object('status', p.status, 'valor', p.valor, 'metodo', p.metodo, 'registrado_em', p.registrado_em,
                     'analisado_em', p.analisado_em, 'mensagem', case when p.status in ('recusado','novo_comprovante_solicitado') then p.observacao_analise end) order by p.registrado_em)
                    from public.pagamentos p where p.inscricao_id = i.id and p.status <> 'cancelado'), '[]'::jsonb),
      'certificado', (select jsonb_build_object('status', ce.status, 'cerimonia', cm.titulo, 'data', cm.data, 'local', cm.local)
                      from public.certificados ce left join public.cerimonias cm on cm.id = ce.cerimonia_id where ce.inscricao_id = i.id and ce.status <> 'cancelado'))
    from public.turmas t join public.cursos c on c.id = t.curso_id join public.pessoas pe on pe.id = i.pessoa_id where t.id = i.turma_id);
end $$;


--
-- Name: minha_pessoa_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.minha_pessoa_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select p.pessoa_id from public.perfis p where p.id = auth.uid()
$$;


--
-- Name: minhas_escalas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.minhas_escalas() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare me uuid := public.minha_pessoa_id();
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'status', p.status, 'versao', p.versao, 'papel', p.papel, 'atividade', p.atividade,
      'orientacoes_individuais', p.orientacoes_individuais, 'prazo', p.prazo, 'respondido_em', p.respondido_em, 'motivo_recusa', p.motivo_recusa,
      'atrasada', p.status = 'aguardando' and p.prazo < now(), 'presenca', p.presenca, 'motivo_cancelamento', p.motivo_cancelamento,
      'inicio', per.inicio, 'fim', per.fim, 'funcao', f.nome, 'area', a.nome, 'orientacoes_funcao', ef.orientacoes,
      'evento', jsonb_build_object('id', e.id, 'titulo', e.titulo, 'local', e.local, 'status', e.status, 'orientacoes', e.orientacoes_gerais,
         'ministerio', (select nome from public.ministerios where id = e.ministerio_id),
         'responsavel', (select x.nome from public.perfis pf join public.pessoas x on x.id = pf.pessoa_id where pf.id = coalesce(p.criado_por, e.criado_por))),
      -- equipe do evento: só nomes e funções (sem contatos)
      'equipe', (select jsonb_agg(jsonb_build_object('nome', x.nome, 'funcao', f2.nome) order by f2.ordem, x.nome)
                 from public.escala_participacoes q join public.pessoas x on x.id = q.pessoa_id join public.escala_evento_funcoes ef2 on ef2.id = q.evento_funcao_id
                 join public.escala_funcoes f2 on f2.id = ef2.funcao_id where q.escala_evento_id = e.id and q.status in ('aguardando','confirmado')))
      order by per.inicio desc)
    from public.escala_participacoes p join public.escala_eventos e on e.id = p.escala_evento_id
    join public.escala_evento_funcoes ef on ef.id = p.evento_funcao_id join public.escala_funcoes f on f.id = ef.funcao_id join public.escala_areas a on a.id = f.area_id
    cross join lateral public.participacao_periodo(p) per
    where p.pessoa_id = me and p.status <> 'rascunho'), '[]'::jsonb);
end $$;


--
-- Name: minhas_notificacoes(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.minhas_notificacoes(p_limite integer DEFAULT 50) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select jsonb_build_object(
    'nao_lidas', (select count(*) from public.notificacoes n where not (auth.uid() = any(n.lida_por))
                    and (n.para_usuario = auth.uid() or (n.para_atribuicao = 'SECRETARIA' and public.e_secretaria()) or (n.para_atribuicao = 'TESOURARIA' and public.e_tesouraria()))),
    'itens', coalesce((select jsonb_agg(x) from (select jsonb_build_object('id', n.id, 'tipo', n.tipo, 'titulo', n.titulo, 'mensagem', n.mensagem, 'ref', n.ref,
               'para', n.para_atribuicao, 'criado_em', n.criado_em, 'lida', auth.uid() = any(n.lida_por)) as x
             from public.notificacoes n
             where public.perfil_ativo() and (n.para_usuario = auth.uid() or (n.para_atribuicao = 'SECRETARIA' and public.e_secretaria()) or (n.para_atribuicao = 'TESOURARIA' and public.e_tesouraria()))
             order by n.id desc limit least(greatest(coalesce(p_limite, 50), 1), 200)) t), '[]'::jsonb))
$$;


--
-- Name: ministerio_admin_obter(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ministerio_admin_obter(p_ministerio uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_m public.ministerios; v_pg public.ministerio_paginas; v_master boolean := public.e_master();
begin
  if not (v_master or public.lider_de(p_ministerio)) then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  select * into v_m from public.ministerios where id = p_ministerio;
  if v_m.id is null then raise exception 'Ministério não encontrado.' using errcode = 'P0002'; end if;
  select * into v_pg from public.ministerio_paginas where ministerio_id = p_ministerio;
  return jsonb_build_object('id', v_m.id, 'nome', v_m.nome, 'slug', v_m.slug, 'descricao', v_m.descricao, 'ativo', v_m.ativo, 'ordem', v_m.ordem,
    'pode_administrar', v_master,
    'pagina', jsonb_build_object('o_que_fazemos', v_pg.o_que_fazemos, 'por_que_existimos', v_pg.por_que_existimos, 'missao', v_pg.missao,
       'complemento', v_pg.complemento, 'foto', v_pg.foto, 'foto_alt', v_pg.foto_alt, 'exibir_publico', v_pg.exibir_publico,
       'exibir_lider', v_pg.exibir_lider, 'textos_confirmados', v_pg.textos_confirmados, 'confirmados_em', v_pg.confirmados_em,
       'vice_pessoa_id', v_pg.vice_pessoa_id, 'vice_nome', (select nome from public.pessoas where id = v_pg.vice_pessoa_id)),
    'integrantes', coalesce((select jsonb_agg(jsonb_build_object('pessoa_id', pe.id, 'nome', pe.nome, 'funcao', mm.funcao, 'cargo', mm.cargo,
         'ativo', mm.ativo, 'desde', mm.desde, 'tem_acesso', exists (select 1 from public.perfis p where p.pessoa_id = pe.id),
         'perfil', (select p.perfil from public.perfis p where p.pessoa_id = pe.id))
         order by mm.ativo desc, (mm.funcao = 'lider') desc, pe.nome)
       from public.ministerio_membros mm join public.pessoas pe on pe.id = mm.pessoa_id where mm.ministerio_id = p_ministerio), '[]'::jsonb),
    'historico', coalesce((select jsonb_agg(jsonb_build_object('quando', a.quando, 'acao', a.acao, 'tabela', a.tabela,
         'antes', a.antes - array['criado_em','atualizado_em','atualizado_por'], 'depois', a.depois - array['criado_em','atualizado_em','atualizado_por'],
         'pessoa', (select nome from public.pessoas where id = coalesce(a.depois->>'pessoa_id', a.antes->>'pessoa_id')::uuid),
         'ator', (select pe.nome from public.perfis p join public.pessoas pe on pe.id = p.pessoa_id where p.id = a.ator)) order by a.id desc)
       from (select * from public.auditoria a
             where (a.tabela = 'ministerio_membros' and coalesce(a.depois->>'ministerio_id', a.antes->>'ministerio_id') = p_ministerio::text)
                or (a.tabela = 'ministerio_paginas' and coalesce(a.depois->>'ministerio_id', a.antes->>'ministerio_id') = p_ministerio::text)
                or (a.tabela = 'ministerios' and a.registro = p_ministerio::text)
             order by a.id desc limit 60) a), '[]'::jsonb));
end $$;


--
-- Name: ministerio_definir_cargo(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ministerio_definir_cargo(p_ministerio uuid, p_pessoa uuid, p_cargo text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not (public.e_master() or public.lider_de(p_ministerio)) then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  update public.ministerio_membros set cargo = public.texto_limpo(p_cargo, 80) where ministerio_id = p_ministerio and pessoa_id = p_pessoa;
  if not found then raise exception 'Vínculo não encontrado.' using errcode = 'P0002'; end if;
  return public.ministerio_admin_obter(p_ministerio);
end $$;


--
-- Name: ministerio_definir_lideranca(uuid, uuid[], uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ministerio_definir_lideranca(p_ministerio uuid, p_lideres uuid[], p_vice uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r record; v_p uuid;
begin
  if not public.e_master() then raise exception 'Somente o MASTER define a liderança.' using errcode = '42501'; end if;
  if not exists (select 1 from public.ministerios where id = p_ministerio) then raise exception 'Ministério não encontrado.' using errcode = 'P0002'; end if;
  if coalesce(cardinality(p_lideres), 0) = 0 then raise exception 'Escolha pelo menos um líder.' using errcode = '22023'; end if;
  foreach v_p in array p_lideres loop
    if not exists (select 1 from public.perfis where pessoa_id = v_p) then
      raise exception 'O líder precisa ser um usuário cadastrado no sistema.' using errcode = '22023'; end if;
  end loop;
  if p_vice is not null and not exists (select 1 from public.perfis where pessoa_id = p_vice) then
    raise exception 'O vice-líder precisa ser um usuário cadastrado no sistema.' using errcode = '22023'; end if;
  if p_vice = any(p_lideres) then raise exception 'A mesma pessoa não pode ser líder e vice.' using errcode = '22023'; end if;
  -- quem deixa a liderança continua no ministério como voluntário, se cumprir os requisitos; senão o vínculo é encerrado (fica no histórico)
  for r in select id from public.ministerio_membros where ministerio_id = p_ministerio and funcao = 'lider' and ativo and not (pessoa_id = any(p_lideres)) loop
    begin
      update public.ministerio_membros set funcao = 'voluntario' where id = r.id;
    exception when check_violation then
      update public.ministerio_membros set ativo = false where id = r.id;
    end;
  end loop;
  foreach v_p in array p_lideres loop
    insert into public.ministerio_membros (pessoa_id, ministerio_id, funcao, ativo) values (v_p, p_ministerio, 'lider', true)
      on conflict (pessoa_id, ministerio_id) do update set funcao = 'lider', ativo = true;
  end loop;
  update public.ministerio_paginas set vice_pessoa_id = p_vice, atualizado_por = auth.uid() where ministerio_id = p_ministerio;
  if p_vice is not null then
    update public.ministerio_membros set cargo = coalesce(cargo, 'Vice-líder') where ministerio_id = p_ministerio and pessoa_id = p_vice;
  end if;
  return public.ministerio_admin_obter(p_ministerio);
end $$;


--
-- Name: ministerio_desvincular(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ministerio_desvincular(p_ministerio uuid, p_pessoa uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_funcao text;
begin
  if not (public.e_master() or public.lider_de(p_ministerio)) then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  select funcao into v_funcao from public.ministerio_membros where ministerio_id = p_ministerio and pessoa_id = p_pessoa and ativo;
  if v_funcao is null then raise exception 'Vínculo não encontrado.' using errcode = 'P0002'; end if;
  if v_funcao = 'lider' and not public.e_master() then raise exception 'Somente o MASTER altera a liderança.' using errcode = '42501'; end if;
  update public.ministerio_membros set ativo = false where ministerio_id = p_ministerio and pessoa_id = p_pessoa;
  update public.ministerio_paginas set vice_pessoa_id = null where ministerio_id = p_ministerio and vice_pessoa_id = p_pessoa;
  return public.ministerio_admin_obter(p_ministerio);
end $$;


--
-- Name: ministerio_paginas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ministerio_paginas (
    ministerio_id uuid NOT NULL,
    o_que_fazemos text,
    por_que_existimos text,
    missao text,
    complemento text,
    vice_pessoa_id uuid,
    foto text,
    foto_alt text,
    exibir_publico boolean DEFAULT true NOT NULL,
    exibir_lider boolean DEFAULT false NOT NULL,
    textos_confirmados boolean DEFAULT false NOT NULL,
    confirmados_em timestamp with time zone,
    confirmados_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_por uuid,
    CONSTRAINT ministerio_paginas_complemento_check CHECK ((char_length(complemento) <= 3000)),
    CONSTRAINT ministerio_paginas_foto_alt_check CHECK ((char_length(foto_alt) <= 200)),
    CONSTRAINT ministerio_paginas_foto_check CHECK (((foto IS NULL) OR (foto ~ '^(img/[a-z0-9._/-]+|site/[a-z0-9-]+/[0-9a-f-]{36}(/[0-9a-f-]{36})?\.(jpg|png|webp))$'::text))),
    CONSTRAINT ministerio_paginas_missao_check CHECK ((char_length(missao) <= 2000)),
    CONSTRAINT ministerio_paginas_o_que_fazemos_check CHECK ((char_length(o_que_fazemos) <= 2000)),
    CONSTRAINT ministerio_paginas_por_que_existimos_check CHECK ((char_length(por_que_existimos) <= 2000))
);


--
-- Name: ministerios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ministerios (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    slug text NOT NULL,
    descricao text,
    ativo boolean DEFAULT true NOT NULL,
    ordem integer DEFAULT 0 NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ministerios_descricao_check CHECK ((char_length(descricao) <= 600)),
    CONSTRAINT ministerios_nome_check CHECK (((char_length(btrim(nome)) >= 2) AND (char_length(btrim(nome)) <= 80))),
    CONSTRAINT ministerios_slug_check CHECK ((slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::text))
);


--
-- Name: ministerio_pagina_publica_json(public.ministerios, public.ministerio_paginas); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ministerio_pagina_publica_json(p_m public.ministerios, p_pg public.ministerio_paginas) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select jsonb_build_object('id', p_m.id, 'slug', p_m.slug, 'nome', p_m.nome, 'descricao', p_m.descricao, 'ordem', p_m.ordem,
    'foto', p_pg.foto, 'foto_alt', p_pg.foto_alt,
    'textos', case when p_pg.textos_confirmados then jsonb_build_object('o_que_fazemos', p_pg.o_que_fazemos,
       'por_que_existimos', p_pg.por_que_existimos, 'missao', p_pg.missao, 'complemento', p_pg.complemento) end,
    'lideres', case when p_pg.exibir_lider then coalesce((select jsonb_agg(pe.nome order by pe.nome) from public.ministerio_membros mm
       join public.pessoas pe on pe.id = mm.pessoa_id where mm.ministerio_id = p_m.id and mm.funcao = 'lider' and mm.ativo), '[]'::jsonb) end)
$$;


--
-- Name: ministerio_salvar_pagina(uuid, jsonb, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ministerio_salvar_pagina(p_ministerio uuid, p_dados jsonb, p_publicar boolean) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare v_master boolean := public.e_master(); v_pg public.ministerio_paginas; v_foto text := nullif(btrim(coalesce(p_dados->>'foto', '')), '');
begin
  if not (v_master or public.lider_de(p_ministerio)) then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  select * into v_pg from public.ministerio_paginas where ministerio_id = p_ministerio for update;
  if v_pg.ministerio_id is null then raise exception 'Ministério não encontrado.' using errcode = 'P0002'; end if;
  if v_foto like 'site/%' then
    if v_foto !~ ('^site/ministerios/' || p_ministerio::text || '/[0-9a-f-]{36}\.(jpg|png|webp)$') or not public.imagem_existe('site', substr(v_foto, 6)) then
      raise exception 'Imagem inválida para este ministério.' using errcode = '22023'; end if;
  elsif v_foto is not null and v_foto !~ '^img/[a-z0-9._/-]+$' then
    raise exception 'Imagem inválida.' using errcode = '22023';
  end if;
  update public.ministerio_paginas set
    -- só altera o que veio no pedido (campo ausente = mantém)
    o_que_fazemos = case when p_dados ? 'o_que_fazemos' then public.texto_limpo(p_dados->>'o_que_fazemos', 2000) else o_que_fazemos end,
    por_que_existimos = case when p_dados ? 'por_que_existimos' then public.texto_limpo(p_dados->>'por_que_existimos', 2000) else por_que_existimos end,
    missao = case when p_dados ? 'missao' then public.texto_limpo(p_dados->>'missao', 2000) else missao end,
    complemento = case when p_dados ? 'complemento' then public.texto_limpo(p_dados->>'complemento', 3000) else complemento end,
    foto = case when p_dados ? 'foto' then v_foto else foto end,
    foto_alt = case when p_dados ? 'foto_alt' then public.texto_limpo(p_dados->>'foto_alt', 200) else foto_alt end,
    exibir_lider = coalesce((p_dados->>'exibir_lider')::boolean, exibir_lider),
    exibir_publico = case when v_master then coalesce((p_dados->>'exibir_publico')::boolean, exibir_publico) else exibir_publico end,
    textos_confirmados = coalesce(p_publicar, false),
    confirmados_em = case when p_publicar then now() else null end,
    confirmados_por = case when p_publicar then auth.uid() else null end,
    atualizado_por = auth.uid()
  where ministerio_id = p_ministerio;
  if p_dados ? 'foto' and v_pg.foto is distinct from v_foto then perform public.site_apagar_imagem(v_pg.foto); end if;
  -- descrição curta fica no cadastro do ministério
  if p_dados ? 'descricao' then
    update public.ministerios set descricao = public.texto_limpo(p_dados->>'descricao', 600) where id = p_ministerio;
  end if;
  return public.ministerio_admin_obter(p_ministerio);
end $_$;


--
-- Name: ministerio_vincular(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ministerio_vincular(p_ministerio uuid, p_pessoa uuid, p_cargo text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not (public.e_master() or public.lider_de(p_ministerio)) then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  if not exists (select 1 from public.perfis where pessoa_id = p_pessoa) then
    raise exception 'Escolha uma pessoa cadastrada no sistema.' using errcode = '22023'; end if;
  insert into public.ministerio_membros (pessoa_id, ministerio_id, funcao, cargo, ativo)
    values (p_pessoa, p_ministerio, 'voluntario', public.texto_limpo(p_cargo, 80), true)
  on conflict (pessoa_id, ministerio_id) do update
    set ativo = true, cargo = coalesce(public.texto_limpo(p_cargo, 80), public.ministerio_membros.cargo);
  return public.ministerio_admin_obter(p_ministerio);
end $$;


--
-- Name: ministerios_publicos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ministerios_publicos() RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(jsonb_agg(public.ministerio_pagina_publica_json(m, pg) order by m.ordem, m.nome), '[]'::jsonb)
  from public.ministerios m join public.ministerio_paginas pg on pg.ministerio_id = m.id
  where m.ativo and pg.exibir_publico
$$;


--
-- Name: notificar(text, uuid, text, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notificar(p_atribuicao text, p_usuario uuid, p_tipo text, p_titulo text, p_msg text, p_ref jsonb) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  insert into public.notificacoes (para_atribuicao, para_usuario, tipo, titulo, mensagem, ref) values (p_atribuicao, p_usuario, p_tipo, p_titulo, p_msg, coalesce(p_ref, '{}'))
$$;


--
-- Name: notificar_gestao(uuid, text, text, text, text, jsonb, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notificar_gestao(p_ministerio uuid, p_chave text, p_tipo text, p_titulo text, p_msg text, p_ref jsonb, p_area uuid DEFAULT NULL::uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare u uuid;
begin
  for u in select distinct pf.id from public.ministerio_membros mm join public.perfis pf on pf.pessoa_id = mm.pessoa_id
            where mm.ministerio_id = p_ministerio and mm.funcao = 'lider' and mm.ativo and pf.ativo
           union select g.perfil_id from public.escala_gestores g join public.perfis pf on pf.id = g.perfil_id
            where g.ministerio_id = p_ministerio and g.ativo and pf.ativo and (g.areas = '{}' or p_area is null or p_area = any(g.areas)) loop
    perform public.notificar_unico(p_chave || ':' || u, u, p_tipo, p_titulo, p_msg, p_ref);
  end loop;
end $$;


--
-- Name: notificar_unico(text, uuid, text, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notificar_unico(p_chave text, p_usuario uuid, p_tipo text, p_titulo text, p_msg text, p_ref jsonb) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  insert into public.notificacoes (para_usuario, tipo, titulo, mensagem, ref, chave, categoria)
  values (p_usuario, p_tipo, p_titulo, p_msg, coalesce(p_ref, '{}'), p_chave, 'escalas')
  on conflict (chave) where chave is not null do nothing
$$;


--
-- Name: organograma_atualizar(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.organograma_atualizar(p_org uuid, p_titulo text, p_descricao text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.pode_editar_organograma(p_org) then raise exception 'Você não pode editar este organograma.' using errcode = '42501'; end if;
  -- o título do organograma de ministério acompanha o nome do ministério; só a descrição muda
  update public.organogramas set titulo = case when tipo = 'ministerio' then titulo else coalesce(public.texto_limpo(p_titulo, 120), titulo) end,
         descricao = public.texto_limpo(p_descricao, 1000)
   where id = p_org;
  return public.organograma_obter(p_org);
end $$;


--
-- Name: organograma_no_mover(uuid, uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.organograma_no_mover(p_org uuid, p_no uuid, p_direcao integer) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_n public.organograma_nos; v_viz public.organograma_nos;
begin
  if not public.pode_editar_organograma(p_org) then raise exception 'Você não pode editar este organograma.' using errcode = '42501'; end if;
  select * into v_n from public.organograma_nos where id = p_no and organograma_id = p_org and ativo;
  if v_n.id is null then raise exception 'Função não encontrada.' using errcode = 'P0002'; end if;
  -- renumera os irmãos e troca de lugar com o vizinho
  with irmaos as (select id, row_number() over (order by ordem, cargo, id) * 10 as nova from public.organograma_nos
                  where organograma_id = p_org and ativo and pai_id is not distinct from v_n.pai_id)
  update public.organograma_nos n set ordem = i.nova from irmaos i where n.id = i.id;
  select * into v_n from public.organograma_nos where id = p_no;
  select * into v_viz from public.organograma_nos where organograma_id = p_org and ativo and pai_id is not distinct from v_n.pai_id
    and case when p_direcao < 0 then ordem < v_n.ordem else ordem > v_n.ordem end
    order by case when p_direcao < 0 then -ordem else ordem end limit 1;
  if v_viz.id is not null then
    update public.organograma_nos set ordem = v_viz.ordem where id = v_n.id;
    update public.organograma_nos set ordem = v_n.ordem where id = v_viz.id;
  end if;
  return public.organograma_obter(p_org);
end $$;


--
-- Name: organograma_no_remover(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.organograma_no_remover(p_org uuid, p_no uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_pai uuid;
begin
  if not public.pode_editar_organograma(p_org) then raise exception 'Você não pode editar este organograma.' using errcode = '42501'; end if;
  select pai_id into v_pai from public.organograma_nos where id = p_no and organograma_id = p_org and ativo;
  if not found then raise exception 'Função não encontrada.' using errcode = 'P0002'; end if;
  update public.organograma_nos set pai_id = v_pai, atualizado_por = auth.uid() where pai_id = p_no and ativo;
  update public.organograma_nos set ativo = false, atualizado_por = auth.uid() where id = p_no;
  return public.organograma_obter(p_org);
end $$;


--
-- Name: organograma_no_salvar(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.organograma_no_salvar(p_org uuid, p_dados jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_id uuid := nullif(p_dados->>'id', '')::uuid; v_pai uuid := nullif(p_dados->>'pai_id', '')::uuid;
        v_pessoa uuid := nullif(p_dados->>'pessoa_id', '')::uuid; v_nome text := public.texto_limpo(p_dados->>'nome_livre', 120);
        v_cargo text := public.texto_limpo(p_dados->>'cargo', 100); v_ordem int := coalesce((p_dados->>'ordem')::int, 0);
begin
  if not public.pode_editar_organograma(p_org) then raise exception 'Você não pode editar este organograma.' using errcode = '42501'; end if;
  if v_cargo is null or char_length(v_cargo) < 2 then raise exception 'Informe o cargo ou a função.' using errcode = '22023'; end if;
  if v_pessoa is not null then
    if not exists (select 1 from public.perfis where pessoa_id = v_pessoa) then raise exception 'Escolha uma pessoa cadastrada no sistema.' using errcode = '22023'; end if;
    v_nome := null;
  elsif v_nome is not null and not public.e_master() then
    raise exception 'Somente o MASTER cadastra nomes de pessoas sem conta no sistema.' using errcode = '42501';
  end if;
  if v_pai is not null then
    if not exists (select 1 from public.organograma_nos where id = v_pai and organograma_id = p_org and ativo) then
      raise exception 'Superior inválido.' using errcode = '22023'; end if;
    if v_id is not null and exists (with recursive acima(id, pai) as (
          select id, pai_id from public.organograma_nos where id = v_pai
          union all select n.id, n.pai_id from public.organograma_nos n join acima a on n.id = a.pai)
        select 1 from acima where id = v_id) then
      raise exception 'Uma função não pode ficar subordinada a ela mesma.' using errcode = '22023'; end if;
  end if;
  if v_id is null then
    insert into public.organograma_nos (organograma_id, pai_id, cargo, pessoa_id, nome_livre, responsabilidades, procurar_para, ordem, atualizado_por)
    values (p_org, v_pai, v_cargo, v_pessoa, v_nome, public.texto_limpo(p_dados->>'responsabilidades', 1500),
            public.texto_limpo(p_dados->>'procurar_para', 500), v_ordem, auth.uid()) returning id into v_id;
  else
    update public.organograma_nos set pai_id = v_pai, cargo = v_cargo, pessoa_id = v_pessoa, nome_livre = v_nome,
      responsabilidades = public.texto_limpo(p_dados->>'responsabilidades', 1500), procurar_para = public.texto_limpo(p_dados->>'procurar_para', 500),
      ordem = v_ordem, atualizado_por = auth.uid()
    where id = v_id and organograma_id = p_org and ativo;
    if not found then raise exception 'Função não encontrada.' using errcode = 'P0002'; end if;
  end if;
  return public.organograma_obter(p_org);
end $$;


--
-- Name: organograma_obter(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.organograma_obter(p_org uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_o public.organogramas;
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  select * into v_o from public.organogramas where id = p_org;
  if v_o.id is null then raise exception 'Organograma não encontrado.' using errcode = 'P0002'; end if;
  return jsonb_build_object('id', v_o.id, 'tipo', v_o.tipo, 'titulo', v_o.titulo, 'descricao', v_o.descricao,
    'pode_editar', public.pode_editar_organograma(v_o.id),
    'nos', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'pai_id', n.pai_id, 'cargo', n.cargo, 'ordem', n.ordem,
         'pessoa', case when n.pessoa_id is not null then public.pessoa_cartao(n.pessoa_id) end, 'nome_livre', n.nome_livre,
         'responsabilidades', n.responsabilidades, 'procurar_para', n.procurar_para) order by n.ordem, n.cargo)
       from public.organograma_nos n where n.organograma_id = v_o.id and n.ativo), '[]'::jsonb),
    -- organograma de ministério: liderança e integrantes vêm dos vínculos atuais (atualiza sozinho)
    'ministerio', case when v_o.tipo = 'ministerio' then jsonb_build_object(
       'lideres', coalesce((select jsonb_agg(public.pessoa_cartao(mm.pessoa_id) || jsonb_build_object('cargo', coalesce(mm.cargo, 'Líder')) order by pe.nome)
          from public.ministerio_membros mm join public.pessoas pe on pe.id = mm.pessoa_id
          where mm.ministerio_id = v_o.ministerio_id and mm.funcao = 'lider' and mm.ativo), '[]'::jsonb),
       'vice', (select public.pessoa_cartao(pg.vice_pessoa_id) || jsonb_build_object('cargo', 'Vice-líder')
          from public.ministerio_paginas pg where pg.ministerio_id = v_o.ministerio_id and pg.vice_pessoa_id is not null
            and exists (select 1 from public.ministerio_membros mm where mm.ministerio_id = v_o.ministerio_id and mm.pessoa_id = pg.vice_pessoa_id and mm.ativo)),
       'integrantes', coalesce((select jsonb_agg(public.pessoa_cartao(mm.pessoa_id) || jsonb_build_object('cargo', mm.cargo) order by pe.nome)
          from public.ministerio_membros mm join public.pessoas pe on pe.id = mm.pessoa_id
          left join public.ministerio_paginas pg on pg.ministerio_id = mm.ministerio_id
          where mm.ministerio_id = v_o.ministerio_id and mm.funcao = 'voluntario' and mm.ativo
            and mm.pessoa_id is distinct from pg.vice_pessoa_id
            and not exists (select 1 from public.organograma_nos n where n.organograma_id = v_o.id and n.ativo and n.pessoa_id = mm.pessoa_id)), '[]'::jsonb))
     end);
end $$;


--
-- Name: organogramas_listar(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.organogramas_listar() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'tipo', o.tipo, 'titulo', o.titulo, 'ministerio_id', o.ministerio_id,
       'pode_editar', public.pode_editar_organograma(o.id),
       'nos', (select count(*) from public.organograma_nos n where n.organograma_id = o.id and n.ativo))
       order by case o.tipo when 'igreja' then 0 when 'secretaria' then 1 when 'tesouraria' then 2 when 'colegio' then 3 else 4 end, o.ordem, o.titulo)
     from public.organogramas o left join public.ministerios m on m.id = o.ministerio_id
     where o.tipo <> 'ministerio' or m.ativo), '[]'::jsonb);
end $$;


--
-- Name: escala_participacoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.escala_participacoes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    escala_evento_id uuid NOT NULL,
    evento_funcao_id uuid NOT NULL,
    pessoa_id uuid NOT NULL,
    papel text DEFAULT 'auxiliar'::text NOT NULL,
    atividade text,
    inicio timestamp with time zone,
    fim timestamp with time zone,
    orientacoes_individuais text,
    observacao_lider text,
    status text DEFAULT 'rascunho'::text NOT NULL,
    versao integer DEFAULT 1 NOT NULL,
    versao_respondida integer,
    solicitado_em timestamp with time zone,
    prazo timestamp with time zone,
    respondido_em timestamp with time zone,
    motivo_recusa text,
    vaga_aberta boolean DEFAULT false NOT NULL,
    substitui_id uuid,
    motivo_cancelamento text,
    presenca text,
    presenca_obs text,
    presenca_por uuid,
    presenca_em timestamp with time zone,
    alertas_cientes jsonb,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT escala_participacoes_atividade_check CHECK ((char_length(atividade) <= 300)),
    CONSTRAINT escala_participacoes_check CHECK (((fim IS NULL) OR (inicio IS NULL) OR (fim > inicio))),
    CONSTRAINT escala_participacoes_motivo_cancelamento_check CHECK ((char_length(motivo_cancelamento) <= 600)),
    CONSTRAINT escala_participacoes_motivo_recusa_check CHECK ((char_length(motivo_recusa) <= 600)),
    CONSTRAINT escala_participacoes_observacao_lider_check CHECK ((char_length(observacao_lider) <= 1000)),
    CONSTRAINT escala_participacoes_orientacoes_individuais_check CHECK ((char_length(orientacoes_individuais) <= 1000)),
    CONSTRAINT escala_participacoes_papel_check CHECK ((papel = ANY (ARRAY['principal'::text, 'auxiliar'::text]))),
    CONSTRAINT escala_participacoes_presenca_check CHECK ((presenca = ANY (ARRAY['presente'::text, 'ausente'::text, 'parcial'::text]))),
    CONSTRAINT escala_participacoes_presenca_obs_check CHECK ((char_length(presenca_obs) <= 300)),
    CONSTRAINT escala_participacoes_status_check CHECK ((status = ANY (ARRAY['rascunho'::text, 'aguardando'::text, 'confirmado'::text, 'recusado'::text, 'substituicao_necessaria'::text, 'substituido'::text, 'cancelado'::text])))
);


--
-- Name: participacao_periodo(public.escala_participacoes); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.participacao_periodo(p public.escala_participacoes, OUT inicio timestamp with time zone, OUT fim timestamp with time zone) RETURNS record
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(p.inicio, ef.hora_inicio, e.inicio), coalesce(p.fim, ef.hora_fim, e.fim)
    from public.escala_evento_funcoes ef join public.escala_eventos e on e.id = ef.escala_evento_id where ef.id = p.evento_funcao_id
$$;


--
-- Name: perfil_ativo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.perfil_ativo() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce((select p.ativo and not p.deve_trocar_senha
                   from public.perfis p where p.id = auth.uid()), false)
$$;


--
-- Name: pessoa_cartao(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pessoa_cartao(p_pessoa uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select jsonb_build_object('pessoa_id', pe.id, 'nome', pe.nome,
    'foto', case when p.foto_no_organograma and p.foto_caminho is not null then p.foto_caminho end)
  from public.pessoas pe left join public.perfis p on p.pessoa_id = pe.id where pe.id = p_pessoa
$$;


--
-- Name: pessoas_para_vinculo(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pessoas_para_vinculo(p_busca text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_master boolean := public.e_master(); v_b text := '%' || lower(btrim(coalesce(p_busca, ''))) || '%';
begin
  if not (v_master or exists (select 1 from public.ministerio_membros mm join public.perfis p on p.pessoa_id = mm.pessoa_id
          where p.id = auth.uid() and mm.funcao = 'lider' and mm.ativo and public.perfil_ativo())) then
    raise exception 'Acesso negado.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(x) from (select jsonb_build_object('pessoa_id', pe.id, 'nome', pe.nome, 'perfil', p.perfil,
       'email', case when v_master then pe.email end) x
     from public.perfis p join public.pessoas pe on pe.id = p.pessoa_id
     where p.ativo and (lower(pe.nome) like v_b or (v_master and lower(coalesce(pe.email, '')) like v_b))
     order by pe.nome limit 40) s), '[]'::jsonb);
end $$;


--
-- Name: pode_editar_organograma(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pode_editar_organograma(p_org uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select public.e_master() or exists (select 1 from public.organogramas o
    where o.id = p_org and o.tipo = 'ministerio' and public.lider_de(o.ministerio_id))
$$;


--
-- Name: pode_enviar_foto_perfil(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pode_enviar_foto_perfil(p_caminho text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $_$
  select public.perfil_ativo() and coalesce(p_caminho, '') ~ ('^' || auth.uid()::text || '/[0-9a-f-]{36}\.(jpg|png|webp)$')
$_$;


--
-- Name: pode_enviar_imagem_site(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pode_enviar_imagem_site(p_caminho text) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare m text[];
begin
  if not public.perfil_ativo() then return false; end if;
  m := regexp_match(coalesce(p_caminho, ''), '^ministerios/([0-9a-f-]{36})/[0-9a-f-]{36}\.(jpg|png|webp)$');
  if m is not null then return public.e_master() or public.lider_de(m[1]::uuid); end if;
  return public.e_master() and coalesce(p_caminho, '') ~ '^(home|colegio)/[0-9a-f-]{36}\.(jpg|png|webp)$';
end $_$;


--
-- Name: pode_solicitar_apoio(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pode_solicitar_apoio(p_ministerio uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select public.perfil_ativo() and (public.lider_de(p_ministerio) or public.e_master() or public.e_secretaria() or public.agenda_coordenador())
$$;


--
-- Name: recusar_solicitacao(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recusar_solicitacao(p_solicitacao uuid, p_motivo text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_master() then raise exception 'Somente o MASTER pode recusar solicitações.' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p_motivo,''))) < 3 then raise exception 'Informe o motivo da recusa.' using errcode = '22023'; end if;
  update public.solicitacoes set status = 'recusada', analisado_por = auth.uid(), analisado_em = now(), motivo = btrim(p_motivo)
   where id = p_solicitacao and tipo = 'acesso' and status = 'pendente';
  if not found then raise exception 'Solicitação não encontrada ou já analisada.' using errcode = 'P0002'; end if;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: registrar_consentimento(uuid, text, uuid, text, jsonb, jsonb, text, text, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.registrar_consentimento(p_pessoa uuid, p_tipo text, p_termo uuid, p_decisao text, p_escopo jsonb, p_responsavel jsonb, p_origem text, p_contexto_tipo text, p_contexto_id uuid, p_documento uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare t public.termos; pe public.pessoas; v_menor boolean; v_resp jsonb; v_escopo jsonb := '{}'; v_id uuid;
begin
  select * into t from public.termos where id = p_termo;
  if not found or t.tipo <> p_tipo then raise exception 'Termo inválido.' using errcode = '22023'; end if;
  if t.status <> 'vigente' then raise exception 'Este termo foi atualizado. Recarregue a página para ler a versão em vigor.' using errcode = '22023'; end if;
  if p_decisao not in ('aceito','recusado') then raise exception 'Decisão inválida.' using errcode = '22023'; end if;
  select * into pe from public.pessoas where id = p_pessoa;
  if pe.data_nascimento is null then raise exception 'Informe a data de nascimento para registrar o termo.' using errcode = '22023'; end if;
  v_menor := public.idade_em(pe.data_nascimento) < 18;
  if v_menor then
    if p_responsavel is null then raise exception 'Menores de 18 anos precisam da autorização do responsável legal.' using errcode = '22023'; end if;
    v_resp := public.responsavel_valido(p_responsavel);
  end if;
  if p_tipo = 'imagem_voz' and p_decisao = 'aceito' then
    v_escopo := jsonb_strip_nulls(jsonb_build_object(
      'fotos', case when coalesce((p_escopo->>'fotos')::boolean, false) then true end,
      'videos', case when coalesce((p_escopo->>'videos')::boolean, false) then true end,
      'voz', case when coalesce((p_escopo->>'voz')::boolean, false) then true end));
    if v_escopo = '{}'::jsonb then raise exception 'Marque o que você autoriza: fotos, vídeos ou voz.' using errcode = '22023'; end if;
  end if;
  insert into public.consentimentos (pessoa_id, termo_id, tipo, decisao, escopo, dado_por, menor_na_data, responsavel, origem,
                                     contexto_tipo, contexto_id, documento_id, texto_hash, registrado_por)
  values (p_pessoa, t.id, p_tipo, p_decisao, v_escopo, case when v_menor then 'responsavel' else 'titular' end, v_menor, v_resp, p_origem,
          p_contexto_tipo, p_contexto_id, p_documento, t.texto_hash, case when p_origem = 'secretaria' then auth.uid() end)
  returning id into v_id;
  -- um novo registro substitui o anterior do mesmo tipo (fica no histórico como revogado/substituído)
  update public.consentimentos set revogado_em = now(), revogado_via = case when p_origem = 'secretaria' then 'secretaria' when v_menor then 'responsavel' else 'titular' end,
         revogado_por = auth.uid(), motivo_revogacao = 'Substituído por nova decisão'
   where pessoa_id = p_pessoa and tipo = p_tipo and id <> v_id and revogado_em is null and p_tipo = 'imagem_voz';
  return v_id;
end $$;


--
-- Name: responsavel_valido(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.responsavel_valido(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $_$
declare v_nome text := regexp_replace(btrim(coalesce(p->>'nome', '')), '\s+', ' ', 'g');
        v_tel text := regexp_replace(coalesce(p->>'telefone', ''), '\D', '', 'g');
        v_email text := lower(btrim(coalesce(p->>'email', '')));
begin
  if char_length(v_nome) < 5 or v_nome !~ '\s' then raise exception 'Informe o nome completo do responsável legal.' using errcode = '22023'; end if;
  if coalesce(p->>'parentesco', '') not in ('mae','pai','tutor','guardiao','outro_responsavel_legal') then
    raise exception 'Informe o vínculo do responsável legal.' using errcode = '22023'; end if;
  if v_tel !~ '^[0-9]{10,13}$' then raise exception 'Informe o telefone do responsável legal, com DDD.' using errcode = '22023'; end if;
  if v_email <> '' and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'E-mail do responsável inválido.' using errcode = '22023'; end if;
  if not coalesce((p->>'declara_responsavel')::boolean, false) then
    raise exception 'O responsável precisa declarar que é o responsável legal do menor.' using errcode = '22023'; end if;
  return jsonb_build_object('nome', v_nome, 'parentesco', p->>'parentesco', 'telefone', v_tel, 'email', nullif(v_email, ''),
                            'declara_responsavel', true);
end $_$;


--
-- Name: revogar_consentimento_link(text, text, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.revogar_consentimento_link(p_protocolo text, p_chave text, p_consentimento uuid, p_motivo text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.inscricoes := public.link_inscricao(p_protocolo, p_chave); c public.consentimentos;
begin
  select * into c from public.consentimentos where id = p_consentimento and pessoa_id = i.pessoa_id for update;
  if not found then raise exception 'Autorização não encontrada.' using errcode = 'P0002'; end if;
  if c.tipo <> 'imagem_voz' then
    raise exception 'Pelo link é possível revogar a autorização de imagem e voz. Para os demais termos, fale com a Secretaria.' using errcode = '22023'; end if;
  if c.revogado_em is not null then raise exception 'Esta autorização já foi revogada.' using errcode = '22023'; end if;
  update public.consentimentos set revogado_em = now(), revogado_via = case when c.dado_por = 'responsavel' then 'responsavel' else 'titular' end,
         motivo_revogacao = coalesce(nullif(btrim(p_motivo), ''), 'Revogado pelo titular') where id = c.id;
  perform public.notificar('SECRETARIA', null, 'imagem_revogada', 'Autorização de imagem revogada',
          (select nome from public.pessoas where id = c.pessoa_id) || ' revogou a autorização de imagem e voz. Avise a equipe de Mídia.', jsonb_build_object('pessoa', c.pessoa_id));
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: salvar_minha_disponibilidade(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.salvar_minha_disponibilidade(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare me uuid := public.minha_pessoa_id(); x jsonb;
begin
  if not public.perfil_ativo() or me is null then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  if p ? 'semana' then
    delete from public.voluntario_disponibilidade where pessoa_id = me;
    for x in select * from jsonb_array_elements(p->'semana') loop
      if (x->>'ate')::time <= (x->>'de')::time then raise exception 'O horário final precisa ser depois do inicial.' using errcode = '22023'; end if;
      insert into public.voluntario_disponibilidade (pessoa_id, dia_semana, hora_inicio, hora_fim) values (me, (x->>'dia')::smallint, (x->>'de')::time, (x->>'ate')::time);
    end loop;
  end if;
  if p ? 'preferencias' then
    insert into public.voluntario_preferencias (pessoa_id, funcoes, observacoes)
    values (me, coalesce((select array_agg(v::uuid) from jsonb_array_elements_text(p->'preferencias'->'funcoes') v), '{}'), nullif(btrim(p->'preferencias'->>'observacoes'), ''))
    on conflict (pessoa_id) do update set funcoes = excluded.funcoes, observacoes = excluded.observacoes, atualizado_em = now();
  end if;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: secretaria_abrir_candidatura(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_abrir_candidatura(p_pessoa uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r jsonb := public.voluntariado_requisitos(p_pessoa); v uuid;
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  if not (r->>'pode_ser_voluntario')::boolean or not (r->>'formacao_voluntarios')::boolean then
    raise exception 'Para abrir a candidatura: membresia validada, Novos Membros e Formação de Voluntários concluídos.' using errcode = '22023'; end if;
  if exists (select 1 from public.voluntariado_candidaturas where pessoa_id = p_pessoa and status in ('aguardando_indicacao','em_analise')) then
    raise exception 'Já existe uma candidatura aberta.' using errcode = '23505'; end if;
  insert into public.voluntariado_candidaturas (pessoa_id, observacao) values (p_pessoa, 'Aberta pela Secretaria') returning id into v;
  return jsonb_build_object('ok', true, 'id', v);
end $$;


--
-- Name: secretaria_abrir_processo(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_abrir_processo(p_pessoa uuid, p_observacao text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v uuid;
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  if public.membresia_validada(p_pessoa) then raise exception 'Esta pessoa já tem a membresia validada.' using errcode = '22023'; end if;
  if exists (select 1 from public.membresia_processos where pessoa_id = p_pessoa and status not in ('validado','encerrado')) then
    raise exception 'Já existe um processo de membresia aberto para esta pessoa.' using errcode = '23505'; end if;
  insert into public.membresia_processos (pessoa_id, status, origem, observacao)
  values (p_pessoa, case when public.curso_concluido(p_pessoa, public.curso_id_por_slug('novos-membros')) then 'aguardando_validacao' else 'interesse' end,
          'secretaria', nullif(btrim(p_observacao), '')) returning id into v;
  return jsonb_build_object('ok', true, 'id', v);
end $$;


--
-- Name: secretaria_arquivar_documento(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_arquivar_documento(p_documento uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  update public.documentos set arquivado_em = now() where id = p_documento and arquivado_em is null;
  return jsonb_build_object('ok', found);
end $$;


--
-- Name: secretaria_cancelar_candidatura(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_cancelar_candidatura(p_candidatura uuid, p_motivo text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 5 then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
  update public.voluntariado_candidaturas set status = 'cancelada', encerrada_em = now(), observacao = btrim(p_motivo)
   where id = p_candidatura and status in ('aguardando_indicacao','em_analise');
  if not found then raise exception 'Candidatura não encontrada ou já encerrada.' using errcode = 'P0002'; end if;
  update public.voluntariado_indicacoes set status = 'cancelada' where candidatura_id = p_candidatura and status = 'pendente';
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: secretaria_cancelar_conclusao_anterior(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_cancelar_conclusao_anterior(p_id uuid, p_motivo text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 5 then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
  update public.cursos_conclusoes_anteriores set cancelado_em = now(), motivo_cancelamento = btrim(p_motivo) where id = p_id and cancelado_em is null;
  if not found then raise exception 'Registro não encontrado.' using errcode = 'P0002'; end if;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: secretaria_cancelar_pagamento(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_cancelar_pagamento(p_pagamento uuid, p_motivo text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare p public.pagamentos;
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  select * into p from public.pagamentos where id = p_pagamento for update;
  if not found then raise exception 'Pagamento não encontrado.' using errcode = 'P0002'; end if;
  if p.registrado_por is distinct from auth.uid() then raise exception 'Só quem registrou o pagamento pode cancelar o registro.' using errcode = '42501'; end if;
  if p.status not in ('aguardando_comprovante','em_analise') then raise exception 'Pagamento já analisado pela Tesouraria não pode ser cancelado.' using errcode = '22023'; end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 3 then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
  update public.pagamentos set status = 'cancelado', observacao = left(coalesce(observacao || ' | ', '') || 'Cancelado: ' || btrim(p_motivo), 600) where id = p.id;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: secretaria_candidaturas(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_candidaturas(p_status text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'candidaturas', coalesce((select jsonb_agg(public.candidatura_json(c.id) order by c.criado_em desc) from public.voluntariado_candidaturas c
                               where (p_status is null and c.status in ('aguardando_indicacao','em_analise')) or c.status = p_status), '[]'::jsonb),
    -- voluntários atuais que ainda não cumprem a regra (cadastros anteriores): só para regularização, nada é removido
    'pendencias', coalesce((select jsonb_agg(jsonb_build_object('pessoa_id', pe.id, 'nome', pe.nome, 'ministerios', x.mins, 'requisitos', public.voluntariado_requisitos(pe.id)) order by pe.nome)
        from (select mm.pessoa_id, jsonb_agg(m.nome order by m.nome) mins from public.ministerio_membros mm join public.ministerios m on m.id = mm.ministerio_id
               where mm.funcao = 'voluntario' and mm.ativo group by mm.pessoa_id) x join public.pessoas pe on pe.id = x.pessoa_id
       where not (public.voluntariado_requisitos(pe.id)->>'pode_ser_voluntario')::boolean), '[]'::jsonb));
end $$;


--
-- Name: secretaria_cerimonia_realizada(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_cerimonia_realizada(p_cerimonia uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare c public.cerimonias;
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  select * into c from public.cerimonias where id = p_cerimonia for update;
  if not found or c.status <> 'planejada' then raise exception 'Cerimônia não encontrada ou não planejada.' using errcode = 'P0002'; end if;
  if c.data > current_date then raise exception 'A cerimônia ainda não aconteceu (%).', to_char(c.data, 'DD/MM/YYYY') using errcode = '22023'; end if;
  update public.cerimonias set status = 'realizada', realizada_em = now(), realizada_por = auth.uid() where id = c.id;
  return jsonb_build_object('ok', true,
    'nao_entregues', (select count(*) from public.certificados where cerimonia_id = c.id and status in ('preparado','impresso')));
end $$;


--
-- Name: secretaria_certificado(uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_certificado(p_certificado uuid, p_acao text, p_dados jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare ce public.certificados; cm public.cerimonias; v_motivo text := nullif(btrim(coalesce(p_dados->>'motivo', '')), '');
begin
  if not public.e_secretaria() then raise exception 'Somente a Secretaria gerencia certificados.' using errcode = '42501'; end if;
  select * into ce from public.certificados where id = p_certificado for update;
  if not found then raise exception 'Certificado não encontrado.' using errcode = 'P0002'; end if;
  if ce.status = 'cancelado' and p_acao <> 'reativar' then raise exception 'Certificado cancelado.' using errcode = '22023'; end if;
  if ce.status = 'entregue' and p_acao not in ('historico') then raise exception 'Certificado já entregue: o registro não muda mais.' using errcode = '22023'; end if;
  perform set_config('app.cert_detalhe', jsonb_strip_nulls(jsonb_build_object('motivo', v_motivo, 'observacao', nullif(btrim(coalesce(p_dados->>'observacao', '')), '')))::text, true);

  if p_acao = 'autorizar' then
    if ce.status <> 'aguardando_autorizacao' then
      raise exception 'A emissão só é autorizada depois que a liderança valida a conclusão.' using errcode = '22023'; end if;
    if ce.validado_por = auth.uid() then
      raise exception 'Quem validou a conclusão não autoriza a emissão. Outra pessoa da Secretaria deve autorizar.' using errcode = '42501'; end if;
    update public.certificados set status = 'autorizado', autorizado_por = auth.uid(), autorizado_em = now() where id = ce.id;
  elsif p_acao = 'recusar_emissao' then
    if ce.status not in ('aguardando_validacao','aguardando_autorizacao') then raise exception 'Só é possível recusar antes da autorização.' using errcode = '22023'; end if;
    if char_length(coalesce(v_motivo, '')) < 5 then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
    update public.certificados set status = 'cancelado', motivo_cancelamento = 'Emissão não autorizada: ' || v_motivo where id = ce.id;
  elsif p_acao in ('vincular','preparar') then
    if ce.status not in ('autorizado','preparado','impresso') then raise exception 'Vincule à cerimônia só depois de autorizar a emissão.' using errcode = '22023'; end if;
    select * into cm from public.cerimonias where id = (p_dados->>'cerimonia_id')::uuid;
    if not found or cm.status <> 'planejada' then raise exception 'Escolha uma cerimônia planejada.' using errcode = '22023'; end if;
    if cm.data < current_date then raise exception 'A data dessa cerimônia já passou.' using errcode = '22023'; end if;
    update public.certificados set cerimonia_id = cm.id, status = case when status = 'autorizado' then 'preparado' else status end,
           preparado_por = auth.uid(), preparado_em = now() where id = ce.id;
  elsif p_acao = 'imprimir' then
    if ce.status not in ('preparado','impresso') then raise exception 'Vincule o certificado a uma cerimônia antes de imprimir.' using errcode = '22023'; end if;
    if ce.vezes_impresso > 0 and char_length(coalesce(v_motivo, '')) < 5 then
      raise exception 'Este certificado já foi impresso. Informe o motivo da reimpressão.' using errcode = '22023'; end if;
    update public.certificados set status = 'impresso', impresso_por = auth.uid(), impresso_em = now(), vezes_impresso = vezes_impresso + 1 where id = ce.id;
    perform set_config('app.cert_detalhe', '', true);
    return jsonb_build_object('ok', true, 'impressao', public.certificado_impressao_json(ce.id));
  elsif p_acao = 'entregar' then
    if ce.status <> 'impresso' then raise exception 'Só certificados impressos podem ser entregues.' using errcode = '22023'; end if;
    if not coalesce((p_dados->>'confirmo_entrega_fisica')::boolean, false) then
      raise exception 'Confirme que o certificado foi entregue em mãos.' using errcode = '22023'; end if;
    if char_length(btrim(coalesce(p_dados->>'recebido_por', ''))) < 5 then raise exception 'Informe o nome completo de quem recebeu o certificado.' using errcode = '22023'; end if;
    if coalesce(p_dados->>'relacao', '') not in ('participante','responsavel_legal','pessoa_autorizada') then raise exception 'Informe quem recebeu (o participante, o responsável legal ou pessoa autorizada).' using errcode = '22023'; end if;
    if coalesce(p_dados->>'ocasiao', '') = 'cerimonia' then
      select * into cm from public.cerimonias where id = ce.cerimonia_id;
      if cm.id is null or cm.status = 'cancelada' then raise exception 'Cerimônia inválida.' using errcode = '22023'; end if;
      if cm.data > current_date then raise exception 'A cerimônia ainda não aconteceu (%): a entrega só é registrada depois dela.', to_char(cm.data, 'DD/MM/YYYY') using errcode = '22023'; end if;
    elsif coalesce(p_dados->>'ocasiao', '') = 'secretaria' then
      if char_length(coalesce(nullif(btrim(p_dados->>'observacao'), ''), '')) < 5 then
        raise exception 'Entrega fora da cerimônia: explique a ocasião (ex.: ausente na cerimônia, retirou na Secretaria em …).' using errcode = '22023'; end if;
    else raise exception 'Informe a ocasião da entrega.' using errcode = '22023';
    end if;
    if p_dados->>'relacao' = 'pessoa_autorizada' and char_length(coalesce(nullif(btrim(p_dados->>'observacao'), ''), '')) < 5 then
      raise exception 'Entrega a terceiro: registre quem autorizou.' using errcode = '22023'; end if;
    update public.certificados set status = 'entregue', entregue_em = now(), entregue_por = auth.uid(), recebido_por = btrim(p_dados->>'recebido_por'),
           recebido_relacao = p_dados->>'relacao', entrega_ocasiao = p_dados->>'ocasiao', entrega_observacao = nullif(btrim(p_dados->>'observacao'), '') where id = ce.id;
  elsif p_acao = 'desvincular' then
    if ce.status not in ('preparado','impresso') then raise exception 'Este certificado não está vinculado.' using errcode = '22023'; end if;
    update public.certificados set cerimonia_id = null, status = case when status = 'preparado' then 'autorizado' else status end where id = ce.id;
  elsif p_acao = 'cancelar' then
    if char_length(coalesce(v_motivo, '')) < 5 then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
    update public.certificados set status = 'cancelado', motivo_cancelamento = v_motivo where id = ce.id;
  elsif p_acao = 'reativar' then
    if not exists (select 1 from public.inscricoes where id = ce.inscricao_id and status = 'concluida') then raise exception 'A inscrição não está concluída.' using errcode = '22023'; end if;
    update public.certificados set status = case when entregue_em is not null then 'entregue' when impresso_em is not null and cerimonia_id is not null then 'impresso'
             when autorizado_em is not null and cerimonia_id is not null then 'preparado' when autorizado_em is not null then 'autorizado'
             when validado_em is not null then 'aguardando_autorizacao' else 'aguardando_validacao' end,
           motivo_cancelamento = null where id = ce.id;
  else raise exception 'Ação inválida.' using errcode = '22023';
  end if;
  perform set_config('app.cert_detalhe', '', true);
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: secretaria_certificado_historico(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_certificado_historico(p_certificado uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('evento', e.evento, 'em', e.em, 'status_antes', e.status_antes, 'status_depois', e.status_depois, 'detalhes', e.detalhes,
      'ator', (select x.nome from public.perfis pf join public.pessoas x on x.id = pf.pessoa_id where pf.id = e.ator)) order by e.em, e.id)
    from public.certificados_eventos e where e.certificado_id = p_certificado), '[]'::jsonb);
end $$;


--
-- Name: secretaria_certificados(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_certificados(p_filtros jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'cerimonias', coalesce((select jsonb_agg(to_jsonb(cm) || jsonb_build_object(
        'certificados', (select count(*) from public.certificados ce where ce.cerimonia_id = cm.id and ce.status <> 'cancelado'),
        'a_imprimir', (select count(*) from public.certificados ce where ce.cerimonia_id = cm.id and ce.status = 'preparado'),
        'entregues', (select count(*) from public.certificados ce where ce.cerimonia_id = cm.id and ce.status = 'entregue'))
        order by cm.data nulls last, cm.criado_em) from public.cerimonias cm), '[]'::jsonb),
    'certificados', coalesce((select jsonb_agg(jsonb_build_object('id', ce.id, 'codigo', ce.codigo, 'status', ce.status, 'cerimonia_id', ce.cerimonia_id,
        'cerimonia', cm.titulo, 'cerimonia_data', cm.data, 'vezes_impresso', ce.vezes_impresso, 'impresso_em', ce.impresso_em, 'entregue_em', ce.entregue_em,
        'recebido_por', ce.recebido_por, 'recebido_relacao', ce.recebido_relacao, 'entrega_ocasiao', ce.entrega_ocasiao,
        'motivo_cancelamento', ce.motivo_cancelamento, 'nome', pe.nome, 'curso', c.titulo, 'modalidade', c.modalidade, 'turma', t.nome,
        'concluida_em', i.concluida_em, 'protocolo', i.protocolo, 'validado_em', ce.validado_em, 'autorizado_em', ce.autorizado_em,
        'validado_por', (select x.nome from public.perfis pf join public.pessoas x on x.id = pf.pessoa_id where pf.id = ce.validado_por),
        'autorizado_por', (select x.nome from public.perfis pf join public.pessoas x on x.id = pf.pessoa_id where pf.id = ce.autorizado_por),
        'eu_validei', ce.validado_por = auth.uid()) order by ce.criado_em desc)
      from public.certificados ce join public.inscricoes i on i.id = ce.inscricao_id join public.pessoas pe on pe.id = i.pessoa_id
      join public.turmas t on t.id = i.turma_id join public.cursos c on c.id = t.curso_id left join public.cerimonias cm on cm.id = ce.cerimonia_id
      where (p_filtros->>'status' is null or ce.status = p_filtros->>'status')
        and (p_filtros->>'cerimonia_id' is null or ce.cerimonia_id = (p_filtros->>'cerimonia_id')::uuid)), '[]'::jsonb),
    'modelo', coalesce((select valor from public.configuracoes where chave = 'certificado_modelo'), '{}'::jsonb));
end $$;


--
-- Name: secretaria_documentos(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_documentos(p_pessoa uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'tipo', d.tipo, 'descricao', d.descricao, 'nome_original', d.nome_original, 'tipo_mime', d.tipo_mime,
      'tamanho', d.tamanho, 'enviado_em', d.enviado_em, 'arquivado_em', d.arquivado_em,
      'enviado_por', (select pe.nome from public.perfis pf join public.pessoas pe on pe.id = pf.pessoa_id where pf.id = d.enviado_por)) order by d.enviado_em desc)
    from public.documentos d where d.pessoa_id = p_pessoa), '[]'::jsonb);
end $$;


--
-- Name: secretaria_encerrar_processo(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_encerrar_processo(p_processo uuid, p_motivo text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 5 then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
  update public.membresia_processos set status = 'encerrado', encerrado_em = now(), motivo_encerramento = btrim(p_motivo)
   where id = p_processo and status not in ('validado','encerrado');
  if not found then raise exception 'Processo não encontrado ou já encerrado.' using errcode = 'P0002'; end if;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: secretaria_ficha_pessoa(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_ficha_pessoa(p_pessoa uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare pe public.pessoas;
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  select * into pe from public.pessoas where id = p_pessoa;
  if not found then raise exception 'Pessoa não encontrada.' using errcode = 'P0002'; end if;
  return jsonb_build_object('id', pe.id, 'nome', pe.nome, 'email', pe.email, 'telefone', pe.telefone, 'data_nascimento', pe.data_nascimento,
    'menor', case when pe.data_nascimento is not null then public.idade_em(pe.data_nascimento) < 18 end,
    'situacao_membresia', pe.situacao_membresia, 'membro_desde', pe.membro_desde, 'membresia_validada_em', pe.membresia_validada_em,
    'requisitos', public.voluntariado_requisitos(pe.id),
    'conclusoes_anteriores', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'curso', cu.titulo, 'concluido_em', c.concluido_em, 'comprovacao', c.comprovacao,
        'cancelado_em', c.cancelado_em, 'registrado_por', (select x.nome from public.perfis pf join public.pessoas x on x.id = pf.pessoa_id where pf.id = c.registrado_por)) order by c.registrado_em)
        from public.cursos_conclusoes_anteriores c join public.cursos cu on cu.id = c.curso_id where c.pessoa_id = pe.id), '[]'::jsonb),
    'ministerios', coalesce((select jsonb_agg(jsonb_build_object('ministerio', m.nome, 'funcao', mm.funcao, 'ativo', mm.ativo))
        from public.ministerio_membros mm join public.ministerios m on m.id = mm.ministerio_id where mm.pessoa_id = pe.id), '[]'::jsonb),
    'consentimentos', public.consentimentos_json(pe.id));
end $$;


--
-- Name: secretaria_imprimir_cerimonia(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_imprimir_cerimonia(p_cerimonia uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare x uuid; v jsonb := '[]'::jsonb;
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  for x in select ce.id from public.certificados ce join public.inscricoes i on i.id = ce.inscricao_id join public.pessoas pe on pe.id = i.pessoa_id
            where ce.cerimonia_id = p_cerimonia and ce.status = 'preparado' order by pe.nome loop
    v := v || jsonb_build_array(public.secretaria_certificado(x, 'imprimir', '{}')->'impressao');
  end loop;
  if jsonb_array_length(v) = 0 then raise exception 'Nenhum certificado pendente de impressão nesta cerimônia.' using errcode = '22023'; end if;
  return jsonb_build_object('ok', true, 'impressoes', v);
end $$;


--
-- Name: secretaria_indicar_ministerios(uuid, uuid[], uuid, boolean, jsonb, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_indicar_ministerios(p_candidatura uuid, p_ministerios uuid[], p_termo uuid, p_termo_presencial boolean, p_responsavel jsonb, p_documento uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  if not coalesce(p_termo_presencial, false) then
    raise exception 'Confirme que o termo de adesão ao voluntariado foi assinado pela pessoa.' using errcode = '22023'; end if;
  perform public.voluntariado_indicar_interno(p_candidatura, p_ministerios, p_termo, 'secretaria', p_responsavel);
  if p_documento is not null then
    -- não altera o consentimento (imutável): o documento fica ligado pela auditoria
    insert into public.auditoria (ator, acao, tabela, registro, detalhes) values (auth.uid(), 'termo_papel_anexado', 'voluntariado_candidaturas', p_candidatura::text, jsonb_build_object('documento', p_documento));
  end if;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: secretaria_inscricoes(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_inscricoes(p_filtros jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_busca text := '%' || lower(btrim(coalesce(p_filtros->>'busca', ''))) || '%';
begin
  if not (public.e_secretaria() or public.e_tesouraria()) then raise exception 'Acesso restrito à Secretaria e à Tesouraria.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(x order by x->>'criado_em' desc) from (
    select jsonb_build_object('id', i.id, 'protocolo', i.protocolo, 'status', i.status, 'criado_em', i.criado_em, 'origem', i.origem,
      'pessoa_id', pe.id, 'nome', pe.nome, 'email', pe.email, 'telefone', pe.telefone,
      'curso', c.titulo, 'turma', t.nome, 'turma_id', t.id, 'financeiro', public.financeiro_inscricao(i.id),
      'beneficios', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'tipo', b.tipo, 'status', b.status, 'valor_desconto', b.valor_desconto, 'motivo', b.motivo)) from public.beneficios b where b.inscricao_id = i.id), '[]'::jsonb),
      'pagamentos', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'status', p.status, 'valor', p.valor, 'metodo', p.metodo, 'origem', p.origem,
          'registrado_em', p.registrado_em, 'eu_registrei', p.registrado_por = auth.uid(), 'observacao_analise', p.observacao_analise,
          'comprovantes', (select count(*) from public.comprovantes cp where cp.pagamento_id = p.id)) order by p.registrado_em) from public.pagamentos p where p.inscricao_id = i.id), '[]'::jsonb),
      'certificado', (select ce.status from public.certificados ce where ce.inscricao_id = i.id)) as x
    from public.inscricoes i join public.pessoas pe on pe.id = i.pessoa_id join public.turmas t on t.id = i.turma_id join public.cursos c on c.id = t.curso_id
    where (p_filtros->>'status' is null or i.status = p_filtros->>'status')
      and (p_filtros->>'turma_id' is null or i.turma_id = (p_filtros->>'turma_id')::uuid)
      and (p_filtros->>'financeiro' is null or public.financeiro_inscricao(i.id)->>'situacao' = p_filtros->>'financeiro')
      and (lower(pe.nome) like v_busca or lower(coalesce(pe.email, '')) like v_busca or i.protocolo ilike v_busca)
    limit 500) s), '[]'::jsonb);
end $$;


--
-- Name: secretaria_lista_cerimonia(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_lista_cerimonia(p_cerimonia uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  return jsonb_build_object('cerimonia', (select to_jsonb(c) from public.cerimonias c where c.id = p_cerimonia),
    'participantes', coalesce((select jsonb_agg(jsonb_build_object('id', ce.id, 'nome', pe.nome, 'curso', cu.titulo, 'turma', t.nome, 'status', ce.status, 'codigo', ce.codigo,
        'menor', case when pe.data_nascimento is not null then extract(year from age(pe.data_nascimento))::int < 18 end) order by cu.titulo, pe.nome)
      from public.certificados ce join public.inscricoes i on i.id = ce.inscricao_id join public.pessoas pe on pe.id = i.pessoa_id
      join public.turmas t on t.id = i.turma_id join public.cursos cu on cu.id = t.curso_id where ce.cerimonia_id = p_cerimonia and ce.status <> 'cancelado'), '[]'::jsonb));
end $$;


--
-- Name: secretaria_pessoas(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_pessoas(p_busca text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v text := '%' || lower(btrim(coalesce(p_busca, ''))) || '%';
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(x order by x->>'nome') from (
    select jsonb_build_object('id', pe.id, 'nome', pe.nome, 'email', pe.email, 'telefone', pe.telefone, 'data_nascimento', pe.data_nascimento,
      'situacao_membresia', pe.situacao_membresia, 'membro_desde', pe.membro_desde, 'membresia_validada_em', pe.membresia_validada_em,
      'validada_por', (select pe2.nome from public.perfis pf join public.pessoas pe2 on pe2.id = pf.pessoa_id where pf.id = pe.membresia_validada_por),
      'tem_conta', pe.usuario_id is not null, 'origem', pe.origem,
      'inscricoes', (select count(*) from public.inscricoes i where i.pessoa_id = pe.id),
      'documentos', (select count(*) from public.documentos d where d.pessoa_id = pe.id and d.arquivado_em is null)) as x
    from public.pessoas pe where pe.arquivado_em is null
      and (lower(pe.nome) like v or lower(coalesce(pe.email, '')) like v or (coalesce(public.so_digitos(p_busca), '') <> '' and coalesce(pe.telefone, '') like '%' || public.so_digitos(p_busca) || '%'))
    limit 500) s), '[]'::jsonb);
end $$;


--
-- Name: secretaria_processos_membresia(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_processos_membresia(p_status text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'status', p.status, 'origem', p.origem, 'mensagem', p.mensagem, 'observacao', p.observacao,
      'forma_ingresso', p.forma_ingresso, 'criado_em', p.criado_em, 'atualizado_em', p.atualizado_em, 'motivo_encerramento', p.motivo_encerramento,
      'pessoa_id', pe.id, 'nome', pe.nome, 'telefone', pe.telefone, 'email', pe.email, 'data_nascimento', pe.data_nascimento,
      'menor', case when pe.data_nascimento is not null then public.idade_em(pe.data_nascimento) < 18 end,
      'situacao_membresia', pe.situacao_membresia,
      'novos_membros', public.curso_concluido(pe.id, public.curso_id_por_slug('novos-membros')),
      'inscricao', (select jsonb_build_object('protocolo', i.protocolo, 'status', i.status, 'turma', t.nome)
                      from public.inscricoes i join public.turmas t on t.id = i.turma_id where i.id = p.inscricao_id))
      order by case p.status when 'aguardando_validacao' then 0 when 'interesse' then 1 when 'em_curso' then 2 else 3 end, p.criado_em)
    from public.membresia_processos p join public.pessoas pe on pe.id = p.pessoa_id
    where (p_status is null and p.status not in ('validado','encerrado')) or p.status = p_status), '[]'::jsonb);
end $$;


--
-- Name: secretaria_publicar_termo(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_publicar_termo(p_termo uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare t public.termos;
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  select * into t from public.termos where id = p_termo for update;
  if not found or t.status <> 'rascunho' then raise exception 'Rascunho não encontrado.' using errcode = 'P0002'; end if;
  if t.texto ~ '⟦' then raise exception 'Complete os campos marcados com ⟦ ⟧ antes de publicar.' using errcode = '22023'; end if;
  update public.termos set status = 'substituido' where tipo = t.tipo and status = 'vigente';
  update public.termos set status = 'vigente', publicado_por = auth.uid(), publicado_em = now(),
         texto_hash = encode(sha256(convert_to(titulo || E'\n' || texto, 'UTF8')), 'hex') where id = t.id;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: secretaria_registrar_conclusao_anterior(uuid, uuid, date, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_registrar_conclusao_anterior(p_pessoa uuid, p_curso uuid, p_concluido_em date, p_comprovacao text, p_documento uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v uuid;
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  if p_concluido_em is null then raise exception 'Informe quando o curso foi concluído.' using errcode = '22023'; end if;
  if char_length(btrim(coalesce(p_comprovacao, ''))) < 10 then
    raise exception 'Descreva a comprovação (ex.: lista de presença de 2019 conferida, certificado apresentado).' using errcode = '22023'; end if;
  if p_documento is not null and not exists (select 1 from public.documentos where id = p_documento and pessoa_id = p_pessoa) then
    raise exception 'Documento inválido.' using errcode = '22023'; end if;
  if public.curso_concluido(p_pessoa, p_curso) then raise exception 'Este curso já consta como concluído.' using errcode = '23505'; end if;
  insert into public.cursos_conclusoes_anteriores (pessoa_id, curso_id, concluido_em, comprovacao, documento_id, registrado_por)
  values (p_pessoa, p_curso, p_concluido_em, btrim(p_comprovacao), p_documento, auth.uid()) returning id into v;
  if p_curso = public.curso_id_por_slug('novos-membros') then
    update public.membresia_processos set status = 'aguardando_validacao' where pessoa_id = p_pessoa and status in ('interesse','em_curso');
  end if;
  return jsonb_build_object('ok', true, 'id', v);
end $$;


--
-- Name: secretaria_registrar_consentimento(uuid, text, uuid, text, jsonb, jsonb, uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_registrar_consentimento(p_pessoa uuid, p_tipo text, p_termo uuid, p_decisao text, p_escopo jsonb, p_responsavel jsonb, p_documento uuid, p_data_nascimento date) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v uuid;
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  if p_tipo not in ('imagem_voz','participacao_curso') then
    raise exception 'O termo de voluntariado é registrado na candidatura.' using errcode = '22023'; end if;
  if p_documento is not null and not exists (select 1 from public.documentos where id = p_documento and pessoa_id = p_pessoa) then
    raise exception 'Documento inválido.' using errcode = '22023'; end if;
  if p_data_nascimento is not null then update public.pessoas set data_nascimento = p_data_nascimento where id = p_pessoa and data_nascimento is null; end if;
  v := public.registrar_consentimento(p_pessoa, p_tipo, p_termo, p_decisao, p_escopo, p_responsavel, 'secretaria', 'avulso', null, p_documento);
  return jsonb_build_object('ok', true, 'id', v);
end $$;


--
-- Name: secretaria_registrar_pagamento_presencial(uuid, text, numeric, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_registrar_pagamento_presencial(p_inscricao uuid, p_metodo text, p_valor numeric, p_pago_em date, p_observacao text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.inscricoes; v_id uuid;
begin
  if not public.e_secretaria() then raise exception 'Somente a Secretaria registra pagamento presencial.' using errcode = '42501'; end if;
  select * into i from public.inscricoes where id = p_inscricao for update;
  if not found then raise exception 'Inscrição não encontrada.' using errcode = 'P0002'; end if;
  if i.status <> 'aguardando_pagamento' then raise exception 'Esta inscrição não está aguardando pagamento.' using errcode = '22023'; end if;
  if p_metodo not in ('dinheiro','cartao_presencial','pix','transferencia','outro') then raise exception 'Forma de pagamento inválida.' using errcode = '22023'; end if;
  if p_valor is null or p_valor <= 0 then raise exception 'Informe o valor recebido.' using errcode = '22023'; end if;
  if p_pago_em is null or p_pago_em > current_date then raise exception 'Informe a data do recebimento.' using errcode = '22023'; end if;
  insert into public.pagamentos (inscricao_id, metodo, origem, valor, pago_em, status, observacao, registrado_por)
  values (p_inscricao, p_metodo, 'secretaria', p_valor, p_pago_em, 'aguardando_comprovante', nullif(btrim(p_observacao), ''), auth.uid())
  returning id into v_id;
  perform public.notificar('TESOURARIA', null, 'pagamento_presencial', 'Pagamento presencial registrado',
    'Inscrição ' || i.protocolo || ': ' || to_char(p_valor, 'FM999G990D00') || ' recebido pela Secretaria. Aguarda o recibo e a validação da Tesouraria.',
    jsonb_build_object('pagamento_id', v_id, 'inscricao_id', i.id, 'protocolo', i.protocolo));
  return jsonb_build_object('ok', true, 'pagamento_id', v_id);
end $$;


--
-- Name: secretaria_revogar_consentimento(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_revogar_consentimento(p_consentimento uuid, p_via text, p_motivo text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare c public.consentimentos; v_n int;
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  if p_via not in ('titular','responsavel','secretaria') then raise exception 'Informe quem pediu a revogação.' using errcode = '22023'; end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 5 then raise exception 'Informe o motivo ou como o pedido foi feito.' using errcode = '22023'; end if;
  select * into c from public.consentimentos where id = p_consentimento for update;
  if not found then raise exception 'Consentimento não encontrado.' using errcode = 'P0002'; end if;
  if c.revogado_em is not null then raise exception 'Já revogado.' using errcode = '22023'; end if;
  update public.consentimentos set revogado_em = now(), revogado_via = p_via, revogado_por = auth.uid(), motivo_revogacao = btrim(p_motivo) where id = c.id;
  -- revogar o termo de adesão = deixar o voluntariado (o vínculo é desativado, não apagado)
  if c.tipo = 'voluntariado' then
    update public.ministerio_membros set ativo = false where pessoa_id = c.pessoa_id and funcao = 'voluntario' and ativo;
    get diagnostics v_n = row_count;
  end if;
  return jsonb_build_object('ok', true, 'vinculos_desativados', coalesce(v_n, 0));
end $$;


--
-- Name: secretaria_salvar_cerimonia(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_salvar_cerimonia(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_data date := nullif(p->>'data', '')::date; v_hora text := nullif(btrim(p->>'horario'), '');
        v_local text := nullif(btrim(p->>'local'), ''); v_status text := coalesce(nullif(p->>'status', ''), 'planejada'); c public.cerimonias;
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p->>'titulo', ''))) < 3 then raise exception 'Informe o título da cerimônia (mínimo 3 caracteres).' using errcode = '22023'; end if;
  if v_data is null or v_hora is null or v_local is null then raise exception 'Informe data, horário e local da cerimônia.' using errcode = '22023'; end if;
  if v_hora !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Horário no formato HH:MM (ex.: 19:30).' using errcode = '22023'; end if;
  if coalesce(p->>'tipo', 'culto') not in ('culto','apresentacao','outra') then raise exception 'Tipo inválido.' using errcode = '22023'; end if;
  if v_status not in ('planejada','cancelada') then raise exception 'Para registrar que a cerimônia aconteceu, use "Marcar como realizada".' using errcode = '22023'; end if;
  if v_id is null then
    if v_data < current_date then raise exception 'A data da cerimônia já passou.' using errcode = '22023'; end if;
    insert into public.cerimonias (titulo, tipo, data, horario, local, evento_ref, responsavel, status, observacoes)
    values (btrim(p->>'titulo'), coalesce(p->>'tipo', 'culto'), v_data, v_hora, v_local, nullif(btrim(p->>'evento_ref'), ''), nullif(btrim(p->>'responsavel'), ''),
            v_status, nullif(btrim(p->>'observacoes'), '')) returning id into v_id;
  else
    select * into c from public.cerimonias where id = v_id for update;
    if not found then raise exception 'Cerimônia não encontrada.' using errcode = 'P0002'; end if;
    if c.status = 'realizada' then raise exception 'Cerimônia já realizada não pode ser alterada.' using errcode = '22023'; end if;
    if v_status = 'cancelada' and exists (select 1 from public.certificados where cerimonia_id = v_id and status <> 'cancelado') then
      raise exception 'Antes de cancelar, transfira os certificados para outra cerimônia.' using errcode = '22023'; end if;
    update public.cerimonias set titulo = btrim(p->>'titulo'), tipo = coalesce(p->>'tipo', tipo), data = v_data, horario = v_hora, local = v_local,
      evento_ref = nullif(btrim(p->>'evento_ref'), ''), responsavel = nullif(btrim(p->>'responsavel'), ''), status = v_status,
      observacoes = nullif(btrim(p->>'observacoes'), '') where id = v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $_$;


--
-- Name: secretaria_salvar_modelo_certificado(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_salvar_modelo_certificado(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v jsonb;
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  if jsonb_array_length(coalesce(p->'assinaturas', '[]'::jsonb)) > 3 then raise exception 'No máximo 3 assinaturas.' using errcode = '22023'; end if;
  v := jsonb_build_object('igreja', left(btrim(coalesce(p->>'igreja', '')), 120), 'cidade', left(btrim(coalesce(p->>'cidade', '')), 80),
         'texto', left(btrim(coalesce(p->>'texto', '')), 400),
         'assinaturas', coalesce((select jsonb_agg(jsonb_build_object('nome', left(btrim(a->>'nome'), 80), 'cargo', left(btrim(a->>'cargo'), 80)))
                                  from jsonb_array_elements(coalesce(p->'assinaturas', '[]'::jsonb)) a where btrim(coalesce(a->>'nome', '')) <> ''), '[]'::jsonb));
  insert into public.configuracoes (chave, valor, publico, atualizado_por) values ('certificado_modelo', v, false, auth.uid())
  on conflict (chave) do update set valor = excluded.valor, atualizado_em = now(), atualizado_por = auth.uid();
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: secretaria_salvar_termo(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_salvar_termo(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_tipo text := p->>'tipo';
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  if v_id is null then
    if exists (select 1 from public.termos where tipo = v_tipo and status = 'rascunho') then
      raise exception 'Já existe um rascunho deste termo. Edite-o.' using errcode = '23505'; end if;
    insert into public.termos (tipo, versao, titulo, resumo, texto, exige_novo_aceite, criado_por)
    values (v_tipo, coalesce((select max(versao) from public.termos where tipo = v_tipo), 0) + 1, btrim(p->>'titulo'),
            nullif(btrim(p->>'resumo'), ''), btrim(p->>'texto'), coalesce((p->>'exige_novo_aceite')::boolean, false), auth.uid()) returning id into v_id;
  else
    update public.termos set titulo = btrim(p->>'titulo'), resumo = nullif(btrim(p->>'resumo'), ''), texto = btrim(p->>'texto'),
           exige_novo_aceite = coalesce((p->>'exige_novo_aceite')::boolean, false) where id = v_id and status = 'rascunho';
    if not found then raise exception 'Só rascunhos podem ser editados. Para mudar um termo publicado, crie uma nova versão.' using errcode = '22023'; end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;


--
-- Name: secretaria_solicitar_beneficio(uuid, text, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_solicitar_beneficio(p_inscricao uuid, p_tipo text, p_valor_desconto numeric, p_motivo text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.inscricoes; v_id uuid;
begin
  if not (public.e_secretaria() or public.e_tesouraria()) then raise exception 'Acesso restrito à Secretaria e à Tesouraria.' using errcode = '42501'; end if;
  select * into i from public.inscricoes where id = p_inscricao;
  if not found then raise exception 'Inscrição não encontrada.' using errcode = 'P0002'; end if;
  if i.valor_bruto <= 0 then raise exception 'Esta inscrição não tem valor.' using errcode = '22023'; end if;
  if i.status in ('cancelada','concluida') then raise exception 'Inscrição cancelada ou concluída.' using errcode = '22023'; end if;
  if p_tipo = 'bolsa_parcial' and (p_valor_desconto is null or p_valor_desconto <= 0 or p_valor_desconto >= i.valor_bruto) then
    raise exception 'Bolsa parcial: informe um desconto maior que zero e menor que o valor (%).', i.valor_bruto using errcode = '22023'; end if;
  if exists (select 1 from public.beneficios where inscricao_id = p_inscricao and status = 'solicitado') then
    raise exception 'Já existe um pedido de bolsa ou isenção aguardando a Tesouraria.' using errcode = '22023'; end if;
  insert into public.beneficios (inscricao_id, tipo, valor_desconto, motivo, solicitado_por)
  values (p_inscricao, p_tipo, case when p_tipo = 'bolsa_parcial' then p_valor_desconto end, btrim(p_motivo), auth.uid()) returning id into v_id;
  perform public.notificar('TESOURARIA', null, 'beneficio_solicitado', 'Pedido de bolsa ou isenção',
    'Inscrição ' || i.protocolo || ': ' || replace(p_tipo, '_', ' ') || '. Motivo: ' || btrim(p_motivo), jsonb_build_object('beneficio_id', v_id, 'inscricao_id', i.id, 'protocolo', i.protocolo));
  return jsonb_build_object('ok', true, 'id', v_id);
exception when check_violation then raise exception 'Informe um motivo (mínimo 3 caracteres) e o tipo do benefício.' using errcode = '22023';
end $$;


--
-- Name: secretaria_termos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_termos() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'tipo', t.tipo, 'versao', t.versao, 'titulo', t.titulo, 'resumo', t.resumo, 'texto', t.texto,
      'exige_novo_aceite', t.exige_novo_aceite, 'status', t.status, 'publicado_em', t.publicado_em, 'criado_em', t.criado_em,
      'aceites', (select count(*) from public.consentimentos c where c.termo_id = t.id and c.decisao = 'aceito'),
      'pendencias', (select array_agg(m[1]) from regexp_matches(t.texto, '⟦([^⟧]*)⟧', 'g') m)) order by t.tipo, t.versao desc)
    from public.termos t), '[]'::jsonb);
end $$;


--
-- Name: secretaria_validar_membresia(uuid, text, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_validar_membresia(p_pessoa uuid, p_situacao text, p_membro_desde date, p_observacao text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_secretaria() then raise exception 'Somente a Secretaria valida membresia.' using errcode = '42501'; end if;
  if p_situacao not in ('visitante','em_integracao','membro','inativo') then raise exception 'Situação inválida.' using errcode = '22023'; end if;
  if p_situacao = 'membro' and p_membro_desde is null then raise exception 'Informe a data em que a pessoa se tornou membro.' using errcode = '22023'; end if;
  -- validação administrativa: exige o fundamento (nunca autodeclaração)
  if p_situacao = 'membro' and char_length(btrim(coalesce(p_observacao, ''))) < 10 then
    raise exception 'Informe o fundamento da validação (ex.: batismo em 12/05/2019, carta de transferência recebida, ata da assembleia).' using errcode = '22023'; end if;
  update public.pessoas set situacao_membresia = p_situacao,
         membro_desde = case when p_situacao = 'membro' then p_membro_desde else membro_desde end,
         membresia_validada_por = case when p_situacao = 'membro' then auth.uid() else membresia_validada_por end,
         membresia_validada_em = case when p_situacao = 'membro' then now() else membresia_validada_em end
   where id = p_pessoa;
  if not found then raise exception 'Pessoa não encontrada.' using errcode = 'P0002'; end if;
  if p_situacao = 'membro' then
    update public.membresia_processos set status = 'validado', encerrado_em = now() where pessoa_id = p_pessoa and status not in ('validado','encerrado');
  end if;
  insert into public.auditoria (ator, acao, tabela, registro, detalhes)
  values (auth.uid(), 'membresia_validada', 'pessoas', p_pessoa::text, jsonb_build_object('situacao', p_situacao, 'membro_desde', p_membro_desde, 'observacao', nullif(btrim(p_observacao), '')));
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: secretaria_vincular_cerimonia(uuid, uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.secretaria_vincular_cerimonia(p_cerimonia uuid, p_certificados uuid[]) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare x uuid; n int := 0;
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  foreach x in array coalesce(p_certificados, '{}') loop
    perform public.secretaria_certificado(x, 'vincular', jsonb_build_object('cerimonia_id', p_cerimonia)); n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'vinculados', n);
end $$;


--
-- Name: servico_criar_usuario(uuid, uuid, text, text, text, text, text[], jsonb, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servico_criar_usuario(p_ator uuid, p_usuario uuid, p_nome text, p_telefone text, p_email text, p_perfil text, p_atribuicoes text[], p_ministerios jsonb, p_solicitacao uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_pessoa uuid; v_email text := lower(btrim(p_email)); v_item jsonb; v_bootstrap boolean;
begin
  -- Primeiros MASTERs: permitido só pela chave de serviço e só enquanto
  -- nenhum MASTER concluiu o primeiro acesso.
  v_bootstrap := p_ator is null and p_perfil = 'MASTER'
                 and not exists (select 1 from public.perfis where perfil = 'MASTER' and ativo and not deve_trocar_senha);
  if not v_bootstrap and not public.e_master_uid(p_ator) then
    raise exception 'Somente o MASTER pode criar usuários.' using errcode = '42501'; end if;
  if p_perfil not in ('MASTER','LIDER','VOLUNTARIO') then
    raise exception 'Perfil inválido.' using errcode = '22023'; end if;
  perform set_config('app.ator', coalesce(p_ator::text, p_usuario::text), true);

  if p_solicitacao is not null then
    perform 1 from public.solicitacoes where id = p_solicitacao and tipo = 'acesso' and status = 'pendente' for update;
    if not found then raise exception 'Solicitação não encontrada ou já analisada.' using errcode = 'P0002'; end if;
  end if;

  -- Reaproveita o cadastro existente da pessoa (sem duplicar)
  select id into v_pessoa from public.pessoas where email = v_email and arquivado_em is null;
  if v_pessoa is null then
    insert into public.pessoas (usuario_id, nome, telefone, email, origem)
    values (p_usuario, regexp_replace(btrim(p_nome), '\s+', ' ', 'g'), nullif(public.so_digitos(p_telefone), ''), v_email,
            case when p_solicitacao is null then 'secretaria' else 'site' end)
    returning id into v_pessoa;
  else
    if exists (select 1 from public.perfis where pessoa_id = v_pessoa) then
      raise exception 'Esta pessoa já tem acesso.' using errcode = '23505'; end if;
    update public.pessoas set usuario_id = p_usuario,
           telefone = coalesce(telefone, nullif(public.so_digitos(p_telefone), '')) where id = v_pessoa;
  end if;

  insert into public.perfis (id, pessoa_id, perfil, atribuicoes, ativo, deve_trocar_senha, aprovado_por, aprovado_em)
  values (p_usuario, v_pessoa, p_perfil, coalesce(p_atribuicoes, '{}'), true, true, p_ator, now());

  for v_item in select * from jsonb_array_elements(coalesce(p_ministerios, '[]'::jsonb)) loop
    insert into public.ministerio_membros (pessoa_id, ministerio_id, funcao)
    values (v_pessoa, (v_item ->> 'ministerio_id')::uuid, v_item ->> 'funcao')
    on conflict (pessoa_id, ministerio_id) do update set funcao = excluded.funcao, ativo = true;
  end loop;

  if p_solicitacao is not null then
    update public.solicitacoes set status = 'aprovada', analisado_por = p_ator, analisado_em = now(), pessoa_id = v_pessoa
     where id = p_solicitacao;
  end if;

  insert into public.auditoria (ator, acao, tabela, registro, detalhes)
  values (p_ator, case when p_solicitacao is null then 'usuario_criado' else 'solicitacao_aprovada' end,
          'perfis', p_usuario::text,
          jsonb_build_object('email', v_email, 'perfil', p_perfil, 'atribuicoes', coalesce(p_atribuicoes,'{}'),
                             'ministerios', coalesce(p_ministerios,'[]'::jsonb), 'solicitacao', p_solicitacao,
                             'primeiro_master', v_bootstrap));
  return jsonb_build_object('ok', true, 'pessoa_id', v_pessoa);
end $$;


--
-- Name: servico_definir_ativo(uuid, uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servico_definir_ativo(p_ator uuid, p_usuario uuid, p_ativo boolean) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_master_uid(p_ator) then raise exception 'Somente o MASTER pode ativar ou desativar contas.' using errcode = '42501'; end if;
  if p_ator = p_usuario and not p_ativo then raise exception 'Você não pode desativar a sua própria conta.' using errcode = '22023'; end if;
  perform set_config('app.ator', p_ator::text, true);
  update public.perfis set ativo = p_ativo where id = p_usuario;
  if not found then raise exception 'Usuário não encontrado.' using errcode = 'P0002'; end if;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: servico_marcar_senha_temporaria(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servico_marcar_senha_temporaria(p_ator uuid, p_usuario uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_master_uid(p_ator) then raise exception 'Somente o MASTER pode gerar senha temporária.' using errcode = '42501'; end if;
  perform set_config('app.ator', p_ator::text, true);
  update public.perfis set deve_trocar_senha = true where id = p_usuario;
  if not found then raise exception 'Usuário não encontrado.' using errcode = 'P0002'; end if;
  insert into public.auditoria (ator, acao, tabela, registro) values (p_ator, 'senha_temporaria_gerada', 'perfis', p_usuario::text);
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: servico_registrar_comprovante(uuid, uuid, uuid, text, numeric, date, text, text, text, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servico_registrar_comprovante(p_ator uuid, p_inscricao uuid, p_pagamento uuid, p_metodo text, p_valor numeric, p_pago_em date, p_path text, p_nome text, p_mime text, p_tamanho integer, p_hash text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.inscricoes; p public.pagamentos; v_via text := case when p_ator is null then 'link' else 'painel' end;
begin
  perform set_config('app.ator', coalesce(p_ator::text, ''), true);
  select * into i from public.inscricoes where id = p_inscricao for update;
  if not found then raise exception 'Inscrição não encontrada.' using errcode = 'P0002'; end if;
  if i.status <> 'aguardando_pagamento' then raise exception 'Esta inscrição não está aguardando pagamento (situação: %).', i.status using errcode = '22023'; end if;
  if p_pagamento is not null then
    select * into p from public.pagamentos where id = p_pagamento and inscricao_id = p_inscricao for update;
    if not found then raise exception 'Pagamento não encontrado.' using errcode = 'P0002'; end if;
    if p.status not in ('aguardando_comprovante','novo_comprovante_solicitado','em_analise') then
      raise exception 'Este pagamento não aceita novo comprovante (situação: %).', p.status using errcode = '22023'; end if;
  else
    -- participante: reaproveita pagamento em que a Tesouraria pediu novo comprovante
    select * into p from public.pagamentos where inscricao_id = p_inscricao and origem = 'participante'
       and status in ('novo_comprovante_solicitado','aguardando_comprovante','em_analise') order by registrado_em desc limit 1 for update;
    if not found then
      if p_metodo not in ('pix','transferencia','outro') then raise exception 'Escolha a forma de pagamento.' using errcode = '22023'; end if;
      if p_valor is null or p_valor <= 0 then raise exception 'Informe o valor pago.' using errcode = '22023'; end if;
      insert into public.pagamentos (inscricao_id, metodo, origem, valor, pago_em, status)
      values (p_inscricao, p_metodo, 'participante', p_valor, p_pago_em, 'aguardando_comprovante') returning * into p;
    elsif p.status = 'em_analise' and p_ator is null then
      raise exception 'Já existe um comprovante em análise pela Tesouraria. Aguarde o retorno.' using errcode = '22023';
    end if;
  end if;
  update public.comprovantes set situacao = 'substituido' where pagamento_id = p.id and situacao = 'atual';
  insert into public.comprovantes (pagamento_id, arquivo_path, nome_original, tipo_mime, tamanho, hash_sha256, enviado_por, enviado_via)
  values (p.id, p_path, left(p_nome, 200), p_mime, p_tamanho, p_hash, p_ator, v_via);
  update public.pagamentos set status = 'em_analise', analisado_por = null, analisado_em = null where id = p.id;
  perform public.notificar('TESOURARIA', null, 'comprovante_recebido', 'Comprovante para análise',
    'Inscrição ' || i.protocolo || ': comprovante de ' || to_char(p.valor, 'FM999G990D00') || ' enviado ' || case when v_via = 'link' then 'pelo participante.' else 'pela Secretaria.' end,
    jsonb_build_object('pagamento_id', p.id, 'inscricao_id', i.id, 'protocolo', i.protocolo));
  return jsonb_build_object('ok', true, 'pagamento_id', p.id, 'status_inscricao', i.status);
end $$;


--
-- Name: servico_registrar_documento(uuid, uuid, text, text, text, text, text, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servico_registrar_documento(p_ator uuid, p_pessoa uuid, p_tipo text, p_descricao text, p_path text, p_nome text, p_mime text, p_tamanho integer, p_hash text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_id uuid;
begin
  perform set_config('app.ator', p_ator::text, true);
  insert into public.documentos (pessoa_id, tipo, descricao, arquivo_path, nome_original, tipo_mime, tamanho, hash_sha256, enviado_por)
  values (p_pessoa, p_tipo, nullif(btrim(p_descricao), ''), p_path, left(p_nome, 200), p_mime, p_tamanho, p_hash, p_ator) returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;


--
-- Name: servico_validar_link(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servico_validar_link(p_protocolo text, p_chave text) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select id from public.inscricoes where protocolo = upper(btrim(p_protocolo))
     and chave_hash = encode(sha256(convert_to(coalesce(p_chave, ''), 'UTF8')), 'hex')
$$;


--
-- Name: site_apagar_imagem(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.site_apagar_imagem(p_foto text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if p_foto like 'site/%' then
    delete from armazenamento.objetos where espaco = 'site' and caminho = substr(p_foto, 6);
  end if;
end $$;


--
-- Name: site_conteudo_publico(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.site_conteudo_publico() RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select jsonb_build_object(
    'contatos', (select valor from public.configuracoes where chave = 'site.contatos'),
    'galeria_home', (select valor from public.configuracoes where chave = 'site.galeria_home'),
    'colegio_etapas', coalesce((select jsonb_agg(jsonb_build_object('slug', e.slug, 'titulo', e.titulo, 'subtitulo', e.subtitulo,
         'descricao', e.descricao, 'objetivos', to_jsonb(e.objetivos), 'diferenciais', to_jsonb(e.diferenciais),
         'faixa_etaria', e.faixa_etaria, 'foto', e.foto, 'foto_alt', e.foto_alt) order by e.ordem)
       from public.colegio_etapas e where e.ativo), '[]'::jsonb))
$$;


--
-- Name: site_salvar_contatos(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.site_salvar_contatos(p_contatos jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare g text;
begin
  if not public.e_master() then raise exception 'Somente o MASTER altera os contatos do site.' using errcode = '42501'; end if;
  foreach g in array array['igreja','celulas','colegio'] loop
    if jsonb_typeof(p_contatos->g) <> 'object' then raise exception 'Dados incompletos (%).', g using errcode = '22023'; end if;
    perform public.site_validar_contato(p_contatos->g, 'telefone', 'telefone');
    perform public.site_validar_contato(p_contatos->g, 'whatsapp', 'telefone');
    perform public.site_validar_contato(p_contatos->g, 'instagram', 'arroba');
    perform public.site_validar_contato(p_contatos->g, 'email', 'email');
    perform public.site_validar_contato(p_contatos->g, 'site', 'url');
    perform public.site_validar_contato(p_contatos->g, 'youtube_url', 'url');
    -- perfis sempre com @ (ex.: betelflamengo → @betelflamengo)
    if coalesce(p_contatos->g->>'instagram', '') ~ '^[A-Za-z0-9._]' then
      p_contatos := jsonb_set(p_contatos, array[g, 'instagram'], to_jsonb('@' || btrim(p_contatos->g->>'instagram')));
    end if;
  end loop;
  insert into public.configuracoes (chave, valor, publico, atualizado_por) values ('site.contatos', p_contatos, true, auth.uid())
    on conflict (chave) do update set valor = excluded.valor, publico = true, atualizado_em = now(), atualizado_por = auth.uid();
  return public.site_conteudo_publico();
end $$;


--
-- Name: site_salvar_galeria(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.site_salvar_galeria(p_fotos jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare f jsonb; v_antes jsonb; v_ref text;
begin
  if not public.e_master() then raise exception 'Somente o MASTER altera as fotos da Home.' using errcode = '42501'; end if;
  if jsonb_typeof(p_fotos) <> 'array' or jsonb_array_length(p_fotos) > 16 then raise exception 'Envie até 16 fotos.' using errcode = '22023'; end if;
  for f in select * from jsonb_array_elements(p_fotos) loop
    v_ref := f->>'foto';
    if v_ref is null or not (v_ref ~ '^img/[a-z0-9._/-]+$' or (v_ref ~ '^site/home/[0-9a-f-]{36}\.(jpg|png|webp)$' and public.imagem_existe('site', substr(v_ref, 6)))) then
      raise exception 'Foto inválida na galeria.' using errcode = '22023'; end if;
    if char_length(coalesce(f->>'alt', '')) not between 3 and 200 then raise exception 'Descreva cada foto (texto alternativo).' using errcode = '22023'; end if;
  end loop;
  select valor into v_antes from public.configuracoes where chave = 'site.galeria_home';
  update public.configuracoes set valor = p_fotos, atualizado_em = now(), atualizado_por = auth.uid() where chave = 'site.galeria_home';
  -- apaga do armazenamento as fotos enviadas que saíram da galeria
  perform public.site_apagar_imagem(x.v->>'foto') from jsonb_array_elements(coalesce(v_antes, '[]'::jsonb)) as x(v)
    where not exists (select 1 from jsonb_array_elements(p_fotos) as y(v) where y.v->>'foto' = x.v->>'foto');
  return public.site_conteudo_publico();
end $_$;


--
-- Name: site_validar_contato(jsonb, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.site_validar_contato(p jsonb, p_campo text, p_tipo text) RETURNS void
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $_$
declare v text := btrim(coalesce(p->>p_campo, ''));
begin
  if v = '' then return; end if;
  if p_tipo = 'telefone' and regexp_replace(v, '\D', '', 'g') !~ '^[0-9]{10,11}$' then
    raise exception 'Telefone inválido em "%": use DDD + número.', p_campo using errcode = '22023'; end if;
  if p_tipo = 'url' and v !~ '^https://[^\s<>"]+$' then raise exception 'Endereço inválido em "%": use https://…', p_campo using errcode = '22023'; end if;
  if p_tipo = 'arroba' and v !~ '^@?[A-Za-z0-9._]{2,60}$' then raise exception 'Perfil inválido em "%".', p_campo using errcode = '22023'; end if;
  if p_tipo = 'email' and v !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'E-mail inválido em "%".', p_campo using errcode = '22023'; end if;
end $_$;


--
-- Name: slugify(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.slugify(p text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select trim(both '-' from regexp_replace(lower(translate(coalesce(p,''),
    'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
    'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')), '[^a-z0-9]+', '-', 'g'))
$$;


--
-- Name: so_digitos(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.so_digitos(p text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$ select regexp_replace(coalesce(p,''), '\D', '', 'g') $$;


--
-- Name: solicitar_acesso(text, text, text, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.solicitar_acesso(p_nome text, p_telefone text, p_email text, p_ministerio uuid, p_funcao text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare v_email text := lower(btrim(coalesce(p_email,'')));
        v_tel text := public.so_digitos(p_telefone);
        v_nome text := regexp_replace(btrim(coalesce(p_nome,'')), '\s+', ' ', 'g');
        v_id uuid;
begin
  if char_length(v_nome) < 3 or v_nome !~ '\s' then
    raise exception 'Informe o nome completo.' using errcode = '22023'; end if;
  if v_tel !~ '^[0-9]{10,13}$' then
    raise exception 'Informe um telefone válido, com DDD.' using errcode = '22023'; end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Informe um e-mail válido.' using errcode = '22023'; end if;
  if p_funcao not in ('lider','voluntario') then
    raise exception 'Escolha a função: Líder ou Voluntário.' using errcode = '22023'; end if;
  if not exists (select 1 from public.ministerios m where m.id = p_ministerio and m.ativo) then
    raise exception 'Escolha um ministério da lista.' using errcode = '22023'; end if;
  -- Limite de envios repetidos pelo mesmo e-mail (não é critério de autorização)
  if (select count(*) from public.solicitacoes s
      where s.email = v_email and s.criado_em > now() - interval '1 hour') >= 3 then
    raise exception 'Muitas solicitações com este e-mail. Tente novamente mais tarde.' using errcode = '22023'; end if;
  -- Respostas neutras: não revelam se o e-mail já tem conta
  if exists (select 1 from public.pessoas pe join public.perfis pf on pf.pessoa_id = pe.id where pe.email = v_email)
     or exists (select 1 from public.solicitacoes s where s.email = v_email and s.tipo = 'acesso' and s.status = 'pendente') then
    return jsonb_build_object('ok', true);
  end if;
  insert into public.solicitacoes (tipo, nome, telefone, email, ministerio_id, funcao_pretendida)
  values ('acesso', v_nome, v_tel, v_email, p_ministerio, p_funcao)
  returning id into v_id;
  return jsonb_build_object('ok', true);
end $_$;


--
-- Name: tem_atribuicao(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tem_atribuicao(p_atribuicao text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce((select p.ativo and not p.deve_trocar_senha and p_atribuicao = any(p.atribuicoes)
                   from public.perfis p where p.id = auth.uid()), false)
$$;


--
-- Name: termos_vigentes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.termos_vigentes() RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(jsonb_object_agg(tipo, jsonb_build_object('id', id, 'versao', versao, 'titulo', titulo, 'resumo', resumo, 'texto', texto)), '{}'::jsonb)
    from public.termos where status = 'vigente'
$$;


--
-- Name: tesouraria_analisar_beneficio(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tesouraria_analisar_beneficio(p_beneficio uuid, p_acao text, p_observacao text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare b public.beneficios; i public.inscricoes; v_desc numeric; v_st text;
begin
  if not public.e_tesouraria() then raise exception 'Somente a Tesouraria concede bolsas e isenções.' using errcode = '42501'; end if;
  select * into b from public.beneficios where id = p_beneficio for update;
  if not found then raise exception 'Pedido não encontrado.' using errcode = 'P0002'; end if;
  if b.status <> 'solicitado' then raise exception 'Este pedido já foi analisado.' using errcode = '22023'; end if;
  select * into i from public.inscricoes where id = b.inscricao_id for update;
  if p_acao = 'aprovar' then
    update public.beneficios set status = 'aprovado', analisado_por = auth.uid(), analisado_em = now(), observacao_analise = nullif(btrim(p_observacao), '') where id = b.id;
    select least(i.valor_bruto, coalesce(sum(case when x.tipo = 'bolsa_parcial' then x.valor_desconto else i.valor_bruto end), 0)) into v_desc
      from public.beneficios x where x.inscricao_id = i.id and x.status = 'aprovado';
    update public.inscricoes set valor_desconto = v_desc, valor_final = i.valor_bruto - v_desc where id = i.id;
    v_st := public.financeiro_reavaliar(i.id);
  elsif p_acao = 'recusar' then
    if char_length(btrim(coalesce(p_observacao, ''))) < 3 then raise exception 'Informe o motivo da recusa.' using errcode = '22023'; end if;
    update public.beneficios set status = 'recusado', analisado_por = auth.uid(), analisado_em = now(), observacao_analise = btrim(p_observacao) where id = b.id;
    v_st := i.status;
  else raise exception 'Ação inválida.' using errcode = '22023';
  end if;
  perform public.notificar('SECRETARIA', null, 'beneficio_' || p_acao, case when p_acao = 'aprovar' then 'Bolsa/isenção aprovada' else 'Bolsa/isenção recusada' end,
    'Inscrição ' || i.protocolo || case when v_st = 'confirmada' and i.status <> 'confirmada' then ': inscrição confirmada.' else '.' end, jsonb_build_object('inscricao_id', i.id, 'protocolo', i.protocolo));
  return jsonb_build_object('ok', true, 'status_inscricao', v_st);
end $$;


--
-- Name: tesouraria_analisar_pagamento(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tesouraria_analisar_pagamento(p_pagamento uuid, p_acao text, p_observacao text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare p public.pagamentos; i public.inscricoes; v_st text;
begin
  if not public.e_tesouraria() then raise exception 'Somente a Tesouraria aprova ou recusa pagamentos.' using errcode = '42501'; end if;
  select * into p from public.pagamentos where id = p_pagamento for update;
  if not found then raise exception 'Pagamento não encontrado.' using errcode = 'P0002'; end if;
  if p.registrado_por = auth.uid() then raise exception 'Quem registrou o pagamento não pode analisá-lo.' using errcode = '42501'; end if;
  if p.status <> 'em_analise' then raise exception 'Só pagamentos em análise (com comprovante) podem ser analisados. Situação: %.', p.status using errcode = '22023'; end if;
  select * into i from public.inscricoes where id = p.inscricao_id for update;
  if p_acao = 'aprovar' then
    if not exists (select 1 from public.comprovantes where pagamento_id = p.id and situacao = 'atual') then
      raise exception 'Não há comprovante anexado a este pagamento.' using errcode = '22023'; end if;
    update public.pagamentos set status = 'aprovado', analisado_por = auth.uid(), analisado_em = now(), observacao_analise = nullif(btrim(p_observacao), '') where id = p.id;
    v_st := public.financeiro_reavaliar(i.id);
    perform public.notificar('SECRETARIA', null, 'pagamento_aprovado', 'Pagamento aprovado',
      'Inscrição ' || i.protocolo || ': pagamento de ' || to_char(p.valor, 'FM999G990D00') || ' aprovado pela Tesouraria' || case when v_st = 'confirmada' and i.status <> 'confirmada' then '. Inscrição confirmada.' else '.' end,
      jsonb_build_object('pagamento_id', p.id, 'inscricao_id', i.id, 'protocolo', i.protocolo));
  elsif p_acao in ('recusar', 'solicitar_novo') then
    if char_length(btrim(coalesce(p_observacao, ''))) < 5 then raise exception 'Explique o motivo para o participante (mínimo 5 caracteres).' using errcode = '22023'; end if;
    update public.pagamentos set status = case when p_acao = 'recusar' then 'recusado' else 'novo_comprovante_solicitado' end,
           analisado_por = auth.uid(), analisado_em = now(), observacao_analise = btrim(p_observacao) where id = p.id;
    perform public.notificar('SECRETARIA', null, 'pagamento_' || p_acao, case when p_acao = 'recusar' then 'Pagamento recusado' else 'Novo comprovante solicitado' end,
      'Inscrição ' || i.protocolo || ': ' || btrim(p_observacao), jsonb_build_object('pagamento_id', p.id, 'inscricao_id', i.id, 'protocolo', i.protocolo));
    v_st := i.status;
  else raise exception 'Ação inválida.' using errcode = '22023';
  end if;
  return jsonb_build_object('ok', true, 'status_inscricao', v_st);
end $$;


--
-- Name: tesouraria_beneficios(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tesouraria_beneficios(p_status text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_tesouraria() then raise exception 'Acesso restrito à Tesouraria.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'tipo', b.tipo, 'status', b.status, 'valor_desconto', b.valor_desconto, 'motivo', b.motivo,
      'solicitado_em', b.solicitado_em, 'analisado_em', b.analisado_em, 'observacao_analise', b.observacao_analise,
      'solicitado_por', (select pe2.nome from public.perfis pf join public.pessoas pe2 on pe2.id = pf.pessoa_id where pf.id = b.solicitado_por),
      'inscricao_id', i.id, 'protocolo', i.protocolo, 'nome', pe.nome, 'curso', c.titulo, 'valor_bruto', i.valor_bruto, 'valor_final', i.valor_final) order by b.solicitado_em desc)
    from public.beneficios b join public.inscricoes i on i.id = b.inscricao_id join public.pessoas pe on pe.id = i.pessoa_id
    join public.turmas t on t.id = i.turma_id join public.cursos c on c.id = t.curso_id where p_status is null or b.status = p_status), '[]'::jsonb);
end $$;


--
-- Name: tesouraria_dashboard(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tesouraria_dashboard(p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_de date := coalesce(p_de, date '2000-01-01'); v_ate date := coalesce(p_ate, current_date);
begin
  if not public.e_tesouraria() then raise exception 'Acesso restrito à Tesouraria.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'periodo', jsonb_build_object('de', p_de, 'ate', v_ate),
    'recebido', coalesce((select sum(valor) from public.pagamentos where status = 'aprovado' and analisado_em::date between v_de and v_ate), 0),
    'reembolsado', coalesce((select sum(valor) from public.reembolsos where realizado_em between v_de and v_ate), 0),
    'em_analise', jsonb_build_object('quantidade', (select count(*) from public.pagamentos where status = 'em_analise'), 'valor', coalesce((select sum(valor) from public.pagamentos where status = 'em_analise'), 0)),
    'aguardando_recibo', (select count(*) from public.pagamentos where status = 'aguardando_comprovante'),
    'a_receber', coalesce((select sum(greatest(i.valor_final - ((public.financeiro_inscricao(i.id))->>'liquido')::numeric, 0)) from public.inscricoes i where i.status = 'aguardando_pagamento'), 0),
    'inscricoes_pendentes', (select count(*) from public.inscricoes where status = 'aguardando_pagamento'),
    'beneficios_concedidos', coalesce((select sum(i.valor_desconto) from public.inscricoes i where i.valor_desconto > 0), 0),
    'beneficios_pendentes', (select count(*) from public.beneficios where status = 'solicitado'),
    'por_metodo', coalesce((select jsonb_object_agg(metodo, total) from (select metodo, sum(valor) total from public.pagamentos where status = 'aprovado' and analisado_em::date between v_de and v_ate group by metodo) m), '{}'::jsonb),
    'por_curso', coalesce((select jsonb_agg(jsonb_build_object('curso', x.curso, 'turma', x.turma, 'inscricoes', x.qtd, 'esperado', x.esperado, 'recebido', x.recebido) order by x.curso, x.turma)
        from (select c.titulo as curso, t.nome as turma, count(*) as qtd,
                     sum(case when i.status <> 'cancelada' then i.valor_final else 0 end) as esperado,
                     coalesce(sum(((public.financeiro_inscricao(i.id))->>'liquido')::numeric), 0) as recebido
              from public.turmas t join public.cursos c on c.id = t.curso_id join public.inscricoes i on i.turma_id = t.id
              where i.valor_bruto > 0 group by c.titulo, t.nome) x), '[]'::jsonb));
end $$;


--
-- Name: tesouraria_movimentos(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tesouraria_movimentos(p_de date, p_ate date) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_tesouraria() then raise exception 'Acesso restrito à Tesouraria.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(m order by m->>'data', m->>'tipo') from (
    select jsonb_build_object('tipo', 'entrada', 'data', p.analisado_em::date, 'pago_em', p.pago_em, 'valor', p.valor, 'metodo', p.metodo, 'origem', p.origem,
      'protocolo', i.protocolo, 'nome', pe.nome, 'curso', c.titulo, 'turma', t.nome,
      'aprovado_por', (select pe2.nome from public.perfis pf join public.pessoas pe2 on pe2.id = pf.pessoa_id where pf.id = p.analisado_por)) as m
    from public.pagamentos p join public.inscricoes i on i.id = p.inscricao_id join public.pessoas pe on pe.id = i.pessoa_id
    join public.turmas t on t.id = i.turma_id join public.cursos c on c.id = t.curso_id
    where p.status = 'aprovado' and p.analisado_em::date between p_de and p_ate
    union all
    select jsonb_build_object('tipo', 'reembolso', 'data', r.realizado_em, 'pago_em', r.realizado_em, 'valor', -r.valor, 'metodo', r.metodo, 'origem', 'tesouraria',
      'protocolo', i.protocolo, 'nome', pe.nome, 'curso', c.titulo, 'turma', t.nome, 'motivo', r.motivo,
      'aprovado_por', (select pe2.nome from public.perfis pf join public.pessoas pe2 on pe2.id = pf.pessoa_id where pf.id = r.registrado_por))
    from public.reembolsos r join public.inscricoes i on i.id = r.inscricao_id join public.pessoas pe on pe.id = i.pessoa_id
    join public.turmas t on t.id = i.turma_id join public.cursos c on c.id = t.curso_id
    where r.realizado_em between p_de and p_ate) s), '[]'::jsonb);
end $$;


--
-- Name: tesouraria_pagamentos(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tesouraria_pagamentos(p_filtros jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.e_tesouraria() then raise exception 'Acesso restrito à Tesouraria.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(x order by x->>'registrado_em') from (
    select jsonb_build_object('id', p.id, 'status', p.status, 'metodo', p.metodo, 'origem', p.origem, 'valor', p.valor, 'pago_em', p.pago_em,
      'observacao', p.observacao, 'registrado_em', p.registrado_em, 'observacao_analise', p.observacao_analise, 'analisado_em', p.analisado_em,
      'registrado_por', (select pe2.nome from public.perfis pf join public.pessoas pe2 on pe2.id = pf.pessoa_id where pf.id = p.registrado_por),
      'analisado_por', (select pe2.nome from public.perfis pf join public.pessoas pe2 on pe2.id = pf.pessoa_id where pf.id = p.analisado_por),
      'eu_registrei', p.registrado_por = auth.uid(),
      'inscricao_id', i.id, 'protocolo', i.protocolo, 'status_inscricao', i.status, 'nome', pe.nome, 'curso', c.titulo, 'turma', t.nome,
      'financeiro', public.financeiro_inscricao(i.id),
      'comprovantes', coalesce((select jsonb_agg(jsonb_build_object('id', cp.id, 'nome', cp.nome_original, 'tipo', cp.tipo_mime, 'tamanho', cp.tamanho,
          'enviado_em', cp.enviado_em, 'via', cp.enviado_via, 'situacao', cp.situacao) order by cp.enviado_em desc) from public.comprovantes cp where cp.pagamento_id = p.id), '[]'::jsonb)) as x
    from public.pagamentos p join public.inscricoes i on i.id = p.inscricao_id join public.pessoas pe on pe.id = i.pessoa_id
    join public.turmas t on t.id = i.turma_id join public.cursos c on c.id = t.curso_id
    where (p_filtros->>'status' is null or p.status = p_filtros->>'status')
      and (p_filtros->>'de' is null or p.registrado_em >= (p_filtros->>'de')::date)
      and (p_filtros->>'ate' is null or p.registrado_em < (p_filtros->>'ate')::date + 1)
    limit 1000) s), '[]'::jsonb);
end $$;


--
-- Name: tesouraria_registrar_reembolso(uuid, numeric, text, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tesouraria_registrar_reembolso(p_pagamento uuid, p_valor numeric, p_metodo text, p_realizado_em date, p_motivo text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare p public.pagamentos; i public.inscricoes; v_liq numeric; v_id uuid;
begin
  if not public.e_tesouraria() then raise exception 'Somente a Tesouraria registra reembolsos.' using errcode = '42501'; end if;
  select * into p from public.pagamentos where id = p_pagamento for update;
  if not found or p.status <> 'aprovado' then raise exception 'Só pagamentos aprovados podem ser reembolsados.' using errcode = '22023'; end if;
  select * into i from public.inscricoes where id = p.inscricao_id for update;
  v_liq := (public.financeiro_inscricao(i.id)->>'liquido')::numeric;
  if p_valor is null or p_valor <= 0 then raise exception 'Informe o valor do reembolso.' using errcode = '22023'; end if;
  if p_valor > p.valor - coalesce((select sum(valor) from public.reembolsos where pagamento_id = p.id), 0) then
    raise exception 'O reembolso não pode passar do valor ainda não reembolsado deste pagamento.' using errcode = '22023'; end if;
  if i.status not in ('cancelada') and v_liq - p_valor < i.valor_final then
    raise exception 'Reembolso só para inscrição cancelada ou para o valor pago a mais (pago a mais: %).', greatest(v_liq - i.valor_final, 0) using errcode = '22023'; end if;
  if p_realizado_em is null or p_realizado_em > current_date then raise exception 'Informe a data do reembolso.' using errcode = '22023'; end if;
  insert into public.reembolsos (inscricao_id, pagamento_id, valor, metodo, realizado_em, motivo, registrado_por)
  values (i.id, p.id, p_valor, p_metodo, p_realizado_em, btrim(p_motivo), auth.uid()) returning id into v_id;
  perform public.notificar('SECRETARIA', null, 'reembolso', 'Reembolso registrado', 'Inscrição ' || i.protocolo || ': reembolso de ' || to_char(p_valor, 'FM999G990D00') || '.',
    jsonb_build_object('inscricao_id', i.id, 'protocolo', i.protocolo));
  return jsonb_build_object('ok', true, 'id', v_id);
exception when check_violation then raise exception 'Informe o motivo do reembolso e uma forma válida.' using errcode = '22023';
end $$;


--
-- Name: texto_limpo(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.texto_limpo(p text, p_max integer) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select nullif(left(btrim(regexp_replace(coalesce(p, ''), '[\u0000-\u0008\u000B\u000C\u000E-\u001F]', '', 'g')), p_max), '')
$$;


--
-- Name: tg_agenda_escala(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_agenda_escala() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare x record; per record;
begin
  if tg_op = 'DELETE' then
    for x in select id from public.escala_eventos where evento_id = old.id and status in ('planejamento','publicada') loop
      perform set_config('app.escala_acao', 'cancelada_pela_agenda', true);
      perform public.escala_cancelar_interno(x.id, 'Evento excluído da Agenda');
      perform set_config('app.escala_acao', '', true);
    end loop;
    return old;
  end if;
  if (new.data::text, new.horario_inicio::text, new.horario_fim::text, new.horario, new.local) is distinct from
     (old.data::text, old.horario_inicio::text, old.horario_fim::text, old.horario, old.local) then
    select * into per from public.agenda_evento_periodo(new.id);
    for x in select id from public.escala_eventos where evento_id = new.id and status in ('planejamento','publicada') loop
      perform public.escala_aplicar_mudanca(x.id, jsonb_build_object('inicio', per.inicio, 'fim', per.fim, 'local', nullif(btrim(coalesce(new.local, '')), '')), 'agenda');
    end loop;
  end if;
  return new;
end $$;


--
-- Name: tg_agenda_evento(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_agenda_evento() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: tg_agenda_reserva(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_agenda_reserva() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: tg_atualizado_em(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_atualizado_em() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin new.atualizado_em := now(); return new; end $$;


--
-- Name: tg_auditar(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_auditar() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: tg_auditoria_imutavel(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_auditoria_imutavel() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin raise exception 'O histórico administrativo não pode ser alterado nem excluído.'; end $$;


--
-- Name: tg_certificado_conclusao(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_certificado_conclusao() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_valida boolean; v_cert uuid; v_nome text;
begin
  if new.status = 'concluida' and old.status is distinct from 'concluida' then
    -- conclusão registrada por quem pode validar = já validada
    v_valida := public.certificado_validador_uid(new.turma_id, new.concluida_por);
    perform set_config('app.cert_detalhe', jsonb_build_object('concluida_por', new.concluida_por, 'validada_na_conclusao', v_valida)::text, true);
    insert into public.certificados (inscricao_id, codigo, status, validado_por, validado_em)
    values (new.id, upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)),
            case when v_valida then 'aguardando_autorizacao' else 'aguardando_validacao' end,
            case when v_valida then new.concluida_por end, case when v_valida then now() end)
    on conflict (inscricao_id) do update set
      status = case when v_valida then 'aguardando_autorizacao' else 'aguardando_validacao' end,
      validado_por = case when v_valida then new.concluida_por end, validado_em = case when v_valida then now() end,
      autorizado_por = null, autorizado_em = null, motivo_cancelamento = null
      where public.certificados.status = 'cancelado' and public.certificados.entregue_em is null
    returning id into v_cert;
    perform set_config('app.cert_detalhe', '', true);
    select nome into v_nome from public.pessoas where id = new.pessoa_id;
    if v_valida then
      perform public.notificar('SECRETARIA', null, 'certificado_autorizar', 'Certificado para autorizar', v_nome || ' (' || new.protocolo || '): conclusão validada pela liderança. Autorize a emissão.', jsonb_build_object('inscricao_id', new.id));
    else
      perform public.notificar(null, r.perfil_id, 'certificado_validar', 'Conclusão para validar', v_nome || ' (' || new.protocolo || ') foi marcado(a) como concluído(a). Valide a conclusão.', jsonb_build_object('inscricao_id', new.id))
        from public.turma_responsaveis r where r.turma_id = new.turma_id and r.ativo;
    end if;
  elsif old.status = 'concluida' and new.status <> 'concluida' then
    v_nome := coalesce(nullif(current_setting('app.cert_detalhe', true), '')::jsonb->>'motivo', 'Conclusão desfeita');
    perform set_config('app.cert_detalhe', jsonb_build_object('motivo', v_nome)::text, true);
    update public.certificados set status = 'cancelado', motivo_cancelamento = v_nome where inscricao_id = new.id and status <> 'entregue';
    perform set_config('app.cert_detalhe', '', true);
  end if;
  return new;
end $$;


--
-- Name: tg_certificado_evento(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_certificado_evento() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_det jsonb := coalesce(nullif(current_setting('app.cert_detalhe', true), '')::jsonb, '{}'::jsonb);
        v_ator uuid := coalesce(auth.uid(), nullif(current_setting('app.ator', true), '')::uuid);
begin
  if tg_op = 'INSERT' then
    insert into public.certificados_eventos (certificado_id, evento, status_depois, ator, detalhes) values (new.id, 'criado', new.status, v_ator, v_det);
    return null;
  end if;
  if new.vezes_impresso > old.vezes_impresso then
    insert into public.certificados_eventos (certificado_id, evento, status_antes, status_depois, ator, detalhes)
    values (new.id, case when old.vezes_impresso = 0 then 'impresso' else 'reimpresso' end, old.status, new.status, v_ator, v_det || jsonb_build_object('vez', new.vezes_impresso));
  end if;
  if new.cerimonia_id is distinct from old.cerimonia_id then
    insert into public.certificados_eventos (certificado_id, evento, status_antes, status_depois, ator, detalhes)
    values (new.id, case when new.cerimonia_id is null then 'desvinculado_cerimonia' else 'vinculado_cerimonia' end, old.status, new.status, v_ator,
            jsonb_build_object('cerimonia', (select titulo from public.cerimonias where id = coalesce(new.cerimonia_id, old.cerimonia_id))));
  end if;
  if new.status is distinct from old.status and new.vezes_impresso = old.vezes_impresso and new.cerimonia_id is not distinct from old.cerimonia_id then
    insert into public.certificados_eventos (certificado_id, evento, status_antes, status_depois, ator, detalhes)
    values (new.id, case new.status when 'aguardando_autorizacao' then 'conclusao_validada' when 'autorizado' then 'emissao_autorizada'
                    when 'entregue' then 'entregue' when 'cancelado' then 'cancelado' else 'situacao_alterada' end, old.status, new.status, v_ator,
            v_det || case when new.status = 'entregue' then jsonb_build_object('recebido_por', new.recebido_por, 'relacao', new.recebido_relacao, 'ocasiao', new.entrega_ocasiao)
                          when new.status = 'cancelado' then jsonb_build_object('motivo', new.motivo_cancelamento) else '{}'::jsonb end);
  end if;
  return null;
end $$;


--
-- Name: tg_consentimento_imutavel(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_consentimento_imutavel() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  if tg_op = 'DELETE' then raise exception 'Consentimentos não podem ser excluídos (histórico exigido pela LGPD).'; end if;
  if old.revogado_em is not null then raise exception 'Este consentimento já foi revogado.'; end if;
  if (to_jsonb(new) - array['revogado_em','revogado_via','revogado_por','motivo_revogacao'])
     is distinct from (to_jsonb(old) - array['revogado_em','revogado_via','revogado_por','motivo_revogacao']) then
    raise exception 'Consentimentos não podem ser alterados; só revogados.';
  end if;
  if new.revogado_em is null then raise exception 'Informe a revogação.'; end if;
  return new;
end $$;


--
-- Name: tg_escala_historico(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_escala_historico() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_ator uuid := coalesce(auth.uid(), nullif(current_setting('app.ator', true), '')::uuid);
        v_acao text := nullif(current_setting('app.escala_acao', true), '');
        a jsonb; d jsonb; ign text[] := array['atualizado_em'];
begin
  if tg_table_name = 'escala_participacoes' then
    if tg_op = 'INSERT' then
      insert into public.escala_historico (escala_evento_id, participacao_id, acao, depois, ator)
      values (new.escala_evento_id, new.id, coalesce(v_acao, case when new.substitui_id is not null then 'substituto_escalado' else 'escalado' end), to_jsonb(new) - ign, v_ator);
    else
      a := to_jsonb(old) - ign; d := to_jsonb(new) - ign;
      if a is distinct from d then
        insert into public.escala_historico (escala_evento_id, participacao_id, acao, antes, depois, ator)
        values (new.escala_evento_id, new.id, coalesce(v_acao, case when new.status is distinct from old.status then 'status_' || new.status else 'alterada' end), a, d, v_ator);
      end if;
    end if;
  elsif tg_table_name = 'escala_eventos' then
    if tg_op = 'INSERT' then
      insert into public.escala_historico (escala_evento_id, acao, depois, ator) values (new.id, 'escala_criada', to_jsonb(new) - ign, v_ator);
    else
      a := to_jsonb(old) - ign; d := to_jsonb(new) - ign;
      if a is distinct from d then
        insert into public.escala_historico (escala_evento_id, acao, antes, depois, ator)
        values (new.id, coalesce(v_acao, case when new.status is distinct from old.status then 'escala_' || new.status else 'escala_alterada' end), a, d, v_ator);
      end if;
    end if;
  elsif tg_table_name = 'escala_evento_funcoes' then
    if tg_op = 'INSERT' then
      insert into public.escala_historico (escala_evento_id, acao, depois, ator) values (new.escala_evento_id, 'funcao_incluida', to_jsonb(new), v_ator);
    elsif to_jsonb(old) is distinct from to_jsonb(new) then
      insert into public.escala_historico (escala_evento_id, acao, antes, depois, ator)
      values (new.escala_evento_id, case when new.removida_em is not null and old.removida_em is null then 'funcao_removida' else 'funcao_alterada' end, to_jsonb(old), to_jsonb(new), v_ator);
    end if;
  end if;
  return null;
end $$;


--
-- Name: tg_eventos_imutaveis(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_eventos_imutaveis() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin raise exception 'O histórico de certificados não pode ser alterado nem excluído.'; end $$;


--
-- Name: tg_garantir_master(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_garantir_master() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  if old.perfil = 'MASTER' and old.ativo
     and (new.perfil <> 'MASTER' or not new.ativo)
     and not exists (select 1 from public.perfis p
                     where p.id <> old.id and p.perfil = 'MASTER' and p.ativo) then
    raise exception 'Não é possível remover o último MASTER ativo.';
  end if;
  return new;
end $$;


--
-- Name: tg_historico_imutavel(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_historico_imutavel() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin raise exception 'O histórico de escalas não pode ser alterado nem excluído.'; end $$;


--
-- Name: tg_inscricao_cancelada_paga(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_inscricao_cancelada_paga() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_liq numeric;
begin
  if new.status = 'cancelada' and old.status <> 'cancelada' then
    v_liq := (public.financeiro_inscricao(new.id)->>'liquido')::numeric;
    if v_liq > 0 then
      perform public.notificar('TESOURARIA', null, 'cancelada_com_pagamento', 'Inscrição paga foi cancelada',
        'Inscrição ' || new.protocolo || ' cancelada com ' || to_char(v_liq, 'FM999G990D00') || ' já aprovado. Avalie o reembolso.', jsonb_build_object('inscricao_id', new.id, 'protocolo', new.protocolo));
    end if;
  end if;
  return new;
end $$;


--
-- Name: tg_inscricao_confirmacao_paga(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_inscricao_confirmacao_paga() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_liq numeric;
begin
  if new.status = 'confirmada' and (tg_op = 'INSERT' or old.status is distinct from 'confirmada') and old.status is distinct from 'concluida'
     and new.valor_final > 0 then
    select coalesce(sum(p.valor), 0) into v_liq from public.pagamentos p
     where p.inscricao_id = new.id and p.status = 'aprovado'
       and exists (select 1 from public.comprovantes c where c.pagamento_id = p.id);
    v_liq := v_liq - coalesce((select sum(r.valor) from public.reembolsos r where r.inscricao_id = new.id), 0);
    if v_liq < new.valor_final then
      raise exception 'Inscrição com valor só é confirmada após a Tesouraria aprovar o pagamento com comprovante.' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;


--
-- Name: tg_inscricao_membresia_voluntariado(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_inscricao_membresia_voluntariado() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_curso uuid; v_proc uuid; v_cand uuid; v_nome text;
begin
  select t.curso_id into v_curso from public.turmas t where t.id = new.turma_id;
  select nome into v_nome from public.pessoas where id = new.pessoa_id;
  if v_curso = public.curso_id_por_slug('novos-membros') then
    if tg_op = 'INSERT' and new.status <> 'cancelada' then
      update public.membresia_processos set status = 'em_curso', inscricao_id = new.id
       where pessoa_id = new.pessoa_id and status in ('interesse','em_curso');
      if not found and not public.membresia_validada(new.pessoa_id)
         and not exists (select 1 from public.membresia_processos where pessoa_id = new.pessoa_id and status not in ('validado','encerrado')) then
        insert into public.membresia_processos (pessoa_id, status, origem, inscricao_id) values (new.pessoa_id, 'em_curso', new.origem, new.id);
      end if;
    elsif tg_op = 'UPDATE' and new.status = 'concluida' and old.status <> 'concluida' then
      update public.membresia_processos set status = 'aguardando_validacao', inscricao_id = new.id
       where pessoa_id = new.pessoa_id and status in ('interesse','em_curso') returning id into v_proc;
      if v_proc is not null then
        perform public.notificar('SECRETARIA', null, 'membresia_aguardando', 'Novos Membros concluído', v_nome || ' concluiu o Curso de Novos Membros e aguarda a validação da membresia.', jsonb_build_object('processo', v_proc));
      end if;
    elsif tg_op = 'UPDATE' and old.status = 'concluida' and new.status <> 'concluida' then
      update public.membresia_processos set status = 'em_curso' where pessoa_id = new.pessoa_id and status = 'aguardando_validacao';
    end if;
  elsif v_curso = public.curso_id_por_slug('formacao-de-voluntarios') then
    if tg_op = 'UPDATE' and new.status = 'concluida' and old.status <> 'concluida'
       and not exists (select 1 from public.voluntariado_candidaturas where pessoa_id = new.pessoa_id and status in ('aguardando_indicacao','em_analise')) then
      insert into public.voluntariado_candidaturas (pessoa_id, inscricao_id) values (new.pessoa_id, new.id) returning id into v_cand;
      perform public.notificar('SECRETARIA', null, 'candidatura_aberta', 'Formação de Voluntários concluída',
              v_nome || ' concluiu a Formação de Voluntários e pode indicar os ministérios em que deseja servir.', jsonb_build_object('candidatura', v_cand));
    end if;
  end if;
  return null;
end $$;


--
-- Name: tg_inscricao_vagas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_inscricao_vagas() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_vagas integer; v_ocupadas integer;
begin
  if new.status in ('confirmada','aguardando_pagamento','concluida')
     and (tg_op = 'INSERT' or old.status not in ('confirmada','aguardando_pagamento','concluida')) then
    select vagas into v_vagas from public.turmas where id = new.turma_id for update;
    if v_vagas is not null then
      select count(*) into v_ocupadas from public.inscricoes
       where turma_id = new.turma_id and status in ('confirmada','aguardando_pagamento','concluida') and id <> new.id;
      if v_ocupadas >= v_vagas then
        raise exception 'Turma sem vagas.' using errcode = '23514';
      end if;
    end if;
  end if;
  return new;
end $$;


--
-- Name: tg_limite_publico(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_limite_publico() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if auth.uid() is not null then return new; end if;        -- só o que chega sem login
  if tg_table_name = 'inscricoes' then
    if (select count(*) from public.inscricoes where pessoa_id = new.pessoa_id and criado_por is null and criado_em > now() - interval '1 hour')
       >= public.limite_publico('inscricoes_por_pessoa_hora', 3) then
      raise exception 'Você já fez várias inscrições agora há pouco. Aguarde uma hora ou fale com a Secretaria.' using errcode = 'P0001';
    end if;
    if (select count(*) from public.inscricoes where criado_por is null and criado_em > now() - interval '10 minutes')
       >= public.limite_publico('inscricoes_10min', 60) then
      raise exception 'Estamos recebendo muitas inscrições neste momento. Tente de novo em alguns minutos.' using errcode = 'P0001';
    end if;
  elsif tg_table_name = 'membresia_processos' then
    if new.origem = 'site' and (select count(*) from public.membresia_processos where origem = 'site' and criado_em > now() - interval '10 minutes')
       >= public.limite_publico('membresia_10min', 20) then
      raise exception 'Estamos recebendo muitos pedidos neste momento. Tente de novo em alguns minutos.' using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;


--
-- Name: tg_ministerio_organograma(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_ministerio_organograma() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  insert into public.organogramas (tipo, ministerio_id, titulo, ordem) values ('ministerio', new.id, new.nome, 100 + new.ordem)
    on conflict (ministerio_id) do nothing;
  insert into public.ministerio_paginas (ministerio_id) values (new.id) on conflict do nothing;
  return new;
end $$;


--
-- Name: tg_nao_excluir(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_nao_excluir() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin raise exception 'Registros financeiros e administrativos não podem ser excluídos; use cancelamento.'; end $$;


--
-- Name: tg_participacao_regras(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_participacao_regras() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare ef public.escala_evento_funcoes;
begin
  if not (tg_op = 'INSERT' or new.pessoa_id <> old.pessoa_id or new.evento_funcao_id <> old.evento_funcao_id or new.papel <> old.papel) then return new; end if;
  select * into ef from public.escala_evento_funcoes where id = new.evento_funcao_id;
  if ef.escala_evento_id <> new.escala_evento_id then raise exception 'Função de outro evento.' using errcode = '22023'; end if;
  perform public.escala_validar_bloqueios(new.evento_funcao_id, new.pessoa_id, new.papel);
  return new;
end $$;


--
-- Name: tg_senha_alterada(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_senha_alterada() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  update public.perfis
     set deve_trocar_senha = false, senha_alterada_em = now()
   where id = new.id and deve_trocar_senha;
  return new;
end $$;


--
-- Name: tg_termo_imutavel(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_termo_imutavel() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'rascunho' then raise exception 'Termo publicado não pode ser excluído.'; end if;
    return old;
  end if;
  if old.status <> 'rascunho' and (new.texto, new.titulo, new.versao, new.tipo, new.resumo, new.exige_novo_aceite)
                                   is distinct from (old.texto, old.titulo, old.versao, old.tipo, old.resumo, old.exige_novo_aceite) then
    raise exception 'O texto de um termo publicado não muda. Crie uma nova versão.';
  end if;
  return new;
end $$;


--
-- Name: tg_voluntario_requisitos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_voluntario_requisitos() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare r jsonb;
begin
  if new.funcao = 'voluntario' and new.ativo
     and (tg_op = 'INSERT' or not old.ativo or old.funcao <> 'voluntario') then
    r := public.voluntariado_requisitos(new.pessoa_id);
    if not (r->>'pode_ser_voluntario')::boolean then
      raise exception 'Para servir como voluntário é preciso ter a membresia validada pela Secretaria e o Curso de Novos Membros concluído. Falta: %.',
        (select string_agg(x, ' e ') from jsonb_array_elements_text(r->'falta') x) using errcode = '23514';
    end if;
  end if;
  return new;
end $$;


--
-- Name: turma_aberta(public.turmas); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.turma_aberta(t public.turmas) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select t.status = 'inscricoes_abertas'
     and (t.inscricao_abre_em is null or now() >= t.inscricao_abre_em)
     and (t.inscricao_fecha_em is null or now() < t.inscricao_fecha_em)
$$;


--
-- Name: voluntariado_indicar(text, text, uuid[], uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.voluntariado_indicar(p_protocolo text, p_chave text, p_ministerios uuid[], p_termo uuid, p_responsavel jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare i public.inscricoes := public.link_inscricao(p_protocolo, p_chave); v uuid;
begin
  select id into v from public.voluntariado_candidaturas where pessoa_id = i.pessoa_id and status = 'aguardando_indicacao';
  if v is null then raise exception 'Não há candidatura aguardando indicação de ministérios.' using errcode = 'P0002'; end if;
  perform public.voluntariado_indicar_interno(v, p_ministerios, p_termo, 'link', p_responsavel);
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: voluntariado_indicar_interno(uuid, uuid[], uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.voluntariado_indicar_interno(p_cand uuid, p_ministerios uuid[], p_termo uuid, p_origem text, p_responsavel jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare c public.voluntariado_candidaturas; v_n int := coalesce(array_length(p_ministerios, 1), 0); k int; v_nome text; v_lider uuid;
begin
  select * into c from public.voluntariado_candidaturas where id = p_cand for update;
  if not found then raise exception 'Candidatura não encontrada.' using errcode = 'P0002'; end if;
  if c.status <> 'aguardando_indicacao' then raise exception 'Os ministérios desta candidatura já foram indicados.' using errcode = '22023'; end if;
  if v_n < 1 or v_n > 3 then raise exception 'Indique de 1 a 3 ministérios.' using errcode = '22023'; end if;
  if (select count(distinct x) from unnest(p_ministerios) x) <> v_n then raise exception 'Ministério repetido.' using errcode = '22023'; end if;
  if exists (select 1 from unnest(p_ministerios) x where not exists (select 1 from public.ministerios m where m.id = x and m.ativo)) then
    raise exception 'Ministério inválido.' using errcode = '22023'; end if;
  if not (public.voluntariado_requisitos(c.pessoa_id)->>'pode_ser_voluntario')::boolean then
    raise exception 'Requisitos não atendidos: membresia validada pela Secretaria e Curso de Novos Membros concluído.' using errcode = '22023'; end if;
  perform public.registrar_consentimento(c.pessoa_id, 'voluntariado', p_termo, 'aceito', null, p_responsavel, p_origem, 'candidatura', c.id);
  for k in 1..v_n loop
    insert into public.voluntariado_indicacoes (candidatura_id, ministerio_id, ordem) values (c.id, p_ministerios[k], k);
  end loop;
  update public.voluntariado_candidaturas set status = 'em_analise' where id = c.id;
  select nome into v_nome from public.pessoas where id = c.pessoa_id;
  for v_lider in select distinct pf.id from public.ministerio_membros mm join public.perfis pf on pf.pessoa_id = mm.pessoa_id
                  where mm.ministerio_id = any(p_ministerios) and mm.funcao = 'lider' and mm.ativo and pf.ativo loop
    perform public.notificar(null, v_lider, 'candidatura_ministerio', 'Novo candidato a voluntário', v_nome || ' indicou o seu ministério após a Formação de Voluntários.', jsonb_build_object('candidatura', c.id));
  end loop;
end $$;


--
-- Name: voluntariado_requisitos(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.voluntariado_requisitos(p_pessoa uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_m boolean := public.membresia_validada(p_pessoa);
        v_nm boolean := public.curso_concluido(p_pessoa, public.curso_id_por_slug('novos-membros'));
        v_fv boolean := public.curso_concluido(p_pessoa, public.curso_id_por_slug('formacao-de-voluntarios'));
        v_t public.consentimentos := public.consentimento_atual(p_pessoa, 'voluntariado');
        v_falta text[] := '{}';
begin
  if not v_m then v_falta := array_append(v_falta, 'membresia validada pela Secretaria'); end if;
  if not v_nm then v_falta := array_append(v_falta, 'Curso de Novos Membros concluído'); end if;
  return jsonb_build_object('membresia_validada', v_m, 'novos_membros', v_nm, 'formacao_voluntarios', v_fv,
    'termo_voluntariado', coalesce(v_t.decisao = 'aceito', false),
    'pode_ser_voluntario', v_m and v_nm,                       -- regra da igreja
    'pode_ser_aprovado', v_m and v_nm and v_fv and coalesce(v_t.decisao = 'aceito', false),
    'falta', to_jsonb(v_falta));
end $$;


--
-- Name: objetos; Type: TABLE; Schema: armazenamento; Owner: -
--

CREATE TABLE armazenamento.objetos (
    espaco text NOT NULL,
    caminho text NOT NULL,
    tipo text NOT NULL,
    tamanho integer NOT NULL,
    conteudo bytea NOT NULL,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: recuperacoes; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.recuperacoes (
    token_hash text NOT NULL,
    usuario_id uuid NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    expira_em timestamp with time zone NOT NULL
);


--
-- Name: sessoes; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.sessoes (
    token_hash text NOT NULL,
    usuario_id uuid NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    expira_em timestamp with time zone NOT NULL,
    sessao_id uuid
);


--
-- Name: sessoes_encerradas; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.sessoes_encerradas (
    sessao_id uuid NOT NULL,
    expira_em timestamp with time zone NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.users (
    instance_id uuid,
    id uuid NOT NULL,
    aud text DEFAULT 'authenticated'::text,
    role text DEFAULT 'authenticated'::text,
    email text,
    encrypted_password text,
    email_confirmed_at timestamp with time zone,
    banned_until timestamp with time zone,
    raw_app_meta_data jsonb DEFAULT '{}'::jsonb,
    raw_user_meta_data jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    last_sign_in_at timestamp with time zone
);


--
-- Name: agenda_envios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agenda_envios (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    link_id uuid NOT NULL,
    dados jsonb NOT NULL,
    status text DEFAULT 'aguardando_analise'::text NOT NULL,
    versao integer DEFAULT 1 NOT NULL,
    enviado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    decidido_por uuid,
    decidido_em timestamp with time zone,
    motivo text,
    evento_id bigint,
    CONSTRAINT agenda_envios_motivo_check CHECK ((char_length(motivo) <= 500)),
    CONSTRAINT agenda_envios_status_check CHECK ((status = ANY (ARRAY['aguardando_analise'::text, 'aprovado'::text, 'recusado'::text])))
);


--
-- Name: agenda_envios_historico; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agenda_envios_historico (
    id bigint NOT NULL,
    envio_id uuid NOT NULL,
    quando timestamp with time zone DEFAULT now() NOT NULL,
    acao text NOT NULL,
    dados jsonb,
    motivo text,
    ator uuid,
    CONSTRAINT agenda_envios_historico_acao_check CHECK ((acao = ANY (ARRAY['enviado'::text, 'complementado'::text, 'aprovado'::text, 'recusado'::text])))
);


--
-- Name: agenda_envios_historico_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.agenda_envios_historico ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.agenda_envios_historico_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: agenda_link_acessos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agenda_link_acessos (
    id bigint NOT NULL,
    link_id uuid NOT NULL,
    quando timestamp with time zone DEFAULT now() NOT NULL,
    acao text NOT NULL,
    CONSTRAINT agenda_link_acessos_acao_check CHECK ((acao = ANY (ARRAY['aberto'::text, 'enviado'::text, 'complementado'::text, 'recusado_expirado'::text, 'recusado_revogado'::text, 'recusado_bloqueado'::text, 'recusado_dados'::text])))
);


--
-- Name: agenda_link_acessos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.agenda_link_acessos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.agenda_link_acessos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: apoio_servico_funcoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.apoio_servico_funcoes (
    servico_id uuid NOT NULL,
    funcao_id uuid NOT NULL
);


--
-- Name: apoio_servicos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.apoio_servicos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ministerio_id uuid NOT NULL,
    nome text NOT NULL,
    descricao text,
    ativo boolean DEFAULT true NOT NULL,
    ordem integer DEFAULT 0 NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT apoio_servicos_descricao_check CHECK ((char_length(descricao) <= 300)),
    CONSTRAINT apoio_servicos_nome_check CHECK (((char_length(btrim(nome)) >= 2) AND (char_length(btrim(nome)) <= 80)))
);


--
-- Name: apoio_solicitacao_mensagens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.apoio_solicitacao_mensagens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    solicitacao_id uuid NOT NULL,
    autor uuid NOT NULL,
    tipo text NOT NULL,
    texto text NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT apoio_solicitacao_mensagens_texto_check CHECK (((char_length(btrim(texto)) >= 2) AND (char_length(btrim(texto)) <= 2000))),
    CONSTRAINT apoio_solicitacao_mensagens_tipo_check CHECK ((tipo = ANY (ARRAY['mensagem'::text, 'pedido_informacao'::text, 'resposta'::text, 'nota_interna'::text])))
);


--
-- Name: apoio_solicitacao_servicos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.apoio_solicitacao_servicos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    solicitacao_id uuid NOT NULL,
    servico_id uuid NOT NULL,
    detalhe text,
    origem text DEFAULT 'solicitado'::text NOT NULL,
    decisao text,
    motivo text,
    decidido_por uuid,
    decidido_em timestamp with time zone,
    CONSTRAINT apoio_solicitacao_servicos_check CHECK (((decisao IS DISTINCT FROM 'nao_atender'::text) OR (char_length(btrim(COALESCE(motivo, ''::text))) >= 5))),
    CONSTRAINT apoio_solicitacao_servicos_decisao_check CHECK ((decisao = ANY (ARRAY['atender'::text, 'nao_atender'::text]))),
    CONSTRAINT apoio_solicitacao_servicos_detalhe_check CHECK ((char_length(detalhe) <= 600)),
    CONSTRAINT apoio_solicitacao_servicos_motivo_check CHECK ((char_length(motivo) <= 600)),
    CONSTRAINT apoio_solicitacao_servicos_origem_check CHECK ((origem = ANY (ARRAY['solicitado'::text, 'acrescentado'::text])))
);


--
-- Name: apoio_solicitacoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.apoio_solicitacoes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ministerio_alvo uuid NOT NULL,
    ministerio_solicitante uuid NOT NULL,
    solicitado_por uuid NOT NULL,
    responsavel_nome text NOT NULL,
    responsavel_contato text,
    evento_id bigint,
    titulo text NOT NULL,
    tipo_evento text NOT NULL,
    inicio timestamp with time zone NOT NULL,
    fim timestamp with time zone NOT NULL,
    local text NOT NULL,
    objetivo text,
    descricao text,
    informacoes text,
    prazo_retorno date,
    status text DEFAULT 'enviada'::text NOT NULL,
    decidido_por uuid,
    decidido_em timestamp with time zone,
    motivo text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT apoio_solicitacoes_check CHECK ((fim > inicio)),
    CONSTRAINT apoio_solicitacoes_descricao_check CHECK ((char_length(descricao) <= 2000)),
    CONSTRAINT apoio_solicitacoes_informacoes_check CHECK ((char_length(informacoes) <= 2000)),
    CONSTRAINT apoio_solicitacoes_local_check CHECK (((char_length(btrim(local)) >= 2) AND (char_length(btrim(local)) <= 200))),
    CONSTRAINT apoio_solicitacoes_motivo_check CHECK ((char_length(motivo) <= 600)),
    CONSTRAINT apoio_solicitacoes_objetivo_check CHECK ((char_length(objetivo) <= 600)),
    CONSTRAINT apoio_solicitacoes_responsavel_contato_check CHECK ((char_length(responsavel_contato) <= 120)),
    CONSTRAINT apoio_solicitacoes_responsavel_nome_check CHECK (((char_length(btrim(responsavel_nome)) >= 3) AND (char_length(btrim(responsavel_nome)) <= 120))),
    CONSTRAINT apoio_solicitacoes_status_check CHECK ((status = ANY (ARRAY['enviada'::text, 'em_analise'::text, 'aguardando_informacoes'::text, 'aprovada'::text, 'aprovada_parcial'::text, 'recusada'::text, 'cancelada'::text]))),
    CONSTRAINT apoio_solicitacoes_tipo_evento_check CHECK ((tipo_evento = ANY (ARRAY['culto'::text, 'conferencia'::text, 'acampamento'::text, 'reuniao'::text, 'acao_evangelistica'::text, 'batismo'::text, 'treinamento'::text, 'programacao_especial'::text, 'outro'::text]))),
    CONSTRAINT apoio_solicitacoes_titulo_check CHECK (((char_length(btrim(titulo)) >= 3) AND (char_length(btrim(titulo)) <= 140)))
);


--
-- Name: auditoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditoria (
    id bigint NOT NULL,
    quando timestamp with time zone DEFAULT now() NOT NULL,
    ator uuid,
    acao text NOT NULL,
    tabela text,
    registro text,
    antes jsonb,
    depois jsonb,
    detalhes jsonb
);


--
-- Name: auditoria_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.auditoria ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.auditoria_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: beneficios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.beneficios (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    inscricao_id uuid NOT NULL,
    tipo text NOT NULL,
    valor_desconto numeric(10,2),
    motivo text NOT NULL,
    status text DEFAULT 'solicitado'::text NOT NULL,
    solicitado_por uuid,
    solicitado_em timestamp with time zone DEFAULT now() NOT NULL,
    analisado_por uuid,
    analisado_em timestamp with time zone,
    observacao_analise text,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT beneficios_check CHECK (((tipo <> 'bolsa_parcial'::text) OR (valor_desconto IS NOT NULL))),
    CONSTRAINT beneficios_motivo_check CHECK (((char_length(btrim(motivo)) >= 3) AND (char_length(btrim(motivo)) <= 600))),
    CONSTRAINT beneficios_observacao_analise_check CHECK ((char_length(observacao_analise) <= 600)),
    CONSTRAINT beneficios_status_check CHECK ((status = ANY (ARRAY['solicitado'::text, 'aprovado'::text, 'recusado'::text, 'cancelado'::text]))),
    CONSTRAINT beneficios_tipo_check CHECK ((tipo = ANY (ARRAY['bolsa_parcial'::text, 'bolsa_integral'::text, 'isencao'::text]))),
    CONSTRAINT beneficios_valor_desconto_check CHECK (((valor_desconto IS NULL) OR (valor_desconto > (0)::numeric)))
);


--
-- Name: categorias_curso; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categorias_curso (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    descricao text,
    ordem integer DEFAULT 0 NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT categorias_curso_descricao_check CHECK ((char_length(descricao) <= 600)),
    CONSTRAINT categorias_curso_nome_check CHECK (((char_length(btrim(nome)) >= 2) AND (char_length(btrim(nome)) <= 80)))
);


--
-- Name: cerimonias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cerimonias (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    titulo text NOT NULL,
    data date,
    horario text,
    local text,
    evento_ref text,
    responsavel text,
    status text DEFAULT 'planejada'::text NOT NULL,
    observacoes text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    tipo text DEFAULT 'culto'::text NOT NULL,
    realizada_em timestamp with time zone,
    realizada_por uuid,
    CONSTRAINT cerimonias_horario_check CHECK ((char_length(horario) <= 60)),
    CONSTRAINT cerimonias_local_check CHECK ((char_length(local) <= 200)),
    CONSTRAINT cerimonias_observacoes_check CHECK ((char_length(observacoes) <= 1000)),
    CONSTRAINT cerimonias_responsavel_check CHECK ((char_length(responsavel) <= 120)),
    CONSTRAINT cerimonias_status_check CHECK ((status = ANY (ARRAY['planejada'::text, 'realizada'::text, 'cancelada'::text]))),
    CONSTRAINT cerimonias_tipo_check CHECK ((tipo = ANY (ARRAY['culto'::text, 'apresentacao'::text, 'outra'::text]))),
    CONSTRAINT cerimonias_titulo_check CHECK (((char_length(btrim(titulo)) >= 3) AND (char_length(btrim(titulo)) <= 140)))
);


--
-- Name: certificados; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.certificados (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    inscricao_id uuid NOT NULL,
    codigo text NOT NULL,
    status text DEFAULT 'aguardando_validacao'::text NOT NULL,
    cerimonia_id uuid,
    preparado_por uuid,
    preparado_em timestamp with time zone,
    impresso_por uuid,
    impresso_em timestamp with time zone,
    vezes_impresso integer DEFAULT 0 NOT NULL,
    entregue_em timestamp with time zone,
    entregue_por uuid,
    recebido_por text,
    motivo_cancelamento text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    validado_por uuid,
    validado_em timestamp with time zone,
    observacao_validacao text,
    autorizado_por uuid,
    autorizado_em timestamp with time zone,
    entrega_ocasiao text,
    recebido_relacao text,
    entrega_observacao text,
    CONSTRAINT certificados_entrega_observacao_check CHECK ((char_length(entrega_observacao) <= 600)),
    CONSTRAINT certificados_entrega_ocasiao_check CHECK ((entrega_ocasiao = ANY (ARRAY['cerimonia'::text, 'secretaria'::text]))),
    CONSTRAINT certificados_fluxo_check CHECK ((((status <> ALL (ARRAY['aguardando_autorizacao'::text, 'autorizado'::text, 'preparado'::text, 'impresso'::text, 'entregue'::text])) OR (validado_em IS NOT NULL)) AND ((status <> ALL (ARRAY['autorizado'::text, 'preparado'::text, 'impresso'::text, 'entregue'::text])) OR (autorizado_em IS NOT NULL)) AND ((status <> ALL (ARRAY['preparado'::text, 'impresso'::text])) OR (cerimonia_id IS NOT NULL) OR (status = 'impresso'::text)) AND ((status <> 'entregue'::text) OR ((entregue_em IS NOT NULL) AND (entregue_por IS NOT NULL) AND (recebido_por IS NOT NULL) AND (entrega_ocasiao IS NOT NULL) AND (recebido_relacao IS NOT NULL) AND (vezes_impresso > 0))) AND ((autorizado_por IS NULL) OR (validado_por IS NULL) OR (autorizado_por <> validado_por)))),
    CONSTRAINT certificados_motivo_cancelamento_check CHECK ((char_length(motivo_cancelamento) <= 300)),
    CONSTRAINT certificados_observacao_validacao_check CHECK ((char_length(observacao_validacao) <= 600)),
    CONSTRAINT certificados_recebido_por_check CHECK ((char_length(recebido_por) <= 120)),
    CONSTRAINT certificados_recebido_relacao_check CHECK ((recebido_relacao = ANY (ARRAY['participante'::text, 'responsavel_legal'::text, 'pessoa_autorizada'::text]))),
    CONSTRAINT certificados_status_check CHECK ((status = ANY (ARRAY['aguardando_validacao'::text, 'aguardando_autorizacao'::text, 'autorizado'::text, 'preparado'::text, 'impresso'::text, 'entregue'::text, 'cancelado'::text])))
);


--
-- Name: certificados_eventos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.certificados_eventos (
    id bigint NOT NULL,
    certificado_id uuid NOT NULL,
    evento text NOT NULL,
    status_antes text,
    status_depois text,
    ator uuid,
    em timestamp with time zone DEFAULT now() NOT NULL,
    detalhes jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: certificados_eventos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.certificados_eventos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.certificados_eventos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: colegio_etapas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.colegio_etapas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slug text NOT NULL,
    titulo text NOT NULL,
    subtitulo text,
    descricao text NOT NULL,
    objetivos text[] DEFAULT '{}'::text[] NOT NULL,
    diferenciais text[] DEFAULT '{}'::text[] NOT NULL,
    faixa_etaria text,
    foto text,
    foto_alt text,
    ordem integer DEFAULT 0 NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    validado boolean DEFAULT false NOT NULL,
    validado_em timestamp with time zone,
    validado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT colegio_etapas_descricao_check CHECK ((char_length(descricao) <= 4000)),
    CONSTRAINT colegio_etapas_faixa_etaria_check CHECK ((char_length(faixa_etaria) <= 120)),
    CONSTRAINT colegio_etapas_foto_alt_check CHECK ((char_length(foto_alt) <= 200)),
    CONSTRAINT colegio_etapas_foto_check CHECK (((foto IS NULL) OR (foto ~ '^(img/[a-z0-9._/-]+|site/[a-z0-9-]+/[0-9a-f-]{36}(/[0-9a-f-]{36})?\.(jpg|png|webp))$'::text))),
    CONSTRAINT colegio_etapas_slug_check CHECK ((slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::text)),
    CONSTRAINT colegio_etapas_subtitulo_check CHECK ((char_length(subtitulo) <= 160)),
    CONSTRAINT colegio_etapas_titulo_check CHECK (((char_length(btrim(titulo)) >= 2) AND (char_length(btrim(titulo)) <= 80)))
);


--
-- Name: comprovantes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comprovantes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pagamento_id uuid NOT NULL,
    arquivo_path text NOT NULL,
    nome_original text,
    tipo_mime text NOT NULL,
    tamanho integer NOT NULL,
    hash_sha256 text NOT NULL,
    enviado_por uuid,
    enviado_via text NOT NULL,
    enviado_em timestamp with time zone DEFAULT now() NOT NULL,
    situacao text DEFAULT 'atual'::text NOT NULL,
    CONSTRAINT comprovantes_enviado_via_check CHECK ((enviado_via = ANY (ARRAY['link'::text, 'painel'::text]))),
    CONSTRAINT comprovantes_hash_sha256_check CHECK ((hash_sha256 ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT comprovantes_nome_original_check CHECK ((char_length(nome_original) <= 200)),
    CONSTRAINT comprovantes_situacao_check CHECK ((situacao = ANY (ARRAY['atual'::text, 'substituido'::text]))),
    CONSTRAINT comprovantes_tamanho_check CHECK (((tamanho >= 1) AND (tamanho <= 5242880))),
    CONSTRAINT comprovantes_tipo_mime_check CHECK ((tipo_mime = ANY (ARRAY['application/pdf'::text, 'image/jpeg'::text, 'image/png'::text, 'image/webp'::text])))
);


--
-- Name: configuracoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.configuracoes (
    chave text NOT NULL,
    valor jsonb NOT NULL,
    publico boolean DEFAULT false NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_por uuid,
    CONSTRAINT configuracoes_chave_check CHECK ((chave ~ '^[a-z0-9_.]+$'::text))
);


--
-- Name: coordenadores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coordenadores (
    id bigint NOT NULL,
    nome text,
    login text,
    senha text NOT NULL,
    ativo boolean DEFAULT true,
    usuario_id uuid,
    migrado_em timestamp with time zone
);


--
-- Name: coordenadores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.coordenadores ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.coordenadores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cursos_conclusoes_anteriores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cursos_conclusoes_anteriores (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pessoa_id uuid NOT NULL,
    curso_id uuid NOT NULL,
    concluido_em date NOT NULL,
    comprovacao text NOT NULL,
    documento_id uuid,
    registrado_por uuid NOT NULL,
    registrado_em timestamp with time zone DEFAULT now() NOT NULL,
    cancelado_em timestamp with time zone,
    motivo_cancelamento text,
    CONSTRAINT cursos_conclusoes_anteriores_comprovacao_check CHECK (((char_length(btrim(comprovacao)) >= 10) AND (char_length(btrim(comprovacao)) <= 600))),
    CONSTRAINT cursos_conclusoes_anteriores_concluido_em_check CHECK ((concluido_em <= CURRENT_DATE)),
    CONSTRAINT cursos_conclusoes_anteriores_motivo_cancelamento_check CHECK ((char_length(motivo_cancelamento) <= 300))
);


--
-- Name: documentos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.documentos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pessoa_id uuid NOT NULL,
    inscricao_id uuid,
    tipo text NOT NULL,
    descricao text,
    arquivo_path text NOT NULL,
    nome_original text,
    tipo_mime text NOT NULL,
    tamanho integer NOT NULL,
    hash_sha256 text NOT NULL,
    enviado_por uuid NOT NULL,
    enviado_em timestamp with time zone DEFAULT now() NOT NULL,
    arquivado_em timestamp with time zone,
    CONSTRAINT documentos_descricao_check CHECK ((char_length(descricao) <= 300)),
    CONSTRAINT documentos_nome_original_check CHECK ((char_length(nome_original) <= 200)),
    CONSTRAINT documentos_tamanho_check CHECK (((tamanho >= 1) AND (tamanho <= 5242880))),
    CONSTRAINT documentos_tipo_check CHECK ((tipo = ANY (ARRAY['ficha_membresia'::text, 'carta_transferencia'::text, 'documento_responsavel'::text, 'documento_identificacao'::text, 'outro'::text, 'termo_assinado'::text, 'autorizacao_responsavel'::text]))),
    CONSTRAINT documentos_tipo_mime_check CHECK ((tipo_mime = ANY (ARRAY['application/pdf'::text, 'image/jpeg'::text, 'image/png'::text, 'image/webp'::text])))
);


--
-- Name: escala_areas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.escala_areas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ministerio_id uuid NOT NULL,
    nome text NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    ordem integer DEFAULT 0 NOT NULL,
    CONSTRAINT escala_areas_nome_check CHECK (((char_length(btrim(nome)) >= 2) AND (char_length(btrim(nome)) <= 80)))
);


--
-- Name: escala_evento_funcoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.escala_evento_funcoes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    escala_evento_id uuid NOT NULL,
    funcao_id uuid NOT NULL,
    quantidade_referencia integer,
    orientacoes text,
    hora_inicio timestamp with time zone,
    hora_fim timestamp with time zone,
    removida_em timestamp with time zone,
    CONSTRAINT escala_evento_funcoes_check CHECK (((hora_fim IS NULL) OR (hora_inicio IS NULL) OR (hora_fim > hora_inicio))),
    CONSTRAINT escala_evento_funcoes_orientacoes_check CHECK ((char_length(orientacoes) <= 2000)),
    CONSTRAINT escala_evento_funcoes_quantidade_referencia_check CHECK (((quantidade_referencia >= 1) AND (quantidade_referencia <= 99)))
);


--
-- Name: escala_funcoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.escala_funcoes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    area_id uuid NOT NULL,
    nome text NOT NULL,
    exige_habilitacao boolean DEFAULT true NOT NULL,
    aceita_em_treinamento boolean DEFAULT true NOT NULL,
    quantidade_referencia integer,
    orientacao_padrao text,
    ativo boolean DEFAULT true NOT NULL,
    ordem integer DEFAULT 0 NOT NULL,
    CONSTRAINT escala_funcoes_nome_check CHECK (((char_length(btrim(nome)) >= 2) AND (char_length(btrim(nome)) <= 80))),
    CONSTRAINT escala_funcoes_orientacao_padrao_check CHECK ((char_length(orientacao_padrao) <= 1000)),
    CONSTRAINT escala_funcoes_quantidade_referencia_check CHECK (((quantidade_referencia >= 1) AND (quantidade_referencia <= 99)))
);


--
-- Name: escala_gestores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.escala_gestores (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ministerio_id uuid NOT NULL,
    perfil_id uuid NOT NULL,
    areas uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: escala_historico; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.escala_historico (
    id bigint NOT NULL,
    escala_evento_id uuid NOT NULL,
    participacao_id uuid,
    acao text NOT NULL,
    antes jsonb,
    depois jsonb,
    ator uuid,
    em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: escala_historico_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.escala_historico ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.escala_historico_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: eventos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.eventos (
    id bigint NOT NULL,
    titulo text,
    data text,
    ministerio text,
    lider text,
    horario text,
    horario_inicio text,
    horario_fim text,
    local text,
    necessita_midia text,
    necessita_louvor text,
    necessita_diaconia text,
    midia_tema text,
    midia_arte text,
    midia_banner text,
    midia_inscricao text,
    midia_link_inscricao text,
    midia_info text,
    observacoes text,
    link_fotos text,
    link_videos text,
    bloqueado boolean DEFAULT false,
    atualizado_em timestamp with time zone,
    ministerio_id uuid,
    criado_por uuid,
    atualizado_por uuid
);


--
-- Name: eventos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.eventos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.eventos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inscricoes_protocolo_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.inscricoes_protocolo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: membresia_processos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.membresia_processos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pessoa_id uuid NOT NULL,
    status text DEFAULT 'interesse'::text NOT NULL,
    origem text NOT NULL,
    forma_ingresso text,
    mensagem text,
    inscricao_id uuid,
    observacao text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    encerrado_em timestamp with time zone,
    motivo_encerramento text,
    CONSTRAINT membresia_processos_forma_ingresso_check CHECK ((forma_ingresso = ANY (ARRAY['batismo'::text, 'transferencia'::text, 'aclamacao'::text, 'reconciliacao'::text]))),
    CONSTRAINT membresia_processos_mensagem_check CHECK ((char_length(mensagem) <= 1000)),
    CONSTRAINT membresia_processos_motivo_encerramento_check CHECK ((char_length(motivo_encerramento) <= 300)),
    CONSTRAINT membresia_processos_observacao_check CHECK ((char_length(observacao) <= 1000)),
    CONSTRAINT membresia_processos_origem_check CHECK ((origem = ANY (ARRAY['site'::text, 'secretaria'::text]))),
    CONSTRAINT membresia_processos_status_check CHECK ((status = ANY (ARRAY['interesse'::text, 'em_curso'::text, 'aguardando_validacao'::text, 'validado'::text, 'encerrado'::text])))
);


--
-- Name: ministerio_membros; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ministerio_membros (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pessoa_id uuid NOT NULL,
    ministerio_id uuid NOT NULL,
    funcao text NOT NULL,
    desde date DEFAULT CURRENT_DATE NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    cargo text,
    CONSTRAINT ministerio_membros_cargo_check CHECK (((cargo IS NULL) OR ((char_length(btrim(cargo)) >= 2) AND (char_length(btrim(cargo)) <= 80)))),
    CONSTRAINT ministerio_membros_funcao_check CHECK ((funcao = ANY (ARRAY['lider'::text, 'voluntario'::text])))
);


--
-- Name: notificacoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notificacoes (
    id bigint NOT NULL,
    para_atribuicao text,
    para_usuario uuid,
    tipo text NOT NULL,
    titulo text NOT NULL,
    mensagem text,
    ref jsonb DEFAULT '{}'::jsonb NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    lida_por uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    chave text,
    categoria text,
    CONSTRAINT notificacoes_check CHECK (((para_atribuicao IS NOT NULL) OR (para_usuario IS NOT NULL))),
    CONSTRAINT notificacoes_para_atribuicao_check CHECK ((para_atribuicao = ANY (ARRAY['SECRETARIA'::text, 'TESOURARIA'::text])))
);


--
-- Name: notificacoes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.notificacoes ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.notificacoes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: organograma_nos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organograma_nos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organograma_id uuid NOT NULL,
    pai_id uuid,
    cargo text NOT NULL,
    pessoa_id uuid,
    nome_livre text,
    responsabilidades text,
    procurar_para text,
    ordem integer DEFAULT 0 NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_por uuid,
    CONSTRAINT organograma_nos_cargo_check CHECK (((char_length(btrim(cargo)) >= 2) AND (char_length(btrim(cargo)) <= 100))),
    CONSTRAINT organograma_nos_check CHECK (((pai_id IS NULL) OR (pai_id <> id))),
    CONSTRAINT organograma_nos_check1 CHECK ((NOT ((pessoa_id IS NOT NULL) AND (nome_livre IS NOT NULL)))),
    CONSTRAINT organograma_nos_nome_livre_check CHECK (((nome_livre IS NULL) OR ((char_length(btrim(nome_livre)) >= 2) AND (char_length(btrim(nome_livre)) <= 120)))),
    CONSTRAINT organograma_nos_procurar_para_check CHECK ((char_length(procurar_para) <= 500)),
    CONSTRAINT organograma_nos_responsabilidades_check CHECK ((char_length(responsabilidades) <= 1500))
);


--
-- Name: organogramas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organogramas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tipo text NOT NULL,
    ministerio_id uuid,
    titulo text NOT NULL,
    descricao text,
    ordem integer DEFAULT 0 NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT organogramas_check CHECK (((tipo = 'ministerio'::text) = (ministerio_id IS NOT NULL))),
    CONSTRAINT organogramas_descricao_check CHECK ((char_length(descricao) <= 1000)),
    CONSTRAINT organogramas_tipo_check CHECK ((tipo = ANY (ARRAY['igreja'::text, 'ministerio'::text, 'colegio'::text, 'secretaria'::text, 'tesouraria'::text]))),
    CONSTRAINT organogramas_titulo_check CHECK (((char_length(btrim(titulo)) >= 2) AND (char_length(btrim(titulo)) <= 120)))
);


--
-- Name: pagamentos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pagamentos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    inscricao_id uuid NOT NULL,
    metodo text NOT NULL,
    origem text NOT NULL,
    valor numeric(10,2) NOT NULL,
    pago_em date,
    status text DEFAULT 'aguardando_comprovante'::text NOT NULL,
    observacao text,
    registrado_por uuid,
    registrado_em timestamp with time zone DEFAULT now() NOT NULL,
    analisado_por uuid,
    analisado_em timestamp with time zone,
    observacao_analise text,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pagamentos_check CHECK (((analisado_por IS NULL) OR (registrado_por IS NULL) OR (analisado_por <> registrado_por))),
    CONSTRAINT pagamentos_metodo_check CHECK ((metodo = ANY (ARRAY['pix'::text, 'transferencia'::text, 'dinheiro'::text, 'cartao_presencial'::text, 'outro'::text]))),
    CONSTRAINT pagamentos_observacao_analise_check CHECK ((char_length(observacao_analise) <= 600)),
    CONSTRAINT pagamentos_observacao_check CHECK ((char_length(observacao) <= 600)),
    CONSTRAINT pagamentos_origem_check CHECK ((origem = ANY (ARRAY['participante'::text, 'secretaria'::text]))),
    CONSTRAINT pagamentos_status_check CHECK ((status = ANY (ARRAY['aguardando_comprovante'::text, 'em_analise'::text, 'aprovado'::text, 'recusado'::text, 'novo_comprovante_solicitado'::text, 'cancelado'::text]))),
    CONSTRAINT pagamentos_valor_check CHECK ((valor > (0)::numeric))
);


--
-- Name: perfis; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.perfis (
    id uuid NOT NULL,
    pessoa_id uuid NOT NULL,
    perfil text NOT NULL,
    atribuicoes text[] DEFAULT '{}'::text[] NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    deve_trocar_senha boolean DEFAULT true NOT NULL,
    senha_alterada_em timestamp with time zone,
    aprovado_por uuid,
    aprovado_em timestamp with time zone,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    foto_caminho text,
    foto_no_organograma boolean DEFAULT false NOT NULL,
    CONSTRAINT perfis_atribuicoes_check CHECK ((atribuicoes <@ ARRAY['SECRETARIA'::text, 'TESOURARIA'::text])),
    CONSTRAINT perfis_foto_caminho_check CHECK (((foto_caminho IS NULL) OR (foto_caminho ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$'::text))),
    CONSTRAINT perfis_perfil_check CHECK ((perfil = ANY (ARRAY['MASTER'::text, 'LIDER'::text, 'VOLUNTARIO'::text])))
);


--
-- Name: pessoas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pessoas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    usuario_id uuid,
    nome text NOT NULL,
    telefone text,
    email text,
    data_nascimento date,
    bairro text,
    cidade text,
    situacao_membresia text DEFAULT 'visitante'::text NOT NULL,
    membro_desde date,
    membresia_validada_por uuid,
    membresia_validada_em timestamp with time zone,
    origem text DEFAULT 'secretaria'::text NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    arquivado_em timestamp with time zone,
    CONSTRAINT pessoas_email_check CHECK (((email = lower(btrim(email))) AND (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'::text))),
    CONSTRAINT pessoas_nome_check CHECK (((char_length(btrim(nome)) >= 3) AND (char_length(btrim(nome)) <= 120))),
    CONSTRAINT pessoas_origem_check CHECK ((origem = ANY (ARRAY['site'::text, 'secretaria'::text, 'migracao'::text]))),
    CONSTRAINT pessoas_situacao_membresia_check CHECK ((situacao_membresia = ANY (ARRAY['visitante'::text, 'em_integracao'::text, 'membro'::text, 'inativo'::text]))),
    CONSTRAINT pessoas_telefone_check CHECK ((telefone ~ '^[0-9]{10,13}$'::text))
);


--
-- Name: reembolsos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reembolsos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    inscricao_id uuid NOT NULL,
    pagamento_id uuid NOT NULL,
    valor numeric(10,2) NOT NULL,
    metodo text NOT NULL,
    realizado_em date NOT NULL,
    motivo text NOT NULL,
    registrado_por uuid NOT NULL,
    registrado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT reembolsos_metodo_check CHECK ((metodo = ANY (ARRAY['pix'::text, 'transferencia'::text, 'dinheiro'::text, 'outro'::text]))),
    CONSTRAINT reembolsos_motivo_check CHECK (((char_length(btrim(motivo)) >= 3) AND (char_length(btrim(motivo)) <= 600))),
    CONSTRAINT reembolsos_valor_check CHECK ((valor > (0)::numeric))
);


--
-- Name: reservas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reservas (
    id bigint NOT NULL,
    ministerio text,
    motivo text,
    espacos text,
    data text,
    horario_inicio text,
    horario_fim text,
    lote_id text,
    ministerio_id uuid,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now()
);


--
-- Name: reservas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.reservas ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.reservas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: solicitacoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solicitacoes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tipo text NOT NULL,
    nome text NOT NULL,
    telefone text NOT NULL,
    email text NOT NULL,
    ministerio_id uuid,
    funcao_pretendida text,
    mensagem text,
    status text DEFAULT 'pendente'::text NOT NULL,
    analisado_por uuid,
    analisado_em timestamp with time zone,
    motivo text,
    pessoa_id uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT solicitacoes_check CHECK (((tipo <> 'acesso'::text) OR ((ministerio_id IS NOT NULL) AND (funcao_pretendida IS NOT NULL)))),
    CONSTRAINT solicitacoes_email_check CHECK (((email = lower(btrim(email))) AND (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'::text))),
    CONSTRAINT solicitacoes_funcao_pretendida_check CHECK ((funcao_pretendida = ANY (ARRAY['lider'::text, 'voluntario'::text]))),
    CONSTRAINT solicitacoes_mensagem_check CHECK ((char_length(mensagem) <= 1000)),
    CONSTRAINT solicitacoes_motivo_check CHECK ((char_length(motivo) <= 500)),
    CONSTRAINT solicitacoes_nome_check CHECK (((char_length(btrim(nome)) >= 3) AND (char_length(btrim(nome)) <= 120))),
    CONSTRAINT solicitacoes_status_check CHECK ((status = ANY (ARRAY['pendente'::text, 'aprovada'::text, 'recusada'::text]))),
    CONSTRAINT solicitacoes_telefone_check CHECK ((telefone ~ '^[0-9]{10,13}$'::text)),
    CONSTRAINT solicitacoes_tipo_check CHECK ((tipo = ANY (ARRAY['acesso'::text, 'voluntariado'::text])))
);


--
-- Name: termos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.termos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tipo text NOT NULL,
    versao integer NOT NULL,
    titulo text NOT NULL,
    resumo text,
    texto text NOT NULL,
    exige_novo_aceite boolean DEFAULT false NOT NULL,
    status text DEFAULT 'rascunho'::text NOT NULL,
    texto_hash text,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    publicado_por uuid,
    publicado_em timestamp with time zone,
    CONSTRAINT termos_resumo_check CHECK ((char_length(resumo) <= 600)),
    CONSTRAINT termos_status_check CHECK ((status = ANY (ARRAY['rascunho'::text, 'vigente'::text, 'substituido'::text]))),
    CONSTRAINT termos_texto_check CHECK (((char_length(btrim(texto)) >= 50) AND (char_length(btrim(texto)) <= 20000))),
    CONSTRAINT termos_tipo_check CHECK ((tipo = ANY (ARRAY['participacao_curso'::text, 'imagem_voz'::text, 'voluntariado'::text]))),
    CONSTRAINT termos_titulo_check CHECK (((char_length(btrim(titulo)) >= 5) AND (char_length(btrim(titulo)) <= 140))),
    CONSTRAINT termos_versao_check CHECK ((versao >= 1))
);


--
-- Name: turma_responsaveis; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.turma_responsaveis (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    turma_id uuid NOT NULL,
    perfil_id uuid NOT NULL,
    papel text DEFAULT 'coordenador'::text NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    criado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT turma_responsaveis_papel_check CHECK ((papel = ANY (ARRAY['coordenador'::text, 'professor'::text])))
);


--
-- Name: voluntariado_candidaturas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.voluntariado_candidaturas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pessoa_id uuid NOT NULL,
    status text DEFAULT 'aguardando_indicacao'::text NOT NULL,
    inscricao_id uuid,
    observacao text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    encerrada_em timestamp with time zone,
    CONSTRAINT voluntariado_candidaturas_observacao_check CHECK ((char_length(observacao) <= 600)),
    CONSTRAINT voluntariado_candidaturas_status_check CHECK ((status = ANY (ARRAY['aguardando_indicacao'::text, 'em_analise'::text, 'aprovada'::text, 'nao_aprovada'::text, 'cancelada'::text])))
);


--
-- Name: voluntariado_indicacoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.voluntariado_indicacoes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    candidatura_id uuid NOT NULL,
    ministerio_id uuid NOT NULL,
    ordem smallint NOT NULL,
    status text DEFAULT 'pendente'::text NOT NULL,
    analisado_por uuid,
    analisado_em timestamp with time zone,
    motivo text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT voluntariado_indicacoes_motivo_check CHECK ((char_length(motivo) <= 600)),
    CONSTRAINT voluntariado_indicacoes_ordem_check CHECK (((ordem >= 1) AND (ordem <= 3))),
    CONSTRAINT voluntariado_indicacoes_status_check CHECK ((status = ANY (ARRAY['pendente'::text, 'aprovada'::text, 'recusada'::text, 'cancelada'::text])))
);


--
-- Name: voluntario_capacitacoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.voluntario_capacitacoes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pessoa_id uuid NOT NULL,
    funcao_id uuid,
    titulo text NOT NULL,
    realizada_em date NOT NULL,
    carga text,
    observacao text,
    registrado_por uuid,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT voluntario_capacitacoes_carga_check CHECK ((char_length(carga) <= 40)),
    CONSTRAINT voluntario_capacitacoes_observacao_check CHECK ((char_length(observacao) <= 600)),
    CONSTRAINT voluntario_capacitacoes_realizada_em_check CHECK ((realizada_em <= CURRENT_DATE)),
    CONSTRAINT voluntario_capacitacoes_titulo_check CHECK (((char_length(btrim(titulo)) >= 3) AND (char_length(btrim(titulo)) <= 140)))
);


--
-- Name: voluntario_disponibilidade; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.voluntario_disponibilidade (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pessoa_id uuid NOT NULL,
    dia_semana smallint NOT NULL,
    hora_inicio time without time zone NOT NULL,
    hora_fim time without time zone NOT NULL,
    CONSTRAINT voluntario_disponibilidade_check CHECK ((hora_fim > hora_inicio)),
    CONSTRAINT voluntario_disponibilidade_dia_semana_check CHECK (((dia_semana >= 0) AND (dia_semana <= 6)))
);


--
-- Name: voluntario_habilitacoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.voluntario_habilitacoes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pessoa_id uuid NOT NULL,
    funcao_id uuid NOT NULL,
    status text NOT NULL,
    desde date DEFAULT CURRENT_DATE NOT NULL,
    autorizado_por uuid,
    observacao text,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT voluntario_habilitacoes_observacao_check CHECK ((char_length(observacao) <= 600)),
    CONSTRAINT voluntario_habilitacoes_status_check CHECK ((status = ANY (ARRAY['habilitado'::text, 'em_treinamento'::text, 'suspenso'::text])))
);


--
-- Name: voluntario_indisponibilidades; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.voluntario_indisponibilidades (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pessoa_id uuid NOT NULL,
    inicio date NOT NULL,
    fim date NOT NULL,
    tipo text NOT NULL,
    motivo text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT voluntario_indisponibilidades_check CHECK ((fim >= inicio)),
    CONSTRAINT voluntario_indisponibilidades_motivo_check CHECK ((char_length(motivo) <= 300)),
    CONSTRAINT voluntario_indisponibilidades_tipo_check CHECK ((tipo = ANY (ARRAY['data'::text, 'ferias'::text, 'afastamento'::text, 'temporaria'::text])))
);


--
-- Name: voluntario_preferencias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.voluntario_preferencias (
    pessoa_id uuid NOT NULL,
    funcoes uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    observacoes text,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT voluntario_preferencias_observacoes_check CHECK ((char_length(observacoes) <= 1000))
);


--
-- Name: migracoes; Type: TABLE; Schema: sistema; Owner: -
--

CREATE TABLE sistema.migracoes (
    nome text NOT NULL,
    aplicada_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: objetos objetos_pkey; Type: CONSTRAINT; Schema: armazenamento; Owner: -
--

ALTER TABLE ONLY armazenamento.objetos
    ADD CONSTRAINT objetos_pkey PRIMARY KEY (espaco, caminho);


--
-- Name: recuperacoes recuperacoes_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.recuperacoes
    ADD CONSTRAINT recuperacoes_pkey PRIMARY KEY (token_hash);


--
-- Name: sessoes_encerradas sessoes_encerradas_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sessoes_encerradas
    ADD CONSTRAINT sessoes_encerradas_pkey PRIMARY KEY (sessao_id);


--
-- Name: sessoes sessoes_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sessoes
    ADD CONSTRAINT sessoes_pkey PRIMARY KEY (token_hash);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: agenda_envios_historico agenda_envios_historico_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda_envios_historico
    ADD CONSTRAINT agenda_envios_historico_pkey PRIMARY KEY (id);


--
-- Name: agenda_envios agenda_envios_link_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda_envios
    ADD CONSTRAINT agenda_envios_link_id_key UNIQUE (link_id);


--
-- Name: agenda_envios agenda_envios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda_envios
    ADD CONSTRAINT agenda_envios_pkey PRIMARY KEY (id);


--
-- Name: agenda_link_acessos agenda_link_acessos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda_link_acessos
    ADD CONSTRAINT agenda_link_acessos_pkey PRIMARY KEY (id);


--
-- Name: agenda_links agenda_links_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda_links
    ADD CONSTRAINT agenda_links_pkey PRIMARY KEY (id);


--
-- Name: agenda_links agenda_links_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda_links
    ADD CONSTRAINT agenda_links_token_hash_key UNIQUE (token_hash);


--
-- Name: apoio_servico_funcoes apoio_servico_funcoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apoio_servico_funcoes
    ADD CONSTRAINT apoio_servico_funcoes_pkey PRIMARY KEY (servico_id, funcao_id);


--
-- Name: apoio_servicos apoio_servicos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apoio_servicos
    ADD CONSTRAINT apoio_servicos_pkey PRIMARY KEY (id);


--
-- Name: apoio_solicitacao_mensagens apoio_solicitacao_mensagens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apoio_solicitacao_mensagens
    ADD CONSTRAINT apoio_solicitacao_mensagens_pkey PRIMARY KEY (id);


--
-- Name: apoio_solicitacao_servicos apoio_solicitacao_servicos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apoio_solicitacao_servicos
    ADD CONSTRAINT apoio_solicitacao_servicos_pkey PRIMARY KEY (id);


--
-- Name: apoio_solicitacao_servicos apoio_solicitacao_servicos_solicitacao_id_servico_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apoio_solicitacao_servicos
    ADD CONSTRAINT apoio_solicitacao_servicos_solicitacao_id_servico_id_key UNIQUE (solicitacao_id, servico_id);


--
-- Name: apoio_solicitacoes apoio_solicitacoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apoio_solicitacoes
    ADD CONSTRAINT apoio_solicitacoes_pkey PRIMARY KEY (id);


--
-- Name: auditoria auditoria_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria
    ADD CONSTRAINT auditoria_pkey PRIMARY KEY (id);


--
-- Name: beneficios beneficios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.beneficios
    ADD CONSTRAINT beneficios_pkey PRIMARY KEY (id);


--
-- Name: categorias_curso categorias_curso_nome_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categorias_curso
    ADD CONSTRAINT categorias_curso_nome_key UNIQUE (nome);


--
-- Name: categorias_curso categorias_curso_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categorias_curso
    ADD CONSTRAINT categorias_curso_pkey PRIMARY KEY (id);


--
-- Name: cerimonias cerimonias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cerimonias
    ADD CONSTRAINT cerimonias_pkey PRIMARY KEY (id);


--
-- Name: certificados certificados_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificados
    ADD CONSTRAINT certificados_codigo_key UNIQUE (codigo);


--
-- Name: certificados_eventos certificados_eventos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificados_eventos
    ADD CONSTRAINT certificados_eventos_pkey PRIMARY KEY (id);


--
-- Name: certificados certificados_inscricao_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificados
    ADD CONSTRAINT certificados_inscricao_id_key UNIQUE (inscricao_id);


--
-- Name: certificados certificados_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificados
    ADD CONSTRAINT certificados_pkey PRIMARY KEY (id);


--
-- Name: colegio_etapas colegio_etapas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colegio_etapas
    ADD CONSTRAINT colegio_etapas_pkey PRIMARY KEY (id);


--
-- Name: colegio_etapas colegio_etapas_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colegio_etapas
    ADD CONSTRAINT colegio_etapas_slug_key UNIQUE (slug);


--
-- Name: comprovantes comprovantes_arquivo_path_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comprovantes
    ADD CONSTRAINT comprovantes_arquivo_path_key UNIQUE (arquivo_path);


--
-- Name: comprovantes comprovantes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comprovantes
    ADD CONSTRAINT comprovantes_pkey PRIMARY KEY (id);


--
-- Name: configuracoes configuracoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.configuracoes
    ADD CONSTRAINT configuracoes_pkey PRIMARY KEY (chave);


--
-- Name: consentimentos consentimentos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consentimentos
    ADD CONSTRAINT consentimentos_pkey PRIMARY KEY (id);


--
-- Name: coordenadores coordenadores_login_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coordenadores
    ADD CONSTRAINT coordenadores_login_key UNIQUE (login);


--
-- Name: coordenadores coordenadores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coordenadores
    ADD CONSTRAINT coordenadores_pkey PRIMARY KEY (id);


--
-- Name: coordenadores coordenadores_usuario_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coordenadores
    ADD CONSTRAINT coordenadores_usuario_id_key UNIQUE (usuario_id);


--
-- Name: cursos_conclusoes_anteriores cursos_conclusoes_anteriores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cursos_conclusoes_anteriores
    ADD CONSTRAINT cursos_conclusoes_anteriores_pkey PRIMARY KEY (id);


--
-- Name: cursos cursos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cursos
    ADD CONSTRAINT cursos_pkey PRIMARY KEY (id);


--
-- Name: cursos cursos_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cursos
    ADD CONSTRAINT cursos_slug_key UNIQUE (slug);


--
-- Name: documentos documentos_arquivo_path_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documentos
    ADD CONSTRAINT documentos_arquivo_path_key UNIQUE (arquivo_path);


--
-- Name: documentos documentos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documentos
    ADD CONSTRAINT documentos_pkey PRIMARY KEY (id);


--
-- Name: escala_areas escala_areas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_areas
    ADD CONSTRAINT escala_areas_pkey PRIMARY KEY (id);


--
-- Name: escala_evento_funcoes escala_evento_funcoes_escala_evento_id_funcao_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_evento_funcoes
    ADD CONSTRAINT escala_evento_funcoes_escala_evento_id_funcao_id_key UNIQUE (escala_evento_id, funcao_id);


--
-- Name: escala_evento_funcoes escala_evento_funcoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_evento_funcoes
    ADD CONSTRAINT escala_evento_funcoes_pkey PRIMARY KEY (id);


--
-- Name: escala_eventos escala_eventos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_eventos
    ADD CONSTRAINT escala_eventos_pkey PRIMARY KEY (id);


--
-- Name: escala_funcoes escala_funcoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_funcoes
    ADD CONSTRAINT escala_funcoes_pkey PRIMARY KEY (id);


--
-- Name: escala_gestores escala_gestores_ministerio_id_perfil_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_gestores
    ADD CONSTRAINT escala_gestores_ministerio_id_perfil_id_key UNIQUE (ministerio_id, perfil_id);


--
-- Name: escala_gestores escala_gestores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_gestores
    ADD CONSTRAINT escala_gestores_pkey PRIMARY KEY (id);


--
-- Name: escala_historico escala_historico_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_historico
    ADD CONSTRAINT escala_historico_pkey PRIMARY KEY (id);


--
-- Name: escala_participacoes escala_participacoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_participacoes
    ADD CONSTRAINT escala_participacoes_pkey PRIMARY KEY (id);


--
-- Name: eventos eventos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eventos
    ADD CONSTRAINT eventos_pkey PRIMARY KEY (id);


--
-- Name: inscricoes inscricoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscricoes
    ADD CONSTRAINT inscricoes_pkey PRIMARY KEY (id);


--
-- Name: inscricoes inscricoes_protocolo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscricoes
    ADD CONSTRAINT inscricoes_protocolo_key UNIQUE (protocolo);


--
-- Name: membresia_processos membresia_processos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membresia_processos
    ADD CONSTRAINT membresia_processos_pkey PRIMARY KEY (id);


--
-- Name: ministerio_membros ministerio_membros_pessoa_id_ministerio_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ministerio_membros
    ADD CONSTRAINT ministerio_membros_pessoa_id_ministerio_id_key UNIQUE (pessoa_id, ministerio_id);


--
-- Name: ministerio_membros ministerio_membros_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ministerio_membros
    ADD CONSTRAINT ministerio_membros_pkey PRIMARY KEY (id);


--
-- Name: ministerio_paginas ministerio_paginas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ministerio_paginas
    ADD CONSTRAINT ministerio_paginas_pkey PRIMARY KEY (ministerio_id);


--
-- Name: ministerios ministerios_nome_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ministerios
    ADD CONSTRAINT ministerios_nome_key UNIQUE (nome);


--
-- Name: ministerios ministerios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ministerios
    ADD CONSTRAINT ministerios_pkey PRIMARY KEY (id);


--
-- Name: ministerios ministerios_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ministerios
    ADD CONSTRAINT ministerios_slug_key UNIQUE (slug);


--
-- Name: notificacoes notificacoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notificacoes
    ADD CONSTRAINT notificacoes_pkey PRIMARY KEY (id);


--
-- Name: organograma_nos organograma_nos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organograma_nos
    ADD CONSTRAINT organograma_nos_pkey PRIMARY KEY (id);


--
-- Name: organogramas organogramas_ministerio_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organogramas
    ADD CONSTRAINT organogramas_ministerio_id_key UNIQUE (ministerio_id);


--
-- Name: organogramas organogramas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organogramas
    ADD CONSTRAINT organogramas_pkey PRIMARY KEY (id);


--
-- Name: pagamentos pagamentos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagamentos
    ADD CONSTRAINT pagamentos_pkey PRIMARY KEY (id);


--
-- Name: perfis perfis_pessoa_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfis
    ADD CONSTRAINT perfis_pessoa_id_key UNIQUE (pessoa_id);


--
-- Name: perfis perfis_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfis
    ADD CONSTRAINT perfis_pkey PRIMARY KEY (id);


--
-- Name: pessoas pessoas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pessoas
    ADD CONSTRAINT pessoas_pkey PRIMARY KEY (id);


--
-- Name: pessoas pessoas_usuario_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pessoas
    ADD CONSTRAINT pessoas_usuario_id_key UNIQUE (usuario_id);


--
-- Name: reembolsos reembolsos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reembolsos
    ADD CONSTRAINT reembolsos_pkey PRIMARY KEY (id);


--
-- Name: reservas reservas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reservas
    ADD CONSTRAINT reservas_pkey PRIMARY KEY (id);


--
-- Name: solicitacoes solicitacoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solicitacoes
    ADD CONSTRAINT solicitacoes_pkey PRIMARY KEY (id);


--
-- Name: termos termos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.termos
    ADD CONSTRAINT termos_pkey PRIMARY KEY (id);


--
-- Name: termos termos_tipo_versao_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.termos
    ADD CONSTRAINT termos_tipo_versao_key UNIQUE (tipo, versao);


--
-- Name: turma_responsaveis turma_responsaveis_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turma_responsaveis
    ADD CONSTRAINT turma_responsaveis_pkey PRIMARY KEY (id);


--
-- Name: turma_responsaveis turma_responsaveis_turma_id_perfil_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turma_responsaveis
    ADD CONSTRAINT turma_responsaveis_turma_id_perfil_id_key UNIQUE (turma_id, perfil_id);


--
-- Name: turmas turmas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turmas
    ADD CONSTRAINT turmas_pkey PRIMARY KEY (id);


--
-- Name: voluntariado_candidaturas voluntariado_candidaturas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntariado_candidaturas
    ADD CONSTRAINT voluntariado_candidaturas_pkey PRIMARY KEY (id);


--
-- Name: voluntariado_indicacoes voluntariado_indicacoes_candidatura_id_ministerio_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntariado_indicacoes
    ADD CONSTRAINT voluntariado_indicacoes_candidatura_id_ministerio_id_key UNIQUE (candidatura_id, ministerio_id);


--
-- Name: voluntariado_indicacoes voluntariado_indicacoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntariado_indicacoes
    ADD CONSTRAINT voluntariado_indicacoes_pkey PRIMARY KEY (id);


--
-- Name: voluntario_capacitacoes voluntario_capacitacoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntario_capacitacoes
    ADD CONSTRAINT voluntario_capacitacoes_pkey PRIMARY KEY (id);


--
-- Name: voluntario_disponibilidade voluntario_disponibilidade_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntario_disponibilidade
    ADD CONSTRAINT voluntario_disponibilidade_pkey PRIMARY KEY (id);


--
-- Name: voluntario_habilitacoes voluntario_habilitacoes_pessoa_id_funcao_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntario_habilitacoes
    ADD CONSTRAINT voluntario_habilitacoes_pessoa_id_funcao_id_key UNIQUE (pessoa_id, funcao_id);


--
-- Name: voluntario_habilitacoes voluntario_habilitacoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntario_habilitacoes
    ADD CONSTRAINT voluntario_habilitacoes_pkey PRIMARY KEY (id);


--
-- Name: voluntario_indisponibilidades voluntario_indisponibilidades_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntario_indisponibilidades
    ADD CONSTRAINT voluntario_indisponibilidades_pkey PRIMARY KEY (id);


--
-- Name: voluntario_preferencias voluntario_preferencias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntario_preferencias
    ADD CONSTRAINT voluntario_preferencias_pkey PRIMARY KEY (pessoa_id);


--
-- Name: migracoes migracoes_pkey; Type: CONSTRAINT; Schema: sistema; Owner: -
--

ALTER TABLE ONLY sistema.migracoes
    ADD CONSTRAINT migracoes_pkey PRIMARY KEY (nome);


--
-- Name: sessoes_sessao_id; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sessoes_sessao_id ON auth.sessoes USING btree (sessao_id);


--
-- Name: sessoes_usuario; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sessoes_usuario ON auth.sessoes USING btree (usuario_id);


--
-- Name: agenda_link_acessos_link; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX agenda_link_acessos_link ON public.agenda_link_acessos USING btree (link_id, quando DESC);


--
-- Name: apoio_servicos_nome; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX apoio_servicos_nome ON public.apoio_servicos USING btree (ministerio_id, lower(nome));


--
-- Name: auditoria_quando_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auditoria_quando_idx ON public.auditoria USING btree (quando DESC);


--
-- Name: candidatura_aberta; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX candidatura_aberta ON public.voluntariado_candidaturas USING btree (pessoa_id) WHERE (status = ANY (ARRAY['aguardando_indicacao'::text, 'em_analise'::text]));


--
-- Name: certificados_eventos_cert; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX certificados_eventos_cert ON public.certificados_eventos USING btree (certificado_id, em);


--
-- Name: comprovantes_pagamento; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX comprovantes_pagamento ON public.comprovantes USING btree (pagamento_id);


--
-- Name: conclusoes_anteriores_unica; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX conclusoes_anteriores_unica ON public.cursos_conclusoes_anteriores USING btree (pessoa_id, curso_id) WHERE (cancelado_em IS NULL);


--
-- Name: consentimentos_pessoa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX consentimentos_pessoa ON public.consentimentos USING btree (pessoa_id, tipo, registrado_em DESC);


--
-- Name: escala_areas_nome; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX escala_areas_nome ON public.escala_areas USING btree (ministerio_id, lower(nome));


--
-- Name: escala_eventos_um_por_evento; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX escala_eventos_um_por_evento ON public.escala_eventos USING btree (evento_id, ministerio_id) WHERE ((evento_id IS NOT NULL) AND (status <> 'cancelada'::text));


--
-- Name: escala_eventos_um_por_solicitacao; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX escala_eventos_um_por_solicitacao ON public.escala_eventos USING btree (solicitacao_id) WHERE ((solicitacao_id IS NOT NULL) AND (status <> 'cancelada'::text));


--
-- Name: escala_funcoes_nome; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX escala_funcoes_nome ON public.escala_funcoes USING btree (area_id, lower(nome));


--
-- Name: escala_historico_evento; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX escala_historico_evento ON public.escala_historico USING btree (escala_evento_id, em);


--
-- Name: escala_participacao_unica; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX escala_participacao_unica ON public.escala_participacoes USING btree (evento_funcao_id, pessoa_id) WHERE (status = ANY (ARRAY['rascunho'::text, 'aguardando'::text, 'confirmado'::text, 'substituicao_necessaria'::text]));


--
-- Name: escala_participacoes_pessoa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX escala_participacoes_pessoa ON public.escala_participacoes USING btree (pessoa_id, status);


--
-- Name: inscricoes_pessoa_turma_ativa; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX inscricoes_pessoa_turma_ativa ON public.inscricoes USING btree (pessoa_id, turma_id) WHERE (status <> 'cancelada'::text);


--
-- Name: inscricoes_turma_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX inscricoes_turma_status ON public.inscricoes USING btree (turma_id, status, criado_em);


--
-- Name: membresia_processo_aberto; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX membresia_processo_aberto ON public.membresia_processos USING btree (pessoa_id) WHERE (status <> ALL (ARRAY['validado'::text, 'encerrado'::text]));


--
-- Name: notificacoes_chave_unica; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX notificacoes_chave_unica ON public.notificacoes USING btree (chave) WHERE (chave IS NOT NULL);


--
-- Name: notificacoes_criado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notificacoes_criado ON public.notificacoes USING btree (criado_em DESC);


--
-- Name: organograma_nos_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX organograma_nos_org ON public.organograma_nos USING btree (organograma_id, pai_id, ordem);


--
-- Name: organogramas_tipo_unico; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX organogramas_tipo_unico ON public.organogramas USING btree (tipo) WHERE (tipo <> 'ministerio'::text);


--
-- Name: pagamentos_inscricao; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pagamentos_inscricao ON public.pagamentos USING btree (inscricao_id);


--
-- Name: pagamentos_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pagamentos_status ON public.pagamentos USING btree (status, registrado_em);


--
-- Name: pessoas_email_unico; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX pessoas_email_unico ON public.pessoas USING btree (email) WHERE ((email IS NOT NULL) AND (arquivado_em IS NULL));


--
-- Name: solicitacoes_acesso_pendente_unica; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX solicitacoes_acesso_pendente_unica ON public.solicitacoes USING btree (email) WHERE ((tipo = 'acesso'::text) AND (status = 'pendente'::text));


--
-- Name: termos_um_vigente; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX termos_um_vigente ON public.termos USING btree (tipo) WHERE (status = 'vigente'::text);


--
-- Name: users betel_senha_alterada; Type: TRIGGER; Schema: auth; Owner: -
--

CREATE TRIGGER betel_senha_alterada AFTER UPDATE OF encrypted_password ON auth.users FOR EACH ROW WHEN ((old.encrypted_password IS DISTINCT FROM new.encrypted_password)) EXECUTE FUNCTION public.tg_senha_alterada();


--
-- Name: eventos agenda_evento_regras; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER agenda_evento_regras BEFORE INSERT OR UPDATE ON public.eventos FOR EACH ROW EXECUTE FUNCTION public.tg_agenda_evento();


--
-- Name: agenda_links agenda_links_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER agenda_links_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.agenda_links FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: reservas agenda_reserva_regras; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER agenda_reserva_regras BEFORE INSERT OR UPDATE ON public.reservas FOR EACH ROW EXECUTE FUNCTION public.tg_agenda_reserva();


--
-- Name: apoio_solicitacao_mensagens apoio_mensagens_nao_excluir; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER apoio_mensagens_nao_excluir BEFORE DELETE ON public.apoio_solicitacao_mensagens FOR EACH ROW EXECUTE FUNCTION public.tg_nao_excluir();


--
-- Name: apoio_servicos apoio_servicos_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER apoio_servicos_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.apoio_servicos FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: apoio_solicitacao_mensagens apoio_solicitacao_mensagens_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER apoio_solicitacao_mensagens_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.apoio_solicitacao_mensagens FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: apoio_solicitacao_servicos apoio_solicitacao_servicos_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER apoio_solicitacao_servicos_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.apoio_solicitacao_servicos FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: apoio_solicitacoes apoio_solicitacoes_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER apoio_solicitacoes_atualizado_em BEFORE UPDATE ON public.apoio_solicitacoes FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: apoio_solicitacoes apoio_solicitacoes_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER apoio_solicitacoes_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.apoio_solicitacoes FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: apoio_solicitacoes apoio_solicitacoes_nao_excluir; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER apoio_solicitacoes_nao_excluir BEFORE DELETE ON public.apoio_solicitacoes FOR EACH ROW EXECUTE FUNCTION public.tg_nao_excluir();


--
-- Name: auditoria auditoria_imutavel; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER auditoria_imutavel BEFORE DELETE OR UPDATE ON public.auditoria FOR EACH ROW EXECUTE FUNCTION public.tg_auditoria_imutavel();


--
-- Name: beneficios beneficios_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER beneficios_atualizado_em BEFORE UPDATE ON public.beneficios FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: beneficios beneficios_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER beneficios_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.beneficios FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: beneficios beneficios_nao_excluir; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER beneficios_nao_excluir BEFORE DELETE ON public.beneficios FOR EACH ROW EXECUTE FUNCTION public.tg_nao_excluir();


--
-- Name: voluntariado_candidaturas candidaturas_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER candidaturas_atualizado_em BEFORE UPDATE ON public.voluntariado_candidaturas FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: voluntariado_candidaturas candidaturas_nao_excluir; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER candidaturas_nao_excluir BEFORE DELETE ON public.voluntariado_candidaturas FOR EACH ROW EXECUTE FUNCTION public.tg_nao_excluir();


--
-- Name: categorias_curso categorias_curso_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER categorias_curso_atualizado_em BEFORE UPDATE ON public.categorias_curso FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: categorias_curso categorias_curso_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER categorias_curso_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.categorias_curso FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: cerimonias cerimonias_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER cerimonias_atualizado_em BEFORE UPDATE ON public.cerimonias FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: cerimonias cerimonias_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER cerimonias_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.cerimonias FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: certificados certificados_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER certificados_atualizado_em BEFORE UPDATE ON public.certificados FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: certificados certificados_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER certificados_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.certificados FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: certificados_eventos certificados_eventos_imutavel; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER certificados_eventos_imutavel BEFORE DELETE OR UPDATE ON public.certificados_eventos FOR EACH ROW EXECUTE FUNCTION public.tg_eventos_imutaveis();


--
-- Name: certificados certificados_eventos_registro; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER certificados_eventos_registro AFTER INSERT OR UPDATE ON public.certificados FOR EACH ROW EXECUTE FUNCTION public.tg_certificado_evento();


--
-- Name: certificados certificados_nao_excluir; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER certificados_nao_excluir BEFORE DELETE ON public.certificados FOR EACH ROW EXECUTE FUNCTION public.tg_nao_excluir();


--
-- Name: colegio_etapas colegio_etapas_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER colegio_etapas_atualizado_em BEFORE UPDATE ON public.colegio_etapas FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: colegio_etapas colegio_etapas_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER colegio_etapas_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.colegio_etapas FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: comprovantes comprovantes_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER comprovantes_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.comprovantes FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: comprovantes comprovantes_nao_excluir; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER comprovantes_nao_excluir BEFORE DELETE ON public.comprovantes FOR EACH ROW EXECUTE FUNCTION public.tg_nao_excluir();


--
-- Name: cursos_conclusoes_anteriores conclusoes_anteriores_nao_excluir; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER conclusoes_anteriores_nao_excluir BEFORE DELETE ON public.cursos_conclusoes_anteriores FOR EACH ROW EXECUTE FUNCTION public.tg_nao_excluir();


--
-- Name: configuracoes configuracoes_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER configuracoes_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.configuracoes FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: consentimentos consentimentos_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER consentimentos_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.consentimentos FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: consentimentos consentimentos_imutavel; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER consentimentos_imutavel BEFORE DELETE OR UPDATE ON public.consentimentos FOR EACH ROW EXECUTE FUNCTION public.tg_consentimento_imutavel();


--
-- Name: coordenadores coordenadores_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER coordenadores_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.coordenadores FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: cursos cursos_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER cursos_atualizado_em BEFORE UPDATE ON public.cursos FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: cursos cursos_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER cursos_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.cursos FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: cursos_conclusoes_anteriores cursos_conclusoes_anteriores_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER cursos_conclusoes_anteriores_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.cursos_conclusoes_anteriores FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: documentos documentos_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER documentos_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.documentos FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: escala_areas escala_areas_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER escala_areas_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.escala_areas FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: escala_eventos escala_eventos_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER escala_eventos_atualizado_em BEFORE UPDATE ON public.escala_eventos FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: escala_eventos escala_eventos_historico; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER escala_eventos_historico AFTER INSERT OR UPDATE ON public.escala_eventos FOR EACH ROW EXECUTE FUNCTION public.tg_escala_historico();


--
-- Name: escala_eventos escala_eventos_nao_excluir; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER escala_eventos_nao_excluir BEFORE DELETE ON public.escala_eventos FOR EACH ROW EXECUTE FUNCTION public.tg_nao_excluir();


--
-- Name: escala_funcoes escala_funcoes_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER escala_funcoes_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.escala_funcoes FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: escala_evento_funcoes escala_funcoes_evento_historico; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER escala_funcoes_evento_historico AFTER INSERT OR UPDATE ON public.escala_evento_funcoes FOR EACH ROW EXECUTE FUNCTION public.tg_escala_historico();


--
-- Name: escala_gestores escala_gestores_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER escala_gestores_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.escala_gestores FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: escala_historico escala_historico_imutavel; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER escala_historico_imutavel BEFORE DELETE OR UPDATE ON public.escala_historico FOR EACH ROW EXECUTE FUNCTION public.tg_historico_imutavel();


--
-- Name: escala_participacoes escala_participacoes_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER escala_participacoes_atualizado_em BEFORE UPDATE ON public.escala_participacoes FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: escala_participacoes escala_participacoes_historico; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER escala_participacoes_historico AFTER INSERT OR UPDATE ON public.escala_participacoes FOR EACH ROW EXECUTE FUNCTION public.tg_escala_historico();


--
-- Name: escala_participacoes escala_participacoes_nao_excluir; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER escala_participacoes_nao_excluir BEFORE DELETE ON public.escala_participacoes FOR EACH ROW EXECUTE FUNCTION public.tg_nao_excluir();


--
-- Name: escala_participacoes escala_participacoes_regras; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER escala_participacoes_regras BEFORE INSERT OR UPDATE ON public.escala_participacoes FOR EACH ROW EXECUTE FUNCTION public.tg_participacao_regras();


--
-- Name: eventos eventos_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER eventos_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.eventos FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: eventos eventos_escala_exclusao; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER eventos_escala_exclusao BEFORE DELETE ON public.eventos FOR EACH ROW EXECUTE FUNCTION public.tg_agenda_escala();


--
-- Name: eventos eventos_escala_mudanca; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER eventos_escala_mudanca AFTER UPDATE ON public.eventos FOR EACH ROW EXECUTE FUNCTION public.tg_agenda_escala();


--
-- Name: voluntariado_indicacoes indicacoes_nao_excluir; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER indicacoes_nao_excluir BEFORE DELETE ON public.voluntariado_indicacoes FOR EACH ROW EXECUTE FUNCTION public.tg_nao_excluir();


--
-- Name: inscricoes inscricoes_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER inscricoes_atualizado_em BEFORE UPDATE ON public.inscricoes FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: inscricoes inscricoes_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER inscricoes_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.inscricoes FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: inscricoes inscricoes_cancelada_paga; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER inscricoes_cancelada_paga AFTER UPDATE OF status ON public.inscricoes FOR EACH ROW EXECUTE FUNCTION public.tg_inscricao_cancelada_paga();


--
-- Name: inscricoes inscricoes_certificado; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER inscricoes_certificado AFTER UPDATE OF status ON public.inscricoes FOR EACH ROW EXECUTE FUNCTION public.tg_certificado_conclusao();


--
-- Name: inscricoes inscricoes_confirmacao_paga; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER inscricoes_confirmacao_paga BEFORE INSERT OR UPDATE OF status ON public.inscricoes FOR EACH ROW EXECUTE FUNCTION public.tg_inscricao_confirmacao_paga();


--
-- Name: inscricoes inscricoes_limite_publico; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER inscricoes_limite_publico BEFORE INSERT ON public.inscricoes FOR EACH ROW EXECUTE FUNCTION public.tg_limite_publico();


--
-- Name: inscricoes inscricoes_membresia_voluntariado; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER inscricoes_membresia_voluntariado AFTER INSERT OR UPDATE OF status ON public.inscricoes FOR EACH ROW EXECUTE FUNCTION public.tg_inscricao_membresia_voluntariado();


--
-- Name: inscricoes inscricoes_vagas; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER inscricoes_vagas BEFORE INSERT OR UPDATE OF status ON public.inscricoes FOR EACH ROW EXECUTE FUNCTION public.tg_inscricao_vagas();


--
-- Name: membresia_processos membresia_limite_publico; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER membresia_limite_publico BEFORE INSERT ON public.membresia_processos FOR EACH ROW EXECUTE FUNCTION public.tg_limite_publico();


--
-- Name: membresia_processos membresia_processos_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER membresia_processos_atualizado_em BEFORE UPDATE ON public.membresia_processos FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: membresia_processos membresia_processos_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER membresia_processos_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.membresia_processos FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: membresia_processos membresia_processos_nao_excluir; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER membresia_processos_nao_excluir BEFORE DELETE ON public.membresia_processos FOR EACH ROW EXECUTE FUNCTION public.tg_nao_excluir();


--
-- Name: ministerio_membros ministerio_membros_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ministerio_membros_atualizado_em BEFORE UPDATE ON public.ministerio_membros FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: ministerio_membros ministerio_membros_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ministerio_membros_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.ministerio_membros FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: ministerio_membros ministerio_membros_voluntario_requisitos; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ministerio_membros_voluntario_requisitos BEFORE INSERT OR UPDATE ON public.ministerio_membros FOR EACH ROW EXECUTE FUNCTION public.tg_voluntario_requisitos();


--
-- Name: ministerio_paginas ministerio_paginas_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ministerio_paginas_atualizado_em BEFORE UPDATE ON public.ministerio_paginas FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: ministerio_paginas ministerio_paginas_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ministerio_paginas_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.ministerio_paginas FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: ministerios ministerios_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ministerios_atualizado_em BEFORE UPDATE ON public.ministerios FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: ministerios ministerios_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ministerios_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.ministerios FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: ministerios ministerios_organograma; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ministerios_organograma AFTER INSERT ON public.ministerios FOR EACH ROW EXECUTE FUNCTION public.tg_ministerio_organograma();


--
-- Name: organograma_nos organograma_nos_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER organograma_nos_atualizado_em BEFORE UPDATE ON public.organograma_nos FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: organograma_nos organograma_nos_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER organograma_nos_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.organograma_nos FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: organogramas organogramas_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER organogramas_atualizado_em BEFORE UPDATE ON public.organogramas FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: organogramas organogramas_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER organogramas_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.organogramas FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: pagamentos pagamentos_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pagamentos_atualizado_em BEFORE UPDATE ON public.pagamentos FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: pagamentos pagamentos_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pagamentos_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.pagamentos FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: pagamentos pagamentos_nao_excluir; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pagamentos_nao_excluir BEFORE DELETE ON public.pagamentos FOR EACH ROW EXECUTE FUNCTION public.tg_nao_excluir();


--
-- Name: perfis perfis_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER perfis_atualizado_em BEFORE UPDATE ON public.perfis FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: perfis perfis_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER perfis_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.perfis FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: perfis perfis_garantir_master; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER perfis_garantir_master BEFORE UPDATE ON public.perfis FOR EACH ROW EXECUTE FUNCTION public.tg_garantir_master();


--
-- Name: pessoas pessoas_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pessoas_atualizado_em BEFORE UPDATE ON public.pessoas FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: pessoas pessoas_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pessoas_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.pessoas FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: reembolsos reembolsos_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER reembolsos_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.reembolsos FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: reembolsos reembolsos_nao_excluir; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER reembolsos_nao_excluir BEFORE DELETE ON public.reembolsos FOR EACH ROW EXECUTE FUNCTION public.tg_nao_excluir();


--
-- Name: reservas reservas_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER reservas_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.reservas FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: solicitacoes solicitacoes_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER solicitacoes_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.solicitacoes FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: termos termos_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER termos_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.termos FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: termos termos_imutavel; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER termos_imutavel BEFORE DELETE OR UPDATE ON public.termos FOR EACH ROW EXECUTE FUNCTION public.tg_termo_imutavel();


--
-- Name: turma_responsaveis turma_responsaveis_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER turma_responsaveis_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.turma_responsaveis FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: turmas turmas_atualizado_em; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER turmas_atualizado_em BEFORE UPDATE ON public.turmas FOR EACH ROW EXECUTE FUNCTION public.tg_atualizado_em();


--
-- Name: turmas turmas_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER turmas_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.turmas FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: voluntariado_candidaturas voluntariado_candidaturas_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER voluntariado_candidaturas_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.voluntariado_candidaturas FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: voluntariado_indicacoes voluntariado_indicacoes_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER voluntariado_indicacoes_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.voluntariado_indicacoes FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: voluntario_capacitacoes voluntario_capacitacoes_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER voluntario_capacitacoes_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.voluntario_capacitacoes FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: voluntario_habilitacoes voluntario_habilitacoes_auditoria; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER voluntario_habilitacoes_auditoria AFTER INSERT OR DELETE OR UPDATE ON public.voluntario_habilitacoes FOR EACH ROW EXECUTE FUNCTION public.tg_auditar();


--
-- Name: recuperacoes recuperacoes_usuario_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.recuperacoes
    ADD CONSTRAINT recuperacoes_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: sessoes sessoes_usuario_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sessoes
    ADD CONSTRAINT sessoes_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: agenda_envios agenda_envios_decidido_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda_envios
    ADD CONSTRAINT agenda_envios_decidido_por_fkey FOREIGN KEY (decidido_por) REFERENCES auth.users(id);


--
-- Name: agenda_envios_historico agenda_envios_historico_envio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda_envios_historico
    ADD CONSTRAINT agenda_envios_historico_envio_id_fkey FOREIGN KEY (envio_id) REFERENCES public.agenda_envios(id);


--
-- Name: agenda_envios agenda_envios_link_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda_envios
    ADD CONSTRAINT agenda_envios_link_id_fkey FOREIGN KEY (link_id) REFERENCES public.agenda_links(id);


--
-- Name: agenda_link_acessos agenda_link_acessos_link_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda_link_acessos
    ADD CONSTRAINT agenda_link_acessos_link_id_fkey FOREIGN KEY (link_id) REFERENCES public.agenda_links(id);


--
-- Name: agenda_links agenda_links_criado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda_links
    ADD CONSTRAINT agenda_links_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES auth.users(id);


--
-- Name: agenda_links agenda_links_ministerio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda_links
    ADD CONSTRAINT agenda_links_ministerio_id_fkey FOREIGN KEY (ministerio_id) REFERENCES public.ministerios(id);


--
-- Name: agenda_links agenda_links_revogado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda_links
    ADD CONSTRAINT agenda_links_revogado_por_fkey FOREIGN KEY (revogado_por) REFERENCES auth.users(id);


--
-- Name: apoio_servico_funcoes apoio_servico_funcoes_funcao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apoio_servico_funcoes
    ADD CONSTRAINT apoio_servico_funcoes_funcao_id_fkey FOREIGN KEY (funcao_id) REFERENCES public.escala_funcoes(id);


--
-- Name: apoio_servico_funcoes apoio_servico_funcoes_servico_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apoio_servico_funcoes
    ADD CONSTRAINT apoio_servico_funcoes_servico_id_fkey FOREIGN KEY (servico_id) REFERENCES public.apoio_servicos(id);


--
-- Name: apoio_servicos apoio_servicos_ministerio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apoio_servicos
    ADD CONSTRAINT apoio_servicos_ministerio_id_fkey FOREIGN KEY (ministerio_id) REFERENCES public.ministerios(id);


--
-- Name: apoio_solicitacao_mensagens apoio_solicitacao_mensagens_autor_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apoio_solicitacao_mensagens
    ADD CONSTRAINT apoio_solicitacao_mensagens_autor_fkey FOREIGN KEY (autor) REFERENCES auth.users(id);


--
-- Name: apoio_solicitacao_mensagens apoio_solicitacao_mensagens_solicitacao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apoio_solicitacao_mensagens
    ADD CONSTRAINT apoio_solicitacao_mensagens_solicitacao_id_fkey FOREIGN KEY (solicitacao_id) REFERENCES public.apoio_solicitacoes(id);


--
-- Name: apoio_solicitacao_servicos apoio_solicitacao_servicos_decidido_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apoio_solicitacao_servicos
    ADD CONSTRAINT apoio_solicitacao_servicos_decidido_por_fkey FOREIGN KEY (decidido_por) REFERENCES auth.users(id);


--
-- Name: apoio_solicitacao_servicos apoio_solicitacao_servicos_servico_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apoio_solicitacao_servicos
    ADD CONSTRAINT apoio_solicitacao_servicos_servico_id_fkey FOREIGN KEY (servico_id) REFERENCES public.apoio_servicos(id);


--
-- Name: apoio_solicitacao_servicos apoio_solicitacao_servicos_solicitacao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apoio_solicitacao_servicos
    ADD CONSTRAINT apoio_solicitacao_servicos_solicitacao_id_fkey FOREIGN KEY (solicitacao_id) REFERENCES public.apoio_solicitacoes(id);


--
-- Name: apoio_solicitacoes apoio_solicitacoes_decidido_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apoio_solicitacoes
    ADD CONSTRAINT apoio_solicitacoes_decidido_por_fkey FOREIGN KEY (decidido_por) REFERENCES auth.users(id);


--
-- Name: apoio_solicitacoes apoio_solicitacoes_evento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apoio_solicitacoes
    ADD CONSTRAINT apoio_solicitacoes_evento_id_fkey FOREIGN KEY (evento_id) REFERENCES public.eventos(id) ON DELETE SET NULL;


--
-- Name: apoio_solicitacoes apoio_solicitacoes_ministerio_alvo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apoio_solicitacoes
    ADD CONSTRAINT apoio_solicitacoes_ministerio_alvo_fkey FOREIGN KEY (ministerio_alvo) REFERENCES public.ministerios(id);


--
-- Name: apoio_solicitacoes apoio_solicitacoes_ministerio_solicitante_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apoio_solicitacoes
    ADD CONSTRAINT apoio_solicitacoes_ministerio_solicitante_fkey FOREIGN KEY (ministerio_solicitante) REFERENCES public.ministerios(id);


--
-- Name: apoio_solicitacoes apoio_solicitacoes_solicitado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apoio_solicitacoes
    ADD CONSTRAINT apoio_solicitacoes_solicitado_por_fkey FOREIGN KEY (solicitado_por) REFERENCES auth.users(id);


--
-- Name: beneficios beneficios_analisado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.beneficios
    ADD CONSTRAINT beneficios_analisado_por_fkey FOREIGN KEY (analisado_por) REFERENCES auth.users(id);


--
-- Name: beneficios beneficios_inscricao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.beneficios
    ADD CONSTRAINT beneficios_inscricao_id_fkey FOREIGN KEY (inscricao_id) REFERENCES public.inscricoes(id);


--
-- Name: beneficios beneficios_solicitado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.beneficios
    ADD CONSTRAINT beneficios_solicitado_por_fkey FOREIGN KEY (solicitado_por) REFERENCES auth.users(id);


--
-- Name: cerimonias cerimonias_realizada_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cerimonias
    ADD CONSTRAINT cerimonias_realizada_por_fkey FOREIGN KEY (realizada_por) REFERENCES auth.users(id);


--
-- Name: certificados certificados_autorizado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificados
    ADD CONSTRAINT certificados_autorizado_por_fkey FOREIGN KEY (autorizado_por) REFERENCES auth.users(id);


--
-- Name: certificados certificados_cerimonia_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificados
    ADD CONSTRAINT certificados_cerimonia_id_fkey FOREIGN KEY (cerimonia_id) REFERENCES public.cerimonias(id);


--
-- Name: certificados certificados_entregue_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificados
    ADD CONSTRAINT certificados_entregue_por_fkey FOREIGN KEY (entregue_por) REFERENCES auth.users(id);


--
-- Name: certificados_eventos certificados_eventos_ator_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificados_eventos
    ADD CONSTRAINT certificados_eventos_ator_fkey FOREIGN KEY (ator) REFERENCES auth.users(id);


--
-- Name: certificados_eventos certificados_eventos_certificado_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificados_eventos
    ADD CONSTRAINT certificados_eventos_certificado_id_fkey FOREIGN KEY (certificado_id) REFERENCES public.certificados(id);


--
-- Name: certificados certificados_impresso_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificados
    ADD CONSTRAINT certificados_impresso_por_fkey FOREIGN KEY (impresso_por) REFERENCES auth.users(id);


--
-- Name: certificados certificados_inscricao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificados
    ADD CONSTRAINT certificados_inscricao_id_fkey FOREIGN KEY (inscricao_id) REFERENCES public.inscricoes(id);


--
-- Name: certificados certificados_preparado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificados
    ADD CONSTRAINT certificados_preparado_por_fkey FOREIGN KEY (preparado_por) REFERENCES auth.users(id);


--
-- Name: certificados certificados_validado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificados
    ADD CONSTRAINT certificados_validado_por_fkey FOREIGN KEY (validado_por) REFERENCES auth.users(id);


--
-- Name: colegio_etapas colegio_etapas_validado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.colegio_etapas
    ADD CONSTRAINT colegio_etapas_validado_por_fkey FOREIGN KEY (validado_por) REFERENCES auth.users(id);


--
-- Name: comprovantes comprovantes_enviado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comprovantes
    ADD CONSTRAINT comprovantes_enviado_por_fkey FOREIGN KEY (enviado_por) REFERENCES auth.users(id);


--
-- Name: comprovantes comprovantes_pagamento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comprovantes
    ADD CONSTRAINT comprovantes_pagamento_id_fkey FOREIGN KEY (pagamento_id) REFERENCES public.pagamentos(id);


--
-- Name: configuracoes configuracoes_atualizado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.configuracoes
    ADD CONSTRAINT configuracoes_atualizado_por_fkey FOREIGN KEY (atualizado_por) REFERENCES auth.users(id);


--
-- Name: consentimentos consentimentos_documento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consentimentos
    ADD CONSTRAINT consentimentos_documento_id_fkey FOREIGN KEY (documento_id) REFERENCES public.documentos(id);


--
-- Name: consentimentos consentimentos_pessoa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consentimentos
    ADD CONSTRAINT consentimentos_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES public.pessoas(id);


--
-- Name: consentimentos consentimentos_registrado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consentimentos
    ADD CONSTRAINT consentimentos_registrado_por_fkey FOREIGN KEY (registrado_por) REFERENCES auth.users(id);


--
-- Name: consentimentos consentimentos_revogado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consentimentos
    ADD CONSTRAINT consentimentos_revogado_por_fkey FOREIGN KEY (revogado_por) REFERENCES auth.users(id);


--
-- Name: consentimentos consentimentos_termo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consentimentos
    ADD CONSTRAINT consentimentos_termo_id_fkey FOREIGN KEY (termo_id) REFERENCES public.termos(id);


--
-- Name: coordenadores coordenadores_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coordenadores
    ADD CONSTRAINT coordenadores_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES auth.users(id);


--
-- Name: cursos cursos_categoria_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cursos
    ADD CONSTRAINT cursos_categoria_id_fkey FOREIGN KEY (categoria_id) REFERENCES public.categorias_curso(id);


--
-- Name: cursos_conclusoes_anteriores cursos_conclusoes_anteriores_curso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cursos_conclusoes_anteriores
    ADD CONSTRAINT cursos_conclusoes_anteriores_curso_id_fkey FOREIGN KEY (curso_id) REFERENCES public.cursos(id);


--
-- Name: cursos_conclusoes_anteriores cursos_conclusoes_anteriores_documento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cursos_conclusoes_anteriores
    ADD CONSTRAINT cursos_conclusoes_anteriores_documento_id_fkey FOREIGN KEY (documento_id) REFERENCES public.documentos(id);


--
-- Name: cursos_conclusoes_anteriores cursos_conclusoes_anteriores_pessoa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cursos_conclusoes_anteriores
    ADD CONSTRAINT cursos_conclusoes_anteriores_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES public.pessoas(id);


--
-- Name: cursos_conclusoes_anteriores cursos_conclusoes_anteriores_registrado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cursos_conclusoes_anteriores
    ADD CONSTRAINT cursos_conclusoes_anteriores_registrado_por_fkey FOREIGN KEY (registrado_por) REFERENCES auth.users(id);


--
-- Name: cursos cursos_criado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cursos
    ADD CONSTRAINT cursos_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES auth.users(id);


--
-- Name: cursos cursos_ministerio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cursos
    ADD CONSTRAINT cursos_ministerio_id_fkey FOREIGN KEY (ministerio_id) REFERENCES public.ministerios(id);


--
-- Name: documentos documentos_enviado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documentos
    ADD CONSTRAINT documentos_enviado_por_fkey FOREIGN KEY (enviado_por) REFERENCES auth.users(id);


--
-- Name: documentos documentos_inscricao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documentos
    ADD CONSTRAINT documentos_inscricao_id_fkey FOREIGN KEY (inscricao_id) REFERENCES public.inscricoes(id);


--
-- Name: documentos documentos_pessoa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documentos
    ADD CONSTRAINT documentos_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES public.pessoas(id);


--
-- Name: escala_areas escala_areas_ministerio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_areas
    ADD CONSTRAINT escala_areas_ministerio_id_fkey FOREIGN KEY (ministerio_id) REFERENCES public.ministerios(id);


--
-- Name: escala_evento_funcoes escala_evento_funcoes_escala_evento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_evento_funcoes
    ADD CONSTRAINT escala_evento_funcoes_escala_evento_id_fkey FOREIGN KEY (escala_evento_id) REFERENCES public.escala_eventos(id);


--
-- Name: escala_evento_funcoes escala_evento_funcoes_funcao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_evento_funcoes
    ADD CONSTRAINT escala_evento_funcoes_funcao_id_fkey FOREIGN KEY (funcao_id) REFERENCES public.escala_funcoes(id);


--
-- Name: escala_eventos escala_eventos_criado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_eventos
    ADD CONSTRAINT escala_eventos_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES auth.users(id);


--
-- Name: escala_eventos escala_eventos_evento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_eventos
    ADD CONSTRAINT escala_eventos_evento_id_fkey FOREIGN KEY (evento_id) REFERENCES public.eventos(id) ON DELETE SET NULL;


--
-- Name: escala_eventos escala_eventos_ministerio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_eventos
    ADD CONSTRAINT escala_eventos_ministerio_id_fkey FOREIGN KEY (ministerio_id) REFERENCES public.ministerios(id);


--
-- Name: escala_eventos escala_eventos_solicitacao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_eventos
    ADD CONSTRAINT escala_eventos_solicitacao_id_fkey FOREIGN KEY (solicitacao_id) REFERENCES public.apoio_solicitacoes(id);


--
-- Name: escala_funcoes escala_funcoes_area_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_funcoes
    ADD CONSTRAINT escala_funcoes_area_id_fkey FOREIGN KEY (area_id) REFERENCES public.escala_areas(id);


--
-- Name: escala_gestores escala_gestores_criado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_gestores
    ADD CONSTRAINT escala_gestores_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES auth.users(id);


--
-- Name: escala_gestores escala_gestores_ministerio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_gestores
    ADD CONSTRAINT escala_gestores_ministerio_id_fkey FOREIGN KEY (ministerio_id) REFERENCES public.ministerios(id);


--
-- Name: escala_gestores escala_gestores_perfil_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_gestores
    ADD CONSTRAINT escala_gestores_perfil_id_fkey FOREIGN KEY (perfil_id) REFERENCES public.perfis(id);


--
-- Name: escala_historico escala_historico_ator_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_historico
    ADD CONSTRAINT escala_historico_ator_fkey FOREIGN KEY (ator) REFERENCES auth.users(id);


--
-- Name: escala_historico escala_historico_escala_evento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_historico
    ADD CONSTRAINT escala_historico_escala_evento_id_fkey FOREIGN KEY (escala_evento_id) REFERENCES public.escala_eventos(id);


--
-- Name: escala_historico escala_historico_participacao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_historico
    ADD CONSTRAINT escala_historico_participacao_id_fkey FOREIGN KEY (participacao_id) REFERENCES public.escala_participacoes(id);


--
-- Name: escala_participacoes escala_participacoes_criado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_participacoes
    ADD CONSTRAINT escala_participacoes_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES auth.users(id);


--
-- Name: escala_participacoes escala_participacoes_escala_evento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_participacoes
    ADD CONSTRAINT escala_participacoes_escala_evento_id_fkey FOREIGN KEY (escala_evento_id) REFERENCES public.escala_eventos(id);


--
-- Name: escala_participacoes escala_participacoes_evento_funcao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_participacoes
    ADD CONSTRAINT escala_participacoes_evento_funcao_id_fkey FOREIGN KEY (evento_funcao_id) REFERENCES public.escala_evento_funcoes(id);


--
-- Name: escala_participacoes escala_participacoes_pessoa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_participacoes
    ADD CONSTRAINT escala_participacoes_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES public.pessoas(id);


--
-- Name: escala_participacoes escala_participacoes_presenca_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_participacoes
    ADD CONSTRAINT escala_participacoes_presenca_por_fkey FOREIGN KEY (presenca_por) REFERENCES auth.users(id);


--
-- Name: escala_participacoes escala_participacoes_substitui_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escala_participacoes
    ADD CONSTRAINT escala_participacoes_substitui_id_fkey FOREIGN KEY (substitui_id) REFERENCES public.escala_participacoes(id);


--
-- Name: eventos eventos_atualizado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eventos
    ADD CONSTRAINT eventos_atualizado_por_fkey FOREIGN KEY (atualizado_por) REFERENCES auth.users(id);


--
-- Name: eventos eventos_criado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eventos
    ADD CONSTRAINT eventos_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES auth.users(id);


--
-- Name: eventos eventos_ministerio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eventos
    ADD CONSTRAINT eventos_ministerio_id_fkey FOREIGN KEY (ministerio_id) REFERENCES public.ministerios(id);


--
-- Name: inscricoes inscricoes_concluida_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscricoes
    ADD CONSTRAINT inscricoes_concluida_por_fkey FOREIGN KEY (concluida_por) REFERENCES auth.users(id);


--
-- Name: inscricoes inscricoes_criado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscricoes
    ADD CONSTRAINT inscricoes_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES auth.users(id);


--
-- Name: inscricoes inscricoes_pessoa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscricoes
    ADD CONSTRAINT inscricoes_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES public.pessoas(id);


--
-- Name: inscricoes inscricoes_turma_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscricoes
    ADD CONSTRAINT inscricoes_turma_id_fkey FOREIGN KEY (turma_id) REFERENCES public.turmas(id);


--
-- Name: membresia_processos membresia_processos_inscricao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membresia_processos
    ADD CONSTRAINT membresia_processos_inscricao_id_fkey FOREIGN KEY (inscricao_id) REFERENCES public.inscricoes(id);


--
-- Name: membresia_processos membresia_processos_pessoa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membresia_processos
    ADD CONSTRAINT membresia_processos_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES public.pessoas(id);


--
-- Name: ministerio_membros ministerio_membros_ministerio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ministerio_membros
    ADD CONSTRAINT ministerio_membros_ministerio_id_fkey FOREIGN KEY (ministerio_id) REFERENCES public.ministerios(id);


--
-- Name: ministerio_membros ministerio_membros_pessoa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ministerio_membros
    ADD CONSTRAINT ministerio_membros_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES public.pessoas(id);


--
-- Name: ministerio_paginas ministerio_paginas_atualizado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ministerio_paginas
    ADD CONSTRAINT ministerio_paginas_atualizado_por_fkey FOREIGN KEY (atualizado_por) REFERENCES auth.users(id);


--
-- Name: ministerio_paginas ministerio_paginas_confirmados_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ministerio_paginas
    ADD CONSTRAINT ministerio_paginas_confirmados_por_fkey FOREIGN KEY (confirmados_por) REFERENCES auth.users(id);


--
-- Name: ministerio_paginas ministerio_paginas_ministerio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ministerio_paginas
    ADD CONSTRAINT ministerio_paginas_ministerio_id_fkey FOREIGN KEY (ministerio_id) REFERENCES public.ministerios(id);


--
-- Name: ministerio_paginas ministerio_paginas_vice_pessoa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ministerio_paginas
    ADD CONSTRAINT ministerio_paginas_vice_pessoa_id_fkey FOREIGN KEY (vice_pessoa_id) REFERENCES public.pessoas(id);


--
-- Name: notificacoes notificacoes_para_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notificacoes
    ADD CONSTRAINT notificacoes_para_usuario_fkey FOREIGN KEY (para_usuario) REFERENCES auth.users(id);


--
-- Name: organograma_nos organograma_nos_atualizado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organograma_nos
    ADD CONSTRAINT organograma_nos_atualizado_por_fkey FOREIGN KEY (atualizado_por) REFERENCES auth.users(id);


--
-- Name: organograma_nos organograma_nos_organograma_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organograma_nos
    ADD CONSTRAINT organograma_nos_organograma_id_fkey FOREIGN KEY (organograma_id) REFERENCES public.organogramas(id);


--
-- Name: organograma_nos organograma_nos_pai_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organograma_nos
    ADD CONSTRAINT organograma_nos_pai_id_fkey FOREIGN KEY (pai_id) REFERENCES public.organograma_nos(id);


--
-- Name: organograma_nos organograma_nos_pessoa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organograma_nos
    ADD CONSTRAINT organograma_nos_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES public.pessoas(id);


--
-- Name: organogramas organogramas_ministerio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organogramas
    ADD CONSTRAINT organogramas_ministerio_id_fkey FOREIGN KEY (ministerio_id) REFERENCES public.ministerios(id);


--
-- Name: pagamentos pagamentos_analisado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagamentos
    ADD CONSTRAINT pagamentos_analisado_por_fkey FOREIGN KEY (analisado_por) REFERENCES auth.users(id);


--
-- Name: pagamentos pagamentos_inscricao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagamentos
    ADD CONSTRAINT pagamentos_inscricao_id_fkey FOREIGN KEY (inscricao_id) REFERENCES public.inscricoes(id);


--
-- Name: pagamentos pagamentos_registrado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagamentos
    ADD CONSTRAINT pagamentos_registrado_por_fkey FOREIGN KEY (registrado_por) REFERENCES auth.users(id);


--
-- Name: perfis perfis_aprovado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfis
    ADD CONSTRAINT perfis_aprovado_por_fkey FOREIGN KEY (aprovado_por) REFERENCES auth.users(id);


--
-- Name: perfis perfis_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfis
    ADD CONSTRAINT perfis_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE RESTRICT;


--
-- Name: perfis perfis_pessoa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfis
    ADD CONSTRAINT perfis_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES public.pessoas(id);


--
-- Name: pessoas pessoas_membresia_validada_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pessoas
    ADD CONSTRAINT pessoas_membresia_validada_por_fkey FOREIGN KEY (membresia_validada_por) REFERENCES auth.users(id);


--
-- Name: pessoas pessoas_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pessoas
    ADD CONSTRAINT pessoas_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES auth.users(id) ON DELETE RESTRICT;


--
-- Name: reembolsos reembolsos_inscricao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reembolsos
    ADD CONSTRAINT reembolsos_inscricao_id_fkey FOREIGN KEY (inscricao_id) REFERENCES public.inscricoes(id);


--
-- Name: reembolsos reembolsos_pagamento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reembolsos
    ADD CONSTRAINT reembolsos_pagamento_id_fkey FOREIGN KEY (pagamento_id) REFERENCES public.pagamentos(id);


--
-- Name: reembolsos reembolsos_registrado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reembolsos
    ADD CONSTRAINT reembolsos_registrado_por_fkey FOREIGN KEY (registrado_por) REFERENCES auth.users(id);


--
-- Name: reservas reservas_criado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reservas
    ADD CONSTRAINT reservas_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES auth.users(id);


--
-- Name: reservas reservas_ministerio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reservas
    ADD CONSTRAINT reservas_ministerio_id_fkey FOREIGN KEY (ministerio_id) REFERENCES public.ministerios(id);


--
-- Name: solicitacoes solicitacoes_analisado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solicitacoes
    ADD CONSTRAINT solicitacoes_analisado_por_fkey FOREIGN KEY (analisado_por) REFERENCES auth.users(id);


--
-- Name: solicitacoes solicitacoes_ministerio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solicitacoes
    ADD CONSTRAINT solicitacoes_ministerio_id_fkey FOREIGN KEY (ministerio_id) REFERENCES public.ministerios(id);


--
-- Name: solicitacoes solicitacoes_pessoa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solicitacoes
    ADD CONSTRAINT solicitacoes_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES public.pessoas(id);


--
-- Name: termos termos_criado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.termos
    ADD CONSTRAINT termos_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES auth.users(id);


--
-- Name: termos termos_publicado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.termos
    ADD CONSTRAINT termos_publicado_por_fkey FOREIGN KEY (publicado_por) REFERENCES auth.users(id);


--
-- Name: turma_responsaveis turma_responsaveis_criado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turma_responsaveis
    ADD CONSTRAINT turma_responsaveis_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES auth.users(id);


--
-- Name: turma_responsaveis turma_responsaveis_perfil_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turma_responsaveis
    ADD CONSTRAINT turma_responsaveis_perfil_id_fkey FOREIGN KEY (perfil_id) REFERENCES public.perfis(id);


--
-- Name: turma_responsaveis turma_responsaveis_turma_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turma_responsaveis
    ADD CONSTRAINT turma_responsaveis_turma_id_fkey FOREIGN KEY (turma_id) REFERENCES public.turmas(id);


--
-- Name: turmas turmas_curso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.turmas
    ADD CONSTRAINT turmas_curso_id_fkey FOREIGN KEY (curso_id) REFERENCES public.cursos(id);


--
-- Name: voluntariado_candidaturas voluntariado_candidaturas_inscricao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntariado_candidaturas
    ADD CONSTRAINT voluntariado_candidaturas_inscricao_id_fkey FOREIGN KEY (inscricao_id) REFERENCES public.inscricoes(id);


--
-- Name: voluntariado_candidaturas voluntariado_candidaturas_pessoa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntariado_candidaturas
    ADD CONSTRAINT voluntariado_candidaturas_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES public.pessoas(id);


--
-- Name: voluntariado_indicacoes voluntariado_indicacoes_analisado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntariado_indicacoes
    ADD CONSTRAINT voluntariado_indicacoes_analisado_por_fkey FOREIGN KEY (analisado_por) REFERENCES auth.users(id);


--
-- Name: voluntariado_indicacoes voluntariado_indicacoes_candidatura_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntariado_indicacoes
    ADD CONSTRAINT voluntariado_indicacoes_candidatura_id_fkey FOREIGN KEY (candidatura_id) REFERENCES public.voluntariado_candidaturas(id);


--
-- Name: voluntariado_indicacoes voluntariado_indicacoes_ministerio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntariado_indicacoes
    ADD CONSTRAINT voluntariado_indicacoes_ministerio_id_fkey FOREIGN KEY (ministerio_id) REFERENCES public.ministerios(id);


--
-- Name: voluntario_capacitacoes voluntario_capacitacoes_funcao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntario_capacitacoes
    ADD CONSTRAINT voluntario_capacitacoes_funcao_id_fkey FOREIGN KEY (funcao_id) REFERENCES public.escala_funcoes(id);


--
-- Name: voluntario_capacitacoes voluntario_capacitacoes_pessoa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntario_capacitacoes
    ADD CONSTRAINT voluntario_capacitacoes_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES public.pessoas(id);


--
-- Name: voluntario_capacitacoes voluntario_capacitacoes_registrado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntario_capacitacoes
    ADD CONSTRAINT voluntario_capacitacoes_registrado_por_fkey FOREIGN KEY (registrado_por) REFERENCES auth.users(id);


--
-- Name: voluntario_disponibilidade voluntario_disponibilidade_pessoa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntario_disponibilidade
    ADD CONSTRAINT voluntario_disponibilidade_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES public.pessoas(id);


--
-- Name: voluntario_habilitacoes voluntario_habilitacoes_autorizado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntario_habilitacoes
    ADD CONSTRAINT voluntario_habilitacoes_autorizado_por_fkey FOREIGN KEY (autorizado_por) REFERENCES auth.users(id);


--
-- Name: voluntario_habilitacoes voluntario_habilitacoes_funcao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntario_habilitacoes
    ADD CONSTRAINT voluntario_habilitacoes_funcao_id_fkey FOREIGN KEY (funcao_id) REFERENCES public.escala_funcoes(id);


--
-- Name: voluntario_habilitacoes voluntario_habilitacoes_pessoa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntario_habilitacoes
    ADD CONSTRAINT voluntario_habilitacoes_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES public.pessoas(id);


--
-- Name: voluntario_indisponibilidades voluntario_indisponibilidades_pessoa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntario_indisponibilidades
    ADD CONSTRAINT voluntario_indisponibilidades_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES public.pessoas(id);


--
-- Name: voluntario_preferencias voluntario_preferencias_pessoa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.voluntario_preferencias
    ADD CONSTRAINT voluntario_preferencias_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES public.pessoas(id);


--
-- Name: agenda_envios; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.agenda_envios ENABLE ROW LEVEL SECURITY;

--
-- Name: agenda_envios_historico agenda_envios_hist_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY agenda_envios_hist_leitura ON public.agenda_envios_historico FOR SELECT TO authenticated USING (public.agenda_coordenador());


--
-- Name: agenda_envios_historico; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.agenda_envios_historico ENABLE ROW LEVEL SECURITY;

--
-- Name: agenda_envios agenda_envios_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY agenda_envios_leitura ON public.agenda_envios FOR SELECT TO authenticated USING (public.agenda_coordenador());


--
-- Name: eventos agenda_eventos_atualizar; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY agenda_eventos_atualizar ON public.eventos FOR UPDATE TO authenticated USING (public.agenda_pode_editar_ficha(ministerio_id)) WITH CHECK (public.agenda_pode_editar_ficha(ministerio_id));


--
-- Name: eventos agenda_eventos_excluir; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY agenda_eventos_excluir ON public.eventos FOR DELETE TO authenticated USING (public.agenda_coordenador());


--
-- Name: eventos agenda_eventos_inserir; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY agenda_eventos_inserir ON public.eventos FOR INSERT TO authenticated WITH CHECK (public.agenda_coordenador());


--
-- Name: eventos agenda_eventos_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY agenda_eventos_leitura ON public.eventos FOR SELECT TO anon, authenticated USING (true);


--
-- Name: agenda_link_acessos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.agenda_link_acessos ENABLE ROW LEVEL SECURITY;

--
-- Name: agenda_link_acessos agenda_link_acessos_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY agenda_link_acessos_leitura ON public.agenda_link_acessos FOR SELECT TO authenticated USING (public.agenda_coordenador());


--
-- Name: agenda_links; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.agenda_links ENABLE ROW LEVEL SECURITY;

--
-- Name: agenda_links agenda_links_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY agenda_links_leitura ON public.agenda_links FOR SELECT TO authenticated USING (public.agenda_coordenador());


--
-- Name: reservas agenda_reservas_atualizar; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY agenda_reservas_atualizar ON public.reservas FOR UPDATE TO authenticated USING (public.agenda_coordenador()) WITH CHECK (public.agenda_coordenador());


--
-- Name: reservas agenda_reservas_excluir; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY agenda_reservas_excluir ON public.reservas FOR DELETE TO authenticated USING (public.agenda_coordenador());


--
-- Name: reservas agenda_reservas_inserir; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY agenda_reservas_inserir ON public.reservas FOR INSERT TO authenticated WITH CHECK (public.agenda_coordenador());


--
-- Name: reservas agenda_reservas_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY agenda_reservas_leitura ON public.reservas FOR SELECT TO anon, authenticated USING (true);


--
-- Name: apoio_servico_funcoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.apoio_servico_funcoes ENABLE ROW LEVEL SECURITY;

--
-- Name: apoio_servicos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.apoio_servicos ENABLE ROW LEVEL SECURITY;

--
-- Name: apoio_solicitacao_mensagens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.apoio_solicitacao_mensagens ENABLE ROW LEVEL SECURITY;

--
-- Name: apoio_solicitacao_servicos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.apoio_solicitacao_servicos ENABLE ROW LEVEL SECURITY;

--
-- Name: apoio_solicitacoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.apoio_solicitacoes ENABLE ROW LEVEL SECURITY;

--
-- Name: auditoria; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.auditoria ENABLE ROW LEVEL SECURITY;

--
-- Name: auditoria auditoria_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY auditoria_leitura ON public.auditoria FOR SELECT TO authenticated USING (public.e_master());


--
-- Name: beneficios; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.beneficios ENABLE ROW LEVEL SECURITY;

--
-- Name: categorias_curso; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.categorias_curso ENABLE ROW LEVEL SECURITY;

--
-- Name: categorias_curso categorias_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY categorias_leitura ON public.categorias_curso FOR SELECT TO anon, authenticated USING ((ativo OR public.cursos_gestor()));


--
-- Name: cerimonias; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cerimonias ENABLE ROW LEVEL SECURITY;

--
-- Name: certificados; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.certificados ENABLE ROW LEVEL SECURITY;

--
-- Name: certificados_eventos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.certificados_eventos ENABLE ROW LEVEL SECURITY;

--
-- Name: colegio_etapas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.colegio_etapas ENABLE ROW LEVEL SECURITY;

--
-- Name: colegio_etapas colegio_etapas_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY colegio_etapas_leitura ON public.colegio_etapas FOR SELECT TO authenticated USING (public.e_master());


--
-- Name: comprovantes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.comprovantes ENABLE ROW LEVEL SECURITY;

--
-- Name: configuracoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.configuracoes ENABLE ROW LEVEL SECURITY;

--
-- Name: configuracoes configuracoes_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY configuracoes_leitura ON public.configuracoes FOR SELECT TO anon, authenticated USING ((publico OR public.perfil_ativo()));


--
-- Name: consentimentos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.consentimentos ENABLE ROW LEVEL SECURITY;

--
-- Name: coordenadores; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.coordenadores ENABLE ROW LEVEL SECURITY;

--
-- Name: cursos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cursos ENABLE ROW LEVEL SECURITY;

--
-- Name: cursos_conclusoes_anteriores; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cursos_conclusoes_anteriores ENABLE ROW LEVEL SECURITY;

--
-- Name: cursos cursos_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cursos_leitura ON public.cursos FOR SELECT TO anon, authenticated USING ((publicado OR public.cursos_gestor()));


--
-- Name: documentos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.documentos ENABLE ROW LEVEL SECURITY;

--
-- Name: escala_areas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.escala_areas ENABLE ROW LEVEL SECURITY;

--
-- Name: escala_evento_funcoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.escala_evento_funcoes ENABLE ROW LEVEL SECURITY;

--
-- Name: escala_eventos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.escala_eventos ENABLE ROW LEVEL SECURITY;

--
-- Name: escala_funcoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.escala_funcoes ENABLE ROW LEVEL SECURITY;

--
-- Name: escala_gestores; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.escala_gestores ENABLE ROW LEVEL SECURITY;

--
-- Name: escala_historico; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.escala_historico ENABLE ROW LEVEL SECURITY;

--
-- Name: escala_participacoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.escala_participacoes ENABLE ROW LEVEL SECURITY;

--
-- Name: eventos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.eventos ENABLE ROW LEVEL SECURITY;

--
-- Name: inscricoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inscricoes ENABLE ROW LEVEL SECURITY;

--
-- Name: inscricoes inscricoes_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY inscricoes_leitura ON public.inscricoes FOR SELECT TO authenticated USING ((public.cursos_gestor() OR (pessoa_id = public.minha_pessoa_id())));


--
-- Name: membresia_processos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.membresia_processos ENABLE ROW LEVEL SECURITY;

--
-- Name: ministerio_membros; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ministerio_membros ENABLE ROW LEVEL SECURITY;

--
-- Name: ministerio_membros ministerio_membros_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ministerio_membros_leitura ON public.ministerio_membros FOR SELECT TO authenticated USING (((pessoa_id = public.minha_pessoa_id()) OR public.e_master() OR public.membro_de(ministerio_id)));


--
-- Name: ministerio_paginas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ministerio_paginas ENABLE ROW LEVEL SECURITY;

--
-- Name: ministerio_paginas ministerio_paginas_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ministerio_paginas_leitura ON public.ministerio_paginas FOR SELECT TO authenticated USING ((public.e_master() OR public.lider_de(ministerio_id)));


--
-- Name: ministerios; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ministerios ENABLE ROW LEVEL SECURITY;

--
-- Name: ministerios ministerios_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ministerios_leitura ON public.ministerios FOR SELECT TO anon, authenticated USING ((ativo OR public.e_master()));


--
-- Name: notificacoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notificacoes ENABLE ROW LEVEL SECURITY;

--
-- Name: organograma_nos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.organograma_nos ENABLE ROW LEVEL SECURITY;

--
-- Name: organograma_nos organograma_nos_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY organograma_nos_leitura ON public.organograma_nos FOR SELECT TO authenticated USING (public.perfil_ativo());


--
-- Name: organogramas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.organogramas ENABLE ROW LEVEL SECURITY;

--
-- Name: organogramas organogramas_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY organogramas_leitura ON public.organogramas FOR SELECT TO authenticated USING (public.perfil_ativo());


--
-- Name: pagamentos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pagamentos ENABLE ROW LEVEL SECURITY;

--
-- Name: perfis; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.perfis ENABLE ROW LEVEL SECURITY;

--
-- Name: perfis perfis_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY perfis_leitura ON public.perfis FOR SELECT TO authenticated USING (((id = auth.uid()) OR public.e_master()));


--
-- Name: pessoas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pessoas ENABLE ROW LEVEL SECURITY;

--
-- Name: pessoas pessoas_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pessoas_leitura ON public.pessoas FOR SELECT TO authenticated USING (((id = public.minha_pessoa_id()) OR public.e_master() OR public.tem_atribuicao('SECRETARIA'::text) OR (EXISTS ( SELECT 1
   FROM public.ministerio_membros mm
  WHERE ((mm.pessoa_id = pessoas.id) AND mm.ativo AND public.lider_de(mm.ministerio_id))))));


--
-- Name: reembolsos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.reembolsos ENABLE ROW LEVEL SECURITY;

--
-- Name: reservas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.reservas ENABLE ROW LEVEL SECURITY;

--
-- Name: solicitacoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.solicitacoes ENABLE ROW LEVEL SECURITY;

--
-- Name: solicitacoes solicitacoes_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY solicitacoes_leitura ON public.solicitacoes FOR SELECT TO authenticated USING (public.e_master());


--
-- Name: termos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.termos ENABLE ROW LEVEL SECURITY;

--
-- Name: turma_responsaveis; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.turma_responsaveis ENABLE ROW LEVEL SECURITY;

--
-- Name: turmas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.turmas ENABLE ROW LEVEL SECURITY;

--
-- Name: turmas turmas_leitura; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY turmas_leitura ON public.turmas FOR SELECT TO anon, authenticated USING ((public.cursos_gestor() OR ((status <> 'rascunho'::text) AND (EXISTS ( SELECT 1
   FROM public.cursos c
  WHERE ((c.id = turmas.curso_id) AND c.publicado))))));


--
-- Name: voluntariado_candidaturas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.voluntariado_candidaturas ENABLE ROW LEVEL SECURITY;

--
-- Name: voluntariado_indicacoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.voluntariado_indicacoes ENABLE ROW LEVEL SECURITY;

--
-- Name: voluntario_capacitacoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.voluntario_capacitacoes ENABLE ROW LEVEL SECURITY;

--
-- Name: voluntario_disponibilidade; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.voluntario_disponibilidade ENABLE ROW LEVEL SECURITY;

--
-- Name: voluntario_habilitacoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.voluntario_habilitacoes ENABLE ROW LEVEL SECURITY;

--
-- Name: voluntario_indisponibilidades; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.voluntario_indisponibilidades ENABLE ROW LEVEL SECURITY;

--
-- Name: voluntario_preferencias; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.voluntario_preferencias ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA auth; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA auth TO anon;
GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT USAGE ON SCHEMA auth TO service_role;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION jwt(); Type: ACL; Schema: auth; Owner: -
--

GRANT ALL ON FUNCTION auth.jwt() TO anon;
GRANT ALL ON FUNCTION auth.jwt() TO authenticated;
GRANT ALL ON FUNCTION auth.jwt() TO service_role;


--
-- Name: FUNCTION role(); Type: ACL; Schema: auth; Owner: -
--

GRANT ALL ON FUNCTION auth.role() TO anon;
GRANT ALL ON FUNCTION auth.role() TO authenticated;
GRANT ALL ON FUNCTION auth.role() TO service_role;


--
-- Name: FUNCTION uid(); Type: ACL; Schema: auth; Owner: -
--

GRANT ALL ON FUNCTION auth.uid() TO anon;
GRANT ALL ON FUNCTION auth.uid() TO authenticated;
GRANT ALL ON FUNCTION auth.uid() TO service_role;


--
-- Name: FUNCTION admin_atualizar_usuario(p_usuario uuid, p_perfil text, p_atribuicoes text[], p_ministerios jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_atualizar_usuario(p_usuario uuid, p_perfil text, p_atribuicoes text[], p_ministerios jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_atualizar_usuario(p_usuario uuid, p_perfil text, p_atribuicoes text[], p_ministerios jsonb) TO service_role;
GRANT ALL ON FUNCTION public.admin_atualizar_usuario(p_usuario uuid, p_perfil text, p_atribuicoes text[], p_ministerios jsonb) TO authenticated;


--
-- Name: FUNCTION admin_remover_foto(p_usuario uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_remover_foto(p_usuario uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_remover_foto(p_usuario uuid) TO service_role;
GRANT ALL ON FUNCTION public.admin_remover_foto(p_usuario uuid) TO authenticated;


--
-- Name: FUNCTION admin_salvar_ministerio(p_id uuid, p_nome text, p_descricao text, p_ordem integer, p_ativo boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_salvar_ministerio(p_id uuid, p_nome text, p_descricao text, p_ordem integer, p_ativo boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_salvar_ministerio(p_id uuid, p_nome text, p_descricao text, p_ordem integer, p_ativo boolean) TO service_role;
GRANT ALL ON FUNCTION public.admin_salvar_ministerio(p_id uuid, p_nome text, p_descricao text, p_ordem integer, p_ativo boolean) TO authenticated;


--
-- Name: FUNCTION agenda_conflitos(p_data text, p_espacos text[], p_ini integer, p_fim integer, p_ignorar_evento text, p_ignorar_reserva text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_conflitos(p_data text, p_espacos text[], p_ini integer, p_fim integer, p_ignorar_evento text, p_ignorar_reserva text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_conflitos(p_data text, p_espacos text[], p_ini integer, p_fim integer, p_ignorar_evento text, p_ignorar_reserva text) TO service_role;


--
-- Name: FUNCTION agenda_coordenador(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_coordenador() FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_coordenador() TO service_role;
GRANT ALL ON FUNCTION public.agenda_coordenador() TO anon;
GRANT ALL ON FUNCTION public.agenda_coordenador() TO authenticated;


--
-- Name: FUNCTION agenda_definir_coordenador(p_usuario uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_definir_coordenador(p_usuario uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_definir_coordenador(p_usuario uuid) TO service_role;
GRANT ALL ON FUNCTION public.agenda_definir_coordenador(p_usuario uuid) TO authenticated;


--
-- Name: FUNCTION agenda_envio_decidir(p_envio uuid, p_decisao text, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_envio_decidir(p_envio uuid, p_decisao text, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_envio_decidir(p_envio uuid, p_decisao text, p_motivo text) TO service_role;
GRANT ALL ON FUNCTION public.agenda_envio_decidir(p_envio uuid, p_decisao text, p_motivo text) TO authenticated;


--
-- Name: FUNCTION agenda_envios_listar(p_status text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_envios_listar(p_status text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_envios_listar(p_status text) TO service_role;
GRANT ALL ON FUNCTION public.agenda_envios_listar(p_status text) TO authenticated;


--
-- Name: FUNCTION agenda_espacos(p text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_espacos(p text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_espacos(p text) TO service_role;


--
-- Name: FUNCTION agenda_evento_periodo(p_evento bigint, OUT inicio timestamp with time zone, OUT fim timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_evento_periodo(p_evento bigint, OUT inicio timestamp with time zone, OUT fim timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_evento_periodo(p_evento bigint, OUT inicio timestamp with time zone, OUT fim timestamp with time zone) TO service_role;


--
-- Name: FUNCTION agenda_faixa_evento(p_ini text, p_fim text, p_horario text, OUT inicio integer, OUT fim integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_faixa_evento(p_ini text, p_fim text, p_horario text, OUT inicio integer, OUT fim integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_faixa_evento(p_ini text, p_fim text, p_horario text, OUT inicio integer, OUT fim integer) TO service_role;


--
-- Name: FUNCTION agenda_link_abrir(p_token text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_link_abrir(p_token text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_link_abrir(p_token text) TO service_role;
GRANT ALL ON FUNCTION public.agenda_link_abrir(p_token text) TO anon;
GRANT ALL ON FUNCTION public.agenda_link_abrir(p_token text) TO authenticated;


--
-- Name: FUNCTION agenda_link_criar(p_rotulo text, p_ministerio uuid, p_titulo text, p_dias integer, p_permite_complemento boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_link_criar(p_rotulo text, p_ministerio uuid, p_titulo text, p_dias integer, p_permite_complemento boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_link_criar(p_rotulo text, p_ministerio uuid, p_titulo text, p_dias integer, p_permite_complemento boolean) TO service_role;
GRANT ALL ON FUNCTION public.agenda_link_criar(p_rotulo text, p_ministerio uuid, p_titulo text, p_dias integer, p_permite_complemento boolean) TO authenticated;


--
-- Name: FUNCTION agenda_link_enviar(p_token text, p_dados jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_link_enviar(p_token text, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_link_enviar(p_token text, p_dados jsonb) TO service_role;
GRANT ALL ON FUNCTION public.agenda_link_enviar(p_token text, p_dados jsonb) TO anon;
GRANT ALL ON FUNCTION public.agenda_link_enviar(p_token text, p_dados jsonb) TO authenticated;


--
-- Name: FUNCTION agenda_link_novo_token(p_link uuid, p_dias integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_link_novo_token(p_link uuid, p_dias integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_link_novo_token(p_link uuid, p_dias integer) TO service_role;
GRANT ALL ON FUNCTION public.agenda_link_novo_token(p_link uuid, p_dias integer) TO authenticated;


--
-- Name: FUNCTION agenda_link_revogar(p_link uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_link_revogar(p_link uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_link_revogar(p_link uuid) TO service_role;
GRANT ALL ON FUNCTION public.agenda_link_revogar(p_link uuid) TO authenticated;


--
-- Name: TABLE agenda_links; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.agenda_links TO anon;
GRANT ALL ON TABLE public.agenda_links TO authenticated;
GRANT ALL ON TABLE public.agenda_links TO service_role;


--
-- Name: FUNCTION agenda_link_valido(p_token text, OUT link public.agenda_links, OUT motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_link_valido(p_token text, OUT link public.agenda_links, OUT motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_link_valido(p_token text, OUT link public.agenda_links, OUT motivo text) TO service_role;


--
-- Name: FUNCTION agenda_links_listar(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_links_listar() FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_links_listar() TO service_role;
GRANT ALL ON FUNCTION public.agenda_links_listar() TO authenticated;


--
-- Name: FUNCTION agenda_listar_coordenadores(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_listar_coordenadores() FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_listar_coordenadores() TO service_role;
GRANT ALL ON FUNCTION public.agenda_listar_coordenadores() TO authenticated;


--
-- Name: FUNCTION agenda_minhas_permissoes(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_minhas_permissoes() FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_minhas_permissoes() TO service_role;
GRANT ALL ON FUNCTION public.agenda_minhas_permissoes() TO authenticated;


--
-- Name: FUNCTION agenda_ministerio_por_nome(p_nome text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_ministerio_por_nome(p_nome text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_ministerio_por_nome(p_nome text) TO service_role;


--
-- Name: FUNCTION agenda_minutos(p text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_minutos(p text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_minutos(p text) TO service_role;


--
-- Name: FUNCTION agenda_novo_token(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_novo_token() FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_novo_token() TO service_role;


--
-- Name: FUNCTION agenda_pode_editar_ficha(p_ministerio uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_pode_editar_ficha(p_ministerio uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_pode_editar_ficha(p_ministerio uuid) TO service_role;
GRANT ALL ON FUNCTION public.agenda_pode_editar_ficha(p_ministerio uuid) TO anon;
GRANT ALL ON FUNCTION public.agenda_pode_editar_ficha(p_ministerio uuid) TO authenticated;


--
-- Name: FUNCTION agenda_status_coordenador(p_coordenador text, p_ativo boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_status_coordenador(p_coordenador text, p_ativo boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_status_coordenador(p_coordenador text, p_ativo boolean) TO service_role;
GRANT ALL ON FUNCTION public.agenda_status_coordenador(p_coordenador text, p_ativo boolean) TO authenticated;


--
-- Name: FUNCTION agenda_token_hash(p_token text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_token_hash(p_token text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_token_hash(p_token text) TO service_role;


--
-- Name: FUNCTION agenda_validar_ficha(p jsonb, p_ministerio_fixo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_validar_ficha(p jsonb, p_ministerio_fixo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_validar_ficha(p jsonb, p_ministerio_fixo text) TO service_role;


--
-- Name: FUNCTION agenda_vincular_coordenador(p_coordenador text, p_usuario uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.agenda_vincular_coordenador(p_coordenador text, p_usuario uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_vincular_coordenador(p_coordenador text, p_usuario uuid) TO service_role;
GRANT ALL ON FUNCTION public.agenda_vincular_coordenador(p_coordenador text, p_usuario uuid) TO authenticated;


--
-- Name: FUNCTION apoio_cancelar(p_solicitacao uuid, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.apoio_cancelar(p_solicitacao uuid, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.apoio_cancelar(p_solicitacao uuid, p_motivo text) TO service_role;
GRANT ALL ON FUNCTION public.apoio_cancelar(p_solicitacao uuid, p_motivo text) TO authenticated;


--
-- Name: FUNCTION apoio_mensagem(p_solicitacao uuid, p_tipo text, p_texto text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.apoio_mensagem(p_solicitacao uuid, p_tipo text, p_texto text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.apoio_mensagem(p_solicitacao uuid, p_tipo text, p_texto text) TO service_role;
GRANT ALL ON FUNCTION public.apoio_mensagem(p_solicitacao uuid, p_tipo text, p_texto text) TO authenticated;


--
-- Name: FUNCTION apoio_minhas_solicitacoes(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.apoio_minhas_solicitacoes() FROM PUBLIC;
GRANT ALL ON FUNCTION public.apoio_minhas_solicitacoes() TO service_role;
GRANT ALL ON FUNCTION public.apoio_minhas_solicitacoes() TO authenticated;


--
-- Name: FUNCTION apoio_servicos_listar(p_ministerio uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.apoio_servicos_listar(p_ministerio uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.apoio_servicos_listar(p_ministerio uuid) TO service_role;
GRANT ALL ON FUNCTION public.apoio_servicos_listar(p_ministerio uuid) TO authenticated;


--
-- Name: FUNCTION apoio_solicitacao_json(p_id uuid, p_interno boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.apoio_solicitacao_json(p_id uuid, p_interno boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.apoio_solicitacao_json(p_id uuid, p_interno boolean) TO service_role;


--
-- Name: FUNCTION apoio_solicitar(p jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.apoio_solicitar(p jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.apoio_solicitar(p jsonb) TO service_role;
GRANT ALL ON FUNCTION public.apoio_solicitar(p jsonb) TO authenticated;


--
-- Name: FUNCTION arquivo_autorizado(p_tipo text, p_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.arquivo_autorizado(p_tipo text, p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.arquivo_autorizado(p_tipo text, p_id uuid) TO service_role;
GRANT ALL ON FUNCTION public.arquivo_autorizado(p_tipo text, p_id uuid) TO authenticated;


--
-- Name: FUNCTION ator_atual(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ator_atual() FROM PUBLIC;
GRANT ALL ON FUNCTION public.ator_atual() TO service_role;


--
-- Name: FUNCTION autorizar_imagem_link(p_protocolo text, p_chave text, p_termo uuid, p_decisao text, p_escopo jsonb, p_responsavel jsonb, p_data_nascimento date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.autorizar_imagem_link(p_protocolo text, p_chave text, p_termo uuid, p_decisao text, p_escopo jsonb, p_responsavel jsonb, p_data_nascimento date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.autorizar_imagem_link(p_protocolo text, p_chave text, p_termo uuid, p_decisao text, p_escopo jsonb, p_responsavel jsonb, p_data_nascimento date) TO service_role;
GRANT ALL ON FUNCTION public.autorizar_imagem_link(p_protocolo text, p_chave text, p_termo uuid, p_decisao text, p_escopo jsonb, p_responsavel jsonb, p_data_nascimento date) TO anon;
GRANT ALL ON FUNCTION public.autorizar_imagem_link(p_protocolo text, p_chave text, p_termo uuid, p_decisao text, p_escopo jsonb, p_responsavel jsonb, p_data_nascimento date) TO authenticated;


--
-- Name: FUNCTION cancelar_minha_inscricao_curso(p_protocolo text, p_chave text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cancelar_minha_inscricao_curso(p_protocolo text, p_chave text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cancelar_minha_inscricao_curso(p_protocolo text, p_chave text) TO service_role;
GRANT ALL ON FUNCTION public.cancelar_minha_inscricao_curso(p_protocolo text, p_chave text) TO anon;
GRANT ALL ON FUNCTION public.cancelar_minha_inscricao_curso(p_protocolo text, p_chave text) TO authenticated;


--
-- Name: FUNCTION candidatura_json(p_cand uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.candidatura_json(p_cand uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.candidatura_json(p_cand uuid) TO service_role;


--
-- Name: FUNCTION certificado_impressao_json(p_cert uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.certificado_impressao_json(p_cert uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.certificado_impressao_json(p_cert uuid) TO service_role;


--
-- Name: FUNCTION certificado_validador(p_turma uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.certificado_validador(p_turma uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.certificado_validador(p_turma uuid) TO service_role;


--
-- Name: FUNCTION certificado_validador_uid(p_turma uuid, p_uid uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.certificado_validador_uid(p_turma uuid, p_uid uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.certificado_validador_uid(p_turma uuid, p_uid uuid) TO service_role;


--
-- Name: FUNCTION colegio_etapa_salvar(p_id uuid, p_dados jsonb, p_validado boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.colegio_etapa_salvar(p_id uuid, p_dados jsonb, p_validado boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.colegio_etapa_salvar(p_id uuid, p_dados jsonb, p_validado boolean) TO service_role;
GRANT ALL ON FUNCTION public.colegio_etapa_salvar(p_id uuid, p_dados jsonb, p_validado boolean) TO authenticated;


--
-- Name: FUNCTION colegio_etapas_admin(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.colegio_etapas_admin() FROM PUBLIC;
GRANT ALL ON FUNCTION public.colegio_etapas_admin() TO service_role;
GRANT ALL ON FUNCTION public.colegio_etapas_admin() TO authenticated;


--
-- Name: TABLE consentimentos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.consentimentos TO service_role;


--
-- Name: FUNCTION consentimento_atual(p_pessoa uuid, p_tipo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.consentimento_atual(p_pessoa uuid, p_tipo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.consentimento_atual(p_pessoa uuid, p_tipo text) TO service_role;


--
-- Name: FUNCTION consentimentos_json(p_pessoa uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.consentimentos_json(p_pessoa uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.consentimentos_json(p_pessoa uuid) TO service_role;


--
-- Name: FUNCTION curso_concluido(p_pessoa uuid, p_curso uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.curso_concluido(p_pessoa uuid, p_curso uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.curso_concluido(p_pessoa uuid, p_curso uuid) TO service_role;


--
-- Name: FUNCTION curso_id_por_slug(p_slug text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.curso_id_por_slug(p_slug text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.curso_id_por_slug(p_slug text) TO service_role;


--
-- Name: FUNCTION curso_publico(p_slug text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.curso_publico(p_slug text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.curso_publico(p_slug text) TO service_role;
GRANT ALL ON FUNCTION public.curso_publico(p_slug text) TO anon;
GRANT ALL ON FUNCTION public.curso_publico(p_slug text) TO authenticated;


--
-- Name: FUNCTION cursos_admin_listar(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cursos_admin_listar() FROM PUBLIC;
GRANT ALL ON FUNCTION public.cursos_admin_listar() TO service_role;
GRANT ALL ON FUNCTION public.cursos_admin_listar() TO authenticated;


--
-- Name: FUNCTION cursos_alterar_inscricao(p_inscricao uuid, p_acao text, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cursos_alterar_inscricao(p_inscricao uuid, p_acao text, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cursos_alterar_inscricao(p_inscricao uuid, p_acao text, p_motivo text) TO service_role;
GRANT ALL ON FUNCTION public.cursos_alterar_inscricao(p_inscricao uuid, p_acao text, p_motivo text) TO authenticated;


--
-- Name: FUNCTION cursos_atualizar_participante(p_pessoa uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cursos_atualizar_participante(p_pessoa uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cursos_atualizar_participante(p_pessoa uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date) TO service_role;
GRANT ALL ON FUNCTION public.cursos_atualizar_participante(p_pessoa uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date) TO authenticated;


--
-- Name: FUNCTION cursos_definir_responsaveis(p_turma uuid, p_perfis uuid[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cursos_definir_responsaveis(p_turma uuid, p_perfis uuid[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cursos_definir_responsaveis(p_turma uuid, p_perfis uuid[]) TO service_role;
GRANT ALL ON FUNCTION public.cursos_definir_responsaveis(p_turma uuid, p_perfis uuid[]) TO authenticated;


--
-- Name: FUNCTION cursos_gestor(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cursos_gestor() FROM PUBLIC;
GRANT ALL ON FUNCTION public.cursos_gestor() TO service_role;
GRANT ALL ON FUNCTION public.cursos_gestor() TO anon;
GRANT ALL ON FUNCTION public.cursos_gestor() TO authenticated;


--
-- Name: FUNCTION cursos_historico_participante(p_pessoa uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cursos_historico_participante(p_pessoa uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cursos_historico_participante(p_pessoa uuid) TO service_role;
GRANT ALL ON FUNCTION public.cursos_historico_participante(p_pessoa uuid) TO authenticated;


--
-- Name: TABLE cursos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.cursos TO service_role;
GRANT SELECT ON TABLE public.cursos TO anon;
GRANT SELECT ON TABLE public.cursos TO authenticated;


--
-- Name: FUNCTION cursos_json_curso(c public.cursos, p_turmas_publicas boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cursos_json_curso(c public.cursos, p_turmas_publicas boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cursos_json_curso(c public.cursos, p_turmas_publicas boolean) TO service_role;


--
-- Name: TABLE turmas; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.turmas TO service_role;
GRANT SELECT ON TABLE public.turmas TO anon;
GRANT SELECT ON TABLE public.turmas TO authenticated;


--
-- Name: FUNCTION cursos_json_turma(t public.turmas); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cursos_json_turma(t public.turmas) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cursos_json_turma(t public.turmas) TO service_role;


--
-- Name: FUNCTION cursos_listar_inscricoes(p_turma uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cursos_listar_inscricoes(p_turma uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cursos_listar_inscricoes(p_turma uuid) TO service_role;
GRANT ALL ON FUNCTION public.cursos_listar_inscricoes(p_turma uuid) TO authenticated;


--
-- Name: FUNCTION cursos_participantes(p_busca text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cursos_participantes(p_busca text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cursos_participantes(p_busca text) TO service_role;
GRANT ALL ON FUNCTION public.cursos_participantes(p_busca text) TO authenticated;


--
-- Name: FUNCTION cursos_promover_fila(p_turma uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cursos_promover_fila(p_turma uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cursos_promover_fila(p_turma uuid) TO service_role;


--
-- Name: FUNCTION cursos_publicos(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cursos_publicos() FROM PUBLIC;
GRANT ALL ON FUNCTION public.cursos_publicos() TO service_role;
GRANT ALL ON FUNCTION public.cursos_publicos() TO anon;
GRANT ALL ON FUNCTION public.cursos_publicos() TO authenticated;


--
-- Name: FUNCTION cursos_responsaveis_turma(p_turma uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cursos_responsaveis_turma(p_turma uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cursos_responsaveis_turma(p_turma uuid) TO service_role;
GRANT ALL ON FUNCTION public.cursos_responsaveis_turma(p_turma uuid) TO authenticated;


--
-- Name: FUNCTION cursos_salvar_categoria(p_id uuid, p_nome text, p_descricao text, p_ordem integer, p_ativo boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cursos_salvar_categoria(p_id uuid, p_nome text, p_descricao text, p_ordem integer, p_ativo boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cursos_salvar_categoria(p_id uuid, p_nome text, p_descricao text, p_ordem integer, p_ativo boolean) TO service_role;
GRANT ALL ON FUNCTION public.cursos_salvar_categoria(p_id uuid, p_nome text, p_descricao text, p_ordem integer, p_ativo boolean) TO authenticated;


--
-- Name: FUNCTION cursos_salvar_curso(p jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cursos_salvar_curso(p jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cursos_salvar_curso(p jsonb) TO service_role;
GRANT ALL ON FUNCTION public.cursos_salvar_curso(p jsonb) TO authenticated;


--
-- Name: FUNCTION cursos_salvar_turma(p jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cursos_salvar_turma(p jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cursos_salvar_turma(p jsonb) TO service_role;
GRANT ALL ON FUNCTION public.cursos_salvar_turma(p jsonb) TO authenticated;


--
-- Name: FUNCTION cursos_vagas_turma(p_turma uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cursos_vagas_turma(p_turma uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cursos_vagas_turma(p_turma uuid) TO service_role;


--
-- Name: FUNCTION cursos_validadores_disponiveis(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cursos_validadores_disponiveis() FROM PUBLIC;
GRANT ALL ON FUNCTION public.cursos_validadores_disponiveis() TO service_role;
GRANT ALL ON FUNCTION public.cursos_validadores_disponiveis() TO authenticated;


--
-- Name: FUNCTION e_master(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.e_master() FROM PUBLIC;
GRANT ALL ON FUNCTION public.e_master() TO service_role;
GRANT ALL ON FUNCTION public.e_master() TO anon;
GRANT ALL ON FUNCTION public.e_master() TO authenticated;


--
-- Name: FUNCTION e_master_uid(p_uid uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.e_master_uid(p_uid uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.e_master_uid(p_uid uuid) TO service_role;


--
-- Name: FUNCTION e_secretaria(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.e_secretaria() FROM PUBLIC;
GRANT ALL ON FUNCTION public.e_secretaria() TO service_role;
GRANT ALL ON FUNCTION public.e_secretaria() TO authenticated;


--
-- Name: FUNCTION e_tesouraria(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.e_tesouraria() FROM PUBLIC;
GRANT ALL ON FUNCTION public.e_tesouraria() TO service_role;
GRANT ALL ON FUNCTION public.e_tesouraria() TO authenticated;


--
-- Name: FUNCTION escala_adicionar(p_evento_funcao uuid, p_pessoa uuid, p jsonb, p_ciente boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_adicionar(p_evento_funcao uuid, p_pessoa uuid, p jsonb, p_ciente boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_adicionar(p_evento_funcao uuid, p_pessoa uuid, p jsonb, p_ciente boolean) TO service_role;
GRANT ALL ON FUNCTION public.escala_adicionar(p_evento_funcao uuid, p_pessoa uuid, p jsonb, p_ciente boolean) TO authenticated;


--
-- Name: FUNCTION escala_alertas(p_pessoa uuid, p_inicio timestamp with time zone, p_fim timestamp with time zone, p_funcao uuid, p_ignorar uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_alertas(p_pessoa uuid, p_inicio timestamp with time zone, p_fim timestamp with time zone, p_funcao uuid, p_ignorar uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_alertas(p_pessoa uuid, p_inicio timestamp with time zone, p_fim timestamp with time zone, p_funcao uuid, p_ignorar uuid) TO service_role;


--
-- Name: FUNCTION escala_alterar(p_escala uuid, p jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_alterar(p_escala uuid, p jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_alterar(p_escala uuid, p jsonb) TO service_role;
GRANT ALL ON FUNCTION public.escala_alterar(p_escala uuid, p jsonb) TO authenticated;


--
-- Name: FUNCTION escala_alterar_participacao(p_part uuid, p jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_alterar_participacao(p_part uuid, p jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_alterar_participacao(p_part uuid, p jsonb) TO service_role;
GRANT ALL ON FUNCTION public.escala_alterar_participacao(p_part uuid, p jsonb) TO authenticated;


--
-- Name: FUNCTION escala_aplicar_mudanca(p_escala uuid, p jsonb, p_origem text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_aplicar_mudanca(p_escala uuid, p jsonb, p_origem text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_aplicar_mudanca(p_escala uuid, p jsonb, p_origem text) TO service_role;


--
-- Name: FUNCTION escala_avisar(p_part uuid, p_tipo text, p_chave text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_avisar(p_part uuid, p_tipo text, p_chave text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_avisar(p_part uuid, p_tipo text, p_chave text) TO service_role;


--
-- Name: FUNCTION escala_cancelar_interno(p_escala uuid, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_cancelar_interno(p_escala uuid, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_cancelar_interno(p_escala uuid, p_motivo text) TO service_role;


--
-- Name: FUNCTION escala_encerrar(p_escala uuid, p_acao text, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_encerrar(p_escala uuid, p_acao text, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_encerrar(p_escala uuid, p_acao text, p_motivo text) TO service_role;
GRANT ALL ON FUNCTION public.escala_encerrar(p_escala uuid, p_acao text, p_motivo text) TO authenticated;


--
-- Name: FUNCTION escala_funcao(p_escala uuid, p_acao text, p jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_funcao(p_escala uuid, p_acao text, p jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_funcao(p_escala uuid, p_acao text, p jsonb) TO service_role;
GRANT ALL ON FUNCTION public.escala_funcao(p_escala uuid, p_acao text, p jsonb) TO authenticated;


--
-- Name: FUNCTION escala_gestor(p_ministerio uuid, p_area uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_gestor(p_ministerio uuid, p_area uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_gestor(p_ministerio uuid, p_area uuid) TO service_role;
GRANT ALL ON FUNCTION public.escala_gestor(p_ministerio uuid, p_area uuid) TO authenticated;


--
-- Name: FUNCTION escala_historico_listar(p_escala uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_historico_listar(p_escala uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_historico_listar(p_escala uuid) TO service_role;
GRANT ALL ON FUNCTION public.escala_historico_listar(p_escala uuid) TO authenticated;


--
-- Name: FUNCTION escala_incluir_funcao_interno(p_escala uuid, p_funcao uuid, p_qtd integer, p_orient text, p_ini timestamp with time zone, p_fim timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_incluir_funcao_interno(p_escala uuid, p_funcao uuid, p_qtd integer, p_orient text, p_ini timestamp with time zone, p_fim timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_incluir_funcao_interno(p_escala uuid, p_funcao uuid, p_qtd integer, p_orient text, p_ini timestamp with time zone, p_fim timestamp with time zone) TO service_role;


--
-- Name: FUNCTION escala_lider(p_ministerio uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_lider(p_ministerio uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_lider(p_ministerio uuid) TO service_role;
GRANT ALL ON FUNCTION public.escala_lider(p_ministerio uuid) TO authenticated;


--
-- Name: FUNCTION escala_participacao_acao(p_part uuid, p_acao text, p jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_participacao_acao(p_part uuid, p_acao text, p jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_participacao_acao(p_part uuid, p_acao text, p jsonb) TO service_role;
GRANT ALL ON FUNCTION public.escala_participacao_acao(p_part uuid, p_acao text, p jsonb) TO authenticated;


--
-- Name: FUNCTION escala_pedir_reconfirmacao(p_part uuid, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_pedir_reconfirmacao(p_part uuid, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_pedir_reconfirmacao(p_part uuid, p_motivo text) TO service_role;


--
-- Name: TABLE escala_eventos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.escala_eventos TO service_role;


--
-- Name: FUNCTION escala_prazo(e public.escala_eventos); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_prazo(e public.escala_eventos) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_prazo(e public.escala_eventos) TO service_role;


--
-- Name: FUNCTION escala_publicar(p_escala uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_publicar(p_escala uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_publicar(p_escala uuid) TO service_role;
GRANT ALL ON FUNCTION public.escala_publicar(p_escala uuid) TO authenticated;


--
-- Name: FUNCTION escala_responder(p_participacao uuid, p_resposta text, p_versao integer, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_responder(p_participacao uuid, p_resposta text, p_versao integer, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_responder(p_participacao uuid, p_resposta text, p_versao integer, p_motivo text) TO service_role;
GRANT ALL ON FUNCTION public.escala_responder(p_participacao uuid, p_resposta text, p_versao integer, p_motivo text) TO authenticated;


--
-- Name: FUNCTION escala_sugerir(p_evento_funcao uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_sugerir(p_evento_funcao uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_sugerir(p_evento_funcao uuid) TO service_role;
GRANT ALL ON FUNCTION public.escala_sugerir(p_evento_funcao uuid) TO authenticated;


--
-- Name: FUNCTION escala_validar_bloqueios(p_evento_funcao uuid, p_pessoa uuid, p_papel text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escala_validar_bloqueios(p_evento_funcao uuid, p_pessoa uuid, p_papel text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.escala_validar_bloqueios(p_evento_funcao uuid, p_pessoa uuid, p_papel text) TO service_role;


--
-- Name: FUNCTION escalas_processar_prazos(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.escalas_processar_prazos() FROM PUBLIC;
GRANT ALL ON FUNCTION public.escalas_processar_prazos() TO service_role;


--
-- Name: FUNCTION financeiro_inscricao(p_inscricao uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.financeiro_inscricao(p_inscricao uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.financeiro_inscricao(p_inscricao uuid) TO service_role;


--
-- Name: FUNCTION financeiro_minhas_permissoes(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.financeiro_minhas_permissoes() FROM PUBLIC;
GRANT ALL ON FUNCTION public.financeiro_minhas_permissoes() TO service_role;
GRANT ALL ON FUNCTION public.financeiro_minhas_permissoes() TO authenticated;


--
-- Name: FUNCTION financeiro_reavaliar(p_inscricao uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.financeiro_reavaliar(p_inscricao uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.financeiro_reavaliar(p_inscricao uuid) TO service_role;


--
-- Name: FUNCTION foto_url_publica(p_foto text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.foto_url_publica(p_foto text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.foto_url_publica(p_foto text) TO service_role;


--
-- Name: FUNCTION idade_em(p_nascimento date, p_data date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.idade_em(p_nascimento date, p_data date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.idade_em(p_nascimento date, p_data date) TO service_role;


--
-- Name: FUNCTION imagem_consultar(p_busca text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.imagem_consultar(p_busca text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.imagem_consultar(p_busca text) TO service_role;
GRANT ALL ON FUNCTION public.imagem_consultar(p_busca text) TO authenticated;


--
-- Name: FUNCTION imagem_existe(p_espaco text, p_caminho text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.imagem_existe(p_espaco text, p_caminho text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.imagem_existe(p_espaco text, p_caminho text) TO service_role;


--
-- Name: FUNCTION inscrever_curso(p_turma uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date, p_observacao text, p_aceite_privacidade boolean, p_origem text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.inscrever_curso(p_turma uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date, p_observacao text, p_aceite_privacidade boolean, p_origem text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.inscrever_curso(p_turma uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date, p_observacao text, p_aceite_privacidade boolean, p_origem text) TO service_role;


--
-- Name: FUNCTION inscrever_curso_com_termos(p_turma uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date, p_observacao text, p_aceite_privacidade boolean, p_termo_participacao uuid, p_imagem jsonb, p_responsavel jsonb, p_origem text, p_termo_presencial boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.inscrever_curso_com_termos(p_turma uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date, p_observacao text, p_aceite_privacidade boolean, p_termo_participacao uuid, p_imagem jsonb, p_responsavel jsonb, p_origem text, p_termo_presencial boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.inscrever_curso_com_termos(p_turma uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date, p_observacao text, p_aceite_privacidade boolean, p_termo_participacao uuid, p_imagem jsonb, p_responsavel jsonb, p_origem text, p_termo_presencial boolean) TO service_role;
GRANT ALL ON FUNCTION public.inscrever_curso_com_termos(p_turma uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date, p_observacao text, p_aceite_privacidade boolean, p_termo_participacao uuid, p_imagem jsonb, p_responsavel jsonb, p_origem text, p_termo_presencial boolean) TO anon;
GRANT ALL ON FUNCTION public.inscrever_curso_com_termos(p_turma uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date, p_observacao text, p_aceite_privacidade boolean, p_termo_participacao uuid, p_imagem jsonb, p_responsavel jsonb, p_origem text, p_termo_presencial boolean) TO authenticated;


--
-- Name: FUNCTION institucional_permissoes(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.institucional_permissoes() FROM PUBLIC;
GRANT ALL ON FUNCTION public.institucional_permissoes() TO service_role;
GRANT ALL ON FUNCTION public.institucional_permissoes() TO authenticated;


--
-- Name: FUNCTION lider_candidaturas(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.lider_candidaturas() FROM PUBLIC;
GRANT ALL ON FUNCTION public.lider_candidaturas() TO service_role;
GRANT ALL ON FUNCTION public.lider_candidaturas() TO authenticated;


--
-- Name: FUNCTION lider_concluir_validar(p_inscricao uuid, p_observacao text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.lider_concluir_validar(p_inscricao uuid, p_observacao text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.lider_concluir_validar(p_inscricao uuid, p_observacao text) TO service_role;
GRANT ALL ON FUNCTION public.lider_concluir_validar(p_inscricao uuid, p_observacao text) TO authenticated;


--
-- Name: FUNCTION lider_de(p_ministerio uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.lider_de(p_ministerio uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.lider_de(p_ministerio uuid) TO service_role;
GRANT ALL ON FUNCTION public.lider_de(p_ministerio uuid) TO anon;
GRANT ALL ON FUNCTION public.lider_de(p_ministerio uuid) TO authenticated;


--
-- Name: FUNCTION lider_decidir_indicacao(p_indicacao uuid, p_acao text, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.lider_decidir_indicacao(p_indicacao uuid, p_acao text, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.lider_decidir_indicacao(p_indicacao uuid, p_acao text, p_motivo text) TO service_role;
GRANT ALL ON FUNCTION public.lider_decidir_indicacao(p_indicacao uuid, p_acao text, p_motivo text) TO authenticated;


--
-- Name: FUNCTION lider_turmas_validacao(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.lider_turmas_validacao() FROM PUBLIC;
GRANT ALL ON FUNCTION public.lider_turmas_validacao() TO service_role;
GRANT ALL ON FUNCTION public.lider_turmas_validacao() TO authenticated;


--
-- Name: FUNCTION lider_validar_certificado(p_certificado uuid, p_acao text, p_observacao text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.lider_validar_certificado(p_certificado uuid, p_acao text, p_observacao text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.lider_validar_certificado(p_certificado uuid, p_acao text, p_observacao text) TO service_role;
GRANT ALL ON FUNCTION public.lider_validar_certificado(p_certificado uuid, p_acao text, p_observacao text) TO authenticated;


--
-- Name: FUNCTION limite_publico(p_chave text, p_padrao integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.limite_publico(p_chave text, p_padrao integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.limite_publico(p_chave text, p_padrao integer) TO service_role;


--
-- Name: TABLE inscricoes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.inscricoes TO service_role;
GRANT SELECT ON TABLE public.inscricoes TO authenticated;


--
-- Name: FUNCTION link_inscricao(p_protocolo text, p_chave text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.link_inscricao(p_protocolo text, p_chave text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.link_inscricao(p_protocolo text, p_chave text) TO service_role;


--
-- Name: FUNCTION listar_auditoria(p_limite integer, p_antes_de bigint); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.listar_auditoria(p_limite integer, p_antes_de bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION public.listar_auditoria(p_limite integer, p_antes_de bigint) TO service_role;
GRANT ALL ON FUNCTION public.listar_auditoria(p_limite integer, p_antes_de bigint) TO authenticated;


--
-- Name: FUNCTION listar_solicitacoes(p_status text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.listar_solicitacoes(p_status text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.listar_solicitacoes(p_status text) TO service_role;
GRANT ALL ON FUNCTION public.listar_solicitacoes(p_status text) TO authenticated;


--
-- Name: FUNCTION listar_usuarios(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.listar_usuarios() FROM PUBLIC;
GRANT ALL ON FUNCTION public.listar_usuarios() TO service_role;
GRANT ALL ON FUNCTION public.listar_usuarios() TO authenticated;


--
-- Name: FUNCTION marcar_notificacoes_lidas(p_ids bigint[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.marcar_notificacoes_lidas(p_ids bigint[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.marcar_notificacoes_lidas(p_ids bigint[]) TO service_role;
GRANT ALL ON FUNCTION public.marcar_notificacoes_lidas(p_ids bigint[]) TO authenticated;


--
-- Name: FUNCTION membresia_interesse(p_nome text, p_telefone text, p_email text, p_data_nascimento date, p_mensagem text, p_aceite_privacidade boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.membresia_interesse(p_nome text, p_telefone text, p_email text, p_data_nascimento date, p_mensagem text, p_aceite_privacidade boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.membresia_interesse(p_nome text, p_telefone text, p_email text, p_data_nascimento date, p_mensagem text, p_aceite_privacidade boolean) TO service_role;
GRANT ALL ON FUNCTION public.membresia_interesse(p_nome text, p_telefone text, p_email text, p_data_nascimento date, p_mensagem text, p_aceite_privacidade boolean) TO anon;
GRANT ALL ON FUNCTION public.membresia_interesse(p_nome text, p_telefone text, p_email text, p_data_nascimento date, p_mensagem text, p_aceite_privacidade boolean) TO authenticated;


--
-- Name: FUNCTION membresia_validada(p_pessoa uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.membresia_validada(p_pessoa uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.membresia_validada(p_pessoa uuid) TO service_role;


--
-- Name: FUNCTION membro_de(p_ministerio uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.membro_de(p_ministerio uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.membro_de(p_ministerio uuid) TO service_role;
GRANT ALL ON FUNCTION public.membro_de(p_ministerio uuid) TO anon;
GRANT ALL ON FUNCTION public.membro_de(p_ministerio uuid) TO authenticated;


--
-- Name: FUNCTION meu_painel(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.meu_painel() FROM PUBLIC;
GRANT ALL ON FUNCTION public.meu_painel() TO service_role;
GRANT ALL ON FUNCTION public.meu_painel() TO authenticated;


--
-- Name: FUNCTION meu_perfil(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.meu_perfil() FROM PUBLIC;
GRANT ALL ON FUNCTION public.meu_perfil() TO authenticated;
GRANT ALL ON FUNCTION public.meu_perfil() TO service_role;


--
-- Name: FUNCTION meu_perfil_atualizar(p_telefone text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.meu_perfil_atualizar(p_telefone text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.meu_perfil_atualizar(p_telefone text) TO authenticated;
GRANT ALL ON FUNCTION public.meu_perfil_atualizar(p_telefone text) TO service_role;


--
-- Name: FUNCTION meu_perfil_foto(p_caminho text, p_no_organograma boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.meu_perfil_foto(p_caminho text, p_no_organograma boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.meu_perfil_foto(p_caminho text, p_no_organograma boolean) TO service_role;
GRANT ALL ON FUNCTION public.meu_perfil_foto(p_caminho text, p_no_organograma boolean) TO authenticated;


--
-- Name: FUNCTION meu_perfil_foto_remover(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.meu_perfil_foto_remover() FROM PUBLIC;
GRANT ALL ON FUNCTION public.meu_perfil_foto_remover() TO service_role;
GRANT ALL ON FUNCTION public.meu_perfil_foto_remover() TO authenticated;


--
-- Name: FUNCTION meus_termos(p_protocolo text, p_chave text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.meus_termos(p_protocolo text, p_chave text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.meus_termos(p_protocolo text, p_chave text) TO service_role;
GRANT ALL ON FUNCTION public.meus_termos(p_protocolo text, p_chave text) TO anon;
GRANT ALL ON FUNCTION public.meus_termos(p_protocolo text, p_chave text) TO authenticated;


--
-- Name: FUNCTION midia_agenda_pendentes(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.midia_agenda_pendentes() FROM PUBLIC;
GRANT ALL ON FUNCTION public.midia_agenda_pendentes() TO service_role;
GRANT ALL ON FUNCTION public.midia_agenda_pendentes() TO authenticated;


--
-- Name: FUNCTION midia_catalogo(p_ministerio uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.midia_catalogo(p_ministerio uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.midia_catalogo(p_ministerio uuid) TO service_role;
GRANT ALL ON FUNCTION public.midia_catalogo(p_ministerio uuid) TO authenticated;


--
-- Name: FUNCTION midia_criar_escala(p jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.midia_criar_escala(p jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.midia_criar_escala(p jsonb) TO service_role;
GRANT ALL ON FUNCTION public.midia_criar_escala(p jsonb) TO authenticated;


--
-- Name: FUNCTION midia_decidir_servico(p_solicitacao uuid, p_servico uuid, p_decisao text, p_detalhe text, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.midia_decidir_servico(p_solicitacao uuid, p_servico uuid, p_decisao text, p_detalhe text, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.midia_decidir_servico(p_solicitacao uuid, p_servico uuid, p_decisao text, p_detalhe text, p_motivo text) TO service_role;
GRANT ALL ON FUNCTION public.midia_decidir_servico(p_solicitacao uuid, p_servico uuid, p_decisao text, p_detalhe text, p_motivo text) TO authenticated;


--
-- Name: FUNCTION midia_decidir_solicitacao(p_solicitacao uuid, p_acao text, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.midia_decidir_solicitacao(p_solicitacao uuid, p_acao text, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.midia_decidir_solicitacao(p_solicitacao uuid, p_acao text, p_motivo text) TO service_role;
GRANT ALL ON FUNCTION public.midia_decidir_solicitacao(p_solicitacao uuid, p_acao text, p_motivo text) TO authenticated;


--
-- Name: FUNCTION midia_definir_gestor(p_ministerio uuid, p_perfil uuid, p_areas uuid[], p_ativo boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.midia_definir_gestor(p_ministerio uuid, p_perfil uuid, p_areas uuid[], p_ativo boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.midia_definir_gestor(p_ministerio uuid, p_perfil uuid, p_areas uuid[], p_ativo boolean) TO service_role;
GRANT ALL ON FUNCTION public.midia_definir_gestor(p_ministerio uuid, p_perfil uuid, p_areas uuid[], p_ativo boolean) TO authenticated;


--
-- Name: FUNCTION midia_evento(p_escala uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.midia_evento(p_escala uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.midia_evento(p_escala uuid) TO service_role;
GRANT ALL ON FUNCTION public.midia_evento(p_escala uuid) TO authenticated;


--
-- Name: FUNCTION midia_habilitar(p_pessoa uuid, p_funcao uuid, p_status text, p_observacao text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.midia_habilitar(p_pessoa uuid, p_funcao uuid, p_status text, p_observacao text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.midia_habilitar(p_pessoa uuid, p_funcao uuid, p_status text, p_observacao text) TO service_role;
GRANT ALL ON FUNCTION public.midia_habilitar(p_pessoa uuid, p_funcao uuid, p_status text, p_observacao text) TO authenticated;


--
-- Name: FUNCTION midia_ministerio_id(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.midia_ministerio_id() FROM PUBLIC;
GRANT ALL ON FUNCTION public.midia_ministerio_id() TO service_role;
GRANT ALL ON FUNCTION public.midia_ministerio_id() TO authenticated;


--
-- Name: FUNCTION midia_painel(p_filtros jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.midia_painel(p_filtros jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.midia_painel(p_filtros jsonb) TO service_role;
GRANT ALL ON FUNCTION public.midia_painel(p_filtros jsonb) TO authenticated;


--
-- Name: FUNCTION midia_registrar_capacitacao(p_pessoa uuid, p_funcao uuid, p_titulo text, p_data date, p_carga text, p_observacao text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.midia_registrar_capacitacao(p_pessoa uuid, p_funcao uuid, p_titulo text, p_data date, p_carga text, p_observacao text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.midia_registrar_capacitacao(p_pessoa uuid, p_funcao uuid, p_titulo text, p_data date, p_carga text, p_observacao text) TO service_role;
GRANT ALL ON FUNCTION public.midia_registrar_capacitacao(p_pessoa uuid, p_funcao uuid, p_titulo text, p_data date, p_carga text, p_observacao text) TO authenticated;


--
-- Name: FUNCTION midia_relatorio(p_de date, p_ate date, p_agrupar text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.midia_relatorio(p_de date, p_ate date, p_agrupar text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.midia_relatorio(p_de date, p_ate date, p_agrupar text) TO service_role;
GRANT ALL ON FUNCTION public.midia_relatorio(p_de date, p_ate date, p_agrupar text) TO authenticated;


--
-- Name: FUNCTION midia_salvar_catalogo(p_tipo text, p jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.midia_salvar_catalogo(p_tipo text, p jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.midia_salvar_catalogo(p_tipo text, p jsonb) TO service_role;
GRANT ALL ON FUNCTION public.midia_salvar_catalogo(p_tipo text, p jsonb) TO authenticated;


--
-- Name: FUNCTION midia_solicitacoes(p_filtros jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.midia_solicitacoes(p_filtros jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.midia_solicitacoes(p_filtros jsonb) TO service_role;
GRANT ALL ON FUNCTION public.midia_solicitacoes(p_filtros jsonb) TO authenticated;


--
-- Name: FUNCTION midia_voluntarios(p_ministerio uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.midia_voluntarios(p_ministerio uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.midia_voluntarios(p_ministerio uuid) TO service_role;
GRANT ALL ON FUNCTION public.midia_voluntarios(p_ministerio uuid) TO authenticated;


--
-- Name: FUNCTION minha_candidatura(p_protocolo text, p_chave text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.minha_candidatura(p_protocolo text, p_chave text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.minha_candidatura(p_protocolo text, p_chave text) TO service_role;
GRANT ALL ON FUNCTION public.minha_candidatura(p_protocolo text, p_chave text) TO anon;
GRANT ALL ON FUNCTION public.minha_candidatura(p_protocolo text, p_chave text) TO authenticated;


--
-- Name: FUNCTION minha_disponibilidade(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.minha_disponibilidade() FROM PUBLIC;
GRANT ALL ON FUNCTION public.minha_disponibilidade() TO service_role;
GRANT ALL ON FUNCTION public.minha_disponibilidade() TO authenticated;


--
-- Name: FUNCTION minha_equipe(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.minha_equipe() FROM PUBLIC;
GRANT ALL ON FUNCTION public.minha_equipe() TO service_role;
GRANT ALL ON FUNCTION public.minha_equipe() TO authenticated;


--
-- Name: FUNCTION minha_indisponibilidade(p_acao text, p jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.minha_indisponibilidade(p_acao text, p jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.minha_indisponibilidade(p_acao text, p jsonb) TO service_role;
GRANT ALL ON FUNCTION public.minha_indisponibilidade(p_acao text, p jsonb) TO authenticated;


--
-- Name: FUNCTION minha_inscricao_curso(p_protocolo text, p_chave text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.minha_inscricao_curso(p_protocolo text, p_chave text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.minha_inscricao_curso(p_protocolo text, p_chave text) TO service_role;
GRANT ALL ON FUNCTION public.minha_inscricao_curso(p_protocolo text, p_chave text) TO anon;
GRANT ALL ON FUNCTION public.minha_inscricao_curso(p_protocolo text, p_chave text) TO authenticated;


--
-- Name: FUNCTION minha_pessoa_id(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.minha_pessoa_id() FROM PUBLIC;
GRANT ALL ON FUNCTION public.minha_pessoa_id() TO service_role;
GRANT ALL ON FUNCTION public.minha_pessoa_id() TO anon;
GRANT ALL ON FUNCTION public.minha_pessoa_id() TO authenticated;


--
-- Name: FUNCTION minhas_escalas(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.minhas_escalas() FROM PUBLIC;
GRANT ALL ON FUNCTION public.minhas_escalas() TO service_role;
GRANT ALL ON FUNCTION public.minhas_escalas() TO authenticated;


--
-- Name: FUNCTION minhas_notificacoes(p_limite integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.minhas_notificacoes(p_limite integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.minhas_notificacoes(p_limite integer) TO service_role;
GRANT ALL ON FUNCTION public.minhas_notificacoes(p_limite integer) TO authenticated;


--
-- Name: FUNCTION ministerio_admin_obter(p_ministerio uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ministerio_admin_obter(p_ministerio uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.ministerio_admin_obter(p_ministerio uuid) TO service_role;
GRANT ALL ON FUNCTION public.ministerio_admin_obter(p_ministerio uuid) TO authenticated;


--
-- Name: FUNCTION ministerio_definir_cargo(p_ministerio uuid, p_pessoa uuid, p_cargo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ministerio_definir_cargo(p_ministerio uuid, p_pessoa uuid, p_cargo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.ministerio_definir_cargo(p_ministerio uuid, p_pessoa uuid, p_cargo text) TO service_role;
GRANT ALL ON FUNCTION public.ministerio_definir_cargo(p_ministerio uuid, p_pessoa uuid, p_cargo text) TO authenticated;


--
-- Name: FUNCTION ministerio_definir_lideranca(p_ministerio uuid, p_lideres uuid[], p_vice uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ministerio_definir_lideranca(p_ministerio uuid, p_lideres uuid[], p_vice uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.ministerio_definir_lideranca(p_ministerio uuid, p_lideres uuid[], p_vice uuid) TO service_role;
GRANT ALL ON FUNCTION public.ministerio_definir_lideranca(p_ministerio uuid, p_lideres uuid[], p_vice uuid) TO authenticated;


--
-- Name: FUNCTION ministerio_desvincular(p_ministerio uuid, p_pessoa uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ministerio_desvincular(p_ministerio uuid, p_pessoa uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.ministerio_desvincular(p_ministerio uuid, p_pessoa uuid) TO service_role;
GRANT ALL ON FUNCTION public.ministerio_desvincular(p_ministerio uuid, p_pessoa uuid) TO authenticated;


--
-- Name: TABLE ministerio_paginas; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ministerio_paginas TO anon;
GRANT ALL ON TABLE public.ministerio_paginas TO authenticated;
GRANT ALL ON TABLE public.ministerio_paginas TO service_role;


--
-- Name: TABLE ministerios; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ministerios TO service_role;
GRANT SELECT ON TABLE public.ministerios TO anon;
GRANT SELECT ON TABLE public.ministerios TO authenticated;


--
-- Name: FUNCTION ministerio_pagina_publica_json(p_m public.ministerios, p_pg public.ministerio_paginas); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ministerio_pagina_publica_json(p_m public.ministerios, p_pg public.ministerio_paginas) FROM PUBLIC;
GRANT ALL ON FUNCTION public.ministerio_pagina_publica_json(p_m public.ministerios, p_pg public.ministerio_paginas) TO service_role;


--
-- Name: FUNCTION ministerio_salvar_pagina(p_ministerio uuid, p_dados jsonb, p_publicar boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ministerio_salvar_pagina(p_ministerio uuid, p_dados jsonb, p_publicar boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.ministerio_salvar_pagina(p_ministerio uuid, p_dados jsonb, p_publicar boolean) TO service_role;
GRANT ALL ON FUNCTION public.ministerio_salvar_pagina(p_ministerio uuid, p_dados jsonb, p_publicar boolean) TO authenticated;


--
-- Name: FUNCTION ministerio_vincular(p_ministerio uuid, p_pessoa uuid, p_cargo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ministerio_vincular(p_ministerio uuid, p_pessoa uuid, p_cargo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.ministerio_vincular(p_ministerio uuid, p_pessoa uuid, p_cargo text) TO service_role;
GRANT ALL ON FUNCTION public.ministerio_vincular(p_ministerio uuid, p_pessoa uuid, p_cargo text) TO authenticated;


--
-- Name: FUNCTION ministerios_publicos(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ministerios_publicos() FROM PUBLIC;
GRANT ALL ON FUNCTION public.ministerios_publicos() TO service_role;
GRANT ALL ON FUNCTION public.ministerios_publicos() TO anon;
GRANT ALL ON FUNCTION public.ministerios_publicos() TO authenticated;


--
-- Name: FUNCTION notificar(p_atribuicao text, p_usuario uuid, p_tipo text, p_titulo text, p_msg text, p_ref jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notificar(p_atribuicao text, p_usuario uuid, p_tipo text, p_titulo text, p_msg text, p_ref jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.notificar(p_atribuicao text, p_usuario uuid, p_tipo text, p_titulo text, p_msg text, p_ref jsonb) TO service_role;


--
-- Name: FUNCTION notificar_gestao(p_ministerio uuid, p_chave text, p_tipo text, p_titulo text, p_msg text, p_ref jsonb, p_area uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notificar_gestao(p_ministerio uuid, p_chave text, p_tipo text, p_titulo text, p_msg text, p_ref jsonb, p_area uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.notificar_gestao(p_ministerio uuid, p_chave text, p_tipo text, p_titulo text, p_msg text, p_ref jsonb, p_area uuid) TO service_role;


--
-- Name: FUNCTION notificar_unico(p_chave text, p_usuario uuid, p_tipo text, p_titulo text, p_msg text, p_ref jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notificar_unico(p_chave text, p_usuario uuid, p_tipo text, p_titulo text, p_msg text, p_ref jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.notificar_unico(p_chave text, p_usuario uuid, p_tipo text, p_titulo text, p_msg text, p_ref jsonb) TO service_role;


--
-- Name: FUNCTION organograma_atualizar(p_org uuid, p_titulo text, p_descricao text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.organograma_atualizar(p_org uuid, p_titulo text, p_descricao text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.organograma_atualizar(p_org uuid, p_titulo text, p_descricao text) TO service_role;
GRANT ALL ON FUNCTION public.organograma_atualizar(p_org uuid, p_titulo text, p_descricao text) TO authenticated;


--
-- Name: FUNCTION organograma_no_mover(p_org uuid, p_no uuid, p_direcao integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.organograma_no_mover(p_org uuid, p_no uuid, p_direcao integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.organograma_no_mover(p_org uuid, p_no uuid, p_direcao integer) TO service_role;
GRANT ALL ON FUNCTION public.organograma_no_mover(p_org uuid, p_no uuid, p_direcao integer) TO authenticated;


--
-- Name: FUNCTION organograma_no_remover(p_org uuid, p_no uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.organograma_no_remover(p_org uuid, p_no uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.organograma_no_remover(p_org uuid, p_no uuid) TO service_role;
GRANT ALL ON FUNCTION public.organograma_no_remover(p_org uuid, p_no uuid) TO authenticated;


--
-- Name: FUNCTION organograma_no_salvar(p_org uuid, p_dados jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.organograma_no_salvar(p_org uuid, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.organograma_no_salvar(p_org uuid, p_dados jsonb) TO service_role;
GRANT ALL ON FUNCTION public.organograma_no_salvar(p_org uuid, p_dados jsonb) TO authenticated;


--
-- Name: FUNCTION organograma_obter(p_org uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.organograma_obter(p_org uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.organograma_obter(p_org uuid) TO service_role;
GRANT ALL ON FUNCTION public.organograma_obter(p_org uuid) TO authenticated;


--
-- Name: FUNCTION organogramas_listar(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.organogramas_listar() FROM PUBLIC;
GRANT ALL ON FUNCTION public.organogramas_listar() TO service_role;
GRANT ALL ON FUNCTION public.organogramas_listar() TO authenticated;


--
-- Name: TABLE escala_participacoes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.escala_participacoes TO service_role;


--
-- Name: FUNCTION participacao_periodo(p public.escala_participacoes, OUT inicio timestamp with time zone, OUT fim timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.participacao_periodo(p public.escala_participacoes, OUT inicio timestamp with time zone, OUT fim timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.participacao_periodo(p public.escala_participacoes, OUT inicio timestamp with time zone, OUT fim timestamp with time zone) TO service_role;


--
-- Name: FUNCTION perfil_ativo(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.perfil_ativo() FROM PUBLIC;
GRANT ALL ON FUNCTION public.perfil_ativo() TO service_role;
GRANT ALL ON FUNCTION public.perfil_ativo() TO anon;
GRANT ALL ON FUNCTION public.perfil_ativo() TO authenticated;


--
-- Name: FUNCTION pessoa_cartao(p_pessoa uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pessoa_cartao(p_pessoa uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pessoa_cartao(p_pessoa uuid) TO service_role;


--
-- Name: FUNCTION pessoas_para_vinculo(p_busca text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pessoas_para_vinculo(p_busca text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pessoas_para_vinculo(p_busca text) TO service_role;
GRANT ALL ON FUNCTION public.pessoas_para_vinculo(p_busca text) TO authenticated;


--
-- Name: FUNCTION pode_editar_organograma(p_org uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pode_editar_organograma(p_org uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pode_editar_organograma(p_org uuid) TO service_role;


--
-- Name: FUNCTION pode_enviar_foto_perfil(p_caminho text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pode_enviar_foto_perfil(p_caminho text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pode_enviar_foto_perfil(p_caminho text) TO service_role;
GRANT ALL ON FUNCTION public.pode_enviar_foto_perfil(p_caminho text) TO authenticated;


--
-- Name: FUNCTION pode_enviar_imagem_site(p_caminho text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pode_enviar_imagem_site(p_caminho text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pode_enviar_imagem_site(p_caminho text) TO service_role;
GRANT ALL ON FUNCTION public.pode_enviar_imagem_site(p_caminho text) TO authenticated;


--
-- Name: FUNCTION pode_solicitar_apoio(p_ministerio uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pode_solicitar_apoio(p_ministerio uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pode_solicitar_apoio(p_ministerio uuid) TO service_role;
GRANT ALL ON FUNCTION public.pode_solicitar_apoio(p_ministerio uuid) TO authenticated;


--
-- Name: FUNCTION recusar_solicitacao(p_solicitacao uuid, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.recusar_solicitacao(p_solicitacao uuid, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.recusar_solicitacao(p_solicitacao uuid, p_motivo text) TO service_role;
GRANT ALL ON FUNCTION public.recusar_solicitacao(p_solicitacao uuid, p_motivo text) TO authenticated;


--
-- Name: FUNCTION registrar_consentimento(p_pessoa uuid, p_tipo text, p_termo uuid, p_decisao text, p_escopo jsonb, p_responsavel jsonb, p_origem text, p_contexto_tipo text, p_contexto_id uuid, p_documento uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.registrar_consentimento(p_pessoa uuid, p_tipo text, p_termo uuid, p_decisao text, p_escopo jsonb, p_responsavel jsonb, p_origem text, p_contexto_tipo text, p_contexto_id uuid, p_documento uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.registrar_consentimento(p_pessoa uuid, p_tipo text, p_termo uuid, p_decisao text, p_escopo jsonb, p_responsavel jsonb, p_origem text, p_contexto_tipo text, p_contexto_id uuid, p_documento uuid) TO service_role;


--
-- Name: FUNCTION responsavel_valido(p jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.responsavel_valido(p jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.responsavel_valido(p jsonb) TO service_role;


--
-- Name: FUNCTION revogar_consentimento_link(p_protocolo text, p_chave text, p_consentimento uuid, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.revogar_consentimento_link(p_protocolo text, p_chave text, p_consentimento uuid, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.revogar_consentimento_link(p_protocolo text, p_chave text, p_consentimento uuid, p_motivo text) TO service_role;
GRANT ALL ON FUNCTION public.revogar_consentimento_link(p_protocolo text, p_chave text, p_consentimento uuid, p_motivo text) TO anon;
GRANT ALL ON FUNCTION public.revogar_consentimento_link(p_protocolo text, p_chave text, p_consentimento uuid, p_motivo text) TO authenticated;


--
-- Name: FUNCTION salvar_minha_disponibilidade(p jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.salvar_minha_disponibilidade(p jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.salvar_minha_disponibilidade(p jsonb) TO service_role;
GRANT ALL ON FUNCTION public.salvar_minha_disponibilidade(p jsonb) TO authenticated;


--
-- Name: FUNCTION secretaria_abrir_candidatura(p_pessoa uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_abrir_candidatura(p_pessoa uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_abrir_candidatura(p_pessoa uuid) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_abrir_candidatura(p_pessoa uuid) TO authenticated;


--
-- Name: FUNCTION secretaria_abrir_processo(p_pessoa uuid, p_observacao text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_abrir_processo(p_pessoa uuid, p_observacao text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_abrir_processo(p_pessoa uuid, p_observacao text) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_abrir_processo(p_pessoa uuid, p_observacao text) TO authenticated;


--
-- Name: FUNCTION secretaria_arquivar_documento(p_documento uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_arquivar_documento(p_documento uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_arquivar_documento(p_documento uuid) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_arquivar_documento(p_documento uuid) TO authenticated;


--
-- Name: FUNCTION secretaria_cancelar_candidatura(p_candidatura uuid, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_cancelar_candidatura(p_candidatura uuid, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_cancelar_candidatura(p_candidatura uuid, p_motivo text) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_cancelar_candidatura(p_candidatura uuid, p_motivo text) TO authenticated;


--
-- Name: FUNCTION secretaria_cancelar_conclusao_anterior(p_id uuid, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_cancelar_conclusao_anterior(p_id uuid, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_cancelar_conclusao_anterior(p_id uuid, p_motivo text) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_cancelar_conclusao_anterior(p_id uuid, p_motivo text) TO authenticated;


--
-- Name: FUNCTION secretaria_cancelar_pagamento(p_pagamento uuid, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_cancelar_pagamento(p_pagamento uuid, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_cancelar_pagamento(p_pagamento uuid, p_motivo text) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_cancelar_pagamento(p_pagamento uuid, p_motivo text) TO authenticated;


--
-- Name: FUNCTION secretaria_candidaturas(p_status text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_candidaturas(p_status text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_candidaturas(p_status text) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_candidaturas(p_status text) TO authenticated;


--
-- Name: FUNCTION secretaria_cerimonia_realizada(p_cerimonia uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_cerimonia_realizada(p_cerimonia uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_cerimonia_realizada(p_cerimonia uuid) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_cerimonia_realizada(p_cerimonia uuid) TO authenticated;


--
-- Name: FUNCTION secretaria_certificado(p_certificado uuid, p_acao text, p_dados jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_certificado(p_certificado uuid, p_acao text, p_dados jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_certificado(p_certificado uuid, p_acao text, p_dados jsonb) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_certificado(p_certificado uuid, p_acao text, p_dados jsonb) TO authenticated;


--
-- Name: FUNCTION secretaria_certificado_historico(p_certificado uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_certificado_historico(p_certificado uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_certificado_historico(p_certificado uuid) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_certificado_historico(p_certificado uuid) TO authenticated;


--
-- Name: FUNCTION secretaria_certificados(p_filtros jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_certificados(p_filtros jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_certificados(p_filtros jsonb) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_certificados(p_filtros jsonb) TO authenticated;


--
-- Name: FUNCTION secretaria_documentos(p_pessoa uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_documentos(p_pessoa uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_documentos(p_pessoa uuid) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_documentos(p_pessoa uuid) TO authenticated;


--
-- Name: FUNCTION secretaria_encerrar_processo(p_processo uuid, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_encerrar_processo(p_processo uuid, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_encerrar_processo(p_processo uuid, p_motivo text) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_encerrar_processo(p_processo uuid, p_motivo text) TO authenticated;


--
-- Name: FUNCTION secretaria_ficha_pessoa(p_pessoa uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_ficha_pessoa(p_pessoa uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_ficha_pessoa(p_pessoa uuid) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_ficha_pessoa(p_pessoa uuid) TO authenticated;


--
-- Name: FUNCTION secretaria_imprimir_cerimonia(p_cerimonia uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_imprimir_cerimonia(p_cerimonia uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_imprimir_cerimonia(p_cerimonia uuid) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_imprimir_cerimonia(p_cerimonia uuid) TO authenticated;


--
-- Name: FUNCTION secretaria_indicar_ministerios(p_candidatura uuid, p_ministerios uuid[], p_termo uuid, p_termo_presencial boolean, p_responsavel jsonb, p_documento uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_indicar_ministerios(p_candidatura uuid, p_ministerios uuid[], p_termo uuid, p_termo_presencial boolean, p_responsavel jsonb, p_documento uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_indicar_ministerios(p_candidatura uuid, p_ministerios uuid[], p_termo uuid, p_termo_presencial boolean, p_responsavel jsonb, p_documento uuid) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_indicar_ministerios(p_candidatura uuid, p_ministerios uuid[], p_termo uuid, p_termo_presencial boolean, p_responsavel jsonb, p_documento uuid) TO authenticated;


--
-- Name: FUNCTION secretaria_inscricoes(p_filtros jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_inscricoes(p_filtros jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_inscricoes(p_filtros jsonb) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_inscricoes(p_filtros jsonb) TO authenticated;


--
-- Name: FUNCTION secretaria_lista_cerimonia(p_cerimonia uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_lista_cerimonia(p_cerimonia uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_lista_cerimonia(p_cerimonia uuid) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_lista_cerimonia(p_cerimonia uuid) TO authenticated;


--
-- Name: FUNCTION secretaria_pessoas(p_busca text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_pessoas(p_busca text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_pessoas(p_busca text) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_pessoas(p_busca text) TO authenticated;


--
-- Name: FUNCTION secretaria_processos_membresia(p_status text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_processos_membresia(p_status text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_processos_membresia(p_status text) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_processos_membresia(p_status text) TO authenticated;


--
-- Name: FUNCTION secretaria_publicar_termo(p_termo uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_publicar_termo(p_termo uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_publicar_termo(p_termo uuid) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_publicar_termo(p_termo uuid) TO authenticated;


--
-- Name: FUNCTION secretaria_registrar_conclusao_anterior(p_pessoa uuid, p_curso uuid, p_concluido_em date, p_comprovacao text, p_documento uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_registrar_conclusao_anterior(p_pessoa uuid, p_curso uuid, p_concluido_em date, p_comprovacao text, p_documento uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_registrar_conclusao_anterior(p_pessoa uuid, p_curso uuid, p_concluido_em date, p_comprovacao text, p_documento uuid) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_registrar_conclusao_anterior(p_pessoa uuid, p_curso uuid, p_concluido_em date, p_comprovacao text, p_documento uuid) TO authenticated;


--
-- Name: FUNCTION secretaria_registrar_consentimento(p_pessoa uuid, p_tipo text, p_termo uuid, p_decisao text, p_escopo jsonb, p_responsavel jsonb, p_documento uuid, p_data_nascimento date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_registrar_consentimento(p_pessoa uuid, p_tipo text, p_termo uuid, p_decisao text, p_escopo jsonb, p_responsavel jsonb, p_documento uuid, p_data_nascimento date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_registrar_consentimento(p_pessoa uuid, p_tipo text, p_termo uuid, p_decisao text, p_escopo jsonb, p_responsavel jsonb, p_documento uuid, p_data_nascimento date) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_registrar_consentimento(p_pessoa uuid, p_tipo text, p_termo uuid, p_decisao text, p_escopo jsonb, p_responsavel jsonb, p_documento uuid, p_data_nascimento date) TO authenticated;


--
-- Name: FUNCTION secretaria_registrar_pagamento_presencial(p_inscricao uuid, p_metodo text, p_valor numeric, p_pago_em date, p_observacao text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_registrar_pagamento_presencial(p_inscricao uuid, p_metodo text, p_valor numeric, p_pago_em date, p_observacao text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_registrar_pagamento_presencial(p_inscricao uuid, p_metodo text, p_valor numeric, p_pago_em date, p_observacao text) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_registrar_pagamento_presencial(p_inscricao uuid, p_metodo text, p_valor numeric, p_pago_em date, p_observacao text) TO authenticated;


--
-- Name: FUNCTION secretaria_revogar_consentimento(p_consentimento uuid, p_via text, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_revogar_consentimento(p_consentimento uuid, p_via text, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_revogar_consentimento(p_consentimento uuid, p_via text, p_motivo text) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_revogar_consentimento(p_consentimento uuid, p_via text, p_motivo text) TO authenticated;


--
-- Name: FUNCTION secretaria_salvar_cerimonia(p jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_salvar_cerimonia(p jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_salvar_cerimonia(p jsonb) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_salvar_cerimonia(p jsonb) TO authenticated;


--
-- Name: FUNCTION secretaria_salvar_modelo_certificado(p jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_salvar_modelo_certificado(p jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_salvar_modelo_certificado(p jsonb) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_salvar_modelo_certificado(p jsonb) TO authenticated;


--
-- Name: FUNCTION secretaria_salvar_termo(p jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_salvar_termo(p jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_salvar_termo(p jsonb) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_salvar_termo(p jsonb) TO authenticated;


--
-- Name: FUNCTION secretaria_solicitar_beneficio(p_inscricao uuid, p_tipo text, p_valor_desconto numeric, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_solicitar_beneficio(p_inscricao uuid, p_tipo text, p_valor_desconto numeric, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_solicitar_beneficio(p_inscricao uuid, p_tipo text, p_valor_desconto numeric, p_motivo text) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_solicitar_beneficio(p_inscricao uuid, p_tipo text, p_valor_desconto numeric, p_motivo text) TO authenticated;


--
-- Name: FUNCTION secretaria_termos(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_termos() FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_termos() TO service_role;
GRANT ALL ON FUNCTION public.secretaria_termos() TO authenticated;


--
-- Name: FUNCTION secretaria_validar_membresia(p_pessoa uuid, p_situacao text, p_membro_desde date, p_observacao text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_validar_membresia(p_pessoa uuid, p_situacao text, p_membro_desde date, p_observacao text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_validar_membresia(p_pessoa uuid, p_situacao text, p_membro_desde date, p_observacao text) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_validar_membresia(p_pessoa uuid, p_situacao text, p_membro_desde date, p_observacao text) TO authenticated;


--
-- Name: FUNCTION secretaria_vincular_cerimonia(p_cerimonia uuid, p_certificados uuid[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.secretaria_vincular_cerimonia(p_cerimonia uuid, p_certificados uuid[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.secretaria_vincular_cerimonia(p_cerimonia uuid, p_certificados uuid[]) TO service_role;
GRANT ALL ON FUNCTION public.secretaria_vincular_cerimonia(p_cerimonia uuid, p_certificados uuid[]) TO authenticated;


--
-- Name: FUNCTION servico_criar_usuario(p_ator uuid, p_usuario uuid, p_nome text, p_telefone text, p_email text, p_perfil text, p_atribuicoes text[], p_ministerios jsonb, p_solicitacao uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.servico_criar_usuario(p_ator uuid, p_usuario uuid, p_nome text, p_telefone text, p_email text, p_perfil text, p_atribuicoes text[], p_ministerios jsonb, p_solicitacao uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.servico_criar_usuario(p_ator uuid, p_usuario uuid, p_nome text, p_telefone text, p_email text, p_perfil text, p_atribuicoes text[], p_ministerios jsonb, p_solicitacao uuid) TO service_role;


--
-- Name: FUNCTION servico_definir_ativo(p_ator uuid, p_usuario uuid, p_ativo boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.servico_definir_ativo(p_ator uuid, p_usuario uuid, p_ativo boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.servico_definir_ativo(p_ator uuid, p_usuario uuid, p_ativo boolean) TO service_role;


--
-- Name: FUNCTION servico_marcar_senha_temporaria(p_ator uuid, p_usuario uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.servico_marcar_senha_temporaria(p_ator uuid, p_usuario uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.servico_marcar_senha_temporaria(p_ator uuid, p_usuario uuid) TO service_role;


--
-- Name: FUNCTION servico_registrar_comprovante(p_ator uuid, p_inscricao uuid, p_pagamento uuid, p_metodo text, p_valor numeric, p_pago_em date, p_path text, p_nome text, p_mime text, p_tamanho integer, p_hash text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.servico_registrar_comprovante(p_ator uuid, p_inscricao uuid, p_pagamento uuid, p_metodo text, p_valor numeric, p_pago_em date, p_path text, p_nome text, p_mime text, p_tamanho integer, p_hash text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.servico_registrar_comprovante(p_ator uuid, p_inscricao uuid, p_pagamento uuid, p_metodo text, p_valor numeric, p_pago_em date, p_path text, p_nome text, p_mime text, p_tamanho integer, p_hash text) TO service_role;


--
-- Name: FUNCTION servico_registrar_documento(p_ator uuid, p_pessoa uuid, p_tipo text, p_descricao text, p_path text, p_nome text, p_mime text, p_tamanho integer, p_hash text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.servico_registrar_documento(p_ator uuid, p_pessoa uuid, p_tipo text, p_descricao text, p_path text, p_nome text, p_mime text, p_tamanho integer, p_hash text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.servico_registrar_documento(p_ator uuid, p_pessoa uuid, p_tipo text, p_descricao text, p_path text, p_nome text, p_mime text, p_tamanho integer, p_hash text) TO service_role;


--
-- Name: FUNCTION servico_validar_link(p_protocolo text, p_chave text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.servico_validar_link(p_protocolo text, p_chave text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.servico_validar_link(p_protocolo text, p_chave text) TO service_role;


--
-- Name: FUNCTION site_apagar_imagem(p_foto text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.site_apagar_imagem(p_foto text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.site_apagar_imagem(p_foto text) TO service_role;


--
-- Name: FUNCTION site_conteudo_publico(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.site_conteudo_publico() FROM PUBLIC;
GRANT ALL ON FUNCTION public.site_conteudo_publico() TO service_role;
GRANT ALL ON FUNCTION public.site_conteudo_publico() TO anon;
GRANT ALL ON FUNCTION public.site_conteudo_publico() TO authenticated;


--
-- Name: FUNCTION site_salvar_contatos(p_contatos jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.site_salvar_contatos(p_contatos jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.site_salvar_contatos(p_contatos jsonb) TO service_role;
GRANT ALL ON FUNCTION public.site_salvar_contatos(p_contatos jsonb) TO authenticated;


--
-- Name: FUNCTION site_salvar_galeria(p_fotos jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.site_salvar_galeria(p_fotos jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.site_salvar_galeria(p_fotos jsonb) TO service_role;
GRANT ALL ON FUNCTION public.site_salvar_galeria(p_fotos jsonb) TO authenticated;


--
-- Name: FUNCTION site_validar_contato(p jsonb, p_campo text, p_tipo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.site_validar_contato(p jsonb, p_campo text, p_tipo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.site_validar_contato(p jsonb, p_campo text, p_tipo text) TO service_role;


--
-- Name: FUNCTION slugify(p text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.slugify(p text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.slugify(p text) TO service_role;


--
-- Name: FUNCTION so_digitos(p text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.so_digitos(p text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.so_digitos(p text) TO service_role;


--
-- Name: FUNCTION solicitar_acesso(p_nome text, p_telefone text, p_email text, p_ministerio uuid, p_funcao text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.solicitar_acesso(p_nome text, p_telefone text, p_email text, p_ministerio uuid, p_funcao text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.solicitar_acesso(p_nome text, p_telefone text, p_email text, p_ministerio uuid, p_funcao text) TO service_role;
GRANT ALL ON FUNCTION public.solicitar_acesso(p_nome text, p_telefone text, p_email text, p_ministerio uuid, p_funcao text) TO anon;
GRANT ALL ON FUNCTION public.solicitar_acesso(p_nome text, p_telefone text, p_email text, p_ministerio uuid, p_funcao text) TO authenticated;


--
-- Name: FUNCTION tem_atribuicao(p_atribuicao text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tem_atribuicao(p_atribuicao text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.tem_atribuicao(p_atribuicao text) TO service_role;
GRANT ALL ON FUNCTION public.tem_atribuicao(p_atribuicao text) TO anon;
GRANT ALL ON FUNCTION public.tem_atribuicao(p_atribuicao text) TO authenticated;


--
-- Name: FUNCTION termos_vigentes(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.termos_vigentes() FROM PUBLIC;
GRANT ALL ON FUNCTION public.termos_vigentes() TO service_role;
GRANT ALL ON FUNCTION public.termos_vigentes() TO anon;
GRANT ALL ON FUNCTION public.termos_vigentes() TO authenticated;


--
-- Name: FUNCTION tesouraria_analisar_beneficio(p_beneficio uuid, p_acao text, p_observacao text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tesouraria_analisar_beneficio(p_beneficio uuid, p_acao text, p_observacao text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.tesouraria_analisar_beneficio(p_beneficio uuid, p_acao text, p_observacao text) TO service_role;
GRANT ALL ON FUNCTION public.tesouraria_analisar_beneficio(p_beneficio uuid, p_acao text, p_observacao text) TO authenticated;


--
-- Name: FUNCTION tesouraria_analisar_pagamento(p_pagamento uuid, p_acao text, p_observacao text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tesouraria_analisar_pagamento(p_pagamento uuid, p_acao text, p_observacao text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.tesouraria_analisar_pagamento(p_pagamento uuid, p_acao text, p_observacao text) TO service_role;
GRANT ALL ON FUNCTION public.tesouraria_analisar_pagamento(p_pagamento uuid, p_acao text, p_observacao text) TO authenticated;


--
-- Name: FUNCTION tesouraria_beneficios(p_status text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tesouraria_beneficios(p_status text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.tesouraria_beneficios(p_status text) TO service_role;
GRANT ALL ON FUNCTION public.tesouraria_beneficios(p_status text) TO authenticated;


--
-- Name: FUNCTION tesouraria_dashboard(p_de date, p_ate date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tesouraria_dashboard(p_de date, p_ate date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.tesouraria_dashboard(p_de date, p_ate date) TO service_role;
GRANT ALL ON FUNCTION public.tesouraria_dashboard(p_de date, p_ate date) TO authenticated;


--
-- Name: FUNCTION tesouraria_movimentos(p_de date, p_ate date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tesouraria_movimentos(p_de date, p_ate date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.tesouraria_movimentos(p_de date, p_ate date) TO service_role;
GRANT ALL ON FUNCTION public.tesouraria_movimentos(p_de date, p_ate date) TO authenticated;


--
-- Name: FUNCTION tesouraria_pagamentos(p_filtros jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tesouraria_pagamentos(p_filtros jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.tesouraria_pagamentos(p_filtros jsonb) TO service_role;
GRANT ALL ON FUNCTION public.tesouraria_pagamentos(p_filtros jsonb) TO authenticated;


--
-- Name: FUNCTION tesouraria_registrar_reembolso(p_pagamento uuid, p_valor numeric, p_metodo text, p_realizado_em date, p_motivo text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tesouraria_registrar_reembolso(p_pagamento uuid, p_valor numeric, p_metodo text, p_realizado_em date, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.tesouraria_registrar_reembolso(p_pagamento uuid, p_valor numeric, p_metodo text, p_realizado_em date, p_motivo text) TO service_role;
GRANT ALL ON FUNCTION public.tesouraria_registrar_reembolso(p_pagamento uuid, p_valor numeric, p_metodo text, p_realizado_em date, p_motivo text) TO authenticated;


--
-- Name: FUNCTION texto_limpo(p text, p_max integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.texto_limpo(p text, p_max integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.texto_limpo(p text, p_max integer) TO service_role;


--
-- Name: FUNCTION tg_agenda_escala(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_agenda_escala() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_agenda_escala() TO service_role;


--
-- Name: FUNCTION tg_agenda_evento(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_agenda_evento() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_agenda_evento() TO service_role;


--
-- Name: FUNCTION tg_agenda_reserva(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_agenda_reserva() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_agenda_reserva() TO service_role;


--
-- Name: FUNCTION tg_atualizado_em(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_atualizado_em() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_atualizado_em() TO service_role;


--
-- Name: FUNCTION tg_auditar(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_auditar() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_auditar() TO service_role;


--
-- Name: FUNCTION tg_auditoria_imutavel(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_auditoria_imutavel() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_auditoria_imutavel() TO service_role;


--
-- Name: FUNCTION tg_certificado_conclusao(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_certificado_conclusao() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_certificado_conclusao() TO service_role;


--
-- Name: FUNCTION tg_certificado_evento(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_certificado_evento() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_certificado_evento() TO service_role;


--
-- Name: FUNCTION tg_consentimento_imutavel(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_consentimento_imutavel() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_consentimento_imutavel() TO service_role;


--
-- Name: FUNCTION tg_escala_historico(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_escala_historico() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_escala_historico() TO service_role;


--
-- Name: FUNCTION tg_eventos_imutaveis(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_eventos_imutaveis() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_eventos_imutaveis() TO service_role;


--
-- Name: FUNCTION tg_garantir_master(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_garantir_master() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_garantir_master() TO service_role;


--
-- Name: FUNCTION tg_historico_imutavel(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_historico_imutavel() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_historico_imutavel() TO service_role;


--
-- Name: FUNCTION tg_inscricao_cancelada_paga(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_inscricao_cancelada_paga() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_inscricao_cancelada_paga() TO service_role;


--
-- Name: FUNCTION tg_inscricao_confirmacao_paga(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_inscricao_confirmacao_paga() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_inscricao_confirmacao_paga() TO service_role;


--
-- Name: FUNCTION tg_inscricao_membresia_voluntariado(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_inscricao_membresia_voluntariado() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_inscricao_membresia_voluntariado() TO service_role;


--
-- Name: FUNCTION tg_inscricao_vagas(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_inscricao_vagas() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_inscricao_vagas() TO service_role;


--
-- Name: FUNCTION tg_limite_publico(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_limite_publico() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_limite_publico() TO service_role;


--
-- Name: FUNCTION tg_ministerio_organograma(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_ministerio_organograma() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_ministerio_organograma() TO service_role;


--
-- Name: FUNCTION tg_nao_excluir(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_nao_excluir() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_nao_excluir() TO service_role;


--
-- Name: FUNCTION tg_participacao_regras(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_participacao_regras() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_participacao_regras() TO service_role;


--
-- Name: FUNCTION tg_senha_alterada(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_senha_alterada() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_senha_alterada() TO service_role;


--
-- Name: FUNCTION tg_termo_imutavel(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_termo_imutavel() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_termo_imutavel() TO service_role;


--
-- Name: FUNCTION tg_voluntario_requisitos(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.tg_voluntario_requisitos() FROM PUBLIC;
GRANT ALL ON FUNCTION public.tg_voluntario_requisitos() TO service_role;


--
-- Name: FUNCTION turma_aberta(t public.turmas); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.turma_aberta(t public.turmas) FROM PUBLIC;
GRANT ALL ON FUNCTION public.turma_aberta(t public.turmas) TO service_role;


--
-- Name: FUNCTION voluntariado_indicar(p_protocolo text, p_chave text, p_ministerios uuid[], p_termo uuid, p_responsavel jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.voluntariado_indicar(p_protocolo text, p_chave text, p_ministerios uuid[], p_termo uuid, p_responsavel jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.voluntariado_indicar(p_protocolo text, p_chave text, p_ministerios uuid[], p_termo uuid, p_responsavel jsonb) TO service_role;
GRANT ALL ON FUNCTION public.voluntariado_indicar(p_protocolo text, p_chave text, p_ministerios uuid[], p_termo uuid, p_responsavel jsonb) TO anon;
GRANT ALL ON FUNCTION public.voluntariado_indicar(p_protocolo text, p_chave text, p_ministerios uuid[], p_termo uuid, p_responsavel jsonb) TO authenticated;


--
-- Name: FUNCTION voluntariado_indicar_interno(p_cand uuid, p_ministerios uuid[], p_termo uuid, p_origem text, p_responsavel jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.voluntariado_indicar_interno(p_cand uuid, p_ministerios uuid[], p_termo uuid, p_origem text, p_responsavel jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.voluntariado_indicar_interno(p_cand uuid, p_ministerios uuid[], p_termo uuid, p_origem text, p_responsavel jsonb) TO service_role;


--
-- Name: FUNCTION voluntariado_requisitos(p_pessoa uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.voluntariado_requisitos(p_pessoa uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.voluntariado_requisitos(p_pessoa uuid) TO service_role;


--
-- Name: TABLE agenda_envios; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.agenda_envios TO anon;
GRANT ALL ON TABLE public.agenda_envios TO authenticated;
GRANT ALL ON TABLE public.agenda_envios TO service_role;


--
-- Name: TABLE agenda_envios_historico; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.agenda_envios_historico TO anon;
GRANT ALL ON TABLE public.agenda_envios_historico TO authenticated;
GRANT ALL ON TABLE public.agenda_envios_historico TO service_role;


--
-- Name: SEQUENCE agenda_envios_historico_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.agenda_envios_historico_id_seq TO anon;
GRANT ALL ON SEQUENCE public.agenda_envios_historico_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.agenda_envios_historico_id_seq TO service_role;


--
-- Name: TABLE agenda_link_acessos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.agenda_link_acessos TO anon;
GRANT ALL ON TABLE public.agenda_link_acessos TO authenticated;
GRANT ALL ON TABLE public.agenda_link_acessos TO service_role;


--
-- Name: SEQUENCE agenda_link_acessos_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.agenda_link_acessos_id_seq TO anon;
GRANT ALL ON SEQUENCE public.agenda_link_acessos_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.agenda_link_acessos_id_seq TO service_role;


--
-- Name: TABLE apoio_servico_funcoes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.apoio_servico_funcoes TO service_role;


--
-- Name: TABLE apoio_servicos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.apoio_servicos TO service_role;


--
-- Name: TABLE apoio_solicitacao_mensagens; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.apoio_solicitacao_mensagens TO service_role;


--
-- Name: TABLE apoio_solicitacao_servicos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.apoio_solicitacao_servicos TO service_role;


--
-- Name: TABLE apoio_solicitacoes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.apoio_solicitacoes TO service_role;


--
-- Name: TABLE auditoria; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.auditoria TO service_role;
GRANT SELECT ON TABLE public.auditoria TO authenticated;


--
-- Name: SEQUENCE auditoria_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.auditoria_id_seq TO anon;
GRANT ALL ON SEQUENCE public.auditoria_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.auditoria_id_seq TO service_role;


--
-- Name: TABLE beneficios; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.beneficios TO service_role;


--
-- Name: TABLE categorias_curso; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.categorias_curso TO service_role;
GRANT SELECT ON TABLE public.categorias_curso TO anon;
GRANT SELECT ON TABLE public.categorias_curso TO authenticated;


--
-- Name: TABLE cerimonias; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.cerimonias TO service_role;


--
-- Name: TABLE certificados; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.certificados TO service_role;


--
-- Name: TABLE certificados_eventos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.certificados_eventos TO service_role;


--
-- Name: SEQUENCE certificados_eventos_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.certificados_eventos_id_seq TO anon;
GRANT ALL ON SEQUENCE public.certificados_eventos_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.certificados_eventos_id_seq TO service_role;


--
-- Name: TABLE colegio_etapas; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.colegio_etapas TO anon;
GRANT ALL ON TABLE public.colegio_etapas TO authenticated;
GRANT ALL ON TABLE public.colegio_etapas TO service_role;


--
-- Name: TABLE comprovantes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.comprovantes TO service_role;


--
-- Name: TABLE configuracoes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.configuracoes TO service_role;
GRANT SELECT ON TABLE public.configuracoes TO anon;
GRANT SELECT ON TABLE public.configuracoes TO authenticated;


--
-- Name: TABLE coordenadores; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.coordenadores TO service_role;


--
-- Name: SEQUENCE coordenadores_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.coordenadores_id_seq TO anon;
GRANT ALL ON SEQUENCE public.coordenadores_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.coordenadores_id_seq TO service_role;


--
-- Name: TABLE cursos_conclusoes_anteriores; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.cursos_conclusoes_anteriores TO service_role;


--
-- Name: TABLE documentos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.documentos TO service_role;


--
-- Name: TABLE escala_areas; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.escala_areas TO service_role;


--
-- Name: TABLE escala_evento_funcoes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.escala_evento_funcoes TO service_role;


--
-- Name: TABLE escala_funcoes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.escala_funcoes TO service_role;


--
-- Name: TABLE escala_gestores; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.escala_gestores TO service_role;


--
-- Name: TABLE escala_historico; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.escala_historico TO service_role;


--
-- Name: SEQUENCE escala_historico_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.escala_historico_id_seq TO anon;
GRANT ALL ON SEQUENCE public.escala_historico_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.escala_historico_id_seq TO service_role;


--
-- Name: TABLE eventos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.eventos TO service_role;
GRANT SELECT ON TABLE public.eventos TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.eventos TO authenticated;


--
-- Name: SEQUENCE eventos_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.eventos_id_seq TO anon;
GRANT ALL ON SEQUENCE public.eventos_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.eventos_id_seq TO service_role;


--
-- Name: SEQUENCE inscricoes_protocolo_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.inscricoes_protocolo_seq TO service_role;


--
-- Name: TABLE membresia_processos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.membresia_processos TO service_role;


--
-- Name: TABLE ministerio_membros; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ministerio_membros TO service_role;
GRANT SELECT ON TABLE public.ministerio_membros TO authenticated;


--
-- Name: TABLE notificacoes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.notificacoes TO service_role;


--
-- Name: SEQUENCE notificacoes_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.notificacoes_id_seq TO anon;
GRANT ALL ON SEQUENCE public.notificacoes_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.notificacoes_id_seq TO service_role;


--
-- Name: TABLE organograma_nos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.organograma_nos TO anon;
GRANT ALL ON TABLE public.organograma_nos TO authenticated;
GRANT ALL ON TABLE public.organograma_nos TO service_role;


--
-- Name: TABLE organogramas; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.organogramas TO anon;
GRANT ALL ON TABLE public.organogramas TO authenticated;
GRANT ALL ON TABLE public.organogramas TO service_role;


--
-- Name: TABLE pagamentos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pagamentos TO service_role;


--
-- Name: TABLE perfis; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.perfis TO service_role;
GRANT SELECT ON TABLE public.perfis TO authenticated;


--
-- Name: TABLE pessoas; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pessoas TO service_role;
GRANT SELECT ON TABLE public.pessoas TO authenticated;


--
-- Name: TABLE reembolsos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.reembolsos TO service_role;


--
-- Name: TABLE reservas; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.reservas TO service_role;
GRANT SELECT ON TABLE public.reservas TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.reservas TO authenticated;


--
-- Name: SEQUENCE reservas_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.reservas_id_seq TO anon;
GRANT ALL ON SEQUENCE public.reservas_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.reservas_id_seq TO service_role;


--
-- Name: TABLE solicitacoes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.solicitacoes TO service_role;
GRANT SELECT ON TABLE public.solicitacoes TO authenticated;


--
-- Name: TABLE termos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.termos TO service_role;


--
-- Name: TABLE turma_responsaveis; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.turma_responsaveis TO service_role;


--
-- Name: TABLE voluntariado_candidaturas; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.voluntariado_candidaturas TO service_role;


--
-- Name: TABLE voluntariado_indicacoes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.voluntariado_indicacoes TO service_role;


--
-- Name: TABLE voluntario_capacitacoes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.voluntario_capacitacoes TO service_role;


--
-- Name: TABLE voluntario_disponibilidade; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.voluntario_disponibilidade TO service_role;


--
-- Name: TABLE voluntario_habilitacoes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.voluntario_habilitacoes TO service_role;


--
-- Name: TABLE voluntario_indisponibilidades; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.voluntario_indisponibilidades TO service_role;


--
-- Name: TABLE voluntario_preferencias; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.voluntario_preferencias TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE betel IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE betel IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE betel IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE betel IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE betel IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE betel IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE betel IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE betel IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE betel IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--


