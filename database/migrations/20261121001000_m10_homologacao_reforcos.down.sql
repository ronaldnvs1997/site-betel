-- DESFAZER M10 — remove os limites de volume dos formulários públicos.
begin;
drop trigger if exists inscricoes_limite_publico on public.inscricoes;
drop trigger if exists membresia_limite_publico on public.membresia_processos;
drop function if exists public.tg_limite_publico();
drop function if exists public.limite_publico(text, int);
delete from public.configuracoes where chave = 'limites_publicos';
commit;
