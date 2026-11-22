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
