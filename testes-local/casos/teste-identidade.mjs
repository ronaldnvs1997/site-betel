// Etapa 8 — auditoria visual automática: todas as telas seguem a identidade do site
// (fontes, fundo, cabeçalho, ausência de emojis, sem rolagem lateral no celular) e capturas de cada módulo.
import { chromium } from "playwright-core";
import { createClient } from "@supabase/supabase-js";
import { execFileSync } from "node:child_process";
import fs from "node:fs";

const BASE = process.env.SUPABASE_URL, SAIDA = process.env.SAIDA || "/tmp/identidade";
fs.mkdirSync(SAIDA, { recursive: true });
let ok = 0, falhas = 0;
const check = (c, n, x) => { if (c) { ok++; console.log("  ✓ " + n); } else { falhas++; console.log("  ✗ " + n + (x !== undefined ? "  → " + String(x).slice(0, 300) : "")); } };
const FONTES = ["Montserrat", "Fraunces"];
const FUNDO = "rgb(18, 7, 7)";

const saida = execFileSync("node", ["../scripts/criar-primeiros-masters.mjs", "Primeiro Master Teste|master1@exemplo.com|31900000001"], { env: process.env }).toString();
const temp = saida.match(/senha temporária: (\S+)/)[1];

const browser = await chromium.launch({ executablePath: "/usr/bin/google-chrome", args: ["--no-sandbox"] });
async function nova(mobile) {
  const ctx = await browser.newContext(mobile ? { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true } : { viewport: { width: 1360, height: 900 } });
  const p = await ctx.newPage(); p.erros = []; p.on("pageerror", (x) => p.erros.push(x.message)); p.on("dialog", (d) => d.dismiss()); return p;
}
// confere a tela aberta: fontes usadas, fundo, cabeçalho do site, emojis e rolagem lateral
async function auditar(p, nome, mobile) {
  const r = await p.evaluate(() => {
    const vis = [...document.querySelectorAll("body *")].filter((e) => e.offsetParent !== null && e.childNodes.length && [...e.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim()));
    const fontes = new Set(vis.map((e) => getComputedStyle(e).fontFamily.split(",")[0].replace(/["']/g, "").trim()));
    const texto = vis.map((e) => [...e.childNodes].filter((n) => n.nodeType === 3).map((n) => n.textContent).join(" ")).join(" ");
    const top = document.querySelector("header.top");
    return { fontes: [...fontes], fundo: getComputedStyle(document.body).backgroundColor, topo: !!top && top.getBoundingClientRect().height > 0,
      emojis: (texto.match(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/gu) || []).filter((c) => !"★✕✓✗".includes(c)),
      lateral: document.documentElement.scrollWidth - window.innerWidth };
  });
  const estranhas = r.fontes.filter((f) => !FONTES.includes(f) && !/mono|system-ui/i.test(f));
  check(!estranhas.length, `${nome}: só as fontes do site`, estranhas.join(", "));
  check(r.fundo === FUNDO, `${nome}: fundo da identidade`, r.fundo);
  check(r.topo, `${nome}: cabeçalho do site`);
  check(!r.emojis.length, `${nome}: sem emojis como ícones`, r.emojis.join(" "));
  if (mobile) check(r.lateral <= 1, `${nome}: sem rolagem lateral no celular`, r.lateral + "px");
}

for (const [m, mobile] of [["computador", false], ["celular", true]]) {
  console.log(`\nPáginas públicas — ${m}`);
  const p = await nova(mobile);
  for (const [n, u] of [["Início", "/#inicio"], ["Agenda do site", "/#agenda"], ["Cursos", "/#cursos"], ["Acesso da equipe", "/#equipe/entrar"], ["Agenda Ministerial", "/agenda-ministerial/"]]) {
    await p.goto(BASE + u); await p.waitForTimeout(1200);
    await auditar(p, `${n} (${m})`, mobile);
    await p.screenshot({ path: `${SAIDA}/${m}-${n.normalize("NFD").replace(/[^\w]+/g, "-").toLowerCase()}.png` });
  }
  check(!p.erros.length, `sem erros de JavaScript (${m})`, p.erros.join(" | "));
}

console.log("\nÁrea da Equipe — todas as abas do MASTER (computador)");
const pc = await nova(false);
await pc.goto(BASE + "/#equipe/entrar"); await pc.waitForSelector("#sbLogin"); await pc.fill("#sbEmail", "master1@exemplo.com"); await pc.fill("#sbSenha", temp); await pc.click("#sbEntrar");
await pc.waitForSelector("#sbNovaSenha"); await pc.fill("#nsSenha", "Ezequiel-Nova-2026"); await pc.fill("#nsConf", "Ezequiel-Nova-2026"); await pc.click("#nsSalvar"); await pc.waitForSelector("#sbPainel:not([hidden])");
const abas = await pc.$$eval("#sbAbas button", (b) => b.map((x) => [x.dataset.sb.slice(4), x.textContent.trim()]));
check((await pc.$$("#sbAbas .cp-sep")).length >= 3, "abas agrupadas por área (com separadores)");
for (const [k, n] of abas) {
  if (k === "agenda") continue;
  await pc.click(`[data-sb="aba:${k}"]`); await pc.waitForFunction(() => !document.querySelector("#sbConteudo")?.textContent.includes("Carregando"), null, { timeout: 10000 }).catch(() => {});
  await pc.waitForTimeout(400);
  await auditar(pc, `aba ${n}`, false);
  await pc.screenshot({ path: `${SAIDA}/equipe-${k}.png`, fullPage: true });
}
check(!pc.erros.length, "sem erros de JavaScript na Área da Equipe", pc.erros.join(" | "));

console.log("\nÁrea da Equipe — celular");
const cel = await nova(true);
const irPara = async (pg, k) => { await pg.click("#sbIrBotao"); await pg.waitForSelector("#sbIrPainel.on"); await pg.click(`#sbIrPainel [data-sb="irAba:${k}"]`); await pg.waitForSelector("#sbIrPainel", { state: "hidden" }); };
await cel.goto(BASE + "/#equipe/entrar"); await cel.waitForSelector("#sbLogin"); await cel.fill("#sbEmail", "master1@exemplo.com"); await cel.fill("#sbSenha", "Ezequiel-Nova-2026"); await cel.click("#sbEntrar");
await cel.waitForSelector("#sbPainel:not([hidden])");
check(await cel.isVisible("#sbIrBotao") && !(await cel.isVisible("#sbAbas")), "no celular, a navegação vira o menu Ir para");
const grupos = await cel.$$eval("#sbIrPainel .cp-ir-grupo", (g) => g.map((x) => x.getAttribute("aria-label")));
check(grupos.includes("Formação e Secretaria") && grupos.includes("Mídia") && grupos.includes("Administração"), "menu do celular com os grupos", grupos.join("|"));
await irPara(cel, "secretaria"); await cel.waitForURL(/#equipe\/secretaria/);
check(await cel.waitForFunction(() => document.querySelector('[data-sb="aba:secretaria"]')?.getAttribute("aria-selected") === "true", null, { timeout: 8000 }).then(() => true, () => false), "escolher no menu abre a aba");
await cel.waitForTimeout(600);
await auditar(cel, "Secretaria (celular)", true);
await cel.screenshot({ path: `${SAIDA}/celular-equipe-secretaria.png`, fullPage: true });
for (const k of await cel.$$eval("#sbIrPainel .cp-ir-item", (o) => o.map((x) => x.dataset.sb.split(":")[1]))) {
  if (k === "agenda" || k === "secretaria") continue;
  await irPara(cel, k); await cel.waitForTimeout(900);
  await auditar(cel, `${k} (celular)`, true);
  await cel.screenshot({ path: `${SAIDA}/celular-equipe-${k}.png`, fullPage: true });
}
check(!cel.erros.length, "sem erros de JavaScript (celular)", cel.erros.join(" | "));

await browser.close();
console.log(`\nResultado: ${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
