#!/bin/bash
# Gera a pasta site/ (o que o servidor publica) a partir das fontes em frontend/.
# Uso: npm run build      (precisa de Node 20+, Python 3 e das dependências de desenvolvimento: npm ci)
set -e
cd "$(dirname "$0")/.."
F=frontend/site; OUT=site; NM=node_modules
[ -x $NM/.bin/tailwindcss ] || { echo "Rode antes: npm ci (instala as ferramentas de build)"; exit 1; }
mkdir -p $OUT/vendor $OUT/agenda-ministerial

# 1. Página principal: cabeçalho + corpo + Área de Membros + Cursos + scripts dos módulos
python3 - <<'PY'
F = "frontend/site/"
b = open(F + "body.html", encoding="utf-8").read()
velho = '<section class="view" id="v-equipe">'
assert velho in b
b = b.replace(velho, open(F + "equipe-sb.html", encoding="utf-8").read() + '\n<section class="view" id="v-equipe-legado" hidden>', 1)
b = b.replace('<section class="view" id="v-equipe-legado" hidden>', open(F + "cursos-sb.html", encoding="utf-8").read() + '\n<section class="view" id="v-equipe-legado" hidden>', 1)
assert b.count('<a href="#agenda">Agenda</a>') >= 1
b = b.replace('<a href="#agenda">Agenda</a>', '<a href="#agenda">Agenda</a>\n    <a href="#cursos">Cursos</a>', 1)
open("/tmp/betel-corpo.html", "w", encoding="utf-8").write(b)
PY
js(){ for f in "$@"; do echo "<script>"; cat $F/$f; echo "</script>"; done; }
{ cat $F/cabecalho.html; echo '<style>'; cat $F/componentes.css; echo '</style>'; cat /tmp/betel-corpo.html; echo
  echo '<script src="config.js"></script>'; echo '<script src="vendor/supabase.js"></script>'
  js qrcode.js; echo '<script>window.BETEL_VIEWS_EXTRA = ["cursos","curso","inscricao-curso","membresia","ministerio"];</script>'
  js app.js componentes.js equipe-sb.js termos-sb.js cursos-sb.js cursos-admin-sb.js secretaria-sb.js tesouraria-sb.js membresia-sb.js certificados-sb.js midia-sb.js institucional-sb.js site-sb.js
  echo "</body>"; echo "</html>"; } > $OUT/index.html
cp $NM/@supabase/supabase-js/dist/umd/supabase.js $OUT/vendor/supabase.js
cp $F/componentes.js $OUT/componentes.js
rm -rf $OUT/img $OUT/video; cp -r $F/img $F/video $OUT/
mkdir -p $OUT/agendaministerialprivada/evento && cp $F/agenda-privada.html $OUT/agendaministerialprivada/evento/index.html

# 2. Agenda Ministerial (gerada a partir da Agenda original, com as mudanças listadas em build_agenda.py)
( cd frontend/agenda && python3 build_agenda.py >/dev/null && cat entrada.css tema-betel.css > /tmp/betel-agenda-entrada.css \
  && ../../$NM/.bin/tailwindcss -c tailwind.config.cjs -i /tmp/betel-agenda-entrada.css -o ../../$OUT/agenda-ministerial/agenda.css --minify 2>/dev/null )
cp $NM/jspdf/dist/jspdf.umd.min.js $OUT/vendor/

# 3. Identidade do site para a Agenda (extraída do CSS da página principal)
python3 scripts/extrair_identidade.py >/dev/null
echo "site/ gerado. O config.js é criado pelo servidor ao vivo (não fica nesta pasta)."
