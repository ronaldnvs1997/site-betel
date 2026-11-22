/* =====================================================================
   Certificados e cerimônias
   - Liderança (aba "Turmas"): conclui e valida a conclusão dos participantes
   - Secretaria (Secretaria › Cerimônias e certificados): autoriza a emissão,
     cadastra cerimônias, vincula, imprime e registra a entrega física
   Entrega exclusivamente presencial: o participante nunca recebe arquivo,
   e nada é enviado por e-mail ou WhatsApp. Regras conferidas no banco.
   ===================================================================== */
(() => {
  const h = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const el = (id) => document.getElementById(id);
  const dataBR = (d) => d ? new Date(String(d).length === 10 ? d + "T12:00:00" : d).toLocaleDateString("pt-BR") : "";
  const dataHora = (d) => d ? new Date(d).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" }) : "";
  const hoje = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`; };
  const ST = { aguardando_validacao: "Aguardando validação da liderança", aguardando_autorizacao: "Aguardando autorização", autorizado: "Autorizado · vincular à cerimônia",
    preparado: "Vinculado · a imprimir", impresso: "Impresso · aguardando entrega", entregue: "Entregue em mãos", cancelado: "Cancelado" };
  const EV = { criado: "Certificado gerado na conclusão", conclusao_validada: "Conclusão validada pela liderança", emissao_autorizada: "Emissão autorizada pela Secretaria",
    vinculado_cerimonia: "Vinculado à cerimônia", desvinculado_cerimonia: "Desvinculado da cerimônia", impresso: "Impresso", reimpresso: "Reimpresso",
    entregue: "Entregue em mãos", cancelado: "Cancelado", situacao_alterada: "Situação alterada" };
  const REL = { participante: "o próprio participante", responsavel_legal: "o responsável legal", pessoa_autorizada: "pessoa autorizada" };
  const TIPO = { culto: "Culto", apresentacao: "Apresentação", outra: "Outra ocasião" };
  const sel = (on) => (on ? ' style="background:var(--creme);color:var(--vinho)"' : "");

  /* ---------- impressão (só chega aqui quem a Secretaria autorizou no banco) ---------- */
  function janelaImpressao(itens, titulo) {
    const w = window.open("", "_blank"); if (!w) { BetelUI.aviso("Permita a abertura de janelas para imprimir."); return; }
    const t = (s) => h(s);
    const pag = (d) => { const m = d.modelo || {}, ass = m.assinaturas || [];
      return `<section class="c"><p class="ig">${t(m.igreja || "Igreja Batista Betel no Flamengo")}</p><h1>CERTIFICADO</h1><p class="p">Certificamos que</p><p class="n">${t(d.nome)}</p>
        <p class="p">${t(m.texto || "concluiu o curso")}</p><p class="cur">${t(d.curso)}</p>${d.carga_horaria ? `<p class="p">Carga horária: ${t(d.carga_horaria)}</p>` : ""}
        <p class="p">${t(m.cidade || "Contagem/MG")}, ${t(dataBR(d.cerimonia_data || d.concluida_em))}</p>
        <div class="ass">${(ass.length ? ass : [{}, {}]).map((a) => `<div><span></span><b>${t(a.nome || "")}</b><i>${t(a.cargo || "")}</i></div>`).join("")}</div>
        <p class="cod">Código ${t(d.codigo)}</p></section>`; };
    w.document.write(`<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>${t(titulo)}</title><style>
      @page{size:A4 landscape;margin:0}body{margin:0;font-family:Georgia,serif;color:#2a0f0f}
      .c{width:297mm;height:210mm;box-sizing:border-box;padding:20mm 26mm;border:10mm solid #582121;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;gap:4mm;page-break-after:always}
      .ig{font-size:13pt;letter-spacing:.12em;text-transform:uppercase;margin:0}h1{font-size:34pt;letter-spacing:.2em;margin:0;color:#582121}.n{font-size:30pt;font-weight:bold;margin:0}
      .cur{font-size:22pt;margin:0}.p{font-size:14pt;margin:0}.cod{font:9pt monospace;color:#777;margin-top:4mm}
      .ass{display:flex;gap:18mm;margin-top:10mm}.ass div{display:flex;flex-direction:column;align-items:center;min-width:60mm}.ass span{display:block;width:100%;border-top:1px solid #2a0f0f;margin-bottom:2mm}
      .ass b{font-size:11pt}.ass i{font-size:10pt}</style></head><body>${itens.map(pag).join("")}<script>window.onload=()=>window.print()<\/script></body></html>`);
    w.document.close();
  }
  function janelaLista(d) {
    const w = window.open("", "_blank"); if (!w) { BetelUI.aviso("Permita a abertura de janelas para imprimir."); return; }
    const c = d.cerimonia;
    w.document.write(`<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>Lista de entrega</title><style>body{font-family:Arial,sans-serif;margin:16mm}table{width:100%;border-collapse:collapse}td,th{border:1px solid #999;padding:6px;font-size:11pt;text-align:left}th{background:#eee}</style></head><body>
      <h2>${h(c.titulo)}</h2><p>${h(dataBR(c.data))} às ${h(c.horario)} · ${h(c.local)}</p>
      <table><tr><th>#</th><th>Participante</th><th>Curso</th><th>Código</th><th>Situação</th><th>Assinatura de quem recebeu</th></tr>
      ${d.participantes.map((p, k) => `<tr><td>${k + 1}</td><td>${h(p.nome)}${p.menor ? " (menor)" : ""}</td><td>${h(p.curso)}</td><td>${h(p.codigo)}</td><td>${h(ST[p.status])}</td><td style="width:30%"></td></tr>`).join("")}</table>
      <script>window.onload=()=>window.print()<\/script></body></html>`);
    w.document.close();
  }

  /* ================= Secretaria ================= */
  let sb, box, tela = "autorizar", filtro = "", dados = null;
  async function rpc(n, a) { const { data, error } = await sb.rpc(n, a || {}); if (error) throw new Error(error.message); return data; }
  async function render(container, ctx) { sb = ctx.sb; box = container; await desenhar(); }
  async function desenhar() {
    box.innerHTML = '<p class="msg">Carregando…</p>';
    try {
      dados = await rpc("secretaria_certificados", { p_filtros: tela === "lista" && filtro ? { status: filtro } : {} });
      const m = (t, n) => `<button class="mini sm" type="button" data-ce="tela:${t}"${sel(tela === t)}>${n}</button>`;
      const pend = dados.certificados.filter((c) => c.status === "aguardando_autorizacao").length;
      box.innerHTML = `<div class="toolbar">${m("autorizar", `Autorizar emissão${pend ? ` (${pend})` : ""}`)}${m("lista", "Certificados")}${m("cerimonias", "Cerimônias")}${m("modelo", "Modelo do certificado")}</div>
        <p class="notice" style="margin-bottom:16px">Todos os certificados, inclusive de cursos online, são entregues somente em mãos, em cerimônias definidas pela Betel. O participante não baixa o certificado e nada é enviado por e-mail ou WhatsApp.</p>`
        + (tela === "autorizar" ? telaAutorizar() : tela === "lista" ? telaLista() : tela === "cerimonias" ? telaCerimonias() : telaModelo());
    } catch (e) { box.innerHTML = `<p class="notice">${h(e.message)}</p>`; }
  }
  const linha = (c, acoes) => `<div class="sbItem" id="ce-${h(c.id)}"><div class="row cp-topo"><div>
      <p class="n cp-item-titulo">${h(c.nome)}<span class="st ${c.status === "entregue" ? "ok" : c.status === "cancelado" ? "" : "novo"}">${h(ST[c.status])}</span>${c.modalidade === "online" ? '<span class="st" style="margin-left:6px">curso online</span>' : ""}</p>
      <p class="m">${h(c.curso)} · ${h(c.turma)} · ${h(c.protocolo)} · concluído em ${h(dataBR(c.concluida_em))} · código ${h(c.codigo)}</p>
      <p class="m">${c.validado_por ? `Validado por ${h(c.validado_por)} em ${h(dataBR(c.validado_em))}` : "Ainda não validado pela liderança"}${c.autorizado_por ? ` · autorizado por ${h(c.autorizado_por)} em ${h(dataBR(c.autorizado_em))}` : ""}
        ${c.cerimonia ? ` · cerimônia: ${h(c.cerimonia)} (${h(dataBR(c.cerimonia_data))})` : ""}${c.vezes_impresso ? ` · impresso ${c.vezes_impresso}x` : ""}
        ${c.recebido_por ? ` · recebido por ${h(c.recebido_por)} (${h(REL[c.recebido_relacao] || "")}) em ${h(dataHora(c.entregue_em))}` : ""}${c.motivo_cancelamento ? " · " + h(c.motivo_cancelamento) : ""}</p></div>
      <div class="acts">${acoes}<button class="linkbtn" type="button" data-ce="hist:${h(c.id)}">histórico</button></div></div><div class="sbExtra"></div></div>`;

  function telaAutorizar() {
    const aut = dados.certificados.filter((c) => c.status === "aguardando_autorizacao"), val = dados.certificados.filter((c) => c.status === "aguardando_validacao");
    return `<h3 class="cp-subsecao">Conclusões validadas pela liderança (${aut.length})</h3>
      <div class="glass list">${aut.map((c) => linha(c, c.eu_validei ? '<span class="st">Você validou: outra pessoa autoriza</span>'
        : `<button class="btn btn-p sm" type="button" data-ce="autorizar:${h(c.id)}">Autorizar emissão</button><button class="mini sm" type="button" data-ce="recusarForm:${h(c.id)}">Não autorizar</button>`)).join("")
        || '<p class="empty cp-vazio">Nada para autorizar.</p>'}</div>
      <h3 style="font-size:20px;margin:26px 0 10px">Aguardando a validação da liderança (${val.length})</h3>
      <p class="msg" style="margin-bottom:10px">Conclusões registradas sem a validação de quem acompanha a turma. A liderança valida na aba "Turmas".</p>
      <div class="glass list">${val.map((c) => linha(c, `<button class="mini sm" type="button" data-ce="recusarForm:${h(c.id)}">Não autorizar</button>`)).join("") || '<p class="empty cp-vazio">Nenhuma.</p>'}</div>`;
  }
  function telaLista() {
    const futuras = dados.cerimonias.filter((c) => c.status === "planejada" && c.data >= hoje());
    const ops = futuras.map((c) => `<option value="${h(c.id)}">${h(c.titulo)} · ${h(dataBR(c.data))}</option>`).join("");
    return `<div class="toolbar"><select data-ce-filtro="1"><option value="">Todos os certificados</option>${Object.entries(ST).map(([k, n]) => `<option value="${k}"${filtro === k ? " selected" : ""}>${n}</option>`).join("")}</select><span class="msg">${dados.certificados.length} certificado(s)</span></div>
      <div class="glass list">${dados.certificados.map((c) => {
        let a = "";
        if (["autorizado", "preparado", "impresso"].includes(c.status) && futuras.length) a += `<select data-ce-vincular="${h(c.id)}"><option value="">${c.cerimonia_id ? "Trocar cerimônia…" : "Vincular à cerimônia…"}</option>${ops}</select>`;
        if (c.status === "preparado") a += `<button class="mini sm" type="button" data-ce="imprimir:${h(c.id)}">Imprimir</button>`;
        if (c.status === "impresso") a += `<button class="btn btn-p sm" type="button" data-ce="entregaForm:${h(c.id)}">Registrar entrega</button><button class="mini sm" type="button" data-ce="reimpForm:${h(c.id)}">Reimprimir</button>`;
        if (["preparado"].includes(c.status)) a += `<button class="mini sm" type="button" data-ce="acao:desvincular:${h(c.id)}">Desvincular</button>`;
        if (c.status === "cancelado" && c.concluida_em) a += `<button class="mini sm" type="button" data-ce="acao:reativar:${h(c.id)}">Reativar</button>`;
        else if (c.status !== "entregue") a += `<button class="mini sm" type="button" data-ce="cancelarForm:${h(c.id)}">Cancelar</button>`;
        return linha(c, a); }).join("") || '<p class="empty cp-vazio">Nenhum certificado. Eles surgem quando um participante conclui o curso.</p>'}</div>`;
  }
  function telaCerimonias() {
    return `<div class="two"><form class="formcard glass" data-ce-form="cerimonia" novalidate><h3 id="ceCerTit">Nova cerimônia</h3><input type="hidden" name="id">
      <label>Título<input name="titulo" maxlength="140" placeholder="Ex.: Entrega de certificados — culto de domingo"></label>
      <div class="formgrid"><label>Tipo<select name="tipo">${Object.entries(TIPO).map(([k, n]) => `<option value="${k}">${n}</option>`).join("")}</select></label>
      <label>Data<input type="date" name="data" min="${hoje()}"></label><label>Horário<input type="time" name="horario"></label><label>Local<input name="local" maxlength="200" placeholder="Ex.: Templo"></label>
      <label>Responsável<input name="responsavel" maxlength="120"></label><label>Situação<select name="status"><option value="planejada">Planejada</option><option value="cancelada">Cancelada</option></select></label>
      <label>Evento na Agenda (código, opcional)<input name="evento_ref" maxlength="40"></label></div><label>Observações<textarea name="observacoes" rows="2" maxlength="1000"></textarea></label>
      <div><button class="btn btn-p" type="submit">Salvar cerimônia</button></div><span class="msg" role="status"></span></form>
      <div class="glass list">${dados.cerimonias.map((c) => `<div class="sbItem" id="cm-${h(c.id)}"><div class="row cp-topo"><div>
        <p class="n cp-item-titulo">${h(c.titulo)}<span class="st ${c.status === "planejada" ? "novo" : c.status === "realizada" ? "ok" : ""}">${h(c.status)}</span></p>
        <p class="m">${h(TIPO[c.tipo] || "")} · ${h(dataBR(c.data))} às ${h(c.horario || "")} · ${h(c.local || "")}${c.responsavel ? " · " + h(c.responsavel) : ""}</p>
        <p class="m">${c.certificados} certificado(s) · ${c.a_imprimir} a imprimir · ${c.entregues} entregue(s)</p></div>
        <div class="acts">${c.status === "planejada" ? `<button class="mini sm" type="button" data-ce="editarCer:${h(c.id)}">Editar</button>${c.a_imprimir ? `<button class="mini sm" type="button" data-ce="lote:${h(c.id)}">Imprimir ${c.a_imprimir} pendente(s)</button>` : ""}` : ""}
          <button class="mini sm" type="button" data-ce="listaCer:${h(c.id)}">Lista de entrega</button>${c.status === "planejada" && c.data <= hoje() ? `<button class="btn btn-p sm" type="button" data-ce="realizada:${h(c.id)}">Marcar como realizada</button>` : ""}</div></div><div class="sbExtra"></div></div>`).join("")
        || '<p class="empty cp-vazio">Nenhuma cerimônia cadastrada.</p>'}</div></div>`;
  }
  function telaModelo() {
    const m = dados.modelo || {}, a = m.assinaturas || [];
    return `<form class="formcard glass" data-ce-form="modelo" novalidate style="max-width:820px"><h3 class="cp-secao">Modelo do certificado</h3>
      <p class="msg">Preencha com os dados oficiais da igreja. Em branco, o certificado sai com linhas de assinatura sem nome.</p>
      <div class="formgrid"><label>Nome da igreja no certificado<input name="igreja" maxlength="120" value="${h(m.igreja || "")}" placeholder="Igreja Batista Betel no Flamengo"></label>
      <label>Cidade<input name="cidade" maxlength="80" value="${h(m.cidade || "")}" placeholder="Contagem/MG"></label>
      <label class="cp-full">Texto antes do nome do curso<input name="texto" maxlength="400" value="${h(m.texto || "")}" placeholder="concluiu o curso"></label>
      ${[0, 1, 2].map((k) => `<label>Assinatura ${k + 1} — nome<input name="a${k}n" maxlength="80" value="${h(a[k]?.nome || "")}"></label><label>Cargo<input name="a${k}c" maxlength="80" value="${h(a[k]?.cargo || "")}"></label>`).join("")}</div>
      <div><button class="btn btn-p" type="submit">Salvar modelo</button></div><span class="msg" role="status"></span></form>`;
  }

  const extra = (id) => el("ce-" + id)?.querySelector(".sbExtra") || el("cm-" + id)?.querySelector(".sbExtra");
  const form = (nome, id, corpo, botao) => `<form class="formcard sbSub" data-ce-form="${nome}" data-id="${h(id)}" novalidate>${corpo}<div><button class="btn btn-p sm" type="submit">${botao}</button></div><span class="msg" role="status"></span></form>`;
  document.addEventListener("change", async (ev) => {
    if (!box || !box.contains(ev.target)) return;
    const t = ev.target;
    if (t.dataset.ceFiltro) { filtro = t.value; return desenhar(); }
    if (t.dataset.ceVincular && t.value) { try { await rpc("secretaria_certificado", { p_certificado: t.dataset.ceVincular, p_acao: "vincular", p_dados: { cerimonia_id: t.value } }); await desenhar(); } catch (e) { BetelUI.aviso(e.message); } }
  });
  document.addEventListener("click", async (ev) => {
    const b = ev.target.closest("[data-ce]"); if (!b || !box || !box.contains(b)) return;
    const [a, x, y] = b.dataset.ce.split(":");
    try {
      if (a === "tela") { tela = x; filtro = ""; return desenhar(); }
      if (a === "autorizar") { if (b.dataset.ok !== "1") { b.dataset.ok = "1"; b.textContent = "Confirmar autorização"; return; } b.disabled = true; await rpc("secretaria_certificado", { p_certificado: x, p_acao: "autorizar" }); return desenhar(); }
      if (a === "recusarForm") return void (extra(x).innerHTML = form("recusar", x, '<label>Motivo<input name="motivo" maxlength="300"></label>', "Não autorizar a emissão"));
      if (a === "cancelarForm") return void (extra(x).innerHTML = form("cancelar", x, '<label>Motivo<input name="motivo" maxlength="300"></label>', "Cancelar certificado"));
      if (a === "reimpForm") return void (extra(x).innerHTML = form("reimprimir", x, '<label>Motivo da reimpressão<input name="motivo" maxlength="300" placeholder="Ex.: nome digitado errado, papel danificado"></label>', "Reimprimir"));
      if (a === "entregaForm") {
        const c = dados.certificados.find((k) => k.id === x);
        return void (extra(x).innerHTML = form("entregar", x, `<div class="formgrid"><label>Ocasião<select name="ocasiao"><option value="cerimonia">Na cerimônia${c.cerimonia ? " (" + h(c.cerimonia) + ")" : ""}</option><option value="secretaria">Fora da cerimônia (com justificativa)</option></select></label>
          <label>Quem recebeu<select name="relacao"><option value="participante">O próprio participante</option><option value="responsavel_legal">O responsável legal</option><option value="pessoa_autorizada">Pessoa autorizada</option></select></label>
          <label>Nome completo de quem recebeu<input name="recebido" maxlength="120" value="${h(c.nome)}"></label><label>Observação (obrigatória fora da cerimônia ou para terceiros)<input name="observacao" maxlength="600"></label></div>
          <label class="cuAceite cp-linha"><input class="cp-check" type="checkbox" name="confirmo"> Confirmo que o certificado impresso foi entregue em mãos</label>`, "Registrar entrega"));
      }
      if (a === "imprimir") { const r = await rpc("secretaria_certificado", { p_certificado: x, p_acao: "imprimir" }); janelaImpressao([r.impressao], "Certificado " + r.impressao.codigo); return desenhar(); }
      if (a === "lote") { const r = await rpc("secretaria_imprimir_cerimonia", { p_cerimonia: x }); janelaImpressao(r.impressoes, "Certificados da cerimônia"); return desenhar(); }
      if (a === "listaCer") return janelaLista(await rpc("secretaria_lista_cerimonia", { p_cerimonia: x }));
      if (a === "realizada") { if (b.dataset.ok !== "1") { b.dataset.ok = "1"; b.textContent = "Confirmar: aconteceu"; return; } const r = await rpc("secretaria_cerimonia_realizada", { p_cerimonia: x }); if (r.nao_entregues) BetelUI.aviso(`${r.nao_entregues} certificado(s) desta cerimônia ainda não têm entrega registrada.`); return desenhar(); }
      if (a === "acao") { await rpc("secretaria_certificado", { p_certificado: y, p_acao: x }); return desenhar(); }
      if (a === "editarCer") { const c = dados.cerimonias.find((k) => k.id === x), f = box.querySelector('[data-ce-form="cerimonia"]');
        for (const k of ["id", "titulo", "tipo", "data", "horario", "local", "responsavel", "status", "evento_ref", "observacoes"]) f.elements[k].value = c[k] || ""; el("ceCerTit").textContent = "Editar cerimônia"; f.scrollIntoView({ block: "center" }); return; }
      if (a === "hist") {
        const hs = await rpc("secretaria_certificado_historico", { p_certificado: x });
        return void (extra(x).innerHTML = `<div class="sbSub" style="padding:10px 0"><p class="cp-forte">Histórico de emissão e entrega</p>${hs.map((e) => `<p class="m">${h(dataHora(e.em))} · <b>${h(EV[e.evento] || e.evento)}</b>${e.detalhes?.validada_na_conclusao ? " (conclusão já validada pela liderança)" : ""}${e.ator ? " · " + h(e.ator) : ""}${e.detalhes?.motivo ? " · motivo: " + h(e.detalhes.motivo) : ""}${e.detalhes?.cerimonia ? " · " + h(e.detalhes.cerimonia) : ""}${e.detalhes?.recebido_por ? " · recebido por " + h(e.detalhes.recebido_por) : ""}${e.detalhes?.observacao ? " · " + h(e.detalhes.observacao) : ""}</p>`).join("")}</div>`);
      }
    } catch (e) { b.disabled = false; BetelUI.aviso(e.message); }
  });
  document.addEventListener("submit", async (ev) => {
    const f = ev.target; if (!box || !box.contains(f) || !f.dataset.ceForm) return;
    ev.preventDefault();
    const msg = f.querySelector(".msg"), bt = f.querySelector('[type="submit"]'), v = (n) => (f.elements[n]?.value ?? "").trim(), id = f.dataset.id;
    bt.disabled = true; msg.textContent = "Salvando…";
    try {
      switch (f.dataset.ceForm) {
        case "recusar": await rpc("secretaria_certificado", { p_certificado: id, p_acao: "recusar_emissao", p_dados: { motivo: v("motivo") } }); break;
        case "cancelar": await rpc("secretaria_certificado", { p_certificado: id, p_acao: "cancelar", p_dados: { motivo: v("motivo") } }); break;
        case "reimprimir": { const r = await rpc("secretaria_certificado", { p_certificado: id, p_acao: "imprimir", p_dados: { motivo: v("motivo") } }); janelaImpressao([r.impressao], "Certificado " + r.impressao.codigo); break; }
        case "entregar": await rpc("secretaria_certificado", { p_certificado: id, p_acao: "entregar", p_dados: { ocasiao: v("ocasiao"), relacao: v("relacao"), recebido_por: v("recebido"), observacao: v("observacao"), confirmo_entrega_fisica: f.elements.confirmo.checked } }); break;
        case "cerimonia": await rpc("secretaria_salvar_cerimonia", { p: { id: v("id") || null, titulo: v("titulo"), tipo: v("tipo"), data: v("data"), horario: v("horario"), local: v("local"), responsavel: v("responsavel"), status: v("status"), evento_ref: v("evento_ref"), observacoes: v("observacoes") } }); break;
        case "modelo": await rpc("secretaria_salvar_modelo_certificado", { p: { igreja: v("igreja"), cidade: v("cidade"), texto: v("texto"), assinaturas: [0, 1, 2].map((k) => ({ nome: v(`a${k}n`), cargo: v(`a${k}c`) })) } }); break;
      }
      await desenhar();
    } catch (e) { msg.textContent = e.message; bt.disabled = false; }
  });
  window.BetelCertificados = { render };

  /* ================= Liderança: turmas e validação de conclusão ================= */
  let sbL, boxL;
  async function renderTurmas(container, ctx) {
    sbL = ctx.sb; boxL = container; boxL.innerHTML = '<p class="msg">Carregando…</p>';
    const { data, error } = await sbL.rpc("lider_turmas_validacao"); if (error) { boxL.innerHTML = `<p class="notice">${h(error.message)}</p>`; return; }
    boxL.innerHTML = `<p class="notice" style="margin-bottom:16px">Valide a conclusão de quem cumpriu a frequência e as atividades da turma. Depois, a Secretaria autoriza a emissão e o certificado é entregue em mãos, numa cerimônia.</p>`
      + (data.map((t) => `<div class="card glass" style="margin-bottom:16px"><p class="eyebrow">${h(t.curso)}${t.modalidade === "online" ? " · online" : ""}</p><h3 class="cp-secao">${h(t.turma)}</h3>
        <div class="list" style="margin-top:10px">${t.inscricoes.map((i) => `<div class="sbItem" id="lt-${h(i.id)}"><div class="row"><div><p class="n" style="font-size:15px">${h(i.nome)}</p>
          <p class="m">${h(i.protocolo)} · ${i.status === "confirmada" ? "cursando" : "concluído em " + h(dataBR(i.concluida_em))}${i.certificado ? " · certificado: " + h(ST[i.certificado.status]) : ""}</p></div>
          <div class="acts">${i.status === "confirmada" ? `<button class="btn btn-p sm" type="button" data-lt="concluirForm:${h(i.id)}">Concluir e validar</button>` : ""}
            ${i.certificado?.status === "aguardando_validacao" ? `<button class="btn btn-p sm" type="button" data-lt="validar:${h(i.certificado.id)}">Validar conclusão</button><button class="mini sm" type="button" data-lt="naoForm:${h(i.certificado.id)}:${h(i.id)}">Não validar</button>` : ""}</div></div><div class="sbExtra"></div></div>`).join("")
          || '<p class="empty">Nenhum participante cursando.</p>'}</div></div>`).join("") || '<p class="empty">Você não é responsável por nenhuma turma em andamento. A Secretaria define os responsáveis de cada turma.</p>');
  }
  document.addEventListener("click", async (ev) => {
    const b = ev.target.closest("[data-lt]"); if (!b || !boxL || !boxL.contains(b)) return;
    const [a, x, y] = b.dataset.lt.split(":");
    if (a === "concluirForm") return void (el("lt-" + x).querySelector(".sbExtra").innerHTML = `<form class="formcard sbSub" data-lt-form="concluir" data-id="${h(x)}" novalidate><label>Observação (opcional)<input name="obs" maxlength="600" placeholder="Ex.: 100% de frequência"></label><label class="cuAceite cp-linha"><input class="cp-check" type="checkbox" name="atesto"> Atesto que a pessoa cumpriu a frequência e as atividades exigidas</label><div><button class="btn btn-p sm" type="submit">Concluir e validar</button></div><span class="msg"></span></form>`);
    if (a === "naoForm") return void (el("lt-" + y).querySelector(".sbExtra").innerHTML = `<form class="formcard sbSub" data-lt-form="nao" data-id="${h(x)}" novalidate><label>Motivo (a pessoa volta a "cursando")<input name="obs" maxlength="600"></label><div><button class="btn btn-p sm" type="submit">Não validar</button></div><span class="msg"></span></form>`);
    if (a === "validar") { if (b.dataset.ok !== "1") { b.dataset.ok = "1"; b.textContent = "Confirmar validação"; return; } b.disabled = true;
      const { error } = await sbL.rpc("lider_validar_certificado", { p_certificado: x, p_acao: "validar", p_observacao: null }); if (error) { BetelUI.aviso(error.message); b.disabled = false; return; } renderTurmas(boxL, { sb: sbL }); }
  });
  document.addEventListener("submit", async (ev) => {
    const f = ev.target; if (!boxL || !boxL.contains(f) || !f.dataset.ltForm) return; ev.preventDefault();
    const msg = f.querySelector(".msg");
    if (f.dataset.ltForm === "concluir" && !f.elements.atesto.checked) { msg.textContent = "Marque o atestado de frequência e atividades."; return; }
    const r = f.dataset.ltForm === "concluir" ? await sbL.rpc("lider_concluir_validar", { p_inscricao: f.dataset.id, p_observacao: f.elements.obs.value || null })
      : await sbL.rpc("lider_validar_certificado", { p_certificado: f.dataset.id, p_acao: "nao_validar", p_observacao: f.elements.obs.value });
    if (r.error) { msg.textContent = r.error.message; return; } renderTurmas(boxL, { sb: sbL });
  });
  window.BetelTurmasLider = { render: renderTurmas };
})();
