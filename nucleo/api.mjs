// =====================================================================
// Núcleo da API do Sistema Betel (sem serviços externos).
// Recebe um Request e devolve um Response (padrão Web), então o MESMO código
// roda no servidor do Render (Node + PostgreSQL) e na versão de teste
// (navegador + PostgreSQL em WebAssembly).
//
// Rotas compatíveis com o cliente usado pelo site:
//   /auth/v1/*       login, sessão, troca de senha, recuperação, administração de contas
//   /rest/v1/*       leitura/escrita nas tabelas e funções do banco, sempre com o papel do usuário (RLS)
//   /storage/v1/*    arquivos guardados NO BANCO (imagens públicas dos cursos e arquivos privados)
//   /functions/v1/*  funções de servidor (usuários, aprovação de acesso, arquivos)
// Toda permissão é conferida no banco. O núcleo só autentica e repassa o papel.
// =====================================================================
import bcrypt from "bcryptjs";

const enc = new TextEncoder();
const b64url = (bytes) => { let s = ""; const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes); for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]); return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, ""); };
const b64urlTexto = (t) => b64url(enc.encode(t));
const deB64url = (s) => { s = s.replace(/-/g, "+").replace(/_/g, "/"); while (s.length % 4) s += "="; return Uint8Array.from(atob(s), (c) => c.charCodeAt(0)); };
const aleatorio = (n) => { const a = new Uint8Array(n); crypto.getRandomValues(a); return b64url(a); };
async function sha256hex(t) { const h = await crypto.subtle.digest("SHA-256", enc.encode(t)); return [...new Uint8Array(h)].map((x) => x.toString(16).padStart(2, "0")).join(""); }
const iguais = (a, b) => { if (a.length !== b.length) return false; let r = 0; for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i); return r === 0; };
const ident = (s) => { if (!/^[a-z_][a-z0-9_]*$/.test(s)) throw Object.assign(new Error("identificador inválido"), { code: "PGRST100" }); return `"${s}"`; };
const json = (corpo, status = 200, extra = {}) => new Response(corpo === undefined ? null : JSON.stringify(corpo, (k, v) => (typeof v === "bigint" ? v.toString() : v)), { status, headers: { "Content-Type": "application/json; charset=utf-8", ...extra } });

export const SENHA_MIN = 10;
const SESSAO_SEG = 3600, REFRESH_DIAS = 30, RECUPERACAO_MIN = 60, TENTATIVAS = 8, JANELA_MIN = 15;

/**
 * @param {object} o
 * @param {object} o.db            { comoPapel(claims, fn), comoDono(fn) } — fn recebe q(sql, params) => {rows}
 * @param {string} o.segredo       segredo para assinar sessões (mín. 32 caracteres)
 * @param {(req:Request)=>string} o.urlPublica  endereço público (para links de recuperação)
 * @param {string} o.urlInterna    endereço que as funções de servidor usam para chamar a própria API
 * @param {object} o.funcoes       { nome: criarHandler } das funções de servidor
 * @param {Function} o.createClient cliente HTTP usado pelas funções de servidor
 * @param {Function} [o.enviarEmail] async ({para, assunto, texto, html}) => boolean
 * @param {Function} [o.fetchInterno] fetch usado pelas funções de servidor (padrão: fetch global)
 */
export async function criarApi(o) {
  if (!o.segredo || o.segredo.length < 32) throw new Error("Defina um segredo (JWT_SECRET) com pelo menos 32 caracteres.");
  const chave = await crypto.subtle.importKey("raw", enc.encode(o.segredo), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
  const assinarBytes = async (t) => new Uint8Array(await crypto.subtle.sign("HMAC", chave, enc.encode(t)));
  async function assinar(claims) {
    const h = b64urlTexto(JSON.stringify({ alg: "HS256", typ: "JWT" })), p = b64urlTexto(JSON.stringify(claims));
    return `${h}.${p}.${b64url(await assinarBytes(h + "." + p))}`;
  }
  // sessões encerradas ("Sair"); a consulta ao banco é guardada por 20 s nesta instância
  const memoSessao = new Map();
  async function encerrada(sid) {
    const m = memoSessao.get(sid);
    if (m && (m.sim || m.ate > Date.now())) return m.sim;
    let sim = false;
    try { sim = (await o.db.comoDono((q) => q("select 1 from auth.sessoes_encerradas where sessao_id = $1::uuid", [sid]))).rows.length > 0; } catch (_) { sim = false; }
    if (memoSessao.size > 5000) memoSessao.clear();
    memoSessao.set(sid, { sim, ate: Date.now() + 20e3 });
    return sim;
  }
  async function verificar(token) {
    const [h, p, s] = String(token || "").split(".");
    if (!h || !p || !s) return null;
    try {
      if (!(await crypto.subtle.verify("HMAC", chave, deB64url(s), enc.encode(h + "." + p)))) return null;
      const c = JSON.parse(new TextDecoder().decode(deB64url(p)));
      if (c.exp && c.exp < Date.now() / 1000) return null;
      if (c.session_id && (await encerrada(c.session_id))) return null;   // sessão encerrada em "Sair"
      return c;
    } catch (_) { return null; }
  }
  const ANON = await assinar({ role: "anon", iss: "betel" });
  const SERVICO = await assinar({ role: "service_role", iss: "betel" });
  const tokenDe = (req) => { const a = req.headers.get("authorization") || ""; return a.startsWith("Bearer ") ? a.slice(7) : req.headers.get("apikey") || ""; };
  const claimsDe = async (req) => (await verificar(tokenDe(req))) || { role: "anon" };
  const db = o.db;
  const dono = (sql, p) => db.comoDono((q) => q(sql, p));

  // ---------------------------------------------------------------- Auth
  const fmtUsuario = (u) => ({ id: u.id, aud: "authenticated", role: "authenticated", email: u.email, email_confirmed_at: u.email_confirmed_at,
    user_metadata: u.raw_user_meta_data || {}, app_metadata: { provider: "email", providers: ["email"], ...(u.raw_app_meta_data || {}) },
    banned_until: u.banned_until, created_at: u.created_at, updated_at: u.updated_at, last_sign_in_at: u.last_sign_in_at });
  const usuario = async (campo, valor) => (await dono(`select * from auth.users where ${campo === "email" ? "email = lower($1)" : "id = $1::uuid"}`, [valor])).rows[0];
  const banido = (u) => u.banned_until && new Date(u.banned_until) > new Date();
  const erroAuth = (status, code, msg) => json({ code: status, error_code: code, msg }, status);
  async function novaSessao(u, sid) {
    const agora = Math.floor(Date.now() / 1000), exp = agora + SESSAO_SEG, session_id = sid || crypto.randomUUID();
    const access_token = await assinar({ sub: u.id, role: "authenticated", aud: "authenticated", email: u.email, iat: agora, exp, session_id });
    const refresh_token = aleatorio(32);
    await dono("insert into auth.sessoes (token_hash, usuario_id, expira_em, sessao_id) values ($1, $2, now() + ($3 || ' days')::interval, $4)", [await sha256hex(refresh_token), u.id, String(REFRESH_DIAS), session_id]);
    return { access_token, token_type: "bearer", expires_in: SESSAO_SEG, expires_at: exp, refresh_token, user: fmtUsuario(u) };
  }
  // limite de tentativas de senha por e-mail (contra adivinhação; não é critério de autorização)
  const falhas = new Map();
  const bloqueado = (email) => { const f = falhas.get(email); if (!f) return false; if (Date.now() - f.desde > JANELA_MIN * 60e3) { falhas.delete(email); return false; } return f.n >= TENTATIVAS; };
  const registrarFalha = (email) => { const f = falhas.get(email); if (!f || Date.now() - f.desde > JANELA_MIN * 60e3) falhas.set(email, { n: 1, desde: Date.now() }); else f.n++; };

  async function auth(req, url) {
    const rota = url.pathname.replace("/auth/v1", "");
    const corpo = ["POST", "PUT"].includes(req.method) ? await req.json().catch(() => ({})) : {};
    if (rota === "/token" && url.searchParams.get("grant_type") === "password") {
      const email = String(corpo.email || "").trim().toLowerCase();
      if (bloqueado(email)) return erroAuth(429, "over_request_rate_limit", "Request rate limit reached");
      const u = await usuario("email", email);
      if (!u || !u.encrypted_password || !(await bcrypt.compare(String(corpo.password || ""), u.encrypted_password))) { registrarFalha(email); return erroAuth(400, "invalid_credentials", "Invalid login credentials"); }
      if (banido(u)) return erroAuth(400, "user_banned", "User is banned");
      falhas.delete(email);
      await dono("update auth.users set last_sign_in_at = now() where id = $1", [u.id]);
      return json(await novaSessao(u));
    }
    if (rota === "/token" && url.searchParams.get("grant_type") === "refresh_token") {
      const h = await sha256hex(String(corpo.refresh_token || ""));
      const s = (await dono("delete from auth.sessoes where token_hash = $1 returning usuario_id, expira_em, sessao_id", [h])).rows[0];
      const u = s && new Date(s.expira_em) > new Date() && (await usuario("id", s.usuario_id));
      if (!u || banido(u)) return erroAuth(400, "refresh_token_not_found", "Invalid Refresh Token");
      if (s.sessao_id && (await encerrada(s.sessao_id))) return erroAuth(400, "refresh_token_not_found", "Invalid Refresh Token");
      return json(await novaSessao(u, s.sessao_id));
    }
    if (rota === "/user") {
      const c = await verificar(tokenDe(req));
      if (!c || !c.sub) return erroAuth(401, "bad_jwt", "invalid JWT");
      let u = await usuario("id", c.sub);
      if (!u) return erroAuth(404, "user_not_found", "User not found");
      if (banido(u)) return erroAuth(401, "user_banned", "User is banned");
      if (req.method === "PUT" && corpo.password !== undefined) {
        if (String(corpo.password).length < SENHA_MIN) return erroAuth(422, "weak_password", `Password should be at least ${SENHA_MIN} characters.`);
        if (await bcrypt.compare(String(corpo.password), u.encrypted_password || "")) return erroAuth(422, "same_password", "New password should be different from the old password.");
        await dono("update auth.users set encrypted_password = $2, updated_at = now() where id = $1", [u.id, await bcrypt.hash(String(corpo.password), 10)]);
        u = await usuario("id", c.sub);
      }
      return json(fmtUsuario(u));
    }
    if (rota === "/logout") {
      const c = await verificar(tokenDe(req));
      if (c?.sub && url.searchParams.get("scope") === "global") await dono("delete from auth.sessoes where usuario_id = $1", [c.sub]);
      if (c?.sub && c.session_id) {
        // encerra esta sessão: apaga a renovação e recusa o token de acesso até ele expirar
        await dono("delete from auth.sessoes where sessao_id = $1", [c.session_id]);
        memoSessao.set(c.session_id, { sim: true });
        await dono("insert into auth.sessoes_encerradas (sessao_id, expira_em) values ($1, to_timestamp($2)) on conflict do nothing", [c.session_id, c.exp || Math.floor(Date.now() / 1000) + SESSAO_SEG]);
      }
      return new Response(null, { status: 204 });
    }
    if (rota === "/recover") {
      const u = await usuario("email", String(corpo.email || "").trim());
      if (u && !banido(u)) {
        const t = aleatorio(32);
        await dono("insert into auth.recuperacoes (token_hash, usuario_id, expira_em) values ($1, $2, now() + ($3 || ' minutes')::interval)", [await sha256hex(t), u.id, String(RECUPERACAO_MIN)]);
        const base = o.urlPublica(req);
        const destino = seguro(url.searchParams.get("redirect_to") || corpo.redirect_to, base);
        const link = `${base}/auth/v1/verify?token=${t}&type=recovery&redirect_to=${encodeURIComponent(destino)}`;
        await o.enviarEmail?.({ para: u.email, assunto: "Igreja Batista Betel — redefinir senha",
          texto: `Olá!\n\nRecebemos um pedido para redefinir a senha da sua conta na Área de Membros da Igreja Batista Betel.\nAbra o link abaixo em até ${RECUPERACAO_MIN} minutos:\n\n${link}\n\nSe não foi você, ignore este e-mail. Sua senha continua a mesma.`, link });
      }
      return json({});   // mesma resposta exista ou não a conta
    }
    if (rota === "/verify" && req.method === "GET") {
      const h = await sha256hex(String(url.searchParams.get("token") || ""));
      const r = (await dono("delete from auth.recuperacoes where token_hash = $1 returning usuario_id, expira_em", [h])).rows[0];
      const base = o.urlPublica(req), destino = seguro(url.searchParams.get("redirect_to"), base);
      const u = r && new Date(r.expira_em) > new Date() && (await usuario("id", r.usuario_id));
      if (!u || banido(u)) return new Response(null, { status: 303, headers: { Location: `${destino}#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired` } });
      const s = await novaSessao(u);
      return new Response(null, { status: 303, headers: { Location: `${destino}#access_token=${s.access_token}&expires_at=${s.expires_at}&expires_in=${SESSAO_SEG}&refresh_token=${s.refresh_token}&token_type=bearer&type=recovery` } });
    }
    if (rota.startsWith("/admin/users")) {
      const c = await verificar(tokenDe(req));
      if (!c || c.role !== "service_role") return erroAuth(403, "not_admin", "User not allowed");
      const id = rota.split("/")[3];
      if (req.method === "POST" && !id) {
        const email = String(corpo.email || "").trim().toLowerCase();
        if (String(corpo.password || "").length < SENHA_MIN) return erroAuth(422, "weak_password", "Password too short");
        if ((await dono("select 1 from auth.users where email = $1", [email])).rows.length) return erroAuth(422, "email_exists", "A user with this email address has already been registered");
        const novo = crypto.randomUUID();
        await dono("insert into auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data) values ($1, $2, $3, $4, $5)",
          [novo, email, await bcrypt.hash(String(corpo.password), 10), corpo.email_confirm ? new Date().toISOString() : null, JSON.stringify(corpo.user_metadata || {})]);
        return json(fmtUsuario(await usuario("id", novo)));
      }
      const u = id && (await usuario("id", id));
      if (!u) return erroAuth(404, "user_not_found", "User not found");
      if (req.method === "GET") return json(fmtUsuario(u));
      if (req.method === "PUT") {
        if (corpo.password !== undefined) { await dono("update auth.users set encrypted_password = $2, updated_at = now() where id = $1", [id, await bcrypt.hash(String(corpo.password), 10)]); await dono("delete from auth.sessoes where usuario_id = $1", [id]); }
        if (corpo.ban_duration !== undefined) {
          const ate = corpo.ban_duration === "none" ? null : new Date(Date.now() + parseInt(corpo.ban_duration) * 3600e3).toISOString();
          await dono("update auth.users set banned_until = $2 where id = $1", [id, ate]);
          if (ate) await dono("delete from auth.sessoes where usuario_id = $1", [id]);
        }
        return json(fmtUsuario(await usuario("id", id)));
      }
      if (req.method === "DELETE") { await dono("delete from auth.users where id = $1", [id]); return json({}); }
    }
    return erroAuth(404, "not_found", "Not found");
  }
  // redirecionamentos só para o próprio site
  function seguro(destino, base) {
    try { const d = new URL(destino || base, base); return d.origin === new URL(base).origin ? d.toString() : base; } catch (_) { return base; }
  }

  // ---------------------------------------------------------------- Banco (REST)
  const tiposFn = {};
  const comPapel = (claims, fn) => claims?.role === "service_role" ? db.comoDono(fn, claims) : db.comoPapel(claims, fn);
  function erroPg(e, claims) {
    const status = e.code === "42501" ? (claims?.role === "anon" ? 401 : 403) : e.code === "P0002" ? 404 : ["23505", "23P01"].includes(e.code) ? 409 : e.code === "PGRST100" ? 400 : 400;
    return json({ code: e.code || null, message: e.message, details: e.detail || null, hint: e.hint || null }, status);
  }
  async function rest(req, url) {
    const c = await claimsDe(req);
    const rota = url.pathname.replace("/rest/v1/", "");
    try {
      if (rota.startsWith("rpc/") && req.method === "POST") {
        const nome = rota.slice(4); const fn = ident(nome);
        const args = await req.json().catch(() => ({}));
        const nomes = Object.keys(args || {});
        if (!tiposFn[nome]) {
          const t = await dono("select a.n, a.t from pg_proc p, unnest(p.proargnames, p.proargtypes::regtype[]::text[]) as a(n, t) where p.proname = $1 and p.pronamespace = 'public'::regnamespace", [nome]);
          if (!t.rows.length && !(await dono("select 1 from pg_proc where proname = $1 and pronamespace = 'public'::regnamespace", [nome])).rows.length) return json({ code: "PGRST202", message: "Função inexistente" }, 404);
          tiposFn[nome] = Object.fromEntries(t.rows.map((r) => [r.n, r.t]));
        }
        const tipos = tiposFn[nome];
        if (nomes.some((k) => !(k in tipos))) return json({ code: "PGRST202", message: "Parâmetros inválidos para a função" }, 404);
        const vals = nomes.map((k) => { const v = args[k]; if (v === null || v === undefined) return null; return /json/.test(tipos[k]) ? JSON.stringify(v) : Array.isArray(v) ? v : typeof v === "object" ? JSON.stringify(v) : v; });
        const sql = `select public.${fn}(${nomes.map((k, i) => `${ident(k)} => $${i + 1}::${tipos[k]}`).join(", ")}) as r`;
        const r = await comPapel(c, (q) => q(sql, vals));
        return json(r.rows[0].r);
      }
      if (req.method === "GET") {
        const tabela = ident(rota);
        const cols = (url.searchParams.get("select") || "*").split(",").map((x) => (x.trim() === "*" ? "*" : ident(x.trim()))).join(",");
        const filtros = [], vals = [];
        for (const [k, v] of url.searchParams) {
          if (["select", "order", "limit", "offset"].includes(k)) continue;
          const [op, ...resto] = v.split("."); const val = resto.join(".");
          if (op === "eq") { vals.push(val); filtros.push(`${ident(k)}::text = $${vals.length}`); }
          else if (op === "neq") { vals.push(val); filtros.push(`${ident(k)}::text <> $${vals.length}`); }
          else if (op === "is" && val === "null") filtros.push(`${ident(k)} is null`);
          else if (["gte", "lte", "gt", "lt"].includes(op)) { vals.push(val); filtros.push(`${ident(k)}::text ${{ gte: ">=", lte: "<=", gt: ">", lt: "<" }[op]} $${vals.length}`); }
          else if (op === "in") { vals.push(val.replace(/^\(|\)$/g, "").split(",").map((x) => x.replace(/^"|"$/g, ""))); filtros.push(`${ident(k)}::text = any($${vals.length}::text[])`); }
          else throw Object.assign(new Error("Filtro não suportado"), { code: "PGRST100" });
        }
        const ordem = (url.searchParams.get("order") || "").split(",").filter(Boolean).map((x) => `${ident(x.split(".")[0])} ${x.includes(".desc") ? "desc" : "asc"}${x.includes("nullslast") ? " nulls last" : x.includes("nullsfirst") ? " nulls first" : ""}`);
        const lim = Math.min(parseInt(url.searchParams.get("limit") || "1000") || 1000, 5000), off = Math.max(parseInt(url.searchParams.get("offset") || "0") || 0, 0);
        const sql = `select ${cols} from public.${tabela}${filtros.length ? " where " + filtros.join(" and ") : ""}${ordem.length ? " order by " + ordem.join(", ") : ""} limit ${lim} offset ${off}`;
        const r = await comPapel(c, (q) => q(sql, vals));
        if (String(req.headers.get("accept") || "").includes("vnd.pgrst.object")) {
          if (r.rows.length !== 1) return json({ code: "PGRST116", message: "JSON object requested, multiple (or no) rows returned", details: `The result contains ${r.rows.length} rows`, hint: null }, 406);
          return json(r.rows[0]);
        }
        return json(r.rows);
      }
      if (["POST", "PATCH", "DELETE"].includes(req.method)) {
        const tabela = ident(rota); const corpo = req.method === "DELETE" ? {} : await req.json().catch(() => ({}));
        const r = await comPapel(c, async (q) => {
          if (req.method === "POST") {
            const linhas = Array.isArray(corpo) ? corpo : [corpo];
            if (!linhas.length) return { rows: [] };
            const ks = [...new Set(linhas.flatMap((l) => Object.keys(l)))]; const vals = []; const tuplas = [];
            if (!ks.length) return q(`insert into public.${tabela} default values returning *`, []);
            for (const l of linhas) tuplas.push("(" + ks.map((k) => { if (!(k in l)) return "default"; vals.push(l[k] !== null && typeof l[k] === "object" && !Array.isArray(l[k]) ? JSON.stringify(l[k]) : l[k]); return "$" + vals.length; }).join(",") + ")");
            return q(`insert into public.${tabela} (${ks.map(ident).join(",")}) values ${tuplas.join(",")} returning *`, vals);
          }
          const filtros = [], vals = [];
          for (const [k, v] of url.searchParams) {
            if (["select", "order", "limit"].includes(k)) continue;
            if (v.startsWith("eq.")) { vals.push(v.slice(3)); filtros.push(`${ident(k)}::text = $${vals.length}`); }
            else if (v.startsWith("neq.")) { vals.push(v.slice(4)); filtros.push(`${ident(k)}::text <> $${vals.length}`); }
            else if (v.startsWith("in.")) { vals.push(v.slice(3).replace(/^\(|\)$/g, "").split(",").map((x) => x.replace(/^"|"$/g, ""))); filtros.push(`${ident(k)}::text = any($${vals.length}::text[])`); }
            else throw Object.assign(new Error("Filtro não suportado"), { code: "PGRST100" });
          }
          if (!filtros.length) throw Object.assign(new Error("Informe um filtro para alterar ou excluir."), { code: "PGRST100" });
          if (req.method === "DELETE") return q(`delete from public.${tabela} where ${filtros.join(" and ")} returning *`, vals);
          const ks = Object.keys(corpo); const base = vals.length;
          if (!ks.length) return { rows: [] };
          return q(`update public.${tabela} set ${ks.map((k, i) => `${ident(k)} = $${base + i + 1}`).join(",")} where ${filtros.join(" and ")} returning *`,
            [...vals, ...ks.map((k) => (corpo[k] !== null && typeof corpo[k] === "object" && !Array.isArray(corpo[k]) ? JSON.stringify(corpo[k]) : corpo[k]))]);
        });
        return json(String(req.headers.get("prefer") || "").includes("return=minimal") ? undefined : r.rows, String(req.headers.get("prefer") || "").includes("return=minimal") ? 204 : 200);
      }
    } catch (e) { return erroPg(e, c); }
    return json({ message: "não encontrado" }, 404);
  }

  // ---------------------------------------------------------------- Arquivos (guardados no banco)
  const ESPACOS = {
    cursos: { publico: true, limite: 2097152, tipos: ["image/jpeg", "image/png", "image/webp"], permissao: "select public.cursos_gestor() as ok" },
    comprovantes: { publico: false, limite: 5242880, tipos: ["application/pdf", "image/jpeg", "image/png", "image/webp"], permissao: "select false as ok" },
    documentos: { publico: false, limite: 5242880, tipos: ["application/pdf", "image/jpeg", "image/png", "image/webp"], permissao: "select false as ok" },
    // fotos do site (ministérios, Home, Colégio) e fotos de perfil: endereços aleatórios, não listáveis
    site: { publico: true, limite: 3145728, tipos: ["image/jpeg", "image/png", "image/webp"], permissao: "select public.pode_enviar_imagem_site($1) as ok", comCaminho: true },
    perfis: { publico: true, limite: 2097152, tipos: ["image/jpeg", "image/png", "image/webp"], permissao: "select public.pode_enviar_foto_perfil($1) as ok", comCaminho: true },
  };
  // Confere o tipo REAL do arquivo pelos primeiros bytes (não confia só no que o navegador declara)
  const tipoReal = (b) => {
    if (b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "image/jpeg";
    if (b.length > 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47 && b[4] === 0x0d && b[5] === 0x0a && b[6] === 0x1a && b[7] === 0x0a) return "image/png";
    if (b.length > 12 && String.fromCharCode(...b.slice(0, 4)) === "RIFF" && String.fromCharCode(...b.slice(8, 12)) === "WEBP") return "image/webp";
    if (b.length > 5 && String.fromCharCode(...b.slice(0, 5)) === "%PDF-") return "application/pdf";
    return "";
  };
  const assinarArquivo = async (b, p, exp) => b64url(await assinarBytes(`arquivo:${b}/${p}:${exp}`));
  const caminhoOk = (partes) => partes.length && partes.every((x) => x && x !== ".." && /^[\w.\-]+$/.test(x));
  async function armazenamento(req, url) {
    const partes = url.pathname.replace("/storage/v1/object/", "").split("/").map(decodeURIComponent);
    const c = await claimsDe(req);
    const servico = c.role === "service_role";
    if (partes[0] === "sign" && req.method === "POST") {      // link temporário: só o servidor
      if (!servico) return json({ message: "not allowed" }, 403);
      const [, espaco, ...resto] = partes; const corpo = await req.json().catch(() => ({}));
      if (!ESPACOS[espaco] || !caminhoOk(resto)) return json({ message: "Caminho inválido" }, 400);
      const exp = Math.floor(Date.now() / 1000) + Math.min(Number(corpo.expiresIn || 60), 3600); const p = resto.join("/");
      return json({ signedURL: `/object/sign/${espaco}/${p}?token=${exp}.${await assinarArquivo(espaco, p, exp)}` });
    }
    const entregar = async (espaco, p) => {
      const r = (await dono("select tipo, conteudo from armazenamento.objetos where espaco = $1 and caminho = $2", [espaco, p])).rows[0];
      if (!r) return json({ message: "Object not found" }, 404);
      const bytes = r.conteudo instanceof Uint8Array ? r.conteudo : new Uint8Array(r.conteudo);
      return new Response(bytes, { status: 200, headers: { "Content-Type": r.tipo, "Cache-Control": ESPACOS[espaco].publico ? "public, max-age=3600" : "private, no-store", "X-Content-Type-Options": "nosniff" } });
    };
    if (partes[0] === "sign" && req.method === "GET") {
      const [, espaco, ...resto] = partes; const p = resto.join("/"); const [exp, sig] = String(url.searchParams.get("token") || "").split(".");
      if (!exp || !sig || Number(exp) < Date.now() / 1000 || !iguais(sig, await assinarArquivo(espaco, p, exp))) return json({ message: "InvalidSignature" }, 400);
      return entregar(espaco, p);
    }
    if (partes[0] === "public" && req.method === "GET") {
      const [, espaco, ...resto] = partes;
      if (!ESPACOS[espaco]?.publico || !caminhoOk(resto)) return json({ message: "Object not found" }, 404);
      return entregar(espaco, resto.join("/"));
    }
    if (req.method === "DELETE") {
      if (!servico) return json({ message: "not allowed" }, 403);
      const corpo = await req.json().catch(() => ({})); const espaco = partes[0];
      for (const p of corpo.prefixes || []) await dono("delete from armazenamento.objetos where espaco = $1 and caminho = $2", [espaco, String(p)]);
      return json([]);
    }
    if (["POST", "PUT"].includes(req.method)) {
      const [espaco, ...resto] = partes; const cfg = ESPACOS[espaco];
      if (!cfg || !caminhoOk(resto)) return json({ message: "Caminho inválido" }, 400);
      const p0 = resto.join("/");
      const ok = servico || (await db.comoPapel(c, (q) => (cfg.comCaminho ? q(cfg.permissao, [p0]) : q(cfg.permissao))).then((r) => r.rows[0].ok === true).catch(() => false));
      if (!ok) return json({ statusCode: "403", error: "Unauthorized", message: "new row violates row-level security policy" }, 403);
      const tipo = String(req.headers.get("content-type") || "").split(";")[0];
      if (!cfg.tipos.includes(tipo)) return json({ statusCode: "415", error: "invalid_mime_type", message: `mime type ${tipo} is not supported` }, 415);
      const bytes = new Uint8Array(await req.arrayBuffer());
      if (bytes.length > cfg.limite) return json({ statusCode: "413", error: "Payload too large", message: "The object exceeded the maximum allowed size" }, 413);
      if (tipoReal(bytes) !== tipo) return json({ statusCode: "415", error: "invalid_mime_type", message: "O conteúdo do arquivo não corresponde ao tipo informado." }, 415);
      const p = resto.join("/");
      const sobrescrever = req.method === "PUT" || String(req.headers.get("x-upsert")) === "true";
      try {
        await dono(`insert into armazenamento.objetos (espaco, caminho, tipo, tamanho, conteudo, criado_por) values ($1, $2, $3, $4, $5, $6)
                    ${sobrescrever ? "on conflict (espaco, caminho) do update set tipo = excluded.tipo, tamanho = excluded.tamanho, conteudo = excluded.conteudo, criado_em = now()" : ""}`,
          [espaco, p, tipo, bytes.length, bytes, c.sub || null]);
      } catch (e) { if (e.code === "23505") return json({ statusCode: "409", error: "Duplicate", message: "The resource already exists" }, 409); throw e; }
      return json({ Key: `${espaco}/${p}`, Id: crypto.randomUUID() });
    }
    return json({ message: "não suportado" }, 404);
  }

  // ---------------------------------------------------------------- Funções de servidor
  const handlers = {};
  const env = { SUPABASE_URL: o.urlInterna, SUPABASE_SERVICE_ROLE_KEY: SERVICO, SUPABASE_ANON_KEY: ANON, SITE_ORIGEM: o.siteOrigem || "" };
  async function funcoes(req, url) {
    const nome = url.pathname.split("/")[3];
    if (!o.funcoes?.[nome]) return json({ erro: "função inexistente" }, 404);
    handlers[nome] ||= o.funcoes[nome]({ createClient: o.createClient, env: (k) => env[k] });
    return handlers[nome](req);
  }

  // ---------------------------------------------------------------- Roteador
  async function tratar(req) {
    const url = new URL(req.url);
    if (req.method === "OPTIONS") return new Response("ok", { status: 200 });
    try {
      if (url.pathname.startsWith("/auth/v1/")) return await auth(req, url);
      if (url.pathname.startsWith("/rest/v1/")) return await rest(req, url);
      if (url.pathname.startsWith("/functions/v1/")) return await funcoes(req, url);
      if (url.pathname.startsWith("/storage/v1/object/")) return await armazenamento(req, url);
    } catch (e) { console.error(e); return json({ message: "Erro interno. Tente novamente." }, 500); }
    return null;   // não é rota da API
  }

  // tarefas periódicas: prazos das escalas e limpeza de sessões vencidas
  async function tarefas() {
    const r = {};
    try { r.escalas = (await dono("select public.escalas_processar_prazos() as r")).rows[0].r; } catch (e) { r.erro_escalas = e.message; }
    try { await dono("delete from auth.sessoes where expira_em < now()"); await dono("delete from auth.sessoes_encerradas where expira_em < now()"); await dono("delete from auth.recuperacoes where expira_em < now()"); } catch (_) {}
    return r;
  }

  return { tratar, tarefas, ANON, SERVICO, assinar, verificar };
}
