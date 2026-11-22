-- =====================================================================
-- Sistema Betel — DIAGNÓSTICO DA INSTÂNCIA SUPABASE (somente leitura)
--
-- Não altera nada: só consulta a estrutura e conta registros.
-- Como usar: Supabase → SQL Editor → New query → cole este arquivo → Run.
-- Copie a tabela do resultado (ou "Export → CSV") e envie antes de aplicar
-- qualquer migração. Ela mostra o que já existe, o que falta e os pontos
-- que precisam de decisão.
-- Não mostra senhas, e-mails nem dados pessoais: só quantidades e nomes de estruturas.
-- =====================================================================
with
t as (select to_regclass(x) as r, x from (values
  ('public.eventos'), ('public.reservas'), ('public.coordenadores'), ('public.pessoas'), ('public.perfis'),
  ('public.ministerios'), ('public.cursos'), ('public.pagamentos'), ('public.termos'), ('public.certificados'),
  ('public.escala_eventos'), ('public.organogramas'), ('public.profiles')) v(x)),
existe as (select x, r is not null as ok from t),
e as (select x, ok from existe),
col as (select table_name || '.' || column_name as c, data_type from information_schema.columns where table_schema = 'public'),
fn as (select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'),
conta as (
  select 'public.eventos' x, case when to_regclass('public.eventos') is not null then (xpath('/row/c/text()', query_to_xml('select count(*) c from public.eventos', false, true, '')))[1]::text end n
  union all select 'public.reservas', case when to_regclass('public.reservas') is not null then (xpath('/row/c/text()', query_to_xml('select count(*) c from public.reservas', false, true, '')))[1]::text end
  union all select 'public.coordenadores', case when to_regclass('public.coordenadores') is not null then (xpath('/row/c/text()', query_to_xml('select count(*) c from public.coordenadores', false, true, '')))[1]::text end
  union all select 'senhas_em_texto', case when exists (select 1 from col where c = 'coordenadores.senha') then (xpath('/row/c/text()', query_to_xml('select count(*) c from public.coordenadores where coalesce(senha, '''') <> ''''', false, true, '')))[1]::text end
  union all select 'perfis', case when to_regclass('public.perfis') is not null then (xpath('/row/c/text()', query_to_xml('select count(*) c from public.perfis', false, true, '')))[1]::text end
  union all select 'masters', case when exists (select 1 from col where c = 'perfis.perfil') then (xpath('/row/c/text()', query_to_xml('select count(*) c from public.perfis where perfil = ''MASTER''', false, true, '')))[1]::text end
),
n as (select x, n from conta),
mig as (
  select 'M00' m, 'Tabelas da Agenda (eventos, reservas, coordenadores)' o,
         (select bool_and(ok) from e where x in ('public.eventos', 'public.reservas', 'public.coordenadores')) feita
  union all select 'M01', 'Pessoas, perfis, ministérios, solicitações, auditoria', (select ok from e where x = 'public.perfis')
  union all select 'M02', 'Colunas novas da Agenda (ministerio_id, criado_por…)', exists (select 1 from col where c = 'eventos.ministerio_id')
  union all select 'M03', 'Segurança da Agenda (login central, RLS novas)', exists (select 1 from col where c = 'coordenadores.usuario_id')
  union all select 'M04', 'Regras da Agenda (conflitos de horário e espaço)', exists (select 1 from fn where proname = 'agenda_conflitos')
  union all select 'M05', 'Cursos e inscrições', (select ok from e where x = 'public.cursos')
  union all select 'M06', 'Secretaria e Tesouraria', (select ok from e where x = 'public.pagamentos')
  union all select 'M07', 'Membros, voluntários e termos', (select ok from e where x = 'public.termos')
  union all select 'M08', 'Certificados e cerimônias', (select ok from e where x = 'public.certificados')
  union all select 'M09', 'Mídia e escalas', (select ok from e where x = 'public.escala_eventos')
  union all select 'M10', 'Reforços de homologação (limites)', exists (select 1 from fn where proname = 'limite_publico')
  union all select 'M11', 'Meu perfil', exists (select 1 from fn where proname = 'meu_perfil')
  union all select 'M12', 'Ministérios, organogramas, fotos, contatos, Colégio, link privado', (select ok from e where x = 'public.organogramas')
  union all select 'M13', 'Tarefa agendada (pg_cron)', case when to_regclass('cron.job') is null then false
         else (xpath('/row/c/text()', query_to_xml('select count(*) > 0 as c from cron.job where jobname = ''betel-escalas-prazos''', false, true, '')))[1]::text::boolean end
),
saida as (
  select 1 ordem, 'Migração ' || m as item, case when feita then 'JÁ APLICADA' else 'FALTA' end as situacao, o as detalhe from mig
  union all select 2, 'Histórico do Supabase CLI', case when to_regclass('supabase_migrations.schema_migrations') is null then 'não usado' else 'existe' end,
    case when to_regclass('supabase_migrations.schema_migrations') is null then 'Migrações não foram aplicadas pelo CLI (provavelmente pelo SQL Editor).'
         else 'Versões registradas: ' || coalesce((xpath('/row/v/text()', query_to_xml('select string_agg(version, '', '' order by version) v from supabase_migrations.schema_migrations', false, true, '')))[1]::text, 'nenhuma') end
  union all select 3, 'Eventos da Agenda', coalesce((select n from n where x = 'public.eventos'), '—'), 'Registros existentes (preservados por todas as migrações)'
  union all select 3, 'Reservas da Agenda', coalesce((select n from n where x = 'public.reservas'), '—'), 'Registros existentes (preservados)'
  union all select 3, 'Coordenadores da Agenda', coalesce((select n from n where x = 'public.coordenadores'), '—'), 'Logins antigos da Agenda'
  union all select 3, 'Tipo da coluna eventos.data', coalesce((select data_type from col where c = 'eventos.data'), '—'), 'As migrações aceitam texto ou date'
  union all select 4, 'Usuários no Supabase Auth', (select count(*)::text from auth.users), 'Contas existentes em auth.users (não são alteradas)'
  union all select 4, 'Perfis do sistema (public.perfis)', coalesce((select n from n where x = 'perfis'), '—'), 'Perfis ligados a auth.users'
  union all select 4, 'Administradores (MASTER)', coalesce((select n from n where x = 'masters'), '—'), 'Se 0 ou —: criar os primeiros com scripts/criar-primeiros-masters.mjs'
  union all select 5, 'ATENÇÃO: senhas em texto da Agenda antiga', coalesce((select n from n where x = 'senhas_em_texto'), '—'),
    'coordenadores.senha guarda senhas legíveis. As migrações bloqueiam o acesso a essa coluna, mas não apagam os valores. Limpar depende da sua aprovação.'
  union all select 5, 'ATENÇÃO: políticas atuais da Agenda', coalesce((select count(*)::text from pg_policies where schemaname = 'public' and tablename in ('eventos', 'reservas', 'coordenadores')), '0'),
    'Políticas hoje: ' || coalesce((select string_agg(tablename || '.' || policyname || ' (' || cmd || ')', '; ' order by tablename, policyname) from pg_policies where schemaname = 'public' and tablename in ('eventos', 'reservas', 'coordenadores')), 'nenhuma')
    || '. A M03 guarda uma cópia delas e as substitui: depois dela, só coordenadores logados gravam na Agenda.'
  union all select 5, 'Tabela public.profiles', case when (select ok from e where x = 'public.profiles') then 'EXISTE' else 'não existe' end,
    'O sistema usa public.perfis (ligada a auth.users). Se public.profiles existir, ela não é usada nem alterada.'
  union all select 5, 'Gatilhos em auth.users', (select count(*)::text from pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal),
    coalesce((select string_agg(tgname, ', ') from pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal), 'nenhum') || '. A M01 acrescenta só betel_senha_alterada (marca a troca da senha temporária).'
  union all select 6, 'Buckets do Storage', (select count(*)::text from storage.buckets),
    coalesce((select string_agg(id || case when public then ' (público)' else ' (privado)' end, ', ' order by id) from storage.buckets), 'nenhum') || '. O sistema usa: cursos, comprovantes, documentos, site, perfis.'
  union all select 6, 'Extensão pg_cron', case when exists (select 1 from pg_extension where extname = 'pg_cron') then 'ATIVA' else 'inativa' end,
    'Necessária para os prazos das escalas (M13 tenta ativar)'
)
select item, situacao, detalhe from saida order by ordem, item;
