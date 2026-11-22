/* =====================================================================
   Área de Membros › Secretaria
   Inscrições (com status financeiro), pagamentos presenciais (registra,
   não aprova), bolsas (solicita), pessoas e membresia, documentos,
   cerimônias e certificados. Toda regra é conferida no banco.
   ===================================================================== */
window.BetelSecretaria = (() => {
  let sb, box, tela = "inscricoes", filtros = {}, busca = "", lista = [], pessoas = [], cert = { cerimonias: [], certificados: [] }, filtroCert = "";
  const h = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const el = (id) => document.getElementById(id);
  const reais = (v) => Number(v || 0).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  const dataBR = (d) => d ? new Date(String(d).length === 10 ? d + "T12:00:00" : d).toLocaleDateString("pt-BR") : "";
  const dataHora = (d) => d ? new Date(d).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" }) : "";
  const hoje = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`; };
  const ST_I = { confirmada: "Confirmada", aguardando_pagamento: "Aguardando pagamento", lista_espera: "Lista de espera", cancelada: "Cancelada", concluida: "Concluída" };
  const FIN = { gratuito: "Gratuito", isento: "Isento", quitado: "Pago (aprovado)", em_analise: "Comprovante em análise", novo_comprovante_solicitado: "Novo comprovante pedido", pendente: "Pagamento pendente" };
  const PAG = { aguardando_comprovante: "Aguardando recibo", em_analise: "Em análise", aprovado: "Aprovado", recusado: "Recusado", novo_comprovante_solicitado: "Novo comprovante pedido", cancelado: "Cancelado" };
  const MET = { pix: "Pix", transferencia: "Transferência", dinheiro: "Dinheiro", cartao_presencial: "Cartão (maquininha)", outro: "Outro" };
  const MEMB = { visitante: "Visitante", em_integracao: "Em integração", membro: "Membro", inativo: "Inativo" };
  const DOC = { ficha_membresia: "Ficha de membresia", carta_transferencia: "Carta de transferência", documento_responsavel: "Documento do responsável", documento_identificacao: "Documento de identificação", outro: "Outro" };
  const BEN = { bolsa_parcial: "Bolsa parcial", bolsa_integral: "Bolsa integral", isencao: "Isenção" };
  const BST = { solicitado: "aguardando a Tesouraria", aprovado: "aprovada", recusado: "recusada", cancelado: "cancelada" };
  const CST = { aguardando_validacao: "Aguardando validação da liderança", aguardando_autorizacao: "Aguardando autorização", autorizado: "Autorizado", preparado: "Vinculado à cerimônia", impresso: "Impresso", entregue: "Entregue em mãos", cancelado: "Cancelado", elegivel: "A preparar" };
  async function rpc(n, a) { const { data, error } = await sb.rpc(n, a || {}); if (error) throw new Error(error.message); return data; }
  async function funcao(corpo) { const { data, error } = await sb.functions.invoke("arquivos", { body: corpo }); if (error) { let m = "Não foi possível concluir."; try { m = (await error.context.json()).erro || m; } catch (_) {} throw new Error(m); } return data; }
  const base64 = (f) => new Promise((ok, err) => { const r = new FileReader(); r.onload = () => ok(String(r.result).split(",")[1]); r.onerror = err; r.readAsDataURL(f); });

  async function render(container, ctx) { sb = ctx.sb; box = container; await desenhar(); }
  async function desenhar() { try { box.innerHTML = '<p class="msg">Carregando…</p>'; if (tela === "inscricoes") await telaInscricoes(); else if (tela === "pessoas") await telaPessoas(); else await telaCertificados(); } catch (e) { box.innerHTML = menu() + `<p class="notice">${h(e.message)}</p>`; } }
  function menu() {
    const b = (t, n) => `<button class="mini sm" type="button" data-se="tela:${t}"${tela === t ? ' data-ativo=""' : ""}>${n}</button>`;
    return `<div class="toolbar">${b("inscricoes", "Inscrições e pagamentos")}${b("pessoas", "Pessoas, membresia e documentos")}${b("certificados", "Cerimônias e certificados")}</div>
      <p class="notice" style="margin-bottom:16px">A Secretaria registra pagamentos presenciais e pede bolsas, mas quem aprova é a Tesouraria. Inscrição com valor só é confirmada depois dessa aprovação.</p>`;
  }

  /* ---------- Inscrições ---------- */
  async function telaInscricoes() {
    lista = await rpc("secretaria_inscricoes", { p_filtros: { busca, status: filtros.status || null, financeiro: filtros.financeiro || null } });
    const sel = (n, o, v) => `<select data-se-filtro="${n}"><option value="">${n === "status" ? "Todas as situações" : "Todo status financeiro"}</option>${Object.entries(o).map(([k, x]) => `<option value="${k}"${v === k ? " selected" : ""}>${x}</option>`).join("")}</select>`;
    box.innerHTML = menu() + `<div class="toolbar"><input id="seBusca" placeholder="Nome, e-mail ou protocolo" value="${h(busca)}"><button class="mini sm" type="button" data-se="buscar">Buscar</button>
      ${sel("status", ST_I, filtros.status)}${sel("financeiro", FIN, filtros.financeiro)}<span class="msg">${lista.length} inscrição(ões)</span></div>
      <div class="glass list">${lista.length ? lista.map(itemInscricao).join("") : '<p class="empty cp-vazio">Nenhuma inscrição encontrada.</p>'}</div>`;
  }
  function itemInscricao(i) {
    const f = i.financeiro, pago = Number(f.valor_bruto) > 0;
    return `<div class="sbItem" id="se-${h(i.id)}"><div class="row cp-topo"><div>
      <p class="n cp-item-titulo">${h(i.nome)}<span class="st ${i.status === "confirmada" || i.status === "concluida" ? "ok" : i.status === "cancelada" ? "" : "novo"}">${h(ST_I[i.status])}</span>${pago ? `<span class="st" style="margin-left:6px">${h(FIN[f.situacao])}</span>` : ""}</p>
      <p class="m">${h(i.protocolo)} · ${h(i.curso)} · ${h(i.turma)} · ${h(i.email || "")}</p>
      ${pago ? `<p class="m">Valor ${h(reais(f.valor_bruto))}${Number(f.valor_desconto) ? ` − desconto ${h(reais(f.valor_desconto))} = ${h(reais(f.valor_final))}` : ""} · aprovado ${h(reais(f.aprovado))}${Number(f.em_analise) ? ` · em análise ${h(reais(f.em_analise))}` : ""}${Number(f.reembolsado) ? ` · reembolsado ${h(reais(f.reembolsado))}` : ""}</p>` : ""}
      ${i.pagamentos.map((p) => `<p class="m">↳ ${h(reais(p.valor))} · ${h(MET[p.metodo])} · ${p.origem === "secretaria" ? "presencial" : "pelo participante"} · <b>${h(PAG[p.status])}</b>${p.comprovantes ? ` · ${p.comprovantes} arquivo(s)` : ""}${p.observacao_analise ? ` · Tesouraria: ${h(p.observacao_analise)}` : ""}
        ${p.eu_registrei && ["aguardando_comprovante", "em_analise"].includes(p.status) ? ` · <label class="linkbtn" style="display:inline;font:inherit;cursor:pointer">anexar recibo<input type="file" hidden data-se-recibo="${h(p.id)}" accept="application/pdf,image/jpeg,image/png,image/webp"></label> · <button class="linkbtn" type="button" data-se="cancelarPagForm:${h(i.id)}:${h(p.id)}">cancelar registro</button>` : ""}</p>`).join("")}
      ${i.beneficios.map((b) => `<p class="m">↳ ${h(BEN[b.tipo] || b.tipo)}${b.valor_desconto ? " de " + h(reais(b.valor_desconto)) : ""} · ${h(BST[b.status] || b.status)} · ${h(b.motivo)}</p>`).join("")}
      ${i.certificado ? `<p class="m">Certificado: ${h(CST[i.certificado])}</p>` : ""}</div>
      <div class="acts">${i.status === "aguardando_pagamento" && !i.pagamentos.some((p) => ["aguardando_comprovante", "em_analise"].includes(p.status)) ? `<button class="btn btn-p sm" type="button" data-se="presencialForm:${h(i.id)}">Registrar pagamento presencial</button>` : ""}
        ${pago && ["aguardando_pagamento", "confirmada", "lista_espera"].includes(i.status) && !i.beneficios.some((b) => b.status === "solicitado") ? `<button class="mini sm" type="button" data-se="bolsaForm:${h(i.id)}">Pedir bolsa/isenção</button>` : ""}
        ${i.status === "confirmada" ? `<button class="mini sm" type="button" data-se="inscr:concluir:${h(i.id)}">Marcar concluído</button>` : ""}
        ${["confirmada", "aguardando_pagamento", "lista_espera"].includes(i.status) ? `<button class="mini sm" type="button" data-se="cancelarInscForm:${h(i.id)}">Cancelar inscrição</button>` : ""}</div>
    </div><div class="sbExtra"></div></div>`;
  }
  const extra = (id) => el("se-" + id).querySelector(".sbExtra");
  function formPresencial(id) {
    const i = lista.find((x) => x.id === id), f = i.financeiro;
    extra(id).innerHTML = `<form class="formcard sbSub" data-se-form="presencial" data-id="${h(id)}" novalidate><p class="cp-forte">Pagamento recebido pela Secretaria</p>
      <div class="formgrid"><label>Forma<select name="metodo">${["dinheiro", "cartao_presencial", "pix", "transferencia", "outro"].map((m) => `<option value="${m}">${MET[m]}</option>`).join("")}</select></label>
      <label>Valor recebido (R$)<input name="valor" type="number" min="0.01" step="0.01" value="${h(Math.max(Number(f.valor_final) - Number(f.aprovado), 0).toFixed(2))}"></label>
      <label>Data do recebimento<input name="pago_em" type="date" value="${hoje()}"></label><label>Observação<input name="observacao" maxlength="600"></label>
      <label class="cp-full">Recibo ou foto do comprovante (obrigatório para a Tesouraria aprovar)<input name="arquivo" type="file" accept="application/pdf,image/jpeg,image/png,image/webp"></label></div>
      <p style="font-size:14px;color:var(--suave)">O registro vai para a Tesouraria validar. A inscrição continua aguardando pagamento até a aprovação.</p>
      <div><button class="btn btn-p sm" type="submit">Registrar e enviar à Tesouraria</button></div><span class="msg" role="status"></span></form>`;
  }
  function formBolsa(id) {
    extra(id).innerHTML = `<form class="formcard sbSub" data-se-form="bolsa" data-id="${h(id)}" novalidate><p class="cp-forte">Pedido de bolsa ou isenção (a Tesouraria decide)</p>
      <div class="formgrid"><label>Tipo<select name="tipo"><option value="bolsa_parcial">Bolsa parcial</option><option value="bolsa_integral">Bolsa integral</option><option value="isencao">Isenção</option></select></label>
      <label>Desconto (R$, só para bolsa parcial)<input name="valor" type="number" min="0.01" step="0.01"></label><label class="cp-full">Motivo<input name="motivo" maxlength="600" required></label></div>
      <div><button class="btn btn-p sm" type="submit">Enviar pedido</button></div><span class="msg" role="status"></span></form>`;
  }
  function formMotivo(id, tipo, alvo) {
    extra(id).innerHTML = `<form class="formcard sbSub" data-se-form="${tipo}" data-id="${h(id)}" data-alvo="${h(alvo || "")}" novalidate><label>Motivo<input name="motivo" maxlength="300" required></label>
      <div><button class="btn btn-p sm" type="submit">Confirmar</button></div><span class="msg" role="status"></span></form>`;
  }

  /* ---------- Pessoas ---------- */
  async function telaPessoas() {
    pessoas = await rpc("secretaria_pessoas", { p_busca: busca || null });
    box.innerHTML = menu() + `<div class="toolbar"><input id="seBusca" placeholder="Nome, e-mail ou telefone" value="${h(busca)}"><button class="mini sm" type="button" data-se="buscar">Buscar</button><span class="msg">${pessoas.length} pessoa(s)</span></div>
      <div class="glass list">${pessoas.map((p) => `<div class="sbItem" id="pe-${h(p.id)}"><div class="row"><div>
        <p class="n cp-item-titulo">${h(p.nome)}<span class="st ${p.situacao_membresia === "membro" ? "ok" : ""}">${h(MEMB[p.situacao_membresia])}</span>${p.tem_conta ? '<span class="st" style="margin-left:6px">Equipe</span>' : ""}</p>
        <p class="m">${h(p.email || "sem e-mail")} · ${h(p.telefone || "sem telefone")} · ${p.inscricoes} inscrição(ões) · ${p.documentos} documento(s)${p.membresia_validada_em ? ` · membro desde ${h(dataBR(p.membro_desde))}, validado por ${h(p.validada_por || "—")} em ${h(dataBR(p.membresia_validada_em))}` : ""}</p></div>
        <div class="acts"><button class="mini sm" type="button" data-se="membForm:${h(p.id)}">Membresia</button><button class="mini sm" type="button" data-se="docs:${h(p.id)}">Documentos</button></div></div><div class="sbExtra"></div></div>`).join("") || '<p class="empty cp-vazio">Ninguém encontrado.</p>'}</div>`;
  }
  function formMembresia(id) {
    const p = pessoas.find((x) => x.id === id);
    el("pe-" + id).querySelector(".sbExtra").innerHTML = `<form class="formcard sbSub" data-se-form="membresia" data-id="${h(id)}" novalidate><p class="cp-forte">Validação administrativa de membresia</p>
      <div class="formgrid"><label>Situação<select name="situacao">${Object.entries(MEMB).map(([k, n]) => `<option value="${k}"${k === p.situacao_membresia ? " selected" : ""}>${n}</option>`).join("")}</select></label>
      <label>Membro desde (obrigatório para "Membro")<input type="date" name="desde" value="${h(p.membro_desde || "")}"></label><label class="cp-full">Fundamento (obrigatório para "Membro": batismo, carta de transferência, ata…)<input name="obs" maxlength="300"></label></div>
      <div><button class="btn btn-p sm" type="submit">Salvar</button></div><span class="msg" role="status"></span></form>`;
  }
  async function docs(id) {
    const d = await rpc("secretaria_documentos", { p_pessoa: id });
    el("pe-" + id).querySelector(".sbExtra").innerHTML = `<div class="sbSub formcard"><p class="cp-forte">Documentos (arquivo privado; cada consulta fica registrada)</p>
      ${d.length ? d.map((x) => `<p class="m">${h(DOC[x.tipo])}${x.descricao ? " · " + h(x.descricao) : ""} · ${h(x.nome_original)} · ${h(dataHora(x.enviado_em))} por ${h(x.enviado_por)}${x.arquivado_em ? " · arquivado" : ` · <button class="linkbtn" type="button" data-se="verDoc:${h(x.id)}">abrir</button> · <button class="linkbtn" type="button" data-se="arquivarDoc:${h(x.id)}:${h(id)}">arquivar</button>`}</p>`).join("") : '<p class="m">Nenhum documento.</p>'}
      <form data-se-form="documento" data-id="${h(id)}" novalidate style="display:grid;gap:12px;margin-top:10px"><div class="formgrid"><label>Tipo<select name="tipo">${Object.entries(DOC).map(([k, n]) => `<option value="${k}">${n}</option>`).join("")}</select></label>
      <label>Descrição<input name="descricao" maxlength="300"></label><label class="cp-full">Arquivo (PDF, JPG, PNG ou WebP, até 5 MB)<input type="file" name="arquivo" accept="application/pdf,image/jpeg,image/png,image/webp"></label></div>
      <div><button class="btn btn-p sm" type="submit">Enviar documento</button></div><span class="msg" role="status"></span></form></div>`;
  }

  /* ---------- Cerimônias e certificados (módulo próprio: certificados-sb.js) ---------- */
  async function telaCertificados() {
    box.innerHTML = menu() + '<div id="seCertBox"></div>';
    await window.BetelCertificados.render(el("seCertBox"), { sb });
  }

  /* ---------- eventos ---------- */
  document.addEventListener("change", async (ev) => {
    if (!box || !box.contains(ev.target)) return;
    const t = ev.target;
    if (t.dataset.seFiltro) { filtros[t.dataset.seFiltro] = t.value || null; return desenhar(); }
    if (t.dataset.seRecibo) {
      const f = t.files[0]; if (!f) return;
      try { await funcao({ acao: "enviar_comprovante", pagamento_id: t.dataset.seRecibo, arquivo: { nome: f.name, tipo: f.type, base64: await base64(f) } }); await desenhar(); }
      catch (e) { BetelUI.aviso(e.message); }
    }
  });
  document.addEventListener("click", async (ev) => {
    const b = ev.target.closest("[data-se]"); if (!b || !box || !box.contains(b)) return;
    const [a, x, y] = b.dataset.se.split(":");
    try {
      if (a === "tela") { tela = x; busca = ""; return desenhar(); }
      if (a === "buscar") { busca = el("seBusca").value.trim(); return desenhar(); }
      if (a === "presencialForm") return formPresencial(x);
      if (a === "bolsaForm") return formBolsa(x);
      if (a === "cancelarInscForm") return formMotivo(x, "cancelarInsc");
      if (a === "cancelarPagForm") return formMotivo(x, "cancelarPag", y);
      if (a === "inscr") { b.disabled = true; await rpc("cursos_alterar_inscricao", { p_inscricao: y, p_acao: x, p_motivo: null }); return desenhar(); }
      if (a === "membForm") return formMembresia(x);
      if (a === "docs") return docs(x);
      if (a === "verDoc") { const r = await funcao({ acao: "link", tipo: "documento", id: x }); window.open(r.url, "_blank", "noopener"); return; }
      if (a === "arquivarDoc") { await rpc("secretaria_arquivar_documento", { p_documento: x }); return docs(y); }
    } catch (e) { b.disabled = false; BetelUI.aviso(e.message); }
  });
  document.addEventListener("submit", async (ev) => {
    const f = ev.target; if (!box || !box.contains(f) || !f.dataset.seForm) return;
    ev.preventDefault();
    const msg = f.querySelector(".msg"), bt = f.querySelector('[type="submit"]'), v = (n) => (f.elements[n]?.value ?? "").trim(), tipo = f.dataset.seForm, id = f.dataset.id;
    bt.disabled = true; msg.textContent = "Salvando…";
    try {
      if (tipo === "presencial") {
        const arq = f.elements.arquivo.files[0];
        const r = await rpc("secretaria_registrar_pagamento_presencial", { p_inscricao: id, p_metodo: v("metodo"), p_valor: Number(v("valor")), p_pago_em: v("pago_em") || null, p_observacao: v("observacao") || null });
        if (arq) await funcao({ acao: "enviar_comprovante", pagamento_id: r.pagamento_id, arquivo: { nome: arq.name, tipo: arq.type, base64: await base64(arq) } });
      } else if (tipo === "bolsa") {
        await rpc("secretaria_solicitar_beneficio", { p_inscricao: id, p_tipo: v("tipo"), p_valor_desconto: v("valor") ? Number(v("valor")) : null, p_motivo: v("motivo") });
      } else if (tipo === "cancelarInsc") {
        await rpc("cursos_alterar_inscricao", { p_inscricao: id, p_acao: "cancelar", p_motivo: v("motivo") });
      } else if (tipo === "cancelarPag") {
        await rpc("secretaria_cancelar_pagamento", { p_pagamento: f.dataset.alvo, p_motivo: v("motivo") });
      } else if (tipo === "membresia") {
        await rpc("secretaria_validar_membresia", { p_pessoa: id, p_situacao: v("situacao"), p_membro_desde: v("desde") || null, p_observacao: v("obs") || null });
      } else if (tipo === "documento") {
        const arq = f.elements.arquivo.files[0]; if (!arq) throw new Error("Anexe o arquivo.");
        await funcao({ acao: "enviar_documento", pessoa_id: id, tipo: v("tipo"), descricao: v("descricao"), arquivo: { nome: arq.name, tipo: arq.type, base64: await base64(arq) } });
        await desenhar(); return docs(id);
      }
      await desenhar();
    } catch (e) { msg.textContent = e.message; bt.disabled = false; }
  });
  return { render };
})();
