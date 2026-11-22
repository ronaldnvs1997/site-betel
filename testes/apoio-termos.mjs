// Apoio aos testes a partir da M07: publica os termos-modelo e prepara pessoas
// que cumprem a regra do voluntariado (como a Secretaria faria no painel).
import pg from "pg";
const sql = async (q, v) => { const c = new pg.Client({ host: "/tmp", port: 5434, user: "postgres", database: "betel" }); await c.connect(); try { return (await c.query(q, v)).rows; } finally { await c.end(); } };
export async function m07() { return (await sql("select to_regclass('public.termos') is not null as ok"))[0].ok; }
export async function publicarTermos() {
  if (!(await m07())) return null;
  await sql(`update termos set texto = regexp_replace(texto, '⟦[^⟧]*⟧', 'secretaria@teste.com', 'g') where status = 'rascunho'`);
  await sql(`update termos set status = 'vigente', publicado_em = now(), texto_hash = encode(sha256(convert_to(titulo || E'\\n' || texto, 'UTF8')), 'hex')
             where status = 'rascunho' and not exists (select 1 from termos v where v.tipo = termos.tipo and v.status = 'vigente')`);
  return Object.fromEntries((await sql("select tipo, id from termos where status = 'vigente'")).map((r) => [r.tipo, r.id]));
}
// parâmetros extras da inscrição com termos (adulto, sem imagem)
export async function paramsTermos() { const t = await publicarTermos(); return { p_termo_participacao: t.participacao_curso, p_imagem: null, p_responsavel: null, p_termo_presencial: true }; }
// pessoa já membro validada e com Novos Membros concluído antes do sistema
export async function prepararVoluntario(nome, email, telefone) {
  if (!(await m07())) return;
  const ator = (await sql("select id from perfis where perfil = 'MASTER' order by criado_em limit 1"))[0].id;
  let p = (await sql("select id from pessoas where email = $1", [email]))[0];
  if (!p) p = (await sql("insert into pessoas (nome, email, telefone, origem) values ($1, $2, $3, 'secretaria') returning id", [nome, email, telefone]))[0];
  await sql("update pessoas set situacao_membresia = 'membro', membro_desde = '2015-01-01', membresia_validada_por = $2, membresia_validada_em = now() where id = $1", [p.id, ator]);
  await sql(`insert into cursos_conclusoes_anteriores (pessoa_id, curso_id, concluido_em, comprovacao, registrado_por)
             select $1, id, '2015-01-01', 'Preparação do teste automatizado', $2 from cursos where slug = 'novos-membros'
             on conflict do nothing`, [p.id, ator]);
}
