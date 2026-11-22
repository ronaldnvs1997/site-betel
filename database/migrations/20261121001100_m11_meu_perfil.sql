-- =====================================================================
-- M11 — Meu perfil (aditiva e reversível)
-- Leitura do próprio cadastro e edição apenas do próprio telefone.
-- Nome, e-mail, perfil de acesso, atribuições e ministérios continuam
-- editáveis só pelo MASTER (funções admin_* já existentes).
-- Não cria nem altera tabelas. A alteração do telefone fica registrada
-- na auditoria pelo gatilho que já existe em public.pessoas.
-- =====================================================================
begin;

create function public.meu_perfil() returns jsonb
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

create function public.meu_perfil_atualizar(p_telefone text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_tel text := public.so_digitos(p_telefone); v_pessoa uuid;
begin
  if not public.perfil_ativo() then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  if v_tel !~ '^[0-9]{10,11}$' then
    raise exception 'Informe um telefone válido, com DDD.' using errcode = '22023'; end if;
  select pessoa_id into v_pessoa from public.perfis where id = auth.uid();
  update public.pessoas set telefone = v_tel, atualizado_em = now() where id = v_pessoa;
  return public.meu_perfil();
end $$;

revoke execute on function public.meu_perfil(), public.meu_perfil_atualizar(text) from public, anon;
grant execute on function public.meu_perfil(), public.meu_perfil_atualizar(text) to authenticated;

commit;
