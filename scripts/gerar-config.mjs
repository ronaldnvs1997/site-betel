// Gera site/config.js com o endereço do projeto Supabase e a chave PÚBLICA (anon / publishable).
// Roda no build do Render e no computador (npm run config). Lê as variáveis de ambiente
// SUPABASE_URL e SUPABASE_ANON_KEY (ou do arquivo .env, se existir).
// Recusa a chave service_role / secret: ela nunca pode ir para o navegador.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const envArq = path.join(RAIZ, ".env");
if (fs.existsSync(envArq)) {
  for (const l of fs.readFileSync(envArq, "utf8").split(/\r?\n/)) {
    const m = l.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)\s*$/);
    if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
}
const url = (process.env.SUPABASE_URL || "").trim().replace(/\/+$/, "");
const chave = (process.env.SUPABASE_ANON_KEY || "").trim();
const falha = (m) => { console.error("ERRO: " + m); process.exit(1); };
if (!url || !chave) falha("defina SUPABASE_URL e SUPABASE_ANON_KEY (Supabase → Project Settings → API).");
if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(url) && !/^https:\/\/[a-z0-9.-]+$/.test(url) && !/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(url))
  falha("SUPABASE_URL inválida (ex.: https://abcdefgh.supabase.co).");
if (/^sb_secret_/.test(chave)) falha("essa é a chave SECRETA. Use a chave pública (anon ou publishable).");
if (chave.split(".").length === 3) {
  try {
    const papel = JSON.parse(Buffer.from(chave.split(".")[1], "base64url").toString()).role;
    if (papel !== "anon") falha(`a chave informada é "${papel}". Use a chave pública (anon).`);
  } catch (e) { if (e?.code !== undefined) throw e; }
}
const saida = path.join(RAIZ, "site/config.js");
fs.writeFileSync(saida, `window.BETEL_SUPABASE = ${JSON.stringify({ url, anonKey: chave })};\n`);
console.log(`site/config.js gerado para ${url}`);
