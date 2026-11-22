// Etapa 3 — Cursos: fluxo completo nas telas (Secretaria, site público, participante), com capturas.
import { chromium } from "playwright-core";
import { createClient } from "@supabase/supabase-js";
import { execFileSync, execSync } from "node:child_process";
import fs from "node:fs";
import { publicarTermos } from "./apoio-termos.mjs";

const BASE = process.env.SUPABASE_URL, SAIDA = process.env.SAIDA || "/tmp/cursos-telas";
fs.mkdirSync(SAIDA, { recursive: true });
let ok = 0, falhas = 0;
const check = (c, n, x) => { if (c) { ok++; console.log("  ✓ " + n); } else { falhas++; console.log("  ✗ " + n + (x !== undefined ? "  → " + String(x).slice(0, 300) : "")); } };

// contas: MASTER (script) e Secretaria (criada pelo MASTER)
const saida = execFileSync("node", ["../scripts/criar-primeiros-masters.mjs", "Primeiro Master Teste|master1@exemplo.com|31900000001"], { env: process.env }).toString();
const api = createClient(BASE, process.env.SUPABASE_ANON_KEY, { auth: { persistSession: false } });
await api.auth.signInWithPassword({ email: "master1@exemplo.com", password: saida.match(/senha temporária: (\S+)/)[1] });
await api.auth.updateUser({ password: "Ezequiel-Nova-2026" });
const sec = (await api.from("ministerios").select("id,nome")).data.find((m) => m.nome === "Secretaria").id;
const e = (await api.functions.invoke("admin-usuarios", { body: { acao: "criar", nome: "Elaine Secretaria Teste", telefone: "31992997440", email: "elaine@teste.com", perfil: "LIDER", atribuicoes: ["SECRETARIA"], ministerios: [{ ministerio_id: sec, funcao: "lider" }] } })).data;
const l = (await api.functions.invoke("admin-usuarios", { body: { acao: "criar", nome: "Lia Líder Teste", telefone: "31988880001", email: "lia@teste.com", perfil: "LIDER", atribuicoes: [], ministerios: [{ ministerio_id: sec, funcao: "lider" }] } })).data;
execSync(`python3 -c "from PIL import Image; i=Image.open('../frontend/site/img/jovem-biblia.jpg'); i.thumbnail((1200,1200)); i.save('/tmp/capa-curso.jpg', quality=82)"`);

const browser = await chromium.launch({ executablePath: "/usr/bin/google-chrome", args: ["--no-sandbox"] });
const nova = async (mobile) => { const ctx = await browser.newContext(mobile ? { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true } : { viewport: { width: 1360, height: 900 }, acceptDownloads: true });
  const p = await ctx.newPage(); p.erros = []; p.on("pageerror", (x) => p.erros.push(x.message)); return p; };
const foto = (p, n, sel) => (sel ? p.locator(sel).screenshot({ path: `${SAIDA}/${n}.png` }) : p.screenshot({ path: `${SAIDA}/${n}.png`, fullPage: true }));
const texto = (p, sel, t) => p.waitForFunction(([s, t]) => document.querySelector(s)?.textContent.includes(t), [sel, t], { timeout: 10000 });
async function entrarEquipe(p, email, temp, nova) {
  await p.goto(BASE + "/#equipe/entrar"); await p.waitForSelector("#sbLogin"); await p.fill("#sbEmail", email); await p.fill("#sbSenha", temp); await p.click("#sbEntrar");
  await p.waitForSelector("#sbNovaSenha"); await p.fill("#nsSenha", nova); await p.fill("#nsConf", nova); await p.click("#nsSalvar"); await p.waitForSelector("#sbPainel:not([hidden])");
}

console.log("\n1. Site antes da publicação");
let pub = await nova();
await pub.goto(BASE + "/#cursos"); await texto(pub, "#cuLista", "em breve");
check(await pub.locator('#nav a[href="#cursos"]').count() === 1, "menu do site tem o link Cursos");
check(true, "sem cursos publicados, a página avisa que serão divulgados em breve");

console.log("\n2. Secretaria: cadastro, imagem, publicação e turma");
const s = await nova();
await entrarEquipe(s, "elaine@teste.com", e.senha_temporaria, "Elaine-Nova-2026");
const abas = await s.$$eval("#sbAbas button", (b) => b.map((x) => x.textContent.trim()));
check(abas.includes("Cursos"), "aba Cursos aparece para quem tem a atribuição Secretaria", abas.join("|"));
await s.click('[data-sb="aba:cursos"]'); await texto(s, "#sbConteudo", "Curso de Batismo");
check((await s.locator("#sbConteudo .row .st", { hasText: "Rascunho" }).count()) === 7, "os 7 cursos aparecem como rascunho");
await foto(s, "01-painel-cursos", "#v-equipe");
await s.locator(".row", { hasText: "Curso de Batismo" }).locator('[data-cu^="curso:"]').click(); await s.waitForSelector("#cuFormCurso");
await s.fill('#cuFormCurso [name="resumo"]', "Preparação para o batismo (texto de teste).");
await s.fill('#cuFormCurso [name="descricao"]', "Descrição de teste preenchida pela Secretaria.\nSegunda linha.");
await s.setInputFiles("#cuArquivo", "/tmp/capa-curso.jpg"); await texto(s, "#cuFormCurso .msg", "Imagem enviada");
check((await s.getAttribute("#cuPrevia", "src")).includes("/storage/v1/object/public/cursos/"), "imagem enviada ao Storage e prévia exibida");
await s.check('#cuFormCurso [name="publicado"]'); await s.click('#cuFormCurso [type="submit"]'); await texto(s, "#cuFormCurso .msg", "Curso salvo");
check(true, "curso salvo e publicado");
await foto(s, "02-editar-curso", "#v-equipe");
await s.click('#cuFormCurso [data-cu^="turmas:"]'); await s.click('[data-cu^="turma:"]'); await s.waitForSelector("#cuFormTurma");
await s.selectOption('#cuFormTurma [name="status"]', "inscricoes_abertas"); await s.fill('#cuFormTurma [name="vagas"]', "2");
await s.click('#cuFormTurma [type="submit"]'); await texto(s, "#sbConteudo", "2 vagas ocupadas".replace("2 vagas", "0 de 2 vagas"));
check(true, "turma criada com 2 vagas, inscrições abertas (datas, local, professores e valor em branco)");
const lider = await nova(); await entrarEquipe(lider, "lia@teste.com", l.senha_temporaria, "Lia-Nova-20261");
check(!(await lider.$$eval("#sbAbas button", (b) => b.map((x) => x.textContent.trim()))).includes("Cursos"), "líder sem atribuição não vê a aba Cursos");
await lider.context().close();

await publicarTermos(); // termos-modelo publicados (Etapa 5)
console.log("\n3. Site público: cards, página do curso e inscrições");
await pub.goto(BASE + "/#inicio"); await pub.goto(BASE + "/#cursos"); await pub.waitForSelector(".cuCard");
check(await pub.locator(".cuCard").count() === 1 && (await pub.textContent(".cuCard")).includes("Inscrições abertas"), "card do curso publicado, com a situação da inscrição");
check(await pub.locator(".cuCard img.cuImg").count() === 1, "card com a imagem enviada");
await foto(pub, "03-pagina-publica-cursos", "#v-cursos");
await pub.click(".cuCard"); await pub.waitForSelector(".cuForm");
check((await pub.textContent("#cuPagina")).includes("Segunda linha") && !(await pub.textContent("#cuPagina")).includes("Professores"), "página individual mostra o que foi preenchido e omite campos vazios");
async function inscrever(p, nome, tel, email) {
  await p.goto(BASE + "/#cursos"); await p.goto(BASE + "/#curso/batismo"); await p.waitForSelector(".cuForm");
  await p.fill('.cuForm [name="nome"]', nome); await p.fill('.cuForm [name="telefone"]', tel); await p.fill('.cuForm [name="email"]', email);
  await p.fill('.cuForm [name="nascimento"]', "1990-05-10"); await p.waitForSelector('.cuForm [name="termo_participacao"]');
  await p.check('.cuForm [name="aceite"]'); await p.check('.cuForm [name="termo_participacao"]'); await p.click('.cuForm [type="submit"]');
}
await inscrever(pub, "Ana Participante", "(31) 91111-0001", "ana@teste.com"); await pub.waitForSelector(".done");
check((await pub.textContent(".done")).includes("confirmada"), "1ª inscrição confirmada na tela");
await foto(pub, "04-inscricao-confirmada", "#v-curso");
const linkAna = await pub.getAttribute(".done a", "href");
await inscrever(pub, "Ana Participante", "(31) 91111-0001", "ana@teste.com"); await texto(pub, ".cuForm .msg", "Já existe");
check(true, "tentar se inscrever de novo mostra o aviso de inscrição duplicada");
await inscrever(pub, "Bruno Participante", "31 91111-0002", "bruno@teste.com"); await pub.waitForSelector(".done");
await pub.goto(BASE + "/#cursos"); await pub.goto(BASE + "/#curso/batismo"); await pub.waitForSelector(".cuForm");
check((await pub.textContent(".cuForm h3")).includes("lista de espera") && (await pub.textContent("#cuPagina")).includes("Esgotadas"), "sem vagas, o formulário vira 'Entrar na lista de espera'");
await inscrever(pub, "Carla Participante", "31 91111-0003", "carla@teste.com"); await pub.waitForSelector(".done");
check((await pub.textContent(".done")).includes("posição 1"), "3ª pessoa entra na lista de espera (posição 1)");
const linkCarla = await pub.getAttribute(".done a", "href");
await foto(pub, "05-lista-de-espera", "#v-curso");

console.log("\n4. Link pessoal");
await pub.goto(linkCarla); await texto(pub, "#cuMinha", "Lista de espera");
check((await pub.textContent("#cuMinha")).includes("número 1"), "link pessoal mostra a posição na espera");
await pub.goto(linkAna); await texto(pub, "#cuMinha", "Inscrição confirmada");
await pub.click("#cuCancelar"); await pub.click("#cuCancelar"); await texto(pub, "#cuMinha", "Cancelada");
check(true, "participante cancela a própria inscrição (com confirmação)");
await pub.goto(BASE + "/#cursos"); await pub.goto(linkCarla); await texto(pub, "#cuMinha", "Inscrição confirmada");
check(true, "a vaga liberada vai automaticamente para quem estava na espera");
await foto(pub, "06-minha-inscricao", "#v-inscricao-curso");

console.log("\n5. Secretaria: inscrições, participantes e histórico");
await s.click('[data-cu="tela:cursos"]'); await s.locator(".row", { hasText: "Curso de Batismo" }).locator('[data-cu^="turmas:"]').click();
await s.click('[data-cu^="inscricoes:"]'); await texto(s, "#sbConteudo", "Carla Participante");
check((await s.textContent("#sbConteudo")).includes("2 confirmada(s)") && (await s.textContent("#sbConteudo")).includes("1 cancelada(s)"), "lista da turma com os totais por situação");
await s.click('[data-cu="novaInscricao"]'); await s.fill('#cuFormInsc [name="nome"]', "Davi Pela Secretaria"); await s.fill('#cuFormInsc [name="telefone"]', "31911110004");
await s.fill('#cuFormInsc [name="email"]', "davi@teste.com"); await s.fill('#cuFormInsc [name="nascimento"]', "1988-02-02"); await s.check('#cuFormInsc [name="aceite"]'); await s.check('#cuFormInsc [name="presencial"]'); await s.click('#cuFormInsc [type="submit"]');
await texto(s, "#sbConteudo", "Lista de espera");
check((await s.textContent("#sbConteudo")).includes("pela Secretaria"), "inscrição feita pela Secretaria vai para a espera (vagas cheias)");
await s.locator(".sbItem", { hasText: "Bruno Participante" }).locator('[data-cu^="cancelarForm:"]').click();
await s.fill('[data-cancelar] input', "Pediu para sair"); await s.click('[data-cancelar] [type="submit"]');
await texto(s, "#sbConteudo", "motivo: Pediu para sair");
check((await s.locator(".sbItem", { hasText: "Davi Pela Secretaria" }).textContent()).includes("Confirmada"), "cancelamento com motivo e promoção automática da espera");
await s.locator(".sbItem", { hasText: "Carla Participante" }).locator('[data-cu^="acao:concluir"]').click();
await s.locator(".sbItem", { hasText: "Carla Participante" }).locator(".st", { hasText: "Concluída" }).waitFor();
check(true, "Secretaria marca a conclusão do curso");
const [down] = await Promise.all([s.waitForEvent("download"), s.click('[data-cu^="csv:"]')]);
const csv = fs.readFileSync(await down.path(), "utf8");
check(csv.includes("Carla Participante") && csv.split("\r\n").length === 5, "lista da turma em planilha (CSV)");
await foto(s, "07-inscricoes-turma", "#v-equipe");
await s.locator(".sbItem", { hasText: "Carla Participante" }).locator('[data-cu^="participante:"]').click(); await s.waitForSelector("#cuFormPessoa");
const hist = await s.textContent("#sbConteudo");
check(hist.includes("Lista de espera → Confirmada") && hist.includes("Confirmada → Concluída"), "histórico de inscrições mostra cada mudança de situação");
await foto(s, "08-historico-participante", "#v-equipe");

console.log("\n6. Celular");
const m = await nova(true);
await m.goto(BASE + "/#cursos"); await m.waitForSelector(".cuCard"); await foto(m, "09-celular-cursos");
await m.goto(BASE + "/#curso/batismo"); await m.waitForSelector(".cuTurma"); await foto(m, "10-celular-curso");
check(true, "páginas de cursos no celular");

for (const [n, p] of [["site", pub], ["secretaria", s], ["celular", m]]) check(p.erros.length === 0, `sem erros de JavaScript (${n})`, p.erros.join(" | "));
await browser.close();
console.log(`\nResultado: ${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
