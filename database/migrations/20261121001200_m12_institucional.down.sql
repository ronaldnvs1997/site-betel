-- DESFAZER M12 — remove o que a M12 criou. Pessoas, usuários, ministérios, vínculos e eventos NÃO são apagados.
-- Atenção: apaga os textos de ministérios, organogramas, etapas do Colégio, links privados e envios feitos pela M12.
begin;
drop trigger if exists ministerios_organograma on public.ministerios;
drop function if exists public.agenda_envio_decidir(uuid, text, text), public.agenda_link_enviar(text, jsonb), public.agenda_link_abrir(text),
  public.agenda_link_valido(text), public.agenda_validar_ficha(jsonb, text), public.agenda_envios_listar(text), public.agenda_links_listar(),
  public.agenda_link_revogar(uuid), public.agenda_link_novo_token(uuid, integer), public.agenda_link_criar(text, uuid, text, integer, boolean),
  public.agenda_novo_token(), public.agenda_token_hash(text), public.colegio_etapa_salvar(uuid, jsonb, boolean), public.colegio_etapas_admin(),
  public.site_salvar_galeria(jsonb), public.site_salvar_contatos(jsonb), public.site_validar_contato(jsonb, text, text), public.site_conteudo_publico(),
  public.admin_remover_foto(uuid), public.meu_perfil_foto_remover(), public.meu_perfil_foto(text, boolean),
  public.organograma_atualizar(uuid, text, text), public.organograma_no_mover(uuid, uuid, integer), public.organograma_no_remover(uuid, uuid),
  public.organograma_no_salvar(uuid, jsonb), public.organograma_obter(uuid), public.organogramas_listar(), public.pessoa_cartao(uuid),
  public.pessoas_para_vinculo(text), public.ministerio_desvincular(uuid, uuid), public.ministerio_definir_cargo(uuid, uuid, text),
  public.ministerio_vincular(uuid, uuid, text), public.ministerio_definir_lideranca(uuid, uuid[], uuid), public.ministerio_salvar_pagina(uuid, jsonb, boolean),
  public.ministerio_admin_obter(uuid), public.ministerios_publicos(), public.ministerio_pagina_publica_json(public.ministerios, public.ministerio_paginas),
  public.institucional_permissoes(), public.imagem_existe(text, text), public.pode_enviar_foto_perfil(text), public.pode_enviar_imagem_site(text),
  public.site_apagar_imagem(text), public.foto_url_publica(text), public.texto_limpo(text, integer), public.tg_ministerio_organograma(),
  public.pode_editar_organograma(uuid);
drop table if exists public.agenda_link_acessos, public.agenda_envios_historico, public.agenda_envios, public.agenda_links,
  public.colegio_etapas, public.organograma_nos, public.organogramas, public.ministerio_paginas;
delete from public.configuracoes where chave in ('site.contatos', 'site.galeria_home');
delete from armazenamento.objetos where espaco in ('site', 'perfis');
alter table public.perfis drop column if exists foto_no_organograma, drop column if exists foto_caminho;
alter table public.ministerio_membros drop column if exists cargo;
-- volta "Meu perfil" à versão da M11
create or replace function public.meu_perfil() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_p public.perfis; v_pe public.pessoas;
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  select * into v_p from public.perfis where id = auth.uid();
  select * into v_pe from public.pessoas where id = v_p.pessoa_id;
  return jsonb_build_object(
    'nome', v_pe.nome, 'email', v_pe.email, 'telefone', v_pe.telefone,
    'perfil', v_p.perfil, 'atribuicoes', to_jsonb(v_p.atribuicoes),
    'conta_criada_em', v_p.criado_em, 'aprovado_em', v_p.aprovado_em,
    'senha_alterada_em', v_p.senha_alterada_em,
    'ministerios', coalesce((select jsonb_agg(jsonb_build_object('nome', m.nome, 'funcao', mm.funcao, 'desde', mm.desde) order by m.ordem, m.nome)
                             from public.ministerio_membros mm join public.ministerios m on m.id = mm.ministerio_id
                             where mm.pessoa_id = v_p.pessoa_id and mm.ativo), '[]'::jsonb),
    'editaveis', jsonb_build_array('telefone'));
end $$;
commit;
