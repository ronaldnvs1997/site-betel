// Homologação — segurança: acesso direto às tabelas, funções expostas, funções administrativas chamadas
// por quem não tem permissão, Edge Functions sem login e injeção de código (XSS) nas telas.
import { createClient } from "@supabase/supabase-js";
import { chromium } from "playwright-core";
import { execFileSync } from "node:child_process";
import pg from "pg";
import { prepararVoluntario, paramsTermos } from "./apoio-termos.mjs";

const URL_ = process.env.SUPABASE_URL, ANON = process.env.SUPABASE_ANON_KEY;
const novo = () => createClient(URL_, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
let ok = 0, falhas = 0; const achados = [];
const check = (c, n, x) => { if (c) { ok++; console.log("  ✓ " + n); } else { falhas++; console.log("  ✗ " + n + (x !== undefined ? "  → " + JSON.stringify(x).slice(0, 300) : "")); } };
const sql = async (q, v) => { const c = new pg.Client({ host: "/tmp", port: 5434, user: "postgres", database: "betel" }); await c.connect(); try { return (await c.query(q, v)).rows; } finally { await c.end(); } };
async function entrar(email, senha, nova) { const c = novo(); const r = await c.auth.signInWithPassword({ email, password: senha }); if (r.error) throw new Error(r.error.message); if (nova) await c.auth.updateUser({ password: nova }); return c; }

const saida = execFileSync("node", ["../supabase/scripts/criar-primeiros-masters.mjs", "Primeiro Master Teste|master1@exemplo.com|31900000001"], { env: process.env }).toString();
const master = await entrar("master1@exemplo.com", saida.match(/senha temporária: (\S+)/)[1], "Ezequiel-Nova-2026");
const mins = (await novo().from("ministerios").select("id,nome")).data, mid = (n) => mins.find((m) => m.nome === n).id;
await prepararVoluntario("Vitor Voluntario", "vitor@teste.com", "31999990000");
const rv = (await master.functions.invoke("admin-usuarios", { body: { acao: "criar", nome: "Vitor Voluntario", telefone: "31999990000", email: "vitor@teste.com", perfil: "VOLUNTARIO", atribuicoes: [], ministerios: [{ ministerio_id: mid("Louvor"), funcao: "voluntario" }] } })).data;
const vol = await entrar("vitor@teste.com", rv.senha_temporaria, "Vitor-Nova-20261");
const anon = novo();

console.log("\n1. Visitante (sem login) nas tabelas");
const tabelas = (await sql("select relname from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' order by 1")).map((r) => r.relname);
const PUBLICAS = ["categorias_curso", "configuracoes", "cursos", "eventos", "ministerios", "reservas", "turmas"];
for (const t of tabelas) {
  const s = await anon.from(t).select("*").limit(5);
  if (PUBLICAS.includes(t)) check(!s.error, `${t}: leitura pública prevista`);
  else check(!!s.error || !s.data.length, `${t}: visitante não lê`, s.data?.[0]);
  const i = await anon.from(t).insert({});
  check(!!i.error, `${t}: visitante não grava`);
}
const cfg = (await anon.from("configuracoes").select("chave,publico")).data;
check(cfg.every((c) => c.publico), "configurações privadas não aparecem para o visitante", cfg.filter((c) => !c.publico));

console.log("\n2. Voluntário nas tabelas (só os próprios dados)");
for (const [t, regra] of [["pessoas", (d) => d.every((p) => p.email === "vitor@teste.com")], ["perfis", (d) => d.length <= 1], ["inscricoes", (d) => d.length === 0],
  ["auditoria", (d) => d.length === 0], ["solicitacoes", (d) => d.length === 0], ["notificacoes", () => true]]) {
  const s = await vol.from(t).select("*").limit(50);
  check(!!s.error || regra(s.data), `${t}: voluntário só vê o que é dele`, s.data?.slice(0, 2));
}
for (const t of tabelas) {
  const u = await vol.from(t).update({ id: null }).neq("id", "00000000-0000-0000-0000-000000000000").select();
  check(!!u.error || !u.data?.length, `${t}: voluntário não altera direto`);
  const d = await vol.from(t).delete().neq("id", "00000000-0000-0000-0000-000000000000").select();
  check(!!d.error || !d.data?.length, `${t}: voluntário não exclui direto`);
}

console.log("\n3. Funções: visitante e voluntário chamando tudo o que podem executar");
const fnAnon = await sql("select p.proname, pg_get_function_identity_arguments(p.oid) a from pg_proc p where p.pronamespace = 'public'::regnamespace and has_function_privilege('anon', p.oid, 'execute') order by 1");
const fnAuth = await sql("select p.proname, pg_get_function_identity_arguments(p.oid) a from pg_proc p where p.pronamespace = 'public'::regnamespace and has_function_privilege('authenticated', p.oid, 'execute') order by 1");
const lixo = (assin) => Object.fromEntries((assin.a ? assin.a.split(", ") : []).map((x) => { const [n, ...t] = x.split(" "); const ty = t.join(" ");
  return [n, /uuid\[\]/.test(ty) ? [] : /uuid/.test(ty) ? "00000000-0000-0000-0000-000000000001" : /int|numeric/.test(ty) ? 1 : /bool/.test(ty) ? true : /jsonb/.test(ty) ? {} : /date/.test(ty) ? "2026-12-01" : /\[\]/.test(ty) ? [] : "x"]; }));
const AUXILIARES = /^(minha_pessoa_id|perfil_ativo|e_master|tem_atribuicao|lider_de|membro_de|agenda_coordenador|agenda_pode_editar_ficha|cursos_gestor|e_secretaria|e_tesouraria|midia_ministerio_id|escala_lider|escala_gestor|pode_solicitar_apoio)$/;
const vazio = (d) => d == null || d === false || (Array.isArray(d) && !d.length) || (typeof d === "object" && !Array.isArray(d) && Object.values(d).every((v) => v == null || v === false || (Array.isArray(v) && !v.length)));
for (const f of fnAnon) {
  if (AUXILIARES.test(f.proname)) continue;
  const r = await anon.rpc(f.proname, lixo(f));
  if (/^(cursos_publicos|curso_publico|termos_vigentes)$/.test(f.proname)) { check(!r.error || r.error.code === "P0002", `visitante: ${f.proname} (público por desenho)`); continue; }
  if (/^(ministerios_publicos|site_conteudo_publico)$/.test(f.proname)) { check(!r.error && !/@|senha|token/i.test(JSON.stringify(r.data).replace(/@[A-Za-z0-9._]+"/g, '"')), `visitante: ${f.proname} (conteúdo público do site, sem dados pessoais)`); continue; }
  if (/^(agenda_link_abrir|agenda_link_enviar)$/.test(f.proname)) { check(!!r.error || r.data?.ok === false, `visitante: ${f.proname} sem código válido não abre nem envia`, r.data); continue; }
  check(!!r.error || vazio(r.data), `visitante: ${f.proname} com dados inválidos não devolve nada`, r.data);
}
const sensiveis = [];
for (const f of fnAuth) {
  if (AUXILIARES.test(f.proname) || fnAnon.some((x) => x.proname === f.proname)) continue;
  const r = await vol.rpc(f.proname, lixo(f));
  if (!r.error && !vazio(r.data)) sensiveis.push(f.proname);
}
const PROPRIOS = ["agenda_minhas_permissoes", "salvar_minha_disponibilidade", "meu_painel", "meu_perfil", "minhas_notificacoes", "minhas_escalas", "minha_disponibilidade", "apoio_minhas_solicitacoes", "midia_catalogo", "apoio_servicos_listar",
  "financeiro_minhas_permissoes", "minha_conta", "meus_ministerios", "minha_equipe", "agenda_meu_acesso", "cursos_validadores_disponiveis",
  "institucional_permissoes", "meu_perfil_foto_remover", "organogramas_listar"];
const estranhas = sensiveis.filter((n) => !PROPRIOS.includes(n));
console.log("    funções que devolvem dados ao voluntário: " + sensiveis.join(", "));
check(!estranhas.length, "voluntário só recebe dados de funções pessoais ou de catálogo", estranhas);
check(fnAuth.length > 100, `${fnAuth.length} funções conferidas com o voluntário e ${fnAnon.length} com o visitante`);

console.log("\n4. Funções administrativas usadas pelo voluntário");
for (const [f, a] of [["secretaria_inscricoes", { p_filtros: {} }], ["secretaria_pessoas", { p_busca: "a" }], ["tesouraria_pagamentos", { p_filtros: {} }], ["midia_painel", { p_filtros: {} }],
  ["midia_voluntarios", {}], ["secretaria_certificados", { p_filtros: {} }], ["imagem_consultar", { p_busca: "Vitor" }]]) {
  const r = await vol.rpc(f, a);
  check(!!r.error && /42501|PGRST202/.test(r.error.code || ""), `voluntário: ${f} negado`, r.error || r.data);
}

const lc = await vol.rpc("lider_candidaturas", {});
check(!!lc.error || (Array.isArray(lc.data) && !lc.data.length), "voluntário: lider_candidaturas não mostra candidaturas (não é líder)");

console.log("\n5. Edge Functions sem login e com login sem permissão");
for (const fn of ["admin-usuarios", "aprovar-acesso", "arquivos"]) {
  const r = await fetch(`${URL_}/functions/v1/${fn}`, { method: "POST", headers: { "content-type": "application/json", apikey: ANON }, body: JSON.stringify({ acao: fn === "arquivos" ? "link" : "listar", tipo: "documento", id: "00000000-0000-0000-0000-000000000001" }) });
  check([401, 403].includes(r.status), `${fn}: sem login recusa (${r.status})`);
}
const ra = await vol.functions.invoke("admin-usuarios", { body: { acao: "listar" } });
check(!!ra.error, "admin-usuarios: voluntário recusado");
const rarq = await vol.functions.invoke("arquivos", { body: { acao: "comprovante", id: "00000000-0000-0000-0000-000000000001" } });
check(!!rarq.error || !rarq.data?.url, "arquivos: voluntário não obtém link de arquivo alheio");

console.log("\n6. Limite de volume nos formulários públicos (M10)");
if ((await sql("select count(*)::int n from pg_proc where proname = 'tg_limite_publico'"))[0].n) {
  const curso = (await sql("select id from cursos where coalesce(cursos_exigidos, '{}') = '{}' and slug <> 'novos-membros' order by titulo limit 1"))[0].id;
  await sql("update cursos set publicado = true where id = $1", [curso]);
  const turmaL = (await master.rpc("cursos_salvar_turma", { p: { curso_id: curso, nome: "Turma robô", status: "inscricoes_abertas", vagas: "30" } })).data.id;
  await sql("update configuracoes set valor = '{\"inscricoes_por_pessoa_hora\": 3, \"inscricoes_10min\": 2, \"membresia_10min\": 2}' where chave = 'limites_publicos'");
  const base = await paramsTermos(); let ultimos = [];
  for (let i = 1; i <= 3; i++) ultimos.push(await anon.rpc("inscrever_curso_com_termos", { p_turma: turmaL, p_nome: `Robo Teste ${i}`, p_telefone: `3199000000${i}`, p_email: `robo${i}@teste.com`,
    p_data_nascimento: "1990-01-01", p_observacao: null, p_aceite_privacidade: true, p_origem: "site", ...base }));
  check(!ultimos[0].error && !ultimos[1].error && /muitas inscrições/.test(ultimos[2].error?.message || ""), "sem login: acima do limite, novas inscrições esperam", ultimos.map((r) => r.error?.message || "ok"));
  const sec = await master.rpc("secretaria_inscricoes", { p_filtros: {} });
  check(!sec.error, "a Secretaria (com login) não é afetada pelo limite");
  const m = []; for (let i = 1; i <= 3; i++) m.push(await anon.rpc("membresia_interesse", { p_nome: `Robo Membro ${i}`, p_telefone: `3198000000${i}`, p_email: `rm${i}@teste.com`, p_data_nascimento: "1990-01-01", p_mensagem: null, p_aceite_privacidade: true }));
  check(/muitos pedidos/.test(m[2].error?.message || ""), "pedidos de membresia sem login também têm limite", m.map((r) => r.error?.message || "ok"));
  await sql("update configuracoes set valor = '{\"inscricoes_por_pessoa_hora\": 3, \"inscricoes_10min\": 60, \"membresia_10min\": 20}' where chave = 'limites_publicos'");
} else console.log("    (M10 não aplicada)");

console.log("\n7. Injeção de código nas telas (XSS)");
const ataque = `<img src=x onerror="window.__xss=1">`;
const turma = (await sql("select t.id from turmas t join cursos c on c.id = t.curso_id where t.status = 'inscricoes_abertas' limit 1"))[0]?.id;
await sql("update termos set status = 'vigente', texto = replace(texto, '⟦', '') where status = 'rascunho'").catch(() => {});
await sql("update eventos set titulo = $1, observacoes = $1 where titulo = 'CULTO DE JOVENS'", [ataque]);
await sql("insert into pessoas (nome, email, telefone) values ($1, 'xss@teste.com', '31999998888')", [ataque]).catch(() => {});
await master.rpc("apoio_solicitar", { p: { ministerio_solicitante: mid("Louvor"), responsavel_nome: ataque, titulo: ataque, tipo_evento: "outro", inicio: "2026-12-20T19:00:00-03:00", fim: "2026-12-20T21:00:00-03:00", local: ataque, servicos: [{ servico_id: (await sql("select id from apoio_servicos limit 1"))[0].id, detalhe: ataque }] } });
const br = await chromium.launch({ executablePath: "/usr/bin/google-chrome", args: ["--no-sandbox"] });
const p = await (await br.newContext({ viewport: { width: 1360, height: 900 } })).newPage(); p.on("dialog", (d) => d.dismiss());
await p.goto(URL_ + "/#equipe/entrar"); await p.waitForSelector("#sbLogin"); await p.fill("#sbEmail", "master1@exemplo.com"); await p.fill("#sbSenha", "Ezequiel-Nova-2026"); await p.click("#sbEntrar");
await p.waitForSelector("#sbPainel:not([hidden])");
for (const aba of (await p.$$eval("#sbAbas button", (b) => b.map((x) => x.dataset.sb.slice(4))))) { if (aba === "agenda") continue; await p.click(`[data-sb="aba:${aba}"]`); await p.waitForTimeout(700); }
await p.click('[data-sb="aba:midia"]'); await p.waitForTimeout(500); await p.click('[data-ml="tela:solicitacoes"]').catch(() => {}); await p.waitForTimeout(900);
check(await p.evaluate(() => document.body.innerText.includes('<img src=x onerror')), "o texto malicioso aparece como texto comum na tela (escapado), não como código");
await p.click('[data-sb="aba:secretaria"]'); await p.waitForTimeout(500); await p.click('[data-se="tela:pessoas"]').catch(() => {}); await p.waitForTimeout(700);
check(!(await p.evaluate(() => window.__xss)), "nenhum código injetado executou na Área da Equipe (todas as abas, Secretaria, Mídia)");
for (const u of ["/#agenda", "/agenda-ministerial/", "/#inicio"]) {
  await p.goto(URL_ + u); await p.waitForTimeout(1800);
  check(!(await p.evaluate(() => window.__xss)), `nenhum código injetado executou em ${u}`);
}
await br.close();

console.log(`\nResultado: ${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
