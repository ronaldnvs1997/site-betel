// Teste do backend da Etapa 1 (autenticação + Área da Equipe) com os três perfis.
// Roda contra o ambiente local (dev-supabase) ou contra um projeto de testes do Supabase:
//   SUPABASE_URL=... SUPABASE_ANON_KEY=... SUPABASE_SERVICE_ROLE_KEY=... node teste-backend.mjs
import { createClient } from "@supabase/supabase-js";
import { execFileSync } from "node:child_process";
import { prepararVoluntario } from "./apoio-termos.mjs";

const URL_ = process.env.SUPABASE_URL, ANON = process.env.SUPABASE_ANON_KEY, SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
const novo = () => createClient(URL_, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
const servico = createClient(URL_, SERVICE, { auth: { persistSession: false, autoRefreshToken: false } });
let ok = 0, falhas = 0;
function check(cond, nome, extra) { if (cond) { ok++; console.log("  ✓ " + nome); } else { falhas++; console.log("  ✗ " + nome + (extra ? "  → " + JSON.stringify(extra) : "")); } }
const negado = (r) => !!r.error && ["42501", "PGRST301"].includes(r.error.code);
async function fn(cli, nome, corpo) {
  const { data, error } = await cli.functions.invoke(nome, { body: corpo });
  if (!error) return { data, status: 200 };
  let j = {}; try { j = await error.context.json(); } catch (_) {}
  return { error: j.erro || error.message, status: error.context?.status };
}
async function entrar(email, senha) { const c = novo(); const r = await c.auth.signInWithPassword({ email, password: senha }); return { c, r }; }

console.log("\n1. Primeiros MASTERs (script de implantação)");
const saida = execFileSync("node", ["../scripts/criar-primeiros-masters.mjs",
  "Primeiro Master Teste|master1@exemplo.com|31900000001",
  "Segundo Master Teste|master2@exemplo.com|31900000002"], { env: { ...process.env } }).toString();
const temp = Object.fromEntries([...saida.matchAll(/<([^>]+)> — senha temporária: (\S+)/g)].map((m) => [m[1], m[2]]));
check(Object.keys(temp).length === 2, "duas contas MASTER criadas com senha temporária");
// A partir da M07, só é voluntário quem tem a membresia validada e o Novos Membros concluído.
for (const [n, e, t] of [["Lia Teste Líder", "lia.lider@teste.com", "31988880001"], ["Vitor Teste Voluntário", "vitor.vol@teste.com", "31988880002"], ["Rui Teste Recusado", "rui@teste.com", "31988880003"], ["Segundo Master Teste", "master2@exemplo.com", "31900000002"]]) await prepararVoluntario(n, e, t);

console.log("\n2. Visitante sem login (anon)");
const anon = novo();
const mins = await anon.from("ministerios").select("id,nome").order("ordem");
check(!mins.error && mins.data.length === 12, "lê a lista de ministérios ativos", mins.error);
const juv = mins.data.find((m) => m.nome === "Juventude Mergulhados").id, midia = mins.data.find((m) => m.nome === "Mídia").id, louvor = mins.data.find((m) => m.nome === "Louvor").id;
check(negado(await anon.from("perfis").select("*")), "não lê perfis");
check(negado(await anon.from("pessoas").select("*")), "não lê pessoas");
check(negado(await anon.from("solicitacoes").select("*")), "não lê solicitações");
check(negado(await anon.rpc("listar_usuarios")), "não lista usuários");
check(negado(await anon.rpc("servico_criar_usuario", { p_ator: null, p_usuario: crypto.randomUUID(), p_nome: "X Y", p_telefone: "", p_email: "x@y.com", p_perfil: "MASTER", p_atribuicoes: [], p_ministerios: [] })), "não chama a função de serviço de criar usuário");
const insDireto = await anon.from("solicitacoes").insert({ tipo: "acesso", nome: "Hacker Teste", telefone: "31999999999", email: "h@h.com", ministerio_id: juv, funcao_pretendida: "lider", status: "aprovada" });
check(!!insDireto.error, "não grava direto na tabela de solicitações");
const sNome = await anon.rpc("solicitar_acesso", { p_nome: "Ana", p_telefone: "31999990000", p_email: "ana@teste.com", p_ministerio: juv, p_funcao: "lider" });
check(sNome.error && /nome completo/.test(sNome.error.message), "recusa nome incompleto", sNome.error);
const sTel = await anon.rpc("solicitar_acesso", { p_nome: "Ana Teste", p_telefone: "123", p_email: "ana@teste.com", p_ministerio: juv, p_funcao: "lider" });
check(sTel.error && /telefone/.test(sTel.error.message), "recusa telefone inválido");
const sFun = await anon.rpc("solicitar_acesso", { p_nome: "Ana Teste", p_telefone: "31999990000", p_email: "ana@teste.com", p_ministerio: juv, p_funcao: "master" });
check(sFun.error && /função/.test(sFun.error.message), "recusa função diferente de Líder/Voluntário");
for (const [n, t, e, m, f] of [["Lia Teste Líder", "31988880001", "lia.lider@teste.com", juv, "lider"], ["Vitor Teste Voluntário", "31988880002", "vitor.vol@teste.com", juv, "voluntario"], ["Rui Teste Recusado", "31988880003", "rui@teste.com", louvor, "voluntario"]]) {
  const r = await anon.rpc("solicitar_acesso", { p_nome: n, p_telefone: t, p_email: e, p_ministerio: m, p_funcao: f });
  check(!r.error && r.data.ok, `solicitação de acesso enviada: ${n}`, r.error);
}
await anon.rpc("solicitar_acesso", { p_nome: "Lia Teste Líder", p_telefone: "31988880001", p_email: "LIA.LIDER@teste.com", p_ministerio: juv, p_funcao: "lider" });
const semToken = await fn(anon, "aprovar-acesso", { solicitacao_id: crypto.randomUUID() });
check(semToken.status === 401, "função de aprovação exige login", semToken);

console.log("\n3. MASTER — primeiro acesso");
let { c: master, r: lm } = await entrar("master1@exemplo.com", temp["master1@exemplo.com"]);
check(!lm.error, "entra com a senha temporária", lm.error);
check((await master.rpc("meu_painel")).data?.status === "trocar_senha", "painel exige troca de senha antes de tudo");
check(negado(await master.rpc("listar_usuarios")), "sem trocar a senha, não acessa nada administrativo");
check((await fn(master, "aprovar-acesso", { solicitacao_id: crypto.randomUUID() })).status === 403, "sem trocar a senha, a função de servidor também nega");
const mesma = await master.auth.updateUser({ password: temp["master1@exemplo.com"] });
check(mesma.error?.code === "same_password", "não aceita repetir a senha temporária", mesma.error);
const curta = await master.auth.updateUser({ password: "curta1" });
check(curta.error?.code === "weak_password", "não aceita senha curta");
check(!(await master.auth.updateUser({ password: "Ezequiel-Nova-2026" })).error, "troca para uma senha própria");
const pm = (await master.rpc("meu_painel")).data;
check(pm.status === "ok" && pm.perfil === "MASTER" && pm.resumo.solicitacoes_pendentes === 3, "painel liberado como MASTER, com 3 solicitações pendentes", pm);
const boot = execFileSync("node", ["../scripts/criar-primeiros-masters.mjs", "Intruso Teste|intruso@teste.com|31900000000"], { env: { ...process.env } }).toString();
const bootErr = (() => { try { execFileSync("node", ["../scripts/criar-primeiros-masters.mjs", "Intruso Dois|intruso2@teste.com|31900000001"], { env: { ...process.env }, stdio: "pipe" }); return ""; } catch (e) { return String(e.stderr); } })();
check(!/senha temporária/.test(boot), "script de primeiros MASTERs para de funcionar depois do primeiro acesso de um MASTER", boot + bootErr);

console.log("\n4. MASTER — solicitações");
const sols = (await master.rpc("listar_solicitacoes", { p_status: "pendente" })).data;
check(sols.length === 3, "lista 3 pendentes (o pedido repetido não duplicou)", sols.length);
const sLia = sols.find((s) => s.email === "lia.lider@teste.com"), sVitor = sols.find((s) => s.email === "vitor.vol@teste.com"), sRui = sols.find((s) => s.email === "rui@teste.com");
const apLia = await fn(master, "aprovar-acesso", { solicitacao_id: sLia.id, perfil: "LIDER", atribuicoes: [], ministerios: [{ ministerio_id: juv, funcao: "lider" }, { ministerio_id: midia, funcao: "voluntario" }] });
check(apLia.data?.ok && /^[A-Za-z0-9]{4}-[A-Za-z0-9]{4}-[A-Za-z0-9]{4}$/.test(apLia.data.senha_temporaria), "aprova a Líder e gera senha temporária forte", apLia);
const apVitor = await fn(master, "aprovar-acesso", { solicitacao_id: sVitor.id });
check(apVitor.data?.ok, "aprova o Voluntário com o que ele pediu", apVitor);
check((await fn(master, "aprovar-acesso", { solicitacao_id: sVitor.id })).status === 409, "não aprova a mesma solicitação duas vezes");
const liderSemMin = await fn(master, "aprovar-acesso", { solicitacao_id: sRui.id, perfil: "LIDER", ministerios: [{ ministerio_id: louvor, funcao: "voluntario" }] });
check(liderSemMin.status === 400, "não cria LÍDER sem ministério liderado");
check((await master.rpc("recusar_solicitacao", { p_solicitacao: sRui.id, p_motivo: "" })).error, "recusa exige motivo");
check(!(await master.rpc("recusar_solicitacao", { p_solicitacao: sRui.id, p_motivo: "Não identificado no Louvor" })).error, "recusa com motivo");
check((await master.rpc("listar_solicitacoes", { p_status: "pendente" })).data.length === 0, "nenhuma pendente depois da análise");

console.log("\n5. LÍDER");
let { c: lider, r: ll } = await entrar("lia.lider@teste.com", apLia.data.senha_temporaria);
check(!ll.error, "entra com a senha temporária");
check((await lider.rpc("meu_painel")).data.status === "trocar_senha", "é obrigada a trocar a senha");
check(negado(await lider.rpc("minha_equipe")), "antes da troca, não vê a equipe");
await lider.auth.updateUser({ password: "Lia-Senha-Nova-01" });
const pl = (await lider.rpc("meu_painel")).data;
check(pl.status === "ok" && pl.perfil === "LIDER" && pl.ministerios.length === 2 && !pl.resumo, "painel de LÍDER com 2 ministérios e sem dados administrativos", pl);
const eq = (await lider.rpc("minha_equipe")).data;
const gJuv = eq.find((g) => g.ministerio === "Juventude Mergulhados"), gMid = eq.find((g) => g.ministerio === "Mídia");
check(gJuv.sou_lider && gJuv.membros.some((m) => m.nome === "Vitor Teste Voluntário" && m.telefone), "na Juventude (que lidera) vê o voluntário com telefone");
check(!gMid.sou_lider && gMid.membros.every((m) => !m.telefone && !m.email), "na Mídia (onde é voluntária) não vê contatos");
check(negado(await lider.rpc("listar_usuarios")), "não lista usuários");
check(negado(await lider.rpc("listar_solicitacoes", { p_status: "pendente" })), "não vê solicitações");
check(negado(await lider.rpc("listar_auditoria", { p_limite: 10 })), "não vê o histórico");
check(negado(await lider.rpc("admin_salvar_ministerio", { p_id: null, p_nome: "Ministério Pirata", p_descricao: "", p_ordem: 1, p_ativo: true })), "não cria ministério");
check(negado(await lider.rpc("admin_atualizar_usuario", { p_usuario: ll.data.user.id, p_perfil: "MASTER", p_atribuicoes: ["TESOURARIA"], p_ministerios: [] })), "não se promove a MASTER");
check((await fn(lider, "admin-usuarios", { acao: "criar", nome: "Novo Usuario", telefone: "31999990000", email: "n@n.com", perfil: "MASTER" })).status === 403, "função de servidor nega criação de usuário");
const pf = await lider.from("perfis").select("id,perfil");
check(pf.data?.length === 1 && pf.data[0].perfil === "LIDER", "lê só o próprio perfil", pf.data);
const pes = await lider.from("pessoas").select("nome");
check(pes.data?.length === 2, "lê só o próprio cadastro e o da pessoa que lidera", pes.data);
check(negado(await lider.from("perfis").update({ perfil: "MASTER" }).eq("id", ll.data.user.id)), "não altera perfil direto na tabela");
check((await lider.from("auditoria").select("id")).data?.length === 0, "tabela de auditoria aparece vazia para ela (RLS)");

console.log("\n6. VOLUNTÁRIO");
let { c: vol, r: lv } = await entrar("vitor.vol@teste.com", apVitor.data.senha_temporaria);
await vol.auth.updateUser({ password: "Vitor-Senha-Nova-01" });
const pv = (await vol.rpc("meu_painel")).data;
check(pv.status === "ok" && pv.perfil === "VOLUNTARIO", "painel de VOLUNTÁRIO", pv);
const ev = (await vol.rpc("minha_equipe")).data;
check(ev.length === 1 && ev[0].membros.every((m) => !m.telefone && !m.email), "vê a própria equipe sem contatos");
check(negado(await vol.rpc("listar_usuarios")) && negado(await vol.rpc("listar_auditoria", {})), "não acessa usuários nem histórico");
check((await vol.from("pessoas").select("nome")).data?.length === 1, "lê só o próprio cadastro");

console.log("\n7. Recuperação de senha");
await vol.auth.resetPasswordForEmail("vitor.vol@teste.com", { redirectTo: URL_ + "/?redefinir=1" });
await novo().auth.resetPasswordForEmail("ninguem@teste.com", { redirectTo: URL_ + "/?redefinir=1" });
const caixa = await (await fetch(URL_ + "/_dev/caixa")).json();
const link = caixa.filter((m) => m.para === "vitor.vol@teste.com").pop()?.link;
check(!!link && caixa.every((m) => m.para !== "ninguem@teste.com"), "e-mail com link só para conta existente (resposta igual para os dois)");
const red = await fetch(link, { redirect: "manual" });
const hash = new URLSearchParams(red.headers.get("location").split("#")[1]);
check(hash.get("type") === "recovery", "link de recuperação abre sessão temporária");
const rec = novo(); await rec.auth.setSession({ access_token: hash.get("access_token"), refresh_token: hash.get("refresh_token") });
check(!(await rec.auth.updateUser({ password: "Vitor-Recuperada-02" })).error, "define nova senha pelo link");
check(!!(await novo().auth.signInWithPassword({ email: "vitor.vol@teste.com", password: "Vitor-Senha-Nova-01" })).error, "senha antiga deixa de valer");
({ c: vol } = await entrar("vitor.vol@teste.com", "Vitor-Recuperada-02"));
check((await vol.rpc("meu_painel")).data.status === "ok", "entra com a nova senha");
const linkReuso = await fetch(link, { redirect: "manual" });
check(/error=/.test(linkReuso.headers.get("location")), "o mesmo link não funciona duas vezes");

console.log("\n8. MASTER — gestão de usuários");
const us = (await master.rpc("listar_usuarios")).data;
const uVitor = us.find((u) => u.email === "vitor.vol@teste.com"), uRonald = us.find((u) => u.email === "master2@exemplo.com"), uEu = us.find((u) => u.eu);
check(us.length === 4, "lista os 4 usuários", us.length);
const nt = await fn(master, "admin-usuarios", { acao: "senha_temporaria", usuario_id: uVitor.id });
check(nt.data?.senha_temporaria, "gera nova senha temporária");
check(!!(await novo().auth.signInWithPassword({ email: "vitor.vol@teste.com", password: "Vitor-Recuperada-02" })).error, "a senha anterior deixa de valer");
({ c: vol } = await entrar("vitor.vol@teste.com", nt.data.senha_temporaria));
check((await vol.rpc("meu_painel")).data.status === "trocar_senha", "volta a exigir troca no próximo acesso");
await vol.auth.updateUser({ password: "Vitor-Senha-Nova-03" });
check((await fn(master, "admin-usuarios", { acao: "definir_ativo", usuario_id: uVitor.id, ativo: false })).data?.ok, "desativa o voluntário");
check((await vol.rpc("meu_painel")).data.status === "inativo", "sessão aberta passa a ver 'inativo'");
check(negado(await vol.rpc("minha_equipe")), "sessão aberta perde acesso aos dados");
const banLogin = await novo().auth.signInWithPassword({ email: "vitor.vol@teste.com", password: "Vitor-Senha-Nova-03" });
check(banLogin.error?.code === "user_banned", "não consegue entrar de novo", banLogin.error);
check((await fn(master, "admin-usuarios", { acao: "definir_ativo", usuario_id: uVitor.id, ativo: true })).data?.ok, "reativa");
check(!(await novo().auth.signInWithPassword({ email: "vitor.vol@teste.com", password: "Vitor-Senha-Nova-03" })).error, "entra de novo depois de reativado");
check((await fn(master, "admin-usuarios", { acao: "definir_ativo", usuario_id: uEu.id, ativo: false })).status === 409, "MASTER não desativa a si mesmo");
check(!(await master.rpc("admin_atualizar_usuario", { p_usuario: uRonald.id, p_perfil: "VOLUNTARIO", p_atribuicoes: [], p_ministerios: [] })).error, "altera o perfil de outro MASTER");
const ultimo = await master.rpc("admin_atualizar_usuario", { p_usuario: uEu.id, p_perfil: "VOLUNTARIO", p_atribuicoes: [], p_ministerios: [] });
check(/último MASTER/.test(ultimo.error?.message || ""), "não remove o último MASTER ativo", ultimo.error);
await master.rpc("admin_atualizar_usuario", { p_usuario: uRonald.id, p_perfil: "MASTER", p_atribuicoes: [], p_ministerios: [{ ministerio_id: midia, funcao: "voluntario" }] });
const atr = await master.rpc("admin_atualizar_usuario", { p_usuario: uVitor.id, p_perfil: "VOLUNTARIO", p_atribuicoes: ["SECRETARIA"], p_ministerios: [{ ministerio_id: juv, funcao: "voluntario" }, { ministerio_id: louvor, funcao: "voluntario" }] });
check(!atr.error && (await vol.rpc("meu_painel")).data?.atribuicoes?.includes("SECRETARIA"), "concede atribuição SECRETARIA e novo ministério");
const cria = await fn(master, "admin-usuarios", { acao: "criar", nome: "Elaine Teste Fraga", telefone: "31992997440", email: "elaine.teste@teste.com", perfil: "LIDER", atribuicoes: ["SECRETARIA"], ministerios: [{ ministerio_id: mins.data.find((m) => m.nome === "Secretaria").id, funcao: "lider" }] });
check(cria.data?.ok && cria.data.senha_temporaria, "cria usuário direto (sem solicitação), com senha temporária", cria);
check((await fn(master, "admin-usuarios", { acao: "criar", nome: "Elaine Teste Fraga", telefone: "31992997440", email: "elaine.teste@teste.com", perfil: "VOLUNTARIO", ministerios: [] })).status === 409, "não cria conta duplicada com o mesmo e-mail");

console.log("\n9. MASTER — ministérios");
const nm = await master.rpc("admin_salvar_ministerio", { p_id: null, p_nome: "Teatro", p_descricao: "Ministério de artes cênicas", p_ordem: 13, p_ativo: true });
check(!nm.error, "cria ministério");
check(/Já existe/.test((await master.rpc("admin_salvar_ministerio", { p_id: null, p_nome: "Teatro", p_descricao: "", p_ordem: 14, p_ativo: true })).error?.message || ""), "não duplica nome de ministério");
check(!(await master.rpc("admin_salvar_ministerio", { p_id: nm.data.id, p_nome: "Teatro", p_descricao: "", p_ordem: 13, p_ativo: false })).error, "desativa ministério");
check(!(await novo().from("ministerios").select("nome")).data.some((m) => m.nome === "Teatro"), "ministério inativo some da lista pública");
check((await master.from("ministerios").select("nome")).data.some((m) => m.nome === "Teatro"), "MASTER continua vendo o ministério inativo");

console.log("\n10. Histórico administrativo");
const hist = (await master.rpc("listar_auditoria", { p_limite: 500 })).data;
const acoes = new Set(hist.map((a) => a.acao));
check(["usuario_criado", "solicitacao_aprovada", "senha_temporaria_gerada"].every((a) => acoes.has(a)), "registra criação, aprovação e senha temporária");
check(hist.some((a) => a.tabela === "solicitacoes" && a.depois?.status === "recusada" && a.ator.startsWith("Primeiro")), "registra a recusa com o nome de quem recusou");
check(hist.some((a) => a.tabela === "perfis" && a.antes?.ativo === true && a.depois?.ativo === false), "registra a desativação");
check(hist.some((a) => a.tabela === "perfis" && a.antes?.deve_trocar_senha && !a.depois?.deve_trocar_senha), "registra a troca da senha temporária");
check(hist.every((a) => !JSON.stringify(a).includes("encrypted_password")) && !JSON.stringify(hist).includes(apLia.data.senha_temporaria), "nenhuma senha (nem hash) aparece no histórico");

console.log(`\nResultado: ${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
