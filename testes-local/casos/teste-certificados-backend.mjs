// Etapa 6 — Certificados e cerimônias (backend): validação, autorização, cerimônias, impressão e entrega física.
import { createClient } from "@supabase/supabase-js";
import { execFileSync } from "node:child_process";
import pg from "pg";
import { publicarTermos } from "./apoio-termos.mjs";

const URL_ = process.env.SUPABASE_URL, ANON = process.env.SUPABASE_ANON_KEY;
const novo = () => createClient(URL_, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
let ok = 0, falhas = 0;
const check = (c, n, x) => { if (c) { ok++; console.log("  ✓ " + n); } else { falhas++; console.log("  ✗ " + n + (x !== undefined ? "  → " + JSON.stringify(x).slice(0, 400) : "")); } };
const negado = (r) => !!r.error && ["42501", "PGRST301"].includes(r.error.code);
const erro = (r, re) => !!r.error && re.test(r.error.message);
const sql = async (q, v) => { const c = new pg.Client({ host: "/tmp", port: 5434, user: "postgres", database: "betel" }); await c.connect(); try { return (await c.query(q, v)).rows; } finally { await c.end(); } };
const sqlErro = async (q, v) => { try { await sql(q, v); return ""; } catch (e) { return e.message; } };
async function entrar(email, senha, nova) { const c = novo(); const r = await c.auth.signInWithPassword({ email, password: senha }); if (r.error) throw new Error(r.error.message); if (nova) await c.auth.updateUser({ password: nova }); return c; }
const dia = (n) => { const d = new Date(); d.setDate(d.getDate() + n); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`; };
const anon = novo();

console.log("\n0. Contas, cursos e inscrições");
const saida = execFileSync("node", ["../scripts/criar-primeiros-masters.mjs", "Primeiro Master Teste|master1@exemplo.com|31900000001"], { env: process.env }).toString();
const master = await entrar("master1@exemplo.com", saida.match(/senha temporária: (\S+)/)[1], "Ezequiel-Nova-2026");
const mins = (await anon.from("ministerios").select("id,nome")).data, mid = (n) => mins.find((m) => m.nome === n).id;
const cria = async (nome, email, atr, mm) => (await master.functions.invoke("admin-usuarios", { body: { acao: "criar", nome, telefone: "31999990000", email, perfil: "LIDER", atribuicoes: atr, ministerios: mm } })).data;
const E = await cria("Elaine Secretaria Teste", "elaine@teste.com", ["SECRETARIA"], [{ ministerio_id: mid("Secretaria"), funcao: "lider" }]);
const L = await cria("Lia Lider Louvor", "lia@teste.com", [], [{ ministerio_id: mid("Louvor"), funcao: "lider" }]);
const K = await cria("Kai Lider Kids", "kai@teste.com", [], [{ ministerio_id: mid("Kids"), funcao: "lider" }]);
const P = await cria("Paulo Lider EBD", "paulo@teste.com", [], [{ ministerio_id: mid("EBD"), funcao: "lider" }]);
const sec = await entrar("elaine@teste.com", E.senha_temporaria, "Elaine-Nova-2026"), lia = await entrar("lia@teste.com", L.senha_temporaria, "Lia-Nova-20261");
const kai = await entrar("kai@teste.com", K.senha_temporaria, "Kai-Nova-20261"), paulo = await entrar("paulo@teste.com", P.senha_temporaria, "Paulo-Nova-2026");
const T = await publicarTermos();
const cursos = (await sec.rpc("cursos_admin_listar")).data.cursos, cur = (s) => cursos.find((c) => c.slug === s);
await sec.rpc("cursos_salvar_curso", { p: { ...cur("hermeneutica"), publicado: true } });
await sec.rpc("cursos_salvar_curso", { p: { ...cur("homiletica"), publicado: true, ministerio_id: mid("EBD") } });
r0: { const r = await sec.rpc("cursos_salvar_curso", { p: { ...cur("vida-de-paulo"), publicado: true, modalidade: "online", plataforma_url: "https://exemplo.org/aulas" } }); if (r.error) console.log(r.error.message); }
const turma = async (s) => (await sec.rpc("cursos_salvar_turma", { p: { curso_id: cur(s).id, nome: "Turma teste", status: "inscricoes_abertas", vagas: "30" } })).data.id;
const tH = await turma("hermeneutica"), tHo = await turma("homiletica"), tOn = await turma("vida-de-paulo");
const inscr = async (t, nome, n, email) => (await anon.rpc("inscrever_curso_com_termos", { p_turma: t, p_nome: nome, p_telefone: "319111100" + n, p_email: email, p_data_nascimento: "1990-05-10",
  p_observacao: null, p_aceite_privacidade: true, p_termo_participacao: T.participacao_curso, p_imagem: null, p_responsavel: null, p_origem: "site", p_termo_presencial: false })).data;
const A = await inscr(tH, "Ana Aluna Teste", "01", "ana@teste.com"), B = await inscr(tH, "Bruno Aluno Teste", "02", "bruno@teste.com"), C = await inscr(tH, "Carla Aluna Teste", "03", "carla@teste.com");
const D = await inscr(tHo, "Davi Aluno Teste", "04", "davi@teste.com"), O = await inscr(tOn, "Olga Aluna Online", "05", "olga@teste.com");
const idIns = async (x) => (await sql("select id from inscricoes where protocolo = $1", [x.protocolo]))[0].id;
const iA = await idIns(A), iB = await idIns(B), iC = await idIns(C), iD = await idIns(D), iO = await idIns(O);
check([A, B, C, D, O].every((x) => x?.status === "confirmada"), "5 inscrições confirmadas (presencial, EBD e um curso online)");
const certDe = async (i) => (await sql("select * from certificados where inscricao_id = $1", [i]))[0];

console.log("\n1. Quem valida a conclusão");
const perfil = async (email) => (await sql("select p.id from perfis p join pessoas pe on pe.id = p.pessoa_id where pe.email = $1", [email]))[0].id;
const pLia = await perfil("lia@teste.com");
check(negado(await lia.rpc("cursos_definir_responsaveis", { p_turma: tH, p_perfis: [pLia] })), "líder não define os responsáveis da turma");
check(erro(await sec.rpc("cursos_definir_responsaveis", { p_turma: tH, p_perfis: [crypto.randomUUID()] }), /Responsável inválido/), "responsável precisa ser líder com conta ativa");
check(!(await sec.rpc("cursos_definir_responsaveis", { p_turma: tH, p_perfis: [pLia] })).error && !(await sec.rpc("cursos_definir_responsaveis", { p_turma: tOn, p_perfis: [pLia] })).error, "Secretaria define a Lia como responsável pela turma de Hermenêutica e pela turma online");
check((await sec.rpc("cursos_responsaveis_turma", { p_turma: tH })).data[0]?.nome === "Lia Lider Louvor", "responsáveis da turma listados");
const tl = (await lia.rpc("lider_turmas_validacao")).data;
check(tl.length === 2 && tl.some((t) => t.curso === "Hermenêutica" && t.inscricoes.length === 3), "Lia vê só as turmas pelas quais responde");
check((await kai.rpc("lider_turmas_validacao")).data.length === 0, "Kai (não responsável) não vê turma nenhuma");
check((await paulo.rpc("lider_turmas_validacao")).data.some((t) => t.curso === "Homilética"), "a liderança do ministério do curso (EBD) também valida");
check(negado(await anon.rpc("lider_turmas_validacao")), "visitante não acessa");

console.log("\n2. Validação de conclusão pela liderança");
check(negado(await kai.rpc("lider_concluir_validar", { p_inscricao: iA, p_observacao: null })), "líder de outro ministério não conclui");
check(negado(await sec.rpc("lider_concluir_validar", { p_inscricao: iA, p_observacao: null })), "a Secretaria não valida conclusão (separação de funções)");
check(!(await lia.rpc("lider_concluir_validar", { p_inscricao: iA, p_observacao: "100% de frequência" })).error, "Lia conclui e valida a Ana");
let cA = await certDe(iA);
check(cA?.status === "aguardando_autorizacao" && cA.validado_por === pLia && cA.observacao_validacao === "100% de frequência", "certificado da Ana: validado pela Lia, aguardando autorização");
await sec.rpc("cursos_alterar_inscricao", { p_inscricao: iB, p_acao: "concluir", p_motivo: null });
await sec.rpc("cursos_alterar_inscricao", { p_inscricao: iC, p_acao: "concluir", p_motivo: null });
check((await certDe(iB)).status === "aguardando_validacao", "conclusão marcada pela Secretaria fica aguardando a validação da liderança");
check(erro(await sec.rpc("secretaria_certificado", { p_certificado: (await certDe(iB)).id, p_acao: "autorizar" }), /liderança valida/), "REGRA: sem validação da liderança, a Secretaria não autoriza");
check(negado(await kai.rpc("lider_validar_certificado", { p_certificado: (await certDe(iB)).id, p_acao: "validar", p_observacao: null })), "Kai não valida certificado de turma que não acompanha");
check(!(await lia.rpc("lider_validar_certificado", { p_certificado: (await certDe(iB)).id, p_acao: "validar", p_observacao: null })).error && (await certDe(iB)).status === "aguardando_autorizacao", "Lia valida a conclusão do Bruno");
check(erro(await lia.rpc("lider_validar_certificado", { p_certificado: (await certDe(iC)).id, p_acao: "nao_validar", p_observacao: "" }), /Explique/), "não validar exige o motivo");
await lia.rpc("lider_validar_certificado", { p_certificado: (await certDe(iC)).id, p_acao: "nao_validar", p_observacao: "Frequência abaixo do mínimo" });
const cC = await certDe(iC), insC = (await sql("select status from inscricoes where id = $1", [iC]))[0].status;
check(cC.status === "cancelado" && /Frequência abaixo/.test(cC.motivo_cancelamento) && insC === "confirmada", "conclusão não validada: certificado cancelado com o motivo e a Carla volta a \"cursando\"");
const avisos = (await sec.rpc("minhas_notificacoes", { p_limite: 100 })).data.itens;
check(avisos.some((n) => n.tipo === "certificado_autorizar") && avisos.some((n) => n.tipo === "certificado_nao_validado"), "Secretaria recebe os avisos de autorizar e de não validação");
check((await lia.rpc("minhas_notificacoes", { p_limite: 50 })).data.itens.some((n) => n.tipo === "certificado_validar"), "a responsável pela turma é avisada quando há conclusão para validar");
await lia.rpc("lider_concluir_validar", { p_inscricao: iO, p_observacao: "Concluiu as aulas online" });
await paulo.rpc("lider_concluir_validar", { p_inscricao: iD, p_observacao: null });
await master.rpc("cursos_definir_responsaveis", { p_turma: tHo, p_perfis: [] });

console.log("\n3. Autorização da emissão pela Secretaria");
check(negado(await lia.rpc("secretaria_certificado", { p_certificado: cA.id, p_acao: "autorizar" })), "líder não autoriza a emissão");
// o MASTER valida e tenta autorizar o próprio validado
await sec.rpc("cursos_alterar_inscricao", { p_inscricao: iC, p_acao: "concluir", p_motivo: null });
await master.rpc("lider_validar_certificado", { p_certificado: (await certDe(iC)).id, p_acao: "validar", p_observacao: "Reposição de aulas comprovada" });
check(erro(await master.rpc("secretaria_certificado", { p_certificado: (await certDe(iC)).id, p_acao: "autorizar" }), /Quem validou/), "quem validou a conclusão não autoriza a emissão (outra pessoa autoriza)");
check(/certificados_fluxo_check/.test(await sqlErro("update certificados set status = 'autorizado', autorizado_em = now(), autorizado_por = validado_por where id = $1", [(await certDe(iC)).id])), "a separação vale até para SQL direto");
for (const i of [iA, iB, iC, iD, iO]) { const r = await sec.rpc("secretaria_certificado", { p_certificado: (await certDe(i)).id, p_acao: "autorizar" }); if (r.error) console.log(r.error.message); }
cA = await certDe(iA);
check(cA.status === "autorizado" && cA.autorizado_por === (await perfil("elaine@teste.com")), "Elaine autoriza a emissão (registro de quem autorizou)");

console.log("\n4. Cerimônias: data, horário e local");
check(negado(await lia.rpc("secretaria_salvar_cerimonia", { p: { titulo: "Teste", data: dia(5), horario: "19:30", local: "Templo" } })), "só a Secretaria cadastra cerimônias");
check(erro(await sec.rpc("secretaria_salvar_cerimonia", { p: { titulo: "Entrega no culto", data: dia(5), horario: "19:30" } }), /data, horário e local/), "data, horário e local são obrigatórios");
check(erro(await sec.rpc("secretaria_salvar_cerimonia", { p: { titulo: "Entrega no culto", data: dia(5), horario: "19h", local: "Templo" } }), /HH:MM/), "horário no formato HH:MM");
check(erro(await sec.rpc("secretaria_salvar_cerimonia", { p: { titulo: "Entrega no culto", data: dia(-1), horario: "19:30", local: "Templo" } }), /já passou/), "não cadastra cerimônia com data passada");
const futura = (await sec.rpc("secretaria_salvar_cerimonia", { p: { titulo: "Culto de formatura", tipo: "culto", data: dia(10), horario: "19:30", local: "Templo", responsavel: "Pastor da igreja" } })).data.id;
const hojeCer = (await sec.rpc("secretaria_salvar_cerimonia", { p: { titulo: "Apresentação da EBD", tipo: "apresentacao", data: dia(0), horario: "09:00", local: "Salão" } })).data.id;
check(futura && hojeCer, "cerimônias cadastradas (culto daqui a 10 dias e apresentação hoje)");
check(erro(await sec.rpc("secretaria_salvar_cerimonia", { p: { id: futura, titulo: "Culto de formatura", data: dia(10), horario: "19:30", local: "Templo", status: "realizada" } }), /Marcar como realizada/), "\"realizada\" só pelo botão próprio");

console.log("\n5. Vínculo e preparação para impressão");
const cO = await certDe(iO);
check(erro(await sec.rpc("secretaria_certificado", { p_certificado: cA.id, p_acao: "imprimir" }), /Vincule/), "não imprime sem vincular a uma cerimônia");
check(!(await sec.rpc("secretaria_certificado", { p_certificado: cA.id, p_acao: "vincular", p_dados: { cerimonia_id: futura } })).error && (await certDe(iA)).status === "preparado", "certificado da Ana vinculado ao culto de formatura");
const lote = await sec.rpc("secretaria_vincular_cerimonia", { p_cerimonia: futura, p_certificados: [(await certDe(iB)).id, (await certDe(iC)).id, cO.id] });
check(lote.data?.vinculados === 3, "vínculo em lote: Bruno, Carla e Olga (curso online) na mesma cerimônia");
check(!(await sec.rpc("secretaria_certificado", { p_certificado: (await certDe(iD)).id, p_acao: "vincular", p_dados: { cerimonia_id: hojeCer } })).error, "Davi vinculado à apresentação de hoje");
check(erro(await sec.rpc("secretaria_salvar_cerimonia", { p: { id: futura, titulo: "Culto de formatura", data: dia(10), horario: "19:30", local: "Templo", status: "cancelada" } }), /transfira/), "não cancela cerimônia com certificados vinculados");

console.log("\n6. Impressão (só administrativos autorizados)");
check(negado(await lia.rpc("secretaria_certificado", { p_certificado: cA.id, p_acao: "imprimir" })) && negado(await kai.rpc("secretaria_imprimir_cerimonia", { p_cerimonia: futura })), "líderes não acessam a impressão");
check(negado(await anon.rpc("secretaria_certificado", { p_certificado: cA.id, p_acao: "imprimir" })), "visitante não acessa a impressão");
let r = await sec.rpc("secretaria_certificado", { p_certificado: cA.id, p_acao: "imprimir" });
check(r.data?.impressao?.nome === "Ana Aluna Teste" && r.data.impressao.curso === "Hermenêutica" && r.data.impressao.cerimonia === "Culto de formatura", "Secretaria recebe os dados de impressão da Ana");
check(erro(await sec.rpc("secretaria_certificado", { p_certificado: cA.id, p_acao: "imprimir" }), /motivo da reimpressão/), "reimpressão exige motivo");
check(!(await sec.rpc("secretaria_certificado", { p_certificado: cA.id, p_acao: "imprimir", p_dados: { motivo: "Papel manchado na impressora" } })).error && (await certDe(iA)).vezes_impresso === 2, "reimpressão com motivo registrada (2ª impressão)");
r = await sec.rpc("secretaria_imprimir_cerimonia", { p_cerimonia: futura });
check(r.data?.impressoes?.length === 3 && r.data.impressoes.some((x) => x.modalidade === "online"), "impressão em lote dos 3 pendentes da cerimônia (inclui o curso online)");
check(erro(await sec.rpc("secretaria_imprimir_cerimonia", { p_cerimonia: futura }), /Nenhum certificado pendente/), "o lote não reimprime o que já foi impresso");
check(erro(await sec.rpc("secretaria_salvar_modelo_certificado", { p: { assinaturas: [{ nome: "A" }, { nome: "B" }, { nome: "C" }, { nome: "D" }] } }), /3 assinaturas/), "modelo aceita no máximo 3 assinaturas");
await sec.rpc("secretaria_salvar_modelo_certificado", { p: { igreja: "Igreja Batista Betel no Flamengo", cidade: "Contagem/MG", texto: "concluiu com aproveitamento o curso", assinaturas: [{ nome: "Nome do pastor (teste)", cargo: "Pastor" }] } });
r = await sec.rpc("secretaria_certificado", { p_certificado: (await certDe(iD)).id, p_acao: "imprimir" });
check(r.data.impressao.modelo.assinaturas[0].cargo === "Pastor" && r.data.impressao.modelo.texto.includes("aproveitamento"), "a impressão usa o modelo definido pela Secretaria");
const lista = (await sec.rpc("secretaria_lista_cerimonia", { p_cerimonia: futura })).data;
check(lista.participantes.length === 4 && lista.cerimonia.local === "Templo", "lista de entrega da cerimônia com os 4 participantes");

console.log("\n7. Entrega física");
const ent = (c, d) => sec.rpc("secretaria_certificado", { p_certificado: c, p_acao: "entregar", p_dados: d });
check(erro(await ent(cA.id, { ocasiao: "cerimonia", relacao: "participante", recebido_por: "Ana Aluna Teste", confirmo_entrega_fisica: true }), /ainda não aconteceu/), "REGRA: não marca entregue antes da cerimônia acontecer");
check(erro(await ent((await certDe(iD)).id, { ocasiao: "cerimonia", relacao: "participante", recebido_por: "Davi Aluno Teste" }), /em mãos/), "exige confirmar a entrega em mãos");
check(erro(await ent((await certDe(iD)).id, { ocasiao: "cerimonia", relacao: "participante", recebido_por: "Davi", confirmo_entrega_fisica: true }), /nome completo/), "exige o nome completo de quem recebeu");
check(erro(await ent((await certDe(iD)).id, { ocasiao: "cerimonia", relacao: "pessoa_autorizada", recebido_por: "Maria Mãe Teste", confirmo_entrega_fisica: true }), /quem autorizou/), "entrega a terceiro exige registrar quem autorizou");
check(negado(await lia.rpc("secretaria_certificado", { p_certificado: (await certDe(iD)).id, p_acao: "entregar", p_dados: { ocasiao: "cerimonia", relacao: "participante", recebido_por: "Davi Aluno Teste", confirmo_entrega_fisica: true } })), "líder não registra entrega");
check(!(await ent((await certDe(iD)).id, { ocasiao: "cerimonia", relacao: "participante", recebido_por: "Davi Aluno Teste", confirmo_entrega_fisica: true })).error, "Davi recebe na apresentação de hoje: entrega registrada");
const cD = await certDe(iD);
check(cD.status === "entregue" && cD.entregue_por === (await perfil("elaine@teste.com")) && cD.entrega_ocasiao === "cerimonia", "fica registrado quem entregou, quando e em que ocasião");
check(erro(await sec.rpc("secretaria_certificado", { p_certificado: cD.id, p_acao: "cancelar", p_dados: { motivo: "teste de alteração" } }), /já entregue/), "certificado entregue não muda mais");
check(erro(await ent((await certDe(iB)).id, { ocasiao: "secretaria", relacao: "participante", recebido_por: "Bruno Aluno Teste", confirmo_entrega_fisica: true }), /explique a ocasião/), "entrega fora da cerimônia exige justificativa");
check(!(await ent((await certDe(iB)).id, { ocasiao: "secretaria", relacao: "participante", recebido_por: "Bruno Aluno Teste", observacao: "Viaja na data do culto; retirou em mãos na Secretaria", confirmo_entrega_fisica: true })).error, "Bruno retira em mãos na Secretaria (com justificativa)");
check(/certificados_fluxo_check/.test(await sqlErro("update certificados set status = 'entregue' where id = $1", [(await certDe(iC)).id])), "nem SQL direto marca entregue sem o registro da entrega física");
// troca da Ana para a cerimônia de hoje e entrega
check(!(await sec.rpc("secretaria_certificado", { p_certificado: cA.id, p_acao: "vincular", p_dados: { cerimonia_id: hojeCer } })).error, "Ana transferida para a apresentação de hoje");
check(!(await ent(cA.id, { ocasiao: "cerimonia", relacao: "participante", recebido_por: "Ana Aluna Teste", confirmo_entrega_fisica: true })).error, "Ana recebe em mãos");

console.log("\n8. O participante nunca recebe o arquivo");
for (const [x, n] of [[A, "Ana (entregue)"], [O, "Olga (curso online, impresso)"]]) {
  const m = (await anon.rpc("minha_inscricao_curso", { p_protocolo: x.protocolo, p_chave: x.chave })).data, js = JSON.stringify(m);
  check(m.certificado && !/codigo|url|arquivo|pdf|download/i.test(js.replace(/plataforma_url/g, "")), `${n}: o link mostra só a situação, sem código, arquivo ou download`);
}
check((await anon.rpc("minha_inscricao_curso", { p_protocolo: O.protocolo, p_chave: O.chave })).data.certificado.status === "impresso", "curso online segue o mesmo fluxo de entrega presencial");
check(negado(await anon.from("certificados").select("*")) && negado(await lia.from("certificados").select("*")) && negado(await sec.from("certificados_eventos").select("*")), "ninguém lê as tabelas de certificados diretamente");

console.log("\n9. Cerimônia realizada e histórico");
check(erro(await sec.rpc("secretaria_cerimonia_realizada", { p_cerimonia: futura }), /ainda não aconteceu/), "não marca como realizada antes da data");
r = await sec.rpc("secretaria_cerimonia_realizada", { p_cerimonia: hojeCer });
check(r.data?.ok && r.data.nao_entregues === 0, "apresentação de hoje marcada como realizada");
check(erro(await sec.rpc("secretaria_salvar_cerimonia", { p: { id: hojeCer, titulo: "Apresentação da EBD", data: dia(0), horario: "09:00", local: "Salão" } }), /já realizada/), "cerimônia realizada não pode ser alterada");
const hist = (await sec.rpc("secretaria_certificado_historico", { p_certificado: cA.id })).data, evs = hist.map((e) => e.evento);
check(JSON.stringify(evs) === JSON.stringify(["criado", "emissao_autorizada", "vinculado_cerimonia", "impresso", "reimpresso", "vinculado_cerimonia", "entregue"]), "histórico completo da Ana: gerado, autorizado, vinculado, impresso, reimpresso, transferido, entregue", evs);
check(hist.find((e) => e.evento === "reimpresso").detalhes.motivo === "Papel manchado na impressora" && hist.find((e) => e.evento === "entregue").ator === "Elaine Secretaria Teste", "o histórico guarda o motivo da reimpressão e quem entregou");
check(hist[0].detalhes.validada_na_conclusao === true, "o histórico registra que a conclusão foi validada pela liderança");
check(/não pode ser alterado/.test(await sqlErro("delete from certificados_eventos where certificado_id = $1", [cA.id])) && /não pode ser alterado/.test(await sqlErro("update certificados_eventos set evento = 'x' where certificado_id = $1", [cA.id])), "o histórico não pode ser apagado nem alterado");
check(/não podem ser excluídos/.test(await sqlErro("delete from certificados where id = $1", [cA.id])), "certificados não podem ser apagados");
check(negado(await lia.rpc("secretaria_certificado_historico", { p_certificado: cA.id })), "o histórico é restrito à Secretaria");

console.log(`\nResultado: ${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
