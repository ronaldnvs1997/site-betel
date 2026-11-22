// Mesma configuração que a Agenda original definia no navegador (tailwind.config)
module.exports = {
  content: ["../../site/agenda-ministerial/index.html", "./*.js", "./*.html"],
  theme: { extend: {
    colors: { betel: { vinho: '#582121', vinhoEscuro: '#3E1515', dourado: '#FFE1B2', douradoEscuro: '#D9A760', creme: '#FFFBF5' } },
    fontFamily: { sans: ['Montserrat', 'system-ui', 'sans-serif'], serif: ['Fraunces', 'Georgia', 'serif'] } } },
};
