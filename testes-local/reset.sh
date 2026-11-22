#!/bin/bash
# Recria o banco local no formato do Supabase: stub (auth, papéis, storage) + Agenda existente + migrações.
# Imita a instância atual: as tabelas da Agenda já existem com dados antes das migrações.
# Uso: ./reset.sh [ate_migracao: 0..13] [variante: texto|date]
ATE=${1:-13}; VAR=${2:-texto}
cd "$(dirname "$0")"
pg_isready -h /tmp -p 5434 -q || su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgsb -o '-p 5434 -k /tmp' -l /tmp/pgsb/log start" >/dev/null; sleep 1
export PGOPTIONS="-c client_min_messages=warning"
P="psql -h /tmp -p 5434 -U postgres -q -v ON_ERROR_STOP=1"
$P -d postgres -c "drop database if exists betel with (force)" -c "create database betel" >/dev/null
$P -d betel -f sql/00_supabase_stub.sql 2>/dev/null || $P -d betel -f <(grep -v "^create role\|^grant anon, authenticated, service_role to authenticator" sql/00_supabase_stub.sql)
# papéis do Supabase (existem no cluster inteiro): service_role ignora o RLS, como no Supabase
$P -d postgres -c "alter role service_role bypassrls" >/dev/null
$P -d betel -f sql/00b_storage_stub.sql
if [ "$VAR" = "date" ]; then $P -d betel -f sql/01b_agenda_tipos_date.sql; else $P -d betel -f sql/01_agenda_existente.sql; fi
for f in ../supabase/migrations/2026*.sql; do
  n=$(basename "$f" | sed -E 's/^[0-9]{14}_m([0-9]+)_.*/\1/'); n=$((10#$n))
  [ "$n" -le "$ATE" ] && $P -d betel -f "$f"
done
echo "banco pronto (ate M$ATE, variante $VAR)"
