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
