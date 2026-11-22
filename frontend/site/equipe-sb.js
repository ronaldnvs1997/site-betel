/* =====================================================================
   Área de Membros — autenticação centralizada (Supabase Auth)
   Toda permissão é conferida no banco (RLS e funções). As telas apenas
   mostram o que o backend libera para o perfil.
   ===================================================================== */
(() => {
  const CFG = window.BETEL_SUPABASE;
  if (!CFG || !window.supabase) return;
  const sb = window.supabase.createClient(CFG.url, CFG.anonKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, storageKey: "betel-equipe" },
  });
  window.betelSB = sb;

  const el = (id) => document.getElementById(id);
  const h = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const PERFIL = { MASTER: "Master", LIDER: "Líder", VOLUNTARIO: "Voluntário(a)" };
  const ATRIB = { SECRETARIA: "Secretaria", TESOURARIA: "Tesouraria" };
  const FUNCAO = { lider: "Líder", voluntario: "Voluntário(a)" };
  const ABAS = {
    MASTER: [["painel", "Painel"], ["agenda", "Agenda Ministerial"], ["solicitacoes", "Solicitações"], ["usuarios", "Usuários"], ["ministerios", "Ministérios"], ["historico", "Histórico"], ["conta", "Meu perfil"]],
    LIDER: [["painel", "Painel"], ["agenda", "Agenda Ministerial"], ["equipe", "Minha equipe"], ["conta", "Meu perfil"]],
    VOLUNTARIO: [["painel", "Painel"], ["agenda", "Agenda Ministerial"], ["equipe", "Minha equipe"], ["conta", "Meu perfil"]],
  };
  const fone = (t) => { const d = String(t || "").replace(/\D/g, ""); return d.length === 11 ? `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}` : d.length === 10 ? `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}` : d; };
  const dataHora = (s) => { if (!s) return ""; const d = new Date(s); return d.toLocaleDateString("pt-BR") + " " + d.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" }); };
  const primeiro = (n) => String(n || "").split(" ")[0];

  let sessao = null, painel = null, ultimaSenha = "", recuperando = false;
  let ministerios = [], solicitacoes = [], usuarios = [], historico = [], filtroSol = "pendente", filtroHist = "principais";
  let carregando = false, saindo = false, aviso = "";

  /* ---------- mensagens de erro ---------- */
  function msgAuth(err) {
    const c = err?.code || err?.error_code || "", m = String(err?.message || "");
    if (c === "invalid_credentials" || /invalid login/i.test(m)) return "E-mail ou senha incorretos.";
    if (c === "user_banned" || /banned/i.test(m)) return "Esta conta está desativada. Fale com o responsável (MASTER).";
    if (c === "weak_password" || /at least|weak/i.test(m)) return "A senha precisa ter pelo menos 10 caracteres.";
    if (c === "same_password" || /different from the old/i.test(m)) return "A nova senha precisa ser diferente da senha atual.";
    if (c === "over_request_rate_limit" || c === "over_email_send_rate_limit" || /rate limit/i.test(m)) return "Muitas tentativas seguidas. Aguarde alguns minutos.";
    return m || "Não foi possível concluir. Tente novamente.";
  }
  async function msgFuncao(error) {
    try { const j = await error.context.json(); return j.erro || "Não foi possível concluir."; } catch (_) { return "Não foi possível concluir."; }
  }
  async function rpc(nome, args) {
    const { data, error } = await sb.rpc(nome, args || {});
    if (error) {
      if (error.code === "42501") throw new Error(error.message || "Acesso negado.");
      throw new Error(error.message || "Erro ao consultar o banco.");
    }
    return data;
  }
  async function funcao(nome, corpo) {
    const { data, error } = await sb.functions.invoke(nome, { body: corpo });
    if (error) throw new Error(await msgFuncao(error));
    return data;
  }
  const senhaOk = (s) => s.length >= 10 && /[A-Za-zÀ-ú]/.test(s) && /\d/.test(s);

  /* ---------- rotas da área ---------- */
  const rotaAtual = () => { const r = location.hash.slice(1); return r === "equipe" || r.startsWith("equipe/") ? (r.split("/")[1] || "") : null; };
  function ir(sub) { const alvo = "#equipe" + (sub ? "/" + sub : ""); if (location.hash !== alvo) location.hash = alvo; else render(); }

  function topo(titulo, lead) { el("sbTitulo").innerHTML = titulo; el("sbLead").textContent = lead; }
  function barra() {
    const b = el("sbBarra");
    if (!sessao || !painel || painel.status !== "ok") { b.hidden = true; return; }
    b.hidden = false;
    b.innerHTML = `Conectado como <b>${h(painel.nome)}</b> · ${h(PERFIL[painel.perfil] || painel.perfil)}${(painel.atribuicoes || []).length ? " + " + h(painel.atribuicoes.map((a) => ATRIB[a]).join(", ")) : ""} · <button type="button" class="linkbtn" data-sb="conta">Meu perfil</button> · <button type="button" class="linkbtn" data-sb="sair">Sair</button>`;
  }

  /* ---------- telas públicas ---------- */
  function telaInicial() {
    topo("Área de <em>Membros</em>.", "Secretaria, líderes de ministério e voluntários entram com a própria conta e veem só o que é da sua função.");
    el("sbPainel").hidden = true;
    el("sbTela").innerHTML = `<div class="two" style="grid-template-columns:repeat(auto-fit,minmax(min(100%,340px),1fr));align-items:stretch">
      <div class="card glass"><p class="eyebrow">Já tenho acesso</p><h3>Fazer login</h3><p style="color:var(--suave);font-size:15px">Entre com o seu e-mail e a sua senha.</p><button class="btn btn-p" type="button" data-sb="ir:entrar">Fazer login</button></div>
      <div class="card glass"><p class="eyebrow">Ainda não tenho acesso</p><h3>Solicitar acesso</h3><p style="color:var(--suave);font-size:15px">Envie seus dados. O responsável pela Área de Membros analisa e libera o acesso.</p><button class="btn btn-s" type="button" data-sb="ir:solicitar">Solicitar acesso</button></div>
    </div>`;
  }
  function telaLogin(msg) {
    topo("Fazer <em>login</em>.", "Use o e-mail e a senha da sua conta de membro da Igreja Batista Betel.");
    el("sbPainel").hidden = true;
    el("sbTela").innerHTML = `<form class="card glass" id="sbLogin" style="max-width:520px" novalidate>
      <h3>Entrar</h3>
      <label>E-mail<input id="sbEmail" type="email" required autocomplete="username" maxlength="120"></label>
      <label>Senha<input id="sbSenha" type="password" required autocomplete="current-password" maxlength="72"></label>
      <div class="cp-acoes"><button class="btn btn-p" type="submit" id="sbEntrar">Entrar</button><button class="btn btn-s" type="button" data-sb="ir:">Voltar</button></div>
      <span class="msg" id="sbMsg" role="status">${h(msg || "")}</span>
      <p class="notice"><button type="button" class="linkbtn" data-sb="ir:esqueci">Esqueci minha senha</button> · Ainda não tem acesso? <button type="button" class="linkbtn" data-sb="ir:solicitar">Solicitar acesso</button></p>
    </form>`;
  }
  async function telaSolicitar() {
    topo("Solicitar <em>acesso</em>.", "Preencha seus dados. O responsável pela Área de Membros analisa o pedido e libera o acesso.");
    el("sbPainel").hidden = true;
    el("sbTela").innerHTML = '<p class="msg">Carregando ministérios…</p>';
    const { data, error } = await sb.from("ministerios").select("id,nome,ordem").order("ordem");
    const lista = error ? [] : data;
    el("sbTela").innerHTML = `<form class="formcard glass" id="sbSolicitar" style="max-width:760px" novalidate>
      <h3>Seus dados</h3>
      <div class="formgrid">
        <label class="cp-full">Nome completo<input id="soNome" required maxlength="120" autocomplete="name"></label>
        <label>Telefone (WhatsApp)<input id="soTel" required inputmode="tel" maxlength="20" placeholder="(31) 99999-9999" autocomplete="tel"></label>
        <label>E-mail<input id="soEmail" type="email" required maxlength="120" autocomplete="email"></label>
        <label>Ministério<select id="soMin" required><option value="">Escolha…</option>${lista.map((m) => `<option value="${h(m.id)}">${h(m.nome)}</option>`).join("")}</select></label>
        <div><p style="font-weight:600;font-size:14px;margin-bottom:8px">Função</p><div class="deps" role="radiogroup"><label><input type="radio" name="soFuncao" value="voluntario" checked> Voluntário</label><label><input type="radio" name="soFuncao" value="lider"> Líder</label></div></div>
        <label class="sbOculto" aria-hidden="true">Site<input id="soSite" tabindex="-1" autocomplete="off"></label>
      </div>
      <p class="notice">Seus dados serão usados apenas para analisar este pedido e, se aprovado, para o seu acesso à Área de Membros.</p>
      <div class="cp-acoes"><button class="btn btn-p" type="submit" id="soEnviar">Enviar solicitação</button><button class="btn btn-s" type="button" data-sb="ir:">Voltar</button></div>
      <span class="msg" id="soMsg" role="status">${error ? "Não foi possível carregar os ministérios. Recarregue a página." : ""}</span>
    </form>`;
  }
  function telaEsqueci() {
    setTimeout(() => { aviso = ""; }, 0);
    topo("Recuperar <em>senha</em>.", "Informe o e-mail da sua conta. Você vai receber um link para criar uma nova senha.");
    el("sbPainel").hidden = true;
    el("sbTela").innerHTML = `<form class="card glass" id="sbEsqueci" style="max-width:520px" novalidate>
      <h3>Esqueci minha senha</h3>
      <label>E-mail<input id="esEmail" type="email" required autocomplete="email" maxlength="120"></label>
      <div class="cp-acoes"><button class="btn btn-p" type="submit" id="esEnviar">Enviar link</button><button class="btn btn-s" type="button" data-sb="ir:entrar">Voltar</button></div>
      <span class="msg" id="esMsg" role="status">${h(aviso)}</span>
    </form>`;
  }
  function telaNovaSenha(titulo, texto, recuperacao) {
    topo(titulo, texto);
    el("sbPainel").hidden = true; el("sbBarra").hidden = true;
    el("sbTela").innerHTML = `<form class="card glass" id="sbNovaSenha" data-recuperacao="${recuperacao ? 1 : 0}" style="max-width:520px" novalidate>
      <p class="eyebrow">${recuperacao ? "Recuperação de senha" : "Primeiro acesso"}</p>
      <h3>Crie a sua senha</h3>
      <p style="color:var(--suave);font-size:15px">Mínimo de 10 caracteres, com letras e números. Ela é só sua: não compartilhe com ninguém.</p>
      <label>Nova senha<input id="nsSenha" type="password" required minlength="10" maxlength="72" autocomplete="new-password"></label>
      <label>Confirme a nova senha<input id="nsConf" type="password" required minlength="10" maxlength="72" autocomplete="new-password"></label>
      <div class="cp-acoes"><button class="btn btn-p" type="submit" id="nsSalvar">Salvar senha</button><button class="btn btn-s" type="button" data-sb="sair">Sair</button></div>
      <span class="msg" id="nsMsg" role="status"></span>
    </form>`;
  }
  function telaBloqueio(titulo, texto) {
    topo(titulo, texto); el("sbPainel").hidden = true; el("sbBarra").hidden = true;
    el("sbTela").innerHTML = `<div class="card glass" style="max-width:560px"><p class="cp-suave">${h(texto)}</p><button class="btn btn-s" type="button" data-sb="sair">Sair</button></div>`;
  }

  /* ---------- painel interno ---------- */
  function abasPermitidas() {
    const base = (ABAS[painel.perfil] || ABAS.VOLUNTARIO).slice();
    // Cursos: MASTER ou atribuição SECRETARIA (conferido também no banco)
    const atr = painel.atribuicoes || [], sec = painel.perfil === "MASTER" || atr.includes("SECRETARIA"), tes = atr.includes("TESOURARIA");
    const extras = [];
    if (window.BetelCursosAdmin && sec) extras.push(["cursos", "Cursos"]);
    if (window.BetelSecretaria && sec) extras.push(["secretaria", "Secretaria"]);
    if (window.BetelTesouraria && tes) extras.push(["tesouraria", "Tesouraria"]);
    if (window.BetelMembresia && sec) extras.push(["membresia", "Membresia"]);
    if (window.BetelCandidatos && (painel.perfil === "MASTER" || (painel.ministerios || []).some((m) => m.funcao === "lider"))) extras.push(["candidatos", "Candidatos"]);
    if (window.BetelTurmasLider && (painel.perfil === "MASTER" || painel.perfil === "LIDER")) extras.push(["turmas", "Turmas"]);
    if (window.BetelMidia && painel.midia?.gestor) extras.push(["midia", "Mídia"]);
    if (window.BetelMidia && (painel.perfil !== "VOLUNTARIO" || atr.includes("SECRETARIA"))) extras.push(["solicitar-midia", "Solicitar mídia"]);
    if (window.BetelMidia) extras.push(["escalas", "Minhas escalas"]);
    if (window.BetelImagemMidia && !sec && (painel.ministerios || []).some((m) => m.nome === "Mídia")) extras.push(["imagem", "Autorizações de imagem"]);
    const inst = painel.inst || {};
    if (window.BetelInstitucional) {
      if (painel.perfil !== "MASTER" && (inst.ministerios_lider || []).length) extras.push(["ministerios", "Meus ministérios"]);
      extras.push(["organogramas", "Organogramas"]);
      if (inst.master) extras.push(["site", "Conteúdo do site"]);
      if (inst.agenda_coordenador) extras.push(["agenda-links", "Formulários da Agenda"]);
    }
    extras.push(["avisos", "Avisos"]);
    base.splice(2, 0, ...extras);
    return base;
  }
  // Grupos da navegação (só organização visual; a lista de abas e as permissões não mudam)
  const GRUPOS = [["Geral", ["painel", "agenda", "agenda-links"]], ["Formação e Secretaria", ["cursos", "secretaria", "tesouraria", "membresia"]],
    ["Ministérios", ["ministerios", "organogramas", "candidatos", "turmas", "equipe"]], ["Mídia", ["midia", "solicitar-midia", "escalas", "imagem"]],
    ["Avisos", ["avisos"]], ["Administração", ["solicitacoes", "usuarios", "site", "historico"]], ["Conta", ["conta"]]];
  const grupoDe = (k) => (GRUPOS.find((g) => g[1].includes(k)) || ["Outros"])[0];
  function renderAbas(atual) {
    const ordem = GRUPOS.flatMap((g) => g[1]), pos = (k) => { const i = ordem.indexOf(k); return i < 0 ? 999 : i; };
    const abas = abasPermitidas().map((a, i) => [a, i]).sort((x, y) => pos(x[0][0]) - pos(y[0][0]) || x[1] - y[1]).map((x) => x[0]);
    el("sbAbas").innerHTML = abas.map(([k, n], i) => `${i && grupoDe(k) !== grupoDe(abas[i - 1][0]) ? '<span class="cp-sep" aria-hidden="true"></span>' : ""}<button role="tab" data-sb="aba:${k}" aria-selected="${k === atual}">${h(n)}${k === "solicitacoes" && painel.resumo?.solicitacoes_pendentes ? ` <span class="sbCont">${h(painel.resumo.solicitacoes_pendentes)}</span>` : ""}</button>`).join("");
    // No celular, a mesma navegação vira o menu "Ir para" (agrupado, com ícones)
    renderIrPara(abas, atual);
  }

  /* ---------- menu "Ir para" ---------- */
  const ico = (k, t) => (window.BetelUI?.icone ? window.BetelUI.icone(k, t) : "");
  function renderIrPara(abas, atual) {
    const nomes = Object.fromEntries(abas);
    let caixa = el("sbIrPara");
    if (!caixa) {
      el("sbAbas").insertAdjacentHTML("beforebegin", '<nav class="cp-nav-movel" id="sbIrPara" aria-label="Navegação da Área de Membros"></nav>');
      caixa = el("sbIrPara");
    }
    caixa.innerHTML = `<button type="button" class="cp-ir-botao" id="sbIrBotao" aria-haspopup="dialog" aria-expanded="false" aria-controls="sbIrPainel">
      <span class="cp-ir-ico">${ico(atual)}</span><span class="cp-ir-txt"><span class="eyebrow">Ir para</span><b>${h(nomes[atual] || "Painel")}</b></span><span class="cp-ir-seta">${ico("seta")}</span></button>`;
    const grupos = GRUPOS.concat([["Outros", abas.map((a) => a[0]).filter((k) => grupoDe(k) === "Outros")]])
      .map(([g, ks]) => [g, ks.filter((k) => nomes[k])]).filter(([, ks]) => ks.length);
    const pend = painel.resumo?.solicitacoes_pendentes;
    let p = el("sbIrPainel");
    if (!p) {
      document.body.insertAdjacentHTML("beforeend", '<div class="cp-ir-fundo" id="sbIrFundo" hidden></div><div class="cp-ir-painel" id="sbIrPainel" role="dialog" aria-modal="true" aria-labelledby="sbIrTitulo" hidden></div>');
      p = el("sbIrPainel");
      el("sbIrFundo").addEventListener("click", () => fecharIrPara());
    }
    p.innerHTML = `<div class="cp-ir-cab"><h2 id="sbIrTitulo">Ir para</h2><button type="button" class="cp-ir-fechar" data-sb="irFechar" aria-label="Fechar menu">${ico("fechar", 22)}</button></div>
      <div class="cp-ir-lista">${grupos.map(([g, ks]) => `<div class="cp-ir-grupo" role="group" aria-label="${h(g)}"><span class="eyebrow">${h(g)}</span>${ks.map((k) => `<button type="button" class="cp-ir-item" data-sb="irAba:${k}"${k === atual ? ' aria-current="page"' : ""}><span class="cp-ir-ico">${ico(k)}</span><span class="cp-ir-nome">${h(nomes[k])}</span>${k === "solicitacoes" && pend ? `<span class="sbCont">${h(pend)}</span>` : ""}${k === "avisos" ? '<span class="sbCont" data-ir-avisos hidden></span>' : ""}</button>`).join("")}</div>`).join("")}</div>
      <div class="cp-ir-rodape"><button type="button" class="btn btn-s" data-sb="sair">${ico("sair", 18)} Sair da conta</button></div>`;
  }
  function abrirIrPara() {
    const p = el("sbIrPainel"), f = el("sbIrFundo"), b = el("sbIrBotao"); if (!p) return;
    p.hidden = false; f.hidden = false; document.body.classList.add("cp-travado");
    requestAnimationFrame(() => { p.classList.add("on"); f.classList.add("on"); });
    b?.setAttribute("aria-expanded", "true");
    (p.querySelector('[aria-current="page"]') || p.querySelector(".cp-ir-item"))?.focus({ preventScroll: true });
  }
  function fecharIrPara(devolverFoco = true) {
    const p = el("sbIrPainel"), f = el("sbIrFundo"), b = el("sbIrBotao"); if (!p || p.hidden) return;
    p.classList.remove("on"); f.classList.remove("on"); document.body.classList.remove("cp-travado");
    b?.setAttribute("aria-expanded", "false");
    setTimeout(() => { p.hidden = true; f.hidden = true; }, 200);
    if (devolverFoco) b?.focus({ preventScroll: true });
  }
  document.addEventListener("keydown", (ev) => {
    if (ev.key !== "Escape") return;
    if (el("sbIrPainel") && !el("sbIrPainel").hidden) { ev.preventDefault(); fecharIrPara(); }
    if (el("cpUsuarioMenu") && !el("cpUsuarioMenu").hidden) { ev.preventDefault(); fecharUsuario(true); }
  });
  // mantém o foco dentro do menu aberto (teclado)
  document.addEventListener("keydown", (ev) => {
    const p = el("sbIrPainel"); if (ev.key !== "Tab" || !p || p.hidden) return;
    const foc = [...p.querySelectorAll("button")]; if (!foc.length) return;
    const [a, z] = [foc[0], foc[foc.length - 1]];
    if (ev.shiftKey && document.activeElement === a) { ev.preventDefault(); z.focus(); }
    else if (!ev.shiftKey && document.activeElement === z) { ev.preventDefault(); a.focus(); }
  });

  /* ---------- quem está conectado (cabeçalho do site) ---------- */
  const iniciais = (n) => { const p = String(n || "").trim().split(/\s+/).filter(Boolean); return ((p[0]?.[0] || "") + (p.length > 1 ? p[p.length - 1][0] : "")).toUpperCase() || "?"; };
  let cabNome = null, cabBusca = null, cabFoto = undefined;
  async function atualizarUsuario(forcar) {
    const c = el("cpUsuario"); if (!c) return;
    if (!sessao) { cabNome = null; cabFoto = undefined; c.hidden = true; c.innerHTML = ""; c.dataset.chave = ""; return; }
    if (cabFoto === undefined && painel?.status === "ok") { cabFoto = null; sb.rpc("meu_perfil").then(({ data }) => { if (data && sessao) { cabFoto = data.foto || null; atualizarUsuario(true); } }).catch(() => {}); }
    if (painel?.nome) cabNome = { nome: painel.nome, perfil: painel.status === "ok" ? PERFIL[painel.perfil] : "" };
    else if (!cabNome && !cabBusca) {
      cabBusca = sb.rpc("meu_painel").then(({ data }) => { if (data?.nome && sessao) cabNome = { nome: data.nome, perfil: data.status === "ok" ? PERFIL[data.perfil] : "" }; }).catch(() => {}).finally(() => { cabBusca = null; atualizarUsuario(); });
    }
    const n = cabNome?.nome || sessao.user?.email || "", chave = n + "|" + (cabNome?.perfil || "") + "|" + (cabFoto || "");
    if (!forcar && !c.hidden && c.dataset.chave === chave) return;   // nada mudou (ex.: renovação do token)
    c.hidden = false; c.dataset.chave = chave;
    c.innerHTML = `<button type="button" class="cp-usuario-botao" id="cpUsuarioBotao" aria-haspopup="menu" aria-expanded="false" aria-controls="cpUsuarioMenu" aria-label="Conta de ${h(n)} (conectado)">
        <span class="cp-avatar" aria-hidden="true">${cabFoto ? `<img src="${h(urlFotoPerfil(cabFoto))}" alt="">` : h(iniciais(cabNome?.nome || n))}</span><span class="cp-usuario-nome">${h(primeiro(cabNome?.nome) || "Minha conta")}</span>${ico("seta", 16)}</button>
      <div class="cp-usuario-menu" id="cpUsuarioMenu" role="menu" hidden>
        <div class="cp-usuario-cab"><b>${h(n)}</b><small>Conectado${cabNome?.perfil ? " · " + h(cabNome.perfil) : ""}</small></div>
        <a href="#equipe" role="menuitem" data-sb-usuario="painel">${ico("painel", 18)} Área de Membros</a>
        <a href="#equipe/conta" role="menuitem" data-sb-usuario="perfil">${ico("conta", 18)} Meu perfil</a>
        <button type="button" role="menuitem" data-sb="sair">${ico("sair", 18)} Sair</button>
      </div>`;
  }
  function fecharUsuario(foco) {
    const m = el("cpUsuarioMenu"); if (!m || m.hidden) return;
    m.hidden = true; el("cpUsuarioBotao")?.setAttribute("aria-expanded", "false"); if (foco) el("cpUsuarioBotao")?.focus();
  }
  document.addEventListener("click", (ev) => {
    const bt = ev.target.closest("#cpUsuarioBotao"), m = el("cpUsuarioMenu");
    if (bt && m) { const abrir = m.hidden; m.hidden = !abrir; bt.setAttribute("aria-expanded", String(abrir)); if (abrir) m.querySelector("a,button")?.focus(); return; }
    if (m && !m.hidden && (!ev.target.closest("#cpUsuarioMenu") || ev.target.closest("a,button"))) fecharUsuario(false);
  });

  async function renderPainelInterno(sub) {
    const permitidas = abasPermitidas().map((a) => a[0]);
    const aba = permitidas.includes(sub) ? sub : "painel";
    if (sub && sub !== aba) { history.replaceState(null, "", "#equipe"); }
    const t = { MASTER: "Área de <em>Membros</em>.", LIDER: "<em>Liderança</em>.", VOLUNTARIO: "Área do <em>voluntário</em>." }[painel.perfil];
    topo(t, `Olá, ${primeiro(painel.nome)}. ${painel.perfil === "MASTER" ? "Você administra os acessos, os ministérios e o histórico da Área de Membros." : painel.perfil === "LIDER" ? "Aqui você acompanha os ministérios que lidera e a sua equipe." : "Aqui você acompanha os ministérios em que serve."}`);
    el("sbTela").innerHTML = ""; el("sbPainel").hidden = false; barra(); renderAbas(aba); contarAvisos();
    const c = el("sbConteudo");
    c.innerHTML = '<p class="msg">Carregando…</p>';
    try {
      if (aba === "painel") return renderInicio(c);
      if (aba === "solicitacoes") return await renderSolicitacoes(c);
      if (aba === "usuarios") return await renderUsuarios(c);
      if (aba === "ministerios") {
        if (!window.BetelInstitucional) return await renderMinisterios(c);
        if (painel.perfil !== "MASTER") return await window.BetelInstitucional.ministerios(c, { sb, inst: painel.inst });
        // MASTER: cadastro (nome, ordem, situação) + página, liderança, integrantes e histórico de cada ministério
        c.innerHTML = '<div class="stack"><section><p class="eyebrow">Cadastro</p><div id="sbMinCad"></div></section><section><p class="eyebrow">Página, liderança e integrantes</p><div id="sbMinInst"></div></section></div>';
        await renderMinisterios(el("sbMinCad"));
        return await window.BetelInstitucional.ministerios(el("sbMinInst"), { sb, inst: painel.inst, semCadastro: true });
      }
      if (aba === "organogramas") return await window.BetelInstitucional.organogramas(c, { sb, inst: painel.inst });
      if (aba === "site") return await window.BetelInstitucional.site(c, { sb, inst: painel.inst });
      if (aba === "agenda-links") return await window.BetelInstitucional.agendaLinks(c, { sb, inst: painel.inst });
      if (aba === "historico") return await renderHistorico(c, true);
      if (aba === "equipe") return await renderEquipe(c);
      if (aba === "agenda") return await renderAgenda(c);
      if (aba === "cursos") return await window.BetelCursosAdmin.render(c, { sb });
      if (aba === "secretaria") return await window.BetelSecretaria.render(c, { sb });
      if (aba === "tesouraria") return await window.BetelTesouraria.render(c, { sb });
      if (aba === "avisos") return await renderAvisos(c);
      if (aba === "membresia") return await window.BetelMembresia.render(c, { sb });
      if (aba === "candidatos") return await window.BetelCandidatos.render(c, { sb });
      if (aba === "turmas") return await window.BetelTurmasLider.render(c, { sb });
      if (aba === "midia") return await window.BetelMidia.lider(c, { sb });
      if (aba === "solicitar-midia") return await window.BetelMidia.solicitar(c, { sb });
      if (aba === "escalas") return await window.BetelMidia.voluntario(c, { sb });
      if (aba === "imagem") return window.BetelImagemMidia.render(c, { sb });
      if (aba === "conta") return await renderConta(c);
    } catch (err) { c.innerHTML = `<p class="notice">${h(err.message)}</p>`; }
  }
  function chipsMinisterios(lista) {
    return (lista || []).length ? `<div class="chips">${lista.map((m) => `<span${m.funcao === "lider" ? ' class="me"' : ""}>${h(m.nome)} · ${h(FUNCAO[m.funcao])}</span>`).join("")}</div>` : '<p class="m" style="margin-top:8px">Nenhum ministério vinculado.</p>';
  }
  function renderInicio(c) {
    const r = painel.resumo;
    c.innerHTML = `<div class="stack">
      ${r ? `<div class="week" style="margin-top:0">
        <button class="wk glass sbKpi" type="button" data-sb="aba:solicitacoes"><span class="dia">Solicitações pendentes</span><span class="hr">${h(r.solicitacoes_pendentes)}</span><small>Pedidos de acesso aguardando a sua análise.</small></button>
        <button class="wk glass sbKpi" type="button" data-sb="aba:usuarios"><span class="dia">Usuários ativos</span><span class="hr">${h(r.usuarios_ativos)}</span><small>Contas com acesso à Área de Membros.</small></button>
        <button class="wk glass sbKpi" type="button" data-sb="aba:ministerios"><span class="dia">Ministérios ativos</span><span class="hr">${h(r.ministerios_ativos)}</span><small>Ministérios disponíveis para vínculo.</small></button>
      </div>` : ""}
      <div class="card glass">
        <p class="eyebrow">Seu acesso</p><h3>${h(painel.nome)}</h3>
        <p class="m" style="font:400 13px/1.6 var(--mono);color:var(--suave)">${h(PERFIL[painel.perfil])}${(painel.atribuicoes || []).length ? " · " + h(painel.atribuicoes.map((a) => ATRIB[a]).join(", ")) : ""} · ${h(painel.email)}</p>
        ${chipsMinisterios(painel.ministerios)}
      </div>
      <p class="notice">A Agenda Ministerial já usa este login. Escalas, inscrições, cursos, secretaria e tesouraria serão ligados a esta área nas próximas etapas.</p>
    </div>`;
  }

  /* --- Avisos (notificações da Secretaria e da Tesouraria) --- */
  async function renderAvisos(c) {
    const r = await rpc("minhas_notificacoes", { p_limite: 100 });
    c.innerHTML = `<div class="toolbar"><span class="msg">${r.nao_lidas} não lido(s)</span>${r.nao_lidas ? '<button class="mini sm" type="button" data-sb="lerAvisos">Marcar todos como lidos</button>' : ""}</div>
      <div class="glass list">${r.itens.length ? r.itens.map((n) => `<div class="row"><div><p class="n cp-item-titulo">${h(n.titulo)}${n.lida ? "" : '<span class="st novo">Novo</span>'}<span class="st" style="margin-left:6px">${h(n.para === "TESOURARIA" ? "Tesouraria" : n.para === "SECRETARIA" ? "Secretaria" : "Para você")}</span></p><p class="m">${h(n.mensagem || "")} · ${h(dataHora(n.criado_em))}</p></div></div>`).join("") : '<p class="empty cp-vazio">Nenhum aviso.</p>'}</div>`;
    c.dataset.avisos = JSON.stringify(r.itens.filter((n) => !n.lida).map((n) => n.id));
  }
  async function contarAvisos() {
    if (!painel || painel.status !== "ok") return;
    const { data } = await sb.rpc("minhas_notificacoes", { p_limite: 1 });
    const b = document.querySelector('#sbAbas [data-sb="aba:avisos"]');
    if (b && data) b.innerHTML = "Avisos" + (data.nao_lidas ? ` <span class="sbCont">${h(data.nao_lidas)}</span>` : "");
    const m = document.querySelector("[data-ir-avisos]");
    if (m && data) { m.hidden = !data.nao_lidas; m.textContent = data.nao_lidas || ""; }
  }

  /* --- Agenda Ministerial (mesma conta; permissões conferidas no banco) --- */
  async function renderAgenda(c) {
    const p = await rpc("agenda_minhas_permissoes");
    const mins = (p.ministerios_lider || []).map((m) => m.nome);
    const papel = p.coordenador ? "Você está na <b>coordenação</b>: cria, move e exclui eventos, reserva o Templo, o Salão de Festas e a Quadra (inclusive em série), tranca e destranca fichas."
      : mins.length ? `Você preenche as <b>fichas oficiais</b> dos eventos de: <b>${h(mins.join(", "))}</b>. Ficha trancada ou de evento que já passou: só os links de fotos e vídeos.`
      : "Você consulta o calendário, as fichas e as reservas.";
    c.innerHTML = `<div class="card glass" style="max-width:760px"><p class="eyebrow">Agenda Ministerial</p><h3>Calendário, fichas e reservas</h3>
      <p style="color:var(--suave);font-size:15px">${papel} Você entra na Agenda com esta mesma conta, sem outra senha.</p>
      ${p.master ? '<p class="notice">Como MASTER, você também define quem é coordenador em "Gestão de Coordenadores", dentro da Agenda.</p>' : ""}
      <div><a class="btn btn-p" href="agenda-ministerial/">Abrir a Agenda Ministerial</a></div></div>`;
  }

  /* --- Minha equipe (LÍDER e VOLUNTÁRIO) --- */
  async function renderEquipe(c) {
    const lista = await rpc("minha_equipe");
    c.innerHTML = lista.length ? `<div class="stack">${lista.map((g) => `<div class="glass list">
      <div class="row"><div><p class="n">${h(g.ministerio)}${g.sou_lider ? '<span class="st novo">Você lidera</span>' : ""}</p><p class="m">${h(g.membros.length)} ${g.membros.length === 1 ? "pessoa" : "pessoas"}</p></div></div>
      ${g.membros.map((m) => `<div class="row"><div><p class="n cp-item-titulo">${h(m.nome)}<span class="st ${m.funcao === "lider" ? "ok" : ""}">${h(FUNCAO[m.funcao])}</span></p>${g.sou_lider ? `<p class="m">${h(fone(m.telefone) || "Sem telefone")} · ${h(m.email || "")}</p>` : ""}</div>
        ${g.sou_lider && m.telefone ? `<div class="acts"><a class="mini sm wa" href="https://wa.me/55${h(String(m.telefone).replace(/^55/, ""))}" target="_blank" rel="noopener">WhatsApp</a></div>` : ""}</div>`).join("")}
    </div>`).join("")}</div>` : '<p class="empty">Você ainda não está vinculado a nenhum ministério. Fale com o responsável pela Área de Membros.</p>';
  }

  /* --- Solicitações (MASTER) --- */
  async function carregarMinisterios() {
    const { data, error } = await sb.from("ministerios").select("id,nome,descricao,ordem,ativo").order("ordem");
    if (error) throw new Error(error.message); ministerios = data;
  }
  function editorVinculos(id, sel) {
    const m = new Map((sel || []).map((v) => [v.ministerio_id, v.funcao]));
    return `<div class="sbMins" id="${id}">${ministerios.filter((x) => x.ativo || m.has(x.id)).map((x) => `<div class="sbMin"><label><input type="checkbox" value="${h(x.id)}"${m.has(x.id) ? " checked" : ""}> ${h(x.nome)}</label><select aria-label="Função em ${h(x.nome)}"><option value="voluntario"${m.get(x.id) !== "lider" ? " selected" : ""}>Voluntário</option><option value="lider"${m.get(x.id) === "lider" ? " selected" : ""}>Líder</option></select></div>`).join("")}</div>`;
  }
  function lerVinculos(id) {
    return [...el(id).querySelectorAll(".sbMin")].filter((d) => d.querySelector("input").checked).map((d) => ({ ministerio_id: d.querySelector("input").value, funcao: d.querySelector("select").value }));
  }
  function campoPerfil(id, valor) {
    return `<label>Perfil<select id="${id}">${["VOLUNTARIO", "LIDER", "MASTER"].map((p) => `<option value="${p}"${p === valor ? " selected" : ""}>${h(PERFIL[p])}</option>`).join("")}</select></label>`;
  }
  function campoAtrib(id, sel) {
    return `<div><p style="font-weight:600;font-size:14px;margin-bottom:8px">Atribuições extras</p><div class="deps" id="${id}">${Object.entries(ATRIB).map(([k, n]) => `<label><input type="checkbox" value="${k}"${(sel || []).includes(k) ? " checked" : ""}> ${h(n)}</label>`).join("")}</div></div>`;
  }
  const lerAtrib = (id) => [...el(id).querySelectorAll("input:checked")].map((i) => i.value);
  function caixaSenha(r, titulo) {
    const msg = `Olá, ${primeiro(r.nome || "")}! Seu acesso à Área de Membros da Igreja Batista Betel foi liberado. Entre em ${location.origin}${location.pathname}#equipe com o e-mail ${r.email} e a senha temporária ${r.senha_temporaria}. No primeiro acesso, você vai criar a sua própria senha.`;
    const tel = String(r.telefone || "").replace(/\D/g, "");
    return `<div class="done" role="status"><p class="eyebrow">${h(titulo)}</p>
      <p><b>${h(r.nome || r.email)}</b> · ${h(r.email)}</p>
      <p>Senha temporária: <b class="sbSenhaTemp">${h(r.senha_temporaria)}</b></p>
      <p style="font-size:14px;color:var(--suave)">Ela aparece só agora. Envie à pessoa por um canal privado. No primeiro acesso, o sistema exige a troca.</p>
      <div class="cp-acoes"><button class="btn btn-s sm" type="button" data-sb-copiar="${h(r.senha_temporaria)}">Copiar senha</button>${tel ? `<a class="btn btn-p sm wa" href="https://wa.me/55${h(tel.replace(/^55/, ""))}?text=${encodeURIComponent(msg)}" target="_blank" rel="noopener">Enviar pelo WhatsApp</a>` : ""}</div></div>`;
  }
  async function renderSolicitacoes(c) {
    await carregarMinisterios();
    solicitacoes = await rpc("listar_solicitacoes", { p_status: filtroSol });
    const filtros = [["pendente", "Pendentes"], ["aprovada", "Aprovadas"], ["recusada", "Recusadas"]];
    c.innerHTML = `<div class="toolbar">${filtros.map(([k, n]) => `<button class="mini sm" type="button" data-sb="filtroSol:${k}" aria-pressed="${k === filtroSol}"${k === filtroSol ? ' data-ativo=""' : ""}>${n}</button>`).join("")}</div>
      <div class="glass list">${solicitacoes.length ? solicitacoes.map((s) => `<div class="sbItem" id="sol-${h(s.id)}"><div class="row"><div>
        <p class="n">${h(s.nome)}<span class="st ${s.status === "pendente" ? "novo" : s.status === "aprovada" ? "ok" : ""}">${h({ pendente: "Pendente", aprovada: "Aprovada", recusada: "Recusada" }[s.status])}</span></p>
        <p class="m">${h(s.ministerio || "—")} · ${h(FUNCAO[s.funcao] || s.funcao)} · ${h(fone(s.telefone))} · ${h(s.email)}</p>
        <p class="m">Pedido em ${h(dataHora(s.criado_em))}${s.analisado_em ? ` · analisado em ${h(dataHora(s.analisado_em))} por ${h(s.analisado_por || "—")}` : ""}${s.motivo ? ` · motivo: ${h(s.motivo)}` : ""}</p></div>
        ${s.status === "pendente" ? `<div class="acts"><button class="btn btn-p sm" type="button" data-sb="aprovarForm:${h(s.id)}">Aprovar</button><button class="mini sm" type="button" data-sb="recusarForm:${h(s.id)}">Recusar</button></div>` : ""}
      </div><div class="sbExtra"></div></div>`).join("") : `<p class="empty cp-vazio">Nenhuma solicitação ${h({ pendente: "pendente", aprovada: "aprovada", recusada: "recusada" }[filtroSol])}.</p>`}</div>`;
  }
  function formAprovar(id) {
    const s = solicitacoes.find((x) => x.id === id); if (!s) return;
    const box = el("sol-" + id).querySelector(".sbExtra");
    box.innerHTML = `<form class="formcard sbSub" data-aprovar="${h(id)}" novalidate>
      <p style="color:var(--suave);font-size:15px">Confira o perfil e os ministérios antes de liberar. A pessoa pediu: <b>${h(FUNCAO[s.funcao])}</b> em <b>${h(s.ministerio)}</b>.</p>
      <div class="formgrid">${campoPerfil("apPerfil-" + id, s.funcao === "lider" ? "LIDER" : "VOLUNTARIO")}${campoAtrib("apAtr-" + id, [])}</div>
      <p style="font-weight:600;font-size:14px">Ministérios</p>${editorVinculos("apMin-" + id, [{ ministerio_id: s.ministerio_id, funcao: s.funcao }])}
      <div class="cp-acoes"><button class="btn btn-p sm" type="submit">Confirmar e criar acesso</button><button class="btn btn-s sm" type="button" data-sb="fecharExtra">Cancelar</button></div>
      <span class="msg" role="status"></span></form>`;
  }
  function formRecusar(id) {
    const box = el("sol-" + id).querySelector(".sbExtra");
    box.innerHTML = `<form class="formcard sbSub" data-recusar="${h(id)}" novalidate>
      <label>Motivo da recusa<input maxlength="500" required placeholder="Ex.: não identificamos a pessoa no ministério informado"></label>
      <div class="cp-acoes"><button class="btn btn-p sm" type="submit">Confirmar recusa</button><button class="btn btn-s sm" type="button" data-sb="fecharExtra">Cancelar</button></div>
      <span class="msg" role="status"></span></form>`;
  }

  /* --- Usuários (MASTER) --- */
  async function renderUsuarios(c) {
    await carregarMinisterios();
    usuarios = await rpc("listar_usuarios");
    c.innerHTML = `<div class="stack">
      <div class="toolbar"><button class="btn btn-p sm" type="button" data-sb="novoUsuario">Novo usuário</button><span class="msg">${h(usuarios.filter((u) => u.ativo).length)} ativos · ${h(usuarios.filter((u) => !u.ativo).length)} inativos</span></div>
      <div id="sbNovo"></div>
      <div class="glass list">${usuarios.map((u) => `<div class="sbItem" id="usr-${h(u.id)}"><div class="row"><div>
        <p class="n">${h(u.nome)}${u.eu ? " (você)" : ""}<span class="st ${u.ativo ? "ok" : ""}">${h(PERFIL[u.perfil])}</span>${(u.atribuicoes || []).map((a) => `<span class="st" style="margin-left:6px">${h(ATRIB[a])}</span>`).join("")}${!u.ativo ? '<span class="badge" style="margin-left:8px">Inativo</span>' : u.deve_trocar_senha ? '<span class="st novo" style="margin-left:6px">Senha temporária</span>' : ""}</p>
        <p class="m">${h(u.email)} · ${h(fone(u.telefone) || "sem telefone")}</p>${chipsMinisterios(u.ministerios)}</div>
        <div class="acts"><button class="mini sm" type="button" data-sb="editarUsuario:${h(u.id)}">Editar acesso</button>${!u.eu ? `<button class="mini sm" type="button" data-sb="senhaTemp:${h(u.id)}">Nova senha temporária</button><button class="mini sm" type="button" data-sb="ativo:${h(u.id)}:${u.ativo ? "0" : "1"}">${u.ativo ? "Desativar" : "Reativar"}</button>` : ""}</div>
      </div><div class="sbExtra"></div></div>`).join("")}</div></div>`;
  }
  function formNovoUsuario() {
    el("sbNovo").innerHTML = `<form class="formcard glass" id="sbFormNovo" novalidate><h3>Novo usuário</h3>
      <div class="formgrid"><label class="cp-full">Nome completo<input id="nuNome" required maxlength="120"></label>
      <label>Telefone<input id="nuTel" required inputmode="tel" maxlength="20"></label><label>E-mail<input id="nuEmail" type="email" required maxlength="120"></label>
      ${campoPerfil("nuPerfil", "VOLUNTARIO")}${campoAtrib("nuAtr", [])}</div>
      <p style="font-weight:600;font-size:14px">Ministérios</p>${editorVinculos("nuMin", [])}
      <div class="cp-acoes"><button class="btn btn-p sm" type="submit">Criar usuário</button><button class="btn btn-s sm" type="button" data-sb="fecharNovo">Cancelar</button></div>
      <span class="msg" role="status"></span></form>`;
  }
  function formEditarUsuario(id) {
    const u = usuarios.find((x) => x.id === id); if (!u) return;
    el("usr-" + id).querySelector(".sbExtra").innerHTML = `<form class="formcard sbSub" data-editar="${h(id)}" novalidate>
      <div class="formgrid">${campoPerfil("edPerfil-" + id, u.perfil)}${campoAtrib("edAtr-" + id, u.atribuicoes)}</div>
      <p style="font-weight:600;font-size:14px">Ministérios</p>${editorVinculos("edMin-" + id, u.ministerios)}
      <div class="cp-acoes"><button class="btn btn-p sm" type="submit">Salvar alterações</button><button class="btn btn-s sm" type="button" data-sb="fecharExtra">Cancelar</button></div>
      <span class="msg" role="status"></span></form>`;
  }

  /* --- Ministérios (MASTER) --- */
  async function renderMinisterios(c) {
    await carregarMinisterios();
    c.innerHTML = `<div class="two">
      <form class="formcard glass" id="sbFormMin" novalidate><h3 id="fmTitulo">Novo ministério</h3><input type="hidden" id="fmId">
        <label>Nome<input id="fmNome" required maxlength="80"></label>
        <label>Descrição<textarea id="fmDesc" maxlength="600" rows="3"></textarea></label>
        <div class="formgrid"><label>Ordem na lista<input id="fmOrdem" type="number" min="0" max="999" value="${h(ministerios.length + 1)}"></label>
        <label>Situação<select id="fmAtivo"><option value="1">Ativo</option><option value="0">Inativo</option></select></label></div>
        <div class="cp-acoes"><button class="btn btn-p" type="submit">Salvar ministério</button><button class="btn btn-s" type="button" data-sb="limparMin">Limpar</button></div>
        <span class="msg" id="fmMsg" role="status"></span></form>
      <div class="glass list">${ministerios.map((m) => `<div class="row"><div><p class="n">${h(m.nome)}<span class="st ${m.ativo ? "ok" : ""}">${m.ativo ? "Ativo" : "Inativo"}</span></p><p class="m">Ordem ${h(m.ordem)}${m.descricao ? " · " + h(m.descricao) : ""}</p></div><div class="acts"><button class="mini sm" type="button" data-sb="editarMin:${h(m.id)}">Editar</button></div></div>`).join("")}</div>
    </div>`;
  }

  /* --- Histórico (MASTER) --- */
  const CAMPOS = { perfil: "perfil", atribuicoes: "atribuições", ativo: "situação", deve_trocar_senha: "senha temporária", nome: "nome", descricao: "descrição", ordem: "ordem", funcao: "função", status: "situação", telefone: "telefone", email: "e-mail", usuario_id: "conta de acesso", senha_alterada_em: "senha" };
  const TABELA = { perfis: "Acesso", pessoas: "Cadastro de pessoa", ministerios: "Ministério", ministerio_membros: "Vínculo com ministério", solicitacoes: "Solicitação de acesso", configuracoes: "Configuração" };
  function descrever(a) {
    const d = a.detalhes || {};
    if (a.acao === "solicitacao_aprovada") return `Aprovou a solicitação e criou o acesso de ${d.email} como ${PERFIL[d.perfil] || d.perfil}`;
    if (a.acao === "usuario_criado") return d.primeiro_master ? `Conta MASTER inicial criada para ${d.email}` : `Criou o usuário ${d.email} como ${PERFIL[d.perfil] || d.perfil}`;
    if (a.acao === "senha_temporaria_gerada") return `Gerou nova senha temporária para ${a.alvo || "um usuário"}`;
    const nome = a.alvo || "";
    if (a.acao === "insert") return `${TABELA[a.tabela] || a.tabela} criado: ${nome}`;
    if (a.acao === "delete") return `${TABELA[a.tabela] || a.tabela} excluído: ${nome}`;
    const antes = a.antes || {}, depois = a.depois || {};
    if (a.tabela === "perfis" && antes.deve_trocar_senha && !depois.deve_trocar_senha) return `${nome} trocou a senha temporária`;
    if (a.tabela === "perfis" && antes.ativo !== depois.ativo) return `${depois.ativo ? "Reativou" : "Desativou"} o acesso de ${nome}`;
    if (a.tabela === "solicitacoes" && depois.status === "recusada") return `Recusou a solicitação de ${nome}${depois.motivo ? " (" + depois.motivo + ")" : ""}`;
    if (a.tabela === "solicitacoes" && antes.status === "pendente" && depois.status === "aprovada") return `Solicitação de ${nome} marcada como aprovada`;
    const mud = Object.keys(depois).filter((k) => !["atualizado_em", "id"].includes(k) && JSON.stringify(antes[k]) !== JSON.stringify(depois[k]));
    const det = mud.map((k) => (["perfil", "funcao", "status", "nome", "ordem"].includes(k) ? `${CAMPOS[k] || k}: ${antes[k] ?? "—"} → ${depois[k] ?? "—"}` : k === "atribuicoes" ? `atribuições: ${(antes[k] || []).join(", ") || "nenhuma"} → ${(depois[k] || []).join(", ") || "nenhuma"}` : k === "ativo" ? `situação: ${depois[k] ? "ativo" : "inativo"}` : CAMPOS[k] || k)).join("; ");
    return `${TABELA[a.tabela] || a.tabela} alterado: ${nome}${det ? " — " + det : ""}`;
  }
  const principal = (a) => !["insert"].includes(a.acao) && !(a.tabela === "solicitacoes" && a.depois?.status === "aprovada") && !(a.tabela === "pessoas" && a.acao === "update");
  async function renderHistorico(c, reiniciar) {
    if (reiniciar) historico = await rpc("listar_auditoria", { p_limite: 100 });
    const lista = filtroHist === "principais" ? historico.filter(principal) : historico;
    c.innerHTML = `<div class="toolbar"><label style="flex-direction:row;align-items:center;gap:10px">Mostrar<select id="sbFiltroHist"><option value="principais"${filtroHist === "principais" ? " selected" : ""}>Ações principais</option><option value="tudo"${filtroHist === "tudo" ? " selected" : ""}>Tudo (inclui registros técnicos)</option></select></label><span class="msg">O histórico não pode ser alterado nem apagado.</span></div>
      <div class="glass list">${lista.length ? lista.map((a) => `<div class="row"><div><p class="n" style="font-size:15.5px;font-weight:600">${h(descrever(a))}</p><p class="m">${h(dataHora(a.quando))} · por ${h(a.ator)}</p></div></div>`).join("") : '<p class="empty cp-vazio">Nada registrado ainda.</p>'}</div>
      ${historico.length >= 100 ? '<div style="margin-top:14px"><button class="btn btn-s sm" type="button" data-sb="maisHist">Carregar mais</button></div>' : ""}`;
  }

  /* --- Minha conta --- */
  async function renderConta(c) {
    const p = await rpc("meu_perfil");
    const data = (d) => (d ? new Date(String(d).length <= 10 ? d + "T12:00:00" : d).toLocaleDateString("pt-BR") : "");
    const linha = (rot, val, nota) => `<div class="row"><div><p class="m">${h(rot)}</p><p class="n cp-item-titulo">${val ? h(val) : '<span class="cp-suave">Não informado</span>'}</p>${nota ? `<p class="m">${h(nota)}</p>` : ""}</div></div>`;
    const acesso = h(PERFIL[p.perfil] || p.perfil) + ((p.atribuicoes || []).length ? " + " + h(p.atribuicoes.map((a) => ATRIB[a]).join(", ")) : "");
    c.innerHTML = `<div class="stack">
      <div class="card glass cp-perfil-cab" style="flex-direction:row;align-items:center;gap:18px;flex-wrap:wrap">
        <span class="cp-avatar" id="mpAvatar" style="width:72px;height:72px;font-size:26px" aria-hidden="true">${p.foto ? `<img src="${h(urlFotoPerfil(p.foto))}" alt="">` : h(iniciais(p.nome))}</span>
        <div style="flex:1;min-width:200px"><p class="eyebrow">Meu perfil</p><h3 style="overflow-wrap:anywhere">${h(p.nome)}</h3><p class="cp-suave" style="font-size:15px">${acesso}</p></div>
      </div>
      <div class="two">
        <div class="glass list"><p class="eyebrow" style="padding:18px 22px 0">Meus dados</p>
          ${linha("Nome completo", p.nome)}
          ${linha("E-mail (usado no login)", p.email)}
          ${linha("Telefone (WhatsApp)", fone(p.telefone))}
          ${linha("Perfil de acesso", PERFIL[p.perfil] + ((p.atribuicoes || []).length ? " + " + p.atribuicoes.map((a) => ATRIB[a]).join(", ") : ""), "Definido pelo responsável pela Área de Membros.")}
          <div class="row"><div><p class="m">Ministérios</p>${(p.ministerios || []).length ? `<div class="chips">${p.ministerios.map((m) => `<span${m.funcao === "lider" ? ' class="me"' : ""}>${h(m.nome)} · ${h(FUNCAO[m.funcao])}${m.desde ? " · desde " + h(data(m.desde)) : ""}</span>`).join("")}</div>` : '<p class="n cp-suave">Nenhum ministério vinculado.</p>'}</div></div>
          ${linha("Cadastro", [p.conta_criada_em ? "Conta criada em " + data(p.conta_criada_em) : "", p.aprovado_em ? "acesso liberado em " + data(p.aprovado_em) : ""].filter(Boolean).join(" · "))}
          ${linha("Senha", p.senha_alterada_em ? "Alterada em " + dataHora(p.senha_alterada_em) : "")}
          <p class="notice" style="margin:4px 22px 22px">Nome, e-mail, perfil de acesso e ministérios só podem ser alterados pelo responsável pela Área de Membros. Para corrigir, fale com ele.</p>
        </div>
        <div class="stack">
          <form class="card glass" id="sbMinhaFoto" novalidate><p class="eyebrow">Você pode alterar</p><h3>Foto de perfil</h3>
            <div class="cp-foto-editor">
              <div class="cp-foto-quadro" id="mpQuadro" title="Arraste para enquadrar">${p.foto ? `<img src="${h(urlFotoPerfil(p.foto))}" alt="Sua foto atual" style="width:100%;height:100%;object-fit:cover">` : `<span class="cp-avatar" style="width:100%;height:100%;font-size:56px;box-shadow:none">${h(iniciais(p.nome))}</span>`}</div>
              <div class="cp-foto-ctrl">
                <label>Escolher foto (JPG, PNG ou WEBP)<input type="file" id="mpArquivo" accept="image/jpeg,image/png,image/webp"></label>
                <label id="mpZoomL" hidden>Aproximar<input type="range" id="mpZoom" min="1" max="3" step="0.01" value="1"></label>
                <p class="cp-suave" id="mpDica" style="font-size:13px" hidden>Arraste a foto no círculo para ajustar o enquadramento.</p>
                <label class="cuAceite cp-linha"><input class="cp-check" type="checkbox" id="mpOrg"${p.foto_no_organograma ? " checked" : ""}> Mostrar minha foto nos organogramas</label>
                <div class="cp-acoes"><button class="btn btn-p" type="submit" id="mpSalvarFoto" disabled>Salvar foto</button>${p.foto ? '<button class="btn btn-s" type="button" data-sb="removerFoto">Remover foto</button>' : ""}</div>
              </div></div>
            <p class="cp-suave" style="font-size:13px">A foto aparece no seu menu, no seu perfil e, se você autorizar, nos organogramas. Ela é reduzida no seu aparelho antes do envio.</p>
            <span class="msg" role="status"></span></form>
          <form class="card glass" id="sbMeuTel" novalidate><p class="eyebrow">Você pode alterar</p><h3>Telefone</h3>
            <label>Telefone (WhatsApp)<input id="mpTel" required inputmode="tel" maxlength="20" autocomplete="tel" placeholder="(31) 99999-9999" value="${h(fone(p.telefone))}"></label>
            <div class="cp-acoes"><button class="btn btn-p" type="submit" id="mpSalvar">Salvar telefone</button></div>
            <span class="msg" id="mpMsg" role="status"></span></form>
          <form class="card glass" id="sbTrocar" novalidate><p class="eyebrow">Segurança</p><h3>Trocar senha</h3>
            <label>Senha atual<input id="tcAtual" type="password" required autocomplete="current-password" maxlength="72"></label>
            <label>Nova senha<input id="tcNova" type="password" required minlength="10" maxlength="72" autocomplete="new-password"></label>
            <label>Confirme a nova senha<input id="tcConf" type="password" required minlength="10" maxlength="72" autocomplete="new-password"></label>
            <div class="cp-acoes"><button class="btn btn-p" type="submit" id="tcSalvar">Salvar nova senha</button><button class="btn btn-s" type="button" data-sb="naoSeiSenha">Não sei minha senha atual</button></div>
            <p class="cp-suave" style="font-size:13px">Por segurança, a senha atual nunca é exibida: ela fica guardada de forma irreversível. Ninguém, nem a administração, consegue vê-la.</p>
            <span class="msg" id="tcMsg" role="status"></span></form>
          <div class="card glass"><p class="eyebrow">Sessão</p><h3>Sair da conta</h3><p class="cp-suave" style="font-size:15px">Encerra o acesso neste aparelho. Para entrar de novo, use seu e-mail e senha.</p><div><button class="btn btn-s" type="button" data-sb="sair">${ico("sair", 18)} Sair da conta</button></div></div>
        </div>
      </div>
    </div>`;
  }

  /* ---------- foto de perfil: enquadramento no aparelho ---------- */
  const urlFotoPerfil = (f) => (f ? `${CFG.url}/storage/v1/object/public/perfis/${f}` : "");
  const FOTO = { img: null, zoom: 1, x: 0, y: 0, arrastando: null };
  function desenharFoto() {
    const q = el("mpQuadro"); if (!q || !FOTO.img) return;
    let cv = q.querySelector("canvas"); if (!cv) { q.innerHTML = '<canvas width="400" height="400" aria-label="Pré-visualização da foto"></canvas>'; cv = q.querySelector("canvas"); }
    const ctx = cv.getContext("2d"), I = FOTO.img, base = Math.max(400 / I.naturalWidth, 400 / I.naturalHeight) * FOTO.zoom;
    const w = I.naturalWidth * base, hh = I.naturalHeight * base;
    FOTO.x = Math.min(0, Math.max(400 - w, FOTO.x)); FOTO.y = Math.min(0, Math.max(400 - hh, FOTO.y));
    ctx.fillStyle = "#1c0909"; ctx.fillRect(0, 0, 400, 400); ctx.drawImage(I, FOTO.x, FOTO.y, w, hh);
  }
  document.addEventListener("change", async (ev) => {
    if (ev.target.id !== "mpArquivo") return;
    const arq = ev.target.files?.[0], msg = el("sbMinhaFoto").querySelector(".msg"); msg.textContent = "";
    if (!arq) return;
    if (!/^image\/(jpeg|png|webp)$/.test(arq.type)) { msg.textContent = "Escolha uma imagem JPG, PNG ou WEBP."; ev.target.value = ""; return; }
    if (arq.size > 15 * 1024 * 1024) { msg.textContent = "Imagem muito grande (máximo 15 MB)."; ev.target.value = ""; return; }
    const img = new Image(); img.onload = () => {
      const base = Math.max(400 / img.naturalWidth, 400 / img.naturalHeight);
      FOTO.img = img; FOTO.zoom = 1; FOTO.x = (400 - img.naturalWidth * base) / 2; FOTO.y = (400 - img.naturalHeight * base) / 2;
      el("mpZoom").value = "1"; el("mpZoomL").hidden = false; el("mpDica").hidden = false; el("mpSalvarFoto").disabled = false; desenharFoto();
    };
    img.onerror = () => { msg.textContent = "Não foi possível abrir essa imagem."; };
    img.src = URL.createObjectURL(arq);
  });
  document.addEventListener("input", (ev) => {
    if (ev.target.id !== "mpZoom" || !FOTO.img) return;
    const z = Number(ev.target.value), c = 200; // aproxima mantendo o centro
    const k = z / FOTO.zoom; FOTO.x = c - (c - FOTO.x) * k; FOTO.y = c - (c - FOTO.y) * k; FOTO.zoom = z; desenharFoto();
  });
  document.addEventListener("pointerdown", (ev) => {
    const q = ev.target.closest("#mpQuadro"); if (!q || !FOTO.img) return;
    ev.preventDefault(); q.setPointerCapture?.(ev.pointerId);
    const r = q.getBoundingClientRect(); FOTO.arrastando = { px: ev.clientX, py: ev.clientY, x: FOTO.x, y: FOTO.y, esc: 400 / r.width };
  });
  document.addEventListener("pointermove", (ev) => {
    const a = FOTO.arrastando; if (!a) return;
    FOTO.x = a.x + (ev.clientX - a.px) * a.esc; FOTO.y = a.y + (ev.clientY - a.py) * a.esc; desenharFoto();
  });
  document.addEventListener("pointerup", () => { FOTO.arrastando = null; });
  async function salvarFoto(f, msg) {
    const org = el("mpOrg").checked;
    if (!FOTO.img) { await rpc("meu_perfil_foto", { p_caminho: null, p_no_organograma: org }); msg.textContent = "Preferência salva."; return; }
    const cv = document.createElement("canvas"); cv.width = 512; cv.height = 512;
    const k = 512 / 400, I = FOTO.img, base = Math.max(400 / I.naturalWidth, 400 / I.naturalHeight) * FOTO.zoom;
    cv.getContext("2d").drawImage(I, FOTO.x * k, FOTO.y * k, I.naturalWidth * base * k, I.naturalHeight * base * k);
    const blob = await new Promise((ok) => cv.toBlob(ok, "image/jpeg", 0.86));
    const caminho = `${sessao.user.id}/${crypto.randomUUID()}.jpg`;
    msg.textContent = "Enviando…";
    const { error } = await sb.storage.from("perfis").upload(caminho, await blob.arrayBuffer(), { contentType: "image/jpeg", upsert: false });
    if (error) throw new Error(error.message || "Falha ao enviar a foto.");
    const r = await rpc("meu_perfil_foto", { p_caminho: caminho, p_no_organograma: org });
    FOTO.img = null; cabFoto = r.foto; if (painel) painel.foto = r.foto;
    el("sbConteudo") && renderPainelInterno("conta"); atualizarUsuario(true);
    window.BetelUI?.aviso("Foto de perfil atualizada.");
  }

  /* ---------- ciclo principal ---------- */
  async function render() {
    const sub = rotaAtual();
    if (sub === null) return; // fora da Área de Membros
    if (recuperando) return telaNovaSenha("Nova <em>senha</em>.", "Crie uma nova senha para a sua conta.", true);
    if (!sessao) {
      painel = null; el("sbBarra").hidden = true; el("sbConteudo").innerHTML = ""; el("sbAbas").innerHTML = ""; el("sbIrPara")?.remove();
      if (sub === "entrar") return telaLogin();
      if (sub === "solicitar") return telaSolicitar();
      if (sub === "esqueci") return telaEsqueci();
      if (sub) history.replaceState(null, "", "#equipe"); // rota protegida: exige login
      return telaInicial();
    }
    if (carregando) return;
    carregando = true;
    try { painel = await rpc("meu_painel"); }
    catch (err) { painel = null; el("sbTela").innerHTML = `<p class="notice">${h(err.message)}</p>`; return; }
    finally { carregando = false; }
    atualizarUsuario();
    if (painel.status === "trocar_senha") return telaNovaSenha("Primeiro <em>acesso</em>.", `Olá, ${primeiro(painel.nome)}. Antes de continuar, troque a senha temporária por uma senha só sua.`, false);
    if (painel.status === "inativo") return telaBloqueio("Acesso <em>desativado</em>.", "Esta conta está desativada. Se acha que é um engano, fale com o responsável pela Área de Membros.");
    if (painel.status !== "ok") return telaBloqueio("Acesso <em>pendente</em>.", "Sua conta ainda não tem um perfil liberado. Fale com o responsável pela Área de Membros.");
    // Mídia: quem pode montar escalas e quem pode solicitar apoio (conferido de novo no banco a cada ação)
    try { painel.inst = (await sb.rpc("institucional_permissoes", {})).data || {}; } catch (_) { painel.inst = {}; }
    if (window.BetelMidia) { try { const c = (await sb.rpc("midia_catalogo", {})).data; painel.midia = c ? { gestor: c.pode_escalar, lider: c.pode_gerir } : null; } catch (_) { painel.midia = null; } }
    if (["entrar", "solicitar", "esqueci"].includes(sub)) { history.replaceState(null, "", "#equipe"); return renderPainelInterno(""); }
    return renderPainelInterno(sub);
  }

  /* ---------- sair ---------- */
  // Apaga a tela interna, encerra a sessão no servidor e no aparelho e volta para uma página pública.
  function limparInterno() {
    fecharIrPara(false); fecharUsuario(false);
    el("sbConteudo").innerHTML = ""; el("sbAbas").innerHTML = ""; el("sbIrPara")?.remove(); el("sbIrPainel")?.remove(); el("sbIrFundo")?.remove();
    el("sbPainel").hidden = true; el("sbBarra").hidden = true; el("sbBarra").innerHTML = "";
    sessao = null; painel = null; cabNome = null; cabFoto = undefined; usuarios = []; solicitacoes = []; historico = [];
    atualizarUsuario();
  }
  async function sair(avisar) {
    saindo = true;
    const interna = rotaAtual() !== null;
    if (interna) history.replaceState(null, "", location.pathname + "#equipe");
    limparInterno(); el("sbTela").innerHTML = '<p class="msg">Saindo…</p>';
    try { await sb.auth.signOut({ scope: "local" }); } catch (_) {}
    try { localStorage.removeItem("betel-equipe"); } catch (_) {}
    saindo = false; recuperando = false; sessao = null;
    if (interna) render(); else el("sbTela").innerHTML = "";
    if (avisar) window.BetelUI?.aviso("Você saiu da sua conta.");
  }
  // Se a sessão acabar em outra aba, ou a página voltar do histórico do navegador, confere de novo
  async function conferirSessao() {
    const { data } = await sb.auth.getSession();
    if (!data.session && (sessao || !el("sbPainel").hidden)) { limparInterno(); if (rotaAtual() !== null) render(); }
  }
  window.addEventListener("pageshow", (ev) => { if (ev.persisted) conferirSessao(); });
  document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") conferirSessao(); });
  window.addEventListener("storage", (ev) => { if (ev.key === "betel-equipe" && !ev.newValue) conferirSessao(); });

  /* ---------- eventos ---------- */
  document.addEventListener("click", async (ev) => {
    if (ev.target.closest("#sbIrBotao")) return abrirIrPara();
    const cp = ev.target.closest("[data-sb-copiar]");
    if (cp) { try { await navigator.clipboard.writeText(cp.dataset.sbCopiar); cp.textContent = "Copiada"; } catch (_) { cp.textContent = "Copie manualmente"; } return; }
    const b = ev.target.closest("[data-sb]"); if (!b) return;
    const [acao, a1, a2] = b.dataset.sb.split(":");
    if (acao === "removerFoto") {
      if (b.dataset.confirmar !== "1") { b.dataset.confirmar = "1"; b.textContent = "Confirmar remoção"; return; }
      b.disabled = true;
      try { await rpc("meu_perfil_foto_remover", {}); cabFoto = null; renderPainelInterno("conta"); atualizarUsuario(true); window.BetelUI?.aviso("Foto removida."); }
      catch (err) { window.BetelUI?.erro(err.message); b.disabled = false; }
      return;
    }
    if (acao === "naoSeiSenha") {
      const email = sessao?.user?.email;
      if (CFG.recuperacaoPorEmail === false) { window.BetelUI?.aviso("A redefinição por e-mail ainda não está ativada. Peça ao responsável pela Área de Membros uma senha temporária."); return; }
      b.disabled = true;
      const { error } = await sb.auth.resetPasswordForEmail(email, { redirectTo: location.origin + location.pathname + "?redefinir=1" });
      b.disabled = false;
      window.BetelUI?.aviso(error ? "O envio por e-mail não está disponível agora. Peça ao responsável pela Área de Membros uma senha temporária." : `Enviamos um link de redefinição para ${email}.`);
      return;
    }
    if (acao === "irFechar") return fecharIrPara();
    if (acao === "irAba") { fecharIrPara(false); ir(a1 === "painel" ? "" : a1); return setTimeout(() => el("sbIrBotao")?.focus({ preventScroll: true }), 50); }
    if (acao === "ir") return ir(a1);
    if (acao === "aba") return ir(a1 === "painel" ? "" : a1);
    if (acao === "conta") return ir("conta");
    if (acao === "sair") { b.disabled = true; return sair(true); }
    if (acao === "filtroSol") { filtroSol = a1; return renderSolicitacoes(el("sbConteudo")).catch((e) => (el("sbConteudo").innerHTML = `<p class="notice">${h(e.message)}</p>`)); }
    if (acao === "aprovarForm") return formAprovar(a1);
    if (acao === "recusarForm") return formRecusar(a1);
    if (acao === "fecharExtra") { b.closest(".sbExtra").innerHTML = ""; return; }
    if (acao === "novoUsuario") return formNovoUsuario();
    if (acao === "fecharNovo") { el("sbNovo").innerHTML = ""; return; }
    if (acao === "editarUsuario") return formEditarUsuario(a1);
    if (acao === "senhaTemp" || acao === "ativo") {
      if (b.dataset.confirma !== "1") { b.dataset.confirma = "1"; b.textContent = acao === "senhaTemp" ? "Confirmar nova senha" : a2 === "0" ? "Confirmar desativação" : "Confirmar reativação"; return; }
      b.disabled = true; b.textContent = "Aguarde…";
      const box = el("usr-" + a1).querySelector(".sbExtra");
      try {
        if (acao === "senhaTemp") { const r = await funcao("admin-usuarios", { acao: "senha_temporaria", usuario_id: a1 }); const u = usuarios.find((x) => x.id === a1); box.innerHTML = caixaSenha({ ...r, nome: u?.nome, telefone: u?.telefone }, "Nova senha temporária"); b.textContent = "Senha gerada"; }
        else { await funcao("admin-usuarios", { acao: "definir_ativo", usuario_id: a1, ativo: a2 === "1" }); await renderUsuarios(el("sbConteudo")); }
      } catch (err) { box.innerHTML = `<p class="notice" style="margin:0 20px 18px">${h(err.message)}</p>`; b.disabled = false; b.textContent = "Tentar de novo"; delete b.dataset.confirma; }
      return;
    }
    if (acao === "editarMin") { const m = ministerios.find((x) => x.id === a1); if (!m) return; el("fmTitulo").textContent = "Editar ministério"; el("fmId").value = m.id; el("fmNome").value = m.nome; el("fmDesc").value = m.descricao || ""; el("fmOrdem").value = m.ordem; el("fmAtivo").value = m.ativo ? "1" : "0"; el("fmNome").focus(); return; }
    if (acao === "limparMin") { el("sbFormMin").reset(); el("fmId").value = ""; el("fmTitulo").textContent = "Novo ministério"; return; }
    if (acao === "lerAvisos") { await rpc("marcar_notificacoes_lidas", { p_ids: JSON.parse(el("sbConteudo").dataset.avisos || "[]") }); return renderPainelInterno("avisos"); }
    if (acao === "maisHist") { b.disabled = true; const ult = historico[historico.length - 1]; const mais = await rpc("listar_auditoria", { p_limite: 100, p_antes_de: ult.id }); historico = historico.concat(mais); return renderHistorico(el("sbConteudo"), false); }
  });
  document.addEventListener("change", (ev) => { if (ev.target.id === "sbFiltroHist") { filtroHist = ev.target.value; renderHistorico(el("sbConteudo"), false); } });

  document.addEventListener("submit", async (ev) => {
    const f = ev.target; const msg = f.querySelector(".msg");
    const botao = f.querySelector('[type="submit"]');
    const comBotao = async (fn) => { botao.disabled = true; try { await fn(); } finally { botao.disabled = false; } };

    if (f.id === "sbLogin") {
      ev.preventDefault();
      const email = el("sbEmail").value.trim().toLowerCase(), senha = el("sbSenha").value;
      if (!email || !senha) { msg.textContent = "Informe e-mail e senha."; return; }
      return comBotao(async () => {
        msg.textContent = "Entrando…";
        const { data, error } = await sb.auth.signInWithPassword({ email, password: senha });
        if (error) { msg.textContent = msgAuth(error); return; }
        ultimaSenha = senha; sessao = data.session; history.replaceState(null, "", "#equipe"); await render();
      });
    }
    if (f.id === "sbSolicitar") {
      ev.preventDefault();
      if (el("soSite").value) { el("sbTela").innerHTML = '<div class="done"><h3>Pedido enviado.</h3></div>'; return; }
      const nome = el("soNome").value.trim(), tel = el("soTel").value.replace(/\D/g, ""), email = el("soEmail").value.trim().toLowerCase(), min = el("soMin").value;
      const funcao = (f.querySelector('input[name="soFuncao"]:checked') || {}).value;
      if (nome.split(/\s+/).length < 2) { msg.textContent = "Informe o nome completo."; return; }
      if (!/^\d{10,13}$/.test(tel)) { msg.textContent = "Informe o telefone com DDD."; return; }
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) { msg.textContent = "Informe um e-mail válido."; return; }
      if (!min) { msg.textContent = "Escolha o ministério."; return; }
      return comBotao(async () => {
        msg.textContent = "Enviando…";
        try { await rpc("solicitar_acesso", { p_nome: nome, p_telefone: tel, p_email: email, p_ministerio: min, p_funcao: funcao }); }
        catch (err) { msg.textContent = err.message; return; }
        el("sbTela").innerHTML = `<div class="done" style="max-width:640px"><p class="eyebrow">Solicitação recebida</p><h3>Obrigado, ${h(primeiro(nome))}!</h3><p>O responsável pela Área de Membros vai analisar o seu pedido. Quando for aprovado, você recebe uma senha temporária pelo contato informado e cria a sua própria senha no primeiro acesso.</p><div><button class="btn btn-s" type="button" data-sb="ir:">Voltar</button></div></div>`;
      });
    }
    if (f.id === "sbEsqueci") {
      ev.preventDefault();
      const email = el("esEmail").value.trim().toLowerCase();
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) { msg.textContent = "Informe um e-mail válido."; return; }
      return comBotao(async () => {
        msg.textContent = "Enviando…";
        const { error } = await sb.auth.resetPasswordForEmail(email, { redirectTo: location.origin + location.pathname + "?redefinir=1" });
        if (error && /rate/i.test(error.message)) { msg.textContent = msgAuth(error); return; }
        // Resposta neutra: não revela se o e-mail tem conta
        el("sbTela").innerHTML = `<div class="done" style="max-width:640px"><p class="eyebrow">Verifique o seu e-mail</p><h3>Link enviado.</h3><p>Se houver uma conta com ${h(email)}, você vai receber um link para criar uma nova senha. Ele vale por pouco tempo.</p><div><button class="btn btn-s" type="button" data-sb="ir:entrar">Voltar ao login</button></div></div>`;
      });
    }
    if (f.id === "sbNovaSenha") {
      ev.preventDefault();
      const s1 = el("nsSenha").value, s2 = el("nsConf").value;
      if (!senhaOk(s1)) { msg.textContent = "Use pelo menos 10 caracteres, com letras e números."; return; }
      if (s1 !== s2) { msg.textContent = "As duas senhas não são iguais."; return; }
      if (f.dataset.recuperacao !== "1" && ultimaSenha && s1 === ultimaSenha) { msg.textContent = "A nova senha precisa ser diferente da senha temporária."; return; }
      return comBotao(async () => {
        msg.textContent = "Salvando…";
        const { error } = await sb.auth.updateUser({ password: s1 });
        if (error) { msg.textContent = msgAuth(error); return; }
        recuperando = false; ultimaSenha = "";
        history.replaceState(null, "", location.pathname + "#equipe");
        await render();
        const t = el("sbConteudo"); if (t) t.insertAdjacentHTML("afterbegin", '<p class="notice" style="margin-bottom:18px">Senha criada. A partir de agora, entre com o seu e-mail e esta nova senha.</p>');
      });
    }
    if (f.id === "sbMinhaFoto") {
      ev.preventDefault();
      return comBotao(async () => { try { await salvarFoto(f, msg); } catch (err) { msg.textContent = err.message; } });
    }
    if (f.id === "sbMeuTel") {
      ev.preventDefault();
      const d = el("mpTel").value.replace(/\D/g, "");
      if (d.length < 10 || d.length > 11) { msg.textContent = "Informe um telefone válido, com DDD."; return; }
      return comBotao(async () => {
        msg.textContent = "Salvando…";
        try { const r = await rpc("meu_perfil_atualizar", { p_telefone: d }); if (painel) painel.telefone = r.telefone; el("mpTel").value = fone(r.telefone); msg.textContent = "Telefone atualizado."; }
        catch (err) { msg.textContent = err.message; }
      });
    }
    if (f.id === "sbTrocar") {
      ev.preventDefault();
      const atual = el("tcAtual").value, s1 = el("tcNova").value, s2 = el("tcConf").value;
      if (!atual) { msg.textContent = "Informe a senha atual."; return; }
      if (!senhaOk(s1)) { msg.textContent = "Use pelo menos 10 caracteres, com letras e números."; return; }
      if (s1 !== s2) { msg.textContent = "As duas senhas não são iguais."; return; }
      return comBotao(async () => {
        msg.textContent = "Conferindo…";
        const { error: e1 } = await sb.auth.signInWithPassword({ email: painel.email, password: atual });
        if (e1) { msg.textContent = e1.code === "invalid_credentials" || /invalid login/i.test(e1.message) ? "A senha atual não confere." : msgAuth(e1); return; }
        const { error } = await sb.auth.updateUser({ password: s1 });
        if (error) { msg.textContent = msgAuth(error); return; }
        f.reset(); msg.textContent = "Senha alterada.";
      });
    }
    if (f.dataset.aprovar) {
      ev.preventDefault(); const id = f.dataset.aprovar;
      const corpo = { solicitacao_id: id, perfil: el("apPerfil-" + id).value, atribuicoes: lerAtrib("apAtr-" + id), ministerios: lerVinculos("apMin-" + id) };
      if (corpo.perfil === "LIDER" && !corpo.ministerios.some((m) => m.funcao === "lider")) { msg.textContent = "Marque ao menos um ministério com a função Líder."; return; }
      return comBotao(async () => {
        msg.textContent = "Criando acesso…";
        try { const r = await funcao("aprovar-acesso", corpo); f.outerHTML = caixaSenha(r, "Acesso criado"); el("sol-" + id).querySelector(".acts")?.remove(); const st = el("sol-" + id).querySelector(".st.novo"); if (st) { st.className = "st ok"; st.textContent = "Aprovada"; } if (painel.resumo) painel.resumo.solicitacoes_pendentes = Math.max(0, painel.resumo.solicitacoes_pendentes - 1); renderAbas("solicitacoes"); }
        catch (err) { msg.textContent = err.message; }
      });
    }
    if (f.dataset.recusar) {
      ev.preventDefault(); const motivo = f.querySelector("input").value.trim();
      if (motivo.length < 3) { msg.textContent = "Informe o motivo."; return; }
      return comBotao(async () => {
        try { await rpc("recusar_solicitacao", { p_solicitacao: f.dataset.recusar, p_motivo: motivo }); if (painel.resumo) painel.resumo.solicitacoes_pendentes = Math.max(0, painel.resumo.solicitacoes_pendentes - 1); await renderSolicitacoes(el("sbConteudo")); renderAbas("solicitacoes"); }
        catch (err) { msg.textContent = err.message; }
      });
    }
    if (f.id === "sbFormNovo") {
      ev.preventDefault();
      const corpo = { acao: "criar", nome: el("nuNome").value, telefone: el("nuTel").value, email: el("nuEmail").value, perfil: el("nuPerfil").value, atribuicoes: lerAtrib("nuAtr"), ministerios: lerVinculos("nuMin") };
      return comBotao(async () => {
        msg.textContent = "Criando…";
        try { const r = await funcao("admin-usuarios", corpo); await renderUsuarios(el("sbConteudo")); el("sbNovo").innerHTML = caixaSenha(r, "Usuário criado"); }
        catch (err) { msg.textContent = err.message; }
      });
    }
    if (f.dataset.editar) {
      ev.preventDefault(); const id = f.dataset.editar;
      return comBotao(async () => {
        msg.textContent = "Salvando…";
        try { await rpc("admin_atualizar_usuario", { p_usuario: id, p_perfil: el("edPerfil-" + id).value, p_atribuicoes: lerAtrib("edAtr-" + id), p_ministerios: lerVinculos("edMin-" + id) }); await renderUsuarios(el("sbConteudo")); }
        catch (err) { msg.textContent = err.message; }
      });
    }
    if (f.id === "sbFormMin") {
      ev.preventDefault();
      return comBotao(async () => {
        try { await rpc("admin_salvar_ministerio", { p_id: el("fmId").value || null, p_nome: el("fmNome").value, p_descricao: el("fmDesc").value, p_ordem: parseInt(el("fmOrdem").value || "0"), p_ativo: el("fmAtivo").value === "1" }); await renderMinisterios(el("sbMinCad") || el("sbConteudo")); el("fmMsg").textContent = "Ministério salvo."; if (el("sbMinInst") && window.BetelInstitucional) await window.BetelInstitucional.ministerios(el("sbMinInst"), { sb, inst: painel.inst, semCadastro: true }); }
        catch (err) { msg.textContent = err.message; }
      });
    }
  });

  /* ---------- sessão ---------- */
  sb.auth.onAuthStateChange((evento, s) => {
    sessao = s; setTimeout(atualizarUsuario, 0);
    if (evento === "PASSWORD_RECOVERY") { recuperando = true; if (rotaAtual() === null) location.hash = "#equipe"; else render(); }
    if (evento === "SIGNED_OUT") { painel = null; if (!saindo) { limparInterno(); if (rotaAtual() !== null) render(); } }
  });
  window.addEventListener("hashchange", render);
  (async () => {
    const { data } = await sb.auth.getSession(); sessao = data.session; atualizarUsuario();
    if (new URLSearchParams(location.search).get("redefinir") && location.hash.includes("error=")) {
      aviso = "O link expirou ou já foi usado. Peça um novo.";
      history.replaceState(null, "", location.pathname + location.hash);
      location.hash = "#equipe/esqueci";
      return;
    }
    if (recuperando && rotaAtual() === null) { location.hash = "#equipe"; return; }
    render();
  })();
})();
