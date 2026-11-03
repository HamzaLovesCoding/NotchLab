const copyButton = document.querySelector('.copy-button');
const copyStatus = document.querySelector('.copy-status');
copyButton.addEventListener('click', async () => {
  const commands = document.querySelector('#install-commands');
  try {
    await navigator.clipboard.writeText(commands.textContent);
    copyStatus.textContent = 'Copied. Ready for Terminal.';
  } catch {
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(commands);
    selection.removeAllRanges();
    selection.addRange(range);
    copyStatus.textContent = 'Commands selected. Press ⌘C on your Mac to copy.';
  }
});

document.querySelector('a[href="#setup-note"]').addEventListener('click', () => {
  document.querySelector('#setup-note').open = true;
});

// Content stays visible without JavaScript; entrance effects only run as it arrives.
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
const entrances = new Set();
const reveal = new IntersectionObserver((entries) => {
  entries.forEach(({ target, isIntersecting }) => {
    if (!isIntersecting) return;
    reveal.unobserve(target);
    if (reducedMotion.matches) return;
    const animation = target.animate([
      { opacity: 0, transform: 'translateY(20px)' },
      { opacity: 1, transform: 'translateY(0)' },
    ], { duration: 650, easing: 'cubic-bezier(.22,1,.36,1)' });
    entrances.add(animation);
    animation.onfinish = animation.oncancel = () => entrances.delete(animation);
  });
}, { threshold: 0.08 });
document.querySelectorAll('.intro, .specs, .developer-copy, .dev-art, .section-heading, .feature-card, .alert-tile, .install-copy, .install-instructions, .faq').forEach((element) => reveal.observe(element));
reducedMotion.addEventListener('change', () => {
  if (reducedMotion.matches) entrances.forEach((animation) => animation.cancel());
});
