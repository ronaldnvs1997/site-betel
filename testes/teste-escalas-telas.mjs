// Etapa 7 — telas: solicitar mídia, avaliar, montar a escala, publicar, confirmar no celular, presença e relatório.
import { chromium } from "playwright-core";
import { createClient } from "@supabase/supabase-js";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import pg from "pg";
import { prepararVoluntario } from "./apoio-termos.mjs";

const BASE = process.env.SUPABASE_URL, SAIDA = process.env.SAIDA || "/tmp/escalas-telas";
fs.mkdirSync(SAIDA, { recursive: true });
let ok = 0, falhas = 0;
const check = (c, n, x) => { if (c) { ok++; console.log("  ✓ " + n); } else { falhas++; console.log("  ✗ " + n + (x !== undefined ? "  → " + String(x).slice(0, 300).replace(/\n/g, " ") : "")); } };
const novo = () => createClient(BASE, process.env.SUPABASE_ANON_KEY, { auth: { persistSession: false } });
const sql = async (q, v) => { const c = new pg.Client({ host: "/tmp", port: 5434, user: "postgres", database: "betel" }); await c.connect(); try { return (await c.query(q, v)).rows; } finally { await c.end(); } };
const dia = (n) => new Date(Date.now() + n * 864e5).toLocaleDateString("sv-SE", { timeZone: "America/Sao_Paulo" });

const saida = execFileSync("node", ["../supabase/scripts/criar-primeiros-masters.mjs", "Primeiro Master Teste|master1@exemplo.com|31900000001"], { env: process.env }).toString();
const api = novo();
await api.auth.signInWithPassword({ email: "master1@exemplo.com", password: saida.match(/senha temporária: (\S+)/)[1] });
await api.auth.updateUser({ password: "Ezequiel-Nova-2026" });
const mins = (await api.from("ministerios").select("id,nome")).data, mid = (n) => mins.find((m) => m.nome === n).id;
const cria = async (nome, email, perfil, mm) => {
  if (mm[0].funcao === "voluntario") await prepararVoluntario(nome, email, "31999990000");
  return (await api.functions.invoke("admin-usuarios", { body: { acao: "criar", nome, telefone: "31999990000", email, perfil, atribuicoes: [], ministerios: mm } })).data;
};
const LIA = await cria("Lia Lider Midia", "lia@teste.com", "LIDER", [{ ministerio_id: mid("Mídia"), funcao: "lider" }]);
const LUAN = await cria("Luan Lider Louvor", "luan@teste.com", "LIDER", [{ ministerio_id: mid("Louvor"), funcao: "lider" }]);
const VIT = await cria("Vitor Fotografo Teste", "vitor@teste.com", "VOLUNTARIO", [{ ministerio_id: mid("Mídia"), funcao: "voluntario" }]);
await cria("Vera Fotografa Teste", "vera@teste.com", "VOLUNTARIO", [{ ministerio_id: mid("Mídia"), funcao: "voluntario" }]);
const fotografo = (await sql("select f.id from escala_funcoes f where f.nome = 'Fotógrafo'"))[0].id;
for (const e of ["vitor@teste.com", "vera@teste.com"])
  await sql("insert into voluntario_habilitacoes (pessoa_id, funcao_id, status) select id, $1, 'habilitado' from pessoas where email = $2", [fotografo, e]);

const browser = await chromium.launch({ executablePath: "/usr/bin/google-chrome", args: ["--no-sandbox"] });
const nova = async (mobile) => { const ctx = await browser.newContext(mobile ? { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true } : { viewport: { width: 1360, height: 900 } });
  const p = await ctx.newPage(); p.erros = []; p.on("pageerror", (x) => p.erros.push(x.message)); p.on("dialog", (d) => d.dismiss()); return p; };
const foto = (p, n, sel) => (sel ? p.locator(sel).screenshot({ path: `${SAIDA}/${n}.png` }) : p.screenshot({ path: `${SAIDA}/${n}.png`, fullPage: true }));
const texto = (p, sel, t) => p.waitForFunction(([s, t]) => document.querySelector(s)?.textContent.replace(/ /g, " ").includes(t), [sel, t], { timeout: 10000 });
const abas = (p) => p.$$eval("#sbAbas button", (b) => b.map((x) => x.textContent.trim()));
async function entrar(p, email, temp, nova) {
  await p.goto(BASE + "/#equipe/entrar"); await p.waitForSelector("#sbLogin"); await p.fill("#sbEmail", email); await p.fill("#sbSenha", temp); await p.click("#sbEntrar");
  await p.waitForSelector("#sbNovaSenha"); await p.fill("#nsSenha", nova); await p.fill("#nsConf", nova); await p.click("#nsSalvar"); await p.waitForSelector("#sbPainel:not([hidden])");
}

console.log("\n1. O Louvor pede cobertura");
const lu = await nova(); await entrar(lu, "luan@teste.com", LUAN.senha_temporaria, "Luan-Nova-20261");
const abasLu = await abas(lu);
check(abasLu.includes("Solicitar mídia") && !abasLu.includes("Mídia"), "líder do Louvor pode solicitar, mas não abre o painel da Mídia", abasLu.join("|"));
await lu.click('[data-sb="aba:solicitar-midia"]'); await lu.waitForSelector("#msForm");
await lu.fill('#msForm [name="titulo"]', "Noite de Louvor"); await lu.selectOption('#msForm [name="tipo"]', "programacao_especial");
await lu.fill('#msForm [name="local"]', "Templo"); await lu.fill('#msForm [name="inicio"]', `${dia(10)}T19:30`); await lu.fill('#msForm [name="fim"]', `${dia(10)}T22:00`);
await lu.fill('#msForm [name="resp"]', "Luan Lider Louvor"); await lu.fill('#msForm [name="objetivo"]', "Registrar a noite de adoração");
await lu.click('#msForm [type="submit"]'); await texto(lu, "#msForm .msg", "ao menos um serviço"); check(true, "exige ao menos um serviço");
await lu.locator("#msForm .cp-lista-opcoes label", { hasText: "Fotografia" }).locator("input").check();
await lu.fill('#msForm [name^="det-"]:not([hidden])', "Fotos da banda e do público");
await foto(lu, "01-solicitar-midia", "#msForm");
await lu.click('#msForm [type="submit"]'); await texto(lu, "#sbConteudo", "Noite de Louvor");
check((await lu.textContent("#sbConteudo")).includes("Enviada") && !(await sql("select 1 from escala_eventos")).length, "solicitação enviada (sem criar escala)");

console.log("\n2. A liderança de Mídia avalia e monta a escala");
const li = await nova(); await entrar(li, "lia@teste.com", LIA.senha_temporaria, "Lia-Nova-20261");
const abasLi = await abas(li);
check(abasLi.includes("Mídia") && abasLi.includes("Minhas escalas"), "a líder de Mídia tem o painel da Mídia", abasLi.join("|"));
await li.click('[data-sb="aba:midia"]'); await texto(li, "#sbConteudo", "solicitações aguardando avaliação");
await foto(li, "02-painel-midia", "#v-equipe");
await li.click('[data-ml="tela:solicitacoes"]'); await texto(li, "#sbConteudo", "Fotos da banda");
await li.fill('[data-ml-form="msg"] [name="texto"]', "Equipe da Mídia já está ciente.");
await li.selectOption('[data-ml-form="msg"] [name="tipo"]', "nota_interna"); await li.click('[data-ml-form="msg"] [type="submit"]'); await texto(li, "#sbConteudo", "nota interna");
await foto(li, "03-avaliar-solicitacao", "#v-equipe");
await li.click('[data-ml^="aprovar:"]'); await li.waitForSelector('[data-ml^="escalaSol:"]'); check(true, "solicitação aprovada");
await li.click('[data-ml^="escalaSol:"]'); await texto(li, "#sbConteudo", "Fotógrafo");
check((await li.textContent("#sbConteudo")).includes("Não necessárias neste evento"), "a página do evento mostra só as equipes necessárias");
await li.click('[data-ml^="addForm:"]'); await li.waitForSelector('[data-ml-form="adicionar"]');
await li.selectOption('[data-ml-form="adicionar"] [name="pessoa"]', { label: (await li.locator('[data-ml-form="adicionar"] option', { hasText: "Vitor" }).textContent()).trim() });
await li.selectOption('[data-ml-form="adicionar"] [name="papel"]', "principal"); await li.click('[data-ml-form="adicionar"] [type="submit"]');
await texto(li, "#sbConteudo", "Vitor Fotografo Teste");
await li.click('[data-ml^="addForm:"]'); await li.waitForSelector('[data-ml-form="adicionar"]'); await li.click('[data-ml-form="adicionar"] [type="submit"]');
await texto(li, "#sbConteudo", "Vera Fotografa Teste"); check(true, "dois fotógrafos no mesmo evento (sem limite)");
const pb = li.locator('[data-ml^="publicar:"]'); await pb.click(); await pb.click();
await texto(li, "#sbConteudo", "Aguardando confirmação"); check(true, "escala publicada: cada voluntário avisado");
await foto(li, "04-evento-escala", "#v-equipe");

console.log("\n3. O voluntário confirma pelo celular");
const vi = await nova(true); await entrar(vi, "vitor@teste.com", VIT.senha_temporaria, "Vitor-Nova-2026");
await vi.goto(BASE + "/#voluntario"); await vi.waitForURL(/#equipe\/escalas/); await texto(vi, "#sbConteudo", "Noite de Louvor");
check(true, "a antiga \"Minha escala\" leva para \"Minhas escalas\"");
check((await vi.textContent("#sbConteudo")).includes("Aguardando a sua resposta (1)") && (await vi.textContent("#sbConteudo")).includes("responsável principal"), "a escala pendente aparece com função e papel");
await foto(vi, "05-voluntario-celular", "#v-equipe");
await vi.click('[data-mv^="confirmar:"]'); await texto(vi, "#sbConteudo", "Próximas escalas confirmadas (1)");
check(true, "presença confirmada pelo próprio voluntário");
await vi.fill('#mvSemana [name="de"]', "18:00"); await vi.fill('#mvSemana [name="ate"]', "22:00"); await vi.click('#mvDisp [type="submit"]');
await vi.waitForFunction(() => document.querySelector('#mvSemana [name="de"]')?.value === "18:00");
let nDisp = 0; for (let i = 0; i < 40 && nDisp !== 1; i++) { nDisp = (await sql("select count(*)::int n from voluntario_disponibilidade"))[0].n; if (nDisp !== 1) await vi.waitForTimeout(200); }
check(nDisp === 1, "disponibilidade salva", nDisp);
await foto(vi, "06-voluntario-confirmado", "#v-equipe");

console.log("\n4. A liderança acompanha");
await li.click('[data-sb="aba:midia"]'); await li.click('[data-ml="tela:painel"]'); await texto(li, "#sbConteudo", "1 confirmado(s)");
await li.click('[data-ml^="abrir:"]'); await texto(li, "#sbConteudo", "Confirmado");
await li.click('[data-ml^="hist:"]'); await texto(li, "#mlEvExtra", "confirmou"); check(true, "histórico na tela registra a confirmação");
await li.click('[data-ml="tela:equipe"]'); await texto(li, "#sbConteudo", "Fotógrafo (Habilitado)");
await foto(li, "07-equipe-habilitacoes", "#v-equipe");
await li.click('[data-ml="tela:relatorios"]'); await texto(li, "#mlRelOut", "Escalados"); await foto(li, "08-relatorios", "#v-equipe");
check(true, "relatório de escalados, confirmações e presença");

console.log("\n5. O solicitante vê a decisão; o voluntário não vê o painel");
await lu.click('[data-sb="aba:solicitar-midia"]'); await texto(lu, "#sbConteudo", "Aprovada");
check(!(await lu.textContent("#sbConteudo")).includes("já está ciente"), "nota interna não aparece para o solicitante");
check(!(await abas(vi)).includes("Mídia") && !(await abas(vi)).includes("Solicitar mídia"), "voluntário não vê painel nem formulário de solicitação");

for (const [n, p] of [["Louvor", lu], ["Mídia", li], ["voluntário", vi]]) check(!p.erros.length, `sem erros de JavaScript (${n})`, p.erros.join(" | "));
await browser.close();
console.log(`\nResultado: ${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
