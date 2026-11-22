-- Plataforma 003 — "Sair" encerra a sessão no servidor (aditiva).
-- Cada login recebe um identificador de sessão. Ao sair, a sessão é
-- encerrada: o token de renovação é apagado e o token de acesso daquela
-- sessão deixa de ser aceito, mesmo antes de expirar.
alter table auth.sessoes add column if not exists sessao_id uuid;
create index if not exists sessoes_sessao_id on auth.sessoes (sessao_id);
create table if not exists auth.sessoes_encerradas (
  sessao_id uuid primary key,
  expira_em timestamptz not null
);
