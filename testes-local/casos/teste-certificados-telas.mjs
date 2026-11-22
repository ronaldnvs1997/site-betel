// Etapa 6 — telas: responsáveis da turma, validação pela liderança, autorização, cerimônia, impressão e entrega.
import { chromium } from "playwright-core";
import { createClient } from "@supabase/supabase-js";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import { publicarTermos } from "./apoio-termos.mjs";

const BASE = process.env.SUPABASE_URL, SAIDA = process.env.SAIDA || "/tmp/certificados-telas";
fs.mkdirSync(SAIDA, { recursive: true });
let ok = 0, falhas = 0;
const check = (c, n, x) => { if (c) { ok++; console.log("  ✓ " + n); } else { falhas++; console.log("  ✗ " + n + (x !== undefined ? "  → " + String(x).slice(0, 300).replace(/\n/g, " ") : "")); } };
const novo = () => createClient(BASE, process.env.SUPABASE_ANON_KEY, { auth: { persistSession: false } });
const hojeISO = new Date().toLocaleDateString("sv-SE");

const saida = execFileSync("node", ["../scripts/criar-primeiros-masters.mjs", "Primeiro Master Teste|master1@exemplo.com|31900000001"], { env: process.env }).toString();
const api = novo();
await api.auth.signInWithPassword({ email: "master1@exemplo.com", password: saida.match(/senha temporária: (\S+)/)[1] });
await api.auth.updateUser({ password: "Ezequiel-Nova-2026" });
const mins = (await api.from("ministerios").select("id,nome")).data, mid = (n) => mins.find((m) => m.nome === n).id;
const cria = async (nome, email, atr, mm) => (await api.functions.invoke("admin-usuarios", { body: { acao: "criar", nome, telefone: "31999990000", email, perfil: "LIDER", atribuicoes: atr, ministerios: mm } })).data;
const E = await cria("Elaine Secretaria Teste", "elaine@teste.com", ["SECRETARIA"], [{ ministerio_id: mid("Secretaria"), funcao: "lider" }]);
const L = await cria("Lia Lider Louvor", "lia@teste.com", [], [{ ministerio_id: mid("Louvor"), funcao: "lider" }]);
const T = await publicarTermos();
const cursos = (await api.rpc("cursos_admin_listar")).data.cursos, herm = cursos.find((c) => c.slug === "hermeneutica");
await api.rpc("cursos_salvar_curso", { p: { ...herm, publicado: true, carga_horaria: "20 horas" } });
const turma = (await api.rpc("cursos_salvar_turma", { p: { curso_id: herm.id, nome: "Turma 2026", status: "em_andamento", vagas: "30" } })).data.id;
const inscr = async (nome, n, email) => (await api.rpc("inscrever_curso_com_termos", { p_turma: turma, p_nome: nome, p_telefone: "319111100" + n, p_email: email, p_data_nascimento: "1990-05-10",
  p_observacao: null, p_aceite_privacidade: true, p_termo_participacao: T.participacao_curso, p_imagem: null, p_responsavel: null, p_origem: "secretaria", p_termo_presencial: true })).data;
const A = await inscr("Ana Aluna Teste", "01", "ana@teste.com"); await inscr("Bruno Aluno Teste", "02", "bruno@teste.com"); await inscr("Carla Aluna Teste", "03", "carla@teste.com");

const browser = await chromium.launch({ executablePath: "/usr/bin/google-chrome", args: ["--no-sandbox"] });
const nova = async (mobile) => { const ctx = await browser.newContext(mobile ? { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true } : { viewport: { width: 1360, height: 900 } });
  const p = await ctx.newPage(); p.erros = []; p.on("pageerror", (x) => p.erros.push(x.message)); p.on("dialog", (d) => d.dismiss()); return p; };
const foto = (p, n, sel) => (sel ? p.locator(sel).screenshot({ path: `${SAIDA}/${n}.png` }) : p.screenshot({ path: `${SAIDA}/${n}.png`, fullPage: true }));
const texto = (p, sel, t) => p.waitForFunction(([s, t]) => document.querySelector(s)?.textContent.replace(/ /g, " ").includes(t), [sel, t], { timeout: 10000 });
const item = (p, nome) => p.locator(".sbItem", { hasText: nome });
async function entrar(p, email, temp, nova) {
  await p.goto(BASE + "/#equipe/entrar"); await p.waitForSelector("#sbLogin"); await p.fill("#sbEmail", email); await p.fill("#sbSenha", temp); await p.click("#sbEntrar");
  await p.waitForSelector("#sbNovaSenha"); await p.fill("#nsSenha", nova); await p.fill("#nsConf", nova); await p.click("#nsSalvar"); await p.waitForSelector("#sbPainel:not([hidden])");
}

console.log("\n1. Secretaria define quem valida a turma");
const s = await nova(); await entrar(s, "elaine@teste.com", E.senha_temporaria, "Elaine-Nova-2026");
await s.click('[data-sb="aba:cursos"]'); await texto(s, "#sbConteudo", "Hermenêutica");
await s.locator(".row", { hasText: "Hermenêutica" }).locator('[data-cu^="turmas:"]').click(); await s.click(`[data-cu$=":${turma}"][data-cu^="turma:"]`);
await s.waitForSelector('#cuResp input[name="responsavel"]');
await s.locator("#cuResp label", { hasText: "Lia Lider Louvor" }).locator("input").check();
await foto(s, "01-turma-responsaveis", "#cuResp");
await s.click('#cuFormTurma [type="submit"]'); await s.waitForSelector("#cuFormTurma", { state: "detached" });
check((await api.rpc("cursos_responsaveis_turma", { p_turma: turma })).data[0]?.nome === "Lia Lider Louvor", "Lia definida como responsável pela validação da turma");

console.log("\n2. Liderança valida as conclusões");
const l = await nova(); await entrar(l, "lia@teste.com", L.senha_temporaria, "Lia-Nova-20261");
const abasL = await l.$$eval("#sbAbas button", (b) => b.map((x) => x.textContent.trim()));
check(abasL.includes("Turmas") && !abasL.includes("Secretaria"), "a líder tem a aba Turmas e não acessa a Secretaria (nem a impressão)", abasL.join("|"));
await l.click('[data-sb="aba:turmas"]'); await texto(l, "#sbConteudo", "Ana Aluna Teste");
await foto(l, "02-lider-turmas", "#v-equipe");
await item(l, "Ana Aluna Teste").locator('[data-lt^="concluirForm:"]').click(); await l.click('[data-lt-form="concluir"] [type="submit"]');
await texto(l, '[data-lt-form="concluir"] .msg', "Marque o atestado"); check(true, "concluir exige atestar frequência e atividades");
await l.fill('[data-lt-form="concluir"] [name="obs"]', "100% de frequência"); await l.check('[data-lt-form="concluir"] [name="atesto"]'); await l.click('[data-lt-form="concluir"] [type="submit"]');
await l.waitForFunction(() => [...document.querySelectorAll(".sbItem")].find((x) => x.textContent.includes("Ana Aluna Teste"))?.textContent.includes("Aguardando autorização"));
check(true, "Ana concluída e validada pela líder: aguardando autorização da Secretaria");
const sec = novo(); await sec.auth.signInWithPassword({ email: "elaine@teste.com", password: "Elaine-Nova-2026" });
const ins = (await sec.rpc("cursos_listar_inscricoes", { p_turma: turma })).data;
for (const n of ["Bruno Aluno Teste", "Carla Aluna Teste"]) await sec.rpc("cursos_alterar_inscricao", { p_inscricao: ins.find((i) => i.nome === n).id, p_acao: "concluir", p_motivo: null });
await l.click('[data-sb="aba:turmas"]'); await texto(l, "#sbConteudo", "Aguardando validação da liderança");
const vb = item(l, "Bruno Aluno Teste").locator('[data-lt^="validar:"]'); await vb.click(); await vb.click();
await l.waitForFunction(() => [...document.querySelectorAll(".sbItem")].find((x) => x.textContent.includes("Bruno Aluno Teste"))?.textContent.includes("Aguardando autorização"));
check(true, "conclusão do Bruno (marcada pela Secretaria) validada pela líder");
await item(l, "Carla Aluna Teste").locator('[data-lt^="naoForm:"]').click(); await l.fill('[data-lt-form="nao"] [name="obs"]', "Frequência abaixo do mínimo");
await l.click('[data-lt-form="nao"] [type="submit"]');
await l.waitForFunction(() => [...document.querySelectorAll(".sbItem")].find((x) => x.textContent.includes("Carla Aluna Teste"))?.textContent.includes("cursando"));
check(true, "conclusão da Carla não validada: ela volta a \"cursando\"");

console.log("\n3. Secretaria autoriza, cadastra a cerimônia e o modelo");
await s.click('[data-sb="aba:secretaria"]'); await s.click('[data-se="tela:certificados"]'); await texto(s, "#seCertBox", "Conclusões validadas pela liderança (2)");
await foto(s, "03-autorizar-emissao", "#v-equipe");
for (const n of ["Ana Aluna Teste", "Bruno Aluno Teste"]) { const b = item(s, n).locator('[data-ce^="autorizar:"]'); await b.click(); await b.click();
  await s.waitForFunction((n) => ![...document.querySelectorAll("#seCertBox .sbItem")].some((x) => x.textContent.includes(n) && x.querySelector("[data-ce^='autorizar:']")), n); }
await texto(s, "#seCertBox", "Nada para autorizar"); check(true, "emissões de Ana e Bruno autorizadas");
await s.click('[data-ce="tela:cerimonias"]'); await s.waitForSelector('[data-ce-form="cerimonia"]');
await s.fill('[data-ce-form="cerimonia"] [name="titulo"]', "Culto de formatura"); await s.click('[data-ce-form="cerimonia"] [type="submit"]');
await texto(s, '[data-ce-form="cerimonia"] .msg', "data, horário e local"); check(true, "cerimônia exige data, horário e local");
await s.fill('[data-ce-form="cerimonia"] [name="data"]', hojeISO); await s.fill('[data-ce-form="cerimonia"] [name="horario"]', "19:30"); await s.fill('[data-ce-form="cerimonia"] [name="local"]', "Templo");
await s.fill('[data-ce-form="cerimonia"] [name="responsavel"]', "Pastor presidente"); await s.click('[data-ce-form="cerimonia"] [type="submit"]'); await texto(s, "#seCertBox", "Culto de formatura");
check((await s.textContent("#seCertBox")).includes("19:30") && (await s.textContent("#seCertBox")).includes("Templo"), "cerimônia cadastrada com data, horário e local");
await s.click('[data-ce="tela:modelo"]'); await s.fill('[data-ce-form="modelo"] [name="a0n"]', "Nome do pastor (teste)"); await s.fill('[data-ce-form="modelo"] [name="a0c"]', "Pastor");
await s.fill('[data-ce-form="modelo"] [name="a1n"]', "Nome da secretária (teste)"); await s.fill('[data-ce-form="modelo"] [name="a1c"]', "Secretaria");
await s.click('[data-ce-form="modelo"] [type="submit"]'); await s.waitForSelector('[data-ce-form="modelo"]');
check((await s.inputValue('[data-ce-form="modelo"] [name="a0c"]')) === "Pastor", "modelo do certificado salvo (assinaturas)");

console.log("\n4. Vínculo, impressão em lote e lista de entrega");
await s.click('[data-ce="tela:lista"]'); await texto(s, "#seCertBox", "Ana Aluna Teste");
for (const n of ["Ana Aluna Teste", "Bruno Aluno Teste"]) { await item(s, n).locator("[data-ce-vincular]").selectOption({ index: 1 });
  await s.waitForFunction((n) => [...document.querySelectorAll(".sbItem")].find((x) => x.textContent.includes(n))?.textContent.includes("Vinculado"), n); }
check(true, "Ana e Bruno vinculados ao culto de formatura");
check(!(await item(s, "Ana Aluna Teste").locator("[data-ce^='entregaForm:']").count()), "não há como registrar entrega antes de imprimir");
await s.click('[data-ce="tela:cerimonias"]'); await texto(s, "#seCertBox", "Imprimir 2 pendente(s)");
const [imp] = await Promise.all([s.context().waitForEvent("page"), s.click('[data-ce^="lote:"]')]);
await imp.waitForLoadState(); const ti = await imp.textContent("body");
check(ti.includes("Ana Aluna Teste") && ti.includes("Bruno Aluno Teste") && ti.includes("Nome do pastor (teste)") && ti.includes("20 horas"), "impressão em lote: 2 certificados com o modelo (assinaturas e carga horária)");
await imp.screenshot({ path: `${SAIDA}/04-impressao-lote.png` }); await imp.close();
const [lst] = await Promise.all([s.context().waitForEvent("page"), s.click('[data-ce^="listaCer:"]')]);
await lst.waitForLoadState(); check((await lst.textContent("body")).includes("Assinatura de quem recebeu"), "lista de entrega para conferência no dia"); await lst.screenshot({ path: `${SAIDA}/05-lista-entrega.png` }); await lst.close();

console.log("\n5. Entrega física e histórico");
await s.click('[data-ce="tela:lista"]'); await texto(s, "#seCertBox", "Impresso");
await item(s, "Ana Aluna Teste").locator('[data-ce^="entregaForm:"]').click(); await s.click('[data-ce-form="entregar"] [type="submit"]');
await texto(s, '[data-ce-form="entregar"] .msg', "em mãos"); check(true, "sem confirmar a entrega em mãos, não registra");
await s.check('[data-ce-form="entregar"] [name="confirmo"]');
await foto(s, "06-registrar-entrega", "#v-equipe");
await s.click('[data-ce-form="entregar"] [type="submit"]'); await texto(s, "#seCertBox", "recebido por Ana Aluna Teste");
check(true, "entrega física da Ana registrada");
await item(s, "Ana Aluna Teste").locator('[data-ce^="hist:"]').click(); await texto(s, "#seCertBox", "Histórico de emissão e entrega");
const hist = await item(s, "Ana Aluna Teste").textContent();
check(["Certificado gerado", "Emissão autorizada", "Vinculado", "Impresso", "Entregue em mãos"].every((x) => hist.includes(x)) && hist.includes("Elaine Secretaria Teste"), "histórico de emissão e entrega na tela");
await foto(s, "07-historico", "#v-equipe");
await s.click('[data-ce="tela:cerimonias"]'); const rb = s.locator('[data-ce^="realizada:"]'); await rb.click(); await rb.click();
await texto(s, "#seCertBox", "realizada"); check(true, "cerimônia marcada como realizada");

console.log("\n6. O participante");
const pa = await nova(true); await pa.goto(`${BASE}/#inscricao-curso/${A.protocolo}/${A.chave}`); await texto(pa, "#cuMinha", "somente em mãos");
const tp = await pa.textContent("#cuMinha");
check(tp.includes("Certificado: entregue") && !(await pa.$("#cuMinha a[download], #cuMinha a[href*='storage']")) && !tp.includes(A.protocolo + "-"), "o participante vê só a situação, sem download nem envio");
await foto(pa, "08-participante-celular", "#cuMinha");

for (const [n, p] of [["Secretaria", s], ["líder", l], ["participante", pa]]) check(!p.erros.length, `sem erros de JavaScript (${n})`, p.erros.join(" | "));
await browser.close();
console.log(`\nResultado: ${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
