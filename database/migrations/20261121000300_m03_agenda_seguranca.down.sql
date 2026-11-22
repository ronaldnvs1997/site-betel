-- DESFAZER M03 — volta RLS, políticas e privilégios ao estado salvo antes da M03.
-- ATENÇÃO: isso reabre a falha de segurança da Agenda antiga (chave pública com escrita).
-- Rode antes o .down da M04, se tiver sido aplicada.
begin;
do $$
declare e jsonb; p jsonb; t text;
begin
  select detalhes into e from public.auditoria where acao = 'agenda_estado_anterior' order by id desc limit 1;
  if e is null then raise exception 'Estado anterior da Agenda não encontrado no histórico.'; end if;
  for p in select * from jsonb_array_elements((select coalesce(jsonb_agg(jsonb_build_object('n', policyname, 't', tablename)), '[]')
                                              from pg_policies where schemaname = 'public' and tablename in ('eventos','reservas','coordenadores'))) loop
    execute format('drop policy %I on public.%I', p->>'n', p->>'t');
  end loop;
  revoke all on public.eventos, public.reservas, public.coordenadores from anon, authenticated;
  for t in select * from jsonb_object_keys(e->'rls') loop
    execute format('alter table public.%I %s row level security', t, case when (e->'rls'->>t)::boolean then 'enable' else 'disable' end);
  end loop;
  for p in select * from jsonb_array_elements(e->'politicas') loop execute p->>'sql'; end loop;
  for p in select * from jsonb_array_elements(e->'privilegios') loop
    execute format('grant %s on public.%I to %I', p->>'privilegio', p->>'tabela', p->>'papel');
  end loop;
  for p in select * from jsonb_array_elements(e->'privilegios_colunas') loop
    execute format('grant %s (%I) on public.%I to %I', p->>'privilegio', p->>'coluna', p->>'tabela', p->>'papel');
  end loop;
end $$;
drop function if exists public.agenda_status_coordenador(text, boolean);
drop function if exists public.agenda_vincular_coordenador(text, uuid);
drop function if exists public.agenda_definir_coordenador(uuid);
drop function if exists public.agenda_listar_coordenadores();
drop function if exists public.agenda_minhas_permissoes();
drop function if exists public.agenda_pode_editar_ficha(uuid);
drop function if exists public.agenda_coordenador();
commit;
