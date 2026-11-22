#!/bin/bash
# Prova que M02–M04 preservam dados/colunas existentes e que os .down restauram o estado anterior.
cd "$(dirname "$0")/.."
P="psql -h /tmp -p 5434 -U postgres -q -At -d betel -v ON_ERROR_STOP=1"; M=../supabase/migrations; ok=0; f=0
chk(){ if [ "$1" = "$2" ]; then ok=$((ok+1)); echo "  ✓ $3"; else f=$((f+1)); echo "  ✗ $3"; diff <(echo "$1") <(echo "$2") | head -5; fi; }
for VAR in texto date; do
  echo "Variante de tipos: $VAR"
  ./reset.sh 1 $VAR >/dev/null
  dados(){ $P -c "select md5(string_agg(x, '|' order by x)) from (select (e.*)::text as x from (select id,titulo,data,ministerio,lider,horario,horario_inicio,horario_fim,local,necessita_midia,necessita_louvor,necessita_diaconia,midia_tema,midia_arte,midia_banner,midia_inscricao,midia_link_inscricao,midia_info,observacoes,link_fotos,link_videos,bloqueado,atualizado_em from eventos) e
     union all select (r.*)::text from (select id,ministerio,motivo,espacos,data,horario_inicio,horario_fim,lote_id from reservas) r
     union all select (c.*)::text from (select id,nome,login,senha,ativo from coordenadores) c) t"; }
  colunas(){ $P -c "select string_agg(table_name||'.'||column_name||':'||data_type||':'||is_nullable||':'||coalesce(column_default,''), ',' order by table_name, ordinal_position) from information_schema.columns where table_schema='public' and table_name in ('eventos','reservas','coordenadores') and column_name not in ('ministerio_id','criado_por','atualizado_por','criado_em','usuario_id','migrado_em')"; }
  seguranca(){ $P -c "select (select string_agg(relname||'='||relrowsecurity, ',' order by relname) from pg_class where relname in ('eventos','reservas','coordenadores') and relnamespace='public'::regnamespace) || ' | ' || (select string_agg(grantee||'.'||table_name||'.'||privilege_type, ',' order by grantee||'.'||table_name||'.'||privilege_type) from information_schema.role_table_grants where table_name in ('eventos','reservas','coordenadores') and grantee in ('anon','authenticated'))"; }
  D0=$(dados); C0=$(colunas); S0=$(seguranca)
  $P -f $M/20261121000200_m02_agenda_colunas.sql; $P -f $M/20261121000300_m03_agenda_seguranca.sql; $P -f $M/20261121000400_m04_agenda_regras.sql
  chk "$(dados)" "$D0" "dados existentes idênticos depois de M02–M04"
  chk "$(colunas)" "$C0" "colunas existentes idênticas (nome, tipo, nulidade, padrão)"
  chk "$($P -c "select count(*) from eventos where ministerio_id is not null")" "4" "4 de 5 eventos ligados ao ministério pelo nome ('Igreja' fica sem vínculo)"
  chk "$($P -c "select ministerio||'→'||(select nome from ministerios m where m.id=ministerio_id) from eventos where ministerio='Juventude'")" "Juventude→Juventude Mergulhados" "'Juventude' reconhecido como Juventude Mergulhados"
  chk "$($P -c "select count(*) from auditoria where depois ? 'senha' or antes ? 'senha'")" "0" "nenhuma senha copiada para o histórico"
  chk "$($P -c "select has_column_privilege('anon','public.coordenadores','senha','select')::text || has_column_privilege('authenticated','public.coordenadores','senha','select')::text")" "falsefalse" "coluna senha inacessível para anon e authenticated"
  chk "$($P -c "select has_table_privilege('anon','public.eventos','insert')::text||has_table_privilege('anon','public.eventos','update')::text||has_table_privilege('anon','public.reservas','delete')::text")" "falsefalsefalse" "chave pública sem escrita em eventos e reservas"
  $P -f ../supabase/rollback/20261121000400_m04_agenda_regras.down.sql; $P -f ../supabase/rollback/20261121000300_m03_agenda_seguranca.down.sql; $P -f ../supabase/rollback/20261121000200_m02_agenda_colunas.down.sql
  chk "$(dados)" "$D0" "após desfazer: dados idênticos"
  chk "$(colunas)" "$C0" "após desfazer: colunas idênticas"
  chk "$(seguranca)" "$S0" "após desfazer: RLS e privilégios restaurados"
  chk "$($P -c "select count(*) from information_schema.columns where table_name in ('eventos','reservas','coordenadores') and column_name in ('ministerio_id','criado_por','atualizado_por','criado_em','usuario_id','migrado_em')")" "0" "após desfazer: colunas novas removidas"
done
echo "Resultado: $ok ok, $f falha(s)"
