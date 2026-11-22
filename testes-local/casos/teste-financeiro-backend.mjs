// Etapa 4 — Secretaria e Tesouraria: permissões e fluxos de pagamento (backend, chamadas diretas).
import { createClient } from "@supabase/supabase-js";
import { execFileSync } from "node:child_process";
import pg from "pg";
import fs from "node:fs";
import { paramsTermos, prepararVoluntario } from "./apoio-termos.mjs";

const URL_ = process.env.SUPABASE_URL, ANON = process.env.SUPABASE_ANON_KEY;
const novo = () => createClient(URL_, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
let ok = 0, falhas = 0;
const check = (c, n, x) => { if (c) { ok++; console.log("  ✓ " + n); } else { falhas++; console.log("  ✗ " + n + (x !== undefined ? "  → " + JSON.stringify(x).slice(0, 400) : "")); } };
const negado = (r) => !!r.error && ["42501", "PGRST301"].includes(r.error.code);
const sql = async (q, v) => { const c = new pg.Client({ host: "/tmp", port: 5434, user: "postgres", database: "betel" }); await c.connect(); try { return (await c.query(q, v)).rows; } finally { await c.end(); } };
async function entrar(email, senha, nova) { const c = novo(); const r = await c.auth.signInWithPassword({ email, password: senha }); if (r.error) throw new Error(r.error.message); if (nova) await c.auth.updateUser({ password: nova }); return c; }
async function fn(cli, corpo) { const { data, error } = await cli.functions.invoke("arquivos", { body: corpo }); if (!error) return { data, status: 200 }; let j = {}; try { j = await error.context.json(); } catch (_) {} return { erro: j.erro, status: error.context?.status }; }
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=", "base64");
const PDF = Buffer.from("%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF");
const arq = (buf, tipo = "image/png", nome = "comprovante.png") => ({ nome, tipo, base64: buf.toString("base64") });
const inscr = async (turma, n, tel, email) => novo().rpc("inscrever_curso_com_termos", { ...(await paramsTermos()), p_turma: turma, p_nome: n, p_telefone: tel, p_email: email, p_data_nascimento: "1990-05-10", p_observacao: null, p_aceite_privacidade: true, p_origem: "site" });
const notifs = async (cli) => (await cli.rpc("minhas_notificacoes", { p_limite: 200 })).data;

console.log("\n0. Contas e turma paga");
const saida = execFileSync("node", ["../scripts/criar-primeiros-masters.mjs", "Primeiro Master Teste|master1@exemplo.com|31900000001"], { env: process.env }).toString();
const master = await entrar("master1@exemplo.com", saida.match(/senha temporária: (\S+)/)[1], "Ezequiel-Nova-2026");
const mins = (await novo().from("ministerios").select("id,nome")).data, mid = (n) => mins.find((m) => m.nome === n).id;
const cria = async (nome, email, atrib) => (await master.functions.invoke("admin-usuarios", { body: { acao: "criar", nome, telefone: "31999990000", email, perfil: "LIDER", atribuicoes: atrib, ministerios: [{ ministerio_id: mid("Secretaria"), funcao: "lider" }] } })).data;
const C = { elaine: await cria("Elaine Secretaria Teste", "elaine@teste.com", ["SECRETARIA"]), tadeu: await cria("Tadeu Tesoureiro Teste", "tadeu@teste.com", ["TESOURARIA"]),
  sara: await cria("Sara Secretaria Tesoureira", "sara@teste.com", ["SECRETARIA", "TESOURARIA"]), lia: await cria("Lia Lider Teste", "lia@teste.com", []) };
const sec = await entrar("elaine@teste.com", C.elaine.senha_temporaria, "Elaine-Nova-2026"), tes = await entrar("tadeu@teste.com", C.tadeu.senha_temporaria, "Tadeu-Nova-2026");
const sara = await entrar("sara@teste.com", C.sara.senha_temporaria, "Sara-Nova-20261"), lider = await entrar("lia@teste.com", C.lia.senha_temporaria, "Lia-Nova-20261");
fs.writeFileSync("/tmp/financeiro-contas.json", JSON.stringify({ master: "Ezequiel-Nova-2026", elaine: "Elaine-Nova-2026", tadeu: "Tadeu-Nova-2026", sara: "Sara-Nova-20261", lia: "Lia-Nova-20261" }));
const herm = (await sec.rpc("cursos_admin_listar")).data.cursos.find((c) => c.slug === "hermeneutica");
await sec.rpc("cursos_salvar_curso", { p: { ...herm, publicado: true, cursos_exigidos: [] } });
const turma = (await sec.rpc("cursos_salvar_turma", { p: { curso_id: herm.id, nome: "Turma paga", status: "inscricoes_abertas", vagas: "20", valor: "100" } })).data.id;
check(!!turma, "turma de R$ 100,00 com inscrições abertas");

console.log("\n1. Permissões (painéis separados)");
const anon = novo();
for (const [nome, cli, esperado] of [["visitante", anon, false], ["líder sem atribuição", lider, false], ["Tesouraria", tes, true], ["Secretaria", sec, true]])
  check(!!(await cli.rpc("secretaria_inscricoes", { p_filtros: {} })).error !== esperado, `${nome} ${esperado ? "consulta" : "não consulta"} inscrições e status financeiro`);
for (const [nome, cli, esperado] of [["Secretaria", sec, false], ["MASTER (sem atribuição)", master, false], ["líder", lider, false], ["Tesouraria", tes, true]])
  check(!(await cli.rpc("tesouraria_dashboard", {})).error === esperado, `${nome} ${esperado ? "abre" : "não abre"} o painel financeiro`);
check(negado(await tes.rpc("secretaria_validar_membresia", { p_pessoa: crypto.randomUUID(), p_situacao: "membro", p_membro_desde: "2020-01-01", p_observacao: null })), "Tesouraria não valida membresia");
check(negado(await tes.rpc("secretaria_certificados", {})), "Tesouraria não gerencia certificados");
check(negado(await lider.rpc("secretaria_pessoas", { p_busca: null })), "líder não vê o cadastro geral de pessoas");
for (const t of ["pagamentos", "comprovantes", "beneficios", "reembolsos", "documentos", "certificados", "notificacoes"])
  check(negado(await tes.from(t).select("*")), `ninguém lê a tabela ${t} direto (só pelas funções)`);
check(negado(await anon.rpc("servico_registrar_comprovante", { p_ator: null, p_inscricao: crypto.randomUUID(), p_pagamento: null, p_metodo: "pix", p_valor: 1, p_pago_em: null, p_path: "x", p_nome: "x", p_mime: "image/png", p_tamanho: 1, p_hash: "0".repeat(64) })), "visitante não chama a função interna de registrar comprovante");

console.log("\n2. Comprovante do participante (o envio NÃO confirma)");
const a = (await inscr(turma, "Ana Participante", "31911110001", "ana@teste.com")).data;
check(a.status === "aguardando_pagamento", "inscrição paga começa aguardando pagamento");
check((await fn(anon, { acao: "enviar_comprovante", protocolo: a.protocolo, chave: "errada", metodo: "pix", valor: 100, pago_em: "2026-11-20", arquivo: arq(PNG) })).status === 404, "link com chave errada não envia nada");
check((await fn(anon, { acao: "enviar_comprovante", protocolo: a.protocolo, chave: a.chave, metodo: "pix", valor: 100, pago_em: "2026-11-20", arquivo: arq(Buffer.from("não é png")) })).status === 415, "arquivo com conteúdo falso é recusado");
check((await fn(anon, { acao: "enviar_comprovante", protocolo: a.protocolo, chave: a.chave, metodo: "pix", valor: 100, pago_em: "2026-11-20", arquivo: arq(Buffer.concat([PNG, Buffer.alloc(5_300_000)])) })).status === 413, "arquivo acima de 5 MB é recusado");
let r = await fn(anon, { acao: "enviar_comprovante", protocolo: a.protocolo, chave: a.chave, metodo: "pix", valor: 100, pago_em: "2026-11-20", arquivo: arq(PNG) });
check(r.data?.ok, "comprovante enviado pelo link pessoal", r);
let minha = (await anon.rpc("minha_inscricao_curso", { p_protocolo: a.protocolo, p_chave: a.chave })).data;
check(minha.status === "aguardando_pagamento" && minha.pagamentos[0].status === "em_analise", "REGRA: depois do envio a inscrição continua aguardando; pagamento fica em análise");
check((await fn(anon, { acao: "enviar_comprovante", protocolo: a.protocolo, chave: a.chave, metodo: "pix", valor: 100, pago_em: "2026-11-20", arquivo: arq(PNG) })).status === 409, "não envia outro enquanto o anterior está em análise");
check((await notifs(tes)).itens.some((n) => n.tipo === "comprovante_recebido"), "Tesouraria recebe aviso do comprovante");
check(!(await notifs(sec)).itens.some((n) => n.tipo === "comprovante_recebido"), "Secretaria não recebe esse aviso");

console.log("\n3. Arquivo privado");
let fila = (await tes.rpc("tesouraria_pagamentos", { p_filtros: { status: "em_analise" } })).data;
const pagA = fila.find((p) => p.protocolo === a.protocolo), compA = pagA.comprovantes[0];
const caminho = (await sql("select arquivo_path from comprovantes where id = $1", [compA.id]))[0].arquivo_path;
check((await fetch(`${URL_}/storage/v1/object/public/comprovantes/${caminho}`)).status === 404, "comprovante não tem endereço público");
const link = await fn(tes, { acao: "link", tipo: "comprovante", id: compA.id });
const baixado = Buffer.from(await (await fetch(link.data.url)).arrayBuffer());
check(baixado.equals(PNG), "Tesouraria abre o comprovante por link temporário (conteúdo idêntico)");
check((await fetch(link.data.url.replace(/token=([^.]+)\.(.)/, "token=$1.X"))).status === 400, "link adulterado não abre");
check((await fn(sec, { acao: "link", tipo: "comprovante", id: compA.id })).status === 403, "Secretaria não abre comprovantes");
check((await fn(anon, { acao: "link", tipo: "comprovante", id: compA.id })).status === 401, "visitante não abre comprovantes");
check((await sql("select hash_sha256 from comprovantes where id = $1", [compA.id]))[0].hash_sha256.length === 64, "hash do arquivo registrado (integridade)");

console.log("\n4. Análise da Tesouraria");
check(/mínimo 5/.test((await tes.rpc("tesouraria_analisar_pagamento", { p_pagamento: pagA.id, p_acao: "solicitar_novo", p_observacao: "x" })).error?.message || ""), "pedir novo comprovante exige explicação");
check(!(await tes.rpc("tesouraria_analisar_pagamento", { p_pagamento: pagA.id, p_acao: "solicitar_novo", p_observacao: "Imagem ilegível, envie o PDF do banco." })).error, "Tesouraria pede novo comprovante");
minha = (await anon.rpc("minha_inscricao_curso", { p_protocolo: a.protocolo, p_chave: a.chave })).data;
check(minha.pagamentos[0].mensagem === "Imagem ilegível, envie o PDF do banco." && minha.status === "aguardando_pagamento", "participante vê o pedido no link pessoal");
r = await fn(anon, { acao: "enviar_comprovante", protocolo: a.protocolo, chave: a.chave, arquivo: arq(PDF, "application/pdf", "extrato.pdf") });
check(r.data?.pagamento_id === pagA.id, "novo comprovante entra no mesmo pagamento");
check((await sql("select situacao from comprovantes where pagamento_id = $1 order by enviado_em", [pagA.id])).map((x) => x.situacao).join() === "substituido,atual", "o anterior fica guardado como substituído");
check(negado(await sec.rpc("tesouraria_analisar_pagamento", { p_pagamento: pagA.id, p_acao: "aprovar" })), "REGRA: a Secretaria não aprova pagamento");
check(!(await tes.rpc("tesouraria_analisar_pagamento", { p_pagamento: pagA.id, p_acao: "aprovar" })).error, "Tesouraria aprova");
minha = (await anon.rpc("minha_inscricao_curso", { p_protocolo: a.protocolo, p_chave: a.chave })).data;
check(minha.status === "confirmada" && minha.financeiro.situacao === "quitado", "inscrição confirmada só depois da aprovação");
check((await notifs(sec)).itens.some((n) => n.tipo === "pagamento_aprovado"), "Secretaria é avisada da aprovação");
check(/em análise/.test((await tes.rpc("tesouraria_analisar_pagamento", { p_pagamento: pagA.id, p_acao: "aprovar" })).error?.message || ""), "pagamento não é aprovado duas vezes");
const b = (await inscr(turma, "Bruno Participante", "31911110002", "bruno@teste.com")).data;
await fn(anon, { acao: "enviar_comprovante", protocolo: b.protocolo, chave: b.chave, metodo: "transferencia", valor: 100, pago_em: "2026-11-20", arquivo: arq(PNG) });
const pagB = (await tes.rpc("tesouraria_pagamentos", { p_filtros: { status: "em_analise" } })).data.find((p) => p.protocolo === b.protocolo);
check(!(await tes.rpc("tesouraria_analisar_pagamento", { p_pagamento: pagB.id, p_acao: "recusar", p_observacao: "Valor não localizado no extrato." })).error, "Tesouraria recusa com motivo");
check((await anon.rpc("minha_inscricao_curso", { p_protocolo: b.protocolo, p_chave: b.chave })).data.status === "aguardando_pagamento", "recusado: inscrição continua aguardando");
r = await fn(anon, { acao: "enviar_comprovante", protocolo: b.protocolo, chave: b.chave, metodo: "pix", valor: 100, pago_em: "2026-11-21", arquivo: arq(PNG) });
check(r.data?.pagamento_id && r.data.pagamento_id !== pagB.id, "após recusa, o participante pode enviar um novo pagamento");

console.log("\n5. A regra no próprio banco");
const insB = (await sql("select id from inscricoes where protocolo = $1", [b.protocolo]))[0].id;
let erroSql = ""; try { await sql("update inscricoes set status = 'confirmada' where id = $1", [insB]); } catch (e) { erroSql = e.message; }
check(/só é confirmada após a Tesouraria/.test(erroSql), "nem um comando direto no banco confirma inscrição paga sem pagamento aprovado", erroSql);
erroSql = ""; try { await sql("delete from pagamentos where id = $1", [pagB.id]); } catch (e) { erroSql = e.message; }
check(/não podem ser excluídos/.test(erroSql), "pagamentos não podem ser apagados");

console.log("\n6. Pagamento presencial");
const c = (await inscr(turma, "Carla Participante", "31911110003", "carla@teste.com")).data;
const insC = (await sql("select id from inscricoes where protocolo = $1", [c.protocolo]))[0].id;
check(negado(await tes.rpc("secretaria_registrar_pagamento_presencial", { p_inscricao: insC, p_metodo: "dinheiro", p_valor: 100, p_pago_em: "2026-11-20", p_observacao: null })), "Tesouraria (sem Secretaria) não registra presencial");
check(negado(await lider.rpc("secretaria_registrar_pagamento_presencial", { p_inscricao: insC, p_metodo: "dinheiro", p_valor: 100, p_pago_em: "2026-11-20", p_observacao: null })), "líder não registra presencial");
const pres = (await sec.rpc("secretaria_registrar_pagamento_presencial", { p_inscricao: insC, p_metodo: "dinheiro", p_valor: 100, p_pago_em: "2026-11-20", p_observacao: "Recebido no balcão" })).data;
check(!!pres?.pagamento_id, "Secretaria registra pagamento em dinheiro");
check((await anon.rpc("minha_inscricao_curso", { p_protocolo: c.protocolo, p_chave: c.chave })).data.status === "aguardando_pagamento", "REGRA: registro presencial não confirma");
check(/em análise/.test((await tes.rpc("tesouraria_analisar_pagamento", { p_pagamento: pres.pagamento_id, p_acao: "aprovar" })).error?.message || ""), "sem recibo anexado, a Tesouraria não consegue aprovar");
check((await fn(lider, { acao: "enviar_comprovante", pagamento_id: pres.pagamento_id, arquivo: arq(PNG) })).status === 403, "líder não anexa recibo");
check((await fn(sec, { acao: "enviar_comprovante", pagamento_id: pres.pagamento_id, arquivo: arq(PDF, "application/pdf", "recibo.pdf") })).data?.ok, "Secretaria anexa o recibo");
check((await notifs(tes)).itens.some((n) => n.tipo === "pagamento_presencial"), "Tesouraria é avisada do presencial");
check(!(await tes.rpc("tesouraria_analisar_pagamento", { p_pagamento: pres.pagamento_id, p_acao: "aprovar" })).error, "Tesouraria valida o pagamento presencial");
check((await anon.rpc("minha_inscricao_curso", { p_protocolo: c.protocolo, p_chave: c.chave })).data.status === "confirmada", "inscrição confirmada após a validação");
const d = (await inscr(turma, "Davi Participante", "31911110004", "davi@teste.com")).data;
const insD = (await sql("select id from inscricoes where protocolo = $1", [d.protocolo]))[0].id;
const presS = (await sara.rpc("secretaria_registrar_pagamento_presencial", { p_inscricao: insD, p_metodo: "cartao_presencial", p_valor: 100, p_pago_em: "2026-11-20", p_observacao: null })).data;
await fn(sara, { acao: "enviar_comprovante", pagamento_id: presS.pagamento_id, arquivo: arq(PNG) });
check(/Quem registrou/.test((await sara.rpc("tesouraria_analisar_pagamento", { p_pagamento: presS.pagamento_id, p_acao: "aprovar" })).error?.message || ""), "quem tem as duas funções não aprova o que ela mesma registrou");
check(!(await tes.rpc("tesouraria_analisar_pagamento", { p_pagamento: presS.pagamento_id, p_acao: "aprovar" })).error, "outra pessoa da Tesouraria aprova");
const e = (await inscr(turma, "Eva Participante", "31911110005", "eva@teste.com")).data;
const insE = (await sql("select id from inscricoes where protocolo = $1", [e.protocolo]))[0].id;
const presE = (await sec.rpc("secretaria_registrar_pagamento_presencial", { p_inscricao: insE, p_metodo: "dinheiro", p_valor: 50, p_pago_em: "2026-11-20", p_observacao: null })).data;
check(/Só quem registrou/.test((await sara.rpc("secretaria_cancelar_pagamento", { p_pagamento: presE.pagamento_id, p_motivo: "teste" })).error?.message || ""), "só quem registrou cancela o registro");
check(!(await sec.rpc("secretaria_cancelar_pagamento", { p_pagamento: presE.pagamento_id, p_motivo: "Valor lançado errado" })).error, "Secretaria cancela o próprio registro antes da análise");

console.log("\n7. Bolsas e isenções");
check(/bolsa parcial/i.test((await sec.rpc("secretaria_solicitar_beneficio", { p_inscricao: insE, p_tipo: "bolsa_parcial", p_valor_desconto: 150, p_motivo: "Pedido do pastor" })).error?.message || ""), "bolsa parcial não pode ser maior que o valor");
const bolsa = (await sec.rpc("secretaria_solicitar_beneficio", { p_inscricao: insE, p_tipo: "bolsa_parcial", p_valor_desconto: 40, p_motivo: "Situação financeira informada à Secretaria" })).data;
check(!!bolsa?.id && /aguardando/.test((await sec.rpc("secretaria_solicitar_beneficio", { p_inscricao: insE, p_tipo: "isencao", p_valor_desconto: null, p_motivo: "Duplicado" })).error?.message || ""), "Secretaria pede bolsa; pedido duplicado é barrado");
check(negado(await sec.rpc("tesouraria_analisar_beneficio", { p_beneficio: bolsa.id, p_acao: "aprovar" })), "Secretaria não aprova a própria bolsa");
check(!(await tes.rpc("tesouraria_analisar_beneficio", { p_beneficio: bolsa.id, p_acao: "aprovar" })).error, "Tesouraria aprova a bolsa");
let fe = (await anon.rpc("minha_inscricao_curso", { p_protocolo: e.protocolo, p_chave: e.chave })).data;
check(Number(fe.financeiro.valor_final) === 60 && fe.status === "aguardando_pagamento", "com a bolsa, o valor devido cai para R$ 60 (inscrição continua aguardando)");
await fn(anon, { acao: "enviar_comprovante", protocolo: e.protocolo, chave: e.chave, metodo: "pix", valor: 60, pago_em: "2026-11-21", arquivo: arq(PNG) });
const pagE = (await tes.rpc("tesouraria_pagamentos", { p_filtros: { status: "em_analise" } })).data.find((p) => p.protocolo === e.protocolo);
await tes.rpc("tesouraria_analisar_pagamento", { p_pagamento: pagE.id, p_acao: "aprovar" });
check((await anon.rpc("minha_inscricao_curso", { p_protocolo: e.protocolo, p_chave: e.chave })).data.status === "confirmada", "pagando os R$ 60 aprovados, confirma");
const f = (await inscr(turma, "Fabio Participante", "31911110006", "fabio@teste.com")).data;
const insF = (await sql("select id from inscricoes where protocolo = $1", [f.protocolo]))[0].id;
const isen = (await sec.rpc("secretaria_solicitar_beneficio", { p_inscricao: insF, p_tipo: "isencao", p_valor_desconto: null, p_motivo: "Voluntário do evento" })).data;
await tes.rpc("tesouraria_analisar_beneficio", { p_beneficio: isen.id, p_acao: "aprovar" });
fe = (await anon.rpc("minha_inscricao_curso", { p_protocolo: f.protocolo, p_chave: f.chave })).data;
check(fe.status === "confirmada" && fe.financeiro.situacao === "isento", "isenção aprovada pela Tesouraria confirma sem pagamento");
const g = (await inscr(turma, "Gabi Participante", "31911110007", "gabi@teste.com")).data;
const insG = (await sql("select id from inscricoes where protocolo = $1", [g.protocolo]))[0].id;
const bg = (await sec.rpc("secretaria_solicitar_beneficio", { p_inscricao: insG, p_tipo: "bolsa_integral", p_valor_desconto: null, p_motivo: "Teste de recusa" })).data;
check(!(await tes.rpc("tesouraria_analisar_beneficio", { p_beneficio: bg.id, p_acao: "recusar", p_observacao: "Sem documentação" })).error
  && (await anon.rpc("minha_inscricao_curso", { p_protocolo: g.protocolo, p_chave: g.chave })).data.status === "aguardando_pagamento", "bolsa recusada: nada muda na inscrição");

console.log("\n8. Reembolsos");
const pagAapr = (await tes.rpc("tesouraria_pagamentos", { p_filtros: { status: "aprovado" } })).data.find((p) => p.protocolo === a.protocolo);
check(/cancelada ou para o valor pago a mais/.test((await tes.rpc("tesouraria_registrar_reembolso", { p_pagamento: pagAapr.id, p_valor: 100, p_metodo: "pix", p_realizado_em: "2026-11-21", p_motivo: "Teste" })).error?.message || ""), "não reembolsa inscrição ativa e quitada");
const insA = (await sql("select id from inscricoes where protocolo = $1", [a.protocolo]))[0].id;
await sec.rpc("cursos_alterar_inscricao", { p_inscricao: insA, p_acao: "cancelar", p_motivo: "Desistiu do curso" });
check((await notifs(tes)).itens.some((n) => n.tipo === "cancelada_com_pagamento"), "cancelamento de inscrição paga avisa a Tesouraria");
check(negado(await sec.rpc("tesouraria_registrar_reembolso", { p_pagamento: pagAapr.id, p_valor: 100, p_metodo: "pix", p_realizado_em: "2026-11-21", p_motivo: "Desistência" })), "Secretaria não registra reembolso");
check(!(await tes.rpc("tesouraria_registrar_reembolso", { p_pagamento: pagAapr.id, p_valor: 100, p_metodo: "pix", p_realizado_em: "2026-11-21", p_motivo: "Desistência antes do início" })).error, "Tesouraria reembolsa a inscrição cancelada");
check(/não pode passar/.test((await tes.rpc("tesouraria_registrar_reembolso", { p_pagamento: pagAapr.id, p_valor: 1, p_metodo: "pix", p_realizado_em: "2026-11-21", p_motivo: "Duplicado" })).error?.message || ""), "não reembolsa mais do que foi pago");
const h2 = (await inscr(turma, "Hugo Participante", "31911110008", "hugo@teste.com")).data;
await fn(anon, { acao: "enviar_comprovante", protocolo: h2.protocolo, chave: h2.chave, metodo: "pix", valor: 120, pago_em: "2026-11-21", arquivo: arq(PNG) });
const pagH = (await tes.rpc("tesouraria_pagamentos", { p_filtros: { status: "em_analise" } })).data.find((p) => p.protocolo === h2.protocolo);
await tes.rpc("tesouraria_analisar_pagamento", { p_pagamento: pagH.id, p_acao: "aprovar" });
check(/pago a mais: 20/.test((await tes.rpc("tesouraria_registrar_reembolso", { p_pagamento: pagH.id, p_valor: 21, p_metodo: "pix", p_realizado_em: "2026-11-21", p_motivo: "Pagou a mais" })).error?.message || ""), "pagou R$ 120 por R$ 100: reembolso limitado aos R$ 20 a mais");
check(!(await tes.rpc("tesouraria_registrar_reembolso", { p_pagamento: pagH.id, p_valor: 20, p_metodo: "pix", p_realizado_em: "2026-11-21", p_motivo: "Pagou a mais" })).error, "devolve os R$ 20");

console.log("\n9. Painel e relatórios");
const dash = (await tes.rpc("tesouraria_dashboard", {})).data;
check(Number(dash.recebido) === 480 && Number(dash.reembolsado) === 120, "recebido R$ 480 (100+100+100+60+120) e reembolsado R$ 120", dash);
check(Number(dash.em_analise.quantidade) === 1 && Number(dash.em_analise.valor) === 100, "1 comprovante em análise (R$ 100)");
check(Number(dash.beneficios_concedidos) === 140, "bolsas/isenções concedidas: R$ 140 (40 + 100)");
const mov = (await tes.rpc("tesouraria_movimentos", { p_de: "2026-01-01", p_ate: "2026-12-31" })).data;
check(mov.filter((m) => m.tipo === "entrada").length === 5 && mov.filter((m) => m.tipo === "reembolso").length === 2 && mov.reduce((s, m) => s + Number(m.valor), 0) === 360, "relatório: 5 entradas, 2 reembolsos, saldo R$ 360");

console.log("\n10. Membresia, documentos e certificados");
const pessoaC = (await sec.rpc("secretaria_pessoas", { p_busca: "carla@teste.com" })).data[0];
check(/data em que/.test((await sec.rpc("secretaria_validar_membresia", { p_pessoa: pessoaC.id, p_situacao: "membro", p_membro_desde: null, p_observacao: null })).error?.message || ""), "validar como membro exige a data");
check(!(await sec.rpc("secretaria_validar_membresia", { p_pessoa: pessoaC.id, p_situacao: "membro", p_membro_desde: "2019-05-12", p_observacao: "Carta de transferência recebida" })).error, "Secretaria valida a membresia");
check((await sec.rpc("secretaria_pessoas", { p_busca: "carla@teste.com" })).data[0].validada_por === "Elaine Secretaria Teste", "registra quem validou");
const doc = await fn(sec, { acao: "enviar_documento", pessoa_id: pessoaC.id, tipo: "carta_transferencia", descricao: "Carta da igreja anterior", arquivo: arq(PDF, "application/pdf", "carta.pdf") });
check(doc.data?.ok, "Secretaria guarda documento (privado)");
check((await fn(tes, { acao: "enviar_documento", pessoa_id: pessoaC.id, tipo: "outro", arquivo: arq(PDF, "application/pdf") })).status === 403, "Tesouraria não envia documentos");
const ld = await fn(sec, { acao: "link", tipo: "documento", id: doc.data.id });
check(Buffer.from(await (await fetch(ld.data.url)).arrayBuffer()).equals(PDF), "Secretaria abre o documento por link temporário");
check((await fn(tes, { acao: "link", tipo: "documento", id: doc.data.id })).status === 403, "Tesouraria não abre documentos");
await sec.rpc("cursos_alterar_inscricao", { p_inscricao: insC, p_acao: "concluir" });
let cs = (await sec.rpc("secretaria_certificados", {})).data;
const certC = cs.certificados.find((x) => x.protocolo === c.protocolo);
check(certC?.status === "aguardando_validacao" && /^[0-9A-F]{10}$/.test(certC.codigo), "concluir o curso gera o certificado (aguardando a validação da liderança — Etapa 6)");
check(/Vincule|autoriz/.test((await sec.rpc("secretaria_certificado", { p_certificado: certC.id, p_acao: "imprimir" })).error?.message || ""), "não imprime antes de validar, autorizar e vincular");
await master.rpc("lider_validar_certificado", { p_certificado: certC.id, p_acao: "validar", p_observacao: null });
check(!(await sec.rpc("secretaria_certificado", { p_certificado: certC.id, p_acao: "autorizar" })).error, "validado pela liderança e autorizado pela Secretaria");
check((await notifs(sec)).itens.some((n) => n.tipo === "certificado_autorizar"), "Secretaria é avisada do certificado para autorizar");
const hojeISO = new Date().toLocaleDateString("sv-SE");
const cer = (await sec.rpc("secretaria_salvar_cerimonia", { p: { titulo: "Entrega de certificados (teste)", data: hojeISO, horario: "19:30", local: "Templo" } })).data;
check(!(await sec.rpc("secretaria_certificado", { p_certificado: certC.id, p_acao: "vincular", p_dados: { cerimonia_id: cer.id } })).error, "liga o certificado à cerimônia");
const imp = (await sec.rpc("secretaria_certificado", { p_certificado: certC.id, p_acao: "imprimir" })).data;
check(imp.impressao.nome === "Carla Participante" && imp.impressao.curso === "Hermenêutica", "impressão devolve os dados para a Secretaria");
check(/quem recebeu|em mãos/.test((await sec.rpc("secretaria_certificado", { p_certificado: certC.id, p_acao: "entregar", p_dados: {} })).error?.message || ""), "entrega exige confirmar a entrega em mãos e quem recebeu");
check(!(await sec.rpc("secretaria_certificado", { p_certificado: certC.id, p_acao: "entregar", p_dados: { recebido_por: "Carla Participante", relacao: "participante", ocasiao: "cerimonia", confirmo_entrega_fisica: true } })).error, "registra a entrega em mãos");
fe = (await anon.rpc("minha_inscricao_curso", { p_protocolo: c.protocolo, p_chave: c.chave })).data;
check(fe.certificado.status === "entregue" && !JSON.stringify(fe).includes("codigo"), "participante vê a situação do certificado, sem arquivo nem código");
await sec.rpc("cursos_alterar_inscricao", { p_inscricao: insE, p_acao: "concluir" });
await sec.rpc("cursos_alterar_inscricao", { p_inscricao: insE, p_acao: "reabrir_conclusao" });
cs = (await sec.rpc("secretaria_certificados", {})).data;
check(cs.certificados.find((x) => x.protocolo === e.protocolo).status === "cancelado", "conclusão desfeita cancela o certificado ainda não entregue");

console.log("\n11. Auditoria e avisos");
const aud = (await master.rpc("listar_auditoria", { p_limite: 500 })).data;
for (const t of ["pagamentos", "comprovantes", "beneficios", "reembolsos", "certificados", "documentos"]) check(aud.some((x) => x.tabela === t), `movimentações em ${t} registradas`);
check(aud.some((x) => x.acao === "arquivo_consultado") && aud.some((x) => x.acao === "membresia_validada"), "consultas de arquivos e validações de membresia registradas");
check(aud.filter((x) => x.tabela === "pagamentos" && x.depois?.status === "aprovado").every((x) => x.ator === "Tadeu Tesoureiro Teste"), "cada aprovação registra quem aprovou");
const nTes = await notifs(tes);
await tes.rpc("marcar_notificacoes_lidas", { p_ids: nTes.itens.map((n) => n.id) });
check((await notifs(tes)).nao_lidas === 0 && (await notifs(sara)).nao_lidas > 0, "marcar como lido vale só para quem leu");

console.log(`\nResultado: ${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
