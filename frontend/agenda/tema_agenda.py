# Etapa 8 — Agenda Ministerial na identidade visual do site (só apresentação).
# Executado por build_agenda.py (usa as mesmas funções troca/troca_re e a variável s).
# Nenhum id, campo, consulta ou regra da Agenda é alterado.

ICO = {
    "lock": '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
    "unlock": '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 7.5-2"/>',
    "key": '<circle cx="8" cy="15" r="4"/><path d="m11 12 9-9m-3 3 3 3m-6 0 2 2"/>',
    "users": '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0M16 4.5a3.5 3.5 0 0 1 0 7M18 14a6 6 0 0 1 3.5 6"/>',
    "templo": '<path d="M3 21h18M5 21V10l7-5 7 5v11M9 21v-6h6v6"/>',
    "file": '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>',
    "link": '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
    "camera": '<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>',
    "video": '<rect x="3" y="6" width="13" height="12" rx="2"/><path d="m16 10 5-3v10l-5-3"/>',
    "pencil": '<path d="M4 20h4L19 9l-4-4L4 16z"/>',
    "trash": '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>',
    "save": '<path d="M5 4h11l3 3v13H5z"/><path d="M8 4v5h7V4M8 20v-6h8v6"/>',
    "alerta": '<path d="M12 3 2 20h20z"/><path d="M12 10v4M12 17h.01"/>',
}
def svg(n):
    return '<svg class="ag-ico" viewBox="0 0 24 24" aria-hidden="true">' + ICO[n] + '</svg>'
EMO = {"🔒": "lock", "🔓": "unlock", "🔑": "key", "👥": "users", "🏛": "templo", "📄": "file", "🔗": "link", "📸": "camera",
       "🎬": "video", "🎥": "video", "✏": "pencil", "🗑": "trash", "💾": "save", "⚠": "alerta"}

# 12a. Textos montados por script (textContent não aceita ícone)
for antigo, novo, nome in [
    ("btnAddRes.textContent = '🏛️';", "btnAddRes.innerHTML = '" + svg("templo") + "';", "botão de reserva no dia"),
    ("pill.textContent = `${ev.bloqueado ? '🔒 ' : ''}${ev.titulo}`;", "pill.textContent = ev.titulo; if (ev.bloqueado) pill.classList.add('ag-trancada');", "evento trancado no calendário"),
    ("pillRes.textContent = `🏛️ ${res.ministerio}: ${res.espacos}`;", "pillRes.textContent = `${res.ministerio}: ${res.espacos}`;", "reserva no calendário"),
    ("${ev.bloqueado ? '🔒 ' : ''}${esc(ev.titulo)}", "${ev.bloqueado ? '" + svg("lock") + " ' : ''}${esc(ev.titulo)}", "evento trancado na lista"),
    ("btnTrancar.textContent = ev.bloqueado ? '🔓 Destrancar Ficha' : '🔒 Trancar Ficha';", "btnTrancar.textContent = ev.bloqueado ? 'Destrancar Ficha' : 'Trancar Ficha';", "botão trancar"),
]:
    troca(antigo, novo, "ícones: " + nome)
troca_re(r"'💾 Salvar Informações no Mural'", "'Salvar Informações no Mural'", "ícones: botão salvar", 2)

# 12b. Cabeçalho do site + identificação do módulo (mesmos componentes: .top, .nav, .sub-hero, .btn)
CABECALHO = """  <header class="top glass">
    <a class="logo" href="../#inicio" aria-label="Igreja Batista Betel — início"><img src="../img/logo.png" alt="Igreja Batista Betel"></a>
    <button class="menu-btn" id="agMenuBtn" type="button" aria-expanded="false" aria-controls="agNav">Menu</button>
    <nav class="nav" id="agNav" aria-label="Principal">
      <a href="../#inicio">Início</a><a href="../#sobre">Sobre nós</a><a href="../#ministerios">Ministérios</a><a href="../#agenda">Agenda</a><a href="../#cursos">Cursos</a><a href="../#colegio">Colégio</a><a href="../#contato">Contato</a><a href="../#equipe" aria-current="page">Área de Membros</a>
    </nav>
  </header>
  <header class="wrap sub-hero ag-modulo">
    <p class="eyebrow">Área de Membros</p>
    <h1 class="cursor-pointer" onclick="voltarParaCalendario()" title="Voltar ao calendário">Agenda <em>Ministerial</em>.</h1>
    <p class="lead" style="margin-top:20px">Calendário dos ministérios, reservas de espaços e fichas dos eventos.</p>
    <div class="ctas">
      <button id="btn-modo-coord" onclick="alternarModoCoordenador()" class="btn btn-s" type="button">Entrar / Modo Coordenador</button>
      <a href="../#equipe" class="btn btn-s">Área de Membros</a>
      <button onclick="perguntarEAbrirPdfAnual()" class="btn btn-p" type="button">""" + svg("file") + """ Baixar PDF Interativo</button>
    </div>
  </header>
"""
i = s.index('  <header class="bg-betel-vinho text-betel-dourado'); j = s.index("</header>\n", i) + len("</header>\n")
s = s[:i] + CABECALHO + s[j:]; mudancas.append("cabeçalho no padrão do site (menu, logo e identificação do módulo)")
troca('<body class="min-h-screen flex flex-col">', '<body class="min-h-screen flex flex-col tema-betel">', "tema institucional")
i = s.index('  <footer class="text-center text-xs text-stone-500'); j = s.index("</footer>", i) + len("</footer>")
s = s[:i] + """  <footer class="ag-rodape">
    <img src="../img/logo.png" alt="Igreja Batista Betel">
    <p>Betel é casa de Deus. · <a href="../">Voltar ao site</a> · <a href="../#equipe">Área de Membros</a></p>
  </footer>""" + s[j:]; mudancas.append("rodapé no padrão do site")
troca('  <link rel="stylesheet" href="agenda.css" />\n', """  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght,SOFT@0,9..144,500,100;0,9..144,600,100;1,9..144,400,0&family=Montserrat:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="agenda.css" />
  <link rel="stylesheet" href="../identidade.css" />
""", "fontes e identidade do site")
troca_re(r"    body \{ background-color: #FFFBF5; color: #2D1A1A; \}\n", "", "cores fixas antigas (agora vêm da identidade)")
troca("</body>", """  <script>
    // Menu do cabeçalho no celular (mesmo comportamento do site)
    (function () { var b = document.getElementById('agMenuBtn'), n = document.getElementById('agNav');
      b.addEventListener('click', function () { var on = n.classList.toggle('open'); b.setAttribute('aria-expanded', String(on)); }); })();
  </script>
</body>""", "menu do celular")

# 12c. Emojis restantes na marcação viram ícones
ini = s.index("<body"); fim = s.index('  <footer class="ag-rodape">')
corpo = s[ini:fim]
for e, n in EMO.items():
    corpo = re.sub(re.escape(e) + "️? ?", svg(n) + " ", corpo)
s = s[:ini] + corpo + s[fim:]
mudancas.append("emojis da marcação trocados por ícones")
resta = [r for r in re.findall("[\U0001F300-\U0001FAFF☀-⛿✀-➿]", s) if r not in "★✕"]
if resta: raise SystemExit(f"[ERRO] emojis restantes: {set(resta)}")
