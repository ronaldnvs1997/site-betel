    // =========================================================================
    // LOGIN E MODO COORDENADOR (login central da Betel — Supabase Auth)
    // A senha nunca é comparada no navegador: quem confere é o Auth.
    // =========================================================================
    const logado = () => !!(permissoes && permissoes.status === 'ok');

    async function alternarModoCoordenador() {
      if (!permissoes) {
        abrirModalLoginCoord();
        return;
      }
      await db.auth.signOut({ scope: 'local' });
      permissoes = null;
      modoCoordenador = false;
      coordenadorAtual = null;
      atualizarInterfaceCoordenador();
      if (eventoSelecionado) abrirPaginaEvento(eventoSelecionado.id);
      mostrarAviso('Você saiu da sua conta.', 'info');
    }

    function abrirModalLoginCoord() {
      document.getElementById('login-coord-usuario').value = '';
      document.getElementById('login-coord-senha').value = '';
      document.getElementById('erro-login-coord').classList.add('hidden');
      document.getElementById('modal-login-coord').classList.remove('hidden');
      setTimeout(() => document.getElementById('login-coord-usuario').focus(), 50);
    }

    function fecharModalLoginCoord() {
      document.getElementById('modal-login-coord').classList.add('hidden');
    }

    function mensagemErroLogin(err) {
      const c = err?.code || '', m = String(err?.message || '');
      if (c === 'invalid_credentials' || /invalid login/i.test(m)) return 'E-mail ou senha incorretos.';
      if (c === 'user_banned' || /banned/i.test(m)) return 'Esta conta está desativada. Fale com o responsável (MASTER).';
      if (/rate limit/i.test(m)) return 'Muitas tentativas seguidas. Aguarde alguns minutos.';
      return 'Não foi possível entrar: ' + m;
    }

    async function autenticarCoordenador(e) {
      e.preventDefault();
      const email = document.getElementById('login-coord-usuario').value.trim().toLowerCase();
      const senha = document.getElementById('login-coord-senha').value;
      const erroEl = document.getElementById('erro-login-coord');
      const btn = document.getElementById('btn-entrar-coord');
      const mostrarErro = (html) => { erroEl.innerHTML = html; erroEl.classList.remove('hidden'); };

      erroEl.classList.add('hidden');
      btn.disabled = true;
      btn.textContent = 'Verificando...';

      const { error } = await db.auth.signInWithPassword({ email, password: senha });
      if (!error) await carregarPermissoes();

      btn.disabled = false;
      btn.textContent = 'Entrar';

      if (error) { mostrarErro(esc(mensagemErroLogin(error))); return; }
      if (permissoes?.status === 'trocar_senha') {
        mostrarErro('Primeiro acesso: crie a sua senha na <a class="underline font-bold" href="../#equipe">Área de Membros</a> e depois volte aqui.');
        return;
      }
      if (permissoes?.status === 'inativo') { await db.auth.signOut({ scope: 'local' }); permissoes = null; mostrarErro('Esta conta está desativada.'); return; }
      if (permissoes?.status !== 'ok') { await db.auth.signOut({ scope: 'local' }); permissoes = null; mostrarErro('Sua conta ainda não tem acesso liberado. Fale com o responsável.'); return; }

      fecharModalLoginCoord();
      atualizarInterfaceCoordenador();
      if (eventoSelecionado) abrirPaginaEvento(eventoSelecionado.id);
      if (modoCoordenador) mostrarAviso(`Bem-vindo(a), ${permissoes.nome}! Modo Coordenador habilitado.`, 'sucesso');
      else if ((permissoes.ministerios_lider || []).length) mostrarAviso(`Bem-vindo(a), ${permissoes.nome}! Você pode preencher as fichas de: ${permissoes.ministerios_lider.map(m => m.nome).join(', ')}.`, 'sucesso');
      else mostrarAviso(`Bem-vindo(a), ${permissoes.nome}! Sua conta pode consultar a agenda.`, 'info');
    }

    function atualizarInterfaceCoordenador(render = true) {
      const btn = document.getElementById('btn-modo-coord');
      btn.textContent = !permissoes ? 'Entrar / Modo Coordenador'
        : modoCoordenador ? 'Sair do Modo Coordenador'
        : `Sair (${String(permissoes.nome || 'conta').split(' ')[0]})`;

      if (modoCoordenador && coordenadorAtual) {
        document.getElementById('nome-coord-logado').textContent = coordenadorAtual.nome;
      }
      document.getElementById('barra-coordenador').classList.toggle('hidden', !modoCoordenador);
      document.getElementById('btn-gestao-coord').classList.toggle('hidden', !(permissoes && permissoes.master));

      const lider = logado() && !modoCoordenador;
      document.getElementById('barra-lider').classList.toggle('hidden', !lider);
      if (lider) {
        const mins = (permissoes.ministerios_lider || []).map(m => m.nome);
        document.getElementById('texto-barra-lider').innerHTML = `<strong>Conectado(a): ${esc(permissoes.nome)}.</strong> ` +
          (mins.length ? `Você pode preencher as fichas de: <strong>${esc(mins.join(', '))}</strong>.` : 'Sua conta pode consultar a agenda.');
      }
      if (render) renderizarCalendario();
    }


    // =========================================================================
    // ALTERAÇÃO DE SENHA (conta central)
    // =========================================================================
    async function abrirModalAlterarSenha() {
      if (!logado()) return;
      const { data: { session } } = await db.auth.getSession();
      document.getElementById('alterar-senha-usuario-label').textContent = `${permissoes.nome} (${session?.user?.email || ''})`;
      document.getElementById('senha-atual-coord').value = '';
      document.getElementById('nova-senha-coord').value = '';
      document.getElementById('confirmar-nova-senha-coord').value = '';
      document.getElementById('erro-alterar-senha').classList.add('hidden');
      document.getElementById('modal-alterar-senha').classList.remove('hidden');
      setTimeout(() => document.getElementById('senha-atual-coord').focus(), 50);
    }

    function fecharModalAlterarSenha() {
      document.getElementById('modal-alterar-senha').classList.add('hidden');
    }

    async function salvarNovaSenhaCoordenador(e) {
      e.preventDefault();
      if (!logado()) return;

      const senhaAtual = document.getElementById('senha-atual-coord').value;
      const novaSenha = document.getElementById('nova-senha-coord').value;
      const confirmarSenha = document.getElementById('confirmar-nova-senha-coord').value;
      const erroEl = document.getElementById('erro-alterar-senha');
      const btn = document.getElementById('btn-salvar-nova-senha');
      const erro = (t) => { erroEl.textContent = t; erroEl.classList.remove('hidden'); };

      erroEl.classList.add('hidden');
      if (novaSenha.length < 10 || !/[A-Za-zÀ-ú]/.test(novaSenha) || !/\d/.test(novaSenha)) { erro('A nova senha deve ter pelo menos 10 caracteres, com letras e números.'); return; }
      if (novaSenha !== confirmarSenha) { erro('A confirmação da nova senha não confere.'); return; }

      btn.disabled = true;
      btn.textContent = 'Verificando...';
      const { data: { session } } = await db.auth.getSession();
      // A senha atual é conferida pelo Auth (no servidor), não no navegador
      const { error: erroVerif } = await db.auth.signInWithPassword({ email: session.user.email, password: senhaAtual });
      if (erroVerif) { btn.disabled = false; btn.textContent = 'Salvar Senha'; erro('A senha atual informada está incorreta.'); return; }

      btn.textContent = 'Salvando...';
      const { error: erroUpdate } = await db.auth.updateUser({ password: novaSenha });
      btn.disabled = false;
      btn.textContent = 'Salvar Senha';
      if (erroUpdate) {
        erro(/different/i.test(erroUpdate.message) ? 'A nova senha precisa ser diferente da atual.' : 'Erro ao atualizar a senha: ' + erroUpdate.message);
        return;
      }
      fecharModalAlterarSenha();
      mostrarAviso('Sua senha foi alterada com sucesso! Ela vale também para a Área de Membros.', 'sucesso');
    }

    // =========================================================================
    // GESTÃO DE COORDENADORES (somente MASTER)
    // Coordenador = conta da equipe com acesso de coordenação na Agenda.
    // Os coordenadores antigos (login e senha próprios) são ligados a uma conta;
    // nenhum registro é apagado: "remover" passa a ser desativar.
    // =========================================================================
    let contasEquipe = [];

    async function abrirModalGestaoCoordenadores() {
      if (!permissoes || !permissoes.master) return;
      document.getElementById('modal-gestao-coord').classList.remove('hidden');
      await carregarListaCoordenadores();
    }

    function fecharModalGestaoCoordenadores() {
      document.getElementById('modal-gestao-coord').classList.add('hidden');
    }

    function opcoesContas(selecionado) {
      return '<option value="">Escolha uma conta…</option>' + contasEquipe.filter(u => u.ativo)
        .map(u => `<option value="${esc(u.id)}"${u.id === selecionado ? ' selected' : ''}>${esc(u.nome)} — ${esc(u.email)}</option>`).join('');
    }

    async function carregarListaCoordenadores() {
      const container = document.getElementById('lista-coordenadores-cadastrados');
      container.innerHTML = '<p class="text-xs text-stone-500">Carregando lista...</p>';

      const [r1, r2] = await Promise.all([db.rpc('agenda_listar_coordenadores'), db.rpc('listar_usuarios')]);
      if (r1.error || r2.error) {
        container.innerHTML = `<p class="text-xs text-red-700">Erro ao listar coordenadores: ${esc((r1.error || r2.error).message)}</p>`;
        return;
      }
      contasEquipe = r2.data || [];
      document.getElementById('novo-coord-conta').innerHTML = opcoesContas('');
      const data = r1.data || [];

      if (!data.length) {
        container.innerHTML = '<p class="text-xs text-stone-500">Nenhum coordenador cadastrado.</p>';
        return;
      }

      container.innerHTML = data.map(coord => {
        const badgeStatus = coord.ativo
          ? '<span class="px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-800 text-[10px] font-bold">Ativo</span>'
          : '<span class="px-2 py-0.5 rounded-full bg-stone-200 text-stone-600 text-[10px] font-bold">Inativo</span>';
        const vinculo = coord.usuario_id
          ? `<p class="text-xs text-stone-500">Conta: <strong>${esc(coord.usuario_email || '')}</strong></p>`
          : `<p class="text-xs text-amber-800">Login antigo: <strong>${esc(coord.login)}</strong> — ainda não ligado a uma conta (sem acesso até ser ligado)</p>
             <div class="flex flex-wrap items-center gap-1.5 mt-1.5">
               <select id="vinc-${esc(coord.id)}" class="px-2 py-1 rounded-lg border border-stone-300 bg-white text-[11px] max-w-[260px]">${opcoesContas('')}</select>
               <button onclick="vincularCoordenador('${esc(coord.id)}')" class="px-2.5 py-1 rounded-lg text-[11px] font-semibold bg-betel-vinho text-betel-dourado hover:bg-betel-vinhoEscuro">Ligar à conta</button>
             </div>`;
        return `
          <div class="flex flex-wrap items-center justify-between gap-2 p-3 rounded-xl border border-stone-200 bg-white">
            <div>
              <div class="flex items-center gap-2">
                <p class="font-bold text-xs sm:text-sm text-stone-900">${esc(coord.nome)}</p>
                ${badgeStatus}
                ${coord.eu ? '<span class="text-[10px] text-betel-vinho font-semibold">(Você)</span>' : ''}
              </div>
              ${vinculo}
            </div>
            ${coord.eu ? '' : `
              <div class="flex items-center gap-1.5">
                <button onclick="alternarStatusCoordenador('${esc(coord.id)}', ${!coord.ativo})"
                  class="px-2.5 py-1 rounded-lg text-[11px] font-semibold ${coord.ativo ? 'bg-amber-100 text-amber-900 hover:bg-amber-200' : 'bg-emerald-100 text-emerald-900 hover:bg-emerald-200'}">
                  ${coord.ativo ? 'Desativar' : 'Reativar'}
                </button>
              </div>
            `}
          </div>
        `;
      }).join('');
    }

    async function criarNovoCoordenador(e) {
      e.preventDefault();
      const conta = document.getElementById('novo-coord-conta').value;
      const btn = document.getElementById('btn-criar-coord');
      if (!conta) { alert('Escolha a conta da equipe que será coordenadora.'); return; }

      btn.disabled = true;
      btn.textContent = 'Salvando...';
      const { error } = await db.rpc('agenda_definir_coordenador', { p_usuario: conta });
      btn.disabled = false;
      btn.textContent = 'Tornar Coordenador';

      if (error) { alert('Não foi possível cadastrar: ' + error.message); return; }
      await carregarListaCoordenadores();
      const u = contasEquipe.find(x => x.id === conta);
      mostrarAviso(`${u ? u.nome : 'Conta'} agora é coordenador(a) da Agenda.`, 'sucesso');
    }

    async function vincularCoordenador(id) {
      const conta = document.getElementById('vinc-' + id).value;
      if (!conta) { alert('Escolha a conta da equipe desta pessoa.'); return; }
      const { error } = await db.rpc('agenda_vincular_coordenador', { p_coordenador: String(id), p_usuario: conta });
      if (error) { alert('Erro ao ligar à conta: ' + error.message); return; }
      await carregarListaCoordenadores();
      mostrarAviso('Coordenador ligado à conta da equipe.', 'sucesso');
    }

    async function alternarStatusCoordenador(id, novoAtivo) {
      const { error } = await db.rpc('agenda_status_coordenador', { p_coordenador: String(id), p_ativo: novoAtivo });
      if (error) {
        alert('Erro ao alterar status: ' + error.message);
        return;
      }
      await carregarListaCoordenadores();
    }
