# Sistema Betel

Site da Igreja Batista Betel (Flamengo, Contagem/MG), Área de Membros e Agenda Ministerial.

## Arquitetura

```
Navegador ──► Render (Static Site) ........ páginas do site (pasta site/)
    │
    └──────► Supabase
               ├─ Auth .................... login, sessões, recuperação de senha
               ├─ PostgreSQL + RLS ........ dados e regras de permissão (schema public)
               ├─ Storage ................. fotos, comprovantes e documentos
               └─ Edge Functions .......... criar usuários, aprovar acessos, arquivos privados
```

- O **Supabase** é o banco de dados, a autenticação, o armazenamento e o lugar das funções de servidor. Não existe outro banco nem outro login.
- O **Render** publica só as páginas (site estático). Ele não cria banco de dados.
- O navegador fala direto com o Supabase pelo `@supabase/supabase-js`, usando a chave **pública** (anon/publishable). O que essa chave pode fazer é limitado pelas políticas RLS e pelas funções do banco.
- A chave **service_role** só existe dentro das Edge Functions (o Supabase a fornece) e, uma única vez, no seu computador para criar os primeiros administradores. Ela nunca vai para o site, para o Render ou para o GitHub.
- Login, sessões e senhas ficam no `auth` do próprio Supabase. O sistema **não cria** o schema `auth` nem tabelas de usuários. Os dados complementares (nome, telefone, foto, perfil, ministérios) ficam em `public.pessoas` e `public.perfis`, ligados a `auth.users(id)`.

## Estrutura

| Pasta / arquivo | O que é |
|---|---|
| `supabase/migrations/` | Migrações versionadas M00 a M13 (aplicadas em ordem, uma única vez) |
| `supabase/rollback/` | Como desfazer cada migração (`.down.sql`). Ficam fora de `migrations/` para o CLI não aplicá-las |
| `supabase/functions/` | Edge Functions: `admin-usuarios`, `aprovar-acesso`, `arquivos` (+ `_shared`) |
| `supabase/diagnostico/diagnostico.sql` | Diagnóstico **somente leitura** da instância: o que já existe e o que falta |
| `supabase/config.toml` | Configuração do Supabase CLI (Auth, funções, ambiente local) |
| `supabase/seed.sql` | Dados do ambiente local do CLI (os dados iniciais do sistema já vêm nas migrações) |
| `frontend/site/` | Fontes da página principal e dos módulos (HTML, CSS, JS, imagens, vídeo) |
| `frontend/agenda/` | Fontes da Agenda Ministerial |
| `site/` | Site gerado por `npm run build` — é o que o Render publica |
| `scripts/` | Build, `config.js`, primeiros administradores, verificação e servidor local |
| `testes/` | Baterias de teste e o ambiente local que imita o Supabase (ver `testes/LEIA-ME.md`) |
| `render.yaml` | Site estático no Render |
| `.env.example` | Nomes das variáveis de ambiente, sem valores |

## Migrações

| Versão | O que faz |
|---|---|
| M00 | Tabelas da Agenda (`eventos`, `reservas`, `coordenadores`) com `create table if not exists`: **na instância atual não faz nada** |
| M01 | Pessoas, perfis (ligados a `auth.users`), ministérios, solicitações de acesso, auditoria |
| M02 | Colunas novas na Agenda (ministério, quem criou/alterou). Só acrescenta; preenche o ministério pelo nome |
| M03 | Segurança da Agenda: RLS novas, login central para coordenadores. **Guarda uma cópia das políticas atuais e as substitui** |
| M04 | Regras da Agenda (conflitos de horário e de espaço) |
| M05 | Cursos e inscrições (bucket `cursos`) |
| M06 | Secretaria e Tesouraria (buckets privados `comprovantes` e `documentos`) |
| M07 | Membros, voluntários e termos |
| M08 | Certificados e cerimônias |
| M09 | Mídia e escalas |
| M10 | Reforços de segurança (limites de uso) |
| M11 | Meu perfil |
| M12 | Páginas dos ministérios, lideranças, organogramas, foto de perfil, contatos e fotos do site, Colégio, link privado da Agenda (buckets `site` e `perfis`) |
| M13 | Tarefa agendada dos prazos das escalas (pg_cron) |

Todas são aditivas: não apagam tabelas, colunas nem registros existentes.

## 1. Pré-requisitos

- Node.js 20.11 ou mais novo (recomendado 22).
- Python 3 — só para `npm run build` (gera o site a partir de `frontend/`).
- [Supabase CLI](https://supabase.com/docs/guides/cli) — para aplicar migrações e publicar as funções.
- Conta no GitHub e no Render.

## 2. Diagnóstico da instância (antes de qualquer alteração)

1. Supabase → **SQL Editor → New query**.
2. Cole `supabase/diagnostico/diagnostico.sql` e clique em **Run**. Ele só lê; não altera nada.
3. O resultado mostra, para cada migração, **JÁ APLICADA** ou **FALTA**, quantos eventos, reservas e usuários existem, os buckets, o pg_cron e os pontos de atenção.

Não aplique nenhuma migração antes de conferir esse resultado. Os pontos que pedem decisão estão em [Pontos que dependem de aprovação](#pontos-que-dependem-de-aprovação).

## 3. Backup

Database → **Backups** (ou `supabase db dump -f backup.sql`). Guarde o arquivo fora do repositório.

## 4. Configurar o Auth

Em **Authentication**:

- **Sign In / Providers → Email:** desligue **Allow new users to sign up**. Só o MASTER cria contas.
- **Senha:** tamanho mínimo de 10 caracteres.
- **URL Configuration:** em **Site URL**, o endereço do site (ex.: `https://betelflamengo.com.br`). Em **Redirect URLs**, inclua o mesmo endereço e o endereço do Render (`https://betel-site.onrender.com`).
- **SMTP:** configure um SMTP próprio (ex.: Google Workspace com senha de app) para os e-mails de recuperação de senha. O SMTP padrão do Supabase tem limite muito baixo.
- **Emails → Reset Password:** traduza o modelo para o português.

## 5. Aplicar as migrações

Aplique **só as que o diagnóstico marcou como FALTA**, em ordem.

**Pelo Supabase CLI:**

```bash
supabase login
supabase link --project-ref SEU_PROJECT_REF
# Para cada migração que o diagnóstico marcou como JÁ APLICADA (feita antes pelo SQL Editor),
# registre-a como aplicada, para o CLI não tentar rodar de novo. Exemplo:
supabase migration repair --status applied 20261121000000 20261121000100
supabase migration list        # confira: as aplicadas e as que faltam
supabase db push               # aplica só as que faltam
```

**Pelo SQL Editor:** abra cada arquivo de `supabase/migrations/` que falta, na ordem do número, cole e clique em **Run**. Cada arquivo roda numa transação: se der erro, nada daquele arquivo fica gravado.

Depois, rode o diagnóstico de novo: todas devem aparecer como **JÁ APLICADA**.

Se o pg_cron estiver inativo, ative em **Database → Extensions → pg_cron** e rode a M13 de novo.

## 6. Publicar as Edge Functions

```bash
supabase functions deploy admin-usuarios aprovar-acesso arquivos
supabase secrets set SITE_ORIGEM=https://betelflamengo.com.br
```

`SITE_ORIGEM` faz as funções aceitarem chamadas só do site (sem ele, aceitam qualquer origem — o login e as permissões continuam sendo exigidos). As funções recebem `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY` automaticamente do Supabase.

## 7. Primeiros administradores (MASTER)

Uma única vez, num computador seguro:

```bash
cp .env.example .env            # preencha SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY
npm ci
npm run masters -- "Nome Completo|email@dominio.com|31999999999"
```

A senha temporária aparece **uma vez** na tela. O sistema exige trocá-la no primeiro acesso. Depois que um MASTER concluir o primeiro acesso, o script deixa de funcionar e as contas passam a ser criadas pela Área de Membros. Apague a `SUPABASE_SERVICE_ROLE_KEY` do `.env` depois.

## 8. Rodar no computador

```bash
npm ci
npm run build        # só se mexeu em frontend/ (precisa de Python 3)
npm run dev          # gera site/config.js a partir do .env e abre em http://localhost:8080
```

Adicione `http://localhost:8080` em Authentication → URL Configuration → Redirect URLs para testar a recuperação de senha localmente.

## 9. Enviar para o GitHub

Crie um repositório **privado** no GitHub. Na primeira vez:

```bash
npm run verificar               # precisa terminar sem erro
git init
git add .
git commit -m "Sistema Betel (Supabase + Render)"
git branch -M main
git remote add origin git@github.com:SUA-CONTA/sistema-betel.git
git push -u origin main
```

Antes de cada `git add`, confira com `git status` que nenhum `.env`, `site/config.js`, backup ou CSV entrou. O `.gitignore` já bloqueia esses casos.

## 10. Publicar no Render

1. Render → **New → Blueprint** → escolha o repositório. O `render.yaml` cria só o **betel-site** (site estático).
2. Preencha as variáveis pedidas:
   - `SUPABASE_URL` — Project Settings → API → Project URL.
   - `SUPABASE_ANON_KEY` — a chave **anon** (ou **publishable**). Nunca a service_role/secret: o build recusa.
3. O build roda `node scripts/gerar-config.mjs`, que cria `site/config.js`, e publica a pasta `site/`.
4. Domínio próprio: **betel-site → Settings → Custom Domains**. Depois, atualize o **Site URL** e as **Redirect URLs** do Auth (passo 4) e o `SITE_ORIGEM` das funções (passo 6).

O Render republica sozinho a cada `git push` na `main`.

## 11. Logs e diagnóstico

- **Render:** betel-site → **Events / Logs** mostra o build. A linha `site/config.js gerado para https://…` confirma a configuração.
- **Supabase → Logs:** **API** (consultas e erros de permissão), **Auth** (logins, recuperação de senha), **Edge Functions** (criar usuário, aprovar acesso, arquivos) e **Postgres**.
- **Verificação completa:** `SUPABASE_URL=… SUPABASE_ANON_KEY=… npm run verificar` confere o projeto, os segredos e se o Supabase responde com as migrações aplicadas.
- **Dentro do site:** Área de Membros → **Histórico** (MASTER) lista quem alterou o quê.

## 12. Atualizar e desfazer

- **Mudança no banco:** crie uma migração nova em `supabase/migrations/` (`AAAAMMDDHHMMSS_mNN_descricao.sql`, aditiva, entre `begin;` e `commit;`) e o `.down.sql` em `supabase/rollback/`. Nunca edite uma migração que já rodou.
- **Mudança no site:** edite `frontend/`, rode `npm run build`, faça commit e push.
- **Voltar o site:** Render → betel-site → **Events → Rollback**.
- **Desfazer uma migração:** faça backup, rode o `.down.sql` correspondente de `supabase/rollback/` no SQL Editor e, se usa o CLI, `supabase migration repair --status reverted VERSÃO`. A reversão da M12 remove o conteúdo cadastrado nas telas dela (páginas, organogramas, fichas da Agenda privada); pessoas, ministérios e eventos ficam.

## Pontos que dependem de aprovação

O diagnóstico mostra estes itens. Nenhum é alterado sem a sua decisão:

1. **Senhas em texto da Agenda antiga** (`coordenadores.senha`). As migrações bloqueiam o acesso a essa coluna para o site, mas não apagam os valores. Depois que os coordenadores passarem a entrar pelo login central, a limpeza pode ser feita por uma migração própria, com a sua aprovação.
2. **Políticas atuais da Agenda.** A M03 guarda uma cópia das políticas e permissões existentes de `eventos`, `reservas` e `coordenadores` (em `public.auditoria`, ação `agenda_estado_anterior`) e as substitui. Depois dela, só coordenadores logados gravam na Agenda: a página antiga da Agenda deixa de gravar sem login. A reversão (`rollback/…m03….down.sql`) recoloca as políticas antigas.
3. **Gatilho em `auth.users`.** A M01 cria um único gatilho (`betel_senha_alterada`) que registra em `public.perfis` quando a pessoa troca a senha temporária. Ele não altera a estrutura nem os dados do `auth` — é o padrão documentado pelo Supabase para reagir a eventos de usuários.

## Segurança

- Login, sessões e senhas: Supabase Auth. Ninguém, nem o administrador, vê a senha de alguém. Sair encerra a sessão daquele aparelho no Supabase Auth; o acesso já emitido vale no máximo até expirar (1 hora, padrão do Supabase).
- Permissões conferidas no banco (RLS e funções), nunca só na tela. O organograma não concede permissões.
- Criar usuários e aprovar acessos: só nas Edge Functions, que conferem se quem chamou é MASTER ativo.
- Comprovantes e documentos: buckets privados, acessados por link temporário de 5 minutos, gerado só para quem tem permissão.
- Fotos do site e de perfil: buckets públicos com endereço aleatório (ninguém lista os arquivos); só envia quem tem permissão, com limite de tamanho e de tipo.
- Formulário privado da Agenda: código aleatório de 64 caracteres, com validade, revogável; só envia uma ficha que fica aguardando análise.
