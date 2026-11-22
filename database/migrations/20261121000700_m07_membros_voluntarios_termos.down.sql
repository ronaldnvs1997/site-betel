-- DESFAZER M07 — remove só o que a M07 criou e devolve inscrever_curso (M05)
-- e secretaria_validar_membresia (M06) às versões anteriores.
-- ATENÇÃO: exporte antes termos, consentimentos, processos de membresia,
-- candidaturas e conclusões anteriores. Consentimentos são prova exigida pela LGPD.
begin;
drop trigger if exists inscricoes_membresia_voluntariado on public.inscricoes;
drop trigger if exists ministerio_membros_voluntario_requisitos on public.ministerio_membros;
drop table if exists public.voluntariado_indicacoes, public.voluntariado_candidaturas, public.membresia_processos,
  public.cursos_conclusoes_anteriores, public.consentimentos, public.termos cascade;
drop function if exists public.inscrever_curso_com_termos(uuid, text, text, text, date, text, boolean, uuid, jsonb, jsonb, text, boolean);
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='tg_termo_imutavel' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='tg_consentimento_imutavel' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='curso_id_por_slug' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='curso_concluido' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='idade_em' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='membresia_validada' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='consentimento_atual' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='voluntariado_requisitos' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='tg_voluntario_requisitos' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='termos_vigentes' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='responsavel_valido' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='registrar_consentimento' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='link_inscricao' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='consentimentos_json' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='meus_termos' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='autorizar_imagem_link' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='revogar_consentimento_link' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='membresia_interesse' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='tg_inscricao_membresia_voluntariado' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_processos_membresia' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_abrir_processo' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_encerrar_processo' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_registrar_conclusao_anterior' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_cancelar_conclusao_anterior' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_ficha_pessoa' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='candidatura_json' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='voluntariado_indicar_interno' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='minha_candidatura' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='voluntariado_indicar' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_candidaturas' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_abrir_candidatura' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_indicar_ministerios' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_cancelar_candidatura' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='lider_candidaturas' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='lider_decidir_indicacao' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_termos' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_salvar_termo' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_publicar_termo' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_registrar_consentimento' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_revogar_consentimento' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='imagem_consultar' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
alter table public.documentos drop constraint documentos_tipo_check;
alter table public.documentos add constraint documentos_tipo_check check (tipo in
  ('ficha_membresia','carta_transferencia','documento_responsavel','documento_identificacao','outro'));
create or replace function public.inscrever_curso(
  p_turma uuid, p_nome text, p_telefone text, p_email text, p_data_nascimento date,
  p_observacao text, p_aceite_privacidade boolean, p_origem text default 'site'
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t public.turmas; c public.cursos; v_email text := lower(btrim(coalesce(p_email, '')));
        v_tel text := public.so_digitos(p_telefone); v_nome text := regexp_replace(btrim(coalesce(p_nome, '')), '\s+', ' ', 'g');
        v_pessoa uuid; v_existente public.inscricoes; v_status text; v_chave text; v_prot text; v_ocup integer; v_pos integer; v_falta text;
        v_secretaria boolean := p_origem = 'secretaria';
begin
  if v_secretaria and not public.cursos_gestor() then raise exception 'Somente a Secretaria pode inscrever pelo painel.' using errcode = '42501'; end if;
  if p_origem not in ('site','secretaria') then raise exception 'Origem inválida.' using errcode = '22023'; end if;
  if char_length(v_nome) < 3 or v_nome !~ '\s' then raise exception 'Informe o nome completo.' using errcode = '22023'; end if;
  if v_tel !~ '^[0-9]{10,13}$' then raise exception 'Informe um telefone válido, com DDD.' using errcode = '22023'; end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Informe um e-mail válido.' using errcode = '22023'; end if;
  if p_data_nascimento is not null and (p_data_nascimento > current_date or p_data_nascimento < date '1900-01-01') then
    raise exception 'Data de nascimento inválida.' using errcode = '22023'; end if;
  if not coalesce(p_aceite_privacidade, false) then raise exception 'É preciso concordar com o uso dos dados para a inscrição.' using errcode = '22023'; end if;

  -- trava a turma: inscrições simultâneas entram uma de cada vez
  select * into t from public.turmas where id = p_turma for update;
  if not found then raise exception 'Turma não encontrada.' using errcode = 'P0002'; end if;
  select * into c from public.cursos where id = t.curso_id;
  if not c.publicado and not v_secretaria then raise exception 'Curso indisponível.' using errcode = 'P0002'; end if;
  if not v_secretaria and not public.turma_aberta(t) then raise exception 'As inscrições desta turma não estão abertas.' using errcode = '22023'; end if;
  if v_secretaria and t.status in ('rascunho','cancelada','concluida') then raise exception 'Esta turma não aceita inscrições (situação: %).', t.status using errcode = '22023'; end if;

  -- pessoa: reaproveita o cadastro pelo e-mail (sem duplicar)
  select id into v_pessoa from public.pessoas where email = v_email and arquivado_em is null;
  -- duplicidade: mesmo e-mail OU mesmo telefone já inscrito nesta turma
  select i.* into v_existente from public.inscricoes i join public.pessoas pe on pe.id = i.pessoa_id
   where i.turma_id = p_turma and i.status <> 'cancelada' and (pe.email = v_email or pe.telefone = v_tel) limit 1;
  if found then
    return jsonb_build_object('ok', true, 'duplicada', true, 'protocolo', v_existente.protocolo, 'status', v_existente.status,
      'mensagem', 'Já existe uma inscrição ativa nesta turma com este e-mail ou telefone (protocolo ' || v_existente.protocolo || ').');
  end if;

  -- pré-requisitos (ex.: Formação de Voluntários)
  if c.exige_membro and not exists (select 1 from public.pessoas pe where pe.id = v_pessoa and pe.situacao_membresia = 'membro' and pe.membresia_validada_em is not null) then
    raise exception 'Este curso é para membros com a membresia validada pela Secretaria. Fale com a Secretaria.' using errcode = '22023';
  end if;
  select string_agg(x.titulo, ', ') into v_falta from public.cursos x
   where x.id = any(c.cursos_exigidos)
     and not exists (select 1 from public.inscricoes i join public.turmas tt on tt.id = i.turma_id
                     where i.pessoa_id = v_pessoa and tt.curso_id = x.id and i.status = 'concluida');
  if v_falta is not null then
    raise exception 'Antes deste curso é preciso concluir: %.', v_falta using errcode = '22023';
  end if;

  if v_pessoa is null then
    insert into public.pessoas (nome, telefone, email, data_nascimento, origem)
    values (v_nome, v_tel, v_email, p_data_nascimento, case when v_secretaria then 'secretaria' else 'site' end)
    returning id into v_pessoa;
  else
    update public.pessoas set telefone = coalesce(telefone, v_tel), data_nascimento = coalesce(data_nascimento, p_data_nascimento) where id = v_pessoa;
  end if;

  v_ocup := (public.cursos_vagas_turma(p_turma)->>'ocupadas')::int;
  if t.vagas is not null and v_ocup >= t.vagas then
    if not t.lista_espera then raise exception 'As vagas desta turma estão esgotadas.' using errcode = '22023'; end if;
    v_status := 'lista_espera';
  else
    v_status := case when coalesce(t.valor, 0) > 0 then 'aguardando_pagamento' else 'confirmada' end;
  end if;

  v_chave := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  v_prot := 'CUR-' || to_char(now() at time zone 'America/Sao_Paulo', 'YYYY') || '-' || lpad(nextval('public.inscricoes_protocolo_seq')::text, 6, '0');
  insert into public.inscricoes (protocolo, pessoa_id, turma_id, status, valor_bruto, valor_final, observacao, aceite_privacidade_em,
                                 chave_hash, origem, criado_por)
  values (v_prot, v_pessoa, p_turma, v_status, coalesce(t.valor, 0), coalesce(t.valor, 0), nullif(btrim(p_observacao), ''), now(),
          encode(sha256(convert_to(v_chave, 'UTF8')), 'hex'), p_origem, auth.uid());

  if v_status = 'lista_espera' then
    select count(*) into v_pos from public.inscricoes where turma_id = p_turma and status = 'lista_espera';
  end if;
  return jsonb_build_object('ok', true, 'duplicada', false, 'protocolo', v_prot, 'chave', v_chave, 'status', v_status,
    'posicao_espera', v_pos, 'curso', c.titulo, 'turma', t.nome, 'valor', t.valor);
exception when unique_violation then
  raise exception 'Já existe uma inscrição ativa desta pessoa nesta turma.' using errcode = '23505';
end $$;
create or replace function public.secretaria_validar_membresia(p_pessoa uuid, p_situacao text, p_membro_desde date, p_observacao text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.e_secretaria() then raise exception 'Somente a Secretaria valida membresia.' using errcode = '42501'; end if;
  if p_situacao not in ('visitante','em_integracao','membro','inativo') then raise exception 'Situação inválida.' using errcode = '22023'; end if;
  if p_situacao = 'membro' and p_membro_desde is null then raise exception 'Informe a data em que a pessoa se tornou membro.' using errcode = '22023'; end if;
  update public.pessoas set situacao_membresia = p_situacao,
         membro_desde = case when p_situacao = 'membro' then p_membro_desde else membro_desde end,
         membresia_validada_por = case when p_situacao = 'membro' then auth.uid() else membresia_validada_por end,
         membresia_validada_em = case when p_situacao = 'membro' then now() else membresia_validada_em end
   where id = p_pessoa;
  if not found then raise exception 'Pessoa não encontrada.' using errcode = 'P0002'; end if;
  insert into public.auditoria (ator, acao, tabela, registro, detalhes)
  values (auth.uid(), 'membresia_validada', 'pessoas', p_pessoa::text, jsonb_build_object('situacao', p_situacao, 'membro_desde', p_membro_desde, 'observacao', nullif(btrim(p_observacao), '')));
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.inscrever_curso(uuid, text, text, text, date, text, boolean, text) from public;
grant execute on function public.inscrever_curso(uuid, text, text, text, date, text, boolean, text) to anon, authenticated;
revoke execute on function public.secretaria_validar_membresia(uuid, text, date, text) from public, anon;
grant execute on function public.secretaria_validar_membresia(uuid, text, date, text) to authenticated;
commit;
