// =====================================================================
// Servidor do Sistema Betel (Render ou qualquer servidor com Node 20+ e PostgreSQL 14+).
// Serve o site, a Área de Membros e a Agenda Ministerial, e a API do sistema.
// Ao iniciar, instala ou atualiza o banco sozinho.
//
// Variáveis de ambiente:
//   DATABASE_URL   endereço do PostgreSQL (no Render: preenchido pelo render.yaml)
//   JWT_SECRET     segredo das sessões, 32+ caracteres (no Render: gerado automaticamente)
//   PORT           porta (o Render define)
//   PUBLIC_URL     endereço público, ex.: https://betelflamengo.com.br (opcional; senão usa o do acesso)
//   BETEL_MASTERS  primeiros administradores: "Nome|email|telefone;Nome|email|telefone" (só na 1ª vez)
//   SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM   e-mail de recuperação de senha (opcional)
//   DATABASE_SSL   "true" para conexão externa com SSL (o endereço interno do Render não precisa)
// =====================================================================
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";
import pg from "pg";
import { createClient } from "@supabase/supabase-js";
import { criarApi } from "../nucleo/api.mjs";
import { instalarNoBanco } from "../nucleo/etapas.mjs";
import { criarHandler as fnUsuarios } from "../funcoes/admin-usuarios.mjs";
import { criarHandler as fnAcesso } from "../funcoes/aprovar-acesso.mjs";
import { criarHandler as fnArquivos } from "../funcoes/arquivos.mjs";

const AQUI = path.dirname(fileURLToPath(import.meta.url));
const RAIZ = path.resolve(AQUI, "..");
const SITE = path.resolve(process.env.SITE_DIR || path.join(RAIZ, "site"));
const PORTA = Number(process.env.PORT || process.env.PORTA || 8095);
const TESTE = process.env.BETEL_MODO_TESTE === "1";
const URL_INTERNA = `http://127.0.0.1:${PORTA}`;
const log = (...a) => console.log(new Date().toISOString(), ...a);

// ---------------- banco
let URL_BANCO = (process.env.DATABASE_URL || "").trim();
let SSL = process.env.DATABASE_SSL === "true" ? { rejectUnauthorized: false } : undefined;
if (URL_BANCO) {
  // "sslmode=..." na URL ou endereço EXTERNO do Render (…render.com): conexão com SSL (certificado do Render)
  try { const u = new URL(URL_BANCO); const modo = u.searchParams.get("sslmode");
    if ((modo && modo !== "disable") || /\.render\.com$/i.test(u.hostname)) SSL = SSL || { rejectUnauthorized: false };
    if (modo) { u.searchParams.delete("sslmode"); URL_BANCO = u.toString(); } } catch (_) {}
}
pg.types.setTypeParser(1082, (v) => v);   // datas (date) como "AAAA-MM-DD"
const pool = new pg.Pool(URL_BANCO ? { connectionString: URL_BANCO, ssl: SSL, max: 10, connectionTimeoutMillis: 15000 }
  : { host: process.env.PGHOST || "/tmp", port: Number(process.env.PGPORT || 5434), user: process.env.PGUSER || "postgres", database: process.env.PGDATABASE || "betel", password: process.env.PGPASSWORD, max: 10 });
pool.on("error", (e) => log("Erro de conexão com o banco:", e.message));
async function transacao(claims, papel, fn) {
  const cli = await pool.connect();
  try {
    await cli.query("begin");
    if (papel) await cli.query(`set local role ${papel}`);
    await cli.query("select set_config('request.jwt.claims', $1, true)", [JSON.stringify(claims || { role: "service_role" })]);
    const r = await fn((sql, p) => cli.query(sql, p));
    await cli.query("commit");
    return r;
  } catch (e) { await cli.query("rollback").catch(() => {}); throw e; } finally { cli.release(); }
}
const db = {
  comoPapel: (claims, fn) => transacao(claims, ["anon", "authenticated"].includes(claims?.role) ? claims.role : "anon", fn),
  comoDono: (fn, claims) => transacao(claims || { role: "service_role" }, null, fn),
};

// ---------------- e-mail (opcional)
let transporte = null;
if (process.env.SMTP_HOST) {
  const nodemailer = (await import("nodemailer")).default;
  transporte = nodemailer.createTransport({ host: process.env.SMTP_HOST, port: Number(process.env.SMTP_PORT || 587), secure: Number(process.env.SMTP_PORT) === 465,
    auth: process.env.SMTP_USER ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS } : undefined });
}
export const caixaDeSaida = [];
async function enviarEmail(m) {
  if (TESTE) { caixaDeSaida.push(m); return true; }
  if (!transporte) { log(`Recuperação de senha pedida para ${m.para}, mas o e-mail (SMTP) não está configurado.`); return false; }
  try { await transporte.sendMail({ from: process.env.SMTP_FROM || process.env.SMTP_USER, to: m.para, subject: m.assunto, text: m.texto }); return true; }
  catch (e) { log("Falha ao enviar e-mail:", e.message); return false; }
}

// ---------------- segredo
// JWT_SECRET vem do Render (render.yaml gera sozinho). Se faltar, o servidor cria um e guarda no próprio banco,
// para as sessões continuarem válidas depois de reiniciar.
let SEGREDO = (process.env.JWT_SECRET || "").trim();
if (SEGREDO && SEGREDO.length < 32) { log("Aviso: JWT_SECRET tem menos de 32 caracteres; usando um segredo guardado no banco."); SEGREDO = ""; }
if (!SEGREDO && TESTE) SEGREDO = "segredo-local-de-testes-com-32-caracteres-ou-mais";
async function segredoDoBanco() {
  await pool.query("create schema if not exists sistema; create table if not exists sistema.segredos (nome text primary key, valor text not null)");
  await pool.query("insert into sistema.segredos (nome, valor) values ('jwt', $1) on conflict do nothing", [crypto.randomBytes(48).toString("hex")]);
  return (await pool.query("select valor from sistema.segredos where nome = 'jwt'")).rows[0].valor;
}

// ---------------- inicialização: espera o banco, instala o que falta e liga a API
// O site já responde enquanto isso (página "iniciando"), e nada derruba o servidor:
// se o banco ainda não estiver pronto (comum no primeiro deploy do Render), tenta de novo.
let api = null, pronto = false, situacao = "Iniciando…";
const espera = (ms) => new Promise((r) => setTimeout(r, ms));
function explicar(e) {
  const m = String(e?.message || e), c = e?.code || "";
  if (!URL_BANCO && !TESTE) return "DATABASE_URL não está definida. No Render, ela vem do banco betel-banco (render.yaml). Confira em Environment.";
  if (["ENOTFOUND", "EAI_AGAIN"].includes(c)) return "Endereço do banco não encontrado (o banco pode estar sendo criado). Se persistir, confira DATABASE_URL e se site e banco estão na MESMA região.";
  if (["ECONNREFUSED", "ETIMEDOUT", "ECONNRESET", "57P03"].includes(c) || /timeout|terminated|starting up/i.test(m)) return "O banco ainda não aceita conexões (pode estar sendo criado). Tentando de novo.";
  if (c === "28P01" || /password authentication/i.test(m)) return "Usuário ou senha do banco recusados. Use a DATABASE_URL do próprio banco (Internal Database URL).";
  if (c === "3D000") return "O banco informado em DATABASE_URL não existe.";
  if (/self.signed|SSL|ssl/i.test(m)) return "Problema de SSL na conexão. Use a Internal Database URL ou defina DATABASE_SSL=true.";
  if (/CREATEROLE|assumir os papéis|permission denied to (create|grant) role/i.test(m)) return "O usuário do banco não pode criar/assumir os papéis anon e authenticated (precisa de CREATEROLE). Use o usuário criado junto com o banco no Render.";
  return m;
}
async function iniciar() {
  for (let tentativa = 1; ; tentativa++) {
    try {
      situacao = "Conectando ao banco…";
      await pool.query("select 1");
      situacao = "Instalando/atualizando o banco…";
      const extras = process.env.BETEL_SEMENTE ? [{ nome: "002_semente_teste", sql: fs.readFileSync(process.env.BETEL_SEMENTE, "utf8") }] : [];
      await instalarNoBanco(pool, RAIZ, log, extras);
      if (!SEGREDO) SEGREDO = await segredoDoBanco();

    api = await criarApi({ db, segredo: SEGREDO, urlInterna: URL_INTERNA, createClient, enviarEmail, siteOrigem: process.env.PUBLIC_URL || "",
      urlPublica: (req) => (process.env.PUBLIC_URL || new URL(req.url).origin).replace(/\/$/, ""),
      funcoes: { "admin-usuarios": fnUsuarios, "aprovar-acesso": fnAcesso, arquivos: fnArquivos } });
    if (TESTE) fs.writeFileSync(path.resolve(process.env.CHAVES || "chaves.json"), JSON.stringify({ url: `http://localhost:${PORTA}`, anon: api.ANON, service: api.SERVICO }, null, 2));

    // primeiros administradores (só funciona enquanto nenhum MASTER concluiu o primeiro acesso)
    if (process.env.BETEL_MASTERS) {
      const admin = createClient(URL_INTERNA, api.SERVICO, { auth: { persistSession: false, autoRefreshToken: false } });
      setTimeout(async () => {
        for (const item of process.env.BETEL_MASTERS.split(";").map((x) => x.trim()).filter(Boolean)) {
          const [nome, email, telefone] = item.split("|").map((x) => (x || "").trim());
          if (!nome || !email) continue;
          if ((await pool.query("select 1 from auth.users where email = lower($1)", [email])).rowCount) continue;
          const alfa = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"; const b = crypto.randomBytes(12);
          let senha = ""; for (let i = 0; i < 12; i++) { senha += alfa[b[i] % alfa.length]; if (i === 3 || i === 7) senha += "-"; }
          senha += "7a";
          const { data, error } = await admin.auth.admin.createUser({ email, password: senha, email_confirm: true, user_metadata: { nome } });
          if (error) { log(`MASTER ${email}: ${error.message}`); continue; }
          const { error: e2 } = await admin.rpc("servico_criar_usuario", { p_ator: null, p_usuario: data.user.id, p_nome: nome, p_telefone: (telefone || "").replace(/\D/g, ""),
            p_email: email.toLowerCase(), p_perfil: "MASTER", p_atribuicoes: [], p_ministerios: [], p_solicitacao: null });
          if (e2) { await admin.auth.admin.deleteUser(data.user.id); log(`MASTER ${email}: ${e2.message}`); continue; }
          log(`MASTER criado: ${nome} <${email}> — senha temporária: ${senha} (troca obrigatória no primeiro acesso)`);
        }
      }, 500);
    }

    // tarefas periódicas (prazos das escalas da Mídia e limpeza de sessões vencidas), a cada 15 minutos
    setInterval(() => api.tarefas().catch((e) => log("Tarefas:", e.message)), 15 * 60e3).unref();

      pronto = true; situacao = "ok";
      log("Sistema pronto.");
      return;
    } catch (e) {
      const ms = Math.min(60e3, 5e3 * tentativa);
      situacao = explicar(e);
      log(`Ainda não foi possível iniciar (tentativa ${tentativa}): ${situacao}${situacao !== String(e?.message) ? `  [detalhe: ${e?.code || ""} ${e?.message}]` : ""} — nova tentativa em ${ms / 1000}s.`);
      await espera(ms);
    }
  }
}

// ---------------- HTTP
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
  ".png": "image/png", ".mp4": "video/mp4", ".svg": "image/svg+xml", ".mp3": "audio/mpeg", ".webp": "image/webp", ".ico": "image/x-icon", ".json": "application/json", ".pdf": "application/pdf", ".woff2": "font/woff2" };
const SEGURANCA = { "X-Content-Type-Options": "nosniff", "Referrer-Policy": "strict-origin-when-cross-origin", "X-Frame-Options": "SAMEORIGIN",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()", ...(process.env.PUBLIC_URL?.startsWith("https") ? { "Strict-Transport-Security": "max-age=31536000" } : {}) };
const LIMITE_CORPO = 8 * 1024 * 1024;

function lerCorpo(req) {
  return new Promise((ok, falha) => { const partes = []; let n = 0;
    req.on("data", (c) => { n += c.length; if (n > LIMITE_CORPO) { falha(Object.assign(new Error("muito grande"), { status: 413 })); req.destroy(); } else partes.push(c); });
    req.on("end", () => ok(Buffer.concat(partes))); req.on("error", falha); });
}
function origem(req) { return process.env.PUBLIC_URL ? process.env.PUBLIC_URL.replace(/\/$/, "") : `${req.headers["x-forwarded-proto"] || "http"}://${req.headers.host}`; }

http.createServer(async (req, res) => {
  try {
    const base = origem(req), propria = `${req.headers["x-forwarded-proto"] || "http"}://${req.headers.host}`;
    const url = new URL(req.url, base);
    if (url.pathname === "/saude") { res.writeHead(pronto ? 200 : 503, { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" }); return res.end(pronto ? "ok" : situacao); }
    if (!pronto) {
      res.writeHead(503, { "Content-Type": "text/html; charset=utf-8", "Retry-After": "15", "Cache-Control": "no-store", ...SEGURANCA });
      return res.end(`<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="15"><title>Igreja Batista Betel</title>
<body style="margin:0;min-height:100vh;display:grid;place-items:center;background:#1C0909;color:#FBEFE0;font:16px/1.6 system-ui,sans-serif;text-align:center;padding:24px">
<div><p style="color:#FFE1B2;letter-spacing:.14em;font-size:12px;text-transform:uppercase">Igreja Batista Betel</p><h1 style="font-weight:600">O site está iniciando.</h1><p>Esta página se atualiza sozinha em alguns segundos.</p></div></body></html>`);
    }
    if (url.pathname === "/config.js") {   // o site descobre sozinho o endereço da API e a chave pública
      res.writeHead(200, { "Content-Type": "text/javascript; charset=utf-8", "Cache-Control": "no-store", ...SEGURANCA });
      return res.end(`window.BETEL_SUPABASE = { url: ${JSON.stringify(TESTE ? `http://localhost:${PORTA}` : propria)}, anonKey: ${JSON.stringify(api.ANON)}, recuperacaoPorEmail: ${TESTE || !!transporte} };\n`);
    }
    if (TESTE && url.pathname === "/_dev/caixa") { res.writeHead(200, { "Content-Type": "application/json" }); return res.end(JSON.stringify(caixaDeSaida)); }
    if (/^\/(auth|rest|storage|functions)\/v1\//.test(url.pathname) || req.method === "OPTIONS") {
      const corpo = ["GET", "HEAD", "OPTIONS"].includes(req.method) ? undefined : await lerCorpo(req);
      const headers = new Headers(); for (const [k, v] of Object.entries(req.headers)) if (typeof v === "string") headers.set(k, v);
      const r = await api.tratar(new Request(url, { method: req.method, headers, body: corpo }));
      if (r) {
        const h = Object.fromEntries(r.headers); const cors = TESTE ? "*" : propria;
        res.writeHead(r.status, { ...h, ...SEGURANCA, "Access-Control-Allow-Origin": cors, "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, prefer, accept-profile, content-profile, x-supabase-api-version, x-upsert",
          "Access-Control-Allow-Methods": "GET,POST,PUT,PATCH,DELETE,OPTIONS", Vary: "Origin" });
        return res.end(Buffer.from(await r.arrayBuffer()));
      }
    }
    // ícone da aba: usa o logo do site (evita erro 404 no navegador)
    if (url.pathname === "/favicon.ico" && !fs.existsSync(path.join(SITE, "favicon.ico"))) {
      const logo = path.join(SITE, "img", "logo.png");
      if (fs.existsSync(logo)) { res.writeHead(200, { "Content-Type": "image/png", "Cache-Control": "public, max-age=86400", ...SEGURANCA }); return fs.createReadStream(logo).pipe(res); }
      res.writeHead(204); return res.end();
    }
    // arquivos do site
    let f = path.join(SITE, decodeURIComponent(url.pathname === "/" ? "/index.html" : url.pathname));
    if (f.startsWith(SITE) && fs.existsSync(f) && fs.statSync(f).isDirectory()) {
      // pasta sem "/" no fim: redireciona (os caminhos relativos da página dependem disso)
      if (!url.pathname.endsWith("/")) { res.writeHead(301, { Location: url.pathname + "/" + url.search, ...SEGURANCA }); return res.end(); }
      f = path.join(f, "index.html");
    }
    // formulário privado da Agenda: fora dos buscadores e sem enviar o endereço (com o código) a outros sites
    const privado = url.pathname.startsWith("/agendaministerialprivada/") ? { "X-Robots-Tag": "noindex, nofollow", "Referrer-Policy": "no-referrer", "Cache-Control": "no-store" } : {};
    if (!f.startsWith(SITE + path.sep) && f !== SITE || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8", ...SEGURANCA }); return res.end("Página não encontrada"); }
    const ext = path.extname(f).toLowerCase(), st = fs.statSync(f);
    const cache = ext === ".html" ? "no-cache" : "public, max-age=86400";
    // vídeos: suporte a pedidos por partes (o navegador avança/retrocede sem baixar tudo)
    const faixa = req.headers.range && /^bytes=(\d*)-(\d*)$/.exec(req.headers.range);
    if (faixa && [".mp4", ".mp3"].includes(ext)) {
      const ini = faixa[1] ? Number(faixa[1]) : 0, fim = faixa[2] ? Math.min(Number(faixa[2]), st.size - 1) : st.size - 1;
      res.writeHead(206, { "Content-Type": MIME[ext], "Content-Range": `bytes ${ini}-${fim}/${st.size}`, "Accept-Ranges": "bytes", "Content-Length": fim - ini + 1, "Cache-Control": cache, ...SEGURANCA });
      return fs.createReadStream(f, { start: ini, end: fim }).pipe(res);
    }
    res.writeHead(200, { "Content-Type": MIME[ext] || "application/octet-stream", "Content-Length": st.size, "Cache-Control": cache, ...(ext === ".mp4" ? { "Accept-Ranges": "bytes" } : {}), ...SEGURANCA, ...privado });
    if (req.method === "HEAD") return res.end();
    fs.createReadStream(f).pipe(res);
  } catch (e) {
    if (e.status === 413) { res.writeHead(413, { "Content-Type": "application/json" }); return res.end(JSON.stringify({ message: "Arquivo ou envio muito grande." })); }
    log(e); if (!res.headersSent) res.writeHead(500, { "Content-Type": "application/json" }); res.end(JSON.stringify({ message: "Erro interno." }));
  }
}).listen(PORTA, () => { log(`Sistema Betel no ar na porta ${PORTA}${TESTE ? " (modo de teste)" : ""}.`); iniciar(); });
process.on("unhandledRejection", (e) => log("Erro não tratado:", e?.message || e));
