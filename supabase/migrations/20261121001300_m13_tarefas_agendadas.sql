-- =====================================================================
-- M13 — Tarefa agendada: prazos das escalas da Mídia a cada 15 minutos
--
-- Usa o pg_cron do próprio Supabase. Se a extensão puder ser ativada por aqui,
-- ela é ativada e a tarefa é agendada; senão, a migração só avisa e não falha
-- (ative em Database → Extensions → pg_cron e rode esta migração de novo).
-- Não altera dados.
-- =====================================================================
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      create extension if not exists pg_cron;
    exception when others then
      raise notice 'Não foi possível ativar o pg_cron por aqui (%). Ative em Database → Extensions.', sqlerrm;
    end;
  end if;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if not exists (select 1 from cron.job where jobname = 'betel-escalas-prazos') then
      perform cron.schedule('betel-escalas-prazos', '*/15 * * * *', 'select public.escalas_processar_prazos()');
    end if;
  else
    raise notice 'pg_cron inativo: os prazos das escalas da Mídia não serão processados automaticamente.';
  end if;
end $$;
