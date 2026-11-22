// Gerado a partir de supabase/functions (_shared/comum.ts). Função de servidor do Sistema Betel.
const ORIGEM = globalThis.Deno?.env?.get?.("SITE_ORIGEM") || "*";
const cors = {
  "Access-Control-Allow-Origin": ORIGEM,
  "Vary": "Origin",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};
function json(corpo, status = 200) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8" }
  });
}
class ErroHttp extends Error {
  status;
  constructor(status, mensagem) {
    super(mensagem);
    this.status = status;
  }
}
function clienteServico(deps) {
  const url = deps.env("SUPABASE_URL");
  const chave = deps.env("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !chave) throw new ErroHttp(500, "Configura\xE7\xE3o do servidor incompleta.");
  return deps.createClient(url, chave, { auth: { persistSession: false, autoRefreshToken: false } });
}
async function exigirMaster(req, admin) {
  const auth = req.headers.get("Authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token) throw new ErroHttp(401, "Fa\xE7a login para continuar.");
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data?.user) throw new ErroHttp(401, "Sess\xE3o inv\xE1lida ou expirada. Entre novamente.");
  const { data: ok, error: e2 } = await admin.rpc("e_master_uid", { p_uid: data.user.id });
  if (e2) throw new ErroHttp(500, "N\xE3o foi poss\xEDvel conferir a permiss\xE3o.");
  if (ok !== true) throw new ErroHttp(403, "Somente o MASTER pode fazer isso.");
  return { id: data.user.id, email: data.user.email };
}
function gerarSenhaTemporaria() {
  const alfabeto = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = new Uint8Array(12);
  crypto.getRandomValues(bytes);
  let s = "";
  for (let i = 0; i < 12; i++) {
    s += alfabeto[bytes[i] % alfabeto.length];
    if (i === 3 || i === 7) s += "-";
  }
  if (!/[A-Z]/.test(s) || !/[a-z]/.test(s) || !/[0-9]/.test(s)) return gerarSenhaTemporaria();
  return s;
}
const PERFIS = ["MASTER", "LIDER", "VOLUNTARIO"];
const ATRIBUICOES = ["SECRETARIA", "TESOURARIA"];
function validarAcesso(perfil, atribuicoes, ministerios) {
  if (typeof perfil !== "string" || !PERFIS.includes(perfil)) throw new ErroHttp(400, "Escolha o perfil: MASTER, L\xCDDER ou VOLUNT\xC1RIO.");
  const atr = Array.isArray(atribuicoes) ? atribuicoes : [];
  if (!atr.every((a) => typeof a === "string" && ATRIBUICOES.includes(a))) throw new ErroHttp(400, "Atribui\xE7\xE3o inv\xE1lida.");
  const mins = Array.isArray(ministerios) ? ministerios : [];
  const uuid = /^[0-9a-f-]{36}$/i;
  for (const m of mins) {
    if (!m || typeof m !== "object" || !uuid.test(String(m.ministerio_id)) || !["lider", "voluntario"].includes(m.funcao)) throw new ErroHttp(400, "Minist\xE9rio inv\xE1lido.");
  }
  if (perfil === "LIDER" && !mins.some((m) => m.funcao === "lider")) {
    throw new ErroHttp(400, "Um L\xCDDER precisa liderar ao menos um minist\xE9rio.");
  }
  return { perfil, atribuicoes: [...new Set(atr)], ministerios: mins };
}
function mensagemErroAuth(e) {
  const m = String(e?.message || "");
  if (/already|registered|exists/i.test(m)) return "J\xE1 existe uma conta com este e-mail.";
  return "N\xE3o foi poss\xEDvel criar a conta de acesso.";
}
function servir(fn) {
  return async (req) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
    if (req.method !== "POST") return json({ erro: "M\xE9todo n\xE3o permitido." }, 405);
    try {
      return await fn(req);
    } catch (e) {
      if (e instanceof ErroHttp) return json({ erro: e.message }, e.status);
      console.error(e);
      return json({ erro: "Erro interno. Tente novamente." }, 500);
    }
  };
}
export {
  ATRIBUICOES,
  ErroHttp,
  PERFIS,
  clienteServico,
  cors,
  exigirMaster,
  gerarSenhaTemporaria,
  json,
  mensagemErroAuth,
  servir,
  validarAcesso
};
