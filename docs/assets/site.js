/*!
 * OSGKeyboard website interactions.
 * The page remains useful without JavaScript; this file adds language,
 * theme, and compact mobile navigation controls.
 */
(function () {
  "use strict";

  const root = document.documentElement;
  const languageButton = document.getElementById("languageToggle");
  const themeButton = document.getElementById("themeToggle");
  const themeIcon = themeButton?.querySelector(".material-symbols-rounded");
  const menuButton = document.getElementById("menuToggle");
  const menuIcon = menuButton?.querySelector(".material-symbols-rounded");
  const mobileNav = document.getElementById("mobileNav");
  const themeColor = document.querySelector('meta[name="theme-color"]');
  const themeMedia = window.matchMedia("(prefers-color-scheme: dark)");
  const supportedLanguages = new Set(["zh", "en"]);

  function preferredLanguage() {
    const query = new URLSearchParams(window.location.search).get("lang");
    if (supportedLanguages.has(query)) return query;
    const saved = localStorage.getItem("osg-site-language");
    if (supportedLanguages.has(saved)) return saved;
    return navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en";
  }

  function applyLanguage(language, persist) {
    const lang = supportedLanguages.has(language) ? language : "zh";
    root.lang = lang === "zh" ? "zh-Hans" : "en";
    root.dataset.lang = lang;

    document.querySelectorAll("[data-zh][data-en]").forEach((element) => {
      element.textContent = element.dataset[lang] || "";
    });

    document.querySelectorAll("[data-zh-html][data-en-html]").forEach((element) => {
      element.innerHTML = element.dataset[`${lang}Html`] || "";
    });

    document.querySelectorAll("[data-zh-alt][data-en-alt]").forEach((element) => {
      element.alt = element.dataset[`${lang}Alt`] || "";
    });

    document.querySelectorAll("[data-zh-src][data-en-src]").forEach((element) => {
      element.src = element.dataset[`${lang}Src`] || "";
    });

    document.querySelectorAll("[data-zh-href][data-en-href]").forEach((element) => {
      element.href = element.dataset[`${lang}Href`] || "";
    });

    document.querySelectorAll("[data-zh-label][data-en-label]").forEach((element) => {
      element.setAttribute("aria-label", element.dataset[`${lang}Label`] || "");
    });

    document.querySelectorAll("[data-zh-content][data-en-content]").forEach((element) => {
      element.setAttribute("content", element.dataset[`${lang}Content`] || "");
    });

    document.title = lang === "zh"
      ? "OSGKeyboard — 语音、打字与 AI 助手键盘"
      : "OSGKeyboard — Voice, typing, and an AI assistant keyboard";

    if (languageButton) {
      languageButton.textContent = lang === "zh" ? "EN" : "中文";
      languageButton.setAttribute(
        "aria-label",
        lang === "zh" ? "Switch to English" : "切换到中文"
      );
    }

    if (menuButton) {
      const isOpen = menuButton.getAttribute("aria-expanded") === "true";
      menuButton.setAttribute(
        "aria-label",
        lang === "zh"
          ? (isOpen ? "关闭导航" : "打开导航")
          : (isOpen ? "Close navigation" : "Open navigation")
      );
    }

    if (persist) {
      localStorage.setItem("osg-site-language", lang);
      const url = new URL(window.location.href);
      if (lang === "en") {
        url.searchParams.set("lang", "en");
      } else {
        url.searchParams.delete("lang");
      }
      history.replaceState({}, "", url);
    }
  }

  function storedTheme() {
    const saved = localStorage.getItem("osg-site-theme");
    return saved === "light" || saved === "dark" ? saved : null;
  }

  function setMenuOpen(isOpen) {
    if (!menuButton || !mobileNav) return;
    const open = Boolean(isOpen);
    menuButton.setAttribute("aria-expanded", String(open));
    mobileNav.hidden = !open;
    if (menuIcon) menuIcon.textContent = open ? "close" : "menu";
    const lang = root.dataset.lang || "zh";
    menuButton.setAttribute(
      "aria-label",
      lang === "zh"
        ? (open ? "关闭导航" : "打开导航")
        : (open ? "Close navigation" : "Open navigation")
    );
  }

  function applyTheme(theme, persist) {
    const resolved = theme === "dark" ? "dark" : "light";
    root.dataset.theme = resolved;
    root.style.colorScheme = resolved;

    if (themeIcon) {
      themeIcon.textContent = resolved === "dark" ? "light_mode" : "dark_mode";
    }

    if (themeButton) {
      const lang = root.dataset.lang || "zh";
      const label = resolved === "dark"
        ? (lang === "zh" ? "切换到浅色模式" : "Switch to light mode")
        : (lang === "zh" ? "切换到深色模式" : "Switch to dark mode");
      themeButton.setAttribute("aria-label", label);
    }

    themeColor?.setAttribute("content", resolved === "dark" ? "#0c0e0f" : "#eef2f6");

    if (persist) localStorage.setItem("osg-site-theme", resolved);
  }

  const initialLanguage = preferredLanguage();
  const initialTheme = storedTheme() || (themeMedia.matches ? "dark" : "light");
  applyLanguage(initialLanguage, false);
  applyTheme(initialTheme, false);

  languageButton?.addEventListener("click", () => {
    applyLanguage(root.dataset.lang === "zh" ? "en" : "zh", true);
    applyTheme(root.dataset.theme, false);
  });

  themeButton?.addEventListener("click", () => {
    applyTheme(root.dataset.theme === "dark" ? "light" : "dark", true);
  });

  menuButton?.addEventListener("click", () => {
    setMenuOpen(menuButton.getAttribute("aria-expanded") !== "true");
  });

  mobileNav?.querySelectorAll("a").forEach((link) => {
    link.addEventListener("click", () => setMenuOpen(false));
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") setMenuOpen(false);
  });

  themeMedia.addEventListener("change", (event) => {
    if (!storedTheme()) applyTheme(event.matches ? "dark" : "light", false);
  });
})();
