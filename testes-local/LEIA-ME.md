# Testes locais

Ambiente que imita o Supabase para rodar as baterias de teste sem tocar no projeto real:

- **PostgreSQL 16 de verdade**, com o essencial do Supabase simulado (`sql/00_supabase_stub.sql`: papéis `anon`, `authenticated`, `service_role`, `auth.users`, `auth.uid()`; `sql/00b_storage_stub.sql`: `storage.buckets`, `storage.objects` com RLS e o bloqueio de exclusão direta).
- A **Agenda já existente com dados** (`sql/01_agenda_existente.sql`), como na instância atual, e as migrações `supabase/migrations` aplicadas por cima.
- `servidor.mjs`: imita as APIs do Supabase (Auth, PostgREST, Storage e as Edge Functions de `supabase/functions`) e publica a pasta `site/`.

As chaves do ambiente local (`chaves.json`, criado ao subir o servidor) são falsas e só valem aqui.

## Como rodar

Precisa de PostgreSQL 16 ouvindo em `/tmp`, porta 5434 (usuário `postgres`), e do Google Chrome para os testes de tela.

```bash
npm ci                    # na raiz do projeto (scripts/criar-primeiros-masters.mjs)
cd testes-local
npm ci
bash rodar-testes.sh      # bateria completa (cerca de 45 minutos)
```

Os casos de teste ficam em `testes-local/casos/`. O último bloco publica a pasta `site/` num servidor estático (porta 8080, como o Render) e confere o site falando com a API em outra origem.

Os resultados ficam em `/tmp/r-*.txt`; o resumo de cada bloco aparece na tela.

## Limites desta simulação

- O Auth e o Storage são imitações: as regras do **banco** (RLS, funções, gatilhos) são as reais, mas o comportamento interno do Supabase Auth (e-mails, limites de tentativas) e do Storage (servidor de arquivos) não é o oficial.
- Por isso, depois de aplicar as migrações no projeto real, confira também `npm run verificar` com `SUPABASE_URL` e `SUPABASE_ANON_KEY` e faça o roteiro manual do README (login, Meu perfil, envio de foto, formulário privado da Agenda).

## Último resultado (22/11/2026, rodado a partir deste repositório)

| Bloco | Resultado |
|---|---|
| Migrações da Agenda: dados e colunas preservados, reversão M02–M04 (tipos texto e date) | 22 ok |
| Etapa 1 — login, solicitações, perfis (API / telas) | 84 / 29 ok |
| Etapa 2 — Agenda (API texto, API date, original × integrada, com todas as migrações) | 60 / 60 / 35 / 60 ok |
| Etapa 3 — Cursos (API / telas) | 70 / 28 ok |
| Etapa 4 — Secretaria e Tesouraria (API / telas) | 109 / 34 ok |
| Etapa 5 — Membros, voluntários e termos (API / telas) | 112 / 34 ok |
| Etapa 6 — Certificados e cerimônias (API / telas) | 72 / 22 ok |
| Etapa 7 — Mídia e escalas (API / telas / Agenda em date) | 103 / 19 / 103 ok |
| Etapa 8 — identidade visual (todas as telas) | 215 ok |
| Segurança (tabelas, funções, Edge Functions, limites, XSS) | 271 ok |
| Conta sem perfil | 2 ok |
| Interface e acesso (rodapé, senha, menu, Meu perfil, Sair) | 74 ok |
| M12 — ministérios, organogramas, fotos (Storage), contatos, Colégio, link privado (API / telas) | 137 / 45 ok |
| Reversão M07 a M13 | ok |
| Site estático + API em outra origem (computador e celular) | 30 ok |
