// Etapa 5 — telas: termos, inscrição com autorização, menor, link pessoal, membresia, candidatura e liderança.
import { chromium } from "playwright-core";
import { createClient } from "@supabase/supabase-js";
import { execFileSync } from "node:child_process";
import fs from "node:fs";

const BASE = process.env.SUPABASE_URL, SAIDA = process.env.SAIDA || "/tmp/membros-telas";
fs.mkdirSync(SAIDA, { recursive: true });
let ok = 0, falhas = 0;
const check = (c, n, x) => { if (c) { ok++; console.log("  ✓ " + n); } else { falhas++; console.log("  ✗ " + n + (x !== undefined ? "  → " + String(x).slice(0, 300).replace(/\n/g, " ") : "")); } };
const novo = () => createClient(BASE, process.env.SUPABASE_ANON_KEY, { auth: { persistSession: false } });
const anos = (n) => `${new Date().getFullYear() - n}-01-15`;

// preparação pela API
const saida = execFileSync("node", ["../scripts/criar-primeiros-masters.mjs", "Primeiro Master Teste|master1@exemplo.com|31900000001"], { env: process.env }).toString();
const api = novo();
await api.auth.signInWithPassword({ email: "master1@exemplo.com", password: saida.match(/senha temporária: (\S+)/)[1] });
await api.auth.updateUser({ password: "Ezequiel-Nova-2026" });
const mins = (await api.from("ministerios").select("id,nome")).data, mid = (n) => mins.find((m) => m.nome === n).id;
const cria = async (nome, email, atr, mm) => (await api.functions.invoke("admin-usuarios", { body: { acao: "criar", nome, telefone: "31999990000", email, perfil: "LIDER", atribuicoes: atr, ministerios: mm } })).data;
const E = await cria("Elaine Secretaria Teste", "elaine@teste.com", ["SECRETARIA"], [{ ministerio_id: mid("Secretaria"), funcao: "lider" }]);
const L = await cria("Lia Lider Louvor", "lia@teste.com", [], [{ ministerio_id: mid("Louvor"), funcao: "lider" }]);
const M = await cria("Mara Lider Midia", "mara@teste.com", [], [{ ministerio_id: mid("Mídia"), funcao: "lider" }]);
const cursos = (await api.rpc("cursos_admin_listar")).data.cursos, cur = (s) => cursos.find((c) => c.slug === s);
for (const s of ["novos-membros", "formacao-de-voluntarios"]) await api.rpc("cursos_salvar_curso", { p: { ...cur(s), publicado: true } });
const turma = async (s) => (await api.rpc("cursos_salvar_turma", { p: { curso_id: cur(s).id, nome: "Turma 2026", status: "inscricoes_abertas", vagas: "40" } })).data.id;
const tNM = await turma("novos-membros"), tFV = await turma("formacao-de-voluntarios");

const browser = await chromium.launch({ executablePath: "/usr/bin/google-chrome", args: ["--no-sandbox"] });
const nova = async (mobile) => { const ctx = await browser.newContext(mobile ? { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true } : { viewport: { width: 1360, height: 900 } });
  const p = await ctx.newPage(); p.erros = []; p.on("pageerror", (x) => p.erros.push(x.message)); p.on("dialog", (d) => d.dismiss()); return p; };
const foto = (p, n, sel) => (sel ? p.locator(sel).screenshot({ path: `${SAIDA}/${n}.png` }) : p.screenshot({ path: `${SAIDA}/${n}.png`, fullPage: true }));
const texto = (p, sel, t) => p.waitForFunction(([s, t]) => document.querySelector(s)?.textContent.replace(/ /g, " ").includes(t), [sel, t], { timeout: 10000 });
async function entrar(p, email, temp, nova) {
  await p.goto(BASE + "/#equipe/entrar"); await p.waitForSelector("#sbLogin"); await p.fill("#sbEmail", email); await p.fill("#sbSenha", temp); await p.click("#sbEntrar");
  await p.waitForSelector("#sbNovaSenha"); await p.fill("#nsSenha", nova); await p.fill("#nsConf", nova); await p.click("#nsSalvar"); await p.waitForSelector("#sbPainel:not([hidden])");
}

console.log("\n1. Secretaria publica os termos");
const s = await nova(); await entrar(s, "elaine@teste.com", E.senha_temporaria, "Elaine-Nova-2026");
check((await s.$$eval("#sbAbas button", (b) => b.map((x) => x.textContent.trim()))).includes("Membresia"), "Secretaria tem a aba Membresia");
const pub0 = await nova(); await pub0.goto(BASE + "/#curso/novos-membros"); await pub0.waitForSelector(".tmBloco .notice");
check((await pub0.textContent(".tmBloco")).includes("ainda não foi publicado") && await pub0.isDisabled('.cuForm [type="submit"]'), "sem termo publicado, o formulário do site fica bloqueado"); await pub0.context().close();
await s.click('[data-sb="aba:membresia"]'); await s.click('[data-mb="tela:termos"]'); await texto(s, "#sbConteudo", "Falta preencher");
await foto(s, "01-termos-rascunho", "#v-equipe");
for (const tipo of ["Participação nos cursos", "Imagem e voz", "Adesão ao voluntariado"]) {
  const item = s.locator(".sbItem", { hasText: tipo });
  await item.locator('[data-mb^="editarTermo:"]').click(); const ta = item.locator('textarea[name="texto"]');
  await ta.fill((await ta.inputValue()).replace(/⟦[^⟧]*⟧/g, (m) => (m.includes("CNPJ") ? "CNPJ 00.000.000/0001-00 (teste)" : "secretaria@betelflamengo.com.br")));
  await item.locator('[type="submit"]').click(); await s.waitForFunction((t) => ![...document.querySelectorAll(".sbItem")].find((x) => x.textContent.includes(t))?.textContent.includes("Falta preencher"), tipo);
  const pb = s.locator(".sbItem", { hasText: tipo }).locator('[data-mb^="publicar:"]'); await pb.click(); await pb.click();
  await s.waitForFunction((t) => [...document.querySelectorAll(".sbItem")].find((x) => x.textContent.includes(t))?.textContent.includes("Em vigor"), tipo);
}
check(await s.locator(".sbItem .st", { hasText: "Em vigor" }).count() === 3, "os três termos preenchidos e publicados (versão 1)");
await foto(s, "02-termos-publicados", "#v-equipe");

console.log("\n2. Páginas públicas");
const pub = await nova();
await pub.goto(BASE + "/#servir"); await texto(pub, "#v-servir", "Membresia validada pela Secretaria");
check(!(await pub.$("#cdForm")) && !(await pub.textContent("#v-servir")).includes("Sim, sou membro"), "\"Quero servir\" mostra o caminho real; não há mais autodeclaração de membro");
await foto(pub, "03-quero-servir", "#v-servir");
await pub.goto(BASE + "/#imagem"); await texto(pub, "#imgBox", "É opcional");
check(true, "página de uso de imagem explica que a autorização é opcional");
await pub.goto(BASE + "/#membresia"); await pub.waitForSelector("#mbForm");
await pub.fill('#mbForm [name="nome"]', "Gabriel Novo Membro"); await pub.fill('#mbForm [name="telefone"]', "31911110010"); await pub.fill('#mbForm [name="email"]', "gabriel@teste.com");
await pub.fill('#mbForm [name="nascimento"]', anos(28)); await pub.check('#mbForm [name="aceite"]');
await foto(pub, "04-quero-ser-membro", "#v-membresia");
await pub.click('#mbForm [type="submit"]'); await texto(pub, "#v-membresia", "Recebemos o seu interesse");
check(true, "formulário \"Quero ser membro\" registra o interesse (sem validar nada)");

console.log("\n3. Inscrição de menor com responsável e imagem opcional");
const m = await nova(true);
await m.goto(BASE + "/#curso/novos-membros"); await m.waitForSelector('.cuForm [name="termo_participacao"]');
await m.fill('.cuForm [name="nome"]', "Theo Menor Teste"); await m.fill('.cuForm [name="telefone"]', "31911110004"); await m.fill('.cuForm [name="email"]', "theo@teste.com");
await m.fill('.cuForm [name="nascimento"]', anos(15));
check(await m.isVisible(".cuForm [data-tm-resp]"), "data de nascimento de menor mostra os campos do responsável legal");
await m.check('.cuForm [name="aceite"]'); await m.check('.cuForm [name="termo_participacao"]'); await m.click('.cuForm [type="submit"]');
await texto(m, ".cuForm .msg", "responsável legal"); check(true, "sem o responsável, a inscrição não segue");
await m.fill('.cuForm [name="resp_nome"]', "Rita Responsavel Teste"); await m.selectOption('.cuForm [name="resp_parentesco"]', "mae"); await m.fill('.cuForm [name="resp_telefone"]', "31988887777");
await m.check('.cuForm [name="resp_declara"]'); await m.check('.cuForm input[name="img"][value="aceito"]');
check(await m.isVisible(".cuForm [data-tm-escopo]"), "ao autorizar a imagem aparecem as opções fotos, vídeos e voz");
await m.uncheck('.cuForm [name="img_voz"]');
await foto(m, "05-inscricao-menor-celular", ".cuForm");
await m.click('.cuForm [type="submit"]'); await m.waitForSelector(".done");
const linkTheo = await m.getAttribute(".done a", "href");
check((await m.textContent(".done")).includes("confirmada"), "menor inscrito com a autorização da responsável");

const g = await nova();
await g.goto(BASE + "/#curso/novos-membros"); await g.waitForSelector('.cuForm [name="termo_participacao"]');
await g.fill('.cuForm [name="nome"]', "Gabriel Novo Membro"); await g.fill('.cuForm [name="telefone"]', "31911110010"); await g.fill('.cuForm [name="email"]', "gabriel@teste.com");
await g.fill('.cuForm [name="nascimento"]', anos(28)); await g.check('.cuForm [name="aceite"]'); await g.check('.cuForm [name="termo_participacao"]');
check(await g.isChecked('.cuForm input[name="img"][value=""]'), "a opção padrão da imagem é \"decidir depois\" (nada pré-marcado como autorizado)");
await g.click('.cuForm [type="submit"]'); await g.waitForSelector(".done");
check((await g.textContent(".done")).includes("confirmada"), "REGRA: adulto se inscreve sem autorizar imagem");
const linkGab = await g.getAttribute(".done a", "href");

console.log("\n4. Link pessoal: termos, autorização e revogação");
await g.goto(linkGab); await texto(g, "#tmMinha", "Termos e autorizações");
check((await g.textContent("#tmMinha")).includes("Participação nos cursos") && !(await g.textContent("#tmMinha")).includes("Imagem e voz · versão"), "o link mostra o termo aceito e nenhuma autorização de imagem");
await g.check('#tmMinha input[name="img"][value="aceito"]'); await g.uncheck('#tmMinha [name="img_videos"]'); await g.click('#tmMinha [type="submit"]');
await texto(g, "#tmMinha", "autorizado (fotos, voz)"); check(true, "autorização de imagem dada depois, pelo link (fotos e voz)");
await foto(g, "06-link-termos", "#cuMinha");
await m.goto(linkTheo); await texto(m, "#tmMinha", "pelo responsável");
const rv = m.locator("[data-tm-revogar]"); await rv.click(); await rv.click();
await texto(m, "#tmMinha", "revogado em"); check(true, "autorização do menor revogada pelo link (fica no histórico)");
await foto(m, "07-link-revogado-celular", "#cuMinha");

console.log("\n5. Secretaria valida a membresia");
const sec = novo(); await sec.auth.signInWithPassword({ email: "elaine@teste.com", password: "Elaine-Nova-2026" });
const insGab = (await sec.rpc("cursos_listar_inscricoes", { p_turma: tNM })).data.find((i) => i.nome === "Gabriel Novo Membro").id;
await sec.rpc("cursos_alterar_inscricao", { p_inscricao: insGab, p_acao: "concluir", p_motivo: null });
await s.click('[data-mb="tela:processos"]'); await texto(s, "#sbConteudo", "Gabriel Novo Membro");
check((await s.locator(".sbItem", { hasText: "Gabriel Novo Membro" }).textContent()).includes("Aguardando validação"), "Gabriel concluiu o Novos Membros: aguardando validação");
await foto(s, "08-processos-membresia", "#v-equipe");
await s.locator(".sbItem", { hasText: "Gabriel Novo Membro" }).locator('[data-mb^="validarForm:"]').click();
await s.fill('[data-mb-form="validar"] [name="desde"]', "2026-11-20"); await s.click('[data-mb-form="validar"] [type="submit"]');
await texto(s, '[data-mb-form="validar"] .msg', "fundamento"); check(true, "sem fundamento, a validação é recusada");
await s.fill('[data-mb-form="validar"] [name="fundamento"]', "Batismo em 20/11/2026, ata da assembleia nº 12"); await s.click('[data-mb-form="validar"] [type="submit"]');
await s.waitForFunction(() => !document.querySelector("#sbConteudo").textContent.includes("Gabriel Novo Membro"));
check(true, "membresia validada com fundamento; o processo sai da lista de abertos");

console.log("\n6. Formação de Voluntários, indicação e aprovação da liderança");
const pub2 = novo();
const T = (await pub2.rpc("termos_vigentes")).data;
const fv = (await pub2.rpc("inscrever_curso_com_termos", { p_turma: tFV, p_nome: "Gabriel Novo Membro", p_telefone: "31911110010", p_email: "gabriel@teste.com", p_data_nascimento: anos(28), p_observacao: null,
  p_aceite_privacidade: true, p_termo_participacao: T.participacao_curso.id, p_imagem: null, p_responsavel: null, p_origem: "site", p_termo_presencial: false })).data;
check(fv?.status === "confirmada", "membro validado com Novos Membros entra na Formação de Voluntários");
await sec.rpc("cursos_alterar_inscricao", { p_inscricao: (await sec.rpc("cursos_listar_inscricoes", { p_turma: tFV })).data[0].id, p_acao: "concluir", p_motivo: null });
await g.goto(`${BASE}/#inscricao-curso/${fv.protocolo}/${fv.chave}`); await g.waitForSelector(".tmCandidatura");
await g.selectOption('.tmCandidatura select[name="ministerio"] >> nth=0', { label: "Louvor" }); await g.selectOption('.tmCandidatura select[name="ministerio"] >> nth=1', { label: "Mídia" });
await g.click('.tmCandidatura [type="submit"]'); await texto(g, ".tmCandidatura .msg", "termo de adesão");
check(true, "sem aceitar o termo de adesão, a indicação não é enviada");
await g.check('.tmCandidatura [name="termo"]');
await foto(g, "09-candidatura-indicacao", "#cuMinha");
await g.click('.tmCandidatura [type="submit"]'); await texto(g, "#tmCand", "Em análise pela liderança");
check((await g.textContent("#tmCand")).includes("1. Louvor") && (await g.textContent("#tmCand")).includes("2. Mídia"), "indicação enviada: Louvor (1ª) e Mídia (2ª)");
const l = await nova(); await entrar(l, "lia@teste.com", L.senha_temporaria, "Lia-Nova-20261");
check(/Avisos\s*1/.test(await l.textContent('#sbAbas [data-sb="aba:avisos"]')), "a líder de Louvor recebe um aviso");
await l.click('[data-sb="aba:candidatos"]'); await texto(l, "#sbConteudo", "Gabriel Novo Membro");
check((await l.textContent("#sbConteudo")).includes("Aprovar em Louvor") && !(await l.textContent("#sbConteudo")).includes("Aprovar em Mídia"), "a líder só decide pelo Louvor");
await foto(l, "10-lider-candidatos", "#v-equipe");
const ab = l.locator('[data-lc^="aprovar:"]'); await ab.click(); await ab.click();
await texto(l, "#sbConteudo", "aprovado"); check(true, "Louvor aprova o candidato");
await g.reload(); await texto(g, "#tmCand", "Aprovada"); check((await g.textContent("#tmCand")).includes("A Secretaria vai enviar o acesso"), "o candidato vê a aprovação no link pessoal");

console.log("\n7. Ficha da pessoa e consulta da Mídia");
await s.click('[data-mb="tela:pessoa"]'); await s.fill("#mbBusca", "gabriel@teste.com"); await s.click('[data-mb="buscar"]');
await s.click('[data-mb^="ficha:"]'); await texto(s, "#sbConteudo", "Histórico de consentimentos");
const ficha = await s.textContent("#sbConteudo");
check(ficha.includes("membresia validada") && ficha.includes("Louvor (voluntário)") && ficha.includes("Adesão ao voluntariado"), "ficha mostra requisitos cumpridos, o ministério e o termo de adesão");
await foto(s, "11-ficha-pessoa", "#v-equipe");
const mi = await nova(); await entrar(mi, "mara@teste.com", M.senha_temporaria, "Mara-Nova-2026");
await mi.click('[data-sb="aba:imagem"]'); await mi.fill("#miBusca", "Teste"); await mi.click("#miBtn"); await texto(mi, "#miRes", "Theo Menor Teste");
const res = await mi.textContent("#miRes");
check(res.includes("Sem autorização registrada"), "Mídia vê Theo sem autorização (revogada)");
await mi.fill("#miBusca", "Gabriel"); await mi.click("#miBtn"); await texto(mi, "#miRes", "Autoriza: fotos, voz");
check(true, "Mídia vê Gabriel autorizado só para fotos e voz");
await foto(mi, "12-midia-consulta", "#v-equipe");

for (const [n, p] of [["Secretaria", s], ["participante", g], ["menor (celular)", m], ["líder", l], ["Mídia", mi], ["público", pub]]) check(!p.erros.length, `sem erros de JavaScript (${n})`, p.erros.join(" | "));
await browser.close();
console.log(`\nResultado: ${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
