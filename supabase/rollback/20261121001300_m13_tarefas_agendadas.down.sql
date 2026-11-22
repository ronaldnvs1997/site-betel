-- Desfaz a M13: tira a tarefa agendada (a extensão pg_cron continua ativa).
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'betel-escalas-prazos';
  end if;
end $$;
