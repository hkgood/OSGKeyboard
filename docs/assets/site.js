/*!
 * OSGKeyboard 主页交互与动效引擎。
 * 无 JavaScript 时页面内容完整可读；本文件负责：
 *   1. 中 / 英双语切换（data-zh / data-en 系列属性，含视频源）
 *   2. 深浅色主题（默认跟随系统，手动选择后持久化；支持时以圆形扩散过渡）
 *   3. 移动端导航开合、导航滑块与当前区块高亮
 *   4. 逐字拆分标题（data-split）
 *   5. 滚动引擎：进度条、Hero 设备「立起」、媒体视差、四幕滚动叙事（真机录屏随幕切换）
 *   6. 声波渲染、Hero 语音胶囊打字机、数字计数
 *   7. 亚克力反光 / 磁吸按钮、FAQ 高度过渡、离屏视频暂停
 * 开启「减弱动态效果」时，持续动画与指针动效全部停用，内容直接呈现最终态。
 */
(function () {
  "use strict";

  const root = document.documentElement;
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

  // 语言切换后需要重算的模块（胶囊文案、真机录屏、导航滑块）在此登记
  const languageHooks = [];
  // 主题切换后需要换源的模块（真机录屏按深浅色各录一份）在此登记
  const themeHooks = [];

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

    // 浏览器顶栏颜色与底板一致（与 site.css 的 --canvas 保持同步）
    themeColor?.setAttribute("content", resolved === "dark" ? "#0e1011" : "#eff1f0");

    document.querySelectorAll("[data-shot]").forEach((image) => {
      const lang = root.dataset.lang || "zh";
      image.src = `assets/screenshots/${lang}/${resolved}/${image.dataset.shot}`;
    });

    themeHooks.forEach((hook) => hook(resolved));

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

  // 复刻键盘真实的麦克风状态流：轻点听写（红色声波 → 打勾）、长按问 AI（青色声波 → 转圈 → 回答）、
  // 复制消息后的嘴替回复（转圈 → 回复）。文案取自 App 的实际界面字符串与演示素材。
  const CAPSULE_SCRIPT = {
    zh: [
      { tag: "轻点听写", mode: "rec", text: "帮我订周五晚上七点的位子，四个人" },
      { tag: "长按问 AI", mode: "ai", text: "周末去哪儿玩比较合适？", busy: "AI 正在思考…", answer: "可以去近郊走走：上午逛古镇，下午找家咖啡馆。" },
      { tag: "复制 · 嘴替回复", busy: "AI 正在思考…", answer: "好的，我整理一下预算版，明天上午发你。" }
    ],
    en: [
      { tag: "Tap to dictate", mode: "rec", text: "Book a table for four, Friday at seven" },
      { tag: "Hold to ask AI", mode: "ai", text: "Where should we go this weekend?", busy: "AI is thinking…", answer: "Try a day trip: an old town in the morning, a café in the afternoon." },
      { tag: "Copy · Reply in your voice", busy: "AI is thinking…", answer: "Sure, I’ll put the budget version together and send it over tomorrow morning." }
    ]
  };

  const CAPSULE_STATES = ["is-rec", "is-ai", "is-busy", "is-ai-busy", "is-done"];

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

  function setCapsuleState(...states) {
    CAPSULE_STATES.forEach((name) => capsule.classList.toggle(name, states.includes(name)));
    const listening = states.includes("is-rec") || states.includes("is-ai");
    if (capsuleWave) capsuleWave.level = listening ? 1 : 0;
    if (listening) wakeWaves();
  }

  // 逐字写入；返回 false 表示本轮已被新一轮（如切换语言）取代
  async function typeLine(run, text, perChar) {
    const characters = Array.from(text);
    for (let i = 1; i <= characters.length; i += 1) {
      if (!(await whenActive(run))) return false;
      capsuleLine.textContent = characters.slice(0, i).join("");
      await wait(perChar());
    }
    return true;
  }

  async function playCapsule() {
    if (!capsule || !capsuleLine || !capsuleTag) return;
    const run = ++capsuleRun;
    const lang = root.dataset.lang === "en" ? "en" : "zh";
    const script = CAPSULE_SCRIPT[lang];

    if (reduceMotion) {
      setCapsuleState();
      capsuleTag.textContent = script[0].tag;
      capsuleLine.textContent = script[0].text;
      return;
    }

    const base = lang === "zh" ? 72 : 34;
    const speech = () => base + Math.random() * base * 0.8;
    let index = 0;
    while (run === capsuleRun) {
      const item = script[index % script.length];
      setCapsuleState();
      capsuleTag.textContent = item.tag;
      capsuleLine.textContent = "";
      await wait(650);

      // 1. 说话：红色（听写）或青色（问 AI）胶囊 + 声波，边说边出字
      if (item.text) {
        setCapsuleState(item.mode === "ai" ? "is-ai" : "is-rec");
        if (!(await typeLine(run, item.text, speech))) return;
        await wait(420);
      }

      // 2. 处理中：胶囊转圈，显示真实界面的状态文案
      if (item.busy) {
        setCapsuleState("is-busy", item.mode === "ai" ? "is-ai-busy" : "");
        capsuleLine.textContent = item.busy;
        await wait(1300);
        if (!(await whenActive(run))) return;
      }

      // 3. 结果：回答快速流出
      if (item.answer) {
        capsuleLine.textContent = "";
        if (!(await typeLine(run, item.answer, () => 16))) return;
      }

      // 4. 插入成功：胶囊打勾
      setCapsuleState("is-done");
      await wait(2100);
      if (!(await whenActive(run))) return;

      // 快速回删，交给下一个能力
      const characters = Array.from(capsuleLine.textContent);
      for (let i = characters.length; i >= 0; i -= 2) {
        if (run !== capsuleRun) return;
        capsuleLine.textContent = characters.slice(0, i).join("");
        await wait(12);
      }
      index += 1;
    }
  }

  languageHooks.push(() => playCapsule());

  /* ---------------- 真机录屏：Apple 机框 + 真实键盘扩展的片段 ---------------- */

  // 片段按「幕-语言-主题」命名，每组都录自模拟器里真实的 OSGKeyboard 扩展
  function clipPath(video, suffix) {
    const lang = root.dataset.lang === "en" ? "en" : "zh";
    const theme = root.dataset.theme === "dark" ? "dark" : "light";
    return `assets/story/${video.dataset.clip}-${lang}-${theme}${suffix}`;
  }

  const clipVideos = Array.from(document.querySelectorAll(".iphone-clip"));

  function playClip(video, restart) {
    if (reduceMotion) return;
    if (restart && video.readyState >= 1) video.currentTime = 0;
    video.dataset.playing = "1";
    video.play().catch(() => {});
  }

  function pauseClip(video) {
    video.dataset.playing = "0";
    video.pause();
  }

  function refreshClipSources() {
    clipVideos.forEach((video) => {
      // 减弱动态效果：不加载视频，只显示最能说明这一幕的关键帧海报
      if (reduceMotion) {
        video.poster = clipPath(video, "-key.jpg");
        return;
      }
      const src = clipPath(video, ".mp4");
      if (video.getAttribute("src") === src) return;
      const resume = video.dataset.playing === "1";
      video.poster = clipPath(video, ".jpg");
      video.src = src;
      if (resume) playClip(video, false);
    });
  }

  // 初始化时语言与主题会先后写入，合并成一次换源，避免同一片段加载两遍
  let clipRefreshQueued = false;
  function queueClipRefresh() {
    if (clipRefreshQueued) return;
    clipRefreshQueued = true;
    queueMicrotask(() => {
      clipRefreshQueued = false;
      refreshClipSources();
    });
  }

  languageHooks.push(queueClipRefresh);
  themeHooks.push(queueClipRefresh);

  /* ---------------- 四幕滚动叙事 ---------------- */

  // 滚动只决定「当前是哪一幕」；画面是这一幕的真机片段，从头播放，播完停留片刻再重播
  const STORY_REPLAY_DELAY = 2200;

  const story = document.getElementById("storyStage");
  const storyActs = story ? Array.from(story.querySelectorAll(".story-act")) : [];
  const storyClips = story ? Array.from(story.querySelectorAll(".iphone-clip")) : [];
  let storyAct = -1;
  let storyInView = false;
  let storyReplayTimer = 0;

  function setStoryAct(act) {
    storyAct = act;
    clearTimeout(storyReplayTimer);
    storyActs.forEach((element, i) => {
      element.classList.toggle("is-active", i === act);
      // 演完的幕进度条保持满格，还没到的幕清空；当前幕由片段播放进度驱动
      if (i !== act || reduceMotion) element.style.setProperty("--ap", i <= act ? "1" : "0");
    });
    storyClips.forEach((video, i) => {
      video.classList.toggle("is-on", i === act);
      if (i === act && storyInView) playClip(video, true);
      else pauseClip(video);
    });
  }

  function updateStory() {
    if (!story) return;
    const rect = story.getBoundingClientRect();
    const viewport = innerHeight;
    const inView = rect.bottom > 0 && rect.top < viewport;
    const p = clamp(-rect.top / Math.max(1, story.offsetHeight - viewport));

    // 滚动距离按幕数均分
    const act = Math.min(storyActs.length - 1, Math.floor(p * storyActs.length));

    // 离开视口暂停，回来接着播
    if (inView !== storyInView) {
      storyInView = inView;
      const current = storyClips[storyAct];
      if (current) {
        if (inView) playClip(current, false);
        else pauseClip(current);
      }
    }
    if (act !== storyAct) setStoryAct(act);
  }

  storyClips.forEach((video, i) => {
    video.addEventListener("timeupdate", () => {
      if (i !== storyAct || !video.duration || reduceMotion) return;
      storyActs[i]?.style.setProperty("--ap", (video.currentTime / video.duration).toFixed(3));
    });
    video.addEventListener("ended", () => {
      storyActs[i]?.style.setProperty("--ap", "1");
      clearTimeout(storyReplayTimer);
      storyReplayTimer = setTimeout(() => {
        if (i === storyAct && storyInView) playClip(video, true);
      }, STORY_REPLAY_DELAY);
    });
  });

  /* ---------------- 技能区、打字区：进入视口时循环播放真机片段 ---------------- */

  const loopClips = clipVideos.filter((video) => !story || !story.contains(video));
  if (!reduceMotion && loopClips.length && "IntersectionObserver" in window) {
    const clipObserver = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) playClip(entry.target, false);
        else pauseClip(entry.target);
      });
    }, { threshold: 0.35 });
    loopClips.forEach((video) => clipObserver.observe(video));
  }

  /* ---------------- 滚动引擎 ---------------- */

  const progressBar = document.querySelector(".scroll-progress");
  const parallaxItems = new Set();
  let scrollTicking = false;
  let lastHeroProgress = -1;

  function updateScroll() {
    scrollTicking = false;
    const y = window.scrollY;
    const viewport = innerHeight;

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

  /* ---------------- 指针动效：亚克力反光 / 磁吸 / Hero 光斑 ---------------- */

  if (finePointer && !reduceMotion) {
    // 亚克力反光：高光跟随指针在面板表面移动
    document.querySelectorAll(".spot").forEach((element) => {
      element.addEventListener("pointermove", (event) => {
        const rect = element.getBoundingClientRect();
        element.style.setProperty("--mx", `${event.clientX - rect.left}px`);
        element.style.setProperty("--my", `${event.clientY - rect.top}px`);
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
