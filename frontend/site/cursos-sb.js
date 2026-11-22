/* =====================================================================
   Cursos e Formação Betel — páginas públicas (cards, página do curso,
   inscrição e acompanhamento). Vagas, duplicidade e pré-requisitos são
   conferidos no banco (função inscrever_curso).
   ===================================================================== */
(() => {
  const sb = window.betelSB;
  if (!sb) return;
  const el = (id) => document.getElementById(id);
  const h = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const imgSegura = (u) => (/^(https:\/\/|\/|img\/)/.test(String(u || "")) || String(u || "").startsWith(location.origin + "/")) ? u : "";
  const data = (d) => d ? new Date(d + (String(d).length === 10 ? "T12:00:00" : "")).toLocaleDateString("pt-BR") : "";
  const dataHora = (d) => d ? new Date(d).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" }) : "";
  const reais = (v) => Number(v).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  const MOD = { presencial: "Presencial", online: "Online", hibrido: "Presencial e online" };
  const ST = { confirmada: "Inscrição confirmada", aguardando_pagamento: "Aguardando pagamento", lista_espera: "Lista de espera", cancelada: "Cancelada", concluida: "Curso concluído" };

  function imagem(c, classe) {
    const u = imgSegura(c.imagem_url);
    return u ? `<img class="cuImg ${classe || ""}" src="${h(u)}" alt="" loading="lazy">` : `<div class="cuImg vazia ${classe || ""}" aria-hidden="true">${h((c.titulo || "B").trim()[0])}</div>`;
  }
  function situacao(c) {
    const abertas = c.turmas.filter((t) => t.aberta);
    if (abertas.length) {
      const semVaga = abertas.every((t) => t.vagas_restantes === 0);
      return semVaga ? '<span class="st">Vagas esgotadas · lista de espera</span>' : '<span class="st novo">Inscrições abertas</span>';
    }
    if (c.turmas.some((t) => t.status === "em_andamento")) return '<span class="st ok">Turma em andamento</span>';
    return '<span class="st">Novas turmas em breve</span>';
  }

  async function renderLista() {
    const box = el("cuLista");
    const { data: cats, error } = await sb.rpc("cursos_publicos");
    if (error) { box.innerHTML = '<p class="notice">Não foi possível carregar os cursos agora. Tente novamente em instantes.</p>'; return; }
    const comCursos = cats.filter((c) => c.cursos.length);
    box.innerHTML = comCursos.length ? comCursos.map((cat) => `<div class="cuGrupo"><h2>${h(cat.nome)}</h2>${cat.descricao ? `<p class="lead" style="margin:-8px 0 22px;text-align:left">${h(cat.descricao)}</p>` : ""}
      <div class="cuCards">${cat.cursos.map((c) => `<a class="cuCard glass" href="#curso/${h(c.slug)}">${imagem(c)}<div class="cuCorpo">
        <p class="eyebrow">${h(MOD[c.modalidade] || "")}${c.carga_horaria ? " · " + h(c.carga_horaria) : ""}</p><h3>${h(c.titulo)}</h3>${c.resumo ? `<p>${h(c.resumo)}</p>` : ""}${situacao(c)}</div></a>`).join("")}</div></div>`).join("")
      : '<p class="empty">Os cursos serão divulgados aqui em breve.</p>';
  }

  function campoInfo(rotulo, valor) { return valor ? `<div><b>${h(rotulo)}</b>${h(valor)}</div>` : ""; }
  function blocoTurma(t, c) {
    const periodo = t.data_inicio ? (t.data_fim && t.data_fim !== t.data_inicio ? `${data(t.data_inicio)} a ${data(t.data_fim)}` : data(t.data_inicio)) : "";
    const vagas = t.vagas == null ? "" : t.vagas_restantes > 0 ? `${t.vagas_restantes} de ${t.vagas}` : `Esgotadas${t.lista_espera ? " · lista de espera aberta" : ""}`;
    const janela = t.inscricao_fecha_em ? `Inscrições até ${dataHora(t.inscricao_fecha_em)}` : "";
    let acao;
    if (t.aberta && (t.vagas_restantes !== 0 || t.lista_espera)) acao = formulario(t, c);
    else if (t.status === "inscricoes_abertas" && t.inscricao_abre_em && new Date(t.inscricao_abre_em) > new Date()) acao = `<p class="notice">As inscrições abrem em ${h(dataHora(t.inscricao_abre_em))}.</p>`;
    else if (t.aberta) acao = '<p class="notice">As vagas desta turma estão esgotadas.</p>';
    else acao = `<p class="notice">${t.status === "em_andamento" ? "Turma em andamento. As inscrições estão encerradas." : "As inscrições desta turma estão encerradas."}</p>`;
    return `<div class="card glass cuTurma" id="turma-${h(t.id)}"><p class="eyebrow">Turma</p><h3>${h(t.nome)}</h3>
      <div class="cuInfo">${campoInfo("Período", periodo)}${campoInfo("Dias e horário", t.dias_horario)}${campoInfo("Local", t.local)}${campoInfo("Professores", t.professores)}${campoInfo("Vagas", vagas)}${campoInfo("Investimento", t.valor > 0 ? reais(t.valor) : t.valor === 0 ? "Gratuito" : "")}${campoInfo("Inscrições", janela)}</div>${acao}</div>`;
  }
  function formulario(t, c) {
    return `<form class="formcard cuForm" data-turma="${h(t.id)}" style="padding:0" novalidate>
      <h3 class="cp-secao">${t.vagas_restantes === 0 ? "Entrar na lista de espera" : "Fazer inscrição"}</h3>
      ${c.exige_membro || c.exigidos_nomes.length ? `<p class="notice">Pré-requisitos: ${c.exige_membro ? "ser membro com a membresia validada pela Secretaria" : ""}${c.exige_membro && c.exigidos_nomes.length ? " e " : ""}${c.exigidos_nomes.length ? "ter concluído " + h(c.exigidos_nomes.join(", ")) : ""}. Use o mesmo e-mail do seu cadastro na igreja.</p>` : ""}
      <div class="formgrid">
        <label class="cp-full">Nome completo<input name="nome" required maxlength="120" autocomplete="name"></label>
        <label>Telefone (WhatsApp)<input name="telefone" required inputmode="tel" maxlength="20" placeholder="(31) 99999-9999" autocomplete="tel"></label>
        <label>E-mail<input name="email" type="email" required maxlength="120" autocomplete="email"></label>
        <label>Data de nascimento<input name="nascimento" type="date" required></label>
        <label>Observação (opcional)<input name="observacao" maxlength="600"></label>
        <label class="cuOculto" aria-hidden="true">Site<input name="site" tabindex="-1" autocomplete="off"></label>
      </div>
      <label class="cuAceite"><input type="checkbox" name="aceite"> <span>Concordo que a Igreja Batista Betel use estes dados para a minha inscrição e para falar comigo sobre este curso.</span></label>
      <div class="tmBloco"><p class="msg">Carregando os termos…</p></div>
      <div><button class="btn btn-p" type="submit">${t.vagas_restantes === 0 ? "Entrar na lista de espera" : "Confirmar inscrição"}</button></div>
      <span class="msg" role="status"></span></form>`;
  }

  async function renderCurso(slug) {
    const box = el("cuPagina");
    box.innerHTML = '<p class="msg">Carregando…</p>';
    const { data: c, error } = await sb.rpc("curso_publico", { p_slug: slug });
    if (error || !c) { box.innerHTML = '<p class="notice">Curso não encontrado. <a href="#cursos">Ver todos os cursos</a></p>'; return; }
    document.title = c.titulo + " · Igreja Batista Betel";
    box.innerHTML = `<p style="margin-bottom:22px"><a href="#cursos" class="linkbtn">← Todos os cursos</a></p>
      <div class="cuTopo"><div><p class="eyebrow">${h(c.categoria)}</p><h1 style="font-size:clamp(34px,5vw,60px);line-height:1.05;text-align:left">${h(c.titulo)}</h1>
        ${c.resumo ? `<p class="lead" style="text-align:left;margin-top:18px">${h(c.resumo)}</p>` : ""}
        <div class="cuInfo">${campoInfo("Modalidade", MOD[c.modalidade])}${campoInfo("Carga horária", c.carga_horaria)}${campoInfo("Para quem", c.publico_alvo)}</div></div>
        <div>${imagem(c)}</div></div>
      ${c.descricao ? `<div class="card glass" style="margin-top:36px"><p class="eyebrow">Sobre o curso</p><div class="cuTexto">${h(c.descricao)}</div></div>` : ""}
      <div style="margin-top:36px"><h2 style="font-size:30px">Turmas</h2>
      ${c.turmas.length ? c.turmas.map((t) => blocoTurma(t, c)).join("") : '<p class="notice" style="margin-top:14px">Ainda não há turma com inscrições para este curso. Datas, horários e local serão divulgados aqui.</p>'}</div>
      ${c.slug === "novos-membros" ? '<p class="notice" style="margin-top:24px">Quer se tornar membro da Betel? <a class="linkbtn" href="#membresia">Fale com a Secretaria</a>.</p>' : ""}`;
    if (window.BetelTermos) window.BetelTermos.preencher(box);
  }

  const CERT = { aguardando_validacao: "em validação", aguardando_autorizacao: "em validação", autorizado: "aprovado, aguardando a definição da cerimônia", preparado: "aguardando a cerimônia de entrega", impresso: "aguardando a cerimônia de entrega", entregue: "entregue", elegivel: "em preparação" };
  const PAG = { em_analise: "Em análise pela Tesouraria", aprovado: "Aprovado", recusado: "Recusado", novo_comprovante_solicitado: "A Tesouraria pediu um novo comprovante", aguardando_comprovante: "Aguardando comprovante" };
  function blocoFinanceiro(i) {
    const f = i.financeiro || {}; if (!(Number(f.valor_bruto) > 0)) return "";
    const pend = i.pagamentos || [];
    const emAnalise = pend.some((p) => p.status === "em_analise");
    const pedido = pend.filter((p) => ["recusado", "novo_comprovante_solicitado"].includes(p.status)).pop();
    const podeEnviar = i.status === "aguardando_pagamento" && !emAnalise;
    return `<div class="card cp-bloco"><p class="eyebrow">Pagamento</p>
      <p>Valor: <b>${h(reais(f.valor_bruto))}</b>${Number(f.valor_desconto) > 0 ? ` · desconto: ${h(reais(f.valor_desconto))} · a pagar: <b>${h(reais(f.valor_final))}</b>` : ""}${Number(f.aprovado) > 0 ? ` · aprovado: ${h(reais(f.aprovado))}` : ""}</p>
      ${pend.map((p) => `<p style="font-size:14px;color:var(--suave)">${h(reais(p.valor))} · ${h(PAG[p.status] || p.status)}${p.mensagem ? ` — <b>${h(p.mensagem)}</b>` : ""}</p>`).join("")}
      ${emAnalise ? '<p class="notice">Seu comprovante foi recebido e está em análise. <b>A inscrição só é confirmada depois da aprovação da Tesouraria.</b></p>' : ""}
      ${podeEnviar ? `<form class="formcard cuComprovante" style="padding:0;margin-top:10px" novalidate><h3 style="font-size:20px">${pedido ? "Enviar novo comprovante" : "Enviar comprovante de pagamento"}</h3>
        <div class="formgrid"><label>Forma de pagamento<select name="metodo"><option value="pix">Pix</option><option value="transferencia">Transferência</option><option value="outro">Outra</option></select></label>
        <label>Valor pago (R$)<input name="valor" type="number" min="0.01" step="0.01" value="${h(Math.max(Number(f.valor_final) - Number(f.aprovado || 0), 0).toFixed(2))}"></label>
        <label>Data do pagamento<input name="pago_em" type="date"></label>
        <label>Comprovante (PDF, JPG, PNG ou WebP, até 5 MB)<input name="arquivo" type="file" accept="application/pdf,image/jpeg,image/png,image/webp"></label></div>
        <p style="font-size:14px;color:var(--suave)">O envio do comprovante não confirma a inscrição: a Tesouraria confere o pagamento e aprova.</p>
        <div><button class="btn btn-p" type="submit">Enviar comprovante</button></div><span class="msg" role="status"></span></form>` : ""}</div>`;
  }
  const paraBase64 = (arq) => new Promise((ok, erro) => { const r = new FileReader(); r.onload = () => ok(String(r.result).split(",")[1]); r.onerror = erro; r.readAsDataURL(arq); });
  document.addEventListener("submit", async (ev) => {
    const f = ev.target; if (!f.classList.contains("cuComprovante")) return;
    ev.preventDefault();
    const msg = f.querySelector(".msg"), b = f.querySelector('[type="submit"]'), arq = f.elements.arquivo.files[0];
    if (!arq) { msg.textContent = "Anexe o comprovante."; return; }
    if (arq.size > 5 * 1024 * 1024) { msg.textContent = "O arquivo passa de 5 MB."; return; }
    if (!f.elements.pago_em.value) { msg.textContent = "Informe a data do pagamento."; return; }
    const [, protocolo, chave] = location.hash.slice(1).split("/");
    b.disabled = true; msg.textContent = "Enviando…";
    const { data, error } = await sb.functions.invoke("arquivos", { body: { acao: "enviar_comprovante", protocolo, chave, metodo: f.elements.metodo.value,
      valor: Number(f.elements.valor.value), pago_em: f.elements.pago_em.value, arquivo: { nome: arq.name, tipo: arq.type, base64: await paraBase64(arq) } } });
    b.disabled = false;
    if (error) { let m = "Não foi possível enviar."; try { m = (await error.context.json()).erro || m; } catch (_) {} msg.textContent = m; return; }
    renderMinha(protocolo, chave);
  });

  async function renderMinha(protocolo, chave) {
    const box = el("cuMinha");
    const { data: i, error } = await sb.rpc("minha_inscricao_curso", { p_protocolo: protocolo, p_chave: chave });
    if (error) { box.innerHTML = `<p class="notice">${h(error.message)}</p>`; return; }
    const t = i.turma;
    box.innerHTML = `<div class="card glass" style="max-width:760px"><p class="eyebrow">Protocolo ${h(i.protocolo)}</p><h3>${h(i.curso)} · ${h(t.nome)}</h3>
      <p><span class="st ${i.status === "confirmada" || i.status === "concluida" ? "ok" : i.status === "cancelada" ? "" : "novo"}">${h(ST[i.status])}</span></p>
      <p class="cp-suave">${h(i.nome)} · inscrição feita em ${h(dataHora(i.criado_em))}</p>
      ${i.status === "lista_espera" ? `<p class="notice">Você é o número <b>${h(i.posicao_espera)}</b> da lista de espera. Se abrir uma vaga, a sua inscrição é confirmada automaticamente, na ordem de chegada.</p>` : ""}
      ${blocoFinanceiro(i)}
      ${i.certificado ? `<p class="notice">Certificado: <b>${h(CERT[i.certificado.status] || i.certificado.status)}</b>${i.certificado.cerimonia ? ` · entrega na cerimônia "${h(i.certificado.cerimonia)}"${i.certificado.data ? " em " + h(data(i.certificado.data)) : ""}${i.certificado.local ? ", " + h(i.certificado.local) : ""}` : ""}. Os certificados são entregues somente em mãos, na cerimônia; não há download nem envio por e-mail ou WhatsApp.</p>` : ""}
      <div class="cp-acoes"><a class="btn btn-s" href="#curso/${h(i.curso_slug)}">Ver o curso</a>
      ${["confirmada", "aguardando_pagamento", "lista_espera"].includes(i.status) ? '<button class="btn btn-s" type="button" id="cuCancelar">Cancelar minha inscrição</button>' : ""}</div>
      <span class="msg" id="cuMinhaMsg" role="status"></span><div id="tmCand"></div><div id="tmMinha"></div></div>`;
    if (window.BetelTermos) { window.BetelTermos.candidatura(el("tmCand"), protocolo, chave); window.BetelTermos.minha(el("tmMinha"), protocolo, chave); }
  }

  function resultado(r, form) {
    const link = `${location.origin}${location.pathname}#inscricao-curso/${r.protocolo}/${r.chave}`;
    const msg = r.status === "lista_espera" ? `As vagas estavam esgotadas: você entrou na <b>lista de espera</b> (posição ${h(r.posicao_espera)}). Se abrir uma vaga, a inscrição é confirmada automaticamente.`
      : r.status === "aguardando_pagamento" ? `Sua vaga está reservada. Valor: <b>${h(reais(r.valor))}</b>. A inscrição será confirmada depois que o pagamento for aprovado pela Tesouraria.`
      : "Sua inscrição está <b>confirmada</b>.";
    form.outerHTML = `<div class="done" role="status"><p class="eyebrow">Protocolo ${h(r.protocolo)}</p><h3>${r.status === "lista_espera" ? "Você está na lista de espera" : "Inscrição recebida"}</h3><p>${msg}</p>
      <p style="font-size:14px">Guarde este link pessoal para acompanhar ou cancelar a inscrição:</p>
      <p style="font:400 13px/1.5 var(--mono);overflow-wrap:anywhere"><a href="${h(link)}">${h(link)}</a></p>
      <div><button class="btn btn-s sm" type="button" data-cu-copiar="${h(link)}">Copiar link</button></div></div>`;
  }

  document.addEventListener("submit", async (ev) => {
    const f = ev.target; if (!f.classList.contains("cuForm")) return;
    ev.preventDefault();
    const msg = f.querySelector(".msg"), b = f.querySelector('[type="submit"]'), v = (n) => f.elements[n].value.trim();
    if (v("site")) return;
    if (v("nome").split(/\s+/).length < 2) { msg.textContent = "Informe o nome completo."; return; }
    if (!/^\d{10,13}$/.test(v("telefone").replace(/\D/g, ""))) { msg.textContent = "Informe o telefone com DDD."; return; }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v("email"))) { msg.textContent = "Informe um e-mail válido."; return; }
    if (!f.elements.aceite.checked) { msg.textContent = "Marque a concordância com o uso dos dados."; return; }
    const tm = window.BetelTermos.coletar(f); if (tm.erro) { msg.textContent = tm.erro; return; }
    b.disabled = true; msg.textContent = "Enviando…";
    const { data, error } = await sb.rpc("inscrever_curso_com_termos", { p_turma: f.dataset.turma, p_nome: v("nome"), p_telefone: v("telefone"), p_email: v("email"),
      p_data_nascimento: v("nascimento"), p_observacao: v("observacao") || null, p_aceite_privacidade: true, ...tm, p_origem: "site", p_termo_presencial: false });
    b.disabled = false;
    if (error) { msg.textContent = error.message; return; }
    if (data.duplicada) { msg.innerHTML = h(data.mensagem) + " Use o link recebido na primeira inscrição para acompanhar."; return; }
    resultado(data, f);
  });
  document.addEventListener("click", async (ev) => {
    const cp = ev.target.closest("[data-cu-copiar]");
    if (cp) { try { await navigator.clipboard.writeText(cp.dataset.cuCopiar); cp.textContent = "Copiado"; } catch (_) { cp.textContent = "Copie o link acima"; } return; }
    if (ev.target.id === "cuCancelar") {
      const b = ev.target; if (b.dataset.confirma !== "1") { b.dataset.confirma = "1"; b.textContent = "Confirmar cancelamento"; return; }
      const [, protocolo, chave] = location.hash.slice(1).split("/");
      b.disabled = true;
      const { error } = await sb.rpc("cancelar_minha_inscricao_curso", { p_protocolo: protocolo, p_chave: chave });
      if (error) { el("cuMinhaMsg").textContent = error.message; b.disabled = false; return; }
      renderMinha(protocolo, chave);
    }
  });

  function rota() {
    const r = location.hash.slice(1);
    if (r === "cursos") renderLista();
    else if (r.startsWith("curso/")) renderCurso(decodeURIComponent(r.slice(6)));
    else if (r.startsWith("inscricao-curso/")) { const [, p, c] = r.split("/"); renderMinha(p, c); }
  }
  window.addEventListener("hashchange", rota);
  rota();
})();
