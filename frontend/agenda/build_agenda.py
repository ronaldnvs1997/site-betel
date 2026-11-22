#!/usr/bin/env python3
"""
Gera a Agenda Ministerial integrada (site/agenda-ministerial/index.html)
a partir do index.html ORIGINAL, aplicando só mudanças pontuais e conferidas.
Tudo o que não está listado aqui fica idêntico ao original.
"""
import re, sys, pathlib

ORIG = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).parent / "original/agenda-original.html")
OUT = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else pathlib.Path(__file__).resolve().parent.parent.parent / "site/agenda-ministerial/index.html")
AQUI = pathlib.Path(__file__).parent
s = ORIG.read_text(encoding="utf-8")
mudancas = []

def troca(antigo, novo, nome, vezes=1):
    global s
    n = s.count(antigo)
    if n != vezes:
        raise SystemExit(f"[ERRO] '{nome}': esperado {vezes} ocorrência(s), encontrado {n}")
    s = s.replace(antigo, novo)
    mudancas.append(nome)

def troca_re(padrao, novo, nome, minimo=1):
    global s
    s2, n = re.subn(padrao, novo, s, flags=re.S)
    if n < minimo:
        raise SystemExit(f"[ERRO] '{nome}': padrão não encontrado")
    s = s2
    mudancas.append(f"{nome} ({n}x)")

# ---------------------------------------------------------------- 1. Dependências sem CDN
troca('  <script src="https://cdn.tailwindcss.com"></script>\n', '  <link rel="stylesheet" href="agenda.css" />\n', "Tailwind compilado localmente (sem CDN)")
troca('  <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>\n',
      '  <script src="../config.js"></script>\n  <script src="../vendor/supabase.js"></script>\n', "supabase-js local + configuração central")
troca('  <script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>\n',
      '  <script src="../vendor/jspdf.umd.min.js"></script>\n', "jsPDF 2.5.1 local")
troca_re(r"\n    tailwind\.config = \{.*?\n    \}\n  </script>", "\n  </script>", "configuração do Tailwind movida para o build")

# ---------------------------------------------------------------- 2. Código duplicado
ini = s.index("  <script>\n\n    // Função para calcular feriados nacionais", s.index("</footer>"))
fim = s.index("    // =========================================================================\n    // CONFIGURAÇÃO DO SUPABASE")
s = s[:ini] + "  <script>\n" + s[fim:]
mudancas.append("removida a 2ª cópia (idêntica) de feriados e PDF anual")

# ---------------------------------------------------------------- 3. Configuração, sessão e permissões
ini = s.index("    // =========================================================================\n    // CONFIGURAÇÃO DO SUPABASE")
fim = s.index("    function mostrarAviso(")
s = s[:ini] + (AQUI / "parte_sessao.js").read_text(encoding="utf-8") + "\n" + s[fim:]
mudancas.append("login antigo (senha comparada no navegador) substituído pelo login central")

# ---------------------------------------------------------------- 4. Login / senha / coordenadores
ini = s.index("    // =========================================================================\n    // LOGIN E MODO COORDENADOR")
fim = s.index("    // =========================================================================\n    // EVENTOS DO COORDENADOR")
s = s[:ini] + (AQUI / "parte_acesso.js").read_text(encoding="utf-8") + "\n" + s[fim:]
mudancas.append("modo coordenador, troca de senha e gestão de coordenadores no login central")

# ---------------------------------------------------------------- 5. Modais de acesso (HTML)
ini = s.index("  <!-- MODAL 0: LOGIN DO COORDENADOR -->")
fim = s.index("  <!-- MODAL 1: COORDENADOR (CRIAR / MOVER DATA DE EVENTO) -->")
s = s[:ini] + (AQUI / "modal_login.html").read_text(encoding="utf-8") + "\n" + s[fim:]
ini = s.index("  <!-- MODAL 5: GESTÃO DE COORDENADORES -->")
fim = s.index("  <footer ")
s = s[:ini] + (AQUI / "modais_coord.html").read_text(encoding="utf-8") + "\n" + s[fim:]
mudancas.append("modais de login, senha e coordenadores")

# ---------------------------------------------------------------- 6. Cabeçalho: botões e links
troca('''          🔒 Modo Coordenador
        </button>''', '''          🔒 Entrar / Modo Coordenador
        </button>
        <a href="../#equipe" class="px-3 py-2 rounded-lg text-xs sm:text-sm font-semibold border border-betel-dourado/30 text-betel-dourado/90 hover:bg-betel-vinhoEscuro transition">Área de Membros</a>
        <a href="../" class="px-3 py-2 rounded-lg text-xs sm:text-sm font-semibold text-betel-dourado/80 hover:bg-betel-vinhoEscuro transition">← Site</a>''', "links para o site e a Área de Membros")
troca('''        <button onclick="abrirModalGestaoCoordenadores()"''', '''        <button id="btn-gestao-coord" onclick="abrirModalGestaoCoordenadores()"''', "botão de gestão só para MASTER")
troca('''  <!-- Conteúdo Principal -->''', '''  <!-- Barra do Líder (preenche fichas do próprio ministério) -->
  <div id="barra-lider" class="hidden bg-emerald-50 border-b border-emerald-200 text-emerald-950 px-4 py-2.5 text-xs sm:text-sm">
    <div class="max-w-6xl mx-auto flex flex-wrap items-center justify-between gap-2">
      <span id="texto-barra-lider"></span>
      <button onclick="abrirModalAlterarSenha()" class="bg-white border border-emerald-400 text-emerald-950 px-3 py-1.5 rounded-md font-semibold hover:bg-emerald-50 transition shadow-sm">🔑 Alterar Minha Senha</button>
    </div>
  </div>
  <datalist id="lista-ministerios"></datalist>

  <!-- Conteúdo Principal -->''', "barra do líder e lista de ministérios")
for campo in ["input-ministerio", "coord-ministerio", "res-ministerio"]:
    troca(f'id="{campo}"', f'id="{campo}" list="lista-ministerios" autocomplete="off"', f"sugestões de ministério em {campo}")

# ---------------------------------------------------------------- 7. Bloqueio da ficha conforme a permissão
troca('''      const hojeISO = new Date().toISOString().split('T')[0];
      const dataPassou = ev.data < hojeISO;''', '''      const hojeISO = hojeLocalISO();
      const dataPassou = String(ev.data) < hojeISO;''', "data de hoje no fuso local (antes era UTC)")
troca('''      if (trancadoManual) {
        return {''', '''      if (!podeEditarFicha(ev)) {
        return {
          bloqueadoParaUsuario: true,
          liberarPosEvento: false,
          motivo: permissoes && permissoes.status === 'ok'
            ? 'Você pode consultar esta ficha, mas só o líder do ministério responsável ou a coordenação podem preenchê-la.'
            : 'Para preencher esta ficha, clique em "Entrar" no topo e use a sua conta da equipe. Somente o líder do ministério responsável e a coordenação podem editar.'
        };
      }

      if (trancadoManual) {
        return {''', "ficha editável só por líder do ministério ou coordenação")

# ---------------------------------------------------------------- 8. Escape de HTML e links seguros
troca('''            <span class="text-[11px] font-bold uppercase text-red-700">${c.tipo}</span>
            <span class="text-[11px] font-semibold text-stone-500">${c.dataFmt}</span>
          </div>
          <p class="font-bold text-stone-900 mt-0.5">${c.titulo}</p>
          <p class="text-xs text-stone-600 mt-0.5">
            <strong>Espaço:</strong> ${c.espacos} • <strong>Horário:</strong> ${c.horario}''', '''            <span class="text-[11px] font-bold uppercase text-red-700">${esc(c.tipo)}</span>
            <span class="text-[11px] font-semibold text-stone-500">${esc(c.dataFmt)}</span>
          </div>
          <p class="font-bold text-stone-900 mt-0.5">${esc(c.titulo)}</p>
          <p class="text-xs text-stone-600 mt-0.5">
            <strong>Espaço:</strong> ${esc(c.espacos)} • <strong>Horário:</strong> ${esc(c.horario)}''', "escape no modal de conflito")
troca('''`<span class="text-xs bg-emerald-100 text-emerald-800 px-2 py-0.5 rounded-full font-medium">Líder: ${ev.lider}</span>`''',
      '''`<span class="text-xs bg-emerald-100 text-emerald-800 px-2 py-0.5 rounded-full font-medium">Líder: ${esc(ev.lider)}</span>`''', "escape do líder")
troca('''            <div onclick="abrirPaginaEvento(${ev.id})"''', '''            <div onclick="abrirPaginaEvento('${esc(ev.id)}')"''', "id do evento escapado")
troca('''                  <p class="font-bold text-sm text-betel-vinho">${ev.bloqueado ? '🔒 ' : ''}${ev.titulo}</p>
                  <p class="text-xs text-stone-500">${ev.local || 'Local a definir'} ${ev.horario ? '• ' + ev.horario : ''}</p>''',
      '''                  <p class="font-bold text-sm text-betel-vinho">${ev.bloqueado ? '🔒 ' : ''}${esc(ev.titulo)}</p>
                  <p class="text-xs text-stone-500">${esc(ev.local || 'Local a definir')} ${ev.horario ? '• ' + esc(ev.horario) : ''}</p>''', "escape na lista de eventos")
troca('''            <div onclick="abrirDetalheReserva(${res.id})"''', '''            <div onclick="abrirDetalheReserva('${esc(res.id)}')"''', "id da reserva escapado")
troca('''                  <p class="font-bold text-sm text-amber-950">${res.ministerio} — ${res.motivo}</p>
                  <p class="text-xs text-stone-600"><strong>${res.espacos}</strong> • ${res.horario_inicio} às ${res.horario_fim}</p>''',
      '''                  <p class="font-bold text-sm text-amber-950">${esc(res.ministerio)} — ${esc(res.motivo)}</p>
                  <p class="text-xs text-stone-600"><strong>${esc(res.espacos)}</strong> • ${esc(hm(res.horario_inicio))} às ${esc(hm(res.horario_fim))}</p>''', "escape na lista de reservas")
troca("linkInscEl.href = ev.midia_link_inscricao.trim();", "linkInscEl.href = urlSegura(ev.midia_link_inscricao) || '#';", "link de inscrição só http(s)")
troca("btnFotos.href = ev.link_fotos.trim();", "btnFotos.href = urlSegura(ev.link_fotos) || '#';", "link de fotos só http(s)")
troca("btnVideos.href = ev.link_videos.trim();", "btnVideos.href = urlSegura(ev.link_videos) || '#';", "link de vídeos só http(s)")

# ---------------------------------------------------------------- 9. Horários "HH:MM:SS" (colunas time) exibidos como HH:MM
troca("pillRes.title = `Reserva (${res.espacos}) • ${res.horario_inicio} às ${res.horario_fim} • ${res.motivo}`;",
      "pillRes.title = `Reserva (${res.espacos}) • ${hm(res.horario_inicio)} às ${hm(res.horario_fim)} • ${res.motivo}`;", "horário da reserva (tooltip)")
troca("document.getElementById('det-res-horario').textContent = `${res.horario_inicio} às ${res.horario_fim}`;",
      "document.getElementById('det-res-horario').textContent = `${hm(res.horario_inicio)} às ${hm(res.horario_fim)}`;", "horário da reserva (detalhe)")
troca("document.getElementById('input-horario-inicio').value = ev.horario_inicio;", "document.getElementById('input-horario-inicio').value = hm(ev.horario_inicio);", "horário início na ficha")
troca("document.getElementById('input-horario-fim').value = ev.horario_fim;", "document.getElementById('input-horario-fim').value = hm(ev.horario_fim);", "horário fim na ficha")

# ---------------------------------------------------------------- 10. Erros do banco: conflito e permissão
troca_re(r"mostrarAviso\('(Erro[^']*)' \+ error\.message, 'erro'\);", r"if (!tratarErroAgenda(error)) mostrarAviso('\1' + error.message, 'erro');", "conflito/permissão vindos do banco tratados")
# Atualizações e exclusões: conferir se o banco aplicou (RLS não devolve erro, devolve 0 linhas)
for antigo, nome in [
    ("        .update({ bloqueado: novoEstado })\n        .eq('id', eventoSelecionado.id);", "trancar ficha"),
    ("        }).eq('id', eventoSelecionado.id);\n\n        btn.disabled = false;", "links pós-evento"),
    ("      const { error } = await db.from('eventos').update(atualizacao).eq('id', eventoSelecionado.id);", "ficha"),
    ("        ({ error } = await db.from('eventos').update(payload).eq('id', id));", "mover evento"),
    ("      const { error } = await db.from('eventos').delete().eq('id', eventoSelecionado.id);", "excluir evento"),
    ("      const { error } = await db.from('reservas').delete().eq('id', reservaSelecionada.id);", "excluir reserva"),
    ("      const { error } = await db.from('reservas').delete().eq('lote_id', reservaSelecionada.lote_id);", "excluir lote"),
]:
    novo = antigo.replace(".eq('id', eventoSelecionado.id);", ".eq('id', eventoSelecionado.id).select('id').then(semEfeito);") \
                 .replace(".eq('id', id));", ".eq('id', id).select('id').then(semEfeito));") \
                 .replace(".eq('id', reservaSelecionada.id);", ".eq('id', reservaSelecionada.id).select('id').then(semEfeito);") \
                 .replace(".eq('lote_id', reservaSelecionada.lote_id);", ".eq('lote_id', reservaSelecionada.lote_id).select('id').then(semEfeito);")
    troca(antigo, novo, f"confirmação do banco: {nome}")

# ---------------------------------------------------------------- 11. Datas fixas em 2027
troca('''    function irParaDataInicial() {
      anoAtual = 2027;
      mesAtual = 1;''', '''    function irParaDataInicial() {
      const hoje = new Date();
      anoAtual = hoje.getFullYear();
      mesAtual = hoje.getMonth();''', "ir para a data inicial = mês atual (antes: fev/2027 fixo)")
troca("document.getElementById('res-data-fim-massa').value = '2027-06-30';",
      "document.getElementById('res-data-fim-massa').value = fimDoSemestre(hojeStr);", "fim padrão da série = fim do semestre (antes: 30/06/2027 fixo)")
troca("const anoInput = prompt(\"Digite o ano que deseja exportar em PDF (ex: 2027):\", anoAtual);",
      "const anoInput = prompt(\"Digite o ano que deseja exportar em PDF (ex: \" + anoAtual + \"):\", anoAtual);", "exemplo do ano do PDF")

# ---------------------------------------------------------------- 12. Identidade visual do site (Etapa 8, só apresentação)
exec((AQUI / "tema_agenda.py").read_text(encoding="utf-8"), globals())

# ---------------------------------------------------------------- 12b. Corrida: voltar ao calendário enquanto um salvamento termina
troca_re(r"(?<!if \(eventoSelecionado\) )abrirPaginaEvento\(eventoSelecionado\.id\);", "if (eventoSelecionado) abrirPaginaEvento(eventoSelecionado.id);", "reabrir a ficha só se ela ainda estiver aberta (evita erro null.id)", minimo=3)

# ---------------------------------------------------------------- 13. Campos de senha com "mostrar / ocultar" (componente compartilhado do site)
troca("</body>", '  <script src="../componentes.js"></script>\n</body>', "botão de olho nos campos de senha (componentes.js do site)")

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(s, encoding="utf-8")
print(f"Agenda integrada gerada: {OUT} ({len(s.splitlines())} linhas)")
for m in mudancas: print(" -", m)
