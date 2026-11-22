// Confere o projeto antes de enviar ao GitHub / publicar. Não altera nada.
//   npm run verificar                      → confere arquivos e segredos
//   SUPABASE_URL=… SUPABASE_ANON_KEY=… npm run verificar → também testa a conexão com o projeto Supabase
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
const R = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
let erros = 0, avisos = 0;
const ok = (m) => console.log("  ✓ " + m), erro = (m) => { erros++; console.log("  ✗ " + m); }, aviso = (m) => { avisos++; console.log("  ! " + m); };
const ler = (p) => fs.readFileSync(path.join(R, p), "utf8");
const todos = (d, filtro = () => true) => fs.existsSync(path.join(R, d)) ? fs.readdirSync(path.join(R, d), { recursive: true }).map(String).filter((f) => fs.statSync(path.join(R, d, f)).isFile() && filtro(f)).map((f) => path.join(d, f)) : [];

console.log("\nMigrações (supabase/migrations)");
const mig = todos("supabase/migrations", (f) => f.endsWith(".sql")).sort();
mig.length >= 14 ? ok(`${mig.length} migrações (M00 a M13)`) : erro(`esperava 14 migrações, achei ${mig.length}`);
mig.some((f) => f.includes(".down.")) ? erro("há .down.sql dentro de supabase/migrations (o CLI aplicaria como migração)") : ok("reversões ficam em supabase/rollback");
const ts = mig.map((f) => path.basename(f).slice(0, 14)); new Set(ts).size === ts.length ? ok("versões únicas") : erro("versões repetidas");
const sql = mig.map((f) => [f, ler(f).replace(/--[^\n]*/g, "")]);
const proib = [[/create\s+schema\s+(if\s+not\s+exists\s+)?"?auth"?/i, "cria o schema auth"], [/create\s+table\s+(if\s+not\s+exists\s+)?"?auth"?\./i, "cria tabela no schema auth"],
  [/insert\s+into\s+"?auth"?\./i, "insere direto em tabela do auth"], [/alter\s+table\s+"?auth"?\./i, "altera tabela do auth"], [/drop\s+table\s+(if\s+exists\s+)?"?auth"?\./i, "apaga tabela do auth"],
  [/create\s+schema\s+(if\s+not\s+exists\s+)?"?storage"?/i, "cria o schema storage"], [/create\s+table\s+(if\s+not\s+exists\s+)?"?storage"?\./i, "cria tabela no schema storage"]];
for (const [re, m] of proib) { const q = sql.filter(([, s]) => re.test(s)).map(([f]) => path.basename(f)); q.length ? erro(`${m}: ${q.join(", ")}`) : ok(`nenhuma migração ${m}`); }
const tabelas = sql.flatMap(([, s]) => [...s.matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?public\.([a-z_]+)/gi)].map((m) => m[1]));
// RLS ligado diretamente ou num laço "foreach t in array[...] loop … enable row level security"
const emLaco = new Set(sql.flatMap(([, s]) => [...s.matchAll(/array\[([^\]]+)\]\s*loop[\s\S]{0,300}?enable\s+row\s+level\s+security/gi)].flatMap((m) => [...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]))));
const semRls = tabelas.filter((t) => !emLaco.has(t) && !sql.some(([, s]) => new RegExp(`alter\\s+table\\s+public\\.${t}\\s+enable\\s+row\\s+level\\s+security`, "i").test(s)));
semRls.length ? erro("tabelas sem RLS: " + semRls.join(", ")) : ok(`RLS ligado nas ${tabelas.length} tabelas criadas`);
["users", "profiles", "sessions", "identities"].some((t) => tabelas.includes(t)) ? erro("há tabela própria duplicando o Auth") : ok("nenhuma tabela própria de usuários/sessões (login é o Supabase Auth)");

console.log("\nEdge Functions (supabase/functions)");
for (const f of ["admin-usuarios", "aprovar-acesso", "arquivos"]) fs.existsSync(path.join(R, "supabase/functions", f, "index.ts")) ? ok(f) : erro(`falta ${f}`);

console.log("\nSegredos");
const publicos = [...todos("site"), ...todos("frontend")].filter((f) => /\.(html|js|css|json|txt)$/.test(f));
let achou = [];
for (const f of publicos) {
  const s = ler(f);
  if (/sb_secret_[A-Za-z0-9_-]{10,}/.test(s)) achou.push(f + " (chave secreta)");
  for (const m of s.matchAll(/eyJ[A-Za-z0-9_-]{10,}\.(eyJ[A-Za-z0-9_-]+)\.[A-Za-z0-9_-]+/g)) {
    try { if (JSON.parse(Buffer.from(m[1], "base64url").toString()).role === "service_role") achou.push(f + " (service_role)"); } catch {}
  }
}
achou.length ? erro("chave privada em arquivo público: " + achou.join(", ")) : ok("nenhuma chave service_role / secreta no site nem no frontend");
fs.existsSync(path.join(R, "site/config.js")) ? aviso("site/config.js existe: ele é gerado no build e não deve ir para o GitHub (está no .gitignore)") : ok("site/config.js não está no projeto (gerado no build)");
fs.existsSync(path.join(R, ".env")) && !ler(".gitignore").split("\n").includes(".env") ? erro(".env existe e não está no .gitignore") : ok(".env protegido pelo .gitignore");
const rnd = ler("render.yaml").split("\n").filter((l) => !/^\s*#/.test(l)).map((l) => l.replace(/\s#.*$/, "")).join("\n");
/type:\s*pserv|databases:|postgres/i.test(rnd) ? erro("render.yaml cria banco no Render") : ok("render.yaml não cria banco (o banco é o Supabase)");
/SERVICE_ROLE/i.test(rnd) ? erro("render.yaml menciona a chave service_role") : ok("render.yaml usa só a chave pública");

console.log("\nSite gerado (site/)");
for (const f of ["site/index.html", "site/vendor/supabase.js", "site/agenda-ministerial/index.html", "site/agendaministerialprivada/evento/index.html", "site/identidade.css"])
  fs.existsSync(path.join(R, f)) ? ok(f) : erro(`falta ${f} (rode npm run build)`);

const URL_ = (process.env.SUPABASE_URL || "").replace(/\/+$/, ""), ANON = process.env.SUPABASE_ANON_KEY;
if (URL_ && ANON) {
  console.log("\nConexão com o Supabase");
  const r = await fetch(`${URL_}/rest/v1/rpc/site_conteudo_publico`, { method: "POST", headers: { apikey: ANON, Authorization: `Bearer ${ANON}`, "Content-Type": "application/json" }, body: "{}" }).catch((e) => ({ ok: false, status: 0, text: async () => e.message }));
  r.ok ? ok("projeto responde e as migrações até a M12 estão aplicadas") : erro(`site_conteudo_publico respondeu ${r.status}: ${(await r.text()).slice(0, 160)}`);
  const s = await fetch(`${URL_}/auth/v1/settings`, { headers: { apikey: ANON } }).then((x) => x.json()).catch(() => null);
  if (s) s.disable_signup ? ok("cadastro aberto no Auth desligado (só o MASTER cria contas)") : aviso("Authentication → Sign In / Providers: desligue \"Allow new users to sign up\"");
}
console.log(`\n${erros ? "✗" : "✓"} ${erros} erro(s), ${avisos} aviso(s)`);
process.exit(erros ? 1 : 0);
