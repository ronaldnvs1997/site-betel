-- DESFAZER M05 — remove só o que a M05 criou. Exporte antes as inscrições, se houver.
-- Os cadastros de pessoas criados pelas inscrições permanecem (tabela pessoas é da M01).
begin;
do $$ begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists cursos_imagens_leitura on storage.objects';
    execute 'drop policy if exists cursos_imagens_envio on storage.objects';
    execute 'drop policy if exists cursos_imagens_troca on storage.objects';
  end if;
end $$;
drop function if exists public.cursos_atualizar_participante(uuid, text, text, text, date);
drop function if exists public.cursos_historico_participante(uuid);
drop function if exists public.cursos_participantes(text);
drop function if exists public.cursos_alterar_inscricao(uuid, text, text);
drop function if exists public.cursos_listar_inscricoes(uuid);
drop function if exists public.cursos_salvar_turma(jsonb);
drop function if exists public.cursos_salvar_curso(jsonb);
drop function if exists public.cursos_salvar_categoria(uuid, text, text, integer, boolean);
drop function if exists public.cursos_admin_listar();
drop function if exists public.cancelar_minha_inscricao_curso(text, text);
drop function if exists public.minha_inscricao_curso(text, text);
drop function if exists public.inscrever_curso(uuid, text, text, text, date, text, boolean, text);
drop function if exists public.cursos_promover_fila(uuid);
drop function if exists public.curso_publico(text);
drop function if exists public.cursos_publicos();
drop table if exists public.inscricoes;
drop sequence if exists public.inscricoes_protocolo_seq;
drop function if exists public.cursos_json_curso(public.cursos, boolean);
drop function if exists public.cursos_json_turma(public.turmas);
drop function if exists public.turma_aberta(public.turmas);
drop function if exists public.cursos_vagas_turma(uuid);
drop table if exists public.turmas;
drop table if exists public.cursos;
drop table if exists public.categorias_curso;
drop function if exists public.tg_inscricao_vagas();
drop function if exists public.cursos_gestor();
commit;
