// Instalação e atualização automática do banco.
// Aplica, em ordem e uma única vez, a base da plataforma, as tabelas da Agenda,
// os dados exportados do sistema anterior (se houver) e as migrações M01 em diante.
// Cada etapa fica registrada em sistema.migracoes; ao iniciar de novo, só roda o que falta.

/**
 * @param {object} o
 * @param {(sql:string)=>Promise<void>} o.exec        executa um arquivo SQL inteiro (várias instruções)
 * @param {(sql:string, p?:any[])=>Promise<{rows:any[]}>} o.query
 * @param {{nome:string, sql:string}[]} o.etapas    base + migrações, na ordem
 * @param {object} [o.agendaAnterior]  { eventos: csv, reservas: csv, coordenadores: csv } — só na primeira instalação
 * @param {(m:string)=>void} [o.log]
 */
export async function instalar(o) {
  const log = o.log || (() => {});
  await o.exec("create schema if not exists sistema; create table if not exists sistema.migracoes (nome text primary key, aplicada_em timestamptz not null default now());");
  const feitas = new Set((await o.query("select nome from sistema.migracoes")).rows.map((r) => r.nome));
  const primeira = !feitas.size;
  let novas = 0;
  for (const e of o.etapas) {
    if (feitas.has(e.nome)) continue;
    log(`Aplicando ${e.nome}…`);
    await o.exec(e.sql);
    await o.query("insert into sistema.migracoes (nome) values ($1) on conflict do nothing", [e.nome]);
    novas++;
    // dados da Agenda anterior entram logo depois das tabelas-base e antes das migrações que as transformam
    if (e.nome === "001_agenda_base" && primeira && o.agendaAnterior) {
      const n = await importarAgenda(o, o.agendaAnterior);
      log(`Agenda anterior importada: ${n.eventos} eventos, ${n.reservas} reservas, ${n.coordenadores} coordenadores.`);
    }
  }
  log(novas ? `Banco atualizado (${novas} etapa(s)).` : "Banco já estava atualizado.");
  return { novas, primeira };
}

// CSV exportado do painel do Supabase (cabeçalho na 1ª linha; campos entre aspas quando preciso)
export function lerCsv(texto) {
  const linhas = []; let campo = "", linha = [], aspas = false;
  const t = String(texto || "").replace(/^﻿/, "");
  for (let i = 0; i < t.length; i++) {
    const ch = t[i];
    if (aspas) { if (ch === '"') { if (t[i + 1] === '"') { campo += '"'; i++; } else aspas = false; } else campo += ch; }
    else if (ch === '"') aspas = true;
    else if (ch === ",") { linha.push(campo); campo = ""; }
    else if (ch === "\n" || ch === "\r") { if (ch === "\r" && t[i + 1] === "\n") i++; linha.push(campo); campo = ""; if (linha.some((x) => x !== "")) linhas.push(linha); linha = []; }
    else campo += ch;
  }
  if (campo !== "" || linha.length) { linha.push(campo); if (linha.some((x) => x !== "")) linhas.push(linha); }
  if (!linhas.length) return [];
  const cab = linhas[0].map((c) => c.trim());
  return linhas.slice(1).map((l) => Object.fromEntries(cab.map((c, i) => [c, l[i] === undefined || l[i] === "" ? null : l[i]])));
}

async function importarAgenda(o, dados) {
  // Cada linha entra separada (ponto de salvamento): uma linha com problema não impede as demais
  // nem a instalação. As linhas recusadas são contadas no registro, sem expor dados pessoais.
  const n = {}, log = o.log || (() => {});
  await o.query("begin");
  try {
    for (const tabela of ["eventos", "reservas", "coordenadores"]) {
      const registros = lerCsv(dados[tabela]);
      const tipos = Object.fromEntries((await o.query("select column_name, data_type from information_schema.columns where table_schema = 'public' and table_name = $1", [tabela])).rows.map((r) => [r.column_name, r.data_type]));
      n[tabela] = 0; let recusadas = 0, motivo = "";
      for (const r of registros) {
        if (tabela === "coordenadores" && (r.senha === null || r.senha === undefined)) r.senha = "";   // a M03 elimina as senhas antigas
        const ks = Object.keys(r).filter((k) => tipos[k]);
        if (!ks.length) continue;
        const vals = ks.map((k) => (tipos[k] === "boolean" ? (r[k] === null ? null : /^(true|t|1|sim|yes)$/i.test(String(r[k]).trim())) : r[k]));
        await o.query("savepoint linha");
        try {
          await o.query(`insert into public.${tabela} (${ks.map((k) => `"${k}"`).join(",")}) overriding system value values (${ks.map((_, i) => `$${i + 1}`).join(",")})`, vals);
          await o.query("release savepoint linha"); n[tabela]++;
        } catch (e) { await o.query("rollback to savepoint linha"); recusadas++; motivo = motivo || e.message; }
      }
      if (recusadas) log(`Agenda anterior: ${recusadas} linha(s) de ${tabela} não importada(s). Primeiro motivo: ${motivo}`);
      if (n[tabela] && tipos.id) await o.query(`select setval(pg_get_serial_sequence('public.${tabela}', 'id'), coalesce((select max(id) from public.${tabela}), 1))`);
    }
    await o.query("commit");
  } catch (e) { await o.query("rollback").catch(() => {}); log("Agenda anterior: importação ignorada — " + e.message); return { eventos: 0, reservas: 0, coordenadores: 0 }; }
  return n;
}
