// =====================================================================
// VERSÃO DE TESTE do Sistema Betel — roda inteira no navegador.
// O mesmo site, o mesmo núcleo da API e as mesmas migrações do servidor do Render,
// com o PostgreSQL rodando em WebAssembly (PGlite). Os dados ficam só neste navegador.
// Não é o sistema de produção: serve para ver e testar as telas e os fluxos.
// =====================================================================
import { PGlite } from "@electric-sql/pglite";
import { createClient } from "@supabase/supabase-js";
import { criarApi } from "../nucleo/api.mjs";
import { instalar } from "../nucleo/instalar.mjs";
import { criarHandler as fnUsuarios } from "../funcoes/admin-usuarios.mjs";
import { criarHandler as fnAcesso } from "../funcoes/aprovar-acesso.mjs";
import { criarHandler as fnArquivos } from "../funcoes/arquivos.mjs";
import { ETAPAS, SEGREDO, CONTAS, PASTA } from "./etapas.gerado.mjs";

const fetchOriginal = window.fetch.bind(window);
const ROTA_API = /\/__betel\/(auth|rest|storage|functions)\/v1\//;
const base = new URL(PASTA, document.currentScript?.src || location.href).href.replace(/\/$/, "");
const urlApi = `${location.origin}/__betel`;
let resolverPronto; const pronto = new Promise((r) => (resolverPronto = r));
let api = null;

// todo pedido para a API desta versão de teste é atendido aqui mesmo, no navegador
window.fetch = async (entrada, init) => {
  const req = entrada instanceof Request && !init ? entrada : new Request(entrada, init);
  if (!ROTA_API.test(req.url)) return fetchOriginal(entrada, init);
  await pronto;
  const u = new URL(req.url); u.pathname = u.pathname.replace(/^.*\/__betel/, "");
  const corpo = ["GET", "HEAD"].includes(req.method) ? undefined : await req.arrayBuffer();
  const r = await api.tratar(new Request(u, { method: req.method, headers: req.headers, body: corpo }));
  return r || new Response(JSON.stringify({ message: "não encontrado" }), { status: 404 });
};

// arquivos abertos por link (comprovantes, documentos) e imagens dos cursos também vêm do banco local
const abrirOriginal = window.open.bind(window);
window.open = (url, alvo, recursos) => {
  if (!url || !ROTA_API.test(String(url))) return abrirOriginal(url, alvo, recursos);
  const w = abrirOriginal("", "_blank");
  window.fetch(String(url)).then((r) => r.blob()).then((b) => { const u = URL.createObjectURL(b); if (w) w.location.href = u; else abrirOriginal(u, "_blank"); });
  return w;
};
const trocarImagem = async (img) => {
  if (img.dataset.betelLocal || !ROTA_API.test(img.getAttribute("src") || "")) return;
  img.dataset.betelLocal = "1";
  try { const r = await window.fetch(img.src); if (r.ok) img.src = URL.createObjectURL(await r.blob()); } catch (_) {}
};
new MutationObserver((ms) => { for (const m of ms) { if (m.type === "attributes") trocarImagem(m.target); else m.addedNodes.forEach((n) => { if (n.tagName === "IMG") trocarImagem(n); else n.querySelectorAll?.("img").forEach(trocarImagem); }); } })
  .observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ["src"] });

// ---------------- faixa de aviso (no padrão visual do site)
function faixa(texto, acoes) {
  let f = document.getElementById("betelPrevia");
  if (!f) {
    f = document.createElement("div"); f.id = "betelPrevia";
    f.style.cssText = "position:fixed;left:12px;bottom:12px;z-index:50;max-width:min(420px,calc(100vw - 24px));padding:12px 16px;border-radius:16px;background:#1A0B0B;border:1px solid rgba(255,225,178,.35);color:#fff;font:500 13px/1.45 Montserrat,system-ui,sans-serif;box-shadow:0 18px 50px rgba(0,0,0,.45)";
    (document.body || document.documentElement).appendChild(f);
  }
  f.innerHTML = `<b style="color:#FFE1B2;letter-spacing:.08em;font-size:11px;text-transform:uppercase">Versão de teste</b><div style="margin-top:4px">${texto}</div>${acoes || ""}`;
  return f;
}
const caixa = [];
function mostrarEmail(m) {
  caixa.push(m);
  faixa(`E-mail que seria enviado para <b>${m.para}</b>:<br><a href="${m.link}" style="color:#FFE1B2;text-decoration:underline">abrir o link de redefinição de senha</a>`,
    `<div style="margin-top:8px"><button type="button" onclick="this.closest('#betelPrevia').remove()" style="background:none;border:1px solid rgba(255,255,255,.2);color:#fff;border-radius:999px;padding:4px 12px;cursor:pointer;font:inherit">Fechar</button></div>`);
}

// ---------------- banco no navegador
async function abrirBanco() {
  const [wasm, initdb, dados] = await Promise.all([
    WebAssembly.compileStreaming(fetchOriginal(`${base}/pglite.wasm`)).catch(async () => WebAssembly.compile(await (await fetchOriginal(`${base}/pglite.wasm`)).arrayBuffer())),
    WebAssembly.compileStreaming(fetchOriginal(`${base}/initdb.wasm`)).catch(async () => WebAssembly.compile(await (await fetchOriginal(`${base}/initdb.wasm`)).arrayBuffer())),
    fetchOriginal(`${base}/pglite-data.txt`).then((r) => r.text()).then((t) => { const bin = atob(t.trim()); const b = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) b[i] = bin.charCodeAt(i); return new Blob([b]); }),
  ]);
  const opcoes = { pgliteWasmModule: wasm, initdbWasmModule: initdb, fsBundle: dados, parsers: { 20: (v) => v, 1082: (v) => v, 1700: (v) => v } };
  try { const pg = new PGlite("idb://betel-previa-v1", opcoes); await pg.waitReady; return pg; }
  catch (e) { console.warn("Sem armazenamento no navegador; usando memória:", e); const pg = new PGlite(opcoes); await pg.waitReady; return pg; }
}

(async () => {
  try {
    const t0 = Date.now();
    const primeiraVez = !localStorage.getItem("betel-previa-pronta");
    if (primeiraVez) faixa("Preparando o banco de dados neste navegador. Na primeira vez leva alguns segundos…");
    const pg = await abrirBanco();
    let fila = Promise.resolve();
    const serial = (fn) => { const p = fila.then(fn, fn); fila = p.catch(() => {}); return p; };
    const transacao = (claims, papel, fn) => serial(() => pg.transaction(async (tx) => {
      if (papel) await tx.query(`set local role ${papel}`);
      await tx.query("select set_config('request.jwt.claims', $1, true)", [JSON.stringify(claims || { role: "service_role" })]);
      return fn((sql, p) => tx.query(sql, p || []));
    }));
    const db = {
      comoPapel: (claims, fn) => transacao(claims, ["anon", "authenticated"].includes(claims?.role) ? claims.role : "anon", fn),
      comoDono: (fn, claims) => transacao(claims || { role: "service_role" }, null, fn),
    };
    await serial(() => instalar({ exec: (sql) => pg.exec(sql), query: (sql, p) => pg.query(sql, p || []), etapas: ETAPAS, log: (m) => console.log("[Betel]", m) }));
    api = await criarApi({ db, segredo: SEGREDO, urlInterna: urlApi, createClient, urlPublica: () => base,
      enviarEmail: async (m) => { mostrarEmail(m); return true; },
      funcoes: { "admin-usuarios": fnUsuarios, "aprovar-acesso": fnAcesso, arquivos: fnArquivos } });
    resolverPronto();
    // contas de teste (MASTER), criadas uma única vez com a mesma regra do servidor
    if (!(await pg.query("select 1 from auth.users limit 1")).rows.length) {
      const admin = createClient(urlApi, api.SERVICO, { auth: { persistSession: false, autoRefreshToken: false, storageKey: "betel-previa-admin" } });
      for (const c of CONTAS) {
        const { data, error } = await admin.auth.admin.createUser({ email: c.email, password: c.senha, email_confirm: true, user_metadata: { nome: c.nome } });
        if (error) { console.warn(error.message); continue; }
        await admin.rpc("servico_criar_usuario", { p_ator: null, p_usuario: data.user.id, p_nome: c.nome, p_telefone: c.telefone, p_email: c.email,
          p_perfil: "MASTER", p_atribuicoes: [], p_ministerios: [], p_solicitacao: null });
      }
    }
    try { localStorage.setItem("betel-previa-pronta", "1"); } catch (_) {}
    setInterval(() => api.tarefas().catch(() => {}), 15 * 60e3);
    console.log(`[Betel] versão de teste pronta em ${Date.now() - t0} ms`);
    const recomeçar = `<div style="margin-top:8px;display:flex;gap:8px;flex-wrap:wrap"><a href="${base}/#equipe/entrar" style="color:#FFE1B2">Entrar na Área da Equipe</a>
      <button type="button" id="betelPreviaFechar" style="background:none;border:1px solid rgba(255,255,255,.2);color:#fff;border-radius:999px;padding:4px 12px;cursor:pointer;font:inherit">Ocultar</button>
      <button type="button" id="betelPreviaZerar" style="background:none;border:1px solid rgba(255,255,255,.2);color:#fff;border-radius:999px;padding:4px 12px;cursor:pointer;font:inherit">Apagar dados de teste</button></div>`;
    const f = faixa(`Os dados ficam só neste navegador. Acesso: <b>${CONTAS[0].email}</b> · senha temporária <b>${CONTAS[0].senha}</b> (o sistema pede uma nova no primeiro acesso).`, recomeçar);
    f.querySelector("#betelPreviaFechar").onclick = () => f.remove();
    f.querySelector("#betelPreviaZerar").onclick = async (ev) => {
      const b = ev.currentTarget;
      if (b.dataset.ok !== "1") { b.dataset.ok = "1"; b.textContent = "Confirmar: apagar tudo"; return; }
      try { localStorage.clear(); indexedDB.deleteDatabase("/pglite/betel-previa-v1"); } catch (_) {}
      location.reload();
    };
    if (sessionStorage.getItem("betel-previa-oculta")) f.remove();
    f.querySelector("#betelPreviaFechar").addEventListener("click", () => { try { sessionStorage.setItem("betel-previa-oculta", "1"); } catch (_) {} });
  } catch (e) {
    console.error(e);
    faixa(`Não foi possível iniciar o banco de teste neste navegador (${String(e.message || e).slice(0, 160)}). Tente o Chrome ou o Edge atualizados.`);
  }
})();
