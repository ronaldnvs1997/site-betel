-- DESFAZER M04 — remove os gatilhos e funções de regras da Agenda. Dados não são alterados.
begin;
drop trigger if exists agenda_evento_regras on public.eventos;
drop trigger if exists agenda_reserva_regras on public.reservas;
drop trigger if exists eventos_auditoria on public.eventos;
drop trigger if exists reservas_auditoria on public.reservas;
drop trigger if exists coordenadores_auditoria on public.coordenadores;
drop function if exists public.tg_agenda_evento();
drop function if exists public.tg_agenda_reserva();
drop function if exists public.agenda_conflitos(text, text[], integer, integer, text, text);
drop function if exists public.agenda_espacos(text);
drop function if exists public.agenda_faixa_evento(text, text, text);
drop function if exists public.agenda_minutos(text);
commit;
