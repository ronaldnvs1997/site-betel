// Gerado a partir de supabase/functions (aprovar-acesso/handler.ts). Função de servidor do Sistema Betel.
import { ErroHttp, clienteServico, exigirMaster, gerarSenhaTemporaria, json, mensagemErroAuth, servir, validarAcesso } from "./comum.mjs";
function criarHandler(deps) {
  return servir(async (req) => {
    const admin = clienteServico(deps);
    const master = await exigirMaster(req, admin);
    const corpo = await req.json().catch(() => ({}));
    const id = String(corpo.solicitacao_id || "");
    if (!/^[0-9a-f-]{36}$/i.test(id)) throw new ErroHttp(400, "Solicita\xE7\xE3o inv\xE1lida.");
    const { data: sols, error: e1 } = await admin.from("solicitacoes").select("id,nome,telefone,email,ministerio_id,funcao_pretendida,status,tipo").eq("id", id);
    if (e1) throw new ErroHttp(500, "N\xE3o foi poss\xEDvel ler a solicita\xE7\xE3o.");
    const s = sols?.[0];
    if (!s || s.tipo !== "acesso" || s.status !== "pendente") throw new ErroHttp(409, "Solicita\xE7\xE3o n\xE3o encontrada ou j\xE1 analisada.");
    const perfilPadrao = s.funcao_pretendida === "lider" ? "LIDER" : "VOLUNTARIO";
    const acesso = validarAcesso(
      corpo.perfil ?? perfilPadrao,
      corpo.atribuicoes ?? [],
      corpo.ministerios ?? [{ ministerio_id: s.ministerio_id, funcao: s.funcao_pretendida }]
    );
    const senha = gerarSenhaTemporaria();
    const { data: criado, error: e2 } = await admin.auth.admin.createUser({
      email: s.email,
      password: senha,
      email_confirm: true,
      user_metadata: { nome: s.nome }
    });
    if (e2 || !criado?.user) throw new ErroHttp(409, mensagemErroAuth(e2));
    const { error: e3 } = await admin.rpc("servico_criar_usuario", {
      p_ator: master.id,
      p_usuario: criado.user.id,
      p_nome: s.nome,
      p_telefone: s.telefone,
      p_email: s.email,
      p_perfil: acesso.perfil,
      p_atribuicoes: acesso.atribuicoes,
      p_ministerios: acesso.ministerios,
      p_solicitacao: s.id
    });
    if (e3) {
      await admin.auth.admin.deleteUser(criado.user.id);
      throw new ErroHttp(409, e3.message || "N\xE3o foi poss\xEDvel concluir a aprova\xE7\xE3o.");
    }
    return json({ ok: true, usuario_id: criado.user.id, nome: s.nome, email: s.email, telefone: s.telefone, senha_temporaria: senha });
  });
}
export {
  criarHandler
};
