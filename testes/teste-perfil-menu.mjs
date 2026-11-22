// Teste das alterações de interface e acesso (rodapé, olho da senha, menu "Ir para",
// Área da Equipe no menu do site, menu do usuário, Meu perfil e Sair).
// Requer o servidor local (formato Render) rodando com o banco recém-instalado.
import { chromium } from "playwright-core";
import { createClient } from "@supabase/supabase-js";
import pg from "pg";
import fs from "node:fs";
import { prepararVoluntario } from "./apoio-termos.mjs";

const BASE = process.env.SUPABASE_URL, ANON = process.env.SUPABASE_ANON_KEY, SERV = process.env.SUPABASE_SERVICE_ROLE_KEY;
const SAIDA = process.env.SAIDA || "/tmp/telas-perfil";
fs.mkdirSync(SAIDA, { recursive: true });
const sql = async (q, v) => { const c = new pg.Client({ host: "/tmp", port: 5434, user: "postgres", database: "betel" }); await c.connect(); try { return (await c.query(q, v)).rows; } finally { await c.end(); } };
let ok = 0, falhas = 0;
const check = (c, n, x) => { if (c) { ok++; console.log("  ✓ " + n); } else { falhas++; console.log("  ✗ " + n + (x !== undefined ? "  → " + x : "")); } };

// ---------- preparação: um MASTER (primeiro acesso) e um LÍDER já ativo
const admin = createClient(BASE, SERV, { auth: { persistSession: false, autoRefreshToken: false } });
async function criar(nome, email, tel, perfil, mins, senha, ator = null) {
  const { data, error } = await admin.auth.admin.createUser({ email, password: senha, email_confirm: true, user_metadata: { nome } });
  if (error) throw error;
  const { error: e2 } = await admin.rpc("servico_criar_usuario", { p_ator: ator, p_usuario: data.user.id, p_nome: nome, p_telefone: tel, p_email: email, p_perfil: perfil, p_atribuicoes: [], p_ministerios: mins, p_solicitacao: null });
  if (e2) throw e2;
  return data.user.id;
}
const SENHA_M = "Temporaria-123", SENHA_L = "Lider-Teste-2026";
const uidM = await criar("Primeiro Master Teste", "master1@exemplo.com", "31900000001", "MASTER", [], SENHA_M);
const uidR = await criar("Segundo Master Teste", "master2@exemplo.com", "31900000002", "MASTER", [], "Ronald-Teste-2026");
await sql("update perfis set deve_trocar_senha = false, senha_alterada_em = now() where id = $1", [uidR]);
await prepararVoluntario("Lia Teste Líder", "lia.lider@teste.com", "31988880001");
const minJuv = (await sql("select id from ministerios where nome = 'Juventude Mergulhados'"))[0].id;
const uidL = await criar("Lia Teste Líder", "lia.lider@teste.com", "31988880001", "LIDER", [{ ministerio_id: minJuv, funcao: "lider" }], SENHA_L, uidR);
await sql("update perfis set deve_trocar_senha = false, senha_alterada_em = now() where id = $1", [uidL]);

// ---------- 1. Banco e API: Meu perfil, restrições e Sair
console.log("\n1. Banco e API");
const cli = () => createClient(BASE, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
const anon = cli();
check(!!(await anon.rpc("meu_perfil")).error, "visitante sem login não lê perfil");
const lia = cli();
const { data: ses } = await lia.auth.signInWithPassword({ email: "lia.lider@teste.com", password: SENHA_L });
const { data: perf, error: ep } = await lia.rpc("meu_perfil");
check(!ep && perf.nome === "Lia Teste Líder" && perf.email === "lia.lider@teste.com" && perf.perfil === "LIDER" && perf.ministerios[0]?.nome === "Juventude Mergulhados", "Meu perfil traz nome, e-mail, perfil e ministérios", JSON.stringify(ep || perf));
check(JSON.stringify(perf?.editaveis) === '["telefone","foto"]' && !!perf?.conta_criada_em, "informa o que pode ser editado (telefone e foto) e a data de cadastro");
check(!!(await lia.rpc("meu_perfil_atualizar", { p_telefone: "123" })).error, "telefone inválido é recusado");
const { data: perf2 } = await lia.rpc("meu_perfil_atualizar", { p_telefone: "(31) 97777-1234" });
check(perf2?.telefone === "31977771234", "próprio telefone atualizado", JSON.stringify(perf2));
check((await sql("select count(*)::int n from auditoria where tabela = 'pessoas' and acao = 'update' and depois->>'telefone' = '31977771234'"))[0].n === 1, "alteração do telefone registrada na auditoria");
await lia.from("perfis").update({ perfil: "MASTER", atribuicoes: ["SECRETARIA", "TESOURARIA"] }).eq("id", uidL);
const [pf] = await sql("select perfil, atribuicoes from perfis where id = $1", [uidL]);
check(pf.perfil === "LIDER" && pf.atribuicoes.length === 0, "usuário NÃO consegue mudar o próprio nível de acesso nem atribuições", JSON.stringify(pf));
await lia.from("pessoas").update({ nome: "Outro Nome" }).eq("email", "lia.lider@teste.com");
check((await sql("select nome from pessoas where email = 'lia.lider@teste.com'"))[0].nome === "Lia Teste Líder", "usuário não altera o próprio nome por fora da tela");
await lia.from("ministerio_membros").update({ funcao: "lider" }).eq("ministerio_id", minJuv);
const adm = await lia.rpc("admin_atualizar_usuario", { p_usuario: uidL, p_perfil: "MASTER", p_atribuicoes: [], p_ministerios: [] });
check(adm.error?.code === "42501" && (await sql("select perfil from perfis where id = $1", [uidL]))[0].perfil === "LIDER", "função de administração recusada para quem não é MASTER", JSON.stringify(adm.error));
const ex = await lia.rpc("meu_perfil_atualizar", { p_telefone: "31977771234", p_perfil: "MASTER" });
check(!!ex.error && (await sql("select perfil from perfis where id = $1", [uidL]))[0].perfil === "LIDER", "parâmetro extra (perfil) não é aceito pela função");
// Sair encerra a sessão no servidor
const token = ses.session.access_token, refresh = ses.session.refresh_token;
const r1 = await fetch(BASE + "/rest/v1/rpc/meu_perfil", { method: "POST", headers: { apikey: ANON, Authorization: "Bearer " + token, "Content-Type": "application/json" }, body: "{}" });
check(r1.ok, "token válido antes de sair");
await lia.auth.signOut({ scope: "local" });
const r2 = await fetch(BASE + "/rest/v1/rpc/meu_perfil", { method: "POST", headers: { apikey: ANON, Authorization: "Bearer " + token, "Content-Type": "application/json" }, body: "{}" });
check(!r2.ok, "depois de Sair, o mesmo token de acesso é recusado", r2.status);
const r3 = await fetch(BASE + "/auth/v1/token?grant_type=refresh_token", { method: "POST", headers: { apikey: ANON, "Content-Type": "application/json" }, body: JSON.stringify({ refresh_token: refresh }) });
check(!r3.ok, "depois de Sair, o token de renovação também não funciona", r3.status);
const outra = cli(); await outra.auth.signInWithPassword({ email: "lia.lider@teste.com", password: SENHA_L });
check(!(await outra.rpc("meu_perfil")).error, "um novo login funciona normalmente");
check((await sql("select count(*)::int n from auth.sessoes where sessao_id is null"))[0].n === 0, "toda sessão nova tem identificador (pode ser encerrada)");
await outra.auth.signOut({ scope: "local" });

// ---------- 2. Navegador
const browser = await chromium.launch({ executablePath: "/usr/bin/google-chrome", args: ["--no-sandbox"] });
async function pagina(mobile) {
  const ctx = await browser.newContext(mobile ? { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true } : { viewport: { width: 1360, height: 900 } });
  const p = await ctx.newPage();
  p.on("pageerror", (e) => { falhas++; console.log("  ✗ erro de JavaScript: " + e.message); });
  return p;
}
const foto = (p, n, sel) => (sel ? p.locator(sel).screenshot({ path: `${SAIDA}/${n}.png` }) : p.screenshot({ path: `${SAIDA}/${n}.png` }));
const semRolagemLateral = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
async function login(p, email, senha) {
  await p.goto(BASE + "/#equipe/entrar"); await p.waitForSelector("#sbLogin");
  await p.fill("#sbEmail", email); await p.fill("#sbSenha", senha); await p.click("#sbEntrar");
}

console.log("\n2. Rodapé e menu do site (computador)");
let p = await pagina();
await p.goto(BASE + "/#inicio"); await p.waitForSelector("footer .fcol");
const rotulos = await p.$$eval("footer .fcol .eyebrow", (e) => e.map((x) => x.textContent.trim()));
check(!rotulos.includes("Igreja") && !rotulos.includes("Servir"), "rodapé sem as seções Igreja e Servir/Área da equipe", rotulos.join(", "));
check(rotulos.join("|") === "Acompanhe|Endereço" && (await p.$$("footer .fcol")).length === 3, "rodapé mantém logo, Acompanhe e Endereço");
const fb = await p.$$eval("footer .fcol", (cs) => cs.map((c) => c.getBoundingClientRect()).map((r) => [Math.round(r.top), Math.round(r.left), Math.round(r.right)]));
check(fb.every((r) => r[0] === fb[0][0]) && fb[0][1] < 200 && fb[2][2] > 1100, "colunas do rodapé alinhadas e distribuídas na largura", JSON.stringify(fb));
check(await p.isVisible("#v-agenda >> text=Registre aqui se autoriza") || (await p.$$('a[href="#imagem"]')).length > 0, "a página de autorização de imagem continua acessível (link na Agenda)");
await foto(p, "01-rodape", "footer");
check(await p.isVisible('#nav a[href="#equipe"]') && (await p.textContent("#navEquipe")).includes("Área de Membros"), "menu principal mostra Área da equipe para qualquer visitante");
await foto(p, "02-cabecalho-visitante", "header");
await p.click("#navEquipe"); await p.waitForSelector('[data-sb="ir:entrar"]');
check(p.url().endsWith("#equipe") && await p.isVisible('[data-sb="ir:solicitar"]'), "sem login, leva à entrada da Área da Equipe com Fazer login e Solicitar acesso");
check(await p.isHidden("#cpUsuario"), "sem login, não aparece identificação de usuário");

console.log("\n3. Olho da senha");
await p.click('[data-sb="ir:entrar"]'); await p.waitForSelector("#sbSenha");
const olho = p.locator("#sbLogin .cp-olho");
check(await olho.count() === 1 && (await p.getAttribute("#sbSenha", "type")) === "password", "campo de senha começa oculto, com o botão de olho");
await p.fill("#sbSenha", "abc123xyz"); await olho.click();
check((await p.getAttribute("#sbSenha", "type")) === "text" && (await olho.getAttribute("aria-pressed")) === "true" && (await olho.getAttribute("aria-label")) === "Ocultar senha", "1º clique mostra a senha");
check((await p.inputValue("#sbSenha")) === "abc123xyz", "o valor digitado não muda ao mostrar");
await foto(p, "03-senha-visivel", "#sbLogin");
await olho.click();
check((await p.getAttribute("#sbSenha", "type")) === "password" && (await olho.getAttribute("aria-label")) === "Mostrar senha", "2º clique volta a ocultar");

const ag = await pagina(); await ag.goto(BASE + "/agenda-ministerial/"); await ag.waitForFunction(() => document.querySelectorAll(".cp-olho").length >= 4, null, { timeout: 15000 }).catch(() => {});
check(await ag.$$eval('input[type=password]', (i) => i.length > 0 && i.every((x) => x.parentElement.querySelector(".cp-olho"))), "Agenda Ministerial: olho em todos os campos de senha (login, senha atual, nova e confirmação)");
await ag.evaluate(() => { document.getElementById("modal-alterar-senha").classList.remove("hidden"); });
await ag.fill("#nova-senha-coord", "Teste-1234"); await ag.click('#modal-alterar-senha .cp-olho >> nth=1');
check((await ag.getAttribute("#nova-senha-coord", "type")) === "text", "Agenda: o olho mostra a nova senha");
await ag.locator("#modal-alterar-senha").screenshot({ path: `${SAIDA}/10-agenda-senha.png` });
await ag.close();

console.log("\n4. Primeiro acesso (criar senha) e troca de senha");
await login(p, "master1@exemplo.com", SENHA_M); await p.waitForSelector("#sbNovaSenha");
check(await p.locator("#sbNovaSenha .cp-olho").count() === 2, "criar senha (primeiro acesso / recuperação): olho nos dois campos");
await p.fill("#nsSenha", "MinhaSenha-2026"); await p.locator("#sbNovaSenha .cp-olho").first().click();
check((await p.getAttribute("#nsSenha", "type")) === "text" && (await p.getAttribute("#nsConf", "type")) === "password", "cada campo mostra/oculta de forma independente");
await p.fill("#nsConf", "MinhaSenha-2026"); await p.click("#nsSalvar"); await p.waitForSelector("#sbPainel:not([hidden])");
check(true, "senha criada com o olho ligado (o formulário envia normalmente)");
check(await p.isVisible("#cpUsuario") && (await p.textContent("#cpUsuario .cp-avatar")).trim() === "ER", "depois do login, o cabeçalho mostra a identificação (iniciais ER)");
await p.click('[data-sb="aba:conta"]'); await p.waitForSelector("#sbTrocar");
check(await p.locator("#sbTrocar .cp-olho").count() === 3, "trocar senha: olho na senha atual, na nova e na confirmação");
await p.fill("#tcAtual", "MinhaSenha-2026"); await p.fill("#tcNova", "OutraSenha-2026"); await p.fill("#tcConf", "OutraSenha-2026"); await p.click("#tcSalvar");
await p.waitForFunction(() => document.querySelector("#tcMsg").textContent.includes("Senha alterada"));
check(true, "troca de senha funciona com o novo campo");
check((await p.getAttribute("#tcNova", "type")) === "password", "depois de enviar, as senhas voltam a ficar ocultas");
const hashOk = (await sql("select encrypted_password from auth.users where email = 'master1@exemplo.com'"))[0].encrypted_password;
check(/^\$2[aby]\$/.test(hashOk) && !hashOk.includes("OutraSenha"), "senha continua guardada só como hash (bcrypt)");
await p.goto(BASE + "/#inicio"); await p.waitForSelector("footer");
check(await p.isVisible("#cpUsuario"), "identificação continua visível fora da Área da Equipe");
await p.click("#navEquipe"); await p.waitForSelector("#sbPainel:not([hidden])");
check(p.url().endsWith("#equipe"), "logado, Área da equipe leva direto ao painel interno do perfil");
await p.click('#sbBarra [data-sb="sair"]');
await p.waitForSelector('[data-sb="ir:entrar"]');

console.log("\n5. Menu do usuário, Meu perfil e Sair (líder, computador)");
await login(p, "lia.lider@teste.com", SENHA_L); await p.waitForSelector("#sbPainel:not([hidden])");
await p.waitForFunction(() => document.querySelector("#cpUsuario .cp-usuario-nome")?.textContent === "Lia");
check(true, "cabeçalho mostra o primeiro nome (Lia)");
await p.click("#cpUsuarioBotao");
check(await p.isVisible("#cpUsuarioMenu") && (await p.textContent("#cpUsuarioMenu")).includes("Meu perfil") && (await p.textContent("#cpUsuarioMenu")).includes("Sair"), "menu do usuário com Meu perfil e Sair");
check((await p.textContent("#cpUsuarioMenu .cp-usuario-cab")).includes("Conectado · Líder"), "menu indica que está conectado e o perfil");
await foto(p, "04-menu-usuario", "header");
await p.mouse.click(700, 600);
check(await p.isHidden("#cpUsuarioMenu"), "clicar fora fecha o menu do usuário");
await p.click("#cpUsuarioBotao"); await p.keyboard.press("Escape");
check(await p.isHidden("#cpUsuarioMenu"), "Esc fecha o menu do usuário");
await p.click("#cpUsuarioBotao"); await p.click('#cpUsuarioMenu a[href="#equipe/conta"]');
await p.waitForSelector("#sbMeuTel");
check(await p.isHidden("#cpUsuarioMenu"), "o menu fecha ao escolher Meu perfil");
const txt = await p.textContent("#sbConteudo");
check(txt.includes("Lia Teste Líder") && txt.includes("lia.lider@teste.com") && txt.includes("(31) 97777-1234") && txt.includes("Juventude Mergulhados") && txt.includes("Líder") && txt.includes("Conta criada em"), "Meu perfil mostra nome, e-mail, telefone, ministério, função e cadastro");
check((await p.$$("#sbConteudo input:not([type=password]):not([type=file]):not([type=range]):not([type=checkbox])")).length === 1 && (await p.$$("#sbMinhaFoto #mpArquivo")).length === 1, "só o telefone e a foto são editáveis na tela (além das senhas)");
await p.fill("#mpTel", "31 96666-5555"); await p.click("#mpSalvar");
await p.waitForFunction(() => document.querySelector("#mpMsg").textContent.includes("Telefone atualizado"));
check((await sql("select telefone from pessoas where email = 'lia.lider@teste.com'"))[0].telefone === "31966665555", "telefone salvo no banco pela tela");
await foto(p, "05-meu-perfil", "#v-equipe");
check(!(await p.$('[data-sb="aba:usuarios"]')), "líder não vê a aba de usuários (administração)");
// Sair pelo menu do usuário
await p.click("#cpUsuarioBotao"); await p.click('#cpUsuarioMenu [data-sb="sair"]');
await p.waitForSelector('[data-sb="ir:entrar"]');
check(p.url().endsWith("#equipe") && await p.isHidden("#cpUsuario"), "Sair: encerra e volta para a entrada da Área da Equipe, sem identificação");
check((await p.evaluate(() => localStorage.getItem("betel-equipe"))) === null, "Sair limpa os dados de login do navegador");
check((await p.textContent("#sbConteudo")).trim() === "" && (await p.innerHTML("#sbAbas")).trim() === "", "a tela interna é apagada da página");
await p.goBack(); await p.waitForTimeout(600);
check(!(await p.textContent("#v-equipe")).includes("97777") && !(await p.textContent("#v-equipe")).includes("96666") && await p.isVisible('[data-sb="ir:entrar"]'), "botão Voltar do navegador não mostra de novo os dados internos", p.url());
await p.goto(BASE + "/#equipe/conta"); await p.waitForSelector('[data-sb="ir:entrar"]');
check(p.url().endsWith("#equipe"), "abrir uma página interna depois de sair pede login de novo");
await p.reload(); await p.waitForSelector('[data-sb="ir:entrar"]');
check(await p.isHidden("#cpUsuario"), "recarregar a página continua desconectado");
// Sair a partir de uma página pública
await login(p, "lia.lider@teste.com", SENHA_L); await p.waitForSelector("#sbPainel:not([hidden])");
await p.goto(BASE + "/#agenda"); await p.waitForSelector("#cpUsuarioBotao");
await p.click("#cpUsuarioBotao"); await p.click('#cpUsuarioMenu [data-sb="sair"]');
await p.waitForFunction(() => document.getElementById("cpUsuario").hidden);
check(p.url().endsWith("#agenda"), "Sair numa página pública continua nela, já desconectado");
await p.waitForSelector(".cp-toast.on"); check((await p.textContent(".cp-toast")).includes("saiu"), "aviso de saída no padrão do site");

console.log("\n6. Celular: menu \"Ir para\", olho da senha e cabeçalho");
const m = await pagina(true);
await m.goto(BASE + "/#equipe/entrar"); await m.waitForSelector("#sbSenha");
await m.fill("#sbSenha", "xyz"); await m.tap("#sbLogin .cp-olho");
check((await m.getAttribute("#sbSenha", "type")) === "text", "no celular, tocar no olho mostra a senha");
await m.tap("#sbLogin .cp-olho"); check((await m.getAttribute("#sbSenha", "type")) === "password", "tocar de novo oculta");
await m.fill("#sbEmail", "master1@exemplo.com"); await m.fill("#sbSenha", "OutraSenha-2026"); await m.tap("#sbEntrar");
await m.waitForSelector("#sbIrBotao");
check(await m.isVisible("#sbIrBotao") && await m.isHidden("#sbAbas"), "no celular aparece o botão Ir para (abas escondidas)");
check((await m.textContent("#sbIrBotao")).includes("Painel"), "o botão mostra onde a pessoa está (Painel)");
check(await m.isVisible("#cpUsuarioBotao") && await m.isHidden(".cp-usuario-nome"), "no celular o cabeçalho mostra só o avatar");
check(await semRolagemLateral(m), "sem rolagem lateral no celular (painel)");
await foto(m, "06-celular-painel");
await m.tap("#sbIrBotao"); await m.waitForSelector("#sbIrPainel.on");
const grupos = await m.$$eval("#sbIrPainel .cp-ir-grupo .eyebrow", (g) => g.map((x) => x.textContent));
check(grupos[0] === "Geral" && grupos.includes("Administração") && grupos.includes("Conta"), "destinos organizados em grupos", grupos.join(", "));
check(await m.$$eval("#sbIrPainel .cp-ir-item", (it) => it.every((i) => i.querySelector("svg"))), "cada destino tem ícone");
check(await m.getAttribute('#sbIrPainel [data-sb="irAba:painel"]', "aria-current") === "page", "o destino atual fica destacado");
check(await m.isVisible('#sbIrPainel [data-sb="irFechar"]') && await m.isVisible('#sbIrPainel [data-sb="sair"]'), "o menu tem botão de fechar e Sair");
check(await m.evaluate(() => document.body.classList.contains("cp-travado")), "a página de fundo não rola com o menu aberto");
await foto(m, "07-celular-ir-para");
await m.tap('#sbIrPainel [data-sb="irFechar"]'); await m.waitForSelector("#sbIrPainel", { state: "hidden" });
check(await m.getAttribute("#sbIrBotao", "aria-expanded") === "false" && !(await m.evaluate(() => document.body.classList.contains("cp-travado"))), "botão X fecha o menu");
await m.tap("#sbIrBotao"); await m.waitForSelector("#sbIrPainel.on");
await m.mouse.click(195, 40); await m.waitForSelector("#sbIrPainel", { state: "hidden" });
check(true, "tocar fora (no fundo escuro) fecha o menu");
await m.tap("#sbIrBotao"); await m.waitForSelector("#sbIrPainel.on"); await m.keyboard.press("Escape"); await m.waitForSelector("#sbIrPainel", { state: "hidden" });
check(true, "Esc fecha o menu");
await m.tap("#sbIrBotao"); await m.waitForSelector("#sbIrPainel.on");
await m.tap('#sbIrPainel [data-sb="irAba:usuarios"]'); await m.waitForURL(/#equipe\/usuarios/);
await m.waitForSelector("#sbIrPainel", { state: "hidden" });
check((await m.textContent("#sbIrBotao")).includes("Usuários"), "escolher um destino navega e fecha o menu sozinho");
for (const k of ["agenda", "conta", "historico", "painel"]) {
  await m.tap("#sbIrBotao"); await m.waitForSelector("#sbIrPainel.on"); await m.tap(`#sbIrPainel [data-sb="irAba:${k}"]`);
  await m.waitForSelector("#sbIrPainel", { state: "hidden" }); await m.waitForTimeout(500);
}
check(m.url().endsWith("#equipe") && await semRolagemLateral(m), "navegação seguida pelo menu, sem rolagem lateral");
await m.tap("#sbIrBotao"); await m.waitForSelector("#sbIrPainel.on"); await m.tap('#sbIrPainel [data-sb="sair"]');
await m.waitForSelector('[data-sb="ir:entrar"]');
check(await m.isHidden("#cpUsuario") && !(await m.$("#sbIrPainel")) && !(await m.evaluate(() => document.body.classList.contains("cp-travado"))), "Sair pelo menu Ir para encerra a sessão e remove o menu");
await m.goto(BASE + "/#inicio"); await m.waitForSelector("footer");
check(await semRolagemLateral(m), "Home sem rolagem lateral no celular");
await m.tap("#menuBtn"); check(await m.isVisible("#navEquipe"), "no celular, Área da equipe aparece no menu do site");
await foto(m, "08-celular-menu-site");
await m.tap("#navEquipe"); await m.waitForSelector('[data-sb="ir:entrar"]');
check(true, "tocar em Área da equipe abre a entrada da equipe");
await m.goto(BASE + "/#inicio"); await m.locator("footer").scrollIntoViewIfNeeded(); await foto(m, "09-celular-rodape", "footer");

await browser.close();
console.log(`\nResultado: ${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
