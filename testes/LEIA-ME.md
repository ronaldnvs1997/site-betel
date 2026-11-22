# Testes

Baterias usadas na homologação. Elas conferem o banco, as permissões (RLS), a API e as telas no navegador.

Nesta cópia, os e-mails, nomes e telefones reais dos administradores foram trocados por contas de exemplo (`master1@exemplo.com`, `master2@exemplo.com`). A bateria original foi executada no ambiente de desenvolvimento, com o seguinte resultado:

| Bateria | Arquivo | Resultado |
|---|---|---|
| Migrações da Agenda | `teste-agenda-migracao.sh` | 22 ok |
| Etapa 1 — autenticação (API / telas) | `teste-backend.mjs`, `teste-telas.mjs` | 84 / 29 ok |
| Etapa 2 — Agenda (API texto / date / telas / com M10) | `teste-agenda-backend.mjs`, `teste-agenda-telas.mjs` | 60 / 60 / 35 / 60 ok |
| Etapa 3 — Cursos (API / telas) | `teste-cursos-*.mjs` | 70 / 28 ok |
| Etapa 4 — Secretaria e Tesouraria | `teste-financeiro-*.mjs` | 109 / 34 ok |
| Etapa 5 — Membros, voluntários e termos | `teste-membros-*.mjs` | 112 / 34 ok |
| Etapa 6 — Certificados | `teste-certificados-*.mjs` | 72 / 22 ok |
| Etapa 7 — Mídia e escalas (API / telas / date) | `teste-escalas-*.mjs` | 103 / 19 / 103 ok |
| Etapa 8 — identidade visual (todas as abas, inclusive as novas) | `teste-identidade.mjs` | 215 ok |
| Segurança | `teste-seguranca.mjs` | 267 ok |
| Conta sem perfil | `teste-conta-sem-perfil.mjs` | 2 ok |
| Interface e acesso (rodapé, senha, Ir para, menu do usuário, Meu perfil, Sair) | `teste-perfil-menu.mjs` | 76 ok |
| M12 — ministérios, lideranças, organogramas, foto de perfil, contatos, Colégio e link privado da Agenda (API) | `teste-institucional-backend.mjs` | 137 ok |
| M12 — telas (site público, Área de Membros e formulário no celular) | `teste-institucional-telas.mjs` | 45 ok |
| Reversão das migrações M07 a M12 | `rodar-todos-render.sh` | ok |
| Fumaça "como no Render" (computador e celular), num banco PostgreSQL 16 novo com usuário sem superusuário | `fumaca-render.mjs` | 39 ok |

## Para rodar

Os scripts esperam o mesmo ambiente usado no desenvolvimento. Não são um comando pronto para outro computador. É preciso:

- PostgreSQL 16 local no socket `/tmp`, porta 5434, com o usuário `postgres`.
- Google Chrome em `/usr/bin/google-chrome`.
- `playwright-core` instalado.
- As pastas no lugar que os scripts indicam: `reset-render.sh` sobe o servidor deste repositório na porta 8095, com `BETEL_MODO_TESTE=1` e a semente `semente_agenda.sql`.

Os caminhos relativos (`../supabase/tests`, `../plataforma`) são os do ambiente original. Ajuste-os antes de usar.
