/* Site público: conteúdo administrável pela Área de Membros
   - contatos centralizados (telefone com tel:, WhatsApp com wa.me, endereço com mapa, redes com ícone e @)
   - ministérios (lista e página de cada ministério)
   - galeria de fotos da Home e etapas de ensino do Colégio
   Se o banco não responder, o site continua com o conteúdo que já está no HTML. */
(() => {
  const CFG = window.BETEL_SUPABASE;
  if (!CFG || !window.supabase) return;
  const sb = window.supabase.createClient(CFG.url, CFG.anonKey, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
  const $ = (id) => document.getElementById(id);
  const h = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const ico = (n, t = 18) => (window.BetelUI?.icone ? window.BetelUI.icone(n, t) : "");
  const EXT = 'target="_blank" rel="noopener noreferrer"';
  const dig = (t) => String(t || "").replace(/\D/g, "");
  // Telefone brasileiro: link tel: e WhatsApp em formato internacional (55 + DDD + número)
  const tel = (t) => (dig(t) ? "tel:+55" + dig(t).replace(/^55(?=\d{10,11}$)/, "") : "");
  const wa = (t, msg) => (dig(t) ? "https://wa.me/55" + dig(t).replace(/^55(?=\d{10,11}$)/, "") + (msg ? "?text=" + encodeURIComponent(msg) : "") : "");
  const mapa = (q) => "https://www.google.com/maps/search/?api=1&query=" + encodeURIComponent(q || "");
  const insta = (u) => "https://www.instagram.com/" + String(u || "").replace(/^@/, "") + "/";
  const arroba = (u) => "@" + String(u || "").replace(/^@/, "");
  const urlFoto = (f) => (!f ? "" : f.startsWith("site/") ? `${CFG.url}/storage/v1/object/public/site/${f.slice(5).split("/").map(encodeURIComponent).join("/")}` : f);
  window.BetelSite = { urlFoto, tel, wa, mapa };

  let conteudo = null, ministerios = null;

  /* ---------- contatos ---------- */
  function aplicarContatos(c) {
    if (!c) return;
    const ig = c.igreja || {}, col = c.colegio || {}, cel = c.celulas || {};
    // todos os botões de WhatsApp marcados no HTML (inclusive o botão flutuante)
    document.querySelectorAll("[data-contato-wa]").forEach((a) => {
      const g = c[a.dataset.contatoWa] || {}; const u = wa(g.whatsapp, a.dataset.msg || "");
      if (u) a.href = u;
      if (a.classList.contains("cp-contato") && g.whatsapp) a.innerHTML = ico("whatsapp") + h(g.whatsapp);
    });
    const ct = $("ctInfo");
    if (ct) ct.innerHTML = `
      ${ig.endereco ? `<div><p class="eyebrow">Endereço</p><p><a class="cp-contato" href="${h(mapa(ig.mapa || ig.endereco))}" ${EXT}>${ico("mapa")}<span>${h(ig.endereco)}${ig.cep ? " · CEP " + h(ig.cep) : ""}</span></a></p></div>` : ""}
      ${ig.telefone ? `<div><p class="eyebrow">Telefone</p><p><a class="cp-contato" href="${h(tel(ig.telefone))}" id="telLink">${ico("telefone")}${h(ig.telefone)}</a></p></div>` : ""}
      ${ig.whatsapp ? `<div><p class="eyebrow">WhatsApp</p><p id="wppBox"><a class="cp-contato" href="${h(wa(ig.whatsapp, "Olá! Vim pelo site da Igreja Batista Betel."))}" ${EXT}>${ico("whatsapp")}${h(ig.whatsapp)}</a></p></div>` : ""}
      <div><p class="eyebrow">Redes</p><div class="social" style="margin-top:10px" id="ctRedes">${redes(ig, "da Igreja Batista Betel")}</div></div>`;
    if ($("ctMapa") && (ig.mapa || ig.endereco)) $("ctMapa").href = "https://www.google.com/maps/dir/?api=1&destination=" + encodeURIComponent(ig.mapa || ig.endereco);
    const ft = $("ftRedes");
    if (ft) ft.innerHTML = `<p class="eyebrow">Acompanhe</p>
      ${ig.youtube_url ? `<a class="cp-rede-link" href="${h(ig.youtube_url)}" ${EXT}>${ico("youtube", 16)}YouTube <span class="cp-arroba">${h(ig.youtube || "")}</span></a>` : ""}
      ${ig.instagram ? `<a class="cp-rede-link" href="${h(insta(ig.instagram))}" ${EXT}>${ico("instagram", 16)}Instagram <span class="cp-arroba">${h(arroba(ig.instagram))}</span></a>` : ""}
      ${col.instagram ? `<a class="cp-rede-link" href="${h(insta(col.instagram))}" ${EXT}>${ico("instagram", 16)}Colégio <span class="cp-arroba">${h(arroba(col.instagram))}</span></a>` : ""}
      ${ig.telefone ? `<a class="cp-rede-link" href="${h(tel(ig.telefone))}">${ico("telefone", 16)}${h(ig.telefone)}</a>` : ""}`;
    const ci = $("colInfo");
    if (ci) ci.innerHTML = `
      ${col.telefone ? `<div><p class="eyebrow">Telefone</p><p><a class="cp-contato" href="${h(tel(col.telefone))}">${ico("telefone")}${h(col.telefone)}</a></p></div>` : ""}
      ${col.whatsapp ? `<div><p class="eyebrow">WhatsApp do Colégio</p><p><a class="cp-contato" href="${h(wa(col.whatsapp, "Olá! Quero saber sobre matrículas no Colégio Batista Betel."))}" ${EXT}>${ico("whatsapp")}${h(col.whatsapp)}</a></p></div>` : ""}
      ${col.email ? `<div><p class="eyebrow">E-mail</p><p><a class="cp-contato" href="mailto:${h(col.email)}">${ico("email")}${h(col.email)}</a></p></div>` : ""}
      ${col.endereco ? `<div><p class="eyebrow">Endereço</p><p><a class="cp-contato" href="${h(mapa(col.mapa || col.endereco))}" ${EXT}>${ico("mapa")}${h(col.endereco)}</a></p></div>` : ""}`;
    const cc = $("colCtas");
    if (cc) cc.innerHTML = `${col.site ? `<a class="btn btn-p cp-rede" href="${h(col.site)}" ${EXT}>${ico("site")}Site e matrículas</a>` : ""}
      ${col.instagram ? `<a class="btn btn-s cp-rede" href="${h(insta(col.instagram))}" ${EXT} aria-label="Instagram do Colégio: ${h(arroba(col.instagram))}">${ico("instagram")}Instagram <span class="cp-arroba">${h(arroba(col.instagram))}</span></a>` : ""}`;
    // links gerados por outras partes do site (ex.: "Células" na programação) seguem a configuração
    trocarNumeros(c);
  }
  function redes(g, quem) {
    return `${g.instagram ? `<a class="btn btn-s cp-rede" href="${h(insta(g.instagram))}" ${EXT} aria-label="Instagram ${h(quem)}: ${h(arroba(g.instagram))}">${ico("instagram")}Instagram <span class="cp-arroba">${h(arroba(g.instagram))}</span></a>` : ""}
      ${g.youtube_url ? `<a class="btn btn-s cp-rede" href="${h(g.youtube_url)}" ${EXT} aria-label="Canal ${h(quem)} no YouTube: ${h(g.youtube || "")}">${ico("youtube")}YouTube <span class="cp-arroba">${h(g.youtube || "")}</span></a>` : ""}`;
  }
  // Números que o site já trazia antes da configuração central: passam a usar o valor configurado
  const ORIGINAIS = { "5531992997440": "celulas", "553184080257": "igreja", "5531995046148": "colegio" };
  function trocarNumeros(c, raiz = document) {
    raiz.querySelectorAll?.('a[href*="wa.me/"]').forEach((a) => {
      const m = a.href.match(/wa\.me\/(\d+)/); const g = m && ORIGINAIS[m[1]];
      if (!g || !c[g]?.whatsapp) return;
      const novo = "55" + dig(c[g].whatsapp).replace(/^55(?=\d{10,11}$)/, "");
      if (novo !== m[1]) a.href = a.href.replace("wa.me/" + m[1], "wa.me/" + novo);
    });
  }
  new MutationObserver((ms) => { if (conteudo?.contatos) ms.forEach((m) => m.addedNodes.forEach((n) => n.nodeType === 1 && trocarNumeros(conteudo.contatos, n))); })
    .observe(document.body, { childList: true, subtree: true });

  /* ---------- galeria da Home ---------- */
  function aplicarGaleria(fotos) {
    const g = $("homeGaleria"); if (!g || !Array.isArray(fotos) || !fotos.length) return;
    g.innerHTML = fotos.map((f) => `<figure class="cp-gal-item reveal in"><img src="${h(urlFoto(f.foto))}" alt="${h(f.alt)}" loading="lazy" decoding="async">${f.legenda ? `<figcaption>${h(f.legenda)}</figcaption>` : ""}</figure>`).join("");
  }

  /* ---------- Colégio: etapas de ensino ---------- */
  function aplicarEtapas(etapas, contatos) {
    const c = $("colEtapas"); if (!c || !Array.isArray(etapas) || !etapas.length) return;
    const col = contatos?.colegio || {};
    const contato = col.whatsapp ? wa(col.whatsapp, "Olá! Quero saber sobre matrículas no Colégio Batista Betel.") : col.telefone ? tel(col.telefone) : "";
    c.innerHTML = `<div class="cp-etapas-nav" role="list">${etapas.map((e) => `<a role="listitem" class="mini" href="#colegio" data-etapa="${h(e.slug)}">${h(e.titulo.replace(/ — .*/, ""))}</a>`).join("")}</div>
      ${etapas.map((e, i) => `<article class="mblock cp-etapa" id="etapa-${h(e.slug)}">
        ${e.foto && i % 2 === 0 ? `<img class="photo reveal in" style="border-radius:32px" src="${h(urlFoto(e.foto))}" alt="${h(e.foto_alt || e.titulo)}" loading="lazy">` : ""}
        <div class="txt reveal in"><p class="eyebrow">Etapa de ensino${e.faixa_etaria ? " · " + h(e.faixa_etaria) : ""}</p><h2>${h(e.titulo)}</h2>
          ${e.subtitulo ? `<p class="cp-etapa-sub">${h(e.subtitulo)}</p>` : ""}
          ${String(e.descricao || "").split(/\n{2,}/).map((p) => `<p class="lead">${h(p)}</p>`).join("")}
          ${e.objetivos?.length ? `<div class="cp-etapa-lista"><p class="eyebrow">Objetivos</p><ul>${e.objetivos.map((o) => `<li>${h(o)}</li>`).join("")}</ul></div>` : ""}
          ${e.diferenciais?.length ? `<div class="cp-etapa-lista"><p class="eyebrow">Diferenciais</p><ul>${e.diferenciais.map((o) => `<li>${h(o)}</li>`).join("")}</ul></div>` : ""}
          ${contato ? `<div class="pills"><a class="btn btn-p" href="${h(contato)}" ${EXT}>${ico(col.whatsapp ? "whatsapp" : "telefone")}Falar com o Colégio</a></div>` : ""}
        </div>
        ${e.foto && i % 2 === 1 ? `<img class="photo reveal in" src="${h(urlFoto(e.foto))}" alt="${h(e.foto_alt || e.titulo)}" loading="lazy">` : ""}
      </article>`).join("")}`;
  }
  document.addEventListener("click", (ev) => {
    const a = ev.target.closest("[data-etapa]"); if (!a) return;
    ev.preventDefault(); $("etapa-" + a.dataset.etapa)?.scrollIntoView({ behavior: "smooth", block: "start" });
  });

  /* ---------- ministérios ---------- */
  function cartaoMinisterio(m) {
    return `<a class="cp-min-card glass reveal in" href="#ministerio/${h(m.slug)}">
      ${m.foto ? `<img src="${h(urlFoto(m.foto))}" alt="${h(m.foto_alt || m.nome)}" loading="lazy" decoding="async">` : `<span class="cp-min-sem-foto" aria-hidden="true">${h(m.nome.slice(0, 1))}</span>`}
      <span class="cp-min-txt"><b>${h(m.nome)}</b>${m.descricao ? `<small>${h(m.descricao)}</small>` : ""}<span class="cp-min-ir">Conhecer →</span></span></a>`;
  }
  function renderListaMinisterios() {
    const c = $("minConteudo"); if (!c || !ministerios?.length) return;
    c.innerHTML = `<div class="cp-min-grid">${ministerios.map(cartaoMinisterio).join("")}</div>
      <div class="cp-min-cta glass"><div><p class="eyebrow">Servir</p><h3>Seus dons têm <em>lugar</em> aqui.</h3></div><a class="btn btn-p" href="#servir">Quero servir em um ministério</a></div>`;
  }
  function paragrafos(t) { return String(t || "").split(/\n{2,}/).map((p) => `<p>${h(p)}</p>`).join(""); }
  function renderMinisterio(slug) {
    const c = $("minDetalhe"); if (!c) return;
    if (!ministerios) { c.innerHTML = '<p class="empty" style="padding-top:160px">Carregando…</p>'; return; }
    const m = ministerios.find((x) => x.slug === slug);
    if (!m) { c.innerHTML = `<div class="sub-hero"><p class="eyebrow">Ministérios</p><h1>Ministério não <em>encontrado</em>.</h1><p class="lead" style="margin-top:24px"><a class="btn btn-p" href="#ministerios">Ver todos os ministérios</a></p></div>`; return; }
    const t = m.textos;
    const secoes = t ? [["O que fazemos", t.o_que_fazemos], ["Por que existimos", t.por_que_existimos], ["Nossa missão", t.missao]].filter((x) => x[1]) : [];
    document.title = `${m.nome} · Igreja Batista Betel`;
    c.innerHTML = `<div class="sub-hero"><p class="eyebrow"><a href="#ministerios" style="color:inherit">Ministérios</a> · ${h(m.nome)}</p><h1>${h(m.nome)}</h1>
        ${m.descricao ? `<p class="lead" style="margin-top:24px">${h(m.descricao)}</p>` : ""}</div>
      <div class="cp-min-detalhe">
        ${m.foto ? `<img class="photo cp-min-foto" src="${h(urlFoto(m.foto))}" alt="${h(m.foto_alt || m.nome)}">` : ""}
        ${secoes.length ? `<div class="cp-min-secoes">${secoes.map(([tt, x]) => `<section class="cp-min-secao glass"><p class="eyebrow">${h(tt)}</p>${paragrafos(x)}</section>`).join("")}</div>` : ""}
        ${t?.complemento ? `<section class="cp-min-secao glass"><p class="eyebrow">Saiba mais</p>${paragrafos(t.complemento)}</section>` : ""}
        ${m.lideres?.length ? `<p class="cp-min-lider"><span class="eyebrow">Liderança</span> ${m.lideres.map(h).join(", ")}</p>` : ""}
        <div class="pills"><a class="btn btn-p" href="#agenda" data-filter="${h(m.nome)}">Ver na agenda</a><a class="btn btn-s" href="#servir">Quero servir</a><a class="btn btn-s" href="#ministerios">Todos os ministérios</a></div>
      </div>`;
  }
  function rota() {
    const hs = location.hash.slice(1);
    if (hs.startsWith("ministerio/")) renderMinisterio(decodeURIComponent(hs.slice(11)));
    else if (document.title !== "Igreja Batista Betel" && /· Igreja Batista Betel$/.test(document.title)) document.title = "Igreja Batista Betel";
  }
  window.addEventListener("hashchange", rota);

  /* ---------- carga ---------- */
  async function carregar() {
    try {
      const [{ data: c }, { data: m }] = await Promise.all([sb.rpc("site_conteudo_publico"), sb.rpc("ministerios_publicos")]);
      if (c) { conteudo = c; aplicarContatos(c.contatos); aplicarGaleria(c.galeria_home); aplicarEtapas(c.colegio_etapas, c.contatos); }
      if (Array.isArray(m)) { ministerios = m; renderListaMinisterios(); }
    } catch (_) { /* mantém o conteúdo do HTML */ }
    if (!ministerios) ministerios = [];
    rota();
  }
  carregar();
})();
