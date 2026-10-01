/*!
 * OSGKeyboard 主页交互与动效引擎。
 * 无 JavaScript 时页面内容完整可读；本文件负责：
 *   1. 中 / 英双语切换（data-zh / data-en 系列属性，含视频源）
 *   2. 深浅色主题（默认跟随系统，手动选择后持久化；支持时以圆形扩散过渡）
 *   3. 移动端导航开合、导航滑块与当前区块高亮
 *   4. 逐字拆分标题（data-split）
 *   5. 滚动引擎：进度条、Hero 设备「立起」、媒体视差、三幕滚动叙事
 *   6. 声波渲染、Hero 语音胶囊打字机、数字计数
 *   7. 指针光斑 / 3D 倾斜 / 磁吸按钮、FAQ 高度过渡、离屏视频暂停
 * 开启「减弱动态效果」时，持续动画与指针动效全部停用，内容直接呈现最终态。
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

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const finePointer = window.matchMedia("(hover: hover) and (pointer: fine)").matches;
  const canObserve = "IntersectionObserver" in window;

  const TITLES = {
    zh: "OSGKeyboard｜AI 语音输入法 · 嘴替输入法 · iPhone / iPad / Mac",
    en: "OSGKeyboard — Agentic Keyboard & AI Voice Keyboard for iPhone and Mac"
  };

  const clamp = (value, min = 0, max = 1) => Math.min(max, Math.max(min, value));

  // 语言切换后需要重算的模块（胶囊文案、叙事文案、导航滑块）在此登记
  const languageHooks = [];

  /* ---------------- 逐字拆分 ---------------- */

  // 每个分组是一段不可断开的文字：英文按词，中文按「到下一个标点为止」的短句，
  // 与原标题的 word-break: keep-all 断行效果一致，标点也不会落到行首
  const CJK_PUNCTUATION = /[，。、！？：；）」』》…～]/;

  function groupCharacters(token) {
    const groups = [];
    let current = [];
    for (const character of token) {
      current.push(character);
      if (CJK_PUNCTUATION.test(character)) {
        groups.push(current);
        current = [];
      }
    }
    if (current.length) groups.push(current);
    return groups;
  }

  function splitText(element) {
    const text = element.textContent.trim();
    // 读屏读取完整句子，逐字拆分的视觉层对辅助技术隐藏
    const readable = document.createElement("span");
    readable.className = "sr-only";
    readable.textContent = text;
    const visual = document.createElement("span");
    visual.setAttribute("aria-hidden", "true");

    let index = 0;
    text.split(/(\s+)/).forEach((token) => {
      if (!token) return;
      if (/^\s+$/.test(token)) {
        visual.append(" ");
        return;
      }
      groupCharacters(token).forEach((group) => {
        const word = document.createElement("span");
        word.className = "w";
        group.forEach((character) => {
          const span = document.createElement("span");
          span.className = "ch";
          span.style.setProperty("--ci", String(index++));
          span.textContent = character;
          word.append(span);
        });
        visual.append(word);
      });
    });

    element.replaceChildren(readable, visual);
    element.classList.add("is-split");
  }

  function splitAll() {
    document.querySelectorAll("[data-split]").forEach(splitText);
  }

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
      const next = element.dataset[`${lang}Src`] || "";
      if (element.getAttribute("src") !== next) element.src = next;
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

    document.title = TITLES[lang];

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

    // 文字已被 data-zh / data-en 重写，需要重新拆分才能继续逐字动效
    splitAll();
    languageHooks.forEach((hook) => hook(lang));

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

  // 以主题按钮为圆心，新主题从一个点扩散覆盖整页（View Transitions API）
  function toggleThemeWithTransition() {
    const next = root.dataset.theme === "dark" ? "light" : "dark";
    if (!document.startViewTransition || reduceMotion || !themeButton) {
      applyTheme(next, true);
      return;
    }
    const rect = themeButton.getBoundingClientRect();
    const x = rect.left + rect.width / 2;
    const y = rect.top + rect.height / 2;
    const radius = Math.hypot(Math.max(x, innerWidth - x), Math.max(y, innerHeight - y));

    root.classList.add("vt-theme");
    const transition = document.startViewTransition(() => applyTheme(next, true));
    transition.ready
      .then(() => {
        root.animate(
          { clipPath: [`circle(0px at ${x}px ${y}px)`, `circle(${radius}px at ${x}px ${y}px)`] },
          {
            duration: 760,
            easing: "cubic-bezier(0.65, 0, 0.35, 1)",
            pseudoElement: "::view-transition-new(root)"
          }
        );
      })
      .catch(() => {});
    transition.finished.finally(() => root.classList.remove("vt-theme"));
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

  /* ---------------- 导航滑块与当前区块 ---------------- */

  const navHost = document.getElementById("navLinks");
  const navLinks = navHost ? Array.from(navHost.querySelectorAll("a")) : [];
  let activeNavLink = null;

  function moveIndicator(link) {
    if (!navHost) return;
    if (!link) {
      navHost.classList.remove("has-indicator");
      return;
    }
    navHost.style.setProperty("--ix", `${link.offsetLeft}px`);
    navHost.style.setProperty("--iw", `${link.offsetWidth}px`);
    navHost.classList.add("has-indicator");
  }

  function setActiveNav(link) {
    activeNavLink = link;
    navLinks.forEach((item) => item.classList.toggle("is-active", item === link));
    moveIndicator(link);
  }

  navLinks.forEach((link) => {
    link.addEventListener("mouseenter", () => moveIndicator(link));
    link.addEventListener("focus", () => moveIndicator(link));
  });
  navHost?.addEventListener("mouseleave", () => moveIndicator(activeNavLink));
  languageHooks.push(() => requestAnimationFrame(() => moveIndicator(activeNavLink)));

  if (canObserve && navLinks.length) {
    const sectionToLink = new Map();
    navLinks.forEach((link) => {
      const section = document.querySelector(link.getAttribute("href"));
      if (section) sectionToLink.set(section, link);
    });
    const visibleSections = new Set();
    const spy = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) visibleSections.add(entry.target);
          else visibleSections.delete(entry.target);
        });
        // 取文档顺序中最后一个处于判定带内的区块
        let current = null;
        sectionToLink.forEach((link, section) => {
          if (visibleSections.has(section)) current = link;
        });
        if (current !== activeNavLink) setActiveNav(current);
      },
      { rootMargin: "-45% 0px -50% 0px" }
    );
    sectionToLink.forEach((_, section) => spy.observe(section));
  }

  /* ---------------- 声波渲染 ---------------- */

  // 每个声波实例：bars 为条形元素，level 为目标音量，amp 为插值后的当前音量
  const waves = [];

  function createWave(container, options = {}) {
    const count = Number(container.dataset.wave) || 16;
    const bars = [];
    for (let i = 0; i < count; i += 1) {
      const bar = document.createElement("i");
      container.append(bar);
      bars.push(bar);
    }
    const wave = { bars, level: 0, amp: 0, active: true, mirror: Boolean(options.mirror), seed: Math.random() * 10 };
    waves.push(wave);
    return wave;
  }

  let waveFrame = 0;

  function renderWaves(now) {
    waveFrame = 0;
    let running = false;
    waves.forEach((wave) => {
      if (!wave.active) return;
      running = true;
      wave.amp += (wave.level - wave.amp) * 0.12;
      const length = wave.bars.length;
      wave.bars.forEach((bar, index) => {
        const i = wave.mirror ? length - 1 - index : index;
        // 两路正弦叠加出「语音包络」，中间条更高，两端收敛
        const envelope = Math.sin(((i + 0.5) / length) * Math.PI) * 0.6 + 0.4;
        const n1 = Math.sin(now * 0.009 + i * 0.85 + wave.seed) * 0.5 + 0.5;
        const n2 = Math.sin(now * 0.0047 + i * 1.9 + wave.seed * 2) * 0.5 + 0.5;
        const value = 0.1 + wave.amp * envelope * (0.25 + n1 * n2 * 0.95);
        bar.style.transform = `scaleY(${Math.min(1, value).toFixed(3)})`;
      });
    });
    if (running) waveFrame = requestAnimationFrame(renderWaves);
  }

  function wakeWaves() {
    if (!reduceMotion && !waveFrame) waveFrame = requestAnimationFrame(renderWaves);
  }

  /* ---------------- Hero 语音胶囊 ---------------- */

  const CAPSULE_SCRIPT = {
    zh: [
      { tag: "听写", text: "帮我订周五晚上七点的位子，四个人" },
      { tag: "嘴替 · 轻松", text: "这周有点累，先不去啦，下次我请！" },
      { tag: "替你做", text: "已建日程：周五 19:00 · 四人晚餐", agent: true }
    ],
    en: [
      { tag: "Dictate", text: "Book a table for four, Friday at seven" },
      { tag: "Your voice", text: "Bit wiped this week — rain check? Next one’s on me!" },
      { tag: "Done for you", text: "Event added: Fri 7:00 PM · Dinner for four", agent: true }
    ]
  };

  const hero = document.getElementById("top");
  const capsule = document.querySelector(".voice-capsule");
  const capsuleTag = capsule?.querySelector(".capsule-tag");
  const capsuleLine = capsule?.querySelector(".capsule-line");
  const capsuleWaveHost = capsule?.querySelector(".capsule-wave");
  const capsuleWave = capsuleWaveHost ? createWave(capsuleWaveHost) : null;
  let heroVisible = true;
  let capsuleRun = 0;

  const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  // Hero 离屏或标签页隐藏时暂停打字，回来后从原处继续
  async function whenActive(run) {
    while (run === capsuleRun && (!heroVisible || document.hidden)) {
      await wait(400);
    }
    return run === capsuleRun;
  }

  async function playCapsule() {
    if (!capsule || !capsuleLine || !capsuleTag) return;
    const run = ++capsuleRun;
    const lang = root.dataset.lang === "en" ? "en" : "zh";
    const script = CAPSULE_SCRIPT[lang];

    if (reduceMotion) {
      capsuleTag.textContent = script[0].tag;
      capsuleLine.textContent = script[0].text;
      return;
    }

    let index = 0;
    while (run === capsuleRun) {
      const item = script[index % script.length];
      capsuleTag.textContent = item.tag;
      capsuleTag.classList.toggle("is-agent", Boolean(item.agent));
      capsuleLine.textContent = "";
      await wait(260);

      // 听写与嘴替模拟「边说边出字」，Agentic 结果直接以完成态弹出
      const listening = !item.agent;
      capsule.classList.toggle("is-listening", listening);
      if (capsuleWave) capsuleWave.level = listening ? 1 : 0.15;
      wakeWaves();

      const characters = Array.from(item.text);
      const base = lang === "zh" ? 70 : 34;
      for (let i = 1; i <= characters.length; i += 1) {
        if (!(await whenActive(run))) return;
        capsuleLine.textContent = characters.slice(0, i).join("");
        await wait(item.agent ? 14 : base + Math.random() * base * 0.8);
      }

      capsule.classList.remove("is-listening");
      if (capsuleWave) capsuleWave.level = 0.12;
      await wait(item.agent ? 2400 : 1900);
      if (!(await whenActive(run))) return;

      // 快速回删，像是把这一句交给下一个能力
      for (let i = characters.length; i >= 0; i -= 2) {
        if (run !== capsuleRun) return;
        capsuleLine.textContent = characters.slice(0, i).join("");
        await wait(12);
      }
      index += 1;
    }
  }

  languageHooks.push(() => playCapsule());

  /* ---------------- 三幕滚动叙事 ---------------- */

  const STORY_TEXT = {
    zh: {
      draft: "可以啊 周五七点 位子我来订",
      tones: [
        "可以，周五七点，位子我来订。",
        "好的，周五晚七点见，座位由我来预订。",
        "好呀！周五七点不见不散，位子包在我身上～"
      ]
    },
    en: {
      draft: "sure friday at seven ill book a table",
      tones: [
        "Sure — Friday at seven. I’ll book a table.",
        "Sounds good. Friday at 7 p.m.; I’ll make the reservation.",
        "Yes! Friday at 7 — leave the table to me."
      ]
    }
  };

  // 进度阈值（0 → 1）：s1 好友来信 · s2 开始聆听 · s3 嘴替改写 · s4 发送
  //                     s5 好友回地址 · s6 复制 · s7 技能弹出 · s8 写入日历
  const STORY_STEPS = [0.03, 0.08, 0.31, 0.585, 0.66, 0.735, 0.805, 0.885];
  const TYPE_START = 0.08;
  const TYPE_END = 0.29;
  const TONE_STEPS = [0.36, 0.44, 0.515];
  const ACT_RANGES = [[0, 0.31], [0.31, 0.66], [0.66, 1]];

  const story = document.getElementById("storyStage");
  const storyText = document.getElementById("storyText");
  const storyActs = story ? Array.from(story.querySelectorAll(".story-act")) : [];
  const storyWaves = story
    ? Array.from(story.querySelectorAll(".kb-wave")).map((host, i) => createWave(host, { mirror: i === 0 }))
    : [];
  let storyLastText = null;
  let storyLastTone = -1;
  let storyLastAct = -1;

  function updateStory(force) {
    if (!story) return;
    const rect = story.getBoundingClientRect();
    const viewport = innerHeight;
    const inView = rect.bottom > 0 && rect.top < viewport;
    storyWaves.forEach((wave) => { wave.active = inView; });
    if (!inView && !force) return;

    const total = Math.max(1, story.offsetHeight - viewport);
    const p = clamp(-rect.top / total);
    const lang = root.dataset.lang === "en" ? "en" : "zh";
    const copy = STORY_TEXT[lang];

    const reached = STORY_STEPS.map((step) => p >= step);
    reached.forEach((on, i) => story.classList.toggle(`s${i + 1}`, on));
    const [, listening, rewriting, sent] = reached;

    // 语气：仅在「改写中」阶段可见，按进度依次切到 普通 → 正式 → 轻松
    let tone = -1;
    if (rewriting && !sent) {
      TONE_STEPS.forEach((step, i) => { if (p >= step) tone = i; });
    }
    if (tone !== storyLastTone) {
      [0, 1, 2].forEach((i) => story.classList.toggle(`tone-${i}`, i === tone));
    }

    // 输入框：聆听阶段按滚动进度逐字「听写」，改写阶段显示当前语气的版本
    let text = "";
    if (listening && !rewriting) {
      const characters = Array.from(copy.draft);
      const count = Math.round(clamp((p - TYPE_START) / (TYPE_END - TYPE_START)) * characters.length);
      text = characters.slice(0, count).join("");
    } else if (rewriting && !sent) {
      text = tone >= 0 ? copy.tones[tone] : copy.draft;
    }

    if (storyText && text !== storyLastText) {
      const isRewrite = tone !== storyLastTone && text && storyLastText;
      storyText.textContent = text;
      if (isRewrite && !reduceMotion) {
        storyText.classList.remove("is-swapping");
        void storyText.offsetWidth;
        storyText.classList.add("is-swapping");
      }
      storyLastText = text;
    }
    storyLastTone = tone;
    story.classList.toggle("has-text", text.length > 0);

    // 左侧三幕：高亮当前幕，幕内进度条随滚动填充
    let act = 0;
    ACT_RANGES.forEach(([start], i) => { if (p >= start) act = i; });
    if (act !== storyLastAct) {
      storyActs.forEach((element, i) => element.classList.toggle("is-active", i === act));
      storyLastAct = act;
    }
    storyActs.forEach((element, i) => {
      const [start, end] = ACT_RANGES[i];
      element.style.setProperty("--ap", clamp((p - start) / (end - start)).toFixed(3));
    });

    storyWaves.forEach((wave) => { wave.level = listening && !rewriting ? 1 : 0.06; });
    if (inView) wakeWaves();
  }

  if (story) {
    story.classList.add("is-live");
    languageHooks.push(() => {
      storyLastText = null;
      storyLastTone = -2;
      updateStory(true);
    });
  }

  /* ---------------- 滚动引擎 ---------------- */

  const progressBar = document.querySelector(".scroll-progress");
  const parallaxItems = new Set();
  let scrollTicking = false;
  let lastHeroProgress = -1;

  function updateNavState() {
    siteNav?.classList.toggle("is-scrolled", window.scrollY > 24);
  }

  function updateScroll() {
    scrollTicking = false;
    const y = window.scrollY;
    const viewport = innerHeight;

    updateNavState();

    if (progressBar) {
      const max = Math.max(1, root.scrollHeight - viewport);
      progressBar.style.transform = `scaleX(${clamp(y / max).toFixed(4)})`;
    }

    // Hero：滚动 0.75 屏内完成「文字淡出 + 设备立起」
    if (hero && !reduceMotion) {
      const heroProgress = clamp(y / (viewport * 0.75));
      if (Math.abs(heroProgress - lastHeroProgress) > 0.001) {
        hero.style.setProperty("--hp", heroProgress.toFixed(4));
        lastHeroProgress = heroProgress;
      }
    }

    // 视差：元素中心偏离视口中心越远，位移越大（方向相反，制造景深）
    if (!reduceMotion) {
      parallaxItems.forEach((element) => {
        const rect = element.getBoundingClientRect();
        const offset = rect.top + rect.height / 2 - viewport / 2;
        const factor = Number(element.dataset.parallax) || 0.05;
        element.style.transform = `translate3d(0, ${(-offset * factor).toFixed(1)}px, 0)`;
      });
    }

    updateStory(false);
  }

  function requestScrollUpdate() {
    if (!scrollTicking) {
      scrollTicking = true;
      requestAnimationFrame(updateScroll);
    }
  }

  /* ---------------- 数字计数 ---------------- */

  const numberFormat = new Intl.NumberFormat("en-US");

  function formatCount(element, value) {
    return `${element.dataset.prefix || ""}${numberFormat.format(value)}`;
  }

  function runCounter(element) {
    const target = Number(element.dataset.count);
    const from = element.dataset.from ? Number(element.dataset.from) : 0;
    const duration = 1700;
    const start = performance.now();
    function frame(now) {
      const t = clamp((now - start) / duration);
      const eased = 1 - Math.pow(1 - t, 4);
      element.textContent = formatCount(element, Math.round(from + (target - from) * eased));
      if (t < 1) requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
  }

  /* ---------------- 初始化 ---------------- */

  const initialLanguage = preferredLanguage();
  const initialTheme = storedTheme() || (themeMedia.matches ? "dark" : "light");
  applyLanguage(initialLanguage, false);
  applyTheme(initialTheme, false);

  languageButton?.addEventListener("click", () => {
    const next = root.dataset.lang === "zh" ? "en" : "zh";
    const swap = () => {
      applyLanguage(next, true);
      applyTheme(root.dataset.theme, false);
    };
    // 支持时以交叉淡化切换语言，整页文字不会「跳」
    if (document.startViewTransition && !reduceMotion) {
      document.startViewTransition(swap);
    } else {
      swap();
    }
  });

  themeButton?.addEventListener("click", toggleThemeWithTransition);

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

  window.addEventListener("scroll", requestScrollUpdate, { passive: true });
  window.addEventListener("resize", () => {
    requestScrollUpdate();
    moveIndicator(activeNavLink);
  });
  updateScroll();

  /* ---------------- 滚动显现、计数与离屏视频暂停 ---------------- */

  const counters = Array.from(document.querySelectorAll("[data-count]"));

  if (reduceMotion || !canObserve) {
    document.querySelectorAll(".reveal").forEach((element) => {
      element.classList.add("is-visible");
    });
  } else {
    // 首屏以下的计数器先归位到起点，进入视口时再滚动到目标值
    counters.forEach((element) => {
      if (element.getBoundingClientRect().top > innerHeight) {
        const from = element.dataset.from ? Number(element.dataset.from) : 0;
        element.textContent = formatCount(element, from);
        element.dataset.pending = "true";
      }
    });

    const revealObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-visible");
          entry.target.querySelectorAll("[data-pending]").forEach((counter) => {
            delete counter.dataset.pending;
            runCounter(counter);
          });
          revealObserver.unobserve(entry.target);
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
    );
    document.querySelectorAll(".reveal").forEach((element) => {
      revealObserver.observe(element);
    });

    // 视差只计算视口附近的元素
    const parallaxObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) parallaxItems.add(entry.target);
          else parallaxItems.delete(entry.target);
        });
        requestScrollUpdate();
      },
      { rootMargin: "20% 0px 20% 0px" }
    );
    document.querySelectorAll("[data-parallax]").forEach((element) => {
      parallaxObserver.observe(element);
    });

    if (hero) {
      new IntersectionObserver((entries) => {
        heroVisible = entries[0].isIntersecting;
        if (capsuleWave) capsuleWave.active = heroVisible;
        if (heroVisible) wakeWaves();
      }).observe(hero);
    }
  }

  if (canObserve) {
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

  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) wakeWaves();
  });

  /* ---------------- 指针动效：光斑 / 倾斜 / 磁吸 / Hero 光斑 ---------------- */

  if (finePointer && !reduceMotion) {
    document.querySelectorAll(".spot").forEach((element) => {
      element.addEventListener("pointermove", (event) => {
        const rect = element.getBoundingClientRect();
        element.style.setProperty("--mx", `${event.clientX - rect.left}px`);
        element.style.setProperty("--my", `${event.clientY - rect.top}px`);
      });
    });

    document.querySelectorAll(".tilt").forEach((element) => {
      element.addEventListener("pointermove", (event) => {
        const rect = element.getBoundingClientRect();
        const x = (event.clientX - rect.left) / rect.width;
        const y = (event.clientY - rect.top) / rect.height;
        element.style.setProperty("--rx", `${((0.5 - y) * 9).toFixed(2)}deg`);
        element.style.setProperty("--ry", `${((x - 0.5) * 11).toFixed(2)}deg`);
      });
      element.addEventListener("pointerleave", () => {
        element.style.setProperty("--rx", "0deg");
        element.style.setProperty("--ry", "0deg");
      });
    });

    // 磁吸按钮：指针靠近时按钮被「吸」向指针，离开时弹簧回位
    document.querySelectorAll(".magnetic").forEach((element) => {
      element.addEventListener("pointermove", (event) => {
        const rect = element.getBoundingClientRect();
        const dx = (event.clientX - rect.left - rect.width / 2) * 0.22;
        const dy = (event.clientY - rect.top - rect.height / 2) * 0.32;
        element.style.transform = `translate(${dx.toFixed(1)}px, ${dy.toFixed(1)}px)`;
      });
      element.addEventListener("pointerleave", () => {
        element.style.transform = "";
      });
    });

    // Hero 光斑以插值追随指针，产生柔和的拖尾
    if (hero) {
      let targetX = 50;
      let targetY = 30;
      let currentX = 50;
      let currentY = 30;
      let spotFrame = 0;
      const step = () => {
        currentX += (targetX - currentX) * 0.08;
        currentY += (targetY - currentY) * 0.08;
        hero.style.setProperty("--hx", `${currentX.toFixed(2)}%`);
        hero.style.setProperty("--hy", `${currentY.toFixed(2)}%`);
        const settled = Math.abs(targetX - currentX) < 0.05 && Math.abs(targetY - currentY) < 0.05;
        spotFrame = settled ? 0 : requestAnimationFrame(step);
      };
      hero.addEventListener("pointermove", (event) => {
        const rect = hero.getBoundingClientRect();
        targetX = ((event.clientX - rect.left) / rect.width) * 100;
        targetY = ((event.clientY - rect.top) / rect.height) * 100;
        if (!spotFrame) spotFrame = requestAnimationFrame(step);
      });
    }
  }

  /* ---------------- FAQ 展开高度过渡 ---------------- */

  document.querySelectorAll(".faq-item").forEach((details) => {
    const summary = details.querySelector("summary");
    if (!summary || reduceMotion || !details.animate) return;
    let animation = null;
    let closing = false;

    summary.addEventListener("click", (event) => {
      event.preventDefault();
      const startHeight = details.offsetHeight;
      const borders = details.offsetHeight - details.clientHeight;

      if (animation) {
        animation.cancel();
        animation = null;
      }

      closing = details.open && !closing;
      if (!closing) details.open = true;
      const endHeight = closing ? summary.offsetHeight + borders : details.offsetHeight;

      animation = details.animate(
        { height: [`${startHeight}px`, `${endHeight}px`] },
        { duration: 460, easing: "cubic-bezier(0.16, 1, 0.3, 1)" }
      );
      animation.onfinish = () => {
        animation = null;
        if (closing) details.open = false;
        closing = false;
      };
    });
  });
})();
