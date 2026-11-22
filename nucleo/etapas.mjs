// Lista, em ordem, as etapas de instalação do banco (as mesmas no servidor, no script de migração e na versão de teste).
//   database/plataforma/NNN_*.sql  base da plataforma (usuários, sessões, arquivos) e a tabela original da Agenda
//   database/migrations/*.sql      migrações versionadas do sistema (M01, M02, ...); os arquivos .down.sql desfazem cada uma
import fs from "node:fs";
import path from "node:path";
import { instalar } from "./instalar.mjs";

const sqls = (pasta, filtro) => fs.readdirSync(pasta).filter((f) => f.endsWith(".sql") && !f.includes(".down.") && filtro(f)).sort()
  .map((f) => ({ nome: f.replace(/\.sql$/, ""), sql: fs.readFileSync(path.join(pasta, f), "utf8") }));

export function lerEtapas(raiz, extras = []) {
  const db = path.join(raiz, "database");
  return [...sqls(path.join(db, "plataforma"), (f) => /^\d{3}_/.test(f)), ...extras, ...sqls(path.join(db, "migrations"), () => true)];
}

// CSVs exportados da Agenda anterior (opcional, só na primeira instalação)
export function lerAgendaAnterior(raiz) {
  const pasta = path.join(raiz, "dados-agenda");
  const ler = (f) => (fs.existsSync(path.join(pasta, f)) ? fs.readFileSync(path.join(pasta, f), "utf8") : "");
  const a = { eventos: ler("eventos.csv"), reservas: ler("reservas.csv"), coordenadores: ler("coordenadores.csv") };
  return a.eventos || a.reservas || a.coordenadores ? a : null;
}

// Instala o que falta, com trava para duas instâncias não instalarem ao mesmo tempo
export async function instalarNoBanco(pool, raiz, log, extras = []) {
  const cli = await pool.connect();
  try {
    await cli.query("select pg_advisory_lock(424242)");
    return await instalar({ exec: (sql) => cli.query(sql), query: (sql, p) => cli.query(sql, p), etapas: lerEtapas(raiz, extras), agendaAnterior: lerAgendaAnterior(raiz), log });
  } finally { await cli.query("select pg_advisory_unlock(424242)").catch(() => {}); cli.release(); }
}
