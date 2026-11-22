// Etapa 2 — comparação da Agenda ORIGINAL com a Agenda INTEGRADA no navegador.
// Fase A: página original + banco no estado atual (aberto). Fase B: página integrada + banco com M02–M04.
// O mesmo roteiro é executado nas duas; no fim, os registros gravados são comparados.
import { chromium } from "playwright-core";
import fs from "node:fs";
import { execSync } from "node:child_process";
import pg from "pg";

const BASE = process.env.SUPABASE_URL;
const ORIGINAL = process.env.AGENDA_ORIGINAL || "/mnt/user-data/uploads/e7845cc7-index.html";
const SAIDA = process.env.SAIDA || "/tmp/agenda-telas";
const SITE = "../supabase/site";
fs.mkdirSync(SAIDA, { recursive: true });
let ok = 0, falhas = 0;
const check = (c, n, x) => { if (c) { ok++; console.log("  ✓ " + n); } else { falhas++; console.log("  ✗ " + n + (x !== undefined ? "  → " + String(x).slice(0, 300) : "")); } };
const browser = await chromium.launch({ executablePath: "/usr/bin/google-chrome", args: ["--no-sandbox"] });

async function abrir(tipo) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, acceptDownloads: true, timezoneId: "America/Sao_Paulo" });
  const p = await ctx.newPage();
  p.erros = [];
  p.on("pageerror", (e) => p.erros.push(e.message));
  p.on("dialog", (d) => d.type() === "prompt" ? d.accept("2026") : d.accept());
  await ctx.route("**/*", async (route) => {
    const u = route.request().url();
    if (u.startsWith("https://fonts.")) return route.abort();
    if (u.startsWith("https://cdn.tailwindcss.com")) return route.fulfill({ contentType: "text/javascript", body: `window.tailwind={};document.head.insertAdjacentHTML('beforeend','<link rel="stylesheet" href="${BASE}/agenda-ministerial/agenda.css">');` });
    if (u.startsWith("https://cdn.jsdelivr.net/npm/@supabase")) return route.fulfill({ contentType: "text/javascript", body: fs.readFileSync(`${SITE}/vendor/supabase.js`) });
    if (u.startsWith("https://cdnjs.cloudflare.com/ajax/libs/jspdf")) return route.fulfill({ contentType: "text/javascript", body: fs.readFileSync(`${SITE}/vendor/jspdf.umd.min.js`) });
    if (u.startsWith("https://agenda-antiga.invalid")) {
      const rq = route.request();
      const r = await fetch(u.replace("https://agenda-antiga.invalid", BASE), { method: rq.method(), headers: rq.headers(), body: ["GET", "HEAD"].includes(rq.method()) ? undefined : rq.postDataBuffer() });
      return route.fulfill({ status: r.status, headers: Object.fromEntries(r.headers), body: Buffer.from(await r.arrayBuffer()) });
    }
    if (u.startsWith(BASE + "/agenda-original/")) return route.fulfill({ contentType: "text/html; charset=utf-8", body: fs.readFileSync(ORIGINAL) });
    return route.continue();
  });
  await p.goto(`${BASE}/${tipo === "original" ? "agenda-original" : "agenda-ministerial"}/`);
  await p.waitForFunction(() => document.querySelectorAll("#grade-dias > div").length > 27);
  await p.waitForTimeout(400);
  return p;
}
const aviso = (p, t) => p.waitForFunction((t) => document.getElementById("status-banner").textContent.includes(t), t, { timeout: 8000 });
const irParaDezembro = async (p) => { await p.evaluate(() => { anoAtual = 2026; mesAtual = 11; renderizarCalendario(); }); };
async function abrirEvento(p, titulo) { await p.locator("#grade-dias button", { hasText: titulo }).first().click(); await p.waitForSelector("#tela-evento:not(.hidden)"); }
async function voltar(p) { await p.locator("header .cursor-pointer").first().click(); await p.waitForSelector("#tela-calendario:not(.hidden)"); }
const foto = (p, n) => p.screenshot({ path: `${SAIDA}/${n}.png`, fullPage: false });

async function loginOriginal(p) {
  await p.click("#btn-modo-coord"); await p.fill("#login-coord-usuario", "coord"); await p.fill("#login-coord-senha", "senha-legada-1");
  await p.click("#btn-entrar-coord"); await p.waitForSelector("#barra-coordenador:not(.hidden)");
}
const senhas = () => JSON.parse(fs.readFileSync("/tmp/agenda-contas.json", "utf8"));
async function loginIntegrada(p, email, senha) {
  await p.click("#btn-modo-coord"); await p.fill("#login-coord-usuario", email); await p.fill("#login-coord-senha", senha);
  await p.click("#btn-entrar-coord"); await p.waitForSelector("#modal-login-coord.hidden", { state: "attached" });
}

// Roteiro idêntico nas duas versões
async function roteiro(p, prefixo) {
  const r = {};
  await irParaDezembro(p); await foto(p, `${prefixo}-01-calendario-coordenador`);
  // 1. novo evento
  await p.click("#barra-coordenador >> text=+ Novo Evento");
  await p.fill("#coord-titulo", "Teste comparativo"); await p.fill("#coord-data", "2026-12-08"); await p.fill("#coord-ministerio", "Kids");
  await p.click("#modal-coord button[type=submit]"); await aviso(p, "Calendário atualizado");
  await irParaDezembro(p);
  r.eventoCriado = await p.locator("#grade-dias button", { hasText: "TESTE COMPARATIVO" }).count();
  // 2. ficha oficial completa
  await abrirEvento(p, "TESTE COMPARATIVO");
  await p.fill("#input-lider", "Ana Kids"); await p.fill("#input-horario-inicio", "18:00"); await p.fill("#input-horario-fim", "20:00");
  await p.check('input[name="evento-local"][value="Quadra"]');
  await p.selectOption("#input-midia", "Sim"); await p.fill("#input-midia-tema", "Natal Kids");
  await p.selectOption("#input-midia-arte", "Sim"); await p.selectOption("#input-midia-banner", "Não"); await p.selectOption("#input-midia-inscricao", "Sim");
  await p.fill("#input-midia-link-inscricao", "https://inscricao.exemplo/kids"); await p.fill("#input-midia-info", "Arte em tons de vermelho");
  await p.selectOption("#input-louvor", "Não"); await p.selectOption("#input-diaconia", "Sim");
  await p.fill("#input-observacoes", "Trazer lanche"); await p.fill("#input-link-fotos", "https://fotos.exemplo/kids");
  await p.click("#btn-salvar-ficha"); await aviso(p, "Informações salvas");
  r.muralTema = await p.textContent("#mural-midia-tema");
  await foto(p, `${prefixo}-02-ficha`);
  // 3. trancar e destrancar
  await p.click("#btn-trancar-ficha"); await aviso(p, "trancada");
  r.badgeTrancada = await p.isVisible("#badge-ficha-trancada");
  await p.click("#btn-trancar-ficha"); await aviso(p, "destrancada");
  await p.click("#btn-trancar-ficha"); await aviso(p, "trancada");
  await voltar(p); await irParaDezembro(p);
  // 4. reserva única com conflito
  await p.click("#barra-coordenador >> text=Reservar Espaço");
  await p.fill("#res-ministerio", "Kids"); await p.fill("#res-motivo", "Ensaio"); await p.check('input[name="res-espaco"][value="Quadra"]');
  await p.fill("#res-inicio", "19:00"); await p.fill("#res-fim", "21:00"); await p.fill("#res-data-unica", "2026-12-08");
  await p.click("#btn-salvar-reserva"); await p.waitForSelector("#modal-conflito:not(.hidden)");
  r.conflito = (await p.textContent("#lista-conflitos-encontrados")).replace(/\s+/g, " ").trim();
  await foto(p, `${prefixo}-03-conflito`);
  await p.click("#modal-conflito button"); await p.click("#modal-reserva button[onclick='fecharModalReserva()']").catch(() => p.evaluate(() => fecharModalReserva()));
  // 5. reserva recorrente (todas as terças de dezembro)
  await p.click("#barra-coordenador >> text=Reservar Espaço");
  await p.fill("#res-ministerio", "Intercessão"); await p.fill("#res-motivo", "Oração"); await p.check('input[name="res-espaco"][value="Salão de Festas"]');
  await p.fill("#res-inicio", "07:00"); await p.fill("#res-fim", "08:00"); await p.check('input[name="res-tipo"][value="massa"]');
  await p.selectOption("#res-dia-semana", "2"); await p.fill("#res-data-inicio-massa", "2026-12-01"); await p.fill("#res-data-fim-massa", "2026-12-31");
  await p.click("#btn-salvar-reserva"); await aviso(p, "reserva(s) confirmada(s)");
  r.avisoLote = await p.textContent("#status-banner");
  await irParaDezembro(p); await foto(p, `${prefixo}-04-reservas-em-serie`);
  // 6. excluir uma data e depois a série
  await p.locator("#grade-dias button", { hasText: "Intercessão" }).first().click(); await p.waitForSelector("#modal-detalhe-reserva:not(.hidden)");
  r.botaoLoteVisivel = await p.isVisible("#btn-excluir-lote");
  await p.click("#modal-detalhe-reserva >> text=Excluir"); await aviso(p, "Reserva excluída");
  await irParaDezembro(p);
  r.restantesAposUnica = await p.locator("#grade-dias button", { hasText: "Intercessão" }).count();
  await p.locator("#grade-dias button", { hasText: "Intercessão" }).first().click(); await p.waitForSelector("#modal-detalhe-reserva:not(.hidden)");
  await p.click("#btn-excluir-lote"); await aviso(p, "série foram excluídas");
  await irParaDezembro(p);
  r.restantesAposLote = await p.locator("#grade-dias button", { hasText: "Intercessão" }).count();
  // 7. mover o evento
  await abrirEvento(p, "TESTE COMPARATIVO");
  await p.click("#acoes-coord-evento >> text=Mudar Data"); await p.fill("#coord-data", "2026-12-09");
  await p.click("#modal-coord button[type=submit]"); await aviso(p, "Calendário atualizado");
  r.dataNova = await p.textContent("#detalhe-data-extenso");
  // 8. PDF anual
  await voltar(p);
  const [down] = await Promise.all([p.waitForEvent("download"), p.click("header >> text=Baixar PDF")]);
  const arq = `${SAIDA}/${prefixo}-calendario-2026.pdf`; await down.saveAs(arq);
  const pdf = fs.readFileSync(arq, "latin1");
  r.pdfPaginas = (pdf.match(/\/Type \/Page\b/g) || []).length; r.pdfNome = down.suggestedFilename();
  r.pdfTemEvento = pdf.includes("TESTE COMPARATIVO") || pdf.includes("TESTE COMPARATIV");
  return r;
}

async function fotografiaBanco() {
  const c = new pg.Client({ host: "/tmp", port: 5434, user: "postgres", database: "betel" }); await c.connect();
  const ev = (await c.query(`select titulo, data::text, ministerio, lider, horario, horario_inicio::text, horario_fim::text, local, necessita_midia, necessita_louvor,
     necessita_diaconia, midia_tema, midia_arte, midia_banner, midia_inscricao, midia_link_inscricao, midia_info, observacoes, link_fotos, link_videos, bloqueado
     from eventos order by titulo`)).rows;
  const rs = (await c.query(`select ministerio, motivo, espacos, data::text, horario_inicio::text, horario_fim::text, (lote_id is not null) as em_lote from reservas order by data, ministerio`)).rows;
  await c.end(); return { eventos: ev, reservas: rs };
}
const reset = (m) => execSync(`./reset.sh ${m} texto`, { stdio: "pipe" });
const reiniciarServidor = () => { execSync("pkill -f \"node servidor[.]mjs\" || true"); execSync("(node servidor.mjs > /tmp/srv.log 2>&1 &)", { shell: "/bin/bash" }); execSync("sleep 1.5"); };

console.log("\nFase A — Agenda ORIGINAL (banco como está hoje)");
reset(1); reiniciarServidor();
let p = await abrir("original");
await foto(p, "A-00-calendario-publico");
await loginOriginal(p);
const A = await roteiro(p, "A"); const bancoA = await fotografiaBanco();
check(A.eventoCriado === 1, "original: roteiro executado");
const errosA = p.erros.slice(); await p.context().close();

console.log("\nFase B — Agenda INTEGRADA (banco com M02–M04, login central)");
reset(4); reiniciarServidor();
execSync("node ../supabase/tests/teste-agenda-backend.mjs > /tmp/agenda-preparo.txt 2>&1 || true", { env: process.env, shell: "/bin/bash" });
// zera a agenda para o mesmo ponto de partida, mantendo as contas criadas pelo teste de backend
{
  const c = new pg.Client({ host: "/tmp", port: 5434, user: "postgres", database: "betel" }); await c.connect();
  await c.query("alter table eventos disable trigger user; alter table reservas disable trigger user");
  await c.query("delete from eventos; delete from reservas");
  const seed = fs.readFileSync("sql/01_agenda_existente.sql", "utf8").match(/insert into public\.eventos[\s\S]*?;\ninsert into public\.reservas[\s\S]*?;\n/)[0];
  await c.query(seed);
  await c.query("update eventos set ministerio_id = public.agenda_ministerio_por_nome(ministerio)");
  await c.query("alter table eventos enable trigger user; alter table reservas enable trigger user");
  await c.end();
}
p = await abrir("integrada");
await foto(p, "B-00-calendario-publico");
await loginIntegrada(p, "carla@teste.com", senhas().carla);
check(await p.isVisible("#barra-coordenador"), "integrada: Carla entra com a conta central e o Modo Coordenador abre");
const B = await roteiro(p, "B"); const bancoB = await fotografiaBanco();

console.log("\nComparação ORIGINAL × INTEGRADA");
for (const k of Object.keys(A)) check(JSON.stringify(A[k]) === JSON.stringify(B[k]), `mesmo resultado: ${k} = ${JSON.stringify(B[k]).slice(0, 90)}`, `original ${JSON.stringify(A[k])} × integrada ${JSON.stringify(B[k])}`);
check(JSON.stringify(bancoA.eventos) === JSON.stringify(bancoB.eventos), `eventos gravados idênticos (${bancoB.eventos.length} registros, todos os campos da ficha)`);
check(JSON.stringify(bancoA.reservas) === JSON.stringify(bancoB.reservas), `reservas gravadas idênticas (${bancoB.reservas.length} registros)`);
check(A.pdfPaginas === 12 && B.pdfPaginas === 12, "PDF anual com 12 páginas nas duas versões");
check(errosA.length === 0 || errosA.every((e) => /tailwind/i.test(e)), "original sem erros de JavaScript", errosA.join(" | "));
check(p.erros.length === 0, "integrada sem erros de JavaScript", p.erros.join(" | "));
// excluir o evento (fim do roteiro) só na integrada, para não repetir
await abrirEvento(p, "TESTE COMPARATIVO").catch(async () => { await irParaDezembro(p); await abrirEvento(p, "TESTE COMPARATIVO"); });
await p.click("#acoes-coord-evento >> text=Excluir"); await aviso(p, "Evento removido");
check(true, "excluir evento pela tela");

console.log("\nFase C — permissões na tela integrada");
// conflito só detectado no banco (outra pessoa reservou depois que a página carregou)
await irParaDezembro(p);
const outro = (await import("@supabase/supabase-js")).createClient(BASE, process.env.SUPABASE_ANON_KEY, { auth: { persistSession: false } });
await outro.auth.signInWithPassword({ email: "carla@teste.com", password: senhas().carla });
await outro.from("reservas").insert([{ ministerio: "Diaconia", motivo: "Reunião", espacos: "Templo", data: "2026-12-14", horario_inicio: "10:00", horario_fim: "11:00" }]);
await p.click("#barra-coordenador >> text=Reservar Espaço");
await p.fill("#res-ministerio", "Kids"); await p.fill("#res-motivo", "Teste"); await p.check('input[name="res-espaco"][value="Templo"]');
await p.fill("#res-inicio", "10:30"); await p.fill("#res-fim", "11:30"); await p.fill("#res-data-unica", "2026-12-14");
await p.click("#btn-salvar-reserva"); await p.waitForSelector("#modal-conflito:not(.hidden)");
check((await p.textContent("#lista-conflitos-encontrados")).includes("Diaconia"), "conflito que a tela não via (dados desatualizados) é barrado pelo banco e mostrado no mesmo aviso");
await foto(p, "C-01-conflito-pelo-banco");
await p.context().close();

p = await abrir("integrada"); await irParaDezembro(p);
await abrirEvento(p, "CULTO DE JOVENS");
check(await p.isDisabled("#input-lider") && await p.isDisabled("#btn-salvar-ficha"), "visitante: ficha somente leitura");
check((await p.textContent("#texto-motivo-bloqueio")).includes("Entrar"), "visitante: explica que é preciso entrar com a conta da equipe");
await foto(p, "C-02-visitante-ficha");
await loginIntegrada(p, "lia@teste.com", senhas().lia);
check(await p.isVisible("#barra-lider") && (await p.textContent("#barra-lider")).includes("Juventude"), "líder: barra mostra os ministérios que ela lidera");
check(!(await p.isVisible("#barra-coordenador")), "líder: sem Modo Coordenador");
check(!(await p.isDisabled("#input-lider")), "líder: ao entrar, a ficha aberta do próprio ministério é liberada na hora");
await voltar(p); await irParaDezembro(p);
await abrirEvento(p, "CULTO DE JOVENS");
check(!(await p.isDisabled("#input-lider")), "líder: ficha do próprio ministério liberada para edição");
await p.fill("#input-observacoes", "Atualizado pela líder"); await p.click("#btn-salvar-ficha"); await aviso(p, "Informações salvas");
check((await p.textContent("#mural-observacoes")).includes("pela líder"), "líder: salva a ficha e o mural mostra a atualização");
await foto(p, "C-04-lider-ficha-salva");
{ const c = new pg.Client({ host: "/tmp", port: 5434, user: "postgres", database: "betel" }); await c.connect(); await c.query("update eventos set bloqueado = true where titulo = 'CULTO DE JOVENS'"); await c.end(); }
await p.reload(); await p.waitForSelector("#tela-evento:not(.hidden)"); await p.waitForTimeout(300);
check((await p.textContent("#detalhe-titulo")) === "CULTO DE JOVENS", "link direto do evento (?evento=) reabre a mesma ficha, já com a sessão da conta");
check(!(await p.isDisabled("#input-link-fotos")) && await p.isDisabled("#input-lider"), "líder: ficha trancada deixa só fotos e vídeos editáveis");
await voltar(p); await irParaDezembro(p);
await abrirEvento(p, "ENSAIO GERAL DE NATAL");
check(await p.isDisabled("#input-lider") && (await p.textContent("#texto-motivo-bloqueio")).includes("líder do ministério responsável"), "líder da Juventude não edita ficha do Louvor");
await foto(p, "C-03-lider-outro-ministerio");
const tentativa = await p.evaluate(async () => (await db.from("eventos").delete().eq("titulo", "ENSAIO GERAL DE NATAL").select("id")).data?.length);
check(tentativa === 0, "líder tentando excluir pelo console: o banco não exclui nada");
await p.click("#btn-modo-coord"); await p.waitForSelector("#barra-lider.hidden", { state: "attached" });
check(true, "sair da conta pela Agenda");
await p.context().close();

console.log("\nFase D — página antiga contra o banco protegido");
p = await abrir("original");
await p.click("#btn-modo-coord"); await p.fill("#login-coord-usuario", "coord"); await p.fill("#login-coord-senha", "senha-legada-1"); await p.click("#btn-entrar-coord");
await p.waitForSelector("#erro-login-coord:not(.hidden)");
check(true, "a página antiga não consegue mais validar a senha na tabela (login antigo bloqueado)");
check((await p.locator("#grade-dias button").count()) > 0, "a página antiga ainda mostra o calendário (leitura pública mantida)");
await p.context().close();

await browser.close();
fs.writeFileSync(`${SAIDA}/comparacao.json`, JSON.stringify({ original: A, integrada: B, bancoOriginal: bancoA, bancoIntegrada: bancoB }, null, 2));
console.log(`\nResultado: ${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
