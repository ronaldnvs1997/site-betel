# Banco de dados — Sistema Betel

O banco é PostgreSQL 14 ou mais novo (o Render usa 16). Ele é instalado e atualizado **pelas migrações deste repositório**. O servidor faz isso sozinho ao iniciar, e `npm run migrate` faz o mesmo sem subir o site.

## O que existe (inventário de um banco instalado até a M12)

| Item | Quantidade |
|---|---|
| Tabelas no esquema `public` | 55 (todas com RLS ligada) |
| Tabelas da plataforma | `auth` (4: usuários, sessões, sessões encerradas, links de recuperação), `armazenamento` (1: arquivos privados), `sistema` (1: migrações aplicadas) |
| Funções (`public`) | 260 |
| Gatilhos | 99 (auditoria, regras da Agenda, limites dos formulários públicos, prazos das escalas…) |
| Políticas de RLS | 27 |
| Chaves estrangeiras | 130 |
| Índices | 107 |
| Extensões | só `plpgsql` (padrão do PostgreSQL) |

Tabelas do esquema `public`: agenda_envios, agenda_envios_historico, agenda_link_acessos, agenda_links, apoio_servico_funcoes, apoio_servicos, apoio_solicitacao_mensagens, apoio_solicitacao_servicos, apoio_solicitacoes, auditoria, beneficios, categorias_curso, cerimonias, certificados, certificados_eventos, colegio_etapas, comprovantes, configuracoes, consentimentos, coordenadores, cursos, cursos_conclusoes_anteriores, documentos, escala_areas, escala_evento_funcoes, escala_eventos, escala_funcoes, escala_gestores, escala_historico, escala_participacoes, eventos, inscricoes, membresia_processos, ministerio_membros, ministerio_paginas, ministerios, notificacoes, organograma_nos, organogramas, pagamentos, perfis, pessoas, reembolsos, reservas, solicitacoes, termos, turma_responsaveis, turmas, voluntariado_candidaturas, voluntariado_indicacoes, voluntario_capacitacoes, voluntario_disponibilidade, voluntario_habilitacoes, voluntario_indisponibilidades, voluntario_preferencias.

A estrutura completa (colunas, tipos, chaves, índices, restrições, políticas, funções e gatilhos) está em **`schema.sql`**, gerado com `pg_dump --schema-only` de um banco instalado por estas migrações.

## Arquivos

```
database/
  plataforma/
    000_plataforma.sql            papéis anon/authenticated/service_role, esquema auth (usuários, sessões),
                                  armazenamento de arquivos, funções auth.uid()/auth.role()/auth.jwt()
    001_agenda_base.sql           tabelas originais da Agenda Ministerial (eventos, reservas, coordenadores)
    003_sessoes_revogaveis.sql    "Sair" encerra a sessão no servidor
  migrations/
    20261121000100_m01_nucleo_autenticacao.sql   (+ .down.sql)  pessoas, perfis, ministérios, solicitações, auditoria
    20261121000200_m02_agenda_colunas.sql        (+ .down.sql)  colunas novas da Agenda (sem apagar as antigas)
    20261121000300_m03_agenda_seguranca.sql      (+ .down.sql)  RLS da Agenda, fim das senhas em texto
    20261121000400_m04_agenda_regras.sql         (+ .down.sql)  conflitos de reserva, fichas, trancamento
    20261121000500_m05_cursos_inscricoes.sql     (+ .down.sql)  cursos, turmas, inscrições
    20261121000600_m06_secretaria_tesouraria.sql (+ .down.sql)  pagamentos, comprovantes, reembolsos
    20261121000700_m07_membros_voluntarios_termos.sql (+ .down.sql)  membresia, voluntariado, termos (LGPD)
    20261121000800_m08_certificados_cerimonias.sql    (+ .down.sql)  certificados (entrega presencial), cerimônias
    20261121000900_m09_midia_escalas.sql         (+ .down.sql)  Mídia, escalas, solicitações de apoio
    20261121001000_m10_homologacao_reforcos.sql  (+ .down.sql)  limites de volume nos formulários públicos
    20261121001100_m11_meu_perfil.sql            (+ .down.sql)  "Meu perfil": ler o próprio cadastro e editar só o telefone
    20261121001200_m12_institucional.sql         (+ .down.sql)  Páginas dos ministérios, lideranças e histórico, organogramas,
                                                                foto de perfil, contatos e fotos do site, etapas do Colégio,
                                                                links privados da Agenda (fichas aguardando análise)
  instalar-tudo.sql               todas as etapas num só arquivo para o psql (opcional; pula o que já foi aplicado)
  schema.sql                      estrutura completa, só para consulta (ver abaixo)
```

## Ordem de execução

A ordem é a dos nomes: `plataforma/000`, `001`, `003` e depois `migrations/` em ordem de data (M01 → M12). Cada etapa roda **uma única vez** e fica registrada em `sistema.migracoes`. O servidor usa uma trava (`pg_advisory_lock`) para duas instâncias não instalarem ao mesmo tempo.

Na **primeira** instalação, logo depois de `001_agenda_base`, entram os dados da Agenda antiga se houver CSVs em `dados-agenda/`. A M02, a M03 e a M04 convertem esses dados para o formato novo sem apagar colunas antigas.

## Executar

```bash
npm run migrate:status   # lista o que já foi aplicado e o que falta (não altera nada)
npm run migrate          # aplica só o que falta
```

Ambos usam `DATABASE_URL` do `.env` ou do ambiente. No Render não é preciso rodar nada: o servidor aplica as migrações ao iniciar.

Sem Node, pelo `psql`, com o mesmo controle de etapas:

```bash
psql "URL_EXTERNA_DO_BANCO" -f database/instalar-tudo.sql
```

Esse arquivo é gerado por `node scripts/gerar-sql-unico.mjs`. Gere de novo sempre que criar uma migração.

## Dependências

- O usuário do banco precisa de `CREATEROLE`, porque a etapa `000` cria os papéis `anon`, `authenticated` e `service_role`. No Render, o usuário dono do banco já tem essa permissão.
- Não precisa de superusuário nem de extensões. `gen_random_uuid()` é nativo desde o PostgreSQL 13.
- As escalas da Mídia têm prazos processados a cada 15 minutos pelo próprio servidor (`escalas_processar_prazos`), sem `pg_cron`.

## Dados iniciais (seed)

Não há `seed.sql` separado. Os únicos dados iniciais necessários e seguros já estão dentro das migrações e entram junto com a estrutura:

- lista de ministérios;
- categorias e cursos-base (ex.: Novos Membros);
- termos-modelo em rascunho;
- configurações padrão, como os limites dos formulários públicos.

Nenhuma pessoa real é criada pelas migrações. Os primeiros administradores vêm da variável `BETEL_MASTERS`. Os dados de demonstração usados nos testes ficam em `testes/semente_agenda.sql` e `previa/exemplos-agenda.sql`, **fora** da instalação de produção.

## Desfazer uma migração

Cada `.down.sql` desfaz a sua migração **sem apagar dados de pessoas**. Ele remove só o que a migração criou: funções, gatilhos, colunas novas ou tabelas novas.

Desfaça sempre da mais nova para a mais antiga. Faça **backup antes**.

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f database/migrations/20261121001200_m12_institucional.down.sql
psql "$DATABASE_URL" -c "delete from sistema.migracoes where nome = '20261121001200_m12_institucional'"
```

**Atenção com a M12:** o `.down.sql` dela remove as tabelas que ela criou (páginas dos ministérios, organogramas, etapas do Colégio, links e fichas da Agenda privada) e as fotos de perfil e do site. Nenhuma pessoa, ministério, vínculo ou evento da Agenda é apagado, mas o conteúdo cadastrado nessas telas depois da M12 se perde. Antes de desfazer em produção, faça backup do banco.

## Preservar os dados existentes

- As migrações são **aditivas**: não renomeiam, não excluem e não recriam tabelas.
- Uma atualização (push) só aplica as migrações novas. As já aplicadas nunca rodam de novo.
- Antes de cada mudança grande, gere um backup manual em **Render → betel-banco → Backups**. Os planos pagos do Render também têm recuperação para um momento no tempo (PITR).
- Para levar os dados para outro servidor PostgreSQL:
  ```bash
  pg_dump --format=custom --no-owner "$DATABASE_URL_ORIGEM" > betel.dump
  pg_restore --no-owner --dbname "$DATABASE_URL_DESTINO" betel.dump
  ```
  O dump já contém `sistema.migracoes`. Assim, o servidor no destino reconhece o que já foi aplicado e não repete nada.
- Nunca rode `schema.sql` num banco que já tem o sistema. Ele é só para consulta e comparação.

## Comparar ambientes

Para conferir se a produção está igual a este repositório:

```bash
pg_dump --schema-only --no-owner --no-comments "$DATABASE_URL" > producao.sql
diff <(grep -v '^--' database/schema.sql) <(grep -v '^--' producao.sql)
```

Se aparecer alguma diferença, analise antes de qualquer alteração destrutiva.
