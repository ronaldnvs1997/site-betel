/* =====================================================================
   Área de Membros › Membresia (Secretaria), Candidatos (liderança) e
   Autorizações de imagem (Secretaria e ministério de Mídia).
   Regras e permissões são conferidas no banco.
   ===================================================================== */
(() => {
  const h = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const escopoTxt = (e) => [["fotos", "fotos"], ["videos", "vídeos"], ["voz", "voz"]].filter(([k]) => (e || {})[k]).map(([, n]) => n).join(", ");
  const el = (id) => document.getElementById(id);
  const dataBR = (d) => d ? new Date(String(d).length === 10 ? d + "T12:00:00" : d).toLocaleDateString("pt-BR") : "";
  const dataHora = (d) => d ? new Date(d).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" }) : "";
  const PROC = { interesse: "Interesse", em_curso: "No Curso de Novos Membros", aguardando_validacao: "Aguardando validação", validado: "Validado", encerrado: "Encerrado" };
  const CAND = { aguardando_indicacao: "Aguardando indicação", em_analise: "Em análise pela liderança", aprovada: "Aprovada", nao_aprovada: "Não aprovada", cancelada: "Cancelada" };
  const IND = { pendente: "pendente", aprovada: "aprovado", recusada: "não aprovado", cancelada: "cancelada" };
  const TIPO = { participacao_curso: "Participação nos cursos", imagem_voz: "Imagem e voz", voluntariado: "Adesão ao voluntariado" };
  const MEMB = { visitante: "Visitante", em_integracao: "Em integração", membro: "Membro", inativo: "Inativo" };
  const SIT = { autorizado: "Autorizado", nao_autorizado: "Não autorizado", sem_autorizacao: "Sem autorização registrada" };
  const req = (r) => `<span class="st ${r.membresia_validada ? "ok" : ""}">membresia ${r.membresia_validada ? "validada" : "não validada"}</span> <span class="st ${r.novos_membros ? "ok" : ""}">Novos Membros ${r.novos_membros ? "✓" : "pendente"}</span> <span class="st ${r.formacao_voluntarios ? "ok" : ""}">Formação ${r.formacao_voluntarios ? "✓" : "pendente"}</span> <span class="st ${r.termo_voluntariado ? "ok" : ""}">termo ${r.termo_voluntariado ? "✓" : "pendente"}</span>`;
  const menu = (estado, itens, attr) => `<div class="toolbar">${itens.map(([t, n]) => `<button class="mini sm" type="button" ${attr}="tela:${t}"${estado === t ? ' data-ativo=""' : ""}>${n}</button>`).join("")}</div>`;

  /* ================= Secretaria ================= */
  let sb, box, tela = "processos", pessoaAtual = null, termosLista = [], cursosCache = null, candCache = null, busca = "";
  async function rpc(n, a) { const { data, error } = await sb.rpc(n, a || {}); if (error) throw new Error(error.message); return data; }
  async function render(container, ctx) { sb = ctx.sb; box = container; await desenhar(); }
  async function desenhar() {
    box.innerHTML = '<p class="msg">Carregando…</p>';
    try {
      const topo = menu(tela, [["processos", "Membresia"], ["voluntariado", "Voluntariado"], ["pessoa", "Ficha da pessoa"], ["termos", "Termos"], ["imagem", "Autorizações de imagem"]], "data-mb")
        + '<p class="notice" style="margin-bottom:16px">Para servir como voluntário: membresia validada pela Secretaria e Curso de Novos Membros concluído. A membresia nunca é validada por autodeclaração.</p>';
      if (tela === "processos") box.innerHTML = topo + await telaProcessos();
      else if (tela === "voluntariado") box.innerHTML = topo + await telaVoluntariado();
      else if (tela === "pessoa") box.innerHTML = topo + await telaPessoa();
      else if (tela === "termos") box.innerHTML = topo + await telaTermos();
      else box.innerHTML = topo + telaImagem();
    } catch (e) { box.innerHTML = `<p class="notice">${h(e.message)}</p>`; }
  }

  async function telaProcessos() {
    const ps = await rpc("secretaria_processos_membresia", { p_status: null });
    return `<div class="glass list">${ps.map((p) => `<div class="sbItem" id="mp-${h(p.id)}"><div class="row cp-topo"><div>
      <p class="n cp-item-titulo">${h(p.nome)}<span class="st ${p.status === "aguardando_validacao" ? "novo" : ""}">${h(PROC[p.status])}</span>${p.menor ? '<span class="st" style="margin-left:6px">menor de 18</span>' : ""}</p>
      <p class="m">${h(p.email || "")} · ${h(p.telefone || "")} · ${p.origem === "site" ? "pelo site" : "pela Secretaria"} em ${h(dataBR(p.criado_em))} · Novos Membros: ${p.novos_membros ? "concluído" : p.inscricao ? h(p.inscricao.protocolo + " (" + p.inscricao.status + ")") : "não inscrito"}</p>
      ${p.mensagem ? `<p class="m">“${h(p.mensagem)}”</p>` : ""}${p.observacao ? `<p class="m">Obs.: ${h(p.observacao)}</p>` : ""}</div>
      <div class="acts">${p.status === "aguardando_validacao" ? `<button class="btn btn-p sm" type="button" data-mb="validarForm:${h(p.pessoa_id)}:${h(p.id)}">Validar membresia</button>` : ""}
        <button class="mini sm" type="button" data-mb="ficha:${h(p.pessoa_id)}">Ficha</button><button class="mini sm" type="button" data-mb="encerrarForm:${h(p.id)}">Encerrar</button></div></div><div class="sbExtra"></div></div>`).join("")
      || '<p class="empty cp-vazio">Nenhum processo aberto. As pessoas chegam pelo formulário "Quero ser membro" ou pela inscrição no Curso de Novos Membros.</p>'}</div>
      <p class="msg" style="margin-top:12px">Para inscrever alguém no Curso de Novos Membros, use a aba Cursos › Novos Membros › Inscrições. O processo acompanha a inscrição automaticamente.</p>`;
  }
  const formValidar = (pessoa) => `<form class="formcard sbSub" data-mb-form="validar" data-id="${h(pessoa)}" novalidate><p class="cp-forte">Validação administrativa de membresia</p>
      <div class="formgrid"><label>Membro desde<input type="date" name="desde"></label>
      <label class="cp-full">Fundamento da validação (obrigatório)<input name="fundamento" maxlength="300" placeholder="Ex.: batismo em 12/05/2026 · ata da assembleia de 20/05/2026"></label></div>
      <div><button class="btn btn-p sm" type="submit">Validar como membro</button></div><span class="msg" role="status"></span></form>`;

  async function telaVoluntariado() {
    const d = candCache = await rpc("secretaria_candidaturas", { p_status: null });
    const mins = (await sb.from("ministerios").select("id,nome").eq("ativo", true).order("nome")).data || [];
    const termo = (await window.BetelTermos.termos()).voluntariado;
    return `<div class="glass list">${d.candidaturas.map((c) => `<div class="sbItem" id="vc-${h(c.id)}"><div class="row cp-topo"><div>
        <p class="n cp-item-titulo">${h(c.nome)}<span class="st novo">${h(CAND[c.status])}</span></p>
        <p class="m">${h(c.email || "")} · ${h(c.telefone || "")} · desde ${h(dataBR(c.criado_em))}</p><p class="m">${req(c.requisitos)}</p>
        ${c.indicacoes.map((i) => `<p class="m">${h(i.ordem)}. ${h(i.ministerio)} · ${h(IND[i.status])}${i.analisado_por ? " por " + h(i.analisado_por) : ""}${i.motivo ? " · " + h(i.motivo) : ""}</p>`).join("")}</div>
        <div class="acts">${c.status === "aguardando_indicacao" ? `<button class="btn btn-p sm" type="button" data-mb="indicarForm:${h(c.id)}">Indicar ministérios (termo em papel)</button>` : ""}<button class="mini sm" type="button" data-mb="cancCandForm:${h(c.id)}">Cancelar</button></div></div>
        <div class="sbExtra"></div></div>`).join("") || '<p class="empty cp-vazio">Nenhuma candidatura aberta. Elas surgem quando alguém conclui a Formação de Voluntários.</p>'}</div>
      <template id="mbMins">${mins.map((m) => `<option value="${h(m.id)}">${h(m.nome)}</option>`).join("")}</template><input type="hidden" id="mbTermoVol" value="${h(termo?.id || "")}">
      <h3 style="margin:28px 0 12px;font-size:22px">Voluntários atuais sem os requisitos (${d.pendencias.length})</h3>
      <p class="msg" style="margin-bottom:10px">Cadastros anteriores à regra. Nada foi removido: regularize registrando a validação da membresia e, se for o caso, a conclusão anterior do Curso de Novos Membros na ficha da pessoa.</p>
      <div class="glass list">${d.pendencias.map((p) => `<div class="row"><div><p class="n" style="font-size:15px">${h(p.nome)}</p><p class="m">${h(p.ministerios.join(", "))} · ${req(p.requisitos)}</p></div><div class="acts"><button class="mini sm" type="button" data-mb="ficha:${h(p.pessoa_id)}">Ficha</button></div></div>`).join("") || '<p class="empty cp-vazio">Nenhuma pendência.</p>'}</div>`;
  }

  async function telaPessoa() {
    let html = `<div class="toolbar"><input id="mbBusca" placeholder="Nome, e-mail ou telefone" value="${h(busca)}"><button class="mini sm" type="button" data-mb="buscar">Buscar</button></div>`;
    if (!pessoaAtual) {
      if (!busca) return html + '<p class="msg">Busque uma pessoa para ver requisitos, conclusões anteriores e o histórico de consentimentos.</p>';
      const ps = await rpc("secretaria_pessoas", { p_busca: busca });
      return html + `<div class="glass list">${ps.map((p) => `<div class="row"><div><p class="n" style="font-size:15px">${h(p.nome)}</p><p class="m">${h(p.email || "")} · ${h(MEMB[p.situacao_membresia])}</p></div><div class="acts"><button class="mini sm" type="button" data-mb="ficha:${h(p.id)}">Abrir ficha</button></div></div>`).join("") || '<p class="empty cp-vazio">Ninguém encontrado.</p>'}</div>`;
    }
    const f = await rpc("secretaria_ficha_pessoa", { p_pessoa: pessoaAtual });
    if (!cursosCache) cursosCache = (await rpc("cursos_admin_listar")).cursos;
    const t = await window.BetelTermos.termos();
    return html + `<div class="card glass" style="display:grid;gap:14px"><div><h3 style="font-size:24px">${h(f.nome)}</h3>
      <p class="m">${h(f.email || "")} · ${h(f.telefone || "")} · nascimento ${h(dataBR(f.data_nascimento) || "não informado")}${f.menor ? " · <b>menor de 18 anos</b>" : ""}</p>
      <p class="m">Membresia: <b>${h(MEMB[f.situacao_membresia])}</b>${f.membresia_validada_em ? ` · validada em ${h(dataBR(f.membresia_validada_em))} (membro desde ${h(dataBR(f.membro_desde))})` : ""}</p>
      <p class="m">${req(f.requisitos)}</p>
      <p class="m">Ministérios: ${f.ministerios.length ? f.ministerios.map((m) => `${h(m.ministerio)} (${m.funcao === "lider" ? "líder" : "voluntário"}${m.ativo ? "" : ", inativo"})`).join(", ") : "nenhum"}</p>
      <div class="toolbar" style="margin:0">${f.situacao_membresia !== "membro" ? `<button class="btn btn-p sm" type="button" data-mb="validarFicha:${h(f.id)}">Validar membresia</button>` : ""}
        ${f.situacao_membresia !== "membro" ? `<button class="mini sm" type="button" data-mb="abrirProc:${h(f.id)}">Abrir processo de membresia</button>` : ""}
        ${f.requisitos.formacao_voluntarios && f.requisitos.pode_ser_voluntario && !f.ministerios.some((m) => m.funcao === "voluntario" && m.ativo) ? `<button class="mini sm" type="button" data-mb="abrirCand:${h(f.id)}">Abrir candidatura ao voluntariado</button>` : ""}</div>
      <div id="mbFichaExtra"></div></div>
      <div class="card glass" style="margin-top:16px"><h3 style="font-size:20px">Conclusões anteriores ao sistema</h3>
      ${f.conclusoes_anteriores.map((c) => `<p class="m">${h(c.curso)} · ${h(dataBR(c.concluido_em))} · ${h(c.comprovacao)} · por ${h(c.registrado_por)}${c.cancelado_em ? " · <b>cancelado</b>" : ` · <button class="linkbtn" type="button" data-mb="cancConcl:${h(c.id)}">cancelar</button>`}</p>`).join("") || '<p class="m">Nenhuma.</p>'}
      <form data-mb-form="conclusao" data-id="${h(f.id)}" novalidate style="display:grid;gap:10px;margin-top:10px"><div class="formgrid">
        <label>Curso<select name="curso">${cursosCache.map((c) => `<option value="${h(c.id)}"${c.slug === "novos-membros" ? " selected" : ""}>${h(c.titulo)}</option>`).join("")}</select></label>
        <label>Concluído em<input type="date" name="data"></label><label class="cp-full">Comprovação (o que foi conferido)<input name="comprovacao" maxlength="600" placeholder="Ex.: lista de presença da turma de 2019 conferida pela Secretaria"></label></div>
        <div><button class="mini sm" type="submit">Registrar conclusão anterior</button></div><span class="msg" role="status"></span></form></div>
      <div class="card glass" style="margin-top:16px"><h3 style="font-size:20px">Histórico de consentimentos</h3>
      ${f.consentimentos.map((c) => `<p class="m"><b>${h(TIPO[c.tipo])}</b> v${h(c.versao)} · ${c.decisao === "aceito" ? (c.tipo === "imagem_voz" ? "autorizado: " + h(escopoTxt(c.escopo)) : "aceito") : "não autorizado"} · ${h(dataHora(c.registrado_em))} · ${c.origem === "secretaria" ? "registrado pela Secretaria" : c.origem === "link" ? "pelo link pessoal" : "pelo site"}${c.dado_por === "responsavel" ? " · pelo responsável " + h(c.responsavel) : ""}
        ${c.revogado_em ? ` · <span class="st">revogado ${h(dataHora(c.revogado_em))} (${h(c.revogado_via)}): ${h(c.motivo_revogacao)}</span>` : c.em_vigor ? ' · <span class="st ok">em vigor</span>' : ""}
        ${!c.revogado_em ? ` · <button class="linkbtn" type="button" data-mb="revogarForm:${h(c.id)}">registrar revogação</button>` : ""}</p>`).join("") || '<p class="m">Nenhum consentimento registrado.</p>'}
      <div id="mbRevogar"></div>
      ${t.imagem_voz ? `<form data-mb-form="consentimento" data-id="${h(f.id)}" data-termo="${h(t.imagem_voz.id)}" data-menor="${f.menor ? 1 : 0}" novalidate style="display:grid;gap:10px;margin-top:12px">
        <p class="cp-forte">Registrar autorização de imagem e voz entregue em papel</p>
        ${!f.data_nascimento ? '<label>Data de nascimento<input type="date" name="nascimento"></label>' : ""}
        <div class="tmOpcoes"><label><input type="radio" name="img" value="aceito"> Autorizou</label><label><input type="radio" name="img" value="recusado"> Não autorizou</label></div>
        <div class="tmOpcoes"><label><input type="checkbox" name="img_fotos" checked> fotos</label><label><input type="checkbox" name="img_videos" checked> vídeos</label><label><input type="checkbox" name="img_voz" checked> voz</label></div>
        ${f.menor ? window.BetelTermos.blocoResponsavel("").replace(" hidden>", ">") : ""}
        <div><button class="mini sm" type="submit">Registrar</button></div><span class="msg" role="status"></span></form>` : ""}</div>`;
  }

  async function telaTermos() {
    termosLista = await rpc("secretaria_termos");
    const ST = { rascunho: "Rascunho", vigente: "Em vigor", substituido: "Substituído" };
    return `<p class="msg" style="margin-bottom:12px">Um termo publicado não muda: para alterar, crie uma nova versão. Marque "exige novo aceite" quando a mudança for relevante; então os aceites da versão anterior deixam de valer. Os trechos ⟦…⟧ precisam ser preenchidos antes de publicar, e os textos devem ser revisados pela igreja.</p>
      <div class="glass list">${termosLista.map((t) => `<div class="sbItem" id="tm-${h(t.id)}"><div class="row cp-topo"><div>
        <p class="n cp-item-titulo">${h(TIPO[t.tipo])} · versão ${h(t.versao)}<span class="st ${t.status === "vigente" ? "ok" : t.status === "rascunho" ? "novo" : ""}">${h(ST[t.status])}</span></p>
        <p class="m">${h(t.titulo)}${t.publicado_em ? " · publicado em " + h(dataBR(t.publicado_em)) : ""} · ${t.aceites} aceite(s)${t.exige_novo_aceite ? " · exige novo aceite" : ""}</p>
        ${t.pendencias ? `<p class="m" style="color:var(--creme)">Falta preencher: ${h(t.pendencias.join(" · "))}</p>` : ""}</div>
        <div class="acts">${t.status === "rascunho" ? `<button class="mini sm" type="button" data-mb="editarTermo:${h(t.id)}">Editar</button><button class="btn btn-p sm" type="button" data-mb="publicar:${h(t.id)}">Publicar</button>` : `<button class="mini sm" type="button" data-mb="verTermo:${h(t.id)}">Ver texto</button>`}
          ${t.status === "vigente" && !termosLista.some((x) => x.tipo === t.tipo && x.status === "rascunho") ? `<button class="mini sm" type="button" data-mb="novaVersao:${h(t.id)}">Nova versão</button>` : ""}</div></div><div class="sbExtra"></div></div>`).join("")}</div>`;
  }
  const formTermo = (t, nova) => `<form class="formcard sbSub" data-mb-form="termo" data-id="${nova ? "" : h(t.id)}" data-tipo="${h(t.tipo)}" novalidate>
      <label>Título<input name="titulo" maxlength="140" value="${h(t.titulo)}"></label><label>Resumo<input name="resumo" maxlength="600" value="${h(t.resumo || "")}"></label>
      <label>Texto<textarea name="texto" rows="14" maxlength="20000">${h(t.texto)}</textarea></label>
      <label class="cuAceite cp-linha"><input class="cp-check" type="checkbox" name="novo"${t.exige_novo_aceite ? " checked" : ""}> Exige novo aceite (os aceites da versão anterior deixam de valer)</label>
      <div><button class="btn btn-p sm" type="submit">${nova ? "Criar rascunho da nova versão" : "Salvar rascunho"}</button></div><span class="msg" role="status"></span></form>`;

  function telaImagem() {
    return `<div class="toolbar"><input id="mbImgBusca" placeholder="Nome da pessoa (mín. 3 letras)"><button class="mini sm" type="button" data-mb="imgBuscar">Consultar</button></div><div id="mbImgRes"></div>`;
  }
  async function consultarImagem(cliente, termo, alvo) {
    const r = await (cliente).rpc("imagem_consultar", { p_busca: termo });
    if (r.error) { alvo.innerHTML = `<p class="notice">${h(r.error.message)}</p>`; return; }
    alvo.innerHTML = `<div class="glass list">${r.data.map((p) => `<div class="row"><div><p class="n" style="font-size:15px">${h(p.nome)}<span class="st ${p.situacao === "autorizado" ? "ok" : ""}">${h(SIT[p.situacao])}</span>${p.menor ? '<span class="st" style="margin-left:6px">menor</span>' : ""}</p>
      <p class="m">${p.situacao === "autorizado" ? "Autoriza: " + h(escopoTxt(p.escopo)) + " · desde " + h(dataBR(p.desde)) : "Não usar imagem ou voz identificável desta pessoa."}</p></div></div>`).join("") || '<p class="empty cp-vazio">Ninguém encontrado.</p>'}</div>`;
  }

  document.addEventListener("click", async (ev) => {
    const b = ev.target.closest("[data-mb]"); if (!b || !box || !box.contains(b)) return;
    const [a, x, y] = b.dataset.mb.split(":");
    const extra = (pref, id) => el(pref + id).querySelector(".sbExtra");
    try {
      if (a === "tela") { tela = x; if (x !== "pessoa") pessoaAtual = null; return desenhar(); }
      if (a === "ficha") { tela = "pessoa"; pessoaAtual = x; return desenhar(); }
      if (a === "buscar") { busca = el("mbBusca").value.trim(); pessoaAtual = null; return desenhar(); }
      if (a === "validarForm") return void (extra("mp-", y).innerHTML = formValidar(x));
      if (a === "validarFicha") return void (el("mbFichaExtra").innerHTML = formValidar(x));
      if (a === "encerrarForm") return void (extra("mp-", x).innerHTML = `<form class="formcard sbSub" data-mb-form="encerrar" data-id="${h(x)}" novalidate><label>Motivo<input name="motivo" maxlength="300"></label><div><button class="btn btn-p sm" type="submit">Encerrar processo</button></div><span class="msg"></span></form>`);
      if (a === "abrirProc") { await rpc("secretaria_abrir_processo", { p_pessoa: x, p_observacao: null }); tela = "processos"; return desenhar(); }
      if (a === "abrirCand") { await rpc("secretaria_abrir_candidatura", { p_pessoa: x }); tela = "voluntariado"; return desenhar(); }
      if (a === "cancConcl") { const m = prompt("Motivo do cancelamento:"); if (!m) return; await rpc("secretaria_cancelar_conclusao_anterior", { p_id: x, p_motivo: m }); return desenhar(); }
      if (a === "revogarForm") return void (el("mbRevogar").innerHTML = `<form class="formcard sbSub" data-mb-form="revogar" data-id="${h(x)}" novalidate><div class="formgrid"><label>Quem pediu<select name="via"><option value="titular">O titular</option><option value="responsavel">O responsável legal</option><option value="secretaria">A Secretaria (de ofício)</option></select></label><label>Motivo e como o pedido foi feito<input name="motivo" maxlength="600"></label></div><div><button class="btn btn-p sm" type="submit">Registrar revogação</button></div><span class="msg"></span></form>`);
      if (a === "indicarForm") {
        const sel = (k) => `<label>${k}ª opção<select name="ministerio"><option value="">—</option>${el("mbMins").innerHTML}</select></label>`;
        return void (extra("vc-", x).innerHTML = `<form class="formcard sbSub" data-mb-form="indicar" data-id="${h(x)}" novalidate><div class="formgrid">${sel(1)}${sel(2)}${sel(3)}</div>
          <label class="cuAceite cp-linha"><input class="cp-check" type="checkbox" name="presencial"> O termo de adesão ao serviço voluntário em vigor foi lido e assinado pela pessoa</label>
          <div><button class="btn btn-p sm" type="submit">Enviar à liderança</button></div><span class="msg"></span></form>`);
      }
      if (a === "cancCandForm") return void (extra("vc-", x).innerHTML = `<form class="formcard sbSub" data-mb-form="cancCand" data-id="${h(x)}" novalidate><label>Motivo<input name="motivo" maxlength="300"></label><div><button class="btn btn-p sm" type="submit">Cancelar candidatura</button></div><span class="msg"></span></form>`);
      if (a === "editarTermo") return void (extra("tm-", x).innerHTML = formTermo(termosLista.find((t) => t.id === x), false));
      if (a === "novaVersao") return void (extra("tm-", x).innerHTML = formTermo(termosLista.find((t) => t.id === x), true));
      if (a === "verTermo") { const t = termosLista.find((k) => k.id === x); return void (extra("tm-", x).innerHTML = `<div class="sbSub cuTexto" style="padding:12px 0">${h(t.texto)}</div>`); }
      if (a === "publicar") { if (b.dataset.ok !== "1") { b.dataset.ok = "1"; b.textContent = "Confirmar publicação"; return; } await rpc("secretaria_publicar_termo", { p_termo: x }); return desenhar(); }
      if (a === "imgBuscar") return consultarImagem(sb, el("mbImgBusca").value.trim(), el("mbImgRes"));
    } catch (e) { BetelUI.aviso(e.message); }
  });
  document.addEventListener("submit", async (ev) => {
    const f = ev.target; if (!box || !box.contains(f) || !f.dataset.mbForm) return;
    ev.preventDefault();
    const msg = f.querySelector(".msg"), bt = f.querySelector('[type="submit"]'), v = (n) => (f.elements[n]?.value ?? "").trim(), id = f.dataset.id;
    bt.disabled = true; msg.textContent = "Salvando…";
    try {
      switch (f.dataset.mbForm) {
        case "validar": await rpc("secretaria_validar_membresia", { p_pessoa: id, p_situacao: "membro", p_membro_desde: v("desde") || null, p_observacao: v("fundamento") }); break;
        case "encerrar": await rpc("secretaria_encerrar_processo", { p_processo: id, p_motivo: v("motivo") }); break;
        case "conclusao": await rpc("secretaria_registrar_conclusao_anterior", { p_pessoa: id, p_curso: v("curso"), p_concluido_em: v("data") || null, p_comprovacao: v("comprovacao"), p_documento: null }); break;
        case "revogar": {
          const r = await rpc("secretaria_revogar_consentimento", { p_consentimento: id, p_via: v("via"), p_motivo: v("motivo") });
          if (r.vinculos_desativados) BetelUI.aviso(`${r.vinculos_desativados} vínculo(s) de voluntariado foram desativados.`); break;
        }
        case "consentimento": {
          const dec = f.querySelector('input[name="img"]:checked')?.value; if (!dec) throw new Error("Escolha Autorizou ou Não autorizou.");
          await rpc("secretaria_registrar_consentimento", { p_pessoa: id, p_tipo: "imagem_voz", p_termo: f.dataset.termo, p_decisao: dec,
            p_escopo: { fotos: f.elements.img_fotos.checked, videos: f.elements.img_videos.checked, voz: f.elements.img_voz.checked },
            p_responsavel: f.dataset.menor === "1" ? window.BetelTermos.responsavel(f) : null, p_documento: null, p_data_nascimento: v("nascimento") || null }); break;
        }
        case "indicar": {
          const mins = [...f.querySelectorAll('select[name="ministerio"]')].map((s) => s.value).filter(Boolean);
          await rpc("secretaria_indicar_ministerios", { p_candidatura: id, p_ministerios: mins, p_termo: el("mbTermoVol").value || null, p_termo_presencial: f.elements.presencial.checked, p_responsavel: null, p_documento: null }); break;
        }
        case "cancCand": await rpc("secretaria_cancelar_candidatura", { p_candidatura: id, p_motivo: v("motivo") }); break;
        case "termo": await rpc("secretaria_salvar_termo", { p: { id: id || null, tipo: f.dataset.tipo, titulo: v("titulo"), resumo: v("resumo"), texto: f.elements.texto.value, exige_novo_aceite: f.elements.novo.checked } }); break;
      }
      window.BetelTermos && (await window.BetelTermos.termos().catch(() => null));
      await desenhar();
    } catch (e) { msg.textContent = e.message; bt.disabled = false; }
  });
  window.BetelMembresia = { render, consultarImagem };

  /* ================= Liderança: candidatos ================= */
  let sbL, boxL;
  async function renderCand(container, ctx) {
    sbL = ctx.sb; boxL = container; boxL.innerHTML = '<p class="msg">Carregando…</p>';
    const { data, error } = await sbL.rpc("lider_candidaturas"); if (error) { boxL.innerHTML = `<p class="notice">${h(error.message)}</p>`; return; }
    boxL.innerHTML = `<p class="notice" style="margin-bottom:16px">Pessoas que concluíram a Formação de Voluntários e indicaram o seu ministério. A aprovação confere de novo, no banco, a membresia validada, o Curso de Novos Membros, a Formação e o termo de adesão.</p>
      <div class="glass list">${data.map((c) => `<div class="sbItem" id="lc-${h(c.id)}"><div class="row cp-topo"><div>
        <p class="n cp-item-titulo">${h(c.nome)}</p><p class="m">${h(c.telefone || "")} · ${h(c.email || "")}</p><p class="m">${req(c.requisitos)}</p>
        <p class="m">Indicou: ${c.indicacoes.map((i) => `${h(i.ordem)}. ${h(i.ministerio)} (${h(IND[i.status])})`).join(" · ")}</p></div>
        <div class="acts">${(c.para_mim || []).filter((i) => i.status === "pendente").map((i) => `<button class="btn btn-p sm" type="button" data-lc="aprovar:${h(i.indicacao_id)}:${h(c.id)}">Aprovar em ${h(i.ministerio)}</button><button class="mini sm" type="button" data-lc="recusarForm:${h(i.indicacao_id)}:${h(c.id)}">Não aprovar em ${h(i.ministerio)}</button>`).join("")}</div></div><div class="sbExtra"></div></div>`).join("")
        || '<p class="empty cp-vazio">Nenhum candidato para os ministérios que você lidera.</p>'}</div>`;
  }
  document.addEventListener("click", async (ev) => {
    const b = ev.target.closest("[data-lc]"); if (!b || !boxL || !boxL.contains(b)) return;
    const [a, x, y] = b.dataset.lc.split(":");
    if (a === "aprovar") {
      if (b.dataset.ok !== "1") { b.dataset.ok = "1"; b.textContent = "Confirmar aprovação"; return; }
      b.disabled = true; const { error } = await sbL.rpc("lider_decidir_indicacao", { p_indicacao: x, p_acao: "aprovar", p_motivo: null });
      if (error) { BetelUI.aviso(error.message); b.disabled = false; return; } return renderCand(boxL, { sb: sbL });
    }
    if (a === "recusarForm") el("lc-" + y).querySelector(".sbExtra").innerHTML = `<form class="formcard sbSub" data-lc-form="${h(x)}" novalidate><label>Motivo (a Secretaria fará o retorno à pessoa)<input name="motivo" maxlength="600"></label><div><button class="btn btn-p sm" type="submit">Confirmar</button></div><span class="msg"></span></form>`;
  });
  document.addEventListener("submit", async (ev) => {
    const f = ev.target; if (!boxL || !boxL.contains(f) || !f.dataset.lcForm) return; ev.preventDefault();
    const { error } = await sbL.rpc("lider_decidir_indicacao", { p_indicacao: f.dataset.lcForm, p_acao: "recusar", p_motivo: f.elements.motivo.value });
    if (error) { f.querySelector(".msg").textContent = error.message; return; } renderCand(boxL, { sb: sbL });
  });
  window.BetelCandidatos = { render: renderCand };

  /* ================= Mídia: consulta de autorizações ================= */
  window.BetelImagemMidia = { render: (c, ctx) => { c.innerHTML = `<p class="notice" style="margin-bottom:16px">Consulte antes de publicar. Sem autorização registrada, não use imagem ou voz identificável da pessoa. Menores só com autorização do responsável.</p>
      <div class="toolbar"><input id="miBusca" placeholder="Nome da pessoa (mín. 3 letras)"><button class="mini sm" type="button" id="miBtn">Consultar</button></div><div id="miRes"></div>`;
    el("miBtn").onclick = () => consultarImagem(ctx.sb, el("miBusca").value.trim(), el("miRes")); } };
})();
