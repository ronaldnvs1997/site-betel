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
