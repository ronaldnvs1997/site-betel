// Fumaça "como no Render + Supabase": o site estático (pasta site/) servido numa origem e a API do
// Supabase em OUTRA origem, como em produção (betel-site.onrender.com × projeto.supabase.co).
// Uso: SITE=http://localhost:8080 SUPABASE_URL=… SUPABASE_ANON_KEY=… SUPABASE_SERVICE_ROLE_KEY=… node fumaca-estatico.mjs
import { chromium } from "playwright-core";
import { createClient } from "@supabase/supabase-js";
import pg from "pg";

const SITE = process.env.SITE || "http://localhost:8080", API = process.env.SUPABASE_URL, SERV = process.env.SUPABASE_SERVICE_ROLE_KEY;
const FOTO = process.env.FOTO_TESTE || new URL("../../frontend/site/img/oracao.jpg", import.meta.url).pathname;
const sql = async (q, v) => { const c = new pg.Client({ host: "/tmp", port: 5434, user: "postgres", database: "betel" }); await c.connect(); try { return (await c.query(q, v)).rows; } finally { await c.end(); } };
let ok = 0, falhas = 0;
const check = (c, n, x) => { if (c) { ok++; console.log("  ✓ " + n); } else { falhas++; console.log("  ✗ " + n + (x !== undefined ? "  → " + String(x).slice(0, 300) : "")); } };

console.log("\n0. Configuração publicada");
const cfg = await (await fetch(SITE + "/config.js")).text();
check(cfg.includes(JSON.stringify(API)) && !/service_role|sb_secret_/.test(cfg), "config.js aponta para o Supabase e só tem a chave pública", cfg);
const h = (await fetch(SITE + "/agendaministerialprivada/evento?t=" + "0".repeat(64))).headers;
check(/noindex/.test(h.get("x-robots-tag") || "") && h.get("referrer-policy") === "no-referrer", "página privada da Agenda fora dos buscadores e sem enviar o endereço");
check((await fetch(SITE + "/")).headers.get("x-content-type-options") === "nosniff", "cabeçalhos de segurança no site");

const admin = createClient(API, SERV, { auth: { persistSession: false, autoRefreshToken: false } });
const { data: u } = await admin.auth.admin.createUser({ email: "master@exemplo.com", password: "Master-Exemplo-2026", email_confirm: true, user_metadata: { nome: "Master Exemplo" } });
await admin.rpc("servico_criar_usuario", { p_ator: null, p_usuario: u.user.id, p_nome: "Master Exemplo", p_telefone: "31900000001", p_email: "master@exemplo.com", p_perfil: "MASTER", p_atribuicoes: [], p_ministerios: [], p_solicitacao: null });
await sql("update perfis set deve_trocar_senha = false, senha_alterada_em = now() where id = $1", [u.user.id]);

const browser = await chromium.launch({ executablePath: "/usr/bin/google-chrome", args: ["--no-sandbox"] });
for (const [tag, vp] of [["computador", { width: 1360, height: 900 }], ["celular", { width: 390, height: 844 }]]) {
  console.log(`\n1. ${tag}`);
  const ctx = await browser.newContext({ viewport: vp, ...(tag === "celular" ? { isMobile: true, hasTouch: true, deviceScaleFactor: 2 } : {}) });
  const p = await ctx.newPage(); const erros = [], chamadas = new Set(), corpos = [];
  p.on("pageerror", (e) => erros.push(e.message));
  p.on("console", (m) => m.type() === "error" && !/fonts\.g|ERR_INTERNET|net::ERR/.test(m.text()) && erros.push(m.text()));
  p.on("request", (r) => chamadas.add(new URL(r.url()).origin));
  p.on("response", async (r) => { if (/javascript/.test(r.headers()["content-type"] || "")) corpos.push(await r.text().catch(() => "")); });
  await p.goto(SITE + "/#inicio"); await p.waitForSelector("#homeGaleria img", { timeout: 15000 });
  check(await p.$$eval("#homeGaleria img", (is) => is.length === 8), `${tag}: Home com as fotos (conteúdo vindo do Supabase)`);
  await p.goto(SITE + "/#ministerios"); check(await p.waitForSelector(".cp-min-card", { timeout: 10000 }).then(() => true).catch(() => false), `${tag}: ministérios carregados do banco`);
  await p.goto(SITE + "/#equipe/entrar"); await p.waitForSelector("#sbLogin");
  await p.fill("#sbEmail", "master@exemplo.com"); await p.fill("#sbSenha", "Master-Exemplo-2026"); await p.click("#sbEntrar");
  check(await p.waitForSelector("#sbAbas [data-sb]", { timeout: 15000, state: "attached" }).then(() => true).catch(() => false), `${tag}: login pelo Supabase Auth`);
  for (const aba of ["usuarios", "ministerios", "organogramas", "site", "agenda-links", "conta"]) {
    await p.goto(SITE + "/#equipe/" + aba); await p.waitForTimeout(1200);
    check(!/Não foi possível|erro/i.test(await p.$eval("#sbConteudo", (e) => e.innerText.slice(0, 300)).catch(() => "erro")), `${tag}: aba ${aba} abre`);
  }
  if (tag === "computador") {
    await p.goto(SITE + "/#equipe/conta"); await p.waitForSelector("#mpArquivo");
    await p.setInputFiles("#mpArquivo", FOTO); await p.waitForSelector("#mpQuadro canvas"); await p.click("#mpSalvarFoto");
    const foto = await p.waitForFunction(() => /Foto de perfil atualizada/.test(document.body.innerText), null, { timeout: 10000 }).then(() => true).catch(() => false);
    const st = await sql("select count(*)::int n from storage.objects where bucket_id = 'perfis'");
    check(foto && st[0].n === 1, "foto de perfil enviada ao Supabase Storage (bucket perfis)", st[0].n);
    await p.goto(SITE + "/#equipe/agenda-links"); await p.waitForSelector("#inAgCriar");
    await p.fill('#inAgCriar [name="rotulo"]', "Ficha de teste"); await p.click('#inAgCriar [type="submit"]'); await p.waitForSelector(".cp-link-gerado");
    const link = await p.$eval(".cp-link-gerado", (e) => e.textContent.trim());
    check(link.startsWith(SITE + "/agendaministerialprivada/evento?t="), "link privado usa o endereço do site", link);
    const m = await (await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true })).newPage();
    await m.goto(link); check(await m.waitForSelector("#ficha", { timeout: 10000 }).then(() => true).catch(() => false), "formulário privado abre sem login (endereço sem barra no fim)");
  }
  const origens = [...chamadas].filter((o) => o.startsWith("http"));
  check(origens.every((o) => o === SITE || o === API || /fonts\.(googleapis|gstatic)\.com|cdn\.tailwindcss|jsdelivr|cdnjs/.test(o)), `${tag}: o site só fala com o próprio endereço e com o Supabase`, origens.join(" "));
  check(!corpos.some((t) => /sb_secret_[A-Za-z0-9_-]{20,}|eyJ[A-Za-z0-9_-]+\.eyJyb2xlIjoic2VydmljZV9yb2xl/.test(t)), `${tag}: nenhum script entregue ao navegador contém chave privada`);
  check(!erros.length, `${tag}: sem erros no navegador`, erros.join(" | "));
  await ctx.close();
}
await browser.close();
console.log(`\nResultado: ${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
