# Sistema Betel

Site da Igreja Batista Betel (Flamengo, Contagem/MG), Área de Membros e Agenda Ministerial.

Um único servidor Node.js publica o site e a API do sistema. Tudo fica num banco PostgreSQL: usuários, permissões, ministérios, organogramas, cursos, secretaria, tesouraria, membresia, certificados, Mídia, Agenda e o conteúdo administrável do site. O projeto não usa Supabase. O site usa a biblioteca `@supabase/supabase-js` só como cliente HTTP, conversando com a API deste próprio servidor.

## O que o sistema tem

| Parte | Onde fica |
|---|---|
| Site público: Início (vídeo e fotos), Sobre nós, Ministérios (lista e página de cada um), Agenda, Cursos, Colégio (etapas de ensino) e Contato | `frontend/site/` |
| Área de Membros: painel, usuários, ministérios e lideranças, organogramas, conteúdo do site, formulários da Agenda, cursos, secretaria, tesouraria, membresia, certificados, Mídia, avisos e Meu perfil (com foto) | `frontend/site/*-sb.js` |
| Agenda Ministerial | `frontend/agenda/` → `site/agenda-ministerial/` |
| Formulário privado da Agenda (sem login, por link com código) | `frontend/site/agenda-privada.html` → `site/agendaministerialprivada/evento/` |
| Banco e regras de permissão | `database/` |

Os endereços antigos continuam funcionando. `#membros` leva para a Área de Membros, que segue no endereço `#equipe`.

## Estrutura

| Pasta / arquivo | O que é |
|---|---|
| `servidor/servidor.mjs` | Servidor HTTP: site, API, instalação do banco, tarefas a cada 15 minutos |
| `nucleo/` | API (login, sessões, consultas com RLS, arquivos), instalação e lista de migrações |
| `funcoes/` | Funções de servidor (criar usuário, aprovar acesso, arquivos) |
| `database/` | Banco: base da plataforma, migrações versionadas e `schema.sql` de referência. Ver `database/README.md` |
| `frontend/site/` | **Fontes** da página principal e dos módulos (HTML, CSS, JS, imagens, vídeo) |
| `frontend/agenda/` | **Fontes** da Agenda Ministerial (Agenda original + mudanças aplicadas pelo build) |
| `site/` | **Gerado** por `npm run build`. É o que o servidor publica e vai pronto para o GitHub |
| `scripts/` | Build do site, migração, verificação e versão de teste no navegador |
| `previa/` | Versão de teste que roda inteira no navegador (PostgreSQL em WebAssembly) |
| `dados-agenda/` | (Opcional) CSVs da Agenda antiga para importar na primeira instalação. Não vão para o GitHub |
| `testes/` | Baterias de teste usadas na homologação (ver `testes/LEIA-ME.md`) |
| `render.yaml` | Configuração do Render (Blueprint): site e banco |
| `.env.example` | Nomes das variáveis de ambiente, sem valores |

## 1. Pré-requisitos

- Node.js 20.11 ou mais novo (recomendado 22, ver `.node-version`).
- PostgreSQL 14 ou mais novo (o Render usa 16). O usuário do banco precisa poder criar papéis (`CREATEROLE`). No Render isso já vem assim.
- Python 3: só para `npm run build`, que gera o site a partir de `frontend/`.
- Git e uma conta no GitHub.

## 2. Instalar as dependências

```bash
npm ci
```

Instala as dependências do servidor e as ferramentas de build (Tailwind, esbuild). Em produção o Render roda `npm ci --omit=dev`, que instala só o necessário para o servidor.

## 3. Configurar as variáveis de ambiente

```bash
cp .env.example .env
```

Preencha o `.env`. Ele está no `.gitignore` e não vai para o GitHub.

| Variável | Obrigatória | Para quê |
|---|---|---|
| `DATABASE_URL` | sim | Endereço do PostgreSQL |
| `JWT_SECRET` | sim | Segredo das sessões (32+ caracteres aleatórios). Gere com `node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"` |
| `PORT` | não | Porta local (padrão 8095) |
| `PUBLIC_URL` | não | Endereço público, ex.: `https://betelflamengo.com.br` |
| `BETEL_MASTERS` | 1ª vez | Primeiros administradores: `Nome\|email\|telefone;Nome\|email\|telefone` |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM` | não | E-mail do "Esqueci minha senha" e do "Não sei minha senha atual". Sem isso, o site orienta a pessoa a pedir uma senha temporária ao administrador |
| `DATABASE_SSL` | não | `true` só para conexão externa com SSL |

## 4. Executar localmente

```bash
createdb betel                 # ou crie o banco pelo seu gerenciador
npm run dev                    # lê o .env, instala/atualiza o banco e sobe em http://localhost:8095
```

Na primeira vez, o servidor cria as tabelas e os administradores de `BETEL_MASTERS`. A senha temporária de cada um aparece **uma vez** no terminal. O sistema exige trocá-la no primeiro acesso.

## 5. Gerar o site (build)

O servidor publica a pasta `site/`. Depois de alterar qualquer arquivo em `frontend/`:

```bash
npm run build
```

O build monta `site/index.html`, a Agenda Ministerial (`site/agenda-ministerial/`), o formulário privado da Agenda (`site/agendaministerialprivada/evento/`), o CSS da Agenda e o `identidade.css`. Faça commit da pasta `site/` junto com as fontes: é ela que vai para o Render. O `config.js` não fica na pasta, porque o servidor o gera na hora.

## 6. Banco de dados

O banco é criado e atualizado sozinho quando o servidor inicia. A ordem das migrações, o que cada uma faz e como desfazer estão em [`database/README.md`](database/README.md).

Conteúdo que já vem cadastrado e **precisa ser revisado** na Área de Membros:

- **Ministérios → página de cada ministério:** os textos "O que fazemos", "Por que existimos" e "Nossa missão" começam como rascunho e só aparecem no site depois que a liderança revisa e clica em **Salvar e publicar**.
- **Conteúdo do site → Colégio:** faixa etária e diferenciais pedagógicos ficam vazios até a direção informar. Campos vazios não aparecem no site.
- **Conteúdo do site → Contatos:** confira se cada número marcado como WhatsApp realmente tem WhatsApp.
- **Organogramas:** o topo da igreja já traz Pr. Clébio Torres (Presidente e Pastor Sênior). As demais funções são cadastradas pela administração.

## 7. Migrações

```bash
npm run verificar        # confere arquivos, variáveis e permissões do banco (não altera nada)
npm run migrate:status   # mostra o que já foi aplicado e o que falta (não altera nada)
npm run migrate          # aplica só o que falta
```

Alternativa sem Node: `psql "URL_DO_BANCO" -f database/instalar-tudo.sql`. É o mesmo conteúdo num único arquivo, e pula o que já foi aplicado.

Cada migração roda uma única vez e fica registrada em `sistema.migracoes`. Para criar uma nova:

1. Crie `database/migrations/AAAAMMDDHHMMSS_mNN_descricao.sql`, aditiva, entre `begin;` e `commit;`.
2. Crie o `.down.sql` correspondente, que desfaz sem apagar dados.
3. Teste num banco de teste antes de publicar.

Nunca edite uma migração que já rodou em produção. Corrija com uma migração nova.

## 8. Testar antes de publicar

1. `npm run verificar` precisa terminar sem erro.
2. Suba localmente (`npm run dev`) e confira: Início, Ministérios, Colégio, Contato, login na Área de Membros, Meu perfil e um formulário privado da Agenda aberto no celular.
3. As baterias automáticas usadas na homologação estão em `testes/` (ver `testes/LEIA-ME.md`).

## 9. Enviar para o GitHub

Crie um repositório **privado** no GitHub. Na primeira vez:

```bash
git init
git add .
git commit -m "Sistema Betel"
git branch -M main
git remote add origin git@github.com:SUA-CONTA/sistema-betel.git
git push -u origin main
```

Antes de cada `git add`, confira com `git status` que nenhum `.env`, CSV da Agenda antiga ou arquivo pessoal entrou na lista. O `.gitignore` já bloqueia esses casos.

## 10. Publicar no Render

O passo a passo completo, com a solução dos erros mais comuns, está em **[PUBLICAR-NO-RENDER.md](PUBLICAR-NO-RENDER.md)**. Resumo:

1. No Render: **New → Blueprint** e escolha o repositório. O `render.yaml` cria:
   - **betel-banco**: PostgreSQL 16 (o plano gratuito expira em 30 dias; para uso real, escolha um pago com backup).
   - **betel-site**: serviço web Node. Build: `npm ci --omit=dev`. Início: `npm start`. Verificação de saúde: `/saude`. A porta vem do Render (`PORT`).
   - O servidor espera o banco ficar pronto, instala as migrações e só então responde "ok" em `/saude`.
2. O Render pede as variáveis marcadas como `sync: false`. Preencha `BETEL_MASTERS`. Deixe `PUBLIC_URL` vazio até o domínio próprio funcionar. `SMTP_*` é opcional. `DATABASE_URL` e `JWT_SECRET` já vêm preenchidos.
3. Confira o preço dos planos na tela antes de confirmar.
4. Domínio próprio: **betel-site → Settings → Custom Domains**. Depois, preencha `PUBLIC_URL` com o domínio.

Para trazer os dados da Agenda antiga, coloque os CSVs em `dados-agenda/` **antes da primeira subida** (ver `dados-agenda/LEIA-ME.txt`).

## 11. Acompanhar os logs

Os logs mostram tudo o que o servidor faz e, em caso de problema, dizem em português o que falta.

- **No Render:** abra **betel-site → Logs**. Na primeira subida aparecem, em ordem: *Aplicando …* (uma linha por etapa do banco), *Banco atualizado*, as **senhas temporárias** dos administradores (anote, aparecem uma vez) e *Sistema pronto*.
- **No computador:** as mesmas mensagens aparecem no terminal do `npm run dev`.
- **Situação do serviço:** abra `https://SEU-ENDERECO/saude`. Responde `ok` quando tudo está pronto, e 503 com o motivo enquanto o banco ainda está sendo preparado.
- **Banco:** **betel-banco → Metrics** mostra conexões e uso de disco. `npm run migrate:status` mostra as etapas aplicadas.
- **Histórico de ações:** dentro do site, **Área de Membros → Histórico** (MASTER) lista quem alterou o quê, inclusive ministérios, organogramas, fotos, contatos e decisões sobre fichas da Agenda.

## 12. Atualizar, fazer backup e desfazer

Cada nova versão:

```bash
npm run build            # se mexeu em frontend/
git add .
git commit -m "Descreva a mudança"
git push
```

O Render publica sozinho a cada push na `main` (Auto-Deploy) e o servidor aplica as migrações novas na subida.

- **Backup:** antes de uma mudança grande, faça um backup manual em **betel-banco → Backups**.
- **Voltar o código:** em **betel-site → Events**, use **Rollback** para a versão anterior.
- **Desfazer uma migração:** rode o `.down.sql` correspondente, depois de um backup. Os detalhes estão em `database/README.md`.

## Segurança

- Senhas guardadas só como hash (bcrypt). Ninguém, nem o administrador, consegue ver a senha atual de alguém. Sessões, links de recuperação e códigos dos formulários privados também são guardados como hash.
- **Sair** encerra a sessão no servidor: o token daquela sessão deixa de valer na hora.
- Permissões conferidas no banco (RLS e funções), nunca só na tela. O organograma não concede permissões.
- Formulário privado da Agenda: código aleatório de 64 caracteres, com validade, revogável e renovável. Ele só envia uma ficha, que fica **aguardando análise**. Não lê, não altera e não exclui eventos. Uso excessivo é bloqueado por alguns minutos, e a página fica fora dos buscadores.
- Fotos: o servidor confere o tipo real do arquivo (não só a extensão) e o tamanho. Cada pessoa troca apenas a própria foto de perfil, que só aparece nos organogramas com autorização.
- Documentos e comprovantes ficam no banco, em área privada, com link temporário.
- Nada de segredo no código: tudo vem das variáveis de ambiente.
