// Etapa 5 — Novos Membros, Formação de Voluntários, termos e autorizações (backend).
import { createClient } from "@supabase/supabase-js";
import { execFileSync } from "node:child_process";
import pg from "pg";

const URL_ = process.env.SUPABASE_URL, ANON = process.env.SUPABASE_ANON_KEY;
const novo = () => createClient(URL_, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
let ok = 0, falhas = 0;
const check = (c, n, x) => { if (c) { ok++; console.log("  ✓ " + n); } else { falhas++; console.log("  ✗ " + n + (x !== undefined ? "  → " + JSON.stringify(x).slice(0, 400) : "")); } };
const negado = (r) => !!r.error && ["42501", "PGRST301"].includes(r.error.code);
const erro = (r, re) => !!r.error && re.test(r.error.message);
const sql = async (q, v) => { const c = new pg.Client({ host: "/tmp", port: 5434, user: "postgres", database: "betel" }); await c.connect(); try { return (await c.query(q, v)).rows; } finally { await c.end(); } };
const sqlErro = async (q, v) => { try { await sql(q, v); return ""; } catch (e) { return e.message; } };
async function entrar(email, senha, nova) { const c = novo(); const r = await c.auth.signInWithPassword({ email, password: senha }); if (r.error) throw new Error(r.error.message); if (nova) await c.auth.updateUser({ password: nova }); return c; }
async function fn(cli, nome, corpo) { const { data, error } = await cli.functions.invoke(nome, { body: corpo }); if (!error) return { data, status: 200 }; let j = {}; try { j = await error.context.json(); } catch (_) {} return { erro: j.erro, status: error.context?.status }; }
const hoje = new Date(), anos = (n) => `${hoje.getFullYear() - n}-01-15`;
const anon = novo();

console.log("\n0. Contas, cursos e turmas");
const saida = execFileSync("node", ["../scripts/criar-primeiros-masters.mjs", "Primeiro Master Teste|master1@exemplo.com|31900000001"], { env: process.env }).toString();
const master = await entrar("master1@exemplo.com", saida.match(/senha temporária: (\S+)/)[1], "Ezequiel-Nova-2026");
const mins = (await anon.from("ministerios").select("id,nome")).data, mid = (n) => mins.find((m) => m.nome === n).id;
const cria = async (nome, email, atr, mm) => (await master.functions.invoke("admin-usuarios", { body: { acao: "criar", nome, telefone: "31999990000", email, perfil: "LIDER", atribuicoes: atr, ministerios: mm } })).data;
const E = await cria("Elaine Secretaria Teste", "elaine@teste.com", ["SECRETARIA"], [{ ministerio_id: mid("Secretaria"), funcao: "lider" }]);
const L = await cria("Lia Lider Louvor", "lia@teste.com", [], [{ ministerio_id: mid("Louvor"), funcao: "lider" }]);
const K = await cria("Kai Lider Kids", "kai@teste.com", [], [{ ministerio_id: mid("Kids"), funcao: "lider" }]);
const M = await cria("Mara Lider Midia", "mara@teste.com", [], [{ ministerio_id: mid("Mídia"), funcao: "lider" }]);
const sec = await entrar("elaine@teste.com", E.senha_temporaria, "Elaine-Nova-2026"), lia = await entrar("lia@teste.com", L.senha_temporaria, "Lia-Nova-20261");
const kai = await entrar("kai@teste.com", K.senha_temporaria, "Kai-Nova-20261"), mara = await entrar("mara@teste.com", M.senha_temporaria, "Mara-Nova-2026");
const cursos = (await sec.rpc("cursos_admin_listar")).data.cursos, cur = (s) => cursos.find((c) => c.slug === s);
for (const s of ["novos-membros", "formacao-de-voluntarios", "hermeneutica"]) await sec.rpc("cursos_salvar_curso", { p: { ...cur(s), publicado: true } });
const turma = async (s) => (await sec.rpc("cursos_salvar_turma", { p: { curso_id: cur(s).id, nome: "Turma teste", status: "inscricoes_abertas", vagas: "50" } })).data.id;
const tNM = await turma("novos-membros"), tFV = await turma("formacao-de-voluntarios"), tHE = await turma("hermeneutica");
check(tNM && tFV && tHE, "turmas de Novos Membros, Formação de Voluntários e Hermenêutica abertas");
const inscr = (cli, t, nome, tel, email, nasc, extra = {}) => cli.rpc("inscrever_curso_com_termos", { p_turma: t, p_nome: nome, p_telefone: tel, p_email: email, p_data_nascimento: nasc,
  p_observacao: null, p_aceite_privacidade: true, p_termo_participacao: extra.termo ?? null, p_imagem: extra.imagem ?? null, p_responsavel: extra.resp ?? null, p_origem: extra.origem ?? "site", p_termo_presencial: extra.presencial ?? false });

console.log("\n1. Termos versionados");
let r = await inscr(anon, tHE, "Ana Adulta Teste", "31911110001", "ana@teste.com", anos(30));
check(erro(r, /ainda não foi publicado/), "sem termo publicado, a inscrição fica fechada (não há aceite implícito)", r.error);
check(negado(await anon.rpc("inscrever_curso", { p_turma: tHE, p_nome: "Ana Adulta Teste", p_telefone: "31911110001", p_email: "ana@teste.com", p_data_nascimento: null, p_observacao: null, p_aceite_privacidade: true, p_origem: "site" })), "a inscrição antiga, sem termos, não pode mais ser chamada");
check(negado(await anon.rpc("secretaria_termos")) && negado(await lia.rpc("secretaria_termos")), "visitante e líder não gerenciam termos");
let termos = (await sec.rpc("secretaria_termos")).data;
check(termos.length === 3 && termos.every((t) => t.status === "rascunho" && t.pendencias?.length), "3 modelos chegam como rascunho, com campos ⟦…⟧ a preencher");
const tp = (tipo) => termos.find((t) => t.tipo === tipo);
check(erro(await sec.rpc("secretaria_publicar_termo", { p_termo: tp("participacao_curso").id }), /⟦/), "termo com campos em aberto não é publicado");
for (const t of termos) {
  const texto = t.texto.replace(/⟦[^⟧]*⟧/g, (m) => (m.includes("CNPJ") ? "CNPJ 00.000.000/0001-00 (teste)" : "secretaria@teste.com"));
  await sec.rpc("secretaria_salvar_termo", { p: { id: t.id, tipo: t.tipo, titulo: t.titulo, resumo: t.resumo, texto, exige_novo_aceite: false } });
  r = await sec.rpc("secretaria_publicar_termo", { p_termo: t.id }); if (r.error) console.log(r.error.message);
}
let vig = (await anon.rpc("termos_vigentes")).data;
check(vig.participacao_curso?.versao === 1 && vig.imagem_voz && vig.voluntariado, "os três termos publicados e visíveis no site");
check(/não muda/.test(await sqlErro("update termos set texto = texto || ' alterado' where id = $1", [vig.imagem_voz.id])), "o texto de um termo publicado não pode ser alterado nem por SQL direto");
check(/não pode ser excluído/.test(await sqlErro("delete from termos where id = $1", [vig.imagem_voz.id])), "termo publicado não pode ser excluído");
check(erro(await sec.rpc("secretaria_salvar_termo", { p: { id: vig.imagem_voz.id, tipo: "imagem_voz", titulo: "Novo título qualquer", texto: "x".repeat(60) } }), /Só rascunhos/), "editar termo em vigor exige nova versão");
check((await sql("select texto_hash from termos where id = $1", [vig.participacao_curso.id]))[0].texto_hash.length === 64, "o hash do texto publicado fica registrado");
const TP = vig.participacao_curso.id, TI = vig.imagem_voz.id, TV = vig.voluntariado.id;

console.log("\n2. Inscrição com termo de participação; imagem opcional");
r = await inscr(anon, tHE, "Ana Adulta Teste", "31911110001", "ana@teste.com", anos(30));
check(erro(r, /aceitar o termo de participação/), "sem aceitar o termo de participação, não inscreve");
r = await inscr(anon, tHE, "Ana Adulta Teste", "31911110001", "ana@teste.com", null, { termo: TP });
check(erro(r, /data de nascimento/), "data de nascimento é obrigatória (para saber se é menor)");
const ana = (await inscr(anon, tHE, "Ana Adulta Teste", "31911110001", "ana@teste.com", anos(30), { termo: TP })).data;
check(ana?.protocolo && ana.status === "confirmada", "REGRA: adulto se inscreve SEM autorizar imagem", ana);
let mt = (await anon.rpc("meus_termos", { p_protocolo: ana.protocolo, p_chave: ana.chave })).data;
check(mt.consentimentos.length === 1 && mt.consentimentos[0].tipo === "participacao_curso" && mt.consentimentos[0].dado_por === "titular", "fica registrado só o aceite do termo de participação, pelo titular");
const bia = (await inscr(anon, tHE, "Bia Adulta Teste", "31911110002", "bia@teste.com", anos(25), { termo: TP, imagem: { termo_id: TI, decisao: "recusado", escopo: {} } })).data;
check(bia?.status === "confirmada", "quem NÃO autoriza a imagem se inscreve normalmente");
check(erro(await inscr(anon, tHE, "Caio Adulto Teste", "31911110003", "caio@teste.com", anos(40), { termo: TP, imagem: { termo_id: TI, decisao: "aceito", escopo: {} } }), /fotos, vídeos ou voz/), "autorizar imagem exige escolher fotos, vídeos ou voz");
const caio = (await inscr(anon, tHE, "Caio Adulto Teste", "31911110003", "caio@teste.com", anos(40), { termo: TP, imagem: { termo_id: TI, decisao: "aceito", escopo: { fotos: true, videos: true } } })).data;
mt = (await anon.rpc("meus_termos", { p_protocolo: caio.protocolo, p_chave: caio.chave })).data;
const imgCaio = mt.consentimentos.find((c) => c.tipo === "imagem_voz");
check(imgCaio?.em_vigor && imgCaio.escopo.fotos && imgCaio.escopo.videos && !imgCaio.escopo.voz, "autorização granular registrada (fotos e vídeos, sem voz)");
check(erro(await inscr(anon, tHE, "Davi Adulto Teste", "31911110009", "davi@teste.com", anos(40), { termo: crypto.randomUUID() }), /aceitar o termo/), "aceite de termo inexistente ou antigo é recusado");

console.log("\n3. Menores de 18 anos");
check(erro(await inscr(anon, tHE, "Theo Menor Teste", "31911110004", "theo@teste.com", anos(15), { termo: TP }), /responsável legal/), "menor sem responsável legal não se inscreve");
check(erro(await inscr(anon, tHE, "Theo Menor Teste", "31911110004", "theo@teste.com", anos(15), { termo: TP, resp: { nome: "Rita", parentesco: "mae", telefone: "31988887777", declara_responsavel: true } }), /nome completo do responsável/), "nome do responsável precisa ser completo");
check(erro(await inscr(anon, tHE, "Theo Menor Teste", "31911110004", "theo@teste.com", anos(15), { termo: TP, resp: { nome: "Rita Menor Teste", parentesco: "mae", telefone: "31988887777", declara_responsavel: false } }), /declarar/), "o responsável precisa declarar que é o responsável legal");
const resp = { nome: "Rita Responsavel Teste", parentesco: "mae", telefone: "(31) 98888-7777", email: "rita@teste.com", declara_responsavel: true };
const theo = (await inscr(anon, tHE, "Theo Menor Teste", "31911110004", "theo@teste.com", anos(15), { termo: TP, resp, imagem: { termo_id: TI, decisao: "aceito", escopo: { fotos: true } } })).data;
check(theo?.menor === true && theo.status === "confirmada", "menor inscrito com a autorização do responsável");
mt = (await anon.rpc("meus_termos", { p_protocolo: theo.protocolo, p_chave: theo.chave })).data;
check(mt.consentimentos.every((c) => c.dado_por === "responsavel" && c.responsavel === "Rita Responsavel Teste"), "participação e imagem do menor registradas como dadas pela responsável");
check(/menor_na_data/.test(await sqlErro("insert into consentimentos (pessoa_id, termo_id, tipo, decisao, dado_por, menor_na_data, origem, texto_hash) select pessoa_id, $1, 'imagem_voz', 'recusado', 'titular', true, 'site', 'x' from inscricoes where protocolo = $2", [TI, theo.protocolo])) ||
  /check/.test(await sqlErro("insert into consentimentos (pessoa_id, termo_id, tipo, decisao, dado_por, menor_na_data, origem, texto_hash) select pessoa_id, $1, 'imagem_voz', 'recusado', 'titular', true, 'site', 'x' from inscricoes where protocolo = $2", [TI, theo.protocolo])),
  "o banco recusa consentimento de menor dado pelo próprio menor");
check((await sql("select responsavel->>'telefone' t from consentimentos c join inscricoes i on i.pessoa_id = c.pessoa_id where i.protocolo = $1 limit 1", [theo.protocolo]))[0].t === "31988887777", "dados do responsável guardados (só nome, vínculo e contato; sem documento)");

console.log("\n4. Autorização pelo link, revogação e histórico");
check(erro(await anon.rpc("autorizar_imagem_link", { p_protocolo: ana.protocolo, p_chave: "errada", p_termo: TI, p_decisao: "aceito", p_escopo: { fotos: true }, p_responsavel: null, p_data_nascimento: null }), /não encontrada/), "link com chave errada não autoriza nada");
check(!(await anon.rpc("autorizar_imagem_link", { p_protocolo: ana.protocolo, p_chave: ana.chave, p_termo: TI, p_decisao: "aceito", p_escopo: { voz: true }, p_responsavel: null, p_data_nascimento: null })).error, "a titular autoriza depois, pelo link");
check(erro(await anon.rpc("autorizar_imagem_link", { p_protocolo: theo.protocolo, p_chave: theo.chave, p_termo: TI, p_decisao: "aceito", p_escopo: { fotos: true, videos: true }, p_responsavel: null, p_data_nascimento: null }), /responsável legal/), "no link do menor, a mudança também exige o responsável");
mt = (await anon.rpc("meus_termos", { p_protocolo: caio.protocolo, p_chave: caio.chave })).data;
const partCaio = mt.consentimentos.find((c) => c.tipo === "participacao_curso");
check(erro(await anon.rpc("revogar_consentimento_link", { p_protocolo: caio.protocolo, p_chave: caio.chave, p_consentimento: partCaio.id, p_motivo: null }), /Secretaria/), "pelo link só se revoga imagem e voz (demais termos pela Secretaria)");
check(!(await anon.rpc("revogar_consentimento_link", { p_protocolo: caio.protocolo, p_chave: caio.chave, p_consentimento: imgCaio.id, p_motivo: "Mudei de ideia" })).error, "o titular revoga a autorização de imagem pelo link");
check(erro(await anon.rpc("revogar_consentimento_link", { p_protocolo: caio.protocolo, p_chave: caio.chave, p_consentimento: imgCaio.id, p_motivo: null }), /já foi revogada/), "não revoga duas vezes");
mt = (await anon.rpc("meus_termos", { p_protocolo: caio.protocolo, p_chave: caio.chave })).data;
check(mt.consentimentos.find((c) => c.id === imgCaio.id).revogado_em && !mt.consentimentos.find((c) => c.id === imgCaio.id).em_vigor, "a revogação aparece no histórico do titular");
check(erro(await anon.rpc("revogar_consentimento_link", { p_protocolo: ana.protocolo, p_chave: ana.chave, p_consentimento: imgCaio.id, p_motivo: null }), /não encontrada/), "ninguém revoga a autorização de outra pessoa");
check((await (await notifsDe(sec)).itens).some((n) => n.tipo === "imagem_revogada"), "Secretaria é avisada da revogação de imagem");
check(/não podem ser excluídos/.test(await sqlErro("delete from consentimentos where id = $1", [imgCaio.id])), "consentimentos não podem ser apagados");
{ const e = await sqlErro("update consentimentos set decisao = 'recusado' where id = $1", [partCaio.id]); check(/só revogados/.test(e), "consentimentos não podem ser alterados (só revogados)", e); }
check(negado(await anon.from("consentimentos").select("*")) && negado(await lia.from("consentimentos").select("*")), "ninguém lê a tabela de consentimentos diretamente");
async function notifsDe(c) { return (await c.rpc("minhas_notificacoes", { p_limite: 200 })).data; }

console.log("\n5. Nova versão do termo");
const pessoaAna = (await sec.rpc("secretaria_pessoas", { p_busca: "ana@teste.com" })).data[0].id;
let cons = (await mara.rpc("imagem_consultar", { p_busca: "Adulta Teste" })).data;
check(cons.find((p) => p.nome === "Ana Adulta Teste").situacao === "autorizado" && cons.find((p) => p.nome === "Bia Adulta Teste").situacao === "nao_autorizado", "Mídia consulta: Ana autorizou (voz), Bia não autorizou");
await sec.rpc("secretaria_salvar_termo", { p: { tipo: "imagem_voz", titulo: "Autorização de uso de imagem e voz (v2)", resumo: "Opcional.", texto: (await sql("select texto from termos where id = $1", [TI]))[0].texto + "\nInclui transmissões ao vivo.", exige_novo_aceite: true } });
const v2 = (await sec.rpc("secretaria_termos")).data.find((t) => t.tipo === "imagem_voz" && t.versao === 2);
check(v2?.status === "rascunho", "nova versão nasce como rascunho (a v1 continua valendo até a publicação)");
await sec.rpc("secretaria_publicar_termo", { p_termo: v2.id });
termos = (await sec.rpc("secretaria_termos")).data;
check(termos.find((t) => t.id === TI).status === "substituido" && termos.find((t) => t.id === v2.id).status === "vigente", "publicada a v2, a v1 fica como substituída");
cons = (await mara.rpc("imagem_consultar", { p_busca: "Ana Adulta" })).data;
check(cons[0].situacao === "sem_autorizacao", "a v2 exige novo aceite: a autorização da v1 deixa de valer");
check(erro(await anon.rpc("autorizar_imagem_link", { p_protocolo: ana.protocolo, p_chave: ana.chave, p_termo: TI, p_decisao: "aceito", p_escopo: { voz: true }, p_responsavel: null, p_data_nascimento: null }), /atualizado/), "aceitar a versão antiga não é mais possível");
await anon.rpc("autorizar_imagem_link", { p_protocolo: ana.protocolo, p_chave: ana.chave, p_termo: v2.id, p_decisao: "aceito", p_escopo: { voz: true, fotos: true }, p_responsavel: null, p_data_nascimento: null });
check((await mara.rpc("imagem_consultar", { p_busca: "Ana Adulta" })).data[0].situacao === "autorizado", "com o aceite da v2, volta a constar como autorizada");
mt = (await anon.rpc("meus_termos", { p_protocolo: ana.protocolo, p_chave: ana.chave })).data;
check(mt.consentimentos.filter((c) => c.tipo === "imagem_voz").length === 2 && mt.consentimentos.filter((c) => c.tipo === "imagem_voz" && c.em_vigor).length === 1, "o histórico guarda as duas decisões; só a última vale");
check(negado(await lia.rpc("imagem_consultar", { p_busca: "Ana Adulta" })) && negado(await anon.rpc("imagem_consultar", { p_busca: "Ana" })), "só a Secretaria e o ministério de Mídia consultam autorizações de imagem");
check(erro(await mara.rpc("imagem_consultar", { p_busca: "An" }), /3 letras/), "a consulta exige busca por nome (não lista todo mundo)");

console.log("\n6. Membresia: interesse, Novos Membros e validação");
r = await anon.rpc("membresia_interesse", { p_nome: "Gabriel Novo Membro", p_telefone: "31911110010", p_email: "gabriel@teste.com", p_data_nascimento: anos(28), p_mensagem: "Quero ser membro", p_aceite_privacidade: true });
check(r.data?.ok, "visitante manifesta interesse em ser membro");
let procs = (await sec.rpc("secretaria_processos_membresia", { p_status: null })).data;
const pGab = procs.find((p) => p.nome === "Gabriel Novo Membro");
check(pGab?.status === "interesse" && pGab.situacao_membresia === "visitante", "REGRA: manifestar interesse não torna ninguém membro (continua visitante)");
check((await notifsDe(sec)).itens.some((n) => n.tipo === "interesse_membresia"), "Secretaria é avisada do interesse");
check(negado(await anon.rpc("secretaria_processos_membresia", { p_status: null })) && negado(await lia.rpc("secretaria_validar_membresia", { p_pessoa: pGab.pessoa_id, p_situacao: "membro", p_membro_desde: "2026-01-01", p_observacao: "Eu mesmo declaro que sou membro" })), "visitante e líder não validam membresia");
check(negado(await anon.rpc("secretaria_validar_membresia", { p_pessoa: pGab.pessoa_id, p_situacao: "membro", p_membro_desde: "2026-01-01", p_observacao: "autodeclaração" })), "não existe caminho público para se declarar membro");
const gab = (await inscr(anon, tNM, "Gabriel Novo Membro", "31911110010", "gabriel@teste.com", anos(28), { termo: TP })).data;
procs = (await sec.rpc("secretaria_processos_membresia", { p_status: null })).data;
check(procs.find((p) => p.nome === "Gabriel Novo Membro").status === "em_curso", "ao se inscrever no Curso de Novos Membros, o processo passa para \"no curso\"");
const insGab = (await sql("select id from inscricoes where protocolo = $1", [gab.protocolo]))[0].id;
await sec.rpc("cursos_alterar_inscricao", { p_inscricao: insGab, p_acao: "concluir", p_motivo: null });
procs = (await sec.rpc("secretaria_processos_membresia", { p_status: null })).data;
check(procs.find((p) => p.nome === "Gabriel Novo Membro").status === "aguardando_validacao", "curso concluído: aguardando a validação da Secretaria");
check((await notifsDe(sec)).itens.some((n) => n.tipo === "membresia_aguardando"), "Secretaria é avisada para validar");
check(erro(await sec.rpc("secretaria_validar_membresia", { p_pessoa: pGab.pessoa_id, p_situacao: "membro", p_membro_desde: "2026-11-20", p_observacao: "ok" }), /fundamento/), "validar exige o fundamento (batismo, carta, ata)");
check(!(await sec.rpc("secretaria_validar_membresia", { p_pessoa: pGab.pessoa_id, p_situacao: "membro", p_membro_desde: "2026-11-20", p_observacao: "Batismo em 20/11/2026, ata da assembleia nº 12" })).error, "Secretaria valida a membresia com fundamento");
check((await sec.rpc("secretaria_processos_membresia", { p_status: "validado" })).data.some((p) => p.nome === "Gabriel Novo Membro"), "processo encerrado como validado");
check((await sql("select membresia_validada_por is not null v from pessoas where id = $1", [pGab.pessoa_id]))[0].v, "fica registrado quem validou");

console.log("\n7. Regra do voluntariado no banco");
const pAna = pessoaAna;
check(/membresia validada pela Secretaria e o Curso de Novos Membros/.test(await sqlErro("insert into ministerio_membros (pessoa_id, ministerio_id, funcao) values ($1, $2, 'voluntario')", [pAna, mid("Louvor")])), "REGRA: nem SQL direto põe não-membro como voluntário");
r = await fn(master, "admin-usuarios", { acao: "criar", nome: "Ana Adulta Teste", telefone: "31911110001", email: "ana@teste.com", perfil: "VOLUNTARIO", atribuicoes: [], ministerios: [{ ministerio_id: mid("Louvor"), funcao: "voluntario" }] });
check(r.status >= 400 && /Novos Membros/.test(r.erro || ""), "nem o MASTER cria conta de voluntário para quem não cumpre a regra", r);
check(!(await sql("select 1 from perfis p join pessoas pe on pe.id = p.pessoa_id where pe.email = 'ana@teste.com'")).length, "a conta não ficou criada pela metade");
// membro validado sem Novos Membros
const pessoaBia = (await sec.rpc("secretaria_pessoas", { p_busca: "bia@teste.com" })).data[0].id;
check((await sec.rpc("secretaria_pessoas", { p_busca: "bia@teste.com" })).data.length === 1, "busca por e-mail traz só a pessoa certa (correção da busca da Etapa 4)");
await sec.rpc("secretaria_validar_membresia", { p_pessoa: pessoaBia, p_situacao: "membro", p_membro_desde: "2015-03-01", p_observacao: "Carta de transferência recebida em 2015" });
check(/Curso de Novos Membros concluído/.test(await sqlErro("insert into ministerio_membros (pessoa_id, ministerio_id, funcao) values ($1, $2, 'voluntario')", [pessoaBia, mid("Louvor")])), "membro validado, mas sem Novos Membros, ainda não pode ser voluntário");
r = await inscr(anon, tFV, "Bia Adulta Teste", "31911110002", "bia@teste.com", anos(25), { termo: TP }); check(erro(r, /Novos Membros/), "Formação de Voluntários exige o Curso de Novos Membros", r.error);
check(erro(await sec.rpc("secretaria_registrar_conclusao_anterior", { p_pessoa: pessoaBia, p_curso: cur("novos-membros").id, p_concluido_em: "2015-02-01", p_comprovacao: "fez", p_documento: null }), /comprovação/), "conclusão anterior exige descrever a comprovação");
check(negado(await lia.rpc("secretaria_registrar_conclusao_anterior", { p_pessoa: pessoaBia, p_curso: cur("novos-membros").id, p_concluido_em: "2015-02-01", p_comprovacao: "Lista de presença conferida", p_documento: null })), "só a Secretaria registra conclusão anterior");
check(!(await sec.rpc("secretaria_registrar_conclusao_anterior", { p_pessoa: pessoaBia, p_curso: cur("novos-membros").id, p_concluido_em: "2015-02-01", p_comprovacao: "Lista de presença da turma de 2015 conferida pela Secretaria", p_documento: null })).error, "Secretaria registra o Novos Membros feito em 2015");
check(erro(await inscr(anon, tFV, "Caio Adulto Teste", "31911110003", "caio@teste.com", anos(40), { termo: TP }), /membros com a membresia validada/), "não-membro não entra na Formação de Voluntários");
r = await inscr(anon, tFV, "Bia Adulta Teste", "31911110002", "bia@teste.com", anos(25), { termo: TP }); if (r.error) console.log(r.error.message); const biaFV = r.data;
const gabFV = (await inscr(anon, tFV, "Gabriel Novo Membro", "31911110010", "gabriel@teste.com", anos(28), { termo: TP })).data;
check(biaFV?.status === "confirmada" && gabFV?.status === "confirmada", "membros com Novos Membros se inscrevem na Formação de Voluntários");
check((await anon.rpc("minha_candidatura", { p_protocolo: biaFV.protocolo, p_chave: biaFV.chave })).data === null, "antes de concluir a Formação, não há candidatura");
for (const p of [biaFV, gabFV]) { const id = (await sql("select id from inscricoes where protocolo = $1", [p.protocolo]))[0].id; await sec.rpc("cursos_alterar_inscricao", { p_inscricao: id, p_acao: "concluir", p_motivo: null }); }
let cand = (await anon.rpc("minha_candidatura", { p_protocolo: biaFV.protocolo, p_chave: biaFV.chave })).data;
check(cand?.status === "aguardando_indicacao" && cand.termo?.id === TV && !cand.telefone, "Formação concluída: candidatura aberta, com o termo de adesão (sem expor contatos no link)");

console.log("\n8. Indicação de ministérios e termo de adesão");
check(erro(await anon.rpc("voluntariado_indicar", { p_protocolo: biaFV.protocolo, p_chave: biaFV.chave, p_ministerios: [mid("Louvor"), mid("Kids"), mid("Mídia"), mid("EBD")], p_termo: TV, p_responsavel: null }), /1 a 3/), "no máximo 3 ministérios");
check(erro(await anon.rpc("voluntariado_indicar", { p_protocolo: biaFV.protocolo, p_chave: biaFV.chave, p_ministerios: [mid("Louvor")], p_termo: null, p_responsavel: null }), /Termo/), "sem o termo de adesão (Lei 9.608/1998), não indica");
check(!(await anon.rpc("voluntariado_indicar", { p_protocolo: biaFV.protocolo, p_chave: biaFV.chave, p_ministerios: [mid("Louvor"), mid("Kids")], p_termo: TV, p_responsavel: null })).error, "Bia indica Louvor e Kids e aceita o termo de adesão");
check(erro(await anon.rpc("voluntariado_indicar", { p_protocolo: biaFV.protocolo, p_chave: biaFV.chave, p_ministerios: [mid("EBD")], p_termo: TV, p_responsavel: null }), /Não há candidatura/), "não indica de novo depois de enviar");
check((await notifsDe(lia)).itens.some((n) => n.tipo === "candidatura_ministerio") && (await notifsDe(kai)).itens.some((n) => n.tipo === "candidatura_ministerio") && !(await notifsDe(mara)).itens.some((n) => n.tipo === "candidatura_ministerio"), "líderes de Louvor e Kids são avisados; a líder de Mídia, não");
let lc = (await lia.rpc("lider_candidaturas")).data;
const indLouvor = lc[0]?.para_mim.find((i) => i.ministerio === "Louvor");
check(lc.length === 1 && lc[0].para_mim.length === 1 && indLouvor, "a líder de Louvor vê a candidata e só decide pelo próprio ministério");
check((await mara.rpc("lider_candidaturas")).data.length === 0, "a líder de Mídia não vê candidatos de outros ministérios");
const indKids = (await kai.rpc("lider_candidaturas")).data[0].para_mim[0].indicacao_id;
check(negado(await lia.rpc("lider_decidir_indicacao", { p_indicacao: indKids, p_acao: "aprovar", p_motivo: null })), "líder de Louvor não decide pelo Kids");
check(negado(await sec.rpc("lider_decidir_indicacao", { p_indicacao: indKids, p_acao: "aprovar", p_motivo: null })), "a Secretaria encaminha, mas a aprovação é da liderança");
check(erro(await kai.rpc("lider_decidir_indicacao", { p_indicacao: indKids, p_acao: "recusar", p_motivo: "" }), /motivo/), "não aprovar exige explicar o motivo");
check(!(await kai.rpc("lider_decidir_indicacao", { p_indicacao: indKids, p_acao: "recusar", p_motivo: "No momento a equipe do Kids está completa" })).error, "Kids não aprova (com motivo)");
check(!(await lia.rpc("lider_decidir_indicacao", { p_indicacao: indLouvor.indicacao_id, p_acao: "aprovar", p_motivo: null })).error, "Louvor aprova");
cand = (await anon.rpc("minha_candidatura", { p_protocolo: biaFV.protocolo, p_chave: biaFV.chave })).data;
check(cand.status === "aprovada", "candidatura aprovada");
check((await sql("select funcao, ativo from ministerio_membros where pessoa_id = $1 and ministerio_id = $2", [pessoaBia, mid("Louvor")]))[0]?.ativo, "Bia entra como voluntária no Louvor");
const solBia = (await master.rpc("listar_solicitacoes", { p_status: "pendente" })).data.find((s) => s.email === "bia@teste.com");
check(solBia?.funcao === "voluntario" && solBia.ministerio === "Louvor", "o pedido de acesso à Área da Equipe vai para o MASTER");
const ap = await fn(master, "aprovar-acesso", { solicitacao_id: solBia.id, perfil: "VOLUNTARIO", atribuicoes: [], ministerios: [{ ministerio_id: mid("Louvor"), funcao: "voluntario" }] });
check(ap.status === 200 && ap.data?.senha_temporaria, "MASTER aprova o acesso: a conta de voluntária é criada", ap);
// candidatura sem aprovação
await anon.rpc("voluntariado_indicar", { p_protocolo: gabFV.protocolo, p_chave: gabFV.chave, p_ministerios: [mid("Kids")], p_termo: TV, p_responsavel: null });
const indG = (await kai.rpc("lider_candidaturas")).data.find((c) => c.nome === "Gabriel Novo Membro").para_mim[0].indicacao_id;
await kai.rpc("lider_decidir_indicacao", { p_indicacao: indG, p_acao: "recusar", p_motivo: "Perfil mais adequado a outro ministério" });
check((await anon.rpc("minha_candidatura", { p_protocolo: gabFV.protocolo, p_chave: gabFV.chave })).data.status === "nao_aprovada" && (await notifsDe(sec)).itens.some((n) => n.tipo === "candidatura_nao_aprovada"), "sem nenhuma aprovação, a candidatura encerra e a Secretaria faz o retorno");

console.log("\n9. Voluntários antigos, termo em papel e revogação do termo de adesão");
// simula um voluntário cadastrado antes da regra (dado existente não é apagado)
await sql("alter table ministerio_membros disable trigger ministerio_membros_voluntario_requisitos");
await sql("insert into ministerio_membros (pessoa_id, ministerio_id, funcao) values ($1, $2, 'voluntario')", [pAna, mid("Diaconia")]);
await sql("alter table ministerio_membros enable trigger ministerio_membros_voluntario_requisitos");
let sc = (await sec.rpc("secretaria_candidaturas", { p_status: null })).data;
check(sc.pendencias.some((p) => p.nome === "Ana Adulta Teste"), "voluntário anterior à regra aparece em pendências, sem ser removido");
check((await sql("select ativo from ministerio_membros where pessoa_id = $1 and ministerio_id = $2", [pAna, mid("Diaconia")]))[0].ativo, "o vínculo antigo continua ativo (nenhum dado apagado)");
// Secretaria abre candidatura para quem fez a Formação antes do sistema e registra o termo em papel
const pessoaCaio = (await sec.rpc("secretaria_pessoas", { p_busca: "caio@teste.com" })).data[0].id;
check(erro(await sec.rpc("secretaria_abrir_candidatura", { p_pessoa: pessoaCaio }), /membresia validada/), "candidatura manual também exige os requisitos");
await sec.rpc("secretaria_validar_membresia", { p_pessoa: pessoaCaio, p_situacao: "membro", p_membro_desde: "2010-05-01", p_observacao: "Batismo em 2010, ata nº 3" });
for (const s of ["novos-membros", "formacao-de-voluntarios"]) await sec.rpc("secretaria_registrar_conclusao_anterior", { p_pessoa: pessoaCaio, p_curso: cur(s).id, p_concluido_em: "2012-01-01", p_comprovacao: "Certificado original apresentado à Secretaria", p_documento: null });
const cCaio = (await sec.rpc("secretaria_abrir_candidatura", { p_pessoa: pessoaCaio })).data.id;
check(erro(await sec.rpc("secretaria_indicar_ministerios", { p_candidatura: cCaio, p_ministerios: [mid("Louvor")], p_termo: TV, p_termo_presencial: false, p_responsavel: null, p_documento: null }), /assinado/), "indicação pela Secretaria exige confirmar o termo assinado");
check(!(await sec.rpc("secretaria_indicar_ministerios", { p_candidatura: cCaio, p_ministerios: [mid("Louvor")], p_termo: TV, p_termo_presencial: true, p_responsavel: null, p_documento: null })).error, "Secretaria indica o ministério com o termo de adesão em papel");
const iC = (await lia.rpc("lider_candidaturas")).data.find((c) => c.nome === "Caio Adulto Teste").para_mim[0].indicacao_id;
await lia.rpc("lider_decidir_indicacao", { p_indicacao: iC, p_acao: "aprovar", p_motivo: null });
const fichaCaio = (await sec.rpc("secretaria_ficha_pessoa", { p_pessoa: pessoaCaio })).data;
const termoCaio = fichaCaio.consentimentos.find((c) => c.tipo === "voluntariado");
check(termoCaio?.origem === "secretaria" && fichaCaio.ministerios.some((m) => m.ministerio === "Louvor" && m.ativo), "Caio aprovado; termo registrado como \"pela Secretaria\"");
check(erro(await sec.rpc("secretaria_revogar_consentimento", { p_consentimento: termoCaio.id, p_via: "titular", p_motivo: "" }), /motivo/), "revogação exige registrar o motivo/pedido");
r = await sec.rpc("secretaria_revogar_consentimento", { p_consentimento: termoCaio.id, p_via: "titular", p_motivo: "Pediu para sair do voluntariado (por WhatsApp)" });
check(r.data?.vinculos_desativados === 1, "revogar o termo de adesão desativa o vínculo de voluntário (sem apagar)");
check(!(await sql("select ativo from ministerio_membros where pessoa_id = $1 and ministerio_id = $2", [pessoaCaio, mid("Louvor")]))[0].ativo, "Caio fica inativo no Louvor");
check(negado(await lia.rpc("secretaria_revogar_consentimento", { p_consentimento: termoCaio.id, p_via: "secretaria", p_motivo: "teste de permissão" })), "líder não revoga consentimentos");

console.log("\n10. Registro em papel pela Secretaria e inscrição pelo painel");
const pessoaTheo = (await sec.rpc("secretaria_pessoas", { p_busca: "theo@teste.com" })).data[0].id;
check(erro(await sec.rpc("secretaria_registrar_consentimento", { p_pessoa: pessoaTheo, p_tipo: "imagem_voz", p_termo: v2.id, p_decisao: "recusado", p_escopo: {}, p_responsavel: null, p_documento: null, p_data_nascimento: null }), /responsável legal/), "mesmo em papel, decisão do menor exige o responsável");
check(!(await sec.rpc("secretaria_registrar_consentimento", { p_pessoa: pessoaTheo, p_tipo: "imagem_voz", p_termo: v2.id, p_decisao: "recusado", p_escopo: {}, p_responsavel: resp, p_documento: null, p_data_nascimento: null })).error, "Secretaria registra a recusa entregue em papel pela responsável");
check((await mara.rpc("imagem_consultar", { p_busca: "Theo Menor" })).data[0].situacao === "nao_autorizado", "Mídia passa a ver Theo como não autorizado");
check(erro(await inscr(sec, tHE, "Lucas Painel Teste", "31911110020", "lucas@teste.com", anos(33), { termo: TP, origem: "secretaria" }), /assinado/), "inscrição pelo painel exige confirmar o termo assinado");
r = await inscr(sec, tHE, "Lucas Painel Teste", "31911110020", "lucas@teste.com", anos(33), { termo: TP, origem: "secretaria", presencial: true });
check(r.data?.protocolo, "Secretaria inscreve com termo assinado em papel");
check(negado(await inscr(lia, tHE, "Lucas Dois Teste", "31911110021", "lucas2@teste.com", anos(33), { termo: TP, origem: "secretaria", presencial: true })), "líder sem atribuição não inscreve pelo painel");

console.log("\n11. Auditoria");
const aud = (await master.rpc("listar_auditoria", { p_limite: 500 })).data || [];
for (const t of ["termos", "consentimentos", "membresia_processos", "voluntariado_candidaturas", "voluntariado_indicacoes", "cursos_conclusoes_anteriores"]) check(aud.some((x) => x.tabela === t), `alterações em ${t} registradas no histórico`);
check(aud.some((x) => x.acao === "membresia_validada" && x.detalhes?.observacao?.includes("Batismo")), "a validação guarda o fundamento no histórico");

console.log(`\nResultado: ${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
