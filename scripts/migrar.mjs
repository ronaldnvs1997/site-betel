// Aplica as migrações do banco que ainda faltam (as mesmas que o servidor aplica ao iniciar).
//   npm run migrate            aplica o que falta
//   npm run migrate:status     só mostra o que já foi aplicado e o que falta, sem alterar nada
// Usa DATABASE_URL (e DATABASE_SSL=true para conexões externas com SSL).
import pg from "pg";
import path from "node:path";
import fs from "node:fs";
import { fileURLToPath } from "node:url";
import { lerEtapas, instalarNoBanco } from "../nucleo/etapas.mjs";

const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
// .env local (se existir); no Render as variáveis já vêm do painel
try { for (const l of fs.readFileSync(path.join(RAIZ, ".env"), "utf8").split(/\r?\n/)) { const m = l.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)\s*$/); if (m && m[2] !== "" && process.env[m[1]] === undefined) process.env[m[1]] = m[2].replace(/^["']|["']$/g, ""); } } catch (_) {}
if (!process.env.DATABASE_URL) { console.error("Defina DATABASE_URL (veja o .env.example)."); process.exit(1); }
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL, ssl: process.env.DATABASE_SSL === "true" ? { rejectUnauthorized: false } : undefined, max: 2 });
const log = (...a) => console.log(new Date().toISOString(), ...a);
try {
  if (process.argv.includes("--status")) {
    const tem = (await pool.query("select to_regclass('sistema.migracoes') is not null as t")).rows[0].t;
    const feitas = new Map(tem ? (await pool.query("select nome, aplicada_em from sistema.migracoes")).rows.map((r) => [r.nome, r.aplicada_em]) : []);
    for (const e of lerEtapas(RAIZ)) console.log(feitas.has(e.nome) ? `  ✓ ${e.nome}  (${new Date(feitas.get(e.nome)).toLocaleString("pt-BR")})` : `  · ${e.nome}  (pendente)`);
  } else {
    await instalarNoBanco(pool, RAIZ, log);
  }
} catch (e) { console.error("Falha:", e.message); process.exitCode = 1; }
finally { await pool.end(); }
