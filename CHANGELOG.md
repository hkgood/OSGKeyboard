# Changelog

All notable changes to OSGKeyboard will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Landing competitor matrix**: compare Typeless / Superwhisper / Openless / OSGKeyboard on open source, pricing, on-device ASR, BYOK, and platforms (incl. honest Windows gap). / **落地页竞品对照**：对比 Typeless / Superwhisper / Openless / OSGKeyboard 的开源、付费、本地识别、BYOK 与平台（含暂无 Windows）。
- **Voluntary support tip**: Settings (top of the page) includes an optional ¥28 Consumable in-app tip (StoreKit 2). All features stay free — no paywall or unlock. / **自愿打赏**：设置页顶部新增可选 ¥28 消耗型应用内打赏（StoreKit 2）。全功能仍免费，无付费墙或功能解锁。
- **iOS appearance preference**: Settings → Preferences adds System / Light / Dark (iPhone + iPad), matching the Mac control. / **iOS 外观偏好**：设置 → 偏好设置新增跟随系统 / 浅色 / 深色（iPhone 与 iPad），与 Mac 一致。
- **DEBUG demo seed URL**: `osgkeyboard://seed-demo` fills Home stats, History, and Dictionary with placeholder data and turns iCloud sync off (script: `scripts/seed_demo_data.py`). / **DEBUG 演示数据**：`osgkeyboard://seed-demo` 填充首页统计、历史与词库占位数据并关闭 iCloud 同步（脚本：`scripts/seed_demo_data.py`）。

### Changed
- **Landing section copy**: interactive pill-tab differentiator explorer (elevated detail stage; BYOK absorbed) plus competitor matrix and section bands; titles →「开源，尽是不同」/「开箱可用，只要三步」。 / **落地页文案**：差异区改为胶囊 Tab + 抬升详情台（BYOK 并入）；含竞品对照与分区底色带；标题含「开源，尽是不同」「开箱可用，只要三步」。
- **Unified welcome slogan**: iPad Home now reuses the iOS onboarding brand line, and macOS onboarding shows the same “Speak it. It’s typed.” welcome slogan. / **统一欢迎口号**：iPad 首页复用 iOS 引导页品牌句，macOS 引导页也显示同一句「开口即文字。」欢迎口号。
- **GitHub Pages landing**: redesign as a commercial product page with zh/en, light/dark, brand mark, scroll motion, and App Store screenshots; emphasizes free, cross-platform, open source, privacy, and BYOK. / **GitHub Pages 落地页**：改版为商业产品页，支持中英与日夜模式、品牌标、滚动动效与 App Store 截图；突出免费、跨端、开源、隐私与 BYOK。
- **Landing hero device family**: Mac + iPad + iPhone nested in one mockup cluster (no outer card stroke); screens swap with language/theme. / **落地页 Hero 设备组**：Mac、iPad、iPhone 叠放在同一组设备框内（无外卡片描边）；截图随语言/主题切换。
- **Landing hero polish**: replace CSS device frames with the marketing composite; full-bleed pale-green hero wash (no side gaps / no radial gradient); Mac story shots sit on transparent chrome. / **落地页 Hero 抛光**：设备框改为营销合成图；首屏淡绿单色通栏（无两侧留白 / 无径向渐变）；Mac 故事截图去卡片底。

### Fixed
- **iPad sidebar brand mark**: use the template `OSGLogoWide` mark with accent tint so the logo stays visible in the split-view sidebar. / **iPad 侧栏品牌标**：改用可着色的 `OSGLogoWide`，保证分栏侧栏始终显示 logo。

## [0.5.3] - 2026-07-11

### Added
- **Shared 7-day usage chart on iOS Home**: iPhone and iPad Home now show the same trailing-7-day dictation chart as macOS, via a shared `UsageStatsCluster`. / **iOS 首页共享近 7 天统计图**：iPhone / iPad 首页与 macOS 共用 `UsageStatsCluster`，展示近 7 天听写字数柱状图。
- **macOS dictation overlay**: a bottom-centered floating pill appears for any recording path (global hotkey, menu bar, or main window) — shows listening / transcribing state, a stronger live waveform, a one-line live transcript preview (partials when chunked ASR runs), front-app name, and a stop control, then briefly confirms success before fading out without stealing focus. / **macOS 听写浮层**：任意录音路径（全局热键、菜单栏或主窗口）都会在屏幕底部居中出现胶囊浮层——显示聆听 / 识别状态、更强的实时波形、单行转写预览（分块识别时显示 partial）、前台应用名与停止按钮，成功后短暂确认再淡出，且不抢前台焦点。
- **macOS Option-key picker**: Settings → Input lets you choose Left / Right / Either Option as the hold-to-talk key, so the shortcut can avoid conflicts with other apps. / **macOS Option 键选择**：设置 → 输入与快捷键可选择左 / 右 / 任一 Option 作为按住听写键，避免与其他应用冲突。

### Changed
- **Shared home stats UI**: 7-day chart, stat tiles, and surface chrome live in `OSGKeyboardShared` (`UsageStatsCluster` / `UsageStatCard` / `SevenDayUsageChart`); Mac Dashboard and iOS Home (phone stacked / iPad split) both consume them. Localization keys moved from `mac.stat.*` to `stat.*`. / **共享首页统计 UI**：近 7 天图表、统计卡与表面壳迁入 `OSGKeyboardShared`（`UsageStatsCluster` / `UsageStatCard` / `SevenDayUsageChart`）；Mac Dashboard 与 iOS 首页（手机上下叠 / iPad 左右分栏）共用。文案 key 由 `mac.stat.*` 改为 `stat.*`。
- **Removed temporary Flow DEBUG panels**: the on-screen App Group / session debug text boxes on Home and the keyboard extension are gone now that the orange-mic investigation is closed. / **移除临时 Flow DEBUG 面板**：橙色麦克风排查结束后，首页与键盘扩展上的 App Group / 会话调试文本框已去掉。
- **macOS local ASR catalog**: removed offline Paraformer; SenseVoice / Qwen3 0.6B / Qwen3 1.7B now show Fastest / Most balanced / Best quality badges (users still on Paraformer migrate to Qwen3 0.6B). / **macOS 本地 ASR 目录**：移除 offline Paraformer；SenseVoice / Qwen3 0.6B / Qwen3 1.7B 分别标注速度最快 / 最平衡 / 质量最好（仍选 Paraformer 的用户迁移到 Qwen3 0.6B）。
- **macOS visual system**: full-app redesign around the brand line “Speak it. It’s typed.” / 「开口即文字。」— grouped sidebar, restrained accent selection, asymmetric Home stats (chars as hero), unified page headers, quieter status footer, and clearer dark-mode card elevation. / **macOS 视觉体系**：围绕品牌句「开口即文字。」/ “Speak it. It’s typed.” 做全 App 设计升级——侧栏分组、克制的选中态、首页不对称统计（字数主卡）、统一页头、降权状态栏，以及更清晰的暗色卡片层次。
- **macOS Home stat cards**: the hero word-count card is now a full-width horizontal bar sized to its content (icon + label + big number) instead of a tall card stretched to match its neighbors, removing the large dead space below the number; the "Recent" list was removed from Home since it duplicated the History page. / **macOS 首页统计卡**：字数主卡改为按内容自适应高度的满宽横条（图标+标题+大数字），不再被拉伸到与相邻卡片等高、留出大片空白；首页底部与历史页重复的「最近」列表已移除。
- **macOS page margins**: Home / History / Dictionary / Settings share `pageHorizontalInset` on titles and scroll *content*; ScrollViews / Forms stay full-bleed so the scrollbar sits on the window edge, while cards stay aligned with the page title. Settings keeps native grouped Form for control layout. / **macOS 页边距**：首页 / 历史 / 词库 / 设置在标题与滚动*内容*上共用 `pageHorizontalInset`；ScrollView / Form 通栏使滚动条贴窗口右缘，卡片仍与页标题对齐。设置保留原生分组 Form 以保证控件排版。

### Fixed
- **Spurious "Voice is ready" overlay**: a healthy in-app Flow session no longer flashes the cold-start overlay after dictation. Keyboard mic presses wait when the session is still alive (including `preparingSession` / single-frame `hostNotReady` races); only a truly dead host opens `startflow`. The host silences overlay when already ready or busy. Proactive auto-launch is disabled. / **误弹「语音已就绪」**：App 内健康 Flow 会话在听写后不再闪冷启动浮层。键盘在会话仍存活时（含 `preparingSession` / 单帧 `hostNotReady` 竞态）只等待；仅宿主真正死亡才打开 `startflow`。主 App 在已就绪或忙碌时静默忽略浮层。已关闭被动自动拉起。
- **Cold-start overlay recursion crash**: dismissing the ready overlay while an utterance is already recording no longer recurses `refreshHostReady` → `reconcile` → `dismiss` on the main thread until stack overflow (`EXC_BAD_ACCESS`). Handoff flags are cleared before any refresh. / **冷启动浮层递归崩溃**：就绪浮层仍在时若已开始录音，不再在主线程上递归 `refreshHostReady` → `reconcile` → `dismiss` 直至栈溢出（`EXC_BAD_ACCESS`）；交接标志会在任何 refresh 之前先清除。
- **macOS Qwen3 “language” garbage transcript**: Sherpa Qwen3 results that still include the model scaffold (`language Chinese<asr_text>…`) are now stripped to the spoken text; incomplete outputs that stop at the bare word `language` are treated as empty instead of being inserted. / **macOS Qwen3「language」乱码转写**：Sherpa Qwen3 结果若仍带模型脚手架（`language Chinese<asr_text>…`）会剥到真实口语文案；不完整输出停在单词 `language` 时按空结果处理，不再插入。
- **macOS local ASR silence garbage output**: dictating with no speech (silence) on a Sherpa-backed local model (SenseVoice/Qwen3/Paraformer) no longer inserts the raw JSON result line (`{"lang": "", "emotion": "", ...}`) as the transcript — it now correctly reports "no speech recognized". / **macOS 本地识别静音乱码**：使用 Sherpa 本地模型（SenseVoice/Qwen3/Paraformer）听写时若未检测到语音，不再把原始 JSON 结果行（`{"lang": "", "emotion": "", ...}`）当作转写文本插入，现在会正确提示「没有识别到语音」。
- **Force-quit mic release**: on termination the host app now synchronously stops `AVAudioEngine`, deactivates `AVAudioSession`, and ends Live Activities (Dynamic Island + Lock Screen) in `applicationWillTerminate`, reducing “microphone in use” errors after reopening. / **强杀麦克风释放**：进程终止时在 `applicationWillTerminate` 内同步停止 `AVAudioEngine`、释放 `AVAudioSession` 并结束 Live Activity（灵动岛 + 锁屏），降低强杀后重开提示麦克风被占用的概率。

## [0.5.2] - 2026-07-09

### Added
- **macOS local ASR models**: the desktop app ships a bundled model catalog with one-click download of Sherpa Qwen3 (hotwords) and SenseVoice models, plus a shared model storage directory; downloads show a circular progress ring with pause / resume, and each row has inline Download / Delete actions. / **macOS 本地 ASR 模型**：桌面 App 内置模型目录，可一键下载 Sherpa Qwen3（热词）与 SenseVoice 模型，并共用同一模型存储目录；下载显示带暂停 / 继续的环形进度，每行提供内联的下载 / 删除操作。
- **Shared model directory for MLX**: Qwen3-ASR MLX now uses a fixed subfolder inside the shared model storage — drop converted weights into the folder opened by "Open folder"; no per-model directory picker. / **MLX 共用模型目录**：Qwen3-ASR MLX 改用共享模型存储中的固定子目录——把转换好的权重放入「打开目录」指向的文件夹即可，不再逐模型选目录。
- **iCloud sync hardening**: per-field settings merge (`appSettings.v2`), per-device usage statistics (G-Counter), tombstoned dictionary/history merge, and a low-risk **Sync Now** action in Settings. / **iCloud 同步加固**：设置按字段合并（`appSettings.v2`）、统计按设备 G-Counter 累计、词库/历史带墓碑合并，并在设置中新增低风险的**立即同步**操作。

### Changed
- **API key sync**: cloud provider API keys now replicate through **iCloud Keychain** when settings sync is on — never through iCloud KVS JSON. / **API 密钥同步**：开启设置同步后，云端服务商 API 密钥改由 **iCloud 钥匙串**复制，不再写入 iCloud KVS JSON。
- **Speech history cap**: synced history limit is **300** entries (aligned with the sync payload). / **语音历史上限**：可同步历史上限为 **300** 条（与同步载荷一致）。
- **macOS app name**: the built product is now `OSGKeyboard.app` (was `OSGKeyboardMac.app`); Dock, About, and Finder all read **OSGKeyboard**. / **macOS 应用名称**：编译产物改为 `OSGKeyboard.app`（原 `OSGKeyboardMac.app`）；Dock、关于窗口与 Finder 均显示 **OSGKeyboard**。
- **macOS local recognition label**: the Settings entry is now simply "Local Recognition" and no longer names a specific model. / **macOS 本地识别标签**：设置项改为「本地识别」，不再绑定具体模型名称。

### Fixed
- **macOS menu-bar icon in light mode**: the status-bar icon now follows the *system* menu-bar appearance, so forcing the app into Light while the system is Dark no longer renders an unreadable dark icon; a refreshed status mark is used. / **macOS 菜单栏图标（浅色模式）**：状态栏图标改为跟随*系统*菜单栏外观，App 强制浅色而系统为深色时不再出现看不清的深色图标；并更新了状态栏图标。
- **macOS light-mode sidebar**: restored the native translucent sidebar material so the light appearance matches system apps (e.g. System Settings, Notes) instead of a flat grey fill. / **macOS 浅色侧边栏**：恢复原生半透明侧栏材质，浅色外观与系统应用（如系统设置、备忘录）一致，不再是扁平灰底。
- **Settings sync wiping API keys**: pulling a legacy settings blob without API key fields no longer deletes local Keychain entries. / **设置同步清空 API 密钥**：拉取不含 API 密钥字段的旧版设置包时，不再删除本地 Keychain 项。
- **Cross-device settings conflicts**: changing different settings on two devices no longer lets one device's full blob overwrite the other's unrelated fields. / **跨设备设置冲突**：两台设备分别修改不同设置项时，不再因整包覆盖而冲掉对方未改动的字段。
- **Usage statistics under-counting**: offline usage on multiple devices now sums correctly instead of taking per-field `max()`. / **使用统计少计**：多设备离线各自累计后合并为求和，不再对总量取 `max()`。
- **Dictionary/history resurrection**: deletes and "clear all" on one device propagate via tombstones so older remote entries cannot come back. / **词库/历史复活**：单设备删除或清空会通过墓碑传播，远端旧条目无法复活。
- **Flow false-ready mic state**: the keyboard mic now stays orange until the host app publishes a real ready contract (capture engine live + polling idle), not merely a fresh heartbeat; green tap-to-talk and jump-to-host behavior share the same `MicVoiceAvailability` gate, and orphaned `stopped` signals self-heal instead of hanging until timeout. / **Flow 伪就绪麦克风状态**：键盘麦克风在主 App 发布真实就绪合约（音频引擎在跑且轮询空闲）之前保持橙色，不再仅凭心跳误判；绿色「点按说话」与跳转主 App 共用同一 `MicVoiceAvailability` 闸门，孤立的 `stopped` 信号会自愈而不再长时间卡住。
- **Flow mic stuck orange after ready**: a single stale cross-process heartbeat read no longer flips a healthy session into a sticky "session ended" error that forced the mic orange. The "session ended" hint now fires only when the (heartbeat-independent) session contract truly drops; a brief read jitter is smoothed by a ready grace window, and a lingering expired hint auto-recovers to green once the host is ready again. / **就绪后麦克风卡橙色**：单次跨进程心跳读数抖动不再把健康会话打成粘滞的「会话已结束」错误、强制麦克风变橙。「会话已结束」提示现仅在（不依赖心跳的）会话合约真正失效时触发；短暂读数抖动由就绪宽限期平滑，遗留的过期提示会在宿主重新就绪后自动恢复为绿色。
- **Orphaned Live Activity after force-quit**: force-quitting the app no longer leaves a stale OSGKeyboard status stuck on the Lock Screen / Dynamic Island. The `staleDate` is now ~45s (refreshed by the heartbeat while the session is alive) so the system reclaims a dead session's island on its own, and every app foreground now sweeps leftover Live Activities *before* trying to (re)start a session — so even a start that later fails (e.g. mic proof timeout) still clears the zombie island. / **强杀后遗留 Live Activity**：强制退出 App 不再在锁屏 / 灵动岛留下无法消失的 OSGKeyboard 状态。`staleDate` 缩短为约 45 秒（会话存活期间由心跳持续刷新），系统会自动回收已死会话的灵动岛；且每次 App 回到前台都会**先**清扫遗留的 Live Activity 再尝试（重新）启动会话——即便本次启动随后失败（如麦克风就绪超时），也不会留下僵尸灵动岛。

## [0.5.0] - 2026-07-07

### Added
- **iCloud settings sync**: engine, language, polish, and Flow preferences now stay in sync across your devices via iCloud (key-value store); a new "Sync settings via iCloud" toggle in Settings controls it. API keys stay on each device and are never uploaded. / **iCloud 设置同步**：引擎、语言、润色与 Flow 偏好现可通过 iCloud（键值存储）在多设备间自动同步；设置中新增「通过 iCloud 同步设置」开关控制此功能。API 密钥仅保留在各自设备本地，绝不上传。

### Changed
- **Cold-start return guidance**: the handoff screen now points to the bottom Home indicator with a left-to-right swipe animation (instead of the misleading "swipe up"), auto-dismisses once you switch back to your previous app, and closes on a tap anywhere; a "Return to [App]" link is still offered when available. / **冷启动返回引导**：交接页改为指向底部横条并配左向右滑动动画（不再是易误解的「向上滑」），切换回上一个 App 后自动消失，点按任意处即可关闭；可用时仍保留「返回 [App]」文本按钮。
- **Voice session handoff robustness**: hardened the keyboard→app cold-start flow, including a clearer "Voice session disconnected" hint when the host session drops. / **语音会话交接健壮性**：强化键盘→主 App 的冷启动链路，宿主会话断开时给出更清晰的「语音会话已断开」提示。

### Fixed
- **Local ASR route-change crash**: dictating with the on-device engine no longer terminates the app with `Failed to create tap due to format mismatch`. On-device `SpeechAnalyzer` warmup reconfigures the shared audio session, which triggers a route change; the tap was reinstalled with a stale hardware format (48 kHz) that no longer matched the live node (24 kHz). The tap now binds to the node's live format (`installTap(format: nil)`) and the downsampling converter rebuilds itself from the actual buffer format, so route churn is handled without crashing. / **本地识别路由切换崩溃**：使用端侧引擎听写不再以 `Failed to create tap due to format mismatch` 崩溃退出。端侧 `SpeechAnalyzer` 预热会重配共享音频会话并触发路由变化，此前重装 tap 时用了过期的硬件采样率（48 kHz），与真实节点（24 kHz）不匹配。现在 tap 绑定节点实时格式（`installTap(format: nil)`），降采样转换器按实际缓冲区格式自适应重建，路由抖动不再导致崩溃。
- **ASR fallback warning showed raw key**: the weak-network / missing-key fallback hint displayed its localization key (e.g. `flow.warning.polishDegraded`) instead of the translated sentence. These keys live in the `Shared.strings` table but were looked up via the main-app `Localizable` table; they are now resolved through `SharedL10n`. / **ASR 兜底提示显示变量名**：弱网 / 缺少密钥的兜底提示此前显示本地化键名（如 `flow.warning.polishDegraded`）而非译文。这些键位于 `Shared.strings`，却被按主 App 的 `Localizable` 表查找；现改为经 `SharedL10n` 解析。
- **Flow multi-utterance recognition**: the second (and later) dictation in a session no longer returns "no speech". The session-long downsampling `AVAudioConverter` was being permanently locked by an `.endOfStream` tail-flush, starving every utterance after the first (both on-device and cloud). Trailing speech is still preserved by the live drain loop. Also added recovery from `mediaServicesWereReset`. / **Flow 连续多句识别**：同一会话内第二句及之后不再提示「未识别到语音」。此前会话级降采样 `AVAudioConverter` 被尾音冲刷的 `.endOfStream` 永久锁死，导致首句之后每句都拿不到音频（端侧与云端均受影响）。尾音仍由实时排空环节保留。并新增媒体服务重置（`mediaServicesWereReset`）后的自愈重建。
- **Local ASR diagnostics**: add chunk-level `SpeechAnalyzer` logs and a settings switch to bypass the custom language model, so local recognition failures can be isolated between Apple assets, CLM attachment, and empty analyzer results. / **本地识别诊断**：新增 `SpeechAnalyzer` 分块级日志，并在设置中加入跳过自定义语言模型的诊断开关，用于区分 Apple 端侧资源、自定义语言模型挂载、以及分析器空结果三类问题。

## [0.4.1] - 2026-07-06

### Added
- **Flow Live Activity**: Dynamic Island shows the OSGKeyboard brand mark during an active voice session (ActivityKit widget extension). / **Flow 灵动岛 Live Activity**：语音会话期间在灵动岛显示 OSGKeyboard 品牌标识（ActivityKit 小组件扩展）。
- **Xiaomi MiMo cloud provider**: preset for the cloud engine with `mimo-v2.5` polish via `api.xiaomimimo.com` (on-device ASR, same pipeline as other online providers). / **小米 MiMo 云端引擎**：云端引擎新增预设，经 `api.xiaomimimo.com` 使用 `mimo-v2.5` 润色（端侧 ASR，与其他在线服务相同管线）。
- **Flow session policy (A)**: on-demand session start from the keyboard; inactivity-based expiry (10m–24h, default 12h) reset after each utterance; handoff auto-starts recording. / **Flow 会话策略（A）**：键盘按需启动会话；无活动超时（10 分钟–24 小时，默认 12 小时）每句结束后重置；交接完成后自动开始录音。
- **Skip app switch (B+C)**: settings toggle (default on) plus cold-start overlay with swipe-back guidance and optional “Return to [App]” alert. / **跳过应用切换（B+C）**：设置开关（默认开）+ 冷启动极简页（右滑引导 + 可选「返回 [App]」弹窗）。
- **Host return whitelist (C+D)**: `HostAppURLRegistry` with 20 high-frequency host apps; `sourceApplication` capture on `startflow`. / **宿主回跳白名单（C+D）**：`HostAppURLRegistry` 覆盖 20 个高频宿主 App；`startflow` 时记录 `sourceApplication`。

### Changed
- **Keyboard language label**: `PrimaryLanguage` set to `mis` so Settings no longer shows a misleading “English” subtitle under OSGKeyboard. / **键盘语言标签**：`PrimaryLanguage` 设为 `mis`，系统设置中 OSGKeyboard 下不再显示误导性的「英文」副标题。
- **Flow ASR pipelining**: shorter first chunk (2.5s) and 5s follow-ups so short utterances start on-device recognition while still recording; session-level ASR warmup and format cache reuse; live partials mirrored to the keyboard transcript line. / **Flow ASR 流水线**：首块 2.5 秒、后续 5 秒，短句录音期间即开始端侧识别；会话级 ASR 预热与格式缓存复用；实时 partial 同步到键盘转写行。
- **Flow tail drain**: after mic stop, capture drains trailing PCM (silence-detected, capped) before finishing the ASR stream; host finalize awaits drain; short final chunks re-transcribed with prior overlap; stitcher safe fallback when overlap merge would drop content. / **Flow 尾音排空**：停止录音后先排空尾部 PCM（静音检测 + 上限）再结束 ASR 流；主 App finalize 等待排空；过短末块与上一块 overlap 合并重识别；拼接误删时回退为安全合并。

## [0.4.0] - 2026-07-05

### Added
- **Custom ASR language model**: on-device `SFCustomLanguageModelData` bias model (computer/IT terms + curated AI/tech brands) prepared via `CustomLanguageModelManager` and applied to `DictationTranscriber` for Chinese dictation; compiled LM/Vocab shared through the App Group. / **自定义语音识别语言模型**：端侧 `SFCustomLanguageModelData` 偏置模型（计算机术语 + 精选 AI/科技品牌词），通过 `CustomLanguageModelManager` 在设备上准备并挂载到 `DictationTranscriber` 用于中文听写；编译后的 LM/Vocab 经 App Group 共享。
- **Cursor navigation**: keyboard drag pad (`CursorDragPad` / `CursorNavigation`) for precise caret movement. / **光标导航**：键盘拖动手势区（`CursorDragPad` / `CursorNavigation`），精确移动光标。
- **Key sound feedback**: `KeyboardSoundFeedback` plays system key clicks on input. / **按键音反馈**：`KeyboardSoundFeedback` 在输入时播放系统按键音。
- **Personal dictionary tooling**: `DictionaryAliasGenerator` and `PersonalDictionaryEntrySheet` for managing custom terms and aliases. / **个人词库工具**：`DictionaryAliasGenerator` 与 `PersonalDictionaryEntrySheet`，用于管理自定义词条与别名。
- **Transcript post-processing**: `TranscriptPostProcessor` quality gate on the shared ASR path. / **转写后处理**：共享 ASR 链路上的 `TranscriptPostProcessor` 质量校验。

### Changed
- **Tab bar visibility**: `TabBarVisibility` centralizes show/hide handling; retired `PageHeaderRow` / `PageHeaderConfirmButton`. / **标签栏可见性**：`TabBarVisibility` 统一管理显隐；移除 `PageHeaderRow` / `PageHeaderConfirmButton`。

### Removed
- **DictionaryLearner**: replaced by the new dictionary tooling. / **DictionaryLearner**：由新的词库工具取代。

### Security
- **DeepSeek key handling**: move the hardcoded API key out of `PreconfiguredKeys.swift` into a gitignored `PreconfiguredKeys.local.swift` (seeded from `.example` by `generate-xcodeproj.sh`). / **DeepSeek 密钥处理**：将硬编码 API 密钥移出 `PreconfiguredKeys.swift`，改为 gitignore 的 `PreconfiguredKeys.local.swift`（由 `generate-xcodeproj.sh` 从 `.example` 生成）。

## [0.3.6] - 2026-07-05

### Changed
- **ASR polish pipeline**: global output contract (no new emojis, punctuation, structure at every intensity), `TranscriptPostProcessor` quality gate, ultra-short utterances skip LLM, removed Off polish tier (legacy `off` migrates to Medium), preceding-text context in keyboard polish path.

## [0.3.4] - 2026-07-04

### Added
- **Home usage statistics**: new home-screen stats card showing cumulative dictation time, dictation characters, translation characters, and personal-dictionary entry count.

### Changed
- **Local engine polish path**: local mode now uses the built-in DeepSeek polish path by default, removing the separate "Cloud polish after ASR" toggle and user-facing DeepSeek API key setup.
- **Provider API keys**: cloud-provider API keys are isolated per provider in Keychain, so switching providers no longer reuses the previous vendor's key.
- **Translation availability**: translation settings are visible for both local and cloud engines.
- **DeepSeek provider visibility**: DeepSeek is reserved for the local engine's built-in path and is no longer shown as a cloud-provider picker option.

### Fixed
- **Home stats rendering**: the stats card gradient background now uses a View-backed background compatible with SwiftUI's type system.
- **Usage statistics imports**: the usage statistics store now imports the shared module required for translation-state checks.

## [0.3.0] - 2026-06-24

### Added
- **Post-polish translation** for cloud and local engines: target-language picker in Settings / onboarding, `TranslationChip` on the keyboard top bar, and `PolishMode.translate` in `PolishingService`.
- **Preconfigured DeepSeek key** (`PreconfiguredKeys`) for local-engine cloud polish without round-tripping the Settings API card.

### Changed
- **Local-engine translation is gated on cloud polish**: the translation row and LLM step are hidden/disabled until "Cloud polish after ASR" is enabled; turning polish off clears a stale translation target.
- **Local-engine LLM endpoint pinning**: when the pipeline routes through DeepSeek, base URL and model come from the DeepSeek preset instead of the user's cloud-provider settings (fixes DeepSeek key + Qwen URL 401s).

### Fixed
- **Translation chip always visible** when the engine can run cloud LLM (cloud always; local when cloud polish is on) — no longer hidden when target is "不翻译".
- **Keyboard translation menu** first item shows "不翻译"; chip label when off stays "翻译".
- **Translation toggle race**: 2.5s protect window after chip writes, Darwin config notification, host finalize re-reads App Group; turning off cloud polish no longer clears saved translation target.

## [0.2.1] - 2026-06-24

### Removed
- **Qwen3 CoreML on-device ASR stack** (rolled back from v0.2.0). Deleted the vendored `Qwen3Speech` SPM package, the `Qwen3ASRService`, the `ModelManager` / `OnDeviceModelWarmup` / `OnDeviceModelsView` / `DownloadConfirmSheet` UI and downloaders, the `OnDeviceModel` and `OnDeviceModelStatus` shared models, and the corresponding `LocalASRBackend.qwen3ASR` enum case. Removed the `Qwen3ASRServiceProvider` registration in `OSGKeyboardApp`, the `ModelScope`/`HuggingFace` mirror picker, and the `Qwen3Speech` SPM package declaration from `project.yml`. No more model download / loading / warm-up code paths or UI state.

### Changed
- **Local engine narrows to iOS ASR**. The on-device engine is now exclusively iOS 26 `SpeechAnalyzer` + `DictationTranscriber` (with `SFSpeechRecognizer` as the pre-26 fallback). The previous `.qwen3ASR` backend has been removed; `LocalASRBackend` retains a single `.speechAnalyzer` case so the next non-iOS backend can slot in without touching every call site.
- **Local engine is genuinely local by default**. When the user picks "local" and leaves the new polish toggle off, the transcript is inserted at the cursor as-is — no cloud LLM round-trip.
- **DeepSeek preset defaults to `deepseek-v4-flash`**. The DeepSeek `LLMProvider.presets` entry's `defaultModel` was bumped from `deepseek-chat`; existing users keep their saved model name until they re-pick the preset.

### Added
- **Cloud polish toggle for the local engine**. Settings → On-device models → "Cloud polish after ASR". When enabled, the local-engine transcript is routed through the user's configured cloud LLM (DeepSeek by default) via the existing `PolishingService` + `LLMClient` chain. When disabled, the local engine is ASR-only. The toggle is a plain `Bool` (`ProviderConfig.localModeCloudPolishEnabled`) and persists in the App Group so the keyboard extension can honour it during live dictation.
- **DeepSeek API key path for the local polish flow**. SettingsView reveals the `providerSection` / `apiSection` cards when the polish toggle is on so the user can paste a DeepSeek key into the existing Keychain-bound field. `PolishingService` short-circuits with a new `PolishError.missingAPIKey` and surfaces a localised "fill in your DeepSeek key" warning when the toggle is on but the Keychain is empty. The raw transcript is still inserted (no data loss).
- **iOS 26 `SpeechAnalyzer` + `DictationTranscriber` is now the documented local ASR path**. The pre-v0.2.0 code already supported this; v0.2.1 makes it the default and only on-device backend and adds a "Built-in" badge on the local-engine card so users see there's nothing to download.

### Fixed
- **Two Swift 6 strict-concurrency issues** in `LiveDictationController` and `FlowSessionManager` (the weak `[weak self]` capture inside `await MainActor.run { }` blocks) that were blocking `xcodebuild` clean builds under `SWIFT_STRICT_CONCURRENCY=complete`. The detached-task closure now re-captures the weak reference under `@MainActor` isolation.
- `OpenSourceLicensesView` no longer lists the deleted `speech-swift`, `swift-transformers`, `qwen3-asr-coreml`, or `qwen3-asr-upstream` entries; only `Google Material Icons` remains.

## [0.2.0] - 2026-06-22

### Added
- **Local engine with on-device Qwen models**: Optional Qwen3-ASR 0.6B speech recognition and Qwen3.5-0.8B text polish, fully offline after download.
- **On-device model management**: Download, progress, delete, and readiness status in Settings; mirror auto-selection between ModelScope and Hugging Face with fallback.
- **Engine picker**: Choose between local (on-device ASR + polish) and cloud (ASR + user-configured LLM polish).
- **Flow session dictation**: TypeWhisper-style continuous capture in the host app with keyboard handoff via App Group.
- **Open-source licenses** screen for bundled third-party components.

### Changed
- **Settings simplified**: Merged language and model sections; cloud mode always enables polish (removed off/transcribe mode picker).
- **Keyboard UI**: Local/cloud engine badges replace the mode menu; shows model-not-downloaded guidance when the local stack is incomplete.
- **iPhone only**: Set `TARGETED_DEVICE_FAMILY` to `"1"` for both targets; portrait-only orientations.
- **Keyboard preview always dark**: Preview injects the dark palette regardless of app theme.
- **Docs consistency**: README/README.zh aligned to the iOS 26+ capability set.

### Fixed
- **ModelScope download progress**: Progress now tracks byte counts instead of jumping to 50% after the first file.
- **Light/Dark mode consistency** for shared button/card modifiers via `@Environment(\.themePalette)`.

## [0.1.2] - 2026-06-20

### Fixed
- **Light/Dark mode consistency**: `cardSurface()`, `primaryButton()`, `secondaryButton()`, and `pillChip()` view modifiers in `Theme.swift` now use `ViewModifier` structs that read from `@Environment(\.themePalette)`. Previously they used hardcoded dark `Palette` constants, causing cards and buttons to always render in dark mode even when the main App was in light mode.
- **TestFlight error 90474** (Invalid bundle): Added `UIRequiresFullScreen: true` and all four `UISupportedInterfaceOrientations` values to `Info.plist` via `project.yml`. The app targets iPhone + iPad (`TARGETED_DEVICE_FAMILY: "1,2"`), and Apple requires all four orientations for iPad multitasking; setting `UIRequiresFullScreen` opts out of slide-over/split-view while still satisfying the validator.
- **Keyboard Preview cycling**: The "Tap the disc to cycle states" prompt now actually works. `KeyboardPreviewStub` gained an `onTap` closure wired to `cyclePhase()` in `KeyboardPreviewSheet`, which rotates `.idle → .recording → .processing → .idle` with animation. Sample transcript text is shown during the `.recording` phase.

### Added
- **Dynamic ASR locale picker**: Settings now loads the full list of supported locales from `SFSpeechRecognizer.supportedLocales()` on appear (off the main thread). Each locale shows an on-device badge (iPhone icon) when the device supports on-device recognition for that language — giving users confidence about which locales avoid sending audio to the cloud. A static fallback list is shown while the async load is in progress.
- `Speech.framework` linked to the main App target in `project.yml` (needed by the new dynamic locale loader in `SettingsView`).

### Changed
- `pillChip(foreground:)` signature changed from `foreground: Color = Palette.textSecondary` to `foreground: Color? = nil`; callers that pass an explicit color are unaffected.

> **Note: v0.1.1 polish** — this is a small follow-up to v0.1.0 focused on review-driven cleanup
> (theme follow-up, ASR robustness, debug-print hygiene, docs). **No features are removed.**
### Fixed
- **PrivacyInfo.xcprivacy audited for honesty**: removed the three undeclared `NSPrivacyAccessedAPIType` entries (`FileTimestamp` / `DiskSpace` / `SystemBootTime`) the project doesn't actually use, and added `ActiveKeyboards` (reason `DDA9.1`) to the keyboard extension's manifest because `advanceToNextInputMode()` is in the tap path. The main App now declares only `UserDefaults` (reason `CA92.1`), which is the only Required Reason API it touches.
- **Theme follows system appearance**: main App now renders a true light palette in light mode via `ThemedRoot` + `EnvironmentKey<ThemePalette>`. The keyboard extension deliberately stays dark (Apple's default) and now uses a transparent `.background(Color.clear)` so the system UI chrome shows through.
- **Speech Recognition permission requested on first press**: added `NSSpeechRecognitionUsageDescription` to both targets' `Info.plist` and an explicit `SFSpeechRecognizer.requestAuthorization` call inside `pressBegan()`. Without these, speech authorization could remain `.denied` and recognition would fail silently.
- **ASRService emits a DEBUG warning when on-device recognition isn't supported**, so it's obvious during dev that the request fell back to cloud.
- **App Group fallback behaviour**:
  - In `DEBUG`, a missing App Group now `fatalError`s with a precise remediation message (was a soft print + `.standard` fallback, which desynced the keyboard extension from the main App).
  - In release, the fallback is preserved but logged via `NSLog`.
- **`KeyboardViewController.loadPersistedLocale` self-check** (DEBUG only) prints the active provider / baseURL / masked API key / mode / locale, so the keyboard extension's view of the App Group is visible in the device console.
- **`KeyboardViewController.handleFinalTranscript` typed-error routing**: `LLMError.noAPIKey` (401) and `LLMError.http(429)` now surface as red, explicit error messages instead of silently inserting the raw transcript. Network / timeout errors still fall back to the raw transcript + error badge (no data loss).
- **`PolishingService` timeout** raised from 12 s to 15 s to align with `LLMClient`'s URL request timeout. Previously the polisher would race the network call and discard a successful response that arrived in the 12–15 s window.
- **DEBUG `print` cleanup**: the four `🔥 [OSGKeyboardApp] …` instrumentation prints in `OSGKeyboardApp.init()` and root views are now wrapped in `#if DEBUG`.

### Added
- "Test connection" button in `APISettingsCard`: fires a single `polish("ping")` round-trip and surfaces success or the typed LLM error inline. Helps the user confirm the App Group + key are working without leaving the main App.
- 5 new unit tests in `OSGKeyboardTests`: App Group cross-process persistence, 401 / 429 / timeout / noAPIKey catch paths, and `mode = .off` short-circuit.

### Changed
- README + `README.zh.md`: replaced `<OWNER>` placeholder with `hkgood` and aligned capability statements to the implemented iOS 26 path.

### Known limitations
- The keyboard does not work in password fields (iOS limitation).
- Microphone requires "Allow Full Access" to be enabled in iOS Settings.
- Whisper.cpp / on-device LLM polish is intentionally out of scope for v1 (cloud-only).

## [0.1.0] - 2026-06-17

### Added
- First public pre-release.
