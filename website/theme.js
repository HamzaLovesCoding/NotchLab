// Apply before styles load so a saved dark theme never flashes light on reload.
(() => {
  const key = 'notchlab-theme';
  const system = window.matchMedia('(prefers-color-scheme: dark)');
  const validTheme = (value) => value === 'dark' || value === 'light';
  let preference = null;
  let toggle;
  let transitionTimer;
  try {
    const saved = localStorage.getItem(key);
    if (validTheme(saved)) preference = saved;
  } catch {
    // Storage can be unavailable in private or restricted browsing.
  }

  function applyTheme() {
    const theme = preference || (system.matches ? 'dark' : 'light');
    document.documentElement.dataset.theme = theme;
    document.querySelector('meta[name="theme-color"]').content = theme === 'dark' ? '#151714' : '#f6f5f1';
    if (toggle) {
      toggle.setAttribute('aria-pressed', String(theme === 'dark'));
      toggle.title = `Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`;
    }
  }

  applyTheme();
  system.addEventListener('change', applyTheme);
  window.addEventListener('storage', (event) => {
    if (event.key !== key && event.key !== null) return;
    preference = validTheme(event.newValue) ? event.newValue : null;
    applyTheme();
  });
  document.addEventListener('DOMContentLoaded', () => {
    toggle = document.querySelector('.theme-toggle');
    toggle.hidden = false;
    applyTheme();
    toggle.addEventListener('click', () => {
      document.documentElement.classList.add('theme-transition');
      clearTimeout(transitionTimer);
      transitionTimer = setTimeout(() => document.documentElement.classList.remove('theme-transition'), 400);
      preference = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
      applyTheme();
      try {
        localStorage.setItem(key, preference);
      } catch {
        // The toggle still works for this visit when storage is blocked.
      }
    });
  });
})();
