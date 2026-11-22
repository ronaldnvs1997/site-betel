// Utilidades compartilhadas pelas funções de servidor (Supabase Edge Functions).
// Escrito só com APIs Web padrão; o cliente do Supabase é injetado em `Deps`.

export type Deps = {
  createClient: (url: string, key: string, opts?: unknown) => any;
  env: (nome: string) => string | undefined;
};

// Em produção, defina o segredo SITE_ORIGEM (ex.: https://betelflamengo.com.br) para só o site chamar estas funções.
// Sem ele (desenvolvimento), aceita qualquer origem. O acesso continua exigindo login e permissão no banco.
const ORIGEM = ((globalThis as any).Deno?.env?.get?.("SITE_ORIGEM") as string | undefined) || "*";
export const cors: Record<string, string> = {
  "Access-Control-Allow-Origin": ORIGEM,
  "Vary": "Origin",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(corpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8" },
  });
}

export class ErroHttp extends Error {
  status: number;
  constructor(status: number, mensagem: string) { super(mensagem); this.status = status; }
}

// Cliente com a chave de serviço (somente no servidor; nunca vai ao navegador)
export function clienteServico(deps: Deps) {
  const url = deps.env("SUPABASE_URL");
  const chave = deps.env("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !chave) throw new ErroHttp(500, "Configuração do servidor incompleta.");
  return deps.createClient(url, chave, { auth: { persistSession: false, autoRefreshToken: false } });
}

// Identifica quem chamou (pelo token da sessão) e exige perfil MASTER ativo.
// A permissão é conferida no banco (e_master_uid), nunca por IP ou pela tela.
export async function exigirMaster(req: Request, admin: any): Promise<{ id: string; email: string }> {
  const auth = req.headers.get("Authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token) throw new ErroHttp(401, "Faça login para continuar.");
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data?.user) throw new ErroHttp(401, "Sessão inválida ou expirada. Entre novamente.");
  const { data: ok, error: e2 } = await admin.rpc("e_master_uid", { p_uid: data.user.id });
  if (e2) throw new ErroHttp(500, "Não foi possível conferir a permissão.");
  if (ok !== true) throw new ErroHttp(403, "Somente o MASTER pode fazer isso.");
  return { id: data.user.id, email: data.user.email };
}

// Senha temporária forte, sem caracteres ambíguos (ex.: k7Qm-9Tz2-Wp4x)
export function gerarSenhaTemporaria(): string {
  const alfabeto = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = new Uint8Array(12);
  crypto.getRandomValues(bytes);
  let s = "";
  for (let i = 0; i < 12; i++) {
    s += alfabeto[bytes[i] % alfabeto.length];
    if (i === 3 || i === 7) s += "-";
  }
  // Garante letra maiúscula, minúscula e número
  if (!/[A-Z]/.test(s) || !/[a-z]/.test(s) || !/[0-9]/.test(s)) return gerarSenhaTemporaria();
  return s;
}

export const PERFIS = ["MASTER", "LIDER", "VOLUNTARIO"];
export const ATRIBUICOES = ["SECRETARIA", "TESOURARIA"];

export type Vinculo = { ministerio_id: string; funcao: "lider" | "voluntario" };

export function validarAcesso(perfil: unknown, atribuicoes: unknown, ministerios: unknown): {
  perfil: string; atribuicoes: string[]; ministerios: Vinculo[];
} {
  if (typeof perfil !== "string" || !PERFIS.includes(perfil)) throw new ErroHttp(400, "Escolha o perfil: MASTER, LÍDER ou VOLUNTÁRIO.");
  const atr = Array.isArray(atribuicoes) ? atribuicoes : [];
  if (!atr.every((a) => typeof a === "string" && ATRIBUICOES.includes(a))) throw new ErroHttp(400, "Atribuição inválida.");
  const mins = Array.isArray(ministerios) ? ministerios : [];
  const uuid = /^[0-9a-f-]{36}$/i;
  for (const m of mins) {
    if (!m || typeof m !== "object" || !uuid.test(String((m as any).ministerio_id)) ||
        !["lider", "voluntario"].includes((m as any).funcao)) throw new ErroHttp(400, "Ministério inválido.");
  }
  if (perfil === "LIDER" && !mins.some((m: any) => m.funcao === "lider")) {
    throw new ErroHttp(400, "Um LÍDER precisa liderar ao menos um ministério.");
  }
  return { perfil, atribuicoes: [...new Set(atr as string[])], ministerios: mins as Vinculo[] };
}

export function mensagemErroAuth(e: any): string {
  const m = String(e?.message || "");
  if (/already|registered|exists/i.test(m)) return "Já existe uma conta com este e-mail.";
  return "Não foi possível criar a conta de acesso.";
}

// Envolve o handler com CORS, método e tratamento de erros
export function servir(fn: (req: Request) => Promise<Response>) {
  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
    if (req.method !== "POST") return json({ erro: "Método não permitido." }, 405);
    try {
      return await fn(req);
    } catch (e) {
      if (e instanceof ErroHttp) return json({ erro: e.message }, e.status);
      console.error(e);
      return json({ erro: "Erro interno. Tente novamente." }, 500);
    }
  };
}
