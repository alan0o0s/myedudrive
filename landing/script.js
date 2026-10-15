(() => {
  const root = document.documentElement;
  const langButton = document.querySelector('.language-toggle');
  const themeButton = document.querySelector('.theme-toggle');
  const menuButton = document.querySelector('.menu-toggle');
  const mobileMenu = document.querySelector('#mobile-menu');
  const systemTheme = window.matchMedia('(prefers-color-scheme: dark)');

  const updateThemeLabel = () => {
    const isDark = root.dataset.theme === 'dark';
    const lang = root.lang;
    const label = isDark
      ? (lang === 'ar' ? 'التبديل للوضع الفاتح' : 'Switch to light mode')
      : (lang === 'ar' ? 'التبديل للوضع الداكن' : 'Switch to dark mode');
    themeButton.setAttribute('aria-label', label);
    themeButton.title = label;
    themeButton.setAttribute('aria-pressed', String(isDark));
    themeButton.querySelector('.theme-label').textContent = isDark
      ? (lang === 'ar' ? 'الوضع الفاتح' : 'Light mode')
      : (lang === 'ar' ? 'الوضع الداكن' : 'Dark mode');
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

  const setLanguage = (lang) => {
    root.lang = lang;
    root.dir = lang === 'ar' ? 'rtl' : 'ltr';
    document.querySelectorAll('[data-en][data-ar]').forEach((el) => {
      el.innerHTML = el.dataset[lang];
    });
    langButton.textContent = lang === 'ar' ? 'English' : 'عربي';
    langButton.setAttribute('aria-label', lang === 'ar' ? 'Switch to English' : 'التبديل إلى العربية');
    updateThemeLabel();
    document.title = lang === 'ar' ? 'MyEduDrive — تعلّمك في مكان واحد' : 'MyEduDrive — Your learning, in one place';
    try { localStorage.setItem('myedudrive-language', lang); } catch (_) { /* local preview can restrict storage */ }
  };

  let language = 'en';
  try { language = localStorage.getItem('myedudrive-language') || 'en'; } catch (_) { /* default to English */ }
  setLanguage(language);
  langButton.addEventListener('click', () => setLanguage(root.lang === 'en' ? 'ar' : 'en'));

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
