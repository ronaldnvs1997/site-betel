/* =====================================================================
   Área de Membros › Cursos (Secretaria e MASTER)
   Cadastro de cursos, categorias e turmas; inscrições, lista de espera,
   participantes e histórico. Toda regra é conferida no banco.
   ===================================================================== */
window.BetelCursosAdmin = (() => {
  let sb, box, dados = { categorias: [], cursos: [] }, ministerios = [], vista = { tela: "cursos" }, inscritos = [], busca = "";
  const h = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const data = (d) => d ? new Date(String(d).length === 10 ? d + "T12:00:00" : d).toLocaleDateString("pt-BR") : "";
  const dataHora = (d) => d ? new Date(d).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" }) : "";
  const reais = (v) => Number(v).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  const fone = (t) => { const d = String(t || ""); return d.length === 11 ? `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}` : d; };
  const local = (iso) => { if (!iso) return ""; const d = new Date(iso); const p = (n) => String(n).padStart(2, "0"); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`; };
  const ST_T = { rascunho: "Rascunho (não aparece no site)", inscricoes_abertas: "Inscrições abertas", inscricoes_encerradas: "Inscrições encerradas", em_andamento: "Em andamento", concluida: "Concluída", cancelada: "Cancelada" };
  const ST_I = { confirmada: "Confirmada", aguardando_pagamento: "Aguardando pagamento", lista_espera: "Lista de espera", cancelada: "Cancelada", concluida: "Concluída" };
  const MOD = { presencial: "Presencial", online: "Online", hibrido: "Presencial e online" };
  const curso = (id) => dados.cursos.find((c) => c.id === id);
  async function rpc(n, a) { const { data, error } = await sb.rpc(n, a || {}); if (error) throw new Error(error.message); return data; }
  async function carregar() { dados = await rpc("cursos_admin_listar"); }
  const erro = (e) => { box.innerHTML = `<p class="notice">${h(e.message)}</p>`; };
  const ir = async (v) => { vista = v; try { await desenhar(); } catch (e) { erro(e); } };

  async function render(container, ctx) {
    sb = ctx.sb; box = container;
    box.innerHTML = '<p class="msg">Carregando cursos…</p>';
    try {
      await carregar();
      const { data: m } = await sb.from("ministerios").select("id,nome").order("ordem"); ministerios = m || [];
      await desenhar();
    } catch (e) { erro(e); }
  }
  function menu() {
    const b = (t, n) => `<button class="mini sm" type="button" data-cu="tela:${t}"${vista.tela === t || (t === "cursos" && ["curso", "turmas", "turma", "inscricoes"].includes(vista.tela)) || (t === "participantes" && vista.tela === "participante") ? ' data-ativo=""' : ""}>${n}</button>`;
    return `<div class="toolbar">${b("cursos", "Cursos")}${b("categorias", "Categorias")}${b("participantes", "Participantes")}<a class="mini sm" href="#cursos" target="_blank" rel="noopener" style="display:inline-flex;align-items:center;text-decoration:none">Ver página pública ↗</a></div>`;
  }
  async function desenhar() {
    const v = vista.tela;
    if (v === "cursos") return telaCursos();
    if (v === "curso") return telaCurso(vista.id);
    if (v === "turmas") return telaTurmas(vista.id);
    if (v === "turma") return telaTurma(vista.cursoId, vista.id);
    if (v === "inscricoes") return telaInscricoes(vista.cursoId, vista.id);
    if (v === "categorias") return telaCategorias();
    if (v === "participantes") return telaParticipantes();
    if (v === "participante") return telaParticipante(vista.id);
  }

  /* ---------- Cursos ---------- */
  function telaCursos() {
    box.innerHTML = menu() + `<div class="toolbar"><button class="btn btn-p sm" type="button" data-cu="novoCurso">Novo curso</button>
      <span class="msg">Cursos começam como rascunho. Preencha os dados e marque "Publicado" para aparecer no site.</span></div>
      ${dados.categorias.map((cat) => `<div class="glass list" style="margin-bottom:18px"><div class="row"><div><p class="n">${h(cat.nome)}${cat.ativo ? "" : '<span class="st">Inativa</span>'}</p></div></div>
        ${dados.cursos.filter((c) => c.categoria_id === cat.id).map((c) => `<div class="row"><div><p class="n cp-item-titulo">${h(c.titulo)}<span class="st ${c.publicado ? "ok" : ""}">${c.publicado ? "Publicado" : "Rascunho"}</span>${c.exige_membro || c.cursos_exigidos.length ? '<span class="st" style="margin-left:6px">Com pré-requisitos</span>' : ""}</p>
          <p class="m">${h(MOD[c.modalidade])} · ${c.turmas.length} turma(s)${c.turmas.filter((t) => t.aberta).length ? " · inscrições abertas" : ""}${!c.descricao ? " · sem descrição" : ""}${!c.imagem_url ? " · sem imagem" : ""}</p></div>
          <div class="acts"><button class="mini sm" type="button" data-cu="curso:${h(c.id)}">Editar curso</button><button class="btn btn-p sm" type="button" data-cu="turmas:${h(c.id)}">Turmas e inscrições</button></div></div>`).join("") || '<p class="empty cp-vazio">Nenhum curso nesta categoria.</p>'}</div>`).join("")}`;
  }
  function telaCurso(id) {
    const c = id ? curso(id) : { titulo: "", categoria_id: dados.categorias[0]?.id, modalidade: "presencial", cursos_exigidos: [], publicado: false, ordem: dados.cursos.length + 1 };
    const sel = (v, x) => (v === x ? " selected" : "");
    box.innerHTML = menu() + `<form class="formcard glass" id="cuFormCurso" data-id="${h(id || "")}" novalidate><p><button class="linkbtn" type="button" data-cu="tela:cursos">← Cursos</button></p>
      <h3>${id ? "Editar curso" : "Novo curso"}</h3>
      <div class="formgrid">
        <label class="cp-full">Nome do curso<input name="titulo" required maxlength="140" value="${h(c.titulo)}"></label>
        <label>Categoria<select name="categoria_id">${dados.categorias.map((x) => `<option value="${h(x.id)}"${sel(x.id, c.categoria_id)}>${h(x.nome)}</option>`).join("")}</select></label>
        <label>Modalidade<select name="modalidade">${Object.entries(MOD).map(([k, n]) => `<option value="${k}"${sel(k, c.modalidade)}>${n}</option>`).join("")}</select></label>
        <label class="cp-full">Resumo (aparece no card, até 300 caracteres)<input name="resumo" maxlength="300" value="${h(c.resumo || "")}"></label>
        <label class="cp-full">Descrição completa<textarea name="descricao" maxlength="6000" rows="6">${h(c.descricao || "")}</textarea></label>
        <label>Para quem é<input name="publico_alvo" maxlength="600" value="${h(c.publico_alvo || "")}"></label>
        <label>Carga horária<input name="carga_horaria" maxlength="60" value="${h(c.carga_horaria || "")}" placeholder="Ex.: 20 horas"></label>
        <label>Ministério responsável (opcional)<select name="ministerio_id"><option value="">—</option>${ministerios.map((m) => `<option value="${h(m.id)}"${sel(m.id, c.ministerio_id)}>${h(m.nome)}</option>`).join("")}</select></label>
        <label>Ordem na lista<input name="ordem" type="number" min="0" max="999" value="${h(c.ordem ?? 0)}"></label>
        <label>Endereço da página (deixe vazio para gerar)<input name="slug" maxlength="80" value="${h(c.slug || "")}"></label>
        <label>Plataforma online (para cursos online futuros)<input name="plataforma_url" maxlength="300" placeholder="https://" value="${h(c.plataforma_url || "")}"></label>
      </div>
      <div><p style="font-weight:600;font-size:14px;margin-bottom:8px">Imagem do curso</p>
        <div style="display:flex;gap:16px;flex-wrap:wrap;align-items:center"><img id="cuPrevia" alt="" style="width:220px;aspect-ratio:16/9;object-fit:cover;border-radius:14px;background:#2a0f0f${c.imagem_url ? "" : ";display:none"}" src="${h(c.imagem_url || "")}">
        <div style="display:flex;flex-direction:column;gap:10px;flex:1;min-width:240px"><label>Enviar imagem (JPG, PNG ou WebP, até 2 MB)<input type="file" id="cuArquivo" accept="image/jpeg,image/png,image/webp"></label>
        <label>ou endereço da imagem<input name="imagem_url" maxlength="500" value="${h(c.imagem_url || "")}" placeholder="https://… ou img/…"></label></div></div></div>
      <div><p style="font-weight:600;font-size:14px;margin-bottom:8px">Pré-requisitos</p><div class="deps">
        <label><input type="checkbox" name="exige_membro"${c.exige_membro ? " checked" : ""}> Exige membresia validada pela Secretaria</label>
        ${dados.cursos.filter((x) => x.id !== id).map((x) => `<label><input type="checkbox" name="exigido" value="${h(x.id)}"${(c.cursos_exigidos || []).includes(x.id) ? " checked" : ""}> Concluiu ${h(x.titulo)}</label>`).join("")}</div></div>
      <label class="cuAceite cp-linha"><input class="cp-check" type="checkbox" name="publicado"${c.publicado ? " checked" : ""}> Publicado (aparece na página pública de cursos)</label>
      <div class="cp-acoes"><button class="btn btn-p" type="submit">Salvar curso</button>${id ? `<button class="btn btn-s" type="button" data-cu="turmas:${h(id)}">Turmas e inscrições</button>` : ""}</div>
      <span class="msg" role="status"></span></form>`;
  }

  /* ---------- Turmas ---------- */
  function telaTurmas(cursoId) {
    const c = curso(cursoId);
    box.innerHTML = menu() + `<p><button class="linkbtn" type="button" data-cu="tela:cursos">← Cursos</button></p><h3 style="margin:12px 0 18px;font-size:26px">${h(c.titulo)}</h3>
      <div class="toolbar"><button class="btn btn-p sm" type="button" data-cu="turma:${h(cursoId)}:">Nova turma</button>${c.publicado ? "" : '<span class="msg">Este curso ainda é rascunho: as turmas só aparecem no site depois de publicar o curso.</span>'}</div>
      <div class="glass list">${c.turmas.length ? c.turmas.map((t) => `<div class="row"><div><p class="n cp-item-titulo">${h(t.nome)}<span class="st ${t.aberta ? "novo" : ""}">${h(ST_T[t.status])}</span>${t.status === "inscricoes_abertas" && !t.aberta ? '<span class="st" style="margin-left:6px">Fora do período</span>' : ""}</p>
        <p class="m">${t.data_inicio ? data(t.data_inicio) + (t.data_fim ? " a " + data(t.data_fim) : "") : "Período não informado"} · ${t.vagas == null ? "vagas sem limite" : `${t.vagas - (t.vagas_restantes ?? 0)} de ${t.vagas} vagas ocupadas`}${t.na_espera ? ` · ${t.na_espera} na espera` : ""} · ${t.valor > 0 ? reais(t.valor) : t.valor === 0 ? "gratuito" : "valor não informado"}</p></div>
        <div class="acts"><button class="mini sm" type="button" data-cu="turma:${h(cursoId)}:${h(t.id)}">Editar turma</button><button class="btn btn-p sm" type="button" data-cu="inscricoes:${h(cursoId)}:${h(t.id)}">Inscrições</button></div></div>`).join("")
        : '<p class="empty cp-vazio">Nenhuma turma cadastrada.</p>'}</div>`;
  }
  async function carregarResponsaveis(id) {
    const box2 = el("cuResp"); if (!box2) return;
    try {
      const todos = await rpc("cursos_validadores_disponiveis"), atuais = id ? (await rpc("cursos_responsaveis_turma", { p_turma: id })).map((r) => r.perfil_id) : [];
      box2.innerHTML = `<p class="msg">A liderança do ministério do curso também pode validar. A Secretaria autoriza a emissão depois.</p><div class="tmOpcoes">${todos.map((p) => `<label><input type="checkbox" name="responsavel" value="${h(p.id)}"${atuais.includes(p.id) ? " checked" : ""}> ${h(p.nome)}</label>`).join("") || "Nenhum líder com conta ativa."}</div>`;
    } catch (e) { box2.innerHTML = `<p class="msg">${h(e.message)}</p>`; }
  }
  function telaTurma(cursoId, id) {
    setTimeout(() => carregarResponsaveis(id), 0);
    const c = curso(cursoId); const t = id ? c.turmas.find((x) => x.id === id) : { nome: `Turma ${c.turmas.length + 1}`, status: "rascunho", lista_espera: true };
    const v = (k) => h(t[k] ?? "");
    box.innerHTML = menu() + `<form class="formcard glass" id="cuFormTurma" data-curso="${h(cursoId)}" data-id="${h(id || "")}" novalidate>
      <p><button class="linkbtn" type="button" data-cu="turmas:${h(cursoId)}">← ${h(c.titulo)}</button></p><h3>${id ? "Editar turma" : "Nova turma"}</h3>
      <p class="notice">Preencha só o que já estiver definido. Campos vazios não aparecem no site.</p>
      <div class="formgrid">
        <label>Nome da turma<input name="nome" required maxlength="120" value="${v("nome")}"></label>
        <label>Situação<select name="status">${Object.entries(ST_T).map(([k, n]) => `<option value="${k}"${k === t.status ? " selected" : ""}>${n}</option>`).join("")}</select></label>
        <label>Data de início<input type="date" name="data_inicio" value="${v("data_inicio")}"></label>
        <label>Data de término<input type="date" name="data_fim" value="${v("data_fim")}"></label>
        <label>Dias e horário<input name="dias_horario" maxlength="200" value="${v("dias_horario")}" placeholder="Ex.: sábados, 9h às 11h"></label>
        <label>Local<input name="local" maxlength="200" value="${v("local")}"></label>
        <label class="cp-full">Professores<input name="professores" maxlength="300" value="${v("professores")}"></label>
        <label>Vagas (vazio = sem limite)<input type="number" name="vagas" min="1" max="5000" value="${v("vagas")}"></label>
        <label>Valor em R$ (vazio = não informado; 0 = gratuito)<input type="number" name="valor" min="0" step="0.01" value="${v("valor")}"></label>
        <label>Inscrições abrem em (opcional)<input type="datetime-local" name="inscricao_abre_em" value="${h(local(t.inscricao_abre_em))}"></label>
        <label>Inscrições fecham em (opcional)<input type="datetime-local" name="inscricao_fecha_em" value="${h(local(t.inscricao_fecha_em))}"></label>
        <label>Link da aula online (futuro)<input name="link_online" maxlength="300" placeholder="https://" value="${v("link_online")}"></label>
        <label>Reserva na Agenda (código do lote, opcional)<input name="lote_reserva" maxlength="60" value="${v("lote_reserva")}" placeholder="LOTE-…"></label>
        <label class="cp-full">Observações internas<textarea name="observacoes" maxlength="1000" rows="3">${v("observacoes")}</textarea></label>
        <fieldset class="tmPart cp-full" id="cuResp"><legend>Quem valida a conclusão (líderes ou professores com conta)</legend><p class="msg">Carregando…</p></fieldset>
      </div>
      <div class="deps"><label><input type="checkbox" name="lista_espera"${t.lista_espera ? " checked" : ""}> Abrir lista de espera quando as vagas acabarem</label></div>
      <div><button class="btn btn-p" type="submit">Salvar turma</button></div><span class="msg" role="status"></span></form>`;
  }

  /* ---------- Inscrições ---------- */
  async function telaInscricoes(cursoId, turmaId) {
    const c = curso(cursoId), t = c.turmas.find((x) => x.id === turmaId);
    inscritos = await rpc("cursos_listar_inscricoes", { p_turma: turmaId });
    const n = (s) => inscritos.filter((i) => i.status === s).length;
    box.innerHTML = menu() + `<p><button class="linkbtn" type="button" data-cu="turmas:${h(cursoId)}">← ${h(c.titulo)}</button></p>
      <h3 style="margin:12px 0 6px;font-size:26px">${h(t.nome)} · inscrições</h3>
      <p class="msg" style="margin-bottom:16px">${t.vagas == null ? "Vagas sem limite" : `${t.vagas} vagas`} · ${n("confirmada")} confirmada(s) · ${n("aguardando_pagamento")} aguardando pagamento · ${n("lista_espera")} na espera · ${n("concluida")} concluída(s) · ${n("cancelada")} cancelada(s)</p>
      <div class="toolbar"><button class="btn btn-p sm" type="button" data-cu="novaInscricao">Inscrever pela Secretaria</button><button class="mini sm" type="button" data-cu="csv:${h(turmaId)}">Baixar lista (CSV)</button></div>
      <div id="cuNovaInsc"></div>
      <div class="glass list">${inscritos.length ? inscritos.map((i) => `<div class="sbItem" id="ins-${h(i.id)}"><div class="row"><div>
        <p class="n cp-item-titulo">${h(i.nome)}<span class="st ${i.status === "confirmada" || i.status === "concluida" ? "ok" : i.status === "cancelada" ? "" : "novo"}">${h(ST_I[i.status])}</span></p>
        <p class="m">${h(i.protocolo)} · ${h(fone(i.telefone))} · ${h(i.email || "")} · ${h(dataHora(i.criado_em))} · ${i.origem === "site" ? "pelo site" : "pela Secretaria"}${i.promovida_em ? " · saiu da espera em " + h(dataHora(i.promovida_em)) : ""}${i.motivo_cancelamento ? " · motivo: " + h(i.motivo_cancelamento) : ""}${i.observacao ? " · obs.: " + h(i.observacao) : ""}</p></div>
        <div class="acts">${i.status === "lista_espera" ? `<button class="mini sm" type="button" data-cu="acao:promover:${h(i.id)}">Promover</button>` : ""}${i.status === "confirmada" ? `<button class="mini sm" type="button" data-cu="acao:concluir:${h(i.id)}">Marcar concluído</button>` : ""}${i.status === "concluida" ? `<button class="mini sm" type="button" data-cu="acao:reabrir_conclusao:${h(i.id)}">Desfazer conclusão</button>` : ""}${["confirmada", "aguardando_pagamento", "lista_espera"].includes(i.status) ? `<button class="mini sm" type="button" data-cu="cancelarForm:${h(i.id)}">Cancelar</button>` : ""}<button class="mini sm" type="button" data-cu="participante:${h(i.pessoa_id)}">Histórico</button></div>
      </div><div class="sbExtra"></div></div>`).join("") : '<p class="empty cp-vazio">Nenhuma inscrição ainda.</p>'}</div>`;
  }
  function formNovaInscricao() {
    el("cuNovaInsc").innerHTML = `<form class="formcard glass" id="cuFormInsc" novalidate style="margin-bottom:18px"><h3 class="cp-secao">Inscrição pela Secretaria</h3>
      <div class="formgrid"><label class="cp-full">Nome completo<input name="nome" required maxlength="120"></label><label>Telefone<input name="telefone" required maxlength="20"></label>
      <label>E-mail<input name="email" type="email" required maxlength="120"></label><label>Data de nascimento<input name="nascimento" type="date" required></label><label>Observação<input name="observacao" maxlength="600"></label></div>
      <label class="cuAceite cp-linha"><input class="cp-check" type="checkbox" name="aceite"> A pessoa autorizou o uso dos dados para esta inscrição</label>
      <label class="cuAceite cp-linha"><input class="cp-check" type="checkbox" name="presencial"> O termo de participação em vigor foi lido e assinado pela pessoa (ou pelo responsável, se menor de 18 anos)</label>
      ${window.BetelTermos ? window.BetelTermos.blocoResponsavel("") : ""}
      <div class="tmImgSec"></div>
      <div><button class="btn btn-p sm" type="submit">Inscrever</button></div><span class="msg" role="status"></span></form>`;
  }
  async function prepararTermosInsc() {
    const f = el("cuFormInsc"); if (!f || !window.BetelTermos) return;
    try { const t = await window.BetelTermos.termos(); f.dataset.termo = t.participacao_curso?.id || ""; f.dataset.imagemTermo = t.imagem_voz?.id || "";
      if (t.imagem_voz) f.querySelector(".tmImgSec").innerHTML = `<fieldset class="tmImg"><legend>Imagem e voz (opcional, conforme a pessoa decidiu no papel)</legend><div class="tmOpcoes"><label><input type="radio" name="img" value="" checked> Não informado</label><label><input type="radio" name="img" value="aceito"> Autorizou</label><label><input type="radio" name="img" value="recusado"> Não autorizou</label></div><div class="tmOpcoes" data-tm-escopo hidden><label><input type="checkbox" name="img_fotos" checked> fotos</label><label><input type="checkbox" name="img_videos" checked> vídeos</label><label><input type="checkbox" name="img_voz" checked> voz</label></div></fieldset>`;
    } catch (_) {}
  }
  const el = (id) => document.getElementById(id);

  /* ---------- Categorias ---------- */
  function telaCategorias() {
    box.innerHTML = menu() + `<div class="two"><form class="formcard glass" id="cuFormCat" novalidate><h3 id="cuCatTitulo">Nova categoria</h3><input type="hidden" name="id">
      <label>Nome<input name="nome" required maxlength="80"></label><label>Descrição (opcional)<textarea name="descricao" maxlength="600" rows="3"></textarea></label>
      <div class="formgrid"><label>Ordem<input type="number" name="ordem" min="0" max="999" value="${dados.categorias.length + 1}"></label><label>Situação<select name="ativo"><option value="1">Ativa</option><option value="0">Inativa</option></select></label></div>
      <div><button class="btn btn-p" type="submit">Salvar categoria</button></div><span class="msg" role="status"></span></form>
      <div class="glass list">${dados.categorias.map((c) => `<div class="row"><div><p class="n">${h(c.nome)}<span class="st ${c.ativo ? "ok" : ""}">${c.ativo ? "Ativa" : "Inativa"}</span></p><p class="m">Ordem ${h(c.ordem)} · ${dados.cursos.filter((x) => x.categoria_id === c.id).length} curso(s)${c.descricao ? " · " + h(c.descricao) : ""}</p></div>
        <div class="acts"><button class="mini sm" type="button" data-cu="editarCat:${h(c.id)}">Editar</button></div></div>`).join("")}</div></div>`;
  }

  /* ---------- Participantes ---------- */
  async function telaParticipantes() {
    const lista = await rpc("cursos_participantes", { p_busca: busca || null });
    box.innerHTML = menu() + `<div class="toolbar"><input id="cuBusca" placeholder="Buscar por nome, e-mail ou telefone" value="${h(busca)}"><button class="mini sm" type="button" data-cu="buscar">Buscar</button><span class="msg">${lista.length} participante(s)</span></div>
      <div class="glass list">${lista.length ? lista.map((p) => `<div class="row"><div><p class="n cp-item-titulo">${h(p.nome)}</p><p class="m">${h(p.email || "")} · ${h(fone(p.telefone))} · ${p.inscricoes} inscrição(ões) · ${p.ativas} ativa(s) · ${p.concluidas} concluída(s)</p></div>
        <div class="acts"><button class="mini sm" type="button" data-cu="participante:${h(p.id)}">Cadastro e histórico</button></div></div>`).join("") : '<p class="empty cp-vazio">Nenhum participante encontrado.</p>'}</div>`;
  }
  async function telaParticipante(id) {
    const r = await rpc("cursos_historico_participante", { p_pessoa: id }); const p = r.pessoa;
    box.innerHTML = menu() + `<p><button class="linkbtn" type="button" data-cu="tela:participantes">← Participantes</button></p>
      <div class="two" style="margin-top:14px"><form class="formcard glass" id="cuFormPessoa" data-id="${h(id)}" novalidate><p class="eyebrow">Cadastro</p>
        <label>Nome completo<input name="nome" required maxlength="120" value="${h(p.nome)}"></label><label>Telefone<input name="telefone" maxlength="20" value="${h(p.telefone || "")}"></label>
        <label>E-mail<input name="email" type="email" maxlength="120" value="${h(p.email || "")}"></label><label>Data de nascimento<input name="nascimento" type="date" value="${h(p.data_nascimento || "")}"></label>
        <p class="m" style="font:400 12.5px/1.6 var(--mono);color:var(--suave)">Cadastro criado em ${h(dataHora(p.criado_em))} · origem: ${h(p.origem)} · membresia: ${h(p.situacao_membresia)}</p>
        <div><button class="btn btn-p sm" type="submit">Salvar cadastro</button></div><span class="msg" role="status"></span></form>
      <div class="glass list"><div class="row"><div><p class="n">Histórico de inscrições</p></div></div>${r.inscricoes.length ? r.inscricoes.map((i) => `<div class="row cp-topo"><div>
        <p class="n cp-item-titulo">${h(i.curso)} · ${h(i.turma)}<span class="st ${i.status === "confirmada" || i.status === "concluida" ? "ok" : ""}">${h(ST_I[i.status])}</span></p>
        <p class="m">${h(i.protocolo)} · ${i.origem === "site" ? "pelo site" : "pela Secretaria"}</p>
        ${i.eventos.map((e) => `<p class="m">${h(dataHora(e.quando))} — ${e.acao === "insert" ? "inscrição feita (" + h(ST_I[e.para] || e.para) + ")" : h(ST_I[e.de] || e.de) + " → " + h(ST_I[e.para] || e.para)} · ${h(e.por)}</p>`).join("")}
        ${i.motivo_cancelamento ? `<p class="m">Motivo do cancelamento: ${h(i.motivo_cancelamento)}</p>` : ""}</div></div>`).join("") : '<p class="empty cp-vazio">Sem inscrições.</p>'}</div></div>`;
  }

  /* ---------- eventos ---------- */
  document.addEventListener("click", async (ev) => {
    const b = ev.target.closest("[data-cu]"); if (!b || !box || !box.contains(b)) return;
    const [a, x, y, z] = b.dataset.cu.split(":");
    try {
      if (a === "tela") return ir({ tela: x });
      if (a === "novoCurso") return ir({ tela: "curso", id: null });
      if (a === "curso") return ir({ tela: "curso", id: x });
      if (a === "turmas") return ir({ tela: "turmas", id: x });
      if (a === "turma") return ir({ tela: "turma", cursoId: x, id: y || null });
      if (a === "inscricoes") return ir({ tela: "inscricoes", cursoId: x, id: y });
      if (a === "participante") return ir({ tela: "participante", id: x });
      if (a === "novaInscricao") { formNovaInscricao(); return prepararTermosInsc(); }
      if (a === "buscar") { busca = el("cuBusca").value.trim(); return ir({ tela: "participantes" }); }
      if (a === "editarCat") { const c = dados.categorias.find((k) => k.id === x); const f = el("cuFormCat"); f.elements.id.value = c.id; f.elements.nome.value = c.nome; f.elements.descricao.value = c.descricao || ""; f.elements.ordem.value = c.ordem; f.elements.ativo.value = c.ativo ? "1" : "0"; el("cuCatTitulo").textContent = "Editar categoria"; return; }
      if (a === "cancelarForm") { el("ins-" + x).querySelector(".sbExtra").innerHTML = `<form class="formcard sbSub" data-cancelar="${h(x)}" novalidate><label>Motivo do cancelamento<input maxlength="300" required></label><div><button class="btn btn-p sm" type="submit">Confirmar cancelamento</button></div><span class="msg" role="status"></span></form>`; return; }
      if (a === "acao") {
        b.disabled = true; await rpc("cursos_alterar_inscricao", { p_inscricao: y, p_acao: x, p_motivo: null });
        await carregar(); return ir(vista);
      }
      if (a === "csv") {
        const linhas = [["Protocolo", "Nome", "E-mail", "Telefone", "Nascimento", "Situação", "Origem", "Inscrição em", "Observação"]]
          .concat(inscritos.map((i) => [i.protocolo, i.nome, i.email, i.telefone, i.data_nascimento || "", ST_I[i.status], i.origem, dataHora(i.criado_em), i.observacao || ""]));
        const csv = "﻿" + linhas.map((l) => l.map((c) => `"${String(c ?? "").replace(/"/g, '""')}"`).join(";")).join("\r\n");
        const link = document.createElement("a"); link.href = URL.createObjectURL(new Blob([csv], { type: "text/csv" })); link.download = "inscricoes.csv"; link.click(); return;
      }
    } catch (e) { b.disabled = false; BetelUI.aviso(e.message); }
  });
  document.addEventListener("change", async (ev) => {
    if (ev.target.id !== "cuArquivo") return;
    const f = ev.target.files[0], form = el("cuFormCurso"), msg = form.querySelector(".msg"); if (!f) return;
    if (!["image/jpeg", "image/png", "image/webp"].includes(f.type)) { msg.textContent = "Use uma imagem JPG, PNG ou WebP."; ev.target.value = ""; return; }
    if (f.size > 2 * 1024 * 1024) { msg.textContent = "A imagem passa de 2 MB. Reduza o tamanho e tente de novo."; ev.target.value = ""; return; }
    msg.textContent = "Enviando imagem…";
    const caminho = `${form.dataset.id || "novos"}/${Date.now()}.${{ "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" }[f.type]}`;
    const { error } = await sb.storage.from("cursos").upload(caminho, await f.arrayBuffer(), { contentType: f.type, upsert: false });
    if (error) { msg.textContent = "Não foi possível enviar a imagem: " + error.message; return; }
    const url = sb.storage.from("cursos").getPublicUrl(caminho).data.publicUrl;
    form.elements.imagem_url.value = url; el("cuPrevia").src = url; el("cuPrevia").style.display = "";
    msg.textContent = "Imagem enviada. Clique em Salvar curso para gravar.";
  });
  document.addEventListener("submit", async (ev) => {
    const f = ev.target; if (!box || !box.contains(f)) return;
    const ids = ["cuFormCurso", "cuFormTurma", "cuFormCat", "cuFormInsc", "cuFormPessoa"];
    if (!ids.includes(f.id) && !f.dataset.cancelar) return;
    ev.preventDefault();
    const msg = f.querySelector(".msg"), b = f.querySelector('[type="submit"]'), v = (n) => (f.elements[n]?.value ?? "").trim();
    b.disabled = true; msg.textContent = "Salvando…";
    try {
      if (f.id === "cuFormCurso") {
        const r = await rpc("cursos_salvar_curso", { p: { id: f.dataset.id || null, titulo: v("titulo"), categoria_id: v("categoria_id"), modalidade: v("modalidade"), resumo: v("resumo"),
          descricao: v("descricao"), publico_alvo: v("publico_alvo"), carga_horaria: v("carga_horaria"), ministerio_id: v("ministerio_id"), ordem: v("ordem") || "0",
          slug: v("slug"), plataforma_url: v("plataforma_url"), imagem_url: v("imagem_url"), exige_membro: f.elements.exige_membro.checked,
          cursos_exigidos: [...f.querySelectorAll('input[name="exigido"]:checked')].map((i) => i.value), publicado: f.elements.publicado.checked } });
        await carregar(); await ir({ tela: "curso", id: r.id }); el("cuFormCurso").querySelector(".msg").textContent = "Curso salvo.";
      } else if (f.id === "cuFormTurma") {
        const iso = (n) => (v(n) ? new Date(v(n)).toISOString() : "");
        const r = await rpc("cursos_salvar_turma", { p: { id: f.dataset.id || null, curso_id: f.dataset.curso, nome: v("nome"), status: v("status"), data_inicio: v("data_inicio"),
          data_fim: v("data_fim"), dias_horario: v("dias_horario"), local: v("local"), professores: v("professores"), vagas: v("vagas"), valor: v("valor"),
          inscricao_abre_em: iso("inscricao_abre_em"), inscricao_fecha_em: iso("inscricao_fecha_em"), link_online: v("link_online"), lote_reserva: v("lote_reserva"),
          observacoes: v("observacoes"), lista_espera: f.elements.lista_espera.checked } });
        if (el("cuResp")?.querySelector('input[name="responsavel"]')) await rpc("cursos_definir_responsaveis", { p_turma: r.id || f.dataset.id, p_perfis: [...f.querySelectorAll('input[name="responsavel"]:checked')].map((x) => x.value) });
        await carregar(); await ir({ tela: "turmas", id: f.dataset.curso });
        if (r.promovidos) box.insertAdjacentHTML("afterbegin", `<p class="notice" style="margin-bottom:14px">${r.promovidos} pessoa(s) saíram da lista de espera e foram inscritas nas novas vagas.</p>`);
      } else if (f.id === "cuFormCat") {
        await rpc("cursos_salvar_categoria", { p_id: v("id") || null, p_nome: v("nome"), p_descricao: v("descricao"), p_ordem: parseInt(v("ordem") || "0"), p_ativo: v("ativo") === "1" });
        await carregar(); await ir({ tela: "categorias" });
      } else if (f.id === "cuFormInsc") {
        if (!f.elements.aceite.checked) throw new Error("Confirme que a pessoa autorizou o uso dos dados.");
        if (!v("nascimento")) throw new Error("Informe a data de nascimento.");
        const menor = window.BetelTermos.idade(v("nascimento")) < 18;
        const r = await rpc("inscrever_curso_com_termos", { p_turma: vista.id, p_nome: v("nome"), p_telefone: v("telefone"), p_email: v("email"), p_data_nascimento: v("nascimento"),
          p_observacao: v("observacao") || null, p_aceite_privacidade: true, p_termo_participacao: f.dataset.termo || null,
          p_imagem: window.BetelTermos.imagem(f, f.dataset.imagemTermo), p_responsavel: menor ? window.BetelTermos.responsavel(f) : null,
          p_origem: "secretaria", p_termo_presencial: f.elements.presencial.checked });
        if (r.duplicada) throw new Error(r.mensagem);
        await carregar(); await ir(vista);
        box.insertAdjacentHTML("afterbegin", `<p class="notice" style="margin-bottom:14px">Inscrição ${h(r.protocolo)} registrada como "${h(ST_I[r.status])}". Link pessoal para a pessoa acompanhar: ${h(location.origin + location.pathname)}#inscricao-curso/${h(r.protocolo)}/${h(r.chave)}</p>`);
      } else if (f.id === "cuFormPessoa") {
        await rpc("cursos_atualizar_participante", { p_pessoa: f.dataset.id, p_nome: v("nome"), p_telefone: v("telefone"), p_email: v("email"), p_data_nascimento: v("nascimento") || null });
        msg.textContent = "Cadastro salvo.";
      } else if (f.dataset.cancelar) {
        await rpc("cursos_alterar_inscricao", { p_inscricao: f.dataset.cancelar, p_acao: "cancelar", p_motivo: f.querySelector("input").value });
        await carregar(); await ir(vista);
      }
    } catch (e) { msg.textContent = e.message; } finally { if (document.body.contains(b)) b.disabled = false; }
  });
  return { render };
})();
