# OSGKeyboard 1.8.0 更新说明

> 以下为 OSGKeyboard 从 1.6.6 升级至 1.8.0 的关键变化。

## 新功能

### AI Agent

- 语音听写与 AI 问答合并为全新的助手模式：轻点麦克风开始听写，长按麦克风可直接语音提问。
- 新增热点与情境热词，麦克风区域会展示天气、节日、新闻、热搜等建议；点按即可向 AI 获取相关信息。
- AI 回答会实时显示在键盘中，确认后可插入当前输入框；支持的服务商可联网搜索，并在失败时自动回退。
- 仅当原输入框与光标上下文仍然匹配时自动插入 AI 回答；上下文变化时会保留回答，等待用户明确插入或丢弃。
- 设置 → AI Agent 可调节回复篇幅：简短、中等或详细。

### 剪贴板与 AI 技能

- 新增剪贴板历史。在设置 → 剪贴板开启“历史记录”后，可在本机保存最近 15 条纯文本；该功能默认关闭。
- 新增剪贴板建议条。可从键盘顶栏打开历史并点按插入；开启建议条后，最新复制内容会显示在键盘上方。
- 复制文字后约 30 秒内，助手会显示回复、总结、翻译等快捷技能；技能支持分页浏览，并可在技能页调整顺序。
- 新增技能页，最多可将 8 个技能放入键盘。内置技能可提取待办、添加日历日程、存入备忘录，或识别地址后打开高德、百度与 Apple 地图导航。
- 新增自定义 AI 技能，可设置名称、图标和提示词，也可选择连接自己的 iCloud 快捷指令。

### 编辑上次输入

- 编辑入口移至键盘右下角。点按后可口述修改要求、对比原文与编辑结果，并选择替换原文或追加内容。
- 编辑只使用最近一次由 OSGKeyboard 插入且仍可验证的文字，不会读取输入框中的无关内容。

## 全新 App 界面

- iPhone 底部导航重做为“首页 / 技能 / 风格 / 设置”四栏 Liquid Glass Dock，并以绿色胶囊标示当前页面。
- 首页改为信息总览，将使用统计、听写历史和个性词库集中显示为资料卡。
- 技能与润色风格采用统一的卡片式管理：点按选择、右上角编辑、右下角显示启用状态；技能支持长按拖动排序。
- 设置入口重新整理，AI Agent、剪贴板、语音与文字输入等页面更容易找到，并直接显示当前设置摘要。
- iPad 改为侧栏 + 内容区布局；键盘横竖屏均充分利用可用宽度，并加入系统地球键、撤销、重做、复制和剪切等操作。

## 中英文输入全面升级

- 中英文输入均可在本机学习用户的输入习惯、候选频率和选择偏好；设置中可单独清除打字习惯，不会删除个性词库。
- 拼音优化混合简拼排序，并支持 `zh`、`ch`、`sh` 两键简拼。
- 英文键盘新增类 QuickType 候选栏，同时显示原词、纠错和补全；约 4 万词离线词表会结合系统词库、通讯录名称与文本替换提供建议。
- 英文邻键纠错更贴合真实键位，并减少对专名、短词和全大写词的误改；拒绝纠错后会学习保留原词。
- 支持叠指连打、英文双空格句号，以及根据输入框显示前往、搜索、发送、完成、下一项等操作。

## 稳定性、隐私与重要变化

- 听写、AI 回答、编辑结果和剪贴板粘贴可通过统一的撤销操作回滚。
- 修复切换键盘崩溃、中文输入初始化后无法恢复、通用剪贴板导致键盘卡住，以及 AI 会话结束后麦克风不可用等问题。
- 全部内置与自定义润色风格都会保留问句原意，不再把用户的问题改写成回答。
- 设备端语音识别仍为默认选项；AI 使用用户自己配置的服务商与 API Key，不再提供内置 DeepSeek 回退。
- 剪贴板历史默认关闭，内容保存在本机，并仅在用户主动调用技能后发送给所配置的 AI 服务商。
- 长按麦克风现用于向 AI 提问；编辑上次输入改用右下角编辑按钮。旧的长按剪贴板语音指令已由剪贴板历史和快捷技能取代。
- 已安装旧中文名称“待办”或“日程”快捷指令的用户，需要从技能页重新安装 `OSGExtractTodos` 和 `OSGExtractEvents`。
- 已移除空白区域滑动光标及其设置开关。

---

# OSGKeyboard 1.8.0 Release Notes

> Key changes when upgrading OSGKeyboard from 1.6.6 to 1.8.0.

## New Features

### AI Agent

- Voice dictation and AI questions now share one Assistant mode: tap the microphone to dictate, or hold it to ask a question by voice.
- New trending and contextual hotwords surface suggestions for weather, holidays, news, trending topics, and more; tap one to ask AI about it.
- AI answers stream directly into the keyboard for review and insertion. Supported providers can search the web and fall back automatically when needed.
- AI answers insert automatically only while the original field and cursor context still match. If the context changes, the answer is retained for explicit insertion or discard.
- Settings → AI Agent now offers Short, Medium, and Detailed response lengths.

### Clipboard and AI Skills

- New Clipboard History keeps the latest 15 plain-text copies on this device when enabled in Settings → Clipboard. It is off by default.
- A new Clipboard suggestion strip lets you open history from the keyboard, insert an item, or keep the latest copy above the keyboard.
- For about 30 seconds after copying text, Assistant shows quick Reply, Summarize, Translate, and other skills. Skills support paging and can be reordered from the Skills page.
- The new Skills page lets you place up to eight skills on the keyboard. Built-in skills extract reminders, add calendar events, save to Notes, or open navigation in Amap, Baidu Maps, or Apple Maps.
- Custom AI Skills support your own name, icon, and prompt, with an optional iCloud Shortcut connection.

### Edit Last Input

- Edit moves to the bottom-right keyboard button. Describe the change by voice, compare the original and edited text, then replace or append the result.
- Editing uses only the latest verifiable text inserted by OSGKeyboard and does not read unrelated field content.

## A New App Interface

- The iPhone dock is rebuilt around four Liquid Glass destinations: Home, Skills, Styles, and Settings, with a green capsule marking the current page.
- Home becomes an overview of usage statistics, dictation history, and Personal Dictionary cards.
- Skills and polish styles share a card-based interaction: tap to select, edit from the top-right, see enabled status at the bottom-right, and long-press skills to reorder.
- Settings navigation is reorganized so AI Agent, Clipboard, Speech, and Text Input are easier to find, with current summaries shown beside each row.
- iPad adopts a sidebar + detail layout. The keyboard fills the available portrait and landscape width and adds the system globe key, undo, redo, copy, and cut.

## Chinese and English Typing, Rebuilt

- Chinese and English typing learn candidate frequency and selection preferences locally. Typing habits can be cleared without deleting Personal Dictionary entries.
- Pinyin improves mixed abbreviations and supports two-key `zh`, `ch`, and `sh` abbreviations.
- The English keyboard adds a QuickType-style bar for the typed word, correction, and completion. An offline list of about 40,000 words works with the system lexicon, contact names, and text replacements.
- Neighbor-key correction follows the physical keyboard while avoiding unwanted changes to names, short words, and all-caps text. Rejecting a correction teaches the original.
- Overlapping key presses, the English double-space period, and contextual Go, Search, Send, Done, and Next actions make typing feel closer to the system keyboard.

## Stability, Privacy, and Important Changes

- One Undo action now rolls back dictation, AI answers, edits, and clipboard pastes.
- Fixes include keyboard-switch crashes, Chinese input recovery after setup, Universal Clipboard freezes, and a microphone that could remain unavailable after AI sessions.
- Every built-in and custom polish style preserves questions instead of rewriting them as answers.
- On-device speech recognition remains the default. AI uses your configured provider and API key; the built-in DeepSeek fallback has been removed.
- Clipboard History stays off by default, keeps its contents on device, and sends text to the configured AI provider only after you invoke a skill.
- Holding the microphone now asks AI, while Edit Last Input moves to the bottom-right Edit button. Clipboard History and quick skills replace the old hold-to-command clipboard flow.
- If you installed the older Chinese-named Tasks or Events Shortcuts, reinstall `OSGExtractTodos` and `OSGExtractEvents` from the Skills page.
- Blank-area cursor sliding and its Settings toggle have been removed.
