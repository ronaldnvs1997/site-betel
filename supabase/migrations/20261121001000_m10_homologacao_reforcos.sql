-- =====================================================================
-- M10 — Reforços da homologação (aditiva e reversível)
-- Limite de volume nos formulários públicos (sem login), contra robôs que
-- lotariam vagas ou encheriam a Secretaria de cadastros falsos.
-- Não usa IP nem nada do aparelho: conta só os registros feitos sem login.
-- Os limites ficam em configuracoes (chave limites_publicos) e podem ser ajustados.
-- =====================================================================
begin;

insert into public.configuracoes (chave, valor, publico)
values ('limites_publicos', '{"inscricoes_por_pessoa_hora": 3, "inscricoes_10min": 60, "membresia_10min": 20}', false)
on conflict (chave) do nothing;

create function public.limite_publico(p_chave text, p_padrao int) returns int
language sql stable security definer set search_path = '' as $$
  select coalesce((select (valor->>p_chave)::int from public.configuracoes where chave = 'limites_publicos'), p_padrao)
$$;

create function public.tg_limite_publico() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null then return new; end if;        -- só o que chega sem login
  if tg_table_name = 'inscricoes' then
    if (select count(*) from public.inscricoes where pessoa_id = new.pessoa_id and criado_por is null and criado_em > now() - interval '1 hour')
       >= public.limite_publico('inscricoes_por_pessoa_hora', 3) then
      raise exception 'Você já fez várias inscrições agora há pouco. Aguarde uma hora ou fale com a Secretaria.' using errcode = 'P0001';
    end if;
    if (select count(*) from public.inscricoes where criado_por is null and criado_em > now() - interval '10 minutes')
       >= public.limite_publico('inscricoes_10min', 60) then
      raise exception 'Estamos recebendo muitas inscrições neste momento. Tente de novo em alguns minutos.' using errcode = 'P0001';
    end if;
  elsif tg_table_name = 'membresia_processos' then
    if new.origem = 'site' and (select count(*) from public.membresia_processos where origem = 'site' and criado_em > now() - interval '10 minutes')
       >= public.limite_publico('membresia_10min', 20) then
      raise exception 'Estamos recebendo muitos pedidos neste momento. Tente de novo em alguns minutos.' using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;

create trigger inscricoes_limite_publico before insert on public.inscricoes for each row execute function public.tg_limite_publico();
create trigger membresia_limite_publico before insert on public.membresia_processos for each row execute function public.tg_limite_publico();

revoke execute on function public.limite_publico(text, int), public.tg_limite_publico() from public, anon, authenticated;

commit;
