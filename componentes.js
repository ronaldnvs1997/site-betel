/* Componentes compartilhados (comportamento): mensagem rápida no padrão do site, ícones
   e o botão "mostrar / ocultar" dos campos de senha. */
(() => {
  let caixa, tempo;
  function aviso(texto, tipo) {
    if (!caixa) { caixa = document.createElement("div"); caixa.className = "cp-toast"; caixa.setAttribute("role", "status"); caixa.setAttribute("aria-live", "polite"); document.body.appendChild(caixa); caixa.addEventListener("click", () => caixa.classList.remove("on")); }
    caixa.textContent = String(texto ?? ""); caixa.classList.toggle("erro", tipo === "erro");
    requestAnimationFrame(() => caixa.classList.add("on"));
    clearTimeout(tempo); tempo = setTimeout(() => caixa.classList.remove("on"), Math.min(9000, 3500 + String(texto).length * 40));
  }

  /* ---------- ícones (traço fino, mesmo desenho do botão do WhatsApp) ---------- */
  const P = {
    painel: '<rect x="3.5" y="3.5" width="7" height="7" rx="2"/><rect x="13.5" y="3.5" width="7" height="7" rx="2"/><rect x="3.5" y="13.5" width="7" height="7" rx="2"/><rect x="13.5" y="13.5" width="7" height="7" rx="2"/>',
    agenda: '<rect x="3.5" y="5" width="17" height="15.5" rx="3"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
    solicitacoes: '<path d="M4 13.5 6.5 5h11l2.5 8.5V19a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 19z"/><path d="M4 13.5h4.5l1.5 2.5h4l1.5-2.5H20"/>',
    usuarios: '<circle cx="9" cy="8.5" r="3.5"/><path d="M2.5 20c.6-3.6 3.2-5.5 6.5-5.5s5.9 1.9 6.5 5.5"/><path d="M16 5.2a3.3 3.3 0 0 1 0 6.6M18 14.8c2 .8 3.2 2.5 3.5 5.2"/>',
    ministerios: '<path d="m12 3.5 8.5 4.5-8.5 4.5L3.5 8z"/><path d="m3.5 12 8.5 4.5 8.5-4.5M3.5 16l8.5 4.5 8.5-4.5"/>',
    historico: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
    conta: '<circle cx="12" cy="8.5" r="4"/><path d="M4 20.5c.9-4 4-6 8-6s7.1 2 8 6"/>',
    equipe: '<circle cx="7" cy="9" r="2.8"/><circle cx="17" cy="9" r="2.8"/><circle cx="12" cy="7" r="3"/><path d="M2.5 19c.4-2.6 2.2-4 4.5-4M21.5 19c-.4-2.6-2.2-4-4.5-4M6.5 20c.6-3.2 2.7-5 5.5-5s4.9 1.8 5.5 5"/>',
    cursos: '<path d="M4 5.5A1.5 1.5 0 0 1 5.5 4H11v16H5.5A1.5 1.5 0 0 1 4 18.5zM20 5.5A1.5 1.5 0 0 0 18.5 4H13v16h5.5a1.5 1.5 0 0 0 1.5-1.5z"/>',
    secretaria: '<rect x="5" y="4.5" width="14" height="16" rx="2.5"/><path d="M9 3.5h6v3H9zM8.5 11h7M8.5 15h5"/>',
    tesouraria: '<rect x="3" y="6.5" width="18" height="12" rx="2.5"/><path d="M3 10.5h18"/><circle cx="16.5" cy="14.5" r="1.2"/>',
    membresia: '<rect x="3" y="5" width="18" height="14" rx="2.5"/><circle cx="8.5" cy="11" r="2.2"/><path d="M5.5 16c.5-1.7 1.6-2.6 3-2.6s2.5.9 3 2.6M14 10h4M14 13.5h3"/>',
    candidatos: '<circle cx="9.5" cy="8.5" r="3.8"/><path d="M3 20c.7-3.8 3.3-5.8 6.5-5.8 1.5 0 2.9.4 4 1.3M18.5 13v6M15.5 16h6"/>',
    turmas: '<path d="m12 4 9.5 4.5L12 13 2.5 8.5z"/><path d="M6.5 10.5V15c1.5 1.5 3.4 2.2 5.5 2.2s4-.7 5.5-2.2v-4.5M21.5 8.5V14"/>',
    midia: '<path d="M3.5 8.5A2 2 0 0 1 5.5 6.5h2l1.5-2h6l1.5 2h2a2 2 0 0 1 2 2v9.5a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/><circle cx="12" cy="13" r="3.6"/>',
    "solicitar-midia": '<path d="M20.5 3.5 10 14M20.5 3.5 14 20.5l-4-6.5-6.5-4z"/>',
    escalas: '<rect x="3.5" y="5" width="17" height="15.5" rx="3"/><path d="M3.5 10h17M8 3v4M16 3v4M8.5 15l2.3 2.2L15.5 13"/>',
    imagem: '<rect x="3.5" y="4.5" width="17" height="15" rx="3"/><circle cx="9" cy="10" r="1.8"/><path d="m20.5 16-4.5-4.5-8.5 8"/>',
    avisos: '<path d="M6 10a6 6 0 1 1 12 0c0 4.5 2 6 2 6H4s2-1.5 2-6"/><path d="M10 19.5a2.2 2.2 0 0 0 4 0"/>',
    sair: '<path d="M14.5 4.5h3a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2h-3M10 16.5 14.5 12 10 7.5M14.5 12H4"/>',
    fechar: '<path d="M6 6l12 12M18 6 6 18"/>',
    seta: '<path d="m6 9 6 6 6-6"/>',
    olho: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
    "olho-fechado": '<path d="M3.5 3.5l17 17M10.6 6.1A9.6 9.6 0 0 1 12 6c6 0 9.5 6 9.5 6a17 17 0 0 1-3 3.6M14.1 14.2A3 3 0 0 1 9.8 9.9M6.6 7.5A16.5 16.5 0 0 0 2.5 12S6 18 12 18c1.6 0 3-.4 4.3-1"/>',
    instagram: '<rect x="3" y="3" width="18" height="18" rx="5"/><circle cx="12" cy="12" r="4.2"/><circle cx="17.4" cy="6.6" r="1" fill="currentColor" stroke="none"/>',
    youtube: '<rect x="2.5" y="5.5" width="19" height="13" rx="4"/><path d="M10.2 9.3v5.4l4.6-2.7z" fill="currentColor"/>',
    telefone: '<path d="M5 3.5h3.2l1.6 4.2-2.1 1.4a11 11 0 0 0 7.2 7.2l1.4-2.1 4.2 1.6V19a1.6 1.6 0 0 1-1.7 1.6C10.6 20.1 3.9 13.4 3.4 5.2A1.6 1.6 0 0 1 5 3.5z"/>',
    whatsapp: '<path d="M20 11.5a8.5 8.5 0 0 1-12.6 7.4L3.5 20l1.2-3.7A8.5 8.5 0 1 1 20 11.5z"/><path d="M9 9.2c.3 2.4 2.4 4.6 4.9 5"/>',
    mapa: '<path d="M12 21s-6.5-5.6-6.5-11a6.5 6.5 0 0 1 13 0c0 5.4-6.5 11-6.5 11z"/><circle cx="12" cy="10" r="2.4"/>',
    email: '<rect x="3" y="5" width="18" height="14" rx="2.5"/><path d="m4 7 8 6 8-6"/>',
    site: '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.5 2.5 3.6 5.5 3.6 8.5S14.5 18 12 20.5C9.5 18 8.4 15 8.4 12S9.5 6 12 3.5z"/>',
    organogramas: '<rect x="9" y="3" width="6" height="5" rx="1.5"/><rect x="3" y="16" width="6" height="5" rx="1.5"/><rect x="15" y="16" width="6" height="5" rx="1.5"/><path d="M12 8v4M6 16v-2h12v2"/>',
    "site-conteudo": '<rect x="3" y="4" width="18" height="16" rx="2.5"/><path d="M3 9h18M7 13h6M7 16.5h4"/>',
    "agenda-links": '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
    camera: '<path d="M3.5 8.5A2 2 0 0 1 5.5 6.5h2l1.5-2h6l1.5 2h2a2 2 0 0 1 2 2v9.5a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/><circle cx="12" cy="13" r="3.6"/>',
    entrar: '<path d="M9.5 4.5h-3a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2h3M14 16.5 18.5 12 14 7.5M18.5 12H8"/>',
  };
  const icone = (nome, tam = 20) => `<svg width="${tam}" height="${tam}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">${P[nome] || P.painel}</svg>`;

  /* ---------- senha: mostrar / ocultar ----------
     Só muda a exibição no próprio aparelho. O valor digitado segue o mesmo caminho de antes
     (enviado por conexão segura e guardado só como hash no servidor). */
  function prepararSenha(inp) {
    if (inp.dataset.cpOlho || inp.closest(".cp-senha")) return;
    inp.dataset.cpOlho = "1";
    const caixaSenha = document.createElement("span"); caixaSenha.className = "cp-senha";
    inp.parentNode.insertBefore(caixaSenha, inp); caixaSenha.appendChild(inp);
    const b = document.createElement("button");
    b.type = "button"; b.className = "cp-olho"; b.setAttribute("aria-pressed", "false"); b.setAttribute("aria-label", "Mostrar senha"); b.title = "Mostrar senha";
    if (inp.id) b.setAttribute("aria-controls", inp.id);
    b.innerHTML = icone("olho");
    caixaSenha.appendChild(b);
    const mostrar = (sim) => {
      inp.type = sim ? "text" : "password";
      b.setAttribute("aria-pressed", String(sim)); b.setAttribute("aria-label", sim ? "Ocultar senha" : "Mostrar senha"); b.title = sim ? "Ocultar senha" : "Mostrar senha";
      b.innerHTML = icone(sim ? "olho-fechado" : "olho");
    };
    b.addEventListener("click", (ev) => {
      ev.preventDefault(); ev.stopPropagation();
      const pos = [inp.selectionStart, inp.selectionEnd];
      mostrar(inp.type === "password");
      inp.focus({ preventScroll: true }); try { inp.setSelectionRange(pos[0], pos[1]); } catch (_) {}
    });
    // ao enviar o formulário a senha volta a ficar oculta (o navegador não guarda como texto comum)
    inp.form?.addEventListener("submit", () => mostrar(false), true);
  }
  const varrer = (raiz) => (raiz.querySelectorAll ? raiz.querySelectorAll('input[type=password]:not([data-cp-olho])') : []).forEach(prepararSenha);
  function iniciarSenhas() {
    varrer(document);
    new MutationObserver((ms) => ms.forEach((m) => m.addedNodes.forEach((n) => n.nodeType === 1 && (n.matches?.("input[type=password]") ? prepararSenha(n) : varrer(n))))).observe(document.body, { childList: true, subtree: true });
  }
  if (document.body) iniciarSenhas(); else document.addEventListener("DOMContentLoaded", iniciarSenhas);

  window.BetelUI = { aviso, erro: (t) => aviso(t, "erro"), icone };
})();
