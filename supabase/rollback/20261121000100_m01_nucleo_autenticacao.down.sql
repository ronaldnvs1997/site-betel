-- =====================================================================
-- DESFAZER M01 — remove somente o que a M01 criou.
-- Não toca em eventos, reservas, coordenadores nem em outras tabelas.
-- ATENÇÃO: antes de rodar, exporte os dados das tabelas abaixo
-- (pessoas, perfis, ministerios, ministerio_membros, solicitacoes,
--  configuracoes, auditoria). As contas criadas no Auth NÃO são apagadas
-- por este script.
-- =====================================================================
begin;
drop trigger if exists betel_senha_alterada on auth.users;

drop policy if exists ministerios_leitura on public.ministerios;
drop policy if exists pessoas_leitura on public.pessoas;
drop policy if exists perfis_leitura on public.perfis;
drop policy if exists ministerio_membros_leitura on public.ministerio_membros;
drop policy if exists solicitacoes_leitura on public.solicitacoes;
drop policy if exists auditoria_leitura on public.auditoria;
drop policy if exists configuracoes_leitura on public.configuracoes;

drop function if exists public.listar_auditoria(integer, bigint);
drop function if exists public.admin_salvar_ministerio(uuid, text, text, integer, boolean);
drop function if exists public.admin_atualizar_usuario(uuid, text, text[], jsonb);
drop function if exists public.listar_usuarios();
drop function if exists public.servico_definir_ativo(uuid, uuid, boolean);
drop function if exists public.servico_marcar_senha_temporaria(uuid, uuid);
drop function if exists public.servico_criar_usuario(uuid, uuid, text, text, text, text, text[], jsonb, uuid);
drop function if exists public.recusar_solicitacao(uuid, text);
drop function if exists public.listar_solicitacoes(text);
drop function if exists public.minha_equipe();
drop function if exists public.meu_painel();
drop function if exists public.solicitar_acesso(text, text, text, uuid, text);

drop table if exists public.auditoria;
drop table if exists public.configuracoes;
drop table if exists public.solicitacoes;
drop table if exists public.ministerio_membros;
drop table if exists public.perfis;
drop table if exists public.ministerios;
drop table if exists public.pessoas;

drop function if exists public.tg_senha_alterada();
drop function if exists public.tg_garantir_master();
drop function if exists public.tg_auditoria_imutavel();
drop function if exists public.tg_auditar();
drop function if exists public.tg_atualizado_em();
drop function if exists public.ator_atual();
drop function if exists public.membro_de(uuid);
drop function if exists public.lider_de(uuid);
drop function if exists public.tem_atribuicao(text);
drop function if exists public.e_master();
drop function if exists public.e_master_uid(uuid);
drop function if exists public.perfil_ativo();
drop function if exists public.minha_pessoa_id();
drop function if exists public.slugify(text);
drop function if exists public.so_digitos(text);
commit;
