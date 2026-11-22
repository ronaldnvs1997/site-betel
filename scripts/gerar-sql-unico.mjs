// Gera database/instalar-tudo.sql: todas as etapas do banco num só arquivo para o psql,
// pulando as que já foram aplicadas (mesmo controle do servidor: sistema.migracoes).
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { lerEtapas } from "../nucleo/etapas.mjs";
const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const partes = [`-- =====================================================================
-- Sistema Betel — instalação completa do banco num único arquivo (PostgreSQL 14+).
--
-- NORMALMENTE NÃO É PRECISO RODAR ESTE ARQUIVO: o servidor faz a mesma coisa sozinho ao iniciar.
-- Use só se quiser preparar o banco antes, pelo terminal:
--     psql "URL_EXTERNA_DO_BANCO" -f database/instalar-tudo.sql
-- (no Render: betel-banco → Connect → External Database URL)
--
-- Pode rodar quantas vezes quiser: cada etapa já aplicada é pulada (tabela sistema.migracoes).
-- Exige o psql (usa \\if). Não importa os CSVs da Agenda antiga — isso o servidor faz na 1ª subida.
-- Gerado por scripts/gerar-sql-unico.mjs a partir de database/plataforma e database/migrations.
-- =====================================================================
\\set ON_ERROR_STOP on
create schema if not exists sistema;
create table if not exists sistema.migracoes (nome text primary key, aplicada_em timestamptz not null default now());
`];
for (const e of lerEtapas(RAIZ)) {
  if (/^\s*\\/m.test(e.sql)) throw new Error(`${e.nome} tem comando de barra invertida`);
  partes.push(`
-- ---------------------------------------------------------------------
-- ${e.nome}
select not exists (select 1 from sistema.migracoes where nome = '${e.nome}') as fazer \\gset
\\if :fazer
\\echo 'Aplicando ${e.nome}'
${e.sql.trim()}
insert into sistema.migracoes (nome) values ('${e.nome}');
\\else
\\echo 'Já aplicada: ${e.nome}'
\\endif
`);
}
partes.push(`\n\\echo 'Banco pronto.'\n`);
fs.writeFileSync(path.join(RAIZ, "database/instalar-tudo.sql"), partes.join(""));
console.log("database/instalar-tudo.sql gerado");
