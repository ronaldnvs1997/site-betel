// Gerado a partir de supabase/functions (arquivos/handler.ts). Função de servidor do Sistema Betel.
import { ErroHttp, clienteServico, json, servir } from "./comum.mjs";
const TIPOS = { "application/pdf": "pdf", "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" };
const MAX = 5 * 1024 * 1024;
const UUID = /^[0-9a-f-]{36}$/i;
function decodificar(arq) {
  if (!arq || typeof arq.base64 !== "string" || typeof arq.tipo !== "string") throw new ErroHttp(400, "Anexe o arquivo.");
  if (!TIPOS[arq.tipo]) throw new ErroHttp(415, "Envie PDF, JPG, PNG ou WebP.");
  const bin = atob(arq.base64);
  if (bin.length === 0) throw new ErroHttp(400, "Arquivo vazio.");
  if (bin.length > MAX) throw new ErroHttp(413, "O arquivo passa de 5 MB.");
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  const ini = (n) => Array.from(bytes.slice(0, n)).map((b) => b.toString(16).padStart(2, "0")).join("");
  const ok = arq.tipo === "application/pdf" ? bin.startsWith("%PDF") : arq.tipo === "image/jpeg" ? ini(3) === "ffd8ff" : arq.tipo === "image/png" ? ini(8) === "89504e470d0a1a0a" : bin.startsWith("RIFF") && bin.slice(8, 12) === "WEBP";
  if (!ok) throw new ErroHttp(415, "O conte\xFAdo do arquivo n\xE3o corresponde ao tipo informado.");
  return { bytes, tipo: arq.tipo, nome: String(arq.nome || "arquivo").slice(0, 200) };
}
async function sha256(bytes) {
  const h = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(h)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
async function quemChamou(req, deps) {
  const auth = req.headers.get("Authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token || token === deps.env("SUPABASE_ANON_KEY")) return null;
  const cli = deps.createClient(deps.env("SUPABASE_URL"), deps.env("SUPABASE_ANON_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } }
  });
  const { data, error } = await cli.rpc("financeiro_minhas_permissoes");
  if (error || !data?.usuario) return null;
  return { cli, id: data.usuario, secretaria: data.secretaria === true, tesouraria: data.tesouraria === true };
}
function criarHandler(deps) {
  return servir(async (req) => {
    const admin = clienteServico(deps);
    const corpo = await req.json().catch(() => ({}));
    const quem = await quemChamou(req, deps);
    if (corpo.acao === "enviar_comprovante") {
      let inscricao, pagamento = null, ator = null;
      if (corpo.pagamento_id) {
        if (!quem || !(quem.secretaria || quem.tesouraria)) throw new ErroHttp(403, "Somente a Secretaria ou a Tesouraria anexam recibos.");
        if (!UUID.test(corpo.pagamento_id)) throw new ErroHttp(400, "Pagamento inv\xE1lido.");
        const { data: data2 } = await admin.from("pagamentos").select("id,inscricao_id").eq("id", corpo.pagamento_id);
        if (!data2?.[0]) throw new ErroHttp(404, "Pagamento n\xE3o encontrado.");
        inscricao = data2[0].inscricao_id;
        pagamento = data2[0].id;
        ator = quem.id;
      } else {
        const { data: data2 } = await admin.rpc("servico_validar_link", { p_protocolo: String(corpo.protocolo || ""), p_chave: String(corpo.chave || "") });
        if (!data2) throw new ErroHttp(404, "Inscri\xE7\xE3o n\xE3o encontrada. Confira o link recebido.");
        inscricao = data2;
      }
      const arq = decodificar(corpo.arquivo);
      const caminho = `${inscricao}/${crypto.randomUUID()}.${TIPOS[arq.tipo]}`;
      const up = await admin.storage.from("comprovantes").upload(caminho, arq.bytes, { contentType: arq.tipo, upsert: false });
      if (up.error) throw new ErroHttp(500, "N\xE3o foi poss\xEDvel guardar o arquivo.");
      const { data, error } = await admin.rpc("servico_registrar_comprovante", {
        p_ator: ator,
        p_inscricao: inscricao,
        p_pagamento: pagamento,
        p_metodo: corpo.metodo ?? null,
        p_valor: corpo.valor ?? null,
        p_pago_em: corpo.pago_em || null,
        p_path: caminho,
        p_nome: arq.nome,
        p_mime: arq.tipo,
        p_tamanho: arq.bytes.length,
        p_hash: await sha256(arq.bytes)
      });
      if (error) {
        await admin.storage.from("comprovantes").remove([caminho]);
        throw new ErroHttp(409, error.message);
      }
      return json({ ok: true, ...data, mensagem: "Comprovante recebido. A inscri\xE7\xE3o ser\xE1 confirmada depois da an\xE1lise da Tesouraria." });
    }
    if (corpo.acao === "enviar_documento") {
      if (!quem || !quem.secretaria) throw new ErroHttp(403, "Somente a Secretaria envia documentos.");
      if (!UUID.test(String(corpo.pessoa_id))) throw new ErroHttp(400, "Pessoa inv\xE1lida.");
      const arq = decodificar(corpo.arquivo);
      const caminho = `${corpo.pessoa_id}/${crypto.randomUUID()}.${TIPOS[arq.tipo]}`;
      const up = await admin.storage.from("documentos").upload(caminho, arq.bytes, { contentType: arq.tipo, upsert: false });
      if (up.error) throw new ErroHttp(500, "N\xE3o foi poss\xEDvel guardar o arquivo.");
      const { data, error } = await admin.rpc("servico_registrar_documento", {
        p_ator: quem.id,
        p_pessoa: corpo.pessoa_id,
        p_tipo: corpo.tipo,
        p_descricao: corpo.descricao ?? null,
        p_path: caminho,
        p_nome: arq.nome,
        p_mime: arq.tipo,
        p_tamanho: arq.bytes.length,
        p_hash: await sha256(arq.bytes)
      });
      if (error) {
        await admin.storage.from("documentos").remove([caminho]);
        throw new ErroHttp(409, /tipo/.test(error.message) ? "Tipo de documento inv\xE1lido." : error.message);
      }
      return json({ ok: true, ...data });
    }
    if (corpo.acao === "link") {
      if (!quem) throw new ErroHttp(401, "Fa\xE7a login para continuar.");
      const tipo = corpo.tipo === "documento" ? "documento" : "comprovante";
      if (!UUID.test(String(corpo.id))) throw new ErroHttp(400, "Arquivo inv\xE1lido.");
      const { data: caminho } = await quem.cli.rpc("arquivo_autorizado", { p_tipo: tipo, p_id: corpo.id });
      if (!caminho) throw new ErroHttp(403, "Voc\xEA n\xE3o tem acesso a este arquivo.");
      const { data, error } = await admin.storage.from(tipo === "documento" ? "documentos" : "comprovantes").createSignedUrl(caminho, 300);
      if (error) throw new ErroHttp(500, "N\xE3o foi poss\xEDvel gerar o link.");
      return json({ ok: true, url: data.signedUrl, expira_em_segundos: 300 });
    }
    throw new ErroHttp(400, "A\xE7\xE3o desconhecida.");
  });
}
export {
  criarHandler
};
