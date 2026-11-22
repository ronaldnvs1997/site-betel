// Etapa 3 — Cursos e Formação Betel: testes do backend (vagas, lista de espera, duplicidade,
// pré-requisitos, permissões, histórico e imagens), com chamadas diretas à API.
import { createClient } from "@supabase/supabase-js";
import { execFileSync } from "node:child_process";
import pg from "pg";
import fs from "node:fs";
import { paramsTermos, prepararVoluntario } from "./apoio-termos.mjs";

const URL_ = process.env.SUPABASE_URL, ANON = process.env.SUPABASE_ANON_KEY;
const novo = () => createClient(URL_, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
let ok = 0, falhas = 0;
const check = (c, n, x) => { if (c) { ok++; console.log("  ✓ " + n); } else { falhas++; console.log("  ✗ " + n + (x !== undefined ? "  → " + JSON.stringify(x) : "")); } };
const negado = (r) => !!r.error && ["42501", "PGRST301"].includes(r.error.code);
const sql = async (q, v) => { const c = new pg.Client({ host: "/tmp", port: 5434, user: "postgres", database: "betel" }); await c.connect(); const r = await c.query(q, v); await c.end(); return r.rows; };
async function entrar(email, senha, nova) { const c = novo(); const r = await c.auth.signInWithPassword({ email, password: senha }); if (r.error) throw new Error(r.error.message); if (nova) await c.auth.updateUser({ password: nova }); return c; }
const inscr = async (cli, turma, nome, tel, email, extra = {}) => cli.rpc("inscrever_curso_com_termos", { ...(await paramsTermos()), p_turma: turma, p_nome: nome, p_telefone: tel, p_email: email, p_data_nascimento: "1990-05-10", p_observacao: null, p_aceite_privacidade: true, p_origem: "site", ...extra });

console.log("\n0. Contas");
const saida = execFileSync("node", ["../scripts/criar-primeiros-masters.mjs", "Primeiro Master Teste|master1@exemplo.com|31900000001"], { env: process.env }).toString();
const master = await entrar("master1@exemplo.com", saida.match(/senha temporária: (\S+)/)[1], "Ezequiel-Nova-2026");
const mins = (await novo().from("ministerios").select("id,nome")).data, mid = (n) => mins.find((m) => m.nome === n).id;
const cria = async (nome, email, perfil, atrib, vinc) => (await master.functions.invoke("admin-usuarios", { body: { acao: "criar", nome, telefone: "31999990000", email, perfil, atribuicoes: atrib, ministerios: vinc } })).data;
const rE = await cria("Elaine Secretaria Teste", "elaine@teste.com", "LIDER", ["SECRETARIA"], [{ ministerio_id: mid("Secretaria"), funcao: "lider" }]);
const rL = await cria("Lia Líder Sem Secretaria", "lia@teste.com", "LIDER", [], [{ ministerio_id: mid("Juventude Mergulhados"), funcao: "lider" }]);
const sec = await entrar("elaine@teste.com", rE.senha_temporaria, "Elaine-Nova-2026");
const lider = await entrar("lia@teste.com", rL.senha_temporaria, "Lia-Nova-20261");
fs.writeFileSync("/tmp/cursos-contas.json", JSON.stringify({ master: "Ezequiel-Nova-2026", elaine: "Elaine-Nova-2026", lia: "Lia-Nova-20261" }));
check(!!sec && !!lider, "Secretaria (atribuição) e líder sem atribuição criadas");

console.log("\n1. Dados iniciais (sem informação inventada)");
const adm = (await sec.rpc("cursos_admin_listar")).data;
check(adm.categorias.map((c) => c.nome).join("|") === "Formação Teológica|Integração e Fundamentos|Serviço e Voluntariado", "3 categorias do planejamento");
check(adm.cursos.length === 7, "7 cursos do planejamento", adm.cursos.map((c) => c.titulo));
check(adm.cursos.every((c) => !c.descricao && !c.resumo && !c.carga_horaria && !c.imagem_url && !c.publico_alvo && c.turmas.length === 0 && !c.publicado), "nenhum dado inventado: sem descrição, carga horária, imagem ou turma; todos como rascunho");
const fv = adm.cursos.find((c) => c.slug === "formacao-de-voluntarios"), nm = adm.cursos.find((c) => c.slug === "novos-membros"), herm = adm.cursos.find((c) => c.slug === "hermeneutica");
check(fv.exige_membro && fv.exigidos_nomes.join() === "Curso de Novos Membros", "Formação de Voluntários exige membresia e o Curso de Novos Membros");

console.log("\n2. Permissões");
const anon = novo();
check((await anon.rpc("cursos_publicos")).data.every((c) => c.cursos.length === 0), "site não mostra cursos não publicados");
check((await anon.rpc("curso_publico", { p_slug: "fateb" })).data === null, "página de curso não publicado não abre");
check((await anon.from("cursos").select("id")).data?.length === 0, "rascunhos invisíveis também pela API");
check(negado(await anon.from("inscricoes").select("*")), "visitante não lê inscrições");
check(negado(await anon.rpc("cursos_admin_listar")), "visitante não acessa o painel de cursos");
check(negado(await lider.rpc("cursos_admin_listar")), "líder sem atribuição de Secretaria não acessa o painel");
check(negado(await lider.rpc("cursos_salvar_curso", { p: { id: herm.id, titulo: "Hackeado", categoria_id: herm.categoria_id, publicado: true } })), "líder não edita curso");
check(!(await master.rpc("cursos_admin_listar")).error, "MASTER acessa o painel de cursos");

console.log("\n3. Cadastro e publicação");
let r = await sec.rpc("cursos_salvar_curso", { p: { ...herm, resumo: "Princípios de interpretação bíblica.", publicado: true, cursos_exigidos: [] } });
check(!r.error, "Secretaria edita e publica Hermenêutica", r.error);
r = await sec.rpc("cursos_salvar_turma", { p: { curso_id: herm.id, nome: "Turma 1", status: "inscricoes_abertas", vagas: "2", lista_espera: true } });
const t1 = r.data.id; check(!r.error, "cria turma com 2 vagas e lista de espera");
check(!!(await sec.rpc("cursos_salvar_curso", { p: { ...herm, imagem_url: "javascript:alert(1)", cursos_exigidos: [] } })).error, "recusa imagem com endereço inválido");
check(/endereço/.test((await sec.rpc("cursos_salvar_curso", { p: { titulo: "Outro", slug: "hermeneutica", categoria_id: herm.categoria_id } })).error?.message || ""), "não duplica endereço de página");
check(/ele mesmo/.test((await sec.rpc("cursos_salvar_curso", { p: { ...herm, cursos_exigidos: [herm.id] } })).error?.message || ""), "curso não pode exigir ele mesmo");
const pub = (await anon.rpc("cursos_publicos")).data;
const cardHerm = pub.flatMap((c) => c.cursos).find((c) => c.slug === "hermeneutica");
check(cardHerm && cardHerm.turmas[0].aberta && cardHerm.turmas[0].vagas_restantes === 2, "site mostra o card com a turma aberta e 2 vagas");
check(pub.flatMap((c) => c.cursos).length === 1, "só o curso publicado aparece");

console.log("\n4. Vagas, lista de espera e duplicidade");
const a = await inscr(anon, t1, "Ana Participante", "31911110001", "ana@teste.com");
check(a.data?.status === "confirmada" && /^CUR-\d{4}-\d{6}$/.test(a.data.protocolo) && a.data.chave?.length >= 32, "1ª inscrição confirmada, com protocolo e chave pessoal", a.error || a.data);
const dup = await inscr(anon, t1, "Ana Participante", "31900000000", "ANA@teste.com");
check(dup.data?.duplicada === true && dup.data.protocolo === a.data.protocolo, "mesmo e-mail (maiúsculas) não gera 2ª inscrição");
const dup2 = await inscr(anon, t1, "Ana Outra Conta", "(31) 91111-0001", "ana.outra@teste.com");
check(dup2.data?.duplicada === true, "mesmo telefone na mesma turma também é barrado");
const b = await inscr(anon, t1, "Bruno Participante", "31911110002", "bruno@teste.com");
const c = await inscr(anon, t1, "Carla Participante", "31911110003", "carla@teste.com");
const d = await inscr(anon, t1, "Davi Participante", "31911110004", "davi@teste.com");
check(b.data.status === "confirmada" && c.data.status === "lista_espera" && c.data.posicao_espera === 1 && d.data.posicao_espera === 2, "vagas acabam: 3ª e 4ª pessoas vão para a lista de espera, em ordem");
check((await sql("select count(*)::int n from inscricoes where turma_id = $1", [t1]))[0].n === 4, "4 inscrições gravadas (nenhuma duplicada)");
check(negado(await anon.from("inscricoes").insert({ protocolo: "X", pessoa_id: crypto.randomUUID(), turma_id: t1, status: "confirmada", aceite_privacidade_em: new Date().toISOString(), chave_hash: "x", origem: "site" })), "ninguém grava inscrição direto na tabela");
check(negado(await sec.from("inscricoes").update({ status: "confirmada" }).eq("turma_id", t1)), "nem a Secretaria muda status direto na tabela (só pelas funções)");
check(!!(await inscr(anon, t1, "Sem Aceite Teste", "31911110009", "x@teste.com", { p_aceite_privacidade: false })).error, "exige a concordância com o uso dos dados");
check(!!(await inscr(anon, t1, "Fulano", "31911110009", "x@teste.com")).error, "exige nome completo");

console.log("\n5. Concorrência (vaga disputada ao mesmo tempo)");
const tc = (await sec.rpc("cursos_salvar_turma", { p: { curso_id: herm.id, nome: "Turma relâmpago", status: "inscricoes_abertas", vagas: "1", lista_espera: true } })).data.id;
const ps = await Promise.all([1, 2, 3, 4, 5].map((i) => inscr(novo(), tc, `Pessoa Simultanea ${i}`, `3192222000${i}`, `simul${i}@teste.com`)));
check(ps.filter((x) => x.data?.status === "confirmada").length === 1 && ps.filter((x) => x.data?.status === "lista_espera").length === 4, "5 pessoas ao mesmo tempo por 1 vaga: 1 confirmada, 4 na espera", ps.map((x) => x.data?.status || x.error?.message));
const ts = (await sec.rpc("cursos_salvar_turma", { p: { curso_id: herm.id, nome: "Turma sem espera", status: "inscricoes_abertas", vagas: "1", lista_espera: false } })).data.id;
const ps2 = await Promise.all([1, 2, 3, 4].map((i) => inscr(novo(), ts, `Pessoa Corrida ${i}`, `3193333000${i}`, `corrida${i}@teste.com`)));
check(ps2.filter((x) => !x.error).length === 1 && ps2.filter((x) => /esgotadas/.test(x.error?.message || "")).length === 3, "sem lista de espera: 1 entra, 3 recebem 'vagas esgotadas'");

console.log("\n6. Link pessoal: acompanhar e cancelar");
let mi = (await anon.rpc("minha_inscricao_curso", { p_protocolo: c.data.protocolo, p_chave: c.data.chave })).data;
check(mi.status === "lista_espera" && mi.posicao_espera === 1, "consulta pelo link mostra a posição na espera");
check(!!(await anon.rpc("minha_inscricao_curso", { p_protocolo: c.data.protocolo, p_chave: "chave-errada" })).error, "chave errada não abre a inscrição");
check(!(await anon.rpc("cancelar_minha_inscricao_curso", { p_protocolo: a.data.protocolo, p_chave: a.data.chave })).error, "participante cancela pelo link");
mi = (await anon.rpc("minha_inscricao_curso", { p_protocolo: c.data.protocolo, p_chave: c.data.chave })).data;
check(mi.status === "confirmada", "a vaga liberada vai automaticamente para a 1ª da lista de espera");
check((await anon.rpc("minha_inscricao_curso", { p_protocolo: d.data.protocolo, p_chave: d.data.chave })).data.posicao_espera === 1, "a fila anda: o próximo passa a ser o nº 1");

console.log("\n7. Painel da Secretaria");
let lista = (await sec.rpc("cursos_listar_inscricoes", { p_turma: t1 })).data;
const insB = lista.find((i) => i.nome === "Bruno Participante");
check(/motivo/.test((await sec.rpc("cursos_alterar_inscricao", { p_inscricao: insB.id, p_acao: "cancelar", p_motivo: "" })).error?.message || ""), "cancelar exige motivo");
check(!(await sec.rpc("cursos_alterar_inscricao", { p_inscricao: insB.id, p_acao: "cancelar", p_motivo: "Mudou de cidade" })).error, "Secretaria cancela com motivo");
lista = (await sec.rpc("cursos_listar_inscricoes", { p_turma: t1 })).data;
check(lista.find((i) => i.nome === "Davi Participante").status === "confirmada", "Davi sai da espera automaticamente");
check(/menor/.test((await sec.rpc("cursos_salvar_turma", { p: { id: t1, curso_id: herm.id, nome: "Turma 1", status: "inscricoes_abertas", vagas: "1", lista_espera: true } })).error?.message || ""), "não reduz vagas abaixo das já ocupadas");
const e = await inscr(anon, t1, "Eva Participante", "31911110005", "eva@teste.com");
check(e.data.status === "lista_espera", "Eva entra na espera");
r = await sec.rpc("cursos_salvar_turma", { p: { id: t1, curso_id: herm.id, nome: "Turma 1", status: "inscricoes_abertas", vagas: "3", lista_espera: true } });
check(r.data?.promovidos === 1, "aumentar as vagas chama a lista de espera automaticamente", r.data || r.error);
const insC = (await sec.rpc("cursos_listar_inscricoes", { p_turma: t1 })).data.find((i) => i.nome === "Carla Participante");
check(!(await sec.rpc("cursos_alterar_inscricao", { p_inscricao: insC.id, p_acao: "concluir" })).error, "marca Carla como concluída");
check(!(await sec.rpc("cursos_alterar_inscricao", { p_inscricao: insC.id, p_acao: "reabrir_conclusao" })).error, "desfaz a conclusão");
await sec.rpc("cursos_alterar_inscricao", { p_inscricao: insC.id, p_acao: "concluir" });
await sec.rpc("cursos_salvar_turma", { p: { id: t1, curso_id: herm.id, nome: "Turma 1", status: "inscricoes_encerradas", vagas: "3", lista_espera: true } });
check(/não estão abertas/.test((await inscr(anon, t1, "Fabio Atrasado", "31911110006", "fabio@teste.com")).error?.message || ""), "turma encerrada: o site não aceita inscrição");
const pelaSec = await inscr(sec, t1, "Fabio Atrasado", "31911110006", "fabio@teste.com", { p_origem: "secretaria" });
check(pelaSec.data?.status === "lista_espera", "a Secretaria ainda inscreve (respeitando as vagas: vai para a espera)", pelaSec.error || pelaSec.data);
check(negado(await inscr(lider, t1, "Gil Teste", "31911110007", "gil@teste.com", { p_origem: "secretaria" })), "líder sem atribuição não usa a inscrição pela Secretaria");
const futura = (await sec.rpc("cursos_salvar_turma", { p: { curso_id: herm.id, nome: "Turma futura", status: "inscricoes_abertas", inscricao_abre_em: new Date(Date.now() + 86400e3).toISOString() } })).data.id;
check(/não estão abertas/.test((await inscr(anon, futura, "Hugo Adiantado", "31911110008", "hugo@teste.com")).error?.message || ""), "antes da data de abertura, o site não aceita inscrição");
check((await anon.rpc("curso_publico", { p_slug: "hermeneutica" })).data.turmas.find((t) => t.id === futura).aberta === false, "e a página mostra a turma como ainda não aberta");

console.log("\n8. Pré-requisitos (Formação de Voluntários)");
await sec.rpc("cursos_salvar_curso", { p: { ...fv, publicado: true } });
const tfv = (await sec.rpc("cursos_salvar_turma", { p: { curso_id: fv.id, nome: "Turma 1", status: "inscricoes_abertas" } })).data.id;
check(/membresia/.test((await inscr(anon, tfv, "Carla Participante", "31911110003", "carla@teste.com")).error?.message || ""), "sem membresia validada: recusada");
await sql("update pessoas set situacao_membresia = 'membro', membresia_validada_em = now(), membresia_validada_por = (select id from perfis where perfil = 'MASTER' limit 1) where email = 'carla@teste.com'");
check(/Novos Membros/.test((await inscr(anon, tfv, "Carla Participante", "31911110003", "carla@teste.com")).error?.message || ""), "membro validado, mas sem o Curso de Novos Membros: recusada");
await sec.rpc("cursos_salvar_curso", { p: { ...nm, publicado: true } });
const tnm = (await sec.rpc("cursos_salvar_turma", { p: { curso_id: nm.id, nome: "Turma 1", status: "inscricoes_abertas", valor: "0" } })).data.id;
const inm = await inscr(anon, tnm, "Carla Participante", "31911110003", "carla@teste.com");
check(inm.data?.status === "confirmada", "Carla se inscreve no Curso de Novos Membros (gratuito)");
const idNm = (await sec.rpc("cursos_listar_inscricoes", { p_turma: tnm })).data[0].id;
await sec.rpc("cursos_alterar_inscricao", { p_inscricao: idNm, p_acao: "concluir" });
const ifv = await inscr(anon, tfv, "Carla Participante", "31911110003", "carla@teste.com");
check(ifv.data?.status === "confirmada", "depois de concluir, a inscrição na Formação de Voluntários é aceita", ifv.error);

console.log("\n9. Turma com valor");
const tp = (await sec.rpc("cursos_salvar_turma", { p: { curso_id: herm.id, nome: "Turma paga", status: "inscricoes_abertas", vagas: "1", valor: "50" } })).data.id;
const pago = await inscr(anon, tp, "Iara Participante", "31911110010", "iara@teste.com");
check(pago.data?.status === "aguardando_pagamento" && Number(pago.data.valor) === 50, "turma paga: inscrição fica aguardando pagamento (Tesouraria na Etapa 5)");
check((await inscr(anon, tp, "Joao Participante", "31911110011", "joao@teste.com")).data?.status === "lista_espera", "e ocupa a vaga: o próximo vai para a espera");

console.log("\n10. Participantes e histórico");
const part = (await sec.rpc("cursos_participantes", { p_busca: "91111-0003" })).data;
check(part.length === 1 && part[0].nome === "Carla Participante" && part[0].inscricoes === 3, "busca pelo telefone; Carla com 3 inscrições, um só cadastro");
const hist = (await sec.rpc("cursos_historico_participante", { p_pessoa: part[0].id })).data;
const hHerm = hist.inscricoes.find((i) => i.curso === "Hermenêutica");
check(hHerm.eventos.map((x) => x.para).join(">") === "lista_espera>confirmada>concluida>confirmada>concluida", "histórico completo: espera → confirmada → concluída (com a conclusão desfeita e refeita)", hHerm.eventos.map((x) => x.para));
check(hHerm.eventos.filter((x) => x.para === "concluida").every((x) => x.por === "Elaine Secretaria Teste"), "cada mudança mostra quem fez");
check(/outro cadastro/.test((await sec.rpc("cursos_atualizar_participante", { p_pessoa: part[0].id, p_nome: "Carla Participante", p_telefone: "31911110003", p_email: "ana@teste.com", p_data_nascimento: null })).error?.message || ""), "não deixa dois cadastros com o mesmo e-mail");
check(!(await sec.rpc("cursos_atualizar_participante", { p_pessoa: part[0].id, p_nome: "Carla Participante Souza", p_telefone: "31911110003", p_email: "carla@teste.com", p_data_nascimento: "1995-04-10" })).error, "Secretaria corrige o cadastro");
check(negado(await lider.rpc("cursos_historico_participante", { p_pessoa: part[0].id })), "líder sem atribuição não vê histórico de participantes");

console.log("\n11. Imagens (Storage)");
const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=", "base64");
r = await sec.storage.from("cursos").upload(`${herm.id}/capa.png`, png, { contentType: "image/png" });
check(!r.error, "Secretaria envia imagem", r.error);
const urlImg = sec.storage.from("cursos").getPublicUrl(`${herm.id}/capa.png`).data.publicUrl;
check((await fetch(urlImg)).status === 200, "imagem pública abre pelo endereço");
check(!!(await lider.storage.from("cursos").upload(`${herm.id}/x.png`, png, { contentType: "image/png" })).error, "líder sem atribuição não envia imagem");
check(!!(await anon.storage.from("cursos").upload(`x.png`, png, { contentType: "image/png" })).error, "visitante não envia imagem");
check(!!(await sec.storage.from("cursos").upload(`${herm.id}/x.svg`, Buffer.from("<svg/>"), { contentType: "image/svg+xml" })).error, "recusa tipo de arquivo não permitido (SVG)");
check(!!(await sec.storage.from("cursos").upload(`${herm.id}/grande.jpg`, Buffer.alloc(2_200_000), { contentType: "image/jpeg" })).error, "recusa arquivo acima de 2 MB");
check(!(await sec.rpc("cursos_salvar_curso", { p: { ...herm, resumo: "Princípios de interpretação bíblica.", publicado: true, cursos_exigidos: [], imagem_url: urlImg } })).error, "imagem ligada ao curso");

console.log("\n12. Auditoria");
let audR; for (let k = 0; k < 3; k++) { audR = await master.rpc("listar_auditoria", { p_limite: 500 }); if (!audR.error) break; await new Promise((r) => setTimeout(r, 500)); } if (audR.error) console.log("ERRO auditoria:", audR.error.message); const aud = audR.data || [];
check(aud.some((x) => x.tabela === "inscricoes") && aud.some((x) => x.tabela === "cursos" && x.acao === "update") && aud.some((x) => x.tabela === "turmas"), "inscrições, cursos e turmas registrados no histórico administrativo");
check(!JSON.stringify(aud).includes(a.data.chave), "a chave pessoal nunca é guardada (só o hash)");

console.log(`\nResultado: ${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
