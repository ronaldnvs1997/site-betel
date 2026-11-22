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
