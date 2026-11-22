-- =====================================================================
-- Sistema Betel — instalação completa do banco num único arquivo (PostgreSQL 14+).
--
-- NORMALMENTE NÃO É PRECISO RODAR ESTE ARQUIVO: o servidor faz a mesma coisa sozinho ao iniciar.
-- Use só se quiser preparar o banco antes, pelo terminal:
--     psql "URL_EXTERNA_DO_BANCO" -f database/instalar-tudo.sql
-- (no Render: betel-banco → Connect → External Database URL)
--
-- Pode rodar quantas vezes quiser: cada etapa já aplicada é pulada (tabela sistema.migracoes).
-- Exige o psql (usa \if). Não importa os CSVs da Agenda antiga — isso o servidor faz na 1ª subida.
-- Gerado por scripts/gerar-sql-unico.mjs a partir de database/plataforma e database/migrations.
-- =====================================================================
\set ON_ERROR_STOP on
create schema if not exists sistema;
create table if not exists sistema.migracoes (nome text primary key, aplicada_em timestamptz not null default now());

-- ---------------------------------------------------------------------
-- 000_plataforma
select not exists (select 1 from sistema.migracoes where nome = '000_plataforma') as fazer \gset
\if :fazer
\echo 'Aplicando 000_plataforma'
-- =====================================================================
-- Base da plataforma Betel (substitui os serviços do Supabase).
-- Papéis do banco usados pelas permissões (RLS), contas de acesso,
-- sessões, recuperação de senha e arquivos guardados no próprio banco.
-- Roda com o usuário dono do banco (no Render, o usuário criado com o banco).
-- =====================================================================
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin noinherit; end if;
end $$;
-- o servidor precisa "vestir" o papel do visitante ou do usuário logado em cada consulta
do $$ begin
  execute format('grant anon, authenticated, service_role to %I', current_user);
exception when others then null;
end $$;
do $$ begin
  if not (pg_has_role(current_user, 'anon', 'MEMBER') and pg_has_role(current_user, 'authenticated', 'MEMBER')) then
    raise exception 'O usuário % precisa poder assumir os papéis anon e authenticated (CREATEROLE).', current_user;
  end if;
end $$;

create schema if not exists auth;
create table if not exists auth.users (
  instance_id uuid, id uuid primary key, aud text default 'authenticated', role text default 'authenticated',
  email text unique, encrypted_password text, email_confirmed_at timestamptz, banned_until timestamptz,
  raw_app_meta_data jsonb default '{}', raw_user_meta_data jsonb default '{}',
  created_at timestamptz default now(), updated_at timestamptz default now(), last_sign_in_at timestamptz
);
create table if not exists auth.sessoes (
  token_hash text primary key, usuario_id uuid not null references auth.users(id) on delete cascade,
  criado_em timestamptz not null default now(), expira_em timestamptz not null
);
create index if not exists sessoes_usuario on auth.sessoes (usuario_id);
create table if not exists auth.recuperacoes (
  token_hash text primary key, usuario_id uuid not null references auth.users(id) on delete cascade,
  criado_em timestamptz not null default now(), expira_em timestamptz not null
);
create or replace function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid $$;
create or replace function auth.role() returns text language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'))::text $$;
create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim', true), ''), nullif(current_setting('request.jwt.claims', true), ''))::jsonb $$;
revoke all on auth.users, auth.sessoes, auth.recuperacoes from anon, authenticated, service_role;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid(), auth.role(), auth.jwt() to anon, authenticated, service_role;

-- arquivos (comprovantes, documentos e imagens dos cursos): só o servidor acessa esta tabela
create schema if not exists armazenamento;
create table if not exists armazenamento.objetos (
  espaco text not null, caminho text not null, tipo text not null, tamanho integer not null,
  conteudo bytea not null, criado_por uuid, criado_em timestamptz not null default now(),
  primary key (espaco, caminho)
);
revoke all on schema armazenamento from public, anon, authenticated, service_role;

grant usage on schema public to anon, authenticated, service_role;
-- privilégios padrão: a proteção vem do RLS e dos revokes de cada migração
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
insert into sistema.migracoes (nome) values ('000_plataforma');
\else
\echo 'Já aplicada: 000_plataforma'
\endif

-- ---------------------------------------------------------------------
-- 001_agenda_base
select not exists (select 1 from sistema.migracoes where nome = '001_agenda_base') as fazer \gset
\if :fazer
\echo 'Aplicando 001_agenda_base'
-- Tabelas da Agenda Ministerial como existiam no sistema anterior.
-- Num banco novo ficam vazias (ou recebem os dados exportados do sistema anterior);
-- as migrações seguintes (M02 a M04) as transformam, preservando os dados.
create table if not exists public.eventos (id bigint generated by default as identity primary key, titulo text, data text, ministerio text, lider text,
  horario text, horario_inicio text, horario_fim text, local text, necessita_midia text, necessita_louvor text, necessita_diaconia text,
  midia_tema text, midia_arte text, midia_banner text, midia_inscricao text, midia_link_inscricao text, midia_info text, observacoes text,
  link_fotos text, link_videos text, bloqueado boolean default false, atualizado_em timestamptz);
create table if not exists public.reservas (id bigint generated by default as identity primary key, ministerio text, motivo text, espacos text, data text,
  horario_inicio text, horario_fim text, lote_id text);
create table if not exists public.coordenadores (id bigint generated by default as identity primary key, nome text, login text unique, senha text not null, ativo boolean default true);
insert into sistema.migracoes (nome) values ('001_agenda_base');
\else
\echo 'Já aplicada: 001_agenda_base'
\endif

-- ---------------------------------------------------------------------
-- 003_sessoes_revogaveis
select not exists (select 1 from sistema.migracoes where nome = '003_sessoes_revogaveis') as fazer \gset
\if :fazer
\echo 'Aplicando 003_sessoes_revogaveis'
-- Plataforma 003 — "Sair" encerra a sessão no servidor (aditiva).
-- Cada login recebe um identificador de sessão. Ao sair, a sessão é
-- encerrada: o token de renovação é apagado e o token de acesso daquela
-- sessão deixa de ser aceito, mesmo antes de expirar.
alter table auth.sessoes add column if not exists sessao_id uuid;
create index if not exists sessoes_sessao_id on auth.sessoes (sessao_id);
create table if not exists auth.sessoes_encerradas (
  sessao_id uuid primary key,
  expira_em timestamptz not null
);
insert into sistema.migracoes (nome) values ('003_sessoes_revogaveis');
\else
\echo 'Já aplicada: 003_sessoes_revogaveis'
\endif

-- ---------------------------------------------------------------------
-- 20261121000100_m01_nucleo_autenticacao
select not exists (select 1 from sistema.migracoes where nome = '20261121000100_m01_nucleo_autenticacao') as fazer \gset
\if :fazer
\echo 'Aplicando 20261121000100_m01_nucleo_autenticacao'
-- =====================================================================
-- M01 — Núcleo: autenticação centralizada e Área da Equipe
-- Igreja Batista Betel no Flamengo
--
-- Migração ADITIVA: cria apenas estruturas novas.
-- NÃO altera, renomeia nem exclui as tabelas existentes
-- (eventos, reservas, coordenadores).
-- Para desfazer: 20261121000100_m01_nucleo_autenticacao.down.sql
-- =====================================================================
begin;

-- ---------------------------------------------------------------------
-- 1. Tabelas novas
-- ---------------------------------------------------------------------

-- Cadastro único de pessoas (pode existir sem conta de acesso)
create table public.pessoas (
  id                      uuid primary key default gen_random_uuid(),
  usuario_id              uuid unique references auth.users(id) on delete restrict,
  nome                    text not null check (char_length(btrim(nome)) between 3 and 120),
  telefone                text check (telefone ~ '^[0-9]{10,13}$'),
  email                   text check (email = lower(btrim(email)) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  data_nascimento         date,
  bairro                  text,
  cidade                  text,
  situacao_membresia      text not null default 'visitante'
                          check (situacao_membresia in ('visitante','em_integracao','membro','inativo')),
  membro_desde            date,
  membresia_validada_por  uuid references auth.users(id),
  membresia_validada_em   timestamptz,
  origem                  text not null default 'secretaria'
                          check (origem in ('site','secretaria','migracao')),
  criado_em               timestamptz not null default now(),
  atualizado_em           timestamptz not null default now(),
  arquivado_em            timestamptz
);
create unique index pessoas_email_unico on public.pessoas (email)
  where email is not null and arquivado_em is null;

-- Ministérios
create table public.ministerios (
  id             uuid primary key default gen_random_uuid(),
  nome           text not null unique check (char_length(btrim(nome)) between 2 and 80),
  slug           text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  descricao      text check (char_length(descricao) <= 600),
  ativo          boolean not null default true,
  ordem          integer not null default 0,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);

-- Perfil de acesso de cada conta (complementa auth.users)
create table public.perfis (
  id                 uuid primary key references auth.users(id) on delete restrict,
  pessoa_id          uuid not null unique references public.pessoas(id),
  perfil             text not null check (perfil in ('MASTER','LIDER','VOLUNTARIO')),
  atribuicoes        text[] not null default '{}'
                     check (atribuicoes <@ array['SECRETARIA','TESOURARIA']::text[]),
  ativo              boolean not null default true,
  deve_trocar_senha  boolean not null default true,
  senha_alterada_em  timestamptz,
  aprovado_por       uuid references auth.users(id),
  aprovado_em        timestamptz,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now()
);

-- Vínculo pessoa × ministério (função por ministério)
create table public.ministerio_membros (
  id             uuid primary key default gen_random_uuid(),
  pessoa_id      uuid not null references public.pessoas(id),
  ministerio_id  uuid not null references public.ministerios(id),
  funcao         text not null check (funcao in ('lider','voluntario')),
  desde          date not null default current_date,
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique (pessoa_id, ministerio_id)
);

-- Solicitações (acesso à Área da Equipe e, futuramente, voluntariado)
create table public.solicitacoes (
  id                 uuid primary key default gen_random_uuid(),
  tipo               text not null check (tipo in ('acesso','voluntariado')),
  nome               text not null check (char_length(btrim(nome)) between 3 and 120),
  telefone           text not null check (telefone ~ '^[0-9]{10,13}$'),
  email              text not null check (email = lower(btrim(email)) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  ministerio_id      uuid references public.ministerios(id),
  funcao_pretendida  text check (funcao_pretendida in ('lider','voluntario')),
  mensagem           text check (char_length(mensagem) <= 1000),
  status             text not null default 'pendente' check (status in ('pendente','aprovada','recusada')),
  analisado_por      uuid references auth.users(id),
  analisado_em       timestamptz,
  motivo             text check (char_length(motivo) <= 500),
  pessoa_id          uuid references public.pessoas(id),
  criado_em          timestamptz not null default now(),
  check (tipo <> 'acesso' or (ministerio_id is not null and funcao_pretendida is not null))
);
create unique index solicitacoes_acesso_pendente_unica on public.solicitacoes (email)
  where tipo = 'acesso' and status = 'pendente';

-- Configurações gerais
create table public.configuracoes (
  chave          text primary key check (chave ~ '^[a-z0-9_.]+$'),
  valor          jsonb not null,
  publico        boolean not null default false,
  atualizado_em  timestamptz not null default now(),
  atualizado_por uuid references auth.users(id)
);

-- Histórico administrativo (somente inclusão)
create table public.auditoria (
  id         bigint generated always as identity primary key,
  quando     timestamptz not null default now(),
  ator       uuid,
  acao       text not null,
  tabela     text,
  registro   text,
  antes      jsonb,
  depois     jsonb,
  detalhes   jsonb
);
create index auditoria_quando_idx on public.auditoria (quando desc);

-- ---------------------------------------------------------------------
-- 2. Funções auxiliares de permissão
--    (security definer, caminho de busca vazio)
-- ---------------------------------------------------------------------

create function public.minha_pessoa_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select p.pessoa_id from public.perfis p where p.id = auth.uid()
$$;

-- Perfil ativo e com a senha temporária já trocada
create function public.perfil_ativo() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select p.ativo and not p.deve_trocar_senha
                   from public.perfis p where p.id = auth.uid()), false)
$$;

create function public.e_master_uid(p_uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select p.ativo and not p.deve_trocar_senha and p.perfil = 'MASTER'
                   from public.perfis p where p.id = p_uid), false)
$$;

create function public.e_master() returns boolean
language sql stable security definer set search_path = '' as $$
  select public.e_master_uid(auth.uid())
$$;

create function public.tem_atribuicao(p_atribuicao text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select p.ativo and not p.deve_trocar_senha and p_atribuicao = any(p.atribuicoes)
                   from public.perfis p where p.id = auth.uid()), false)
$$;

create function public.lider_de(p_ministerio uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.perfil_ativo() and exists (
    select 1 from public.perfis p
    join public.ministerio_membros mm on mm.pessoa_id = p.pessoa_id
    where p.id = auth.uid() and p.perfil in ('MASTER','LIDER')
      and mm.ministerio_id = p_ministerio and mm.funcao = 'lider' and mm.ativo)
$$;

create function public.membro_de(p_ministerio uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.perfil_ativo() and exists (
    select 1 from public.perfis p
    join public.ministerio_membros mm on mm.pessoa_id = p.pessoa_id
    where p.id = auth.uid() and mm.ministerio_id = p_ministerio and mm.ativo)
$$;

-- Ator usado na auditoria: usuário logado ou, nas funções de servidor,
-- o ator informado por set_config('app.ator', ...).
create function public.ator_atual() returns uuid
language sql stable set search_path = '' as $$
  select coalesce(auth.uid(), nullif(current_setting('app.ator', true), '')::uuid)
$$;

-- ---------------------------------------------------------------------
-- 3. Gatilhos: data de atualização, auditoria e regras de proteção
-- ---------------------------------------------------------------------

create function public.tg_atualizado_em() returns trigger
language plpgsql set search_path = '' as $$
begin new.atualizado_em := now(); return new; end $$;

create trigger pessoas_atualizado_em before update on public.pessoas
  for each row execute function public.tg_atualizado_em();
create trigger perfis_atualizado_em before update on public.perfis
  for each row execute function public.tg_atualizado_em();
create trigger ministerios_atualizado_em before update on public.ministerios
  for each row execute function public.tg_atualizado_em();
create trigger ministerio_membros_atualizado_em before update on public.ministerio_membros
  for each row execute function public.tg_atualizado_em();

create function public.tg_auditar() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_antes jsonb; v_depois jsonb; v_id text;
begin
  if tg_op in ('UPDATE','DELETE') then v_antes := to_jsonb(old); end if;
  if tg_op in ('INSERT','UPDATE') then v_depois := to_jsonb(new); end if;
  if tg_op = 'UPDATE' and v_antes - 'atualizado_em' = v_depois - 'atualizado_em' then
    return new;  -- nada mudou de fato
  end if;
  v_id := coalesce(v_depois ->> 'id', v_antes ->> 'id', v_depois ->> 'chave', v_antes ->> 'chave');
  insert into public.auditoria (ator, acao, tabela, registro, antes, depois)
  values (public.ator_atual(), lower(tg_op), tg_table_name, v_id, v_antes, v_depois);
  return coalesce(new, old);
end $$;

create trigger pessoas_auditoria after insert or update or delete on public.pessoas
  for each row execute function public.tg_auditar();
create trigger perfis_auditoria after insert or update or delete on public.perfis
  for each row execute function public.tg_auditar();
create trigger ministerios_auditoria after insert or update or delete on public.ministerios
  for each row execute function public.tg_auditar();
create trigger ministerio_membros_auditoria after insert or update or delete on public.ministerio_membros
  for each row execute function public.tg_auditar();
create trigger solicitacoes_auditoria after insert or update or delete on public.solicitacoes
  for each row execute function public.tg_auditar();
create trigger configuracoes_auditoria after insert or update or delete on public.configuracoes
  for each row execute function public.tg_auditar();

-- A auditoria não pode ser alterada nem apagada
create function public.tg_auditoria_imutavel() returns trigger
language plpgsql set search_path = '' as $$
begin raise exception 'O histórico administrativo não pode ser alterado nem excluído.'; end $$;
create trigger auditoria_imutavel before update or delete on public.auditoria
  for each row execute function public.tg_auditoria_imutavel();

-- Sempre deve existir ao menos um MASTER ativo
create function public.tg_garantir_master() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.perfil = 'MASTER' and old.ativo
     and (new.perfil <> 'MASTER' or not new.ativo)
     and not exists (select 1 from public.perfis p
                     where p.id <> old.id and p.perfil = 'MASTER' and p.ativo) then
    raise exception 'Não é possível remover o último MASTER ativo.';
  end if;
  return new;
end $$;
create trigger perfis_garantir_master before update on public.perfis
  for each row execute function public.tg_garantir_master();

-- Troca de senha: quando a própria pessoa troca a senha no Auth
-- (primeiro acesso ou recuperação), a senha temporária deixa de valer.
create function public.tg_senha_alterada() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.perfis
     set deve_trocar_senha = false, senha_alterada_em = now()
   where id = new.id and deve_trocar_senha;
  return new;
end $$;
create trigger betel_senha_alterada
  after update of encrypted_password on auth.users
  for each row when (old.encrypted_password is distinct from new.encrypted_password)
  execute function public.tg_senha_alterada();

-- ---------------------------------------------------------------------
-- 4. RLS: ligado em todas as tabelas novas.
--    Leitura direta só onde necessário; toda escrita passa por funções.
-- ---------------------------------------------------------------------

alter table public.pessoas            enable row level security;
alter table public.perfis             enable row level security;
alter table public.ministerios        enable row level security;
alter table public.ministerio_membros enable row level security;
alter table public.solicitacoes       enable row level security;
alter table public.configuracoes      enable row level security;
alter table public.auditoria          enable row level security;

revoke all on public.pessoas, public.perfis, public.ministerios, public.ministerio_membros,
              public.solicitacoes, public.configuracoes, public.auditoria
  from anon, authenticated;

grant select on public.ministerios to anon, authenticated;
grant select on public.pessoas, public.perfis, public.ministerio_membros,
                public.solicitacoes, public.auditoria to authenticated;
grant select on public.configuracoes to anon, authenticated;

create policy ministerios_leitura on public.ministerios for select to anon, authenticated
  using (ativo or public.e_master());

create policy pessoas_leitura on public.pessoas for select to authenticated
  using (id = public.minha_pessoa_id() or public.e_master()
         or public.tem_atribuicao('SECRETARIA')
         or exists (select 1 from public.ministerio_membros mm
                    where mm.pessoa_id = pessoas.id and mm.ativo and public.lider_de(mm.ministerio_id)));

create policy perfis_leitura on public.perfis for select to authenticated
  using (id = auth.uid() or public.e_master());

create policy ministerio_membros_leitura on public.ministerio_membros for select to authenticated
  using (pessoa_id = public.minha_pessoa_id() or public.e_master()
         or public.membro_de(ministerio_id));

create policy solicitacoes_leitura on public.solicitacoes for select to authenticated
  using (public.e_master());

create policy auditoria_leitura on public.auditoria for select to authenticated
  using (public.e_master());

create policy configuracoes_leitura on public.configuracoes for select to anon, authenticated
  using (publico or public.perfil_ativo());

-- ---------------------------------------------------------------------
-- 5. Funções da Área da Equipe
-- ---------------------------------------------------------------------

-- Normalização
create function public.so_digitos(p text) returns text
language sql immutable set search_path = '' as $$ select regexp_replace(coalesce(p,''), '\D', '', 'g') $$;

create function public.slugify(p text) returns text
language sql immutable set search_path = '' as $$
  select trim(both '-' from regexp_replace(lower(translate(coalesce(p,''),
    'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
    'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')), '[^a-z0-9]+', '-', 'g'))
$$;

-- 5.1 Solicitar acesso (público)
create function public.solicitar_acesso(
  p_nome text, p_telefone text, p_email text, p_ministerio uuid, p_funcao text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
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
end $$;

-- 5.2 Painel: dados da própria conta
create function public.meu_painel() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

-- 5.3 Minha equipe: membros dos ministérios onde a pessoa serve
--     (líder vê telefone e e-mail; voluntário vê só nome e função)
create function public.minha_equipe() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

-- 5.4 MASTER: solicitações
create function public.listar_solicitacoes(p_status text default 'pendente') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.recusar_solicitacao(p_solicitacao uuid, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.e_master() then raise exception 'Somente o MASTER pode recusar solicitações.' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p_motivo,''))) < 3 then raise exception 'Informe o motivo da recusa.' using errcode = '22023'; end if;
  update public.solicitacoes set status = 'recusada', analisado_por = auth.uid(), analisado_em = now(), motivo = btrim(p_motivo)
   where id = p_solicitacao and tipo = 'acesso' and status = 'pendente';
  if not found then raise exception 'Solicitação não encontrada ou já analisada.' using errcode = 'P0002'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- 5.5 Serviço (só a função de servidor, com a chave de serviço):
--     cria pessoa + perfil + vínculos para uma conta já criada no Auth.
create function public.servico_criar_usuario(
  p_ator uuid, p_usuario uuid, p_nome text, p_telefone text, p_email text,
  p_perfil text, p_atribuicoes text[], p_ministerios jsonb, p_solicitacao uuid default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- 5.6 Serviço: marca senha temporária (após o MASTER gerar uma nova)
create function public.servico_marcar_senha_temporaria(p_ator uuid, p_usuario uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.e_master_uid(p_ator) then raise exception 'Somente o MASTER pode gerar senha temporária.' using errcode = '42501'; end if;
  perform set_config('app.ator', p_ator::text, true);
  update public.perfis set deve_trocar_senha = true where id = p_usuario;
  if not found then raise exception 'Usuário não encontrado.' using errcode = 'P0002'; end if;
  insert into public.auditoria (ator, acao, tabela, registro) values (p_ator, 'senha_temporaria_gerada', 'perfis', p_usuario::text);
  return jsonb_build_object('ok', true);
end $$;

-- 5.7 Serviço: ativar / desativar conta (a função de servidor também bloqueia o login no Auth)
create function public.servico_definir_ativo(p_ator uuid, p_usuario uuid, p_ativo boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.e_master_uid(p_ator) then raise exception 'Somente o MASTER pode ativar ou desativar contas.' using errcode = '42501'; end if;
  if p_ator = p_usuario and not p_ativo then raise exception 'Você não pode desativar a sua própria conta.' using errcode = '22023'; end if;
  perform set_config('app.ator', p_ator::text, true);
  update public.perfis set ativo = p_ativo where id = p_usuario;
  if not found then raise exception 'Usuário não encontrado.' using errcode = 'P0002'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- 5.8 MASTER: usuários
create function public.listar_usuarios() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.admin_atualizar_usuario(
  p_usuario uuid, p_perfil text, p_atribuicoes text[], p_ministerios jsonb
) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- 5.9 MASTER: ministérios
create function public.admin_salvar_ministerio(
  p_id uuid, p_nome text, p_descricao text, p_ordem integer, p_ativo boolean
) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- 5.10 MASTER: histórico administrativo
create function public.listar_auditoria(p_limite integer default 100, p_antes_de bigint default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

-- ---------------------------------------------------------------------
-- 6. Permissões de execução: nada é público por padrão
-- ---------------------------------------------------------------------
-- Revoga só das funções criadas nesta migração (não mexe em funções existentes)
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = any (array[
             'minha_pessoa_id','perfil_ativo','e_master_uid','e_master','tem_atribuicao','lider_de','membro_de',
             'ator_atual','tg_atualizado_em','tg_auditar','tg_auditoria_imutavel','tg_garantir_master','tg_senha_alterada',
             'so_digitos','slugify','solicitar_acesso','meu_painel','minha_equipe','listar_solicitacoes','recusar_solicitacao',
             'servico_criar_usuario','servico_marcar_senha_temporaria','servico_definir_ativo','listar_usuarios',
             'admin_atualizar_usuario','admin_salvar_ministerio','listar_auditoria'])
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;

grant execute on function public.solicitar_acesso(text, text, text, uuid, text) to anon, authenticated;
grant execute on function public.meu_painel()                                   to authenticated;
grant execute on function public.minha_equipe()                                 to authenticated;
grant execute on function public.listar_solicitacoes(text)                      to authenticated;
grant execute on function public.recusar_solicitacao(uuid, text)                to authenticated;
grant execute on function public.listar_usuarios()                              to authenticated;
grant execute on function public.admin_atualizar_usuario(uuid, text, text[], jsonb) to authenticated;
grant execute on function public.admin_salvar_ministerio(uuid, text, text, integer, boolean) to authenticated;
grant execute on function public.listar_auditoria(integer, bigint)              to authenticated;
-- Usadas pelas políticas de RLS
grant execute on function public.minha_pessoa_id(), public.perfil_ativo(), public.e_master(),
                          public.tem_atribuicao(text), public.lider_de(uuid), public.membro_de(uuid)
  to anon, authenticated;
-- Somente as funções de servidor (chave de serviço)
grant execute on function public.servico_criar_usuario(uuid, uuid, text, text, text, text, text[], jsonb, uuid),
                          public.servico_marcar_senha_temporaria(uuid, uuid),
                          public.servico_definir_ativo(uuid, uuid, boolean),
                          public.e_master_uid(uuid)
  to service_role;

-- ---------------------------------------------------------------------
-- 7. Dados iniciais: ministérios (hoje fixos no código do site)
-- ---------------------------------------------------------------------
insert into public.ministerios (nome, slug, ordem) values
  ('Louvor','louvor',1), ('Mídia','midia',2), ('Diaconia','diaconia',3),
  ('Juventude Mergulhados','juventude-mergulhados',4), ('Kids','kids',5), ('EBD','ebd',6),
  ('Secretaria','secretaria',7), ('Células','celulas',8), ('Homens Betel','homens-betel',9),
  ('Mulheres Betel','mulheres-betel',10), ('Escola de Artes','escola-de-artes',11), ('Colégio','colegio',12);

commit;
insert into sistema.migracoes (nome) values ('20261121000100_m01_nucleo_autenticacao');
\else
\echo 'Já aplicada: 20261121000100_m01_nucleo_autenticacao'
\endif

-- ---------------------------------------------------------------------
-- 20261121000200_m02_agenda_colunas
select not exists (select 1 from sistema.migracoes where nome = '20261121000200_m02_agenda_colunas') as fazer \gset
\if :fazer
\echo 'Aplicando 20261121000200_m02_agenda_colunas'
-- =====================================================================
-- M02 — Agenda: colunas novas e opcionais nas tabelas existentes
-- Não renomeia, não exclui e não altera nenhuma coluna existente.
-- As colunas atuais (e os seus dados) continuam exatamente como estão.
-- Para desfazer: 20261121000200_m02_agenda_colunas.down.sql
-- =====================================================================
begin;

alter table public.eventos
  add column if not exists ministerio_id  uuid references public.ministerios(id),
  add column if not exists criado_por     uuid references auth.users(id),
  add column if not exists atualizado_por uuid references auth.users(id);

alter table public.reservas
  add column if not exists ministerio_id uuid references public.ministerios(id),
  add column if not exists criado_por    uuid references auth.users(id),
  add column if not exists criado_em     timestamptz;          -- vazio nas linhas antigas
alter table public.reservas alter column criado_em set default now();  -- preenchido nas novas

alter table public.coordenadores
  add column if not exists usuario_id uuid unique references auth.users(id),
  add column if not exists migrado_em timestamptz;

-- Liga o texto do ministério (que continua existindo) ao cadastro de ministérios.
-- Regra: nome igual ao do cadastro, ou início único do nome (ex.: "Juventude" → "Juventude Mergulhados").
create or replace function public.agenda_ministerio_por_nome(p_nome text) returns uuid
language sql stable security definer set search_path = '' as $$
  with alvo as (select public.slugify(p_nome) as s)
  select coalesce(
    (select m.id from public.ministerios m, alvo where m.slug = alvo.s and alvo.s <> ''),
    (select min(m.id::text)::uuid from public.ministerios m, alvo
      where alvo.s <> '' and m.slug like alvo.s || '-%'
      having count(*) = 1))
$$;
revoke execute on function public.agenda_ministerio_por_nome(text) from public, anon, authenticated;

update public.eventos  set ministerio_id = public.agenda_ministerio_por_nome(ministerio) where ministerio_id is null and ministerio is not null;
update public.reservas set ministerio_id = public.agenda_ministerio_por_nome(ministerio) where ministerio_id is null and ministerio is not null;

insert into public.auditoria (acao, tabela, detalhes)
select 'agenda_ministerios_vinculados', 'eventos', jsonb_build_object(
  'eventos_vinculados', (select count(*) from public.eventos where ministerio_id is not null),
  'eventos_sem_vinculo', (select coalesce(jsonb_agg(distinct coalesce(ministerio, '(vazio)')), '[]') from public.eventos where ministerio_id is null),
  'reservas_vinculadas', (select count(*) from public.reservas where ministerio_id is not null),
  'reservas_sem_vinculo', (select coalesce(jsonb_agg(distinct coalesce(ministerio, '(vazio)')), '[]') from public.reservas where ministerio_id is null));

commit;
insert into sistema.migracoes (nome) values ('20261121000200_m02_agenda_colunas');
\else
\echo 'Já aplicada: 20261121000200_m02_agenda_colunas'
\endif

-- ---------------------------------------------------------------------
-- 20261121000300_m03_agenda_seguranca
select not exists (select 1 from sistema.migracoes where nome = '20261121000300_m03_agenda_seguranca') as fazer \gset
\if :fazer
\echo 'Aplicando 20261121000300_m03_agenda_seguranca'
-- =====================================================================
-- M03 — Agenda: segurança (RLS, permissões e coordenadores no login central)
--
-- Antes de mudar qualquer coisa, salva no histórico (tabela auditoria) o estado
-- atual de RLS, políticas e privilégios das três tabelas, para o .down restaurar.
-- Nenhum dado é alterado ou excluído. A coluna coordenadores.senha continua
-- existindo com o mesmo conteúdo, mas fica inacessível pela chave pública.
--
-- ATENÇÃO: publicar junto com a nova página da Agenda. A página antiga deixa de
-- conseguir gravar (era exatamente essa a falha de segurança).
-- =====================================================================
begin;

-- 1. Estado anterior (para o desfazer)
insert into public.auditoria (acao, tabela, detalhes)
select 'agenda_estado_anterior', 'eventos,reservas,coordenadores', jsonb_build_object(
  'rls', (select jsonb_object_agg(c.relname, c.relrowsecurity) from pg_class c
          where c.relnamespace = 'public'::regnamespace and c.relname in ('eventos','reservas','coordenadores')),
  'politicas', (select coalesce(jsonb_agg(jsonb_build_object('tabela', p.tablename, 'nome', p.policyname, 'sql',
          format('create policy %I on public.%I as %s for %s to %s%s%s', p.policyname, p.tablename, p.permissive, p.cmd,
                 (select string_agg(quote_ident(r), ', ') from unnest(p.roles) r),
                 case when p.qual is not null then ' using (' || p.qual || ')' else '' end,
                 case when p.with_check is not null then ' with check (' || p.with_check || ')' else '' end))), '[]'::jsonb)
          from pg_policies p where p.schemaname = 'public' and p.tablename in ('eventos','reservas','coordenadores')),
  'privilegios', (select coalesce(jsonb_agg(jsonb_build_object('tabela', g.table_name, 'papel', g.grantee, 'privilegio', g.privilege_type)), '[]'::jsonb)
          from information_schema.role_table_grants g
          where g.table_schema = 'public' and g.table_name in ('eventos','reservas','coordenadores') and g.grantee in ('anon','authenticated')),
  'privilegios_colunas', (select coalesce(jsonb_agg(jsonb_build_object('tabela', g.table_name, 'coluna', g.column_name, 'papel', g.grantee, 'privilegio', g.privilege_type)), '[]'::jsonb)
          from information_schema.column_privileges g
          where g.table_schema = 'public' and g.table_name in ('eventos','reservas','coordenadores') and g.grantee in ('anon','authenticated')
            and not exists (select 1 from information_schema.role_table_grants t where t.table_schema = 'public' and t.table_name = g.table_name
                            and t.grantee = g.grantee and t.privilege_type = g.privilege_type)));

-- 2. Funções de permissão da Agenda
-- Coordenação = MASTER ou pessoa com conta ligada a um coordenador ativo
create function public.agenda_coordenador() returns boolean
language sql stable security definer set search_path = '' as $$
  select public.perfil_ativo() and (public.e_master() or exists (
    select 1 from public.coordenadores c where c.usuario_id = auth.uid() and c.ativo))
$$;

-- Ficha do evento: coordenação ou líder do ministério do evento
create function public.agenda_pode_editar_ficha(p_ministerio uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.agenda_coordenador() or (p_ministerio is not null and public.lider_de(p_ministerio))
$$;

-- 3. RLS e privilégios
alter table public.eventos       enable row level security;
alter table public.reservas      enable row level security;
alter table public.coordenadores enable row level security;

do $$ declare p record; begin
  for p in select policyname, tablename from pg_policies
           where schemaname = 'public' and tablename in ('eventos','reservas','coordenadores') loop
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

revoke all on public.eventos, public.reservas, public.coordenadores from public, anon, authenticated;
grant select on public.eventos, public.reservas to anon, authenticated;
grant insert, update, delete on public.eventos, public.reservas to authenticated;
-- sequências dos ids (serial ou identity)
do $$ declare s text; begin
  foreach s in array array[pg_get_serial_sequence('public.eventos','id'), pg_get_serial_sequence('public.reservas','id')] loop
    if s is not null then execute format('grant usage, select on sequence %s to authenticated', s); end if;
  end loop;
end $$;

-- Leitura pública da agenda, como hoje
create policy agenda_eventos_leitura  on public.eventos  for select to anon, authenticated using (true);
create policy agenda_reservas_leitura on public.reservas for select to anon, authenticated using (true);
-- Criar, mover e excluir: coordenação
create policy agenda_eventos_inserir on public.eventos for insert to authenticated with check (public.agenda_coordenador());
create policy agenda_eventos_excluir on public.eventos for delete to authenticated using (public.agenda_coordenador());
-- Atualizar: coordenação (tudo) ou líder do ministério (só a ficha; regras na M04)
create policy agenda_eventos_atualizar on public.eventos for update to authenticated
  using (public.agenda_pode_editar_ficha(ministerio_id)) with check (public.agenda_pode_editar_ficha(ministerio_id));
create policy agenda_reservas_inserir   on public.reservas for insert to authenticated with check (public.agenda_coordenador());
create policy agenda_reservas_atualizar on public.reservas for update to authenticated using (public.agenda_coordenador()) with check (public.agenda_coordenador());
create policy agenda_reservas_excluir   on public.reservas for delete to authenticated using (public.agenda_coordenador());
-- coordenadores: nenhum acesso direto (só pelas funções abaixo, que nunca devolvem a senha)

-- 4. Funções da Agenda
create function public.agenda_minhas_permissoes() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.agenda_listar_coordenadores() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.e_master() then raise exception 'Somente o MASTER gerencia coordenadores.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id::text, 'nome', c.nome, 'login', c.login, 'ativo', c.ativo, 'usuario_id', c.usuario_id, 'migrado_em', c.migrado_em,
      'usuario_nome', pe.nome, 'usuario_email', pe.email, 'eu', c.usuario_id = auth.uid()) order by c.id)
    from public.coordenadores c left join public.perfis pf on pf.id = c.usuario_id left join public.pessoas pe on pe.id = pf.pessoa_id), '[]'::jsonb);
end $$;

-- Torna uma conta da equipe coordenadora (ou reativa). Se a conta já está ligada a um
-- coordenador, só reativa; senão cria a linha (login = e-mail; sem senha própria).
create function public.agenda_definir_coordenador(p_usuario uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- Liga um coordenador antigo (login e senha próprios) a uma conta do login central
create function public.agenda_vincular_coordenador(p_coordenador text, p_usuario uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- Ativa / desativa (substitui a antiga exclusão: o registro é mantido)
create function public.agenda_status_coordenador(p_coordenador text, p_ativo boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.e_master() then raise exception 'Somente o MASTER gerencia coordenadores.' using errcode = '42501'; end if;
  update public.coordenadores set ativo = p_ativo where id::text = p_coordenador;
  if not found then raise exception 'Coordenador não encontrado.' using errcode = 'P0002'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- 5. Execução
revoke execute on function public.agenda_coordenador(), public.agenda_pode_editar_ficha(uuid),
  public.agenda_minhas_permissoes(), public.agenda_listar_coordenadores(), public.agenda_definir_coordenador(uuid),
  public.agenda_vincular_coordenador(text, uuid), public.agenda_status_coordenador(text, boolean) from public, anon, authenticated;
grant execute on function public.agenda_coordenador(), public.agenda_pode_editar_ficha(uuid) to anon, authenticated;
grant execute on function public.agenda_minhas_permissoes(), public.agenda_listar_coordenadores(), public.agenda_definir_coordenador(uuid),
  public.agenda_vincular_coordenador(text, uuid), public.agenda_status_coordenador(text, boolean) to authenticated;

commit;
insert into sistema.migracoes (nome) values ('20261121000300_m03_agenda_seguranca');
\else
\echo 'Já aplicada: 20261121000300_m03_agenda_seguranca'
\endif

-- ---------------------------------------------------------------------
-- 20261121000400_m04_agenda_regras
select not exists (select 1 from sistema.migracoes where nome = '20261121000400_m04_agenda_regras') as fazer \gset
\if :fazer
\echo 'Aplicando 20261121000400_m04_agenda_regras'
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
insert into sistema.migracoes (nome) values ('20261121000400_m04_agenda_regras');
\else
\echo 'Já aplicada: 20261121000400_m04_agenda_regras'
\endif

-- ---------------------------------------------------------------------
-- 20261121000500_m05_cursos_inscricoes
select not exists (select 1 from sistema.migracoes where nome = '20261121000500_m05_cursos_inscricoes') as fazer \gset
\if :fazer
\echo 'Aplicando 20261121000500_m05_cursos_inscricoes'
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
insert into sistema.migracoes (nome) values ('20261121000500_m05_cursos_inscricoes');
\else
\echo 'Já aplicada: 20261121000500_m05_cursos_inscricoes'
\endif

-- ---------------------------------------------------------------------
-- 20261121000600_m06_secretaria_tesouraria
select not exists (select 1 from sistema.migracoes where nome = '20261121000600_m06_secretaria_tesouraria') as fazer \gset
\if :fazer
\echo 'Aplicando 20261121000600_m06_secretaria_tesouraria'
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
insert into sistema.migracoes (nome) values ('20261121000600_m06_secretaria_tesouraria');
\else
\echo 'Já aplicada: 20261121000600_m06_secretaria_tesouraria'
\endif

-- ---------------------------------------------------------------------
-- 20261121000700_m07_membros_voluntarios_termos
select not exists (select 1 from sistema.migracoes where nome = '20261121000700_m07_membros_voluntarios_termos') as fazer \gset
\if :fazer
\echo 'Aplicando 20261121000700_m07_membros_voluntarios_termos'
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
insert into sistema.migracoes (nome) values ('20261121000700_m07_membros_voluntarios_termos');
\else
\echo 'Já aplicada: 20261121000700_m07_membros_voluntarios_termos'
\endif

-- ---------------------------------------------------------------------
-- 20261121000800_m08_certificados_cerimonias
select not exists (select 1 from sistema.migracoes where nome = '20261121000800_m08_certificados_cerimonias') as fazer \gset
\if :fazer
\echo 'Aplicando 20261121000800_m08_certificados_cerimonias'
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
insert into sistema.migracoes (nome) values ('20261121000800_m08_certificados_cerimonias');
\else
\echo 'Já aplicada: 20261121000800_m08_certificados_cerimonias'
\endif

-- ---------------------------------------------------------------------
-- 20261121000900_m09_midia_escalas
select not exists (select 1 from sistema.migracoes where nome = '20261121000900_m09_midia_escalas') as fazer \gset
\if :fazer
\echo 'Aplicando 20261121000900_m09_midia_escalas'
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
insert into sistema.migracoes (nome) values ('20261121000900_m09_midia_escalas');
\else
\echo 'Já aplicada: 20261121000900_m09_midia_escalas'
\endif

-- ---------------------------------------------------------------------
-- 20261121001000_m10_homologacao_reforcos
select not exists (select 1 from sistema.migracoes where nome = '20261121001000_m10_homologacao_reforcos') as fazer \gset
\if :fazer
\echo 'Aplicando 20261121001000_m10_homologacao_reforcos'
-- =====================================================================
-- M10 — Reforços da homologação (aditiva e reversível)
-- Limite de volume nos formulários públicos (sem login), contra robôs que
-- lotariam vagas ou encheriam a Secretaria de cadastros falsos.
-- Não usa IP nem nada do aparelho: conta só os registros feitos sem login.
-- Os limites ficam em configuracoes (chave limites_publicos) e podem ser ajustados.
-- =====================================================================
begin;

insert into public.configuracoes (chave, valor, publico)
values ('limites_publicos', '{"inscricoes_por_pessoa_hora": 3, "inscricoes_10min": 60, "membresia_10min": 20}', false)
on conflict (chave) do nothing;

create function public.limite_publico(p_chave text, p_padrao int) returns int
language sql stable security definer set search_path = '' as $$
  select coalesce((select (valor->>p_chave)::int from public.configuracoes where chave = 'limites_publicos'), p_padrao)
$$;

create function public.tg_limite_publico() returns trigger language plpgsql security definer set search_path = '' as $$
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

create trigger inscricoes_limite_publico before insert on public.inscricoes for each row execute function public.tg_limite_publico();
create trigger membresia_limite_publico before insert on public.membresia_processos for each row execute function public.tg_limite_publico();

revoke execute on function public.limite_publico(text, int), public.tg_limite_publico() from public, anon, authenticated;

commit;
insert into sistema.migracoes (nome) values ('20261121001000_m10_homologacao_reforcos');
\else
\echo 'Já aplicada: 20261121001000_m10_homologacao_reforcos'
\endif

-- ---------------------------------------------------------------------
-- 20261121001100_m11_meu_perfil
select not exists (select 1 from sistema.migracoes where nome = '20261121001100_m11_meu_perfil') as fazer \gset
\if :fazer
\echo 'Aplicando 20261121001100_m11_meu_perfil'
-- =====================================================================
-- M11 — Meu perfil (aditiva e reversível)
-- Leitura do próprio cadastro e edição apenas do próprio telefone.
-- Nome, e-mail, perfil de acesso, atribuições e ministérios continuam
-- editáveis só pelo MASTER (funções admin_* já existentes).
-- Não cria nem altera tabelas. A alteração do telefone fica registrada
-- na auditoria pelo gatilho que já existe em public.pessoas.
-- =====================================================================
begin;

create function public.meu_perfil() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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
    'ministerios', coalesce((select jsonb_agg(jsonb_build_object('nome', m.nome, 'funcao', mm.funcao, 'desde', mm.desde) order by m.ordem, m.nome)
                             from public.ministerio_membros mm join public.ministerios m on m.id = mm.ministerio_id
                             where mm.pessoa_id = v_p.pessoa_id and mm.ativo), '[]'::jsonb),
    'editaveis', jsonb_build_array('telefone'));
end $$;

create function public.meu_perfil_atualizar(p_telefone text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_tel text := public.so_digitos(p_telefone); v_pessoa uuid;
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  if v_tel !~ '^[0-9]{10,11}$' then
    raise exception 'Informe um telefone válido, com DDD.' using errcode = '22023'; end if;
  select pessoa_id into v_pessoa from public.perfis where id = auth.uid();
  update public.pessoas set telefone = v_tel, atualizado_em = now() where id = v_pessoa;
  return public.meu_perfil();
end $$;

revoke execute on function public.meu_perfil(), public.meu_perfil_atualizar(text) from public, anon;
grant execute on function public.meu_perfil(), public.meu_perfil_atualizar(text) to authenticated;

commit;
insert into sistema.migracoes (nome) values ('20261121001100_m11_meu_perfil');
\else
\echo 'Já aplicada: 20261121001100_m11_meu_perfil'
\endif

-- ---------------------------------------------------------------------
-- 20261121001200_m12_institucional
select not exists (select 1 from sistema.migracoes where nome = '20261121001200_m12_institucional') as fazer \gset
\if :fazer
\echo 'Aplicando 20261121001200_m12_institucional'
-- =====================================================================
-- M12 — Conteúdo institucional, gestão de ministérios, organogramas,
--       foto de perfil, contatos centralizados, Colégio e link privado
--       da Agenda Ministerial.  (aditiva e reversível: ver .down.sql)
--
-- Não renomeia, não exclui e não recria tabelas existentes. Só acrescenta:
--   * colunas novas e opcionais: ministerio_membros.cargo, perfis.foto_*
--   * tabelas novas: ministerio_paginas, organogramas, organograma_nos,
--     colegio_etapas, agenda_links, agenda_envios, agenda_envios_historico,
--     agenda_link_acessos
--   * configurações públicas: site.contatos e site.galeria_home
-- Textos dos ministérios entram como RASCUNHO (não aparecem no site) até
-- a liderança confirmar. Nenhum nome, cargo ou vínculo é inventado: o único
-- nome cadastrado nos organogramas é o informado pela igreja
-- (Pr. Clébio Torres — Presidente e Pastor Sênior).
-- =====================================================================
begin;

-- ---------------------------------------------------------------------
-- 1. Colunas opcionais em tabelas existentes
-- ---------------------------------------------------------------------
alter table public.ministerio_membros add column cargo text check (cargo is null or char_length(btrim(cargo)) between 2 and 80);
alter table public.perfis add column foto_caminho text check (foto_caminho is null or foto_caminho ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$');
alter table public.perfis add column foto_no_organograma boolean not null default false;

-- ---------------------------------------------------------------------
-- 2. Página pública de cada ministério
-- ---------------------------------------------------------------------
create table public.ministerio_paginas (
  ministerio_id       uuid primary key references public.ministerios(id),
  o_que_fazemos       text check (char_length(o_que_fazemos) <= 2000),
  por_que_existimos   text check (char_length(por_que_existimos) <= 2000),
  missao              text check (char_length(missao) <= 2000),
  complemento         text check (char_length(complemento) <= 3000),
  vice_pessoa_id      uuid references public.pessoas(id),
  foto                text check (foto is null or foto ~ '^(img/[a-z0-9._/-]+|site/[a-z0-9-]+/[0-9a-f-]{36}(/[0-9a-f-]{36})?\.(jpg|png|webp))$'),
  foto_alt            text check (char_length(foto_alt) <= 200),
  exibir_publico      boolean not null default true,
  exibir_lider        boolean not null default false,
  textos_confirmados  boolean not null default false,
  confirmados_em      timestamptz,
  confirmados_por     uuid references auth.users(id),
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  atualizado_por      uuid references auth.users(id)
);
create trigger ministerio_paginas_atualizado_em before update on public.ministerio_paginas for each row execute function public.tg_atualizado_em();
create trigger ministerio_paginas_auditoria after insert or update or delete on public.ministerio_paginas for each row execute function public.tg_auditar();
alter table public.ministerio_paginas enable row level security;
create policy ministerio_paginas_leitura on public.ministerio_paginas for select to authenticated
  using (public.e_master() or public.lider_de(ministerio_id));

-- ---------------------------------------------------------------------
-- 3. Organogramas (estrutura aprovada; NÃO concede permissões)
-- ---------------------------------------------------------------------
create table public.organogramas (
  id             uuid primary key default gen_random_uuid(),
  tipo           text not null check (tipo in ('igreja','ministerio','colegio','secretaria','tesouraria')),
  ministerio_id  uuid unique references public.ministerios(id),
  titulo         text not null check (char_length(btrim(titulo)) between 2 and 120),
  descricao      text check (char_length(descricao) <= 1000),
  ordem          integer not null default 0,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  check ((tipo = 'ministerio') = (ministerio_id is not null))
);
create unique index organogramas_tipo_unico on public.organogramas (tipo) where tipo <> 'ministerio';
create trigger organogramas_atualizado_em before update on public.organogramas for each row execute function public.tg_atualizado_em();
create trigger organogramas_auditoria after insert or update or delete on public.organogramas for each row execute function public.tg_auditar();

create table public.organograma_nos (
  id                  uuid primary key default gen_random_uuid(),
  organograma_id      uuid not null references public.organogramas(id),
  pai_id              uuid references public.organograma_nos(id),
  cargo               text not null check (char_length(btrim(cargo)) between 2 and 100),
  pessoa_id           uuid references public.pessoas(id),
  nome_livre          text check (nome_livre is null or char_length(btrim(nome_livre)) between 2 and 120),
  responsabilidades   text check (char_length(responsabilidades) <= 1500),
  procurar_para       text check (char_length(procurar_para) <= 500),
  ordem               integer not null default 0,
  ativo               boolean not null default true,
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  atualizado_por      uuid references auth.users(id),
  check (pai_id is null or pai_id <> id),
  check (not (pessoa_id is not null and nome_livre is not null))
);
create index organograma_nos_org on public.organograma_nos (organograma_id, pai_id, ordem);
create trigger organograma_nos_atualizado_em before update on public.organograma_nos for each row execute function public.tg_atualizado_em();
create trigger organograma_nos_auditoria after insert or update or delete on public.organograma_nos for each row execute function public.tg_auditar();

alter table public.organogramas enable row level security;
alter table public.organograma_nos enable row level security;
create policy organogramas_leitura on public.organogramas for select to authenticated using (public.perfil_ativo());
create policy organograma_nos_leitura on public.organograma_nos for select to authenticated using (public.perfil_ativo());

-- Quem edita: MASTER em todos; líder do ministério no organograma do próprio ministério
create function public.pode_editar_organograma(p_org uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.e_master() or exists (select 1 from public.organogramas o
    where o.id = p_org and o.tipo = 'ministerio' and public.lider_de(o.ministerio_id))
$$;

-- Organograma de ministério criado junto com cada ministério novo
create function public.tg_ministerio_organograma() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.organogramas (tipo, ministerio_id, titulo, ordem) values ('ministerio', new.id, new.nome, 100 + new.ordem)
    on conflict (ministerio_id) do nothing;
  insert into public.ministerio_paginas (ministerio_id) values (new.id) on conflict do nothing;
  return new;
end $$;
create trigger ministerios_organograma after insert on public.ministerios for each row execute function public.tg_ministerio_organograma();

-- ---------------------------------------------------------------------
-- 4. Etapas de ensino do Colégio
-- ---------------------------------------------------------------------
create table public.colegio_etapas (
  id              uuid primary key default gen_random_uuid(),
  slug            text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  titulo          text not null check (char_length(btrim(titulo)) between 2 and 80),
  subtitulo       text check (char_length(subtitulo) <= 160),
  descricao       text not null check (char_length(descricao) <= 4000),
  objetivos       text[] not null default '{}',
  diferenciais    text[] not null default '{}',
  faixa_etaria    text check (char_length(faixa_etaria) <= 120),
  foto            text check (foto is null or foto ~ '^(img/[a-z0-9._/-]+|site/[a-z0-9-]+/[0-9a-f-]{36}(/[0-9a-f-]{36})?\.(jpg|png|webp))$'),
  foto_alt        text check (char_length(foto_alt) <= 200),
  ordem           integer not null default 0,
  ativo           boolean not null default true,
  validado        boolean not null default false,
  validado_em     timestamptz,
  validado_por    uuid references auth.users(id),
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);
create trigger colegio_etapas_atualizado_em before update on public.colegio_etapas for each row execute function public.tg_atualizado_em();
create trigger colegio_etapas_auditoria after insert or update or delete on public.colegio_etapas for each row execute function public.tg_auditar();
alter table public.colegio_etapas enable row level security;
-- o site lê as etapas por site_conteudo_publico(); leitura direta da tabela só para o MASTER
create policy colegio_etapas_leitura on public.colegio_etapas for select to authenticated using (public.e_master());

-- ---------------------------------------------------------------------
-- 5. Link privado da Agenda Ministerial (preenchimento sem login)
-- ---------------------------------------------------------------------
create table public.agenda_links (
  id                    uuid primary key default gen_random_uuid(),
  token_hash            text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  rotulo                text not null check (char_length(btrim(rotulo)) between 2 and 120),
  ministerio_id         uuid references public.ministerios(id),
  titulo_sugerido       text check (char_length(titulo_sugerido) <= 120),
  expira_em             timestamptz not null,
  permite_complemento   boolean not null default true,
  revogado_em           timestamptz,
  revogado_por          uuid references auth.users(id),
  criado_por            uuid references auth.users(id),
  criado_em             timestamptz not null default now(),
  token_trocado_em      timestamptz,
  usos                  integer not null default 0,
  ultimo_uso_em         timestamptz
);
create table public.agenda_envios (
  id             uuid primary key default gen_random_uuid(),
  link_id        uuid not null unique references public.agenda_links(id),
  dados          jsonb not null,
  status         text not null default 'aguardando_analise' check (status in ('aguardando_analise','aprovado','recusado')),
  versao         integer not null default 1,
  enviado_em     timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  decidido_por   uuid references auth.users(id),
  decidido_em    timestamptz,
  motivo         text check (char_length(motivo) <= 500),
  evento_id      bigint
);
create table public.agenda_envios_historico (
  id        bigint generated always as identity primary key,
  envio_id  uuid not null references public.agenda_envios(id),
  quando    timestamptz not null default now(),
  acao      text not null check (acao in ('enviado','complementado','aprovado','recusado')),
  dados     jsonb,
  motivo    text,
  ator      uuid
);
create table public.agenda_link_acessos (
  id       bigint generated always as identity primary key,
  link_id  uuid not null references public.agenda_links(id),
  quando   timestamptz not null default now(),
  acao     text not null check (acao in ('aberto','enviado','complementado','recusado_expirado','recusado_revogado','recusado_bloqueado','recusado_dados'))
);
create index agenda_link_acessos_link on public.agenda_link_acessos (link_id, quando desc);
create trigger agenda_links_auditoria after insert or update or delete on public.agenda_links for each row execute function public.tg_auditar();
alter table public.agenda_links enable row level security;
alter table public.agenda_envios enable row level security;
alter table public.agenda_envios_historico enable row level security;
alter table public.agenda_link_acessos enable row level security;
-- leitura direta só pela coordenação (as telas usam as funções abaixo)
create policy agenda_links_leitura on public.agenda_links for select to authenticated using (public.agenda_coordenador());
create policy agenda_envios_leitura on public.agenda_envios for select to authenticated using (public.agenda_coordenador());
create policy agenda_envios_hist_leitura on public.agenda_envios_historico for select to authenticated using (public.agenda_coordenador());
create policy agenda_link_acessos_leitura on public.agenda_link_acessos for select to authenticated using (public.agenda_coordenador());

-- ---------------------------------------------------------------------
-- 6. Funções auxiliares
-- ---------------------------------------------------------------------
create function public.texto_limpo(p text, p_max integer) returns text
language sql immutable set search_path = '' as $$
  select nullif(left(btrim(regexp_replace(coalesce(p, ''), '[\u0000-\u0008\u000B\u000C\u000E-\u001F]', '', 'g')), p_max), '')
$$;

create function public.foto_url_publica(p_foto text) returns text
language sql immutable set search_path = '' as $$ select p_foto $$;  -- o site monta o endereço (img/... ou site/...)

-- Apaga do armazenamento uma imagem do site que deixou de ser usada
create function public.site_apagar_imagem(p_foto text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_foto like 'site/%' then
    delete from armazenamento.objetos where espaco = 'site' and caminho = substr(p_foto, 6);
  end if;
end $$;

-- Permissões de envio de imagens (usadas pelo servidor de arquivos, com o caminho como parâmetro)
create function public.pode_enviar_imagem_site(p_caminho text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare m text[];
begin
  if not public.perfil_ativo() then return false; end if;
  m := regexp_match(coalesce(p_caminho, ''), '^ministerios/([0-9a-f-]{36})/[0-9a-f-]{36}\.(jpg|png|webp)$');
  if m is not null then return public.e_master() or public.lider_de(m[1]::uuid); end if;
  return public.e_master() and coalesce(p_caminho, '') ~ '^(home|colegio)/[0-9a-f-]{36}\.(jpg|png|webp)$';
end $$;

create function public.pode_enviar_foto_perfil(p_caminho text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.perfil_ativo() and coalesce(p_caminho, '') ~ ('^' || auth.uid()::text || '/[0-9a-f-]{36}\.(jpg|png|webp)$')
$$;

-- Confere se a imagem enviada existe e é imagem (o servidor já conferiu tipo real e tamanho no envio)
create function public.imagem_existe(p_espaco text, p_caminho text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from armazenamento.objetos where espaco = p_espaco and caminho = p_caminho and tipo in ('image/jpeg','image/png','image/webp'))
$$;

-- ---------------------------------------------------------------------
-- 7. Permissões institucionais (para a navegação da Área de Membros)
-- ---------------------------------------------------------------------
create function public.institucional_permissoes() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.perfil_ativo() then return jsonb_build_object('ativo', false); end if;
  return jsonb_build_object('ativo', true, 'master', public.e_master(),
    'agenda_coordenador', public.agenda_coordenador(),
    'ministerios_lider', coalesce((select jsonb_agg(mm.ministerio_id) from public.ministerio_membros mm
       join public.perfis p on p.pessoa_id = mm.pessoa_id
       where p.id = auth.uid() and mm.funcao = 'lider' and mm.ativo and p.perfil in ('MASTER','LIDER')), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------
-- 8. Ministérios: página pública e gestão
-- ---------------------------------------------------------------------
create function public.ministerio_pagina_publica_json(p_m public.ministerios, p_pg public.ministerio_paginas) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', p_m.id, 'slug', p_m.slug, 'nome', p_m.nome, 'descricao', p_m.descricao, 'ordem', p_m.ordem,
    'foto', p_pg.foto, 'foto_alt', p_pg.foto_alt,
    'textos', case when p_pg.textos_confirmados then jsonb_build_object('o_que_fazemos', p_pg.o_que_fazemos,
       'por_que_existimos', p_pg.por_que_existimos, 'missao', p_pg.missao, 'complemento', p_pg.complemento) end,
    'lideres', case when p_pg.exibir_lider then coalesce((select jsonb_agg(pe.nome order by pe.nome) from public.ministerio_membros mm
       join public.pessoas pe on pe.id = mm.pessoa_id where mm.ministerio_id = p_m.id and mm.funcao = 'lider' and mm.ativo), '[]'::jsonb) end)
$$;

create function public.ministerios_publicos() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(public.ministerio_pagina_publica_json(m, pg) order by m.ordem, m.nome), '[]'::jsonb)
  from public.ministerios m join public.ministerio_paginas pg on pg.ministerio_id = m.id
  where m.ativo and pg.exibir_publico
$$;

create function public.ministerio_admin_obter(p_ministerio uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.ministerio_salvar_pagina(p_ministerio uuid, p_dados jsonb, p_publicar boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
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
end $$;

-- Liderança: só o MASTER define (o líder ganha as permissões de líder que já existem no sistema)
create function public.ministerio_definir_lideranca(p_ministerio uuid, p_lideres uuid[], p_vice uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- Integrantes: MASTER ou líder do ministério vinculam voluntários (as regras de voluntariado continuam valendo)
create function public.ministerio_vincular(p_ministerio uuid, p_pessoa uuid, p_cargo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.ministerio_definir_cargo(p_ministerio uuid, p_pessoa uuid, p_cargo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not (public.e_master() or public.lider_de(p_ministerio)) then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  update public.ministerio_membros set cargo = public.texto_limpo(p_cargo, 80) where ministerio_id = p_ministerio and pessoa_id = p_pessoa;
  if not found then raise exception 'Vínculo não encontrado.' using errcode = 'P0002'; end if;
  return public.ministerio_admin_obter(p_ministerio);
end $$;

-- Encerrar vínculo: não apaga a pessoa nem o histórico
create function public.ministerio_desvincular(p_ministerio uuid, p_pessoa uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- Pessoas que podem ser escolhidas (usuários cadastrados; o e-mail só aparece para o MASTER)
create function public.pessoas_para_vinculo(p_busca text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

-- ---------------------------------------------------------------------
-- 9. Organogramas: leitura e edição
-- ---------------------------------------------------------------------
create function public.pessoa_cartao(p_pessoa uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('pessoa_id', pe.id, 'nome', pe.nome,
    'foto', case when p.foto_no_organograma and p.foto_caminho is not null then p.foto_caminho end)
  from public.pessoas pe left join public.perfis p on p.pessoa_id = pe.id where pe.id = p_pessoa
$$;

create function public.organogramas_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'tipo', o.tipo, 'titulo', o.titulo, 'ministerio_id', o.ministerio_id,
       'pode_editar', public.pode_editar_organograma(o.id),
       'nos', (select count(*) from public.organograma_nos n where n.organograma_id = o.id and n.ativo))
       order by case o.tipo when 'igreja' then 0 when 'secretaria' then 1 when 'tesouraria' then 2 when 'colegio' then 3 else 4 end, o.ordem, o.titulo)
     from public.organogramas o left join public.ministerios m on m.id = o.ministerio_id
     where o.tipo <> 'ministerio' or m.ativo), '[]'::jsonb);
end $$;

create function public.organograma_obter(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.organograma_no_salvar(p_org uuid, p_dados jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- Retirar uma função do organograma: os subordinados passam para o superior dela; a pessoa não é apagada
create function public.organograma_no_remover(p_org uuid, p_no uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_pai uuid;
begin
  if not public.pode_editar_organograma(p_org) then raise exception 'Você não pode editar este organograma.' using errcode = '42501'; end if;
  select pai_id into v_pai from public.organograma_nos where id = p_no and organograma_id = p_org and ativo;
  if not found then raise exception 'Função não encontrada.' using errcode = 'P0002'; end if;
  update public.organograma_nos set pai_id = v_pai, atualizado_por = auth.uid() where pai_id = p_no and ativo;
  update public.organograma_nos set ativo = false, atualizado_por = auth.uid() where id = p_no;
  return public.organograma_obter(p_org);
end $$;

create function public.organograma_no_mover(p_org uuid, p_no uuid, p_direcao int) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.organograma_atualizar(p_org uuid, p_titulo text, p_descricao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.pode_editar_organograma(p_org) then raise exception 'Você não pode editar este organograma.' using errcode = '42501'; end if;
  -- o título do organograma de ministério acompanha o nome do ministério; só a descrição muda
  update public.organogramas set titulo = case when tipo = 'ministerio' then titulo else coalesce(public.texto_limpo(p_titulo, 120), titulo) end,
         descricao = public.texto_limpo(p_descricao, 1000)
   where id = p_org;
  return public.organograma_obter(p_org);
end $$;

-- ---------------------------------------------------------------------
-- 10. Foto de perfil
-- ---------------------------------------------------------------------
create function public.meu_perfil_foto(p_caminho text, p_no_organograma boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
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
end $$;

create function public.meu_perfil_foto_remover() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_antiga text;
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  select foto_caminho into v_antiga from public.perfis where id = auth.uid();
  update public.perfis set foto_caminho = null where id = auth.uid();
  if v_antiga is not null then delete from armazenamento.objetos where espaco = 'perfis' and caminho = v_antiga; end if;
  return public.meu_perfil();
end $$;

-- MASTER pode retirar a foto de alguém (ex.: imagem imprópria)
create function public.admin_remover_foto(p_usuario uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_antiga text;
begin
  if not public.e_master() then raise exception 'Somente o MASTER.' using errcode = '42501'; end if;
  select foto_caminho into v_antiga from public.perfis where id = p_usuario;
  update public.perfis set foto_caminho = null where id = p_usuario;
  if v_antiga is not null then delete from armazenamento.objetos where espaco = 'perfis' and caminho = v_antiga; end if;
  return jsonb_build_object('ok', true);
end $$;

-- "Meu perfil" passa a trazer a foto (substitui a função da M11 mantendo os mesmos campos)
create or replace function public.meu_perfil() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

-- ---------------------------------------------------------------------
-- 11. Conteúdo do site: contatos, galeria da Home e Colégio
-- ---------------------------------------------------------------------
create function public.site_conteudo_publico() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'contatos', (select valor from public.configuracoes where chave = 'site.contatos'),
    'galeria_home', (select valor from public.configuracoes where chave = 'site.galeria_home'),
    'colegio_etapas', coalesce((select jsonb_agg(jsonb_build_object('slug', e.slug, 'titulo', e.titulo, 'subtitulo', e.subtitulo,
         'descricao', e.descricao, 'objetivos', to_jsonb(e.objetivos), 'diferenciais', to_jsonb(e.diferenciais),
         'faixa_etaria', e.faixa_etaria, 'foto', e.foto, 'foto_alt', e.foto_alt) order by e.ordem)
       from public.colegio_etapas e where e.ativo), '[]'::jsonb))
$$;

create function public.site_validar_contato(p jsonb, p_campo text, p_tipo text) returns void
language plpgsql immutable set search_path = '' as $$
declare v text := btrim(coalesce(p->>p_campo, ''));
begin
  if v = '' then return; end if;
  if p_tipo = 'telefone' and regexp_replace(v, '\D', '', 'g') !~ '^[0-9]{10,11}$' then
    raise exception 'Telefone inválido em "%": use DDD + número.', p_campo using errcode = '22023'; end if;
  if p_tipo = 'url' and v !~ '^https://[^\s<>"]+$' then raise exception 'Endereço inválido em "%": use https://…', p_campo using errcode = '22023'; end if;
  if p_tipo = 'arroba' and v !~ '^@?[A-Za-z0-9._]{2,60}$' then raise exception 'Perfil inválido em "%".', p_campo using errcode = '22023'; end if;
  if p_tipo = 'email' and v !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'E-mail inválido em "%".', p_campo using errcode = '22023'; end if;
end $$;

create function public.site_salvar_contatos(p_contatos jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.site_salvar_galeria(p_fotos jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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
end $$;

create function public.colegio_etapas_admin() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.e_master() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(e) - 'criado_em' order by e.ordem) from public.colegio_etapas e), '[]'::jsonb);
end $$;

create function public.colegio_etapa_salvar(p_id uuid, p_dados jsonb, p_validado boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
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
end $$;

-- ---------------------------------------------------------------------
-- 12. Link privado da Agenda: geração, uso público e revisão
-- ---------------------------------------------------------------------
create function public.agenda_token_hash(p_token text) returns text
language sql immutable set search_path = '' as $$ select encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex') $$;

create function public.agenda_novo_token() returns text
language sql volatile set search_path = '' as $$
  -- 2 UUIDs aleatórios (gerador criptográfico do PostgreSQL) = 244 bits; nada sequencial
  select replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')
$$;

create function public.agenda_link_criar(p_rotulo text, p_ministerio uuid, p_titulo text, p_dias integer, p_permite_complemento boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.agenda_link_novo_token(p_link uuid, p_dias integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.agenda_link_revogar(p_link uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.agenda_coordenador() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  update public.agenda_links set revogado_em = now(), revogado_por = auth.uid() where id = p_link and revogado_em is null;
  if not found then raise exception 'Link não encontrado ou já revogado.' using errcode = 'P0002'; end if;
  return jsonb_build_object('ok', true);
end $$;

create function public.agenda_links_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

create function public.agenda_envios_listar(p_status text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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

-- Valida e normaliza os dados do formulário (mesmos campos da ficha da Agenda)
create function public.agenda_validar_ficha(p jsonb, p_ministerio_fixo text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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
end $$;

-- Situação do link (uso interno): devolve o link válido ou o motivo da recusa
create function public.agenda_link_valido(p_token text, out link public.agenda_links, out motivo text)
language plpgsql security definer set search_path = '' as $$
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
end $$;

create function public.agenda_link_abrir(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

create function public.agenda_link_enviar(p_token text, p_dados jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- Revisão: aprovar cria um NOVO evento na Agenda (nunca altera um existente); recusar guarda o motivo
create function public.agenda_envio_decidir(p_envio uuid, p_decisao text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- ---------------------------------------------------------------------
-- 13. Privilégios
-- ---------------------------------------------------------------------
revoke execute on function public.pode_editar_organograma(uuid), public.tg_ministerio_organograma(), public.texto_limpo(text, integer),
  public.foto_url_publica(text), public.site_apagar_imagem(text), public.pode_enviar_imagem_site(text), public.pode_enviar_foto_perfil(text),
  public.imagem_existe(text, text), public.institucional_permissoes(), public.ministerio_pagina_publica_json(public.ministerios, public.ministerio_paginas),
  public.ministerios_publicos(), public.ministerio_admin_obter(uuid), public.ministerio_salvar_pagina(uuid, jsonb, boolean),
  public.ministerio_definir_lideranca(uuid, uuid[], uuid), public.ministerio_vincular(uuid, uuid, text), public.ministerio_definir_cargo(uuid, uuid, text),
  public.ministerio_desvincular(uuid, uuid), public.pessoas_para_vinculo(text), public.pessoa_cartao(uuid), public.organogramas_listar(),
  public.organograma_obter(uuid), public.organograma_no_salvar(uuid, jsonb), public.organograma_no_remover(uuid, uuid), public.organograma_no_mover(uuid, uuid, integer),
  public.organograma_atualizar(uuid, text, text), public.meu_perfil_foto(text, boolean), public.meu_perfil_foto_remover(), public.admin_remover_foto(uuid),
  public.site_conteudo_publico(), public.site_validar_contato(jsonb, text, text), public.site_salvar_contatos(jsonb), public.site_salvar_galeria(jsonb),
  public.colegio_etapas_admin(), public.colegio_etapa_salvar(uuid, jsonb, boolean), public.agenda_token_hash(text), public.agenda_novo_token(),
  public.agenda_link_criar(text, uuid, text, integer, boolean), public.agenda_link_novo_token(uuid, integer), public.agenda_link_revogar(uuid),
  public.agenda_links_listar(), public.agenda_envios_listar(text), public.agenda_validar_ficha(jsonb, text), public.agenda_link_valido(text),
  public.agenda_link_abrir(text), public.agenda_link_enviar(text, jsonb), public.agenda_envio_decidir(uuid, text, text)
  from public, anon, authenticated;

-- visitantes (sem login)
grant execute on function public.ministerios_publicos(), public.site_conteudo_publico(),
  public.agenda_link_abrir(text), public.agenda_link_enviar(text, jsonb) to anon, authenticated;
-- usuários logados (cada função confere a permissão por dentro)
grant execute on function public.institucional_permissoes(), public.pode_enviar_imagem_site(text), public.pode_enviar_foto_perfil(text),
  public.ministerio_admin_obter(uuid), public.ministerio_salvar_pagina(uuid, jsonb, boolean), public.ministerio_definir_lideranca(uuid, uuid[], uuid),
  public.ministerio_vincular(uuid, uuid, text), public.ministerio_definir_cargo(uuid, uuid, text), public.ministerio_desvincular(uuid, uuid),
  public.pessoas_para_vinculo(text), public.organogramas_listar(), public.organograma_obter(uuid), public.organograma_no_salvar(uuid, jsonb),
  public.organograma_no_remover(uuid, uuid), public.organograma_no_mover(uuid, uuid, integer), public.organograma_atualizar(uuid, text, text),
  public.meu_perfil_foto(text, boolean), public.meu_perfil_foto_remover(), public.admin_remover_foto(uuid),
  public.site_salvar_contatos(jsonb), public.site_salvar_galeria(jsonb), public.colegio_etapas_admin(), public.colegio_etapa_salvar(uuid, jsonb, boolean),
  public.agenda_link_criar(text, uuid, text, integer, boolean), public.agenda_link_novo_token(uuid, integer), public.agenda_link_revogar(uuid),
  public.agenda_links_listar(), public.agenda_envios_listar(text), public.agenda_envio_decidir(uuid, text, text)
  to authenticated;

-- ---------------------------------------------------------------------
-- 14. Dados iniciais (sem dados pessoais; textos dos ministérios como RASCUNHO)
-- ---------------------------------------------------------------------
-- Contatos: exatamente os que o site já publica hoje
insert into public.configuracoes (chave, valor, publico) values ('site.contatos', jsonb_build_object(
  'igreja', jsonb_build_object('nome', 'Igreja Batista Betel', 'telefone', '(31) 3333-9749', 'whatsapp', '(31) 8408-0257',
     'instagram', 'betelflamengo', 'youtube', '@betelflamengo', 'youtube_url', 'https://www.youtube.com/@betelflamengo',
     'endereco', 'Rua dos Luxemburgueses, 31 · Bairro Flamengo · Contagem/MG', 'cep', '32241-130',
     'mapa', 'Rua dos Luxemburgueses, 31 - Flamengo, Contagem - MG, 32241-130'),
  'celulas', jsonb_build_object('whatsapp', '(31) 99299-7440'),
  'colegio', jsonb_build_object('nome', 'Colégio Batista Betel', 'telefone', '(31) 3361-8686', 'whatsapp', '(31) 99504-6148',
     'email', 'colegiobatistabetel@gmail.com', 'instagram', 'colegiobatistabetelcontagem', 'site', 'https://www.colegiobatistabetel.com.br/',
     'endereco', 'Rua dos Luxemburgueses, 31 · Flamengo · Contagem/MG',
     'mapa', 'Rua dos Luxemburgueses, 31 - Flamengo, Contagem - MG, 32241-130')), true)
on conflict (chave) do nothing;

-- Galeria da Home: fotografias reais da igreja que já fazem parte do site
insert into public.configuracoes (chave, valor, publico) values ('site.galeria_home', '[
  {"foto":"img/galeria/adoracao-maos.jpg","alt":"Irmã em adoração com a mão no peito durante o culto","legenda":"Adoração"},
  {"foto":"img/galeria/jovens-juntos.jpg","alt":"Jovens reunidos e sorrindo no Acampamento Mergulhados","legenda":"Comunhão"},
  {"foto":"img/galeria/oracao-ministracao.jpg","alt":"Irmão orando por outra pessoa ajoelhada no altar","legenda":"Oração"},
  {"foto":"img/galeria/louvor.jpg","alt":"Ministro de louvor cantando no culto","legenda":"Louvor"},
  {"foto":"img/galeria/quebrantamento.jpg","alt":"Irmã emocionada em adoração","legenda":"Presença de Deus"},
  {"foto":"img/galeria/alegria-jovens.jpg","alt":"Jovens sorrindo juntos","legenda":"Alegria"},
  {"foto":"img/galeria/mulheres-oracao.jpg","alt":"Mulheres em oração no Congresso de Mulheres","legenda":"Intercessão"},
  {"foto":"img/galeria/reverencia.jpg","alt":"Irmão em oração e reverência","legenda":"Reverência"}
]'::jsonb, true) on conflict (chave) do nothing;

-- Organogramas: geral, Secretaria, Tesouraria, Colégio e um para cada ministério
insert into public.organogramas (tipo, titulo, descricao, ordem) values
  ('igreja', 'Igreja Batista Betel Flamengo', 'Estrutura de liderança da igreja. Cargos e nomes cadastrados pela administração.', 0),
  ('secretaria', 'Secretaria', 'Funções administrativas da Secretaria, a serem confirmadas pela liderança.', 1),
  ('tesouraria', 'Tesouraria', 'Funções e responsabilidades financeiras, a serem confirmadas pela liderança.', 2),
  ('colegio', 'Colégio Batista Betel', 'Estrutura administrativa e pedagógica, a ser cadastrada pela direção.', 3);
insert into public.organogramas (tipo, ministerio_id, titulo, ordem) select 'ministerio', id, nome, 100 + ordem from public.ministerios
  on conflict (ministerio_id) do nothing;
insert into public.organograma_nos (organograma_id, cargo, nome_livre, ordem)
  select id, 'Presidente e Pastor Sênior', 'Pr. Clébio Torres', 0 from public.organogramas where tipo = 'igreja';

-- Páginas dos ministérios: rascunhos para a liderança revisar (não aparecem no site até serem confirmados)
insert into public.ministerio_paginas (ministerio_id, exibir_publico, foto, foto_alt, o_que_fazemos, por_que_existimos, missao)
select m.id,
  m.slug not in ('secretaria', 'colegio'),
  case m.slug when 'homens-betel' then 'img/homens-adoracao.jpg' when 'mulheres-betel' then 'img/culto-mulheres-adoracao.jpg'
              when 'juventude-mergulhados' then 'img/mergulhados-acamp.jpg' when 'louvor' then 'img/louvor.jpg'
              when 'kids' then 'img/kids-teatro.jpg' when 'ebd' then 'img/jovem-biblia.jpg' when 'celulas' then 'img/oracao.jpg' end,
  case m.slug when 'homens-betel' then 'Irmão em adoração durante o culto' when 'mulheres-betel' then 'Mulheres em adoração no Congresso de Mulheres'
              when 'juventude-mergulhados' then 'Jovens reunidos no Acampamento Mergulhados' when 'louvor' then 'Ministro de louvor durante o culto'
              when 'kids' then 'Teatro de fantoches com as crianças' when 'ebd' then 'Jovem com a Bíblia aberta em oração' when 'celulas' then 'Irmão em oração' end,
  t.o_que, t.por_que, t.missao
from public.ministerios m
left join (values
  ('louvor', 'Conduzimos a igreja em louvor e adoração nos cultos, preparando cada momento com ensaio, oração e cuidado com a música e com as pessoas.',
             'Porque a adoração a Deus está no centro da vida da igreja, e cantar juntos fortalece a fé e une a família da Betel.',
             'Levar a igreja à presença de Deus com excelência e simplicidade, servindo com unidade e vida devocional.'),
  ('midia', 'Registramos e comunicamos a vida da igreja: fotografia, vídeo, transmissões e as artes de divulgação das programações.',
            'Porque o que Deus faz no meio do seu povo merece ser lembrado e anunciado, e a comunicação aproxima quem está perto e quem está longe.',
            'Servir à igreja e à cidade com comunicação de qualidade, respeitando as pessoas e apontando para Cristo.'),
  ('diaconia', 'Cuidamos do acolhimento e do serviço nos cultos e eventos: recepção, organização do espaço e apoio a quem precisa.',
               'Porque servir é seguir o exemplo de Jesus, e cada pessoa que chega à Betel deve se sentir em casa.',
               'Expressar o amor de Deus por meio do cuidado prático, do acolhimento e do serviço fiel.'),
  ('juventude-mergulhados', 'Reunimos a juventude em cultos de jovens, células, acampamento e conferência, para mergulhar na presença de Deus e crescer juntos na fé.',
             'Porque cada geração precisa conhecer Deus pessoalmente e encontrar na igreja um lugar de pertencimento, amizade e propósito.',
             'Formar jovens firmados na identidade de filhos de Deus, chamados como filhos e enviados pelo Pai.'),
  ('kids', 'Ensinamos a fé às crianças com cuidado e linguagem adequada à idade, em momentos de aprendizado, louvor e convivência.',
           'Porque a fé ensinada desde cedo marca a vida, e as famílias contam com a igreja para formar as crianças no caminho do Senhor.',
           'Apresentar Jesus às crianças com amor e segurança, em parceria com as famílias.'),
  ('ebd', 'Promovemos o estudo bíblico aos domingos, com turmas para todas as idades.',
          'Porque conhecer a Palavra de Deus é essencial para uma fé firme, e aprender em comunidade fortalece a caminhada cristã.',
          'Ensinar a Bíblia com fidelidade e clareza, ajudando cada pessoa a aplicar a Palavra no dia a dia.'),
  ('celulas', 'Reunimos a igreja nas casas, em pequenos grupos, para estudar a Palavra, orar e cuidar uns dos outros.',
              'Porque a vida cristã é vivida em comunhão, e nos pequenos grupos ninguém caminha sozinho.',
              'Multiplicar a comunhão e o cuidado mútuo, alcançando famílias e vizinhanças com o amor de Cristo.'),
  ('homens-betel', 'Reunimos homens de todas as idades para se fortalecerem na Palavra, na oração e na amizade.',
                   'Porque homens firmes em Deus servem com amor em casa, na igreja e no trabalho.',
                   'Formar homens comprometidos com Cristo, com a família e com a igreja.'),
  ('mulheres-betel', 'Promovemos congressos, encontros e momentos de comunhão para que as mulheres cresçam na fé e no cuidado umas com as outras.',
                     'Porque as mulheres da Betel se fortalecem juntas e são instrumentos de Deus em suas famílias e na igreja.',
                     'Edificar mulheres na Palavra e na oração, cultivando amizade, cuidado e serviço.'),
  ('escola-de-artes', 'Oferecemos aulas de violão, bateria, hip hop, ballet, teclado e violino.',
                      'Porque a arte é um dom de Deus e uma forma de desenvolver talentos, disciplina e convivência.',
                      'Desenvolver talentos artísticos com propósito, a serviço de Deus e da comunidade.')
) as t(slug, o_que, por_que, missao) on t.slug = m.slug
on conflict (ministerio_id) do nothing;

-- Etapas do Colégio (textos de apresentação; faixa etária e diferenciais ficam para a direção confirmar)
insert into public.colegio_etapas (slug, titulo, subtitulo, descricao, objetivos, foto, foto_alt, ordem) values
('maternal', 'Maternal', 'Os primeiros passos, com acolhimento.',
 'O Maternal é o primeiro contato de muitas crianças com a vida escolar. Por isso, tudo começa pelo acolhimento: um ambiente seguro e afetuoso, uma adaptação feita com calma e uma rotina que dá tranquilidade à criança e à família. Nesta fase, aprender é brincar, explorar e conviver, sempre respeitando o tempo e o jeito de cada um.',
 array['Acolher a criança e a família, com uma adaptação tranquila e respeitosa',
       'Oferecer estímulos sensoriais e motores por meio de brincadeiras e experiências',
       'Incentivar o desenvolvimento da linguagem e da comunicação',
       'Favorecer a interação, a socialização e a construção de vínculos',
       'Estimular a autonomia nas pequenas tarefas do dia a dia',
       'Caminhar em parceria com a família, com cuidado, segurança e afeto'],
 'img/col-01.jpg', 'Aluna com as mãos pintadas fazendo um coração', 1),
('educacao-infantil', 'Educação Infantil', 'Brincar, descobrir e aprender.',
 'Na Educação Infantil, a criança se desenvolve por inteiro: corpo, emoções, linguagem e relações. A aprendizagem acontece por meio de experiências, brincadeiras e descobertas, que despertam a curiosidade e a criatividade e ajudam a criança a conhecer o ambiente e o mundo ao seu redor. É uma etapa fundamental, que prepara com segurança para os anos seguintes.',
 array['Promover o desenvolvimento integral da criança',
       'Aprender por meio de experiências, brincadeiras e investigação',
       'Desenvolver a linguagem oral e a comunicação',
       'Trabalhar a coordenação motora fina e ampla',
       'Estimular a criatividade, a curiosidade e a expressão',
       'Cuidar do desenvolvimento emocional e da convivência com os colegas',
       'Favorecer a descoberta do ambiente e do mundo ao redor'],
 'img/col-03.jpg', 'Aluno sorrindo durante a Festa dos Pais', 2),
('primeiro-segundo-periodos', 'Introdução aos Ensinos — 1º e 2º Períodos', 'Novas experiências, no tempo certo da criança.',
 'O 1º e o 2º Períodos marcam a transição para novas experiências de aprendizagem. A criança amplia o vocabulário, tem os primeiros contatos com a leitura e a escrita e começa a construir noções matemáticas, sempre de acordo com a proposta pedagógica e a faixa etária. A preparação para o Ensino Fundamental é gradual: a aprendizagem respeita o desenvolvimento de cada criança, sem antecipar exigências das etapas seguintes.',
 array['Desenvolver a linguagem e ampliar o vocabulário',
       'Iniciar o contato com a leitura e a escrita, respeitando a faixa etária',
       'Construir noções matemáticas iniciais',
       'Trabalhar a coordenação motora fina e ampla',
       'Fortalecer a socialização, a convivência e a autonomia',
       'Valorizar a curiosidade e a investigação',
       'Preparar, de forma gradual, a chegada ao Ensino Fundamental'],
 'img/colegio-poster.jpg', 'Aluno sorrindo em sala de aula', 3),
('ensino-fundamental', 'Ensino Fundamental', 'Do 1º ao 5º ano, com valores cristãos.',
 'No Ensino Fundamental, a criança consolida a leitura e a escrita, desenvolve o raciocínio lógico e amplia o conhecimento sobre a ciência, a história e o espaço em que vive. Com mais autonomia, aprende a pensar de forma crítica e criativa, a conviver com responsabilidade e a formar valores. É uma etapa de continuidade, que cuida do desenvolvimento acadêmico e pessoal de cada aluno.',
 array['Desenvolver as habilidades de leitura e escrita',
       'Trabalhar a matemática e o raciocínio lógico',
       'Construir conhecimento científico',
       'Compreender a história e a sociedade',
       'Compreender o espaço geográfico',
       'Desenvolver autonomia, pensamento crítico e criatividade',
       'Cultivar a convivência, a responsabilidade e a formação de valores'],
 'img/col-06.jpg', 'Alunos cantando juntos em uma apresentação', 4);

commit;
insert into sistema.migracoes (nome) values ('20261121001200_m12_institucional');
\else
\echo 'Já aplicada: 20261121001200_m12_institucional'
\endif

\echo 'Banco pronto.'
