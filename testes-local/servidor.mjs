// =====================================================================
// Ambiente LOCAL de testes que imita as APIs do Supabase usadas pelo site
// (Auth, REST/RPC e Edge Functions) sobre um PostgreSQL real.
// Serve só para testar a migração, o RLS, as funções e as telas antes de
// aplicar no projeto Supabase oficial. Não vai para produção.
// =====================================================================
import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import pg from "pg";
import bcrypt from "bcryptjs";
import { createClient } from "@supabase/supabase-js";

const PORTA = Number(process.env.PORTA || 8095);
const BASE = `http://localhost:${PORTA}`;
const SEGREDO = "segredo-local-de-testes-com-32-caracteres-ou-mais";
const SITE = path.resolve(process.env.SITE_DIR || "../site");
const pool = new pg.Pool({ host: "/tmp", port: 5434, user: "postgres", database: "betel", max: 8 });

const b64 = (o) => Buffer.from(typeof o === "string" ? o : JSON.stringify(o)).toString("base64url");
function assinar(claims) {
  const h = b64({ alg: "HS256", typ: "JWT" }), p = b64(claims);
  const s = crypto.createHmac("sha256", SEGREDO).update(h + "." + p).digest("base64url");
  return `${h}.${p}.${s}`;
}
function verificar(token) {
  const [h, p, s] = String(token || "").split(".");
  if (!s) return null;
  const ok = crypto.createHmac("sha256", SEGREDO).update(h + "." + p).digest("base64url");
  if (ok.length !== s.length || !crypto.timingSafeEqual(Buffer.from(ok), Buffer.from(s))) return null;
  const c = JSON.parse(Buffer.from(p, "base64url").toString());
  if (c.exp && c.exp < Date.now() / 1000) return null;
  return c;
}
export const ANON_KEY = assinar({ role: "anon", iss: "supabase-local" });
export const SERVICE_KEY = assinar({ role: "service_role", iss: "supabase-local" });
fs.writeFileSync(path.resolve("chaves.json"), JSON.stringify({ url: BASE, anon: ANON_KEY, service: SERVICE_KEY }, null, 2));

const refresh = new Map();   // refresh_token -> user id
const sessaoDoRefresh = new Map();   // refresh_token -> session_id (para o logout, como no Supabase Auth)
const recuperacao = new Map(); // token -> user id
export const caixaDeSaida = [];
const PASSWORD_MIN = 10;

function resp(res, status, corpo, extra = {}) {
  res.writeHead(status, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, prefer, accept-profile, content-profile, x-supabase-api-version, x-upsert, cache-control, x-region",
    "Access-Control-Allow-Methods": "GET,POST,PUT,PATCH,DELETE,OPTIONS", ...extra });
  res.end(corpo === undefined ? "" : JSON.stringify(corpo));
}
const erroAuth = (res, status, code, msg) => resp(res, status, { code: status, error_code: code, msg });
const lerCorpo = (req) => new Promise((ok) => { let d = ""; req.on("data", (c) => (d += c)); req.on("end", () => ok(d)); });

function token(req) {
  const a = req.headers.authorization || "";
  return a.startsWith("Bearer ") ? a.slice(7) : req.headers.apikey || "";
}
async function usuarioPorId(id) {
  const { rows } = await pool.query("select * from auth.users where id = $1", [id]);
  return rows[0];
}
function formatarUsuario(u) {
  return { id: u.id, aud: "authenticated", role: "authenticated", email: u.email, email_confirmed_at: u.email_confirmed_at,
    user_metadata: u.raw_user_meta_data || {}, app_metadata: { provider: "email", providers: ["email"], ...(u.raw_app_meta_data || {}) },
    banned_until: u.banned_until, created_at: u.created_at, updated_at: u.updated_at, last_sign_in_at: u.last_sign_in_at };
}
function sessao(u) {
  const agora = Math.floor(Date.now() / 1000), exp = agora + 3600;
  const session_id = crypto.randomUUID();
  const access_token = assinar({ sub: u.id, role: "authenticated", aud: "authenticated", email: u.email, iat: agora, exp, session_id });
  const refresh_token = crypto.randomBytes(24).toString("base64url");
  refresh.set(refresh_token, u.id); sessaoDoRefresh.set(refresh_token, session_id);
  return { access_token, token_type: "bearer", expires_in: 3600, expires_at: exp, refresh_token, user: formatarUsuario(u) };
}
const banido = (u) => u.banned_until && new Date(u.banned_until) > new Date();

async function auth(req, res, url) {
  const rota = url.pathname.replace("/auth/v1", "");
  const corpo = ["POST", "PUT"].includes(req.method) ? JSON.parse((await lerCorpo(req)) || "{}") : {};
  if (rota === "/token" && url.searchParams.get("grant_type") === "password") {
    const { rows } = await pool.query("select * from auth.users where email = lower($1)", [corpo.email || ""]);
    const u = rows[0];
    if (!u || !u.encrypted_password || !bcrypt.compareSync(String(corpo.password || ""), u.encrypted_password))
      return erroAuth(res, 400, "invalid_credentials", "Invalid login credentials");
    if (banido(u)) return erroAuth(res, 400, "user_banned", "User is banned");
    await pool.query("update auth.users set last_sign_in_at = now() where id = $1", [u.id]);
    return resp(res, 200, sessao(u));
  }
  if (rota === "/token" && url.searchParams.get("grant_type") === "refresh_token") {
    const id = refresh.get(corpo.refresh_token); refresh.delete(corpo.refresh_token);
    const u = id && (await usuarioPorId(id));
    if (!u || banido(u)) return erroAuth(res, 400, "refresh_token_not_found", "Invalid Refresh Token");
    return resp(res, 200, sessao(u));
  }
  if (rota === "/user") {
    const c = verificar(token(req));
    if (!c || !c.sub) return erroAuth(res, 401, "bad_jwt", "invalid JWT");
    let u = await usuarioPorId(c.sub);
    if (!u) return erroAuth(res, 404, "user_not_found", "User not found");
    if (req.method === "PUT" && corpo.password !== undefined) {
      if (String(corpo.password).length < PASSWORD_MIN) return erroAuth(res, 422, "weak_password", `Password should be at least ${PASSWORD_MIN} characters.`);
      if (bcrypt.compareSync(String(corpo.password), u.encrypted_password || "")) return erroAuth(res, 422, "same_password", "New password should be different from the old password.");
      await pool.query("update auth.users set encrypted_password = $2, updated_at = now() where id = $1", [u.id, bcrypt.hashSync(String(corpo.password), 10)]);
      u = await usuarioPorId(c.sub);
    }
    return resp(res, 200, formatarUsuario(u));
  }
  if (rota === "/logout") {
    // Como no Supabase Auth: scope=local encerra a sessão deste token; global, todas do usuário
    const c = verificar(token(req)); if (!c?.sub) return resp(res, 204);
    const global = (url.searchParams.get("scope") || "global") === "global";
    for (const [rt, uid] of refresh) if (uid === c.sub && (global || sessaoDoRefresh.get(rt) === c.session_id)) { refresh.delete(rt); sessaoDoRefresh.delete(rt); }
    return resp(res, 204);
  }
  if (rota === "/recover") {
    const { rows } = await pool.query("select * from auth.users where email = lower($1)", [corpo.email || ""]);
    if (rows[0]) {
      const t = crypto.randomBytes(20).toString("hex"); recuperacao.set(t, rows[0].id);
      const redirect = url.searchParams.get("redirect_to") || BASE;
      caixaDeSaida.push({ para: rows[0].email, assunto: "Redefinir senha", link: `${BASE}/auth/v1/verify?token=${t}&type=recovery&redirect_to=${encodeURIComponent(redirect)}` });
    }
    return resp(res, 200, {});
  }
  if (rota === "/verify" && req.method === "GET") {
    const id = recuperacao.get(url.searchParams.get("token")); recuperacao.delete(url.searchParams.get("token"));
    const redirect = url.searchParams.get("redirect_to") || BASE;
    const u = id && (await usuarioPorId(id));
    if (!u) { res.writeHead(303, { Location: `${redirect}#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired` }); return res.end(); }
    const s = sessao(u);
    res.writeHead(303, { Location: `${redirect}#access_token=${s.access_token}&expires_at=${s.expires_at}&expires_in=3600&refresh_token=${s.refresh_token}&token_type=bearer&type=recovery` });
    return res.end();
  }
  // ---- Admin (somente chave de serviço)
  if (rota.startsWith("/admin/users")) {
    const c = verificar(token(req));
    if (!c || c.role !== "service_role") return erroAuth(res, 403, "not_admin", "User not allowed");
    const id = rota.split("/")[3];
    if (req.method === "POST" && !id) {
      const email = String(corpo.email || "").toLowerCase();
      if (String(corpo.password || "").length < PASSWORD_MIN) return erroAuth(res, 422, "weak_password", "Password too short");
      const ex = await pool.query("select 1 from auth.users where email = $1", [email]);
      if (ex.rowCount) return erroAuth(res, 422, "email_exists", "A user with this email address has already been registered");
      const novo = crypto.randomUUID();
      await pool.query("insert into auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data) values ($1,$2,$3,$4,$5)",
        [novo, email, bcrypt.hashSync(String(corpo.password), 10), corpo.email_confirm ? new Date() : null, corpo.user_metadata || {}]);
      return resp(res, 200, formatarUsuario(await usuarioPorId(novo)));
    }
    const u = id && (await usuarioPorId(id));
    if (!u) return erroAuth(res, 404, "user_not_found", "User not found");
    if (req.method === "GET") return resp(res, 200, formatarUsuario(u));
    if (req.method === "PUT") {
      if (corpo.password !== undefined) await pool.query("update auth.users set encrypted_password = $2, updated_at = now() where id = $1", [id, bcrypt.hashSync(String(corpo.password), 10)]);
      if (corpo.ban_duration !== undefined) {
        const ate = corpo.ban_duration === "none" ? null : new Date(Date.now() + parseInt(corpo.ban_duration) * 3600e3);
        await pool.query("update auth.users set banned_until = $2 where id = $1", [id, ate]);
        if (ate) for (const [k, v] of refresh) if (v === id) refresh.delete(k);
      }
      return resp(res, 200, formatarUsuario(await usuarioPorId(id)));
    }
    if (req.method === "DELETE") { await pool.query("delete from auth.users where id = $1", [id]); return resp(res, 200, {}); }
  }
  return erroAuth(res, 404, "not_found", "Not found");
}

// ---- REST (subconjunto do PostgREST usado pelo site e pelas funções)
const ident = (s) => { if (!/^[a-z_][a-z0-9_]*$/.test(s)) throw new Error("identificador inválido"); return `"${s}"`; };
async function comPapel(claims, fn) {
  const cli = await pool.connect();
  try {
    await cli.query("begin");
    const papel = ["anon", "authenticated", "service_role"].includes(claims?.role) ? claims.role : "anon";
    await cli.query(`set local role ${papel}`);
    await cli.query("select set_config('request.jwt.claims', $1, true)", [JSON.stringify(claims || { role: "anon" })]);
    const r = await fn(cli);
    await cli.query("commit");
    return r;
  } catch (e) { await cli.query("rollback").catch(() => {}); throw e; } finally { cli.release(); }
}
function erroPg(res, e, claims) {
  const status = e.code === "42501" ? (claims?.role === "anon" ? 401 : 403) : e.code === "P0002" ? 404 : ["23505", "23P01"].includes(e.code) ? 409 : 400;
  return resp(res, status, { code: e.code, message: e.message, details: e.detail || null, hint: e.hint || null });
}
async function rest(req, res, url) {
  const c = verificar(token(req)) || { role: "anon" };
  const rota = url.pathname.replace("/rest/v1/", "");
  try {
    if (rota.startsWith("rpc/") && req.method === "POST") {
      const fn = ident(rota.slice(4));
      const args = JSON.parse((await lerCorpo(req)) || "{}");
      const nomes = Object.keys(args);
      if (!tiposFn[fn]) {
        const t = await pool.query("select a.n, a.t from pg_proc p, unnest(p.proargnames, p.proargtypes::regtype[]::text[]) as a(n, t) where p.proname = $1 and p.pronamespace = 'public'::regnamespace", [fn.replace(/"/g, "")]);
        tiposFn[fn] = Object.fromEntries(t.rows.map((r) => [r.n, r.t]));
      }
      const tipos = tiposFn[fn];
      const vals = nomes.map((k) => { const v = args[k]; if (v === null || v === undefined) return null; return /json/.test(tipos[k] || "") ? JSON.stringify(v) : v; });
      const sql = `select public.${fn}(${nomes.map((k, i) => `${ident(k)} => $${i + 1}::${tipos[k] || "text"}`).join(", ")}) as r`;
      const r = await comPapel(c, (cli) => cli.query(sql, vals));
      return resp(res, 200, r.rows[0].r);
    }
    if (req.method === "GET") {
      const tabela = ident(rota);
      const cols = (url.searchParams.get("select") || "*").split(",").map((x) => (x === "*" ? "*" : ident(x.trim()))).join(",");
      const filtros = [], vals = [];
      for (const [k, v] of url.searchParams) {
        if (["select", "order", "limit", "offset"].includes(k)) continue;
        const [op, ...resto] = v.split("."); const val = resto.join(".");
        if (op === "eq") { vals.push(val); filtros.push(`${ident(k)}::text = $${vals.length}`); }
        else if (op === "is" && val === "null") filtros.push(`${ident(k)} is null`);
        else if (op === "in" && /^\(.*\)$/.test(val)) { vals.push(val.slice(1, -1).split(",").map((x) => x.replace(/^"|"$/g, ""))); filtros.push(`${ident(k)}::text = any($${vals.length}::text[])`); }
        else if (["neq", "gt", "gte", "lt", "lte"].includes(op)) { vals.push(val); filtros.push(`${ident(k)}::text ${{ neq: "<>", gt: ">", gte: ">=", lt: "<", lte: "<=" }[op]} $${vals.length}`); }
        else throw Object.assign(new Error("filtro não suportado no ambiente local"), { code: "PGRST100" });
      }
      const ord = url.searchParams.get("order"); const lim = parseInt(url.searchParams.get("limit") || "1000");
      const sql = `select ${cols} from public.${tabela}${filtros.length ? " where " + filtros.join(" and ") : ""}${ord ? ` order by ${ident(ord.split(".")[0])} ${ord.includes(".desc") ? "desc" : "asc"}` : ""} limit ${lim}`;
      const r = await comPapel(c, (cli) => cli.query(sql, vals));
      if (String(req.headers.accept || "").includes("vnd.pgrst.object")) {
        if (r.rows.length !== 1) return resp(res, 406, { code: "PGRST116", message: "JSON object requested, multiple (or no) rows returned", details: `The result contains ${r.rows.length} rows`, hint: null });
        return resp(res, 200, r.rows[0]);
      }
      return resp(res, 200, r.rows);
    }
    // Escrita direta nas tabelas: reproduz o PostgREST rodando com o papel do usuário
    if (["POST", "PATCH", "DELETE"].includes(req.method)) {
      const tabela = ident(rota); const corpo = JSON.parse((await lerCorpo(req)) || "{}");
      const r = await comPapel(c, async (cli) => {
        if (req.method === "POST") {
          const linhas = Array.isArray(corpo) ? corpo : [corpo];
          const ks = [...new Set(linhas.flatMap((l) => Object.keys(l)))]; const vals = []; const tuplas = [];
          for (const l of linhas) { tuplas.push("(" + ks.map((k) => { if (!(k in l)) return "default"; vals.push(l[k]); return "$" + vals.length; }).join(",") + ")"); }
          return cli.query(`insert into public.${tabela} (${ks.map(ident).join(",")}) values ${tuplas.join(",")} returning *`, vals);
        }
        const filtros = [], vals = [];
        for (const [k, v] of url.searchParams) { if (v.startsWith("eq.")) { vals.push(v.slice(3)); filtros.push(`${ident(k)}::text = $${vals.length}`); } }
        if (req.method === "DELETE") return cli.query(`delete from public.${tabela} where ${filtros.join(" and ") || "true"} returning *`, vals);
        const ks = Object.keys(corpo); const base = vals.length;
        return cli.query(`update public.${tabela} set ${ks.map((k, i) => `${ident(k)} = $${base + i + 1}`).join(",")} where ${filtros.join(" and ") || "true"} returning *`, [...vals, ...ks.map((k) => corpo[k])]);
      });
      return resp(res, 200, r.rows);
    }
  } catch (e) { return erroPg(res, e, c); }
  return resp(res, 404, { message: "não encontrado" });
}

// ---- Storage (subconjunto): espaço "cursos" público; envio só para quem a política do banco permite
const BUCKETS = {
  cursos: { publico: true, limite: 2097152, tipos: ["image/jpeg", "image/png", "image/webp"], permissao: "select public.cursos_gestor() as ok" },
  comprovantes: { publico: false, limite: 5242880, tipos: ["application/pdf", "image/jpeg", "image/png", "image/webp"], permissao: "select false as ok" },
  documentos: { publico: false, limite: 5242880, tipos: ["application/pdf", "image/jpeg", "image/png", "image/webp"], permissao: "select false as ok" },
};
const assinarArquivo = (b, p, exp) => crypto.createHmac("sha256", SEGREDO).update(`${b}/${p}:${exp}`).digest("base64url");
async function storage(req, res, url) {
  const partes = url.pathname.replace("/storage/v1/object/", "").split("/");
  const servico = (verificar(token(req)) || {}).role === "service_role";
  if (partes[0] === "sign" && req.method === "POST") {   // link temporário: só a chave de serviço
    if (!servico) return resp(res, 403, { message: "not allowed" });
    const [, bucket, ...resto] = partes; const corpo = JSON.parse((await lerCorpo(req)) || "{}");
    const exp = Math.floor(Date.now() / 1000) + Number(corpo.expiresIn || 60); const p = resto.join("/");
    return resp(res, 200, { signedURL: `/object/sign/${bucket}/${p}?token=${exp}.${assinarArquivo(bucket, p, exp)}` });
  }
  if (partes[0] === "sign" && req.method === "GET") {
    const [, bucket, ...resto] = partes; const p = resto.join("/"); const [exp, sig] = String(url.searchParams.get("token") || "").split(".");
    if (!exp || Number(exp) < Date.now() / 1000 || sig !== assinarArquivo(bucket, p, exp)) return resp(res, 400, { message: "InvalidSignature" });
    const f = path.resolve("_storage", bucket, ...resto); if (!fs.existsSync(f)) return resp(res, 404, { message: "Object not found" });
    res.writeHead(200, { "Content-Type": fs.readFileSync(f + ".tipo", "utf8") }); return fs.createReadStream(f).pipe(res);
  }
  if (req.method === "DELETE") {
    if (!servico) return resp(res, 403, { message: "not allowed" });
    const corpo = JSON.parse((await lerCorpo(req)) || "{}"); const bucket = partes[0];
    for (const p of corpo.prefixes || []) { const f = path.resolve("_storage", bucket, p); if (f.startsWith(path.resolve("_storage")) && fs.existsSync(f)) { fs.unlinkSync(f); fs.unlinkSync(f + ".tipo"); } }
    return resp(res, 200, []);
  }
  // Buckets do Storage do Supabase (storage.buckets/storage.objects com RLS), quando existirem no banco
  const bk = async (b) => { try { return (await pool.query("select * from storage.buckets where id = $1", [b])).rows[0]; } catch { return null; } };
  if (partes[0] === "public" && req.method === "GET" && !BUCKETS[partes[1]]) {
    const [, bucket, ...resto] = partes; const nome = resto.join("/"); const b = await bk(bucket);
    const obj = b?.public ? (await pool.query("select metadata from storage.objects where bucket_id = $1 and name = $2", [bucket, nome])).rows[0] : null;
    const f = path.resolve("_storage", bucket, ...resto);
    if (!obj || !f.startsWith(path.resolve("_storage")) || !fs.existsSync(f)) return resp(res, 404, { message: "Object not found" });
    res.writeHead(200, { "Content-Type": obj.metadata?.mimetype || "application/octet-stream", "Access-Control-Allow-Origin": "*" }); return fs.createReadStream(f).pipe(res);
  }
  if (["POST", "PUT"].includes(req.method) && !BUCKETS[partes[0]] && partes[0] !== "sign" && partes[0] !== "list") {
    const [bucket, ...resto] = partes; const b = await bk(bucket); const nome = resto.join("/");
    if (!b || !resto.length || resto.some((x) => x === ".." || !/^[\w.\-]+$/.test(x))) return resp(res, 400, { message: "Bucket not found" });
    const tipo = String(req.headers["content-type"] || "").split(";")[0];
    if (b.allowed_mime_types && !b.allowed_mime_types.includes(tipo)) return resp(res, 415, { statusCode: "415", error: "invalid_mime_type", message: `mime type ${tipo} is not supported` });
    const pc = []; let tam = 0;
    for await (const ch of req) { tam += ch.length; pc.push(ch); }   // lê tudo antes de responder (conexão reaproveitada)
    if (b.file_size_limit && tam > Number(b.file_size_limit)) return resp(res, 413, { statusCode: "413", error: "Payload too large", message: "The object exceeded the maximum allowed size" });
    const c = verificar(token(req)) || { role: "anon" };
    try { await comPapel(c, (cli) => cli.query("insert into storage.objects (bucket_id, name, metadata) values ($1, $2, $3)", [bucket, nome, { mimetype: tipo, size: tam }])); }
    catch (e) { return resp(res, e.code === "23505" ? 409 : 403, { statusCode: e.code === "23505" ? "409" : "403", error: "Unauthorized", message: e.code === "23505" ? "The resource already exists" : "new row violates row-level security policy" }); }
    const f = path.resolve("_storage", bucket, ...resto); fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, Buffer.concat(pc));
    return resp(res, 200, { Key: `${bucket}/${nome}`, Id: crypto.randomUUID() });
  }
  if (partes[0] === "public" && req.method === "GET") {
    const [, bucket, ...resto] = partes; const f = path.resolve("_storage", bucket, ...resto);
    if (!BUCKETS[bucket] || !BUCKETS[bucket].publico || !f.startsWith(path.resolve("_storage")) || !fs.existsSync(f)) return resp(res, 404, { message: "Object not found" });
    res.writeHead(200, { "Content-Type": fs.readFileSync(f + ".tipo", "utf8"), "Access-Control-Allow-Origin": "*" }); return fs.createReadStream(f).pipe(res);
  }
  if (["POST", "PUT"].includes(req.method)) {
    const [bucket, ...resto] = partes; const cfg = BUCKETS[bucket];
    if (!cfg || !resto.length || resto.some((x) => x === ".." || !/^[\w.\-]+$/.test(x))) return resp(res, 400, { message: "Caminho inválido" });
    const c = verificar(token(req)) || { role: "anon" };
    const ok = servico || await comPapel(c, (cli) => cli.query(cfg.permissao)).then((r) => r.rows[0].ok).catch(() => false);
    if (!ok) return resp(res, 403, { statusCode: "403", error: "Unauthorized", message: "new row violates row-level security policy" });
    const tipo = String(req.headers["content-type"] || "").split(";")[0];
    if (!cfg.tipos.includes(tipo)) return resp(res, 415, { statusCode: "415", error: "invalid_mime_type", message: `mime type ${tipo} is not supported` });
    const partesCorpo = []; let tam = 0;
    for await (const ch of req) { tam += ch.length; if (tam > cfg.limite) return resp(res, 413, { statusCode: "413", error: "Payload too large", message: "The object exceeded the maximum allowed size" }); partesCorpo.push(ch); }
    const f = path.resolve("_storage", bucket, ...resto); fs.mkdirSync(path.dirname(f), { recursive: true });
    fs.writeFileSync(f, Buffer.concat(partesCorpo)); fs.writeFileSync(f + ".tipo", tipo);
    return resp(res, 200, { Key: `${bucket}/${resto.join("/")}`, Id: crypto.randomUUID() });
  }
  return resp(res, 404, { message: "não suportado no ambiente local" });
}

// ---- Edge Functions (o mesmo código que vai para o Supabase)
const handlers = {};
const tiposFn = {};
async function funcoes(req, res, url) {
  const nome = url.pathname.split("/")[3];
  if (!/^[a-z-]+$/.test(nome)) return resp(res, 404, { erro: "função inexistente" });
  if (!handlers[nome]) {
    const arq = path.resolve(`../supabase/functions/${nome}/handler.ts`);
    if (!fs.existsSync(arq)) return resp(res, 404, { erro: "função inexistente" });
    const mod = await import(arq);
    const env = { SUPABASE_URL: BASE, SUPABASE_SERVICE_ROLE_KEY: SERVICE_KEY, SUPABASE_ANON_KEY: ANON_KEY };
    handlers[nome] = mod.criarHandler({ createClient, env: (k) => env[k] });
  }
  const corpo = ["POST", "PUT"].includes(req.method) ? await lerCorpo(req) : undefined;
  const r = await handlers[nome](new Request(BASE + url.pathname, { method: req.method, headers: req.headers, body: corpo }));
  res.writeHead(r.status, Object.fromEntries(r.headers)); res.end(await r.text());
}

const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".jpg": "image/jpeg", ".png": "image/png", ".mp4": "video/mp4", ".svg": "image/svg+xml", ".mp3": "audio/mpeg", ".webp": "image/webp" };
http.createServer(async (req, res) => {
  const url = new URL(req.url, BASE);
  try {
    if (req.method === "OPTIONS") return resp(res, 200, "ok");
    if (url.pathname.startsWith("/auth/v1/")) return await auth(req, res, url);
    if (url.pathname.startsWith("/rest/v1/")) return await rest(req, res, url);
    if (url.pathname.startsWith("/functions/v1/")) return await funcoes(req, res, url);
    if (url.pathname.startsWith("/storage/v1/object/")) return await storage(req, res, url);
    if (url.pathname === "/_dev/caixa") return resp(res, 200, caixaDeSaida);
    let f = path.join(SITE, decodeURIComponent(url.pathname === "/" ? "/index.html" : url.pathname));
    if (f.startsWith(SITE) && fs.existsSync(f) && fs.statSync(f).isDirectory()) f = path.join(f, "index.html");
    if (!f.startsWith(SITE) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end("404"); }
    res.writeHead(200, { "Content-Type": MIME[path.extname(f)] || "application/octet-stream" });
    fs.createReadStream(f).pipe(res);
  } catch (e) { console.error(e); resp(res, 500, { message: String(e.message) }); }
}).listen(PORTA, () => console.log("Supabase local em " + BASE));
