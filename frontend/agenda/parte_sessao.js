    // =========================================================================
    // CONFIGURAÇÃO DO SUPABASE (projeto central da Betel)
    // Mesma conta e mesma sessão da Área de Membros. As permissões são
    // conferidas no banco (RLS e gatilhos); a tela só reflete o que é permitido.
    // =========================================================================
    const CFG_BETEL = window.BETEL_SUPABASE || {};
    const db = window.supabase.createClient(CFG_BETEL.url, CFG_BETEL.anonKey, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false, storageKey: 'betel-equipe' }
    });

    // Estado da Aplicação
    let eventos = [];
    let reservas = [];
    const _d = new Date();
    let anoAtual = _d.getFullYear();
    let mesAtual = _d.getMonth(); // 0 = Janeiro, 1 = Fevereiro
    let modoCoordenador = false;
    let coordenadorAtual = null;
    let permissoes = null;        // resultado de agenda_minhas_permissoes()
    let eventoSelecionado = null;
    let reservaSelecionada = null;

    const NOMES_MESES = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];

    // ---------- utilidades de segurança e formatação ----------
    function esc(v) {
      return String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    }
    function urlSegura(u) {
      try { const x = new URL(String(u || '').trim()); return ['http:', 'https:'].includes(x.protocol) ? x.href : ''; } catch (_) { return ''; }
    }
    function hm(v) { return v ? String(v).slice(0, 5) : ''; } // colunas time devolvem HH:MM:SS
    function hojeLocalISO() {
      const d = new Date();
      return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    }
    function fimDoSemestre(dataISO) {
      const [a, m] = String(dataISO).split('-').map(Number);
      return m <= 6 ? `${a}-06-30` : `${a}-12-31`;
    }
    // Atualização/exclusão bloqueada pelo RLS não dá erro: volta sem linhas. Aqui vira erro claro.
    function semEfeito(r) {
      if (!r.error && Array.isArray(r.data) && r.data.length === 0) {
        return { ...r, error: { code: '42501', message: 'você não tem permissão para esta alteração (ou o registro não existe mais).' } };
      }
      return r;
    }
    // Erros vindos do banco: conflito de agenda (modal original) e permissão
    function tratarErroAgenda(error) {
      if (!error) return false;
      if (error.code === '23P01') {
        let lista = [];
        try { lista = JSON.parse(error.details || '[]'); } catch (_) {}
        if (lista.length) { abrirModalConflito(lista); return true; }
      }
      if (error.code === '42501' || error.code === 'PGRST301' || /permission denied|row-level security/i.test(error.message || '')) {
        mostrarAviso('Sem permissão: ' + (error.message && !/permission denied|row-level/i.test(error.message) ? error.message : 'entre com uma conta de coordenação ou do líder do ministério.'), 'erro');
        return true;
      }
      return false;
    }

    // ---------- permissões da conta logada ----------
    async function carregarPermissoes() {
      const { data: { session } } = await db.auth.getSession();
      if (!session) { permissoes = null; modoCoordenador = false; coordenadorAtual = null; return; }
      let { data, error } = await db.rpc('agenda_minhas_permissoes');
      // logo após o login a sessão pode levar um instante para valer em todas as chamadas: tenta mais uma vez
      if (error) { await new Promise(r => setTimeout(r, 500)); ({ data, error } = await db.rpc('agenda_minhas_permissoes')); }
      if (error) { permissoes = null; modoCoordenador = false; coordenadorAtual = null; mostrarAviso('Não foi possível conferir o seu acesso: ' + error.message, 'erro'); return; }
      permissoes = data;
      modoCoordenador = data.status === 'ok' && data.coordenador === true;
      coordenadorAtual = data.status === 'ok' ? { nome: data.nome } : null;
    }
    function podeEditarFicha(ev) {
      if (!permissoes || permissoes.status !== 'ok') return false;
      if (permissoes.coordenador) return true;
      return !!ev.ministerio_id && (permissoes.ministerios_lider || []).some(m => m.id === ev.ministerio_id);
    }

    async function carregarListaMinisterios() {
      const { data } = await db.from('ministerios').select('nome').order('ordem');
      document.getElementById('lista-ministerios').innerHTML = (data || []).map(m => `<option value="${esc(m.nome)}"></option>`).join('');
    }

    // Inicialização
    document.addEventListener('DOMContentLoaded', async () => {
      await Promise.all([carregarEventos(), carregarReservas(), carregarPermissoes(), carregarListaMinisterios()]);
      atualizarInterfaceCoordenador(false);

      const params = new URLSearchParams(window.location.search);
      const eventoIdParam = params.get('evento');
      if (eventoIdParam) {
        const encontrado = eventos.find(e => String(e.id) === String(eventoIdParam));
        if (encontrado) {
          const [ano, mes] = String(encontrado.data).split('-').map(Number);
          anoAtual = ano;
          mesAtual = mes - 1;
          renderizarCalendario();
          abrirPaginaEvento(encontrado.id);
          return;
        }
      }
      renderizarCalendario();
    });

    // Sessão encerrada em outra aba (ex.: "Sair" na Área de Membros)
    db.auth.onAuthStateChange(async (evento) => {
      if (evento === 'SIGNED_OUT' && permissoes) {
        await carregarPermissoes(); atualizarInterfaceCoordenador();
        const ev = eventoSelecionado; if (ev) abrirPaginaEvento(ev.id);
      }
    });
