{
/* ================= dados fixos ================= */
const MINS = ["Igreja","Homens Betel","Mulheres Betel","Juventude Mergulhados","Kids","EBD","Células","Escola de Artes","Colégio"];
const DEPS = ["Louvor","Mídia","Juventude","Diaconia","Kids","EBD","Secretaria"];
const NEEDS = ["Mídia","Diaconia","Louvor"];
const MESES = ["JAN","FEV","MAR","ABR","MAI","JUN","JUL","AGO","SET","OUT","NOV","DEZ"];
const DIAS = ["Domingo","Segunda","Terça","Quarta","Quinta","Sexta","Sábado"];
const FIXOS = [
  {dows:[1,2,3,4,5], h:"06:30", fim:"08:00", t:"Amanhecer com Deus"},
  {dows:[1,2,3], h:"", t:"Células", txt:"Nas casas · fale com a secretaria", link:"https://wa.me/5531992997440?text=" + encodeURIComponent("Olá! Quero saber sobre as células da Igreja Batista Betel.")},
  {dows:[1], h:"17:30", fim:"20:00", t:"Escola de Artes", txt:"Violão, bateria, hip hop, ballet, teclado e violino"},
  {dows:[2], h:"16:00", t:"Tarde da Bênção"},
  {dows:[4], h:"19:30", t:"Aviva Quinta"},
  {dows:[0], h:"09:00", t:"EBD", txt:"Escola Bíblica Dominical"},
  {dows:[0], h:"18:00", t:"Culto de Celebração", txt:"Ao vivo no YouTube"}
];
const FRASES = ["Betel é casa de Deus", "Fazendo discípulos em nossa geração", "A vitória é nossa em nome de Jesus"];
const DEF = {
  telefone:"(31) 3333-9749", whatsapp:"(31) 8408-0257",
  msgMembro:"Olá, {primeiro}! Seja muito bem-vindo(a) à família da Igreja Batista Betel. A partir de agora, esta casa também é sua. Conte com a gente para caminhar junto na fé. Qualquer dúvida, é só falar com a secretaria por aqui. Deus abençoe!",
  msgVisitante:"Olá, {primeiro}! Aqui é da Igreja Batista Betel. Foi uma alegria ter você com a gente! Betel é casa de Deus, e as portas estão sempre abertas pra você. Nos próximos dias, a Elaine, da nossa equipe, vai falar com você por aqui. Deus abençoe!",
  msgElaine:"Oi, Elaine! Novo visitante para acompanhar:\nNome: {nome}\nWhatsApp: {telefone}\nVisitou em: {data} ({culto})\nComo conheceu: {como}\nTem igreja: {igreja}\nDeseja visita: {visita}\nPedido de oração: {oracao}\nObservações: {obs}\n\nA mensagem de boas-vindas já foi enviada.",
  msgEscala:"Olá, {primeiro}! Você está escalado(a) para servir na equipe de {departamento} no {culto}, {dia}, {data}, às {hora}. Confira os detalhes em \"Minha escala\", no site da Betel. Se não puder servir, avise a liderança o quanto antes. Deus abençoe!",
  msgLider:"Olá, {lider}! A secretaria cadastrou o evento \"{evento}\" em {data}, às {hora}, no {local}, e ele vai precisar de {departamento}. Por favor, monte a escala na Área de Membros do site. Observações: {obs}"
};

/* ================= formulários (esquemas) ================= */
const F_EV = [
  {k:"titulo", l:"Nome do evento", req:1, full:1},
  {k:"tipo", l:"Tipo", t:"select", o:["Culto","Culto especial","Conferência","Congresso","Encontro","Retiro ou acampamento","Ação social ou evangelismo","Reunião","Curso","Outro"]},
  {k:"ministerio", l:"Ministério responsável", t:"select", o:MINS},
  {k:"data", l:"Data", t:"date", req:1},
  {k:"dataFim", l:"Data de término (se durar mais de um dia)", t:"date"},
  {k:"hora", l:"Horário de início", t:"time", req:1},
  {k:"horaFim", l:"Horário de término", t:"time"},
  {k:"local", l:"Local", def:"Templo da Betel"},
  {k:"publico", l:"Público", t:"select", o:["Toda a igreja","Aberto ao público","Jovens","Mulheres","Homens","Crianças","Casais","Liderança"]},
  {k:"responsavel", l:"Responsável pelo evento"},
  {k:"descricao", l:"Descrição (aparece no site)", t:"textarea", full:1},
  {h:"Inscrição"},
  {k:"inscricao", l:"Este evento precisa de inscrição", t:"check", full:1},
  {k:"inscricaoSite", l:"Inscrição pelo próprio site da Betel (formulário, confirmação e pagamento)", t:"check", full:1},
  {k:"valor", l:"Valor da inscrição (R$)", t:"number", ph:"0 = gratuito"},
  {k:"pagamento", l:"Como receber", t:"select", o:["Pix direto na chave do ministério","PagBank pelo site (Pix, débito e crédito)"]},
  {k:"chavePix", l:"Chave Pix deste evento (opcional)", ph:"Em branco: Juventude usa a chave da Juventude, os demais a chave da igreja"},
  {k:"linkInscricao", l:"Ou link externo de inscrição", t:"url", ph:"https://forms.gle/…"},
  {k:"vagas", l:"Número de vagas", t:"number"},
  {k:"prazoInscricao", l:"Inscrições até", t:"date"},
  {k:"infoInscricao", l:"Informação extra", ph:"Ex.: levar Bíblia e caderno"},
  {h:"Equipes"},
  {k:"precisa", l:"Este evento vai precisar de", t:"checks", o:NEEDS, full:1},
  {k:"obsEquipe", l:"Observações para as equipes", t:"textarea", full:1, ph:"Ex.: transmissão ao vivo, ministração com banda completa, recepção de convidados"}
];
const F_M = [
  {h:"Dados pessoais"},
  {k:"nome", l:"Nome completo", req:1, full:1},
  {k:"telefone", l:"WhatsApp", t:"tel", req:1, ph:"(31) 9 0000-0000"},
  {k:"email", l:"E-mail", t:"email"},
  {k:"nascimento", l:"Data de nascimento", t:"date"},
  {k:"sexo", l:"Sexo", t:"select", o:["","Feminino","Masculino"]},
  {k:"estadoCivil", l:"Estado civil", t:"select", o:["","Solteiro(a)","Casado(a)","Divorciado(a)","Viúvo(a)"]},
  {k:"conjuge", l:"Nome do cônjuge"},
  {k:"profissao", l:"Profissão"},
  {h:"Endereço"},
  {k:"endereco", l:"Rua e número", full:1},
  {k:"bairro", l:"Bairro"},
  {k:"cidade", l:"Cidade", def:"Contagem"},
  {k:"cep", l:"CEP"},
  {h:"Vida na igreja"},
  {k:"admissao", l:"Forma de admissão", t:"select", o:["","Batismo","Carta de transferência","Aclamação","Reconciliação"]},
  {k:"desde", l:"Membro desde", t:"date"},
  {k:"dataBatismo", l:"Data do batismo", t:"date"},
  {k:"igrejaAnterior", l:"Igreja anterior"},
  {k:"ministerios", l:"Ministérios em que serve", full:1},
  {k:"obs", l:"Observações", t:"textarea", full:1},
  {k:"consentimento", l:"A pessoa autorizou o cadastro e o contato pelo WhatsApp", t:"check", req:1, full:1}
];
const F_V = [
  {h:"Quem nos visitou"},
  {k:"nome", l:"Nome completo", req:1, full:1},
  {k:"telefone", l:"WhatsApp", t:"tel", req:1, ph:"(31) 9 0000-0000"},
  {k:"email", l:"E-mail", t:"email"},
  {k:"bairro", l:"Bairro"},
  {k:"cidade", l:"Cidade", def:"Contagem"},
  {h:"A visita"},
  {k:"dataVisita", l:"Data da visita", t:"date", req:1},
  {k:"culto", l:"Culto ou evento", t:"select", o:["Culto de Celebração","EBD","Aviva Quinta","Tarde da Bênção","Amanhecer com Deus","Culto de Jovens","Evento especial","Outro"]},
  {k:"primeiraVez", l:"Primeira vez na Betel?", t:"select", o:["Sim","Não"]},
  {k:"como", l:"Como conheceu a Betel", t:"select", o:["Convite de amigo ou familiar","Instagram","YouTube","Passando na rua","Colégio Batista Betel","Outro"]},
  {k:"convidadoPor", l:"Quem convidou"},
  {k:"igreja", l:"Frequenta alguma igreja? Qual?", ph:"Não, ou o nome da igreja"},
  {k:"visita", l:"Deseja receber uma visita ou ligação da igreja", t:"check", full:1},
  {k:"oracao", l:"Pedido de oração", t:"textarea", full:1},
  {k:"obs", l:"Observações", t:"textarea", full:1},
  {k:"consentimento", l:"A pessoa autorizou o contato pelo WhatsApp", t:"check", req:1, full:1}
];

/* ================= utilitários ================= */
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const safeUrl = u => /^https:\/\//i.test(u || "") ? u : "";
const $ = id => document.getElementById(id);
const digits = t => { let d = String(t || "").replace(/\D/g, ""); if (d.length === 10 || d.length === 11) d = "55" + d; return d.length >= 12 && d.length <= 13 ? d : ""; };
const wa = (tel, msg) => { const d = digits(tel); return d ? "https://wa.me/" + d + (msg ? "?text=" + encodeURIComponent(msg) : "") : ""; };
const br = iso => { const [y,m,d] = String(iso || "").split("-"); return y && m && d ? d + "/" + m + "/" + y : ""; };
const iso = dt => { const t = new Date(dt); t.setMinutes(t.getMinutes() - t.getTimezoneOffset()); return t.toISOString().slice(0,10); };
const today = () => iso(new Date());
const parseD = s => { const [y,m,d] = String(s || "").split("-"); return new Date(+y, +m - 1, +d); };
const isUp = s => { const t = new Date(); t.setHours(0,0,0,0); return parseD(s) >= t; };
const fill = (tpl, p) => String(tpl || "").replace(/\{(\w+)\}/g, (_, k) => {
  if (k === "primeiro") return String(p.nome || "").trim().split(/\s+/)[0];
  if (k === "data") return br(p.dataVisita || p.data || p.desde || "") || "";
  if (k === "visita") return p.visita ? "Sim" : "Não";
  const v = p[k]; return v === undefined || v === "" || v === null ? "—" : String(v);
});
const wrap = (fn, ms) => { let t; return () => { clearTimeout(t); t = setTimeout(fn, ms); }; };

function renderFields(box, prefix, fields){
  $(box).innerHTML = fields.map(f => {
    if (f.h) return `<h4>${esc(f.h)}</h4>`;
    const id = prefix + "_" + f.k, cls = f.full ? ' class="full"' : "", req = f.req ? " required" : "", ph = f.ph ? ` placeholder="${esc(f.ph)}"` : "";
    if (f.t === "select") return `<label${cls}>${esc(f.l)}<select id="${id}"${req}>${f.o.map(o => `<option value="${esc(o)}">${esc(o || "—")}</option>`).join("")}</select></label>`;
    if (f.t === "textarea") return `<label${cls}>${esc(f.l)}<textarea id="${id}" maxlength="800"${ph}></textarea></label>`;
    if (f.t === "check") return `<label class="check${f.full ? " full" : ""}"><input id="${id}" type="checkbox"${req}> ${esc(f.l)}</label>`;
    if (f.t === "checks") return `<fieldset${cls} style="border:0;padding:0;margin:0"><legend style="font-weight:600;font-size:14px;margin-bottom:10px">${esc(f.l)}</legend><div class="deps" id="${id}">${f.o.map(o => `<label><input type="checkbox" value="${esc(o)}"> ${esc(o)}</label>`).join("")}</div></fieldset>`;
    return `<label${cls}>${esc(f.l)}<input id="${id}" type="${f.t || "text"}" maxlength="${f.t === "url" ? 300 : 160}"${req}${ph}></label>`;
  }).join("");
  setVals(prefix, fields, {});
}
function getVals(prefix, fields){
  const o = {};
  for (const f of fields) { if (f.h) continue; const el = $(prefix + "_" + f.k);
    if (f.t === "check") o[f.k] = el.checked;
    else if (f.t === "checks") o[f.k] = [...el.querySelectorAll("input:checked")].map(i => i.value);
    else if (f.t === "number") o[f.k] = el.value ? Number(el.value) : "";
    else o[f.k] = el.value.trim(); }
  return o;
}
function setVals(prefix, fields, obj){
  for (const f of fields) { if (f.h) continue; const el = $(prefix + "_" + f.k), v = obj[f.k] ?? f.def ?? "";
    if (f.t === "check") el.checked = !!obj[f.k];
    else if (f.t === "checks") el.querySelectorAll("input").forEach(i => i.checked = (obj[f.k] || []).includes(i.value));
    else if (f.t === "select") el.value = v || f.o[0];
    else el.value = v; }
}
function missing(prefix, fields){
  for (const f of fields) { if (!f.req) continue; const el = $(prefix + "_" + f.k);
    if (f.t === "check" ? !el.checked : !el.value.trim()) { el.focus(); return f.l; } }
  return "";
}

/* ================= estado ================= */
let db = null, canEdit = false, loaded = false, uid = null, isOwn = false, papel = null, roleReady = false, myPedido = null, pedidos = [], papeis = [];
const PAPEL_NOME = {master:"Master", secretaria:"Secretaria", lider:"Líder de ministério", voluntario:"Voluntário(a)"};
const ROLE_TABS = {owner:["agenda","membros","visitantes","inscricoes","imagem","voluntarios","escalas","candidaturas","config","acessos"], secretaria:["agenda","membros","visitantes","inscricoes","imagem","config","acessos"], lider:["inscricoes","imagem","voluntarios","escalas","candidaturas","acessos"]};
function role(){ if (isOwn) return "owner"; const p = papel && papel.papel; if (p === "master" && canEdit) return "owner"; if ((p === "secretaria" || p === "lider") && canEdit) return p; if (p === "voluntario") return "voluntario"; return null; }
const isStaff = () => ["owner","secretaria","lider"].includes(role());
let autImg = [], inscricoes = [], volTel = {}, events = [], vols = [], escalas = [], membros = [], visitantes = [], candidaturas = [], indisp = [];
let cfg = {...DEF}, cfgPriv = {telefoneElaine:"", msgElaine:DEF.msgElaine, msgLider:DEF.msgLider, lideres:{}};
let filter = "Todos", vFiltro = "Todos", volFiltro = "Todos", esFiltro = "Próximas", cdFiltro = "Todas";
const editing = {};

/* ================= rotas ================= */
const VIEWS = ["inicio","sobre","ministerios","agenda","colegio","contato","servir","voluntario","equipe","inscricao","pagamento","imagem"].concat(window.BETEL_VIEWS_EXTRA || []);
let insEvId = null;
function route(){
  let h = location.hash.slice(1);
  // "Área de Membros": o endereço #membros também funciona (mesma área de #equipe)
  if (h === "membros" || h.startsWith("membros/")) { h = "equipe" + h.slice(7); history.replaceState(null, "", location.pathname + location.search + "#" + h); }
  let v = VIEWS.includes(h) ? h : "inicio";
  if (h.startsWith("equipe/")) v = "equipe";
  if (h.startsWith("inscricao-") && !h.startsWith("inscricao-curso/")) { v = "inscricao"; insEvId = h.slice(10); renderInscricao(); }
  if (h.startsWith("pagamento-")) { v = "pagamento"; renderPagamento(h.slice(10)); }
  if (h.startsWith("pagar-")) { v = "inscricao"; insEvId = null; renderPagar(h.slice(6)); }
  if (VIEWS.includes("curso") && h.startsWith("curso/")) v = "curso";
  if (VIEWS.includes("ministerio") && h.startsWith("ministerio/")) v = "ministerio";
  if (VIEWS.includes("inscricao-curso") && h.startsWith("inscricao-curso/")) v = "inscricao-curso";
  if (v === "imagem") setTimeout(() => { fillImgEscopo(); initAssinatura("imgCanvas", "imgLimpar"); updImgTermo(); }, 60);
  VIEWS.forEach(x => $("v-" + x).classList.toggle("on", x === v));
  document.querySelectorAll(".nav a").forEach(a => { if (a.getAttribute("href") === "#" + v) a.setAttribute("aria-current","page"); else a.removeAttribute("aria-current"); });
  $("nav").classList.remove("open"); $("menuBtn").setAttribute("aria-expanded","false");
  if (h === "programacao") { setTimeout(() => $("programacao").scrollIntoView(), 30); } else window.scrollTo(0,0);
  observeReveals(); bindTilt();
}
window.addEventListener("hashchange", route);
$("menuBtn").addEventListener("click", () => { const o = $("nav").classList.toggle("open"); $("menuBtn").setAttribute("aria-expanded", String(o)); });
document.addEventListener("click", e => { const a = e.target.closest("[data-filter]"); if (a) { filter = a.dataset.filter; renderEvents(); } });
const io = new IntersectionObserver(es => es.forEach(en => { if (en.isIntersecting) { en.target.classList.add("in"); io.unobserve(en.target); } }), {threshold:.08});
function observeReveals(){ document.querySelectorAll(".view.on .reveal:not(.in)").forEach(el => io.observe(el)); }

/* ================= movimento: inclinação 3D, brilho do cursor ================= */
const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches, fine = matchMedia("(hover: hover)").matches;
function bindTilt(){
  if (reduce || !fine) return;
  document.querySelectorAll(".view.on .tilt:not([data-t])").forEach(el => {
    el.dataset.t = "1";
    el.addEventListener("pointermove", e => { const r = el.getBoundingClientRect(), x = (e.clientX - r.left) / r.width - .5, y = (e.clientY - r.top) / r.height - .5;
      el.style.setProperty("--ry", (x * 10).toFixed(2) + "deg"); el.style.setProperty("--rx", (-y * 10).toFixed(2) + "deg"); });
    el.addEventListener("pointerleave", () => { el.style.setProperty("--ry","0deg"); el.style.setProperty("--rx","0deg"); });
  });
}
if (!reduce && fine && $("cglow")) { const g = $("cglow"); g.classList.add("on"); addEventListener("pointermove", e => { g.style.transform = `translate(${e.clientX}px,${e.clientY}px)`; }, {passive:true}); }
if ($("mq")) $("mq").innerHTML = [0,1].map(() => FRASES.map((f, i) => `<span class="${i === 1 ? "f" : ""}">${esc(f)}</span><span><i>✦</i></span>`).join("")).join("");

/* ================= animação do logo e frases (como um vídeo) ================= */
{
  const bm = $("bm"), frs = [...document.querySelectorAll(".bm-frases p")];
  const BG = ["1", "1", "1.6", "1.25"];
  let st = -1, timer = null;
  function show(n){
    st = n; bm.dataset.s = String(n);
    bm.classList.remove("go"); void bm.offsetWidth; bm.classList.add("go");
    frs.forEach((f, i) => f.classList.toggle("on", i === n - 1));
    bm.style.setProperty("--hi", BG[n]);
  }
  const step = () => show((st + 1) % 4);
  if (reduce) { bm.dataset.s = "1"; frs.forEach(f => f.classList.add("on")); }
  else new IntersectionObserver(es => { if (es[0].isIntersecting) { if (!timer) { show(0); timer = setInterval(step, 3400); } } else { clearInterval(timer); timer = null; } }, {threshold:.35}).observe(bm);
}

/* ================= vídeo ================= */
const vid = $("heroVideo");
try { vid.play().catch(() => {}); } catch (_) {}
$("soundBtn").addEventListener("click", () => { vid.muted = !vid.muted; if (!vid.muted) { vid.volume = .7; vid.play().catch(() => {}); } $("soundBtn").textContent = vid.muted ? "Ativar som" : "Desativar som"; $("soundBtn").setAttribute("aria-pressed", String(!vid.muted)); });
$("pauseBtn").addEventListener("click", () => { const p = !vid.paused; if (p) vid.pause(); else vid.play().catch(() => {}); $("pauseBtn").textContent = p ? "Continuar vídeo" : "Pausar vídeo"; $("pauseBtn").setAttribute("aria-pressed", String(p)); });
if (reduce) { vid.removeAttribute("autoplay"); vid.pause(); $("pauseBtn").textContent = "Continuar vídeo"; }

/* ================= programação: fixos + agenda ================= */
function itemsOn(date){
  const ds = iso(date), dow = date.getDay();
  const fx = FIXOS.filter(f => f.dows.includes(dow)).map(f => ({h:f.h, fim:f.fim, t:f.t, txt:f.txt, link:f.link, ag:false}));
  const ev = events.filter(e => e.data === ds).map(e => ({h:e.hora || "", fim:e.horaFim, t:e.titulo, txt:[e.local, e.inscricao ? "Inscrições abertas" : ""].filter(Boolean).join(" · "), ag:true}));
  return fx.concat(ev).sort((a, b) => (a.h || "99") < (b.h || "99") ? -1 : 1);
}
function renderDays(){
  const out = [];
  for (let i = 0; i < 7; i++) { const d = new Date(); d.setHours(0,0,0,0); d.setDate(d.getDate() + i);
    const label = i === 0 ? "Hoje" : i === 1 ? "Amanhã" : DIAS[d.getDay()].slice(0,3);
    const its = itemsOn(d);
    out.push(`<div class="day glass reveal${i === 0 ? " hoje" : ""}"><div class="dh"><b>${esc(label)}</b><span>${String(d.getDate()).padStart(2,"0")}/${String(d.getMonth()+1).padStart(2,"0")}</span></div>
      <div class="its">${its.length ? its.map(x => { const inner = `${x.h ? `<time>${esc(x.h)}${x.fim ? "–" + esc(x.fim) : ""}</time>` : ""}<b>${esc(x.t)}</b>${x.txt ? `<small>${esc(x.txt)}</small>` : ""}`;
        return x.link ? `<a class="it lk" href="${esc(x.link)}" target="_blank" rel="noopener">${inner}<small class="go">Quero saber sobre células →</small></a>` : `<div class="it${x.ag ? " ag" : ""}">${inner}</div>`; }).join("") : '<small style="color:var(--suave)">Sem programação.</small>'}</div></div>`); }
  $("days").innerHTML = out.slice(0, 3).join(""); if ($("daysAll")) $("daysAll").innerHTML = out.join(""); observeReveals();
}
function nextCulto(){
  const now = new Date(); let best = null;
  for (let add = 0; add < 8; add++) { const day = new Date(now); day.setHours(0,0,0,0); day.setDate(day.getDate() + add);
    for (const x of itemsOn(day)) { if (!x.h) continue; const [hh, mm] = x.h.split(":"); const d = new Date(day); d.setHours(+hh, +mm || 0, 0, 0);
      let end = new Date(d.getTime() + 2 * 36e5); if (x.fim) { const [fh, fm] = x.fim.split(":"); end = new Date(day); end.setHours(+fh, +fm || 0, 0, 0); }
      const live = now >= d && now < end;
      if ((live || d > now) && (!best || d < best.date)) best = {date:d, t:x.t, h:x.h, live}; } }
  return best;
}
function tick(){
  const n = nextCulto(); if (!n) return;
  $("nxWhen").textContent = n.live ? "AGORA" : DIAS[n.date.getDay()].slice(0,3).toUpperCase() + " " + n.h;
  $("nxWhat").textContent = n.t;
  $("nxLabel").innerHTML = n.live ? '<span class="dot" aria-hidden="true"></span> Acontecendo agora' : "Próximo encontro";
  if (n.live) { $("nxCount").innerHTML = '<a href="https://www.youtube.com/@betelflamengo" target="_blank" rel="noopener">Acompanhar no YouTube</a>'; return; }
  const ms = n.date - new Date(), d = Math.floor(ms / 864e5), h = Math.floor(ms % 864e5 / 36e5), m = Math.floor(ms % 36e5 / 6e4);
  $("nxCount").textContent = "Começa em " + (d ? d + "d " : "") + h + "h " + String(m).padStart(2,"0") + "min";
}
setInterval(tick, 30000);

/* ================= contato ================= */
function renderContato(){
  if (window.BETEL_SUPABASE) return; // contatos vêm da configuração central (site-sb.js)
  const w = wa(cfg.whatsapp, "Olá! Vim pelo site da Igreja Batista Betel.");
  if (w) $("wfab").href = w;
  $("wppBox").innerHTML = w ? `<a href="${esc(w)}" target="_blank" rel="noopener">${esc(cfg.whatsapp)}</a>` : "Em breve";
  const t = String(cfg.telefone || DEF.telefone); $("telLink").textContent = t; $("telLink").href = "tel:+55" + t.replace(/\D/g, "");
}

/* ================= agenda pública ================= */
const brl = v => Number(v || 0).toLocaleString("pt-BR", {style:"currency", currency:"BRL"});
const MESX = ["janeiro","fevereiro","março","abril","maio","junho","julho","agosto","setembro","outubro","novembro","dezembro"];
function periodo(e){
  const a = parseD(e.data), b = e.dataFim ? parseD(e.dataFim) : null; if (isNaN(a)) return "";
  if (!b || isNaN(b) || e.dataFim === e.data) return `${DIAS[a.getDay()]}, ${a.getDate()} de ${MESX[a.getMonth()]} de ${a.getFullYear()}`;
  return a.getMonth() === b.getMonth() ? `${a.getDate()} a ${b.getDate()} de ${MESX[a.getMonth()]} de ${a.getFullYear()}` : `${a.getDate()} de ${MESX[a.getMonth()]} a ${b.getDate()} de ${MESX[b.getMonth()]} de ${b.getFullYear()}`;
}
function evHTML(e, admin){
  const [y,mo,da] = String(e.data || "").split("-"), dt = parseD(e.data);
  const meta = [isNaN(dt) ? "" : (e.dataFim && e.dataFim !== e.data ? periodo(e) : DIAS[dt.getDay()]), e.hora ? e.hora + (e.horaFim ? "–" + e.horaFim : "") : "", e.local, e.publico].filter(Boolean).map(esc).join(" · ");
  const link = safeUrl(e.linkInscricao);
  const closed = e.prazoInscricao && !isUp(e.prazoInscricao);
  const tag = e.inscricao ? (closed ? '<span class="tag">Inscrições encerradas</span>' : '<span class="tag on">Inscrições abertas</span>') : '<span class="tag">Entrada livre</span>';
  const extra = [e.valor ? brl(e.valor) : "", e.vagas ? e.vagas + " vagas" : "", e.prazoInscricao ? "até " + br(e.prazoInscricao) : "", e.infoInscricao].filter(Boolean).join(" · ");
  const act = admin
    ? `<div class="act"><button class="mini" data-edit-ev="${esc(e.id)}">Editar</button><button class="mini" data-del="eventos|${esc(e.id)}">Excluir</button></div>`
    : (e.inscricao && !closed ? `<div class="act">${e.inscricaoSite ? `<a class="btn btn-p" href="#inscricao-${esc(e.id)}">Fazer inscrição</a>` : link ? `<a class="btn btn-p" href="${esc(link)}" target="_blank" rel="noopener">Fazer inscrição</a>` : `<span class="btn btn-s">Inscrição em breve</span>`}${extra ? `<small>${esc(extra)}</small>` : ""}</div>` : "");
  const needs = admin && (e.precisa || []).length ? `<div class="chips">${e.precisa.map(p => `<span>${esc(p)}</span>`).join("")}</div>` : "";
  return `<article class="ev"${admin ? ' style="padding:22px 20px"' : ""}><div class="d"><b>${esc(da || "--")}</b><span>${esc(MESES[+mo - 1] || "")}</span></div>
    <div>${tag}<h3>${esc(e.titulo)}</h3><p class="meta">${meta}${e.ministerio ? " · " + esc(e.ministerio) : ""}</p>${e.descricao && !admin ? `<p class="desc">${esc(e.descricao)}</p>` : ""}${needs}</div>${act}</article>`;
}
function renderEvents(){
  if ($("v-imagem") && $("v-imagem").classList.contains("on")) fillImgEscopo();
  if (insEvId && $("v-inscricao").classList.contains("on") && !$("insForm") && !$("insDone")) renderInscricao();
  const up = events.filter(e => isUp(e.data));
  const opts = ["Todos","Com inscrição", ...MINS.filter(m => up.some(e => e.ministerio === m))];
  if (!opts.includes(filter)) opts.push(filter);
  $("filters").innerHTML = opts.map(o => `<button class="chip" aria-pressed="${o === filter}" data-f="${esc(o)}">${esc(o)}</button>`).join("");
  const list = up.filter(e => filter === "Todos" || (filter === "Com inscrição" ? e.inscricao : e.ministerio === filter));
  const emptyMsg = !loaded ? "Carregando a agenda…" : (db ? "Nenhum evento por aqui ainda. Acompanhe nosso Instagram." : "A agenda aparece aqui para quem está conectado.");
  $("allEvents").innerHTML = list.length ? list.map(e => evHTML(e)).join("") : `<p class="empty">${emptyMsg}</p>`;
  $("homeEvents").innerHTML = up.length ? up.slice(0,3).map(e => evHTML(e)).join("") : `<p class="empty">${emptyMsg}</p>`;
  renderDays(); tick();
  if (canEdit) { $("admList").innerHTML = events.length ? events.slice().reverse().map(e => evHTML(e, true)).join("") : '<p class="empty" style="padding:24px">Nenhum evento cadastrado.</p>'; renderPend(); renderEsEventos(); }
}
$("filters").addEventListener("click", e => { const b = e.target.closest("[data-f]"); if (b) { filter = b.dataset.f; renderEvents(); } });

/* ================= voluntário: minha escala + indisponibilidade ================= */
function renderVolPick(){
  const cur = $("volPick").value;
  $("volPick").innerHTML = '<option value="">Selecione…</option>' + vols.map(v => `<option value="${esc(v.id)}">${esc(v.nome)}</option>`).join("");
  $("volPick").value = vols.some(v => v.id === cur) ? cur : "";
  syncVolPick(); renderVolOut();
}
const volName = id => (vols.find(v => v.id === id) || {}).nome || "";
const isOff = (vid_, d) => indisp.some(x => x.voluntario === vid_ && x.data === d);
function escHTML(s, me){
  const [y,mo,da] = String(s.data || "").split("-"), dt = parseD(s.data);
  const names = (s.voluntarios || []).map(id => `<span class="${id === me ? "me" : ""}">${esc(volName(id) || "—")}${isOff(id, s.data) ? " · indisponível" : ""}</span>`).join("");
  return `<div class="esc"><div class="d"><b>${esc(da || "--")}</b><span>${esc(MESES[+mo - 1] || "")} · ${esc(isNaN(dt) ? "" : DIAS[dt.getDay()].slice(0,3).toUpperCase())}</span></div>
    <div><span class="tag on">${esc(s.departamento)}</span><h3 style="font-size:24px">${esc(s.culto || "Escala")}</h3><p class="meta" style="font-size:13px;color:var(--suave);margin-top:4px">${esc([s.hora, s.obs].filter(Boolean).join(" · "))}</p><div class="chips">${names}</div></div></div>`;
}
function syncVolPick(){
  const link = papel && papel.voluntario; $("volPickWrap").hidden = !isStaff();
  if (link && (!isStaff() || !$("volPick").value) && vols.some(v => v.id === link)) $("volPick").value = link;
}
function renderVolOut(){
  if (db && !roleReady) { $("volOut").innerHTML = '<p class="empty">Verificando seu acesso…</p>'; return; }
  if (window.betelAuth && !uid) { $("volOut").innerHTML = '<p class="empty">Entre com sua conta na <a href="#equipe">Área de Membros</a> para ver sua escala.</p>'; return; }
  if (db && !isStaff() && !(papel && papel.voluntario)) { $("volOut").innerHTML = `<p class="empty">${role() === "voluntario" ? "Seu acesso foi liberado, mas ainda falta ligar você ao cadastro de voluntários. Fale com o líder do seu ministério." : 'Seu acesso de voluntário ainda não foi liberado. Peça acesso na <a href="#equipe">Área de Membros</a>.'}</p>`; return; }
  const id = $("volPick").value, v = vols.find(x => x.id === id);
  if (!loaded) return;
  if (!vols.length) { $("volOut").innerHTML = `<p class="empty">${db ? "Nenhum voluntário cadastrado ainda." : "A escala aparece aqui para quem está conectado."}</p>`; return; }
  if (!v) { $("volOut").innerHTML = '<p class="empty">Escolha seu nome acima.</p>'; return; }
  const mine = escalas.filter(s => isUp(s.data) && (s.voluntarios || []).includes(id));
  const off = indisp.filter(x => x.voluntario === id && isUp(x.data));
  $("volOut").innerHTML = `<p class="eyebrow">Seus departamentos</p><div class="chips" style="margin:12px 0 40px">${(v.departamentos || []).map(d => `<span class="me">${esc(d)}</span>`).join("")}</div>
    <div class="split" style="align-items:start;gap:40px">
      <div><p class="eyebrow">Você está escalado(a)</p><div class="events" style="margin-top:16px">${mine.length ? mine.map(s => escHTML(s, id)).join("") : '<p class="empty">Nenhuma escala marcada para você nos próximos dias.</p>'}</div></div>
      <form class="card glass neon" id="offForm"><h3>Minhas indisponibilidades</h3><p style="color:var(--suave);font-size:15px">Marque as datas em que você não pode servir. Os líderes veem isso ao montar a escala.</p>
        <label>Data<input type="date" id="offData" required min="${today()}"></label>
        <label>Motivo (opcional)<input id="offObs" maxlength="120" placeholder="Viagem, trabalho…"></label>
        <div><button class="btn btn-p" type="submit">Marcar indisponível</button></div><span class="msg" id="offMsg"></span>
        <div class="chips">${off.length ? off.map(x => `<span class="me">${esc(br(x.data))}${x.obs ? " · " + esc(x.obs) : ""} <button type="button" class="mini" style="min-height:28px;padding:0 10px;margin-left:6px" data-deloff="${esc(x.id)}" aria-label="Remover ${esc(br(x.data))}">remover</button></span>`).join("") : '<span>Nenhuma data marcada.</span>'}</div>
      </form></div>`;
}
$("volPick").addEventListener("change", renderVolOut);
document.addEventListener("submit", async e => {
  if (e.target.id !== "offForm") return; e.preventDefault();
  const id = $("volPick").value, d = $("offData").value, obs = $("offObs").value.trim(); if (!id || !d) return;
  $("offMsg").textContent = "Salvando…";
  try { await db.collection("indisponibilidades").add({voluntario:id, data:d, obs, criadoEm:new Date().toISOString()}); $("offMsg").textContent = "Data marcada."; }
  catch (_) {
    const v = vols.find(x => x.id === id) || {}, w = wa(cfg.whatsapp || DEF.whatsapp, `Olá! Sou ${v.nome}, voluntário(a) de ${(v.departamentos || []).join(", ")}. Não poderei servir em ${br(d)}.${obs ? " Motivo: " + obs : ""}`);
    $("offMsg").innerHTML = w ? `Seu acesso não permite salvar aqui. <a href="${esc(w)}" target="_blank" rel="noopener">Avise pelo WhatsApp da igreja</a>.` : "Não foi possível salvar.";
  }
});
document.addEventListener("click", async e => { const b = e.target.closest("[data-deloff]"); if (!b) return; try { await db.collection("indisponibilidades").doc(b.dataset.deloff).delete(); } catch (_) { b.textContent = "sem permissão"; } });

/* ================= candidatura (público) ================= */
const DISP = ["Domingo manhã","Domingo noite","Segunda","Terça","Quarta","Quinta","Sexta","Sábado"];
$("cdDisp").innerHTML = DISP.map(d => `<label><input type="checkbox" value="${esc(d)}"> ${esc(d)}</label>`).join("");
function cdText(c){ return `Olá! Quero servir na Igreja Batista Betel.\n\nNome: ${c.nome}\nWhatsApp: ${c.telefone}\nMembro: ${c.membro}\nTempo: ${c.tempo}\nDons e habilidades: ${c.dons}\nJá serviu: ${c.experiencia || "—"}\nDisponibilidade: ${(c.disponibilidade || []).join(", ") || "—"}\nPor que quero servir: ${c.motivo}`; }
$("cdForm").addEventListener("submit", async e => {
  e.preventDefault();
  if (!digits($("cdTel").value)) { $("cdMsg").textContent = "Confira o WhatsApp: use DDD + número."; return; }
  const m = document.querySelector('input[name=cdm]:checked');
  const c = {nome:$("cdNome").value.trim(), telefone:$("cdTel").value.trim(), membro:m ? m.value : "", tempo:$("cdTempo").value, dons:$("cdDons").value.trim(), experiencia:$("cdExp").value.trim(),
    disponibilidade:[...$("cdDisp").querySelectorAll("input:checked")].map(i => i.value), motivo:$("cdPq").value.trim(), consentimento:true, status:"Nova", enviadoEm:new Date().toISOString()};
  $("cdSend").disabled = true; $("cdMsg").textContent = "Enviando…";
  let saved = false;
  if (db && uid) { try { await db.doc("candidaturas/" + uid).set(c); saved = true; } catch (_) {} }
  else if (db && window.betelAuth) { try { await db.collection("candidaturas").add(c); saved = true; } catch (_) {} }
  const w = wa(cfg.whatsapp || DEF.whatsapp, cdText(c));
  $("cdMsg").textContent = "";
  $("cdDone").innerHTML = saved
    ? `<div class="done"><b>Recebemos sua candidatura, ${esc(c.nome.split(/\s+/)[0])}!</b><span style="color:rgba(255,255,255,.86)">Nossa liderança vai falar com você pelo WhatsApp.</span></div>`
    : `<div class="done"><b>Falta um passo.</b><span style="color:rgba(255,255,255,.86)">Toque no botão abaixo: o WhatsApp da igreja abre com sua candidatura pronta. É só enviar.</span>${w ? `<div><a class="btn btn-p" href="${esc(w)}" target="_blank" rel="noopener">Enviar pelo WhatsApp</a></div>` : ""}</div>`;
  if (saved) $("cdForm").reset();
  $("cdSend").disabled = false;
});

/* ================= Área de Membros ================= */
$("tabs").addEventListener("click", e => { const b = e.target.closest("[data-tab]"); if (!b) return;
  document.querySelectorAll("#tabs button").forEach(x => x.setAttribute("aria-selected", String(x === b)));
  document.querySelectorAll(".pane").forEach(p => p.classList.toggle("on", p.id === "p-" + b.dataset.tab)); });

async function save(col, id, body, msgId, okTxt){
  $(msgId).textContent = "Salvando…";
  try { const ref = id ? db.collection(col).doc(id) : db.collection(col).doc(); await ref.set(body); $(msgId).textContent = okTxt; return ref.id; }
  catch (e) { $(msgId).textContent = e && e.code === "quota_exceeded" ? "Limite de cadastros atingido." : "Não foi possível salvar. Confira sua permissão de edição."; return null; }
}
async function mark(col, id, data){ try { await db.collection(col).doc(id).update(data); } catch (_) {} }

/* eventos */
renderFields("evFields", "ev", F_EV);
function liderBtn(e, dep){
  const L = (cfgPriv.lideres || {})[dep] || {};
  const u = wa(L.tel, fill(cfgPriv.msgLider || DEF.msgLider, {...e, lider:L.nome || "líder", evento:e.titulo, departamento:dep, obs:e.obsEquipe || "—"}));
  const sent = (e.acionados || {})[dep];
  return u ? `<a class="btn ${sent ? "btn-s" : "btn-p"} sm" href="${esc(u)}" target="_blank" rel="noopener" data-acionar="${esc(e.id)}|${esc(dep)}">${sent ? "Avisar de novo" : "Avisar líder de " + esc(dep)}</a>` : `<span class="st">Cadastre o líder de ${esc(dep)}</span>`;
}
function clearEv(){ editing.ev = null; setVals("ev", F_EV, {}); $("evTitle").textContent = "Novo evento"; }
$("evCancel").addEventListener("click", () => { clearEv(); $("evMsg").textContent = ""; $("evDone").innerHTML = ""; });
$("evForm").addEventListener("submit", async ev => {
  ev.preventDefault(); if (!db) return;
  const miss = missing("ev", F_EV); if (miss) { $("evMsg").textContent = "Preencha: " + miss; return; }
  const v = getVals("ev", F_EV);
  if (v.linkInscricao && !/^https:\/\//i.test(v.linkInscricao)) { $("evMsg").textContent = "O link da inscrição precisa começar com https://"; return; }
  const old = events.find(x => x.id === editing.ev) || {};
  const body = {...old, ...v, atualizadoEm:new Date().toISOString()}; delete body.id;
  const id = await save("eventos", editing.ev, body, "evMsg", "Evento salvo. Ele já aparece na agenda e na programação.");
  if (id && (v.precisa || []).length) { const e = {...body, id};
    $("evDone").innerHTML = `<div class="done"><b>Acione os líderes</b><span style="color:rgba(255,255,255,.86)">O WhatsApp abre com a mensagem pronta para cada líder. O evento também fica em "Escalas" até a escala ser montada.</span><div style="display:flex;gap:8px;flex-wrap:wrap">${v.precisa.map(d => liderBtn(e, d)).join("")}</div></div>`; }
  else if (id) $("evDone").innerHTML = "";
  if (id) clearEv();
});

/* membros */
renderFields("mFields", "m", F_M);
function waMembroBtn(m){ const u = wa(m.telefone, fill(cfg.msgMembro, m)); return u ? `<a class="btn btn-p sm" href="${esc(u)}" target="_blank" rel="noopener" data-mark="membros|${esc(m.id)}|boas-vindas">${m.boasVindasEm ? "Enviar de novo" : "Enviar boas-vindas"}</a>` : '<span class="st">WhatsApp inválido</span>'; }
function renderMembros(){
  const q = $("mBusca").value.trim().toLowerCase();
  const list = membros.filter(m => !q || [m.nome, m.bairro, m.telefone].join(" ").toLowerCase().includes(q));
  $("mList").innerHTML = list.length ? list.map(m => `<div class="row"><div><p class="n">${esc(m.nome)}${m.boasVindasEm ? '<span class="st ok">Boas-vindas enviada</span>' : '<span class="st novo">Novo</span>'}</p>
    <p class="m">${esc([m.telefone, m.bairro, m.nascimento ? "Nasc. " + br(m.nascimento) : "", m.estadoCivil, m.admissao, m.desde ? "Membro desde " + br(m.desde) : ""].filter(Boolean).join(" · "))}</p></div>
    <div class="acts">${waMembroBtn(m)}<button class="mini sm" data-edit-m="${esc(m.id)}">Editar</button><button class="mini sm" data-del="membros|${esc(m.id)}">Excluir</button></div></div>`).join("")
    : `<p class="empty" style="padding:24px">${membros.length ? "Nenhum membro encontrado." : "Nenhum membro cadastrado ainda."}</p>`;
}
$("mBusca").addEventListener("input", renderMembros);
function clearM(){ editing.m = null; setVals("m", F_M, {}); $("mTitle").textContent = "Cadastrar membro"; }
$("mCancel").addEventListener("click", () => { clearM(); $("mMsg").textContent = ""; $("mDone").innerHTML = ""; });
$("mForm").addEventListener("submit", async e => {
  e.preventDefault(); const miss = missing("m", F_M); if (miss) { $("mMsg").textContent = "Preencha: " + miss; return; }
  const v = getVals("m", F_M); if (!digits(v.telefone)) { $("mMsg").textContent = "Confira o WhatsApp: use DDD + número."; return; }
  const old = membros.find(m => m.id === editing.m) || {};
  const body = {...old, ...v, atualizadoEm:new Date().toISOString()}; delete body.id; if (!editing.m) body.criadoEm = body.atualizadoEm;
  const id = await save("membros", editing.m, body, "mMsg", "Membro salvo.");
  if (id && !editing.m) { const m = {...body, id}; $("mDone").innerHTML = `<div class="done"><b>${esc(m.nome)} foi cadastrado(a).</b><span style="color:rgba(255,255,255,.86)">Envie agora a mensagem de boas-vindas. O WhatsApp abre com o texto pronto; é só tocar em enviar.</span><div>${waMembroBtn(m)}</div></div>`; }
  if (id) clearM();
});

/* visitantes */
renderFields("vFields", "v", F_V);
const VST = {"novo":"Novo","boas-vindas":"Boas-vindas enviada","elaine":"Com a Elaine"};
function visitBtns(v){
  const b1 = wa(v.telefone, fill(cfg.msgVisitante, v)), b2 = wa(cfgPriv.telefoneElaine, fill(cfgPriv.msgElaine || DEF.msgElaine, v));
  return (b1 ? `<a class="btn ${v.status === "novo" || !v.status ? "btn-p" : "btn-s"} sm" href="${esc(b1)}" target="_blank" rel="noopener" data-mark="visitantes|${esc(v.id)}|boas-vindas">1 · Boas-vindas</a>` : '<span class="st">WhatsApp inválido</span>')
    + (b2 ? `<a class="btn ${v.status === "boas-vindas" ? "btn-p" : "btn-s"} sm" href="${esc(b2)}" target="_blank" rel="noopener" data-mark="visitantes|${esc(v.id)}|elaine">2 · Passar para a Elaine</a>` : '<span class="st">Cadastre o WhatsApp da Elaine</span>');
}
function renderVisitantes(){
  const q = $("vBusca").value.trim().toLowerCase();
  $("vFiltro").innerHTML = ["Todos", ...Object.values(VST)].map(o => `<button class="chip" aria-pressed="${o === vFiltro}" data-vf="${esc(o)}">${esc(o)}</button>`).join("");
  const list = visitantes.filter(v => (!q || (v.nome || "").toLowerCase().includes(q)) && (vFiltro === "Todos" || VST[v.status || "novo"] === vFiltro));
  $("vList").innerHTML = list.length ? list.map(v => `<div class="row"><div><p class="n">${esc(v.nome)}<span class="st ${v.status === "elaine" ? "ok" : v.status === "boas-vindas" ? "" : "novo"}">${esc(VST[v.status || "novo"])}</span>${v.visita ? '<span class="badge" style="margin-left:8px">Quer visita</span>' : ""}</p>
    <p class="m">${esc([v.telefone, "Visitou " + br(v.dataVisita), v.culto, v.primeiraVez === "Sim" ? "1ª vez" : "", v.como, v.bairro].filter(Boolean).join(" · "))}</p>${v.oracao ? `<p class="m" style="color:var(--tinta)">Oração: ${esc(v.oracao)}</p>` : ""}</div>
    <div class="acts">${visitBtns(v)}<button class="mini sm" data-edit-v="${esc(v.id)}">Editar</button><button class="mini sm" data-del="visitantes|${esc(v.id)}">Excluir</button></div></div>`).join("")
    : `<p class="empty" style="padding:24px">${visitantes.length ? "Nenhum visitante neste filtro." : "Nenhum visitante cadastrado ainda."}</p>`;
}
$("vBusca").addEventListener("input", renderVisitantes);
$("vFiltro").addEventListener("click", e => { const b = e.target.closest("[data-vf]"); if (b) { vFiltro = b.dataset.vf; renderVisitantes(); } });
function clearV(){ editing.v = null; setVals("v", F_V, {dataVisita:today()}); $("vTitle").textContent = "Cadastrar visitante"; }
$("vCancel").addEventListener("click", () => { clearV(); $("vMsg").textContent = ""; $("vDone").innerHTML = ""; });
$("vForm").addEventListener("submit", async e => {
  e.preventDefault(); const miss = missing("v", F_V); if (miss) { $("vMsg").textContent = "Preencha: " + miss; return; }
  const v0 = getVals("v", F_V); if (!digits(v0.telefone)) { $("vMsg").textContent = "Confira o WhatsApp: use DDD + número."; return; }
  const old = visitantes.find(v => v.id === editing.v) || {};
  const body = {...old, ...v0, status:old.status || "novo", atualizadoEm:new Date().toISOString()}; delete body.id; if (!editing.v) body.criadoEm = body.atualizadoEm;
  const id = await save("visitantes", editing.v, body, "vMsg", "Visitante salvo.");
  if (id && !editing.v) { const v = {...body, id}; $("vDone").innerHTML = `<div class="done"><b>${esc(v.nome)} foi cadastrado(a).</b><span style="color:rgba(255,255,255,.86)">Passo 1: envie a mensagem de boas-vindas. Passo 2: passe o contato para a Elaine continuar o acompanhamento.</span><div style="display:flex;gap:8px;flex-wrap:wrap">${visitBtns(v)}</div></div>`; }
  if (id) clearV();
});

/* voluntários */
$("volDeps").innerHTML = DEPS.map(d => `<label><input type="checkbox" value="${esc(d)}"> ${esc(d)}</label>`).join("");
function renderVoluntarios(){
  $("volFiltro").innerHTML = ["Todos", ...DEPS].map(o => `<button class="chip" aria-pressed="${o === volFiltro}" data-volf="${esc(o)}">${esc(o)}</button>`).join("");
  const list = vols.filter(v => volFiltro === "Todos" || (v.departamentos || []).includes(volFiltro));
  $("volList").innerHTML = list.length ? list.map(v => { const off = indisp.filter(x => x.voluntario === v.id && isUp(x.data));
    return `<div class="row"><div><p class="n">${esc(v.nome)}</p><div class="chips">${(v.departamentos || []).map(d => `<span>${esc(d)}</span>`).join("")}</div>${volTel[v.id] ? `<p class="m" style="margin-top:8px">WhatsApp: ${esc(volTel[v.id])}</p>` : `<p class="m" style="margin-top:8px">Sem WhatsApp cadastrado</p>`}${off.length ? `<p class="m" style="margin-top:8px">Indisponível: ${esc(off.map(x => br(x.data)).join(", "))}</p>` : ""}</div>
    <div class="acts"><button class="mini sm" data-edit-vol="${esc(v.id)}">Editar</button><button class="mini sm" data-del="voluntarios|${esc(v.id)}">Excluir</button></div></div>`; }).join("")
    : `<p class="empty" style="padding:24px">${vols.length ? "Ninguém neste departamento." : "Nenhum voluntário cadastrado ainda."}</p>`;
  renderEsVols();
}
$("volFiltro").addEventListener("click", e => { const b = e.target.closest("[data-volf]"); if (b) { volFiltro = b.dataset.volf; renderVoluntarios(); } });
function clearVol(){ editing.vol = null; $("volForm").reset(); $("volTitle").textContent = "Cadastrar voluntário"; }
$("volCancel").addEventListener("click", () => { clearVol(); $("volMsg").textContent = ""; });
$("volForm").addEventListener("submit", async e => {
  e.preventDefault();
  const deps = [...$("volDeps").querySelectorAll("input:checked")].map(i => i.value);
  if (!deps.length) { $("volMsg").textContent = "Marque pelo menos um departamento."; return; }
  const tel = $("volTel").value.trim(); if (tel && digits(tel).length < 10) { $("volMsg").textContent = "Confira o WhatsApp: use DDD + número."; return; }
  const id = await save("voluntarios", editing.vol, {nome:$("volNome").value.trim(), departamentos:deps, atualizadoEm:new Date().toISOString()}, "volMsg", "Voluntário salvo.");
  if (id) { try { await db.doc("voluntarios-privado/" + id).set({telefone:tel}); } catch (_) {} clearVol(); }
});

/* escalas */
$("esDep").innerHTML = DEPS.map(d => `<option>${esc(d)}</option>`).join("");
function renderEsEventos(){
  const cur = $("esEvento").value;
  $("esEvento").innerHTML = '<option value="">Nenhum (culto fixo ou outro)</option>' + events.filter(e => isUp(e.data)).map(e => `<option value="${esc(e.id)}">${esc(br(e.data))} · ${esc(e.titulo)}</option>`).join("");
  $("esEvento").value = [...$("esEvento").options].some(o => o.value === cur) ? cur : "";
}
$("esEvento").addEventListener("change", () => { const e = events.find(x => x.id === $("esEvento").value); if (!e) return; $("esData").value = e.data || ""; $("esHora").value = e.hora || ""; $("esCulto").value = e.titulo || ""; renderEsVols(); });
function renderEsVols(){
  const dep = $("esDep").value, d = $("esData").value, checked = new Set([...$("esVols").querySelectorAll("input:checked")].map(i => i.value));
  const list = vols.filter(v => (v.departamentos || []).includes(dep));
  $("esVols").innerHTML = list.length ? list.map(v => { const off = d && isOff(v.id, d) && !checked.has(v.id);
    return `<label class="${off ? "off" : ""}"><input type="checkbox" value="${esc(v.id)}"${checked.has(v.id) ? " checked" : ""}${off ? " disabled" : ""}> ${esc(v.nome)}${off ? " · indisponível" : ""}</label>`; }).join("") : `<p class="notice">Nenhum voluntário cadastrado em ${esc(dep)}.</p>`;
}
$("esDep").addEventListener("change", renderEsVols); $("esData").addEventListener("change", renderEsVols);
function renderPend(){
  const items = [];
  for (const e of events.filter(x => isUp(x.data))) for (const dep of (e.precisa || []))
    if (!escalas.some(s => s.evento === e.id && s.departamento === dep)) items.push({e, dep});
  $("pendList").innerHTML = items.length ? items.map(({e, dep}) => `<div class="pend"><div><span class="badge">${esc(dep)}</span><p class="n" style="font-weight:700;font-size:17px;margin-top:8px">${esc(e.titulo)}</p><p class="m" style="font-size:13px;color:var(--suave)">${esc([br(e.data), e.hora, e.local].filter(Boolean).join(" · "))}${(e.acionados || {})[dep] ? " · líder avisado em " + esc(br(String(e.acionados[dep]).slice(0,10))) : ""}</p></div>
    <div class="acts" style="display:flex;gap:8px;flex-wrap:wrap">${liderBtn(e, dep)}<button class="mini sm" data-montar="${esc(e.id)}|${esc(dep)}">Montar escala</button></div></div>`).join("")
    : '<p class="empty" style="padding:4px 22px 22px">Nenhum evento aguardando escala.</p>';
}
function avisarBtn(s, vid_){
  const nome = volName(vid_) || "voluntário", dt = parseD(s.data);
  const u = wa(volTel[vid_], fill(cfgPriv.msgEscala || DEF.msgEscala, {nome, primeiro:nome.split(" ")[0], departamento:s.departamento, culto:s.culto || "culto", dia:isNaN(dt) ? "" : DIAS[dt.getDay()].toLowerCase(), data:br(s.data), hora:s.hora || "—"}));
  const at = (s.avisados || {})[vid_];
  if (!u) return `<span class="st">${esc(nome.split(" ")[0])}: sem WhatsApp</span>`;
  return `<a class="btn ${at ? "btn-s" : "btn-p"} sm" href="${esc(u)}" target="_blank" rel="noopener" data-avisar="${esc(s.id)}|${esc(vid_)}">${at ? "Avisado · reenviar " : "Avisar "}${esc(nome.split(" ")[0])}</a>`;
}
function renderEscalas(){
  $("esFiltro").innerHTML = ["Próximas", ...DEPS, "Anteriores"].map(o => `<button class="chip" aria-pressed="${o === esFiltro}" data-esf="${esc(o)}">${esc(o)}</button>`).join("");
  const list = escalas.filter(s => esFiltro === "Anteriores" ? !isUp(s.data) : isUp(s.data) && (esFiltro === "Próximas" || s.departamento === esFiltro));
  if (esFiltro === "Anteriores") list.reverse();
  $("esList").innerHTML = list.length ? list.map(s => `<div>${escHTML(s)}<div style="display:flex;gap:8px;padding:0 24px 20px 140px;flex-wrap:wrap">${(s.voluntarios || []).map(v => avisarBtn(s, v)).join("")}<button class="mini sm" data-edit-es="${esc(s.id)}">Editar</button><button class="mini sm" data-del="escalas|${esc(s.id)}">Excluir</button></div></div>`).join("")
    : '<p class="empty" style="padding:24px">Nenhuma escala neste filtro.</p>';
  renderPend(); renderVolOut();
}
$("esFiltro").addEventListener("click", e => { const b = e.target.closest("[data-esf]"); if (b) { esFiltro = b.dataset.esf; renderEscalas(); } });
function clearEs(){ editing.es = null; $("esForm").reset(); $("esTitle").textContent = "Nova escala"; renderEsVols(); }
$("esCancel").addEventListener("click", () => { clearEs(); $("esMsg").textContent = ""; });
$("esForm").addEventListener("submit", async e => {
  e.preventDefault();
  const ids = [...$("esVols").querySelectorAll("input:checked")].map(i => i.value);
  if (!ids.length) { $("esMsg").textContent = "Escolha pelo menos um voluntário."; return; }
  const id = await save("escalas", editing.es, {evento:$("esEvento").value, data:$("esData").value, hora:$("esHora").value, departamento:$("esDep").value, culto:$("esCulto").value.trim(), voluntarios:ids, obs:$("esObs").value.trim(), atualizadoEm:new Date().toISOString()}, "esMsg", "Escala salva.");
  if (id) clearEs();
});

/* candidaturas */
const CDST = ["Nova","Em conversa","Encaminhada","Arquivada"];
function renderCandidaturas(){
  $("cdFiltro").innerHTML = ["Todas", ...CDST].map(o => `<button class="chip" aria-pressed="${o === cdFiltro}" data-cdf="${esc(o)}">${esc(o)}</button>`).join("");
  const list = candidaturas.filter(c => cdFiltro === "Todas" || (c.status || "Nova") === cdFiltro);
  $("cdList").innerHTML = list.length ? list.map(c => { const w = wa(c.telefone, `Olá, ${String(c.nome || "").split(/\s+/)[0]}! Aqui é da Igreja Batista Betel. Recebemos sua candidatura para servir e queremos conversar com você.`);
    return `<div class="row" style="align-items:start"><div><p class="n">${esc(c.nome)}<span class="st ${c.status === "Nova" || !c.status ? "novo" : "ok"}">${esc(c.status || "Nova")}</span></p>
    <p class="m">${esc([c.telefone, c.membro, c.tempo, "Enviada " + br(String(c.enviadoEm || "").slice(0,10))].filter(Boolean).join(" · "))}</p>
    <p style="margin-top:10px"><b>Dons e habilidades:</b> ${esc(c.dons)}</p>${c.experiencia ? `<p style="margin-top:6px"><b>Já serviu:</b> ${esc(c.experiencia)}</p>` : ""}
    <p style="margin-top:6px"><b>Disponibilidade:</b> ${esc((c.disponibilidade || []).join(", ") || "—")}</p><p style="margin-top:6px"><b>Por que quer servir:</b> ${esc(c.motivo)}</p></div>
    <div class="acts" style="flex-direction:column;align-items:stretch">${w ? `<a class="btn btn-p sm" href="${esc(w)}" target="_blank" rel="noopener">Responder no WhatsApp</a>` : ""}
    <label style="font-size:13px">Situação<select data-cdst="${esc(c.id)}">${CDST.map(s => `<option${s === (c.status || "Nova") ? " selected" : ""}>${s}</option>`).join("")}</select></label>
    <button class="mini sm" data-del="candidaturas|${esc(c.id)}">Excluir</button></div></div>`; }).join("")
    : '<p class="empty" style="padding:24px">Nenhuma candidatura neste filtro.</p>';
}
$("cdFiltro").addEventListener("click", e => { const b = e.target.closest("[data-cdf]"); if (b) { cdFiltro = b.dataset.cdf; renderCandidaturas(); } });
$("cdList").addEventListener("change", e => { const s = e.target.closest("[data-cdst]"); if (s) mark("candidaturas", s.dataset.cdst, {status:s.value}); });

/* configurações */
$("cfLideres").innerHTML = NEEDS.map(d => `<label>Líder de ${esc(d)}<input id="lN_${esc(d)}" maxlength="60" placeholder="Nome"></label><label>WhatsApp do líder de ${esc(d)}<input id="lT_${esc(d)}" type="tel" maxlength="20" placeholder="(31) 9 0000-0000"></label>`).join("");
function fillCfgForm(){
  if (document.activeElement && $("cfForm").contains(document.activeElement)) return;
  $("cfWpp").value = cfg.whatsapp || ""; $("cfTel").value = cfg.telefone || DEF.telefone; $("cfPix").value = cfg.pixIgreja || cfg.pix || PIX_IGREJA; $("cfPixJ").value = cfg.pixJuventude || PIX_JUVENTUDE; $("cfTxPix").value = taxa("pix"); $("cfTxDeb").value = taxa("debito"); $("cfTxCred").value = taxa("credito");
  $("cfMsgM").value = cfg.msgMembro || DEF.msgMembro; $("cfMsgV").value = cfg.msgVisitante || DEF.msgVisitante;
  $("cfElaine").value = cfgPriv.telefoneElaine || ""; $("cfMsgE").value = cfgPriv.msgElaine || DEF.msgElaine; $("cfMsgL").value = cfgPriv.msgLider || DEF.msgLider;
  NEEDS.forEach(d => { const L = (cfgPriv.lideres || {})[d] || {}; $("lN_" + d).value = L.nome || ""; $("lT_" + d).value = L.tel || ""; });
}
$("cfForm").addEventListener("submit", async e => {
  e.preventDefault();
  const phones = [["cfWpp","WhatsApp da igreja"],["cfElaine","WhatsApp da Elaine"], ...NEEDS.map(d => ["lT_" + d, "WhatsApp do líder de " + d])];
  for (const [id, label] of phones) if ($(id).value.trim() && !digits($(id).value)) { $("cfMsg").textContent = "Confira o " + label + ": use DDD + número."; return; }
  const lideres = {}; NEEDS.forEach(d => lideres[d] = {nome:$("lN_" + d).value.trim(), tel:$("lT_" + d).value.trim()});
  $("cfMsg").textContent = "Salvando…";
  try {
    await db.doc("config/geral").set({pixIgreja:$("cfPix").value.trim(), pixJuventude:$("cfPixJ").value.trim(), taxas:{pix:Number($("cfTxPix").value || 0), debito:Number($("cfTxDeb").value || 0), credito:Number($("cfTxCred").value || 0)}, whatsapp:$("cfWpp").value.trim(), telefone:$("cfTel").value.trim(), msgMembro:$("cfMsgM").value, msgVisitante:$("cfMsgV").value});
    await db.doc("config-privado/geral").set({telefoneElaine:$("cfElaine").value.trim(), msgElaine:$("cfMsgE").value, msgLider:$("cfMsgL").value, lideres});
    $("cfMsg").textContent = "Configurações salvas.";
  } catch (_) { $("cfMsg").textContent = "Não foi possível salvar."; }
});

/* ações das listas */
document.addEventListener("click", async e => {
  const ac = e.target.closest("[data-acionar]");
  if (ac) { const [id, dep] = ac.dataset.acionar.split("|"); const ev = events.find(x => x.id === id) || {}; mark("eventos", id, {acionados:{...(ev.acionados || {}), [dep]:new Date().toISOString()}}); return; }
  const av = e.target.closest("[data-avisar]");
  if (av) { const [id, vid_] = av.dataset.avisar.split("|"); const s0 = escalas.find(x => x.id === id) || {}; mark("escalas", id, {avisados:{...(s0.avisados || {}), [vid_]:new Date().toISOString()}}); return; }
  const mk = e.target.closest("[data-mark]");
  if (mk) { const [col, id, st] = mk.dataset.mark.split("|"); const now = new Date().toISOString();
    if (col === "membros") mark(col, id, {boasVindasEm:now});
    else { const v = visitantes.find(x => x.id === id) || {}; const order = ["novo","boas-vindas","elaine"];
      const data = st === "elaine" ? {elaineEm:now} : {boasVindasEm:now};
      if (order.indexOf(st) > order.indexOf(v.status || "novo")) data.status = st; mark(col, id, data); }
    return; }
  const del = e.target.closest("[data-del]");
  if (del) { if (del.dataset.confirm !== "1") { del.dataset.confirm = "1"; del.textContent = "Confirmar exclusão"; return; }
    const [col, id] = del.dataset.del.split("|"); try { await db.collection(col).doc(id).delete(); } catch (_) { del.textContent = "Não foi possível excluir"; } return; }
  let b;
  if ((b = e.target.closest("[data-montar]"))) { const [id, dep] = b.dataset.montar.split("|"); clearEs(); $("esEvento").value = id; $("esDep").value = dep;
    const ev = events.find(x => x.id === id) || {}; $("esData").value = ev.data || ""; $("esHora").value = ev.hora || ""; $("esCulto").value = ev.titulo || ""; renderEsVols(); $("esForm").scrollIntoView({behavior:"smooth"}); }
  if ((b = e.target.closest("[data-edit-ev]"))) { const x = events.find(v => v.id === b.dataset.editEv); if (!x) return; editing.ev = x.id; setVals("ev", F_EV, x);
    $("evTitle").textContent = "Editar evento"; $("evForm").scrollIntoView({behavior:"smooth"}); }
  if ((b = e.target.closest("[data-edit-m]"))) { const x = membros.find(v => v.id === b.dataset.editM); if (!x) return; editing.m = x.id; setVals("m", F_M, {...x, consentimento:true});
    $("mTitle").textContent = "Editar membro"; $("mForm").scrollIntoView({behavior:"smooth"}); }
  if ((b = e.target.closest("[data-edit-v]"))) { const x = visitantes.find(v => v.id === b.dataset.editV); if (!x) return; editing.v = x.id; setVals("v", F_V, {...x, consentimento:true});
    $("vTitle").textContent = "Editar visitante"; $("vForm").scrollIntoView({behavior:"smooth"}); }
  if ((b = e.target.closest("[data-edit-vol]"))) { const x = vols.find(v => v.id === b.dataset.editVol); if (!x) return; editing.vol = x.id;
    $("volNome").value = x.nome || ""; $("volTel").value = volTel[x.id] || ""; $("volDeps").querySelectorAll("input").forEach(i => i.checked = (x.departamentos || []).includes(i.value));
    $("volTitle").textContent = "Editar voluntário"; $("volForm").scrollIntoView({behavior:"smooth"}); }
  if ((b = e.target.closest("[data-edit-es]"))) { const x = escalas.find(v => v.id === b.dataset.editEs); if (!x) return; editing.es = x.id;
    $("esEvento").value = x.evento || ""; $("esData").value = x.data || ""; $("esHora").value = x.hora || ""; $("esDep").value = x.departamento || DEPS[0]; $("esCulto").value = x.culto || ""; $("esObs").value = x.obs || "";
    renderEsVols(); $("esVols").querySelectorAll("input").forEach(i => { if ((x.voluntarios || []).includes(i.value)) { i.checked = true; i.disabled = false; } });
    $("esTitle").textContent = "Editar escala"; $("esForm").scrollIntoView({behavior:"smooth"}); }
});

/* ================= 3D: casa neon ================= */
function casa3d(){
  const cv = $("casa3d"); if (!cv) return; if (!window.THREE) { cv.style.display = "none"; return; }
  const T = window.THREE, r = new T.WebGLRenderer({canvas:cv, alpha:true, antialias:true});
  r.setPixelRatio(Math.min(devicePixelRatio, 2));
  const sc = new T.Scene(), cam = new T.PerspectiveCamera(38, 1, .1, 100); cam.position.set(0, 1.2, 9);
  const g = new T.Group(); sc.add(g);
  const P = (x, y, z) => new T.Vector3(x, y, z);
  const w = 1.6, h = 1.5, d = 1.2, ry = 2.75;
  const pts = [P(-w,0,-d),P(w,0,-d),P(w,0,d),P(-w,0,d),P(-w,h,-d),P(w,h,-d),P(w,h,d),P(-w,h,d),P(-w-.25,h-.05,0),P(w+.25,h-.05,0)];
  const E = [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]];
  const roof = [P(0,ry,-d-.2),P(0,ry,d+.2)];
  const segs = [];
  E.forEach(([a,b]) => segs.push(pts[a], pts[b]));
  segs.push(P(-w-.35,h-.1,-d-.2), roof[0], roof[0], P(w+.35,h-.1,-d-.2), P(-w-.35,h-.1,d+.2), roof[1], roof[1], P(w+.35,h-.1,d+.2), roof[0], roof[1]);
  segs.push(P(-.45,0,d), P(-.45,1,d), P(-.45,1,d), P(.45,1,d), P(.45,1,d), P(.45,0,d));
  const geo = new T.BufferGeometry().setFromPoints(segs);
  g.add(new T.LineSegments(geo, new T.LineBasicMaterial({color:0xFFE1B2})));
  const glow = new T.LineSegments(geo, new T.LineBasicMaterial({color:0xFF4F6E, transparent:true, opacity:.55}));
  glow.scale.setScalar(1.025); g.add(glow);
  const book = [];
  for (let i = 0; i <= 16; i++) { const t = i / 16, x = -2.2 + 4.4 * t, y = -.55 + .25 * Math.sin(Math.PI * Math.abs(t - .5) * 2); book.push(P(x, y, d + .6)); }
  g.add(new T.Line(new T.BufferGeometry().setFromPoints(book), new T.LineBasicMaterial({color:0xFFE1B2, transparent:true, opacity:.8})));
  const N = 260, pos = new Float32Array(N * 3);
  for (let i = 0; i < N; i++) { pos[i*3] = (Math.random() - .5) * 12; pos[i*3+1] = (Math.random() - .3) * 7; pos[i*3+2] = (Math.random() - .5) * 8; }
  const pg = new T.BufferGeometry(); pg.setAttribute("position", new T.BufferAttribute(pos, 3));
  const stars = new T.Points(pg, new T.PointsMaterial({color:0xFFE1B2, size:.045, transparent:true, opacity:.75})); sc.add(stars);
  g.position.y = -.6;
  let mx = 0, my = 0, vis = true;
  addEventListener("pointermove", e => { mx = e.clientX / innerWidth - .5; my = e.clientY / innerHeight - .5; }, {passive:true});
  new IntersectionObserver(es => { vis = es[0].isIntersecting; }).observe(cv);
  const size = () => { const W = cv.clientWidth, H = cv.clientHeight; if (!W || !H) return; r.setSize(W, H, false); cam.aspect = W / H; cam.updateProjectionMatrix(); };
  new ResizeObserver(size).observe(cv); size();
  const t0 = performance.now();
  (function loop(){ if (!reduce) requestAnimationFrame(loop); if (!vis || document.hidden) return;
    const t = (performance.now() - t0) / 1000;
    g.rotation.y = t * .35 + mx * .6; g.rotation.x = -.12 + my * .25; g.position.y = -.6 + Math.sin(t * 1.2) * .08;
    stars.rotation.y = t * .03; glow.material.opacity = .4 + .2 * Math.sin(t * 2);
    r.render(sc, cam); })();
}
casa3d();

/* ================= inscrição em eventos ================= */
const idade = nasc => { const n = parseD(nasc); if (isNaN(n)) return null; const t = new Date(); let a = t.getFullYear() - n.getFullYear(); if (t.getMonth() < n.getMonth() || (t.getMonth() === n.getMonth() && t.getDate() < n.getDate())) a--; return a; };
const TERMO_VERSAO = "2026-11";
const NOMES_MET = {pix:"Pix", debito:"Cartão de débito", credito:"Cartão de crédito"};
function termoConsentimento(e){ return termoLGPD(e) + "\n\nUso de imagem: " + termoImagem(e); }
function termoLGPD(e){ return `Ao me inscrever no evento "${e.titulo}", autorizo a Igreja Batista Betel no Flamengo (CNPJ 73.517.948/0001-92) a coletar e usar os dados deste formulário (nome, data de nascimento, contatos, contato de emergência, informações de saúde e, se for o caso, dados e assinatura do responsável) exclusivamente para organizar o evento: inscrição, comunicação, segurança, cuidados de saúde e prestação de contas do pagamento. Os dados não serão vendidos nem compartilhados com terceiros, exceto quando necessário para o próprio evento (por exemplo, seguro, transporte ou atendimento médico) ou por obrigação legal. Posso pedir a qualquer momento acesso, correção ou exclusão dos meus dados pela secretaria da igreja, conforme a Lei Geral de Proteção de Dados (Lei nº 13.709/2018).`; }
function termoImagem(e){ return `Autorizo, de forma gratuita, a Igreja Batista Betel no Flamengo a usar fotos e vídeos em que eu (ou o participante menor sob minha responsabilidade) apareça, registrados durante o evento "${e.titulo}", no site, nas redes sociais, em telões e em materiais de divulgação da igreja e de seus ministérios, sem fins comerciais. A autorização pode ser revogada a qualquer momento pela secretaria da igreja, valendo para publicações futuras.`; }
function termoResp(e, d){ return `Eu, ${d.responsavelNome || "[nome do responsável]"}${d.responsavelDoc ? ", documento " + d.responsavelDoc : ""}, ${(d.responsavelParentesco || "responsável legal").toLowerCase()} de ${d.nome || "[nome do participante]"}${d.nascimento ? ", nascido(a) em " + br(d.nascimento) : ""}, autorizo sua participação no evento "${e.titulo}" (${periodo(e)}${e.local ? ", " + e.local : ""}), promovido pela Igreja Batista Betel no Flamengo. Declaro que as informações de saúde prestadas são verdadeiras e autorizo a equipe responsável a buscar atendimento médico de urgência, se necessário, avisando-me imediatamente pelo telefone ${d.responsavelTel || "informado"}. Comprometo-me a orientar o participante a seguir as regras e os horários do evento.`; }
function renderInscricao(){
  if (!insEvId) return;
  const e = events.find(x => x.id === insEvId), box = $("insBox");
  if (!e) { if (loaded) { $("insTitulo").textContent = "Evento não encontrado"; box.innerHTML = '<p class="empty">Não encontramos este evento. Veja a <a href="#agenda">agenda</a>.</p>'; } return; }
  $("insEyebrow").textContent = "Inscrição · " + (e.ministerio || "Igreja Batista Betel");
  $("insTitulo").textContent = e.titulo;
  $("insMeta").textContent = [periodo(e), e.hora ? "a partir das " + e.hora : "", e.local].filter(Boolean).join(" · ");
  const closed = !e.inscricaoSite || (e.prazoInscricao && !isUp(e.prazoInscricao)) || !isUp(e.dataFim || e.data);
  const v = Number(e.valor || 0), pb = modoEvento(e) === "pagbank";
  const info = `<div class="ins-info glass"><div><p class="eyebrow">Valor</p><b class="ins-valor">${v ? brl(v) : "Gratuito"}</b>${v ? `<small style="display:block;margin-top:6px;color:var(--suave)">+ taxa da forma de pagamento</small>` : ""}</div>${e.vagas ? `<div><p class="eyebrow">Vagas</p><b>${esc(e.vagas)}</b></div>` : ""}${e.prazoInscricao ? `<div><p class="eyebrow">Inscrições até</p><b>${esc(br(e.prazoInscricao))}</b></div>` : ""}<div><p class="eyebrow">Local</p><b>${esc(e.local || "A confirmar")}</b></div></div>${e.descricao ? `<p class="lead" style="margin:28px 0 0">${esc(e.descricao)}</p>` : ""}`;
  if (closed) { box.innerHTML = info + '<p class="notice" style="margin-top:32px">As inscrições para este evento estão encerradas.</p>'; return; }
  const mets = pb ? ["pix","debito","credito"] : ["pix"];
  const pagamento = v ? `<div class="full ins-sec"><h4>Forma de pagamento</h4><p class="m" style="color:var(--suave);font-size:14px;margin:0 0 12px">A taxa de cada forma de pagamento é somada ao valor, para a inscrição chegar completa à igreja.</p>
      <div class="pay-ops" role="radiogroup">${mets.map((m, k) => `<label class="pay-op"><input type="radio" name="iMetodo" value="${m}"${k === 0 ? " checked" : ""}><b>${NOMES_MET[m]}</b><span>${brl(totalCom(v, taxa(m)))}</span>${m === "credito" ? "<small>à vista ou em até 12x (juros do parcelamento por conta de quem paga)</small>" : m === "pix" && !pb ? `<small>QR Code Pix na chave ${esc(chaveEvento(e))}</small>` : ""}</label>`).join("")}</div></div>` : "";
  box.innerHTML = info + `<form class="formcard glass" id="insForm" style="margin-top:40px;max-width:900px" autocomplete="on" novalidate>
    <h3>Seus dados</h3><div class="formgrid">
      <label class="full">Nome completo do participante<input id="iNome" required maxlength="100" autocomplete="name"></label>
      <label>Data de nascimento<input id="iNasc" type="date" required></label>
      <label>WhatsApp<input id="iTel" type="tel" required maxlength="20" placeholder="(31) 9 0000-0000" autocomplete="tel"></label>
      <label class="full">E-mail (a confirmação chega aqui)<input id="iEmail" type="email" required maxlength="120" autocomplete="email"></label>
      <label>Você é da Igreja Batista Betel?<select id="iMembro"><option>Sou membro da Betel</option><option>Congrego na Betel, mas não sou membro</option><option>Sou de outra igreja</option><option>Não frequento igreja</option></select></label>
      <label id="iIgrejaL" hidden>Qual igreja?<input id="iIgreja" maxlength="100"></label>
      <h4>Contato de emergência</h4>
      <label>Nome<input id="iEmNome" required maxlength="100"></label>
      <label>WhatsApp<input id="iEmTel" type="tel" required maxlength="20"></label>
      <div class="full ins-sec" id="iMenor" hidden><h4>Autorização do responsável <span class="tag on" style="margin-left:6px">menor de 18 anos</span></h4>
        <p class="m" style="color:var(--suave);font-size:14px;margin:0 0 12px">O pai, a mãe ou o responsável legal preenche e assina abaixo.</p>
        <div class="formgrid" style="padding:0">
          <label>Nome do responsável<input id="iRespNome" maxlength="100"></label>
          <label>Parentesco<select id="iRespPar"><option>Pai</option><option>Mãe</option><option>Responsável legal</option></select></label>
          <label>CPF ou RG do responsável<input id="iRespDoc" maxlength="20" inputmode="numeric"></label>
          <label>WhatsApp do responsável<input id="iRespTel" type="tel" maxlength="20"></label>
        </div>
        <div class="termo" id="iTermoResp"></div>
        <p style="font-weight:600;font-size:14px;margin:14px 0 8px">Assinatura do responsável</p>
        <div class="ass-wrap"><canvas id="assCanvas" aria-label="Área para assinar com o dedo ou o mouse"></canvas><button class="mini sm" type="button" id="assLimpar">Limpar</button></div>
        <p class="m" style="color:var(--suave);font-size:13px;margin-top:6px">Assine com o dedo (celular) ou com o mouse (computador).</p>
        <label class="check" style="margin-top:10px"><input id="iRespOk" type="checkbox"> Sou o responsável legal pelo participante, li e assino esta autorização.</label>
      </div>
      <h4>Saúde e cuidados</h4>
      <label class="full">Alergias, medicamentos ou restrições alimentares (opcional)<textarea id="iSaude" maxlength="500" placeholder="Ex.: alergia a camarão, uso de insulina"></textarea></label>
      <div class="full ins-sec"><h4>Termos</h4>
        <details class="termo-d"><summary>Termo de consentimento (uso de dados e de imagem)</summary><div class="termo" style="white-space:pre-line">${esc(termoConsentimento(e))}</div></details>
        <label class="check"><input id="iOk" type="checkbox" required> Li e aceito o termo de consentimento, incluindo a autorização de uso de imagem nos eventos.</label>
        <p class="m" style="color:var(--suave);font-size:13px;margin:6px 0 0">O aceite do termo é obrigatório para participar do evento.</p>
      </div>
      ${pagamento}
    </div>
    <div style="display:flex;gap:12px;flex-wrap:wrap;align-items:center;margin-top:8px"><button class="btn btn-p" type="submit" id="iSend">Confirmar inscrição</button><span class="msg" id="iMsg"></span></div>
  </form>`;
  updTermoResp();
}
function insDados(){ return {nome:$("iNome").value.trim(), nascimento:$("iNasc").value, responsavelNome:$("iRespNome").value.trim(), responsavelDoc:$("iRespDoc").value.trim(), responsavelParentesco:$("iRespPar").value, responsavelTel:$("iRespTel").value.trim()}; }
function updTermoResp(){ const e = events.find(x => x.id === insEvId); if (e && $("iTermoResp")) $("iTermoResp").textContent = termoResp(e, insDados()); }
const assHas = {};
function initAssinatura(cid = "assCanvas", lid = "assLimpar"){
  const c = $(cid); if (!c || c.dataset.ini) return; const w = c.clientWidth; if (!w) return;
  c.dataset.ini = "1"; const dpr = Math.max(1, window.devicePixelRatio || 1); c.width = w * dpr; c.height = 180 * dpr;
  const x = c.getContext("2d"); x.scale(dpr, dpr); x.fillStyle = "#fff"; x.fillRect(0, 0, w, 180); x.lineWidth = 2.4; x.lineCap = "round"; x.lineJoin = "round"; x.strokeStyle = "#1a0b0b";
  let on = false; const pos = ev => { const r = c.getBoundingClientRect(); return [ev.clientX - r.left, ev.clientY - r.top]; };
  c.addEventListener("pointerdown", ev => { on = true; c.setPointerCapture(ev.pointerId); const [a, b] = pos(ev); x.beginPath(); x.moveTo(a, b); x.lineTo(a + .1, b + .1); x.stroke(); assHas[cid] = true; });
  c.addEventListener("pointermove", ev => { if (!on) return; const [a, b] = pos(ev); x.lineTo(a, b); x.stroke(); });
  const fim = () => { on = false; }; c.addEventListener("pointerup", fim); c.addEventListener("pointercancel", fim);
  $(lid).onclick = () => { x.fillStyle = "#fff"; x.fillRect(0, 0, w, 180); assHas[cid] = false; };
}
document.addEventListener("change", e => {
  if (e.target.id === "iMembro") $("iIgrejaL").hidden = e.target.value !== "Sou de outra igreja";
  if (e.target.id === "iNasc") { const a = idade(e.target.value); $("iMenor").hidden = !(a !== null && a < 18); if (!$("iMenor").hidden) setTimeout(initAssinatura, 30); }
  if (e.target.closest && e.target.closest("#iMenor, #iNome, #iNasc")) updTermoResp();
});
document.addEventListener("input", e => { if (["iNome","iRespNome","iRespDoc","iRespTel"].includes(e.target.id)) updTermoResp(); });
function insTexto(d, e){ return `Olá! Fiz minha inscrição no ${e.titulo}.\nProtocolo: ${d.protocolo || "—"}\nNome: ${d.nome}\nNascimento: ${br(d.nascimento)}\nWhatsApp: ${d.telefone}\nE-mail: ${d.email}\nIgreja: ${d.membro}${d.igreja ? " (" + d.igreja + ")" : ""}${d.metodo ? "\nForma de pagamento: " + NOMES_MET[d.metodo] : ""}`; }
document.addEventListener("submit", async ev => {
  if (ev.target.id !== "insForm") return; ev.preventDefault();
  const e = events.find(x => x.id === insEvId); if (!e) return;
  const met = document.querySelector('input[name=iMetodo]:checked');
  const d = {evento:e.id, nome:$("iNome").value.trim(), nascimento:$("iNasc").value, telefone:$("iTel").value.trim(), email:$("iEmail").value.trim(), membro:$("iMembro").value,
    igreja:$("iIgreja").value.trim(), emergenciaNome:$("iEmNome").value.trim(), emergenciaTel:$("iEmTel").value.trim(), saude:$("iSaude").value.trim(),
    metodo:met ? met.value : "", consentimento:$("iOk").checked, imagem:$("iOk").checked ? "Autorizo" : "", termoVersao:TERMO_VERSAO, aceiteEm:new Date().toISOString()};
  const a = idade(d.nascimento), menor = a !== null && a < 18;
  if (menor) Object.assign(d, {responsavelNome:$("iRespNome").value.trim(), responsavelParentesco:$("iRespPar").value, responsavelDoc:$("iRespDoc").value.trim(), responsavelTel:$("iRespTel").value.trim(), autorizacaoResp:$("iRespOk").checked});
  const falta = [!d.nome && "nome", !d.nascimento && "data de nascimento", !digits(d.telefone) && "WhatsApp", !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(d.email) && "e-mail", !d.emergenciaNome && "contato de emergência", !digits(d.emergenciaTel) && "WhatsApp de emergência",
    menor && !d.responsavelNome && "nome do responsável", menor && String(d.responsavelDoc).replace(/\W/g, "").length < 5 && "CPF ou RG do responsável", menor && !digits(d.responsavelTel) && "WhatsApp do responsável", menor && !assHas.assCanvas && "assinatura do responsável", menor && !$("iRespOk").checked && "confirmação do responsável",
    !d.consentimento && "aceite do termo de consentimento (obrigatório para participar)", Number(e.valor) > 0 && !d.metodo && "forma de pagamento"].filter(Boolean);
  if (falta.length) { $("iMsg").textContent = "Falta: " + falta.join(", ") + "."; return; }
  if (menor) { d.assinatura = $("assCanvas").toDataURL("image/png"); d.termoResponsavel = termoResp(e, d); }
  $("iSend").disabled = true; $("iMsg").textContent = "Enviando…";
  let res = null;
  try {
    if (window.betelAuth) { const r = await fetch("/api/inscricoes", {method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify(d)}); const j = await r.json(); if (!r.ok) throw new Error(j.erro || "Erro"); res = j; }
    else if (db && uid) { const p = "BET-" + Math.random().toString(36).slice(2, 8).toUpperCase(); await db.doc("inscricoes/" + uid).set({...d, protocolo:p, valor:e.valor || 0, eventoTitulo:e.titulo, status:Number(e.valor) > 0 ? "Aguardando pagamento" : "Pago", criadoEm:new Date().toISOString()}); res = {protocolo:p, valor:e.valor || 0}; }
  } catch (err) { if (window.betelAuth) { $("iMsg").textContent = err.message; $("iSend").disabled = false; return; } }
  const w = wa(cfg.whatsapp || DEF.whatsapp, insTexto({...d, protocolo:res && res.protocolo}, e) + (res ? "" : "\n\n(Inscrição enviada pelo WhatsApp)"));
  const pago = res && res.valor > 0;
  payCtx = {i:{id:res && res.id, chave:res && res.chave, protocolo:res && res.protocolo, valor:res && res.valor, nome:d.nome}, e, online:!!(res && res.pagamentoOnline)};
  $("insBox").innerHTML = `<div class="card glass" id="insDone" style="max-width:760px"><p class="eyebrow">Inscrição ${res ? "recebida" : "quase pronta"}</p>
    <h3 style="font-size:clamp(28px,4vw,40px)">${res ? `Tudo certo, ${esc(d.nome.split(/\s+/)[0])}!` : "Falta um passo"}</h3>
    ${res ? `<p class="lead">Sua inscrição no <b>${esc(e.titulo)}</b> foi registrada${menor ? ", com a autorização assinada pelo responsável" : ""}.</p><div class="ins-prot"><span>Protocolo</span><b>${esc(res.protocolo)}</b></div>
      ${res.emailEnviado ? `<p style="color:var(--suave)">Enviamos a confirmação para <b>${esc(d.email)}</b>. Se não encontrar, olhe no spam.</p>` : `<p style="color:var(--suave)">Guarde o seu protocolo. Faça um print desta tela.</p>`}`
    : `<p class="lead">Toque no botão abaixo: o WhatsApp da igreja abre com a sua inscrição pronta. É só enviar.</p>`}
    ${pago ? `<div class="ins-pay" id="insPay">${payBox(payCtx.i, e, payCtx.online, d.metodo)}</div>` : ""}
    <div class="ctas" style="margin-top:20px">${w ? `<a class="btn ${res ? "btn-s" : "btn-p"}" href="${esc(w)}" target="_blank" rel="noopener">${res ? "Falar com a igreja no WhatsApp" : "Enviar pelo WhatsApp"}</a>` : ""}<a class="btn btn-s" href="#agenda">Ver a agenda</a></div></div>`;
  window.scrollTo({top:0, behavior:"smooth"});
});
let payCtx = null;
document.addEventListener("click", async e => {
  const tr = e.target.closest("[data-trocar]");
  if (tr && payCtx) { $("insPay").innerHTML = payBox(payCtx.i, payCtx.e, payCtx.online); return; }
  const cp = e.target.closest("[data-copiar]");
  if (cp) { const t = $(cp.dataset.copiar); try { await navigator.clipboard.writeText(t.value); } catch (_) { t.select(); document.execCommand && document.execCommand("copy"); } cp.textContent = "Copiado!"; setTimeout(() => cp.textContent = "Copiar código Pix", 1800); return; }
  const b = e.target.closest("[data-pagar]"); if (!b) return; document.querySelectorAll("[data-pagar]").forEach(x => x.disabled = true); $("insPgMsg").textContent = "Abrindo o pagamento seguro do PagBank…";
  try { const r = await fetch(`/api/inscricoes/${encodeURIComponent(b.dataset.id)}/pagar`, {method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify({chave:b.dataset.chave, metodo:b.dataset.pagar})}); const j = await r.json(); if (!r.ok) throw new Error(j.erro || "Erro"); location.href = j.url; }
  catch (err) { $("insPgMsg").textContent = err.message || "Não foi possível abrir o pagamento."; document.querySelectorAll("[data-pagar]").forEach(x => x.disabled = false); }
});
/* pagamento: taxas repassadas para quem paga (a igreja recebe 100%) */
const TAXAS_PADRAO = {pix:0.99, debito:1.99, credito:4.99};
const PIX_IGREJA = "73.517.948/0001-92", PIX_JUVENTUDE = "(31) 99178-4222";
const taxa = m => { const t = (cfg.taxas || {})[m]; return t === undefined || t === "" || isNaN(Number(t)) ? TAXAS_PADRAO[m] : Number(t); };
const totalCom = (valor, pct) => Math.ceil(Number(valor) / (1 - pct / 100) * 100) / 100;
const modoEvento = e => String(e.pagamento || "").startsWith("PagBank") ? "pagbank" : "pix";
const chaveEvento = e => e.chavePix || (e.ministerio === "Juventude Mergulhados" ? (cfg.pixJuventude || PIX_JUVENTUDE) : (cfg.pixIgreja || cfg.pix || PIX_IGREJA));
function pixChave(k){ k = String(k || "").trim(); const d = k.replace(/\D/g, "");
  if (k.includes("@")) return k.toLowerCase();
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(k)) return k.toLowerCase();
  if (d.length === 14) return d;                                   // CNPJ
  if (/^\+/.test(k) || /\(/.test(k) || (d.length >= 10 && d.length <= 11 && !/\./.test(k))) return "+" + (d.startsWith("55") && d.length > 11 ? d : "55" + d);  // telefone
  return d || k; }
const semAcento = s => String(s).normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^A-Za-z0-9 ]/g, "").toUpperCase();
function brCode(chave, valor, txid){
  const f = (id, v) => id + String(v.length).padStart(2, "0") + v;
  const mai = f("00", "br.gov.bcb.pix") + f("01", pixChave(chave));
  let p = f("00", "01") + f("26", mai) + f("52", "0000") + f("53", "986") + f("54", Number(valor).toFixed(2)) + f("58", "BR") + f("59", "IGREJA BATISTA BETEL") + f("60", "CONTAGEM") + f("62", f("05", (String(txid || "").replace(/[^A-Za-z0-9]/g, "") || "***").slice(0, 25))) + "6304";
  let c = 0xFFFF; for (let i = 0; i < p.length; i++) { c ^= p.charCodeAt(i) << 8; for (let j = 0; j < 8; j++) c = (c & 0x8000) ? ((c << 1) ^ 0x1021) & 0xFFFF : (c << 1) & 0xFFFF; }
  return p + c.toString(16).toUpperCase().padStart(4, "0");
}
function qrImg(texto){ try { const q = qrcode(0, "M"); q.addData(texto); q.make(); return `<img class="pix-qr" src="${q.createDataURL(6, 12)}" alt="QR Code Pix">`; } catch (_) { return ""; } }
function pixBox(i, e){
  const total = totalCom(i.valor, taxa("pix")), code = brCode(chaveEvento(e), total, i.protocolo || "BETEL");
  const w = wa(cfg.whatsapp || DEF.whatsapp, `Olá! Fiz o Pix da minha inscrição no ${e.titulo}.\nProtocolo: ${i.protocolo || "—"}\nValor: ${brl(total)}\n(Segue o comprovante)`);
  return `<div class="pix-box">${qrImg(code)}<div><p><b>Pix · ${brl(total)}</b></p><p style="font-size:14px;color:var(--suave)">Abra o app do seu banco, escolha Pix → Ler QR Code, ou use o Pix copia e cola. O valor já vem preenchido.</p>
    <textarea id="pixCode" readonly rows="3" style="width:100%;font-size:12px">${esc(code)}</textarea>
    <div class="ctas" style="margin-top:10px"><button class="btn btn-p sm" type="button" data-copiar="pixCode">Copiar código Pix</button>${w ? `<a class="btn btn-s sm" href="${esc(w)}" target="_blank" rel="noopener">Enviar comprovante</a>` : ""}</div></div></div>
    <p class="seguro">🔒 Antes de confirmar no banco, confira o destinatário e a chave: <b>${esc(chaveEvento(e))}</b>. Depois de pagar, envie o comprovante: a equipe confirma a sua inscrição.</p>`;
}
function payBox(i, e, online, metodo){
  const v = Number(i.valor || 0); if (!v) return "";
  const pb = modoEvento(e) === "pagbank";
  const head = `<p class="eyebrow">Pagamento · inscrição ${brl(v)}</p>`;
  const msg = '<span class="msg" id="insPgMsg"></span>';
  if (!metodo) {
    if (pb && online) return head + `<p style="color:var(--suave);font-size:14px">A taxa da forma de pagamento é somada ao valor, para a inscrição chegar completa à igreja.</p><div class="pay-ops">${["pix","debito","credito"].map(m => `<button class="pay-op" type="button" data-pagar="${m}" data-id="${esc(i.id)}" data-chave="${esc(i.chave)}"><b>${NOMES_MET[m]}</b><span>${brl(totalCom(v, taxa(m)))}</span>${m === "credito" ? "<small>à vista ou em até 12x (juros do parcelamento por conta de quem paga)</small>" : ""}</button>`).join("")}</div>
      <p class="seguro">🔒 O pagamento abre no ambiente seguro do PagBank. A confirmação chega por e-mail assim que o pagamento é aprovado.</p>` + msg;
    return head + pixBox(i, e) + msg;
  }
  const total = totalCom(v, taxa(metodo)), trocar = pb ? `<button class="linkbtn" type="button" data-trocar="1" style="margin-top:10px">Trocar a forma de pagamento</button>` : "";
  if (pb && online) return head + `<p>Forma escolhida: <b>${NOMES_MET[metodo]}</b> · ${brl(total)}${metodo === "credito" ? " à vista (no parcelamento, os juros do cartão são somados pelo PagBank)" : ""}</p>
    <button class="btn btn-p" type="button" data-pagar="${metodo}" data-id="${esc(i.id)}" data-chave="${esc(i.chave)}">Pagar ${brl(total)} no PagBank</button>
    <p class="seguro">🔒 O pagamento abre no ambiente seguro do PagBank. A confirmação chega por e-mail assim que o pagamento é aprovado.</p>${trocar}` + msg;
  if (metodo === "pix") return head + pixBox(i, e) + msg;
  const w = wa(cfg.whatsapp || DEF.whatsapp, `Olá! Fiz minha inscrição no ${e.titulo} (protocolo ${i.protocolo || "—"}) e quero pagar com ${NOMES_MET[metodo].toLowerCase()}: ${brl(total)}. Pode me enviar o link de pagamento?`);
  return head + `<p>Forma escolhida: <b>${NOMES_MET[metodo]}</b> · ${brl(total)}</p><p style="color:var(--suave);font-size:14px">O pagamento com cartão é feito pelo link seguro do PagBank. Peça o seu link à igreja pelo WhatsApp, ou pague agora por Pix.</p>
    <div class="ctas">${w ? `<a class="btn btn-p sm" href="${esc(w)}" target="_blank" rel="noopener">Pedir o link de pagamento</a>` : ""}<button class="btn btn-s sm" type="button" data-trocar="1">Pagar com Pix</button></div>` + msg;
}
async function renderPagar(par){
  const [id, chave] = par.split("."); $("insEyebrow").textContent = "Pagamento da inscrição"; $("insTitulo").textContent = "Pagamento"; $("insMeta").textContent = "";
  if (!window.betelAuth) { $("insBox").innerHTML = '<p class="empty">Abra o link pelo site da igreja.</p>'; return; }
  $("insBox").innerHTML = '<p class="empty">Carregando a sua inscrição…</p>';
  try { const r = await fetch(`/api/inscricoes/${encodeURIComponent(id)}/resumo?chave=${encodeURIComponent(chave)}`); const i = await r.json(); if (!r.ok) throw new Error(i.erro);
    const e = events.find(x => x.id === i.evento) || {titulo:i.eventoTitulo, ministerio:i.ministerio, pagamento:i.pagamento, chavePix:i.chavePix};
    $("insTitulo").textContent = i.eventoTitulo;
    $("insBox").innerHTML = `<div class="card glass" style="max-width:760px"><p class="lead">Inscrição de <b>${esc(i.nome)}</b></p><div class="ins-prot"><span>Protocolo</span><b>${esc(i.protocolo)}</b></div>
      ${i.status === "Pago" ? '<p class="lead">✅ Esta inscrição já está paga e confirmada.</p>' : `<div class="ins-pay" id="insPay">${payBox({...i, id, chave}, e, i.pagamentoOnline)}</div>`}</div>`;
    payCtx = {i:{...i, id, chave}, e, online:i.pagamentoOnline};
  } catch (err) { $("insBox").innerHTML = `<p class="empty">${esc(err.message || "Não encontramos esta inscrição.")} Fale com a igreja pelo WhatsApp.</p>`; }
}
/* ================= autorização de uso de imagem (eventos e cultos) ================= */
const ESCOPO_GERAL = "Todos os cultos e eventos da Igreja Batista Betel";
function fillImgEscopo(){ const s = $("iaEscopo"); if (!s) return; const cur = s.value;
  s.innerHTML = `<option>${ESCOPO_GERAL}</option>` + events.filter(e => isUp(e.dataFim || e.data)).map(e => `<option value="${esc(e.titulo)}">Somente: ${esc(e.titulo)} (${esc(br(e.data))})</option>`).join("");
  if ([...s.options].some(o => o.value === cur)) s.value = cur; }
function imgDados(){ const r = document.querySelector('input[name=iaResp]:checked'); return {nome:$("iaNome").value.trim(), nascimento:$("iaNasc").value, escopo:$("iaEscopo").value || ESCOPO_GERAL, resposta:r ? r.value : "",
  responsavelNome:$("iaRespNome").value.trim(), responsavelParentesco:$("iaRespPar").value, responsavelDoc:$("iaRespDoc").value.trim(), responsavelTel:$("iaRespTel").value.trim()}; }
function termoImagemGeral(d){
  const a = idade(d.nascimento), menor = a !== null && a < 18, quem = d.nome || "[nome do participante]", aut = d.resposta === "Não autorizo" ? "NÃO AUTORIZO" : "AUTORIZO";
  const onde = d.escopo && d.escopo !== ESCOPO_GERAL ? `no evento "${d.escopo}"` : "nos cultos, eventos e atividades";
  const abertura = menor ? `Eu, ${d.responsavelNome || "[nome do responsável]"}${d.responsavelDoc ? ", documento " + d.responsavelDoc : ""}, ${(d.responsavelParentesco || "responsável legal").toLowerCase()} de ${quem}${d.nascimento ? ", nascido(a) em " + br(d.nascimento) : ""}, ${aut} o uso da imagem e da voz do(a) menor` : `Eu, ${quem}${d.nascimento ? ", nascido(a) em " + br(d.nascimento) : ""}, ${aut} o uso da minha imagem e da minha voz`;
  return `${abertura}, captadas em fotos e vídeos ${onde} da Igreja Batista Betel no Flamengo (CNPJ 73.517.948/0001-92), para publicação no site, nas redes sociais, em transmissões ao vivo, em telões e em materiais de divulgação da igreja e de seus ministérios, de forma gratuita e sem fins comerciais. Esta autorização vale por tempo indeterminado e pode ser revogada a qualquer momento pela secretaria da igreja, valendo para publicações futuras, conforme o art. 20 do Código Civil e a Lei Geral de Proteção de Dados (Lei nº 13.709/2018).`;
}
function updImgTermo(){ if (!$("iaTermo")) return; const d = imgDados(), a = idade(d.nascimento); $("iaMenor").hidden = !(a !== null && a < 18); $("iaAssLbl").textContent = $("iaMenor").hidden ? "Assinatura do participante" : "Assinatura do responsável"; $("iaTermo").textContent = termoImagemGeral(d); }
document.addEventListener("input", e => { if (e.target.closest && e.target.closest("#imgForm")) updImgTermo(); });
document.addEventListener("change", e => { if (e.target.closest && e.target.closest("#imgForm")) updImgTermo(); });
document.addEventListener("submit", async ev => {
  if (ev.target.id !== "imgForm") return; ev.preventDefault();
  const d = {...imgDados(), telefone:$("iaTel").value.trim(), email:$("iaEmail").value.trim()}, a = idade(d.nascimento), menor = a !== null && a < 18;
  if (!menor) ["responsavelNome","responsavelParentesco","responsavelDoc","responsavelTel"].forEach(k => delete d[k]);
  const falta = [!d.nome && "nome", !d.nascimento && "data de nascimento", !digits(d.telefone) && "WhatsApp", !d.resposta && "sua resposta (autorizo ou não autorizo)",
    menor && !d.responsavelNome && "nome do responsável", menor && String(d.responsavelDoc || "").replace(/\W/g, "").length < 5 && "CPF ou RG do responsável", menor && !digits(d.responsavelTel) && "WhatsApp do responsável",
    !assHas.imgCanvas && "assinatura", !$("iaOk").checked && "confirmação"].filter(Boolean);
  if (falta.length) { $("iaMsg").textContent = "Falta: " + falta.join(", ") + "."; return; }
  Object.assign(d, {termo:termoImagemGeral(d), assinatura:$("imgCanvas").toDataURL("image/png"), termoVersao:TERMO_VERSAO, aceiteEm:new Date().toISOString()});
  $("iaSend").disabled = true; $("iaMsg").textContent = "Enviando…"; let prot = null;
  try {
    if (window.betelAuth) { const r = await fetch("/api/imagem", {method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify(d)}); const j = await r.json(); if (!r.ok) throw new Error(j.erro || "Erro"); prot = j.protocolo; }
    else if (db && uid) { prot = "IMG-" + Math.random().toString(36).slice(2, 8).toUpperCase(); await db.doc("autorizacoes-imagem/" + uid).set({...d, protocolo:prot, criadoEm:new Date().toISOString()}); }
  } catch (err) { if (window.betelAuth) { $("iaMsg").textContent = err.message; $("iaSend").disabled = false; return; } }
  const w = wa(cfg.whatsapp || DEF.whatsapp, `Autorização de uso de imagem\nNome: ${d.nome}\nNascimento: ${br(d.nascimento)}\nResposta: ${d.resposta}\nAbrangência: ${d.escopo}${menor ? "\nResponsável: " + d.responsavelNome + " (" + d.responsavelParentesco + ")" : ""}`);
  $("imgBox").innerHTML = `<div class="card glass" style="max-width:760px"><p class="eyebrow">Autorização de uso de imagem</p><h3 style="font-size:clamp(28px,4vw,40px)">${prot ? "Resposta registrada!" : "Falta um passo"}</h3>
    ${prot ? `<p class="lead">Obrigado, ${esc(d.nome.split(/\s+/)[0])}. Sua resposta (<b>${esc(d.resposta)}</b>) foi registrada para: ${esc(d.escopo)}.</p><div class="ins-prot"><span>Protocolo</span><b>${esc(prot)}</b></div><p style="color:var(--suave)">Para mudar a sua resposta depois, fale com a secretaria.</p>`
      : `<p class="lead">Toque no botão abaixo para enviar a sua resposta pelo WhatsApp da igreja.</p>${w ? `<div><a class="btn btn-p" href="${esc(w)}" target="_blank" rel="noopener">Enviar pelo WhatsApp</a></div>` : ""}`}</div>`;
  window.scrollTo({top:0, behavior:"smooth"});
});
let imgFiltro = "", imgBusca = "";
function renderImgAdm(){
  if (!$("imgList")) return;
  const q = imgBusca.toLowerCase(), list = autImg.filter(i => (!imgFiltro || i.resposta === imgFiltro) && (!q || String(i.nome).toLowerCase().includes(q)));
  const nao = autImg.filter(i => i.resposta === "Não autorizo").length;
  $("imgKpis").innerHTML = `<div><span>Respostas</span><b>${autImg.length}</b></div><div><span>Autorizam</span><b>${autImg.length - nao}</b></div><div><span>Não autorizam</span><b>${nao}</b></div>`;
  $("imgList").innerHTML = list.length ? list.map(i => { const a = idade(i.nascimento);
    return `<div class="row"><div><p class="n">${esc(i.nome)}<span class="st ${i.resposta === "Autorizo" ? "ok" : ""}">${esc(i.resposta)}</span></p>
      <p class="m">${esc([i.protocolo, a !== null ? a + " anos" : "", i.telefone, i.escopo, "em " + br(String(i.criadoEm || i.aceiteEm || "").slice(0, 10))].filter(Boolean).join(" · "))}</p>
      ${i.responsavelNome ? `<p class="m" style="margin-top:6px">Responsável: ${esc(i.responsavelNome)} (${esc(i.responsavelParentesco || "")}) · ${esc(i.responsavelTel || "")}</p>` : ""}</div>
      <div class="acts"><button class="mini sm" data-ver-img="${esc(i.id)}">Ver termo e assinatura</button><button class="mini sm" data-del="autorizacoes-imagem|${esc(i.id)}">Excluir</button></div></div>`; }).join("")
    : '<p class="empty" style="padding:24px">Nenhuma autorização neste filtro.</p>';
}
document.addEventListener("change", e => { if (e.target.id === "imgFiltro") { imgFiltro = e.target.value; renderImgAdm(); } });
document.addEventListener("input", e => { if (e.target.id === "imgBusca") { imgBusca = e.target.value; renderImgAdm(); } });
document.addEventListener("click", e => {
  const b = e.target.closest("[data-ver-img]"); if (!b) return; const i = autImg.find(x => x.id === b.dataset.verImg); if (!i) return;
  document.body.insertAdjacentHTML("beforeend", `<div id="modalBg" class="modal-bg"><div class="modal-c" role="dialog" aria-modal="true" aria-label="Autorização de uso de imagem">
    <div class="modal-top"><b>Autorização de uso de imagem · ${esc(i.protocolo || "")}</b><div style="display:flex;gap:8px"><button class="mini sm" data-imprimir="1">Imprimir / salvar PDF</button><button class="mini sm" data-fechar-modal="1">Fechar</button></div></div>
    <div class="modal-doc"><p><b>Igreja Batista Betel no Flamengo</b> · CNPJ 73.517.948/0001-92</p><h4>Autorização de uso de imagem e voz — ${esc(String(i.resposta || "").toUpperCase())}</h4><p>${esc(i.termo || termoImagemGeral(i))}</p>
      <p><b>Abrangência:</b> ${esc(i.escopo || ESCOPO_GERAL)}<br><b>Registrado em:</b> ${esc(i.aceiteEm ? new Date(i.aceiteEm).toLocaleString("pt-BR") : "—")} · versão ${esc(i.termoVersao || "—")}<br><b>Contato:</b> ${esc(i.telefone || "")}${i.email ? " · " + esc(i.email) : ""}</p>
      ${i.assinatura ? `<p><b>Assinatura ${i.responsavelNome ? "do responsável" : "do participante"}:</b></p><img class="ass-img" src="${esc(i.assinatura)}" alt="Assinatura"><p>${esc(i.responsavelNome || i.nome)}${i.responsavelDoc ? " · " + esc(i.responsavelDoc) : ""}</p>` : ""}</div></div></div>`);
});
document.addEventListener("click", async e => { if (e.target.id !== "imgCsv") return;
  const cols = ["protocolo","nome","nascimento","telefone","email","resposta","escopo","responsavelNome","responsavelParentesco","responsavelDoc","responsavelTel","aceiteEm"];
  const q = v => '"' + String(v ?? "").replace(/"/g, '""') + '"', csv = "﻿" + cols.join(";") + "\n" + autImg.map(i => cols.map(c => q(i[c])).join(";")).join("\n");
  let dl = null; try { dl = await window.claude?.use("downloads"); } catch (_) {}
  if (dl) { try { await dl.save({filename:"autorizacoes-imagem.csv", data:csv}); } catch (_) {} return; }
  const a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([csv], {type:"text/csv;charset=utf-8"})); a.download = "autorizacoes-imagem.csv"; a.click(); });
function renderPagamento(st){
  const T = {aprovado:["Pagamento aprovado!","Sua inscrição está confirmada. Você vai receber a confirmação por e-mail."], pendente:["Pagamento em análise","Assim que o pagamento for confirmado, você recebe um e-mail. Pix costuma confirmar em poucos minutos."], recusado:["Pagamento não concluído","Nada foi cobrado. Você pode tentar de novo pelo link do e-mail de inscrição ou falar com a igreja no WhatsApp."]}[st] || ["Obrigado!", ""];
  $("pgTitulo").textContent = T[0]; $("pgTexto").textContent = T[1];
}
/* inscrições: Área de Membros */
let insFiltroEv = "", insFiltroSt = "";
function renderInscricoesAdm(){
  if (!$("insEv")) return;
  const evs = events.filter(e => e.inscricaoSite || inscricoes.some(i => i.evento === e.id));
  if (!insFiltroEv && evs.length) insFiltroEv = (evs.find(e => isUp(e.dataFim || e.data)) || evs[0]).id;
  $("insEv").innerHTML = evs.map(e => `<option value="${esc(e.id)}"${e.id === insFiltroEv ? " selected" : ""}>${esc(br(e.data))} · ${esc(e.titulo)}</option>`).join("") || '<option value="">Nenhum evento com inscrição pelo site</option>';
  const ev = events.find(e => e.id === insFiltroEv) || {};
  const all = inscricoes.filter(i => i.evento === insFiltroEv), list = all.filter(i => !insFiltroSt || (i.status || "Aguardando pagamento") === insFiltroSt);
  const pagos = all.filter(i => i.status === "Pago"), ativos = all.filter(i => i.status !== "Cancelada");
  $("insKpis").innerHTML = `<div><span>Inscritos</span><b>${ativos.length}${ev.vagas ? " / " + esc(ev.vagas) : ""}</b></div><div><span>Pagos</span><b>${pagos.length}</b></div><div><span>Aguardando</span><b>${ativos.length - pagos.length}</b></div><div><span>Arrecadado</span><b>${brl(pagos.reduce((s, i) => s + Number(i.valor || 0), 0))}</b></div>`;
  $("insList").innerHTML = list.length ? list.map(i => { const a = idade(i.nascimento), st = i.status || "Aguardando pagamento";
    const w = wa(i.telefone, st === "Pago" ? `Olá, ${String(i.nome).split(/\s+/)[0]}! Sua inscrição no ${i.eventoTitulo || ev.titulo} está confirmada. Protocolo ${i.protocolo}. Te esperamos!` : `Olá, ${String(i.nome).split(/\s+/)[0]}! Recebemos sua inscrição no ${i.eventoTitulo || ev.titulo} (protocolo ${i.protocolo}). Falta só o pagamento de ${brl(i.valor)} para confirmar.`);
    return `<div class="row" style="align-items:start"><div><p class="n">${esc(i.nome)}<span class="st ${st === "Pago" ? "ok" : st === "Cancelada" ? "" : "novo"}">${esc(st)}</span></p>
      <p class="m">${esc([i.protocolo, a !== null ? a + " anos" : "", i.telefone, i.email, i.membro + (i.igreja ? " · " + i.igreja : "")].filter(Boolean).join(" · "))}</p>
      <p class="m" style="margin-top:6px">Emergência: ${esc(i.emergenciaNome)} ${esc(i.emergenciaTel)}${i.responsavelNome ? " · Responsável: " + esc(i.responsavelNome) + " " + esc(i.responsavelTel) : ""}</p>
      ${i.saude ? `<p class="m" style="margin-top:6px"><b>Saúde:</b> ${esc(i.saude)}</p>` : ""}
      <p class="m" style="margin-top:6px">${i.consentimento ? "✓ Termo de consentimento aceito (dados e imagem)" : "Termo de consentimento não registrado"}${i.responsavelNome ? (i.assinatura ? " · ✓ Autorização do responsável assinada" : " · Sem assinatura do responsável") : ""}${i.metodo ? " · Pagamento escolhido: " + esc(NOMES_MET[i.metodo] || i.metodo) : ""}</p>${i.pagoEm ? `<p class="m" style="margin-top:6px">Pago em ${esc(br(String(i.pagoEm).slice(0,10)))}${i.pagamentoId ? " · pago online" + (i.parcelas > 1 ? " em " + esc(i.parcelas) + "x" : "") + " · " + esc(i.pagamentoId) : " · registrado pela equipe"}</p>` : ""}</div>
      <div class="acts" style="flex-direction:column;align-items:stretch">${w ? `<a class="btn btn-p sm" href="${esc(w)}" target="_blank" rel="noopener">WhatsApp</a>` : ""}
      <label style="font-size:13px">Situação<select data-insst="${esc(i.id)}">${["Aguardando pagamento","Pago","Cancelada"].map(o => `<option${o === st ? " selected" : ""}>${o}</option>`).join("")}</select></label>
      <button class="mini sm" data-ver-termo="${esc(i.id)}">Ver termos${i.assinatura ? " e assinatura" : ""}</button>
      <button class="mini sm" data-del="inscricoes|${esc(i.id)}">Excluir</button></div></div>`; }).join("")
    : '<p class="empty" style="padding:24px">Nenhuma inscrição neste filtro.</p>';
}
document.addEventListener("change", e => {
  if (e.target.id === "insEv") { insFiltroEv = e.target.value; renderInscricoesAdm(); }
  if (e.target.id === "insSt") { insFiltroSt = e.target.value; renderInscricoesAdm(); }
  const s = e.target.closest("[data-insst]"); if (s) { const up = {status:s.value}; if (s.value === "Pago") up.pagoEm = new Date().toISOString(); mark("inscricoes", s.dataset.insst, up); }
});
document.addEventListener("click", e => {
  if (e.target.closest("[data-fechar-modal]") || e.target.id === "modalBg") { const m = $("modalBg"); if (m) m.remove(); return; }
  if (e.target.closest("[data-imprimir]")) { window.print(); return; }
  const b = e.target.closest("[data-ver-termo]"); if (!b) return;
  const i = inscricoes.find(x => x.id === b.dataset.verTermo); if (!i) return;
  const ev = events.find(x => x.id === i.evento) || {titulo:i.eventoTitulo};
  const bloco = (t, txt) => `<h4>${t}</h4><p>${esc(txt)}</p>`;
  document.body.insertAdjacentHTML("beforeend", `<div id="modalBg" class="modal-bg"><div class="modal-c" role="dialog" aria-modal="true" aria-label="Termos da inscrição">
    <div class="modal-top"><b>Termos da inscrição · ${esc(i.protocolo || "")}</b><div style="display:flex;gap:8px"><button class="mini sm" data-imprimir="1">Imprimir / salvar PDF</button><button class="mini sm" data-fechar-modal="1">Fechar</button></div></div>
    <div class="modal-doc"><p><b>Igreja Batista Betel no Flamengo</b> · CNPJ 73.517.948/0001-92</p><p><b>Evento:</b> ${esc(ev.titulo)} · <b>Participante:</b> ${esc(i.nome)} (${esc(br(i.nascimento))}) · <b>Protocolo:</b> ${esc(i.protocolo || "")}</p>
      <p><b>Aceite registrado em:</b> ${esc(i.aceiteEm ? new Date(i.aceiteEm).toLocaleString("pt-BR") : "—")} · versão dos termos ${esc(i.termoVersao || "—")}</p>
      ${bloco("Termo de consentimento (uso de dados e de imagem) — " + (i.consentimento ? "ACEITO" : "não registrado"), termoLGPD(ev))}<p>${esc("Uso de imagem: " + termoImagem(ev))}</p>
      ${i.responsavelNome ? bloco("Autorização do responsável (" + (i.responsavelParentesco || "responsável") + ")", i.termoResponsavel || termoResp(ev, i)) + (i.assinatura ? `<p><b>Assinatura do responsável:</b></p><img class="ass-img" src="${esc(i.assinatura)}" alt="Assinatura de ${esc(i.responsavelNome)}"><p>${esc(i.responsavelNome)} · ${esc(i.responsavelDoc || "")} · ${esc(i.responsavelTel || "")}</p>` : "<p><b>Sem assinatura registrada.</b></p>") : ""}
    </div></div></div>`);
});
document.addEventListener("click", async e => { if (e.target.id !== "insCsv") return;
  const rows = inscricoes.filter(i => i.evento === insFiltroEv), cols = ["protocolo","nome","nascimento","telefone","email","membro","igreja","emergenciaNome","emergenciaTel","responsavelNome","responsavelParentesco","responsavelDoc","responsavelTel","saude","consentimento","imagem","metodo","status","valor","pagoEm","criadoEm"];
  const q = v => '"' + String(v ?? "").replace(/"/g, '""') + '"';
  const csv = "﻿" + cols.join(";") + "\n" + rows.map(i => cols.map(c => q(i[c])).join(";")).join("\n");
  const nome = "inscricoes-" + insFiltroEv + ".csv";
  let dl = null; try { dl = await window.claude?.use("downloads"); } catch (_) {}
  if (dl) { try { await dl.save({filename:nome, data:csv}); } catch (_) {} return; }
  const a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([csv], {type:"text/csv;charset=utf-8"})); a.download = nome; a.click(); });

/* ================= acesso por função ================= */
const on = new Set(); const once = (k, fn) => { if (!on.has(k)) { on.add(k); fn(); } };
function startSubs(r){
  if (!["owner","secretaria","lider"].includes(r)) return;
  once("priv", () => db.doc("config-privado/geral").onSnapshot(s => { cfgPriv = {telefoneElaine:"", msgElaine:DEF.msgElaine, msgLider:DEF.msgLider, lideres:{}, ...(s.exists ? s.data() : {})}; fillCfgForm(); renderVisitantes(); renderPend(); }, () => {}));
  once("insc", () => sub(db.collection("inscricoes").orderBy("criadoEm", "desc"), d => { inscricoes = d; renderInscricoesAdm(); }));
  once("img", () => sub(db.collection("autorizacoes-imagem").orderBy("criadoEm", "desc"), d => { autImg = d; renderImgAdm(); }));
  once("acessos", () => { sub(db.collection("pedidos").orderBy("enviadoEm"), d => { pedidos = d; renderAcessos(); }); sub(db.collection("papeis"), d => { papeis = d; renderAcessos(); }); });
  if (r !== "lider") once("sec", () => { sub(db.collection("membros").orderBy("nome"), d => { membros = d; renderMembros(); }); sub(db.collection("visitantes").orderBy("dataVisita", "desc"), d => { visitantes = d; renderVisitantes(); }); clearV(); });
  if (r !== "secretaria") once("lid", () => { sub(db.collection("voluntarios-privado"), d => { volTel = Object.fromEntries(d.map(x => [x.id, x.telefone || ""])); renderVoluntarios(); renderEscalas(); }); sub(db.collection("candidaturas").orderBy("enviadoEm", "desc"), d => { candidaturas = d; renderCandidaturas(); }); });
  renderEsVols(); fillCfgForm();
}
const LEADS = {owner:"Você é o responsável pelo site e vê todas as áreas.", secretaria:"Agenda, membros, visitantes, contatos e liberação de acessos.", lider:"Voluntários, escalas e candidaturas de quem deseja servir."};
let liderFiltroSet = false;
function applyRole(){
  const r = role(), tabs = ROLE_TABS[r] || [];
  $("admin").hidden = !tabs.length;
  document.querySelectorAll("#tabs [data-tab]").forEach(b => { b.hidden = !tabs.includes(b.dataset.tab); });
  const cur = document.querySelector('#tabs [aria-selected="true"]');
  if (tabs.length && (!cur || cur.hidden)) document.querySelector(`#tabs [data-tab="${tabs[0]}"]`).click();
  $("admTitle").innerHTML = r === "owner" ? "Área de <em>Membros</em>." : r === "secretaria" ? "<em>Secretaria</em>." : r === "lider" ? `<em>Liderança</em>${papel.ministerio ? " · " + esc(papel.ministerio) : ""}.` : "Área de <em>Membros</em>.";
  $("admLead").textContent = LEADS[r] || "Secretaria, líderes de ministério e voluntários entram com a própria conta e veem só o que é da sua função.";
  if (r === "lider" && papel.ministerio && DEPS.includes(papel.ministerio) && !liderFiltroSet) { liderFiltroSet = true; volFiltro = papel.ministerio; esFiltro = papel.ministerio; $("esDep").value = papel.ministerio; }
  startSubs(r); renderGate(); syncVolPick(); renderVolOut(); renderAcessos();
  if (canEdit) { renderVoluntarios(); renderEscalas(); }
}
function renderGate(){
  if (window.BETEL_SUPABASE) return; // versão Supabase: a Área de Membros é tratada por equipe-sb.js
  const g = $("admGate"), r = role();
  if (!db) { g.innerHTML = '<p class="msg">Para entrar, abra o site conectado à sua conta Claude. O acesso é por convite: peça à secretaria.</p>'; return; }
  renderAuthBar();
  if (window.betelAuth && !uid) { if (!g.querySelector("#loginForm")) g.innerHTML = `<form class="card glass" id="loginForm" style="max-width:520px"><h3 id="lgTitle">Entrar</h3><p style="color:var(--suave);font-size:15px" id="lgInfo">Use o e-mail e a senha da sua conta de membro da Igreja Batista Betel.</p>
    <label id="lgNomeL" hidden>Seu nome<input id="lgNome" maxlength="80" autocomplete="name"></label>
    <label>E-mail<input id="lgEmail" type="email" required autocomplete="email"></label>
    <label>Senha<input id="lgSenha" type="password" required minlength="8" autocomplete="current-password"></label>
    <div style="display:flex;gap:10px;flex-wrap:wrap"><button class="btn btn-p" type="submit" id="lgBtn">Entrar</button><button class="btn btn-s" type="button" id="lgModo">Primeiro acesso? Criar conta</button></div>
    <span class="msg" id="lgMsg"></span><p class="notice">Esqueceu a senha? Peça uma senha provisória à secretaria.</p></form>`; return; }
  if (!roleReady) return;
  if (ROLE_TABS[r]) { g.innerHTML = ""; return; }
  if (r === "voluntario") { g.innerHTML = `<div class="card glass" style="max-width:640px"><h3>Olá${papel.nome ? ", " + esc(String(papel.nome).split(" ")[0]) : ""}!</h3><p style="color:var(--suave)">Você entrou como voluntário(a). Sua escala e suas indisponibilidades ficam em Minha escala.</p><div><a class="btn btn-p" href="#voluntario">Ver minha escala</a></div></div>`; return; }
  if (papel && (papel.papel === "secretaria" || papel.papel === "lider")) { g.innerHTML = `<div class="card glass" style="max-width:640px"><h3>Acesso quase pronto</h3><p style="color:var(--suave)">Sua função de ${esc(PAPEL_NOME[papel.papel])} foi liberada, mas o convite deste site precisa ser como Editor. Peça ao responsável pelo site para alterar o compartilhamento.</p></div>`; return; }
  if (myPedido && !g.dataset.edit) { g.innerHTML = `<div class="card glass" style="max-width:640px"><h3>Pedido enviado</h3><p style="color:var(--suave)">Você pediu acesso como ${esc(PAPEL_NOME[myPedido.papel] || "")} em ${esc(br(String(myPedido.enviadoEm || "").slice(0,10)))}. Assim que for liberado, suas áreas aparecem aqui.</p><div><button class="btn btn-s" type="button" id="rqEdit">Alterar pedido</button></div></div>`; return; }
  if (g.querySelector("#reqForm")) { fillRqVol(); return; }
  g.innerHTML = `<form class="card glass" id="reqForm" style="max-width:640px" autocomplete="off"><h3>Solicitar acesso</h3><p style="color:var(--suave);font-size:15px">Diga quem você é. A secretaria ou o líder do ministério libera o seu acesso.</p>
    <label>Seu nome<input id="rqNome" required maxlength="80"></label>
    <label>Você é<select id="rqPapel"><option value="voluntario">Voluntário(a)</option><option value="lider">Líder de ministério</option><option value="secretaria">Secretaria</option></select></label>
    <label id="rqVolL">Seu nome na lista de voluntários<select id="rqVol"></select></label>
    <label id="rqDepL" hidden>Ministério que você lidera<select id="rqDep">${DEPS.map(d => `<option>${esc(d)}</option>`).join("")}</select></label>
    <div><button class="btn btn-p" type="submit">Enviar pedido</button></div><span class="msg" id="rqMsg"></span></form>`;
  if (myPedido) { $("rqNome").value = myPedido.nome || ""; $("rqPapel").value = myPedido.papel || "voluntario"; if (myPedido.ministerio) $("rqDep").value = myPedido.ministerio; }
  fillRqVol(); rqToggle();
}
function renderAuthBar(){
  const b = $("authBar"); if (!b) return; if (!window.betelAuth || !uid) { b.hidden = true; return; }
  window.betelAuth.me().then(m => { b.hidden = false; b.innerHTML = `Conectado como <b>${esc(m.email || "")}</b> · <button type="button" class="linkbtn" id="trocaSenha">Trocar senha</button> · <button type="button" class="linkbtn" id="sair">Sair</button><span id="tsBox"></span>`;
    if (m.trocarSenha && !sessionStorageGet("betelPular") && !$("primeiroAcesso")) b.insertAdjacentHTML("afterend", `<form class="card glass" id="primeiroAcesso" style="max-width:560px;margin-bottom:32px" autocomplete="off"><p class="eyebrow">Primeiro acesso</p><h3>Crie a sua senha</h3>
      <p style="color:var(--suave);font-size:15px">Você entrou com uma senha provisória. Crie agora uma senha só sua, com pelo menos 8 caracteres. Se preferir, faça isso depois em Trocar senha.</p>
      <label>Nova senha<input type="password" id="paNova" minlength="8" required autocomplete="new-password"></label>
      <label>Repita a nova senha<input type="password" id="paConf" minlength="8" required autocomplete="new-password"></label>
      <div style="display:flex;gap:10px;flex-wrap:wrap"><button class="btn btn-p" type="submit">Salvar minha senha</button><button class="btn btn-s" type="button" id="paDepois">Agora não</button></div><span class="msg" id="paMsg"></span></form>`); });
}
function sessionStorageGet(k){ try { return sessionStorage.getItem(k); } catch (_) { return null; } }
function sessionStorageSet(k, v){ try { sessionStorage.setItem(k, v); } catch (_) {} }
document.addEventListener("click", e => { if (e.target.id === "paDepois") { sessionStorageSet("betelPular", "1"); $("primeiroAcesso").remove(); } });
document.addEventListener("submit", async e => {
  if (e.target.id !== "primeiroAcesso") return; e.preventDefault();
  const n = $("paNova").value, c = $("paConf").value;
  if (n.length < 8) { $("paMsg").textContent = "Use pelo menos 8 caracteres."; return; }
  if (n !== c) { $("paMsg").textContent = "As duas senhas não são iguais."; return; }
  $("paMsg").textContent = "Salvando…";
  try { await window.betelAuth.trocarSenha("", n); $("primeiroAcesso").innerHTML = '<p class="eyebrow">Primeiro acesso</p><h3>Senha criada!</h3><p style="color:var(--suave)">A partir de agora, entre com o seu e-mail e a senha que você acabou de criar.</p>'; }
  catch (err) { $("paMsg").textContent = err.message || "Não foi possível salvar."; }
});
let lgCriar = false;
document.addEventListener("click", async e => {
  if (e.target.id === "lgModo") { lgCriar = !lgCriar; $("lgNomeL").hidden = !lgCriar; $("lgTitle").textContent = lgCriar ? "Criar conta" : "Entrar"; $("lgBtn").textContent = lgCriar ? "Criar conta" : "Entrar";
    $("lgInfo").textContent = lgCriar ? "Crie sua conta com seu e-mail. Depois você envia o pedido de acesso e a secretaria ou o líder libera." : "Use o e-mail e a senha da sua conta de membro da Igreja Batista Betel.";
    $("lgModo").textContent = lgCriar ? "Já tenho conta. Entrar" : "Primeiro acesso? Criar conta"; $("lgSenha").autocomplete = lgCriar ? "new-password" : "current-password"; }
  if (e.target.id === "sair") { try { await window.betelAuth.logout(); } catch (_) {} location.reload(); }
  if (e.target.id === "trocaSenha") $("tsBox").innerHTML = `<form id="tsForm" style="display:flex;gap:8px;flex-wrap:wrap;margin-top:12px"><input type="password" id="tsAtual" placeholder="Senha atual" required autocomplete="current-password"><input type="password" id="tsNova" placeholder="Nova senha (8+)" minlength="8" required autocomplete="new-password"><button class="btn btn-p sm" type="submit">Salvar</button><span class="msg" id="tsMsg"></span></form>`;
  const ns = e.target.closest("[data-ac-senha]");
  if (ns) { ns.textContent = "Gerando…"; try { const r = await window.betelAuth.novaSenha(ns.dataset.acSenha); ns.outerHTML = `<span class="st ok">Senha provisória: <b>${esc(r.senha)}</b> · envie à pessoa e peça para trocar</span>`; } catch (err) { ns.textContent = err.message || "Não foi possível"; } }
});
document.addEventListener("submit", async e => {
  if (e.target.id === "tsForm") { e.preventDefault(); try { await window.betelAuth.trocarSenha($("tsAtual").value, $("tsNova").value); $("tsMsg").textContent = "Senha alterada."; setTimeout(() => location.reload(), 900); } catch (err) { $("tsMsg").textContent = err.message; } return; }
  if (e.target.id !== "loginForm") return; e.preventDefault();
  const em = $("lgEmail").value.trim(), pw = $("lgSenha").value; $("lgMsg").textContent = lgCriar ? "Criando conta…" : "Entrando…";
  try { if (lgCriar) await window.betelAuth.signup(em, pw, $("lgNome").value.trim()); else await window.betelAuth.login(em, pw); location.reload(); }
  catch (err) { $("lgMsg").textContent = err.message || "Não foi possível entrar."; }
});
function fillRqVol(){ const s = $("rqVol"); if (!s) return; const cur = s.value || (myPedido && myPedido.voluntario) || "";
  s.innerHTML = '<option value="">Ainda não estou na lista</option>' + vols.map(v => `<option value="${esc(v.id)}">${esc(v.nome)}</option>`).join(""); s.value = vols.some(v => v.id === cur) ? cur : ""; }
function rqToggle(){ const p = $("rqPapel").value; $("rqVolL").hidden = p !== "voluntario"; $("rqDepL").hidden = p !== "lider"; }
document.addEventListener("change", e => { if (e.target.id === "rqPapel") rqToggle(); });
document.addEventListener("click", e => { if (e.target.id === "rqEdit") { $("admGate").dataset.edit = "1"; $("admGate").innerHTML = ""; renderGate(); } });
document.addEventListener("submit", async e => {
  if (e.target.id !== "reqForm") return; e.preventDefault();
  const p = $("rqPapel").value, body = {nome:$("rqNome").value.trim(), papel:p, enviadoEm:new Date().toISOString()};
  if (p === "voluntario") body.voluntario = $("rqVol").value; if (p === "lider") body.ministerio = $("rqDep").value;
  $("rqMsg").textContent = "Enviando…";
  try { await db.doc("pedidos/" + uid).set(body); delete $("admGate").dataset.edit; myPedido = body; renderGate(); }
  catch (_) { $("rqMsg").textContent = window.betelAuth ? "Não foi possível enviar. Tente de novo em instantes." : "Não foi possível enviar. O convite deste site precisa ser como Colaborador (voluntários) ou Editor (secretaria e líderes)."; }
});
function canApprove(p){ const r = role(); return r === "owner" || (r === "secretaria" && (p === "lider" || p === "voluntario")) || (r === "lider" && p === "voluntario"); }
function papelDesc(p){ if (p.papel === "master") return "Acesso total" + (p.voluntario ? " · Cadastro: " + (volName(p.voluntario) || "—") : ""); return p.papel === "voluntario" ? (p.voluntario ? "Cadastro: " + (volName(p.voluntario) || "não encontrado") : "Ainda não está na lista de voluntários") : p.papel === "lider" ? "Ministério: " + (p.ministerio || "—") : "Agenda, membros e visitantes"; }
function renderAcessos(){
  if (!$("acPend")) return; const r = role(); if (!ROLE_TABS[r]) return;
  const vis = p => r !== "lider" || p.papel === "voluntario";
  if (window.betelAuth && $("acHow")) $("acHow").textContent = "Como liberar alguém: 1) a pessoa abre a Área de Membros e cria a conta com o próprio e-mail. 2) Envia o pedido dizendo quem é. 3) O pedido aparece aqui para liberar. Se alguém esquecer a senha, gere uma senha provisória na lista abaixo.";
  $("acInfo").textContent = r === "lider" ? "Você libera o acesso dos voluntários. Confira se a pessoa escolheu o nome certo no cadastro." : r === "secretaria" ? "Você libera voluntários e líderes. Acesso de secretaria é liberado pelo responsável pelo site." : "Você libera qualquer função.";
  const pend = pedidos.filter(vis), list = papeis.filter(vis).sort((a, b) => String(a.nome).localeCompare(String(b.nome)));
  $("acPend").innerHTML = pend.length ? pend.map(p => `<div class="row"><div><p class="n">${esc(p.nome || "Sem nome")}<span class="st novo">${esc(PAPEL_NOME[p.papel] || p.papel)}</span></p><p class="m">${esc(papelDesc(p))} · pedido em ${esc(br(String(p.enviadoEm || "").slice(0,10)))}</p></div>
    <div class="acts">${canApprove(p.papel) ? `<button class="btn btn-p sm" data-ac-ok="${esc(p.id)}">Liberar</button>` : '<span class="st">Aguardando o responsável</span>'}<button class="mini sm" data-del="pedidos|${esc(p.id)}">Recusar</button></div></div>`).join("")
    : '<p class="empty" style="padding:4px 22px 22px">Nenhum pedido aguardando.</p>';
  $("acList").innerHTML = list.length ? list.map(p => `<div class="row"><div><p class="n">${esc(p.nome || "Sem nome")}${p.id === uid ? " (você)" : ""}<span class="st ok">${esc(PAPEL_NOME[p.papel] || p.papel)}</span></p><p class="m">${esc(papelDesc(p))}</p></div>
    <div class="acts">${(p.papel === "voluntario" || p.papel === "master") && canApprove(p.papel) ? `<label style="font-size:13px">Ligar ao cadastro<select data-ac-vol="${esc(p.id)}"><option value="">—</option>${vols.map(v => `<option value="${esc(v.id)}"${v.id === p.voluntario ? " selected" : ""}>${esc(v.nome)}</option>`).join("")}</select></label>` : ""}${r === "owner" && p.id !== uid && p.papel !== "master" ? `<button class="mini sm" data-ac-master="${esc(p.id)}">Tornar master</button>` : ""}${window.betelAuth && p.id !== uid && (r === "owner" || (r === "secretaria" && canApprove(p.papel))) ? `<button class="mini sm" data-ac-senha="${esc(p.id)}">Gerar senha provisória</button>` : ""}${canApprove(p.papel) && p.id !== uid ? `<button class="mini sm" data-del="papeis|${esc(p.id)}">Remover acesso</button>` : ""}</div></div>`).join("")
    : '<p class="empty" style="padding:4px 22px 22px">Ninguém liberado ainda.</p>';
}
document.addEventListener("click", async e => { const b = e.target.closest("[data-ac-ok]"); if (!b) return;
  const p = pedidos.find(x => x.id === b.dataset.acOk); if (!p || !canApprove(p.papel)) return; b.textContent = "Liberando…";
  const doc = {nome:p.nome || "", papel:p.papel, aprovadoEm:new Date().toISOString(), aprovadoPor:uid}; if (p.voluntario) doc.voluntario = p.voluntario; if (p.ministerio) doc.ministerio = p.ministerio;
  try { await db.doc("papeis/" + p.id).set(doc); await db.doc("pedidos/" + p.id).delete(); } catch (_) { b.textContent = "Não foi possível liberar"; } });
document.addEventListener("click", e => { const b = e.target.closest("[data-ac-master]"); if (!b || role() !== "owner") return;
  if (b.dataset.confirm !== "1") { b.dataset.confirm = "1"; b.textContent = "Confirmar: acesso total"; return; }
  b.textContent = "Salvando…"; mark("papeis", b.dataset.acMaster, {papel:"master"}); });
document.addEventListener("change", e => { const s = e.target.closest("[data-ac-vol]"); if (!s) return; mark("papeis", s.dataset.acVol, {voluntario:s.value}); });

/* ================= banco de dados ================= */
function sub(q, cb){ q.onSnapshot(s => cb(s.docs.map(d => ({id:d.id, ...d.data()})), s), () => {}); }
(async () => {
  let user = null;
  try { db = await window.claude?.use("db"); user = await window.claude?.use("user"); } catch (_) {}
  if (!db) { loaded = true; renderEvents(); renderVolOut(); renderGate(); return; }
  try { canEdit = !!(user && await user.canEdit()); } catch (_) { canEdit = false; }
  try { isOwn = !!(user && await user.isOwner()); } catch (_) { isOwn = false; }
  try { uid = user ? await user.id() : null; } catch (_) { uid = null; }
  const timer = setTimeout(() => { if (!loaded) { loaded = true; renderEvents(); renderVolOut(); } if (!roleReady) { roleReady = true; applyRole(); } }, 10000);
  sub(db.collection("eventos").orderBy("data"), (d, s) => { events = d; if (!s.metadata.fromCache) { loaded = true; clearTimeout(timer); } renderEvents(); renderInscricoesAdm(); });
  sub(db.collection("voluntarios").orderBy("nome"), d => { vols = d; loaded = true; renderVolPick(); fillRqVol(); renderAcessos(); if (canEdit) { renderVoluntarios(); renderEscalas(); } });
  sub(db.collection("escalas").orderBy("data"), d => { escalas = d; renderVolOut(); if (canEdit) renderEscalas(); });
  sub(db.collection("indisponibilidades").orderBy("data"), d => { indisp = d; renderVolOut(); if (canEdit) { renderVoluntarios(); renderEscalas(); } });
  db.doc("config/geral").onSnapshot(s => { cfg = {...DEF, ...(s.exists ? s.data() : {})}; renderContato(); if (canEdit) { fillCfgForm(); renderMembros(); renderVisitantes(); } }, () => {});
  if (uid) {
    db.doc("pedidos/" + uid).onSnapshot(s => { myPedido = s.exists ? s.data() : null; renderGate(); }, () => {});
    db.doc("papeis/" + uid).onSnapshot(s => { papel = s.exists ? s.data() : null; roleReady = true; applyRole(); }, () => { roleReady = true; applyRole(); });
  } else { roleReady = true; applyRole(); }
})();

renderContato(); route(); renderEvents();
}
