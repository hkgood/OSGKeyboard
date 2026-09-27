/*!
 * OSGKeyboard 主页交互。
 * 无 JavaScript 时页面内容完整可读；本文件负责：
 *   1. 中 / 英双语切换（data-zh / data-en 系列属性，含视频源）
 *   2. 深浅色主题（默认跟随系统，手动选择后持久化）
 *   3. 移动端导航开合
 *   4. 导航栏滚动状态、滚动显现动效、离屏视频暂停
 */
(function () {
  "use strict";

  const root = document.documentElement;
  const siteNav = document.getElementById("siteNav");
  const languageButton = document.getElementById("languageToggle");
  const themeButton = document.getElementById("themeToggle");
  const themeIconUse = document.getElementById("themeIconUse");
  const menuButton = document.getElementById("menuToggle");
  const menuIconUse = document.getElementById("menuIconUse");
  const mobileNav = document.getElementById("mobileNav");
  const themeColor = document.querySelector('meta[name="theme-color"]');
  const themeMedia = window.matchMedia("(prefers-color-scheme: dark)");
  const supportedLanguages = new Set(["zh", "en"]);

  /* ---------------- 语言 ---------------- */

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

    // 同时覆盖 <img> 与 <video>：切换语言后视频自动重新加载播放
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

    // 实机截图按 语言 + 主题 组合切换
    document.querySelectorAll("[data-shot]").forEach((image) => {
      const theme = root.dataset.theme || "light";
      image.src = `assets/screenshots/${lang}/${theme}/${image.dataset.shot}`;
    });

    document.title = lang === "zh"
      ? "OSGKeyboard — 开口即文字"
      : "OSGKeyboard — Say it. It’s typed.";

    if (languageButton) {
      languageButton.textContent = lang === "zh" ? "EN" : "中文";
      languageButton.setAttribute(
        "aria-label",
        lang === "zh" ? "切换到英文" : "Switch to Chinese"
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

  /* ---------------- 主题 ---------------- */

  function storedTheme() {
    const saved = localStorage.getItem("osg-site-theme");
    return saved === "light" || saved === "dark" ? saved : null;
  }

  function applyTheme(theme, persist) {
    const resolved = theme === "dark" ? "dark" : "light";
    root.dataset.theme = resolved;
    root.style.colorScheme = resolved;

    // 图标指向「点击后切换到的目标主题」
    if (themeIconUse) {
      themeIconUse.setAttribute("href", resolved === "dark" ? "#i-sun" : "#i-moon");
    }

    if (themeButton) {
      const lang = root.dataset.lang || "zh";
      const label = resolved === "dark"
        ? (lang === "zh" ? "切换到浅色模式" : "Switch to light mode")
        : (lang === "zh" ? "切换到深色模式" : "Switch to dark mode");
      themeButton.setAttribute("aria-label", label);
    }

    // 深色舞台在各主题下配色一致，theme-color 跟随舞台色
    themeColor?.setAttribute("content", "#0e1013");

    document.querySelectorAll("[data-shot]").forEach((image) => {
      const lang = root.dataset.lang || "zh";
      image.src = `assets/screenshots/${lang}/${resolved}/${image.dataset.shot}`;
    });

    if (persist) localStorage.setItem("osg-site-theme", resolved);
  }

  /* ---------------- 移动端导航 ---------------- */

  function setMenuOpen(isOpen) {
    if (!menuButton || !mobileNav) return;
    const open = Boolean(isOpen);
    menuButton.setAttribute("aria-expanded", String(open));
    mobileNav.hidden = !open;
    if (menuIconUse) menuIconUse.setAttribute("href", open ? "#i-close" : "#i-menu");
    const lang = root.dataset.lang || "zh";
    menuButton.setAttribute(
      "aria-label",
      lang === "zh"
        ? (open ? "关闭导航" : "打开导航")
        : (open ? "Close navigation" : "Open navigation")
    );
  }

  /* ---------------- 初始化 ---------------- */

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

  /* ---------------- 导航栏滚动状态 ---------------- */

  function updateNavState() {
    siteNav?.classList.toggle("is-scrolled", window.scrollY > 24);
  }
  updateNavState();
  window.addEventListener("scroll", updateNavState, { passive: true });

  /* ---------------- 滚动显现与离屏视频暂停 ---------------- */

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  if (reduceMotion || !("IntersectionObserver" in window)) {
    document.querySelectorAll(".reveal").forEach((element) => {
      element.classList.add("is-visible");
    });
  } else {
    const revealObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            revealObserver.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
    );
    document.querySelectorAll(".reveal").forEach((element) => {
      revealObserver.observe(element);
    });

    // 视频滚出视口时暂停，回来时恢复，省电且避免分散注意力
    const videoObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          const video = entry.target;
          if (entry.isIntersecting) {
            video.play().catch(() => {});
          } else {
            video.pause();
          }
        });
      },
      { threshold: 0.15 }
    );
    document.querySelectorAll("video[autoplay]").forEach((video) => {
      videoObserver.observe(video);
    });
  }
})();
