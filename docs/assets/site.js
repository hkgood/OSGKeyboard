/*!
 * OSGKeyboard website interactions.
 * The page remains useful without JavaScript; this file adds language, theme,
 * media, and the decorative Three.js hero enhancement.
 */
(function () {
  "use strict";

  const root = document.documentElement;
  const languageButton = document.getElementById("languageToggle");
  const themeButton = document.getElementById("themeToggle");
  const themeIcon = themeButton?.querySelector(".material-symbols-rounded");
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const themeMedia = window.matchMedia("(prefers-color-scheme: dark)");
  const supportedLanguages = new Set(["zh", "en"]);
  let beams = null;

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

    document.querySelectorAll("[data-shot]").forEach((image) => {
      const theme = root.dataset.theme || "light";
      image.src = `assets/screenshots/${lang}/${theme}/${image.dataset.shot}`;
    });

    document.querySelectorAll("[data-media-name]").forEach((media) => {
      const name = media.dataset.mediaName;
      const extension = media.dataset.mediaExtension || "mp4";
      media.src = `assets/whats-new/${name}-${lang}.${extension}`;
      media.load?.();
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

    document.querySelectorAll("[data-shot]").forEach((image) => {
      const lang = root.dataset.lang || "zh";
      image.src = `assets/screenshots/${lang}/${resolved}/${image.dataset.shot}`;
    });

    beams?.setBackground(resolved === "dark" ? "#020805" : "#020805");
    beams?.setLightColor(resolved === "dark" ? "#72F49D" : "#61E987");

    if (persist) localStorage.setItem("osg-site-theme", resolved);
  }

  function initializeBeams() {
    const canvas = document.getElementById("heroAuroraCanvas");
    if (!canvas || !window.OSGBeamsHero || !window.THREE) return;

    try {
      beams = window.OSGBeamsHero.create(canvas, {
        beamWidth: 4.5,
        beamHeight: 6,
        beamNumber: 26,
        lightColor: "#72F49D",
        speed: 4.5,
        noiseIntensity: 2.65,
        scale: 0.62,
        rotation: 208,
        background: "#020805",
        reduceMotion
      });
    } catch (error) {
      console.warn("OSGKeyboard hero enhancement unavailable.", error);
      canvas.hidden = true;
    }
  }

  function initializeVideos() {
    document.querySelectorAll("video[autoplay]").forEach((video) => {
      if (reduceMotion) {
        video.autoplay = false;
        video.pause();
        return;
      }

      const observer = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            video.play().catch(() => {});
          } else {
            video.pause();
          }
        });
      }, { threshold: 0.15 });
      observer.observe(video);
    });
  }

  const initialLanguage = preferredLanguage();
  const initialTheme = storedTheme() || (themeMedia.matches ? "dark" : "light");
  applyLanguage(initialLanguage, false);
  applyTheme(initialTheme, false);
  initializeBeams();
  initializeVideos();

  languageButton?.addEventListener("click", () => {
    applyLanguage(root.dataset.lang === "zh" ? "en" : "zh", true);
    applyTheme(root.dataset.theme, false);
  });

  themeButton?.addEventListener("click", () => {
    applyTheme(root.dataset.theme === "dark" ? "light" : "dark", true);
  });

  themeMedia.addEventListener("change", (event) => {
    if (!storedTheme()) applyTheme(event.matches ? "dark" : "light", false);
  });

  document.addEventListener("visibilitychange", () => {
    beams?.setVisible(!document.hidden);
  });
})();
