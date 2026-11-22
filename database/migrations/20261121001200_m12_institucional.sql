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
