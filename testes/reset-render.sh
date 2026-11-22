#!/bin/bash
# Banco igual ao do Render: usuário dono do banco, SEM superusuário (só CREATEROLE).
# O servidor novo (plataforma/servidor) instala a base, a Agenda e as migrações sozinho.
# Uso: ./reset-render.sh   (deixa o servidor rodando na porta 8095)
cd "$(dirname "$0")"
pg_isready -h /tmp -p 5434 -q || su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgsb -o '-p 5434 -k /tmp' -l /tmp/pgsb/log start" >/dev/null; sleep 1
P="psql -h /tmp -p 5434 -U postgres -q"
pkill -f "servidor/servidor.mjs"; pkill -f "node servidor[.]mjs"; sleep 0.3
$P -d postgres -c "drop database if exists betel with (force)" >/dev/null 2>&1
for r in anon authenticated service_role authenticator supabase_auth_admin; do $P -d postgres -c "drop role if exists $r" >/dev/null 2>&1; done
$P -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'betel_app') then create role betel_app login createrole nosuperuser; end if; end \$\$" >/dev/null
$P -d postgres -c "create database betel owner betel_app" >/dev/null
rm -rf _storage
( cd ../plataforma && BETEL_MODO_TESTE=1 PGUSER=betel_app PGDATABASE=betel SITE_DIR=../supabase/site CHAVES=../dev-supabase/chaves.json \
  BETEL_SEMENTE=../dev-supabase/sql/semente_agenda.sql node servidor/servidor.mjs > /tmp/srv.log 2>&1 & )
for i in $(seq 1 60); do curl -sf -o /dev/null http://localhost:8095/saude && break; sleep 0.5; done
curl -sf http://localhost:8095/saude >/dev/null || { echo "servidor não subiu"; tail -20 /tmp/srv.log; exit 1; }
