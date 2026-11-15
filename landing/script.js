(() => {
  const root = document.documentElement;
  const themeButton = document.querySelector('.theme-toggle');
  const menuButton = document.querySelector('.menu-toggle');
  const mobileMenu = document.querySelector('#mobile-menu');
  const systemTheme = window.matchMedia('(prefers-color-scheme: dark)');

  const updateThemeLabel = () => {
    const isDark = root.dataset.theme === 'dark';
    const label = isDark ? 'Switch to light mode' : 'Switch to dark mode';
    themeButton.setAttribute('aria-label', label);
    themeButton.title = label;
    themeButton.setAttribute('aria-pressed', String(isDark));
    themeButton.querySelector('.theme-label').textContent = isDark ? 'Light mode' : 'Dark mode';
    document.querySelector('meta[name="theme-color"]').content = isDark ? '#101827' : '#f7f9fc';
  };

  const applyTheme = (preference) => {
    const effective = preference === 'system' ? (systemTheme.matches ? 'dark' : 'light') : preference;
    root.dataset.theme = effective;
    root.dataset.themePreference = preference;
    updateThemeLabel();
  };

  let themePreference = 'system';
  try { themePreference = localStorage.getItem('myedudrive-theme') || 'system'; } catch (_) { /* default to system preference */ }
  applyTheme(themePreference);
  themeButton.addEventListener('click', () => {
    themePreference = root.dataset.theme === 'dark' ? 'light' : 'dark';
    applyTheme(themePreference);
    try { localStorage.setItem('myedudrive-theme', themePreference); } catch (_) { /* theme still works for this visit */ }
  });
  systemTheme.addEventListener?.('change', () => {
    if (themePreference === 'system') applyTheme('system');
  });

  document.querySelectorAll('.login-link').forEach((link) => {
    link.addEventListener('click', (event) => {
      if (location.protocol !== 'file:') return;
      event.preventDefault();
      const address = window.prompt('Enter the Minikube address, for example http://192.168.49.2:30080');
      if (!address) return;
      try {
        const target = new URL(address.includes('://') ? address : `http://${address}`);
        target.pathname = '/login';
        target.search = '';
        target.hash = '';
        window.location.href = target.href;
      } catch (_) {
        window.alert('Please enter a valid Minikube URL, such as http://192.168.49.2:30080');
      }
    });
  });

  menuButton.addEventListener('click', () => {
    const expanded = menuButton.getAttribute('aria-expanded') === 'true';
    menuButton.setAttribute('aria-expanded', String(!expanded));
    menuButton.setAttribute('aria-label', expanded ? 'Open navigation menu' : 'Close navigation menu');
    mobileMenu.hidden = expanded;
  });
  mobileMenu.querySelectorAll('a').forEach((link) => link.addEventListener('click', () => {
    menuButton.setAttribute('aria-expanded', 'false');
    mobileMenu.hidden = true;
  }));
  document.querySelector('#year').textContent = new Date().getFullYear();
})();
