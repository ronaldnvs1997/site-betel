/* =====================================================================
   Área de Membros › Tesouraria (somente atribuição TESOURARIA)
   Painel financeiro, comprovantes, aprovação/recusa/novo comprovante,
   validação de pagamentos presenciais, bolsas e isenções, reembolsos,
   relatórios e exportações. Toda regra é conferida no banco.
   ===================================================================== */
window.BetelTesouraria = (() => {
  let sb, box, tela = "painel", filtroPag = "", periodo = { de: "", ate: "" }, pagamentos = [], beneficios = [], movimentos = [];
  const h = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const el = (id) => document.getElementById(id);
  const reais = (v) => Number(v || 0).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  const dataBR = (d) => d ? new Date(String(d).length === 10 ? d + "T12:00:00" : d).toLocaleDateString("pt-BR") : "";
  const dataHora = (d) => d ? new Date(d).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" }) : "";
  const hoje = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`; };
  const PAG = { aguardando_comprovante: "Aguardando recibo", em_analise: "Em análise", aprovado: "Aprovado", recusado: "Recusado", novo_comprovante_solicitado: "Novo comprovante pedido", cancelado: "Cancelado" };
  const MET = { pix: "Pix", transferencia: "Transferência", dinheiro: "Dinheiro", cartao_presencial: "Cartão (maquininha)", outro: "Outro" };
  const BEN = { bolsa_parcial: "Bolsa parcial", bolsa_integral: "Bolsa integral", isencao: "Isenção" };
  async function rpc(n, a) { const { data, error } = await sb.rpc(n, a || {}); if (error) throw new Error(error.message); return data; }
  async function verArquivo(id) {
    const { data, error } = await sb.functions.invoke("arquivos", { body: { acao: "link", tipo: "comprovante", id } });
    if (error) { let m = "Não foi possível abrir."; try { m = (await error.context.json()).erro || m; } catch (_) {} throw new Error(m); }
    window.open(data.url, "_blank", "noopener");
  }
  function csv(nome, linhas) {
    const t = "﻿" + linhas.map((l) => l.map((c) => `"${String(c ?? "").replace(/"/g, '""')}"`).join(";")).join("\r\n");
    const a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([t], { type: "text/csv" })); a.download = nome; a.click();
  }

  async function render(container, ctx) { sb = ctx.sb; box = container; await desenhar(); }
  async function desenhar() {
    box.innerHTML = '<p class="msg">Carregando…</p>';
    try { if (tela === "painel") await telaPainel(); else if (tela === "fila") await telaPagamentos("em_analise"); else if (tela === "pagamentos") await telaPagamentos(filtroPag || null); else if (tela === "bolsas") await telaBolsas(); else await telaRelatorios(); }
    catch (e) { box.innerHTML = menu() + `<p class="notice">${h(e.message)}</p>`; }
  }
  function menu() {
    const b = (t, n) => `<button class="mini sm" type="button" data-te="tela:${t}"${tela === t ? ' data-ativo=""' : ""}>${n}</button>`;
    return `<div class="toolbar">${b("painel", "Painel financeiro")}${b("fila", "Comprovantes para analisar")}${b("pagamentos", "Pagamentos e reembolsos")}${b("bolsas", "Bolsas e isenções")}${b("relatorios", "Relatórios e exportações")}</div>`;
  }

  /* ---------- Painel ---------- */
  async function telaPainel() {
    const d = await rpc("tesouraria_dashboard", { p_de: periodo.de || null, p_ate: periodo.ate || null });
    const kpi = (t, v, s, acao) => `<${acao ? `button type="button" data-te="tela:${acao}"` : "div"} class="wk glass sbKpi"><span class="dia">${t}</span><span class="hr">${v}</span><small>${s}</small></${acao ? "button" : "div"}>`;
    box.innerHTML = menu() + `<div class="toolbar"><label class="cp-linha">De<input type="date" id="teDe" value="${h(periodo.de)}"></label><label class="cp-linha">Até<input type="date" id="teAte" value="${h(periodo.ate)}"></label><button class="mini sm" type="button" data-te="periodo">Aplicar período</button></div>
      <div class="week" style="margin-top:0">
        ${kpi("Recebido (aprovado)", h(reais(d.recebido)), "Pagamentos aprovados no período.")}
        ${kpi("Reembolsado", h(reais(d.reembolsado)), "Devoluções no período.")}
        ${kpi("Comprovantes em análise", h(d.em_analise.quantidade), `${h(reais(d.em_analise.valor))} aguardando a sua decisão.`, "fila")}
        ${kpi("A receber", h(reais(d.a_receber)), `${h(d.inscricoes_pendentes)} inscrição(ões) aguardando pagamento.`)}
        ${kpi("Presenciais sem recibo", h(d.aguardando_recibo), "Registrados pela Secretaria, sem arquivo anexado.", "pagamentos")}
        ${kpi("Bolsas e isenções", h(reais(d.beneficios_concedidos)), `${h(d.beneficios_pendentes)} pedido(s) aguardando.`, "bolsas")}
      </div>
      <div class="two" style="margin-top:24px"><div class="glass list"><div class="row"><div><p class="n">Recebido por forma de pagamento</p></div></div>
        ${Object.entries(d.por_metodo).map(([m, v]) => `<div class="row"><div><p class="m" style="font-size:14px">${h(MET[m] || m)}</p></div><div class="acts"><b>${h(reais(v))}</b></div></div>`).join("") || '<p class="empty cp-vazio">Nada no período.</p>'}</div>
      <div class="glass list"><div class="row"><div><p class="n">Por curso e turma</p></div></div>
        ${d.por_curso.map((c) => `<div class="row"><div><p class="m" style="font-size:14px">${h(c.curso)} · ${h(c.turma)} · ${c.inscricoes} inscrição(ões)</p></div><div class="acts"><span>${h(reais(c.recebido))} de ${h(reais(c.esperado))}</span></div></div>`).join("") || '<p class="empty cp-vazio">Nenhuma turma com valor.</p>'}</div></div>`;
  }

  /* ---------- Pagamentos (fila e geral) ---------- */
  async function telaPagamentos(status) {
    const geral = tela === "pagamentos";
    pagamentos = await rpc("tesouraria_pagamentos", { p_filtros: { status, de: geral ? periodo.de || null : null, ate: geral ? periodo.ate || null : null } });
    box.innerHTML = menu() + (geral ? `<div class="toolbar"><select data-te-filtro="1"><option value="">Todas as situações</option>${Object.entries(PAG).map(([k, n]) => `<option value="${k}"${filtroPag === k ? " selected" : ""}>${n}</option>`).join("")}</select><span class="msg">${pagamentos.length} pagamento(s)</span></div>`
      : `<p class="notice" style="margin-bottom:16px">Confira cada comprovante antes de decidir. Aprovar confirma a inscrição quando o valor devido estiver coberto. Você não pode analisar um pagamento que você mesmo registrou.</p>`)
      + `<div class="glass list">${pagamentos.length ? pagamentos.map((p) => `<div class="sbItem" id="pg-${h(p.id)}"><div class="row cp-topo"><div>
        <p class="n cp-item-titulo">${h(p.nome)} · ${h(reais(p.valor))}<span class="st ${p.status === "aprovado" ? "ok" : p.status === "em_analise" ? "novo" : ""}">${h(PAG[p.status])}</span></p>
        <p class="m">${h(p.protocolo)} · ${h(p.curso)} · ${h(p.turma)} · ${h(MET[p.metodo])} · ${p.origem === "secretaria" ? `presencial, registrado por ${h(p.registrado_por)}` : "enviado pelo participante"} · ${h(dataHora(p.registrado_em))}${p.pago_em ? " · pago em " + h(dataBR(p.pago_em)) : ""}</p>
        <p class="m">Devido ${h(reais(p.financeiro.valor_final))} · aprovado ${h(reais(p.financeiro.aprovado))}${Number(p.financeiro.reembolsado) ? " · reembolsado " + h(reais(p.financeiro.reembolsado)) : ""} · inscrição: ${h(p.status_inscricao)}${p.observacao ? " · obs.: " + h(p.observacao) : ""}${p.analisado_por ? ` · analisado por ${h(p.analisado_por)} em ${h(dataHora(p.analisado_em))}` : ""}${p.observacao_analise ? " · " + h(p.observacao_analise) : ""}</p>
        ${p.comprovantes.map((c) => `<p class="m">📎 ${h(c.nome)} (${Math.ceil(c.tamanho / 1024)} KB, ${c.via === "link" ? "participante" : "Secretaria"}, ${h(dataHora(c.enviado_em))})${c.situacao === "substituido" ? " · substituído" : ""} · <button class="linkbtn" type="button" data-te="ver:${h(c.id)}">abrir</button></p>`).join("") || '<p class="m">Sem comprovante anexado.</p>'}</div>
        <div class="acts">${p.status === "em_analise" && !p.eu_registrei ? `<button class="btn btn-p sm" type="button" data-te="aprovar:${h(p.id)}">Aprovar</button><button class="mini sm" type="button" data-te="motivo:recusar:${h(p.id)}">Recusar</button><button class="mini sm" type="button" data-te="motivo:solicitar_novo:${h(p.id)}">Pedir novo comprovante</button>` : ""}
          ${p.status === "em_analise" && p.eu_registrei ? '<span class="st">Registrado por você: outra pessoa da Tesouraria deve analisar</span>' : ""}
          ${p.status === "aprovado" ? `<button class="mini sm" type="button" data-te="reembolsoForm:${h(p.id)}">Registrar reembolso</button>` : ""}</div></div><div class="sbExtra"></div></div>`).join("")
        : `<p class="empty cp-vazio">${geral ? "Nenhum pagamento." : "Nenhum comprovante aguardando análise."}</p>`}</div>`;
  }

  /* ---------- Bolsas ---------- */
  async function telaBolsas() {
    beneficios = await rpc("tesouraria_beneficios", {});
    box.innerHTML = menu() + `<form class="formcard glass" data-te-form="conceder" novalidate style="margin-bottom:18px"><h3 class="cp-secao">Conceder bolsa ou isenção</h3>
      <div class="formgrid"><label>Protocolo da inscrição<input name="protocolo" placeholder="CUR-2026-000001" required></label><label>Tipo<select name="tipo">${Object.entries(BEN).map(([k, n]) => `<option value="${k}">${n}</option>`).join("")}</select></label>
      <label>Desconto (R$, só bolsa parcial)<input type="number" name="valor" min="0.01" step="0.01"></label><label>Motivo<input name="motivo" maxlength="600" required></label></div>
      <div><button class="btn btn-p sm" type="submit">Conceder</button></div><span class="msg" role="status"></span></form>
      <div class="glass list">${beneficios.map((b) => `<div class="sbItem" id="bn-${h(b.id)}"><div class="row"><div>
        <p class="n cp-item-titulo">${h(b.nome)} · ${h(BEN[b.tipo])}${b.valor_desconto ? " de " + h(reais(b.valor_desconto)) : ""}<span class="st ${b.status === "aprovado" ? "ok" : b.status === "solicitado" ? "novo" : ""}">${h(b.status)}</span></p>
        <p class="m">${h(b.protocolo)} · ${h(b.curso)} · valor ${h(reais(b.valor_bruto))} → ${h(reais(b.valor_final))} · pedido por ${h(b.solicitado_por || "—")} em ${h(dataHora(b.solicitado_em))} · motivo: ${h(b.motivo)}${b.observacao_analise ? " · decisão: " + h(b.observacao_analise) : ""}</p></div>
        <div class="acts">${b.status === "solicitado" ? `<button class="btn btn-p sm" type="button" data-te="benef:aprovar:${h(b.id)}">Aprovar</button><button class="mini sm" type="button" data-te="motivoBen:${h(b.id)}">Recusar</button>` : ""}</div></div><div class="sbExtra"></div></div>`).join("") || '<p class="empty cp-vazio">Nenhum pedido.</p>'}</div>`;
  }

  /* ---------- Relatórios ---------- */
  async function telaRelatorios() {
    const de = periodo.de || hoje().slice(0, 8) + "01", ate = periodo.ate || hoje();
    movimentos = await rpc("tesouraria_movimentos", { p_de: de, p_ate: ate });
    const ent = movimentos.filter((m) => m.tipo === "entrada").reduce((s, m) => s + Number(m.valor), 0), sai = movimentos.filter((m) => m.tipo === "reembolso").reduce((s, m) => s + Number(m.valor), 0);
    box.innerHTML = menu() + `<div class="toolbar"><label class="cp-linha">De<input type="date" id="teDe" value="${h(de)}"></label><label class="cp-linha">Até<input type="date" id="teAte" value="${h(ate)}"></label><button class="mini sm" type="button" data-te="periodo">Atualizar</button>
      <button class="btn btn-p sm" type="button" data-te="csvMov">Exportar movimentações (CSV)</button><button class="mini sm" type="button" data-te="csvPag">Exportar todos os pagamentos (CSV)</button></div>
      <p class="msg" style="margin-bottom:14px">Entradas ${h(reais(ent))} · reembolsos ${h(reais(-sai))} · saldo ${h(reais(ent + sai))} · ${movimentos.length} movimentação(ões)</p>
      <div class="glass list">${movimentos.map((m) => `<div class="row"><div><p class="n" style="font-size:15px">${m.tipo === "entrada" ? "Entrada" : "Reembolso"} · ${h(reais(m.valor))}</p><p class="m">${h(dataBR(m.data))} · ${h(m.protocolo)} · ${h(m.nome)} · ${h(m.curso)} · ${h(MET[m.metodo] || m.metodo)} · por ${h(m.aprovado_por || "—")}${m.motivo ? " · " + h(m.motivo) : ""}</p></div></div>`).join("") || '<p class="empty cp-vazio">Nenhuma movimentação no período.</p>'}</div>`;
  }

  /* ---------- eventos ---------- */
  document.addEventListener("change", (ev) => { if (box && box.contains(ev.target) && ev.target.dataset.teFiltro) { filtroPag = ev.target.value; desenhar(); } });
  document.addEventListener("click", async (ev) => {
    const b = ev.target.closest("[data-te]"); if (!b || !box || !box.contains(b)) return;
    const [a, x, y] = b.dataset.te.split(":");
    try {
      if (a === "tela") { tela = x; return desenhar(); }
      if (a === "periodo") { periodo = { de: el("teDe").value, ate: el("teAte").value }; return desenhar(); }
      if (a === "ver") return await verArquivo(x);
      if (a === "aprovar") { if (b.dataset.ok !== "1") { b.dataset.ok = "1"; b.textContent = "Confirmar aprovação"; return; } b.disabled = true; await rpc("tesouraria_analisar_pagamento", { p_pagamento: x, p_acao: "aprovar", p_observacao: null }); return desenhar(); }
      if (a === "motivo") { el("pg-" + y).querySelector(".sbExtra").innerHTML = `<form class="formcard sbSub" data-te-form="analise" data-acao="${h(x)}" data-id="${h(y)}" novalidate><label>${x === "recusar" ? "Motivo da recusa" : "O que precisa ser corrigido"} (o participante vê esta mensagem)<input name="obs" maxlength="600" required></label><div><button class="btn btn-p sm" type="submit">${x === "recusar" ? "Recusar pagamento" : "Pedir novo comprovante"}</button></div><span class="msg"></span></form>`; return; }
      if (a === "reembolsoForm") { const p = pagamentos.find((k) => k.id === x); el("pg-" + x).querySelector(".sbExtra").innerHTML = `<form class="formcard sbSub" data-te-form="reembolso" data-id="${h(x)}" novalidate><div class="formgrid"><label>Valor (R$)<input type="number" name="valor" min="0.01" step="0.01" value="${h(Number(p.valor).toFixed(2))}"></label><label>Forma<select name="metodo"><option value="pix">Pix</option><option value="transferencia">Transferência</option><option value="dinheiro">Dinheiro</option><option value="outro">Outro</option></select></label><label>Data<input type="date" name="data" value="${hoje()}"></label><label>Motivo<input name="motivo" maxlength="600" required></label></div><div><button class="btn btn-p sm" type="submit">Registrar reembolso</button></div><span class="msg"></span></form>`; return; }
      if (a === "benef") { b.disabled = true; await rpc("tesouraria_analisar_beneficio", { p_beneficio: y, p_acao: x, p_observacao: null }); return desenhar(); }
      if (a === "motivoBen") { el("bn-" + x).querySelector(".sbExtra").innerHTML = `<form class="formcard sbSub" data-te-form="recusaBen" data-id="${h(x)}" novalidate><label>Motivo da recusa<input name="obs" maxlength="600" required></label><div><button class="btn btn-p sm" type="submit">Recusar</button></div><span class="msg"></span></form>`; return; }
      if (a === "csvMov") return csv("movimentacoes.csv", [["Tipo", "Data", "Valor", "Forma", "Protocolo", "Participante", "Curso", "Turma", "Responsável", "Motivo"]].concat(movimentos.map((m) => [m.tipo, dataBR(m.data), String(m.valor).replace(".", ","), MET[m.metodo] || m.metodo, m.protocolo, m.nome, m.curso, m.turma, m.aprovado_por, m.motivo || ""])));
      if (a === "csvPag") { const t = await rpc("tesouraria_pagamentos", { p_filtros: {} }); return csv("pagamentos.csv", [["Situação", "Valor", "Forma", "Origem", "Registrado em", "Pago em", "Protocolo", "Participante", "Curso", "Turma", "Analisado por", "Analisado em", "Observação da análise"]].concat(t.map((p) => [PAG[p.status], String(p.valor).replace(".", ","), MET[p.metodo], p.origem, dataHora(p.registrado_em), dataBR(p.pago_em), p.protocolo, p.nome, p.curso, p.turma, p.analisado_por || "", dataHora(p.analisado_em), p.observacao_analise || ""]))); }
    } catch (e) { b.disabled = false; BetelUI.aviso(e.message); }
  });
  document.addEventListener("submit", async (ev) => {
    const f = ev.target; if (!box || !box.contains(f) || !f.dataset.teForm) return;
    ev.preventDefault();
    const msg = f.querySelector(".msg"), bt = f.querySelector('[type="submit"]'), v = (n) => (f.elements[n]?.value ?? "").trim(), tipo = f.dataset.teForm;
    bt.disabled = true; msg.textContent = "Salvando…";
    try {
      if (tipo === "analise") await rpc("tesouraria_analisar_pagamento", { p_pagamento: f.dataset.id, p_acao: f.dataset.acao, p_observacao: v("obs") });
      else if (tipo === "reembolso") await rpc("tesouraria_registrar_reembolso", { p_pagamento: f.dataset.id, p_valor: Number(v("valor")), p_metodo: v("metodo"), p_realizado_em: v("data") || null, p_motivo: v("motivo") });
      else if (tipo === "recusaBen") await rpc("tesouraria_analisar_beneficio", { p_beneficio: f.dataset.id, p_acao: "recusar", p_observacao: v("obs") });
      else if (tipo === "conceder") {
        const achou = (await rpc("secretaria_inscricoes", { p_filtros: { busca: v("protocolo") } })).find((i) => i.protocolo.toUpperCase() === v("protocolo").toUpperCase());
        if (!achou) throw new Error("Inscrição não encontrada.");
        const r = await rpc("secretaria_solicitar_beneficio", { p_inscricao: achou.id, p_tipo: v("tipo"), p_valor_desconto: v("valor") ? Number(v("valor")) : null, p_motivo: v("motivo") });
        await rpc("tesouraria_analisar_beneficio", { p_beneficio: r.id, p_acao: "aprovar", p_observacao: "Concedido pela Tesouraria" });
      }
      await desenhar();
    } catch (e) { msg.textContent = e.message; bt.disabled = false; }
  });
  return { render };
})();
