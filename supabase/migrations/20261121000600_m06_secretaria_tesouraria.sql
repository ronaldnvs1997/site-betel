-- =====================================================================
-- M06 — Secretaria e Tesouraria
-- Pagamentos, comprovantes (armazenamento privado), bolsas e isenções,
-- reembolsos, documentos, membresia, cerimônias, certificados, notificações.
--
-- REGRA FUNDAMENTAL (garantida no banco):
--  * Inscrição com valor só fica "confirmada" quando a Tesouraria aprova
--    pagamento(s) com comprovante anexado que cubram o valor devido.
--  * Enviar comprovante NÃO confirma a inscrição.
--  * A Secretaria registra pagamento presencial, mas não aprova; e quem
--    registrou um pagamento nunca pode aprová-lo.
-- Só cria estruturas novas; as funções da M05 trocadas aqui são da própria M05.
-- =====================================================================
begin;

-- 1. Permissões --------------------------------------------------------
create function public.e_secretaria() returns boolean
language sql stable security definer set search_path = '' as $$ select public.e_master() or public.tem_atribuicao('SECRETARIA') $$;
create function public.e_tesouraria() returns boolean
language sql stable security definer set search_path = '' as $$ select public.tem_atribuicao('TESOURARIA') $$;
create function public.financeiro_minhas_permissoes() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('secretaria', public.e_secretaria(), 'tesouraria', public.e_tesouraria(), 'usuario', auth.uid()) $$;

-- 2. Tabelas -----------------------------------------------------------
create table public.pagamentos (
  id                 uuid primary key default gen_random_uuid(),
  inscricao_id       uuid not null references public.inscricoes(id),
  metodo             text not null check (metodo in ('pix','transferencia','dinheiro','cartao_presencial','outro')),
  origem             text not null check (origem in ('participante','secretaria')),
  valor              numeric(10,2) not null check (valor > 0),
  pago_em            date,
  status             text not null default 'aguardando_comprovante'
                     check (status in ('aguardando_comprovante','em_analise','aprovado','recusado','novo_comprovante_solicitado','cancelado')),
  observacao         text check (char_length(observacao) <= 600),
  registrado_por     uuid references auth.users(id),          -- vazio: enviado pelo participante
  registrado_em      timestamptz not null default now(),
  analisado_por      uuid references auth.users(id),
  analisado_em       timestamptz,
  observacao_analise text check (char_length(observacao_analise) <= 600),
  atualizado_em      timestamptz not null default now(),
  check (analisado_por is null or registrado_por is null or analisado_por <> registrado_por)
);
create index pagamentos_inscricao on public.pagamentos (inscricao_id);
create index pagamentos_status on public.pagamentos (status, registrado_em);

create table public.comprovantes (
  id            uuid primary key default gen_random_uuid(),
  pagamento_id  uuid not null references public.pagamentos(id),
  arquivo_path  text not null unique,                 -- bucket privado "comprovantes"
  nome_original text check (char_length(nome_original) <= 200),
  tipo_mime     text not null check (tipo_mime in ('application/pdf','image/jpeg','image/png','image/webp')),
  tamanho       integer not null check (tamanho between 1 and 5242880),
  hash_sha256   text not null check (hash_sha256 ~ '^[0-9a-f]{64}$'),
  enviado_por   uuid references auth.users(id),
  enviado_via   text not null check (enviado_via in ('link','painel')),
  enviado_em    timestamptz not null default now(),
  situacao      text not null default 'atual' check (situacao in ('atual','substituido'))
);
create index comprovantes_pagamento on public.comprovantes (pagamento_id);

create table public.beneficios (
  id                 uuid primary key default gen_random_uuid(),
  inscricao_id       uuid not null references public.inscricoes(id),
  tipo               text not null check (tipo in ('bolsa_parcial','bolsa_integral','isencao')),
  valor_desconto     numeric(10,2) check (valor_desconto is null or valor_desconto > 0),
  motivo             text not null check (char_length(btrim(motivo)) between 3 and 600),
  status             text not null default 'solicitado' check (status in ('solicitado','aprovado','recusado','cancelado')),
  solicitado_por     uuid references auth.users(id),
  solicitado_em      timestamptz not null default now(),
  analisado_por      uuid references auth.users(id),
  analisado_em       timestamptz,
  observacao_analise text check (char_length(observacao_analise) <= 600),
  atualizado_em      timestamptz not null default now(),
  check (tipo <> 'bolsa_parcial' or valor_desconto is not null)
);

create table public.reembolsos (
  id             uuid primary key default gen_random_uuid(),
  inscricao_id   uuid not null references public.inscricoes(id),
  pagamento_id   uuid not null references public.pagamentos(id),
  valor          numeric(10,2) not null check (valor > 0),
  metodo         text not null check (metodo in ('pix','transferencia','dinheiro','outro')),
  realizado_em   date not null,
  motivo         text not null check (char_length(btrim(motivo)) between 3 and 600),
  registrado_por uuid not null references auth.users(id),
  registrado_em  timestamptz not null default now()
);

create table public.documentos (
  id            uuid primary key default gen_random_uuid(),
  pessoa_id     uuid not null references public.pessoas(id),
  inscricao_id  uuid references public.inscricoes(id),
  tipo          text not null check (tipo in ('ficha_membresia','carta_transferencia','documento_responsavel','documento_identificacao','outro')),
  descricao     text check (char_length(descricao) <= 300),
  arquivo_path  text not null unique,                 -- bucket privado "documentos"
  nome_original text check (char_length(nome_original) <= 200),
  tipo_mime     text not null check (tipo_mime in ('application/pdf','image/jpeg','image/png','image/webp')),
  tamanho       integer not null check (tamanho between 1 and 5242880),
  hash_sha256   text not null,
  enviado_por   uuid not null references auth.users(id),
  enviado_em    timestamptz not null default now(),
  arquivado_em  timestamptz
);

create table public.cerimonias (
  id            uuid primary key default gen_random_uuid(),
  titulo        text not null check (char_length(btrim(titulo)) between 3 and 140),
  data          date,
  horario       text check (char_length(horario) <= 60),
  local         text check (char_length(local) <= 200),
  evento_ref    text,                                 -- id do evento na Agenda (opcional)
  responsavel   text check (char_length(responsavel) <= 120),
  status        text not null default 'planejada' check (status in ('planejada','realizada','cancelada')),
  observacoes   text check (char_length(observacoes) <= 1000),
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table public.certificados (
  id               uuid primary key default gen_random_uuid(),
  inscricao_id     uuid not null unique references public.inscricoes(id),
  codigo           text not null unique,
  status           text not null default 'elegivel' check (status in ('elegivel','preparado','impresso','entregue','cancelado')),
  cerimonia_id     uuid references public.cerimonias(id),
  preparado_por    uuid references auth.users(id),
  preparado_em     timestamptz,
  impresso_por     uuid references auth.users(id),
  impresso_em      timestamptz,
  vezes_impresso   integer not null default 0,
  entregue_em      timestamptz,
  entregue_por     uuid references auth.users(id),
  recebido_por     text check (char_length(recebido_por) <= 120),
  motivo_cancelamento text check (char_length(motivo_cancelamento) <= 300),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now()
);

create table public.notificacoes (
  id              bigint generated always as identity primary key,
  para_atribuicao text check (para_atribuicao in ('SECRETARIA','TESOURARIA')),
  para_usuario    uuid references auth.users(id),
  tipo            text not null,
  titulo          text not null,
  mensagem        text,
  ref             jsonb not null default '{}',
  criado_em       timestamptz not null default now(),
  lida_por        uuid[] not null default '{}',
  check (para_atribuicao is not null or para_usuario is not null)
);
create index notificacoes_criado on public.notificacoes (criado_em desc);

-- 3. Gatilhos comuns ----------------------------------------------------
do $$ declare t text; begin
  foreach t in array array['pagamentos','beneficios','cerimonias','certificados'] loop
    execute format('create trigger %1$s_atualizado_em before update on public.%1$s for each row execute function public.tg_atualizado_em()', t);
  end loop;
  foreach t in array array['pagamentos','comprovantes','beneficios','reembolsos','documentos','cerimonias','certificados'] loop
    execute format('create trigger %1$s_auditoria after insert or update or delete on public.%1$s for each row execute function public.tg_auditar()', t);
  end loop;
end $$;

-- Histórico financeiro e administrativo não se apaga
create function public.tg_nao_excluir() returns trigger language plpgsql set search_path = '' as $$
begin raise exception 'Registros financeiros e administrativos não podem ser excluídos; use cancelamento.'; end $$;
create trigger pagamentos_nao_excluir before delete on public.pagamentos for each row execute function public.tg_nao_excluir();
create trigger comprovantes_nao_excluir before delete on public.comprovantes for each row execute function public.tg_nao_excluir();
create trigger reembolsos_nao_excluir before delete on public.reembolsos for each row execute function public.tg_nao_excluir();
create trigger beneficios_nao_excluir before delete on public.beneficios for each row execute function public.tg_nao_excluir();
create trigger certificados_nao_excluir before delete on public.certificados for each row execute function public.tg_nao_excluir();

-- 4. Resumo financeiro de uma inscrição ---------------------------------
create function public.financeiro_inscricao(p_inscricao uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
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

-- REGRA FUNDAMENTAL no banco: inscrição com valor só confirma se quitada por pagamento aprovado
create function public.tg_inscricao_confirmacao_paga() returns trigger
language plpgsql security definer set search_path = '' as $$
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
create trigger inscricoes_confirmacao_paga before insert or update of status on public.inscricoes
  for each row execute function public.tg_inscricao_confirmacao_paga();

-- Confirma a inscrição quando o valor devido está coberto (chamada só pela Tesouraria/benefícios)
create function public.financeiro_reavaliar(p_inscricao uuid) returns text
language plpgsql security definer set search_path = '' as $$
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

-- 5. Notificações -------------------------------------------------------
create function public.notificar(p_atribuicao text, p_usuario uuid, p_tipo text, p_titulo text, p_msg text, p_ref jsonb) returns void
language sql security definer set search_path = '' as $$
  insert into public.notificacoes (para_atribuicao, para_usuario, tipo, titulo, mensagem, ref) values (p_atribuicao, p_usuario, p_tipo, p_titulo, p_msg, coalesce(p_ref, '{}'))
$$;
create function public.minhas_notificacoes(p_limite integer default 50) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'nao_lidas', (select count(*) from public.notificacoes n where not (auth.uid() = any(n.lida_por))
                    and (n.para_usuario = auth.uid() or (n.para_atribuicao = 'SECRETARIA' and public.e_secretaria()) or (n.para_atribuicao = 'TESOURARIA' and public.e_tesouraria()))),
    'itens', coalesce((select jsonb_agg(x) from (select jsonb_build_object('id', n.id, 'tipo', n.tipo, 'titulo', n.titulo, 'mensagem', n.mensagem, 'ref', n.ref,
               'para', n.para_atribuicao, 'criado_em', n.criado_em, 'lida', auth.uid() = any(n.lida_por)) as x
             from public.notificacoes n
             where public.perfil_ativo() and (n.para_usuario = auth.uid() or (n.para_atribuicao = 'SECRETARIA' and public.e_secretaria()) or (n.para_atribuicao = 'TESOURARIA' and public.e_tesouraria()))
             order by n.id desc limit least(greatest(coalesce(p_limite, 50), 1), 200)) t), '[]'::jsonb))
$$;
create function public.marcar_notificacoes_lidas(p_ids bigint[]) returns jsonb
language sql security definer set search_path = '' as $$
  update public.notificacoes n set lida_por = array_append(n.lida_por, auth.uid())
   where n.id = any(p_ids) and not (auth.uid() = any(n.lida_por)) and public.perfil_ativo()
     and (n.para_usuario = auth.uid() or (n.para_atribuicao = 'SECRETARIA' and public.e_secretaria()) or (n.para_atribuicao = 'TESOURARIA' and public.e_tesouraria()))
  returning jsonb_build_object('ok', true)
$$;

-- 6. Participante: comprovante pelo link pessoal (chamado pela função de servidor)
create function public.servico_validar_link(p_protocolo text, p_chave text) returns uuid
language sql stable security definer set search_path = '' as $$
  select id from public.inscricoes where protocolo = upper(btrim(p_protocolo))
     and chave_hash = encode(sha256(convert_to(coalesce(p_chave, ''), 'UTF8')), 'hex')
$$;

-- Registra o comprovante (participante ou Secretaria). Nunca confirma a inscrição.
create function public.servico_registrar_comprovante(
  p_ator uuid, p_inscricao uuid, p_pagamento uuid, p_metodo text, p_valor numeric, p_pago_em date,
  p_path text, p_nome text, p_mime text, p_tamanho integer, p_hash text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- Consulta pelo link pessoal: inclui situação financeira e certificado (sem arquivos)
create or replace function public.minha_inscricao_curso(p_protocolo text, p_chave text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

-- 7. Secretaria ------------------------------------------------------------
create function public.secretaria_inscricoes(p_filtros jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.secretaria_pessoas(p_busca text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.secretaria_validar_membresia(p_pessoa uuid, p_situacao text, p_membro_desde date, p_observacao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.e_secretaria() then raise exception 'Somente a Secretaria valida membresia.' using errcode = '42501'; end if;
  if p_situacao not in ('visitante','em_integracao','membro','inativo') then raise exception 'Situação inválida.' using errcode = '22023'; end if;
  if p_situacao = 'membro' and p_membro_desde is null then raise exception 'Informe a data em que a pessoa se tornou membro.' using errcode = '22023'; end if;
  update public.pessoas set situacao_membresia = p_situacao,
         membro_desde = case when p_situacao = 'membro' then p_membro_desde else membro_desde end,
         membresia_validada_por = case when p_situacao = 'membro' then auth.uid() else membresia_validada_por end,
         membresia_validada_em = case when p_situacao = 'membro' then now() else membresia_validada_em end
   where id = p_pessoa;
  if not found then raise exception 'Pessoa não encontrada.' using errcode = 'P0002'; end if;
  insert into public.auditoria (ator, acao, tabela, registro, detalhes)
  values (auth.uid(), 'membresia_validada', 'pessoas', p_pessoa::text, jsonb_build_object('situacao', p_situacao, 'membro_desde', p_membro_desde, 'observacao', nullif(btrim(p_observacao), '')));
  return jsonb_build_object('ok', true);
end $$;

create function public.secretaria_registrar_pagamento_presencial(p_inscricao uuid, p_metodo text, p_valor numeric, p_pago_em date, p_observacao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.secretaria_cancelar_pagamento(p_pagamento uuid, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.secretaria_solicitar_beneficio(p_inscricao uuid, p_tipo text, p_valor_desconto numeric, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- Documentos
create function public.servico_registrar_documento(p_ator uuid, p_pessoa uuid, p_tipo text, p_descricao text, p_path text, p_nome text, p_mime text, p_tamanho integer, p_hash text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  perform set_config('app.ator', p_ator::text, true);
  insert into public.documentos (pessoa_id, tipo, descricao, arquivo_path, nome_original, tipo_mime, tamanho, hash_sha256, enviado_por)
  values (p_pessoa, p_tipo, nullif(btrim(p_descricao), ''), p_path, left(p_nome, 200), p_mime, p_tamanho, p_hash, p_ator) returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
create function public.secretaria_documentos(p_pessoa uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'tipo', d.tipo, 'descricao', d.descricao, 'nome_original', d.nome_original, 'tipo_mime', d.tipo_mime,
      'tamanho', d.tamanho, 'enviado_em', d.enviado_em, 'arquivado_em', d.arquivado_em,
      'enviado_por', (select pe.nome from public.perfis pf join public.pessoas pe on pe.id = pf.pessoa_id where pf.id = d.enviado_por)) order by d.enviado_em desc)
    from public.documentos d where d.pessoa_id = p_pessoa), '[]'::jsonb);
end $$;
create function public.secretaria_arquivar_documento(p_documento uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  update public.documentos set arquivado_em = now() where id = p_documento and arquivado_em is null;
  return jsonb_build_object('ok', found);
end $$;

-- Acesso a arquivos (a função de servidor gera link temporário só se isto devolver o caminho)
create function public.arquivo_autorizado(p_tipo text, p_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
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

-- Cerimônias e certificados
create function public.secretaria_salvar_cerimonia(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p->>'id', '')::uuid;
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  if v_id is null then
    insert into public.cerimonias (titulo, data, horario, local, evento_ref, responsavel, status, observacoes)
    values (btrim(p->>'titulo'), nullif(p->>'data', '')::date, nullif(btrim(p->>'horario'), ''), nullif(btrim(p->>'local'), ''), nullif(btrim(p->>'evento_ref'), ''),
            nullif(btrim(p->>'responsavel'), ''), coalesce(nullif(p->>'status', ''), 'planejada'), nullif(btrim(p->>'observacoes'), '')) returning id into v_id;
  else
    update public.cerimonias set titulo = btrim(p->>'titulo'), data = nullif(p->>'data', '')::date, horario = nullif(btrim(p->>'horario'), ''), local = nullif(btrim(p->>'local'), ''),
      evento_ref = nullif(btrim(p->>'evento_ref'), ''), responsavel = nullif(btrim(p->>'responsavel'), ''), status = coalesce(nullif(p->>'status', ''), status),
      observacoes = nullif(btrim(p->>'observacoes'), '') where id = v_id;
    if not found then raise exception 'Cerimônia não encontrada.' using errcode = 'P0002'; end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
exception when check_violation or not_null_violation then raise exception 'Informe o título da cerimônia (mínimo 3 caracteres).' using errcode = '22023';
end $$;

create function public.secretaria_certificados(p_filtros jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'cerimonias', coalesce((select jsonb_agg(to_jsonb(cm) || jsonb_build_object('certificados', (select count(*) from public.certificados ce where ce.cerimonia_id = cm.id and ce.status <> 'cancelado')) order by cm.data nulls last, cm.criado_em) from public.cerimonias cm), '[]'::jsonb),
    'certificados', coalesce((select jsonb_agg(jsonb_build_object('id', ce.id, 'codigo', ce.codigo, 'status', ce.status, 'cerimonia_id', ce.cerimonia_id,
        'cerimonia', cm.titulo, 'vezes_impresso', ce.vezes_impresso, 'impresso_em', ce.impresso_em, 'entregue_em', ce.entregue_em, 'recebido_por', ce.recebido_por,
        'motivo_cancelamento', ce.motivo_cancelamento, 'nome', pe.nome, 'curso', c.titulo, 'turma', t.nome, 'concluida_em', i.concluida_em, 'protocolo', i.protocolo) order by ce.criado_em desc)
      from public.certificados ce join public.inscricoes i on i.id = ce.inscricao_id join public.pessoas pe on pe.id = i.pessoa_id
      join public.turmas t on t.id = i.turma_id join public.cursos c on c.id = t.curso_id left join public.cerimonias cm on cm.id = ce.cerimonia_id
      where (p_filtros->>'status' is null or ce.status = p_filtros->>'status') and (p_filtros->>'cerimonia_id' is null or ce.cerimonia_id = (p_filtros->>'cerimonia_id')::uuid)), '[]'::jsonb));
end $$;

-- preparar (liga à cerimônia) | imprimir (registra impressão; devolve os dados) | entregar | cancelar
create function public.secretaria_certificado(p_certificado uuid, p_acao text, p_dados jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare ce public.certificados; v_imp jsonb;
begin
  if not public.e_secretaria() then raise exception 'Somente a Secretaria gerencia certificados.' using errcode = '42501'; end if;
  select * into ce from public.certificados where id = p_certificado for update;
  if not found then raise exception 'Certificado não encontrado.' using errcode = 'P0002'; end if;
  if ce.status = 'cancelado' and p_acao <> 'reativar' then raise exception 'Certificado cancelado.' using errcode = '22023'; end if;
  if p_acao = 'preparar' then
    if ce.status = 'entregue' then raise exception 'Certificado já entregue.' using errcode = '22023'; end if;
    if not exists (select 1 from public.cerimonias where id = (p_dados->>'cerimonia_id')::uuid and status = 'planejada') then
      raise exception 'Escolha uma cerimônia planejada.' using errcode = '22023'; end if;
    update public.certificados set cerimonia_id = (p_dados->>'cerimonia_id')::uuid, status = case when status = 'elegivel' then 'preparado' else status end,
           preparado_por = auth.uid(), preparado_em = now() where id = ce.id;
  elsif p_acao = 'imprimir' then
    if ce.status not in ('preparado','impresso') then raise exception 'Prepare o certificado (ligue a uma cerimônia) antes de imprimir.' using errcode = '22023'; end if;
    update public.certificados set status = 'impresso', impresso_por = auth.uid(), impresso_em = now(), vezes_impresso = vezes_impresso + 1 where id = ce.id;
    select jsonb_build_object('codigo', ce.codigo, 'nome', pe.nome, 'curso', c.titulo, 'carga_horaria', c.carga_horaria, 'concluida_em', i.concluida_em,
             'turma', t.nome, 'cerimonia', cm.titulo, 'cerimonia_data', cm.data)
      into v_imp from public.inscricoes i join public.pessoas pe on pe.id = i.pessoa_id join public.turmas t on t.id = i.turma_id
      join public.cursos c on c.id = t.curso_id left join public.cerimonias cm on cm.id = ce.cerimonia_id where i.id = ce.inscricao_id;
    return jsonb_build_object('ok', true, 'impressao', v_imp);
  elsif p_acao = 'entregar' then
    if ce.status <> 'impresso' then raise exception 'Só certificados impressos podem ser entregues.' using errcode = '22023'; end if;
    if char_length(btrim(coalesce(p_dados->>'recebido_por', ''))) < 3 then raise exception 'Informe quem recebeu o certificado.' using errcode = '22023'; end if;
    update public.certificados set status = 'entregue', entregue_em = now(), entregue_por = auth.uid(), recebido_por = btrim(p_dados->>'recebido_por') where id = ce.id;
  elsif p_acao = 'cancelar' then
    if char_length(btrim(coalesce(p_dados->>'motivo', ''))) < 3 then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
    update public.certificados set status = 'cancelado', motivo_cancelamento = btrim(p_dados->>'motivo') where id = ce.id;
  elsif p_acao = 'reativar' then
    if not exists (select 1 from public.inscricoes where id = ce.inscricao_id and status = 'concluida') then raise exception 'A inscrição não está concluída.' using errcode = '22023'; end if;
    update public.certificados set status = case when entregue_em is not null then 'entregue' when impresso_em is not null then 'impresso' when cerimonia_id is not null then 'preparado' else 'elegivel' end,
           motivo_cancelamento = null where id = ce.id;
  else raise exception 'Ação inválida.' using errcode = '22023';
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- Certificado nasce quando a inscrição é concluída (e é cancelado se a conclusão for desfeita antes da entrega)
create function public.tg_certificado_conclusao() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'concluida' and old.status is distinct from 'concluida' then
    insert into public.certificados (inscricao_id, codigo)
    values (new.id, upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)))
    on conflict (inscricao_id) do update set status = case when public.certificados.entregue_em is not null then 'entregue'
      when public.certificados.impresso_em is not null then 'impresso' when public.certificados.cerimonia_id is not null then 'preparado' else 'elegivel' end,
      motivo_cancelamento = null where public.certificados.status = 'cancelado';
    perform public.notificar('SECRETARIA', null, 'certificado_elegivel', 'Certificado a preparar', 'Inscrição ' || new.protocolo || ' concluída: certificado pronto para ser preparado.', jsonb_build_object('inscricao_id', new.id));
  elsif old.status = 'concluida' and new.status <> 'concluida' then
    update public.certificados set status = 'cancelado', motivo_cancelamento = 'Conclusão desfeita' where inscricao_id = new.id and status <> 'entregue';
  end if;
  return new;
end $$;
create trigger inscricoes_certificado after update of status on public.inscricoes for each row execute function public.tg_certificado_conclusao();

-- Inscrição cancelada com valor já aprovado: avisa a Tesouraria (possível reembolso)
create function public.tg_inscricao_cancelada_paga() returns trigger
language plpgsql security definer set search_path = '' as $$
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
create trigger inscricoes_cancelada_paga after update of status on public.inscricoes for each row execute function public.tg_inscricao_cancelada_paga();

-- 8. Tesouraria --------------------------------------------------------------
create function public.tesouraria_pagamentos(p_filtros jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

-- aprovar | recusar | solicitar_novo
create function public.tesouraria_analisar_pagamento(p_pagamento uuid, p_acao text, p_observacao text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.tesouraria_beneficios(p_status text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.e_tesouraria() then raise exception 'Acesso restrito à Tesouraria.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'tipo', b.tipo, 'status', b.status, 'valor_desconto', b.valor_desconto, 'motivo', b.motivo,
      'solicitado_em', b.solicitado_em, 'analisado_em', b.analisado_em, 'observacao_analise', b.observacao_analise,
      'solicitado_por', (select pe2.nome from public.perfis pf join public.pessoas pe2 on pe2.id = pf.pessoa_id where pf.id = b.solicitado_por),
      'inscricao_id', i.id, 'protocolo', i.protocolo, 'nome', pe.nome, 'curso', c.titulo, 'valor_bruto', i.valor_bruto, 'valor_final', i.valor_final) order by b.solicitado_em desc)
    from public.beneficios b join public.inscricoes i on i.id = b.inscricao_id join public.pessoas pe on pe.id = i.pessoa_id
    join public.turmas t on t.id = i.turma_id join public.cursos c on c.id = t.curso_id where p_status is null or b.status = p_status), '[]'::jsonb);
end $$;

-- aprovar | recusar (a Tesouraria também pode conceder direto: solicitar + aprovar)
create function public.tesouraria_analisar_beneficio(p_beneficio uuid, p_acao text, p_observacao text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.tesouraria_registrar_reembolso(p_pagamento uuid, p_valor numeric, p_metodo text, p_realizado_em date, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.tesouraria_dashboard(p_de date default null, p_ate date default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

-- Relatório de movimentações (entradas aprovadas e reembolsos) no período
create function public.tesouraria_movimentos(p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

-- 9. Ajuste de funções da M05 (a regra de pagamento passa a valer nelas) -----
-- cursos_alterar_inscricao: "promover" de turma paga vai para aguardando_pagamento (sem mudança);
-- o gatilho inscricoes_confirmacao_paga impede qualquer confirmação sem pagamento aprovado.

-- 10. RLS: tudo fechado; acesso só pelas funções ------------------------------
alter table public.pagamentos   enable row level security;
alter table public.comprovantes enable row level security;
alter table public.beneficios   enable row level security;
alter table public.reembolsos   enable row level security;
alter table public.documentos   enable row level security;
alter table public.cerimonias   enable row level security;
alter table public.certificados enable row level security;
alter table public.notificacoes enable row level security;
revoke all on public.pagamentos, public.comprovantes, public.beneficios, public.reembolsos, public.documentos,
              public.cerimonias, public.certificados, public.notificacoes from anon, authenticated;

-- 11. Armazenamento privado (sem nenhuma política de leitura: só links temporários gerados no servidor)
do $$ begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
      ('comprovantes', 'comprovantes', false, 5242880, array['application/pdf','image/jpeg','image/png','image/webp']),
      ('documentos',   'documentos',   false, 5242880, array['application/pdf','image/jpeg','image/png','image/webp'])
    on conflict (id) do nothing;
  end if;
end $$;

-- 12. Execução ----------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array[
      'e_secretaria','e_tesouraria','financeiro_minhas_permissoes','tg_nao_excluir','financeiro_inscricao','tg_inscricao_confirmacao_paga','financeiro_reavaliar',
      'notificar','minhas_notificacoes','marcar_notificacoes_lidas','servico_validar_link','servico_registrar_comprovante','minha_inscricao_curso',
      'secretaria_inscricoes','secretaria_pessoas','secretaria_validar_membresia','secretaria_registrar_pagamento_presencial','secretaria_cancelar_pagamento',
      'secretaria_solicitar_beneficio','servico_registrar_documento','secretaria_documentos','secretaria_arquivar_documento','arquivo_autorizado',
      'secretaria_salvar_cerimonia','secretaria_certificados','secretaria_certificado','tg_certificado_conclusao','tg_inscricao_cancelada_paga','tesouraria_pagamentos',
      'tesouraria_analisar_pagamento','tesouraria_beneficios','tesouraria_analisar_beneficio','tesouraria_registrar_reembolso','tesouraria_dashboard','tesouraria_movimentos'])
  loop execute format('revoke execute on function %s from public, anon, authenticated', f.sig); end loop;
end $$;
grant execute on function public.minha_inscricao_curso(text, text) to anon, authenticated;
grant execute on function public.e_secretaria(), public.e_tesouraria(), public.financeiro_minhas_permissoes(), public.minhas_notificacoes(integer),
  public.marcar_notificacoes_lidas(bigint[]), public.secretaria_inscricoes(jsonb), public.secretaria_pessoas(text), public.secretaria_validar_membresia(uuid, text, date, text),
  public.secretaria_registrar_pagamento_presencial(uuid, text, numeric, date, text), public.secretaria_cancelar_pagamento(uuid, text),
  public.secretaria_solicitar_beneficio(uuid, text, numeric, text), public.secretaria_documentos(uuid), public.secretaria_arquivar_documento(uuid),
  public.arquivo_autorizado(text, uuid), public.secretaria_salvar_cerimonia(jsonb), public.secretaria_certificados(jsonb), public.secretaria_certificado(uuid, text, jsonb),
  public.tesouraria_pagamentos(jsonb), public.tesouraria_analisar_pagamento(uuid, text, text), public.tesouraria_beneficios(text),
  public.tesouraria_analisar_beneficio(uuid, text, text), public.tesouraria_registrar_reembolso(uuid, numeric, text, date, text),
  public.tesouraria_dashboard(date, date), public.tesouraria_movimentos(date, date) to authenticated;
grant execute on function public.servico_validar_link(text, text), public.servico_registrar_comprovante(uuid, uuid, uuid, text, numeric, date, text, text, text, integer, text),
  public.servico_registrar_documento(uuid, uuid, text, text, text, text, text, integer, text) to service_role;

commit;
