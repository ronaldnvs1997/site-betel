/* =====================================================================
   Mídia e Audiovisual — solicitações de apoio, escalas e confirmações
   - "Solicitar mídia": ministérios pedem cobertura (não cria escala)
   - "Mídia": liderança avalia, planeja cada evento e acompanha
   - "Minhas escalas": cada voluntário confirma ou recusa a própria escala
   Toda regra e permissão é conferida no banco.
   ===================================================================== */
(() => {
  const TZ = "America/Sao_Paulo";
  const h = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const el = (id) => document.getElementById(id);
  const dt = (d) => d ? new Date(d).toLocaleString("pt-BR", { timeZone: TZ, weekday: "short", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }) : "";
  const hora = (d) => d ? new Date(d).toLocaleTimeString("pt-BR", { timeZone: TZ, hour: "2-digit", minute: "2-digit" }) : "";
  const dataBR = (d) => d ? new Date(String(d).length === 10 ? d + "T12:00:00" : d).toLocaleDateString("pt-BR", { timeZone: TZ }) : "";
  const inLocal = (d) => d ? new Date(d).toLocaleString("sv-SE", { timeZone: TZ }).slice(0, 16).replace(" ", "T") : "";
  const deLocal = (v) => v ? `${v}:00-03:00` : null;                 // Brasília (sem horário de verão)
  const hojeISO = () => new Date().toLocaleDateString("sv-SE", { timeZone: TZ });
  const STP = { rascunho: "Rascunho (não publicado)", aguardando: "Aguardando confirmação", confirmado: "Confirmado", recusado: "Recusado", substituicao_necessaria: "Substituição necessária", substituido: "Substituído", cancelado: "Cancelado pelo líder" };
  const STS = { enviada: "Enviada", em_analise: "Em análise", aguardando_informacoes: "Aguardando informações", aprovada: "Aprovada", aprovada_parcial: "Aprovada em parte", recusada: "Recusada", cancelada: "Cancelada" };
  const STE = { planejamento: "Em planejamento", publicada: "Publicada", concluida: "Concluída", cancelada: "Cancelada" };
  const TIPOS = { culto: "Culto", conferencia: "Conferência", acampamento: "Acampamento", reuniao: "Reunião", acao_evangelistica: "Ação evangelística", batismo: "Batismo", treinamento: "Treinamento", programacao_especial: "Programação especial", outro: "Outro" };
  const DIAS = ["Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"];
  const HAB = { habilitado: "Habilitado", em_treinamento: "Em treinamento", suspenso: "Suspenso" };
  const cor = (s) => (["confirmado", "aprovada", "concluida", "publicada"].includes(s) ? "ok" : ["recusado", "recusada", "cancelado", "cancelada", "substituido"].includes(s) ? "" : "novo");
  const chip = (s, mapa) => `<span class="st ${cor(s)}">${h(mapa[s] || s)}</span>`;
  const msgErro = async (error) => error?.message || "Não foi possível concluir.";
  /* ================= Solicitar mídia ================= */
  async function solicitar(box, { sb }) {
    box.innerHTML = '<p class="msg">Carregando…</p>';
    const [{ data: d, error }, { data: servicos }, ag] = await Promise.all([sb.rpc("apoio_minhas_solicitacoes"), sb.rpc("apoio_servicos_listar", {}),
      sb.from("eventos").select("id,titulo,data,local,ministerio").order("data")]);
    if (error) { box.innerHTML = `<p class="notice">${h(error.message)}</p>`; return; }
    const eventos = (ag.data || []).filter((e) => String(e.data || "") >= hojeISO());
    const form = d.ministerios.length ? `<form class="formcard glass" id="msForm" novalidate><h3 class="cp-secao">Pedir cobertura ou suporte da Mídia</h3>
      <p class="msg">O pedido vai para a liderança de Mídia, que avalia o que será atendido. Enviar não cria escala nem garante todos os serviços.</p>
      <div class="formgrid"><label>Ministério solicitante<select name="min">${d.ministerios.map((m) => `<option value="${h(m.id)}">${h(m.nome)}</option>`).join("")}</select></label>
      <label>Evento da Agenda<select name="evento"><option value="">Não está na Agenda (preencher abaixo)</option>${eventos.map((e) => `<option value="${h(e.id)}">${h(dataBR(e.data))} · ${h(e.titulo)}</option>`).join("")}</select></label>
      <label class="cp-full">Nome do evento ou programação<input name="titulo" maxlength="140"></label>
      <label>Tipo<select name="tipo">${Object.entries(TIPOS).map(([k, n]) => `<option value="${k}">${n}</option>`).join("")}</select></label><label>Local<input name="local" maxlength="200"></label>
      <label>Início<input type="datetime-local" name="inicio"></label><label>Término<input type="datetime-local" name="fim"></label>
      <label>Responsável pela solicitação<input name="resp" maxlength="120"></label><label>Contato<input name="contato" maxlength="120" placeholder="(31) 9…"></label>
      <label class="cp-full">Objetivo da programação<input name="objetivo" maxlength="600"></label>
      <label class="cp-full">Descrição da necessidade<textarea name="descricao" rows="3" maxlength="2000"></textarea></label></div>
      <fieldset class="tmPart"><legend>Serviços solicitados (marque um ou mais e explique o que espera)</legend><div class="cp-lista-opcoes">
        ${(servicos || []).map((s) => `<div><label><input type="checkbox" name="serv" value="${h(s.id)}"> ${h(s.nome)}</label><input name="det-${h(s.id)}" maxlength="600" placeholder="O que você espera deste serviço" hidden style="margin-top:6px"></div>`).join("")}</div></fieldset>
      <div class="formgrid"><label class="cp-full">Informações adicionais e orientações<textarea name="info" rows="2" maxlength="2000"></textarea></label>
      <label>Prazo para retorno<input type="date" name="prazo" min="${hojeISO()}"></label></div>
      <div><button class="btn btn-p" type="submit">Enviar solicitação</button></div><span class="msg" role="status"></span></form>`
      : '<p class="notice">Somente a liderança de um ministério, a Secretaria ou a coordenação da Agenda podem pedir apoio da Mídia.</p>';
    box.innerHTML = form + `<h3 class="cp-secao cp-espaco">Minhas solicitações</h3>` + (d.solicitacoes.map((s) => cardSolicitacao(s, false)).join("") || '<p class="empty">Nenhuma solicitação.</p>');
    if (box.dataset.ok) return; box.dataset.ok = "1";
    box.addEventListener("change", (ev) => {
      if (ev.target.name === "serv") ev.target.closest("div").querySelector("input[name^='det-']").hidden = !ev.target.checked;
      if (ev.target.name === "evento") { const f = ev.target.form, manual = !ev.target.value; for (const n of ["titulo", "local", "inicio", "fim"]) f.elements[n].closest("label").style.opacity = manual ? 1 : 0.5; }
    });
    box.addEventListener("submit", async (ev) => {
      ev.preventDefault(); const f = ev.target, msg = f.querySelector(".msg"), v = (n) => (f.elements[n]?.value ?? "").trim();
      let r;
      if (f.id === "msForm") {
        const servs = [...f.querySelectorAll("input[name=serv]:checked")].map((c) => ({ servico_id: c.value, detalhe: v("det-" + c.value) }));
        r = await sb.rpc("apoio_solicitar", { p: { ministerio_solicitante: v("min"), evento_id: v("evento") || null, titulo: v("titulo"), tipo_evento: v("tipo"), local: v("local"),
          inicio: deLocal(v("inicio")), fim: deLocal(v("fim")), responsavel_nome: v("resp"), responsavel_contato: v("contato"), objetivo: v("objetivo"), descricao: v("descricao"),
          informacoes: v("info"), prazo_retorno: v("prazo") || null, servicos: servs } });
      } else if (f.dataset.msResp) r = await sb.rpc("apoio_mensagem", { p_solicitacao: f.dataset.msResp, p_tipo: "resposta", p_texto: v("texto") });
      else if (f.dataset.msCanc) r = await sb.rpc("apoio_cancelar", { p_solicitacao: f.dataset.msCanc, p_motivo: v("motivo") });
      else return;
      if (r.error) { msg.textContent = await msgErro(r.error); return; }
      solicitar(box, { sb });
    });
  }
  function cardSolicitacao(s, interno) {
    return `<div class="card glass cp-card" id="sol-${h(s.id)}"><div><p class="eyebrow">${h(s.ministerio_solicitante)} · ${h(TIPOS[s.tipo_evento])}</p><h3>${h(s.titulo)} ${chip(s.status, STS)}</h3>
      <p class="cp-meta">${h(dt(s.inicio))} a ${h(hora(s.fim))} · ${h(s.local)}${s.evento_id ? " · ligado à Agenda" : ""} · pedido por ${h(s.solicitado_por)} (${h(s.responsavel_nome)}${s.responsavel_contato ? ", " + h(s.responsavel_contato) : ""})${s.prazo_retorno ? " · retorno até " + h(dataBR(s.prazo_retorno)) : ""}</p>
      ${s.objetivo ? `<p class="cp-meta"><b>Objetivo:</b> ${h(s.objetivo)}</p>` : ""}${s.descricao ? `<p class="cp-meta"><b>Necessidade:</b> ${h(s.descricao)}</p>` : ""}${s.informacoes ? `<p class="cp-meta"><b>Informações:</b> ${h(s.informacoes)}</p>` : ""}
      ${s.motivo ? `<p class="cp-meta"><b>Retorno da Mídia:</b> ${h(s.motivo)}</p>` : ""}</div>
      <div>${s.servicos.map((x) => `<p class="cp-meta">• <b>${h(x.nome)}</b>${x.detalhe ? " — " + h(x.detalhe) : ""}${x.origem === "acrescentado" ? " <span class='st'>acrescentado pela Mídia</span>" : ""}
        ${x.decisao === "atender" ? " <span class='st ok'>será atendido</span>" : x.decisao === "nao_atender" ? ` <span class='st'>não será atendido</span> ${h(x.motivo || "")}` : ""}
        ${interno && !["recusada", "cancelada"].includes(s.status) ? ` · <button class="linkbtn" type="button" data-ml="serv:atender:${h(s.id)}:${h(x.servico_id)}">atender</button> · <button class="linkbtn" type="button" data-ml="servNao:${h(s.id)}:${h(x.servico_id)}">não atender</button>` : ""}</p>`).join("")}</div>
      <div>${s.mensagens.map((m) => `<p class="cp-meta"><b>${h(m.autor)}</b> (${h(dt(m.criado_em))})${m.tipo === "pedido_informacao" ? " pediu informações" : m.tipo === "nota_interna" ? " · nota interna" : ""}: ${h(m.texto)}</p>`).join("")}</div>
      ${!interno && !["recusada", "cancelada"].includes(s.status) ? `<form class="cp-pilha" data-ms-resp="${h(s.id)}" novalidate><label>${s.status === "aguardando_informacoes" ? "Responder ao pedido de informações" : "Mensagem para a Mídia"}<textarea name="texto" rows="2" maxlength="2000"></textarea></label><div class="cp-acoes"><button class="mini sm" type="submit">Enviar</button></div><span class="msg"></span></form>
        ${!s.escala || s.escala.status !== "publicada" ? `<form class="cp-form-linha" data-ms-canc="${h(s.id)}" novalidate><label class="cp-cresce">Cancelar a solicitação (motivo)<input name="motivo" maxlength="600"></label><button class="mini sm" type="submit">Cancelar</button><span class="msg"></span></form>` : ""}` : ""}
      <div class="sbExtra"></div></div>`;
  }

  /* ================= Minhas escalas (voluntário) ================= */
  async function voluntario(box, { sb }) {
    box.innerHTML = '<p class="msg">Carregando…</p>';
    const [r1, r2] = await Promise.all([sb.rpc("minhas_escalas"), sb.rpc("minha_disponibilidade")]);
    if (r1.error || r2.error) { box.innerHTML = `<p class="notice">${h((r1.error || r2.error).message)}</p>`; return; }
    const es = r1.data, disp = r2.data, agora = Date.now();
    const futuras = es.filter((e) => new Date(e.fim) > agora && e.evento.status !== "cancelada");
    const pend = futuras.filter((e) => e.status === "aguardando" && e.evento.status === "publicada");
    const conf = futuras.filter((e) => e.status === "confirmado");
    const outras = es.filter((e) => !pend.includes(e) && !conf.includes(e) && (new Date(e.fim) > agora || ["cancelado"].includes(e.status)));
    const hist = es.filter((e) => new Date(e.fim) <= agora && !outras.includes(e));
    const card = (e, acoes) => `<div class="card glass cp-card" id="mv-${h(e.id)}"><div><p class="eyebrow">${h(e.evento.ministerio)} · ${h(e.area)}</p><h3>${h(e.evento.titulo)}</h3>
      <p class="cp-meta">${h(dt(e.inicio))} a ${h(hora(e.fim))} · ${h(e.evento.local)}</p>
      <p class="cp-meta">Função: <b>${h(e.funcao)}</b>${e.papel === "principal" ? " (responsável principal)" : ""}${e.atividade ? " · " + h(e.atividade) : ""} · escala de ${h(e.evento.responsavel || "liderança")}</p>
      <p>${chip(e.status, STP)}${e.atrasada ? ' <span class="st">prazo vencido</span>' : ""}${e.status === "aguardando" && e.prazo ? ` <span class="cp-meta">responda até ${h(dt(e.prazo))}</span>` : ""}${e.presenca ? ` <span class="st ${e.presenca === "presente" ? "ok" : ""}">${h(e.presenca)}</span>` : ""}</p>
      ${e.evento.orientacoes ? `<p class="cp-meta"><b>Orientações gerais:</b> ${h(e.evento.orientacoes)}</p>` : ""}${e.orientacoes_funcao ? `<p class="cp-meta"><b>Para ${h(e.funcao)}:</b> ${h(e.orientacoes_funcao)}</p>` : ""}
      ${e.orientacoes_individuais ? `<p class="cp-meta"><b>Para você:</b> ${h(e.orientacoes_individuais)}</p>` : ""}${e.motivo_cancelamento ? `<p class="cp-meta">${h(e.motivo_cancelamento)}</p>` : ""}
      ${e.equipe?.length ? `<p class="cp-meta"><b>Equipe:</b> ${e.equipe.map((x) => h(x.nome) + " (" + h(x.funcao) + ")").join(", ")}</p>` : ""}</div>${acoes || ""}<span class="msg" role="status"></span></div>`;
    const botoes = (e) => `<div class="cp-acoes"><button class="btn btn-p cp-btn-grande" type="button" data-mv="confirmar:${h(e.id)}:${e.versao}">Confirmar presença</button><button class="btn btn-s cp-btn-grande" type="button" data-mv="recusarForm:${h(e.id)}:${e.versao}">Não poderei participar</button></div><div class="sbExtra"></div>`;
    const habil = disp.habilitacoes.map((x) => `${h(x.funcao)} <span class="st ${x.status === "habilitado" ? "ok" : ""}">${h(HAB[x.status])}</span>`).join(" · ") || "Nenhuma função habilitada ainda.";
    box.innerHTML = `<h3 class="cp-secao cp-espaco">Aguardando a sua resposta (${pend.length})</h3>${pend.map((e) => card(e, botoes(e))).join("") || '<p class="empty">Nada pendente.</p>'}
      <h3 class="cp-secao cp-espaco">Próximas escalas confirmadas (${conf.length})</h3>${conf.map((e) => card(e, `<div class="cp-acoes"><button class="mini sm" type="button" data-mv="recusarForm:${h(e.id)}:${e.versao}">Não poderei mais participar</button></div><div class="sbExtra"></div>`)).join("") || '<p class="empty">Nenhuma.</p>'}
      ${outras.length ? `<h3 class="cp-secao cp-espaco">Recusadas, alteradas e canceladas</h3>${outras.map((e) => card(e)).join("")}` : ""}
      <details style="margin-top:20px"><summary style="cursor:pointer;font-weight:700">Histórico de participação (${hist.length})</summary>${hist.map((e) => card(e)).join("") || '<p class="empty">Ainda sem histórico.</p>'}</details>
      <div class="card glass cp-card" style="margin-top:26px"><h3>Minhas funções</h3><p class="cp-meta">${habil}</p>${disp.capacitacoes.length ? `<p class="cp-meta">Capacitações: ${disp.capacitacoes.map((c) => h(c.titulo) + " (" + h(dataBR(c.realizada_em)) + ")").join(", ")}</p>` : ""}</div>
      <form class="formcard glass" id="mvDisp" novalidate><h3 class="cp-secao">Minha disponibilidade</h3><p class="msg">Serve de referência para a liderança. A escala só vale depois da sua confirmação.</p>
        <div id="mvSemana">${(disp.semana.length ? disp.semana : [{}]).map(linhaDia).join("")}</div><div><button class="mini sm" type="button" data-mv="maisDia">+ dia e horário</button></div>
        <fieldset class="tmPart"><legend>Funções de preferência</legend><div class="cp-opcoes">${disp.funcoes_disponiveis.map((f) => `<label><input type="checkbox" name="pref" value="${h(f.id)}"${disp.preferencias.funcoes?.includes(f.id) ? " checked" : ""}> ${h(f.nome)}</label>`).join("") || "—"}</div></fieldset>
        <label>Observações importantes<textarea name="obs" rows="2" maxlength="1000">${h(disp.preferencias.observacoes || "")}</textarea></label>
        <div><button class="btn btn-p" type="submit">Salvar disponibilidade</button></div><span class="msg" role="status"></span></form>
      <form class="formcard glass" id="mvIndisp" novalidate style="margin-top:16px"><h3 class="cp-secao">Datas em que não poderei servir</h3>
        ${disp.indisponibilidades.map((i) => `<p class="cp-meta">${h(dataBR(i.inicio))}${i.fim !== i.inicio ? " a " + h(dataBR(i.fim)) : ""} · ${h({ data: "data", ferias: "férias", afastamento: "afastamento", temporaria: "indisponibilidade temporária" }[i.tipo])}${i.motivo ? " · " + h(i.motivo) : ""} · <button class="linkbtn" type="button" data-mv="remInd:${h(i.id)}">remover</button></p>`).join("") || '<p class="cp-meta">Nenhuma data marcada.</p>'}
        <div class="formgrid"><label>De<input type="date" name="inicio" min="${hojeISO()}"></label><label>Até<input type="date" name="fim" min="${hojeISO()}"></label>
        <label>Tipo<select name="tipo"><option value="data">Data</option><option value="ferias">Férias</option><option value="afastamento">Afastamento</option><option value="temporaria">Indisponibilidade temporária</option></select></label>
        <label>Motivo (opcional, só a liderança vê)<input name="motivo" maxlength="300"></label></div><div><button class="mini sm" type="submit">Incluir</button></div><span class="msg" role="status"></span></form>`;
    if (box.dataset.ok) return; box.dataset.ok = "1";
    box.addEventListener("click", async (ev) => {
      const b = ev.target.closest("[data-mv]"); if (!b) return;
      const [a, x, ver] = b.dataset.mv.split(":");
      if (a === "maisDia") return el("mvSemana").insertAdjacentHTML("beforeend", linhaDia({}));
      if (a === "remDia") return b.closest(".mvDia").remove();
      if (a === "recusarForm") return void (el("mv-" + x).querySelector(".sbExtra").innerHTML = `<form data-mv-recusa="${h(x)}" data-versao="${h(ver)}" novalidate style="display:grid;gap:8px;margin-top:8px"><label>Motivo (opcional, vai para a liderança)<input name="motivo" maxlength="600"></label><div class="cp-acoes"><button class="btn btn-p cp-btn-grande" type="submit">Confirmar que não poderei</button></div></form>`);
      let r;
      if (a === "confirmar") { b.disabled = true; r = await sb.rpc("escala_responder", { p_participacao: x, p_resposta: "confirmar", p_versao: Number(ver), p_motivo: null }); }
      if (a === "remInd") r = await sb.rpc("minha_indisponibilidade", { p_acao: "remover", p: { id: x } });
      if (r?.error) { b.disabled = false; (b.closest(".cp-card, form")?.querySelector(".msg") || {}).textContent = r.error.message; return; }
      voluntario(box, { sb });
    });
    box.addEventListener("submit", async (ev) => {
      ev.preventDefault(); const f = ev.target, msg = f.querySelector(".msg") || f.closest(".cp-card")?.querySelector(".msg"); let r;
      if (f.dataset.mvRecusa) r = await sb.rpc("escala_responder", { p_participacao: f.dataset.mvRecusa, p_resposta: "recusar", p_versao: Number(f.dataset.versao), p_motivo: f.elements.motivo.value });
      else if (f.id === "mvDisp") {
        const semana = [...f.querySelectorAll(".mvDia")].map((d) => ({ dia: d.querySelector("[name=dia]").value, de: d.querySelector("[name=de]").value, ate: d.querySelector("[name=ate]").value })).filter((d) => d.de && d.ate);
        r = await sb.rpc("salvar_minha_disponibilidade", { p: { semana, preferencias: { funcoes: [...f.querySelectorAll("input[name=pref]:checked")].map((c) => c.value), observacoes: f.elements.obs.value } } });
      } else if (f.id === "mvIndisp") {
        if (!f.elements.inicio.value) { msg.textContent = "Informe a data."; return; }
        r = await sb.rpc("minha_indisponibilidade", { p_acao: "incluir", p: { inicio: f.elements.inicio.value, fim: f.elements.fim.value || f.elements.inicio.value, tipo: f.elements.tipo.value, motivo: f.elements.motivo.value } });
      } else return;
      if (r.error) { if (msg) msg.textContent = r.error.message; return; }
      voluntario(box, { sb });
    });
  }
  const linhaDia = (d) => `<div class="mvDia formgrid" style="align-items:end"><label>Dia<select name="dia">${DIAS.map((n, i) => `<option value="${i}"${Number(d.dia) === i ? " selected" : ""}>${n}</option>`).join("")}</select></label>
    <label>Das<input type="time" name="de" value="${h(d.de || "")}"></label><label>Até<input type="time" name="ate" value="${h(d.ate || "")}"></label><div><button class="linkbtn" type="button" data-mv="remDia">remover</button></div></div>`;

  /* ================= Liderança de Mídia ================= */
  const L = { tela: "painel", escala: null, filtros: {}, cat: null };
  async function lider(box, ctx) {
    const sb = ctx.sb; L.sb = sb; L.box = box;
    box.innerHTML = '<p class="msg">Carregando…</p>';
    try {
      L.cat = (await sb.rpc("midia_catalogo", {})).data;
      const m = (t, n) => `<button class="mini sm" type="button" data-ml="tela:${t}"${L.tela === t ? ' data-ativo=""' : ""}>${n}</button>`;
      const topo = `<div class="toolbar">${m("painel", "Painel")}${m("solicitacoes", "Solicitações")}${L.escala ? m("evento", "Evento aberto") : ""}${m("equipe", "Equipe e habilitações")}${L.cat.pode_gerir ? m("catalogo", "Funções e serviços") : ""}${m("relatorios", "Relatórios")}</div>`;
      const corpo = L.tela === "painel" ? await telaPainel() : L.tela === "solicitacoes" ? await telaSolicitacoes() : L.tela === "evento" ? await telaEvento()
        : L.tela === "equipe" ? await telaEquipe() : L.tela === "catalogo" ? telaCatalogo() : telaRelatorios();
      box.innerHTML = topo + corpo;
    } catch (e) { box.innerHTML = `<p class="notice">${h(e.message)}</p>`; }
    if (!box.dataset.ok) { box.dataset.ok = "1"; box.addEventListener("click", cliqueLider); box.addEventListener("submit", envioLider); box.addEventListener("change", mudancaLider); }
  }
  async function rpc(n, a) { const { data, error } = await L.sb.rpc(n, a || {}); if (error) throw new Error(error.message); return data; }
  const todasFuncoes = () => L.cat.areas.flatMap((a) => a.funcoes.filter((f) => f.ativo).map((f) => ({ ...f, area: a.nome, area_id: a.id })));

  async function telaPainel() {
    const d = await rpc("midia_painel", { p_filtros: L.filtros }), r = d.resumo, f = L.filtros;
    const k = (n, t) => `<div class="cp-kpi"><b>${h(n)}</b><span>${h(t)}</span></div>`;
    const sols = await rpc("midia_solicitacoes", { p_filtros: { status: "abertas" } });
    return `<div class="cp-kpis">${k(r.solicitacoes_abertas, "solicitações aguardando avaliação")}${k(r.aguardando_confirmacao, "voluntários aguardando confirmação")}${k(r.atrasadas, "confirmações atrasadas")}
        ${k(r.confirmados, "confirmados nas próximas escalas")}${k(r.recusas, "recusas")}${k(r.substituicoes, "substituições necessárias")}${k(r.indisponiveis_semana, "indisponíveis nos próximos 7 dias")}</div>
      <form class="toolbar" id="mlFiltro" novalidate style="flex-wrap:wrap"><label class="cp-linha">De<input type="date" name="de" value="${h(f.de || "")}"></label>
        <label class="cp-linha">Até<input type="date" name="ate" value="${h(f.ate || "")}"></label><input name="busca" placeholder="Evento" value="${h(f.busca || "")}">
        <select name="status"><option value="">Todas as situações</option>${Object.entries(STE).map(([a, n]) => `<option value="${a}"${f.status === a ? " selected" : ""}>${n}</option>`).join("")}</select>
        <select name="funcao_id"><option value="">Todas as funções</option>${todasFuncoes().map((x) => `<option value="${h(x.id)}"${f.funcao_id === x.id ? " selected" : ""}>${h(x.nome)}</option>`).join("")}</select>
        <select name="confirmacao"><option value="">Qualquer confirmação</option>${["aguardando", "confirmado", "recusado", "substituicao_necessaria"].map((a) => `<option value="${a}"${f.confirmacao === a ? " selected" : ""}>${STP[a]}</option>`).join("")}</select>
        <button class="mini sm" type="submit">Filtrar</button></form>
      ${sols.length ? `<p class="notice" style="margin-bottom:14px">${sols.length} solicitação(ões) aguardando avaliação. <button class="linkbtn" type="button" data-ml="tela:solicitacoes">Avaliar</button></p>` : ""}
      <div class="glass list">${d.eventos.map((e) => `<div class="row"><div><p class="n cp-item-titulo">${h(e.titulo)} ${chip(e.status, STE)}${e.vagas_abertas ? ` <span class="st">substituição necessária (${e.vagas_abertas})</span>` : ""}${e.funcoes_vazias || e.abaixo_referencia ? ' <span class="st">equipe incompleta</span>' : ""}</p>
          <p class="m">${h(dt(e.inicio))} · ${h(e.local)}${e.solicitante ? " · pedido de " + h(e.solicitante) : ""} · ${e.funcoes} função(ões) · ${e.escalados} escalado(s), ${e.confirmados} confirmado(s), ${e.aguardando} aguardando</p></div>
          <div class="acts"><button class="btn btn-p sm" type="button" data-ml="abrir:${h(e.id)}">Abrir</button></div></div>`).join("") || '<p class="empty cp-vazio">Nenhum evento no período.</p>'}</div>
      ${d.agenda_pendentes.length ? `<h3 class="cp-subsecao cp-espaco">Na Agenda com "Necessita mídia: Sim" e sem pedido</h3><div class="glass list">${d.agenda_pendentes.map((e) => `<div class="row"><div><p class="n" style="font-size:15px">${h(e.titulo)}</p><p class="m">${h(dataBR(e.data))} ${h(e.horario || "")} · ${h(e.local || "")} · ${h(e.ministerio || "")}</p></div><div class="acts"><button class="mini sm" type="button" data-ml="escalaAgenda:${h(e.id)}">Montar escala</button></div></div>`).join("")}</div>` : ""}
      ${formNovaEscala()}`;
  }
  function formNovaEscala() {
    return `<details style="margin-top:22px"><summary style="cursor:pointer;font-weight:700">Nova escala sem solicitação</summary><form class="formcard glass" id="mlNova" novalidate style="margin-top:10px">
      <div class="formgrid"><label class="cp-full">Título<input name="titulo" maxlength="140"></label><label>Início<input type="datetime-local" name="inicio"></label><label>Término<input type="datetime-local" name="fim"></label><label>Local<input name="local" maxlength="200"></label></div>
      ${seletorFuncoes([])}<div><button class="btn btn-p" type="submit">Criar escala</button></div><span class="msg"></span></form></details>`;
  }
  const seletorFuncoes = (marcadas) => `<fieldset class="tmPart"><legend>Equipes e funções deste evento (só as necessárias)</legend>${L.cat.areas.filter((a) => a.ativo).map((a) => `<div><p style="font-weight:600;margin:4px 0">${h(a.nome)}</p><div class="cp-opcoes">${a.funcoes.filter((f) => f.ativo).map((f) => `<label><input type="checkbox" name="funcao" value="${h(f.id)}"${marcadas.includes(f.id) ? " checked" : ""}> ${h(f.nome)}</label>`).join("")}</div></div>`).join("")}</fieldset>`;

  async function telaSolicitacoes() {
    const fs = L.filtros.sol || "abertas";
    const lista = await rpc("midia_solicitacoes", { p_filtros: fs === "todas" ? {} : { status: fs } });
    const servOps = L.cat.servicos.filter((s) => s.ativo).map((s) => `<option value="${h(s.id)}">${h(s.nome)}</option>`).join("");
    return `<div class="toolbar"><select data-ml-filtro="sol"><option value="abertas">Aguardando avaliação</option><option value="aprovada"${fs === "aprovada" ? " selected" : ""}>Aprovadas</option><option value="aprovada_parcial"${fs === "aprovada_parcial" ? " selected" : ""}>Aprovadas em parte</option><option value="recusada"${fs === "recusada" ? " selected" : ""}>Recusadas</option><option value="todas"${fs === "todas" ? " selected" : ""}>Todas</option></select><span class="msg">${lista.length} solicitação(ões)</span></div>`
      + (lista.map((s) => cardSolicitacao(s, true).replace('<div class="sbExtra"></div>', `${!["recusada", "cancelada"].includes(s.status) ? `
        <form class="cp-pilha" data-ml-form="msg" data-id="${h(s.id)}" novalidate><div class="formgrid"><label>Tipo<select name="tipo"><option value="pedido_informacao">Pedir informações</option><option value="mensagem">Mensagem ao solicitante</option><option value="nota_interna">Nota interna (só a liderança vê)</option></select></label><label>Texto<input name="texto" maxlength="2000"></label></div><div><button class="mini sm" type="submit">Registrar</button></div><span class="msg"></span></form>
        ${L.cat.pode_gerir ? `<form class="cp-form-linha" data-ml-form="acrescentar" data-id="${h(s.id)}" novalidate><label>Acrescentar serviço<select name="servico">${servOps}</select></label><label class="cp-cresce">Detalhe<input name="detalhe" maxlength="600"></label><button class="mini sm" type="submit">Acrescentar</button><span class="msg"></span></form>
        <div class="cp-acoes">${["aprovada", "aprovada_parcial"].includes(s.status) ? "" : `<button class="btn btn-p sm" type="button" data-ml="aprovar:${h(s.id)}">Aprovar</button>`}<button class="mini sm" type="button" data-ml="recusarSol:${h(s.id)}">Recusar</button></div>` : ""}` : ""}
        ${["aprovada", "aprovada_parcial"].includes(s.status) ? (s.escala ? `<div><button class="btn btn-p sm" type="button" data-ml="abrir:${h(s.escala.id)}">Abrir a escala</button></div>` : `<div><button class="btn btn-p sm" type="button" data-ml="escalaSol:${h(s.id)}">Montar a escala</button></div>`) : ""}
        <div class="sbExtra"></div>`)).join("") || '<p class="empty">Nenhuma solicitação.</p>');
  }

  async function telaEvento() {
    const e = await rpc("midia_evento", { p_escala: L.escala }), aberto = ["planejamento", "publicada"].includes(e.status), comecou = new Date(e.inicio) <= Date.now();
    const usadas = e.areas.filter((a) => a.usada), naoUsadas = e.areas.filter((a) => !a.usada);
    const presentes = new Set(usadas.flatMap((a) => a.funcoes.map((f) => f.funcao_id)));
    const faltam = todasFuncoes().filter((f) => !presentes.has(f.id));
    const pessoa = (p, f) => `<div class="cp-pessoa" id="mp-${h(p.id)}"><b>${h(p.nome)}</b>${p.papel === "principal" ? ' <span class="st">principal</span>' : ""} ${chip(p.status, STP)}${p.atrasada ? ' <span class="st">prazo vencido</span>' : ""}${p.vaga_aberta ? ' <span class="st">vaga a substituir</span>' : ""}
        ${p.atividade ? `<span class="cp-meta">· ${h(p.atividade)}</span>` : ""}${p.inicio ? `<span class="cp-meta">· ${h(hora(p.inicio))}–${h(hora(p.fim))}</span>` : ""}${p.motivo_recusa ? `<span class="cp-meta">· “${h(p.motivo_recusa)}”</span>` : ""}${p.presenca ? ` <span class="st ${p.presenca === "presente" ? "ok" : ""}">${h(p.presenca)}</span>` : ""}
        ${aberto && ["rascunho", "aguardando", "confirmado"].includes(p.status) ? `<button class="linkbtn" type="button" data-ml="editarP:${h(p.id)}:${h(f.id)}">alterar</button> <button class="linkbtn" type="button" data-ml="subForm:${h(p.id)}:${h(f.id)}">substituir</button> <button class="linkbtn" type="button" data-ml="cancP:${h(p.id)}">cancelar</button>` : ""}
        ${aberto && p.vaga_aberta ? `<button class="linkbtn" type="button" data-ml="subForm:${h(p.id)}:${h(f.id)}">escolher substituto</button> <button class="linkbtn" type="button" data-ml="dispensar:${h(p.id)}">não precisa substituir</button>` : ""}
        ${comecou && !["rascunho", "substituido", "cancelado"].includes(p.status) ? `<select data-ml-presenca="${h(p.id)}"><option value="">Presença…</option><option value="presente"${p.presenca === "presente" ? " selected" : ""}>Serviu</option><option value="parcial"${p.presenca === "parcial" ? " selected" : ""}>Serviu em parte</option><option value="ausente"${p.presenca === "ausente" ? " selected" : ""}>Não serviu</option></select>` : ""}
        <div class="sbExtra" style="flex-basis:100%"></div></div>`;
    const funcao = (f) => { const situ = f.vagas_abertas ? "substituição necessária" : !f.ativos ? "sem ninguém" : f.confirmados === f.ativos && (!f.quantidade_referencia || f.ativos >= f.quantidade_referencia) ? "completa" : "com pendências";
      return `<div class="cp-subitem" id="mf-${h(f.id)}"><p><b>${h(f.funcao)}</b> <span class="st ${situ === "completa" ? "ok" : situ === "com pendências" ? "novo" : ""}">${situ}</span> <span class="cp-meta">${f.confirmados}/${f.ativos} confirmado(s)${f.quantidade_referencia ? ` · referência ${f.quantidade_referencia}` : ""}${f.hora_inicio ? ` · ${h(hora(f.hora_inicio))}–${h(hora(f.hora_fim))}` : ""}</span></p>
        ${f.orientacoes ? `<p class="cp-meta">Orientações: ${h(f.orientacoes)}</p>` : ""}${f.participacoes.map((p) => pessoa(p, f)).join("") || '<p class="cp-meta">Ninguém escalado.</p>'}
        ${aberto ? `<div class="cp-acoes"><button class="mini sm" type="button" data-ml="addForm:${h(f.id)}">+ voluntário</button><button class="linkbtn" type="button" data-ml="funForm:${h(f.id)}">orientações e horário</button>${!f.ativos ? `<button class="linkbtn" type="button" data-ml="remFun:${h(f.id)}">retirar função</button>` : ""}</div>` : ""}<div class="sbExtra"></div></div>`; };
    return `<div class="card glass cp-card"><p class="eyebrow">${e.solicitacao ? "Pedido de " + h(e.solicitacao.ministerio_solicitante) : "Escala da Mídia"}${e.evento_id ? " · ligado à Agenda" : ""} · versão ${e.versao}</p>
      <h3 style="font-size:26px">${h(e.titulo)} ${chip(e.status, STE)}</h3><p class="cp-meta">${h(dt(e.inicio))} a ${h(hora(e.fim))} · ${h(e.local)} · prazo de confirmação ${h(dt(e.prazo_confirmacao))}</p>
      ${e.orientacoes_gerais ? `<p class="cp-meta"><b>Orientações gerais:</b> ${h(e.orientacoes_gerais)}</p>` : ""}
      <div class="cp-acoes">${e.status === "planejamento" ? `<button class="btn btn-p sm" type="button" data-ml="publicar:${h(e.id)}">Publicar e pedir confirmações</button>` : ""}${aberto ? `<button class="mini sm" type="button" data-ml="editarE:${h(e.id)}">Alterar evento ou orientações</button><button class="mini sm" type="button" data-ml="cancE:${h(e.id)}">Cancelar escala</button>` : ""}
        ${e.status === "publicada" && new Date(e.fim) < Date.now() ? `<button class="mini sm" type="button" data-ml="concluir:${h(e.id)}">Concluir</button>` : ""}<button class="linkbtn" type="button" data-ml="hist:${h(e.id)}">histórico</button></div>
      ${usadas.some((a) => /Fotografia|Vídeo|Transmissão/.test(a.area)) ? '<p class="cp-meta">Antes de publicar fotos ou vídeos, consulte as autorizações de imagem (aba "Autorizações de imagem").</p>' : ""}<div id="mlEvExtra"></div></div>
      ${usadas.map((a) => `<div class="cp-grupo"><p class="eyebrow">${h(a.area)}</p>${a.funcoes.map(funcao).join("")}</div>`).join("") || '<p class="notice">Nenhuma equipe escolhida para este evento.</p>'}
      ${naoUsadas.length ? `<p class="cp-meta" style="margin-top:12px">Não necessárias neste evento: ${naoUsadas.map((a) => h(a.area)).join(", ")}.</p>` : ""}
      ${aberto && faltam.length ? `<form data-ml-form="incluirFun" novalidate style="display:flex;gap:8px;flex-wrap:wrap;align-items:end;margin-top:14px"><label>Incluir função<select name="funcao">${faltam.map((f) => `<option value="${h(f.id)}">${h(f.area)} · ${h(f.nome)}</option>`).join("")}</select></label><button class="mini sm" type="submit">Incluir</button><span class="msg"></span></form>` : ""}`;
  }
  async function formAdicionar(efId, alvo, substitui) {
    const sug = await rpc("escala_sugerir", { p_evento_funcao: efId });
    alvo.innerHTML = `<form class="formcard sbSub" data-ml-form="${substitui ? "substituir" : "adicionar"}" data-ef="${h(efId)}" data-sub="${h(substitui || "")}" novalidate>
      <label>Voluntário (sugestões em ordem: sem conflito, preferência e menos escalas recentes)<select name="pessoa">${sug.map((s) => `<option value="${h(s.pessoa_id)}">${h(s.nome)}${s.habilitacao === "em_treinamento" ? " · em treinamento" : ""} · ${s.escalas_60_dias} escala(s) em 60 dias${s.alertas.length ? " · ⚠ " + s.alertas.map((a) => a.texto).join("; ") : ""}</option>`).join("") || '<option value="">Ninguém habilitado disponível</option>'}</select></label>
      ${substitui ? "" : `<div class="formgrid"><label>Papel<select name="papel"><option value="auxiliar">Auxiliar</option><option value="principal">Responsável principal</option></select></label><label>Atividade específica<input name="atividade" maxlength="300"></label>
      <label>Das (opcional)<input type="datetime-local" name="inicio"></label><label>Até (opcional)<input type="datetime-local" name="fim"></label><label class="cp-full">Orientações individuais<input name="orient" maxlength="1000"></label></div>`}
      <div class="mdAlertas"></div><div class="cp-acoes"><button class="btn btn-p sm" type="submit">${substitui ? "Escalar substituto" : "Escalar"}</button></div><span class="msg"></span></form>`;
  }
  async function cliqueLider(ev) {
    const b = ev.target.closest("[data-ml]"); if (!b) return;
    const [a, x, y, z] = b.dataset.ml.split(":"), box = L.box;
    const extra = (id) => el(id)?.querySelector(".sbExtra");
    try {
      if (a === "tela") { L.tela = x; return lider(box, { sb: L.sb }); }
      if (a === "abrir") { L.escala = x; L.tela = "evento"; return lider(box, { sb: L.sb }); }
      if (a === "escalaSol" || a === "escalaAgenda") { const r = await rpc("midia_criar_escala", { p: a === "escalaSol" ? { solicitacao_id: x } : { evento_id: x } }); L.escala = r.id; L.tela = "evento"; return lider(box, { sb: L.sb }); }
      if (a === "serv") { await rpc("midia_decidir_servico", { p_solicitacao: y, p_servico: z, p_decisao: "atender", p_detalhe: null, p_motivo: null }); return lider(box, { sb: L.sb }); }
      if (a === "servNao") return void (extra("sol-" + x).innerHTML = `<form class="cp-form-linha" data-ml-form="servNao" data-id="${h(x)}" data-serv="${h(y)}" novalidate><label class="cp-cresce">Motivo (o solicitante vê)<input name="motivo" maxlength="600"></label><button class="mini sm" type="submit">Não atender</button><span class="msg"></span></form>`);
      if (a === "aprovar") { await rpc("midia_decidir_solicitacao", { p_solicitacao: x, p_acao: "aprovar", p_motivo: null }); L.filtros.sol = "todas"; return lider(box, { sb: L.sb }); }
      if (a === "recusarSol") return void (extra("sol-" + x).innerHTML = `<form class="cp-form-linha" data-ml-form="recusarSol" data-id="${h(x)}" novalidate><label class="cp-cresce">Motivo da recusa<input name="motivo" maxlength="600"></label><button class="mini sm" type="submit">Recusar</button><span class="msg"></span></form>`);
      if (a === "publicar") { if (b.dataset.ok !== "1") { b.dataset.ok = "1"; b.textContent = "Confirmar: avisar cada voluntário"; return; } const r = await rpc("escala_publicar", { p_escala: x }); BetelUI.aviso(`${r.avisados} voluntário(s) avisado(s) para confirmar.`); return lider(box, { sb: L.sb }); }
      if (a === "addForm") return formAdicionar(x, extra("mf-" + x), null);
      if (a === "subForm") return formAdicionar(y, extra("mp-" + x), x);
      if (a === "funForm") { const f = (await rpc("midia_evento", { p_escala: L.escala })).areas.flatMap((q) => q.funcoes).find((q) => q.id === x);
        return void (extra("mf-" + x).innerHTML = `<form class="formcard sbSub" data-ml-form="funcao" data-id="${h(x)}" novalidate><div class="formgrid"><label>Quantidade de referência<input type="number" min="1" max="99" name="qtd" value="${h(f.quantidade_referencia || "")}"></label><label>Das<input type="datetime-local" name="ini" value="${h(inLocal(f.hora_inicio))}"></label><label>Até<input type="datetime-local" name="fim" value="${h(inLocal(f.hora_fim))}"></label><label class="cp-full">Orientações desta função<textarea name="orient" rows="2" maxlength="2000">${h(f.orientacoes || "")}</textarea></label></div><label class="cuAceite cp-linha"><input class="cp-check" type="checkbox" name="exigir"> Exigir nova confirmação de quem já está escalado</label><div><button class="mini sm" type="submit">Salvar</button></div><span class="msg"></span></form>`); }
      if (a === "remFun") { await rpc("escala_funcao", { p_escala: L.escala, p_acao: "remover", p: { id: x } }); return lider(box, { sb: L.sb }); }
      if (a === "editarP") return void (extra("mp-" + x).innerHTML = `<form class="formcard sbSub" data-ml-form="editarP" data-id="${h(x)}" novalidate><div class="formgrid"><label>Papel<select name="papel"><option value="">(manter)</option><option value="auxiliar">Auxiliar</option><option value="principal">Responsável principal</option></select></label><label>Atividade<input name="atividade" maxlength="300"></label><label class="cp-full">Orientações individuais<input name="orient" maxlength="1000"></label><label class="cp-full">Observação da liderança (interna)<input name="obs" maxlength="1000"></label></div><p class="cp-meta">Mudar papel, atividade ou horário pede nova confirmação; orientações só avisam.</p><div><button class="mini sm" type="submit">Salvar</button></div><span class="msg"></span></form>`);
      if (a === "cancP") return void (extra("mp-" + x).innerHTML = `<form class="cp-form-linha" data-ml-form="cancP" data-id="${h(x)}" novalidate><label class="cp-cresce">Motivo (o voluntário é avisado)<input name="motivo" maxlength="600"></label><button class="mini sm" type="submit">Cancelar participação</button><span class="msg"></span></form>`);
      if (a === "dispensar") { await rpc("escala_participacao_acao", { p_part: x, p_acao: "dispensar_vaga", p: { motivo: "Vaga dispensada pela liderança" } }); return lider(box, { sb: L.sb }); }
      if (a === "editarE") { const e = await rpc("midia_evento", { p_escala: x });
        return void (el("mlEvExtra").innerHTML = `<form class="formcard sbSub" data-ml-form="editarE" data-id="${h(x)}" novalidate><div class="formgrid"><label>Título<input name="titulo" maxlength="140" value="${h(e.titulo)}"></label><label>Local<input name="local" maxlength="200" value="${h(e.local)}"></label>
          <label>Início${e.evento_id ? " (mude na Agenda)" : ""}<input type="datetime-local" name="inicio" value="${h(inLocal(e.inicio))}"${e.evento_id ? " disabled" : ""}></label><label>Término<input type="datetime-local" name="fim" value="${h(inLocal(e.fim))}"${e.evento_id ? " disabled" : ""}></label>
          <label>Prazo de confirmação<input type="datetime-local" name="prazo" value="${h(inLocal(e.prazo_confirmacao))}"></label><label class="cp-full">Orientações gerais<textarea name="orient" rows="2" maxlength="2000">${h(e.orientacoes_gerais || "")}</textarea></label></div>
          <label class="cuAceite cp-linha"><input class="cp-check" type="checkbox" name="exigir"> Mudança significativa: exigir nova confirmação de todos</label><div><button class="mini sm" type="submit">Salvar</button></div><span class="msg"></span></form>`); }
      if (a === "cancE") return void (el("mlEvExtra").innerHTML = `<form class="cp-form-linha" data-ml-form="cancE" data-id="${h(x)}" novalidate><label class="cp-cresce">Motivo do cancelamento (todos são avisados)<input name="motivo" maxlength="600"></label><button class="mini sm" type="submit">Cancelar a escala</button><span class="msg"></span></form>`);
      if (a === "concluir") { await rpc("escala_encerrar", { p_escala: x, p_acao: "concluir", p_motivo: null }); return lider(box, { sb: L.sb }); }
      if (a === "hist") { const hs = await rpc("escala_historico_listar", { p_escala: x });
        return void (el("mlEvExtra").innerHTML = `<div class="sbSub" style="padding-top:8px"><p class="cp-forte">Histórico</p>${hs.map((q) => `<p class="cp-meta">${h(dt(q.em))} · <b>${h(q.acao.replace(/_/g, " "))}</b>${q.pessoa ? " · " + h(q.pessoa) : ""}${q.ator ? " · por " + h(q.ator) : ""}</p>`).join("")}</div>`); }
      if (a === "csv") { const t = (L.rel || []).map((q) => [q.chave, q.escalados, q.confirmaram, q.recusaram, q.serviram, q.faltaram]);
        const csv = "﻿" + [["Grupo", "Escalados", "Confirmaram", "Recusaram", "Serviram", "Não serviram"], ...t].map((l) => l.map((c) => `"${String(c).replace(/"/g, '""')}"`).join(";")).join("\r\n");
        const lk = document.createElement("a"); lk.href = URL.createObjectURL(new Blob([csv], { type: "text/csv" })); lk.download = "escalas-midia.csv"; lk.click(); return; }
      if (a === "habForm") { const p = L.vols.find((v) => v.pessoa_id === x);
        return void (extra("mv-" + x).innerHTML = `<form class="formcard sbSub" data-ml-form="hab" data-id="${h(x)}" novalidate><div class="formgrid"><label>Função<select name="funcao">${todasFuncoes().map((f) => `<option value="${h(f.id)}">${h(f.area)} · ${h(f.nome)}</option>`).join("")}</select></label><label>Situação<select name="status"><option value="habilitado">Habilitado</option><option value="em_treinamento">Em treinamento</option><option value="suspenso">Suspenso</option></select></label><label class="cp-full">Observação<input name="obs" maxlength="600"></label></div><div><button class="mini sm" type="submit">Salvar habilitação</button></div><span class="msg"></span></form>
          <form class="formcard sbSub" data-ml-form="cap" data-id="${h(x)}" novalidate><div class="formgrid"><label>Capacitação ou treinamento<input name="titulo" maxlength="140"></label><label>Data<input type="date" name="data" max="${hojeISO()}"></label><label>Carga<input name="carga" maxlength="40"></label><label>Função relacionada<select name="funcao"><option value="">—</option>${todasFuncoes().map((f) => `<option value="${h(f.id)}">${h(f.nome)}</option>`).join("")}</select></label></div><div><button class="mini sm" type="submit">Registrar capacitação</button></div><span class="msg"></span></form>`); }
    } catch (e) { BetelUI.aviso(e.message); }
  }
  async function mudancaLider(ev) {
    const t = ev.target;
    try {
      if (t.dataset.mlFiltro === "sol") { L.filtros.sol = t.value; return lider(L.box, { sb: L.sb }); }
      if (t.dataset.mlPresenca && t.value) { await rpc("escala_participacao_acao", { p_part: t.dataset.mlPresenca, p_acao: "presenca", p: { presenca: t.value } }); return lider(L.box, { sb: L.sb }); }
    } catch (e) { BetelUI.aviso(e.message); }
  }
  async function envioLider(ev) {
    const f = ev.target; if (!L.box.contains(f)) return; ev.preventDefault();
    const msg = f.querySelector(".msg"), v = (n) => (f.elements[n]?.value ?? "").trim(), id = f.dataset.id;
    try {
      if (f.id === "mlFiltro") { L.filtros = Object.fromEntries(["de", "ate", "busca", "status", "funcao_id", "confirmacao"].map((n) => [n, v(n) || null]).filter(([, x]) => x)); return lider(L.box, { sb: L.sb }); }
      if (f.id === "mlNova") { const r = await rpc("midia_criar_escala", { p: { titulo: v("titulo"), inicio: deLocal(v("inicio")), fim: deLocal(v("fim")), local: v("local"), funcoes: [...f.querySelectorAll("input[name=funcao]:checked")].map((c) => c.value) } }); L.escala = r.id; L.tela = "evento"; return lider(L.box, { sb: L.sb }); }
      if (f.id === "mlRel") { L.relFiltro = { de: v("de"), ate: v("ate"), agrupar: v("agrupar") }; return lider(L.box, { sb: L.sb }); }
      switch (f.dataset.mlForm) {
        case "msg": await rpc("apoio_mensagem", { p_solicitacao: id, p_tipo: v("tipo"), p_texto: v("texto") }); break;
        case "acrescentar": await rpc("midia_decidir_servico", { p_solicitacao: id, p_servico: v("servico"), p_decisao: "acrescentar", p_detalhe: v("detalhe"), p_motivo: null }); break;
        case "servNao": await rpc("midia_decidir_servico", { p_solicitacao: id, p_servico: f.dataset.serv, p_decisao: "nao_atender", p_detalhe: null, p_motivo: v("motivo") }); break;
        case "recusarSol": await rpc("midia_decidir_solicitacao", { p_solicitacao: id, p_acao: "recusar", p_motivo: v("motivo") }); break;
        case "incluirFun": await rpc("escala_funcao", { p_escala: L.escala, p_acao: "incluir", p: { funcao_id: v("funcao") } }); break;
        case "funcao": await rpc("escala_funcao", { p_escala: L.escala, p_acao: "alterar", p: { id, quantidade_referencia: v("qtd"), orientacoes: v("orient"), hora_inicio: deLocal(v("ini")), hora_fim: deLocal(v("fim")), exigir_confirmacao: f.elements.exigir.checked } }); break;
        case "adicionar": case "substituir": {
          if (!v("pessoa")) throw new Error("Escolha o voluntário.");
          const ciente = f.dataset.ciente === "1";
          const r = f.dataset.mlForm === "adicionar"
            ? await rpc("escala_adicionar", { p_evento_funcao: f.dataset.ef, p_pessoa: v("pessoa"), p: { papel: v("papel"), atividade: v("atividade"), inicio: deLocal(v("inicio")), fim: deLocal(v("fim")), orientacoes_individuais: v("orient") }, p_ciente: ciente })
            : await rpc("escala_participacao_acao", { p_part: f.dataset.sub, p_acao: "substituir", p: { pessoa_id: v("pessoa"), ciente } });
          if (r && r.ok === false && r.precisa_ciencia) { f.dataset.ciente = "1"; f.querySelector(".mdAlertas").innerHTML = `<div class="cp-alerta"><b>Atenção:</b> ${r.alertas.map((q) => h(q.texto)).join("; ")}. Envie de novo para escalar mesmo assim.</div>`; f.querySelector("[type=submit]").textContent = "Escalar mesmo assim"; return; }
          break;
        }
        case "editarP": { const p = {}; if (v("papel")) p.papel = v("papel"); if (v("atividade")) p.atividade = v("atividade"); if (v("orient")) p.orientacoes_individuais = v("orient"); if (v("obs")) p.observacao_lider = v("obs");
          const r = await rpc("escala_alterar_participacao", { p_part: id, p }); if (r.nova_confirmacao) BetelUI.aviso("Nova confirmação pedida ao voluntário."); break; }
        case "cancP": await rpc("escala_participacao_acao", { p_part: id, p_acao: "cancelar", p: { motivo: v("motivo") } }); break;
        case "editarE": { const p = { titulo: v("titulo"), local: v("local"), orientacoes_gerais: v("orient"), prazo_confirmacao: deLocal(v("prazo")), exigir_confirmacao: f.elements.exigir.checked };
          if (!f.elements.inicio.disabled) { p.inicio = deLocal(v("inicio")); p.fim = deLocal(v("fim")); }
          const r = await rpc("escala_alterar", { p_escala: id, p }); if (r.nova_confirmacao) BetelUI.aviso(`${r.nova_confirmacao} voluntário(s) receberam pedido de nova confirmação.`); break; }
        case "cancE": await rpc("escala_encerrar", { p_escala: id, p_acao: "cancelar", p_motivo: v("motivo") }); break;
        case "hab": await rpc("midia_habilitar", { p_pessoa: id, p_funcao: v("funcao"), p_status: v("status"), p_observacao: v("obs") }); break;
        case "cap": await rpc("midia_registrar_capacitacao", { p_pessoa: id, p_funcao: v("funcao") || null, p_titulo: v("titulo"), p_data: v("data") || null, p_carga: v("carga"), p_observacao: null }); break;
        case "servico": await rpc("midia_salvar_catalogo", { p_tipo: "servico", p: { id: id || null, nome: v("nome"), ativo: f.elements.ativo ? f.elements.ativo.checked : true, funcoes: [...f.querySelectorAll("input[name=funcao]:checked")].map((c) => c.value) } }); break;
        case "area": await rpc("midia_salvar_catalogo", { p_tipo: "area", p: { id: id || null, nome: v("nome"), ativo: f.elements.ativo ? f.elements.ativo.checked : true } }); break;
        case "funcaoCat": await rpc("midia_salvar_catalogo", { p_tipo: "funcao", p: { id: id || null, area_id: v("area"), nome: v("nome"), exige_habilitacao: f.elements.exige.checked, aceita_em_treinamento: f.elements.treino.checked, quantidade_referencia: v("qtd"), orientacao_padrao: v("orient"), ativo: f.elements.ativo ? f.elements.ativo.checked : true } }); break;
        case "gestor": await rpc("midia_definir_gestor", { p_ministerio: L.cat.ministerio_id, p_perfil: v("perfil"), p_areas: [...f.querySelectorAll("input[name=area]:checked")].map((c) => c.value), p_ativo: v("ativo") !== "0" }); break;
        default: return;
      }
      return lider(L.box, { sb: L.sb });
    } catch (e) { if (msg) msg.textContent = e.message; else BetelUI.aviso(e.message); }
  }

  async function telaEquipe() {
    L.vols = await rpc("midia_voluntarios", {});
    return `<p class="msg" style="margin-bottom:12px">Integrantes ativos do ministério. Só quem tem habilitação ativa pode ser escalado em cada função, e só quem tem conta pode confirmar.</p><div class="glass list">${L.vols.map((p) => `<div class="sbItem" id="mv-${h(p.pessoa_id)}"><div class="row cp-topo"><div>
      <p class="n cp-item-titulo">${h(p.nome)}${p.funcao_ministerio === "lider" ? ' <span class="st">líder</span>' : ""}${p.tem_conta ? "" : ' <span class="st">sem conta: não pode ser escalado</span>'}</p>
      <p class="m">${p.habilitacoes.map((x) => `${h(x.funcao)} (${h(HAB[x.status])})`).join(" · ") || "Sem habilitações"}</p>
      <p class="m">${p.escalas_60_dias} escala(s) em 60 dias · serviu ${p.serviu_total} vez(es)${p.disponibilidade.length ? " · disponível: " + p.disponibilidade.map((d) => `${DIAS[d.dia].slice(0, 3)} ${d.de}–${d.ate}`).join(", ") : ""}${p.indisponibilidades.length ? " · indisponível: " + p.indisponibilidades.map((i) => `${dataBR(i.inicio)}–${dataBR(i.fim)}`).join(", ") : ""}</p>
      ${p.capacitacoes.length ? `<p class="m">Capacitações: ${p.capacitacoes.map((c) => h(c.titulo)).join(", ")}</p>` : ""}${p.preferencias?.observacoes ? `<p class="m">Observações: ${h(p.preferencias.observacoes)}</p>` : ""}</div>
      ${L.cat.pode_gerir ? `<div class="acts"><button class="mini sm" type="button" data-ml="habForm:${h(p.pessoa_id)}">Habilitações</button></div>` : ""}</div><div class="sbExtra"></div></div>`).join("") || '<p class="empty cp-vazio">Ninguém no ministério.</p>'}</div>`;
  }
  function telaCatalogo() {
    const c = L.cat, fns = todasFuncoes();
    return `<h3 class="cp-subsecao">Serviços que os ministérios podem pedir</h3>${c.servicos.map((s) => `<form class="formcard glass" data-ml-form="servico" data-id="${h(s.id)}" novalidate style="margin-bottom:10px"><div class="formgrid"><label>Nome<input name="nome" maxlength="80" value="${h(s.nome)}"></label><label class="cuAceite" style="flex-direction:row;align-self:end"><input class="cp-check" type="checkbox" name="ativo"${s.ativo ? " checked" : ""}> ativo</label></div>
      <div class="cp-opcoes"><span class="cp-meta">Funções sugeridas:</span>${fns.map((f) => `<label><input type="checkbox" name="funcao" value="${h(f.id)}"${s.funcoes.includes(f.id) ? " checked" : ""}> ${h(f.nome)}</label>`).join("")}</div><div><button class="mini sm" type="submit">Salvar</button></div><span class="msg"></span></form>`).join("")}
      <form class="formcard glass" data-ml-form="servico" novalidate style="margin-bottom:22px"><label>Novo serviço<input name="nome" maxlength="80"></label><div><button class="mini sm" type="submit">Incluir serviço</button></div><span class="msg"></span></form>
      <h3 class="cp-subsecao">Equipes e funções</h3>${c.areas.map((a) => `<div class="cp-grupo"><form class="cp-form-linha" data-ml-form="area" data-id="${h(a.id)}" novalidate><label>Equipe<input name="nome" maxlength="80" value="${h(a.nome)}"></label><label class="cuAceite cp-linha"><input class="cp-check" type="checkbox" name="ativo"${a.ativo ? " checked" : ""}> ativa</label><button class="mini sm" type="submit">Salvar</button><span class="msg"></span></form>
        ${a.funcoes.map((f) => formFuncao(a, f)).join("")}${formFuncao(a, null)}</div>`).join("")}
      <form class="formcard glass" data-ml-form="area" novalidate style="margin-top:12px"><label>Nova equipe<input name="nome" maxlength="80"></label><div><button class="mini sm" type="submit">Incluir equipe</button></div><span class="msg"></span></form>
      <h3 class="cp-subsecao cp-espaco">Gestores delegados (montam escalas nas equipes indicadas)</h3>${c.gestores.map((g) => `<p class="cp-meta">${h(g.nome)} · ${g.areas.length ? g.areas.map((x) => h(c.areas.find((a) => a.id === x)?.nome || "")).join(", ") : "todas as equipes"} · ${g.ativo ? "ativo" : "inativo"}</p>`).join("") || '<p class="cp-meta">Nenhum.</p>'}
      <form class="formcard glass" data-ml-form="gestor" novalidate id="mlGestor"><div class="formgrid"><label>Integrante (com conta)<select name="perfil" id="mlGestorSel"><option value="">Carregando…</option></select></label><label>Situação<select name="ativo"><option value="1">Ativo</option><option value="0">Inativo</option></select></label></div>
        <div class="cp-opcoes"><span class="cp-meta">Equipes (nenhuma marcada = todas):</span>${c.areas.map((a) => `<label><input type="checkbox" name="area" value="${h(a.id)}"> ${h(a.nome)}</label>`).join("")}</div><div><button class="mini sm" type="submit">Salvar gestor</button></div><span class="msg"></span></form>`;
  }
  const formFuncao = (a, f) => `<form class="cp-subitem cp-pilha" data-ml-form="funcaoCat" data-id="${h(f?.id || "")}" novalidate><input type="hidden" name="area" value="${h(a.id)}"><div class="formgrid">
      <label>${f ? "Função" : "Nova função"}<input name="nome" maxlength="80" value="${h(f?.nome || "")}"></label><label>Quantidade de referência<input type="number" name="qtd" min="1" max="99" value="${h(f?.quantidade_referencia || "")}"></label>
      <label class="cp-full">Orientação padrão<input name="orient" maxlength="1000" value="${h(f?.orientacao_padrao || "")}"></label></div>
      <div class="cp-opcoes"><label><input type="checkbox" name="exige"${!f || f.exige_habilitacao ? " checked" : ""}> exige habilitação</label><label><input type="checkbox" name="treino"${!f || f.aceita_em_treinamento ? " checked" : ""}> aceita em treinamento (como auxiliar)</label>${f ? `<label><input type="checkbox" name="ativo"${f.ativo ? " checked" : ""}> ativa</label>` : ""}</div>
      <div><button class="mini sm" type="submit">${f ? "Salvar" : "Incluir função"}</button></div><span class="msg"></span></form>`;
  function telaRelatorios() {
    const f = L.relFiltro || { de: new Date(Date.now() - 90 * 864e5).toISOString().slice(0, 10), ate: hojeISO(), agrupar: "voluntario" };
    setTimeout(async () => { const alvo = el("mlRelOut"); if (!alvo) return;
      try { L.rel = await rpc("midia_relatorio", { p_de: f.de, p_ate: f.ate, p_agrupar: f.agrupar });
        alvo.innerHTML = `<table class="cp-tabela"><tr><th>${f.agrupar === "funcao" ? "Função" : f.agrupar === "evento" ? "Evento" : "Voluntário"}</th><th>Escalados</th><th>Confirmaram</th><th>Recusaram</th><th>Serviram</th><th>Não serviram</th></tr>${L.rel.map((q) => `<tr><td>${h(q.chave)}</td><td>${q.escalados}</td><td>${q.confirmaram}</td><td>${q.recusaram}</td><td>${q.serviram}</td><td>${q.faltaram}</td></tr>`).join("") || '<tr><td colspan="6">Nada no período.</td></tr>'}</table>`;
      } catch (e) { alvo.innerHTML = `<p class="notice">${h(e.message)}</p>`; } }, 0);
    return `<form class="toolbar" id="mlRel" novalidate style="flex-wrap:wrap"><label class="cp-linha">De<input type="date" name="de" value="${h(f.de)}"></label><label class="cp-linha">Até<input type="date" name="ate" value="${h(f.ate)}"></label>
      <select name="agrupar"><option value="voluntario">Por voluntário</option><option value="funcao"${f.agrupar === "funcao" ? " selected" : ""}>Por função</option><option value="evento"${f.agrupar === "evento" ? " selected" : ""}>Por evento</option></select><button class="mini sm" type="submit">Atualizar</button><button class="mini sm" type="button" data-ml="csv">Exportar CSV</button></form>
      <p class="msg" style="margin:8px 0 12px">Escalado, confirmou e serviu são contados separadamente: a confirmação não vale como presença.</p><div class="glass" style="padding:12px;overflow:auto" id="mlRelOut"><p class="msg">Carregando…</p></div>`;
  }
  // gestores: lista de integrantes com conta (via equipe)
  document.addEventListener("toggle", () => {}, true);
  const obsGestor = new MutationObserver(async () => { const s = el("mlGestorSel"); if (!s || s.dataset.ok) return; s.dataset.ok = "1";
    try { const v = await rpc("midia_voluntarios", {}); const perfis = (await L.sb.from("perfis").select("id,pessoa_id")).data || [];
      s.innerHTML = v.filter((p) => p.tem_conta).map((p) => `<option value="${h(perfis.find((x) => x.pessoa_id === p.pessoa_id)?.id || "")}">${h(p.nome)}</option>`).join(""); } catch (_) { s.innerHTML = '<option value="">—</option>'; } });
  obsGestor.observe(document.body, { childList: true, subtree: true });

  window.BetelMidia = { solicitar, voluntario, lider };
})();

/* A antiga página "Minha escala" (#voluntario) passa a ser a aba "Minhas escalas" da Área de Membros */
(() => {
  if (!window.BETEL_SUPABASE) return;
  const ir = () => { if (location.hash === "#voluntario") location.replace("#equipe/escalas"); };
  window.addEventListener("hashchange", ir); ir();
})();
