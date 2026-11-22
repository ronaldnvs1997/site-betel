-- DESFAZER M06 — remove só o que a M06 criou e devolve minha_inscricao_curso à versão da M05.
-- ATENÇÃO: exporte antes pagamentos, comprovantes, reembolsos, documentos e certificados.
-- Os arquivos nos espaços privados "comprovantes" e "documentos" não são apagados por este script.
begin;
drop trigger if exists inscricoes_confirmacao_paga on public.inscricoes;
drop trigger if exists inscricoes_certificado on public.inscricoes;
drop trigger if exists inscricoes_cancelada_paga on public.inscricoes;
create or replace function public.minha_inscricao_curso(p_protocolo text, p_chave text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare i public.inscricoes; v_pos integer;
begin
  select * into i from public.inscricoes where protocolo = upper(btrim(p_protocolo))
     and chave_hash = encode(sha256(convert_to(coalesce(p_chave, ''), 'UTF8')), 'hex');
  if not found then raise exception 'Inscrição não encontrada. Confira o link recebido.' using errcode = 'P0002'; end if;
  if i.status = 'lista_espera' then
    select count(*) into v_pos from public.inscricoes where turma_id = i.turma_id and status = 'lista_espera'
       and (criado_em, protocolo) <= (i.criado_em, i.protocolo);
  end if;
  return (select jsonb_build_object('protocolo', i.protocolo, 'status', i.status, 'posicao_espera', v_pos,
      'nome', pe.nome, 'curso', c.titulo, 'curso_slug', c.slug, 'turma', public.cursos_json_turma(t), 'criado_em', i.criado_em, 'valor_final', i.valor_final)
    from public.turmas t join public.cursos c on c.id = t.curso_id join public.pessoas pe on pe.id = i.pessoa_id where t.id = i.turma_id);
end $$;

grant execute on function public.minha_inscricao_curso(text, text) to anon, authenticated;
drop function if exists public.tesouraria_movimentos(date, date);
drop function if exists public.tesouraria_dashboard(date, date);
drop function if exists public.tesouraria_registrar_reembolso(uuid, numeric, text, date, text);
drop function if exists public.tesouraria_analisar_beneficio(uuid, text, text);
drop function if exists public.tesouraria_beneficios(text);
drop function if exists public.tesouraria_analisar_pagamento(uuid, text, text);
drop function if exists public.tesouraria_pagamentos(jsonb);
drop function if exists public.secretaria_certificado(uuid, text, jsonb);
drop function if exists public.secretaria_certificados(jsonb);
drop function if exists public.secretaria_salvar_cerimonia(jsonb);
drop function if exists public.arquivo_autorizado(text, uuid);
drop function if exists public.secretaria_arquivar_documento(uuid);
drop function if exists public.secretaria_documentos(uuid);
drop function if exists public.servico_registrar_documento(uuid, uuid, text, text, text, text, text, integer, text);
drop function if exists public.secretaria_solicitar_beneficio(uuid, text, numeric, text);
drop function if exists public.secretaria_cancelar_pagamento(uuid, text);
drop function if exists public.secretaria_registrar_pagamento_presencial(uuid, text, numeric, date, text);
drop function if exists public.secretaria_validar_membresia(uuid, text, date, text);
drop function if exists public.secretaria_pessoas(text);
drop function if exists public.secretaria_inscricoes(jsonb);
drop function if exists public.servico_registrar_comprovante(uuid, uuid, uuid, text, numeric, date, text, text, text, integer, text);
drop function if exists public.servico_validar_link(text, text);
drop function if exists public.marcar_notificacoes_lidas(bigint[]);
drop function if exists public.minhas_notificacoes(integer);
drop function if exists public.notificar(text, uuid, text, text, text, jsonb);
drop function if exists public.financeiro_reavaliar(uuid);
drop table if exists public.notificacoes, public.certificados, public.cerimonias, public.documentos, public.reembolsos, public.beneficios, public.comprovantes, public.pagamentos;
drop function if exists public.financeiro_inscricao(uuid);
drop function if exists public.tg_inscricao_cancelada_paga();
drop function if exists public.tg_certificado_conclusao();
drop function if exists public.tg_inscricao_confirmacao_paga();
drop function if exists public.tg_nao_excluir();
drop function if exists public.financeiro_minhas_permissoes();
drop function if exists public.e_tesouraria();
drop function if exists public.e_secretaria();
commit;
