// Cria as contas dos primeiros MASTERs (uso único, na implantação).
// Rodar num computador seguro, com a chave de serviço do projeto:
//   SUPABASE_URL=https://<projeto>.supabase.co SUPABASE_SERVICE_ROLE_KEY=<chave> \
//   node criar-primeiros-masters.mjs "Nome Completo|email|telefone" ...
// Cada pessoa recebe uma senha temporária (mostrada só aqui) e é obrigada a trocá-la no primeiro acesso.
// Depois que um MASTER concluir o primeiro acesso, este script deixa de funcionar
// (novos usuários passam a ser criados pela Área de Membros).
import { createClient } from "@supabase/supabase-js";
import crypto from "node:crypto";

const url = process.env.SUPABASE_URL, chave = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !chave) { console.error("Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY."); process.exit(1); }
const admin = createClient(url, chave, { auth: { persistSession: false, autoRefreshToken: false } });
const alfabeto = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";
function senha() { const b = crypto.randomBytes(12); let s = ""; for (let i = 0; i < 12; i++) { s += alfabeto[b[i] % alfabeto.length]; if (i === 3 || i === 7) s += "-"; } return /[A-Z]/.test(s) && /[a-z]/.test(s) && /\d/.test(s) ? s : senha(); }

const pessoas = process.argv.slice(2).map((a) => { const [nome, email, telefone] = a.split("|"); return { nome, email: email.trim().toLowerCase(), telefone: (telefone || "").replace(/\D/g, "") }; });
if (!pessoas.length) { console.error('Informe ao menos uma pessoa: "Nome Completo|email|telefone"'); process.exit(1); }
for (const p of pessoas) {
  const s = senha();
  const { data, error } = await admin.auth.admin.createUser({ email: p.email, password: s, email_confirm: true, user_metadata: { nome: p.nome } });
  if (error) { console.error(`${p.email}: ${error.message}`); continue; }
  const { error: e2 } = await admin.rpc("servico_criar_usuario", { p_ator: null, p_usuario: data.user.id, p_nome: p.nome, p_telefone: p.telefone, p_email: p.email,
    p_perfil: "MASTER", p_atribuicoes: [], p_ministerios: [], p_solicitacao: null });
  if (e2) { await admin.auth.admin.deleteUser(data.user.id); console.error(`${p.email}: ${e2.message}`); continue; }
  console.log(`${p.nome} <${p.email}> — senha temporária: ${s}`);
}
