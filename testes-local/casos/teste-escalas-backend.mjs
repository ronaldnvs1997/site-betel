// Etapa 7 — Mídia: solicitações, escalas, confirmação individual, substituição, prazos, Agenda, presença e histórico (backend).
import { createClient } from "@supabase/supabase-js";
import { execFileSync } from "node:child_process";
import pg from "pg";
import { prepararVoluntario } from "./apoio-termos.mjs";

const URL_ = process.env.SUPABASE_URL, ANON = process.env.SUPABASE_ANON_KEY;
const novo = () => createClient(URL_, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
let ok = 0, falhas = 0;
const check = (c, n, x) => { if (c) { ok++; console.log("  ✓ " + n); } else { falhas++; console.log("  ✗ " + n + (x !== undefined ? "  → " + JSON.stringify(x).slice(0, 400) : "")); } };
const negado = (r) => !!r.error && ["42501", "PGRST301"].includes(r.error.code);
const erro = (r, re) => !!r.error && re.test(r.error.message);
const sql = async (q, v) => { const c = new pg.Client({ host: "/tmp", port: 5434, user: "postgres", database: "betel" }); await c.connect(); try { return (await c.query(q, v)).rows; } finally { await c.end(); } };
const sqlErro = async (q, v) => { try { await sql(q, v); return ""; } catch (e) { return e.message; } };
async function entrar(email, senha, nova) { const c = novo(); const r = await c.auth.signInWithPassword({ email, password: senha }); if (r.error) throw new Error(email + ": " + r.error.message); if (nova) await c.auth.updateUser({ password: nova }); return c; }
const quando = (dias, hh, mm = 0) => { const d = new Date(Date.now() + dias * 864e5); const s = d.toLocaleDateString("sv-SE", { timeZone: "America/Sao_Paulo" }); return `${s}T${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}:00-03:00`; };
const anon = novo();
const avisos = async (c) => (await c.rpc("minhas_notificacoes", { p_limite: 300 })).data.itens;

console.log("\n0. Contas, equipe de Mídia e habilitações");
const saida = execFileSync("node", ["../scripts/criar-primeiros-masters.mjs", "Primeiro Master Teste|master1@exemplo.com|31900000001"], { env: process.env }).toString();
const master = await entrar("master1@exemplo.com", saida.match(/senha temporária: (\S+)/)[1], "Ezequiel-Nova-2026");
const mins = (await anon.from("ministerios").select("id,nome")).data, mid = (n) => mins.find((m) => m.nome === n).id;
const MIDIA = mid("Mídia");
async function conta(nome, email, perfil, mm, senha) {
  if (mm.some((x) => x.funcao === "voluntario")) await prepararVoluntario(nome, email, "31999990000");
  const r = (await master.functions.invoke("admin-usuarios", { body: { acao: "criar", nome, telefone: "31999990000", email, perfil, atribuicoes: [], ministerios: mm } })).data;
  if (!r?.senha_temporaria) throw new Error("conta " + email + " " + JSON.stringify(r));
  return entrar(email, r.senha_temporaria, senha);
}
const lia = await conta("Lia Lider Midia", "lia@teste.com", "LIDER", [{ ministerio_id: MIDIA, funcao: "lider" }], "Lia-Nova-20261");
const luan = await conta("Luan Lider Louvor", "luan@teste.com", "LIDER", [{ ministerio_id: mid("Louvor"), funcao: "lider" }], "Luan-Nova-20261");
const V = {};
for (const [k, nome] of [["vitor", "Vitor Fotografo"], ["vera", "Vera Fotografa"], ["vanda", "Vanda Fotografa"], ["davi", "Davi Fotografo"], ["gil", "Gil Projecao"],
  ["paula", "Paula Projecao"], ["sergio", "Sergio Som"], ["sara", "Sara Som"], ["tina", "Tina Treinamento"]])
  V[k] = await conta(nome + " Teste", `${k}@teste.com`, "VOLUNTARIO", [{ ministerio_id: MIDIA, funcao: "voluntario" }], `${k[0].toUpperCase()}${k.slice(1)}-Nova-2026`);
// integrante sem conta
await prepararVoluntario("Nina Sem Conta", "nina@teste.com", "31999990000");
await sql("insert into ministerio_membros (pessoa_id, ministerio_id, funcao) select id, $1, 'voluntario' from pessoas where email = 'nina@teste.com'", [MIDIA]);
const pid = async (k) => (await sql("select id from pessoas where email = $1", [`${k}@teste.com`]))[0].id;
const P = {}; for (const k of [...Object.keys(V), "nina"]) P[k] = await pid(k);
let cat = (await lia.rpc("midia_catalogo", {})).data;
const fn = (nome) => cat.areas.flatMap((a) => a.funcoes).find((f) => f.nome === nome).id;
const sv = (nome) => cat.servicos.find((s) => s.nome.startsWith(nome)).id;
check(cat.areas.length === 6 && cat.areas.flatMap((a) => a.funcoes).length === 18 && cat.servicos.length === 11, "catálogo inicial: 6 equipes, 18 funções e 11 serviços (sugestões editáveis)");
const hab = (k, f, st = "habilitado") => lia.rpc("midia_habilitar", { p_pessoa: P[k], p_funcao: fn(f), p_status: st, p_observacao: null });
for (const k of ["vitor", "vera", "vanda", "davi"]) await hab(k, "Fotógrafo");
for (const k of ["gil", "paula"]) await hab(k, "Operador de projeção");
for (const k of ["sergio", "sara"]) await hab(k, "Operador de som");
await hab("vitor", "Videomaker"); await hab("davi", "Videomaker"); await hab("vera", "Responsável pelos Stories"); await hab("gil", "Operador de transmissão"); await hab("paula", "Operador de transmissão");
await hab("tina", "Fotógrafo", "em_treinamento"); await hab("nina", "Fotógrafo");
check(negado(await V.vitor.rpc("midia_habilitar", { p_pessoa: P.vitor, p_funcao: fn("Diretor da Live"), p_status: "habilitado", p_observacao: null })), "voluntário não se habilita sozinho");
check(!(await lia.rpc("midia_registrar_capacitacao", { p_pessoa: P.tina, p_funcao: fn("Fotógrafo"), p_titulo: "Oficina de fotografia em eventos", p_data: "2026-10-10", p_carga: "8h", p_observacao: null })).error, "capacitação registrada");
check(!(await lia.rpc("midia_salvar_catalogo", { p_tipo: "servico", p: { nome: "Cobertura de batismo", descricao: "Serviço criado pelo líder" } })).error, "o líder cadastra um serviço novo");
check(negado(await luan.rpc("midia_salvar_catalogo", { p_tipo: "servico", p: { nome: "Outro" } })), "líder de outro ministério não mexe no catálogo da Mídia");

console.log("\n1. Permissões");
check(negado(await anon.rpc("midia_painel", { p_filtros: {} })) && negado(await V.vitor.rpc("midia_painel", { p_filtros: {} })) && negado(await luan.rpc("midia_painel", { p_filtros: {} })), "visitante, voluntário e líder de outro ministério não abrem o painel da Mídia");
for (const t of ["apoio_solicitacoes", "escala_eventos", "escala_participacoes", "escala_historico", "voluntario_habilitacoes", "voluntario_disponibilidade"])
  check(negado(await lia.from(t).select("*")), `ninguém lê ${t} diretamente`);

console.log("\n2. Solicitação de cobertura");
const solBase = { ministerio_solicitante: mid("Louvor"), responsavel_nome: "Luan Lider Louvor", responsavel_contato: "31999990000", titulo: "Noite de Louvor", tipo_evento: "programacao_especial",
  inicio: quando(10, 19, 30), fim: quando(10, 22, 0), local: "Templo", objetivo: "Registrar a noite", descricao: "Gravação de duas músicas", prazo_retorno: quando(5, 0).slice(0, 10) };
check(negado(await luan.rpc("apoio_solicitar", { p: { ...solBase, ministerio_solicitante: mid("Kids"), servicos: [{ servico_id: sv("Fotografia") }] } })), "só pede pelo próprio ministério");
check(erro(await luan.rpc("apoio_solicitar", { p: { ...solBase, servicos: [] } }), /ao menos um serviço/), "é preciso marcar ao menos um serviço");
let r = await luan.rpc("apoio_solicitar", { p: { ...solBase, servicos: [{ servico_id: sv("Fotografia"), detalhe: "Fotos da banda" }, { servico_id: sv("Transmissão"), detalhe: "Live no YouTube" }, { servico_id: sv("Filmagem"), detalhe: "Duas músicas" }] } });
const SOL = r.data?.id;
check(SOL && r.data.servicos === 3, "Louvor pede Fotografia, Live e Filmagem, explicando cada uma");
check(!(await sql("select count(*)::int n from escala_eventos"))[0].n, "REGRA: o envio não cria escala");
check((await avisos(lia)).some((n) => n.tipo === "apoio_nova"), "a liderança de Mídia é avisada");
check(negado(await V.vitor.rpc("apoio_mensagem", { p_solicitacao: SOL, p_tipo: "mensagem", p_texto: "oi" })), "voluntário não participa da conversa da solicitação");
await lia.rpc("apoio_mensagem", { p_solicitacao: SOL, p_tipo: "pedido_informacao", p_texto: "A Live é no YouTube da igreja ou do Louvor?" });
await lia.rpc("apoio_mensagem", { p_solicitacao: SOL, p_tipo: "nota_interna", p_texto: "Temos só 2 operadores de transmissão." });
let minhas = (await luan.rpc("apoio_minhas_solicitacoes")).data.solicitacoes;
check(minhas[0].status === "aguardando_informacoes" && (await avisos(luan)).some((n) => n.tipo === "apoio_informacoes"), "pedido de informações: status atualizado e solicitante avisado");
check(!minhas[0].mensagens.some((m) => m.tipo === "nota_interna"), "nota interna não aparece para o solicitante");
check(negado(await luan.rpc("apoio_mensagem", { p_solicitacao: SOL, p_tipo: "nota_interna", p_texto: "teste" })), "solicitante não escreve nota interna");
await luan.rpc("apoio_mensagem", { p_solicitacao: SOL, p_tipo: "resposta", p_texto: "No YouTube da igreja." });
check((await lia.rpc("midia_solicitacoes", { p_filtros: {} })).data[0].status === "em_analise", "com a resposta, volta para \"em análise\"");
check(erro(await lia.rpc("midia_decidir_servico", { p_solicitacao: SOL, p_servico: sv("Transmissão"), p_decisao: "nao_atender", p_detalhe: null, p_motivo: "" }), /Explique/), "retirar um serviço exige motivo");
await lia.rpc("midia_decidir_servico", { p_solicitacao: SOL, p_servico: sv("Transmissão"), p_decisao: "nao_atender", p_detalhe: null, p_motivo: "Não há operadores livres nessa data" });
await lia.rpc("midia_decidir_servico", { p_solicitacao: SOL, p_servico: sv("Produção de Stories"), p_decisao: "acrescentar", p_detalhe: "Stories dos bastidores", p_motivo: "Divulgar a noite" });
check(negado(await V.gil.rpc("midia_decidir_solicitacao", { p_solicitacao: SOL, p_acao: "aprovar", p_motivo: null })), "voluntário não decide solicitação");
r = await lia.rpc("midia_decidir_solicitacao", { p_solicitacao: SOL, p_acao: "aprovar", p_motivo: "Atendemos fotografia, filmagem e Stories" });
check(r.data?.status === "aprovada_parcial", "aprovação parcial (Live retirada, Stories acrescentado)");
minhas = (await luan.rpc("apoio_minhas_solicitacoes")).data.solicitacoes[0];
check(minhas.servicos.find((s) => s.nome.startsWith("Transmissão")).motivo.includes("operadores") && minhas.servicos.some((s) => s.origem === "acrescentado") && (await avisos(luan)).some((n) => n.tipo === "apoio_decisao"), "o solicitante vê o que foi atendido, o motivo e o serviço acrescentado");
const sol2 = (await luan.rpc("apoio_solicitar", { p: { ...solBase, titulo: "Ensaio aberto", servicos: [{ servico_id: sv("Fotografia") }] } })).data.id;
check(erro(await lia.rpc("midia_decidir_solicitacao", { p_solicitacao: sol2, p_acao: "recusar", p_motivo: "" }), /motivo/) && !(await lia.rpc("midia_decidir_solicitacao", { p_solicitacao: sol2, p_acao: "recusar", p_motivo: "Ensaio sem necessidade de cobertura" })).error, "recusa exige motivo");

console.log("\n3. Integração com a Agenda");
const evCulto = (await sql("select id from eventos where titulo = 'CULTO DE JOVENS'"))[0].id;
r = await luan.rpc("apoio_solicitar", { p: { ministerio_solicitante: mid("Louvor"), responsavel_nome: "Luan Lider Louvor", evento_id: evCulto, tipo_evento: "culto", servicos: [{ servico_id: sv("Projeção") }, { servico_id: sv("Sonoplastia") }] } });
const solAg = (await lia.rpc("midia_solicitacoes", { p_filtros: {} })).data.find((s) => s.id === r.data.id);
check(solAg.titulo === "CULTO DE JOVENS" && solAg.local === "Templo" && new Date(solAg.inicio).toISOString() === "2026-12-05T22:30:00.000Z", "solicitação ligada ao evento da Agenda: título, data, horário e local vêm de lá");
check((await sql("select count(*)::int n from eventos"))[0].n === 5, "nenhum evento novo é criado na Agenda");
const pend = (await lia.rpc("midia_agenda_pendentes")).data;
check(!pend.some((e) => e.titulo === "CULTO DE JOVENS") && pend.some((e) => e.titulo === "CAFÉ DAS MULHERES"), "eventos com \"Necessita mídia: Sim\" sem solicitação aparecem como lembrete");
await lia.rpc("midia_decidir_solicitacao", { p_solicitacao: solAg.id, p_acao: "aprovar", p_motivo: null });

console.log("\n4. Cada evento com as equipes que precisa");
const criar = async (p) => { const x = await lia.rpc("midia_criar_escala", { p }); if (x.error) throw new Error(x.error.message); return x.data.id; };
const ESC_CULTO = await criar({ solicitacao_id: solAg.id });
let ev = (await lia.rpc("midia_evento", { p_escala: ESC_CULTO })).data;
const usadas = ev.areas.filter((a) => a.usada).map((a) => a.area);
check(JSON.stringify(usadas) === JSON.stringify(["Projeção", "Sonoplastia"]), "culto de sábado: só Projeção e Sonoplastia (vindas dos serviços aprovados)", usadas);
check(erro(await lia.rpc("midia_criar_escala", { p: { evento_id: evCulto } }), /Já existe uma escala/), "não duplica a escala do mesmo evento");
const ESC_CONF = await criar({ titulo: "Conferência Mergulhados", inicio: quando(20, 19, 0), fim: quando(20, 22, 0), local: "Templo",
  funcoes: ["Fotógrafo", "Videomaker", "Responsável pelos Stories", "Operador de projeção", "Operador de som", "Operador de câmera", "Operador de transmissão"].map(fn) });
check((await lia.rpc("midia_evento", { p_escala: ESC_CONF })).data.areas.filter((a) => a.usada).length === 6, "conferência: 7 funções em 6 equipes");
const ESC_JOV = await criar({ solicitacao_id: SOL, funcoes: [fn("Fotógrafo"), fn("Responsável pelos Stories")] });
const ESC_REU = await criar({ titulo: "Reunião administrativa", inicio: quando(12, 20, 0), fim: quando(12, 21, 0), local: "Sala 2", funcoes: [] });
check((await lia.rpc("midia_evento", { p_escala: ESC_REU })).data.areas.every((a) => !a.usada), "reunião administrativa: nenhuma equipe (nada obrigatório)");
const efDe = async (esc, nome) => (await lia.rpc("midia_evento", { p_escala: esc })).data.areas.flatMap((a) => a.funcoes).find((f) => f.funcao === nome).id;

console.log("\n5. Sem limite por função e habilitação obrigatória");
const add = (c, ef, k, extra = {}, ciente = false) => c.rpc("escala_adicionar", { p_evento_funcao: ef, p_pessoa: P[k], p: extra, p_ciente: ciente });
const efProj = await efDe(ESC_CULTO, "Operador de projeção"), efSom = await efDe(ESC_CULTO, "Operador de som");
for (const [ef, k, papel] of [[efProj, "gil", "principal"], [efProj, "paula", "auxiliar"], [efSom, "sergio", "principal"], [efSom, "sara", "auxiliar"]]) {
  const x = await add(lia, ef, k, { papel }); if (!x.data?.ok) console.log(k, JSON.stringify(x));
}
ev = (await lia.rpc("midia_evento", { p_escala: ESC_CULTO })).data;
check(ev.areas.flatMap((a) => a.funcoes).every((f) => f.ativos === 2), "2 na projeção e 2 no som no mesmo culto (sem limite)");
check(erro(await add(lia, efProj, "gil"), /já está nesta função/), "a mesma pessoa não entra duas vezes na mesma função");
check(erro(await add(lia, efProj, "vitor"), /Sem habilitação/), "REGRA: sem habilitação para a função, não é escalado");
check(/Sem habilitação/.test(await sqlErro("insert into escala_participacoes (escala_evento_id, evento_funcao_id, pessoa_id) values ($1, $2, $3)", [ESC_CULTO, efProj, P.vitor])), "a trava vale até para SQL direto");
const efFotoJ = await efDe(ESC_JOV, "Fotógrafo");
check(erro(await add(lia, efFotoJ, "tina", { papel: "principal" }), /só pode ser escalado\(a\) como auxiliar/), "em treinamento não entra como responsável principal");
check(erro(await add(lia, efFotoJ, "nina"), /não tem conta ativa/), "sem conta não é escalado (não teria como confirmar)");
await hab("davi", "Fotógrafo", "suspenso");
check(erro(await add(lia, efFotoJ, "davi"), /Sem habilitação ativa/), "habilitação suspensa bloqueia");
await hab("davi", "Fotógrafo");

console.log("\n6. Publicação e confirmação individual");
for (const k of ["vitor", "vera", "vanda"]) { const x = await add(lia, efFotoJ, k, { papel: k === "vitor" ? "principal" : "auxiliar" }); if (!x.data?.ok) console.log(k, JSON.stringify(x)); }
check(!(await add(lia, efFotoJ, "tina", { papel: "auxiliar" }, true)).error, "em treinamento entra como auxiliar (o líder fica ciente do alerta)");
check(!(await avisos(V.vitor)).some((n) => n.tipo === "escala_nova"), "antes de publicar, ninguém é avisado");
r = await lia.rpc("escala_publicar", { p_escala: ESC_JOV });
check(r.data?.avisados === 4, "publicar avisa cada escalado individualmente (4 avisos)");
const nv = (await avisos(V.vera)).find((n) => n.tipo === "escala_nova");
check(nv && nv.mensagem.includes("Noite de Louvor") && nv.mensagem.includes("Templo") && nv.mensagem.includes("Fotógrafo") && nv.mensagem.includes("Mídia") && nv.mensagem.includes("Lia Lider Midia") && nv.mensagem.includes("responda até"),
  "o aviso traz evento, data, horário, local, ministério, função, responsável e prazo", nv?.mensagem);
const minha = async (k) => (await V[k].rpc("minhas_escalas")).data.find((e) => e.evento.id === ESC_JOV);
const mv = await minha("vitor"), mve = await minha("vera"), mva = await minha("vanda");
check(mv.status === "aguardando" && mv.equipe.length === 4 && !JSON.stringify(mv.equipe).includes("3199"), "o voluntário vê a escala e a equipe (só nomes e funções, sem contatos)");
check(negado(await V.vera.rpc("escala_responder", { p_participacao: mv.id, p_resposta: "confirmar", p_versao: mv.versao, p_motivo: null })), "ninguém responde pela escala de outra pessoa");
check(negado(await lia.rpc("escala_responder", { p_participacao: mv.id, p_resposta: "confirmar", p_versao: mv.versao, p_motivo: null })), "nem o líder confirma no lugar do voluntário");
check(erro(await V.vitor.rpc("escala_responder", { p_participacao: mv.id, p_resposta: "confirmar", p_versao: mv.versao + 5, p_motivo: null }), /mudou/), "resposta a uma versão antiga é recusada");
await V.vitor.rpc("escala_responder", { p_participacao: mv.id, p_resposta: "confirmar", p_versao: mv.versao, p_motivo: null });
await V.vera.rpc("escala_responder", { p_participacao: mve.id, p_resposta: "confirmar", p_versao: mve.versao, p_motivo: null });
await V.vanda.rpc("escala_responder", { p_participacao: mva.id, p_resposta: "recusar", p_versao: mva.versao, p_motivo: "Viagem a trabalho" });
ev = (await lia.rpc("midia_evento", { p_escala: ESC_JOV })).data;
const fotos = ev.areas.flatMap((a) => a.funcoes).find((f) => f.funcao === "Fotógrafo");
const st = Object.fromEntries(fotos.participacoes.map((p) => [p.nome.split(" ")[0], p.status]));
check(st.Vitor === "confirmado" && st.Vera === "confirmado" && st.Vanda === "recusado" && st.Tina === "aguardando", "REGRA: 2 confirmam e 1 recusa; os outros continuam confirmados", st);
check(fotos.vagas_abertas === 1 && (await avisos(lia)).some((n) => n.tipo === "escala_recusada" && n.mensagem.includes("Viagem")), "a recusa abre a vaga e avisa o líder com o motivo");
const pVanda = fotos.participacoes.find((p) => p.nome.startsWith("Vanda")).id;
r = await lia.rpc("escala_participacao_acao", { p_part: pVanda, p_acao: "substituir", p: { pessoa_id: P.davi } });
check(r.data?.ok, "o líder escolhe o substituto (Davi)");
ev = (await lia.rpc("midia_evento", { p_escala: ESC_JOV })).data;
const fotos2 = ev.areas.flatMap((a) => a.funcoes).find((f) => f.funcao === "Fotógrafo");
const pDavi = fotos2.participacoes.find((p) => p.nome.startsWith("Davi"));
check(fotos2.participacoes.find((p) => p.id === pVanda).status === "substituido" && pDavi.status === "aguardando" && pDavi.substitui_id === pVanda && fotos2.vagas_abertas === 0, "Vanda fica como substituída, Davi recebe o próprio pedido de confirmação");
check((await avisos(V.davi)).some((n) => n.tipo === "escala_nova"), "o substituto é avisado individualmente");

console.log("\n7. Prazo, lembrete e ausência de resposta");
await sql("update escala_participacoes set prazo = now() + interval '3 hours' where id = $1", [pDavi.id]);
const pTina = fotos2.participacoes.find((p) => p.nome.startsWith("Tina")).id;
await sql("update escala_participacoes set prazo = now() - interval '1 hour' where id = $1", [pTina]);
r = await master.rpc("escalas_processar_prazos"); check(negado(r), "a tarefa de prazos não é chamada por usuários");
const proc = async () => (await sql("select escalas_processar_prazos() r"))[0].r;
const r1 = await proc(), r2 = await proc();
check(r1.lembretes === 1 && r1.atrasadas === 1, "lembrete a quem está perto do prazo e aviso de atraso", r1);
const nAvisos = (await sql("select count(*)::int n from notificacoes where chave like 'lembrete:%' or chave like 'atrasada:%'"))[0].n;
check(nAvisos === 1 + 1 + 1 && r2.lembretes === 1, "rodar de novo não duplica avisos (chave única)", nAvisos);
check((await avisos(lia)).some((n) => n.tipo === "escala_atrasada_lider"), "o líder é avisado do prazo vencido");
const mt = (await V.tina.rpc("minhas_escalas")).data.find((e) => e.id === pTina);
check(mt.status === "aguardando" && mt.atrasada, "REGRA: sem resposta continua pendente (\"atrasada\"), nunca confirmada");

console.log("\n8. Alterações relevantes e orientações");
r = await lia.rpc("escala_alterar", { p_escala: ESC_JOV, p: { orientacoes_gerais: "Chegar 30 minutos antes." } });
check(r.data?.relevante === false && (await minha("vitor")).status === "confirmado" && (await avisos(V.vitor)).some((n) => n.tipo === "escala_orientacoes"), "mudar orientações só avisa (confirmação mantida)");
r = await lia.rpc("escala_alterar", { p_escala: ESC_JOV, p: { inicio: quando(10, 19, 0), fim: quando(10, 22, 0) } });
const mv2 = await minha("vitor");
check(r.data?.relevante && mv2.status === "aguardando" && mv2.versao === 2 && (await avisos(V.vitor)).some((n) => n.tipo === "escala_reconfirmar"), "mudar o horário pede nova confirmação a quem já tinha confirmado");
check((await minha("vanda")).status === "substituido", "quem foi substituído não é chamado de novo");
check(erro(await V.vitor.rpc("escala_responder", { p_participacao: mv2.id, p_resposta: "confirmar", p_versao: 1, p_motivo: null }), /mudou/) && !(await V.vitor.rpc("escala_responder", { p_participacao: mv2.id, p_resposta: "confirmar", p_versao: 2, p_motivo: null })).error, "a confirmação vale para a versão nova");
r = await lia.rpc("escala_alterar_participacao", { p_part: mve.id, p: { atividade: "Fotos do público" } });
check(r.data?.nova_confirmacao && (await minha("vera")).status === "aguardando", "mudar a atividade de uma pessoa pede nova confirmação só a ela");
check((await minha("vitor")).status === "confirmado", "os demais não são afetados");

console.log("\n9. Mudança na Agenda");
await lia.rpc("escala_publicar", { p_escala: ESC_CULTO });
const pg1 = (await V.gil.rpc("minhas_escalas")).data.find((e) => e.evento.id === ESC_CULTO);
await V.gil.rpc("escala_responder", { p_participacao: pg1.id, p_resposta: "confirmar", p_versao: pg1.versao, p_motivo: null });
check(erro(await lia.rpc("escala_alterar", { p_escala: ESC_CULTO, p: { inicio: quando(30, 18, 0), fim: quando(30, 20, 0) } }), /mude a data e o horário na Agenda/), "evento da Agenda: data e horário se mudam na Agenda");
await sql("update eventos set horario_inicio = '20:00', horario_fim = '22:00', horario = '20:00 às 22:00' where id = $1", [evCulto]);
const pg2 = (await V.gil.rpc("minhas_escalas")).data.find((e) => e.evento.id === ESC_CULTO);
check(new Date(pg2.inicio).toISOString() === "2026-12-05T23:00:00.000Z" && pg2.status === "aguardando" && pg2.versao === 2, "a mudança de horário na Agenda chega à escala e pede nova confirmação");
check((await lia.rpc("escala_historico_listar", { p_escala: ESC_CULTO })).data.some((h) => h.acao === "alterada_pela_agenda"), "o histórico registra que a mudança veio da Agenda");
await sql("delete from eventos where id = $1", [evCulto]);
const pg3 = (await V.gil.rpc("minhas_escalas")).data.find((e) => e.evento.id === ESC_CULTO);
check(pg3.status === "cancelado" && pg3.evento.status === "cancelada" && (await avisos(V.gil)).some((n) => n.tipo === "escala_cancelada"), "evento excluído da Agenda: escala cancelada e voluntários avisados");

console.log("\n10. Conflitos, disponibilidade e sugestões");
const efFotoC = await efDe(ESC_CONF, "Fotógrafo");
await V.vera.rpc("minha_indisponibilidade", { p_acao: "incluir", p: { inicio: quando(19, 0).slice(0, 10), fim: quando(22, 0).slice(0, 10), tipo: "ferias", motivo: "Férias" } });
await V.gil.rpc("salvar_minha_disponibilidade", { p: { semana: [{ dia: 0, de: "08:00", ate: "12:00" }], preferencias: { funcoes: [fn("Operador de projeção")], observacoes: "Só manhãs de domingo" } } });
const dispGil = (await V.gil.rpc("minha_disponibilidade")).data;
check(dispGil.semana.length === 1 && dispGil.preferencias.observacoes.includes("domingo") && dispGil.habilitacoes.length === 2, "voluntário cadastra disponibilidade, preferências e vê as próprias habilitações");
r = await add(lia, efFotoC, "vera");
check(r.data?.ok === false && r.data.alertas.some((a) => a.tipo === "indisponivel"), "alerta: voluntária de férias na data (não escala sem ciência)");
check(!(await sql("select 1 from escala_participacoes where evento_funcao_id = $1 and pessoa_id = $2", [efFotoC, P.vera])).length, "sem ciência, nada é gravado");
const efProjC = await efDe(ESC_CONF, "Operador de projeção");
r = await add(lia, efProjC, "gil");
check(r.data?.alertas?.some((a) => a.tipo === "fora_disponibilidade"), "alerta: fora dos dias e horários informados");
// conflito: mesmo horário que outra escala
const ESC_X = await criar({ titulo: "Culto paralelo", inicio: quando(20, 20, 0), fim: quando(20, 21, 0), local: "Salão", funcoes: [fn("Fotógrafo")] });
await add(lia, await efDe(ESC_X, "Fotógrafo"), "vitor");
r = await add(lia, efFotoC, "vitor");
check(r.data?.ok === false && r.data.alertas.some((a) => a.tipo === "conflito" && a.texto.includes("Culto paralelo")), "alerta: já escalado em outro evento no mesmo período");
check((await add(lia, efFotoC, "vitor", {}, true)).data?.ok, "com ciência do líder, a escala é feita e o alerta fica registrado");
const sug = (await lia.rpc("escala_sugerir", { p_evento_funcao: efFotoC })).data;
check(sug.length >= 3 && sug[0].alertas.length === 0 && !sug.some((s) => s.nome.startsWith("Nina")) && !sug.some((s) => s.nome.startsWith("Vitor")), "sugestões: habilitados com conta, sem conflito primeiro, sem quem já está na função", sug.map((s) => s.nome));
check(sug.findIndex((s) => s.nome.startsWith("Vera")) > sug.findIndex((s) => s.alertas.length === 0), "quem está indisponível vem depois");
check(!(await sql("select 1 from escala_participacoes where evento_funcao_id = $1 and pessoa_id = $2", [efFotoC, P.davi])).length, "sugestão não escala ninguém automaticamente");

console.log("\n11. Gestor delegado");
const perfilGil = (await sql("select p.id from perfis p join pessoas pe on pe.id = p.pessoa_id where pe.email = 'gil@teste.com'"))[0].id;
const areaProj = cat.areas.find((a) => a.nome === "Projeção").id;
check(negado(await V.gil.rpc("midia_definir_gestor", { p_ministerio: MIDIA, p_perfil: perfilGil, p_areas: [areaProj], p_ativo: true })), "voluntário não se nomeia gestor");
await lia.rpc("midia_definir_gestor", { p_ministerio: MIDIA, p_perfil: perfilGil, p_areas: [areaProj], p_ativo: true });
check(!(await add(V.gil, efProjC, "paula", {}, true)).error, "Gil (gestor da Projeção) escala na Projeção");
check(negado(await add(V.gil, efFotoC, "davi", {}, true)), "mas não escala na Fotografia");
check(negado(await V.gil.rpc("midia_decidir_solicitacao", { p_solicitacao: sol2, p_acao: "em_analise", p_motivo: null })) && negado(await V.gil.rpc("midia_habilitar", { p_pessoa: P.paula, p_funcao: fn("Diretor da Live"), p_status: "habilitado", p_observacao: null })), "gestor não decide solicitações nem habilita voluntários");

console.log("\n12. Presença efetiva, cancelamento e relatório");
const ESC_HOJE = await criar({ titulo: "Culto em andamento", inicio: new Date(Date.now() - 3600e3).toISOString(), fim: new Date(Date.now() + 3600e3).toISOString(), local: "Templo", funcoes: [fn("Operador de som")] });
const efSomH = await efDe(ESC_HOJE, "Operador de som");
await add(lia, efSomH, "sergio", {}, true); await add(lia, efSomH, "sara", {}, true);
await lia.rpc("escala_publicar", { p_escala: ESC_HOJE });
const ps = (await V.sergio.rpc("minhas_escalas")).data.find((e) => e.evento.id === ESC_HOJE), psa = (await V.sara.rpc("minhas_escalas")).data.find((e) => e.evento.id === ESC_HOJE);
await V.sergio.rpc("escala_responder", { p_participacao: ps.id, p_resposta: "confirmar", p_versao: ps.versao, p_motivo: null });
await V.sara.rpc("escala_responder", { p_participacao: psa.id, p_resposta: "confirmar", p_versao: psa.versao, p_motivo: null });
const pres = (id, presenca) => lia.rpc("escala_participacao_acao", { p_part: id, p_acao: "presenca", p: { presenca } });
check(erro(await pres(mv2.id, "presente"), /depois do início/), "presença só depois do início do evento");
check(negado(await V.sergio.rpc("escala_participacao_acao", { p_part: ps.id, p_acao: "presenca", p: { presenca: "presente" } })), "o voluntário não registra a própria presença");
await pres(ps.id, "presente"); await pres(psa.id, "ausente");
check((await V.sara.rpc("minhas_escalas")).data.find((e) => e.id === psa.id).status === "confirmado", "REGRA: confirmou mas faltou — a confirmação não vira presença");
const rel = (await lia.rpc("midia_relatorio", { p_de: new Date(Date.now() - 864e5).toISOString().slice(0, 10), p_ate: new Date(Date.now() + 864e5).toISOString().slice(0, 10), p_agrupar: "evento" })).data;
const lin = rel.find((x) => x.chave.startsWith("Culto em andamento"));
check(lin.escalados === 2 && lin.confirmaram === 2 && lin.serviram === 1 && lin.faltaram === 1, "relatório separa escalados (2), confirmaram (2) e serviram (1)", lin);
r = await lia.rpc("escala_participacao_acao", { p_part: pDavi.id, p_acao: "cancelar", p: { motivo: "" } });
check(erro(r, /motivo/), "cancelar uma participação exige motivo");
await lia.rpc("escala_participacao_acao", { p_part: pDavi.id, p_acao: "cancelar", p: { motivo: "Equipe de fotos suficiente" } });
check((await V.davi.rpc("minhas_escalas")).data.find((e) => e.id === pDavi.id).status === "cancelado" && (await avisos(V.davi)).some((n) => n.tipo === "escala_cancelada"), "cancelamento individual pelo líder, com aviso");
check(erro(await lia.rpc("escala_encerrar", { p_escala: ESC_JOV, p_acao: "concluir", p_motivo: null }), /ainda não terminou/), "não conclui escala de evento futuro");

console.log("\n13. Histórico e auditoria");
const hist = (await lia.rpc("escala_historico_listar", { p_escala: ESC_JOV })).data.map((h) => h.acao);
for (const a of ["escala_criada", "funcao_incluida", "escalado", "escala_publicada", "confirmou", "recusou", "substituto_escalado", "nova_confirmacao_pedida", "escala_alterada", "status_cancelado"])
  check(hist.includes(a), `histórico registra: ${a}`, hist);
check(/não pode ser alterado/.test(await sqlErro("delete from escala_historico where escala_evento_id = $1", [ESC_JOV])), "o histórico não pode ser apagado");
check(/não podem ser excluídos/.test(await sqlErro("delete from escala_participacoes where id = $1", [pVanda])), "participações não são apagadas (substituição preserva o anterior)");
check(negado(await V.vitor.rpc("escala_historico_listar", { p_escala: ESC_JOV })), "o histórico é da liderança");
const dup = (await sql("select chave, count(*)::int n from notificacoes where chave is not null group by chave having count(*) > 1")).length;
check(dup === 0, "nenhum aviso duplicado");

console.log(`\nResultado: ${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
