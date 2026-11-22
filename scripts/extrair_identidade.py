#!/usr/bin/env python3
"""
Gera site/identidade.css: a identidade do site principal (variáveis, cabeçalho,
menu, botões, vidro, rótulos) extraída AUTOMATICAMENTE do CSS do próprio site
(frontend/site/cabecalho.html), mais os componentes compartilhados (frontend/site/componentes.css).
Assim a Agenda Ministerial usa exatamente as mesmas regras, sem cópia manual.
"""
import re, sys, pathlib
RAIZ = pathlib.Path(__file__).resolve().parent.parent
html = (RAIZ / "frontend/site/cabecalho.html").read_text(encoding="utf-8")
css = "\n".join(re.findall(r"<style[^>]*>(.*?)</style>", html.split("<body")[0], re.S))
css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)

# seletores de componentes (classes) que a Agenda reaproveita
QUER = re.compile(r"^(:root|\.glass|\.top\b|\.top |\.logo|\.nav\b|\.nav |\.nav\.|\.menu-btn|\.btn\b|\.btn-|\.btn:|\.eyebrow|\.sub-hero|\.lead|\.wrap\b|\.ctas|\.tabs|\.st\b|\.st\.|\.notice|\.msg\b|\.empty)")

def blocos(t):
    """divide em (prelúdio, corpo) respeitando chaves aninhadas"""
    i, n, out = 0, len(t), []
    while i < n:
        a = t.find("{", i)
        if a < 0: break
        pre = t[i:a].strip(); d = 1; j = a + 1
        while j < n and d:
            d += {"{": 1, "}": -1}.get(t[j], 0); j += 1
        out.append((pre, t[a + 1:j - 1])); i = j
    return out

def filtra(t):
    res = []
    for pre, corpo in blocos(t):
        if pre.startswith("@media"):
            dentro = filtra(corpo)
            if dentro: res.append(pre + "{" + dentro + "}")
        elif pre.startswith("@"):
            continue
        else:
            sels = [s.strip() for s in pre.split(",")]
            bons = [s for s in sels if QUER.match(s)]
            if bons: res.append(",".join(bons) + "{" + corpo.strip() + "}")
    return "".join(res)

saida = ["/* Gerado por ferramentas/extrair_identidade.py — não edite à mão. Fonte: web2/index.html + web2/componentes.css */", filtra(css),
         (RAIZ / "frontend/site/componentes.css").read_text(encoding="utf-8")]
destino = RAIZ / (sys.argv[1] if len(sys.argv) > 1 else "site/identidade.css")
destino.write_text("\n".join(saida), encoding="utf-8")
print("identidade.css:", destino.stat().st_size, "bytes")
