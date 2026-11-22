-- =====================================================================
-- M08 — Certificados e cerimônias (entrega exclusivamente presencial)
-- Fluxo: conclusão validada pela liderança → emissão autorizada pela
-- Secretaria → vínculo à cerimônia → impressão (só administrativos) →
-- entrega física registrada. Vale para todos os cursos, inclusive online.
-- Nenhum arquivo é oferecido ao participante; nada é enviado por e-mail
-- ou WhatsApp. Aditiva: novas tabelas e colunas; as funções de
-- certificado da M06 são substituídas (o .down as devolve).
-- =====================================================================
begin;

-- Segurança: o fluxo anterior (M06) não chegou a ser usado. Se houver certificado já
-- preparado, impresso ou entregue pelo fluxo antigo, a migração para e pede revisão manual
-- (não inventamos quem validou, autorizou ou recebeu).
do $$ begin
  if exists (select 1 from public.certificados where status not in ('elegivel','cancelado')) then
    raise exception 'Há certificados em andamento no fluxo anterior. Revise-os com a Secretaria antes de aplicar a M08.';
  end if;
end $$;

-- 1. Estrutura ------------------------------------------------------------
-- Quem valida a conclusão de cada turma (além da liderança do ministério do curso)
create table public.turma_responsaveis (
  id          uuid primary key default gen_random_uuid(),
  turma_id    uuid not null references public.turmas(id),
  perfil_id   uuid not null references public.perfis(id),
  papel       text not null default 'coordenador' check (papel in ('coordenador','professor')),
  ativo       boolean not null default true,
  criado_por  uuid references auth.users(id),
  criado_em   timestamptz not null default now(),
  unique (turma_id, perfil_id)
);

-- Histórico imutável de emissão e entrega
create table public.certificados_eventos (
  id             bigint generated always as identity primary key,
  certificado_id uuid not null references public.certificados(id),
  evento         text not null,
  status_antes   text,
  status_depois  text,
  ator           uuid references auth.users(id),
  em             timestamptz not null default now(),
  detalhes       jsonb not null default '{}'::jsonb
);
create index certificados_eventos_cert on public.certificados_eventos (certificado_id, em);

alter table public.certificados
  add column validado_por        uuid references auth.users(id),
  add column validado_em         timestamptz,
  add column observacao_validacao text check (char_length(observacao_validacao) <= 600),
  add column autorizado_por      uuid references auth.users(id),
  add column autorizado_em       timestamptz,
  add column entrega_ocasiao     text check (entrega_ocasiao in ('cerimonia','secretaria')),
  add column recebido_relacao    text check (recebido_relacao in ('participante','responsavel_legal','pessoa_autorizada')),
  add column entrega_observacao  text check (char_length(entrega_observacao) <= 600);

-- novos estados (o antigo "elegivel" passa a "aguardando_validacao": ainda não foi validado pela liderança)
alter table public.certificados drop constraint certificados_status_check;
update public.certificados set status = 'aguardando_validacao' where status = 'elegivel';
alter table public.certificados alter column status set default 'aguardando_validacao';
alter table public.certificados add constraint certificados_status_check check (status in
  ('aguardando_validacao','aguardando_autorizacao','autorizado','preparado','impresso','entregue','cancelado'));
-- coerência no banco: autorização só depois da validação; entregue só com registro da entrega física
alter table public.certificados add constraint certificados_fluxo_check check (
  (status not in ('aguardando_autorizacao','autorizado','preparado','impresso','entregue') or validado_em is not null)
  and (status not in ('autorizado','preparado','impresso','entregue') or autorizado_em is not null)
  and (status not in ('preparado','impresso') or cerimonia_id is not null or status = 'impresso')
  and (status <> 'entregue' or (entregue_em is not null and entregue_por is not null and recebido_por is not null
                                and entrega_ocasiao is not null and recebido_relacao is not null and vezes_impresso > 0))
  and (autorizado_por is null or validado_por is null or autorizado_por <> validado_por));

alter table public.cerimonias
  add column tipo text not null default 'culto' check (tipo in ('culto','apresentacao','outra')),
  add column realizada_em timestamptz,
  add column realizada_por uuid references auth.users(id);

create trigger turma_responsaveis_auditoria after insert or update or delete on public.turma_responsaveis for each row execute function public.tg_auditar();

create function public.tg_eventos_imutaveis() returns trigger language plpgsql set search_path = '' as $$
begin raise exception 'O histórico de certificados não pode ser alterado nem excluído.'; end $$;
create trigger certificados_eventos_imutavel before update or delete on public.certificados_eventos for each row execute function public.tg_eventos_imutaveis();

-- registra cada mudança de certificado no histórico (detalhe opcional vindo da função que agiu)
create function public.tg_certificado_evento() returns trigger language plpgsql security definer set search_path = '' as $$
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
create trigger certificados_eventos_registro after insert or update on public.certificados for each row execute function public.tg_certificado_evento();

-- 2. Quem valida ------------------------------------------------------------
-- Responsáveis designados na turma, liderança do ministério do curso ou MASTER
create function public.certificado_validador(p_turma uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.perfil_ativo() and (
    public.e_master()
    or exists (select 1 from public.turma_responsaveis r where r.turma_id = p_turma and r.ativo and r.perfil_id = auth.uid())
    or exists (select 1 from public.turmas t join public.cursos c on c.id = t.curso_id where t.id = p_turma and c.ministerio_id is not null and public.lider_de(c.ministerio_id)))
$$;
create function public.certificado_validador_uid(p_turma uuid, p_uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_uid is not null and (
    public.e_master_uid(p_uid)
    or exists (select 1 from public.turma_responsaveis r where r.turma_id = p_turma and r.ativo and r.perfil_id = p_uid)
    or exists (select 1 from public.turmas t join public.cursos c on c.id = t.curso_id join public.ministerio_membros mm on mm.ministerio_id = c.ministerio_id
                join public.perfis pf on pf.pessoa_id = mm.pessoa_id where t.id = p_turma and pf.id = p_uid and mm.funcao = 'lider' and mm.ativo and pf.ativo))
$$;

-- 3. Certificado nasce na conclusão (substitui a versão da M06) ---------------
create or replace function public.tg_certificado_conclusao() returns trigger
language plpgsql security definer set search_path = '' as $$
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

-- 4. Liderança: turmas, conclusão e validação -------------------------------
create function public.lider_turmas_validacao() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

-- Concluir e validar ao mesmo tempo (o líder atesta frequência e atividades)
create function public.lider_concluir_validar(p_inscricao uuid, p_observacao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- Validar (ou não) uma conclusão registrada por outra pessoa (ex.: Secretaria)
create function public.lider_validar_certificado(p_certificado uuid, p_acao text, p_observacao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- Responsáveis da turma (definidos pela Secretaria)
create function public.cursos_validadores_disponiveis() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.cursos_gestor() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', pf.id, 'nome', pe.nome, 'perfil', pf.perfil) order by pe.nome)
    from public.perfis pf join public.pessoas pe on pe.id = pf.pessoa_id where pf.ativo and pf.perfil in ('MASTER','LIDER')), '[]'::jsonb);
end $$;
create function public.cursos_responsaveis_turma(p_turma uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.cursos_gestor() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('perfil_id', r.perfil_id, 'nome', pe.nome, 'papel', r.papel) order by pe.nome)
    from public.turma_responsaveis r join public.perfis pf on pf.id = r.perfil_id join public.pessoas pe on pe.id = pf.pessoa_id where r.turma_id = p_turma and r.ativo), '[]'::jsonb);
end $$;
create function public.cursos_definir_responsaveis(p_turma uuid, p_perfis uuid[]) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- 5. Cerimônias ---------------------------------------------------------------
create or replace function public.secretaria_salvar_cerimonia(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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
end $$;

create function public.secretaria_cerimonia_realizada(p_cerimonia uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- 6. Secretaria: autorização, vínculo, impressão e entrega (substitui a M06) --
create function public.certificado_impressao_json(p_cert uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', ce.id, 'codigo', ce.codigo, 'nome', pe.nome, 'curso', c.titulo, 'carga_horaria', c.carga_horaria, 'modalidade', c.modalidade,
         'concluida_em', i.concluida_em, 'turma', t.nome, 'cerimonia', cm.titulo, 'cerimonia_data', cm.data, 'cerimonia_local', cm.local,
         'modelo', coalesce((select valor from public.configuracoes where chave = 'certificado_modelo'), '{}'::jsonb))
    from public.certificados ce join public.inscricoes i on i.id = ce.inscricao_id join public.pessoas pe on pe.id = i.pessoa_id
    join public.turmas t on t.id = i.turma_id join public.cursos c on c.id = t.curso_id left join public.cerimonias cm on cm.id = ce.cerimonia_id where ce.id = p_cert
$$;

create or replace function public.secretaria_certificado(p_certificado uuid, p_acao text, p_dados jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- Vincular vários de uma vez
create function public.secretaria_vincular_cerimonia(p_cerimonia uuid, p_certificados uuid[]) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare x uuid; n int := 0;
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  foreach x in array coalesce(p_certificados, '{}') loop
    perform public.secretaria_certificado(x, 'vincular', jsonb_build_object('cerimonia_id', p_cerimonia)); n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'vinculados', n);
end $$;

-- Impressão em lote: os certificados da cerimônia ainda não impressos
create function public.secretaria_imprimir_cerimonia(p_cerimonia uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- Lista de entrega para a cerimônia (conferência no dia)
create function public.secretaria_lista_cerimonia(p_cerimonia uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  return jsonb_build_object('cerimonia', (select to_jsonb(c) from public.cerimonias c where c.id = p_cerimonia),
    'participantes', coalesce((select jsonb_agg(jsonb_build_object('id', ce.id, 'nome', pe.nome, 'curso', cu.titulo, 'turma', t.nome, 'status', ce.status, 'codigo', ce.codigo,
        'menor', case when pe.data_nascimento is not null then extract(year from age(pe.data_nascimento))::int < 18 end) order by cu.titulo, pe.nome)
      from public.certificados ce join public.inscricoes i on i.id = ce.inscricao_id join public.pessoas pe on pe.id = i.pessoa_id
      join public.turmas t on t.id = i.turma_id join public.cursos cu on cu.id = t.curso_id where ce.cerimonia_id = p_cerimonia and ce.status <> 'cancelado'), '[]'::jsonb));
end $$;

create or replace function public.secretaria_certificados(p_filtros jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.secretaria_certificado_historico(p_certificado uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('evento', e.evento, 'em', e.em, 'status_antes', e.status_antes, 'status_depois', e.status_depois, 'detalhes', e.detalhes,
      'ator', (select x.nome from public.perfis pf join public.pessoas x on x.id = pf.pessoa_id where pf.id = e.ator)) order by e.em, e.id)
    from public.certificados_eventos e where e.certificado_id = p_certificado), '[]'::jsonb);
end $$;

-- Modelo do certificado (texto e assinaturas definidos pela igreja)
create function public.secretaria_salvar_modelo_certificado(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- 7. Permissões -----------------------------------------------------------------
alter table public.turma_responsaveis enable row level security;
alter table public.certificados_eventos enable row level security;
revoke all on public.turma_responsaveis, public.certificados_eventos from anon, authenticated;
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array[
      'tg_eventos_imutaveis','tg_certificado_evento','certificado_validador','certificado_validador_uid','tg_certificado_conclusao','lider_turmas_validacao',
      'lider_concluir_validar','lider_validar_certificado','cursos_validadores_disponiveis','cursos_responsaveis_turma','cursos_definir_responsaveis',
      'secretaria_salvar_cerimonia','secretaria_cerimonia_realizada','certificado_impressao_json','secretaria_certificado','secretaria_vincular_cerimonia',
      'secretaria_imprimir_cerimonia','secretaria_lista_cerimonia','secretaria_certificados','secretaria_certificado_historico','secretaria_salvar_modelo_certificado'])
  loop execute format('revoke execute on function %s from public, anon, authenticated', f.sig); end loop;
end $$;
grant execute on function public.lider_turmas_validacao(), public.lider_concluir_validar(uuid, text), public.lider_validar_certificado(uuid, text, text),
  public.cursos_validadores_disponiveis(), public.cursos_responsaveis_turma(uuid), public.cursos_definir_responsaveis(uuid, uuid[]),
  public.secretaria_salvar_cerimonia(jsonb), public.secretaria_cerimonia_realizada(uuid), public.secretaria_certificado(uuid, text, jsonb),
  public.secretaria_vincular_cerimonia(uuid, uuid[]), public.secretaria_imprimir_cerimonia(uuid), public.secretaria_lista_cerimonia(uuid),
  public.secretaria_certificados(jsonb), public.secretaria_certificado_historico(uuid), public.secretaria_salvar_modelo_certificado(jsonb) to authenticated;

commit;
