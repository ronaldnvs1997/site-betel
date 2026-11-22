// M12 — telas: site público (ministérios, galeria, contatos, Colégio, nome "Área de Membros"),
// Área de Membros (ministérios, organogramas, conteúdo do site, formulários da Agenda, foto de perfil)
// e o formulário privado da Agenda no celular.
import { chromium } from "playwright-core";
import { createClient } from "@supabase/supabase-js";
import pg from "pg";
import fs from "node:fs";
import { prepararVoluntario } from "./apoio-termos.mjs";

const BASE = process.env.SUPABASE_URL, SERV = process.env.SUPABASE_SERVICE_ROLE_KEY;
const SAIDA = process.env.SAIDA || "/tmp/telas-institucional";
const FOTO = process.env.FOTO_TESTE || new URL("../../web2/img/oracao.jpg", import.meta.url).pathname;
fs.mkdirSync(SAIDA, { recursive: true });
const sql = async (q, v) => { const c = new pg.Client({ host: "/tmp", port: 5434, user: "postgres", database: "betel" }); await c.connect(); try { return (await c.query(q, v)).rows; } finally { await c.end(); } };
let ok = 0, falhas = 0;
const check = (c, n, x) => { if (c) { ok++; console.log("  ✓ " + n); } else { falhas++; console.log("  ✗ " + n + (x !== undefined ? "  → " + String(x).slice(0, 300) : "")); } };

const admin = createClient(BASE, SERV, { auth: { persistSession: false, autoRefreshToken: false } });
async function criar(nome, email, perfil, mins, senha, ator = null) {
  const { data, error } = await admin.auth.admin.createUser({ email, password: senha, email_confirm: true, user_metadata: { nome } });
  if (error) throw error;
  const { error: e2 } = await admin.rpc("servico_criar_usuario", { p_ator: ator, p_usuario: data.user.id, p_nome: nome, p_telefone: "31999990000", p_email: email, p_perfil: perfil, p_atribuicoes: [], p_ministerios: mins, p_solicitacao: null });
  if (e2) throw e2;
  await sql("update perfis set deve_trocar_senha = false, senha_alterada_em = now() where id = $1", [data.user.id]);
  return data.user.id;
}
const minId = async (n) => (await sql("select id from ministerios where nome = $1", [n]))[0].id;
const uidM = await criar("Master Teste", "master@teste.com", "MASTER", [], "Master-Teste-2026");
await prepararVoluntario("Lia Lider Louvor", "lia@teste.com", "31999990000");
await criar("Lia Lider Louvor", "lia@teste.com", "LIDER", [{ ministerio_id: await minId("Louvor"), funcao: "lider" }], "Lia-Teste-2026", uidM);

const browser = await chromium.launch({ executablePath: "/usr/bin/google-chrome", args: ["--no-sandbox"] });
async function pagina(mobile) {
  const ctx = await browser.newContext(mobile ? { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true } : { viewport: { width: 1360, height: 900 } });
  const p = await ctx.newPage();
  p.on("pageerror", (e) => { falhas++; console.log("  ✗ erro de JavaScript: " + e.message); });
  p.on("dialog", (d) => { falhas++; console.log("  ✗ janela do navegador aberta: " + d.message()); d.dismiss(); });
  return p;
}
const foto = (p, n, sel) => (sel ? p.locator(sel).first().screenshot({ path: `${SAIDA}/${n}.png` }) : p.screenshot({ path: `${SAIDA}/${n}.png`, fullPage: false }));
const semRolagemLateral = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
async function login(p, email, senha) {
  await p.goto(BASE + "/#equipe/entrar"); await p.waitForSelector("#sbLogin");
  await p.fill("#sbEmail", email); await p.fill("#sbSenha", senha); await p.click("#sbEntrar");
  await p.waitForSelector("#sbAbas [data-sb]", { timeout: 15000, state: "attached" });
}
const aba = async (p, k) => { await p.click(`#sbAbas [data-sb="aba:${k}"]`); await p.waitForTimeout(600); };
const aguardarAviso = (p, re) => p.waitForFunction((r) => new RegExp(r).test(document.body.innerText), re.source, { timeout: 10000 }).then(() => true).catch(() => false);

console.log("\n1. Site público");
let p = await pagina();
await p.goto(BASE + "/#inicio"); await p.waitForSelector("#homeGaleria img");
await p.evaluate(() => document.querySelector("#homeGaleria").scrollIntoView()); await p.waitForTimeout(1500);
const gal = await p.$$eval("#homeGaleria img", (is) => is.map((i) => ({ ok: i.complete && i.naturalWidth > 0, alt: i.alt })));
check(gal.length === 8 && gal.every((g) => g.ok && g.alt.length > 3), "Home: 8 fotos reais carregadas, todas com descrição", JSON.stringify(gal));
await foto(p, "01-home-galeria", "#homeGaleria");
const nav = await p.$eval("#navEquipe", (a) => a.textContent.trim());
check(nav === "Área de Membros", "menu mostra \"Área de Membros\"", nav);
const corpo = await p.evaluate(() => document.body.innerText);
check(!/Área da Equipe|Acesso da equipe/i.test(corpo), "nenhum texto visível com o nome antigo");
const blank = await p.$$eval('a[target="_blank"]', (as) => as.filter((a) => !/noopener/.test(a.rel)).map((a) => a.href));
check(!blank.length, "todos os links externos abrem com segurança (noopener)", blank.join(" "));
const wa = await p.$$eval('a[href*="wa.me"]', (as) => as.map((a) => a.href));
check(wa.length && wa.every((h) => /^https:\/\/wa\.me\/55\d{10,11}(\?|$)/.test(h)), "WhatsApp em formato internacional (wa.me/55…)", wa.join(" "));
const tels = await p.$$eval('a[href^="tel:"]', (as) => as.map((a) => a.getAttribute("href")));
check(tels.length && tels.every((t) => /^tel:\+55\d{10,11}$/.test(t)), "telefones viram link de ligação", tels.join(" "));
await p.goto(BASE + "/#contato"); await p.waitForTimeout(800);
const ct = await p.$eval("#ctInfo", (e) => ({ t: e.innerText, mapa: [...e.querySelectorAll("a")].some((a) => /google\.com\/maps/.test(a.href)), insta: [...e.querySelectorAll("a")].some((a) => /instagram\.com\/betelflamengo/.test(a.href)) }));
check(ct.mapa && ct.insta && /@betelflamengo/.test(ct.t), "Contato: endereço abre o mapa e redes mostram ícone + @", ct.t);
await foto(p, "02-contato", "#ctInfo");
await p.goto(BASE + "/#membros"); await p.waitForTimeout(500);
check((await p.evaluate(() => location.hash)).startsWith("#equipe"), "endereço antigo #membros leva à Área de Membros");
await p.goto(BASE + "/#colegio"); await p.waitForSelector("#colEtapas .cp-etapa", { timeout: 10000 }).catch(() => {});
const etapas = await p.$$eval("#colEtapas .cp-etapa h3, #colEtapas .cp-etapa h2", (h) => h.map((x) => x.textContent.trim()));
check(etapas.length === 4 && /Maternal/.test(etapas[0]) && /Fundamental/.test(etapas[3]), "Colégio: 4 etapas (Maternal → Ensino Fundamental)", etapas.join(" | "));
const colTxt = await p.$eval("#colEtapas", (e) => e.innerText);
check(!/anos de idade|\d+\s*a\s*\d+\s*anos/i.test(colTxt), "Colégio: nenhuma faixa etária inventada");
check(await p.$eval("#colCtas", (e) => [...e.querySelectorAll("a")].some((a) => a.href === "https://www.colegiobatistabetel.com.br/")), "link oficial do site do Colégio");
await foto(p, "03-colegio-etapas", "#colEtapas");
await p.goto(BASE + "/#ministerios"); await p.waitForSelector(".cp-min-card", { timeout: 10000 }).catch(() => {});
const cards = await p.$$eval(".cp-min-card", (c) => c.length);
check(cards >= 5, "Ministérios: cards carregados do banco", cards);
await foto(p, "04-ministerios-lista");

console.log("\n2. Área de Membros (MASTER)");
await login(p, "master@teste.com", "Master-Teste-2026");
const abas = await p.$$eval("#sbAbas [data-sb]", (b) => b.map((x) => x.textContent.trim()));
check(["Ministérios", "Organogramas", "Conteúdo do site", "Formulários da Agenda"].every((n) => abas.some((a) => a.startsWith(n))), "MASTER vê Ministérios, Organogramas, Conteúdo do site e Formulários da Agenda", abas.join(", "));
await aba(p, "ministerios"); await p.waitForSelector("#inMinPagina");
await p.selectOption("#inMinSel", { label: "Louvor" }); await p.waitForTimeout(800);
await p.fill('#inMinPagina [name="o_que_fazemos"]', "Conduzimos a adoração nos cultos da Betel.");
await p.fill('#inMinPagina [name="por_que_existimos"]', "Porque Deus é digno de todo louvor.");
await p.fill('#inMinPagina [name="missao"]', "Levar a igreja à presença de Deus por meio da música.");
await p.setInputFiles('#inMinPagina [data-in-foto="ministerio"]', FOTO);
check(await aguardarAviso(p, /Foto enviada/), "foto do ministério enviada (reduzida no navegador)");
await p.fill('#inMinPagina [name="foto_alt"]', "Equipe de louvor ministrando");
await p.click('#inMinPagina [data-publicar="1"]');
check(await aguardarAviso(p, /Página publicada/), "página do ministério publicada");
await foto(p, "05-membros-ministerio", "#inMinEd");
const pg2 = await pagina(); await pg2.goto(BASE + "/#ministerio/louvor"); await pg2.waitForSelector(".cp-min-secao", { timeout: 10000 }).catch(() => {});
const secoes = await pg2.$$eval(".cp-min-secao .eyebrow", (h) => h.map((x) => x.textContent.trim()));
const img = await pg2.$eval("#minDetalhe img", (i) => i.complete && i.naturalWidth > 0 && /storage\/v1\/object\/public\/site\/ministerios/.test(i.src)).catch(() => false);
check(secoes.join("|").includes("O que fazemos") && secoes.join("|").includes("Por que existimos") && secoes.join("|").includes("Nossa missão"), "página pública mostra as 3 seções", secoes.join(" | "));
check(img, "página pública usa a foto enviada");
await foto(pg2, "06-ministerio-publico"); await pg2.context().close();

await aba(p, "organogramas"); await p.waitForSelector(".cp-org-cartao");
const topo = await p.$eval(".cp-org-cartao.raiz", (e) => e.textContent);
check(/Pr\. Clébio Torres/.test(topo) && /Presidente e Pastor Sênior/.test(topo), "organograma geral: Pr. Clébio Torres no topo", topo);
await p.click('[data-org="novo:"]'); await p.fill('#inOrgNo [name="cargo"]', "Secretaria geral");
await p.selectOption('#inOrgNo [name="pai_id"]', { index: 1 });
await p.fill('#inOrgNo [name="responsabilidades"]', "Cadastros e documentos"); await p.click('#inOrgNo [type="submit"]');
check(await aguardarAviso(p, /Organograma atualizado/) && /Secretaria geral/.test(await p.$eval(".cp-org", (e) => e.textContent)), "função criada no organograma");
const subBtn = p.locator('.cp-org-no:has-text("Presidente e Pastor Sênior") [data-org^="rec:"]').first();
await subBtn.click(); const recolhido = !(/Secretaria geral/.test(await p.$eval(".cp-org", (e) => e.textContent)));
await subBtn.click(); check(recolhido && /Secretaria geral/.test(await p.$eval(".cp-org", (e) => e.textContent)), "recolher e expandir níveis");
await foto(p, "07-organograma-igreja", ".cp-org");
for (const t of ["Secretaria", "Tesouraria", "Colégio", "Ministérios"]) {
  await p.click(`.cp-org-abas button:has-text("${t}")`); await p.waitForTimeout(500);
  check((await p.$eval("#inOrg h3", (e) => e.textContent)).length > 2, `aba de organograma: ${t}`);
}
await foto(p, "08-organograma-ministerio", "#inOrg");

await aba(p, "site"); await p.waitForSelector("#inSiteContatos");
check(await p.$$eval("#inGalLista [data-gal]", (r) => r.length) === 8 && await p.$$eval(".cp-etapa-form", (f) => f.length) === 4, "Conteúdo do site: galeria (8) e etapas do Colégio (4)");
await p.fill('#inSiteContatos [name="colegio.site"]', "javascript:alert(1)"); await p.click('#inSiteContatos [type="submit"]');
check(await aguardarAviso(p, /Endereço inválido/), "link inseguro é recusado com mensagem clara");
await p.fill('#inSiteContatos [name="colegio.site"]', "https://www.colegiobatistabetel.com.br/"); await p.click('#inSiteContatos [type="submit"]');
check(await aguardarAviso(p, /Contatos salvos/), "contatos salvos");
await foto(p, "09-conteudo-site");

await aba(p, "agenda-links"); await p.waitForSelector("#inAgCriar");
await p.fill('#inAgCriar [name="rotulo"]', "Ficha do Culto de Louvor"); await p.selectOption('#inAgCriar [name="ministerio"]', { label: "Louvor" });
await p.click('#inAgCriar [type="submit"]'); await p.waitForSelector(".cp-link-gerado");
const link = await p.$eval(".cp-link-gerado", (e) => e.textContent.trim());
check(/\/agendaministerialprivada\/evento\?t=[0-9a-f]{64}$/.test(link), "link privado gerado no formato pedido", link);
await foto(p, "10-formularios-agenda");

console.log("\n3. Formulário privado no celular (sem login)");
const m = await pagina(true);
await m.goto(link); await m.waitForSelector("#ficha");
check(await semRolagemLateral(m), "formulário cabe na tela do celular");
check(/Louvor/.test(await m.$eval("#ficha", (f) => f.innerText + [...f.querySelectorAll("input")].map((i) => i.value).join(" "))), "ministério fixado pelo link");
await foto(m, "11-celular-ficha");
await m.tap("#enviar"); check(/Preencha/.test(await m.$eval("#erro", (e) => e.textContent)), "avisa os campos obrigatórios");
const dia = new Date(Date.now() + 25 * 864e5).toLocaleDateString("sv-SE");
await m.fill('[name="titulo"]', "Culto de Louvor Especial"); await m.fill('[name="data"]', dia); await m.fill('[name="lider"]', "Lia Lider Louvor");
await m.fill('[name="horario_inicio"]', "19:00"); await m.fill('[name="horario_fim"]', "21:30"); await m.check('[name="locais"][value="Templo"]');
await m.selectOption('[name="necessita_midia"]', "Sim"); await m.fill('[name="midia_tema"]', "Adoração"); await m.selectOption('[name="necessita_louvor"]', "Sim"); await m.selectOption('[name="necessita_diaconia"]', "Não");
await m.tap("#enviar"); await m.waitForSelector(".ok", { timeout: 10000 }).catch(() => {});
check(/Obrigado/.test(await m.evaluate(() => document.body.innerText)), "ficha enviada pelo celular");
await foto(m, "12-celular-enviado");
const rob = (await fetch(link)).headers.get("x-robots-tag") || "";
check(/noindex/.test(rob), "página privada fora dos buscadores", rob);
await m.goto(link.replace(/t=[0-9a-f]+/, "t=" + "0".repeat(64))); await m.waitForTimeout(1200);
check(/inválido/i.test(await m.evaluate(() => document.body.innerText)), "código errado mostra \"link inválido\"");
await m.context().close();

await aba(p, "agenda-links"); await p.waitForSelector("[data-ag-envio]", { timeout: 10000 });
check(/CULTO DE LOUVOR ESPECIAL/.test(await p.$eval("[data-ag-envio]", (f) => f.closest("details").innerText)), "envio aparece aberto, aguardando análise, com os dados da ficha");
await foto(p, "12b-envio-pendente", "details.row");
await p.click('[data-ag-envio] [data-decisao="aprovar"]');
check(await aguardarAviso(p, /evento criado na Agenda/), "coordenação aprova e o evento entra na Agenda");
const ev = await sql("select titulo from eventos where titulo ilike '%LOUVOR ESPECIAL%'");
check(ev.length === 1, "evento gravado na Agenda", JSON.stringify(ev));

console.log("\n4. Foto de perfil");
await aba(p, "conta"); await p.waitForSelector("#sbMinhaFoto");
await p.setInputFiles("#mpArquivo", FOTO); await p.waitForSelector("#mpQuadro canvas");
await p.fill("#mpZoom", "1.6").catch(() => {}); await p.dispatchEvent("#mpZoom", "input");
const q = await p.$("#mpQuadro"); const bb = await q.boundingBox();
await p.mouse.move(bb.x + bb.width / 2, bb.y + bb.height / 2); await p.mouse.down(); await p.mouse.move(bb.x + bb.width / 2 + 30, bb.y + bb.height / 2 + 20); await p.mouse.up();
await foto(p, "13-perfil-enquadrar", "#sbMinhaFoto");
await p.click("#mpSalvarFoto");
check(await aguardarAviso(p, /Foto de perfil atualizada/), "foto salva");
await p.waitForTimeout(800);
const cab = await p.$eval("#cpUsuario .cp-avatar img", (i) => i.complete && i.naturalWidth === 512 || i.naturalWidth > 0).catch(() => false);
check(cab, "foto aparece no menu do usuário");
const perf = await sql("select foto_caminho from perfis p join auth.users u on u.id = p.id where u.email = 'master@teste.com'");
check(/^[0-9a-f-]{36}\/[0-9a-f-]{36}\.jpg$/.test(perf[0].foto_caminho || ""), "foto gravada com caminho aleatório", perf[0].foto_caminho);
await foto(p, "14-perfil-com-foto");
await p.click('[data-sb="removerFoto"]'); await p.click('[data-sb="removerFoto"]');
check(await aguardarAviso(p, /Foto removida/), "foto removida");
check(await p.waitForSelector('[data-sb="naoSeiSenha"]', { timeout: 8000 }).then(() => true).catch(() => false), "opção \"Não sei minha senha atual\" no perfil");

console.log("\n5. Líder");
const l = await pagina();
await login(l, "lia@teste.com", "Lia-Teste-2026");
const abasL = await l.$$eval("#sbAbas [data-sb]", (b) => b.map((x) => x.textContent.trim()));
check(abasL.some((a) => a.startsWith("Meus ministérios")) && abasL.some((a) => a.startsWith("Organogramas")) && !abasL.some((a) => a.startsWith("Conteúdo do site")) && !abasL.some((a) => a.startsWith("Formulários da Agenda")), "líder vê só Meus ministérios e Organogramas", abasL.join(", "));
await aba(l, "ministerios"); await l.waitForSelector("#inMinPagina");
check(!(await l.$("#inMinLider")) && !(await l.$('#inMinPagina [name="exibir_publico"]')), "líder não altera liderança nem retira o ministério do site");
await foto(l, "15-lider-ministerio");
const lm = await pagina(true); await login(lm, "lia@teste.com", "Lia-Teste-2026"); await lm.goto(BASE + "/#equipe/organogramas"); await lm.waitForSelector(".cp-org-cartao");
check(await semRolagemLateral(lm), "organograma no celular sem rolagem lateral da página");
await foto(lm, "16-celular-organograma");

await browser.close();
console.log(`\n${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
