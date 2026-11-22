-- =====================================================================
-- M09 — Mídia e Audiovisual: solicitações de apoio, escalas por evento,
-- confirmação individual, substituições, presença e histórico.
-- Estrutura por ministério (ativada para a Mídia). Aditiva: tabelas novas,
-- colunas novas e opcionais em notificacoes e gatilhos em eventos.
-- Nada existente é apagado, renomeado ou recriado.
-- =====================================================================
begin;

-- 0. Avisos sem duplicidade (colunas novas, opcionais) ---------------------
alter table public.notificacoes add column chave text, add column categoria text;
create unique index notificacoes_chave_unica on public.notificacoes (chave) where chave is not null;

create function public.notificar_unico(p_chave text, p_usuario uuid, p_tipo text, p_titulo text, p_msg text, p_ref jsonb) returns void
language sql security definer set search_path = '' as $$
  insert into public.notificacoes (para_usuario, tipo, titulo, mensagem, ref, chave, categoria)
  values (p_usuario, p_tipo, p_titulo, p_msg, coalesce(p_ref, '{}'), p_chave, 'escalas')
  on conflict (chave) where chave is not null do nothing
$$;

-- 1. Catálogo, equipe e delegação ---------------------------------------------
create table public.apoio_servicos (
  id            uuid primary key default gen_random_uuid(),
  ministerio_id uuid not null references public.ministerios(id),
  nome          text not null check (char_length(btrim(nome)) between 2 and 80),
  descricao     text check (char_length(descricao) <= 300),
  ativo         boolean not null default true,
  ordem         integer not null default 0,
  criado_em     timestamptz not null default now()
);
create unique index apoio_servicos_nome on public.apoio_servicos (ministerio_id, lower(nome));

create table public.escala_areas (
  id            uuid primary key default gen_random_uuid(),
  ministerio_id uuid not null references public.ministerios(id),
  nome          text not null check (char_length(btrim(nome)) between 2 and 80),
  ativo         boolean not null default true,
  ordem         integer not null default 0
);
create unique index escala_areas_nome on public.escala_areas (ministerio_id, lower(nome));

create table public.escala_funcoes (
  id                    uuid primary key default gen_random_uuid(),
  area_id               uuid not null references public.escala_areas(id),
  nome                  text not null check (char_length(btrim(nome)) between 2 and 80),
  exige_habilitacao     boolean not null default true,
  aceita_em_treinamento boolean not null default true,     -- em treinamento: só como auxiliar
  quantidade_referencia integer check (quantidade_referencia between 1 and 99),  -- referência, nunca limite
  orientacao_padrao     text check (char_length(orientacao_padrao) <= 1000),
  ativo                 boolean not null default true,
  ordem                 integer not null default 0
);
create unique index escala_funcoes_nome on public.escala_funcoes (area_id, lower(nome));

create table public.apoio_servico_funcoes (
  servico_id uuid not null references public.apoio_servicos(id),
  funcao_id  uuid not null references public.escala_funcoes(id),
  primary key (servico_id, funcao_id)
);

create table public.escala_gestores (
  id            uuid primary key default gen_random_uuid(),
  ministerio_id uuid not null references public.ministerios(id),
  perfil_id     uuid not null references public.perfis(id),
  areas         uuid[] not null default '{}',             -- vazio = todas as equipes
  ativo         boolean not null default true,
  criado_por    uuid references auth.users(id),
  criado_em     timestamptz not null default now(),
  unique (ministerio_id, perfil_id)
);

create table public.voluntario_habilitacoes (
  id            uuid primary key default gen_random_uuid(),
  pessoa_id     uuid not null references public.pessoas(id),
  funcao_id     uuid not null references public.escala_funcoes(id),
  status        text not null check (status in ('habilitado','em_treinamento','suspenso')),
  desde         date not null default current_date,
  autorizado_por uuid references auth.users(id),
  observacao    text check (char_length(observacao) <= 600),
  atualizado_em timestamptz not null default now(),
  unique (pessoa_id, funcao_id)
);

create table public.voluntario_capacitacoes (
  id             uuid primary key default gen_random_uuid(),
  pessoa_id      uuid not null references public.pessoas(id),
  funcao_id      uuid references public.escala_funcoes(id),
  titulo         text not null check (char_length(btrim(titulo)) between 3 and 140),
  realizada_em   date not null check (realizada_em <= current_date),
  carga          text check (char_length(carga) <= 40),
  observacao     text check (char_length(observacao) <= 600),
  registrado_por uuid references auth.users(id),
  criado_em      timestamptz not null default now()
);

-- 2. Disponibilidade (preenchida pelo voluntário) ------------------------------
create table public.voluntario_disponibilidade (
  id          uuid primary key default gen_random_uuid(),
  pessoa_id   uuid not null references public.pessoas(id),
  dia_semana  smallint not null check (dia_semana between 0 and 6),   -- 0 = domingo
  hora_inicio time not null,
  hora_fim    time not null,
  check (hora_fim > hora_inicio)
);
create table public.voluntario_indisponibilidades (
  id        uuid primary key default gen_random_uuid(),
  pessoa_id uuid not null references public.pessoas(id),
  inicio    date not null,
  fim       date not null,
  tipo      text not null check (tipo in ('data','ferias','afastamento','temporaria')),
  motivo    text check (char_length(motivo) <= 300),
  criado_em timestamptz not null default now(),
  check (fim >= inicio)
);
create table public.voluntario_preferencias (
  pessoa_id     uuid primary key references public.pessoas(id),
  funcoes       uuid[] not null default '{}',
  observacoes   text check (char_length(observacoes) <= 1000),
  atualizado_em timestamptz not null default now()
);

-- 3. Solicitações dos ministérios -------------------------------------------------
create table public.apoio_solicitacoes (
  id                     uuid primary key default gen_random_uuid(),
  ministerio_alvo        uuid not null references public.ministerios(id),
  ministerio_solicitante uuid not null references public.ministerios(id),
  solicitado_por         uuid not null references auth.users(id),
  responsavel_nome       text not null check (char_length(btrim(responsavel_nome)) between 3 and 120),
  responsavel_contato    text check (char_length(responsavel_contato) <= 120),
  evento_id              bigint references public.eventos(id) on delete set null,
  titulo                 text not null check (char_length(btrim(titulo)) between 3 and 140),
  tipo_evento            text not null check (tipo_evento in ('culto','conferencia','acampamento','reuniao','acao_evangelistica','batismo','treinamento','programacao_especial','outro')),
  inicio                 timestamptz not null,
  fim                    timestamptz not null,
  local                  text not null check (char_length(btrim(local)) between 2 and 200),
  objetivo               text check (char_length(objetivo) <= 600),
  descricao              text check (char_length(descricao) <= 2000),
  informacoes            text check (char_length(informacoes) <= 2000),
  prazo_retorno          date,
  status                 text not null default 'enviada' check (status in ('enviada','em_analise','aguardando_informacoes','aprovada','aprovada_parcial','recusada','cancelada')),
  decidido_por           uuid references auth.users(id),
  decidido_em            timestamptz,
  motivo                 text check (char_length(motivo) <= 600),
  criado_em              timestamptz not null default now(),
  atualizado_em          timestamptz not null default now(),
  check (fim > inicio)
);
create table public.apoio_solicitacao_servicos (
  id             uuid primary key default gen_random_uuid(),
  solicitacao_id uuid not null references public.apoio_solicitacoes(id),
  servico_id     uuid not null references public.apoio_servicos(id),
  detalhe        text check (char_length(detalhe) <= 600),
  origem         text not null default 'solicitado' check (origem in ('solicitado','acrescentado')),
  decisao        text check (decisao in ('atender','nao_atender')),
  motivo         text check (char_length(motivo) <= 600),
  decidido_por   uuid references auth.users(id),
  decidido_em    timestamptz,
  unique (solicitacao_id, servico_id),
  check (decisao is distinct from 'nao_atender' or char_length(btrim(coalesce(motivo, ''))) >= 5)
);
create table public.apoio_solicitacao_mensagens (
  id             uuid primary key default gen_random_uuid(),
  solicitacao_id uuid not null references public.apoio_solicitacoes(id),
  autor          uuid not null references auth.users(id),
  tipo           text not null check (tipo in ('mensagem','pedido_informacao','resposta','nota_interna')),
  texto          text not null check (char_length(btrim(texto)) between 2 and 2000),
  criado_em      timestamptz not null default now()
);

-- 4. Escalas, participações e histórico -----------------------------------------
create table public.escala_eventos (
  id                 uuid primary key default gen_random_uuid(),
  ministerio_id      uuid not null references public.ministerios(id),
  solicitacao_id     uuid references public.apoio_solicitacoes(id),
  evento_id          bigint references public.eventos(id) on delete set null,
  titulo             text not null check (char_length(btrim(titulo)) between 3 and 140),
  inicio             timestamptz not null,
  fim                timestamptz not null,
  local              text not null check (char_length(btrim(local)) between 2 and 200),
  status             text not null default 'planejamento' check (status in ('planejamento','publicada','concluida','cancelada')),
  prazo_confirmacao  timestamptz,
  orientacoes_gerais text check (char_length(orientacoes_gerais) <= 2000),
  versao             integer not null default 1,
  versao_orientacoes integer not null default 1,
  motivo_cancelamento text check (char_length(motivo_cancelamento) <= 600),
  criado_por         uuid references auth.users(id),
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now(),
  check (fim > inicio)
);
create unique index escala_eventos_um_por_evento on public.escala_eventos (evento_id, ministerio_id) where evento_id is not null and status <> 'cancelada';
create unique index escala_eventos_um_por_solicitacao on public.escala_eventos (solicitacao_id) where solicitacao_id is not null and status <> 'cancelada';

create table public.escala_evento_funcoes (
  id                    uuid primary key default gen_random_uuid(),
  escala_evento_id      uuid not null references public.escala_eventos(id),
  funcao_id             uuid not null references public.escala_funcoes(id),
  quantidade_referencia integer check (quantidade_referencia between 1 and 99),
  orientacoes           text check (char_length(orientacoes) <= 2000),
  hora_inicio           timestamptz,
  hora_fim              timestamptz,
  removida_em           timestamptz,
  unique (escala_evento_id, funcao_id),
  check (hora_fim is null or hora_inicio is null or hora_fim > hora_inicio)
);

create table public.escala_participacoes (
  id                     uuid primary key default gen_random_uuid(),
  escala_evento_id       uuid not null references public.escala_eventos(id),
  evento_funcao_id       uuid not null references public.escala_evento_funcoes(id),
  pessoa_id              uuid not null references public.pessoas(id),
  papel                  text not null default 'auxiliar' check (papel in ('principal','auxiliar')),
  atividade              text check (char_length(atividade) <= 300),
  inicio                 timestamptz,
  fim                    timestamptz,
  orientacoes_individuais text check (char_length(orientacoes_individuais) <= 1000),
  observacao_lider       text check (char_length(observacao_lider) <= 1000),
  status                 text not null default 'rascunho' check (status in ('rascunho','aguardando','confirmado','recusado','substituicao_necessaria','substituido','cancelado')),
  versao                 integer not null default 1,
  versao_respondida      integer,
  solicitado_em          timestamptz,
  prazo                  timestamptz,
  respondido_em          timestamptz,
  motivo_recusa          text check (char_length(motivo_recusa) <= 600),
  vaga_aberta            boolean not null default false,          -- recusado/substituição: a vaga ainda precisa de alguém
  substitui_id           uuid references public.escala_participacoes(id),
  motivo_cancelamento    text check (char_length(motivo_cancelamento) <= 600),
  presenca               text check (presenca in ('presente','ausente','parcial')),
  presenca_obs           text check (char_length(presenca_obs) <= 300),
  presenca_por           uuid references auth.users(id),
  presenca_em            timestamptz,
  alertas_cientes        jsonb,
  criado_por             uuid references auth.users(id),
  criado_em              timestamptz not null default now(),
  atualizado_em          timestamptz not null default now(),
  check (fim is null or inicio is null or fim > inicio)
);
-- sem limite de pessoas por função; só impede a mesma pessoa duas vezes ativa na mesma função do evento
create unique index escala_participacao_unica on public.escala_participacoes (evento_funcao_id, pessoa_id)
  where status in ('rascunho','aguardando','confirmado','substituicao_necessaria');
create index escala_participacoes_pessoa on public.escala_participacoes (pessoa_id, status);

create table public.escala_historico (
  id               bigint generated always as identity primary key,
  escala_evento_id uuid not null references public.escala_eventos(id),
  participacao_id  uuid references public.escala_participacoes(id),
  acao             text not null,
  antes            jsonb,
  depois           jsonb,
  ator             uuid references auth.users(id),
  em               timestamptz not null default now()
);
create index escala_historico_evento on public.escala_historico (escala_evento_id, em);

-- 5. Gatilhos de histórico e proteção --------------------------------------------
create function public.tg_historico_imutavel() returns trigger language plpgsql set search_path = '' as $$
begin raise exception 'O histórico de escalas não pode ser alterado nem excluído.'; end $$;
create trigger escala_historico_imutavel before update or delete on public.escala_historico for each row execute function public.tg_historico_imutavel();
create trigger escala_eventos_nao_excluir before delete on public.escala_eventos for each row execute function public.tg_nao_excluir();
create trigger escala_participacoes_nao_excluir before delete on public.escala_participacoes for each row execute function public.tg_nao_excluir();
create trigger apoio_solicitacoes_nao_excluir before delete on public.apoio_solicitacoes for each row execute function public.tg_nao_excluir();
create trigger apoio_mensagens_nao_excluir before delete on public.apoio_solicitacao_mensagens for each row execute function public.tg_nao_excluir();

create function public.tg_escala_historico() returns trigger language plpgsql security definer set search_path = '' as $$
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
create trigger escala_participacoes_historico after insert or update on public.escala_participacoes for each row execute function public.tg_escala_historico();
create trigger escala_eventos_historico after insert or update on public.escala_eventos for each row execute function public.tg_escala_historico();
create trigger escala_funcoes_evento_historico after insert or update on public.escala_evento_funcoes for each row execute function public.tg_escala_historico();
create trigger escala_eventos_atualizado_em before update on public.escala_eventos for each row execute function public.tg_atualizado_em();
create trigger escala_participacoes_atualizado_em before update on public.escala_participacoes for each row execute function public.tg_atualizado_em();
create trigger apoio_solicitacoes_atualizado_em before update on public.apoio_solicitacoes for each row execute function public.tg_atualizado_em();
do $$ declare t text; begin
  foreach t in array array['apoio_servicos','escala_areas','escala_funcoes','escala_gestores','voluntario_habilitacoes','voluntario_capacitacoes',
                           'apoio_solicitacoes','apoio_solicitacao_servicos','apoio_solicitacao_mensagens'] loop
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.tg_auditar()', t || '_auditoria', t);
  end loop;
end $$;

-- 6. Permissões (funções auxiliares) ------------------------------------------------
create function public.midia_ministerio_id() returns uuid
language sql stable security definer set search_path = '' as $$ select id from public.ministerios where slug = 'midia' $$;

-- liderança plena do módulo no ministério (catálogo, habilitações, solicitações)
create function public.escala_lider(p_ministerio uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.perfil_ativo() and (public.e_master() or public.lider_de(p_ministerio))
$$;
-- monta escala: liderança ou gestor delegado (para a equipe indicada, quando houver)
create function public.escala_gestor(p_ministerio uuid, p_area uuid default null) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.escala_lider(p_ministerio) or (public.perfil_ativo() and exists (
    select 1 from public.escala_gestores g where g.ministerio_id = p_ministerio and g.perfil_id = auth.uid() and g.ativo
      and (g.areas = '{}' or p_area is null or p_area = any(g.areas))))
$$;
create function public.pode_solicitar_apoio(p_ministerio uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.perfil_ativo() and (public.lider_de(p_ministerio) or public.e_master() or public.e_secretaria() or public.agenda_coordenador())
$$;

-- avisa toda a gestão do ministério (liderança + gestores delegados), sem duplicar
create function public.notificar_gestao(p_ministerio uuid, p_chave text, p_tipo text, p_titulo text, p_msg text, p_ref jsonb, p_area uuid default null) returns void
language plpgsql security definer set search_path = '' as $$
declare u uuid;
begin
  for u in select distinct pf.id from public.ministerio_membros mm join public.perfis pf on pf.pessoa_id = mm.pessoa_id
            where mm.ministerio_id = p_ministerio and mm.funcao = 'lider' and mm.ativo and pf.ativo
           union select g.perfil_id from public.escala_gestores g join public.perfis pf on pf.id = g.perfil_id
            where g.ministerio_id = p_ministerio and g.ativo and pf.ativo and (g.areas = '{}' or p_area is null or p_area = any(g.areas)) loop
    perform public.notificar_unico(p_chave || ':' || u, u, p_tipo, p_titulo, p_msg, p_ref);
  end loop;
end $$;

-- período de um evento da Agenda (data e horário guardados como texto ou como data/hora)
create function public.agenda_evento_periodo(p_evento bigint, out inicio timestamptz, out fim timestamptz)
language plpgsql stable security definer set search_path = '' as $$
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

-- 7. Regras de escalação --------------------------------------------------------------
-- Bloqueio no banco: voluntário ativo do ministério, com conta ativa e habilitação
create function public.escala_validar_bloqueios(p_evento_funcao uuid, p_pessoa uuid, p_papel text) returns void
language plpgsql stable security definer set search_path = '' as $$
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

create function public.tg_participacao_regras() returns trigger language plpgsql security definer set search_path = '' as $$
declare ef public.escala_evento_funcoes;
begin
  if not (tg_op = 'INSERT' or new.pessoa_id <> old.pessoa_id or new.evento_funcao_id <> old.evento_funcao_id or new.papel <> old.papel) then return new; end if;
  select * into ef from public.escala_evento_funcoes where id = new.evento_funcao_id;
  if ef.escala_evento_id <> new.escala_evento_id then raise exception 'Função de outro evento.' using errcode = '22023'; end if;
  perform public.escala_validar_bloqueios(new.evento_funcao_id, new.pessoa_id, new.papel);
  return new;
end $$;
create trigger escala_participacoes_regras before insert or update on public.escala_participacoes for each row execute function public.tg_participacao_regras();

-- Alertas (o líder decide): choque de horário, indisponibilidade, fora da disponibilidade, em treinamento
create function public.escala_alertas(p_pessoa uuid, p_inicio timestamptz, p_fim timestamptz, p_funcao uuid, p_ignorar uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

-- período efetivo de uma participação
create function public.participacao_periodo(p public.escala_participacoes, out inicio timestamptz, out fim timestamptz)
language sql stable security definer set search_path = '' as $$
  select coalesce(p.inicio, ef.hora_inicio, e.inicio), coalesce(p.fim, ef.hora_fim, e.fim)
    from public.escala_evento_funcoes ef join public.escala_eventos e on e.id = ef.escala_evento_id where ef.id = p.evento_funcao_id
$$;

-- prazo de resposta para um pedido feito agora
create function public.escala_prazo(e public.escala_eventos) returns timestamptz
language sql stable set search_path = '' as $$
  select least(e.inicio, greatest(coalesce(e.prazo_confirmacao, e.inicio - interval '48 hours'), now() + interval '12 hours'))
$$;

-- aviso individual de escala (com tudo que o voluntário precisa saber)
create function public.escala_avisar(p_part uuid, p_tipo text, p_chave text) returns void
language plpgsql security definer set search_path = '' as $$
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

-- 8. Catálogo e equipe (liderança) ------------------------------------------------------
create function public.midia_catalogo(p_ministerio uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.midia_salvar_catalogo(p_tipo text, p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.midia_definir_gestor(p_ministerio uuid, p_perfil uuid, p_areas uuid[], p_ativo boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare m uuid := coalesce(p_ministerio, public.midia_ministerio_id());
begin
  if not public.escala_lider(m) then raise exception 'Somente a liderança do ministério delega a montagem de escalas.' using errcode = '42501'; end if;
  if not exists (select 1 from public.perfis pf join public.ministerio_membros mm on mm.pessoa_id = pf.pessoa_id where pf.id = p_perfil and pf.ativo and mm.ministerio_id = m and mm.ativo) then
    raise exception 'O gestor precisa ser integrante ativo do ministério, com conta.' using errcode = '22023'; end if;
  insert into public.escala_gestores (ministerio_id, perfil_id, areas, ativo, criado_por) values (m, p_perfil, coalesce(p_areas, '{}'), coalesce(p_ativo, true), auth.uid())
  on conflict (ministerio_id, perfil_id) do update set areas = excluded.areas, ativo = excluded.ativo;
  return jsonb_build_object('ok', true);
end $$;

-- equipe: integrantes, conta, habilitações, capacitações, disponibilidade e participação recente
create function public.midia_voluntarios(p_ministerio uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.midia_habilitar(p_pessoa uuid, p_funcao uuid, p_status text, p_observacao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.midia_registrar_capacitacao(p_pessoa uuid, p_funcao uuid, p_titulo text, p_data date, p_carga text, p_observacao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare m uuid := public.midia_ministerio_id();
begin
  if p_funcao is not null then select a.ministerio_id into m from public.escala_funcoes f join public.escala_areas a on a.id = f.area_id where f.id = p_funcao; end if;
  if not public.escala_lider(m) then raise exception 'Somente a liderança do ministério registra capacitações.' using errcode = '42501'; end if;
  insert into public.voluntario_capacitacoes (pessoa_id, funcao_id, titulo, realizada_em, carga, observacao, registrado_por)
  values (p_pessoa, p_funcao, btrim(p_titulo), p_data, nullif(btrim(p_carga), ''), nullif(btrim(p_observacao), ''), auth.uid());
  return jsonb_build_object('ok', true);
end $$;

-- 9. Voluntário: disponibilidade e escalas -------------------------------------------------
create function public.minha_disponibilidade() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.salvar_minha_disponibilidade(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.minha_indisponibilidade(p_acao text, p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.minhas_escalas() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

-- Resposta individual (só a própria pessoa, só a versão atual)
create function public.escala_responder(p_participacao uuid, p_resposta text, p_versao integer, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- 10. Solicitações ------------------------------------------------------------------------
create function public.apoio_servicos_listar(p_ministerio uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.nome, 'descricao', s.descricao) order by s.ordem, s.nome)
    from public.apoio_servicos s where s.ministerio_id = coalesce(p_ministerio, public.midia_ministerio_id()) and s.ativo), '[]'::jsonb);
end $$;

create function public.apoio_solicitar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.apoio_solicitacao_json(p_id uuid, p_interno boolean) returns jsonb
language sql stable security definer set search_path = '' as $$
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

create function public.apoio_minhas_solicitacoes() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'ministerios', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'nome', m.nome) order by m.nome) from public.ministerios m
        where m.ativo and public.pode_solicitar_apoio(m.id) and m.id <> public.midia_ministerio_id()), '[]'::jsonb),
    'solicitacoes', coalesce((select jsonb_agg(public.apoio_solicitacao_json(s.id, false) order by s.inicio desc) from public.apoio_solicitacoes s
        where s.solicitado_por = auth.uid() or public.lider_de(s.ministerio_solicitante)), '[]'::jsonb));
end $$;

create function public.apoio_mensagem(p_solicitacao uuid, p_tipo text, p_texto text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.apoio_cancelar(p_solicitacao uuid, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- Liderança de Mídia: listar, decidir serviços e decidir a solicitação
create function public.midia_solicitacoes(p_filtros jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare m uuid := coalesce(nullif(p_filtros->>'ministerio_id', '')::uuid, public.midia_ministerio_id());
begin
  if not public.escala_gestor(m) then raise exception 'Acesso restrito à liderança de Mídia.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(public.apoio_solicitacao_json(s.id, true) order by s.inicio) from public.apoio_solicitacoes s
    where s.ministerio_alvo = m
      and (p_filtros->>'status' is null or s.status = p_filtros->>'status' or (p_filtros->>'status' = 'abertas' and s.status in ('enviada','em_analise','aguardando_informacoes')))
      and (p_filtros->>'de' is null or s.fim >= (p_filtros->>'de')::date) and (p_filtros->>'ate' is null or s.inicio < (p_filtros->>'ate')::date + 1)
      and (p_filtros->>'solicitante' is null or s.ministerio_solicitante = (p_filtros->>'solicitante')::uuid)), '[]'::jsonb);
end $$;

create function public.midia_decidir_servico(p_solicitacao uuid, p_servico uuid, p_decisao text, p_detalhe text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.midia_decidir_solicitacao(p_solicitacao uuid, p_acao text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- Eventos da Agenda que indicam mídia e ainda não têm solicitação nem escala
create function public.midia_agenda_pendentes() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare m uuid := public.midia_ministerio_id();
begin
  if not public.escala_gestor(m) then raise exception 'Acesso restrito à liderança de Mídia.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'titulo', e.titulo, 'data', e.data::text, 'horario', coalesce(e.horario_inicio::text, e.horario), 'local', e.local, 'ministerio', e.ministerio) order by e.data::text)
    from public.eventos e where coalesce(e.necessita_midia, '') = 'Sim' and e.data::text >= to_char(current_date, 'YYYY-MM-DD')
      and not exists (select 1 from public.apoio_solicitacoes s where s.evento_id = e.id and s.status <> 'cancelada')
      and not exists (select 1 from public.escala_eventos x where x.evento_id = e.id and x.status <> 'cancelada')), '[]'::jsonb);
end $$;

-- 11. Escala: criar, funções, escalar, publicar, alterar, substituir, cancelar -----------------
create function public.midia_criar_escala(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.escala_incluir_funcao_interno(p_escala uuid, p_funcao uuid, p_qtd integer, p_orient text, p_ini timestamptz, p_fim timestamptz) returns uuid
language plpgsql security definer set search_path = '' as $$
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

create function public.escala_funcao(p_escala uuid, p_acao text, p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.escala_pedir_reconfirmacao(p_part uuid, p_motivo text) returns void
language plpgsql security definer set search_path = '' as $$
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

-- Escalar um voluntário (alertas exigem ciência; bloqueios são recusados)
create function public.escala_adicionar(p_evento_funcao uuid, p_pessoa uuid, p jsonb, p_ciente boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.escala_publicar(p_escala uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- Alterar o evento: data, horário e local pedem nova confirmação; orientações só avisam
create function public.escala_aplicar_mudanca(p_escala uuid, p jsonb, p_origem text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.escala_alterar(p_escala uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- Alterar uma participação: função, horário, atividade ou papel pedem nova confirmação
create function public.escala_alterar_participacao(p_part uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- Substituição, vaga, cancelamento (sempre por decisão do líder)
create function public.escala_participacao_acao(p_part uuid, p_acao text, p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.escala_encerrar(p_escala uuid, p_acao text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.escala_cancelar_interno(p_escala uuid, p_motivo text) returns void
language plpgsql security definer set search_path = '' as $$
declare q record;
begin
  update public.escala_eventos set status = 'cancelada', motivo_cancelamento = p_motivo where id = p_escala and status in ('planejamento','publicada');
  for q in select id, status from public.escala_participacoes where escala_evento_id = p_escala and status in ('rascunho','aguardando','confirmado','substituicao_necessaria') loop
    update public.escala_participacoes set status = 'cancelado', vaga_aberta = false, motivo_cancelamento = p_motivo where id = q.id;
    if q.status <> 'rascunho' then perform public.escala_avisar(q.id, 'escala_cancelada', 'canc:' || q.id); end if;
  end loop;
end $$;

-- 12. Consultas da liderança: painel, evento, sugestões, histórico e relatório ------------------
create function public.midia_evento(p_escala uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.escala_sugerir(p_evento_funcao uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.midia_painel(p_filtros jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.escala_historico_listar(p_escala uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

-- Relatório: escalado, confirmou e serviu são contados separadamente
create function public.midia_relatorio(p_de date, p_ate date, p_agrupar text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

-- 13. Prazos e lembretes (tarefa agendada, idempotente) -------------------------------------
create function public.escalas_processar_prazos() returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- 14. Agenda: mudança de data/horário/local chega à escala; exclusão cancela -------------------
create function public.tg_agenda_escala() returns trigger language plpgsql security definer set search_path = '' as $$
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
create trigger eventos_escala_mudanca after update on public.eventos for each row execute function public.tg_agenda_escala();
create trigger eventos_escala_exclusao before delete on public.eventos for each row execute function public.tg_agenda_escala();

-- 15. Dados iniciais (sugestões editáveis pelo líder) ----------------------------------------
do $$
declare m uuid := (select id from public.ministerios where slug = 'midia'); a uuid; s text; f text; i int; j int;
  areas jsonb := '[["Fotografia",["Fotógrafo","Segundo fotógrafo","Auxiliar de fotografia"]],
                   ["Vídeo e audiovisual",["Videomaker","Operador de câmera","Diretor audiovisual","Editor de vídeo"]],
                   ["Redes sociais",["Social Media","Responsável pelos Stories","Responsável por Reels e Trends"]],
                   ["Projeção",["Operador de projeção","Auxiliar de projeção"]],
                   ["Sonoplastia",["Operador de som","Auxiliar de sonoplastia"]],
                   ["Transmissão ao vivo",["Operador de transmissão","Operador de câmera da transmissão","Diretor da Live","Responsável pelo monitoramento da transmissão"]]]';
  servicos text[] := array['Fotografia','Filmagem e videomaker','Captação de vídeos para edição posterior','Transmissão ao vivo (Live)','Operação de câmeras',
    'Projeção de letras, apresentações e conteúdos','Sonoplastia e operação de áudio','Produção de Stories','Reels e Trends','Cobertura para redes sociais','Produção de vídeos institucionais'];
  mapa jsonb := '{"Fotografia":["Fotógrafo"],"Filmagem e videomaker":["Videomaker"],"Captação de vídeos para edição posterior":["Videomaker","Editor de vídeo"],
    "Transmissão ao vivo (Live)":["Operador de transmissão","Operador de câmera da transmissão"],"Operação de câmeras":["Operador de câmera"],
    "Projeção de letras, apresentações e conteúdos":["Operador de projeção"],"Sonoplastia e operação de áudio":["Operador de som"],"Produção de Stories":["Responsável pelos Stories"],
    "Reels e Trends":["Responsável por Reels e Trends"],"Cobertura para redes sociais":["Social Media"],"Produção de vídeos institucionais":["Videomaker","Editor de vídeo"]}';
begin
  if m is null then raise notice 'Ministério de Mídia não encontrado: catálogo não semeado.'; return; end if;
  for i in 0 .. jsonb_array_length(areas) - 1 loop
    insert into public.escala_areas (ministerio_id, nome, ordem) values (m, areas->i->>0, i + 1) returning id into a;
    for j in 0 .. jsonb_array_length(areas->i->1) - 1 loop
      insert into public.escala_funcoes (area_id, nome, ordem) values (a, areas->i->1->>j, j + 1);
    end loop;
  end loop;
  for i in 1 .. array_length(servicos, 1) loop
    insert into public.apoio_servicos (ministerio_id, nome, ordem) values (m, servicos[i], i);
  end loop;
  insert into public.apoio_servico_funcoes (servico_id, funcao_id)
  select sv.id, f.id from public.apoio_servicos sv cross join lateral jsonb_array_elements_text(mapa->sv.nome) fn
    join public.escala_funcoes f on f.nome = fn join public.escala_areas ar on ar.id = f.area_id and ar.ministerio_id = m
   where sv.ministerio_id = m;
end $$;

-- 16. Permissões ---------------------------------------------------------------------------
do $$ declare t text; begin
  foreach t in array array['apoio_servicos','escala_areas','escala_funcoes','apoio_servico_funcoes','escala_gestores','voluntario_habilitacoes','voluntario_capacitacoes',
     'voluntario_disponibilidade','voluntario_indisponibilidades','voluntario_preferencias','apoio_solicitacoes','apoio_solicitacao_servicos','apoio_solicitacao_mensagens',
     'escala_eventos','escala_evento_funcoes','escala_participacoes','escala_historico'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array[
      'notificar_unico','tg_historico_imutavel','tg_escala_historico','midia_ministerio_id','escala_lider','escala_gestor','pode_solicitar_apoio','notificar_gestao',
      'agenda_evento_periodo','escala_validar_bloqueios','tg_participacao_regras','escala_alertas','participacao_periodo','escala_prazo','escala_avisar','midia_catalogo','midia_salvar_catalogo',
      'midia_definir_gestor','midia_voluntarios','midia_habilitar','midia_registrar_capacitacao','minha_disponibilidade','salvar_minha_disponibilidade','minha_indisponibilidade',
      'minhas_escalas','escala_responder','apoio_servicos_listar','apoio_solicitar','apoio_solicitacao_json','apoio_minhas_solicitacoes','apoio_mensagem','apoio_cancelar',
      'midia_solicitacoes','midia_decidir_servico','midia_decidir_solicitacao','midia_agenda_pendentes','midia_criar_escala','escala_incluir_funcao_interno','escala_funcao',
      'escala_pedir_reconfirmacao','escala_adicionar','escala_publicar','escala_aplicar_mudanca','escala_alterar','escala_alterar_participacao','escala_participacao_acao',
      'escala_encerrar','escala_cancelar_interno','midia_evento','escala_sugerir','midia_painel','escala_historico_listar','midia_relatorio','escalas_processar_prazos','tg_agenda_escala'])
  loop execute format('revoke execute on function %s from public, anon, authenticated', f.sig); end loop;
end $$;
grant execute on function public.midia_ministerio_id(), public.escala_gestor(uuid, uuid), public.escala_lider(uuid), public.pode_solicitar_apoio(uuid),
  public.midia_catalogo(uuid), public.midia_salvar_catalogo(text, jsonb), public.midia_definir_gestor(uuid, uuid, uuid[], boolean), public.midia_voluntarios(uuid),
  public.midia_habilitar(uuid, uuid, text, text), public.midia_registrar_capacitacao(uuid, uuid, text, date, text, text), public.minha_disponibilidade(),
  public.salvar_minha_disponibilidade(jsonb), public.minha_indisponibilidade(text, jsonb), public.minhas_escalas(), public.escala_responder(uuid, text, integer, text),
  public.apoio_servicos_listar(uuid), public.apoio_solicitar(jsonb), public.apoio_minhas_solicitacoes(), public.apoio_mensagem(uuid, text, text), public.apoio_cancelar(uuid, text),
  public.midia_solicitacoes(jsonb), public.midia_decidir_servico(uuid, uuid, text, text, text), public.midia_decidir_solicitacao(uuid, text, text), public.midia_agenda_pendentes(),
  public.midia_criar_escala(jsonb), public.escala_funcao(uuid, text, jsonb), public.escala_adicionar(uuid, uuid, jsonb, boolean), public.escala_publicar(uuid),
  public.escala_alterar(uuid, jsonb), public.escala_alterar_participacao(uuid, jsonb), public.escala_participacao_acao(uuid, text, jsonb), public.escala_encerrar(uuid, text, text),
  public.midia_evento(uuid), public.escala_sugerir(uuid), public.midia_painel(jsonb), public.escala_historico_listar(uuid), public.midia_relatorio(date, date, text) to authenticated;

-- 17. Tarefa agendada de prazos (pg_cron, quando a extensão estiver ativa no projeto) -------
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('betel-escalas-prazos', '*/15 * * * *', 'select public.escalas_processar_prazos()');
  else
    raise notice 'pg_cron não está ativo: ative a extensão no Supabase e agende "select public.escalas_processar_prazos()" a cada 15 minutos.';
  end if;
end $$;

commit;
