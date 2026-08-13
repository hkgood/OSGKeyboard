# Changelog

All notable changes to OSGKeyboard will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Skills tab**: Home dock and iPad sidebar add Skills between Home and Styles; cards list default Reply / Summarize / Translate plus installable export skills (max 8 enabled, long-press drag to reorder). / **技能 Tab**：首页 Dock 与 iPad 侧栏在「首页」和「风格」之间新增「技能」；卡片列出默认的回复 / 总结 / 翻译以及可安装的出口技能（最多启用 8 个，长按拖动排序）。
- **Extract tasks skill**: the Skills tab opens a ready-made companion Shortcut named `OSG · 提取待办` on the system Add page (split lines → Reminders, default list). After you tap Add, copying text and tapping Tasks asks the LLM for to-dos and silently adds them; no tasks stays in the current app with a keyboard tip. / **提取待办技能**：技能页会打开已做好的配套捷径 `OSG · 提取待办` 的系统添加页（按行拆分并写入默认提醒清单）。点添加后，复制文字并点「待办」会让模型抽取待办并静默写入；没有待办则留在当前 App，键盘上给出提示。
- **Extract events skill**: the Skills tab opens a ready-made companion Shortcut named `OSG · 提取日程` on the system Add page (multiple events into Calendar; date-only → all-day, time-only → today, optional end time and location). After you tap Add, copying text and tapping Events asks the LLM for events and silently adds them; no date or time stays in the current app with a keyboard tip. / **提取日程技能**：技能页会打开已做好的配套捷径 `OSG · 提取日程` 的系统添加页（可多条写入日历；只有日期为全天；只有时刻用当天；可带结束时间与地点）。点添加后，复制文字并点「日程」会让模型抽取日程并静默写入；没有日期或时间则留在当前 App，键盘上给出提示。
- **Navigate skill**: the Skills tab opens a companion Shortcut named `OSG · 导航`. After you add it, copying text and tapping Navigate asks the LLM for one address (or origin → destination) and opens driving directions — Amap if installed, then Baidu Maps, then Apple Maps. No address stays in the current app with a keyboard tip. / **导航技能**：技能页打开配套捷径 `OSG · 导航`。添加后，复制文字并点「导航」会抽取一条地址（或起点→终点）并开始驾车导航——已装高德则用高德，否则百度，再否则 Apple 地图。没有地址则留在当前 App，键盘上给出提示。
- **Skills clipboard guide**: when Clipboard History is off, the Skills tab shows a card that jumps to in-app Clipboard settings and to iOS Settings for paste authorization. / **技能页剪贴板指引**：未开启剪贴板历史时，技能页展示可点击卡片，分别跳转 App 内剪贴板设置和系统设置以完成粘贴授权。
- **Custom skills**: Skills tab `+` adds a user skill (name, about, SF Symbol, prompt, required iCloud Shortcut link with name lookup, independent Shortcut name, thinking off by default). Built-in thinking stays off and disabled. No cap on how many custom skills you can save; the keyboard still holds at most 8. / **自定义技能**：技能页右上角 `+` 可添加用户技能（名称、介绍、SF Symbol、提示词、必填 iCloud 捷径链接并自动读取名称、可与技能名分开的捷径名、思考默认关）。内置技能思考固定关闭且不可开。自定义数量不设上限，键盘仍最多启用 8 个。

### Fixed
- **Extract tasks Shortcut**: receive Shortcut Input as Text, then split lines and add each title to Reminders — the previous recipe could finish successfully without creating items. / **提取待办捷径**：先把快捷指令输入收成文本，再按行写入提醒；旧配方会成功跑完但不创建条目。
- **Skill reorder feedback**: long-press lifts a skill card and the grid slides live under the finger, matching Home Screen rearrange. / **技能拖动排序**：长按拎起技能卡片，网格随手指实时让位，接近主屏幕图标重排。
- **Skill drag preview corners**: the lift preview clips to the card’s continuous rounded rect so square white corners no longer show. / **技能拖动圆角**：拖起预览按卡片连续圆角裁剪，去掉圆角外的直角白底。

### Changed
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

### Fixed
- **Clipboard skills jumped to a sentence chip**: copying no longer swaps the three skill buttons for a leftover carousel card such as “translate the clipboard”. Clipboard sentence cards stay out of the idle rotation. / **剪贴板技能跳成句子芯片**：复制后不再把三个技能按钮换成「把剪贴板翻译成…」这类旧轮播卡片；剪贴板句子不再进入空闲轮播。
- **Clipboard skill status XML**: tapping Reply / Summarize / Translate no longer flashes the internal `<clipboard_request>` envelope above the mic. / **剪贴板技能状态 XML**：点回复 / 总结 / 翻译不再把内部 `<clipboard_request>` 信封闪现在麦克风上方。
- **Idle keyboard re-adopted recognition**: aborting a session now remembers that utterance id, so a lagging host `processing` snapshot cannot reopen the voice keyboard in 「识别中」. / **空闲打开误进识别中**：中止会话会记住该句 id，滞后的主机 processing 快照不会在下次打开语音键盘时显示「识别中」。
- **Voice cancel chrome until result**: Cancel (X) stays up through ASR/polish and through abort wait after leaving AI Agent, so the voice mic no longer looks ready while the host is still busy. / **语音取消直到出结果**：X 一直保留到识别/润色结束，以及离开 AI Agent 后的中断收尾；语音麦克风不再在宿主仍忙时显示为可用。
- **Empty double-tap skip**: a mic press shorter than 300 ms with near-silence (or no samples) is discarded before ASR, so accidental double taps no longer wait on a no-speech error. / **空连点跳过**：按下短于 300ms 且接近静音（或尚无样本）的录音在进入识别前丢弃，避免误触后长时间等待「没听清」。
- **AI hint left the mic stuck**: prefilled AI questions now drop the host processing gate after the answer or error; consuming an ack for the live utterance also heals a leaked gate. Reopening the keyboard only aborts when App Group already acked that utterance and the result is gone — a live LLM/ASR wait with no result yet is left running. Cancel during generate no longer delivers the answer afterwards. / **AI 建议卡住麦克风**：预填 AI 问题在出答案或失败后会关掉宿主 processing 闸门；若键盘已 ack 当前句而闸门仍开着，宿主消费 ack 时一并放闸。再次打开键盘仅在 App Group 已 ack 且结果已空时才中断残留闸门；LLM/ASR 仍在跑、尚无结果时继续等待。生成中取消后不再把答案写回来。

## [1.7.5] - 2026-08-13

### Added
- **AI idle hint carousel**: AI mode empty state rotates one-line suggestions (local evergreen + optional remote hot topics); tap sends the card prompt to the LLM without the mic. Coexists with the clipboard suggestion strip in the top bar. / **AI 空闲建议轮播**：AI 模式空状态轮播单行建议（内置常驻 + 可选远程热点）；点按即跳过麦克风把卡片 prompt 发给模型。与顶栏剪贴板建议条并存。
- **Hint feed refresh**: main app silently fetches `https://key.osglab.com/hints` about every 12 hours, compresses titles with the user’s polish LLM, and writes App Group ready packs for the keyboard. / **建议源刷新**：主 App 约每 12 小时静默拉取 `https://key.osglab.com/hints`，用用户润色 LLM 压缩标题，写入 App Group 供键盘只读。
- **Clipboard history**: optional keyboard clipboard history (latest 15 plain-text items, App Group local), top-bar clipboard entry, history panel with whitespace token chips, and a suggestion strip across voice / typing / AI when enabled. Within ~30s of a copy, AI idle hints can prefer clipboard-related cards. / **剪贴板历史**：可选的键盘剪贴板历史（最近 15 条纯文本、App Group 本地），顶栏剪贴板入口、带空白分词芯片的历史面板，以及开启后在语音 / 打字 / AI 面显示的建议条；复制后约 30 秒内 AI 空闲建议可偏向剪贴板相关卡片。
- **Clipboard settings**: Settings home adds a Clipboard page under AI Agent with History and Suggestion-strip toggles (both default off); keyboard deep-links open that page. / **剪贴板设置**：设置首页在 AI Agent 下方新增「剪贴板」页，含历史记录与候选栏展示开关（均默认关闭）；键盘可深链打开该页。
- **Paste permission guidance**: the Clipboard settings page explains iOS's durable “Paste from Other Apps” permission and opens iOS Settings directly, so users can set it to Allow once and stop the per-copy paste prompt. / **粘贴授权引导**：剪贴板设置页说明 iOS 的「从其他 App 粘贴」持久授权并可直接跳转系统设置，用户设为「允许」一次即不再每次复制都弹窗。
- **Clipboard settings copy**: shorten history, suggestion-strip, and paste-permission wording to brief user-facing lines. / **剪贴板设置文案**：精简历史、建议条与粘贴授权说明，改为简短面向用户的表述。
- **Settings summary placement**: navigation-row summaries (AI Agent, Clipboard, etc.) sit trailing before the chevron, matching the Version row. / **设置摘要位置**：导航行摘要（AI Agent、剪贴板等）移到右侧 chevron 前，与「版本」行一致。
- **AI answer streaming**: AI mode streams visible answer text into the keyboard as the model writes (all AI-mode transports), with throttled App Group updates, search-fallback draft restart, and a “thinking” status before the first token; dictation polish stays non-streaming. / **AI 回答流式输出**：AI 模式在模型开始写正文后将可见答案增量推送到键盘（覆盖全部 AI 传输路径），经 App Group 节流更新；搜索失败回退会清空半截草稿；首 token 前显示「思考中」；听写润色仍为整段返回。
- **Spoken clipboard requests**: in AI mode, naming the clipboard out loud (“reply to the clipboard”, “translate my clipboard”) now attaches the stored clipboard text to that question. Naming it is the authorization, so no second confirmation appears; every other AI question is still sent without clipboard text, and with Clipboard History off the request fails with a clear reason instead of guessing. / **口述剪贴板指令**：AI 模式中说出「回复剪贴板」「把剪贴板翻译成英文」等，会把已保存的剪贴板正文附加到该问题。说出即视为授权，不再二次确认；其余 AI 提问一律不附带剪贴板；未开启剪贴板历史时会给出明确原因而非自行猜测。
- **AI Agent settings**: Settings home adds an AI Agent row under General, with a Response length preference (Short / Medium / Detailed, default Medium). AI mode injects soft length guidance into the system prompt and syncs the choice via iCloud settings. / **AI Agent 设置**：设置首页在「通用」下方新增 AI Agent 入口，支持「回复篇幅」（简短 / 中等 / 详细，默认中等）。AI 模式将篇幅作为软约束写入 system prompt，并纳入 iCloud 设置同步。

### Changed
- **Home library cards**: History and Personal dictionary leave the bottom dock; Home shows two self-sizing preview cards — transcripts split by hairlines (two lines each) and dictionary terms with their source/usage detail line — that push the existing pages with a standard back button. / **首页资料卡片**：历史记录与个性词库移出底部 Dock；首页改为两张按内容自适应高度的预览卡——历史条目用细线分隔（每条最多两行），词库显示词条与来源/使用次数小字——点按后以标准返回按钮进入原页面。
- **Home scroll status**: engine and session status scroll with the page at the bottom (dock clearance via tab-bar padding) instead of a pinned footer. / **首页滚动状态**：引擎与会话状态随页面滚到底部（Dock 留白与设置页一致），不再钉在底部。
- **Clipboard AI prompt contract**: clipboard text now reaches the model as a separate escaped `clipboard_text` block beside the instruction, and the AI system prompt treats that block as untrusted content instead of instructions. Hint cards carry only the instruction. / **剪贴板 AI 提示词契约**：剪贴板正文改为与指令并列的独立转义 `clipboard_text` 块，AI system prompt 明确将该块视为不可信内容而非指令；建议卡片只保留指令本身。
- **Hint feed freshness**: refresh tracks success per locale (a Chinese success no longer masks an English failure), a manifest failure no longer aborts the packs, and a pack past its `expiresAt` — or older than 48 hours without one — falls back to the built-in evergreen catalog instead of showing stale hot topics. / **建议源新鲜度**：刷新按语言分别记录成功（中文成功不再掩盖英文失败），manifest 失败不再中断整轮；超过 `expiresAt`（或无该字段且超过 48 小时）的建议包回退到内置常驻卡片，不再展示陈旧热点。
- **Privacy policy**: document AI idle suggestions, opt-in clipboard history (panel, suggestion strip, and AI hint use), and when clipboard text is sent to your AI provider. / **隐私政策**：补充 AI 空闲建议、可选剪贴板历史（面板、建议条与 AI 提示用途），以及剪贴板正文在何种情况下会发送给 AI 服务商。
- **Clipboard history row opacity**: history panel entry cards use 50% surface opacity so the keyboard chrome shows through. / **剪贴板历史条目透明度**：历史面板每条记录背景改为 50% 透明度，键盘底色可透出。
- **Translation button chrome**: voice mic-row translation control matches the adjacent undo key (44×44 rounded rectangle) instead of a circular chip. / **翻译按钮样式**：语音麦克风行的翻译控件改为与相邻撤销键一致的 44×44 圆角矩形，不再使用圆形芯片。
- **Undo covers clipboard pastes**: the undo key now rolls back text inserted from the clipboard suggestion strip or history panel, in one step regardless of length. Pasted text stays out of dictation history and is never offered for last-input editing. / **撤销支持剪贴板粘贴**：撤销键现在可回滚从剪贴板建议条或历史面板插入的文字，无论长度都一次撤销到底。粘贴内容不进入听写历史，也不会成为「编辑上次输入」的对象。
- **Undo key label**: rename the accessibility label from “Undo last dictation” to “Undo last input” now that it covers dictation, AI answers, edits and pastes. / **撤销键文案**：无障碍标签由「撤销上次听写」改为「撤销上次输入」，因其现已覆盖听写、AI 答案、编辑与粘贴。
- **Translation chip placement**: move the top-bar translation control onto the voice mic row, mirrored with Undo; the top-bar slot becomes the clipboard button. / **翻译入口位置**：顶栏翻译控件移到语音麦克风行并与撤销对称；原顶栏位置改为剪贴板按钮。
- **AI empty-state tip**: center “Tap the microphone to ask AI” in the answer area (horizontal + vertical); idle state now rotates hint cards there. / **AI 空状态指引**：答案区域水平与垂直居中展示空闲建议轮播（替代静态「点击麦克风」文案）。

### Fixed
- **Clipboard hints missed a fresh copy**: the AI idle carousel now refreshes from the clipboard store as soon as a copy is captured, instead of waiting for the next 4-second rotation or a re-entry into AI mode — the reason clipboard suggestions often never appeared inside their 30-second window. / **新复制无剪贴板建议**：AI 空闲轮播在采集到新复制时立即依据剪贴板刷新，不再等待下一次 4 秒轮换或重新进入 AI 模式——这正是 30 秒窗口内常常看不到剪贴板建议的原因。
- **Reduce Motion froze hint data**: Reduce Motion now only stops the fade rotation. Cards still refresh, so a new copy appears and a card whose clipboard window closed leaves the carousel. / **Reduce Motion 冻结建议数据**：辅助功能「减弱动态效果」现在只停止渐隐轮换，数据仍会刷新：新复制会出现，剪贴板窗口关闭的卡片会退出轮播。
- **Expired clipboard hint tap**: tapping a clipboard card after its 30-second window fails closed with a “copy the text again” message instead of sending the instruction with empty material. / **过期剪贴板建议点击**：超过 30 秒窗口后点击剪贴板卡片会明确提示重新复制，而不是把缺少材料的指令发出去。
- **Blank keyboard on cross-device clipboard**: clipboard-history capture no longer reads `UIPasteboard` on the main thread or during the appear sequence — a Universal Clipboard item still being fetched from another device blocked the main thread for seconds, freezing the keyboard mid-presentation. Reads now run on a background queue, start on the first poll tick after the slide-in, and never overlap. / **跨设备剪贴板导致键盘空白**：剪贴板历史采集不再在主线程、也不再在键盘出现流程中读取 `UIPasteboard`——待从其他设备拉取的通用剪贴板内容会同步阻塞主线程数秒，使键盘卡在呈现过程中。读取改到后台队列、延后到滑入完成后的首次轮询，且不会重叠执行。
- **Keyboard presentation height**: drop the `target − system encapsulated height` priming trick. It read the pre-presentation full-screen height (874 pt on an iPhone) rather than the keyboard slot, clamped our constraint to 0, and lost to the system's required constraint anyway; the surface is now bottom-anchored so a transient over-tall container can never park it above the visible slot. / **键盘呈现高度**：移除「目标高度 − 系统封装高度」的预置技巧。它读到的是呈现前的整屏高度（iPhone 上 874pt）而非键盘槽，把约束夹成 0，且本来就压不过系统的 required 约束；键盘内容改为底部锚定，容器临时过高时不会再被顶到可见区域之外。
- **Undo of long insertions**: caret verification now compares the tail of the inserted text's last line instead of the whole string, so long or multi-line insertions no longer lose undo the moment the host returns a truncated context. / **长文本撤销**：光标校验改为比对插入文本最后一行的尾部而非整段，长文本或多行插入不再因宿主返回截断上下文而立刻失去撤销能力。
- **Undo after editing last input**: a newer insertion now clears the pending edit transaction, so undo rolls back that insertion instead of deleting it and restoring the older edit's original text. / **编辑上次输入后的撤销**：新的插入会清除待撤销的编辑事务，撤销将回滚该次插入，而不再是删除它并还原上一次编辑前的旧文本。
- **AI waiting spinner duplicate**: remove the mini ProgressView beside the AI status caption; the mic button spinner remains the sole loading indicator while recognizing or generating. / **AI 等待转圈重复**：去掉 AI 状态文案旁的迷你 ProgressView；识别/生成中仅保留麦克风按钮上的 loading。
- **AI stream UTF-8 mojibake**: SSE framing now accumulates raw bytes and decodes each line as UTF-8, so Chinese AI answers (e.g. weather) no longer appear as Latin-1 garbage like `ä»å¤©…`. / **AI 流式 UTF-8 乱码**：SSE 行缓冲改为累积原始字节并以 UTF-8 解码，中文 AI 回答（如天气）不再显示为 `ä»å¤©…` 一类 Latin-1 乱码。
- **Local ASR dictionary correction**: apply deterministic personal-dictionary alias correction before iOS Flow branches into dictation polish or AI question handling, so AI mode keeps local transcript optimization while still skipping cloud LLM polish. / **本地 ASR 词库纠错**：在 iOS Flow 分流到听写润色或 AI 问答前统一应用个人词库别名确定性纠错，使 AI 模式保留本地转写优化，同时继续跳过云端 LLM 润色。

## [1.7.0] - 2026-08-10

### Added
- **AI keyboard mode**: add a temporary multi-turn AI surface that sends raw ASR questions to the configured LLM, keeps the latest scrollable answer for review, and uses a two-step white Insert then green Send action in messaging fields; only inserted answers enter history and AI character statistics. / **AI 键盘模式**：新增临时多轮 AI 输入面，将原始 ASR 问题直接交给已配置模型，滚动展示最新答案，并在即时通信输入框中采用先点白色「插入」、再点绿色「发送」的两步操作；只有真正插入的答案会进入历史与 AI 字数统计。
- **AI mode web search**: AI questions use a dedicated transport that enables provider-side search when available (DeepSeek/OpenAI/xAI Responses `web_search`, Qwen `enable_search`, Zhipu/Anthropic/Moonshot tools), forces thinking on, and silently retries without search on failure — polish stays on plain Chat Completions. / **AI 模式联网搜索**：AI 问答走独立传输层，在服务商支持时启用服务端搜索（DeepSeek/OpenAI/xAI Responses `web_search`、通义 `enable_search`、智谱/Anthropic/Moonshot tools），强制开启 thinking，失败则静默无搜索重试；润色仍走普通 Chat Completions。
- **API key setup guidance**: Home shows a tip when the polish LLM key is missing; the keyboard mic line warns above the microphone. Without a key, dictation still inserts raw ASR text. / **API Key 引导**：未填写润色 API Key 时首页显示提示，键盘麦克风上方同步提醒；无 Key 时听写仍插入原始识别结果。

### Changed
- **User-owned polish keys only**: remove the built-in DeepSeek `PreconfiguredKeys` fallback. Local and cloud polish (and AI mode) require a user-filled API key; AI question timeout is 60s. / **仅使用用户 API Key**：移除内置 DeepSeek `PreconfiguredKeys` 回退。本地/云端润色与 AI 模式均需用户自行填写 API Key；AI 问答超时为 60 秒。
- **OpenAI default model**: preset default is now `gpt-5.4-mini` (Responses `web_search` capable). Existing saved model names are unchanged. / **OpenAI 默认模型**：预设改为 `gpt-5.4-mini`（支持 Responses 联网搜索）；用户已保存的模型名不受影响。
- **LLM preset defaults refreshed**: update defaults for Qwen (`qwen-plus-latest`), Zhipu (`glm-4.7-flash`), Moonshot (`kimi-k2.5`), xAI (`grok-4-fast-reasoning`), Gemini (`gemini-3.1-flash-lite`), MiniMax (`MiniMax-M2.7`), SiliconFlow / OpenRouter / CometAPI / CodingPlanX; Anthropic stays on `claude-sonnet-4-6`. Polish and AI mode both resolve the Settings provider/model via the same endpoint helper. / **LLM 预设默认值更新**：通义 / 智谱 / Moonshot / xAI / Gemini / MiniMax 及部分聚合预设已换新默认模型；Anthropic 仍为 `claude-sonnet-4-6`。润色与 AI 模式共用同一套设置中的服务商与模型解析。
- **Privacy policy**: document user-owned LLM keys, AI-mode optional provider web search, and remove built-in DeepSeek wording (in-app + GitHub Pages). / **隐私政策**：说明用户自备 LLM Key、AI 模式可选服务商联网搜索，并移除内置 DeepSeek 表述（App 内 + GitHub Pages）。
- **iPad system globe key**: add the system 🌐 key on both iPad voice and typing surfaces — tap to switch to the next keyboard, long-press to open the system input-mode picker. The key uses UIKit's standard all-touch-events input-mode action and the same SwiftUI chrome as adjacent action keys; iPhone relies on its system-provided switch below the keyboard. / **iPad 系统地球键**：在 iPad 语音面与打字面均新增系统 🌐 键——轻点切换下一个键盘，长按打开系统键盘列表。按键采用 UIKit 标准全触摸事件输入模式动作，并与相邻功能键共用同一套 SwiftUI 键面；iPhone 则使用键盘下方由系统提供的切换入口。
- **iPad typing layout**: the typing keyboard now adapts to iPad — taller 54 pt key rows, a second-row inset that widens in landscape (40 pt) vs portrait (30 pt), a small grey number overlay (1–0) on the top letter row mirroring iOS, and a content-driven height (≈300 pt on iPad vs 281 pt on iPhone) so the bottom row is never clipped. Metrics live in `TypingLayoutMetrics` and are selected from one controller-owned device-idiom + horizontal-size-class decision. / **iPad 打字布局**：打字键盘现已适配 iPad——键行加高至 54pt，第二行缩进在横屏（40pt）比竖屏（30pt）更宽，首字母行叠加 1–0 小号灰数字（对齐 iOS），并改为内容驱动高度（iPad 约 300pt，iPhone 281pt），底部行不再被裁切。尺寸由控制器统一结合设备类型与水平尺寸类判定。
- **Editing toolbar (iPad)**: the typing top bar gains an iOS-style undo / redo / copy / cut cluster on iPad. Undo/redo track the last voice insertion (redo re-applies it); copy/cut read the host selection. Availability is refreshed from `textDidChange` / `selectionDidChange`. / **编辑工具栏（iPad）**：打字面顶栏在 iPad 上新增类 iOS 的撤销/重做/拷贝/剪切簇。撤销/重做跟踪上次听写插入（重做可复原），拷贝/剪切读取宿主选区；可用性随 `textDidChange` / `selectionDidChange` 刷新。
- **Edit last input**: long-press the microphone to describe changes to the last verified OSGKeyboard insertion, then preview and replace or append the validated result without exposing unrelated field text. / **编辑上次输入**：长按麦克风口述对最近一次已验证 OSGKeyboard 输入的修改，预览后可替换原文或追加结果，且不暴露无关输入框内容。

### Removed
- **Clipboard voice commands**: remove the iOS keyboard's long-press clipboard capture, persisted resume state, clipboard prompt pipeline, and related pasteboard access; normal dictation, last-input editing, main-app/macOS copy features, and keyboard copy/cut remain available. / **剪贴板语音指令**：移除 iOS 键盘长按读取剪贴板、持久化恢复状态、剪贴板提示词链路及相关粘贴板访问；普通听写、编辑上次输入、主 App/macOS 独立复制功能与键盘拷贝/剪切继续保留。

### Fixed
- **Focused recording chrome and cancellation**: edit mode now aligns its logo and close button to the same outer inset as the normal voice surface. During normal voice startup, recording, and processing, the capsule tabs and translation button are replaced by a high-visibility cancel button; cancelling aborts ASR and polish and discards any late result. Disabled undo and bottom action keys stay hidden so the live microphone remains the unambiguous focus. / **聚焦录音界面与取消入口**：编辑模式的 Logo 与关闭按钮现与普通语音界面使用相同外边距。普通语音从启动、录音到处理期间，胶囊标签与翻译按钮会替换为高可见度取消按钮；取消会终止 ASR 与润色，并丢弃任何迟到结果。不可用的撤销键和底部操作键保持隐藏，让正在工作的麦克风成为明确焦点。
- **Repeat edit sessions**: completed edits no longer re-adopt stale recording snapshots and enter an eight-second busy quarantine, so the next long-press starts ASR immediately with the latest applied text. The edit surface enlarges its comparison swipe area, shows live ASR text and an audio-level waveform instead of status copy, widens the centred edit microphone into a three-times-wide capsule, and keeps the green “hold to edit” hint visible for ten seconds. / **连续编辑会话**：已完成的编辑不再重新接管过期录音快照并进入八秒忙碌隔离，下一次长按会立即基于最新已应用文本启动 ASR。编辑界面同时扩大对比滑动热区，以实时 ASR 文本与音量波形替代状态文案，将居中的编辑麦克风加宽为原宽度三倍的胶囊按钮，并将绿色“长按编辑”提示延长至十秒。
- **Faster first mic and stable edit review**: each host process performs one bounded post-PiP audio health check (real first-frame proof, one soft-dead rebuild, then release), while touching the main mic primes the same single-flight capture for the imminent tap/hold utterance. Edit review now keeps its Flow identity until confirm/close, deduplicates final results by utterance+revision, and uses native horizontal paging; a simulator XCUITest verifies left/right swipes over the text area. / **更快首录与稳定编辑预览**：每个宿主进程在 PiP 就绪后执行一次有界音频健康检查（真实首帧证明、软死时最多重建一次、随后释放），手指按下主麦克风时则预热同一个单飞 capture，供即将成立的短按/长按 utterance 直接接管。编辑预览在确认/关闭前持续保留 Flow 身份，按 utterance+revision 去重结果，并改用原生横向分页；模拟器 XCUITest 已验证文字区域左右滑动。
- **Unified edit-mode recording**: dictation and last-input editing now share one `FlowUtteranceRequest` start transaction for host handoff, microphone activation, recording confirmation, stop, timeout, and ASR; edit mode no longer pre-allocates a ghost utterance or runs its own confirmation polling. The initiating long press is consumed before switching views, preventing a replayed finger-up from sending `stopRecording`. / **统一编辑模式录音**：普通听写与编辑上次输入现共用同一个 `FlowUtteranceRequest` 启动事务，统一处理宿主交接、麦克风激活、录音确认、停止、超时与 ASR；编辑模式不再预创建幽灵 utterance，也不再维护独立确认轮询。切换界面前先消费发起编辑的长按，避免抬手被重放为 `stopRecording`。
- **iPad keyboard width**: the typing keyboard was clamped to a 700 pt centred column on every device, leaving 67 pt of dead space per side on an 11" iPad in portrait and 247 pt in landscape (51% of the screen on a 13" in landscape), so no key sat where the system keyboard puts it. The cap was a voice-surface ergonomics constraint (`contentMaxWidth`) that the key grid had inherited; it is now voice-only (`voiceContentMaxWidth`) and the typing grid spans the full host width. Letter keys grow from 61 pt to 75 pt wide on an 11" iPad in portrait. / **iPad 键盘宽度**：打字键盘此前在所有设备上都被钳制为 700pt 居中列，11 寸 iPad 竖屏每侧留白 67pt、横屏 247pt（13 寸横屏占屏幕 51%），导致没有一个按键落在系统键盘的位置上。该上限原是语音面的可达性约束（`contentMaxWidth`），却被键盘网格一并继承；现已改为语音面专用（`voiceContentMaxWidth`），打字网格铺满宿主宽度。11 寸 iPad 竖屏字母键宽由 61pt 增至 75pt。
- **iPad keyboard height ignored orientation**: `contentHeight` hardcoded `isLandscape: true` while orientation only fed the second-row inset, so portrait and landscape resolved to an identical 300 pt. Height is now driven by available width (394 pt at iPad landscape widths vs 300 pt in portrait, against roughly 398 pt / 313 pt for the system keyboard), which also fixes `traitCollectionDidChange` never firing on iPad rotation — both orientations are `regular`, so the resize is now picked up in `viewDidLayoutSubviews`. / **iPad 键盘高度不随方向变化**：`contentHeight` 硬编码 `isLandscape: true`，而方向仅用于第二行缩进，横竖屏因此解析出完全相同的 300pt。现改由可用宽度驱动（iPad 横屏宽度下 394pt、竖屏 300pt，系统键盘约为 398pt / 313pt），同时修复 iPad 旋转不触发 `traitCollectionDidChange` 的问题——横竖屏同为 `regular`，改在 `viewDidLayoutSubviews` 捕获尺寸变化。
- **Second-row indent no longer a fixed constant**: the ASDF row used a hardcoded 30 / 40 pt inset tuned for a 700 pt column, which stops reading as a deliberate indent once the grid fills an iPad. It is now derived so second-row keys are exactly as wide as first-row keys, leaving a half key at each end — the system keyboard's own rule, and correct at any width. / **第二行缩进不再是固定常量**：ASDF 行原用为 700pt 列调校的 30 / 40pt 硬编码缩进，网格铺满 iPad 后已无法读作有意的缩进。现改为推导值，使第二行键宽与第一行完全一致、两端各留半个键——即系统键盘自身的规则，在任意宽度下都成立。
- **iPad bottom row gains comma / period**: filling the width turned the phone row's 50% centre fraction into a 663 pt space bar on a 13" iPad in landscape. iPad now uses a six-slot row `[globe · 123 · , · space · . · return]` (9/13/9/38/9/22), spending the extra width on keys the way the system keyboard does; space settles at 432 pt on an 11" in landscape against roughly 430 pt for the system. Punctuation routes through the engine, so a pending composition commits first. / **iPad 底行新增逗号/句号**：铺满宽度后，手机版 50% 的中央比例会使 13 寸 iPad 横屏空格键达到 663pt。iPad 现采用六槽底行 `[globe · 123 · , · space · . · return]`（9/13/9/38/9/22），像系统键盘那样把多出的宽度用于增加按键；11 寸横屏空格为 432pt，系统约为 430pt。标点经由引擎提交，未上屏的编码会先行确认。
- **Voice surface matches the typing surface**: the voice surface also fills the host width, and both surfaces now resolve to one content-driven height, so switching between them no longer resizes the keyboard (a 113 pt jump on an iPad in landscape). Surplus height is parked above the action cluster, keeping its keys on the typing bottom row's baseline. Its bottom row uses a flatter iPad split (10/24/40/26), widening the primary return key without letting the phone's 50% centre fraction hand it ~577 pt at full width. / **语音面与打字面对齐**：语音面同样铺满宿主宽度，且两面现在解析出同一个内容驱动的高度，互相切换不再改变键盘尺寸（iPad 横屏原有 113pt 跳变）。多余高度置于操作簇上方，使其按键与打字面底行保持同一基线；底行在 iPad 上采用更平缓的比例（10/24/40/26），加宽主要回车键，同时避免手机版 50% 的中央比例让其在铺满时达到约 577pt。
- **Layout metrics are now testable**: typing size decisions moved from `TypingRootView` (extension target) into `TypingSurfaceMetrics` (shared), so the UIKit height constraint and the SwiftUI grid provably read the same source and unit tests can cover them without the extension. / **布局尺寸可测**：打字面尺寸决策由 `TypingRootView`（扩展 target）移至 `TypingSurfaceMetrics`（共享层），UIKit 高度约束与 SwiftUI 网格可证明地读取同一数据源，且单测无需依赖扩展即可覆盖。
- **Chinese input never initializes**: the keyboard could show 「请先打开 OSGKeyboard 完成输入法初始化」 indefinitely even after opening the app, because Rime deployment was scheduled only as opportunistic warmup — a 45 s delay that additionally required the app to stay foregrounded and to clear a memory gate, and silently dropped the work otherwise. Deployment is now also run deterministically at the moments the user is actually waiting on it: during the onboarding "Add Keyboard" step (with an inline progress / retry status row), immediately on onboarding completion, and on demand via a new `osgkeyboard://deployrime` deeplink. / **中文输入始终无法初始化**：即使已打开主 App，键盘仍可能长期显示「请先打开 OSGKeyboard 完成输入法初始化」——因为 Rime 部署只作为机会性预热调度：延迟 45 秒，且要求 App 保持前台并通过内存闸门，否则静默放弃。现在在用户真正等待结果的时机改为确定性执行：引导「添加键盘」步骤内（附行内进度 / 重试状态）、引导完成时立即执行，以及通过新增的 `osgkeyboard://deployrime` deeplink 按需触发。
- **Keyboard recovers without a restart**: a keyboard already showing the setup error now retries engine preparation when the host posts its post-deployment App Group notification, and the error text itself became a tappable jump into the host app (only for failures host deployment can actually fix). Previously the error persisted until the user switched surfaces or relaunched the keyboard. / **键盘无需重启即可恢复**：已显示初始化错误的键盘，会在宿主发出部署完成的 App Group 通知后自动重试引擎准备；错误文案本身也变为可点击跳转（仅对确实能由宿主部署修复的故障开放）。此前该错误会一直保留，直到用户切换面板或重新拉起键盘。
- **Rime deployment stays in the host app**: the shared installer now rejects every `.appex` process, and personal-dictionary callbacks skip deployment when invoked by the keyboard extension. Returning users trigger idempotent deployment immediately when the host opens instead of waiting for a 45-second opportunistic warmup. The host now clears its heavy-work flag before notifying the keyboard, so the extension's automatic retry cannot lose the only completion event to stale busy state. / **Rime 部署仅限主 App**：共享安装器现会拒绝所有 `.appex` 进程，个人词库回调若来自键盘扩展也会跳过部署。老用户打开主 App 时立即触发幂等部署，不再等待 45 秒的机会性预热；宿主还会先清除重任务标记再通知键盘，避免扩展自动重试因读到过期忙碌状态而错失唯一完成事件。
- **iPad globe key at bottom-left**: the system 🌐 key now lives at the bottom-left of both iPad surfaces — voice (`KeyboardRootView.micActionRow`) and typing (`TypingRootView.typingKeySurface`) — while iPhone removes the duplicate custom key and redistributes its three remaining actions across the row. UIKit owns the iPad key's complete native tap / long-press event chain, and its visible chrome matches adjacent keys. / **iPad 地球键移至左下角**：系统 🌐 键现位于 iPad 语音面与打字面的最左下角；iPhone 删除重复的自定义地球键，并将剩余三个操作键重新铺满底行。iPad 地球键由 UIKit 完整接管原生轻点/长按事件链，可见键面与相邻按键保持一致。
- **iPad typing height**: `TypingRootView.totalHeight` is now a function `totalHeight(isIPad:)`; `KeyboardViewController` resolves one layout mode from device idiom plus horizontal size class and publishes it to SwiftUI, keeping compact iPad multitasking on phone metrics and wide iPhones off iPad metrics. Trait changes refresh the height constraint so UIKit and SwiftUI stay aligned. / **iPad 打字高度**：`TypingRootView.totalHeight` 改为函数 `totalHeight(isIPad:)`；`KeyboardViewController` 结合设备类型与水平尺寸类统一解析布局模式并发布给 SwiftUI，使 iPad 紧凑分屏使用手机尺寸、宽屏 iPhone 不误用 iPad 尺寸；尺寸类变化时同步刷新高度约束，确保 UIKit 与 SwiftUI 始终一致。
- **iPad sidebar breathing room**: on the iPad / regular-width sidebar, the gap between the brand logo and the first menu item is roughly doubled (brand header bottom padding `Spacing.md` → `Spacing.xxxl`), and each sidebar row is taller with larger text (font 13 → 15, vertical padding 7 → 12) so rows hit the Apple HIG 44pt touch target. / **iPad 侧栏留白**：iPad / 横屏规则宽度侧栏里，logo 与首个菜单项之间的间距大约翻倍（`brandHeader.bottom` 由 `Spacing.md` 改为 `Spacing.xxxl`），每行菜单项更高、字号更大（字号 13 → 15、垂直内边距 7 → 12），行高达到 Apple HIG 44pt 触摸目标。
- **iPad sidebar row alignment**: sidebar titles started at a different x on every row because `Label`'s default style sizes the icon to each SF Symbol's intrinsic width, which ranges from 13 pt (`character.book.closed`) to 17.5 pt (`house`) across this menu — pushing 「键盘」 5.2 pt right of 「词库」. A `LabelStyle` now reserves a uniform 22 pt icon column (the alignment `List` provides for free and this hand-rolled `VStack` sidebar lacked), and the selected row's corner radius moves off a stray hardcoded 7 pt onto the design scale at `Radius.medium` (12 pt). / **iPad 侧栏行对齐**：侧栏各行文字起点不一致——`Label` 默认样式按每个 SF Symbol 的固有宽度排布图标，本菜单内该宽度从 13pt（`character.book.closed`）到 17.5pt（`house`）不等，使「键盘」比「词库」右移 5.2pt。现由 `LabelStyle` 预留统一的 22pt 图标列（`List` 自带、而手写 `VStack` 侧栏缺失的对齐），选中行圆角也从游离的硬编码 7pt 收回设计标度 `Radius.medium`（12pt）。
- **iPad Home hint position**: the keyboard-setup hint (and other flow-session extras) on the iPad / regular-width home view used to render below the usage-stats cards, burying the most actionable guidance beneath the stats. The hint now sits right after the hero header and above the stats, matching the phone layout, so it is the first thing a user notices at the top of the page. / **iPad 首页提示位置**：iPad / 横屏规则宽度首页的「去系统设置添加键盘」提示（以及其他 Flow 会话附注）原本位于使用统计卡片之下，最关键的引导被压在统计之下。现已将其移到 hero 标题与统计卡片之间，与手机端布局一致，使其位于页面顶部最显眼处。
- **Polish never answers a question draft**: dictating 「你能听到我说话吗？」 could come back as 「能听到，你说。」. The never-answer boundary and the question guard now ship with every style, every intensity, and custom packs (heavy fun styles previously bypassed both), question detection covers A-not-A forms such as 「你在不在」, and a deterministic validator rejects any result that stops asking the draft's question and falls back to a local clean of the user's own words. A 800-request live matrix across 10 styles × 2 intensities × 20 short-to-long phrasings now delivers zero answers. / **润色不再代答问句**：口述「你能听到我说话吗？」可能被润色成「能听到，你说。」。现在「不可协商边界」与问句守卫覆盖全部风格、全部强度与自定义风格包（此前重度趣味风格会绕过两者），问句识别补齐「你在不在」等正反问句式，并新增确定性校验：结果若不再是问句则丢弃，回退为用户原话的本地清理。10 风格 × 2 强度 × 20 种长短句式、共 800 次真实模型压测下代答为 0。
- **Polish diagnostics**: `polish.config` now records style, intensity, sampling temperature, and which safeguard layers reached the model, and `polish.skippedLLM` records locally short-circuited utterances. / **润色诊断**：`polish.config` 记录风格、强度、采样温度以及本次真正发给模型的防线层级，`polish.skippedLLM` 记录本地短路的语句。

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
