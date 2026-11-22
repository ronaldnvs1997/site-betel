# Publicar o Sistema Betel no Render (passo a passo)

Tempo estimado: 20 a 30 minutos. Você precisa de:

- uma conta no **GitHub**;
- uma conta no **Render** com cartão cadastrado (os planos padrão são pagos);
- os dados dos primeiros administradores: nome, e-mail e telefone.

---

## Passo 1 — Colocar o projeto no GitHub

O Render lê o projeto do GitHub. O arquivo `render.yaml` precisa ficar **na raiz** do repositório, e não dentro de outra pasta.

1. No GitHub: **New repository** → nome `sistema-betel` → marque **Private** → **Create repository**. Não marque "Add a README".
2. Envie os arquivos por **um** dos caminhos abaixo.

**Caminho A — GitHub Desktop (recomendado, sem limite de arquivos)**

1. Instale o GitHub Desktop: <https://desktop.github.com>.
2. Descompacte o zip. A pasta `sistema-betel` é a que tem o `render.yaml` dentro.
3. No GitHub Desktop: **File → Add local repository →** escolha a pasta `sistema-betel`.
4. Se ele avisar que a pasta não é um repositório, clique em **create a repository**.
5. Faça o **Commit to main** e depois **Publish repository**. Deixe a opção "Keep this code private" marcada.

**Caminho B — pelo navegador**

O site do GitHub aceita no máximo **100 arquivos por envio**, e o projeto tem mais que isso. Envie em duas vezes:

1. Na página do repositório: **Add file → Upload files**.
   - Arraste **o conteúdo** da pasta `sistema-betel`, e não a pasta em si: as pastas `database`, `funcoes`, `nucleo`, `scripts`, `servidor`, `previa`, `dados-agenda`, `testes` e os arquivos soltos (`render.yaml`, `package.json`, `package-lock.json`, `README.md`, `PUBLICAR-NO-RENDER.md`).
   - **Commit changes**.
2. De novo **Add file → Upload files**: arraste as pastas `site` e `frontend` → **Commit changes**.
3. O navegador às vezes não envia arquivos que começam com ponto (`.gitignore`, `.env.example`, `.node-version`). Não tem problema: o sistema funciona sem eles.

**Confira antes de seguir.** Na página do repositório, você deve ver `render.yaml`, `package.json`, `package-lock.json` e as pastas `site`, `servidor`, `nucleo`, `funcoes` e `database` **direto na lista principal**.

---

## Passo 2 — (Opcional) Dados da Agenda antiga

Se for aproveitar os eventos da Agenda atual:

1. No Supabase, exporte as tabelas `eventos`, `reservas` e `coordenadores` em CSV.
2. Coloque os arquivos na pasta `dados-agenda/` com esses nomes: `eventos.csv`, `reservas.csv` e `coordenadores.csv`.
3. Envie a pasta **antes** do Passo 3. O sistema importa uma única vez, na primeira subida. Linhas com problema são puladas e contadas no registro (Logs).

---

## Passo 3 — Criar tudo no Render (Blueprint)

1. No Render: **New + → Blueprint**.
2. Conecte a conta do GitHub, se ele pedir, e escolha o repositório `sistema-betel`.
3. O Render mostra o que vai criar: **betel-banco** (PostgreSQL 16) e **betel-site** (Node). Confira os preços na tela.
4. Ele pede os valores das variáveis abaixo.

| Variável | O que colocar |
|---|---|
| `BETEL_MASTERS` | `Nome Completo\|email\|telefone`. Para duas pessoas, separe com ponto e vírgula, ex.: `Fulano de Tal\|fulano@betelflamengo.com.br\|31999999999;Ciclano Silva\|ciclano@betelflamengo.com.br\|31988888888` |
| `PUBLIC_URL` | **Deixe vazio por enquanto.** Preencha só depois de o domínio próprio estar funcionando (Passo 6) |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM` | Opcional (e-mail de "Esqueci minha senha"). Pode deixar vazio |

5. Clique em **Apply**.

`DATABASE_URL` e `JWT_SECRET` são preenchidos sozinhos. Não mexa neles.

---

## Passo 4 — Acompanhar a primeira subida

1. Abra **betel-site → Logs**.
2. É **normal** aparecer, nos primeiros minutos, uma mensagem como `Ainda não foi possível iniciar … o banco pode estar sendo criado`. O servidor tenta de novo sozinho até o banco ficar pronto.
3. Quando estiver tudo certo, aparecem estas linhas:

```
Banco atualizado (14 etapa(s)).
Sistema pronto.
MASTER criado: Fulano de Tal <fulano@...> — senha temporária: XXXX-XXXX-XXXX7a (troca obrigatória no primeiro acesso)
```

4. **Anote as senhas temporárias.** Elas aparecem uma única vez.
5. O status do serviço fica **Live**.

---

## Passo 5 — Testar

1. Abra o endereço do serviço (algo como `https://betel-site.onrender.com`).
2. Clique em **Área de Membros**, entre com o e-mail e a senha temporária e crie a senha definitiva.
3. Confira se aparece o seu nome no canto do cabeçalho e se **Meu perfil** e **Sair** funcionam.

Para conferir o projeto e o banco por dentro (opcional): **betel-site → Shell** e rode:

```
npm run verificar
```

---

## Passo 6 — Domínio próprio

1. **betel-site → Settings → Custom Domains → Add**, ex.: `betelflamengo.com.br`.
2. O Render mostra o registro de DNS que deve ser criado no provedor do domínio.
3. Quando o domínio abrir o site com o cadeado (https), vá em **Environment**, preencha `PUBLIC_URL` com `https://betelflamengo.com.br` e salve. O serviço reinicia sozinho.

---

## Atualizações futuras

Envie os arquivos alterados para o GitHub, pelo GitHub Desktop: **Commit → Push**. O Render publica sozinho a cada envio e aplica só as migrações novas do banco, sem apagar dados. Antes de mudanças grandes, faça um backup em **betel-banco → Backups**.

---

## Se algo der errado

| O que aparece | O que fazer |
|---|---|
| Ao criar o Blueprint: *"render.yaml not found"* ou nenhum serviço listado | O `render.yaml` não está na raiz do repositório. Envie de novo o **conteúdo** da pasta, e não a pasta |
| Ao criar o Blueprint: pedido de cartão / *payment information* | Os planos padrão são pagos. Cadastre o cartão. Para só testar, acrescente `plan: free` no banco e no site dentro do `render.yaml` (o banco gratuito é apagado em 30 dias) |
| Build: *npm ci … package-lock.json* | O `package-lock.json` não foi enviado. Envie esse arquivo |
| Build: *Cannot find module* | Faltou enviar alguma pasta (`servidor`, `nucleo`, `funcoes`, `database`). Rode `npm run verificar` no Shell para ver qual |
| Logs: *O banco ainda não aceita conexões* / *banco não existe* por mais de 10 minutos | Confira se **betel-banco** está *Available* e se site e banco estão na **mesma região** (`virginia`) |
| Logs: *precisa de CREATEROLE* | O `DATABASE_URL` foi trocado por outro usuário. Volte a usar a URL do próprio betel-banco (Environment → DATABASE_URL → *From database*) |
| Site abre, mas o login não funciona | Deixe `PUBLIC_URL` vazio até o domínio próprio funcionar |
| Não apareceu nenhuma senha de MASTER nos Logs | `BETEL_MASTERS` ficou vazio ou mal escrito. Preencha em **Environment** (formato acima) e clique em **Save, rebuild and deploy** |
| Página *"O site está iniciando"* por muito tempo | Veja a última mensagem dos Logs. Ela diz exatamente o que falta |
