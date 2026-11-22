#!/bin/bash
# Recria o banco local do zero: stub do Supabase + Agenda existente (+ migrações, se ATE for informado)
# Uso: ./reset.sh [ate_migracao: 0|1|2|3|4] [variante: texto|date]
ATE=${1:-10}; VAR=${2:-texto}
pg_isready -h /tmp -p 5434 -q || su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgsb -o '-p 5434 -k /tmp' -l /tmp/pgsb/log start" >/dev/null; sleep 1
P="psql -h /tmp -p 5434 -U postgres -q -v ON_ERROR_STOP=1"
$P -d postgres -c "drop database if exists betel with (force)" -c "create database betel" >/dev/null
$P -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname='anon') then null; end if; end \$\$" >/dev/null
$P -d betel -f sql/00_supabase_stub.sql 2>/dev/null || $P -d betel -f <(grep -v "^create role\|^grant anon, authenticated, service_role to authenticator" sql/00_supabase_stub.sql)
if [ "$VAR" = "date" ]; then $P -d betel -f sql/01b_agenda_tipos_date.sql; else $P -d betel -f sql/01_agenda_existente.sql; fi
M=../supabase/migrations
[ $ATE -ge 1 ] && $P -d betel -f $M/20261121000100_m01_nucleo_autenticacao.sql
[ $ATE -ge 2 ] && $P -d betel -f $M/20261121000200_m02_agenda_colunas.sql
[ $ATE -ge 3 ] && $P -d betel -f $M/20261121000300_m03_agenda_seguranca.sql
[ $ATE -ge 4 ] && $P -d betel -f $M/20261121000400_m04_agenda_regras.sql
[ $ATE -ge 5 ] && $P -d betel -f $M/20261121000500_m05_cursos_inscricoes.sql
[ $ATE -ge 6 ] && $P -d betel -f $M/20261121000600_m06_secretaria_tesouraria.sql
[ $ATE -ge 7 ] && $P -d betel -f $M/20261121000700_m07_membros_voluntarios_termos.sql
[ $ATE -ge 8 ] && $P -d betel -f $M/20261121000800_m08_certificados_cerimonias.sql
[ $ATE -ge 9 ] && $P -d betel -f $M/20261121000900_m09_midia_escalas.sql
[ $ATE -ge 10 ] && $P -d betel -f $M/20261121001000_m10_homologacao_reforcos.sql
[ $ATE -ge 11 ] && $P -d betel -f $M/20261121001100_m11_meu_perfil.sql
echo "banco pronto (ate M0$ATE, variante $VAR)"
