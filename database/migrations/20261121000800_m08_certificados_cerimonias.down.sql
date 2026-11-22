-- DESFAZER M08 — volta certificados e cerimônias ao fluxo da M06.
-- ATENÇÃO: exporte antes certificados_eventos (histórico de emissão e entrega) e turma_responsaveis.
-- Certificados nos estados novos voltam para o estado equivalente da M06.
begin;
drop trigger if exists certificados_eventos_registro on public.certificados;
drop table if exists public.certificados_eventos, public.turma_responsaveis cascade;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='tg_eventos_imutaveis' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='tg_certificado_evento' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='certificado_validador' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='certificado_validador_uid' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='lider_turmas_validacao' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='lider_concluir_validar' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='lider_validar_certificado' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='cursos_validadores_disponiveis' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='cursos_responsaveis_turma' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='cursos_definir_responsaveis' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_cerimonia_realizada' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='certificado_impressao_json' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_vincular_cerimonia' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_imprimir_cerimonia' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_lista_cerimonia' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_certificado_historico' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
do $$ declare f record; begin for f in select oid::regprocedure s from pg_proc where pronamespace='public'::regnamespace and proname='secretaria_salvar_modelo_certificado' loop execute 'drop function ' || f.s || ' cascade'; end loop; end $$;
alter table public.certificados drop constraint certificados_fluxo_check;
alter table public.certificados drop constraint certificados_status_check;
update public.certificados set status = 'elegivel' where status in ('aguardando_validacao','aguardando_autorizacao','autorizado');
alter table public.certificados alter column status set default 'elegivel';
alter table public.certificados add constraint certificados_status_check check (status in ('elegivel','preparado','impresso','entregue','cancelado'));
alter table public.certificados drop column validado_por, drop column validado_em, drop column observacao_validacao, drop column autorizado_por,
  drop column autorizado_em, drop column entrega_ocasiao, drop column recebido_relacao, drop column entrega_observacao;
alter table public.cerimonias drop column tipo, drop column realizada_em, drop column realizada_por;
delete from public.configuracoes where chave = 'certificado_modelo';
create or replace function public.tg_certificado_conclusao() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'concluida' and old.status is distinct from 'concluida' then
    insert into public.certificados (inscricao_id, codigo)
    values (new.id, upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)))
    on conflict (inscricao_id) do update set status = case when public.certificados.entregue_em is not null then 'entregue'
      when public.certificados.impresso_em is not null then 'impresso' when public.certificados.cerimonia_id is not null then 'preparado' else 'elegivel' end,
      motivo_cancelamento = null where public.certificados.status = 'cancelado';
    perform public.notificar('SECRETARIA', null, 'certificado_elegivel', 'Certificado a preparar', 'Inscrição ' || new.protocolo || ' concluída: certificado pronto para ser preparado.', jsonb_build_object('inscricao_id', new.id));
  elsif old.status = 'concluida' and new.status <> 'concluida' then
    update public.certificados set status = 'cancelado', motivo_cancelamento = 'Conclusão desfeita' where inscricao_id = new.id and status <> 'entregue';
  end if;
  return new;
end $$;

create or replace function public.secretaria_salvar_cerimonia(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p->>'id', '')::uuid;
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  if v_id is null then
    insert into public.cerimonias (titulo, data, horario, local, evento_ref, responsavel, status, observacoes)
    values (btrim(p->>'titulo'), nullif(p->>'data', '')::date, nullif(btrim(p->>'horario'), ''), nullif(btrim(p->>'local'), ''), nullif(btrim(p->>'evento_ref'), ''),
            nullif(btrim(p->>'responsavel'), ''), coalesce(nullif(p->>'status', ''), 'planejada'), nullif(btrim(p->>'observacoes'), '')) returning id into v_id;
  else
    update public.cerimonias set titulo = btrim(p->>'titulo'), data = nullif(p->>'data', '')::date, horario = nullif(btrim(p->>'horario'), ''), local = nullif(btrim(p->>'local'), ''),
      evento_ref = nullif(btrim(p->>'evento_ref'), ''), responsavel = nullif(btrim(p->>'responsavel'), ''), status = coalesce(nullif(p->>'status', ''), status),
      observacoes = nullif(btrim(p->>'observacoes'), '') where id = v_id;
    if not found then raise exception 'Cerimônia não encontrada.' using errcode = 'P0002'; end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
exception when check_violation or not_null_violation then raise exception 'Informe o título da cerimônia (mínimo 3 caracteres).' using errcode = '22023';
end $$;

create or replace function public.secretaria_certificado(p_certificado uuid, p_acao text, p_dados jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare ce public.certificados; v_imp jsonb;
begin
  if not public.e_secretaria() then raise exception 'Somente a Secretaria gerencia certificados.' using errcode = '42501'; end if;
  select * into ce from public.certificados where id = p_certificado for update;
  if not found then raise exception 'Certificado não encontrado.' using errcode = 'P0002'; end if;
  if ce.status = 'cancelado' and p_acao <> 'reativar' then raise exception 'Certificado cancelado.' using errcode = '22023'; end if;
  if p_acao = 'preparar' then
    if ce.status = 'entregue' then raise exception 'Certificado já entregue.' using errcode = '22023'; end if;
    if not exists (select 1 from public.cerimonias where id = (p_dados->>'cerimonia_id')::uuid and status = 'planejada') then
      raise exception 'Escolha uma cerimônia planejada.' using errcode = '22023'; end if;
    update public.certificados set cerimonia_id = (p_dados->>'cerimonia_id')::uuid, status = case when status = 'elegivel' then 'preparado' else status end,
           preparado_por = auth.uid(), preparado_em = now() where id = ce.id;
  elsif p_acao = 'imprimir' then
    if ce.status not in ('preparado','impresso') then raise exception 'Prepare o certificado (ligue a uma cerimônia) antes de imprimir.' using errcode = '22023'; end if;
    update public.certificados set status = 'impresso', impresso_por = auth.uid(), impresso_em = now(), vezes_impresso = vezes_impresso + 1 where id = ce.id;
    select jsonb_build_object('codigo', ce.codigo, 'nome', pe.nome, 'curso', c.titulo, 'carga_horaria', c.carga_horaria, 'concluida_em', i.concluida_em,
             'turma', t.nome, 'cerimonia', cm.titulo, 'cerimonia_data', cm.data)
      into v_imp from public.inscricoes i join public.pessoas pe on pe.id = i.pessoa_id join public.turmas t on t.id = i.turma_id
      join public.cursos c on c.id = t.curso_id left join public.cerimonias cm on cm.id = ce.cerimonia_id where i.id = ce.inscricao_id;
    return jsonb_build_object('ok', true, 'impressao', v_imp);
  elsif p_acao = 'entregar' then
    if ce.status <> 'impresso' then raise exception 'Só certificados impressos podem ser entregues.' using errcode = '22023'; end if;
    if char_length(btrim(coalesce(p_dados->>'recebido_por', ''))) < 3 then raise exception 'Informe quem recebeu o certificado.' using errcode = '22023'; end if;
    update public.certificados set status = 'entregue', entregue_em = now(), entregue_por = auth.uid(), recebido_por = btrim(p_dados->>'recebido_por') where id = ce.id;
  elsif p_acao = 'cancelar' then
    if char_length(btrim(coalesce(p_dados->>'motivo', ''))) < 3 then raise exception 'Informe o motivo.' using errcode = '22023'; end if;
    update public.certificados set status = 'cancelado', motivo_cancelamento = btrim(p_dados->>'motivo') where id = ce.id;
  elsif p_acao = 'reativar' then
    if not exists (select 1 from public.inscricoes where id = ce.inscricao_id and status = 'concluida') then raise exception 'A inscrição não está concluída.' using errcode = '22023'; end if;
    update public.certificados set status = case when entregue_em is not null then 'entregue' when impresso_em is not null then 'impresso' when cerimonia_id is not null then 'preparado' else 'elegivel' end,
           motivo_cancelamento = null where id = ce.id;
  else raise exception 'Ação inválida.' using errcode = '22023';
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.secretaria_certificados(p_filtros jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.e_secretaria() then raise exception 'Acesso restrito à Secretaria.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'cerimonias', coalesce((select jsonb_agg(to_jsonb(cm) || jsonb_build_object('certificados', (select count(*) from public.certificados ce where ce.cerimonia_id = cm.id and ce.status <> 'cancelado')) order by cm.data nulls last, cm.criado_em) from public.cerimonias cm), '[]'::jsonb),
    'certificados', coalesce((select jsonb_agg(jsonb_build_object('id', ce.id, 'codigo', ce.codigo, 'status', ce.status, 'cerimonia_id', ce.cerimonia_id,
        'cerimonia', cm.titulo, 'vezes_impresso', ce.vezes_impresso, 'impresso_em', ce.impresso_em, 'entregue_em', ce.entregue_em, 'recebido_por', ce.recebido_por,
        'motivo_cancelamento', ce.motivo_cancelamento, 'nome', pe.nome, 'curso', c.titulo, 'turma', t.nome, 'concluida_em', i.concluida_em, 'protocolo', i.protocolo) order by ce.criado_em desc)
      from public.certificados ce join public.inscricoes i on i.id = ce.inscricao_id join public.pessoas pe on pe.id = i.pessoa_id
      join public.turmas t on t.id = i.turma_id join public.cursos c on c.id = t.curso_id left join public.cerimonias cm on cm.id = ce.cerimonia_id
      where (p_filtros->>'status' is null or ce.status = p_filtros->>'status') and (p_filtros->>'cerimonia_id' is null or ce.cerimonia_id = (p_filtros->>'cerimonia_id')::uuid)), '[]'::jsonb));
end $$;

revoke execute on function public.tg_certificado_conclusao() from public, anon, authenticated;
revoke execute on function public.secretaria_salvar_cerimonia(jsonb), public.secretaria_certificado(uuid, text, jsonb), public.secretaria_certificados(jsonb) from public, anon;
grant execute on function public.secretaria_salvar_cerimonia(jsonb), public.secretaria_certificado(uuid, text, jsonb), public.secretaria_certificados(jsonb) to authenticated;
commit;
