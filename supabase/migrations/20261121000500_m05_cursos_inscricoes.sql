-- =====================================================================
-- M05 — Cursos e Formação Betel: categorias, cursos, turmas e inscrições
-- Só cria estruturas novas. Não altera tabelas existentes.
-- Datas, professores, valores, horários, locais e vagas NÃO são preenchidos:
-- ficam vazios até a Secretaria configurar no painel.
-- Preparado para cursos online (modalidade, link da aula, endereço da plataforma),
-- sem ambiente de EAD.
-- Para desfazer: 20261121000500_m05_cursos_inscricoes.down.sql
-- =====================================================================
begin;

-- 1. Tabelas ----------------------------------------------------------
create table public.categorias_curso (
  id            uuid primary key default gen_random_uuid(),
  nome          text not null unique check (char_length(btrim(nome)) between 2 and 80),
  descricao     text check (char_length(descricao) <= 600),
  ordem         integer not null default 0,
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table public.cursos (
  id               uuid primary key default gen_random_uuid(),
  categoria_id     uuid not null references public.categorias_curso(id),
  ministerio_id    uuid references public.ministerios(id),
  titulo           text not null check (char_length(btrim(titulo)) between 2 and 140),
  slug             text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  resumo           text check (char_length(resumo) <= 300),
  descricao        text check (char_length(descricao) <= 6000),
  publico_alvo     text check (char_length(publico_alvo) <= 600),
  imagem_url       text check (imagem_url is null or imagem_url ~ '^(https?://|/|img/)'),
  carga_horaria    text check (char_length(carga_horaria) <= 60),
  modalidade       text not null default 'presencial' check (modalidade in ('presencial','online','hibrido')),
  plataforma_url   text check (plataforma_url is null or plataforma_url ~ '^https://'),   -- futuro EAD
  exige_membro     boolean not null default false,
  cursos_exigidos  uuid[] not null default '{}',
  termos_exigidos  text[] not null default '{}',
  publicado        boolean not null default false,
  ordem            integer not null default 0,
  criado_por       uuid references auth.users(id),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now()
);

create table public.turmas (
  id                  uuid primary key default gen_random_uuid(),
  curso_id            uuid not null references public.cursos(id),
  nome                text not null check (char_length(btrim(nome)) between 2 and 120),
  data_inicio         date,
  data_fim            date,
  dias_horario        text check (char_length(dias_horario) <= 200),
  local               text check (char_length(local) <= 200),
  professores         text check (char_length(professores) <= 300),
  vagas               integer check (vagas is null or vagas between 1 and 5000),        -- vazio = sem limite
  lista_espera        boolean not null default true,
  valor               numeric(10,2) check (valor is null or valor >= 0),                  -- vazio ou 0 = gratuito
  inscricao_abre_em   timestamptz,
  inscricao_fecha_em  timestamptz,
  status              text not null default 'rascunho'
                      check (status in ('rascunho','inscricoes_abertas','inscricoes_encerradas','em_andamento','concluida','cancelada')),
  link_online         text check (link_online is null or link_online ~ '^https://'),      -- futuro EAD
  lote_reserva        text,                                                               -- reservas.lote_id da Agenda
  observacoes         text check (char_length(observacoes) <= 1000),
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  check (data_fim is null or data_inicio is null or data_fim >= data_inicio),
  check (inscricao_fecha_em is null or inscricao_abre_em is null or inscricao_fecha_em > inscricao_abre_em)
);

create sequence public.inscricoes_protocolo_seq;
create table public.inscricoes (
  id                    uuid primary key default gen_random_uuid(),
  protocolo             text not null unique,
  pessoa_id             uuid not null references public.pessoas(id),
  turma_id              uuid not null references public.turmas(id),   -- inscrições de eventos entram na Etapa 5 (coluna evento_id)
  status                text not null check (status in ('confirmada','aguardando_pagamento','lista_espera','cancelada','concluida')),
  valor_bruto           numeric(10,2) not null default 0,
  valor_desconto        numeric(10,2) not null default 0,
  valor_final           numeric(10,2) not null default 0,
  observacao            text check (char_length(observacao) <= 600),
  aceite_privacidade_em timestamptz not null,
  chave_hash            text not null,            -- hash da chave do link pessoal (a chave não é guardada)
  origem                text not null check (origem in ('site','secretaria')),
  criado_por            uuid references auth.users(id),
  criado_em             timestamptz not null default now(),
  promovida_em          timestamptz,
  cancelada_em          timestamptz,
  motivo_cancelamento   text check (char_length(motivo_cancelamento) <= 300),
  concluida_em          timestamptz,
  concluida_por         uuid references auth.users(id),
  atualizado_em         timestamptz not null default now()
);
-- Inscrição duplicada: uma pessoa só tem uma inscrição ativa por turma
create unique index inscricoes_pessoa_turma_ativa on public.inscricoes (pessoa_id, turma_id) where status <> 'cancelada';
create index inscricoes_turma_status on public.inscricoes (turma_id, status, criado_em);

-- 2. Permissão de gestão: MASTER ou atribuição SECRETARIA -------------
create function public.cursos_gestor() returns boolean
language sql stable security definer set search_path = '' as $$
  select public.e_master() or public.tem_atribuicao('SECRETARIA')
$$;

-- 3. Gatilhos ---------------------------------------------------------
create trigger categorias_curso_atualizado_em before update on public.categorias_curso for each row execute function public.tg_atualizado_em();
create trigger cursos_atualizado_em before update on public.cursos for each row execute function public.tg_atualizado_em();
create trigger turmas_atualizado_em before update on public.turmas for each row execute function public.tg_atualizado_em();
create trigger inscricoes_atualizado_em before update on public.inscricoes for each row execute function public.tg_atualizado_em();
create trigger categorias_curso_auditoria after insert or update or delete on public.categorias_curso for each row execute function public.tg_auditar();
create trigger cursos_auditoria after insert or update or delete on public.cursos for each row execute function public.tg_auditar();
create trigger turmas_auditoria after insert or update or delete on public.turmas for each row execute function public.tg_auditar();
create trigger inscricoes_auditoria after insert or update or delete on public.inscricoes for each row execute function public.tg_auditar();

-- Vagas: última barreira no banco, mesmo fora das funções
create function public.tg_inscricao_vagas() returns trigger
language plpgsql security definer set search_path = '' as $$
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
create trigger inscricoes_vagas before insert or update of status on public.inscricoes
  for each row execute function public.tg_inscricao_vagas();

-- 4. RLS --------------------------------------------------------------
alter table public.categorias_curso enable row level security;
alter table public.cursos           enable row level security;
alter table public.turmas           enable row level security;
alter table public.inscricoes       enable row level security;
revoke all on public.categorias_curso, public.cursos, public.turmas, public.inscricoes from anon, authenticated;
revoke all on sequence public.inscricoes_protocolo_seq from anon, authenticated;
grant select on public.categorias_curso, public.cursos, public.turmas to anon, authenticated;
grant select on public.inscricoes to authenticated;

create policy categorias_leitura on public.categorias_curso for select to anon, authenticated using (ativo or public.cursos_gestor());
create policy cursos_leitura on public.cursos for select to anon, authenticated using (publicado or public.cursos_gestor());
create policy turmas_leitura on public.turmas for select to anon, authenticated
  using (public.cursos_gestor() or (status <> 'rascunho' and exists (select 1 from public.cursos c where c.id = curso_id and c.publicado)));
create policy inscricoes_leitura on public.inscricoes for select to authenticated
  using (public.cursos_gestor() or pessoa_id = public.minha_pessoa_id());

-- 5. Funções públicas --------------------------------------------------
create function public.cursos_vagas_turma(p_turma uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'ocupadas', count(*) filter (where i.status in ('confirmada','aguardando_pagamento','concluida')),
    'espera',   count(*) filter (where i.status = 'lista_espera'))
  from public.inscricoes i where i.turma_id = p_turma
$$;

-- Turma com inscrições abertas agora (status + janela de datas)
create function public.turma_aberta(t public.turmas) returns boolean
language sql stable set search_path = '' as $$
  select t.status = 'inscricoes_abertas'
     and (t.inscricao_abre_em is null or now() >= t.inscricao_abre_em)
     and (t.inscricao_fecha_em is null or now() < t.inscricao_fecha_em)
$$;

create function public.cursos_json_turma(t public.turmas) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', t.id, 'nome', t.nome, 'data_inicio', t.data_inicio, 'data_fim', t.data_fim,
    'dias_horario', t.dias_horario, 'local', t.local, 'professores', t.professores, 'vagas', t.vagas,
    'lista_espera', t.lista_espera, 'valor', t.valor, 'inscricao_abre_em', t.inscricao_abre_em, 'inscricao_fecha_em', t.inscricao_fecha_em,
    'status', t.status, 'aberta', public.turma_aberta(t),
    'vagas_restantes', case when t.vagas is null then null else greatest(t.vagas - (public.cursos_vagas_turma(t.id)->>'ocupadas')::int, 0) end,
    'na_espera', (public.cursos_vagas_turma(t.id)->>'espera')::int)
$$;

create function public.cursos_json_curso(c public.cursos, p_turmas_publicas boolean) returns jsonb
language sql stable security definer set search_path = '' as $$
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

-- Página pública: categorias e cursos publicados
create function public.cursos_publicos() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', cat.id, 'nome', cat.nome, 'descricao', cat.descricao,
           'cursos', (select coalesce(jsonb_agg(public.cursos_json_curso(c, true) order by c.ordem, c.titulo), '[]')
                      from public.cursos c where c.categoria_id = cat.id and c.publicado)) order by cat.ordem, cat.nome), '[]'::jsonb)
  from public.categorias_curso cat where cat.ativo
$$;

create function public.curso_publico(p_slug text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select public.cursos_json_curso(c, true) from public.cursos c where c.slug = p_slug and c.publicado
$$;

-- Promove a lista de espera enquanto houver vaga (ordem de chegada)
create function public.cursos_promover_fila(p_turma uuid) returns integer
language plpgsql security definer set search_path = '' as $$
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

-- Inscrição (site ou secretaria). Vagas, duplicidade e pré-requisitos conferidos aqui.
create function public.inscrever_curso(
  p_turma uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date,
  p_observacao text, p_aceite_privacidade boolean, p_origem text default 'site'
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t public.turmas; c public.cursos; v_email text := lower(btrim(coalesce(p_email, '')));
        v_tel text := public.so_digitos(p_telefone); v_nome text := regexp_replace(btrim(coalesce(p_nome, '')), '\s+', ' ', 'g');
        v_pessoa uuid; v_existente public.inscricoes; v_status text; v_chave text; v_prot text; v_ocup integer; v_pos integer; v_falta text;
        v_secretaria boolean := p_origem = 'secretaria';
begin
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
  if c.exige_membro and not exists (select 1 from public.pessoas pe where pe.id = v_pessoa and pe.situacao_membresia = 'membro' and pe.membresia_validada_em is not null) then
    raise exception 'Este curso é para membros com a membresia validada pela Secretaria. Fale com a Secretaria.' using errcode = '22023';
  end if;
  select string_agg(x.titulo, ', ') into v_falta from public.cursos x
   where x.id = any(c.cursos_exigidos)
     and not exists (select 1 from public.inscricoes i join public.turmas tt on tt.id = i.turma_id
                     where i.pessoa_id = v_pessoa and tt.curso_id = x.id and i.status = 'concluida');
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

-- Acompanhar e cancelar pelo link pessoal (protocolo + chave)
create function public.minha_inscricao_curso(p_protocolo text, p_chave text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare i public.inscricoes; v_pos integer;
begin
  select * into i from public.inscricoes where protocolo = upper(btrim(p_protocolo))
     and chave_hash = encode(sha256(convert_to(coalesce(p_chave, ''), 'UTF8')), 'hex');
  if not found then raise exception 'Inscrição não encontrada. Confira o link recebido.' using errcode = 'P0002'; end if;
  if i.status = 'lista_espera' then
    select count(*) into v_pos from public.inscricoes where turma_id = i.turma_id and status = 'lista_espera'
       and (criado_em, protocolo) <= (i.criado_em, i.protocolo);
  end if;
  return (select jsonb_build_object('protocolo', i.protocolo, 'status', i.status, 'posicao_espera', v_pos,
      'nome', pe.nome, 'curso', c.titulo, 'curso_slug', c.slug, 'turma', public.cursos_json_turma(t), 'criado_em', i.criado_em, 'valor_final', i.valor_final)
    from public.turmas t join public.cursos c on c.id = t.curso_id join public.pessoas pe on pe.id = i.pessoa_id where t.id = i.turma_id);
end $$;

create function public.cancelar_minha_inscricao_curso(p_protocolo text, p_chave text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- 6. Funções do painel (Secretaria / MASTER) --------------------------
create function public.cursos_admin_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.cursos_gestor() then raise exception 'Somente a Secretaria ou o MASTER gerenciam cursos.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'categorias', (select coalesce(jsonb_agg(to_jsonb(cat) order by cat.ordem, cat.nome), '[]') from public.categorias_curso cat),
    'cursos', (select coalesce(jsonb_agg(public.cursos_json_curso(c, false) order by c.ordem, c.titulo), '[]') from public.cursos c));
end $$;

create function public.cursos_salvar_categoria(p_id uuid, p_nome text, p_descricao text, p_ordem integer, p_ativo boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.cursos_salvar_curso(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.cursos_salvar_turma(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.cursos_listar_inscricoes(p_turma uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.cursos_gestor() then raise exception 'Somente a Secretaria ou o MASTER veem as inscrições.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'protocolo', i.protocolo, 'status', i.status, 'origem', i.origem,
      'criado_em', i.criado_em, 'promovida_em', i.promovida_em, 'cancelada_em', i.cancelada_em, 'motivo_cancelamento', i.motivo_cancelamento,
      'concluida_em', i.concluida_em, 'valor_final', i.valor_final, 'observacao', i.observacao,
      'pessoa_id', pe.id, 'nome', pe.nome, 'email', pe.email, 'telefone', pe.telefone, 'data_nascimento', pe.data_nascimento)
      order by case i.status when 'lista_espera' then 2 when 'cancelada' then 3 else 1 end, i.criado_em)
    from public.inscricoes i join public.pessoas pe on pe.id = i.pessoa_id where i.turma_id = p_turma), '[]'::jsonb);
end $$;

-- cancelar | promover | concluir | reabrir_conclusao
create function public.cursos_alterar_inscricao(p_inscricao uuid, p_acao text, p_motivo text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- Participantes: busca, cadastro e histórico
create function public.cursos_participantes(p_busca text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.cursos_historico_participante(p_pessoa uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.cursos_atualizar_participante(p_pessoa uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- 7. Imagens: espaço público "cursos" no Storage (só a gestão envia) ---
do $$ begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('cursos', 'cursos', true, 2097152, array['image/jpeg','image/png','image/webp'])
    on conflict (id) do nothing;
    execute $p$create policy cursos_imagens_leitura on storage.objects for select to anon, authenticated using (bucket_id = 'cursos')$p$;
    execute $p$create policy cursos_imagens_envio on storage.objects for insert to authenticated with check (bucket_id = 'cursos' and public.cursos_gestor())$p$;
    execute $p$create policy cursos_imagens_troca on storage.objects for update to authenticated using (bucket_id = 'cursos' and public.cursos_gestor())$p$;
  end if;
end $$;

-- 8. Execução ---------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array[
      'cursos_gestor','tg_inscricao_vagas','cursos_vagas_turma','turma_aberta','cursos_json_turma','cursos_json_curso','cursos_publicos','curso_publico',
      'cursos_promover_fila','inscrever_curso','minha_inscricao_curso','cancelar_minha_inscricao_curso','cursos_admin_listar','cursos_salvar_categoria',
      'cursos_salvar_curso','cursos_salvar_turma','cursos_listar_inscricoes','cursos_alterar_inscricao','cursos_participantes',
      'cursos_historico_participante','cursos_atualizar_participante'])
  loop execute format('revoke execute on function %s from public, anon, authenticated', f.sig); end loop;
end $$;
grant execute on function public.cursos_gestor() to anon, authenticated;
grant execute on function public.cursos_publicos(), public.curso_publico(text),
  public.inscrever_curso(uuid, text, text, text, date, text, boolean, text),
  public.minha_inscricao_curso(text, text), public.cancelar_minha_inscricao_curso(text, text) to anon, authenticated;
grant execute on function public.cursos_admin_listar(), public.cursos_salvar_categoria(uuid, text, text, integer, boolean),
  public.cursos_salvar_curso(jsonb), public.cursos_salvar_turma(jsonb), public.cursos_listar_inscricoes(uuid),
  public.cursos_alterar_inscricao(uuid, text, text), public.cursos_participantes(text), public.cursos_historico_participante(uuid),
  public.cursos_atualizar_participante(uuid, text, text, text, date) to authenticated;

-- 9. Dados iniciais: categorias e cursos do planejamento --------------
-- Somente nomes e categorias. Tudo o mais fica em branco para a Secretaria preencher.
-- Os cursos começam NÃO publicados.
insert into public.categorias_curso (nome, ordem) values ('Formação Teológica', 1), ('Integração e Fundamentos', 2), ('Serviço e Voluntariado', 3);
insert into public.cursos (categoria_id, titulo, slug, ordem)
select c.id, x.titulo, x.slug, x.ordem from (values
  ('Formação Teológica', 'FATEB — Faculdade Teológica Betel', 'fateb', 1),
  ('Formação Teológica', 'Hermenêutica', 'hermeneutica', 2),
  ('Formação Teológica', 'Homilética', 'homiletica', 3),
  ('Formação Teológica', 'Curso completo sobre a vida de Paulo', 'vida-de-paulo', 4),
  ('Integração e Fundamentos', 'Curso de Batismo', 'batismo', 1),
  ('Integração e Fundamentos', 'Curso de Novos Membros', 'novos-membros', 2),
  ('Serviço e Voluntariado', 'Formação de Voluntários', 'formacao-de-voluntarios', 1)
) as x(categoria, titulo, slug, ordem) join public.categorias_curso c on c.nome = x.categoria;
-- Regra do planejamento: Formação de Voluntários exige membresia validada e o Curso de Novos Membros concluído
update public.cursos set exige_membro = true,
       cursos_exigidos = array[(select id from public.cursos where slug = 'novos-membros')]
 where slug = 'formacao-de-voluntarios';

commit;
