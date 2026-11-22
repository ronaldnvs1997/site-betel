-- =====================================================================
-- M07 — Novos Membros, Formação de Voluntários, termos e autorizações
-- Aditiva: cria tabelas novas; troca três funções (inscrever_curso,
-- secretaria_validar_membresia e a regra de pré-requisito) e acrescenta
-- dois tipos de documento. O .down devolve tudo ao estado da M06.
-- LGPD: dados mínimos, finalidade declarada em cada termo, versão e hash
-- do texto aceito, revogação a qualquer tempo, histórico imutável.
-- =====================================================================
begin;

-- 1. Tabelas -----------------------------------------------------------
-- Termos versionados. O texto publicado não muda mais: mudança = nova versão.
create table public.termos (
  id                uuid primary key default gen_random_uuid(),
  tipo              text not null check (tipo in ('participacao_curso','imagem_voz','voluntariado')),
  versao            integer not null check (versao >= 1),
  titulo            text not null check (char_length(btrim(titulo)) between 5 and 140),
  resumo            text check (char_length(resumo) <= 600),
  texto             text not null check (char_length(btrim(texto)) between 50 and 20000),
  exige_novo_aceite boolean not null default false,   -- se true, aceites de versões anteriores deixam de valer
  status            text not null default 'rascunho' check (status in ('rascunho','vigente','substituido')),
  texto_hash        text,
  criado_por        uuid references auth.users(id),
  criado_em         timestamptz not null default now(),
  publicado_por     uuid references auth.users(id),
  publicado_em      timestamptz,
  unique (tipo, versao)
);
create unique index termos_um_vigente on public.termos (tipo) where status = 'vigente';

-- Consentimentos: uma linha por decisão. Nunca é apagada nem alterada,
-- exceto o registro único de revogação.
create table public.consentimentos (
  id                 uuid primary key default gen_random_uuid(),
  pessoa_id          uuid not null references public.pessoas(id),
  termo_id           uuid not null references public.termos(id),
  tipo               text not null check (tipo in ('participacao_curso','imagem_voz','voluntariado')),
  decisao            text not null check (decisao in ('aceito','recusado')),
  escopo             jsonb not null default '{}'::jsonb,       -- imagem/voz: {"fotos":true,"videos":true,"voz":false}
  dado_por           text not null check (dado_por in ('titular','responsavel')),
  menor_na_data      boolean not null default false,
  responsavel        jsonb,                                     -- {nome, parentesco, telefone, email}
  origem             text not null check (origem in ('site','link','secretaria')),
  contexto_tipo      text check (contexto_tipo in ('inscricao','candidatura','avulso')),
  contexto_id        uuid,
  documento_id       uuid references public.documentos(id),      -- termo em papel digitalizado (opcional)
  texto_hash         text not null,                              -- hash do texto exato aceito
  registrado_por     uuid references auth.users(id),             -- quando a Secretaria registra
  registrado_em      timestamptz not null default now(),
  revogado_em        timestamptz,
  revogado_via       text check (revogado_via in ('titular','responsavel','secretaria')),
  revogado_por       uuid references auth.users(id),
  motivo_revogacao   text check (char_length(motivo_revogacao) <= 600),
  check (dado_por = 'titular' or (responsavel ? 'nome' and responsavel ? 'parentesco')),
  check (not menor_na_data or dado_por = 'responsavel'),
  check (tipo <> 'imagem_voz' or decisao = 'recusado' or (escopo ?| array['fotos','videos','voz']))
);
create index consentimentos_pessoa on public.consentimentos (pessoa_id, tipo, registrado_em desc);

-- Conclusões anteriores ao sistema (ex.: Novos Membros feito em 2019),
-- registradas pela Secretaria com comprovação. Não é autodeclaração.
create table public.cursos_conclusoes_anteriores (
  id            uuid primary key default gen_random_uuid(),
  pessoa_id     uuid not null references public.pessoas(id),
  curso_id      uuid not null references public.cursos(id),
  concluido_em  date not null check (concluido_em <= current_date),
  comprovacao   text not null check (char_length(btrim(comprovacao)) between 10 and 600),
  documento_id  uuid references public.documentos(id),
  registrado_por uuid not null references auth.users(id),
  registrado_em timestamptz not null default now(),
  cancelado_em  timestamptz,
  motivo_cancelamento text check (char_length(motivo_cancelamento) <= 300)
);
create unique index conclusoes_anteriores_unica on public.cursos_conclusoes_anteriores (pessoa_id, curso_id) where cancelado_em is null;

-- Processo de membresia (do interesse à validação pela Secretaria)
create table public.membresia_processos (
  id             uuid primary key default gen_random_uuid(),
  pessoa_id      uuid not null references public.pessoas(id),
  status         text not null default 'interesse' check (status in ('interesse','em_curso','aguardando_validacao','validado','encerrado')),
  origem         text not null check (origem in ('site','secretaria')),
  forma_ingresso text check (forma_ingresso in ('batismo','transferencia','aclamacao','reconciliacao')),
  mensagem       text check (char_length(mensagem) <= 1000),
  inscricao_id   uuid references public.inscricoes(id),
  observacao     text check (char_length(observacao) <= 1000),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  encerrado_em   timestamptz,
  motivo_encerramento text check (char_length(motivo_encerramento) <= 300)
);
create unique index membresia_processo_aberto on public.membresia_processos (pessoa_id) where status not in ('validado','encerrado');

-- Candidatura ao voluntariado (aberta ao concluir a Formação de Voluntários)
create table public.voluntariado_candidaturas (
  id            uuid primary key default gen_random_uuid(),
  pessoa_id     uuid not null references public.pessoas(id),
  status        text not null default 'aguardando_indicacao'
                check (status in ('aguardando_indicacao','em_analise','aprovada','nao_aprovada','cancelada')),
  inscricao_id  uuid references public.inscricoes(id),   -- inscrição na Formação de Voluntários
  observacao    text check (char_length(observacao) <= 600),
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  encerrada_em  timestamptz
);
create unique index candidatura_aberta on public.voluntariado_candidaturas (pessoa_id) where status in ('aguardando_indicacao','em_analise');

create table public.voluntariado_indicacoes (
  id             uuid primary key default gen_random_uuid(),
  candidatura_id uuid not null references public.voluntariado_candidaturas(id),
  ministerio_id  uuid not null references public.ministerios(id),
  ordem          smallint not null check (ordem between 1 and 3),
  status         text not null default 'pendente' check (status in ('pendente','aprovada','recusada','cancelada')),
  analisado_por  uuid references auth.users(id),
  analisado_em   timestamptz,
  motivo         text check (char_length(motivo) <= 600),
  criado_em      timestamptz not null default now(),
  unique (candidatura_id, ministerio_id)
);

-- Dois tipos novos de documento (termo assinado em papel e autorização do responsável)
alter table public.documentos drop constraint documentos_tipo_check;
alter table public.documentos add constraint documentos_tipo_check check (tipo in
  ('ficha_membresia','carta_transferencia','documento_responsavel','documento_identificacao','outro','termo_assinado','autorizacao_responsavel'));

-- 2. Proteções de histórico -------------------------------------------
create function public.tg_termo_imutavel() returns trigger language plpgsql set search_path = '' as $$
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
create trigger termos_imutavel before update or delete on public.termos for each row execute function public.tg_termo_imutavel();

create function public.tg_consentimento_imutavel() returns trigger language plpgsql set search_path = '' as $$
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
create trigger consentimentos_imutavel before update or delete on public.consentimentos for each row execute function public.tg_consentimento_imutavel();
create trigger conclusoes_anteriores_nao_excluir before delete on public.cursos_conclusoes_anteriores for each row execute function public.tg_nao_excluir();
create trigger candidaturas_nao_excluir before delete on public.voluntariado_candidaturas for each row execute function public.tg_nao_excluir();
create trigger indicacoes_nao_excluir before delete on public.voluntariado_indicacoes for each row execute function public.tg_nao_excluir();
create trigger membresia_processos_nao_excluir before delete on public.membresia_processos for each row execute function public.tg_nao_excluir();

create trigger membresia_processos_atualizado_em before update on public.membresia_processos for each row execute function public.tg_atualizado_em();
create trigger candidaturas_atualizado_em before update on public.voluntariado_candidaturas for each row execute function public.tg_atualizado_em();
do $$ declare t text; begin
  foreach t in array array['termos','consentimentos','cursos_conclusoes_anteriores','membresia_processos','voluntariado_candidaturas','voluntariado_indicacoes'] loop
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.tg_auditar()', t || '_auditoria', t);
  end loop;
end $$;

-- 3. Regras centrais ---------------------------------------------------
create function public.curso_id_por_slug(p_slug text) returns uuid
language sql stable security definer set search_path = '' as $$ select id from public.cursos where slug = p_slug $$;

-- Curso concluído: pela inscrição concluída ou por conclusão anterior registrada pela Secretaria
create function public.curso_concluido(p_pessoa uuid, p_curso uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.inscricoes i join public.turmas t on t.id = i.turma_id
                  where i.pessoa_id = p_pessoa and t.curso_id = p_curso and i.status = 'concluida')
      or exists (select 1 from public.cursos_conclusoes_anteriores c
                  where c.pessoa_id = p_pessoa and c.curso_id = p_curso and c.cancelado_em is null)
$$;

create function public.idade_em(p_nascimento date, p_data date default current_date) returns integer
language sql immutable set search_path = '' as $$ select extract(year from age(p_data, p_nascimento))::integer $$;

-- Membresia válida: somente a validada pela Secretaria (nunca autodeclaração)
create function public.membresia_validada(p_pessoa uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.pessoas where id = p_pessoa and situacao_membresia = 'membro'
                  and membresia_validada_em is not null and membresia_validada_por is not null and arquivado_em is null)
$$;

-- Consentimento em vigor (último registro, não revogado, de termo ainda válido)
create function public.consentimento_atual(p_pessoa uuid, p_tipo text) returns public.consentimentos
language sql stable security definer set search_path = '' as $$
  select c.* from public.consentimentos c join public.termos t on t.id = c.termo_id
   where c.pessoa_id = p_pessoa and c.tipo = p_tipo and c.revogado_em is null
     and not exists (select 1 from public.termos n where n.tipo = p_tipo and n.status = 'vigente'
                      and n.versao > t.versao and n.exige_novo_aceite)
   order by c.registrado_em desc limit 1
$$;

create function public.voluntariado_requisitos(p_pessoa uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

-- Regra no banco: ninguém entra como voluntário sem membresia validada e Novos Membros
create function public.tg_voluntario_requisitos() returns trigger language plpgsql set search_path = '' as $$
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
create trigger ministerio_membros_voluntario_requisitos before insert or update on public.ministerio_membros
  for each row execute function public.tg_voluntario_requisitos();

-- Termos vigentes (público)
create function public.termos_vigentes() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(tipo, jsonb_build_object('id', id, 'versao', versao, 'titulo', titulo, 'resumo', resumo, 'texto', texto)), '{}'::jsonb)
    from public.termos where status = 'vigente'
$$;

-- Validação dos dados do responsável legal
create function public.responsavel_valido(p jsonb) returns jsonb
language plpgsql immutable set search_path = '' as $$
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
end $$;

-- Registro interno de um consentimento (todas as entradas passam por aqui)
create function public.registrar_consentimento(
  p_pessoa uuid, p_tipo text, p_termo uuid, p_decisao text, p_escopo jsonb, p_responsavel jsonb,
  p_origem text, p_contexto_tipo text, p_contexto_id uuid, p_documento uuid default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
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

-- 4. Inscrição com termos (substitui a chamada direta de inscrever_curso) ----
create or replace function public.inscrever_curso(
  p_turma uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date,
  p_observacao text, p_aceite_privacidade boolean, p_origem text default 'site'
) returns jsonb
language plpgsql security definer set search_path = '' as $$
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
end $$;

create function public.inscrever_curso_com_termos(
  p_turma uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date, p_observacao text,
  p_aceite_privacidade boolean, p_termo_participacao uuid, p_imagem jsonb, p_responsavel jsonb,
  p_origem text default 'site', p_termo_presencial boolean default false
) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- 5. Termos e consentimentos pelo link pessoal -------------------------
create function public.link_inscricao(p_protocolo text, p_chave text) returns public.inscricoes
language plpgsql stable security definer set search_path = '' as $$
declare i public.inscricoes;
begin
  select * into i from public.inscricoes where protocolo = upper(btrim(p_protocolo))
     and chave_hash = encode(sha256(convert_to(coalesce(p_chave, ''), 'UTF8')), 'hex');
  if not found then raise exception 'Inscrição não encontrada. Confira o link recebido.' using errcode = 'P0002'; end if;
  return i;
end $$;

create function public.consentimentos_json(p_pessoa uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'tipo', c.tipo, 'decisao', c.decisao, 'escopo', c.escopo, 'versao', t.versao,
           'titulo', t.titulo, 'dado_por', c.dado_por, 'responsavel', c.responsavel->>'nome', 'origem', c.origem, 'registrado_em', c.registrado_em,
           'revogado_em', c.revogado_em, 'revogado_via', c.revogado_via, 'motivo_revogacao', c.motivo_revogacao,
           'em_vigor', c.id = (public.consentimento_atual(c.pessoa_id, c.tipo)).id,
           'versao_desatualizada', exists (select 1 from public.termos n where n.tipo = c.tipo and n.status = 'vigente' and n.versao > t.versao))
         order by c.registrado_em desc), '[]'::jsonb)
    from public.consentimentos c join public.termos t on t.id = c.termo_id where c.pessoa_id = p_pessoa
$$;

create function public.meus_termos(p_protocolo text, p_chave text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare i public.inscricoes := public.link_inscricao(p_protocolo, p_chave); pe public.pessoas;
begin
  select * into pe from public.pessoas where id = i.pessoa_id;
  return jsonb_build_object('consentimentos', public.consentimentos_json(i.pessoa_id),
    'menor', case when pe.data_nascimento is null then null else public.idade_em(pe.data_nascimento) < 18 end,
    'tem_nascimento', pe.data_nascimento is not null, 'vigentes', public.termos_vigentes());
end $$;

create function public.autorizar_imagem_link(p_protocolo text, p_chave text, p_termo uuid, p_decisao text, p_escopo jsonb, p_responsavel jsonb, p_data_nascimento date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare i public.inscricoes := public.link_inscricao(p_protocolo, p_chave); v_id uuid;
begin
  if p_data_nascimento is not null then
    update public.pessoas set data_nascimento = p_data_nascimento where id = i.pessoa_id and data_nascimento is null;
  end if;
  v_id := public.registrar_consentimento(i.pessoa_id, 'imagem_voz', p_termo, p_decisao, p_escopo, p_responsavel, 'link', 'inscricao', i.id);
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create function public.revogar_consentimento_link(p_protocolo text, p_chave text, p_consentimento uuid, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- 6. Membresia: interesse (público), processos e validação --------------
create function public.membresia_interesse(p_nome text, p_telefone text, p_email text, p_data_nascimento date, p_mensagem text, p_aceite_privacidade boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
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
end $$;

-- O andamento acompanha o Curso de Novos Membros e a Formação de Voluntários
create function public.tg_inscricao_membresia_voluntariado() returns trigger language plpgsql security definer set search_path = '' as $$
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
create trigger inscricoes_membresia_voluntariado after insert or update of status on public.inscricoes
  for each row execute function public.tg_inscricao_membresia_voluntariado();

create or replace function public.secretaria_validar_membresia(p_pessoa uuid, p_situacao text, p_membro_desde date, p_observacao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.secretaria_processos_membresia(p_status text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.secretaria_abrir_processo(p_pessoa uuid, p_observacao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.secretaria_encerrar_processo(p_processo uuid, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 5 then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
  update public.membresia_processos set status = 'encerrado', encerrado_em = now(), motivo_encerramento = btrim(p_motivo)
   where id = p_processo and status not in ('validado','encerrado');
  if not found then raise exception 'Processo não encontrado ou já encerrado.' using errcode = 'P0002'; end if;
  return jsonb_build_object('ok', true);
end $$;

create function public.secretaria_registrar_conclusao_anterior(p_pessoa uuid, p_curso uuid, p_concluido_em date, p_comprovacao text, p_documento uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.secretaria_cancelar_conclusao_anterior(p_id uuid, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 5 then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
  update public.cursos_conclusoes_anteriores set cancelado_em = now(), motivo_cancelamento = btrim(p_motivo) where id = p_id and cancelado_em is null;
  if not found then raise exception 'Registro não encontrado.' using errcode = 'P0002'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- Ficha da pessoa para a Secretaria: requisitos, conclusões e consentimentos
create function public.secretaria_ficha_pessoa(p_pessoa uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

-- 7. Voluntariado ------------------------------------------------------
create function public.candidatura_json(p_cand uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', c.id, 'status', c.status, 'criado_em', c.criado_em, 'observacao', c.observacao,
    'pessoa_id', pe.id, 'nome', pe.nome, 'telefone', pe.telefone, 'email', pe.email,
    'requisitos', public.voluntariado_requisitos(pe.id),
    'indicacoes', coalesce((select jsonb_agg(jsonb_build_object('id', vi.id, 'ministerio_id', vi.ministerio_id, 'ministerio', m.nome, 'ordem', vi.ordem,
        'status', vi.status, 'motivo', vi.motivo, 'analisado_em', vi.analisado_em,
        'analisado_por', (select x.nome from public.perfis pf join public.pessoas x on x.id = pf.pessoa_id where pf.id = vi.analisado_por)) order by vi.ordem)
        from public.voluntariado_indicacoes vi join public.ministerios m on m.id = vi.ministerio_id where vi.candidatura_id = c.id), '[]'::jsonb))
  from public.voluntariado_candidaturas c join public.pessoas pe on pe.id = c.pessoa_id where c.id = p_cand
$$;

-- Indicação de até 3 ministérios + termo de adesão ao serviço voluntário (Lei 9.608/1998)
create function public.voluntariado_indicar_interno(p_cand uuid, p_ministerios uuid[], p_termo uuid, p_origem text, p_responsavel jsonb) returns void
language plpgsql security definer set search_path = '' as $$
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

create function public.minha_candidatura(p_protocolo text, p_chave text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare i public.inscricoes := public.link_inscricao(p_protocolo, p_chave); v uuid;
begin
  select id into v from public.voluntariado_candidaturas where pessoa_id = i.pessoa_id order by criado_em desc limit 1;
  if v is null then return null; end if;
  return (public.candidatura_json(v) - 'telefone' - 'email' - 'pessoa_id')
    || jsonb_build_object('ministerios', (select jsonb_agg(jsonb_build_object('id', id, 'nome', nome) order by ordem, nome) from public.ministerios where ativo),
                          'termo', public.termos_vigentes()->'voluntariado');
end $$;

create function public.voluntariado_indicar(p_protocolo text, p_chave text, p_ministerios uuid[], p_termo uuid, p_responsavel jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare i public.inscricoes := public.link_inscricao(p_protocolo, p_chave); v uuid;
begin
  select id into v from public.voluntariado_candidaturas where pessoa_id = i.pessoa_id and status = 'aguardando_indicacao';
  if v is null then raise exception 'Não há candidatura aguardando indicação de ministérios.' using errcode = 'P0002'; end if;
  perform public.voluntariado_indicar_interno(v, p_ministerios, p_termo, 'link', p_responsavel);
  return jsonb_build_object('ok', true);
end $$;

create function public.secretaria_candidaturas(p_status text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.secretaria_abrir_candidatura(p_pessoa uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.secretaria_indicar_ministerios(p_candidatura uuid, p_ministerios uuid[], p_termo uuid, p_termo_presencial boolean, p_responsavel jsonb, p_documento uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.secretaria_cancelar_candidatura(p_candidatura uuid, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 5 then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
  update public.voluntariado_candidaturas set status = 'cancelada', encerrada_em = now(), observacao = btrim(p_motivo)
   where id = p_candidatura and status in ('aguardando_indicacao','em_analise');
  if not found then raise exception 'Candidatura não encontrada ou já encerrada.' using errcode = 'P0002'; end if;
  update public.voluntariado_indicacoes set status = 'cancelada' where candidatura_id = p_candidatura and status = 'pendente';
  return jsonb_build_object('ok', true);
end $$;

-- Liderança: candidatos que indicaram os ministérios que lidero
create function public.lider_candidaturas() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.lider_decidir_indicacao(p_indicacao uuid, p_acao text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- 8. Termos (gestão) e consentimentos pela Secretaria --------------------
create function public.secretaria_termos() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'tipo', t.tipo, 'versao', t.versao, 'titulo', t.titulo, 'resumo', t.resumo, 'texto', t.texto,
      'exige_novo_aceite', t.exige_novo_aceite, 'status', t.status, 'publicado_em', t.publicado_em, 'criado_em', t.criado_em,
      'aceites', (select count(*) from public.consentimentos c where c.termo_id = t.id and c.decisao = 'aceito'),
      'pendencias', (select array_agg(m[1]) from regexp_matches(t.texto, '⟦([^⟧]*)⟧', 'g') m)) order by t.tipo, t.versao desc)
    from public.termos t), '[]'::jsonb);
end $$;

create function public.secretaria_salvar_termo(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.secretaria_publicar_termo(p_termo uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.secretaria_registrar_consentimento(p_pessoa uuid, p_tipo text, p_termo uuid, p_decisao text, p_escopo jsonb,
  p_responsavel jsonb, p_documento uuid, p_data_nascimento date) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.secretaria_revogar_consentimento(p_consentimento uuid, p_via text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- Consulta para a equipe de Mídia: só nome e situação da autorização (busca por nome)
create function public.imagem_consultar(p_busca text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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
-- 9. Dados iniciais: modelos de termos em RASCUNHO --------------------
-- Os textos são modelos para revisão da igreja. Os trechos ⟦…⟧ precisam ser
-- preenchidos pela igreja; um termo com ⟦…⟧ não pode ser publicado.
insert into public.termos (tipo, versao, titulo, resumo, texto) values
('participacao_curso', 1, 'Termo de participação nos cursos da Igreja Batista Betel',
 'Regras de participação e uso dos seus dados para organizar o curso.',
 E'Ao me inscrever em um curso da Igreja Batista Betel no Flamengo (Contagem/MG), declaro que:\n\n1. Li as informações do curso e me comprometo a respeitar as orientações da coordenação, os horários e as pessoas da turma.\n2. Entendo que a conclusão depende da frequência e das atividades definidas para o curso, e que o certificado, quando houver, é entregue pessoalmente.\n3. Autorizo o uso dos meus dados (nome, telefone, e-mail e data de nascimento) somente para organizar o curso, controlar a frequência, registrar a conclusão e entrar em contato sobre ele. Os dados não são vendidos nem compartilhados com terceiros.\n4. Sei que posso pedir a consulta, a correção ou a exclusão dos meus dados, ressalvados os registros que a igreja precisa manter, pelo contato ⟦e-mail ou telefone da Secretaria para assuntos de dados pessoais⟧.\n5. Se o participante tiver menos de 18 anos, este termo é aceito pelo responsável legal, que autoriza a participação.\n\nResponsável pelo tratamento dos dados: Igreja Batista Betel no Flamengo, ⟦CNPJ⟧.'),
('imagem_voz', 1, 'Autorização de uso de imagem e voz',
 'Opcional. Não é condição para participar de cursos ou eventos.',
 E'Esta autorização é OPCIONAL. Quem não autoriza participa normalmente de todos os cursos e eventos.\n\nAutorizo a Igreja Batista Betel no Flamengo a usar, sem custo, a minha imagem e/ou voz, conforme as opções que marquei (fotos, vídeos, voz), captadas em cursos, cultos e eventos, para divulgação das atividades da igreja no site, nas redes sociais e em materiais impressos da própria igreja.\n\nA igreja não usa a imagem em contexto que prejudique a honra ou a dignidade da pessoa e não cede a imagem para fins comerciais de terceiros.\n\nPosso revogar esta autorização a qualquer momento, pelo link da minha inscrição ou pela Secretaria. A revogação vale para novos usos; materiais já publicados serão retirados quando for possível fazê-lo.\n\nPara menores de 18 anos, esta autorização só é válida quando dada pelo responsável legal.\n\nContato para assuntos de dados pessoais: ⟦e-mail ou telefone da Secretaria⟧.'),
('voluntariado', 1, 'Termo de adesão ao serviço voluntário',
 'Exigido pela Lei 9.608/1998 para o serviço voluntário.',
 E'Termo de adesão ao serviço voluntário (Lei nº 9.608/1998).\n\nEu me ofereço para servir como voluntário(a) na Igreja Batista Betel no Flamengo, ⟦CNPJ⟧, nos ministérios em que for aprovado(a) pela liderança.\n\n1. O serviço é voluntário, sem remuneração e sem vínculo de emprego ou obrigação trabalhista, previdenciária ou afim.\n2. Comprometo-me a seguir as orientações da liderança do ministério, as escalas combinadas e as normas de conduta e de proteção a crianças e adolescentes da igreja.\n3. Despesas só são reembolsadas quando previamente autorizadas e comprovadas.\n4. Meus dados (nome, contato e ministérios) são usados para organizar escalas, comunicação da equipe e o histórico de serviço.\n5. Posso encerrar o voluntariado a qualquer momento, comunicando a liderança ou a Secretaria.\n\nContato para assuntos de dados pessoais: ⟦e-mail ou telefone da Secretaria⟧.');

-- 10. RLS e permissões -----------------------------------------------
alter table public.termos enable row level security;
alter table public.consentimentos enable row level security;
alter table public.cursos_conclusoes_anteriores enable row level security;
alter table public.membresia_processos enable row level security;
alter table public.voluntariado_candidaturas enable row level security;
alter table public.voluntariado_indicacoes enable row level security;
revoke all on public.termos, public.consentimentos, public.cursos_conclusoes_anteriores, public.membresia_processos,
              public.voluntariado_candidaturas, public.voluntariado_indicacoes from anon, authenticated;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array[
      'tg_termo_imutavel','tg_consentimento_imutavel','curso_id_por_slug','curso_concluido','idade_em','membresia_validada','consentimento_atual',
      'voluntariado_requisitos','tg_voluntario_requisitos','termos_vigentes','responsavel_valido','registrar_consentimento','inscrever_curso',
      'inscrever_curso_com_termos','link_inscricao','consentimentos_json','meus_termos','autorizar_imagem_link','revogar_consentimento_link',
      'membresia_interesse','tg_inscricao_membresia_voluntariado','secretaria_validar_membresia','secretaria_processos_membresia','secretaria_abrir_processo',
      'secretaria_encerrar_processo','secretaria_registrar_conclusao_anterior','secretaria_cancelar_conclusao_anterior','secretaria_ficha_pessoa',
      'candidatura_json','voluntariado_indicar_interno','minha_candidatura','voluntariado_indicar','secretaria_candidaturas','secretaria_abrir_candidatura',
      'secretaria_indicar_ministerios','secretaria_cancelar_candidatura','lider_candidaturas','lider_decidir_indicacao','secretaria_termos',
      'secretaria_salvar_termo','secretaria_publicar_termo','secretaria_registrar_consentimento','secretaria_revogar_consentimento','imagem_consultar'])
  loop execute format('revoke execute on function %s from public, anon, authenticated', f.sig); end loop;
end $$;
-- públicas (site e link pessoal)
grant execute on function public.termos_vigentes(), public.membresia_interesse(text, text, text, date, text, boolean),
  public.inscrever_curso_com_termos(uuid, text, text, text, date, text, boolean, uuid, jsonb, jsonb, text, boolean),
  public.meus_termos(text, text), public.autorizar_imagem_link(text, text, uuid, text, jsonb, jsonb, date),
  public.revogar_consentimento_link(text, text, uuid, text), public.minha_candidatura(text, text),
  public.voluntariado_indicar(text, text, uuid[], uuid, jsonb) to anon, authenticated;
-- equipe (cada função confere a permissão)
grant execute on function public.secretaria_validar_membresia(uuid, text, date, text), public.secretaria_processos_membresia(text),
  public.secretaria_abrir_processo(uuid, text), public.secretaria_encerrar_processo(uuid, text),
  public.secretaria_registrar_conclusao_anterior(uuid, uuid, date, text, uuid), public.secretaria_cancelar_conclusao_anterior(uuid, text),
  public.secretaria_ficha_pessoa(uuid), public.secretaria_candidaturas(text), public.secretaria_abrir_candidatura(uuid),
  public.secretaria_indicar_ministerios(uuid, uuid[], uuid, boolean, jsonb, uuid), public.secretaria_cancelar_candidatura(uuid, text),
  public.lider_candidaturas(), public.lider_decidir_indicacao(uuid, text, text), public.secretaria_termos(), public.secretaria_salvar_termo(jsonb),
  public.secretaria_publicar_termo(uuid), public.secretaria_registrar_consentimento(uuid, text, uuid, text, jsonb, jsonb, uuid, date),
  public.secretaria_revogar_consentimento(uuid, text, text), public.imagem_consultar(text) to authenticated;
-- inscrever_curso deixa de ser chamada diretamente: só pela inscrição com termos

commit;
