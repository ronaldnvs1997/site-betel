/* =====================================================================
   Termos, autorizações e voluntariado no site público
   - bloco de termos no formulário de inscrição (participação obrigatória;
     imagem e voz OPCIONAL; responsável legal para menores de 18 anos)
   - "Termos e autorizações" e candidatura ao voluntariado no link pessoal
   - formulário "Quero me tornar membro" (só manifesta interesse)
   As regras são conferidas no banco.
   ===================================================================== */
window.BetelTermos = (() => {
  const sb = window.betelSB;
  const h = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const escopoTxt = (e) => [["fotos", "fotos"], ["videos", "vídeos"], ["voz", "voz"]].filter(([k]) => (e || {})[k]).map(([, n]) => n).join(", ");
  const el = (id) => document.getElementById(id);
  const dataHora = (d) => d ? new Date(d).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" }) : "";
  const PAR = { mae: "Mãe", pai: "Pai", tutor: "Tutor(a)", guardiao: "Guardião(ã)", outro_responsavel_legal: "Outro responsável legal" };
  const TIPO = { participacao_curso: "Participação nos cursos", imagem_voz: "Imagem e voz", voluntariado: "Adesão ao voluntariado" };
  let vigentes = null;
  async function termos() { if (!vigentes) { const { data, error } = await sb.rpc("termos_vigentes"); if (error) throw new Error(error.message); vigentes = data || {}; } return vigentes; }
  const idade = (nasc) => { if (!nasc) return null; const n = new Date(nasc + "T12:00:00"), d = new Date(); let a = d.getFullYear() - n.getFullYear(); if (d.getMonth() < n.getMonth() || (d.getMonth() === n.getMonth() && d.getDate() < n.getDate())) a--; return a; };
  const textoTermo = (t) => `<details class="tmTexto"><summary>Ler o termo completo (versão ${h(t.versao)})</summary><div>${h(t.texto)}</div></details>`;

  function blocoResponsavel(prefixo) {
    return `<fieldset class="tmResp" data-tm-resp hidden><legend>Responsável legal (participante menor de 18 anos)</legend>
      <div class="formgrid"><label class="cp-full">Nome completo do responsável<input name="${prefixo}resp_nome" maxlength="120"></label>
      <label>Vínculo<select name="${prefixo}resp_parentesco"><option value="">Selecione</option>${Object.entries(PAR).map(([k, n]) => `<option value="${k}">${n}</option>`).join("")}</select></label>
      <label>Telefone do responsável<input name="${prefixo}resp_telefone" inputmode="tel" maxlength="20"></label>
      <label class="cp-full">E-mail do responsável (opcional)<input name="${prefixo}resp_email" type="email" maxlength="120"></label></div>
      <label class="cuAceite"><input type="checkbox" name="${prefixo}resp_declara"> <span>Declaro que sou o responsável legal pelo participante e dou as autorizações marcadas neste formulário em nome dele.</span></label></fieldset>`;
  }
  const blocoImagem = (t, prefixo) => `<fieldset class="tmImg"><legend>${h(t.titulo)} <small>(opcional)</small></legend>
      <p class="tmNota">${h(t.resumo || "")} Você pode decidir depois, pelo link da inscrição, e pode revogar quando quiser.</p>
      <div class="tmOpcoes"><label><input type="radio" name="${prefixo}img" value="" checked> Decidir depois</label><label><input type="radio" name="${prefixo}img" value="aceito"> Autorizo</label><label><input type="radio" name="${prefixo}img" value="recusado"> Não autorizo</label></div>
      <div class="tmOpcoes" data-tm-escopo hidden><span>Autorizo o uso de:</span><label><input type="checkbox" name="${prefixo}img_fotos" checked> fotos</label><label><input type="checkbox" name="${prefixo}img_videos" checked> vídeos</label><label><input type="checkbox" name="${prefixo}img_voz" checked> voz</label></div>
      ${textoTermo(t)}</fieldset>`;

  /* ---------- formulário de inscrição ---------- */
  async function preencher(raiz) {
    const blocos = raiz.querySelectorAll(".tmBloco"); if (!blocos.length) return;
    let t; try { t = await termos(); } catch (e) { blocos.forEach((b) => (b.innerHTML = `<p class="notice">${h(e.message)}</p>`)); return; }
    blocos.forEach((b) => {
      if (!t.participacao_curso) { b.innerHTML = '<p class="notice">As inscrições estão temporariamente fechadas: o termo de participação ainda não foi publicado pela Secretaria.</p>'; b.closest("form")?.querySelector('[type="submit"]')?.setAttribute("disabled", ""); return; }
      b.innerHTML = `${blocoResponsavel("")}
        <fieldset class="tmPart"><legend>${h(t.participacao_curso.titulo)}</legend>${textoTermo(t.participacao_curso)}
        <label class="cuAceite"><input type="checkbox" name="termo_participacao" value="${h(t.participacao_curso.id)}"> <span>Li e aceito o termo de participação (versão ${h(t.participacao_curso.versao)}).</span></label></fieldset>
        ${t.imagem_voz ? blocoImagem(t.imagem_voz, "") : ""}`;
      b.dataset.imagemTermo = t.imagem_voz?.id || "";
    });
  }
  // mostra os campos do responsável e o escopo da imagem conforme as escolhas
  document.addEventListener("input", (ev) => atualizar(ev.target));
  document.addEventListener("change", (ev) => atualizar(ev.target));
  function atualizar(t) {
    const f = t.closest && t.closest("form"); if (!f) return;
    const r = f.querySelector("[data-tm-resp]");
    if (r && f.elements.nascimento) { const a = idade(f.elements.nascimento.value); r.hidden = !(a !== null && a < 18); }
    const esc = f.querySelector("[data-tm-escopo]"), img = f.querySelector('input[name$="img"]:checked');
    if (esc && img) esc.hidden = img.value !== "aceito";
  }
  function responsavel(f, prefixo = "") {
    const g = (n) => (f.elements[prefixo + n]?.value ?? "").trim();
    return { nome: g("resp_nome"), parentesco: g("resp_parentesco"), telefone: g("resp_telefone"), email: g("resp_email") || null, declara_responsavel: !!f.elements[prefixo + "resp_declara"]?.checked };
  }
  function imagem(f, termoId, prefixo = "") {
    const dec = f.querySelector(`input[name="${prefixo}img"]:checked`)?.value; if (!dec || !termoId) return null;
    return { termo_id: termoId, decisao: dec, escopo: dec === "aceito" ? { fotos: f.elements[prefixo + "img_fotos"].checked, videos: f.elements[prefixo + "img_videos"].checked, voz: f.elements[prefixo + "img_voz"].checked } : {} };
  }
  // devolve os parâmetros da inscrição ou uma mensagem de erro
  function coletar(f) {
    const b = f.querySelector(".tmBloco"), nasc = f.elements.nascimento.value;
    if (!nasc) return { erro: "Informe a data de nascimento." };
    const tp = f.elements.termo_participacao; if (!tp) return { erro: "O termo de participação não carregou. Recarregue a página." };
    if (!tp.checked) return { erro: "Para se inscrever é preciso ler e aceitar o termo de participação." };
    const menor = idade(nasc) < 18, resp = menor ? responsavel(f) : null;
    if (menor) {
      if (resp.nome.split(/\s+/).length < 2) return { erro: "Informe o nome completo do responsável legal." };
      if (!resp.parentesco) return { erro: "Informe o vínculo do responsável legal." };
      if (!/^\d{10,13}$/.test(resp.telefone.replace(/\D/g, ""))) return { erro: "Informe o telefone do responsável com DDD." };
      if (!resp.declara_responsavel) return { erro: "O responsável precisa confirmar a declaração." };
    }
    const img = imagem(f, b.dataset.imagemTermo);
    if (img?.decisao === "aceito" && !img.escopo.fotos && !img.escopo.videos && !img.escopo.voz) return { erro: "Marque fotos, vídeos ou voz, ou escolha outra opção de imagem." };
    return { p_termo_participacao: tp.value, p_imagem: img, p_responsavel: resp };
  }

  /* ---------- link pessoal: termos e autorizações ---------- */
  async function minha(box, protocolo, chave) {
    const { data: d, error } = await sb.rpc("meus_termos", { p_protocolo: protocolo, p_chave: chave });
    if (error) { box.innerHTML = `<p class="notice">${h(error.message)}</p>`; return; }
    const img = d.consentimentos.find((c) => c.tipo === "imagem_voz" && c.em_vigor);
    const lista = d.consentimentos.map((c) => `<li><b>${h(TIPO[c.tipo])}</b> · versão ${h(c.versao)} · ${c.decisao === "aceito" ? (c.tipo === "imagem_voz" ? "autorizado (" + h(escopoTxt(c.escopo)) + ")" : "aceito") : "não autorizado"}
        · ${h(dataHora(c.registrado_em))}${c.dado_por === "responsavel" ? " · pelo responsável " + h(c.responsavel) : ""}${c.origem === "secretaria" ? " · registrado pela Secretaria" : ""}
        ${c.revogado_em ? ` · <span class="st">revogado em ${h(dataHora(c.revogado_em))}</span>` : c.em_vigor ? ' · <span class="st ok">em vigor</span>' : ""}${c.versao_desatualizada && c.em_vigor ? " · há uma versão mais nova do termo" : ""}
        ${!c.revogado_em && c.tipo === "imagem_voz" && c.decisao === "aceito" ? ` · <button class="linkbtn" type="button" data-tm-revogar="${h(c.id)}">revogar</button>` : ""}</li>`).join("");
    const t = d.vigentes.imagem_voz;
    box.innerHTML = `<div class="card cp-bloco"><p class="eyebrow">Termos e autorizações</p>
      ${lista ? `<ul class="tmLista">${lista}</ul>` : '<p class="cp-suave">Nenhum termo registrado nesta inscrição.</p>'}
      ${t && !(img && img.decisao === "aceito") ? `<form class="tmImagemLink" novalidate style="display:grid;gap:12px;margin-top:12px">
        ${!d.tem_nascimento ? '<label>Data de nascimento<input name="nascimento" type="date"></label>' : `<input type="hidden" name="menor" value="${d.menor ? 1 : 0}">`}
        ${blocoImagem(t, "")}${blocoResponsavel("")}
        <div><button class="btn btn-s" type="submit">Salvar minha escolha</button></div><span class="msg" role="status"></span></form>` : ""}
      <p style="font-size:13px;color:var(--suave);margin-top:10px">A autorização de imagem e voz é opcional e não é condição para participar. Para revogar outros termos ou pedir acesso, correção ou exclusão dos seus dados, fale com a Secretaria.</p></div>`;
    const f = box.querySelector(".tmImagemLink"); if (f) { f.dataset.termo = t.id; const r = f.querySelector("[data-tm-resp]"); if (d.menor) r.hidden = false; }
  }
  document.addEventListener("submit", async (ev) => {
    const f = ev.target;
    if (f.classList.contains("tmImagemLink")) {
      ev.preventDefault();
      const [, protocolo, chave] = location.hash.slice(1).split("/"), msg = f.querySelector(".msg");
      const img = imagem(f, f.dataset.termo); if (!img) { msg.textContent = "Escolha Autorizo ou Não autorizo."; return; }
      const menor = f.elements.menor ? f.elements.menor.value === "1" : idade(f.elements.nascimento?.value) < 18;
      const { error } = await sb.rpc("autorizar_imagem_link", { p_protocolo: protocolo, p_chave: chave, p_termo: img.termo_id, p_decisao: img.decisao, p_escopo: img.escopo,
        p_responsavel: menor ? responsavel(f) : null, p_data_nascimento: f.elements.nascimento?.value || null });
      if (error) { msg.textContent = error.message; return; }
      minha(f.closest("#tmMinha"), protocolo, chave);
    }
    if (f.classList.contains("tmCandidatura")) {
      ev.preventDefault();
      const [, protocolo, chave] = location.hash.slice(1).split("/"), msg = f.querySelector(".msg");
      const mins = [...f.querySelectorAll('select[name="ministerio"]')].map((s) => s.value).filter(Boolean);
      if (!mins.length) { msg.textContent = "Escolha ao menos um ministério."; return; }
      if (!f.elements.termo.checked) { msg.textContent = "É preciso aceitar o termo de adesão ao serviço voluntário."; return; }
      const { error } = await sb.rpc("voluntariado_indicar", { p_protocolo: protocolo, p_chave: chave, p_ministerios: mins, p_termo: f.elements.termo.value, p_responsavel: null });
      if (error) { msg.textContent = error.message; return; }
      candidatura(f.closest("#tmCand"), protocolo, chave);
    }
    if (f.id === "mbForm") {
      ev.preventDefault();
      const msg = f.querySelector(".msg"), v = (n) => f.elements[n].value.trim();
      if (v("site")) return;
      if (!f.elements.aceite.checked) { msg.textContent = "Marque a concordância com o uso dos dados."; return; }
      const { data, error } = await sb.rpc("membresia_interesse", { p_nome: v("nome"), p_telefone: v("telefone"), p_email: v("email"), p_data_nascimento: v("nascimento") || null, p_mensagem: v("mensagem") || null, p_aceite_privacidade: true });
      if (error) { msg.textContent = error.message; return; }
      f.outerHTML = `<div class="done" role="status"><h3>Recebemos o seu interesse</h3><p>${h(data.mensagem)}</p></div>`;
    }
  });
  document.addEventListener("click", async (ev) => {
    const b = ev.target.closest("[data-tm-revogar]"); if (!b) return;
    if (b.dataset.ok !== "1") { b.dataset.ok = "1"; b.textContent = "confirmar revogação"; return; }
    const [, protocolo, chave] = location.hash.slice(1).split("/");
    const { error } = await sb.rpc("revogar_consentimento_link", { p_protocolo: protocolo, p_chave: chave, p_consentimento: b.dataset.tmRevogar, p_motivo: null });
    if (error) { BetelUI.aviso(error.message); return; }
    minha(b.closest("#tmMinha"), protocolo, chave);
  });

  /* ---------- link pessoal: candidatura ao voluntariado ---------- */
  const CAND = { aguardando_indicacao: "Indique os ministérios", em_analise: "Em análise pela liderança", aprovada: "Aprovada", nao_aprovada: "Não aprovada", cancelada: "Cancelada" };
  const IND = { pendente: "aguardando a liderança", aprovada: "aprovado(a)", recusada: "não aprovado(a)", cancelada: "cancelada" };
  async function candidatura(box, protocolo, chave) {
    const { data: c, error } = await sb.rpc("minha_candidatura", { p_protocolo: protocolo, p_chave: chave });
    if (error || !c) { box.innerHTML = ""; return; }
    const sel = (k) => `<label>${k}ª opção${k > 1 ? " (opcional)" : ""}<select name="ministerio"><option value="">—</option>${c.ministerios.map((m) => `<option value="${h(m.id)}">${h(m.nome)}</option>`).join("")}</select></label>`;
    box.innerHTML = `<div class="card cp-bloco"><p class="eyebrow">Voluntariado</p>
      <p><span class="st ${c.status === "aprovada" ? "ok" : "novo"}">${h(CAND[c.status])}</span></p>
      ${c.indicacoes.map((i) => `<p style="font-size:14px;color:var(--suave)">${h(i.ordem)}. ${h(i.ministerio)} · ${h(IND[i.status])}</p>`).join("")}
      ${c.status === "aprovada" ? '<p class="notice">Parabéns! A liderança aprovou você. A Secretaria vai enviar o acesso à Área de Membros.</p>' : ""}
      ${c.status === "aguardando_indicacao" ? (c.termo ? `<form class="tmCandidatura" novalidate style="display:grid;gap:12px">
        <p class="cp-suave">Escolha até três ministérios, em ordem de preferência. A liderança de cada um analisa a sua candidatura.</p>
        <div class="formgrid">${sel(1)}${sel(2)}${sel(3)}</div>
        <fieldset class="tmPart"><legend>${h(c.termo.titulo)}</legend>${textoTermo(c.termo)}
        <label class="cuAceite"><input type="checkbox" name="termo" value="${h(c.termo.id)}"> <span>Li e aceito o termo de adesão ao serviço voluntário (versão ${h(c.termo.versao)}).</span></label></fieldset>
        <div><button class="btn btn-p" type="submit">Enviar indicação</button></div><span class="msg" role="status"></span></form>`
        : '<p class="notice">O termo de adesão ao voluntariado ainda não foi publicado. Fale com a Secretaria.</p>') : ""}</div>`;
  }

  /* ---------- página "Quero me tornar membro" ---------- */
  function paginaMembresia() {
    const box = el("mbConteudo"); if (!box || box.dataset.ok) return; box.dataset.ok = "1";
    box.innerHTML = `<form class="formcard glass" id="mbForm" novalidate style="max-width:760px">
      <p class="cp-suave">Preencha para a Secretaria entrar em contato. O caminho para a membresia passa pelo Curso de Novos Membros, e a membresia é validada pela Secretaria. Este formulário não torna ninguém membro.</p>
      <div class="formgrid"><label class="cp-full">Nome completo<input name="nome" maxlength="120" autocomplete="name"></label>
      <label>Telefone (WhatsApp)<input name="telefone" inputmode="tel" maxlength="20" autocomplete="tel"></label><label>E-mail<input name="email" type="email" maxlength="120" autocomplete="email"></label>
      <label>Data de nascimento<input name="nascimento" type="date"></label><label>Mensagem (opcional)<input name="mensagem" maxlength="1000"></label>
      <label class="cuOculto" aria-hidden="true">Site<input name="site" tabindex="-1" autocomplete="off"></label></div>
      <label class="cuAceite"><input type="checkbox" name="aceite"> <span>Concordo que a Igreja Batista Betel use estes dados para falar comigo sobre a membresia e o Curso de Novos Membros.</span></label>
      <div><button class="btn btn-p" type="submit">Enviar</button></div><span class="msg" role="status"></span></form>`;
  }
  window.addEventListener("hashchange", () => { if (location.hash === "#membresia") paginaMembresia(); });
  if (location.hash === "#membresia") paginaMembresia();

  /* ---------- páginas antigas "Quero servir" e "Uso de imagem" ----------
     No sistema novo não há autodeclaração de membresia nem formulário avulso
     de imagem sem vínculo com a pessoa: as páginas explicam o caminho real. */
  function substituirAntigas() {
    const servir = document.querySelector("#v-servir .wrap:last-child");
    if (servir && !servir.dataset.novo) { servir.dataset.novo = "1"; servir.innerHTML = `<div class="card glass" style="max-width:860px;display:grid;gap:16px">
      <p class="eyebrow">Como se tornar voluntário</p>
      <ol class="tmPassos"><li><b>Membresia validada pela Secretaria.</b> Ainda não é membro? <a class="linkbtn" href="#membresia">Fale com a Secretaria</a>.</li>
      <li><b>Curso de Novos Membros</b> concluído. <a class="linkbtn" href="#curso/novos-membros">Ver o curso</a></li>
      <li><b>Formação de Voluntários</b>. <a class="linkbtn" href="#curso/formacao-de-voluntarios">Ver o curso</a></li>
      <li><b>Indicação dos ministérios</b> e aceite do termo de adesão, pelo link pessoal da sua inscrição na Formação.</li>
      <li><b>Aprovação da liderança</b> do ministério. Depois, a Secretaria envia o seu acesso à Área de Membros.</li></ol>
      <p class="cp-suave">Já é membro há mais tempo e fez o Curso de Novos Membros antes do site? A Secretaria registra a sua conclusão anterior.</p></div>`; }
    const img = el("imgBox");
    if (img && !img.dataset.novo) { img.dataset.novo = "1"; img.innerHTML = `<div class="card glass" style="max-width:860px;display:grid;gap:14px">
      <p class="eyebrow">Autorização de uso de imagem e voz</p>
      <p><b>É opcional.</b> Quem não autoriza participa normalmente de todos os cursos e eventos.</p>
      <p class="cp-suave">Fez inscrição em um curso? Abra o link pessoal da inscrição para autorizar, recusar ou revogar a autorização a qualquer momento. Também é possível registrar ou revogar a autorização com a Secretaria, inclusive em papel. Para menores de 18 anos, quem decide é o responsável legal.</p></div>`; }
  }
  if (window.BETEL_SUPABASE) substituirAntigas();

  return { preencher, coletar, minha, candidatura, responsavel, imagem, termos, idade, blocoResponsavel };
})();
