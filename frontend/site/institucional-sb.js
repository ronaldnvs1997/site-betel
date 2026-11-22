/* Área de Membros › Institucional
   - Ministérios: página pública (O que fazemos / Por que existimos / Nossa missão), liderança, integrantes e histórico
   - Organogramas: geral, ministérios, Colégio, Secretaria e Tesouraria (visual, com níveis recolhíveis)
   - Conteúdo do site: contatos centralizados, fotos da Home e etapas do Colégio
   - Formulários da Agenda: links privados para preenchimento sem login e análise dos envios
   Tudo é conferido no banco: cada função verifica quem pode ver e alterar. */
(() => {
  const CFG = window.BETEL_SUPABASE;
  const h = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const ico = (n, t = 18) => (window.BetelUI?.icone ? window.BetelUI.icone(n, t) : "");
  const aviso = (t) => window.BetelUI?.aviso(t);
  const erro = (t) => window.BetelUI?.erro(t);
  const data = (d) => (d ? new Date(String(d).length <= 10 ? d + "T12:00:00" : d).toLocaleDateString("pt-BR") : "");
  const dataHora = (s) => (s ? new Date(s).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" }) : "");
  const iniciais = (n) => { const p = String(n || "").trim().split(/\s+/).filter(Boolean); return ((p[0]?.[0] || "") + (p.length > 1 ? p[p.length - 1][0] : "")).toUpperCase() || "?"; };
  const urlSite = (f) => (!f ? "" : f.startsWith("site/") ? `${CFG.url}/storage/v1/object/public/site/${f.slice(5)}` : f);
  const urlPerfil = (f) => (f ? `${CFG.url}/storage/v1/object/public/perfis/${f}` : "");
  const avatar = (nome, foto, t = 48) => `<span class="cp-avatar" style="width:${t}px;height:${t}px" aria-hidden="true">${foto ? `<img src="${h(urlPerfil(foto))}" alt="">` : h(iniciais(nome))}</span>`;
  const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : "10000000-1000-4000-8000-100000000000".replace(/[018]/g, (c) => (c ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (c / 4)))).toString(16)));
  const FUNCAO = { lider: "Líder", voluntario: "Voluntário" };
  const fid = (f) => f.getAttribute("id") || "";
  // nenhum formulário da Área de Membros é enviado pelo navegador (evita dados no endereço)
  document.addEventListener("submit", (e) => { if (e.target.closest?.("#v-equipe") && !e.target.hasAttribute("action")) e.preventDefault(); }, true);

  async function rpc(sb, nome, args) {
    const { data: d, error } = await sb.rpc(nome, args || {});
    if (error) throw new Error(error.message || "Não foi possível concluir.");
    return d;
  }
  async function comBotao(b, fn) { if (b) b.disabled = true; try { return await fn(); } catch (e) { erro(e.message); } finally { if (b) b.disabled = false; } }

  /* ---------- imagens: reduz no aparelho e envia (o servidor confere tipo real e tamanho) ---------- */
  async function prepararImagem(arquivo, max = 1600) {
    if (!arquivo || !/^image\/(jpeg|png|webp)$/.test(arquivo.type)) throw new Error("Escolha uma foto JPG, PNG ou WEBP.");
    if (arquivo.size > 15 * 1024 * 1024) throw new Error("Foto muito grande (máximo 15 MB).");
    const img = await new Promise((ok, falha) => { const i = new Image(); i.onload = () => ok(i); i.onerror = () => falha(new Error("Não foi possível ler a imagem.")); i.src = URL.createObjectURL(arquivo); });
    const r = Math.min(1, max / Math.max(img.naturalWidth, img.naturalHeight));
    const cv = document.createElement("canvas"); cv.width = Math.round(img.naturalWidth * r); cv.height = Math.round(img.naturalHeight * r);
    cv.getContext("2d").drawImage(img, 0, 0, cv.width, cv.height); URL.revokeObjectURL(img.src);
    return await new Promise((ok) => cv.toBlob(ok, "image/jpeg", 0.84));
  }
  async function enviarImagem(sb, espaco, caminho, blob) {
    const { error } = await sb.storage.from(espaco).upload(caminho, await blob.arrayBuffer(), { contentType: "image/jpeg", upsert: false });
    if (error) throw new Error(error.message || "Falha ao enviar a foto.");
  }

  /* =====================================================================
     MINISTÉRIOS
     ===================================================================== */
  const MIN = { lista: [], atual: null, dados: null, busca: [] };
  async function ministerios(c, ctx) {
    const { sb, inst } = ctx;
    const master = !!inst?.master;
    let q = sb.from("ministerios").select("id,nome,slug,ativo,ordem,descricao").order("ordem").order("nome");
    if (!master) q = q.in("id", inst?.ministerios_lider?.length ? inst.ministerios_lider : ["00000000-0000-0000-0000-000000000000"]);
    const { data: lista, error } = await q; if (error) throw error;
    MIN.lista = lista || [];
    if (!MIN.atual || !MIN.lista.some((m) => m.id === MIN.atual)) MIN.atual = MIN.lista[0]?.id || null;
    c.innerHTML = `<div class="stack">
      <div class="cp-acoes" style="justify-content:space-between;align-items:center">
        <label style="flex:1;min-width:240px;max-width:460px">Ministério<select id="inMinSel">${MIN.lista.map((m) => `<option value="${h(m.id)}"${m.id === MIN.atual ? " selected" : ""}>${h(m.nome)}${m.ativo ? "" : " (inativo)"}</option>`).join("")}</select></label>
        ${master && !ctx.semCadastro ? '<button class="btn btn-s" type="button" data-in="novoMin">+ Cadastrar ministério</button>' : ""}
      </div>
      <div id="inMinNovo"></div>
      <div id="inMinEd">${MIN.lista.length ? '<p class="msg">Carregando…</p>' : '<p class="empty">Você não lidera nenhum ministério.</p>'}</div></div>`;
    c.querySelector("#inMinSel")?.addEventListener("change", (e) => { MIN.atual = e.target.value; abrirMinisterio(c, ctx); });
    c.onclick = (e) => cliqueMinisterio(e, c, ctx);
    c.onsubmit = (e) => enviarMinisterio(e, c, ctx);
    if (MIN.atual) await abrirMinisterio(c, ctx);
  }
  async function abrirMinisterio(c, ctx) {
    const box = c.querySelector("#inMinEd");
    try { MIN.dados = await rpc(ctx.sb, "ministerio_admin_obter", { p_ministerio: MIN.atual }); }
    catch (e) { box.innerHTML = `<p class="msg">${h(e.message)}</p>`; return; }
    renderMinisterio(box, ctx);
  }
  function renderMinisterio(box, ctx) {
    const d = MIN.dados, p = d.pagina, adm = d.pode_administrar;
    const ativos = d.integrantes.filter((i) => i.ativo), lideres = ativos.filter((i) => i.funcao === "lider");
    const pend = [];
    if (!p.textos_confirmados) pend.push("Textos de apresentação em rascunho: revise e publique quando a liderança confirmar.");
    if (!p.o_que_fazemos || !p.por_que_existimos || !p.missao) pend.push("Falta preencher alguma das três seções (O que fazemos, Por que existimos, Nossa missão).");
    if (!p.foto) pend.push("Sem foto: envie uma fotografia real do ministério.");
    if (!lideres.length) pend.push("Nenhum líder definido.");
    box.innerHTML = `<div class="stack">
      <div class="card glass"><div class="cp-acoes" style="justify-content:space-between;align-items:flex-start">
        <div><p class="eyebrow">Ministério${d.ativo ? "" : " · inativo"}</p><h3 style="margin:0">${h(d.nome)}</h3>
          <p class="cp-suave" style="font-size:15px;margin-top:6px">${p.textos_confirmados ? `Página publicada${p.confirmados_em ? " em " + h(data(p.confirmados_em)) : ""}` : '<span class="cp-rascunho">Rascunho — aguardando confirmação</span>'}
          ${p.exibir_publico && d.ativo ? ` · <a href="#ministerio/${h(d.slug)}" target="_blank" rel="noopener">ver no site</a>` : " · não aparece no site"}</p></div>
        <div class="cp-acoes"><button class="btn btn-s sm" type="button" data-in="verOrg">${ico("organogramas", 16)} Organograma</button>
          ${INST.inst?.master && !INST.semCadastro ? `<button class="btn btn-s sm" type="button" data-in="ativo">${d.ativo ? "Desativar ministério" : "Reativar ministério"}</button>` : ""}</div></div>
        ${pend.length ? `<div class="cp-pendente" style="margin-top:12px"><b>Para revisar:</b><ul style="margin:6px 0 0;padding-left:18px">${pend.map((x) => `<li>${h(x)}</li>`).join("")}</ul></div>` : ""}
      </div>
      <div class="two">
        <form class="formcard glass" id="inMinPagina" novalidate><h3>Página do ministério</h3>
          ${adm ? `<label>Descrição curta (aparece na lista)<textarea name="descricao" rows="2" maxlength="600">${h(d.descricao || "")}</textarea></label>` : ""}
          <label>O que fazemos<textarea name="o_que_fazemos" rows="4" maxlength="2000">${h(p.o_que_fazemos || "")}</textarea></label>
          <label>Por que existimos<textarea name="por_que_existimos" rows="4" maxlength="2000">${h(p.por_que_existimos || "")}</textarea></label>
          <label>Nossa missão<textarea name="missao" rows="3" maxlength="2000">${h(p.missao || "")}</textarea></label>
          <label>Informações complementares (opcional)<textarea name="complemento" rows="3" maxlength="3000">${h(p.complemento || "")}</textarea></label>
          <div class="cp-foto-site">${p.foto ? `<img src="${h(urlSite(p.foto))}" alt="" style="width:100%;max-height:220px;object-fit:cover;border-radius:16px">` : '<p class="cp-suave">Sem foto.</p>'}
            <input type="hidden" name="foto" value="${h(p.foto || "")}">
            <label>Trocar foto<input type="file" accept="image/jpeg,image/png,image/webp" data-in-foto="ministerio"></label>
            <label>Descrição da foto (acessibilidade)<input name="foto_alt" maxlength="200" value="${h(p.foto_alt || "")}"></label></div>
          <p class="notice">Use fotografias reais da Betel e respeite as autorizações de uso de imagem, principalmente de crianças.</p>
          ${adm ? `<label class="cuAceite cp-linha"><input class="cp-check" type="checkbox" name="exibir_publico"${p.exibir_publico ? " checked" : ""}> Mostrar este ministério no site</label>` : ""}
          <label class="cuAceite cp-linha"><input class="cp-check" type="checkbox" name="exibir_lider"${p.exibir_lider ? " checked" : ""}> Mostrar o nome da liderança na página pública</label>
          <div class="cp-acoes"><button class="btn btn-p" type="submit" data-publicar="1">Salvar e publicar</button><button class="btn btn-s" type="submit" data-publicar="0">Salvar como rascunho</button></div>
          ${p.textos_confirmados ? '<p class="cp-suave" style="font-size:13px">Atenção: salvar como rascunho tira os três textos do site até você publicar de novo.</p>' : ""}
          <span class="msg" role="status"></span></form>
        <div class="stack">
          ${adm ? `<form class="formcard glass" id="inMinLider" novalidate><h3>Liderança</h3>
            <p class="cp-suave" style="font-size:14px">O líder é escolhido entre os usuários cadastrados. Ele passa a ter, no sistema, as permissões de líder deste ministério (o perfil de acesso continua sendo definido em Usuários).</p>
            <div data-lideres>${lideres.map((l) => `<span class="mini" data-pessoa="${h(l.pessoa_id)}">${h(l.nome)}${l.perfil && l.perfil === "VOLUNTARIO" ? " ⚠" : ""} <button type="button" class="linkbtn" data-in="tirarLider:${h(l.pessoa_id)}" aria-label="Retirar ${h(l.nome)}">×</button></span>`).join(" ") || '<span class="cp-suave">Nenhum</span>'}</div>
            ${lideres.some((l) => l.perfil === "VOLUNTARIO") ? '<p class="cp-pendente">⚠ Este líder tem perfil de Voluntário: para ter acesso de líder, altere o perfil em Usuários.</p>' : ""}
            ${seletorPessoa("lider", "Adicionar líder")}
            <label>Vice-líder ou responsável auxiliar<select name="vice"><option value="">Nenhum</option>${ativos.filter((i) => i.funcao !== "lider").map((i) => `<option value="${h(i.pessoa_id)}"${i.pessoa_id === p.vice_pessoa_id ? " selected" : ""}>${h(i.nome)}</option>`).join("")}</select></label>
            <div class="cp-acoes"><button class="btn btn-p" type="submit">Salvar liderança</button></div><span class="msg" role="status"></span></form>` : ""}
          <div class="card glass"><h3>Integrantes (${ativos.length})</h3>
            <div class="list">${ativos.map((i) => `<div class="row"><div style="flex:1"><p class="n">${h(i.nome)} <span class="st ${i.funcao === "lider" ? "ok" : ""}">${h(FUNCAO[i.funcao] || i.funcao)}</span>${i.pessoa_id === p.vice_pessoa_id ? ' <span class="st">Vice-líder</span>' : ""}</p>
              <p class="m">${i.cargo ? h(i.cargo) + " · " : ""}desde ${h(data(i.desde))}</p></div>
              <div class="acts"><button class="mini sm" type="button" data-in="cargo:${h(i.pessoa_id)}">Função</button>${i.funcao !== "lider" || adm ? `<button class="mini sm" type="button" data-in="desvincular:${h(i.pessoa_id)}">Encerrar vínculo</button>` : ""}</div></div>`).join("") || '<p class="empty">Ninguém vinculado.</p>'}</div>
            <form id="inMinVinc" novalidate style="margin-top:14px"><p class="eyebrow">Vincular voluntário</p>${seletorPessoa("vinc", "Pessoa")}
              <label>Função ou responsabilidade (opcional)<input name="cargo" maxlength="80" placeholder="Ex.: Coordenação de som"></label>
              <div class="cp-acoes"><button class="btn btn-s" type="submit">Vincular</button></div>
              <p class="cp-suave" style="font-size:13px">As regras de voluntariado continuam valendo (membresia validada e Curso de Novos Membros).</p><span class="msg" role="status"></span></form>
          </div>
          <details class="card glass"><summary><b>Histórico de liderança e integrantes</b></summary>
            <div class="list" style="margin-top:10px">${d.historico.map((x) => `<div class="row"><div><p class="n">${h(descreverHist(x))}</p><p class="m">${h(dataHora(x.quando))}${x.ator ? " · por " + h(x.ator) : ""}</p></div></div>`).join("") || '<p class="empty">Sem alterações registradas.</p>'}</div></details>
        </div>
      </div></div>`;
  }
  function seletorPessoa(id, rotulo) {
    return `<div class="cp-sel-pessoa" data-sel="${id}"><label>${h(rotulo)}<input type="search" placeholder="Digite o nome" autocomplete="off" data-busca-pessoa="${id}"></label>
      <input type="hidden" name="pessoa_${id}"><div class="cp-sel-res" data-res="${id}"></div></div>`;
  }
  function descreverHist(x) {
    const a = x.antes || {}, d = x.depois || {};
    if (x.tabela === "ministerio_membros") {
      if (x.acao === "insert") return `${x.pessoa || "Pessoa"} vinculado(a) como ${FUNCAO[d.funcao] || d.funcao}`;
      if (a.ativo && d.ativo === false) return `Vínculo de ${x.pessoa || "pessoa"} encerrado`;
      if (!a.ativo && d.ativo) return `${x.pessoa || "Pessoa"} vinculado(a) novamente`;
      if (a.funcao !== d.funcao) return `${x.pessoa || "Pessoa"}: ${FUNCAO[a.funcao] || a.funcao} → ${FUNCAO[d.funcao] || d.funcao}`;
      if (a.cargo !== d.cargo) return `${x.pessoa || "Pessoa"}: função "${d.cargo || "sem função"}"`;
      return `Vínculo de ${x.pessoa || "pessoa"} atualizado`;
    }
    if (x.tabela === "ministerio_paginas") {
      if (a.vice_pessoa_id !== d.vice_pessoa_id) return d.vice_pessoa_id ? "Vice-líder definido" : "Vice-líder retirado";
      if (!a.textos_confirmados && d.textos_confirmados) return "Página publicada";
      if (a.textos_confirmados && !d.textos_confirmados) return "Página voltou para rascunho";
      return "Página do ministério editada";
    }
    if (x.tabela === "ministerios") return a.ativo !== d.ativo ? (d.ativo ? "Ministério reativado" : "Ministério desativado") : "Cadastro do ministério alterado";
    return x.acao;
  }
  let buscaTempo;
  document.addEventListener("input", (e) => {
    const inp = e.target.closest("[data-busca-pessoa]"); if (!inp || !inp.closest("#v-equipe")) return;
    const id = inp.dataset.buscaPessoa, res = inp.closest("[data-sel]").querySelector(`[data-res="${id}"]`);
    inp.closest("[data-sel]").querySelector(`[name="pessoa_${id}"]`).value = "";
    clearTimeout(buscaTempo);
    if (inp.value.trim().length < 2) { res.innerHTML = ""; return; }
    buscaTempo = setTimeout(async () => {
      try {
        const sb = INST.sb; const r = await rpc(sb, "pessoas_para_vinculo", { p_busca: inp.value });
        res.innerHTML = r.length ? r.map((p) => `<button type="button" class="mini sm" data-escolher="${h(id)}:${h(p.pessoa_id)}" data-nome="${h(p.nome)}">${h(p.nome)}${p.email ? " · " + h(p.email) : ""}</button>`).join(" ") : '<span class="cp-suave">Nenhum usuário encontrado.</span>';
      } catch (err) { res.innerHTML = `<span class="cp-suave">${h(err.message)}</span>`; }
    }, 280);
  });
  document.addEventListener("click", (e) => {
    const b = e.target.closest("[data-escolher]"); if (!b) return;
    const [id, pessoa] = b.dataset.escolher.split(":"); const sel = b.closest("[data-sel]");
    sel.querySelector(`[name="pessoa_${id}"]`).value = pessoa; sel.querySelector(`[data-busca-pessoa="${id}"]`).value = b.dataset.nome;
    sel.querySelector(`[data-res="${id}"]`).innerHTML = `<span class="cp-suave">Selecionado: ${h(b.dataset.nome)}</span>`;
  });
  async function cliqueMinisterio(e, c, ctx) {
    const b = e.target.closest("[data-in]"); if (!b || !c.contains(b)) return;
    const [acao, arg] = b.dataset.in.split(":");
    const sb = ctx.sb, d = MIN.dados;
    if (acao === "novoMin") {
      c.querySelector("#inMinNovo").innerHTML = `<form class="formcard glass" id="inMinCriar" novalidate><h3>Novo ministério</h3>
        <label>Nome<input name="nome" required maxlength="80"></label><label>Descrição curta<textarea name="descricao" rows="2" maxlength="600"></textarea></label>
        <div class="cp-acoes"><button class="btn btn-p" type="submit">Cadastrar</button><button class="btn btn-s" type="button" data-in="fecharNovo">Cancelar</button></div><span class="msg" role="status"></span></form>`;
      return;
    }
    if (acao === "fecharNovo") { c.querySelector("#inMinNovo").innerHTML = ""; return; }
    if (acao === "ativo") {
      if (d.ativo && b.dataset.confirmar !== "1") { b.dataset.confirmar = "1"; b.textContent = "Confirmar: sai do site, dados ficam guardados"; return; }
      return comBotao(b, async () => {
        await rpc(sb, "admin_salvar_ministerio", { p_id: d.id, p_nome: d.nome, p_descricao: d.descricao, p_ordem: d.ordem, p_ativo: !d.ativo });
        aviso(d.ativo ? "Ministério desativado (nada foi apagado)." : "Ministério reativado."); await ministerios(c, ctx);
      });
    }
    if (acao === "verOrg") { INST.orgAbrir = { ministerio_id: d.id }; location.hash = "#equipe/organogramas"; return; }
    if (acao === "tirarLider") {
      const restantes = d.integrantes.filter((i) => i.ativo && i.funcao === "lider" && i.pessoa_id !== arg).map((i) => i.pessoa_id);
      if (!restantes.length) return erro("O ministério precisa de pelo menos um líder. Adicione outro antes de retirar este.");
      return comBotao(b, async () => { MIN.dados = await rpc(sb, "ministerio_definir_lideranca", { p_ministerio: d.id, p_lideres: restantes, p_vice: d.pagina.vice_pessoa_id }); renderMinisterio(c.querySelector("#inMinEd"), ctx); aviso("Liderança atualizada."); });
    }
    if (acao === "cargo") {
      const atual = d.integrantes.find((i) => i.pessoa_id === arg);
      c.querySelector("#inMinCargo")?.remove();
      b.closest(".row").insertAdjacentHTML("afterend", `<form class="cp-acoes" id="inMinCargo" data-pessoa="${h(arg)}" novalidate style="margin:6px 0 12px">
        <input name="cargo" maxlength="80" value="${h(atual?.cargo || "")}" placeholder="Função de ${h(atual?.nome || "")} (em branco para retirar)" aria-label="Função" style="flex:1;min-width:200px">
        <button class="btn btn-p sm" type="submit">Salvar função</button><button class="btn btn-s sm" type="button" data-in="fecharCargo">Cancelar</button></form>`);
      c.querySelector("#inMinCargo [name=cargo]").focus(); return;
    }
    if (acao === "fecharCargo") { c.querySelector("#inMinCargo")?.remove(); return; }
    if (acao === "desvincular") {
      const p = d.integrantes.find((i) => i.pessoa_id === arg);
      if (b.dataset.confirmar !== "1") { b.dataset.confirmar = "1"; b.textContent = "Confirmar"; setTimeout(() => { if (b.isConnected) { b.dataset.confirmar = ""; b.textContent = "Encerrar vínculo"; } }, 4000); return; }
      return comBotao(b, async () => { MIN.dados = await rpc(sb, "ministerio_desvincular", { p_ministerio: d.id, p_pessoa: arg }); renderMinisterio(c.querySelector("#inMinEd"), ctx); aviso(`Vínculo de ${p?.nome || "pessoa"} encerrado (fica no histórico).`); });
    }
  }
  async function enviarMinisterio(e, c, ctx) {
    const f = e.target; if (!["inMinCriar", "inMinPagina", "inMinLider", "inMinVinc", "inMinCargo"].includes(fid(f))) return; e.preventDefault();
    const sb = ctx.sb, d = MIN.dados, msg = f.querySelector(".msg"), btn = e.submitter || f.querySelector("[type=submit]");
    const fd = new FormData(f);
    if (fid(f) === "inMinCriar") {
      return comBotao(btn, async () => {
        const r = await rpc(sb, "admin_salvar_ministerio", { p_id: null, p_nome: fd.get("nome"), p_descricao: fd.get("descricao"), p_ordem: MIN.lista.length + 1, p_ativo: true });
        MIN.atual = r.id; aviso("Ministério cadastrado."); await ministerios(c, ctx);
      });
    }
    if (fid(f) === "inMinPagina") {
      const dados = { o_que_fazemos: fd.get("o_que_fazemos"), por_que_existimos: fd.get("por_que_existimos"), missao: fd.get("missao"), complemento: fd.get("complemento"),
        foto: fd.get("foto"), foto_alt: fd.get("foto_alt"), exibir_lider: f.exibir_lider.checked };
      if (f.descricao) dados.descricao = fd.get("descricao");
      if (f.exibir_publico) dados.exibir_publico = f.exibir_publico.checked;
      const publicar = btn?.dataset.publicar === "1";
      return comBotao(btn, async () => {
        MIN.dados = await rpc(sb, "ministerio_salvar_pagina", { p_ministerio: d.id, p_dados: dados, p_publicar: publicar });
        renderMinisterio(c.querySelector("#inMinEd"), ctx); aviso(publicar ? "Página publicada no site." : "Rascunho salvo (não aparece no site).");
      });
    }
    if (fid(f) === "inMinLider") {
      const atuais = d.integrantes.filter((i) => i.ativo && i.funcao === "lider").map((i) => i.pessoa_id);
      const novo = fd.get("pessoa_lider"); const lideres = [...new Set(atuais.concat(novo ? [novo] : []))];
      if (!lideres.length) { msg.textContent = "Escolha pelo menos um líder."; return; }
      return comBotao(btn, async () => { MIN.dados = await rpc(sb, "ministerio_definir_lideranca", { p_ministerio: d.id, p_lideres: lideres, p_vice: fd.get("vice") || null }); renderMinisterio(c.querySelector("#inMinEd"), ctx); aviso("Liderança salva."); });
    }
    if (fid(f) === "inMinCargo") {
      return comBotao(btn, async () => { MIN.dados = await rpc(sb, "ministerio_definir_cargo", { p_ministerio: d.id, p_pessoa: f.dataset.pessoa, p_cargo: fd.get("cargo") }); renderMinisterio(c.querySelector("#inMinEd"), ctx); aviso("Função salva."); });
    }
    if (fid(f) === "inMinVinc") {
      if (!fd.get("pessoa_vinc")) { msg.textContent = "Busque e escolha a pessoa."; return; }
      return comBotao(btn, async () => { MIN.dados = await rpc(sb, "ministerio_vincular", { p_ministerio: d.id, p_pessoa: fd.get("pessoa_vinc"), p_cargo: fd.get("cargo") }); renderMinisterio(c.querySelector("#inMinEd"), ctx); aviso("Voluntário vinculado."); });
    }
  }
  // envio de foto do ministério (vai para site/ministerios/<id>/<aleatório>.jpg)
  document.addEventListener("change", async (e) => {
    const inp = e.target.closest('[data-in-foto="ministerio"]'); if (!inp || !inp.files?.[0]) return;
    const f = inp.closest("form"); const msg = f.querySelector(".msg");
    try {
      msg.textContent = "Enviando foto…";
      const blob = await prepararImagem(inp.files[0]); const caminho = `ministerios/${MIN.dados.id}/${uuid()}.jpg`;
      await enviarImagem(INST.sb, "site", caminho, blob);
      f.foto.value = "site/" + caminho;
      f.querySelector(".cp-foto-site img")?.remove();
      f.querySelector(".cp-foto-site").insertAdjacentHTML("afterbegin", `<img src="${h(urlSite("site/" + caminho))}" alt="" style="width:100%;max-height:220px;object-fit:cover;border-radius:16px">`);
      msg.textContent = "Foto enviada. Clique em salvar para usar na página.";
    } catch (err) { msg.textContent = err.message; }
  });

  /* =====================================================================
     ORGANOGRAMAS
     ===================================================================== */
  const ORG = { lista: [], atual: null, dados: null, recolhidos: new Set(), editando: null };
  const TIPO = { igreja: "Geral da Igreja", ministerio: "Ministérios", colegio: "Colégio", secretaria: "Secretaria", tesouraria: "Tesouraria" };
  async function organogramas(c, ctx) {
    ORG.lista = await rpc(ctx.sb, "organogramas_listar");
    if (INST.orgAbrir?.ministerio_id) { ORG.atual = ORG.lista.find((o) => o.ministerio_id === INST.orgAbrir.ministerio_id)?.id || ORG.atual; INST.orgAbrir = null; }
    if (!ORG.atual || !ORG.lista.some((o) => o.id === ORG.atual)) ORG.atual = ORG.lista[0]?.id;
    const tipoAtual = ORG.lista.find((o) => o.id === ORG.atual)?.tipo;
    const mins = ORG.lista.filter((o) => o.tipo === "ministerio");
    c.innerHTML = `<div class="stack">
      <div class="cp-org-abas" role="tablist" aria-label="Organogramas">${["igreja", "ministerio", "colegio", "secretaria", "tesouraria"].map((t) => {
        const alvo = t === "ministerio" ? (tipoAtual === "ministerio" ? ORG.atual : mins[0]?.id) : ORG.lista.find((o) => o.tipo === t)?.id;
        return alvo ? `<button class="mini" type="button" role="tab" data-org="abrir:${h(alvo)}" data-ativo="${tipoAtual === t}" aria-selected="${tipoAtual === t}">${h(TIPO[t])}</button>` : "";
      }).join("")}</div>
      ${tipoAtual === "ministerio" ? `<label style="max-width:420px">Ministério<select id="inOrgMin">${mins.map((o) => `<option value="${h(o.id)}"${o.id === ORG.atual ? " selected" : ""}>${h(o.titulo)}</option>`).join("")}</select></label>` : ""}
      <p class="cp-suave" style="font-size:14px">O organograma mostra a estrutura aprovada pela igreja. Ele <b>não</b> concede permissões no sistema: acessos são definidos separadamente, em Usuários.</p>
      <div id="inOrg"><p class="msg">Carregando…</p></div></div>`;
    c.querySelector("#inOrgMin")?.addEventListener("change", (e) => { ORG.atual = e.target.value; carregarOrg(c, ctx); });
    c.onclick = (e) => cliqueOrg(e, c, ctx);
    c.onsubmit = (e) => enviarOrg(e, c, ctx);
    await carregarOrg(c, ctx);
  }
  async function carregarOrg(c, ctx) {
    try { ORG.dados = await rpc(ctx.sb, "organograma_obter", { p_org: ORG.atual }); } catch (e) { c.querySelector("#inOrg").innerHTML = `<p class="msg">${h(e.message)}</p>`; return; }
    renderOrg(c.querySelector("#inOrg"));
  }
  function nomeNo(n) { return n.pessoa?.nome || n.nome_livre || ""; }
  function cartao(n, opts = {}) {
    const nome = nomeNo(n), aberto = ORG.detalhe === n.id;
    const filhos = opts.filhos || [];
    const rec = ORG.recolhidos.has(n.id);
    return `<li class="cp-org-no" data-no="${h(n.id || "")}">
      <div class="cp-org-cartao${opts.raiz ? " raiz" : ""}">
        ${avatar(nome || n.cargo, n.pessoa?.foto)}
        <div class="cp-org-info"><span class="cp-org-cargo">${h(n.cargo)}</span><b>${nome ? h(nome) : '<span class="cp-org-vazio">A definir</span>'}</b>
          ${opts.superior ? `<small>Responde a: ${h(opts.superior)}</small>` : ""}${opts.extra ? `<small>${h(opts.extra)}</small>` : ""}</div>
        <div class="cp-org-acoes">
          ${n.id && (n.responsabilidades || n.procurar_para) ? `<button class="cp-org-toggle" type="button" data-org="det:${h(n.id)}" aria-expanded="${aberto}" aria-label="Responsabilidades de ${h(n.cargo)}" title="Responsabilidades">i</button>` : ""}
          ${filhos.length ? `<button class="cp-org-toggle" type="button" data-org="rec:${h(n.id)}" aria-expanded="${!rec}" aria-label="${rec ? "Mostrar" : "Recolher"} subordinados" title="${rec ? "Mostrar" : "Recolher"}">${rec ? "+" : "−"}</button>` : ""}
          ${ORG.dados.pode_editar && n.id && !opts.virtual ? `<button class="mini sm" type="button" data-org="sub:${h(n.id)}" title="Adicionar subordinado">+ Sub</button><button class="mini sm" type="button" data-org="editar:${h(n.id)}">Editar</button><button class="mini sm" type="button" data-org="cima:${h(n.id)}" aria-label="Mover para cima">↑</button><button class="mini sm" type="button" data-org="baixo:${h(n.id)}" aria-label="Mover para baixo">↓</button>` : ""}
        </div></div>
      ${aberto ? `<div class="cp-org-det">${n.responsabilidades ? `<p><b>Responsabilidades:</b> ${h(n.responsabilidades)}</p>` : ""}${n.procurar_para ? `<p><b>Procure para:</b> ${h(n.procurar_para)}</p>` : ""}</div>` : ""}
      ${filhos.length && !rec ? `<ul class="cp-org-filhos">${filhos.join("")}</ul>` : ""}
    </li>`;
  }
  function arvore(nos, pai, superior) {
    return nos.filter((n) => (n.pai_id || null) === pai).sort((a, b) => a.ordem - b.ordem || a.cargo.localeCompare(b.cargo))
      .map((n) => cartao(n, { superior, filhos: arvore(nos, n.id, n.cargo + (nomeNo(n) ? " (" + nomeNo(n) + ")" : "")) }));
  }
  function renderOrg(box) {
    const d = ORG.dados;
    let html;
    if (d.tipo === "ministerio") {
      const m = d.ministerio || {};
      const lider = m.lideres?.[0];
      const virt = (p, cargo, extra) => cartao({ id: "", cargo, pessoa: p, ordem: 0 }, { virtual: true, extra });
      const dentro = arvore(d.nos, null, lider ? "Liderança" : "");
      if (m.vice) dentro.unshift(virt(m.vice, "Vice-líder", lider ? "Responde a: liderança do ministério" : ""));
      if (m.integrantes?.length) dentro.push(`<li class="cp-org-no"><div class="cp-org-cartao"><div class="cp-org-info"><span class="cp-org-cargo">Voluntários</span><b>${m.integrantes.length} integrante(s)</b></div></div>
        <ul class="cp-org-filhos">${m.integrantes.map((p) => virt(p, p.cargo || "Voluntário")).join("")}</ul></li>`);
      const raizes = (m.lideres || []).map((l) => cartao({ id: "", cargo: l.cargo || "Líder", pessoa: l, ordem: 0 }, { raiz: true, virtual: true }));
      html = raizes.length ? `<ul class="cp-org-arvore">${raizes[0].replace(/<\/li>$/, `<ul class="cp-org-filhos">${dentro.join("")}</ul></li>`)}${raizes.slice(1).join("")}</ul>`
        : `<p class="cp-pendente">Liderança ainda não definida (cadastre em Ministérios).</p><ul class="cp-org-arvore">${dentro.join("")}</ul>`;
    } else {
      const r = arvore(d.nos, null, "");
      html = r.length ? `<ul class="cp-org-arvore">${r.join("").replace('class="cp-org-cartao"', 'class="cp-org-cartao raiz"')}</ul>` : '<p class="empty">Nenhuma função cadastrada ainda.</p>';
    }
    box.innerHTML = `<div class="card glass">
      <div class="cp-acoes" style="justify-content:space-between"><div><p class="eyebrow">${h(TIPO[d.tipo])}</p><h3 style="margin:0">${h(d.titulo)}</h3>${d.descricao ? `<p class="cp-suave" style="font-size:15px;margin-top:6px">${h(d.descricao)}</p>` : ""}</div>
        ${d.pode_editar ? `<div class="cp-acoes"><button class="btn btn-p sm" type="button" data-org="novo:">+ Função</button><button class="btn btn-s sm" type="button" data-org="desc:">Editar descrição</button></div>` : ""}</div>
      <div id="inOrgForm"></div>
      <nav class="cp-org" aria-label="Organograma ${h(d.titulo)}">${html}</nav></div>`;
  }
  function formNo(n, paiPadrao) {
    const d = ORG.dados, nos = d.nos.filter((x) => !n || x.id !== n.id);
    return `<form class="formcard glass" id="inOrgNo" novalidate style="margin:14px 0"><h3>${n ? "Editar função" : "Nova função"}</h3>
      <input type="hidden" name="no_id" value="${h(n?.id || "")}"><input type="hidden" name="ordem" value="${h(n?.ordem ?? (d.nos.length + 1) * 10)}">
      <label>Cargo ou função *<input name="cargo" required maxlength="100" value="${h(n?.cargo || "")}" placeholder="Ex.: Coordenação de recepção"></label>
      <label>Subordinado a<select name="pai_id"><option value="">${d.tipo === "ministerio" ? "Liderança do ministério" : "Topo da estrutura"}</option>${nos.map((x) => `<option value="${h(x.id)}"${(n?.pai_id || paiPadrao) === x.id ? " selected" : ""}>${h(x.cargo)}${nomeNo(x) ? " — " + h(nomeNo(x)) : ""}</option>`).join("")}</select></label>
      ${seletorPessoa("org", "Pessoa (usuário cadastrado)")}
      ${n?.pessoa ? `<p class="cp-suave" style="font-size:14px">Atual: ${h(n.pessoa.nome)} <label class="cuAceite cp-linha"><input class="cp-check" type="checkbox" name="manter" checked> manter</label></p>` : ""}
      ${INST.inst?.master ? `<label>Ou nome (pessoa sem conta no sistema)<input name="nome_livre" maxlength="120" value="${h(n?.nome_livre || "")}"></label>` : ""}
      <label>Responsabilidades<textarea name="responsabilidades" rows="3" maxlength="1500">${h(n?.responsabilidades || "")}</textarea></label>
      <label>Quem deve procurar esta função? (tipos de demanda)<textarea name="procurar_para" rows="2" maxlength="500">${h(n?.procurar_para || "")}</textarea></label>
      <div class="cp-acoes"><button class="btn btn-p" type="submit">Salvar</button><button class="btn btn-s" type="button" data-org="cancelar:">Cancelar</button>
        ${n ? `<button class="btn btn-s" type="button" data-org="remover:${h(n.id)}">Retirar do organograma</button>` : ""}</div>
      <p class="cp-suave" style="font-size:13px">Retirar uma função não apaga a pessoa; os subordinados passam para o superior dela.</p><span class="msg" role="status"></span></form>`;
  }
  async function cliqueOrg(e, c, ctx) {
    const b = e.target.closest("[data-org]"); if (!b) return;
    const [acao, arg] = b.dataset.org.split(":");
    const sb = ctx.sb, d = ORG.dados, fbox = c.querySelector("#inOrgForm");
    if (acao === "abrir") { ORG.atual = arg; ORG.detalhe = null; return organogramas(c, ctx); }
    if (acao === "det") { ORG.detalhe = ORG.detalhe === arg ? null : arg; return renderOrg(c.querySelector("#inOrg")); }
    if (acao === "rec") { ORG.recolhidos.has(arg) ? ORG.recolhidos.delete(arg) : ORG.recolhidos.add(arg); return renderOrg(c.querySelector("#inOrg")); }
    if (acao === "novo") { fbox.innerHTML = formNo(null, null); fbox.querySelector("[name=cargo]").focus(); return; }
    if (acao === "sub") { fbox.innerHTML = formNo(null, arg); fbox.scrollIntoView({ block: "nearest" }); fbox.querySelector("[name=cargo]").focus(); return; }
    if (acao === "editar") { fbox.innerHTML = formNo(d.nos.find((n) => n.id === arg)); fbox.scrollIntoView({ block: "nearest" }); return; }
    if (acao === "cancelar") { fbox.innerHTML = ""; return; }
    if (acao === "desc") {
      fbox.innerHTML = `<form class="formcard glass" id="inOrgDesc" novalidate style="margin:14px 0"><label>Descrição do organograma<textarea name="descricao" rows="3" maxlength="1000">${h(d.descricao || "")}</textarea></label>
        <div class="cp-acoes"><button class="btn btn-p sm" type="submit">Salvar</button><button class="btn btn-s sm" type="button" data-org="cancelar:">Cancelar</button></div></form>`;
      return;
    }
    if (acao === "cima" || acao === "baixo") return comBotao(b, async () => { ORG.dados = await rpc(sb, "organograma_no_mover", { p_org: d.id, p_no: arg, p_direcao: acao === "cima" ? -1 : 1 }); renderOrg(c.querySelector("#inOrg")); });
    if (acao === "remover") {
      if (b.dataset.confirmar !== "1") { b.dataset.confirmar = "1"; b.textContent = "Confirmar retirada"; return; }
      return comBotao(b, async () => { ORG.dados = await rpc(sb, "organograma_no_remover", { p_org: d.id, p_no: arg }); renderOrg(c.querySelector("#inOrg")); aviso("Função retirada do organograma."); });
    }
  }
  async function enviarOrg(e, c, ctx) {
    const f = e.target; if (fid(f) === "inOrgDesc") {
      e.preventDefault(); const d = ORG.dados;
      return comBotao(f.querySelector("[type=submit]"), async () => { ORG.dados = await rpc(ctx.sb, "organograma_atualizar", { p_org: d.id, p_titulo: d.titulo, p_descricao: f.descricao.value }); renderOrg(c.querySelector("#inOrg")); aviso("Descrição salva."); });
    }
    if (fid(f) !== "inOrgNo") return; e.preventDefault();
    const fd = new FormData(f), d = ORG.dados, atual = d.nos.find((n) => n.id === fd.get("no_id"));
    const pessoa = fd.get("pessoa_org") || (atual?.pessoa && f.manter?.checked ? atual.pessoa.pessoa_id : "");
    const dados = { id: fd.get("no_id"), cargo: fd.get("cargo"), pai_id: fd.get("pai_id"), pessoa_id: pessoa, nome_livre: pessoa ? "" : fd.get("nome_livre") || "",
      responsabilidades: fd.get("responsabilidades"), procurar_para: fd.get("procurar_para"), ordem: Number(fd.get("ordem")) || 0 };
    await comBotao(f.querySelector("[type=submit]"), async () => { ORG.dados = await rpc(ctx.sb, "organograma_no_salvar", { p_org: d.id, p_dados: dados }); renderOrg(c.querySelector("#inOrg")); aviso("Organograma atualizado."); });
  }

  /* =====================================================================
     CONTEÚDO DO SITE (MASTER)
     ===================================================================== */
  const SITE = { conteudo: null, etapas: [] };
  const CAMPOS_CONTATO = {
    igreja: [["telefone", "Telefone (ligação)"], ["whatsapp", "WhatsApp"], ["instagram", "Instagram (@perfil)"], ["youtube", "YouTube (identificação, ex.: @canal)"], ["youtube_url", "YouTube (endereço https://)"], ["endereco", "Endereço (como aparece no site)"], ["cep", "CEP"], ["mapa", "Endereço para o mapa"]],
    celulas: [["whatsapp", "WhatsApp das células"]],
    colegio: [["telefone", "Telefone (ligação)"], ["whatsapp", "WhatsApp"], ["email", "E-mail"], ["instagram", "Instagram (@perfil)"], ["site", "Site oficial (https://)"], ["endereco", "Endereço"], ["mapa", "Endereço para o mapa"]],
  };
  const GRUPO = { igreja: "Igreja", celulas: "Células", colegio: "Colégio" };
  async function site(c, ctx) {
    const [conteudo, etapas] = await Promise.all([rpc(ctx.sb, "site_conteudo_publico"), rpc(ctx.sb, "colegio_etapas_admin")]);
    SITE.conteudo = conteudo; SITE.etapas = etapas;
    const ct = conteudo.contatos || {}, gal = conteudo.galeria_home || [];
    c.innerHTML = `<div class="stack">
      <form class="formcard glass" id="inSiteContatos" novalidate><h3>Contatos e links do site</h3>
        <p class="cp-suave" style="font-size:14px">Valem para todas as páginas: telefones viram link de ligação; WhatsApp abre a conversa; endereços abrem o mapa; redes mostram ícone e @. Só marque como WhatsApp números que têm WhatsApp.</p>
        ${Object.entries(CAMPOS_CONTATO).map(([g, cs]) => `<fieldset class="cp-fieldset"><legend>${h(GRUPO[g])}</legend><div class="formgrid">${cs.map(([k, r]) => `<label>${h(r)}<input name="${g}.${k}" value="${h(ct[g]?.[k] || "")}" maxlength="200"></label>`).join("")}</div></fieldset>`).join("")}
        <div class="cp-acoes"><button class="btn btn-p" type="submit">Salvar contatos</button></div><span class="msg" role="status"></span></form>
      <form class="formcard glass" id="inSiteGaleria" novalidate><h3>Fotos da Home</h3>
        <p class="cp-suave" style="font-size:14px">Fotografias reais da Betel: alegria, comunhão, adoração, oração e reverência. Respeite as autorizações de uso de imagem, principalmente de crianças. Até 16 fotos.</p>
        <div class="list" id="inGalLista">${gal.map((f, i) => linhaGaleria(f, i, gal.length)).join("")}</div>
        <label>Adicionar foto<input type="file" accept="image/jpeg,image/png,image/webp" data-in-foto="home"></label>
        <div class="cp-acoes"><button class="btn btn-p" type="submit">Salvar fotos da Home</button></div><span class="msg" role="status"></span></form>
      <div class="card glass"><h3>Colégio — etapas de ensino</h3>
        <p class="cp-suave" style="font-size:14px">Faixa etária e diferenciais só aparecem no site depois de preenchidos. Marque "validado" quando a direção confirmar o texto.</p>
        ${etapas.map(formEtapa).join("")}</div></div>`;
    c.onsubmit = (e) => enviarSite(e, c, ctx);
    c.onclick = (e) => cliqueSite(e, c, ctx);
  }
  function linhaGaleria(f, i, n) {
    return `<div class="row" data-gal="${i}"><img src="${h(urlSite(f.foto))}" alt="" style="width:88px;height:64px;object-fit:cover;border-radius:10px;flex:none">
      <div style="flex:1;display:grid;gap:6px"><input data-gal-campo="alt" value="${h(f.alt || "")}" maxlength="200" placeholder="Descrição da foto (obrigatória)" aria-label="Descrição da foto"><input data-gal-campo="legenda" value="${h(f.legenda || "")}" maxlength="40" placeholder="Legenda curta (ex.: Comunhão)" aria-label="Legenda"></div>
      <input type="hidden" data-gal-campo="foto" value="${h(f.foto)}">
      <div class="acts"><button class="mini sm" type="button" data-site="galCima:${i}"${i ? "" : " disabled"} aria-label="Subir">↑</button><button class="mini sm" type="button" data-site="galBaixo:${i}"${i < n - 1 ? "" : " disabled"} aria-label="Descer">↓</button><button class="mini sm" type="button" data-site="galTirar:${i}">Retirar</button></div></div>`;
  }
  function galeriaAtual(c) {
    return [...c.querySelectorAll("#inGalLista [data-gal]")].map((r) => ({ foto: r.querySelector('[data-gal-campo="foto"]').value, alt: r.querySelector('[data-gal-campo="alt"]').value.trim(), legenda: r.querySelector('[data-gal-campo="legenda"]').value.trim() }));
  }
  function redesenharGaleria(c, g) { c.querySelector("#inGalLista").innerHTML = g.map((f, i) => linhaGaleria(f, i, g.length)).join(""); }
  function formEtapa(e) {
    return `<form class="cp-etapa-form" data-etapa-id="${h(e.id)}" novalidate style="border-top:1px solid var(--linha);padding-top:16px;margin-top:16px">
      <p class="eyebrow">${h(e.titulo)} ${e.validado ? '<span class="st ok">Validado pela direção</span>' : '<span class="cp-rascunho">Aguardando validação da direção</span>'}</p>
      <div class="formgrid"><label>Título<input name="titulo" maxlength="80" value="${h(e.titulo)}"></label><label>Subtítulo<input name="subtitulo" maxlength="160" value="${h(e.subtitulo || "")}"></label></div>
      <label>Descrição<textarea name="descricao" rows="5" maxlength="4000">${h(e.descricao)}</textarea></label>
      <div class="formgrid"><label>Objetivos (um por linha)<textarea name="objetivos" rows="5">${h((e.objetivos || []).join("\n"))}</textarea></label>
        <label>Diferenciais pedagógicos confirmados (um por linha)<textarea name="diferenciais" rows="5" placeholder="Preencher somente com o que a direção confirmar">${h((e.diferenciais || []).join("\n"))}</textarea></label></div>
      <div class="formgrid"><label>Faixa etária (oficial)<input name="faixa_etaria" maxlength="120" value="${h(e.faixa_etaria || "")}" placeholder="A confirmar pela direção"></label>
        <label class="cuAceite cp-linha" style="align-self:end"><input class="cp-check" type="checkbox" name="ativo"${e.ativo ? " checked" : ""}> Mostrar no site</label></div>
      ${!e.faixa_etaria ? '<p class="cp-pendente">Faixa etária: a confirmar pela direção (não aparece no site enquanto estiver vazia).</p>' : ""}
      <div class="formgrid" style="align-items:end">${e.foto ? `<img src="${h(urlSite(e.foto))}" alt="" style="width:100%;max-height:160px;object-fit:cover;border-radius:14px">` : ""}
        <div><input type="hidden" name="foto" value="${h(e.foto || "")}"><label>Trocar foto<input type="file" accept="image/jpeg,image/png,image/webp" data-in-foto="colegio"></label>
        <label>Descrição da foto<input name="foto_alt" maxlength="200" value="${h(e.foto_alt || "")}"></label></div></div>
      <div class="cp-acoes"><button class="btn btn-p sm" type="submit" data-validado="1">Salvar como validado</button><button class="btn btn-s sm" type="submit" data-validado="0">Salvar</button></div><span class="msg" role="status"></span></form>`;
  }
  function cliqueSite(e, c) {
    const b = e.target.closest("[data-site]"); if (!b) return;
    const [acao, i] = b.dataset.site.split(":"); const g = galeriaAtual(c), k = Number(i);
    if (acao === "galTirar") g.splice(k, 1);
    if (acao === "galCima" && k > 0) [g[k - 1], g[k]] = [g[k], g[k - 1]];
    if (acao === "galBaixo" && k < g.length - 1) [g[k + 1], g[k]] = [g[k], g[k + 1]];
    redesenharGaleria(c, g);
  }
  async function enviarSite(e, c, ctx) {
    const f = e.target; if (!(fid(f) === "inSiteContatos" || fid(f) === "inSiteGaleria" || f.classList.contains("cp-etapa-form"))) return;
    e.preventDefault(); const btn = e.submitter || f.querySelector("[type=submit]");
    if (fid(f) === "inSiteContatos") {
      const ct = JSON.parse(JSON.stringify(SITE.conteudo.contatos || {}));
      new FormData(f).forEach((v, k) => { const [g, campo] = k.split("."); ct[g] = ct[g] || {}; ct[g][campo] = String(v).trim(); });
      return comBotao(btn, async () => { SITE.conteudo = await rpc(ctx.sb, "site_salvar_contatos", { p_contatos: ct }); aviso("Contatos salvos. O site já usa os novos dados."); });
    }
    if (fid(f) === "inSiteGaleria") {
      const g = galeriaAtual(c);
      if (g.some((x) => x.alt.length < 3)) return erro("Descreva cada foto (pelo menos 3 letras).");
      return comBotao(btn, async () => { SITE.conteudo = await rpc(ctx.sb, "site_salvar_galeria", { p_fotos: g }); redesenharGaleria(c, SITE.conteudo.galeria_home); aviso("Fotos da Home salvas."); });
    }
    if (f.classList.contains("cp-etapa-form")) {
      const fd = new FormData(f), linhas = (k) => String(fd.get(k) || "").split("\n").map((x) => x.trim()).filter(Boolean);
      const dados = { titulo: fd.get("titulo"), subtitulo: fd.get("subtitulo"), descricao: fd.get("descricao"), objetivos: linhas("objetivos"), diferenciais: linhas("diferenciais"),
        faixa_etaria: fd.get("faixa_etaria"), foto: fd.get("foto"), foto_alt: fd.get("foto_alt"), ativo: f.ativo.checked };
      return comBotao(btn, async () => { SITE.etapas = await rpc(ctx.sb, "colegio_etapa_salvar", { p_id: f.dataset.etapaId, p_dados: dados, p_validado: btn?.dataset.validado === "1" });
        const nova = SITE.etapas.find((x) => x.id === f.dataset.etapaId); f.outerHTML = formEtapa(nova); aviso("Etapa salva."); });
    }
  }
  document.addEventListener("change", async (e) => {
    const inp = e.target.closest('[data-in-foto="home"],[data-in-foto="colegio"]'); if (!inp || !inp.files?.[0]) return;
    const f = inp.closest("form"); const msg = f.querySelector(".msg"), tipo = inp.dataset.inFoto;
    try {
      msg.textContent = "Enviando foto…";
      const blob = await prepararImagem(inp.files[0]); const caminho = `${tipo}/${uuid()}.jpg`;
      await enviarImagem(INST.sb, "site", caminho, blob);
      if (tipo === "home") {
        const c = f.closest(".stack"); const g = galeriaAtual(c); g.push({ foto: "site/" + caminho, alt: "", legenda: "" }); redesenharGaleria(c, g);
        msg.textContent = "Foto adicionada. Escreva a descrição e salve.";
      } else { f.foto.value = "site/" + caminho; msg.textContent = "Foto enviada. Clique em salvar."; }
      inp.value = "";
    } catch (err) { msg.textContent = err.message; }
  });

  /* =====================================================================
     FORMULÁRIOS PRIVADOS DA AGENDA (coordenação)
     ===================================================================== */
  const AG = { filtro: "aguardando_analise", ultimoLink: null };
  const linkCompleto = (token) => `${location.origin}${location.pathname.replace(/[^/]*$/, "")}agendaministerialprivada/evento?t=${token}`;
  const SIT = { ativo: "Ativo", expirado: "Expirado", revogado: "Desativado" };
  const STATUS = { aguardando_analise: "Aguardando análise", aprovado: "Aprovado", recusado: "Recusado" };
  async function agendaLinks(c, ctx) {
    const [links, envios] = await Promise.all([rpc(ctx.sb, "agenda_links_listar"), rpc(ctx.sb, "agenda_envios_listar", { p_status: AG.filtro === "todos" ? null : AG.filtro })]);
    const { data: mins } = await ctx.sb.from("ministerios").select("id,nome").eq("ativo", true).order("ordem");
    c.innerHTML = `<div class="stack">
      <div class="two">
        <form class="formcard glass" id="inAgCriar" novalidate><h3>Gerar link privado</h3>
          <p class="cp-suave" style="font-size:14px">O responsável pelo evento preenche a ficha sem entrar na Área de Membros. O envio chega aqui como <b>solicitação pendente</b>: nada entra na Agenda sem a sua aprovação.</p>
          <label>Nome do link *<input name="rotulo" required maxlength="120" placeholder="Ex.: Ficha do Retiro de Casais"></label>
          <label>Ministério (opcional — fixa o ministério no formulário)<select name="ministerio"><option value="">Escolhido por quem preenche</option>${(mins || []).map((m) => `<option value="${h(m.id)}">${h(m.nome)}</option>`).join("")}</select></label>
          <label>Nome sugerido do evento (opcional)<input name="titulo" maxlength="120"></label>
          <div class="formgrid"><label>Validade (dias)<input name="dias" type="number" min="1" max="180" value="30" required></label>
            <label class="cuAceite cp-linha" style="align-self:end"><input class="cp-check" type="checkbox" name="complemento" checked> Permitir complementar enquanto estiver em análise</label></div>
          <div class="cp-acoes"><button class="btn btn-p" type="submit">${ico("agenda-links", 16)} Gerar link</button></div><span class="msg" role="status"></span>
          <div id="inAgNovo">${AG.ultimoLink ? blocoLink(AG.ultimoLink) : ""}</div></form>
        <div class="card glass"><h3>Links gerados</h3><div class="list">${links.map((l) => `<div class="row"><div style="flex:1"><p class="n">${h(l.rotulo)} <span class="st ${l.situacao === "ativo" ? "ok" : ""}">${h(SIT[l.situacao])}</span></p>
            <p class="m">${l.ministerio ? h(l.ministerio) + " · " : ""}válido até ${h(dataHora(l.expira_em))} · ${h(l.usos)} acesso(s)${l.envio ? " · envio: " + h(STATUS[l.envio.status]) : " · sem envio"}</p></div>
            <div class="acts">${l.situacao === "ativo" ? `<button class="mini sm" type="button" data-ag="revogar:${h(l.id)}">Desativar</button>` : ""}<button class="mini sm" type="button" data-ag="token:${h(l.id)}">Gerar novo link</button></div></div>`).join("") || '<p class="empty">Nenhum link gerado ainda.</p>'}</div>
          <p class="cp-suave" style="font-size:13px;margin-top:10px">Por segurança, o endereço completo só aparece quando é gerado. Se perder, use "Gerar novo link" (o anterior deixa de funcionar).</p></div>
      </div>
      <div class="card glass"><div class="cp-acoes" style="justify-content:space-between"><h3 style="margin:0">Envios recebidos</h3>
        <div class="toolbar">${[["aguardando_analise", "Aguardando"], ["aprovado", "Aprovados"], ["recusado", "Recusados"], ["todos", "Todos"]].map(([k, n]) => `<button class="mini" type="button" data-ag="filtro:${k}" data-ativo="${AG.filtro === k}">${n}</button>`).join("")}</div></div>
        <div class="list" style="margin-top:10px">${envios.map(cartaoEnvio).join("") || '<p class="empty">Nenhum envio nesta situação.</p>'}</div></div></div>`;
    c.onsubmit = (e) => enviarAg(e, c, ctx);
    c.onclick = (e) => cliqueAg(e, c, ctx);
  }
  function blocoLink(r) {
    const u = linkCompleto(r.token);
    return `<div class="stack" style="margin-top:14px"><p class="eyebrow">Link pronto — copie agora</p><p class="cp-link-gerado">${h(u)}</p>
      <div class="cp-acoes"><button class="btn btn-s sm" type="button" data-sb-copiar="${h(u)}">Copiar link</button><a class="btn btn-s sm" href="${h(u)}" target="_blank" rel="noopener noreferrer">Abrir</a></div>
      <p class="cp-suave" style="font-size:13px">Pode ser colocado no PDF interativo da ficha. Quem tiver o link consegue apenas enviar as informações deste evento.</p></div>`;
  }
  function cartaoEnvio(e) {
    const d = e.dados || {};
    const campos = [["Evento", d.titulo], ["Data", data(d.data)], ["Horário", d.horario], ["Ministério", d.ministerio], ["Líder", d.lider], ["Espaços", d.local],
      ["Mídia", d.necessita_midia], ["Louvor", d.necessita_louvor], ["Diaconia", d.necessita_diaconia], ["Tema", d.midia_tema], ["Arte", d.midia_arte], ["Banner", d.midia_banner],
      ["Inscrição", d.midia_inscricao], ["Link de inscrição", d.midia_link_inscricao], ["Informações para a arte", d.midia_info], ["Observações", d.observacoes],
      ["Contato", [d.contato_nome, d.contato_telefone].filter(Boolean).join(" · ")]].filter((x) => x[1]);
    return `<details class="row" style="display:block"${e.status === "aguardando_analise" ? " open" : ""}><summary><b>${h(d.titulo || "Evento")}</b> · ${h(data(d.data))} · ${h(d.ministerio || "")} <span class="st ${e.status === "aprovado" ? "ok" : ""}">${h(STATUS[e.status])}</span>
        <span class="m"> — ${h(e.link)} · enviado ${h(dataHora(e.enviado_em))}${e.versao > 1 ? ` · complementado ${e.versao - 1}x` : ""}</span></summary>
      <dl class="cp-dl">${campos.map(([k, v]) => `<dt>${h(k)}</dt><dd>${h(v)}</dd>`).join("")}</dl>
      ${e.status === "aguardando_analise" ? `<form class="cp-acoes" data-ag-envio="${h(e.id)}" novalidate><input name="motivo" maxlength="500" placeholder="Observação (obrigatória para recusar)" style="flex:1;min-width:220px">
        <button class="btn btn-p sm" type="submit" data-decisao="aprovar">Aprovar e criar na Agenda</button><button class="btn btn-s sm" type="submit" data-decisao="recusar">Recusar</button></form>`
        : `<p class="m">${e.status === "aprovado" ? `Evento criado na Agenda (nº ${h(e.evento_id)})` : "Recusado"}${e.decidido_por ? " por " + h(e.decidido_por) : ""} em ${h(dataHora(e.decidido_em))}${e.motivo ? ` — ${h(e.motivo)}` : ""}</p>`}
      ${e.historico?.length ? `<p class="m">Histórico: ${e.historico.map((x) => `${h(dataHora(x.quando))} ${h(x.acao)}`).join(" · ")}</p>` : ""}</details>`;
  }
  async function cliqueAg(e, c, ctx) {
    const b = e.target.closest("[data-ag]"); if (!b) return;
    const [acao, arg] = b.dataset.ag.split(":");
    if (acao === "filtro") { AG.filtro = arg; return agendaLinks(c, ctx); }
    if (acao === "revogar") {
      if (b.dataset.confirmar !== "1") { b.dataset.confirmar = "1"; b.textContent = "Confirmar"; return; }
      return comBotao(b, async () => { await rpc(ctx.sb, "agenda_link_revogar", { p_link: arg }); aviso("Link desativado."); await agendaLinks(c, ctx); });
    }
    if (acao === "token") {
      if (b.dataset.confirmar !== "1") { b.dataset.confirmar = "1"; b.textContent = "Confirmar (o link anterior para de funcionar)"; return; }
      return comBotao(b, async () => { AG.ultimoLink = await rpc(ctx.sb, "agenda_link_novo_token", { p_link: arg, p_dias: null }); await agendaLinks(c, ctx); aviso("Novo link gerado."); c.querySelector("#inAgNovo")?.scrollIntoView({ block: "nearest" }); });
    }
  }
  async function enviarAg(e, c, ctx) {
    const f = e.target; if (!(fid(f) === "inAgCriar" || f.dataset.agEnvio)) return;
    e.preventDefault(); const btn = e.submitter || f.querySelector("[type=submit]");
    if (fid(f) === "inAgCriar") {
      const fd = new FormData(f);
      return comBotao(btn, async () => {
        AG.ultimoLink = await rpc(ctx.sb, "agenda_link_criar", { p_rotulo: fd.get("rotulo"), p_ministerio: fd.get("ministerio") || null, p_titulo: fd.get("titulo"), p_dias: Number(fd.get("dias")), p_permite_complemento: f.complemento.checked });
        await agendaLinks(c, ctx); aviso("Link gerado. Copie agora.");
      });
    }
    if (f.dataset.agEnvio) {
      const decisao = btn?.dataset.decisao, motivo = f.motivo.value.trim();
      if (decisao === "recusar" && !motivo) return erro("Informe o motivo da recusa.");
      return comBotao(btn, async () => {
        const r = await rpc(ctx.sb, "agenda_envio_decidir", { p_envio: f.dataset.agEnvio, p_decisao: decisao, p_motivo: motivo || null });
        aviso(decisao === "aprovar" ? `Aprovado: evento criado na Agenda (nº ${r.evento_id}).` : "Envio recusado."); await agendaLinks(c, ctx);
      });
    }
  }

  const INST = { sb: null, inst: null, orgAbrir: null };
  window.BetelInstitucional = {
    iniciar(ctx) { INST.sb = ctx.sb; INST.inst = ctx.inst; },
    ministerios: (c, ctx) => { INST.sb = ctx.sb; INST.inst = ctx.inst; INST.semCadastro = !!ctx.semCadastro; return ministerios(c, ctx); },
    organogramas: (c, ctx) => { INST.sb = ctx.sb; INST.inst = ctx.inst; return organogramas(c, ctx); },
    site: (c, ctx) => { INST.sb = ctx.sb; INST.inst = ctx.inst; return site(c, ctx); },
    agendaLinks: (c, ctx) => { INST.sb = ctx.sb; INST.inst = ctx.inst; return agendaLinks(c, ctx); },
    prepararImagem, enviarImagem, urlPerfil, avatar,
  };
})();
