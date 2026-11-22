// Confere se o projeto está pronto para subir e, se houver DATABASE_URL, se o banco aceita a instalação.
//   npm run verificar
// Não altera nada no banco (testes de permissão rodam dentro de uma transação desfeita no final).
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
try { for (const l of fs.readFileSync(path.join(RAIZ, ".env"), "utf8").split(/\r?\n/)) { const m = l.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)\s*$/); if (m && m[2] !== "" && process.env[m[1]] === undefined) process.env[m[1]] = m[2].replace(/^["']|["']$/g, ""); } } catch (_) {}
let falhas = 0, avisos = 0;
const ok = (t) => console.log("  ✓ " + t), erro = (t) => { falhas++; console.log("  ✗ " + t); }, aviso = (t) => { avisos++; console.log("  ! " + t); };

console.log("\nArquivos do projeto");
const exigidos = ["render.yaml", "package.json", "package-lock.json", "servidor/servidor.mjs", "nucleo/api.mjs", "nucleo/instalar.mjs", "nucleo/etapas.mjs",
  "funcoes/comum.mjs", "funcoes/admin-usuarios.mjs", "funcoes/aprovar-acesso.mjs", "funcoes/arquivos.mjs",
  "database/plataforma/000_plataforma.sql", "database/plataforma/001_agenda_base.sql", "site/index.html", "site/vendor/supabase.js",
  "site/componentes.js", "site/identidade.css", "site/agenda-ministerial/index.html", "site/agenda-ministerial/agenda.css", "site/img/logo.png"];
const faltando = exigidos.filter((f) => !fs.existsSync(path.join(RAIZ, f)));
faltando.length ? erro("Faltam arquivos (o envio para o GitHub ficou incompleto?): " + faltando.join(", ")) : ok(`${exigidos.length} arquivos essenciais presentes`);
const migr = fs.existsSync(path.join(RAIZ, "database/migrations")) ? fs.readdirSync(path.join(RAIZ, "database/migrations")).filter((f) => f.endsWith(".sql") && !f.includes(".down.")) : [];
migr.length >= 12 ? ok(`${migr.length} migrações em database/migrations`) : erro(`Só ${migr.length} migrações em database/migrations (esperado 12 ou mais)`);
if (fs.existsSync(path.join(RAIZ, "site/config.js"))) aviso("site/config.js existe; o servidor gera esse arquivo sozinho — pode apagar");
try {
  const pkg = JSON.parse(fs.readFileSync(path.join(RAIZ, "package.json"), "utf8")), lock = JSON.parse(fs.readFileSync(path.join(RAIZ, "package-lock.json"), "utf8"));
  const dif = Object.keys(pkg.dependencies || {}).filter((d) => !lock.packages?.["node_modules/" + d]);
  dif.length ? erro("package-lock.json não tem: " + dif.join(", ") + " (rode npm install e envie o package-lock.json)") : ok("package.json e package-lock.json combinam");
} catch (e) { erro("package.json ou package-lock.json inválido: " + e.message); }
const yaml = fs.existsSync(path.join(RAIZ, "render.yaml")) ? fs.readFileSync(path.join(RAIZ, "render.yaml"), "utf8") : "";
/startCommand:\s*npm start/.test(yaml) && /healthCheckPath:\s*\/saude/.test(yaml) && /fromDatabase/.test(yaml) ? ok("render.yaml com início, verificação de saúde e banco ligado") : erro("render.yaml incompleto");
const [maior] = process.versions.node.split(".").map(Number);
maior >= 20 ? ok("Node " + process.versions.node) : erro("Node " + process.versions.node + " — precisa ser 20 ou mais novo");

console.log("\nVariáveis de ambiente");
const jwt = process.env.JWT_SECRET || "";
jwt.length >= 32 ? ok("JWT_SECRET definido") : aviso("JWT_SECRET ausente ou curto: o servidor cria um e guarda no banco (no Render o render.yaml já gera)");
process.env.BETEL_MASTERS ? ok("BETEL_MASTERS definido (" + process.env.BETEL_MASTERS.split(";").filter((x) => x.includes("|")).length + " pessoa(s))") : aviso("BETEL_MASTERS vazio: nenhum administrador será criado na primeira subida");
if (process.env.BETEL_MASTERS) for (const p of process.env.BETEL_MASTERS.split(";").map((x) => x.trim()).filter(Boolean)) { const [n, e] = p.split("|"); if (!n || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test((e || "").trim())) erro(`BETEL_MASTERS: item mal escrito "${p}" (use Nome|email|telefone; separe pessoas com ;)`); }
if (process.env.PUBLIC_URL && !/^https?:\/\/[^/]+\/?$/.test(process.env.PUBLIC_URL)) erro("PUBLIC_URL deve ser só o endereço, ex.: https://betelflamengo.com.br");

console.log("\nBanco de dados");
if (!process.env.DATABASE_URL) aviso("DATABASE_URL não definida aqui — teste do banco pulado (no Render ela vem do betel-banco)");
else {
  const pg = (await import("pg")).default;
  let url = process.env.DATABASE_URL, ssl;
  try { const u = new URL(url); const modo = u.searchParams.get("sslmode"); if ((modo && modo !== "disable") || /\.render\.com$/i.test(u.hostname) || process.env.DATABASE_SSL === "true") ssl = { rejectUnauthorized: false }; if (modo) { u.searchParams.delete("sslmode"); url = u.toString(); } } catch (_) {}
  const c = new pg.Client({ connectionString: url, ssl, connectionTimeoutMillis: 15000 });
  try {
    await c.connect(); ok("conexão com o banco");
    const v = (await c.query("show server_version_num")).rows[0].server_version_num;
    Number(v) >= 140000 ? ok("PostgreSQL " + (await c.query("show server_version")).rows[0].server_version) : erro("PostgreSQL muito antigo (precisa 14+)");
    const r = (await c.query("select rolsuper, rolcreaterole from pg_roles where rolname = current_user")).rows[0];
    r.rolsuper || r.rolcreaterole ? ok("o usuário do banco pode criar papéis (CREATEROLE)") : erro("o usuário do banco NÃO tem CREATEROLE — use o usuário criado junto com o banco no Render");
    await c.query("begin");
    try {
      await c.query("create role betel_verificacao_tmp nologin");
      await c.query("do $$ begin execute format('grant betel_verificacao_tmp to %I', current_user); end $$");
      await c.query("set local role betel_verificacao_tmp"); await c.query("reset role");
      ok("consegue assumir os papéis de visitante/usuário (necessário para as permissões)");
    } catch (e) { erro("não consegue criar/assumir papéis: " + e.message); }
    await c.query("rollback");
    const tem = (await c.query("select to_regclass('sistema.migracoes') is not null as t")).rows[0].t;
    if (tem) { const n = (await c.query("select count(*)::int n from sistema.migracoes")).rows[0].n; ok(`banco já instalado (${n} etapa(s) registradas)`); }
    else ok("banco vazio: o sistema será instalado na primeira subida");
  } catch (e) { erro("banco: " + e.message); }
  finally { await c.end().catch(() => {}); }
}

console.log(falhas ? `\n✗ ${falhas} problema(s) para corrigir antes de subir.` : `\n✓ Tudo certo${avisos ? ` (${avisos} aviso(s))` : ""}.`);
process.exit(falhas ? 1 : 0);
