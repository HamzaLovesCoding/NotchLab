const palettes = document.querySelectorAll('[data-palette]');
palettes.forEach((button) => button.addEventListener('click', () => {
  document.documentElement.dataset.palette = button.dataset.palette;
  palettes.forEach((item) => item.setAttribute('aria-pressed', String(item === button)));
}));

const party = document.querySelector('.party-button');
let celebrating = false;
party.addEventListener('click', () => {
  if (celebrating || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  celebrating = true;
  const { x, y, width, height } = party.getBoundingClientRect();
  const colors = ['#ffe76c', '#7543db', '#ffc2d9', '#d9ef9c', '#ff7e57'];
  for (let i = 0; i < 28; i += 1) {
    const piece = document.createElement('i');
    piece.className = 'confetti-piece';
    piece.setAttribute('aria-hidden', 'true');
    piece.style.cssText = `left:${x + width / 2}px;top:${y + height / 2}px;background:${colors[i % colors.length]}`;
    document.body.append(piece);
    const animation = piece.animate([
      { transform: 'translate(0,0) rotate(0deg)', opacity: 1 },
      { transform: `translate(${(Math.random() - .5) * 360}px,${-80 - Math.random() * 100}px) rotate(180deg)`, opacity: 1, offset: .45 },
      { transform: `translate(${(Math.random() - .5) * 480}px,180px) rotate(400deg)`, opacity: 0 },
    ], { duration: 1100 + Math.random() * 400, easing: 'ease-out' });
    animation.onfinish = () => piece.remove();
  }
  setTimeout(() => { celebrating = false; }, 1500);
});
