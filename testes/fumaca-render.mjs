// Teste de fumaça no servidor "como no Render": site, Área de Membros, Agenda, perfil, menu e saída.
import { chromium } from "playwright-core";
const BASE = process.env.BASE, EMAIL = process.env.EMAIL, SENHA = process.env.SENHA, NOVA = process.env.NOVA;
let ok = 0, falhas = 0; const check = (c, n, x) => { if (c) { ok++; console.log("  ✓ " + n); } else { falhas++; console.log("  ✗ " + n + (x ? "  → " + x : "")); } };
const b = await chromium.launch({ executablePath: "/usr/bin/google-chrome", args: ["--no-sandbox"] });
for (const movel of [false, true]) {
  const ctx = await b.newContext(movel ? { viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true } : { viewport: { width: 1360, height: 900 } });
  const p = await ctx.newPage(); const erros = [], falhasRede = [];
  p.on("pageerror", (e) => erros.push(e.message)); p.on("console", (m) => m.type() === "error" && !/favicon|fonts\.g/.test(m.text()) && erros.push(m.text()));
  p.on("response", (r) => { if (r.status() >= 500) falhasRede.push(r.status() + " " + r.url()); if (r.status() === 404) console.log("    (404: " + r.url() + ")"); });
  const tag = movel ? "celular" : "computador";
  await p.goto(BASE + "/"); await p.waitForSelector("#navEquipe", { state: "attached" });
  check(await p.title() !== "" && (await p.$$("footer .fcol")).length === 3, `${tag}: Home carrega com o rodapé novo`);
  await p.goto(BASE + "/#equipe/entrar"); await p.waitForSelector("#sbLogin");
  await p.fill("#sbEmail", EMAIL); await p.fill("#sbSenha", movel ? NOVA : SENHA); await p.click("#sbEntrar");
  if (!movel) { await p.waitForSelector("#sbNovaSenha"); await p.fill("#nsSenha", NOVA); await p.fill("#nsConf", NOVA); await p.click("#nsSalvar"); check(true, "primeiro acesso: senha nova criada"); }
  await p.waitForSelector("#sbPainel:not([hidden])"); check(await p.isVisible("#cpUsuario"), `${tag}: login e identificação no cabeçalho`);
  if (movel) { await p.tap("#sbIrBotao"); await p.waitForSelector("#sbIrPainel.on"); await p.tap('#sbIrPainel [data-sb="irAba:conta"]'); }
  else { await p.click("#cpUsuarioBotao"); await p.click('#cpUsuarioMenu a[href="#equipe/conta"]'); }
  await p.waitForSelector("#sbMeuTel"); check(true, `${tag}: Meu perfil abre`);
  for (const aba of ["usuarios", "secretaria", "midia", "avisos", "ministerios", "organogramas", "site", "agenda-links"]) {
    await p.goto(BASE + "/#equipe/" + aba); await p.waitForTimeout(1200);
    check(!(await p.textContent("#sbConteudo")).includes("Erro"), `${tag}: aba ${aba} sem erro`);
  }
  for (const [rota, sel] of [["ministerios", ".cp-min-card"], ["colegio", "#colEtapas .cp-etapa"], ["inicio", "#homeGaleria img"]]) {
    await p.goto(BASE + "/#" + rota); const achou = await p.waitForSelector(sel, { timeout: 8000, state: "attached" }).then(() => true).catch(() => false);
    check(achou, `${tag}: página pública ${rota} carrega do banco`);
  }
  await p.goto(BASE + "/agendaministerialprivada/evento?t=" + "0".repeat(64)); await p.waitForTimeout(2500);
  check(/inválido/i.test(await p.textContent("body")), `${tag}: formulário privado da Agenda responde (código inválido recusado)`);
  await p.goto(BASE + "/agenda-ministerial/"); await p.waitForTimeout(4000);
  check((await p.textContent("body")).includes("Agenda"), `${tag}: Agenda Ministerial abre`);
  await p.goto(BASE + "/#equipe"); await p.waitForSelector("#cpUsuarioBotao");
  await p.click("#cpUsuarioBotao"); await p.click('#cpUsuarioMenu [data-sb="sair"]'); await p.waitForSelector('[data-sb="ir:entrar"]');
  check(true, `${tag}: Sair`);
  check(!erros.length, `${tag}: sem erros no console`, erros.slice(0, 3).join(" | "));
  check(!falhasRede.length, `${tag}: nenhuma resposta 5xx do servidor`, falhasRede.slice(0, 3).join(" | "));
  await ctx.close();
}
await b.close(); console.log(`\nResultado: ${ok} ok, ${falhas} falha(s)`); process.exit(falhas ? 1 : 0);
