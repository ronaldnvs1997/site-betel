-- DESFAZER M02 — remove só as colunas que a M02 adicionou. As colunas originais não são tocadas.
-- Rode antes o .down da M04 e da M03, se tiverem sido aplicadas.
begin;
alter table public.eventos  drop column if exists ministerio_id, drop column if exists criado_por, drop column if exists atualizado_por;
alter table public.reservas drop column if exists ministerio_id, drop column if exists criado_por, drop column if exists criado_em;
alter table public.coordenadores drop column if exists usuario_id, drop column if exists migrado_em;
drop function if exists public.agenda_ministerio_por_nome(text);
commit;
