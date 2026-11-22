// Etapa 4 — Secretaria e Tesouraria nas telas: participante, Secretaria e Tesouraria, com capturas.
import { chromium } from "playwright-core";
import { createClient } from "@supabase/supabase-js";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import { paramsTermos, prepararVoluntario } from "./apoio-termos.mjs";

const BASE = process.env.SUPABASE_URL, SAIDA = process.env.SAIDA || "/tmp/financeiro-telas";
fs.mkdirSync(SAIDA, { recursive: true });
let ok = 0, falhas = 0;
const check = (c, n, x) => { if (c) { ok++; console.log("  ✓ " + n); } else { falhas++; console.log("  ✗ " + n + (x !== undefined ? "  → " + String(x).slice(0, 300) : "")); } };
const novo = () => createClient(BASE, process.env.SUPABASE_ANON_KEY, { auth: { persistSession: false } });

// preparação pela API: MASTER, Secretaria, Tesouraria, líder, curso publicado com turma de R$ 100
const saida = execFileSync("node", ["../supabase/scripts/criar-primeiros-masters.mjs", "Primeiro Master Teste|master1@exemplo.com|31900000001"], { env: process.env }).toString();
const api = novo();
await api.auth.signInWithPassword({ email: "master1@exemplo.com", password: saida.match(/senha temporária: (\S+)/)[1] });
await api.auth.updateUser({ password: "Ezequiel-Nova-2026" });
const minSec = (await api.from("ministerios").select("id,nome")).data.find((m) => m.nome === "Secretaria").id;
const cria = async (nome, email, atr) => (await api.functions.invoke("admin-usuarios", { body: { acao: "criar", nome, telefone: "31999990000", email, perfil: "LIDER", atribuicoes: atr, ministerios: [{ ministerio_id: minSec, funcao: "lider" }] } })).data;
const E = await cria("Elaine Secretaria Teste", "elaine@teste.com", ["SECRETARIA"]), T = await cria("Tadeu Tesoureiro Teste", "tadeu@teste.com", ["TESOURARIA"]), L = await cria("Lia Líder Teste", "lia@teste.com", []);
const herm = (await api.rpc("cursos_admin_listar")).data.cursos.find((c) => c.slug === "hermeneutica");
await api.rpc("cursos_salvar_curso", { p: { ...herm, publicado: true, cursos_exigidos: [] } });
const turma = (await api.rpc("cursos_salvar_turma", { p: { curso_id: herm.id, nome: "Turma paga", status: "inscricoes_abertas", vagas: "20", valor: "100" } })).data.id;
const inscr = async (n, tel, email) => (await novo().rpc("inscrever_curso_com_termos", { ...(await paramsTermos()), p_turma: turma, p_nome: n, p_telefone: tel, p_email: email, p_data_nascimento: "1990-05-10", p_observacao: null, p_aceite_privacidade: true, p_origem: "site" })).data;
const A = await inscr("Ana Participante", "31911110001", "ana@teste.com"), B = await inscr("Bruno Participante", "31911110002", "bruno@teste.com"), C = await inscr("Carla Participante", "31911110003", "carla@teste.com");
fs.writeFileSync("/tmp/comprovante.png", Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=", "base64"));
fs.writeFileSync("/tmp/recibo.pdf", "%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF");

const browser = await chromium.launch({ executablePath: "/usr/bin/google-chrome", args: ["--no-sandbox"] });
const nova = async (mobile) => { const ctx = await browser.newContext(mobile ? { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true } : { viewport: { width: 1360, height: 900 }, acceptDownloads: true });
  const p = await ctx.newPage(); p.erros = []; p.on("pageerror", (x) => p.erros.push(x.message)); p.on("dialog", (d) => { p.ultimoAlerta = d.message(); d.dismiss(); }); return p; };
const foto = (p, n, sel) => (sel ? p.locator(sel).screenshot({ path: `${SAIDA}/${n}.png` }) : p.screenshot({ path: `${SAIDA}/${n}.png`, fullPage: true }));
const texto = (p, sel, t) => p.waitForFunction(([s, t]) => document.querySelector(s)?.textContent.replace(/\u00a0/g, " ").includes(t), [sel, t], { timeout: 10000 });
const abas = (p) => p.$$eval("#sbAbas button", (b) => b.map((x) => x.textContent.trim().replace(/\s*\d+$/, "")));
async function entrar(p, email, temp, nova) {
  await p.goto(BASE + "/#equipe/entrar"); await p.waitForSelector("#sbLogin"); await p.fill("#sbEmail", email); await p.fill("#sbSenha", temp); await p.click("#sbEntrar");
  await p.waitForSelector("#sbNovaSenha"); await p.fill("#nsSenha", nova); await p.fill("#nsConf", nova); await p.click("#nsSalvar"); await p.waitForSelector("#sbPainel:not([hidden])");
}
const minha = async (x) => (await novo().rpc("minha_inscricao_curso", { p_protocolo: x.protocolo, p_chave: x.chave })).data;

console.log("\n1. Participante envia o comprovante pelo link pessoal");
const pa = await nova(true);
await pa.goto(`${BASE}/#inscricao-curso/${A.protocolo}/${A.chave}`); await pa.waitForSelector(".cuComprovante");
check((await pa.textContent("#cuMinha")).includes("não confirma a inscrição"), "a página avisa que o envio não confirma a inscrição");
await foto(pa, "01-participante-pagamento");
await pa.click('.cuComprovante [type="submit"]'); await texto(pa, ".cuComprovante .msg", "Anexe o comprovante");
check(true, "sem arquivo, o formulário não envia");
await pa.fill('.cuComprovante [name="pago_em"]', "2026-11-20"); await pa.setInputFiles('.cuComprovante [name="arquivo"]', "/tmp/comprovante.png");
await pa.click('.cuComprovante [type="submit"]'); await texto(pa, "#cuMinha", "está em análise");
check((await pa.textContent("#cuMinha")).includes("Aguardando pagamento") && !(await pa.$(".cuComprovante")), "depois do envio: em análise, inscrição ainda aguardando, sem novo envio");
await foto(pa, "02-participante-em-analise");

console.log("\n2. Abas separadas por atribuição");
const s = await nova(); await entrar(s, "elaine@teste.com", E.senha_temporaria, "Elaine-Nova-2026");
let a = await abas(s);
check(a.includes("Secretaria") && a.includes("Avisos") && !a.includes("Tesouraria"), "Secretaria vê Secretaria e Avisos, não vê Tesouraria", a.join("|"));
const t = await nova(); await entrar(t, "tadeu@teste.com", T.senha_temporaria, "Tadeu-Nova-2026");
a = await abas(t);
check(a.includes("Tesouraria") && a.includes("Avisos") && !a.includes("Secretaria") && !a.includes("Cursos"), "Tesouraria vê Tesouraria e Avisos, não vê Secretaria nem Cursos", a.join("|"));
check(await t.waitForFunction(() => /Avisos\s*1/.test(document.querySelector('#sbAbas [data-sb="aba:avisos"]')?.textContent || ""), null, { timeout: 8000 }).then(() => true, () => false), "aba Avisos da Tesouraria mostra 1 não lido");
const l = await nova(); await entrar(l, "lia@teste.com", L.senha_temporaria, "Lia-Nova-20261");
a = await abas(l);
check(!a.includes("Secretaria") && !a.includes("Tesouraria"), "líder sem atribuição não vê Secretaria nem Tesouraria", a.join("|"));
await l.context().close();
const m = await nova(); await m.goto(BASE + "/#equipe/entrar"); await m.fill("#sbEmail", "master1@exemplo.com"); await m.fill("#sbSenha", "Ezequiel-Nova-2026"); await m.click("#sbEntrar"); await m.waitForSelector("#sbPainel:not([hidden])");
a = await abas(m);
check(a.includes("Secretaria") && !a.includes("Tesouraria"), "MASTER sem atribuição vê Secretaria, mas não Tesouraria", a.join("|"));
await m.context().close();

console.log("\n3. Secretaria: inscrições e pagamento presencial");
await s.click('[data-sb="aba:secretaria"]'); await texto(s, "#sbConteudo", "Ana Participante");
check((await s.locator(".sbItem", { hasText: "Ana Participante" }).textContent()).includes("Comprovante em análise"), "Secretaria vê o status financeiro (comprovante em análise)");
check(!(await s.locator(".sbItem", { hasText: "Ana Participante" }).locator("text=abrir").count()), "Secretaria não tem acesso ao arquivo do comprovante");
check(!(await s.locator(".sbItem", { hasText: "Ana Participante" }).locator('[data-se^="presencialForm:"]').count()), "com comprovante em análise, a Secretaria não registra outro pagamento");
const itemB = s.locator(".sbItem", { hasText: "Bruno Participante" });
await itemB.locator('[data-se^="presencialForm:"]').click(); await s.waitForSelector('[data-se-form="presencial"]');
await s.selectOption('[data-se-form="presencial"] [name="metodo"]', "dinheiro"); await s.fill('[data-se-form="presencial"] [name="observacao"]', "Recebido no balcão após o culto");
await s.setInputFiles('[data-se-form="presencial"] [name="arquivo"]', "/tmp/recibo.pdf");
await foto(s, "03-secretaria-registro-presencial", "#v-equipe");
await s.click('[data-se-form="presencial"] [type="submit"]');
await s.waitForFunction(() => [...document.querySelectorAll(".sbItem")].find((x) => x.textContent.includes("Bruno Participante"))?.textContent.includes("Em análise"));
check((await itemB.textContent()).includes("Aguardando pagamento") && (await itemB.textContent()).includes("presencial"), "presencial registrado com recibo: em análise, inscrição ainda aguardando");
const itemC = s.locator(".sbItem", { hasText: "Carla Participante" });
await itemC.locator('[data-se^="bolsaForm:"]').click(); await s.selectOption('[data-se-form="bolsa"] [name="tipo"]', "isencao");
await s.fill('[data-se-form="bolsa"] [name="motivo"]', "Voluntária da equipe de recepção"); await s.click('[data-se-form="bolsa"] [type="submit"]');
await s.waitForFunction(() => [...document.querySelectorAll(".sbItem")].find((x) => x.textContent.includes("Carla Participante"))?.textContent.includes("Isenção · aguardando a Tesouraria"));
check(true, "Secretaria pede isenção para outra inscrição");
await foto(s, "04-secretaria-inscricoes", "#v-equipe");

console.log("\n4. Tesouraria: painel, análise e bolsas");
await t.click('[data-sb="aba:tesouraria"]'); await texto(t, "#sbConteudo", "Comprovantes em análise");
check((await t.textContent("#sbConteudo")).replace(/\u00a0/g, " ").includes("R$ 200,00 aguardando"), "painel mostra 2 comprovantes (R$ 200) em análise");
await foto(t, "05-tesouraria-painel", "#v-equipe");
await t.click('[data-te="tela:fila"]'); await texto(t, "#sbConteudo", "Ana Participante");
const [popup] = await Promise.all([t.context().waitForEvent("page"), t.locator(".sbItem", { hasText: "Ana Participante" }).locator('[data-te^="ver:"]').click()]);
await popup.waitForLoadState(); check(popup.url().includes("/storage/v1/object/sign/comprovantes/"), "abrir o comprovante usa link temporário assinado"); await popup.close();
await t.locator(".sbItem", { hasText: "Ana Participante" }).locator('[data-te^="motivo:solicitar_novo:"]').click();
await t.fill('[data-te-form="analise"] [name="obs"]', "Imagem ilegível, envie o PDF do banco."); await t.click('[data-te-form="analise"] [type="submit"]');
await t.waitForFunction(() => !document.querySelector("#sbConteudo").textContent.includes("Ana Participante"));
const bt = t.locator(".sbItem", { hasText: "Bruno Participante" }).locator('[data-te^="aprovar:"]');
await bt.click(); check((await bt.textContent()).includes("Confirmar"), "aprovação pede confirmação"); await bt.click();
await texto(t, "#sbConteudo", "Nenhum comprovante aguardando");
check((await minha(B)).status === "confirmada", "presencial validado: inscrição do Bruno confirmada");
await t.click('[data-te="tela:bolsas"]'); await texto(t, "#sbConteudo", "Carla Participante");
await foto(t, "06-tesouraria-bolsas", "#v-equipe");
await t.locator(".sbItem", { hasText: "Carla Participante" }).locator('[data-te^="benef:aprovar:"]').click();
await t.waitForFunction(() => [...document.querySelectorAll(".sbItem")].find((x) => x.textContent.includes("Carla Participante"))?.textContent.includes("aprovado"));
check((await minha(C)).status === "confirmada", "isenção aprovada: inscrição da Carla confirmada");

console.log("\n5. Participante vê o pedido, reenvia e é confirmado");
await pa.reload(); await pa.waitForSelector(".cuComprovante");
check((await pa.textContent("#cuMinha")).includes("Imagem ilegível, envie o PDF do banco."), "participante vê a explicação da Tesouraria");
await foto(pa, "07-participante-novo-comprovante");
await pa.fill('.cuComprovante [name="pago_em"]', "2026-11-20"); await pa.setInputFiles('.cuComprovante [name="arquivo"]', "/tmp/recibo.pdf");
await pa.click('.cuComprovante [type="submit"]'); await texto(pa, "#cuMinha", "está em análise");
await t.click('[data-te="tela:fila"]'); await texto(t, "#sbConteudo", "Ana Participante");
check((await t.locator(".sbItem", { hasText: "Ana Participante" }).textContent()).includes("substituído"), "Tesouraria vê o comprovante anterior como substituído");
const ba = t.locator(".sbItem", { hasText: "Ana Participante" }).locator('[data-te^="aprovar:"]'); await ba.click(); await ba.click();
await texto(t, "#sbConteudo", "Nenhum comprovante aguardando");
await pa.reload(); await texto(pa, "#cuMinha", "Inscrição confirmada");
check(true, "após a aprovação, o participante vê a inscrição confirmada");
await foto(pa, "08-participante-confirmada");

console.log("\n6. Reembolso, relatórios e exportação");
await sbCancelar();
async function sbCancelar() {
  await s.click('[data-sb="aba:secretaria"]'); await texto(s, "#sbConteudo", "Ana Participante");
  await s.locator(".sbItem", { hasText: "Ana Participante" }).locator('[data-se^="cancelarInscForm:"]').click();
  await s.fill('[data-se-form="cancelarInsc"] [name="motivo"]', "Desistiu antes do início"); await s.click('[data-se-form="cancelarInsc"] [type="submit"]');
  await s.waitForFunction(() => [...document.querySelectorAll(".sbItem")].find((x) => x.textContent.includes("Ana Participante"))?.textContent.includes("Cancelada"));
}
await t.click('[data-sb="aba:tesouraria"]'); await t.click('[data-te="tela:pagamentos"]'); await texto(t, "#sbConteudo", "Ana Participante");
await t.locator(".sbItem", { hasText: "Ana Participante" }).locator('[data-te^="reembolsoForm:"]').click();
await t.fill('[data-te-form="reembolso"] [name="motivo"]', "Desistência antes do início"); await t.click('[data-te-form="reembolso"] [type="submit"]');
await texto(t, "#sbConteudo", "Pagamentos e reembolsos");
await t.click('[data-te="tela:relatorios"]'); await texto(t, "#sbConteudo", "movimentação");
const rel = (await t.textContent("#sbConteudo")).replace(/\u00a0/g, " ");
check(rel.includes("Entradas R$ 200,00") && rel.includes("reembolsos R$ 100,00") && rel.includes("saldo R$ 100,00"), "relatório do mês: entradas R$ 200, reembolso R$ 100, saldo R$ 100", rel.slice(0, 300));
await foto(t, "09-tesouraria-relatorio", "#v-equipe");
const [dl] = await Promise.all([t.waitForEvent("download"), t.click('[data-te="csvMov"]')]);
const csv = fs.readFileSync(await dl.path(), "utf8");
check(csv.split("\r\n").length === 4 && csv.includes("Ana Participante") && csv.includes("-100"), "CSV de movimentações exportado (cabeçalho + 3 linhas)", csv.slice(0, 300));
const [dl2] = await Promise.all([t.waitForEvent("download"), t.click('[data-te="csvPag"]')]);
check(fs.readFileSync(await dl2.path(), "utf8").split("\r\n").length === 3, "CSV de todos os pagamentos exportado (2 pagamentos: Ana e Bruno; Carla foi isenta)");

console.log("\n7. Membresia, documentos e certificado entregue em mãos");
await s.click('[data-se="tela:pessoas"]'); await texto(s, "#sbConteudo", "Bruno Participante");
const pB = s.locator(".sbItem", { hasText: "Bruno Participante" });
await pB.locator('[data-se^="membForm:"]').click(); await s.selectOption('[data-se-form="membresia"] [name="situacao"]', "membro");
await s.fill('[data-se-form="membresia"] [name="desde"]', "2019-05-12"); await s.fill('[data-se-form="membresia"] [name="obs"]', "Carta de transferência recebida em 2019"); await s.click('[data-se-form="membresia"] [type="submit"]');
await s.waitForFunction(() => [...document.querySelectorAll(".sbItem")].find((x) => x.textContent.includes("Bruno Participante"))?.textContent.includes("validado por Elaine"));
check(true, "membresia validada, com quem validou e quando");
await s.locator(".sbItem", { hasText: "Bruno Participante" }).locator('[data-se^="docs:"]').click(); await s.waitForSelector('[data-se-form="documento"]');
await s.selectOption('[data-se-form="documento"] [name="tipo"]', "carta_transferencia"); await s.setInputFiles('[data-se-form="documento"] [name="arquivo"]', "/tmp/recibo.pdf");
await s.click('[data-se-form="documento"] [type="submit"]'); await texto(s, "#sbConteudo", "Carta de transferência");
check(true, "documento enviado ao arquivo privado");
await foto(s, "10-secretaria-pessoas", "#v-equipe");
await s.click('[data-se="tela:inscricoes"]'); await texto(s, "#sbConteudo", "Bruno Participante");
await s.locator(".sbItem", { hasText: "Bruno Participante" }).locator('[data-se^="inscr:concluir:"]').click();
await s.waitForFunction(() => [...document.querySelectorAll(".sbItem")].find((x) => x.textContent.includes("Bruno Participante"))?.textContent.includes("Concluída"));
// Etapa 6: a conclusão marcada pela Secretaria precisa da validação da liderança (aqui, o MASTER)
const certB = (await api.rpc("secretaria_certificados", {})).data.certificados.find((x) => x.nome === "Bruno Participante");
await api.rpc("lider_validar_certificado", { p_certificado: certB.id, p_acao: "validar", p_observacao: null });
await s.click('[data-se="tela:certificados"]'); await texto(s, "#sbConteudo", "Bruno Participante");
const au = s.locator(".sbItem:has-text('Bruno Participante') [data-ce^='autorizar:']"); await au.click(); await au.click();
await texto(s, "#sbConteudo", "Nada para autorizar");
await s.click('[data-ce="tela:cerimonias"]'); await s.waitForSelector('[data-ce-form="cerimonia"]');
await s.fill('[data-ce-form="cerimonia"] [name="titulo"]', "Entrega de certificados — culto de domingo"); await s.fill('[data-ce-form="cerimonia"] [name="local"]', "Templo");
await s.fill('[data-ce-form="cerimonia"] [name="data"]', new Date().toLocaleDateString("sv-SE")); await s.fill('[data-ce-form="cerimonia"] [name="horario"]', "19:30");
await s.click('[data-ce-form="cerimonia"] [type="submit"]'); await texto(s, "#sbConteudo", "culto de domingo");
await s.click('[data-ce="tela:lista"]'); await texto(s, "#sbConteudo", "Bruno Participante");
await s.selectOption(".sbItem:has-text('Bruno Participante') [data-ce-vincular]", { index: 1 });
await s.waitForSelector(".sbItem:has-text('Bruno Participante') [data-ce^='imprimir:']");
const [imp] = await Promise.all([s.context().waitForEvent("page"), s.click(".sbItem:has-text('Bruno Participante') [data-ce^='imprimir:']")]);
await imp.waitForLoadState(); const ti = await imp.textContent("body");
check(ti.includes("Bruno Participante") && ti.includes("Hermenêutica") && ti.includes("CERTIFICADO"), "certificado abre para impressão pela Secretaria");
await imp.screenshot({ path: `${SAIDA}/11-certificado-impressao.png` }); await imp.close();
await s.waitForSelector(".sbItem:has-text('Bruno Participante') [data-ce^='entregaForm:']");
await s.click(".sbItem:has-text('Bruno Participante') [data-ce^='entregaForm:']"); await s.check('[data-ce-form="entregar"] [name="confirmo"]');
await s.click('[data-ce-form="entregar"] [type="submit"]'); await texto(s, "#sbConteudo", "recebido por Bruno Participante");
check(true, "entrega em mãos registrada");
await foto(s, "12-secretaria-certificados", "#v-equipe");
const pb = await nova(true); await pb.goto(`${BASE}/#inscricao-curso/${B.protocolo}/${B.chave}`); await texto(pb, "#cuMinha", "somente em mãos");
const tb = await pb.textContent("#cuMinha");
check(tb.includes("entregue") && tb.includes("somente em mãos") && !(await pb.$("#cuMinha a[download]")), "participante vê só a situação do certificado, sem download", tb);

console.log("\n8. Avisos");
await t.click('[data-sb="aba:avisos"]'); await texto(t, "#sbConteudo", "não lido");
await foto(t, "13-tesouraria-avisos", "#v-equipe");
await t.click('[data-sb="lerAvisos"]'); await texto(t, "#sbConteudo", "0 não lido");
check(!/\d/.test(await t.textContent('#sbAbas [data-sb="aba:avisos"]')), "marcar como lidos zera o contador");

for (const [n, p] of [["participante", pa], ["Secretaria", s], ["Tesouraria", t], ["participante 2", pb]]) check(!p.erros.length, `sem erros de JavaScript (${n})`, p.erros.join(" | "));
await browser.close();
console.log(`\nResultado: ${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
