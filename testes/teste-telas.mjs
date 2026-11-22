// Teste das telas da Área da Equipe no navegador (três perfis), com capturas de tela.
// Requer o ambiente local (dev-supabase) rodando e as contas MASTER criadas pelo script.
import { chromium } from "playwright-core";
import fs from "node:fs";
import { prepararVoluntario } from "./apoio-termos.mjs";

const BASE = process.env.SUPABASE_URL;
const SAIDA = process.env.SAIDA || "/tmp/telas";
fs.mkdirSync(SAIDA, { recursive: true });
const temp = JSON.parse(fs.readFileSync("/tmp/masters.json", "utf8"));
// A partir da M07, só é voluntário quem tem a membresia validada e o Novos Membros concluído.
for (const [n, e, t] of [["Lia Teste Líder", "lia.lider@teste.com", "31988880001"], ["Vitor Teste Voluntário", "vitor.vol@teste.com", "31988880002"], ["Rui Teste Recusado", "rui@teste.com", "31988880003"], ["Segundo Master Teste", "master2@exemplo.com", "31900000002"]]) await prepararVoluntario(n, e, t);
let ok = 0, falhas = 0;
const check = (c, n, x) => { if (c) { ok++; console.log("  ✓ " + n); } else { falhas++; console.log("  ✗ " + n + (x ? "  → " + x : "")); } };

const browser = await chromium.launch({ executablePath: "/usr/bin/google-chrome", args: ["--no-sandbox"] });
async function pagina(mobile) {
  const ctx = await browser.newContext(mobile ? { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true } : { viewport: { width: 1360, height: 900 } });
  const p = await ctx.newPage();
  p.on("pageerror", (e) => { falhas++; console.log("  ✗ erro de JavaScript: " + e.message); });
  return p;
}
const foto = (p, n) => p.locator("#v-equipe").screenshot({ path: `${SAIDA}/${n}.png` });
const esperar = (p, t) => p.waitForFunction((t) => document.querySelector("#v-equipe").textContent.includes(t), t, { timeout: 8000 });
async function login(p, email, senha) {
  await p.goto(BASE + "/#equipe/entrar");
  try { await p.waitForSelector("#sbLogin", { timeout: 8000 }); }
  catch (e) { console.log("DEBUG", p.url(), JSON.stringify((await p.textContent("#sbTela")).slice(0, 200)), await p.evaluate(() => document.querySelector("#v-equipe").className)); await foto(p, "erro-login"); throw e; }
  await p.fill("#sbEmail", email); await p.fill("#sbSenha", senha); await p.click("#sbEntrar");
}
async function trocarSenha(p, nova) {
  await p.waitForSelector("#sbNovaSenha"); await p.fill("#nsSenha", nova); await p.fill("#nsConf", nova); await p.click("#nsSalvar");
  await p.waitForSelector("#sbPainel:not([hidden])");
}
async function sair(p) { await p.click('#sbBarra [data-sb="sair"]'); await p.waitForSelector('[data-sb="ir:entrar"]'); }

console.log("\n1. Telas públicas");
let p = await pagina();
await p.goto(BASE + "/#equipe"); await p.waitForSelector('[data-sb="ir:solicitar"]');
check(await p.isVisible('[data-sb="ir:entrar"]') && await p.isVisible('[data-sb="ir:solicitar"]'), "tela inicial com as duas opções: Fazer login e Solicitar acesso");
await foto(p, "01-inicio");
await p.goto(BASE + "/#equipe/usuarios"); await p.waitForSelector('[data-sb="ir:solicitar"]');
check(p.url().endsWith("#equipe"), "rota interna sem login volta para a tela inicial (rota protegida)", p.url());
for (const [nome, tel, email, min, fun] of [["Lia Teste Líder", "(31) 98888-0001", "lia.lider@teste.com", "Juventude Mergulhados", "lider"], ["Vitor Teste Voluntário", "31 98888-0002", "vitor.vol@teste.com", "Juventude Mergulhados", "voluntario"]]) {
  await p.goto(BASE + "/#equipe"); await p.goto(BASE + "/#equipe/solicitar"); await p.waitForSelector("#soMin option:nth-child(2)", { state: "attached" });
  await p.fill("#soNome", nome); await p.fill("#soTel", tel); await p.fill("#soEmail", email);
  await p.selectOption("#soMin", { label: min }); await p.check(`input[name="soFuncao"][value="${fun}"]`);
  if (fun === "lider") await foto(p, "02-solicitar-acesso");
  await p.click("#soEnviar"); await esperar(p, "Solicitação recebida");
}
check(true, "duas solicitações enviadas pela tela");
await foto(p, "03-solicitacao-enviada");
await p.goto(BASE + "/#equipe"); await p.goto(BASE + "/#equipe/solicitar"); await p.waitForSelector("#soEnviar");
await p.fill("#soNome", "Fulano"); await p.click("#soEnviar");
check((await p.textContent("#soMsg")).includes("nome completo"), "valida o nome completo na tela");

console.log("\n2. MASTER");
await login(p, "master1@exemplo.com", "senha-errada-123");
await p.waitForFunction(() => document.querySelector("#sbMsg").textContent.includes("incorretos"));
check(true, "senha errada: mensagem clara, sem entrar");
await p.fill("#sbSenha", temp.ezequiel); await p.click("#sbEntrar");
await p.waitForSelector("#sbNovaSenha");
check(true, "primeiro acesso leva à troca obrigatória de senha");
await foto(p, "04-primeiro-acesso");
await p.fill("#nsSenha", temp.ezequiel); await p.fill("#nsConf", temp.ezequiel); await p.click("#nsSalvar");
await p.waitForFunction(() => /diferente/.test(document.querySelector("#nsMsg").textContent));
check(true, "não aceita repetir a senha temporária");
await trocarSenha(p, "Ezequiel-Nova-2026");
const abasM = await p.$$eval("#sbAbas button", (b) => b.map((x) => x.textContent.trim()));
check(abasM.join("|").startsWith("Painel|Agenda Ministerial|Formulários da Agenda|Cursos|Secretaria|Membresia|Ministérios|Organogramas|Candidatos|Turmas|Mídia|Solicitar mídia|Minhas escalas|Avisos|Solicitações") && abasM.includes("Conteúdo do site") && abasM.includes("Usuários") && abasM.includes("Ministérios") && abasM.includes("Histórico"), "MASTER vê todas as abas administrativas", abasM.join("|"));
await foto(p, "05-painel-master");
await p.click('[data-sb="aba:solicitacoes"]'); await p.waitForSelector('[data-sb^="aprovarForm:"]');
await foto(p, "06-solicitacoes");
const senhas = {};
for (const nome of ["Lia Teste Líder", "Vitor Teste Voluntário"]) {
  const item = p.locator(".sbItem", { hasText: nome });
  await item.locator('[data-sb^="aprovarForm:"]').click();
  await item.locator('form [type="submit"]').click();
  await item.locator(".sbSenhaTemp").waitFor();
  senhas[nome] = (await item.locator(".sbSenhaTemp").textContent()).trim();
  if (nome.startsWith("Lia")) await foto(p, "07-acesso-aprovado");
}
check(Object.values(senhas).every((s) => /^\w{4}-\w{4}-\w{4}$/.test(s)), "aprovação mostra a senha temporária uma única vez");
await p.click('[data-sb="aba:usuarios"]'); await p.waitForSelector("#usr-" + "", { state: "attached" }).catch(() => {});
await esperar(p, "Lia Teste Líder");
await foto(p, "08-usuarios");
await p.click('[data-sb="aba:ministerios"]'); await p.waitForSelector("#sbFormMin");
await p.fill("#fmNome", "Teatro"); await p.fill("#fmDesc", "Ministério de artes cênicas"); await p.click('#sbFormMin [type="submit"]');
await esperar(p, "Ministério salvo");
check(await p.locator(".row", { hasText: "Teatro" }).count() === 1, "cria ministério pela tela");
await foto(p, "09-ministerios");
await p.click('[data-sb="aba:historico"]'); await esperar(p, "Aprovou a solicitação");
check(true, "histórico mostra as aprovações");
await foto(p, "10-historico");
await sair(p);
check(!(await p.evaluate(() => Object.keys(localStorage).some((k) => k.includes("betel-equipe") && localStorage.getItem(k)))), "sair apaga a sessão do navegador");
await p.goto(BASE + "/#equipe/historico"); await p.waitForSelector('[data-sb="ir:solicitar"]');
check(p.url().endsWith("#equipe"), "depois de sair, o histórico não abre mais");

console.log("\n3. LÍDER");
await login(p, "lia.lider@teste.com", senhas["Lia Teste Líder"]); await trocarSenha(p, "Lia-Senha-Nova-01");
const abasL = await p.$$eval("#sbAbas button", (b) => b.map((x) => x.textContent.trim()));
check(abasL.join("|") === "Painel|Agenda Ministerial|Meus ministérios|Organogramas|Candidatos|Turmas|Minha equipe|Solicitar mídia|Minhas escalas|Avisos|Meu perfil", "LÍDER vê, agrupadas: Painel, Agenda Ministerial, Meus ministérios, Organogramas, Candidatos, Turmas, Minha equipe, Solicitar mídia, Minhas escalas, Avisos e Meu perfil", abasL.join("|"));
await p.goto(BASE + "/#equipe/usuarios"); await p.waitForTimeout(600);
check(!(await p.isVisible('[data-sb="novoUsuario"]')), "abrir a rota de usuários pela barra de endereço não mostra a tela");
const tentativa = await p.evaluate(async () => { const r = await window.betelSB.rpc("listar_usuarios"); return r.error?.code; });
check(tentativa === "42501", "mesmo chamando o banco direto pelo navegador, o backend nega", tentativa);
await p.click('[data-sb="aba:equipe"]'); await esperar(p, "Você lidera");
check(await p.locator("a.wa").count() >= 1, "LÍDER vê WhatsApp da equipe que lidera");
await foto(p, "11-lider-equipe");
await sair(p);

console.log("\n4. VOLUNTÁRIO");
await login(p, "vitor.vol@teste.com", senhas["Vitor Teste Voluntário"]); await trocarSenha(p, "Vitor-Senha-Nova-01");
const abasV = await p.$$eval("#sbAbas button", (b) => b.map((x) => x.textContent.trim()));
check(abasV.join("|") === "Painel|Agenda Ministerial|Organogramas|Minha equipe|Minhas escalas|Avisos|Meu perfil", "VOLUNTÁRIO vê só Painel, Agenda Ministerial, Organogramas (só leitura), Minha equipe, Minhas escalas, Avisos e Meu perfil", abasV.join("|"));
await p.click('[data-sb="aba:agenda"]'); await esperar(p, "Você consulta o calendário");
check(await p.locator('a[href="agenda-ministerial/"]').count() === 1, "aba Agenda Ministerial com acesso direto à Agenda");
await p.click('[data-sb="aba:equipe"]'); await esperar(p, "Juventude Mergulhados");
check(await p.locator("a.wa").count() === 0, "VOLUNTÁRIO não vê contatos da equipe");
await foto(p, "12-voluntario-equipe");
await p.click('[data-sb="aba:conta"]'); await p.waitForSelector("#sbTrocar");
await p.fill("#tcAtual", "errada-12345"); await p.fill("#tcNova", "Vitor-Senha-Nova-02"); await p.fill("#tcConf", "Vitor-Senha-Nova-02"); await p.click("#tcSalvar");
await p.waitForFunction(() => /não confere/.test(document.querySelector("#tcMsg").textContent));
check(true, "trocar senha exige a senha atual correta");
await p.fill("#tcAtual", "Vitor-Senha-Nova-01"); await p.click("#tcSalvar");
await p.waitForFunction(() => /alterada/.test(document.querySelector("#tcMsg").textContent));
check(true, "troca de senha pelo Meu perfil");
await foto(p, "13-minha-conta");
await sair(p);

console.log("\n5. Recuperação de senha pela tela");
await p.goto(BASE + "/#equipe/esqueci"); await p.waitForSelector("#esEmail");
await p.fill("#esEmail", "vitor.vol@teste.com"); await p.click("#esEnviar"); await esperar(p, "Link enviado");
const caixa = await (await fetch(BASE + "/_dev/caixa")).json();
const link = caixa.filter((m) => m.para === "vitor.vol@teste.com").pop().link;
await p.goto(link); await p.waitForSelector('#sbNovaSenha[data-recuperacao="1"]');
check(true, "link do e-mail abre a tela de nova senha");
await foto(p, "14-recuperacao");
await p.fill("#nsSenha", "Vitor-Recuperada-03"); await p.fill("#nsConf", "Vitor-Recuperada-03"); await p.click("#nsSalvar");
await p.waitForSelector("#sbPainel:not([hidden])");
check(true, "nova senha salva e painel aberto");
await sair(p);
await login(p, "vitor.vol@teste.com", "Vitor-Recuperada-03"); await p.waitForSelector("#sbPainel:not([hidden])");
check(true, "entra com a senha recuperada");
await sair(p);
await p.goto(link); await p.waitForSelector("#esMsg");
check((await p.textContent("#esMsg")).includes("expirou"), "link usado uma vez não funciona de novo");

console.log("\n6. Desativação e celular");
const m = await pagina(true);
const irPara = async (pg, k) => { await pg.click("#sbIrBotao"); await pg.waitForSelector("#sbIrPainel.on"); await pg.click(`#sbIrPainel [data-sb="irAba:${k}"]`); await pg.waitForSelector("#sbIrPainel", { state: "hidden" }); };
await login(m, "master1@exemplo.com", "Ezequiel-Nova-2026"); await m.waitForSelector("#sbPainel:not([hidden])");
await foto(m, "15-celular-painel");
check(await m.isVisible("#sbIrBotao"), "no celular, a navegação é o menu Ir para");
await irPara(m, "usuarios"); await m.locator(".sbItem", { hasText: "Vitor" }).waitFor();
const btn = m.locator(".sbItem", { hasText: "Vitor" }).locator('[data-sb^="ativo:"]');
await btn.click(); await btn.click();
await m.locator(".sbItem", { hasText: "Vitor" }).locator(".badge", { hasText: "Inativo" }).waitFor();
check(true, "MASTER desativa (com confirmação)");
await foto(m, "16-celular-usuarios");
await login(p, "vitor.vol@teste.com", "Vitor-Recuperada-03");
await p.waitForFunction(() => /desativada/.test(document.querySelector("#sbMsg").textContent));
check(true, "conta desativada não entra");

await browser.close();
console.log(`\nResultado: ${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
