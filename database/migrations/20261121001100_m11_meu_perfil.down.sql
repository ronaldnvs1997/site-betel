-- DESFAZER M11 — remove as funções de "Meu perfil". Nenhum dado é apagado.
begin;
drop function if exists public.meu_perfil_atualizar(text);
drop function if exists public.meu_perfil();
commit;
