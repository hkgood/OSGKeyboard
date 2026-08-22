# Changelog

All notable changes to OSGKeyboard will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Local clipboard semantics**: add reproducible bilingual Create ML training, self-contained on-device classifiers for tasks, questions, invitations, complaints, and sentiment, plus deterministic language, date, address, phone, URL, person, and organization labels without uploading clipboard text. / **本地剪贴板语义**：新增可复现的中英语料与 Create ML 训练流程，以及任务、问句、邀约、投诉和情感的端侧自包含分类器，并结合确定性的语言、日期、地址、电话、URL、人名和组织名标签，全程不上传剪贴板原文。
- **Contextual clipboard skills**: add source-language, invitation, task, clarification, empathy, business, conclusion, and list actions, then select up to five relevant keyboard skills from the complete catalog using ephemeral local clipboard labels, independent of installation state or user-managed ordering. / **情境化剪贴板技能**：新增原语言回复、邀约、任务、澄清、共情、商务、结论与清单操作，并通过本地临时剪贴板标签从完整目录中自动选出最多五个相关技能，不再依赖安装状态或用户管理的固定顺序。
- **Learned speaking styles**: unlock user-initiated style generation after 5,000 effective dictation characters, prioritize recurring native speech and explicit user edits, use historical polish prompts only to subtract AI-added style, and require review before saving. / **学习说话风格**：累积 5,000 个有效听写字符后，可优先根据反复出现的原生口述与用户明确编辑生成个人风格，历史润色 Prompt 仅用于排除 AI 附加风格，并在保存前强制检查。

### Changed
- **Skill catalog layout**: replace the two-column cards with scroll-safe installed and uninstalled lists; selecting a row now opens a full detail page where installation, Shortcut setup, and custom-skill editing are managed. / **技能目录布局**：将双列卡片改为可稳定滚动的已安装与未安装列表；点击列表项进入完整详情页，并统一管理安装、捷径配置与自定义技能编辑。

### Fixed
- **Repeatable OOBE practice**: scope each free feature to one use per short-lived guided session, so returning to OOBE starts a fresh four-page experience without misreporting consumed-page conflicts as weak network; also simplify lesson titles, add a voice sample to read aloud, and streamline the completion page. / **可重复的 OOBE 体验**：将每项免费功能限制为每个短期引导会话使用一次，让用户重新进入 OOBE 时可以重新体验四个页面，并避免把页面已完成冲突误报为弱网；同时精简各环节标题，加入语音朗读示例，并简化完成页。

## [2.0.1] - 2026-08-21

### Added
- **Rime term suggestions**: move the Personal Dictionary card above History and surface up to five repeated local Rime terms for explicit one-tap confirmation without recording full keystrokes. / **Rime 词条建议**：将个性词库卡片移到历史记录上方，展示最多五个本机 Rime 高频新词，并由用户逐个确认加入，不记录完整击键内容。
- **Private keyboard usage summaries**: count only manually committed Chinese, Latin, and other graphemes plus UTC-day input-session classes, then upload immutable App Group summaries without retaining typed text, host-app context, or per-key events. / **隐私键盘用量摘要**：仅统计手动上屏的中文、拉丁字母及其他字形簇与 UTC 每日输入会话分类，并通过 App Group 上传不可变摘要，不保留输入原文、宿主上下文或逐按键事件。
- **Official Skill Catalog**: fetch validated transform skills anonymously from the OSG content service, cache the last-known-good snapshot in App Group storage, and update enabled keyboard skills without requiring an app release. / **官方技能目录**：从 OSG 内容服务匿名获取并严格校验转换类技能，将最后可用快照缓存到 App Group，并可在无需发布新版 App 的情况下更新已启用的键盘技能。
- **Privacy-preserving product analytics**: add an optional first-party event queue with cross-process SQLite durability, idempotent retry, fixed privacy-safe dimensions, and a device-local opt-out that clears pending events. / **隐私友好的产品分析**：新增可选的第一方事件队列，通过跨进程 SQLite 持久化、幂等重试与固定隐私安全维度可靠投递，并提供清除待发送事件的本机退出开关。
- **Managed-cloud consent**: the first switch to OSG credits now explains which audio, text, context, and account data leaves the device and requires explicit agreement before enabling the service. / **托管云确认**：首次切换到 OSG 积分时会说明哪些音频、文字、上下文与账号数据会离开设备，并在用户明确同意后才启用服务。
- **Anonymous four-feature OOBE**: after App Attest verifies the installation, first-run users can try voice input, clipboard translation, smart reply, and hold-to-ask AI once each without an account, API key, or credit charge; an optional sign-in step then offers the existing 1,000-credit signup reward. / **匿名四功能 OOBE**：App Attest 验证安装后，首次用户无需账号、API Key 或积分即可各体验一次语音输入、剪贴板翻译、智能回复与长按询问 AI；随后可选择登录并领取现有的 1000 积分注册奖励。

### Changed
- **Paired voice history corpus**: retain the corrected pre-polish ASR transcript beside the displayed final text, together with translation and active-style metadata, so future style learning can exclude incompatible samples without exposing raw text in History. / **成对语音历史语料**：在展示的最终文本旁保留纠错后的润色前 ASR 转写，并记录翻译与当时风格元数据，便于后续风格学习排除不兼容样本，同时不在历史界面显示原文。
- **Anonymous hint feed**: move AI hint manifests and locale packs to the account content API with ETag revalidation while preserving per-locale last-known-good packs and local evergreen merging. / **匿名提示内容源**：将 AI 提示清单与语言包迁移到账号内容 API，并加入 ETag 重新验证，同时保留各语言最后可用包与本地常驻内容合并策略。
- **Native Liquid Glass tabs**: replace the custom iPhone dock with the system TabView so tab selection uses the native iOS 26 Liquid Glass transition and preserves each tab's navigation context. / **原生液态玻璃标签栏**：以系统 TabView 取代 iPhone 自定义 Dock，让标签切换使用 iOS 26 原生液态玻璃过渡，并保留各标签页的导航上下文。
- **AI Agent first run**: replace the technical six-step setup with a concise privacy, permission, and keyboard flow that teaches four real keyboard capabilities before the optional account offer and verifies every lesson result before completion. / **AI Agent 首次体验**：以简洁的隐私、权限与键盘流程取代技术化的六步配置，在可选账号邀请之前教学四项真实键盘能力，并逐项验证结果后再完成。
- **Focused skill icons**: remove math, indices, arrows, shapes, commerce, keyboard, media, text-formatting, automotive, device, and variable-rendering categories from the custom-skill symbol picker. / **精简技能图标**：从自定义技能图标选择器中移除数学、索引、箭头、形状、商业、键盘、媒体、文本格式、汽车、设备与可变渲染分类。

### Fixed
- **Signed-out AI billing safety**: switch every AI path back to user-owned BYOK when the account signs out or expires, and reject cached managed grants unless the host has confirmed an authenticated session. / **未登录 AI 计费安全**：账号退出或过期时将所有 AI 路径切回用户自备 BYOK，并在主 App 未确认有效登录会话时拒绝使用缓存的托管 Grant。
- **Suspension-safe analytics**: batch uploads in the foreground or a system-granted refresh task, close SQLite outside authorized execution windows, release cancelled leases immediately, and keep keyboard extensions recording-only to prevent system termination from database locks. / **安全挂起埋点**：仅在前台或系统授权的刷新任务中批量上传，在授权执行窗口之外关闭 SQLite，并立即释放已取消的租约，同时让键盘扩展仅负责记录，避免数据库锁触发系统终止。
- **One-shot purchase confirmation**: show a successful credit purchase only for the current action, automatically dismiss it, and prevent recovered historical StoreKit transactions from restoring stale green confirmation text. / **单次购买确认**：积分购买成功提示只对应当前操作并自动消失，恢复 StoreKit 历史交易时不再重新显示过期的绿色确认文字。
- **Permanent invitation links**: load the account-scoped server invitation profile after sign-in, cache it per account, and keep sharing the exact stable server URL across refreshes and offline failures. / **永久邀请链接**：登录后异步加载账号级服务端邀请资料，按账号缓存，并在刷新或离线失败时持续分享服务端返回的固定链接。
- **Cross-process settings safety**: App Group updates now write only changed fields so a stale main-app or keyboard-extension snapshot cannot overwrite newer unrelated settings. / **跨进程设置安全**：App Group 更新现在只写入发生变化的字段，避免主 App 或键盘扩展的旧快照覆盖其他较新的设置。
- **Account-data freshness**: Settings and Account now share one background-refreshed snapshot, preserve cached content on failure, retry transient read errors, and isolate optional referral outages from core account and credit updates. / **账号数据新鲜度**：设置页与账号页现在共用同一份后台刷新快照，刷新失败时保留缓存内容，对瞬时读取错误自动重试，并避免可选邀请接口故障影响账号与积分更新。
- **Account purchase recovery**: keep App Store credit packs independent from account-snapshot failures, retry transient product loading, cancel stale account tasks safely, and return expired sessions to sign-in without requiring a manual sign-out. / **账号内购恢复**：积分包不再受账号快照失败影响，商品瞬时加载失败会自动重试，旧账号任务可安全取消，登录过期后会直接返回登录状态，无需手动退出。
- **Managed AI task routing**: credit-backed requests now preserve dictation, translation, editing, question, clipboard, custom-skill, and agent intent so the gateway can disable costly reasoning for low-latency transforms. / **托管 AI 任务路由**：积分请求现在会保留听写、翻译、编辑、问答、剪贴板、自定义技能与 Agent 意图，让网关可为低延迟转换任务关闭高成本思考。

## [2.0.0] - 2026-08-19

### Added
- **Optional OSG account**: add Sign in with Apple, managed credits, App Store credit packs, referrals, profile controls, and in-app account deletion while keeping local dictation and user-owned provider keys independent. / **可选 OSG 账号**：新增 Apple 登录、托管积分、App Store 积分包、邀请、资料管理与 App 内账号注销，同时保持本地听写和用户自备 API Key 独立可用。
- **Safe AI insertion**: AI answers insert automatically only while the original input field and cursor context still match; otherwise the keyboard retains the answer for explicit insertion or discard. / **安全 AI 上屏**：仅当原输入框和光标上下文仍一致时自动插入 AI 回答；上下文变化时保留回答，由用户明确插入或丢弃。

### Changed
- **Unified assistant keyboard**: merge Voice and AI into one Assistant tab with tap-to-dictate, hold-to-ask-AI, a liquid-glass capsule microphone, contextual hotwords, one-row paged clipboard skills, and shared Send / undo / edit actions; delete, space, undo, and edit remain available while clipboard skills are visible. / **统一助手键盘**：将语音与 AI 合并为一个助手入口，支持轻点听写、长按问 AI、液态玻璃胶囊麦克风、情境热词、单行分页剪贴板技能，以及共用的发送 / 撤销 / 编辑操作；剪贴板技能出现时仍保留删除、空格、撤销与编辑按钮。
- **Adaptive field action**: the assistant action now follows the focused field’s current content and Return semantics, refreshes immediately after keyboard-generated edits, and shows Send, Search, Go, Done, Next, newline, and other matching icons. / **自适应输入框动作**：助手动作现根据焦点输入框的当前内容与 Return 语义显示发送、搜索、前往、完成、下一步、换行等对应图标，并在键盘主动编辑后立即刷新。
- **Clipboard setup guidance**: replace the Skills permission wall with a compact next-step card that enables history inline, verifies paste access, hides completed steps, and shortens Clipboard settings copy. / **剪贴板设置指引**：技能页权限墙改为紧凑的下一步卡片，可直接开启历史、验证粘贴访问并隐藏已完成步骤，同时精简剪贴板设置文案。
- **AI output language**: apply the global translation target to AI answers while letting an explicit language request override it and preserving source-language structured export data. / **AI 输出语言**：AI 回答遵循全局翻译目标，但明确的语言请求优先，结构化导出数据保留源语言。

### Removed
- **Cursor drag pads**: remove blank-area cursor sliding and its Settings toggle; legacy synced values remain decode-compatible. / **光标拖动区**：移除空白区域滑动光标及其设置开关；旧版同步值仍保持解码兼容。

### Fixed
- **Account confirmation anchors**: sign-out and account-deletion confirmations now open from their selected action rows instead of the profile summary card. / **账号确认弹窗锚点**：退出登录与注销账号确认弹窗现在从对应操作行弹出，不再错误指向资料卡。

## [1.8.0] - 2026-08-14

> **Release highlights**: See the concise [1.8.0 release notes](docs/RELEASE_NOTES_1.8.0.md) for the key changes since 1.6.6. / **版本亮点**：请参阅精简的 [1.8.0 更新说明](docs/RELEASE_NOTES_1.8.0.md)，了解自 1.6.6 以来的关键变化。

### Added
- **English QuickType bar**: while typing a word, three equal slots show the verbatim text (quoted when unknown), the unique Space correction, and a completion. The bar stays empty before typing and between committed words. / **英文 QuickType 栏**：输入单词时，三个等宽格显示原文（生词带引号）、空格会采用的唯一纠错和补全；尚未输入及单词提交后保持空白。
- **System English lexicon**: typing uses `UITextChecker` completions/guesses and `requestSupplementaryLexicon` contact names / text replacements. / **系统英文词库**：打字使用 `UITextChecker` 补全/猜测，以及 `requestSupplementaryLexicon` 的通讯录名与文本替换。
- **QWERTY proximity correction**: fat-finger substitutions on neighboring keys (for example `gppd` → `good`) outrank distant edit-distance neighbors. / **邻键纠错**：相邻键的胖手指替换（如 `gppd` → `good`）优先于远键编辑距离。
- **Larger English word list**: about 40k unigrams and truncated bigrams, derived from Peter Norvig’s public-domain n-gram counts, shipped as an mmap binary so the keyboard extension does not parse them into Swift dictionaries. / **更大英文词表**：约 4 万 unigram 与截断 bigram，来自 Peter Norvig 公有领域 n-gram 计数，以 mmap 二进制随扩展加载，避免解析进 Swift 字典。
- **Pinyin abbreviation ranking**: drop dialect single-letter syllables (`m` / `n` / `ng` / `hm`) before abbrev so mixes like `wom` prefer 我们, matching rime-pinyin-simp; full pinyin also allows `zh` / `ch` / `sh` two-key abbrev (resource version `2.4.0`). / **拼音简拼排序**：在简拼前擦掉方言单字母音节（`m` / `n` / `ng` / `hm`），使 `wom` 一类混拼优先「我们」，对齐 rime-pinyin-simp；全拼同时支持 `zh` / `ch` / `sh` 两键简拼（资源版本 `2.4.0`）。
- **Clear typing habits**: Settings → Text Input can reset learned Chinese Rime user dictionaries and English boosts without deleting the personal dictionary. / **清除打字习惯**：设置 → 文本输入可重置中文 Rime 用户词库与英文加分，不删除个性词库。
- **Overlapping key presses**: the typing grid tracks multiple fingers, so the next key can go down before the previous lifts. Pending letters commit in press order (not release order); Shift can be held with one finger while another types. / **叠指连打**：打字网格跟踪多指，上一键未松开也可按下下一键。未提交的字母按按下顺序出字（而非抬手顺序）；一只手指按住 Shift 时另一只可打字。
- **Period shortcut**: in English, a second Space shortly after a Space that follows a word becomes `. ` and arms sentence Shift, matching the system "." Shortcut. / **句号快捷**：英文下，在单词后的空格上短时间内再按一次空格会变成 `. ` 并点亮句首 Shift，对齐系统「句号快捷」。
- **Return key labels**: Go / Search / Send / Done / Next / Join and the other `UIReturnKeyType` values show their system captions on the green action key instead of collapsing to Send or a return arrow. / **回车键文案**：前往 / 搜索 / 发送 / 完成 / 下一项 / 加入等 `UIReturnKeyType` 在绿色动作键上显示系统对应文案，不再一律变成「发送」或换行箭头。
- **Skills tab**: Home dock and iPad sidebar add Skills between Home and Styles; cards list default Reply / Summarize / Translate plus installable export skills (max 8 enabled, long-press drag to reorder). / **技能 Tab**：首页 Dock 与 iPad 侧栏在「首页」和「风格」之间新增「技能」；卡片列出默认的回复 / 总结 / 翻译以及可安装的出口技能（最多启用 8 个，长按拖动排序）。
- **Extract tasks skill**: the Skills tab opens the bundled companion Shortcut `OSGExtractTodos` on the system Add page (split lines → Reminders, default list). After you tap Add, copying text and tapping Tasks asks the LLM for to-dos and silently adds them; no tasks stays in the current app with a keyboard tip. / **提取待办技能**：技能页会打开 App 内置的配套捷径 `OSGExtractTodos` 系统添加页（按行拆分并写入默认提醒清单）。点添加后，复制文字并点「待办」会让模型抽取待办并静默写入；没有待办则留在当前 App，键盘上给出提示。
- **Extract events skill**: the Skills tab opens the bundled companion Shortcut `OSGExtractEvents` on the system Add page (multiple events into Calendar; date-only → all-day, time-only → today, optional end time and location). After you tap Add, copying text and tapping Events asks the LLM for events and silently adds them; no date or time stays in the current app with a keyboard tip. / **提取日程技能**：技能页会打开 App 内置的配套捷径 `OSGExtractEvents` 系统添加页（可多条写入日历；只有日期为全天；只有时刻用当天；可带结束时间与地点）。点添加后，复制文字并点「日程」会让模型抽取日程并静默写入；没有日期或时间则留在当前 App，键盘上给出提示。
- **Navigate skill**: copying text and tapping Navigate asks the LLM for one address (or origin → destination) and the host app opens driving directions — Amap if installed, then Baidu Maps, then Apple Maps. No companion Shortcut. No address stays in the current app with a keyboard tip. / **导航技能**：复制文字并点「导航」会抽取一条地址（或起点→终点），由 App 直接打开驾车导航——已装高德则用高德，否则百度，再否则 Apple 地图。不需要配套捷径。没有地址则留在当前 App，键盘上给出提示。
- **Save to Notes skill**: the Skills tab opens a ready-made companion Shortcut named `OSGSaveToNotes` on the system Add page (one new Apple Note with an explicit title and body). After you tap Add, copying text and tapping Notes asks the LLM for a short title from the time and content; the body stays the original clipboard. / **存入备忘录技能**：技能页会打开已做好的配套捷径 `OSGSaveToNotes` 的系统添加页（新建一条带标题和正文的苹果备忘录）。点添加后，复制文字并点「备忘录」会按时间和内容生成短标题；正文保持剪贴板原文。
- **Skills clipboard guide**: when Clipboard History is off, the Skills tab shows a card that jumps to in-app Clipboard settings and to iOS Settings for paste authorization. / **技能页剪贴板指引**：未开启剪贴板历史时，技能页展示可点击卡片，分别跳转 App 内剪贴板设置和系统设置以完成粘贴授权。
- **Custom skills**: Skills tab `+` adds a user skill (name, about, SF Symbol, prompt, optional iCloud Shortcut link with name lookup, independent Shortcut name, thinking off by default). Without a link, the model result is reviewed and inserted directly; with a link, it keeps the Shortcut export flow. Built-in thinking stays off and disabled. No cap on how many custom skills you can save; the keyboard still holds at most 8. / **自定义技能**：技能页右上角 `+` 可添加用户技能（名称、介绍、SF Symbol、提示词、可选 iCloud 捷径链接并自动读取名称、可与技能名分开的捷径名、思考默认关）。不填链接时，模型结果经确认后直接插入；填写链接时继续走捷径导出流程。内置技能思考固定关闭且不可开。自定义数量不设上限，键盘仍最多启用 8 个。
- **AI keyboard mode**: ask the configured LLM by voice, watch answers stream into the keyboard, then review, Insert, and optionally Send; supported providers can search the web with automatic fallback. / **AI 键盘模式**：通过语音向已配置模型提问，回答会实时显示在键盘中，确认后可插入并按需发送；支持的服务商可联网搜索，失败时自动回退。
- **AI idle suggestions and response length**: the empty AI surface rotates tappable evergreen and current-topic prompts; Settings → AI Agent chooses Short, Medium, or Detailed answers. / **AI 空闲建议与回复篇幅**：AI 空状态轮播可点按的常用问题与热点建议；设置 → AI Agent 可选择简短、中等或详细回答。
- **AI setup guidance**: Home and the keyboard microphone line show a clear prompt when the user-owned AI key is missing; dictation can still insert the raw on-device transcript. / **AI 配置引导**：未配置用户自备 AI Key 时，首页与键盘麦克风上方会明确提示；听写仍可插入设备端原始识别结果。
- **Clipboard history and suggestion strip**: optionally keep the latest 15 plain-text copies on device, open them from the keyboard top bar, and show the newest copy above Voice, Typing, and AI for one-tap insertion. / **剪贴板历史与建议条**：可选在本机保存最近 15 条纯文本，从键盘顶栏打开历史，并在语音、打字与 AI 界面上方显示最新复制内容以便一键插入。
- **Edit last input**: hold the microphone after an OSGKeyboard insertion, describe the change, compare the original and edited text, then replace or append without exposing unrelated field content. / **编辑上次输入**：OSGKeyboard 输入后长按麦克风口述修改要求，对比原文与结果后可替换或追加，且不会读取无关输入框内容。
- **iPad keyboard workspace**: voice and typing surfaces fill the available width in portrait and landscape; the bottom row adds comma, period, and the native globe key, while typing gains undo, redo, copy, and cut. / **iPad 键盘工作区**：语音与打字界面在横竖屏均铺满可用宽度；底行加入逗号、句号与原生地球键，打字顶栏提供撤销、重做、复制和剪切。

### Changed
- **Privacy and third-party disclosures**: align the bundled and web privacy policies with AI Agent skills, Shortcuts/maps handoff, OSGKeyboard web endpoints, Keychain/iCloud behavior, clipboard retention, local typing learning, and Mac model downloads; expand the iOS/macOS license catalog with complete upstream notices. / **隐私与第三方披露**：统一 App 内与网页隐私政策，补充 AI Agent 技能、快捷指令/地图交接、OSGKeyboard 网页端点、Keychain/iCloud、剪贴板保留、本地输入学习与 Mac 模型下载，并为 iOS/macOS 许可目录补齐上游声明。
- **Licensed local speech lexicon**: rebuild the Apple custom language model from the project-curated MIT data subset only, replacing the previous third-party cell-dictionary import chain. / **许可明确的本地语音词表**：Apple 自定义语言模型改为仅由项目维护的 MIT 数据子集重建，替换原第三方细胞词库导入链。
- **Keyboard input tabs**: the four-tab capsule is centered independently of the side controls, with equal 42 pt hit widths and a translucent-black light-mode track. AI and Voice use enlarged `sparkle` and `waveform.mid` symbols, and the leading logo is 16 pt tall. / **键盘输入标签**：四标签胶囊不受两侧控件影响并在键盘上独立居中，点击宽度统一为 42 pt，浅色模式轨道使用半透明黑色；AI 与语音使用放大的 `sparkle` 和 `waveform.mid` 图标，左侧 Logo 高度为 16 pt。
- **English lexicon mmap**: the 40k-word English table loads only in English and stays file-mapped; Chinese typing no longer pulls it in on keyboard appear. / **英文词表 mmap**：4 万词英文表仅在英文加载且走文件映射；中文打字不再在唤起键盘时一并灌入。
- **English autocorrect conservatism**: Title Case / short / ALL CAPS tokens are not replaced, except same-length transpositions (`Teh` → `The`). Machine-applied corrections no longer boost the replacement; rejecting them learns the original. / **英文自动更正更克制**：Title Case / 短词 / 全大写默认不改，仅保留同长换位（`Teh` → `The`）。机器改写不再给新词加分；拒绝纠错会学会原文。
- **Chinese user-dict flush**: leaving the typing surface finalizes librime so user-frequency ticks persist; secure fields insert Latin and skip Rime so passwords are not learned. / **中文用户词落盘**：离开打字表面时 finalize librime，使用频度得以保存；安全输入框改为直接插入拉丁字母、不进 Rime，避免把密码写入用户词库。
- **Bundled Shortcut names**: Tasks and Events now install their signed in-app resources as `OSGExtractTodos` and `OSGExtractEvents`, matching `OSGSaveToNotes`; existing Chinese-named copies must be replaced from the Skills tab. / **内置捷径名称**：待办与日程改为安装 App 内签名资源 `OSGExtractTodos` 和 `OSGExtractEvents`，与 `OSGSaveToNotes` 保持一致；已有中文名称版本需从技能页重新安装。
- **Navigation icons**: Skills uses a wand; Styles uses a dial. The phone dock and iPad sidebar (except Home) use outline when idle and fill when selected. Mac Styles / Settings follow the same pairing. iPad and Mac Home stay the house icon. / **导航图标**：技能改为魔杖，风格改为旋钮。手机 Dock 与 iPad 侧栏（除首页外）未选中描边、选中填充；Mac 的风格 / 设置同样切换。iPad / Mac 首页仍用房子图标。
- **Phone dock size**: slightly smaller — 22 pt icons, 46 pt rows, 8 pt glass padding. / **手机 Dock 尺寸**：略缩小，图标 22 pt、行高 46 pt、玻璃内边距 8 pt。
- **Skill and style cards**: every card uses a top-right edit pencil and a bottom-right selected check; skill Done sits on the right like style details; tapping a skill card toggles the keyboard slot (unconfirmed Shortcut skills still open the install sheet). / **技能与风格卡片**：右上为编辑铅笔、右下为选中勾选；技能详情「完成」改到右侧；点技能卡片切换是否上键盘（未确认捷径的仍打开安装页）。
- **Clipboard skill grid**: idle skill chips stay as one centered block, wrapping to two rows of up to four instead of scrolling sideways after four. / **剪贴板技能网格**：空闲技能按钮作为一整块居中，超过四个改为两行（每行最多四个），不再横向滚动。
- **Skill sheet buttons**: Add, Turn off, Add Shortcut, I’ve added it, and Reinstall are solid capsules — primary actions use the brand green (`#3AA05A`), secondary actions use an elevated fill. / **技能弹窗按钮**：添加、关闭、添加捷径、我已添加、重新安装改为实心胶囊；主操作为品牌绿（`#3AA05A`），次要为抬升底。
- **AI idle hint keywords**: chips show the entity (from feed `metadata.title` / city / holiday name) instead of a long sentence; category prefixes like「全网热点：」are dropped, and LLM compression is only a last resort. / **AI 空闲建议关键词**：芯片展示实体（来自 feed 的 `metadata.title` / 城市 / 节日名）而不再是长句；去掉「全网热点：」一类前缀，LLM 压缩仅作兜底。
- **AI idle hint chrome**: each rotating suggestion sits in a Liquid Glass capsule with a category SF Symbol (calendar, weather, news, stocks, trending, search). / **AI 空闲建议样式**：轮播建议放入 Liquid Glass 胶囊，左侧为类型 SF Symbol（日历、天气、新闻、股票、热搜、搜索）。
- **Clipboard AI skills**: within 30 seconds of a copy, AI idle shows compact circular Reply / Summarize / Translate buttons; translate follows the keyboard language setting, or Chinese ↔ English when unset. The skill list is catalog-based so more actions can be added later. / **剪贴板 AI 技能**：复制后约 30 秒内，空闲态改为小圆形「回复 / 总结 / 翻译」按钮；翻译跟随键盘目标语言，未设置时中英互译。技能来自目录，便于日后扩展。
- **Clipboard Translate label**: the Translate chip shows the live direction — `中译英` / `To JP` when a target is set, `中↔英` / `CN↔EN` when unset, and `简↔繁` when Chinese UI targets 简体 or 繁體. / **剪贴板翻译文案**：翻译按钮按当前设置显示方向——已选目标为「中译英」/「To JP」，未设置为「中↔英」/「CN↔EN」，中文界面目标为简繁时为「简↔繁」。

- **AI idle capsule size**: rotating suggestion chips keep a 44 pt tap height with 16 pt side padding. / **AI 空闲胶囊尺寸**：轮播建议芯片保持 44 pt 点击高度，左右各 16 pt 内边距。
- **Undo / translation chrome**: voice mic-row undo and translation controls are 52 pt circular Liquid Glass buttons. / **撤销与翻译按钮**：语音麦克风行的撤销、翻译改为 52 pt 圆形 Liquid Glass 按钮。
- **Clipboard skill circles**: Reply / Summarize / Translate idle buttons match the same 52 pt circle. / **剪贴板技能圆钮**：回复 / 总结 / 翻译空闲按钮与语音侧键同为 52 pt 圆。
- **Home tab selection**: the dock stays Liquid Glass at its original height; the selected tab is a wider green fill capsule with a 5 pt inset, not a second glass chip. Dock items are 24 pt icons with Home / Skills / Styles / Settings labels. / **首页 Tab 选中态**：dock 仍是原高度 Liquid Glass；选中项改为更宽的绿色填充胶囊，距栏边 5 pt，不再套第二层玻璃。dock 为 24 pt 图标加「首页 / 技能 / 风格 / 设置」文字。
- **Home library card titles**: History and Personal dictionary headers use a 16 pt icon and 13 pt label. / **首页资料卡标题**：历史与个性词库标题改为 16 pt 图标、13 pt 文字。
- **App navigation redesign**: Home becomes the overview with statistics, History, and Personal Dictionary cards; iPhone uses a four-destination Liquid Glass dock, while iPad uses an aligned sidebar + detail workspace. / **App 导航重构**：首页成为统计、历史与个性词库资料卡的总览；iPhone 使用四入口 Liquid Glass Dock，iPad 使用对齐的侧栏 + 内容区工作台。
- **Unified Undo and keyboard chrome**: one Undo action covers dictation, AI answers, edits, and clipboard pastes; Translation moves beside the voice microphone while the top-bar slot becomes Clipboard. / **统一撤销与键盘界面**：同一个撤销操作覆盖听写、AI 回答、编辑与剪贴板粘贴；翻译移到语音麦克风旁，顶栏原位置改为剪贴板入口。
- **User-owned AI keys**: remove the built-in DeepSeek fallback; polish and AI mode use the provider and API key configured by the user. / **用户自备 AI Key**：移除内置 DeepSeek 回退；润色与 AI 模式统一使用用户配置的服务商和 API Key。

### Removed
- **Hold-to-command clipboard flow**: long-pressing the microphone now edits the last verified OSGKeyboard input; Clipboard History, spoken AI clipboard requests, and quick skills replace the previous one-shot clipboard voice-command path. / **长按剪贴板语音流程**：长按麦克风现用于编辑最近一次经验证的 OSGKeyboard 输入；剪贴板历史、AI 口述剪贴板请求与快捷技能取代原来的一次性剪贴板语音指令。

### Fixed
- **Keyboard switch crash**: `requestSupplementaryLexicon` completion hops to the main actor before writing session state, so switching to OSG Keyboard no longer traps on `com.apple.TextInput.lexicon-request`. / **切换键盘崩溃**：`requestSupplementaryLexicon` 回调先回到主线程再写会话状态，切换到 OSG Keyboard 不再在 `com.apple.TextInput.lexicon-request` 上触发隔离断言。
- **Save to Notes Shortcut**: bind the combined first-line title and clipboard body through iPhone Create Note’s real `WFCreateNoteInput` field. The previous `contents` binding was ignored and left an enter-content sheet or a title-only note. / **存入备忘录捷径**：通过 iPhone「创建备忘录」真正的 `WFCreateNoteInput` 字段绑定首行标题与剪贴板正文；旧版 `contents` 绑定会被忽略，导致弹出内容填写框或只生成标题。
- **Extract tasks Shortcut**: receive Shortcut Input as Text, then split lines and add each title to Reminders — the previous recipe could finish successfully without creating items. / **提取待办捷径**：先把快捷指令输入收成文本，再按行写入提醒；旧配方会成功跑完但不创建条目。
- **Skill reorder feedback**: long-press lifts a skill card and the grid slides live under the finger, matching Home Screen rearrange. / **技能拖动排序**：长按拎起技能卡片，网格随手指实时让位，接近主屏幕图标重排。
- **Skill drag preview corners**: the lift preview clips to the card’s continuous rounded rect so square white corners no longer show. / **技能拖动圆角**：拖起预览按卡片连续圆角裁剪，去掉圆角外的直角白底。
- **Clipboard skills jumped to a sentence chip**: copying no longer swaps the three skill buttons for a leftover carousel card such as “translate the clipboard”. Clipboard sentence cards stay out of the idle rotation. / **剪贴板技能跳成句子芯片**：复制后不再把三个技能按钮换成「把剪贴板翻译成…」这类旧轮播卡片；剪贴板句子不再进入空闲轮播。
- **Clipboard skill status XML**: tapping Reply / Summarize / Translate no longer flashes the internal `<clipboard_request>` envelope above the mic. / **剪贴板技能状态 XML**：点回复 / 总结 / 翻译不再把内部 `<clipboard_request>` 信封闪现在麦克风上方。
- **Idle keyboard re-adopted recognition**: aborting a session now remembers that utterance id, so a lagging host `processing` snapshot cannot reopen the voice keyboard in 「识别中」. / **空闲打开误进识别中**：中止会话会记住该句 id，滞后的主机 processing 快照不会在下次打开语音键盘时显示「识别中」。
- **Voice cancel chrome until result**: Cancel (X) stays up through ASR/polish and through abort wait after leaving AI Agent, so the voice mic no longer looks ready while the host is still busy. / **语音取消直到出结果**：X 一直保留到识别/润色结束，以及离开 AI Agent 后的中断收尾；语音麦克风不再在宿主仍忙时显示为可用。
- **Empty double-tap skip**: a mic press shorter than 300 ms with near-silence (or no samples) is discarded before ASR, so accidental double taps no longer wait on a no-speech error. / **空连点跳过**：按下短于 300ms 且接近静音（或尚无样本）的录音在进入识别前丢弃，避免误触后长时间等待「没听清」。
- **AI hint left the mic stuck**: prefilled AI questions now drop the host processing gate after the answer or error; consuming an ack for the live utterance also heals a leaked gate. Reopening the keyboard only aborts when App Group already acked that utterance and the result is gone — a live LLM/ASR wait with no result yet is left running. Cancel during generate no longer delivers the answer afterwards. / **AI 建议卡住麦克风**：预填 AI 问题在出答案或失败后会关掉宿主 processing 闸门；若键盘已 ack 当前句而闸门仍开着，宿主消费 ack 时一并放闸。再次打开键盘仅在 App Group 已 ack 且结果已空时才中断残留闸门；LLM/ASR 仍在跑、尚无结果时继续等待。生成中取消后不再把答案写回来。
- **Chinese input setup and recovery**: Rime deploys deterministically during onboarding and host-app startup; an already-open keyboard retries automatically after deployment instead of remaining stuck on the setup error. / **中文输入初始化与恢复**：Rime 在引导和主 App 启动时确定性部署；部署完成后已打开的键盘会自动重试，不再长期停留在初始化错误。
- **Universal Clipboard and presentation stability**: pasteboard reads move off the main thread and start after presentation, preventing cross-device copies from freezing or blanking the keyboard. / **通用剪贴板与呈现稳定性**：剪贴板读取移出主线程并延后到键盘呈现完成后，避免跨设备复制使键盘卡住或空白。
- **Question-preserving polish**: all built-in and custom styles keep question drafts as questions, with deterministic fallback when a model attempts to answer the user instead. / **保留问句的润色**：全部内置与自定义风格都会保留问句；模型若试图替用户回答，会确定性回退到用户原意。

## [1.6.6] - 2026-08-08

### Added
- **Voice undo**: square undo key beside the mic (outer edge, handedness-mirrored) rolls back the last dictation / clipboard-command insertion when it is still at the caret. / **语音撤销**：麦克风旁外侧圆角撤销键（随左右手镜像），在听写/剪贴板指令结果仍位于光标前时一键撤回。
- **In-app release notes**: after onboarding, show a What's New sheet when the marketing version changes; Settings version row opens the same remote page (`download.osglab.com`) with current version, language, and theme. / **应用内更新说明**：完成引导后，在 marketing 版本变化时弹出更新说明；设置页版本行打开同一远程页（`download.osglab.com`），并传入当前版本、语言与深浅色。
- **Typing input settings l10n**: localize schema / fuzzy / resource strings on the Text Input settings page (and related General toggles) via in-app language. / **文本输入设置双语**：文本输入设置页的方案 / 模糊音 / 资源文案（及通用里相关开关）跟随应用内语言。
- **Clipboard voice command**: long-press the mic when the clipboard has text to treat speech as an instruction over a one-shot clipboard snapshot and insert the result; short press stays dictation; tap again to stop (not release-to-stop). / **剪贴板语音指令**：剪贴板有文字时长按麦克风，将语音视为对该次冻结快照的指令并插入结果；短按仍为听写；再点一下结束录音（非松手结束）。
- **Clipboard record confirm**: show recording UI only after the host confirms capture; enforce a short minimum record window after confirm. / **剪贴板开录确认**：宿主确认采音后再显示录音态；确认后再保证最短有效录音。
- **Clipboard recording chrome**: after host-confirmed clipboard recording, the mic disc animates red→blue and shows side captions (“指令录制中” / “点按结束处理”); dictation stays red. / **剪贴板录音视觉**：宿主确认剪贴板录音后，麦克风圆盘红→蓝过渡，两侧显示「指令录制中」「点按结束处理」；普通听写仍为红色。
- **Clipboard failure tips**: when long-press cannot start (paste denied, empty/short/code-like material, secure field, no Full Access), show a brief reason above the mic. / **剪贴板失败提示**：长按无法开始时（拒贴、空/过短/验证码类、密码框、无完全访问）在麦克风上方短暂显示原因。

### Removed
- **Keep-alive settings & Live Activity**: remove Settings keep-alive mode picker and its note; delete the Dynamic Island Live Activity extension and all ActivityKit session code. Voice sessions stay on silent low-profile PiP only, with user-facing copy that never names Picture in Picture. / **保活设置与灵动岛**：移除设置中的保活方式选项及说明；删除灵动岛 Live Activity 扩展与全部 ActivityKit 会话代码。语音会话仅保留静默低感知 PiP，用户可见文案不再出现「画中画」。
- **Clipboard 30s window & continuous rewrite**: drop the copy-time eligibility clock and multi-turn rewrite session; each long-press is an independent round. / **剪贴板 30 秒窗与连续改写**：去掉复制后资格计时与多轮改写会话；每次长按为独立一轮。

### Fixed
- **Release notes cache**: load the remote What's New page with `reloadRevalidatingCacheData` so edited HTML is not stuck behind WebKit heuristic caching when the host sends no `Cache-Control`. / **更新说明缓存**：远程更新说明用 `reloadRevalidatingCacheData` 回源校验，避免服务器无 `Cache-Control` 时 WebKit 启发式缓存把旧 HTML 卡很久。
- **Clipboard multi-intent commands**: "reply and translate to English" no longer collapses into a plain translation of the clipboard. The command contract now runs every spoken operation in order, translates the previous step's output instead of the material, pins the reply speaker (material "I" is the other party, reply "I" is the user), and rejects a restated material as a reply. / **剪贴板复合指令**：「回复并翻译成英文」不再塌缩成只把剪贴板译成英文。指令契约现按口述顺序执行全部操作，翻译作用于上一步产物而非材料，钉死回复视角（材料里的「我」是对方，回信里的「我」是用户），并禁止把材料复述后当作回复。
- **Clipboard style-bias conflict**: dictation packs' "input is the user's draft, not a message from the other party" and "never answer the transcript" lines are stripped before the pack is injected as tone bias, so the personality can no longer override the reply intent. / **剪贴板风格偏置冲突**：注入语气底色前剔除听写风格包中「输入是用户草稿、不是对方消息」「不回答原文」等语句，避免人格设定压过回复意图。
- **Clipboard prepare stuck**: after the first Allow Paste, do not double-`startRecording`; recover or cancel when host never confirms capture so UI cannot remain on「准备录音…」. / **剪贴板卡在准备录音**：首次「允许粘贴」后不再重复 `startRecording`；宿主未确认采音时及时恢复或取消，避免 UI 一直停在「准备录音…」。
- **Clipboard prepare decision tests**: unit-cover restore/dedupe/adopt/abort matrices (including a 20-round stress case) so paste-alert reopen cannot regress into a second start. / **剪贴板准备态决策单测**：覆盖恢复/去重/领养/中止矩阵（含 20 轮加压），防止粘贴弹窗重开再次双发 start。
- **Clipboard cold-start handoff**: when the host app is not alive, long-press stores a sticky voice+snapshot and opens `startflow` without entering fake「准备录音…」; after return (including default typing → forced voice), the user long-presses again to start blue clipboard recording. / **剪贴板冷启动交接**：宿主未活时长按只保留语音+快照粘性并走 `startflow`，不进入假「准备录音…」；返回后（含默认打字→强制语音）再长按才进入蓝色剪贴板录音。
- **PiP arm re-jump**: keyboard open / Voice-tab appear no longer reopens `startflow` while a session is alive, warming, or within the arm cooldown; force-quit zombies can still arm after an 8s unreachable grace. / **PiP 反复跳转**：会话已存活/预热中或仍在拉起冷却窗内时不再重复 `startflow`；强杀后残留 session 在心跳失联超过 8s 仍可拉起一次。
- **Clipboard prepare chrome**: while waiting for host capture confirm, the mic stays grey and disabled (not blue); blue + side captions appear only after confirmed recording. / **剪贴板准备态视觉**：等待宿主确认采音时麦克风保持灰色不可点（非蓝色）；确认录音后才显示蓝色与两侧文案。
- **Cold capture first-press**: host retries a soft-dead / failed engine start once and rejects `running && !engineLive` as success. / **冷启动首次采音**：宿主对软死/失败引擎自动重建一次，且不把 `running 但无 live` 当作成功。
- **Clipboard paste prompt spam**: idle affordance peeks `hasStrings` only; pasteboard *contents* are read only on long-press, so opening the keyboard no longer repeatedly requests paste permission. / **剪贴板粘贴授权刷屏**：空闲仅探测 `hasStrings`；正文只在长按时读取，打开键盘不再反复申请粘贴权限。
- **Clipboard paste-alert continuity**: survive the system Allow Paste alert without snapping to the typing grid, keep blue clipboard chrome from prepare onward, and ignore the finger-up that follows long-press so stop stays tap-to-finish. / **剪贴板粘贴弹窗连续性**：系统「允许粘贴」弹窗期间不跳回打字键盘；准备阶段即显示蓝色剪贴板态；忽略长按后的抬手，仍需再点结束。
- **Clipboard paste-alert voice sticky**: persist a short App Group prefer-voice + snapshot flag (with `synchronize`) across paste-alert dismiss/recreate so reopen stays on the voice keyboard with blue clipboard chrome instead of the default typing grid / red dictation mic. / **剪贴板粘贴弹窗语音粘性**：用 App Group 短时标记（并 `synchronize`）跨弹窗销毁/重建，重开仍进语音键盘并恢复蓝色剪贴板态，而不是默认打字键盘 / 红色听写麦。
- **Custom polish style editor**: open create/edit with `sheet(item:)` so the form always loads the selected pack instead of a blank default template. / **自定义润色风格编辑**：新建/编辑改为 `sheet(item:)` 呈现，表单始终加载所选风格，而不再偶发显示空白默认模板。

## [1.6.5] - 2026-08-06

### Added
- **Volcengine ASR API Key auth**: settings can switch to the new-console single `X-Api-Key` mode while keeping legacy APP ID + Access Token as the default; SAUC resource is fixed to Doubao streaming 2.0 (`volc.seedasr.sauc.duration`). / **火山 ASR API Key 鉴权**：设置可切换到新控制台单字段 `X-Api-Key`，默认仍为旧版 APP ID + Access Token；SAUC 资源固定为豆包流式 2.0（`volc.seedasr.sauc.duration`）。
- **Custom style mood emoji**: custom polish styles can opt in (default off) to allow emotion-matched emoji; the prompt overrides R5 and post-processing keeps them on screen. Paste-only prompts that declare emoji opt-in are detected automatically. / **自定义风格情绪 emoji**：自定义润色风格可单独开启（默认关）按情绪点缀 emoji；提示词覆盖 R5，后处理保留上屏。仅粘贴声明允许 emoji 的 prompt 也会自动识别。

### Changed
- **Automatic low-profile PiP**: replace the 18 FPS sample-buffer teaching video with a transparent 0.1 pt VideoCall PiP; every host-app open now arms it automatically, keyboard appearance performs one silent handoff when it is absent (including Pinyin/English typing mode), and idle mic UI stays green without PiP startup copy or host overlays. Once active, PiP stops frame rendering, releases the idle audio session, allows screen sleep, and refreshes audio levels only while recording. / **自动低感知 PiP**：用透明且高度仅 0.1pt 的 VideoCall PiP 替换 18 FPS SampleBuffer 教学视频；每次打开主 App 都自动武装，键盘出现且 PiP 缺失时静默跳转一次（包括默认拼音/英文输入模式），空闲麦克风始终保持绿色，不再显示 PiP 启动文案或主 App 浮层。PiP 激活后停止帧渲染、释放空闲音频会话、允许屏幕休眠，并仅在录音时刷新音量。

### Fixed
- **Shared LevelDB privacy manifest**: ship `PrivacyInfo.xcprivacy` inside `OSGKeyboardShared.framework` so App Store Connect no longer rejects uploads for ITMS-91061 (leveldb via librime). / **Shared LevelDB 隐私清单**：在 `OSGKeyboardShared.framework` 内打包 `PrivacyInfo.xcprivacy`，避免 App Store Connect 因 ITMS-91061（librime 内嵌 leveldb）拒收。
- **PiP post-utterance yellow flash**: after a voice turn, the mic no longer briefly shows yellow「正在启动画中画」— hold ready once the session proved live, refresh host ready on ack, and avoid labeling an already-active PiP as `.starting`. / **PiP 句末黄色闪烁**：语音说完后麦克风不再短暂变黄并提示「正在启动画中画」——会话曾就绪后保持绿灯、ack 后立即刷新 host ready，且已激活的 PiP 不再标成 `.starting`。
- **English Shift after Return**: sentence autocapitalization treats newline as a new-line boundary (system keyboard behavior), so Notes-style multi-line Return arms Shift again. / **回车后英文 Shift**：句首自动大写将换行视为新行边界（对齐系统键盘），备忘录等多行回车后会重新点亮 Shift。
- **English Shift with stale proxy**: after our own insert/delete, autocap merges a local caret-prefix shadow when `documentContextBeforeInput` lags (e.g. period / Return in Notes). / **滞后前文下的英文 Shift**：自身插删后若 `documentContextBeforeInput` 滞后，自动大写会合并本地光标前文影子（如备忘录中的句号/回车）。

## [1.6.2] - 2026-08-06

### Changed
- **ASR capture voice processing**: iOS App Flow / preview capture switches from `.measurement` to `.voiceChat`, enables `AVAudioEngine` Voice Processing, and prefers a near-talk built-in mic pattern so competing talkers in the same room are suppressed more strongly (Control Center Voice Isolation remains available once VP is on). / **ASR 采音人声处理**：iOS App 的 Flow / 预览采音从 `.measurement` 改为 `.voiceChat`，打开 `AVAudioEngine` Voice Processing，并优先近讲内置麦指向，以更好压制同房间旁人说话（开启 VP 后控制中心仍可选人声隔离）。

### Fixed
- **Voice toolbar haptics**: delete / space / return on the voice keyboard follow Settings → General → Haptics (mic unchanged). / **语音底栏震动**：语音键盘的删除 / 空格 / 回车跟随设置 → 通用 → 震动（麦克风大圆钮不变）。
- **Haptics after app switch**: re-prepare Taptic when the keyboard appears so feedback does not go cold after switching host apps. / **切 App 后震动消失**：键盘每次出现时重新预热触觉引擎，避免从 A 切到 B 后触感变冷。
- **Typing switch after cold start**: a sticky App Group `hostHeavy` flag no longer silently blocks 中文/EN when the host died mid-warmup; the flag now expires and is cleared on Flow state reset / host relaunch. / **冷启动后无法切拼音/英文**：宿主中途被杀留下的 `hostHeavy` 不再静默挡住中文/EN；该标志会过期，并在 Flow 状态清理与宿主重启时清除。
- **Chinese Shift uppercase**: with Shift / Caps Lock / Shift-hold on in Pinyin mode, letter keys insert Latin uppercase directly (system-keyboard style) instead of sending uppercase keycodes to Rime, which rejects them. / **拼音 Shift 大写**：拼音模式下开启 Shift / Caps Lock / 按住 Shift 时，字母键直接插入大写拉丁字母（对齐系统键盘），不再把大写键码送给会拒绝的 Rime。

## [1.6.1] - 2026-08-05

### Added
- **Personal dictionary → Chinese Pinyin**: adding or deleting terms redeploys an `osg_personal` Rime sidecar (local pinyin from the bundled dict; same-code pin-to-top; Latin names also surface in Chinese mode); English typing and ASR keep using the same dictionary automatically. Takes effect the next time the keyboard opens. / **个性词库 → 中文拼音**：增删词条会重部署 `osg_personal` Rime 旁路词表（复用打包词典本地注音；同码置顶；拉丁专名在中文键盘也可出候选）；英文打字与 ASR 继续自动共用同一词库。下次打开键盘生效。
- **Typing key sound & haptics**: letter / modifier / space / return / delete keys play system click sounds on press-down; Settings → General → Haptics offers Off / Light (default) / Strong role-based feedback. / **打字按键音效与震动**：字母 / 修饰 / 空格 / 回车 / 删除键按下即播系统咔嗒音；设置 → 通用 → 震动提供关 / 轻（默认） / 强 的角色分层触感。
- **Typing touch accuracy (Phase 1–3)**: gap-filling hit regions (no dead seams), grid-level down → move → up tracking with slide-to-reselect, release-to-commit for letters/space/return, press-and-repeat delete, and a light upward touch intent offset. / **打字触控准确率（Phase 1–3）**：热区填缝（无死区）、网格级按下→滑动改选→松手确认、字母/空格/回车松手提交、删除按下连删，以及轻微向上的触点意图偏移。
- **Pinyin next-key bias (Phase 4)**: during full-pinyin composition, ambiguous seam hits prefer legal next letters (capped boost/shrink); clear on-key hits and English / double-pinyin stay unbiased. / **拼音下一键偏心（Phase 4）**：全拼组词中，缝隙歧义命中优先合法后续字母（有上下限）；明确落在键上的点击以及英文/双拼不受偏置。

### Changed
- **Rime personal-dict import**: SharedSupport now imports `osg_personal` into `osg_pinyin` (resource version `2.3.0`). / **Rime 个性词导入**：SharedSupport 将 `osg_personal` 导入 `osg_pinyin`（资源版本 `2.3.0`）。
- **Two-level polish intensity**: Light is the default and restores full fidelity, question, and insertion-context safeguards for fun styles; Heavy keeps the formatting-only creative path for Dating, Flex, Corp, Diba, and XHS. / **两档润色强度**：默认轻度，为趣味风格启用完整保真、问句与落点上下文守卫；重度保持直男癌、装逼、大厂、帝吧和小红书仅格式化后执行人格的创意链路。
- **Built-in polish style JSON**: ship each built-in personality as `Resources/PolishStyles/*.json` plus a manifest; the loader strips the retired fun-foundation placeholder while the composer owns the single shared formatting layer. / **内置润色风格 JSON**：每个内置人格改为 `Resources/PolishStyles/*.json` + manifest；加载器移除已退役的趣味共享占位符，唯一共享格式化层由 Composer 负责。
- **Dating V6 alignment**: restore heartbeat goals, action definitions, chat paragraphing, and the “吃饭了吗” example in `builtin.dating.json`; practical safeguards no longer override those Dating instructions. / **直男癌对齐 V6**：在 `builtin.dating.json` 恢复终极目标、心动动作定义、聊天分段与「吃饭了吗」示例；实用润色守卫不再覆盖 Dating 指令。
- **Polish prompt pipeline**: restore builtin style personalities and per-style intensity guidelines; inject custom packs with priority over generic cleanup; keep sparse hard-brakes only in conservative/fallback modes; strengthen Clear Structure paragraphing guidance; remove unused `globalContract` wiring. / **润色提示词管线**：恢复内置风格人格与分风格力度细则；自定义包优先于泛化清理口吻；稀疏硬刹车仅在保守/降级模式注入；加强清晰结构分段指引；移除未使用的 `globalContract` 假接线。
- **Bounded Flow latency**: ASR drain, batch recovery, and polish now use finite stage budgets; available raw transcription is inserted when optional polish cannot finish in time. / **Flow 有界延迟**：ASR 收尾、整段补偿与润色现采用分阶段时限；可选润色未及时完成时直接上屏已有原始转写。
- **Dating polish quality**: route care, availability checks, concrete invites, praise, longing, apologies, and pressure separately; add controlled per-utterance variation and absolute short-message length budgets, with deterministic local fallbacks when the model violates intent. / **直男癌润色质量**：分别路由关心、档期询问、明确邀约、赞美、想念、道歉与施压场景；增加按单次语音变化的受控多样性和短消息绝对长度预算，模型改意图时由本地确定性兜底。

### Fixed
- **Polish homophone repair**: strengthen shared T3 for contextual 同音/近音 fixes, enforce correct-then-style ordering in one LLM pass, and keep dictionary hints from replacing general correction rules. / **润色同音纠错**：加厚共享 T3 的上下文同音/近音修复，在单次 LLM 内强制先纠后润，并避免词典段顶掉一般纠错规则。
- **Translation paragraph structure**: translation prompts enforce hard structure rules with few-shot correct/wrong examples so flat ASR enumerations become blank-line paragraphs and `1. 2. 3.` lists instead of one collapsed block. / **翻译段落结构**：翻译提示词改为硬结构规则 + 正误 few-shot 示例，使平铺 ASR 列举重建为空行分段与 `1. 2. 3.` 列表，避免压成单段。
- **Bluetooth Flow capture**: serialize PiP/recording audio work off the main thread, wait for a stable input and first frame before ASR, and ignore format-stable route notifications instead of rebuilding every utterance. / **蓝牙 Flow 录音**：在主线程外串行执行 PiP/录音音频操作，等待输入路由与首帧稳定后再进入 ASR，并忽略格式未变化的路由通知，避免每次语音都重建引擎。
- **Reliable Flow delivery**: preserve rapid start/stop commands, make utterance termination idempotent, and recover unacknowledged final results after keyboard-extension recreation. / **Flow 可靠交付**：保留快速按下/松开命令，确保单次语音仅有一个终态，并在键盘扩展重建后恢复未确认的最终结果。

## [1.6.0] - 2026-08-04

### Removed
- **In-keyboard onboarding overlay**: first-run setup lives only in the host app; the keyboard no longer mounts the multi-step enable/permission guide. / **键盘内引导遮罩**：首次设置仅在主 App 完成；键盘不再挂载多步启用/权限引导。

### Changed
- **Voice setup gate**: until host onboarding finishes, typing stays available; tapping mic (or Flow cold-start) shows a hint and opens OSGKeyboard. / **语音设置门禁**：主 App 引导完成前仍可打字；点麦克风（或 Flow 冷启动）会提示并跳转 OSGKeyboard。
- **Host memory hybrid Flow**: after onboarding, Rime then CLM run serially under an RSS gate (~120 MB); ASR warms on first mic press instead of session activate. / **宿主混合 Flow 内存策略**：引导完成后按序执行 Rime→CLM 并受 RSS 门闩（约 120 MB）约束；ASR 改在首次按麦时预热，不再随会话激活叠峰。
- **HostSupport framework split**: ASR / CLM / CloudASR / Charts / StoreKit move to `OSGKeyboardHostSupport`; the keyboard extension no longer links those SDKs or embeds the heavy Rime/CLM/license assets. / **HostSupport 框架拆分**：ASR / CLM / CloudASR / Charts / StoreKit 迁入 `OSGKeyboardHostSupport`；键盘扩展不再链接这些 SDK，也不再内嵌大型 Rime/CLM/许可证资源。
- **Typing stack lazy load**: voice surface skips `TypingSessionController` until typing; engines and English lexicon load on enter and unload on leave. / **打字栈懒加载**：语音面不提前创建 `TypingSessionController`；引擎与英文词表进入打字面再加载，离开时卸载。
- **Host↔extension coexistence**: App Group `hostHeavy` blocks typing prepare while the host is doing heavy work; Rime redeploy uses full integrity check only when forced. / **宿主与扩展共存**：宿主重活期间 App Group `hostHeavy` 阻止打字 prepare；Rime 仅在强制重部署时做完整校验。

### Fixed
- **Volcengine ASR validate**: settings connection check handshakes only (no silence transcribe), so valid APP ID / Token no longer fail with “Socket is not connected”. / **火山 ASR 验证**：设置页连接检查仅握手鉴权（不再推静音转写），有效 APP ID / Token 不再误报「Socket 未连接」。
- **Cold-start overlay above keyboard**: the bottom gradient and status copy now track keyboard overlap so “Voice could not start” stays on the opaque band instead of floating over Home content. / **冷启动浮层跟键盘**：底部渐变与状态文案随键盘 overlap 上移，「语音暂时无法启动」留在不透明渐变带上，不再裸叠首页内容。
- **App Group under XCTest**: unsigned test hosts no longer `fatalError` on bare `AppGroupStore()`; speech-history cloud push skips when the suite is missing so one trap cannot abort the whole process. / **XCTest 下 App Group**：未签名测试宿主上裸构 `AppGroupStore()` 不再 `fatalError`；语音历史云推送在 suite 缺失时直接跳过，避免一次 trap 拖垮整进程。
- **Keychain under unsigned XCTest**: when SecItem returns `errSecMissingEntitlement` (-34018) with XCTest loaded, fall back to a process-local map so Keychain/API-key tests stay hermetic. / **未签名 XCTest 下 Keychain**：SecItem 返回 `-34018` 且已加载 XCTest 时回退进程内映射，保证 Keychain/API Key 用例可稳定跑通。
- **Polish output validation**: re-enable hard-violation retry + `minimalPolish` fallback (temporary diagnostic bypass removed). / **润色输出校验**：恢复硬违规重试与 `minimalPolish` 回退（移除临时诊断旁路）。
- **English manual Shift priority**: autocapitalization no longer clears a user-armed Shift, so mid-sentence names stay capitalizable; letter keys show uppercase while Shift / Caps / hold is active. / **英文手动 Shift 优先**：自动大写不再清掉用户点亮的 Shift，句中人名可正常大写；Shift / Caps / 按住时字母键显示大写。
- **Dual enterTypingMode**: typing prepare runs once from the keyboard controller (not again from `TypingRootView.onAppear`). / **双重 enterTypingMode**：打字 prepare 仅由键盘控制器触发一次，不再在 `TypingRootView.onAppear` 重复执行。
- **Keyboard startup layout crash**: initialize cursor-layout dependencies before applying the preferred surface, make early layout callbacks safe, and remove startup `layoutIfNeeded()` re-entry that caused a deterministic `SIGTRAP`. / **键盘启动布局崩溃**：在应用首选界面前初始化光标布局依赖，安全处理提前到来的布局回调，并移除启动阶段 `layoutIfNeeded()` 重入，修复必现的 `SIGTRAP`。
- **Foreground capture jetsam**: opening the host no longer auto-starts continuous mic capture; idle background capture is released so the keyboard can cold-start (`KVC.init`). / **前台录音 jetsam**：打开宿主不再自动开启连续麦克风采集；后台空闲时释放采集，让键盘能冷启动（出现 `KVC.init`）。
- **Host CLM packaging + deferred warmup**: ship Custom Language Model assets in the iOS app bundle (folder reference) and delay Rime/CLM ~45s so they no longer race keyboard cold start. / **宿主 CLM 打包与延后预热**：CLM 资源以文件夹方式打进 iOS App，并将 Rime/CLM 延后约 45 秒，避免与键盘冷启动抢内存。

### Added
- **Voice pipeline performance tests**: hermetic PCM→ASR→guard→polish→bridge stage timings (`./Scripts/run-tests.sh perf`); included in `all`, not in `pr`. / **语音管线性能测试**：合成 PCM→ASR→guard→润色→bridge 分阶段耗时（`./Scripts/run-tests.sh perf`）；纳入 `all`，不进 `pr`。
- **Grouped hermetic test suite**: `Tests/suite-manifest.json` plus `./Scripts/run-tests.sh` run presets (`pr` / `all` / `api` / `keyboard` / …) or atomic groups without duplicating XCTest classes; CI uses `pr` (includes ExtTests). / **分组固定测试集**：用 `Tests/suite-manifest.json` 与 `./Scripts/run-tests.sh` 按预设（`pr` / `all` / `api` / `keyboard` / …）或原子组运行，测试类不重复归属；CI 默认跑 `pr`（含 ExtTests）。
- **Cloud ASR + Flow policy regressions**: streaming/HTTP fixtures, Alibaba vocabulary cache, moonshot local-fallback routing, and Shared Flow keyboard decision helpers (warming / re-adopt / command gate). / **云端 ASR 与 Flow 策略回归**：流式/HTTP fixture、阿里词汇缓存、Moonshot 本地回退路由，以及 Shared 层键盘 Flow 决策（warming / 重附着 / 命令门控）。
- **Streaming ASR event parsers**: Bailian / OpenAI realtime reducers and Volcengine binary frame round-trip fixtures; translation chip 2.5s poll-protection policy is Shared-tested. / **流式 ASR 事件解析**：百炼 / OpenAI Realtime reducer 与火山二进制帧 round-trip fixture；翻译芯片 2.5 秒轮询保护策略下沉 Shared 并单测。
- **Shift hold continuous caps**: press and hold Shift to type uppercase until release (does not enter Caps Lock). / **按住 Shift 持续大写**：按住 Shift 可持续输入大写，松手结束（不进入 Caps Lock）。
- **English autocomplete & prediction**: English mode reuses the candidate bar for prefix completions, high-confidence autocorrect (with ⌫ / original-candidate undo), and next-word suggestions backed by an offline lexicon plus personal dictionary boosts. / **英文补全与预测**：英文模式复用候选栏，提供前缀补全、高置信自动纠错（⌫ / 原文候选可撤销）以及下一词建议；离线词表结合个人词典加权。
- **Chinese more-candidates panel**: when composing Chinese with ≥2 candidates, a ▼ expands a same-height scrollable grid (~80 candidates) over the key area; selecting or ▲ collapses without growing the keyboard. / **中文更多候选面板**：中文组词且候选 ≥2 时，▼ 在同高度内展开可滚动候选网格（约 80 条）覆盖按键区；点选或 ▲ 收起，不增高键盘。
- **Remember last input surface**: optional setting under Default to Text Input; when on, the keyboard reopens on the voice or typing surface left last time. / **记住上次输入界面**：在「默认进行文字输入」下新增可选开关；开启后，下次打开键盘保持上次离开时的语音或文字界面。

### Changed
- **Chinese curly quotes on 123**: Simplified Chinese numbers page uses `“ ”`; corner brackets `「」` moved to `#+=`. / **中文弯引号**：简体中文 123 页使用 `“ ”`；直角引号 `「」` 移至 `#+=`。
- **123 / #+= punctuation by language**: Chinese mode uses iOS Simplified Chinese punctuation (e.g. `：；（）￥“”。，、？！【】「」《》`); English mode keeps the iOS US set and drops the extra Chinese-only fourth row. / **123 / #+= 标点按语言区分**：中文模式对齐 iOS 简体中文标点（如 `：；（）￥“”。，、？！【】「」《》`）；英文模式保持 iOS 美式键位，并去掉多余的中文第四行。
- **Expanded candidate chrome**: drop per-cell fills for row hairlines, enlarge the ▼/▲ hit target, and disable layout animation on expand/collapse to reduce tap lag. / **展开候选样式**：去掉每格白底改行间细分割线，加大 ▼/▲ 热区，并关闭展开/收起布局动画以减轻点击卡顿。
- **Expand/collapse responsiveness**: collapsed bar shows at most 10 candidates; ▼ sits in a `safeAreaInset` outside the horizontal ScrollView; QWERTY stays mounted under an opacity toggle so expand does not rebuild the key grid. / **展开/收起跟手**：收起顶栏最多 10 个候选；▼ 用 `safeAreaInset` 放在横滑外；QWERTY 以透明度显隐保留，避免展开时重建键区。
- **Candidate expand UX**: ▼ uses a translation-style opaque white/dark chip in an HStack (no overlay on text); the expand panel is a recycled UIKit `UICollectionView` of plain labels instead of SwiftUI Buttons. / **候选展开体验**：▼ 改为翻译按钮式不透明白底圆片并放在 HStack 内（不再盖住文字）；展开面板改用可复用的 UIKit 纯文字网格，替代大量 SwiftUI Button。
- **Product docs & licenses**: README, GitHub Pages, and in-app third-party licenses now describe Chinese/English typing capabilities and disclose the OSG-owned English lexicon notice. / **产品文档与许可**：README、GitHub Pages 与 App 内第三方许可现说明中英打字能力，并披露 OSG 自有英文词表说明。
- **Typing delete hold-repeat**: Chinese/English ⌫ shares the voice toolbar’s repeating delete engine (tap once, hold to accelerate). / **打字删除连按**：中英文 ⌫ 与语音工具栏共用连删引擎（点按一次，长按加速连续删除）。
- **English personal hotwords**: English suggestions only load Latin personal-dictionary terms (and English aliases), filtering out Chinese entries. / **英文个性热词**：英文建议仅加载拉丁文个人词条（及英文别名），自动过滤中文词。
- **Unified bottom key widths**: Chinese, English, and voice surfaces now use matching compact side keys with a wider flexible center key. / **统一底栏键宽**：中文、英文与语音界面现统一为两侧窄键、中间宽键。
- **Rime candidate page size**: menu `page_size` / snapshot limit raised to 80 so the expand panel can show a mobile-scale candidate pool (redeploy via resource version `2.1.0`). / **Rime 候选页大小**：`page_size` / 快照上限提升至 80，供展开面板展示移动端规模候选池（资源版本 `2.1.0` 触发重新部署）。
- **Rime candidate depth & progressive chars**: bridge iterates the full candidate list (up to ~160 shown), and for incomplete multi-syllable input places phrase completions before first-syllable characters (e.g. 中国 then 中 for `zhongg`); resource version `2.2.0`. / **Rime 候选深度与渐进单字**：桥接遍历完整候选列表（展示约 160 条），未完成多音节输入时词组补全排在首音节单字前（如 `zhongg` 先中国后中）；资源版本 `2.2.0`。

### Removed
- **English long-press accents**: removed grey key-cap hints and the accent popup strip after poor feel in practice. / **英文长按扩展字符**：实测手感不佳，已移除键帽灰字提示与长按弹出条。
- **English idle next-word bar**: candidate suggestions no longer appear until at least one letter of the current word is typed. / **英文空闲下一词栏**：未输入字母时不再显示候选；至少输入一个字母后才出现补全。

### Fixed
- **Defer CLM/Rime until after onboarding**: Custom LM compile and Rime deploy no longer run from `App.init` / welcome flow (host was hitting ~150 MB then signal 9). / **引导后再做 CLM/Rime**：Custom LM 编译与 Rime 部署不再在 `App.init`/欢迎流程执行（此前宿主约 150 MB 后被 signal 9 杀掉）。
- **Keyboard idle cold-start**: opening the keyboard no longer auto-launches `startflow` when a stale Flow session dies without a mic press (host ASR warmup was jetsamming the extension). / **键盘空闲冷启动**：无麦克风意图时，残留 Flow 会话失效不再自动跳 `startflow`（避免宿主 ASR 预热把扩展 jetsam）。
- **Gesture-delay scan scope**: `disableSystemGestureDelays` only walks the extension’s own view tree, not the host window. / **手势延迟扫描范围**：仅遍历扩展自身视图树，不再扫宿主 window。
- **English autocapitalization**: Shift arms automatically at field start and after sentence terminators, respecting the host field’s autocapitalization type. / **英文自动大写**：在输入框开头与句末标点后自动点亮 Shift，并遵循宿主输入框的自动大写类型。
- **Default text-input flash**: apply the preferred surface before mounting SwiftUI so “Default to Text Input” no longer briefly shows the voice UI first. / **默认文字输入闪跳**：在挂载 SwiftUI 前应用首选界面，开启「默认进行文字输入」后不再先短暂闪过语音界面。

## [1.5.0] - 2026-08-03

### Added
- **Rime typing surface**: keyboard extension adds Chinese/English QWERTY with phrase candidates, full pinyin, Microsoft/Sogou double pinyin, user learning, and opt-in fuzzy pairs; the top-right tab switches back to the voice-first surface. / **Rime 打字表面**：键盘扩展新增中英 QWERTY、词组候选、全拼、微软/搜狗双拼、用户词频学习与可选模糊音；右上角按钮可切回语音主界面。
- **macOS direct download**: bilingual README and GitHub Pages download areas now offer a signed, notarized macOS DMG alongside the iPhone / iPad App Store badge, using matching two-line badge designs. / **macOS 直接下载**：中英文 README 与 GitHub Pages 下载区在 iPhone / iPad App Store 徽章旁新增已签名、公证的 macOS DMG，并统一采用双行徽章样式。
- **Beams hero**: radiant noise-warped beam array (React Bits–style, vanilla Three.js) with the shared demo preset (26 beams, 208° rotation) and OSG green light. / **Beams Hero**：放射状噪声光束阵列（React Bits 风格，原生 Three.js），采用分享的演示预设（26 束、208° 旋转）与 OSG 绿色灯光。
- **Platform download badges**: matching App Store and macOS badges on bilingual READMEs and the website, with localized copy and platform-specific links. / **平台下载徽章**：中英文 README 与官网采用统一样式的 App Store、macOS 徽章，并提供本地化文案与平台专属链接。
- **Website SEO & AI discovery**: richer meta/JSON-LD/FAQ, `llms.txt`, sitemap, and bilingual single-page landing. / **官网 SEO 与 AI 发现**：强化 meta/JSON-LD/FAQ、`llms.txt`、sitemap，以及双语单页落地站。
- **Context-aware polish safeguards**: polish can use a redacted cursor-neighborhood snapshot for natural continuation, validates protected terms and identifiers, retries once, and falls back to a conservative local cleanup when needed. / **上下文润色护栏**：润色可使用经截断脱敏的光标附近文字自然衔接，并校验受保护词与标识符；失败时重试一次，仍不合格则降级为本地保守清理。
- **Pause-aware chunk polish**: chunked ASR carries detected silence boundaries into the polish request while keeping previews and final output marker-free. / **分块停顿感知润色**：分块 ASR 将检测到的静音边界传入润色请求，实时预览与最终输出均不会显示内部标记。
- **True streaming cloud ASR**: Bailian, Volcengine, and OpenAI Realtime use one utterance-level WebSocket with live partials; Volcengine enables official two-pass (`enable_nonstream`) so interim text stays on-screen while definite ASR feeds polish. / **真流式云端 ASR**：百炼、火山与 OpenAI Realtime 按整句长连接推流并实时上屏；火山开启官方二遍识别（`enable_nonstream`），interim 仅上屏，definite 再送润色。
- **Streaming ASR badge**: settings ASR provider chip shows 【流式识别】 for Bailian, Volcengine, and OpenAI. / **流式识别标签**：设置里 ASR 供应商对百炼、火山、OpenAI 显示【流式识别】。
- **Fun polish styles**: new subcategory with Flex Guide, Corp Speak, and DiBa Logic alongside Dating Coach. / **趣味润色风格**：新增小分类，含装逼指南、大厂黑话、帝吧大神，并与直男癌拯救器同组。
- **Xiaohongshu Sisters style**: fun polish pack that rewrites drafts into a strong, fact-grounded sisterly RED note with a topic hook and scannable short paragraphs. / **小红书集美风格**：趣味润色包，将草稿直接改写为强风格、事实保真的姐妹向小红书笔记，并使用贴题钩子与易扫读短段。
- **Delete day in History**: each day header has a Delete action with confirmation to clear that day's transcripts only (iOS and Mac). / **历史按天删除**：日期行右侧提供删除按钮，确认后仅清除当天记录（iOS 与 Mac）。
- **Mac Settings translation target**: polish-provider section includes “Polish then translate” with the same locale picker as Home / menu bar. / **Mac 设置翻译目标**：润色（LLM）分区新增「润色后翻译」，与首页 / 菜单栏同一套目标语言选择。

### Changed
- **Strong polish by default**: remove the Light / Medium / Heavy setting and its persisted/cloud-synced state; every style now executes its strongest fact-safe interpretation in one prompt. / **默认强润色**：移除轻度 / 中度 / 深度设置及其本地与云同步状态；每种风格现在都在单个 Prompt 中执行事实安全范围内的最强版本。
- **Unified keyboard chrome**: voice, Chinese, and English now share a 281-point height, aligned native action keys, a tappable OSG wordmark that opens the host app, a compact translation menu, and an adaptive green Send key. / **统一键盘外观**：语音、中文与英文现统一为 281 点高度及对齐的原生操作键；OSG 横向标志可点击打开主 App，翻译入口改为紧凑菜单按钮，发送键使用自适应绿色。
- **Native-style typing keyboard**: voice, Chinese, and English now share one top-right segmented control that yields to active candidates; keys are taller, rounder, adapt to light/dark mode, use filled Shift state and native press feedback, while only the first candidate is highlighted. / **原生风格打字键盘**：语音、中文与英文共用右上角分段切换，组词时让位给候选栏；键帽更高、更圆并适配深浅模式，Shift 选中改为实心并增加原生按压反馈，仅首候选高亮。
- **Platform-aware third-party licenses**: About now lists the complete iOS Rime/dictionary stack with readable bundled dependency notices, while iOS and macOS hide components they do not ship. / **分平台第三方许可**：「关于」现在完整列出 iOS Rime 与词库依赖及可阅读的传递依赖许可，并在 iOS、macOS 分别隐藏未随该平台分发的组件。
- **Landing page single surface**: remove separate install / compare / Mac / English content pages from navigation; keep one bilingual home page with in-page anchors, and leave thin redirects for old URLs. / **官网收成单页**：导航去掉独立的安装 / 对比 / Mac / 英文专题页，保留双语首页与页内锚点，旧 URL 仅保留轻量跳转。
- **Hero stays dark**: the beams hero background, overlay, and light text stay on the dark stage in light mode too, matching night mode. / **Hero 固定暗色**：白天模式下 Beams Hero 底色、遮罩与浅色文字仍保持与黑夜一致的暗色舞台。
- **Website download actions**: App Store and source buttons now share a compact rounded-rectangle shape and matching height instead of mixing badge and pill silhouettes. / **官网操作按钮**：App Store 与源码按钮统一为等高的紧凑圆角矩形，不再混用徽章与胶囊轮廓。
- **Layered bilingual polish prompts**: transcripts are sent once as user data; stable Chinese/English core rules, style policies, dictionaries, and runtime context now have explicit responsibilities for better consistency and provider prefix caching. / **分层双语润色提示词**：转写仅作为用户消息发送一次；稳定的中英文核心规则、风格策略、词典和运行时上下文职责明确，提升一致性并支持服务商前缀缓存。
- **Two-tier short polish skip**: ultra-short (≤4 CJK) still skips the LLM; 5–10 CJK now skips only low-value acks/closings (e.g. “好的我知道了”), while questions and contentful shorts still polish. / **两级短句跳过润色**：≤4 字仍跳过 LLM；5–10 字仅对低价值确认/收束语跳过（如「好的我知道了」），问句与有内容短句仍走润色。
- **Single-pass polish pipeline**: each selected style now contributes only its personality to one composed prompt; the obsolete router file, duplicated style-card prompts, embedded Core boilerplate, soft validation telemetry, style remapping, dedicated degrade blocks, and second LLM retries are removed. Ultra-short practical/chat acknowledgements may still use deterministic local cleanup without calling the model. / **单次润色链路**：用户选择的风格现在只向单个组合 Prompt 提供人格；移除废弃 Router 文件、重复风格卡 Prompt、内嵌 Core 样板、软校验遥测、风格重映射、专属降级块与第二次 LLM 重试。实用/日常风格的极短确认语仍可直接使用确定性本地清理，不调用模型。
- **Practical polish prompts**: Light Clean / Structured / Formal / Daily Chat share a “transcript-only, not a chatbot” boundary; Structured gains active itemization, light semantic reorder, and paragraphing hard rules inspired by high-readability polish patterns. / **实用润色提示词**：轻度清理 / 清晰结构 / 正式表达 / 日常聊天统一「只整理转写、非聊天助手」边界；清晰结构加强积极分项、轻度语义重排与分段硬规则，提升长口述可读性。
- **RED Note keeps the draft's audience**: the Xiaohongshu style no longer opens with 姐妹们/集美们 or adds comment CTAs unless the draft already addresses a group, and a positive draft can no longer be rewritten with an 避雷-style hook. / **小红书不再擅自加受众**：除非原文本身在对一群人说话，否则不再添加「姐妹们/集美们」开场与评论区互动话术；正面体验也不会被写成「真诚避雷」式钩子。
- **Style-specific forbidden-items chapters**: every built-in polish prompt now has a dedicated `# 禁止事项` section modeled on Daily Chat—no interlocutor replies, no answering question drafts—with per-style bans (e.g. dating must not turn asks into verdicts; flex/corp must not answer as the other party; XHS must not invent product claims). / **风格专属禁止事项**：全部内置润色提示词均新增「# 禁止事项」章节，结构对齐日常聊天（禁接话、禁代答问句），并按风格补充专属禁令（如直男癌不得把征求意见改成评价；装逼/黑话不得替对方作答；小红书不得编造功效细节）。
- **Settings hierarchy**: General is now the first Daily entry; Text Input and its opt-in default-surface switch live under Keyboard & Gestures, while ASR and LLM configuration links remain below the transcription choices. / **设置层级**：「通用」现为「日常」首项；「文本输入」及默认进入文字键盘的开关移入「键盘与操作」，ASR 与 LLM 配置入口仍位于转写选项下方。
- **Transcription option rows**: local and cloud choices now use the same text-first list-row style as the rest of Settings, without leading icons. / **转写选项行**：本地与云端选项移除前置图标，统一采用设置页的文字优先列表样式。
- **Simplified style cards and summaries**: polish-style cards drop decorative badges, and speech-configuration summaries show only the active engine or provider/model without redundant status prefixes. / **简化风格卡与摘要**：润色风格卡移除装饰图标；语音配置摘要仅显示引擎或服务商/模型，不再附加冗余状态前缀。
- **Mac polish style grid**: cards drop decorative icons and use a denser adaptive grid (about three columns at the default window; two when narrower, four+ when wider). / **Mac 润色风格网格**：卡片去掉装饰图标，并以更密的自适应网格排布（默认窗口约三列；变窄两列、变宽四列及以上）。
- **OpenAI ASR default**: cloud OpenAI ASR defaults to `gpt-realtime-whisper` for streaming; batch transcription remains the fallback. / **OpenAI ASR 默认**：云端 OpenAI ASR 默认 `gpt-realtime-whisper` 走流式；批处理转写仍作降级。
- **Dating Coach prompt**: spoken WeChat first with clever lines only as seasoning; refreshed examples to reduce copywriting AI tone. / **直男癌拯救器提示词**：以口语微信为主、巧思仅作点缀；刷新示例以降低文案式 AI 腔。
- **Unified card-page layout**: Settings, polish styles, and related detail pages now share 20-point page margins, section labels, and card chrome. / **统一卡片页面布局**：设置、润色风格及相关详情页共用 20 点页面留白、分组标题和卡片外观。

### Fixed
- **macOS menu-bar dictation delivery**: menu-bar sessions now retain the external target app before the popover takes focus, use that app for polish context and local bias, and reactivate it before pasting. / **macOS 菜单栏听写投递**：菜单栏会话会在弹窗抢焦点前保留外部目标应用，并将其用于润色上下文与本地偏置，粘贴前重新激活目标应用。
- **macOS recording and clipboard fallback**: cancelling microphone preparation no longer lets an untracked button task restart recording; clipboard restoration waits longer, preserves newer third-party writes, clears an originally empty clipboard correctly, and Accessibility failures explain that the transcript remains available for manual paste. / **macOS 录音与剪贴板降级**：取消麦克风准备后，未跟踪的按钮任务不会再次启动录音；剪贴板恢复延长等待时间、保留第三方较新的写入、正确还原原本为空的剪贴板，并在辅助功能权限失败时明确提示可手动粘贴识别结果。
- **Polish validator false positives**: slash-form dates, fractions, and words such as `and/or` are no longer treated as hard-protected file paths; confirmed ordinal ASR repairs also stop polluting missing-number telemetry. / **润色校验误报**：斜杠日期、分数及 `and/or` 等词不再被误判为文件路径硬违规；已确认的序号 ASR 修复也不再污染数字缺失遥测。
- **Transient chunk loss**: a failed middle ASR chunk now retries once with the same PCM before the serial worker advances, preventing brief network failures from silently removing several seconds of speech. / **瞬时分块丢字**：中段 ASR 分块失败后会使用同一份 PCM 原地重试一次，再继续串行处理，避免短暂网络抖动静默丢失数秒语音。
- **macOS Option release freeze**: finishing a live snapshot stream no longer calls `AsyncStream.Continuation.finish()` while holding the recorder lock — the termination handler re-entered the same `NSLock` on the main thread and wedged the app when the hold-to-talk key was released. / **macOS 松开 Option 卡死**：结束实时 snapshot 流时不再在持有 recorder 锁的情况下调用 `AsyncStream.Continuation.finish()`；终止回调会在主线程重入同一把 `NSLock`，松开听写键时导致整个 App 无响应。
- **macOS dictation HUD layout storm**: the floating pill no longer reassigns its hosting view and forces a synchronous relayout on every view-model tick (~20×/s from the level timer); it uses a fixed panel size and lets SwiftUI refresh through `@ObservedObject` instead. / **macOS 听写浮层布局风暴**：悬浮胶囊不再在每次 view-model 更新时重建 hosting 视图并强制同步重排（音量定时器约 20 次/秒）；改为固定面板尺寸，由 SwiftUI `@ObservedObject` 驱动刷新。
- **Polish never answers the transcript**: fun styles (dating / flex / corp) could turn “你觉得这个包怎么样” into a reply such as “还行，挺顺眼的”. A top-priority “polish only, never answer” rule now sits in the global contract, every built-in style pack, the prompt safety boundary, and a router question guard that keeps question drafts as questions. / **润色不再代答转写内容**：趣味风格（直男癌/装逼指南/大厂黑话）曾把「你觉得这个包怎么样」润色成「还行，挺顺眼的」。现已在全局契约、全部内置风格包、提示词安全边界与路由问句守卫四层加入最高优先级的「只润色、不作答」规则，问句必须仍是问句。
- **Daily-chat short replies**: chat polish forbids interlocutor-style continuations on ultra-short drafts (e.g. “嗯” no longer becomes “嗯，我在呢”). / **日常聊天短句接话**：日常润色禁止对极短草稿做对方口吻续写（如「嗯」不再变成「嗯，我在呢」）。
- **Card corner consistency**: the seven-day chart and shared usage cards now use the same continuous 20-point corners as the other Home cards; shared Settings cards also clip child backgrounds to their border shape. / **卡片圆角一致性**：最近 7 天图表及共享统计卡改用与首页其他卡片一致的连续 20 点圆角；共享设置卡片也会将子视图背景裁切到边框形状。
- **PiP mic spin-up drop**: on record press, open capture and the utterance gate before waiting for audio proof, and keep ~3 s of idle preroll so speech during mic warm-up is not discarded. / **PiP 开麦丢音**：按下录音后先启动采集并打开 utterance gate，再等待音频证明；空闲 preroll 约 3 秒，避免麦克风预热期间的语音被丢掉。
- **Empty preMerge wipe**: final-chunk preMerge that returns empty text no longer removes a prior good segment; ASR pipeline failures also recover via partial snapshot instead of clearing it. / **空 preMerge 抹字**：末块 preMerge 若识别为空，不再删除已有有效片段；流水线失败时改用 partial 快照恢复，而不再清空兜底。
- **History day label alignment**: date headers line up with the history card's left edge like Settings section labels. / **历史日期对齐**：日期标题与下方卡片左边缘对齐，与设置页分组标题一致。

## [1.0.1] - 2026-07-27

### Fixed
- **Onboarding Done stuck**: finishing step 6 no longer wraps the route change in an animation transaction; `MainAppRoot` force-swaps view identity so Settings replay cannot freeze on the last page. / **引导完成卡住**：第六步完成不再包进动画事务；`MainAppRoot` 强制切换视图身份，避免从设置重走引导后停在最后一页。
- **PiP closed loop**: activate a playback audio session before creating `AVPictureInPictureController`, never treat “armed but inactive” as success, and restore playback audio after releasing the mic between utterances so Home `hostReady` matches a real PiP window. / **PiP 闭环**：在创建画中画控制器前先激活 playback 音频会话，不再把「已武装但未激活」当成功，并在句间释麦后恢复 playback，使首页就绪状态与真实 PiP 窗口一致。
- **Onboarding after reinstall**: fresh installs clear the durable Keychain onboarding flag via a container install identity so delete-and-reinstall shows the welcome flow again. / **重装后引导**：通过容器安装身份在全新安装时清除 Keychain 引导标记，删除重装后会再次显示欢迎流程。
- **Cloud engine footer**: Home / preview status lines name the configured ASR provider and model instead of the polish LLM. / **云端引擎文案**：首页与预览状态行显示已配置的 ASR 服务商与模型，而不再显示润色 LLM。
- **PiP Flow handoff**: wait for the PiP host view, distinguish real start failures, and stop pointing users at a non-existent Settings toggle; cold-start / keyboard copy now match Picture in Picture keep-alive. / **PiP Flow 交接**：等待 PiP Host 就绪、区分真实启动失败，并不再引导不存在的系统设置开关；冷启动与键盘文案对齐画中画保活。
- **PiP start reliability**: restore unconditional `startPictureInPicture` retries, live `positiveInfinity` time range, DisplayImmediately sample buffers, and arm auto-inline PiP for background; Home status footer uses a bottom inset so the adaptive preview field shrinks instead of sitting under the tab dock. / **PiP 启动可靠性**：恢复无条件 `startPictureInPicture` 重试、直播 `positiveInfinity` 时间范围、DisplayImmediately 帧，并武装后台自动画中画；首页状态行改为 bottom inset，由自适应输入框让位，避免被 Tab 遮挡。
- **PiP / Live Activity exclusivity**: Picture in Picture sessions no longer start or refresh Live Activities. / **PiP / 灵动岛互斥**：画中画会话不再启动或刷新灵动岛 Live Activity。
- **Flow tail ASR drop**: after mic stop, iOS Flow now uses a longer silence drain (350 ms), a fixed 150 ms post-roll, expanded final-chunk ASR recovery, and a partial transcript guard so weak trailing syllables are less likely to disappear from the result. / **Flow 尾音识别丢失**：松手后 iOS Flow 采用更长的静音排空（350 ms）、固定 150 ms 尾音保留、增强末块 ASR 恢复与 partial 兜底，降低弱尾音从结果中消失的概率。
- **Flow batch ASR fallback**: when pipelined chunk output is clearly shorter than the live partial, the host re-transcribes the full utterance PCM captured during recording (Mac-style safety net). / **Flow 整句 ASR 兜底**：流水线拼接结果明显短于实时 partial 时，主 App 对录音期间累积的整段 PCM 重新识别（对齐 Mac 双保险）。

### Changed
- **Unified navigation icons**: iPhone History and Personal Dictionary tabs now use the same SF Symbols as the Mac and iPad sidebars. / **统一导航图标**：iPhone 的历史记录与个性词库 Tab 现使用与 Mac、iPad 侧边栏一致的 SF Symbols。
- **Mac header actions**: personal-word and polish-style add buttons now match the adjacent search field height and use a consistent capsule shape. / **Mac 页头操作**：添加个性词与添加润色风格按钮现与相邻搜索框等高，并统一使用胶囊外形。
- **Responsive Mac polish styles**: replace fixed full-width style rows with iOS-aligned adaptive cards that reflow with the window width. / **Mac 润色风格响应式布局**：将固定通栏列表改为对齐 iOS 的自适应卡片，并随窗口宽度自动重排。
- **Mac MLX tail drain**: streaming capture now uses the shared `FlowUtteranceEndCoordinator` (silence drain + post-roll) instead of an inline poll loop. / **Mac MLX 尾音排空**：流式采集改用 Shared 层 `FlowUtteranceEndCoordinator`（静音排空 + post-roll），替代内联轮询循环。
- **Default Flow keep-alive**: new installs default to Picture in Picture instead of Dynamic Island. / **默认 Flow 保活**：新安装默认使用画中画，不再默认灵动岛。

### Added
- **Mac personal words**: add custom dictionary terms on macOS with automatic recognition-alias generation and iCloud sync. / **Mac 个性词**：可在 macOS 添加自定义词条，自动生成识别别名并通过 iCloud 同步。
- **Polish style packs**: choose a complete writing personality from the new iOS tab or Mac sidebar, create custom prompts, and sync selections and custom styles through iCloud. / **润色风格包**：可在 iOS 新 Tab 或 Mac 侧栏选择完整写作人格、创建自定义提示词，并通过 iCloud 同步选择与自定义风格。
- **PiP Flow keep-alive**: Settings → Voice session lets you choose **Picture in Picture** (default) or **Dynamic Island** — a live waveform PiP keeps the host alive with the mic released between utterances; closing PiP ends the session. / **PiP Flow 保活**：设置 → 语音会话可选 **画中画**（默认）或 **灵动岛** — 实时波形 PiP 保活、句间释麦；关闭 PiP 即结束会话。
- **Mac MLX streaming ASR**: local dictation uses Qwen3-ASR via mlx-audio-swift with overlay partial preview, tail drain, vocabulary prompt, and polish-before-insert. / **Mac MLX 流式 ASR**：本地听写改用 mlx-audio-swift 的 Qwen3-ASR，支持浮层 partial 预览、尾部截断、词库 prompt 与润色后再插入。

### Changed
- **Privacy-safe Flow timeout**: new sessions default to a 5-minute inactivity window, with new 1-minute and 5-minute options in Settings; previous 30-/10-minute product defaults migrate once. / **更安全的 Flow 超时**：新会话默认在无活动 5 分钟后结束，设置中新增 1 分钟与 5 分钟选项；旧的 30/10 分钟产品默认会一次性迁移到 5 分钟。
- **Cloud ASR privacy disclosure**: permission prompts and the bundled privacy policy now explain that audio stays on-device by default and is sent to the configured speech provider only after cloud recognition is enabled. / **云端 ASR 隐私说明**：权限弹窗与内置隐私政策现明确说明音频默认在设备端处理，仅在启用云端识别后发送至用户配置的语音服务商。
- **Mac local ASR engine**: removed Sherpa offline CLI; default model is Qwen3 MLX 0.6B 4-bit (1.7B optional download). / **Mac 本地 ASR 引擎**：移除 Sherpa offline CLI；默认模型改为 Qwen3 MLX 0.6B 4-bit（1.7B 可选下载）。
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
- **Permission pre-prompt CTA**: onboarding / Home buttons use Next instead of Allow before the system microphone and speech dialogs (App Store 5.1.1(iv)). / **权限引导按钮**：系统麦克风与语音识别弹窗前的引导/首页按钮改为「下一步」，不再使用「允许」（App Store 5.1.1(iv)）。
- **Model download for China networks**: add the `hf-mirror.com` mirror as the mainland-China-first source (bypasses the flaky HF Xet backend), drop the dead ModelScope link, and correct the model file list; add automatic resume-on-drop retry with cross-mirror fallback and a manual "Download source" picker in Settings. / **国内网络模型下载**：新增 `hf-mirror.com` 镜像并在中国大陆优先（绕开不稳定的 HF Xet 后端），删除失效的 ModelScope 链接并修正模型文件清单；下载中断自动断点续传重试并在镜像间回退，设置里新增手动「下载源」选择。
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
