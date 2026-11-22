// Homologação — conta criada no Supabase Auth sem perfil no sistema (ex.: cadastro aberto ligado por engano) não acessa nada.
import { createClient } from "@supabase/supabase-js";
import pg from "pg";
const c = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY, { auth: { persistSession: false } });
const adm = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const su = await adm.auth.admin.createUser({ email: "intruso@teste.com", password: "Intruso-2026-xx", email_confirm: true });
console.log("signup:", su.error?.message || "ok");
const si = await c.auth.signInWithPassword({ email: "intruso@teste.com", password: "Intruso-2026-xx" });
console.log("login:", si.error?.message || "ok");
if (!si.error) {
  const db = new pg.Client({ host: "/tmp", port: 5434, user: "postgres", database: "betel" }); await db.connect();
  const fns = (await db.query("select p.proname, pg_get_function_identity_arguments(p.oid) a from pg_proc p where p.pronamespace='public'::regnamespace and has_function_privilege('authenticated', p.oid, 'execute')")).rows; await db.end();
  const lixo = (f) => Object.fromEntries((f.a ? f.a.split(", ") : []).map((x) => { const [n, ...t] = x.split(" "); const ty = t.join(" "); return [n, /uuid\[\]/.test(ty) ? [] : /uuid/.test(ty) ? "00000000-0000-0000-0000-000000000001" : /int|numeric/.test(ty) ? 1 : /bool/.test(ty) ? true : /jsonb/.test(ty) ? {} : /date/.test(ty) ? "2026-12-01" : /\[\]/.test(ty) ? [] : "x"]; }));
  const ok = [];
  for (const f of fns) { const r = await c.rpc(f.proname, lixo(f)); if (!r.error && r.data != null && r.data !== false && JSON.stringify(r.data) !== "[]" && JSON.stringify(r.data) !== "{}") ok.push(f.proname + "=" + JSON.stringify(r.data).slice(0, 80)); }
  const PERMITIDAS = /^(agenda_minhas_permissoes|meu_painel|financeiro_minhas_permissoes|minhas_notificacoes|cursos_publicos|midia_ministerio_id|ministerios_publicos|site_conteudo_publico)=/;
  // agenda_link_abrir sem código válido e institucional_permissoes sem perfil só respondem "não"
  const NEGATIVAS = /^(agenda_link_abrir=\{"ok":false|agenda_link_enviar=\{"ok":false|institucional_permissoes=\{"ativo":false\})/;
  const ruins = ok.filter((x) => NEGATIVAS.test(x) ? false : !PERMITIDAS.test(x) || /"(secretaria|tesouraria)":true/.test(x) || /"itens":\[\{/.test(x));
  console.log(ruins.length ? "  ✗ conta sem perfil recebe dados: " + ruins.join(" | ") : "  ✓ conta sem perfil só recebe \"sem perfil\" e o catálogo público");
  const tabs = (await (async () => { const d = new pg.Client({ host: "/tmp", port: 5434, user: "postgres", database: "betel" }); await d.connect(); const r = (await d.query("select relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'")).rows; await d.end(); return r; })()).map((r) => r.relname);
  const vaz = []; for (const t of tabs) { const r = await c.from(t).select("*").limit(3); if (!r.error && r.data.length && !["categorias_curso","configuracoes","cursos","eventos","ministerios","reservas","turmas"].includes(t)) vaz.push(t); }
  console.log(vaz.length ? "  ✗ tabelas visíveis: " + vaz.join(",") : "  ✓ conta sem perfil não lê nenhuma tabela restrita");
  console.log(`\nResultado: ${2 - (ruins.length ? 1 : 0) - (vaz.length ? 1 : 0)} ok, ${(ruins.length ? 1 : 0) + (vaz.length ? 1 : 0)} falha(s)`);
}
