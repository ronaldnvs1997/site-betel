// Etapa 2 — Agenda Ministerial integrada: testes do backend (RLS, gatilhos, conflitos, lotes,
// bloqueio de fichas, coordenadores) com chamadas diretas à API, como um atacante faria.
import { createClient } from "@supabase/supabase-js";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import { prepararVoluntario } from "./apoio-termos.mjs";

const URL_ = process.env.SUPABASE_URL, ANON = process.env.SUPABASE_ANON_KEY;
const novo = () => createClient(URL_, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
let ok = 0, falhas = 0;
const check = (c, n, x) => { if (c) { ok++; console.log("  ✓ " + n); } else { falhas++; console.log("  ✗ " + n + (x !== undefined ? "  → " + JSON.stringify(x) : "")); } };
const vazio = (r) => !r.error && Array.isArray(r.data) && r.data.length === 0;           // RLS: nada afetado
const bloqueado = (r) => !!r.error || vazio(r);
async function fn(cli, nome, corpo) { const { data, error } = await cli.functions.invoke(nome, { body: corpo }); if (error) { let j = {}; try { j = await error.context.json(); } catch (_) {} return { erro: j.erro }; } return data; }
async function entrar(email, senha, nova) {
  const c = novo(); const r = await c.auth.signInWithPassword({ email, password: senha });
  if (r.error) throw new Error(email + ": " + r.error.message);
  if (nova) await c.auth.updateUser({ password: nova });
  return c;
}

console.log("\n0. Preparação: contas da equipe");
const saida = execFileSync("node", ["../scripts/criar-primeiros-masters.mjs", "Primeiro Master Teste|master1@exemplo.com|31900000001"], { env: process.env }).toString();
const tempM = saida.match(/senha temporária: (\S+)/)[1];
const master = await entrar("master1@exemplo.com", tempM, "Ezequiel-Nova-2026");
const mins = (await novo().from("ministerios").select("id,nome")).data;
const mid = (n) => mins.find((m) => m.nome === n).id;
const contas = {};
for (const [n, e] of [["Carla Coordenadora", "carla@teste.com"], ["Vitor Voluntário", "vitor@teste.com"]]) await prepararVoluntario(n, e, "31999990000");
for (const [chave, nome, email, perfil, vinc] of [
  ["carla", "Carla Coordenadora", "carla@teste.com", "VOLUNTARIO", [{ ministerio_id: mid("Mídia"), funcao: "voluntario" }]],
  ["lia", "Lia Líder Juventude", "lia@teste.com", "LIDER", [{ ministerio_id: mid("Juventude Mergulhados"), funcao: "lider" }]],
  ["luan", "Luan Líder Louvor", "luan@teste.com", "LIDER", [{ ministerio_id: mid("Louvor"), funcao: "lider" }]],
  ["vitor", "Vitor Voluntário", "vitor@teste.com", "VOLUNTARIO", [{ ministerio_id: mid("Juventude Mergulhados"), funcao: "voluntario" }]],
]) {
  const r = await fn(master, "admin-usuarios", { acao: "criar", nome, telefone: "31999990000", email, perfil, atribuicoes: [], ministerios: vinc });
  contas[chave] = { id: r.usuario_id, email, temp: r.senha_temporaria };
}
const carla = await entrar("carla@teste.com", contas.carla.temp, "Carla-Nova-2026");
const lia = await entrar("lia@teste.com", contas.lia.temp, "Lia-Nova-20261");
const luan = await entrar("luan@teste.com", contas.luan.temp, "Luan-Nova-20261");
const vitor = await entrar("vitor@teste.com", contas.vitor.temp, "Vitor-Nova-2026");
fs.writeFileSync("/tmp/agenda-contas.json", JSON.stringify({ master: "Ezequiel-Nova-2026", carla: "Carla-Nova-2026", lia: "Lia-Nova-20261", luan: "Luan-Nova-20261", vitor: "Vitor-Nova-2026" }));
check(Object.keys(contas).length === 4, "contas criadas: coordenadora, 2 líderes e 1 voluntário");

console.log("\n1. Visitante sem login (chave pública)");
const anon = novo();
const ev0 = await anon.from("eventos").select("*").order("data");
const rs0 = await anon.from("reservas").select("*").order("data");
check(ev0.data?.length === 5 && rs0.data?.length === 4, "continua lendo a agenda pública (5 eventos, 4 reservas)");
const culto = ev0.data.find((e) => e.titulo === "CULTO DE JOVENS"), ensaio = ev0.data.find((e) => e.titulo === "ENSAIO GERAL DE NATAL");
const conferencia = ev0.data.find((e) => e.titulo === "CONFERÊNCIA MERGULHADOS"), cafe = ev0.data.find((e) => e.titulo === "CAFÉ DAS MULHERES");
check(bloqueado(await anon.from("coordenadores").select("id, nome, login").eq("login", "coord").eq("senha", "senha-legada-1")), "o ataque do login antigo (ler coordenadores com a senha) não funciona mais");
check(bloqueado(await anon.from("coordenadores").select("senha")), "a coluna senha não é lida por ninguém de fora");
check(bloqueado(await anon.from("eventos").insert([{ titulo: "INVASÃO", data: "2026-12-30" }])), "não cria evento");
check(bloqueado(await anon.from("eventos").update({ titulo: "ALTERADO" }).eq("id", culto.id).select("id")), "não altera evento");
check(bloqueado(await anon.from("eventos").delete().eq("id", culto.id).select("id")), "não exclui evento");
check(bloqueado(await anon.from("reservas").delete().eq("lote_id", "LOTE-1700000000000").select("id")), "não exclui lote de reservas");
check(bloqueado(await anon.from("coordenadores").insert([{ nome: "X", login: "x", senha: "x", ativo: true }])), "não cria coordenador");
check(bloqueado(await anon.rpc("agenda_listar_coordenadores")), "não lista coordenadores");

console.log("\n2. MASTER — coordenadores no login central");
let lc = (await master.rpc("agenda_listar_coordenadores")).data;
check(lc.length === 2 && lc.every((c) => !("senha" in c) && !c.usuario_id), "lista os 2 coordenadores antigos, sem senha e ainda sem conta ligada", lc);
check(bloqueado(await master.from("coordenadores").select("senha")), "nem o MASTER lê a coluna senha pela API");
const antigo = lc.find((c) => c.login === "coord");
check(!(await master.rpc("agenda_vincular_coordenador", { p_coordenador: antigo.id, p_usuario: contas.carla.id })).error, "liga o coordenador antigo 'coord' à conta da Carla");
check((await carla.rpc("agenda_minhas_permissoes")).data.coordenador === true, "Carla passa a ser coordenadora entrando com a conta dela");
check(bloqueado(await lia.rpc("agenda_vincular_coordenador", { p_coordenador: antigo.id, p_usuario: contas.lia.id })), "líder não se torna coordenadora sozinha");
check(bloqueado(await carla.rpc("agenda_definir_coordenador", { p_usuario: contas.vitor.id })), "coordenadora não cria coordenadores (só o MASTER)");
check((await master.rpc("agenda_minhas_permissoes")).data.coordenador === true, "MASTER tem acesso de coordenação");

console.log("\n3. Coordenação — eventos");
const novoEv = await carla.from("eventos").insert([{ titulo: "TESTE BACKEND", data: "2026-12-08", ministerio: "Juventude" }]).select("*");
check(!novoEv.error && novoEv.data[0].ministerio_id === mid("Juventude Mergulhados") && novoEv.data[0].criado_por === contas.carla.id, "cria evento; ministério ligado pelo nome e autoria registrada", novoEv.error || novoEv.data);
const idNovo = novoEv.data[0].id;
check(!(await carla.from("eventos").update({ horario: "18:00 às 20:00", horario_inicio: "18:00", horario_fim: "20:00", local: "Quadra" }).eq("id", idNovo).select("id")).error, "preenche horário e local");
check(!(await carla.from("eventos").update({ data: "2026-12-09" }).eq("id", idNovo).select("id")).error, "move o evento para outra data");
check(!(await carla.from("eventos").update({ bloqueado: true }).eq("id", idNovo).select("id")).error, "tranca a ficha");
check(!(await carla.from("eventos").update({ bloqueado: false }).eq("id", idNovo).select("id")).error, "destranca a ficha");

console.log("\n4. Conflitos de espaço e horário (no banco)");
let r = await carla.from("reservas").insert([{ ministerio: "Kids", motivo: "Teste", espacos: "Templo", data: "2026-12-05", horario_inicio: "20:00", horario_fim: "21:00", lote_id: null }]).select("id");
const det = (() => { try { return JSON.parse(r.error?.details || "[]"); } catch (_) { return []; } })();
check(r.error?.code === "23P01" && det[0]?.tipo === "Evento Oficial" && det[0]?.titulo === "CULTO DE JOVENS", "reserva sobre o Culto de Jovens é recusada, com o conflito descrito", r.error);
r = await carla.from("reservas").insert([{ ministerio: "Kids", motivo: "Teste", espacos: "Templo", data: "2026-12-05", horario_inicio: "21:30", horario_fim: "22:30", lote_id: null }]).select("id");
check(!r.error, "horário encostado (21:30, quando o culto termina) é permitido, como na Agenda original", r.error);
r = await carla.from("reservas").insert([{ ministerio: "Kids", motivo: "Teste", espacos: "Quadra", data: "2026-12-05", horario_inicio: "19:30", horario_fim: "21:30", lote_id: null }]).select("id");
check(!r.error, "mesmo horário em outro espaço (Quadra) é permitido", r.error);
r = await carla.from("reservas").insert([{ ministerio: "Kids", motivo: "Teste", espacos: "Salão de Festas", data: "2026-12-12", horario_inicio: "20:00", horario_fim: "21:00", lote_id: null }]).select("id");
check(r.error?.code === "23P01", "detecta conflito com evento antigo que só tem o texto '19h às 22h'", r.error);
r = await carla.from("eventos").update({ local: "Templo", horario_inicio: "19:00", horario_fim: "20:00", horario: "19:00 às 20:00", data: "2026-12-03" }).eq("id", idNovo).select("id");
check(r.error?.code === "23P01", "evento não pode ser movido para cima de uma reserva (ensaio do Louvor no Templo)", r.error);
r = await carla.from("reservas").insert([{ ministerio: "Kids", motivo: "Teste", espacos: "Templo", data: "2026-12-14", horario_inicio: "21:00", horario_fim: "20:00", lote_id: null }]).select("id");
check(/término/.test(r.error?.message || ""), "horário de término antes do início é recusado no banco");
const [p1, p2] = await Promise.all([1, 2].map(() => carla.from("reservas").insert([{ ministerio: "Kids", motivo: "Simultânea", espacos: "Templo", data: "2026-12-21", horario_inicio: "10:00", horario_fim: "11:00", lote_id: null }]).select("id")));
check([p1, p2].filter((x) => !x.error).length === 1 && [p1, p2].some((x) => x.error?.code === "23P01"), "duas reservas iguais ao mesmo tempo: só uma entra");

console.log("\n5. Reservas recorrentes (lotes)");
const datas = ["2026-12-03", "2026-12-10", "2026-12-17", "2026-12-24", "2026-12-31"];
r = await carla.from("reservas").insert(datas.map((d) => ({ ministerio: "Intercessão", motivo: "Oração", espacos: "Templo", data: d, horario_inicio: "07:00", horario_fim: "08:00", lote_id: "LOTE-TESTE-1" }))).select("id");
check(!r.error && r.data.length === 5, "cria série de 5 quintas-feiras no mesmo lote", r.error);
r = await carla.from("reservas").insert(datas.map((d) => ({ ministerio: "Louvor", motivo: "Ensaio extra", espacos: "Templo", data: d, horario_inicio: "20:00", horario_fim: "20:30", lote_id: "LOTE-TESTE-2" }))).select("id");
check(r.error?.code === "23P01", "série em que uma data conflita é recusada");
check((await anon.from("reservas").select("id").eq("lote_id", "LOTE-TESTE-2")).data.length === 0, "nada da série recusada fica gravado (tudo ou nada)");
const lote = (await anon.from("reservas").select("id,data").eq("lote_id", "LOTE-TESTE-1")).data;
check(!(await carla.from("reservas").delete().eq("id", lote[0].id).select("id")).error, "exclui uma data da série");
check((await anon.from("reservas").select("id").eq("lote_id", "LOTE-TESTE-1")).data.length === 4, "as outras 4 datas continuam");
r = await carla.from("reservas").delete().eq("lote_id", "LOTE-TESTE-1").select("id");
check(!r.error && r.data.length === 4, "exclui a série inteira pelo lote");

console.log("\n6. Líder — ficha oficial do próprio ministério");
check(!(await lia.from("eventos").update({ lider: "Lia", observacoes: "Ficha pela líder", necessita_midia: "Sim", midia_tema: "Natal" }).eq("id", culto.id).select("id")).error, "líder da Juventude preenche a ficha do Culto de Jovens");
check(vazio(await lia.from("eventos").update({ lider: "Lia" }).eq("id", ensaio.id).select("id")), "não altera a ficha de evento do Louvor");
check(!(await luan.from("eventos").update({ observacoes: "Ok do Louvor" }).eq("id", ensaio.id).select("id")).error, "o líder do Louvor altera a ficha do Louvor");
r = await lia.from("eventos").update({ data: "2026-12-06" }).eq("id", culto.id).select("id");
check(r.error?.code === "42501", "líder não muda a data do evento (só a coordenação)", r.error);
check(!!(await lia.from("eventos").update({ bloqueado: true }).eq("id", culto.id).select("id")).error, "líder não tranca a ficha");
check(bloqueado(await lia.from("eventos").insert([{ titulo: "EVENTO DA LÍDER", data: "2026-12-27", ministerio: "Juventude Mergulhados" }])), "líder não cria evento");
check(bloqueado(await lia.from("eventos").delete().eq("id", culto.id).select("id")), "líder não exclui evento");
check(bloqueado(await lia.from("reservas").insert([{ ministerio: "Juventude", motivo: "x", espacos: "Quadra", data: "2026-12-28", horario_inicio: "10:00", horario_fim: "11:00" }])), "líder não reserva espaço");
await carla.from("eventos").update({ bloqueado: true }).eq("id", culto.id);
r = await lia.from("eventos").update({ observacoes: "Tentando editar trancada" }).eq("id", culto.id).select("id");
check(/bloqueada/.test(r.error?.message || ""), "ficha trancada: líder não altera o planejamento", r.error);
check(!(await lia.from("eventos").update({ link_fotos: "https://fotos.exemplo/culto", link_videos: "https://videos.exemplo/culto" }).eq("id", culto.id).select("id")).error, "ficha trancada: líder ainda registra fotos e vídeos");
r = await lia.from("eventos").update({ observacoes: "Depois do evento" }).eq("id", conferencia.id).select("id");
check(/bloqueada/.test(r.error?.message || ""), "evento que já passou: líder não altera o planejamento");
check(!(await lia.from("eventos").update({ link_fotos: "https://fotos.exemplo/conf" }).eq("id", conferencia.id).select("id")).error, "evento que já passou: fotos e vídeos liberados");
check(!(await carla.from("eventos").update({ observacoes: "Ajuste da coordenação" }).eq("id", cafe.id).select("id")).error, "coordenação edita mesmo com a ficha trancada");
r = await lia.from("eventos").update({ link_fotos: "javascript:alert(1)" }).eq("id", culto.id).select("link_fotos");
check(!r.error, "texto salvo como dado (a tela só abre links http/https)");

console.log("\n7. Voluntário e conta desativada");
check(vazio(await vitor.from("eventos").update({ lider: "Vitor" }).eq("id", culto.id).select("id")), "voluntário não altera fichas");
check(bloqueado(await vitor.from("reservas").insert([{ ministerio: "Kids", motivo: "x", espacos: "Quadra", data: "2026-12-29", horario_inicio: "10:00", horario_fim: "11:00" }])), "voluntário não reserva");
await master.rpc("agenda_status_coordenador", { p_coordenador: antigo.id, p_ativo: false });
check((await carla.rpc("agenda_minhas_permissoes")).data.coordenador === false, "coordenador desativado pelo MASTER perde a coordenação na hora");
check(bloqueado(await carla.from("eventos").insert([{ titulo: "DEPOIS DE DESATIVADA", data: "2026-12-30" }])), "e não cria mais eventos");
await master.rpc("agenda_status_coordenador", { p_coordenador: antigo.id, p_ativo: true });
check(!(await master.rpc("agenda_definir_coordenador", { p_usuario: contas.luan.id })).error, "MASTER torna um líder coordenador");
check((await luan.rpc("agenda_minhas_permissoes")).data.coordenador === true, "o novo coordenador já tem acesso");
lc = (await master.rpc("agenda_listar_coordenadores")).data;
check(lc.length === 3 && lc.some((c) => c.login === "antigo" && !c.ativo), "coordenador antigo inativo continua registrado (nada excluído)");

console.log("\n8. Exclusão de evento e histórico");
check(!(await carla.from("eventos").delete().eq("id", idNovo).select("id")).error, "coordenação exclui o evento de teste");
const hist = (await master.rpc("listar_auditoria", { p_limite: 500 })).data;
const exclusao = hist.find((a) => a.tabela === "eventos" && a.acao === "delete" && a.antes?.titulo === "TESTE BACKEND");
check(exclusao && exclusao.ator.startsWith("Carla"), "a exclusão fica no histórico, com os dados do evento e quem excluiu");
check(hist.some((a) => a.tabela === "reservas" && a.acao === "delete" && a.antes?.lote_id === "LOTE-TESTE-1"), "exclusão do lote registrada data a data");
check(!JSON.stringify(hist).includes("senha-legada"), "nenhuma senha antiga aparece no histórico");

console.log(`\nResultado: ${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
