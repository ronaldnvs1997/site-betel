// Administração de contas pelo MASTER:
//  - criar: cria conta com senha temporária (sem solicitação prévia)
//  - senha_temporaria: gera nova senha temporária (troca obrigatória no próximo acesso)
//  - definir_ativo: ativa ou desativa a conta (bloqueia também o login no Auth)
import { type Deps, ErroHttp, clienteServico, exigirMaster, gerarSenhaTemporaria, json, mensagemErroAuth, servir, validarAcesso } from "../_shared/comum.ts";

const UUID = /^[0-9a-f-]{36}$/i;

export function criarHandler(deps: Deps) {
  return servir(async (req) => {
    const admin = clienteServico(deps);
    const master = await exigirMaster(req, admin);
    const corpo = await req.json().catch(() => ({}));

    if (corpo.acao === "criar") {
      const nome = String(corpo.nome || "").trim().replace(/\s+/g, " ");
      const email = String(corpo.email || "").trim().toLowerCase();
      const telefone = String(corpo.telefone || "").replace(/\D/g, "");
      if (nome.length < 3 || !nome.includes(" ")) throw new ErroHttp(400, "Informe o nome completo.");
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new ErroHttp(400, "Informe um e-mail válido.");
      if (!/^[0-9]{10,13}$/.test(telefone)) throw new ErroHttp(400, "Informe um telefone válido, com DDD.");
      const acesso = validarAcesso(corpo.perfil, corpo.atribuicoes, corpo.ministerios);
      const senha = gerarSenhaTemporaria();
      const { data: criado, error } = await admin.auth.admin.createUser({ email, password: senha, email_confirm: true, user_metadata: { nome } });
      if (error || !criado?.user) throw new ErroHttp(409, mensagemErroAuth(error));
      const { error: e2 } = await admin.rpc("servico_criar_usuario", {
        p_ator: master.id, p_usuario: criado.user.id, p_nome: nome, p_telefone: telefone, p_email: email,
        p_perfil: acesso.perfil, p_atribuicoes: acesso.atribuicoes, p_ministerios: acesso.ministerios, p_solicitacao: null,
      });
      if (e2) { await admin.auth.admin.deleteUser(criado.user.id); throw new ErroHttp(409, e2.message || "Não foi possível criar o usuário."); }
      return json({ ok: true, usuario_id: criado.user.id, nome, email, telefone, senha_temporaria: senha });
    }

    const alvo = String(corpo.usuario_id || "");
    if (!UUID.test(alvo)) throw new ErroHttp(400, "Usuário inválido.");

    if (corpo.acao === "senha_temporaria") {
      if (alvo === master.id) throw new ErroHttp(400, "Para a sua própria conta, use \"Trocar senha\".");
      const senha = gerarSenhaTemporaria();
      const { error } = await admin.auth.admin.updateUserById(alvo, { password: senha });
      if (error) throw new ErroHttp(404, "Usuário não encontrado.");
      const { error: e2 } = await admin.rpc("servico_marcar_senha_temporaria", { p_ator: master.id, p_usuario: alvo });
      if (e2) throw new ErroHttp(409, e2.message);
      const { data: u } = await admin.auth.admin.getUserById(alvo);
      return json({ ok: true, usuario_id: alvo, email: u?.user?.email, senha_temporaria: senha });
    }

    if (corpo.acao === "definir_ativo") {
      const ativo = corpo.ativo === true;
      const { error } = await admin.rpc("servico_definir_ativo", { p_ator: master.id, p_usuario: alvo, p_ativo: ativo });
      if (error) throw new ErroHttp(409, error.message);
      // Bloqueio também no Auth: conta desativada não consegue entrar nem renovar a sessão
      const { error: e2 } = await admin.auth.admin.updateUserById(alvo, { ban_duration: ativo ? "none" : "876000h" });
      if (e2) throw new ErroHttp(500, "Conta atualizada no cadastro, mas o bloqueio de login falhou. Tente de novo.");
      return json({ ok: true });
    }

    throw new ErroHttp(400, "Ação desconhecida.");
  });
}
