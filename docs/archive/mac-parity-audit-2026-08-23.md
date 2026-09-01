# OSGKeyboard · iOS 完整检查 + macOS 差距与移植建议报告

> **文档状态**：**一次性审计快照（历史存档）**——仅代表 2026-08-23 当时的代码状态，其后 Mac 与 iOS 均有改动（如总览页已改为月度用量日历），不要作为现行文档使用
> **报告日期**：2026-08-23
> **当前版本**：2.0.1（build 90）— `project.yml:51-52`
> **审查范围**：iOS Host (`OSGKeyboard/`, 88 .swift) + iOS HostSupport (`OSGKeyboardHostSupport/`, 29 .swift) + iOS Extension (`OSGKeyboardExt/`, 27 .swift) + Shared (`OSGKeyboardShared/`, 230 .swift) + macOS (`OSGKeyboardMac/`, 39 .swift) + macOS Tests (3 .swift)
> **方法**：只读代码考古，证据来自 `project.yml` 共享 / 排除清单 + 文件结构 + 关键源码摘录 + `CHANGELOG.md`

---

## TL;DR

| 维度 | iOS | macOS | 结论 |
|---|---|---|---|
| 产品形态 | 宿主 App + 自定义键盘扩展 | 单窗口菜单栏 App + 浮动 HUD | **不同形态**——Mac 不是键盘，是"按住 Option 说话→⌘V 注入" |
| 核心流水线 | Flow 跨进程会话 + SpeechAnalyzer | 单一进程 + MLX Audio Qwen3 流式 | **架构不可同构** |
| LLM 润色 | ✅ 完整（`PolishingService`） | ✅ 完整（**直接复用** iOS `PolishingService`） | **完全对齐** |
| 本地 ASR | iOS 26 `SpeechAnalyzer + DictationTranscriber` | **MLX Qwen3-ASR 0.6B/1.7B 4-bit** + Apple Speech 兜底 | **完全不同的技术栈** |
| 云 ASR | 7 家供应商 + 流式 | ✅ **完全对齐**（同 `CloudASRClientFactory`） | **完全对齐** |
| 个人词典 | ✅ | ✅ | **完全对齐** |
| 历史 / 使用统计 | ✅ | ✅（iCloud KVS 共用） | **完全对齐** |
| 润色样式 + 学习 | ✅ | ✅ | **完全对齐** |
| iCloud 同步 | ✅（5 路：设置/词典/历史/使用/样式） | ✅（**5 路全部对齐**） | **完全对齐** |
| 提示页 (Tip) | ✅ | ✅ | **完全对齐** |
| 自定义语言模型 CLM | ✅ UI + 后台 | ⚠️ 后台调用了，**无 UI** | **部分缺失** |
| 剪贴板历史 + AI 技能 | ✅ | ❌ 共享代码已编译但**无 Mac UI** | **完全缺失** |
| AI 提示轮播 / 上下文技能 | ✅ | ❌ 共享代码已编译但**无 Mac UI** | **完全缺失** |
| Flow 跨进程会话 / PiP | ✅ | ❌ | **Mac 形态不需要** |
| 自定义键盘 (Rime/拼音/英文) | ✅ | ❌（`Typing/**` 全排除） | **Mac 形态不需要** |
| OSG 账户 (Sign in with Apple + 积分 + 推荐) | ✅ | ❌ | **完全缺失** |
| App Attest | ✅ | ❌（无对应 entitlement） | **完全缺失** |
| 一方分析 (Analytics) | ✅（108 测试覆盖） | ❌（共享代码已编译但**无任何调用**） | **完全缺失** |
| 助手指令 (Shortcuts) | ✅ | ❌ | **完全缺失** |
| 屏幕唤醒 / 锁 / Live Activity | ✅ | ❌ | **Mac 形态不需要** |

**最关键的发现**：

1. **macOS 复用策略 = 源码级 include**。Mac 不 `import OSGKeyboardShared`——`project.yml:570-602` 把 Shared + HostSupport 的 `.swift` 文件直接编进 Mac target，再用 `excludes:` 列表过滤 iOS-only 文件。**整个框架里没有 `#if os(macOS)` 条件编译**（Mac target 内部有几处 `import AppKit` 守卫，是防御性的）。
2. **LLM 润色、云 ASR、iCloud 同步、本地 ASR 模型管理、模型目录、个人词典、润色样式、提示页、Onboarding——这 9 大块是 iOS / Mac 完全对齐的**。差异主要在"宿主 App 才有"的系统集成（Account、App Attest、Analytics、Shortcuts、Flow 跨进程会话）。
3. **"共享代码已编进 Mac 但零调用"的浪费**：`OSGKeyboardShared/Features/Account/`、`Features/ManagedGateway/`、`Features/Analytics/`、`Services/AIClipboard*.swift`、`Services/AIHint*.swift`、`Services/AIUserSkill*.swift` —— 这些文件编译进了 Mac 二进制但没有任何 Mac 文件引用。**编译器开销 + 二进制体积 + 维护面全白付**。要么真正接进 Mac，要么从 Mac target 排除。
4. **Mac 真正独占的体验是 MLX 流式 ASR**。这是 iOS 受限于 ARM NEON + iOS 26 平台绑定做不到的能力，恰好把 Mac 的 Apple Silicon 算力用足。
5. **移植优先级不应是"把 iOS 全搬到 Mac"**。Mac 是"按住说话→润色→注入"工具，自然形态完全不同。**真正应该补的是：剪贴板 AI、CLM 管理、Account 体系、Analytics。**其他（Flow、自定义键盘）不应该硬塞进 Mac。

---

## 1. iOS 端完整状态

### 1.1 Target 拓扑

| Target | 平台 | 类型 | .swift 数 | 备注 |
|---|---|---|---|---|
| `OSGKeyboard` | iOS 26 | App | 88 | 宿主 App，沙盒、StoreKit、iCloud、App Attest |
| `OSGKeyboardExt` | iOS 26 | App Extension (键盘服务) | 27 | `RequestsOpenAccess: true` |
| `OSGKeyboardShared` | iOS 26 | Framework | 230 | 跨进程共用 + 复用到 Mac |
| `OSGKeyboardHostSupport` | iOS 26 | Framework | 29 | 宿主专用（Speech/AVFoundation/Charts/StoreKit） |
| `OSGKeyboardMac` | macOS 15+ | App | 39 | 菜单栏单窗口，**沙盒关闭**（Accessibility 需要） |
| `OSGKeyboardMacTests` | macOS 15+ | Unit Test | 3 | 挂在 Mac App bundle 内 |
| `OSGKeyboardTests` | iOS 26 | Unit Test | 108 | 覆盖 host + shared + hostsupport |
| `OSGKeyboardExtTests` | iOS 26 | Unit Test | 16 | 覆盖 ext + shared |
| `OSGKeyboardUITests` | iOS 26 | UI Test | — | TestFlight 截图自动化 |

### 1.2 iOS Host App (`OSGKeyboard/`) — 用户可见的所有功能

**导航**：4 Tab (Keyboard / Skills / Styles / Settings) on iPhone；iPad 自动切换到 `NavigationSplitView` + 240pt 侧栏 + `WideStatusFooter`。

**7 大用户场景**：

1. **Onboarding**（`Views/OnboardingExperienceView.swift`）—— 7 步：欢迎 → 权限 → 键盘安装 → 切换引导 → 4-feature 实践（语音/翻译/回复/AI）→ 登录奖励 → 完成。匿名实践用 `OOBEClientInfrastructure` 拿服务器发放的体验金。
2. **Home 仪表盘**（`Views/HomeView.swift:122`）—— 7 天柱状图 + 指标瓦片 + Flow 连接卡 + 词典/历史卡 + 中英文高频词条 chip。
3. **Settings**（`Views/SettingsView.swift:30`）—— 7 个子面板：账户、AI 代理、剪贴板、Locale、润色强度、翻译目标、语音识别、文本润色、通用、关于。NavigationStack + `SettingsRoute` 枚举。
4. **Account Center**（`Views/Account/AccountCenterView.swift:11`）—— 已登录摘要、积分 + 等级、StoreKit 商品列表、购买历史链接、登出 / 删号 (reauth)、推荐链接。下拉刷新。
5. **Polish Styles**（`Views/PolishStylesView.swift:11`）—— 内置/社区/自定义样式网格 + 编辑器 sheet + "从历史学习"按钮。
6. **AI Agent Skills**（`Views/AIAgentSkillsView.swift:12`）—— 已装/未装技能卡，安装调起 `shortcuts://` 或 bundled `.shortcut` 文件。
7. **Legal / 隐私**—— `PrivacyPolicyView` / `OpenSourceLicensesView` / 远程 web view。

**宿主端 Services（`OSGKeyboard/Services/`）** 关键件：

| 文件 | 职责 | LOC 估算 |
|---|---|---|
| `FlowSessionManager.swift` | **唯一拥有者**——AVAudioSession 激活、连续 `.playAndRecord` 捕获、ASR 选择、后处理、`PolishingService` 调用、AI 模式、App Group 写、utterance token、launch reconciliation、start/stop/end session | ~3500 |
| `FlowPictureInPictureController.swift` | PiP keep-alive（`AVPictureInPictureVideoCallViewController` 0.1pt content，no audio session） | — |
| `FlowASRPostProcessor.swift` | 本地引擎转写后处理（`LocalASRTranscriptCorrector.apply`） | — |
| `FlowTerminationCoordinator.swift` | 进程退出时同步释放 mic、结束 LiveActivity | — |
| `FlowAnalyticsOperationRegistry.swift` | 会话级分析去重，订阅 `FlowSessionManager` 事件 | — |
| `RimeDeploymentController.swift` | Rime 资源部署（host-owned） | — |
| `AIAgentShortcutInstaller.swift` | 调起 `shortcuts://` 安装 iCloud 分享的技能 / bundled `.shortcut` | — |
| `OOBEClientInfrastructure.swift` | 匿名 OOBE 体验金客户端 | — |
| `OfficialSkillCatalogRefreshService.swift` | 15 分钟 ETag-aware 刷新 `https://account.osglab.com/v1/content/skills` | — |
| `AIHintRefreshService.swift` | 12 小时静默刷新远程提示包 | — |
| `AnalyticsHostService.swift` | `BGTaskScheduler` 注册 (`com.osgkeyboard.ios.analytics-sync`) + `NWPathMonitor` + 后台 drain | — |
| `HostReturnService.swift` | 解析 `FlowSessionBridge.pendingHostBundleId()` 通过 `HostAppURLRegistry` 重开原 App | — |
| `AppURLHandler.swift` | `UIApplicationDelegate` + `UISceneDelegate`：`osgkeyboard://startflow` / `https://osglab.com/i/...` 通用链接 / `didBecomeActiveNotification` 反弹保留 `sourceApplication` | — |
| `AppPermissions.swift` | `AVAudioApplication.requestRecordPermission` (iOS 17+) + `SFSpeechRecognizer` + `PasteAccessResult` 一次性 `pasteAccessVerified` | — |

**宿主端 Models 关键点**：
- `AppGroupConfiguration` 完整 Codable blob —— 镜像到 App Group + iCloud KVS
- `ProviderConfig` 8 家供应商预设（openai/ark/deepseek/qwen/zhipu/moonshot/siliconflow/groq）

**关键 iOS-only 调用**：
- `UIOpenURLContext.options.sourceApplication` (iOS 26 only) —— 保留源 bundle id（host-return 白名单唯一路径）
- `AVAudioApplication.requestRecordPermission` (iOS 17+)
- `SpeechAnalyzer + DictationTranscriber` (iOS 26 only)
- `OSAllocatedUnfairLock` (iOS 16+)
- iOS 26 Icon Composer (`OSGKeyboard/AppIcon.icon`)
- `UIBackgroundModes: audio` + `BGTaskScheduler`
- `applinks:osglab.com` Universal Links
- `LSApplicationQueriesSchemes` 白名单 50+ 国外 App scheme
- `SKIncludeConsumableInAppPurchaseHistory=true` —— StoreKit 2 一次性商品进历史

**iOS-only entitlements**（在 `OSGKeyboard.entitlements`）：
- App Group `group.com.osgkeyboard.shared`（与扩展共享）
- 两个 keychain-access-groups（shared + iOS-only）
- `aps-environment: $(APP_ATTEST_ENVIRONMENT)` ← xcconfig 注入（debug=development / release=production）
- Sign in with Apple `Default`
- iCloud KVS `$(TeamIdentifierPrefix)com.osgkeyboard.ios`（**单字符串**，非数组 —— 数组会破坏自动签名）
- 音频输入
- 关联域名 `applinks:osglab.com`

**StoreKit 配置**（`OSGKeyboard.storekit`）：4 个消耗型 —— 自愿打赏 `ByRockyACoffee` (¥28) + 3 档账户积分 `500tks/1500tks/3000tks` (¥8/¥18/¥28)。**无订阅**。

### 1.3 iOS HostSupport 框架 (`OSGKeyboardHostSupport/`)

设计原则：**唯一**链接 `Speech / AVFoundation / Charts / StoreKit` 的 iOS 框架——键盘扩展**不**链接它，把 jetsam 预算留给 Shared。

**子目录**：

| 路径 | 内容 |
|---|---|
| `Services/` | ASR + 云 ASR + Flow 捕获 + Dictation + Tip + `CloudASR/` + `Tip/` |
| `Models/` | `AudioBufferSnapshot+AVFoundation.swift` —— `AVAudioPCMBuffer` ↔ 共享 `AudioBufferSnapshot` 适配 |
| `DesignSystem/` | `SevenDayUsageChart` + `UsageStatsCluster` + `SupportDeveloperSection` |
| `Features/Account/` | `AccountAPIClient` / `SignInWithApple` / `DeviceIntegrity` (App Attest) / `HostPrivateAccountKeychain` / `AccountModels` / `OOBEGrantProvisioningCoordinator` |

**关键 Services**：

- **`ASRService.swift:1`** —— 公共协议 `transcribe(stream:locale:)` 返回 `AsyncStream<ASREvent>` (`.capability/.partial/.final/.error`)；`transcribeChunk(samples:locale:)` 用于流水线 Flow 路径。`ASRServiceFactory.make(store:)` 返回 `SpeechAnalyzerASR`（本地）或 `CloudASRService`（云）。`SpeechAnalyzerASR` 用 **iOS 26 `SpeechAnalyzer + DictationTranscriber` + bundled `SFCustomLanguageModelData`**，锁用 `OSAllocatedUnfairLock`，支持流水线 chunk 复用。
- **`CloudASRService.swift:1`** —— 云 ASR 前门。`CloudASRClientFactory.make(...)` 返回 8 个客户端：`ZhipuCloudASRClient` / `AlibabaFunASRClient` / `BailianRealtimeASRClient` / `VolcengineCloudASRClient` / `OpenAIRealtimeASRClient` / `PromptCloudASRClient` / `ManagedVolcengineASRClient` / `UnsupportedCloudASRClient`。
- **`LiveDictationController.swift:1`** —— `@MainActor ObservableObject`，阶段机 `idle/recording/processing/denied/error`，自管 `AVAudioEngine + AVAudioSession`。生产键盘**不**用它，**生产用 `FlowSessionManager + FlowContinuousCapture`**。
- **`FlowAudioSessionCoordinator.swift:1`** —— 进程级 `AVAudioSession` + Flow 的 `AVAudioEngine` 拥有者。`.voiceChat` 模式。
- **`CustomLanguageModelManager.swift`** —— 单例，准备 bundled `OSGKeyboardCLM.bin` 写进 App Group。指数退避 30s/120s/600s。**重到 `MainAppRoot.scheduleCLMWarmup` 延后 45s 启动，Flow 忙时拒绝运行**。

**HostSupport 持久化**：
- CLM 编译产物 → App Group container
- Account 令牌 → host-only keychain（**不**走 App Group）
- Managed AI 凭证 → 单独 `GatewayGrantKeychainStore`；**只**镜像"会话可用"布尔进 App Group
- Tip 计数 → 标准 `UserDefaults`

### 1.4 iOS Keyboard Extension (`OSGKeyboardExt/`)

**入口**：`KeyboardViewController.swift:33-38` —— `@objc(KeyboardViewController) @MainActor` `UIInputViewController`。**单一** `KeyboardState` ObservableObject。

**生命周期（`KVC.swift`）**：
- `init` → 启动 `KeyboardExtensionMemoryTelemetry`（warning 36MB / safe 40MB / critical 48MB）
- `viewDidLoad` (`:148-207`) → 设 `showsSystemGlobeKey = isPad`、`primaryLanguage = "mis"`（隐藏"English"副标题误导），读 `TypingInputConfiguration.preferredSurfaceOnOpen()`，调 `refreshLayoutMode() + installKeyboardHeight() + configureDictationBehavior() + installServices() + installSwiftUI()`
- `viewWillAppear` (`:256-293`) → 标记 `KeyboardSetupBridge.markExtensionAppearance(hasFullAccess:)`、刷新 Flow/config、同步 onboarding、准备 `KeyboardHapticFeedback` generators
- `viewIsAppearing/viewDidAppear` (`:295-356`) → 锁高度 `lockPresentedKeyboardHeight()`，禁系统手势延迟，记录 analytics
- `viewWillDisappear` (`:209-254`) → 通知 `AnalyticsExtensionService.keyboardWillDisappear()`、取消 `assistantFieldActionRefreshTask`、使 `editHintScheduler` 失效、持久化最后 surface
- `textDidChange/selectionDidChange` → `refreshReturnKeyRole`、同步 English 文档上下文
- `didReceiveMemoryWarning` (`:390-404`) → **取消流水线、退出 typing 模式、强制回 voice surface** —— typing 引擎是最大内存消费者

**`installServices` (`:419-547`)** 安装的 8 个 coordinator：
- `EditHintScheduler`（mic 上方一句话提示）
- `KeyboardTextInserter`（插入 Flow 转写 / undo / redo / 粘贴剪贴板）
- `KeyboardConfigSync`（App Group 配置 + Darwin observers + onboarding 镜像）
- `KeyboardFlowCoordinator`（Flow start/stop + session monitor + watchdogs）
- `LastInputEditCoordinator`（长按 → 编辑上次输入）
- `AIKeyboardCoordinator`（长按 → AI 模式）
- `ClipboardCaptureCoordinator`（`changeCount` 轮询，secure-field 抑制，建议条）
- `AnalyticsExtensionService`

**`installStateActions` (`:551-655`)** 装的 30+ action：`beginRecording/endRecording/tapMic/cancelVoiceInput/beginEditLastInput/.../setMode/setLocale/setEngineMode/setTranslationTargetLocaleId/insertNewline/insertSpace/deleteBackward/undoLastInsertion/redoLastInsertion/copySelection/cutSelection/setSurface`

**手势模型**：
- 长按 push-to-talk → `RecordButtonGesturePolicy` 阈值 `longPressDuration = 0.45s`
- 点击 mic → 切换（`RecordButton.tapAction`）
- 重复删除 → `RepeatingPressButton` + `RepeatingDeleteTiming`（80→50→30→15 ms 加速）
- Shift 长按 → `TypingSessionController.shiftHeld`，双击 capsLock
- 语言切换 → 3-tab `KeyboardInputTab`（assistant / 中文 / 英文）
- 触觉 → `KeyboardHapticFeedback`（5 个 Taptic generator + 4 个按键角色 + `KeyboardHapticIntensity` off/light/strong）
- 声音 → `UIDevice.playInputClick()` + 系统音 1155 (delete)，通过 `@retroactive UIInputView: UIInputViewAudioFeedback` 启用点击声
- 主题 → 始终深色（`Palette.dark` 是 canonical）

**iOS-only 扩展调用**：`UIInputViewController` / `UIInputView` / `UITextDocumentProxy` / `NSExtensionContext` / `UIPasteboard.general` / `UIImpactFeedbackGenerator` / `UIDevice.playInputClick()` / `AudioServicesPlaySystemSound(1155)` / `UIButton` / `UICollectionView` + `UICollectionViewCompositionalLayout` / `UIHostingController<KeyboardSurfaceRoot>`

**Host/Extension 边界数据**（`AppGroupPersistor.load(into:)` 读取）：
- `providerId` / `baseURL` / `apiKey`（`Keychain.apiKeyOutcome` 解析 shared keychain `$(AppIdentifierPrefix)com.osgkeyboard.shared`）
- `model` / `modeId`（恒为 `polish`）/ `localeId` / `engineMode`（local/cloud）
- `translationTargetLocaleId` / `handednessPreference`（左/右手 delete↔space 互换）/ `clipboardHistoryEnabled` / `clipboardCandidateBarEnabled`
- `keyboardHapticIntensity` / `clipboardSkillSnapshot`（启用技能 ID）/ `apiKeyAvailability`

**`KeyboardConfigSync` (`KeyboardConfigSync.swift:24-62`)** 安装 4 个 `FlowSessionDarwinObserver`：`session.changed` / `command.changed` / `transcription.changed` / `host.ready.changed`

### 1.5 iOS Shared Framework (`OSGKeyboardShared/`)

**目录**：

| 路径 | 内容 |
|---|---|
| `Constants/AppGroup.swift` | App Group ID 唯一源 |
| `Core/Configuration/` | `ConfigurationStore` 协议 + iOS 实现 `AppGroupStore+ConfigurationStore.swift` + `LiveConfigurationStore` |
| `DesignSystem/` (9 文件) | `Theme` / `RecordButton` / `RecordButtonGesturePolicy` / `WaveformView` / `EditTextPager` / `CardPageLayout` / `SonicParticleField` / `ThemedRoot` / `UsageStatCard` / `UsageSurfaceCard` |
| `Features/Analytics/` (10 文件) | `AnalyticsClient` / `AnalyticsRepository` (SQLite) / `AnalyticsUploadCoordinator` / `KeyboardUsageRepository` (跨进程 SQLite WAL) / ... |
| `Features/ManagedGateway/` (8 文件) | `ManagedLLMClient` / `GatewayGrantCoordinator` (actor) / `GatewayGrantCredentialStore` / `ManagedGatewayAccountAccessPolicy` / `ManagedGatewayScopePolicy` / `ManagedGatewayQuestionRouter` / `ManagedGatewayModels` / `OOBEGatewayGrantCoordinator` |
| `Localization/SharedL10n.swift` | `NSLocalizedString` against `Shared.strings`；解析 `AppUILanguage` |
| `Models/` (~50 文件) | 见下 |
| `Resources/` | `ClipboardSemantics/{*.mlmodel,*.json}` (6 CoreML) / `PolishStyles/{manifest.json,builtin.*.json}` (10 内置样式) / `Typing/English/{english_lexicon.{bin,tsv},english_bigrams.tsv}` |
| `Services/` (~80 文件) | 见下 |
| `Typing/` (24 文件) | librime + 拼音 + 英文 autocorrect + 触屏 + 布局 |
| `Utilities/` (21 文件) | 日志、错误模型、keychain、locale、Han 脚本、PCM/WAV、内存预算等 |

**关键 Services 详解**：

- **`PolishingService.swift:34-105`** —— `public actor`。`polish(_ raw:mode:systemPrompt:context:) -> PolishOutcome(text:qualityDegraded:polishStyleID:polishStylePrompt:)`。**单一融合 LLM 调用**：T1 自纠 → T2 填料清理 → T3 同音纠正 → T4 标点 → T5 结构 → 应用样式。Fun personality 在 heavy 强度切到"仅格式"共享核心。
- **`LLMClient` 协议** (`Services/LLMClient.swift:91-150`) —— `polish(_:systemPrompt:timeout:)` + `complete(messages:tools:timeout:options:)`。实现：`LLMClientFactory`（OpenAI 兼容）、`AnthropicLLMClient`（Anthropic Messages API）、`ResponsesAPILLMClient`（OpenAI Responses）、`ManagedLLMClient`（账户 grant 范围）、`AIModeSearchFallbackClient`（搜索→纯）。
- **`Keychain.swift:15`** —— `kSecClassGenericPassword` 读写 + iCloud 同步变体 + `OnFirstUnlockThisDeviceOnly` 本地变体 + XCTest 内存回退。
- **`AIClipboardSkill.swift:44`** —— 技能模型：`id` / `systemImage` / `titleKey` / `kind`（`.direct/.transform/.export`）/ `isDefault` / `shortcutName` + iCloud 分享 URL + bundled `.shortcut` 资源 / `thinkingEnabled` / `customName/Summary/Prompt` / `requiresShortcut` / `isUserCreated` / `isOfficial` / `managedGatewayTaskKind` / `supportsReplyStyle`。
- **`ClipboardHistoryStore.swift:10-84`** —— App-Group-backed observable store。合并通过 `ClipboardHistoryPolicy`（去重、清洗、保留）。
- **`ClipboardSemanticAnalyzer.swift:1-58`** —— 本地：`NLTokenizer/NLTagger` + 6 CoreML 分类器（`ClipboardSemantics/*.mlmodel`）产生 `language/dates/addresses/phoneNumbers/urls/personNames/organizationNames/sentiment/task/question/invitation/complaint/replyableMessage` 意图。
- **`ClipboardSkillSemanticRanker.swift:11-66`** —— 用语义分析 + 偏好语言对完整目录排序，固定 generic Reply 兜底。Stateless / `Sendable`。
- **`SpeechHistoryStore.swift:10-78`** —— iCloud-KVS 镜像 observable，prompt-fingerprint dedup。
- **`LocalASRModelManager.swift:11`** —— macOS Qwen3-MLX 权重 Application-Support 安装管理器。状态持久化到 `installed-manifest.json`。**Mac 专用**（iOS 用系统 SpeechAnalyzer）。
- **`LocalASRBiasAdapter.swift:9`** —— 分层偏差：`PersonalDictionary.effectiveEntries` + 内置 `BuiltinLexiconIndex.topTerms(...)`；按前台 App bundle id 选 `builtin-computer` vs `builtin-top`（Xcode/VSCode/Android Studio/IntelliJ/AppCode/Sublime/Terminal/iTerm2/Warp）。
- **`LocalASRTranscriptCorrector.swift:9-65`** —— 确定式 alias→canonical 替换，最长匹配优先，ASCII whole-word 感知。
- **`PolishStyleLearningService.swift:64`** —— `build(from:)` 从 `SpeechHistoryEntry` 历史生成 `PolishStyleLearningCorpus`（5000 字符 `requiredEffectiveCharacterCount`）。
- **`AIQuestionService.swift:20`** —— `actor AIConversationStore` 保留 `retainedConversationRounds` 轮 / 对话。
- **`AIEventExtraction` / `AIAddressExtraction` / `AITodoExtraction`** —— 解析 LLM 输出为 `start|end|title|location` / `origin|destination` / 列表。**全部 fail-closed**。
- **`HostAppURLRegistry`** —— 白名单 deep-link 路径（`deployrime`、`settings/clipboard`、`skill/run` 等），host + ext 共用。
- **`KeyboardSetupBridge`** —— `markExtensionAppearance(hasFullAccess:)` + OOBE 实践会话标志。
- **`AppGroupConfigDarwin`** —— `CFNotificationCenter` 发 `com.osgkeyboard.config.changed`（host 写完后）。
- **`FlowSessionBridge` + `FlowSessionKeys`** —— 跨进程 mailbox 全部 App-Group key：`flowHostReady` / `flowHostReadyAt` / `flowHeartbeat` / `flowSessionActive` / `flowSessionExpires` / `hostHeavy/At` / `hostGeneration` / `transcriptionResult` / `transcriptionPartial` / `transcriptionError{Kind,PolishWarning}` / `pendingKeyboardUtteranceId` / `lastPiPArmAttemptAt` / `flow.commandPayload.v1` / `flow.commandJournalPayload.v2` / `flow.resultPayload.v1` / `flow.ackPayload.v1` / `flow.startTransaction.v1` / `flow.readyPayload.v1`。
- **`SettingsCloudSync` / `SpeechHistoryCloudSync` / `UsageStatisticsCloudSync` / `AppCloudSync`** —— KVS 镜像；`ICloudSyncPreferences` + `SyncDeviceID` 保留每设备身份。
- **`AIHintStore` + `AIHintPool` + `AIHintKeywordExtractor` + `AIHintKeywordCompressor` + `AIHintLocalCatalog`** —— 闲置热词轮播：App-Group-pack loader、合并远端 + 本地卡片、确定性 10 或 22 字符关键词抽取（zh/en）。
- **`TranscriptionPolishFallback.swift`** —— LLM 润色失败或跳过时，交付原始转写 + 软警告。
- **`WhatsNewDemoScenario`** —— "What's New" 时间轴 driver，host（peek/consume）和 ext（DEBUG）共用。

**Polish 子系统详细**：
- `PolishContext` (`Models/PolishContext.swift`)：appContext + precedingText + followingText + fieldHints + dictionarySupplement + maxPrecedingChars=600 + maxFollowingChars=200
- `AppContext` 5 种（code/email/chat/document/unknown）
- `AppContextDetector` (`:30-116`)：3-fallback 链——`textDocumentProxy.documentContextBeforeInput` 启发式（iPad 沙盒安全；键盘读不到前台 bundle id）→ 30 分钟缓存 → 环境 blend
- `PolishStylePack` (`Models/PolishStylePack.swift:9-87`)：`Codable, Equatable, Identifiable, Sendable`；`id/name/prompt/allowsAddedEmoji/kind(.builtin/.user)/createdAt/updatedAt`
- `PolishStyleLimits`：`maximumUserPacks = 8` / `maximumPromptCharacters = 6_000`
- 内置样式分两组：`.practical`（light/structured/formal/chat）+ `.fun`（dating/flex/corp/diba/xhs）

**Typing 子系统**（`Typing/`）：
- `LibrimeEngine.swift` —— `@MainActor` 中文 IME，部署 3 套 schema：`osg_pinyin` / `osg_double_pinyin_mspy` / `osg_double_pinyin_sogou`
- `EnglishSuggestionEngine.swift` —— 3 槽 QuickType（verbatim / correction / completion），`inVocabularyFrequencyGap = 250`
- `EnglishLexicon.swift` —— mmap 40k 词 `english_lexicon.bin`
- `EnglishSystemLexicon.swift` —— `#if canImport(UIKit)` 守卫包 `UITextChecker + UILexicon`
- `EnglishQWERTYProximity.swift` —— 空间编辑代价
- `TypingSessionController` —— 拥有 typing surface：language/page/shift state、English 引擎、librime 引擎、拼音/英文消歧、autocap、句号快捷、shadow preceding text、`supplementaryWords`、hot reload
- `TypingSurfaceMetrics` (`Models/TypingSurfaceMetrics.swift`) + `KeyboardChromeLayout` —— 单一源：键行指标、底部动作行分数、总高 281pt，iPad narrow/wide（narrow 54pt / wide 76pt），`wideIPadWidthThreshold = 1100`
- `TypingInputConfiguration` —— `TypingInputSchema` (3 case) + `DefaultInputMode` (voice/pinyin/english)
- `PeriodShortcut.swift` —— iOS 句号快捷：letter→number 后第二个空格 0.45s 内变 ". " + arm sentence Shift
- `TypingAutocapitalization` —— 镜像 `UITextAutocapitalizationType`

**Models (~50 文件) 关键**：
- `AppGroupConfiguration` —— 完整 Codable blob
- `SyncedAppSettingsV2` —— per-field `SyncedField<T>` LWW + broken-clock containment (6h skew horizon)
- `LLMProvider` —— 8 家云预设
- `AIUserSkill` / `AIAgentSkillLayout` / `OfficialSkillCatalog` / `OfficialSkillDefinition` —— 技能体系
- `PolishStylePack` / `PolishStyleCatalog` / `PolishStyleLearningCorpus`
- `PersonalDictionary` / `+Merging` / `+ASRBias` —— 跨设备词典，iCloud 合并；提供 `hotwords` / `asrPromptBias` / `alibabaHotwordEntries` / `vocabularySyncFingerprint`
- `ClipboardHistoryEntry` / `SpeechHistoryEntry` / `SyncedSpeechHistory`
- `PolishContext` / `FieldHints` / `AppContext` / `AppUILanguage`
- `ProviderConfig` / `CloudProviderRole` / `CloudASRModels` / `LocalASRModelCatalog` / `LocalASRCapabilities` / `LocalASRBiasPayload`
- `TypingInputConfiguration` / `TypingSurfaceMetrics` / `KeyboardChromeLayout`
- `HandednessPreference` / `KeyboardHapticIntensity` / `PolishIntensity` / `AIResponseLength`
- `FlowUtteranceRequest` / `FlowUtteranceMode` / `FlowUtteranceChunkConfig` / `FlowHandoffPolicy` / `FlowAck` / `FlowResult` / `FlowCommand` / `FlowReadySnapshot` / `FlowStartTransaction` / `FlowTranscriptionError` / `FlowFieldContext`
- `MicVoiceAvailability` / `+Keyboard` —— mic 状态 + 派生
- `EditableInputReference` —— 跨进程最后插入引用（10 min TTL、≤1200 graphemes、schema v1）
- `EditSessionState` —— 关闭状态机 `.inactive/.preparing/.listening/.processing/.review/.applying/.appending/.failed`
- `AISessionState` —— `.inactive/.idle/.preparing/.listening/.recognizing/.generating/.ready/.awaitingSend/.inserted/.sent/.failed`

**Utilities (21 文件)**：
- `OSGLog.swift` —— subsystem + 类别（`flow/clm/config/asr/keyboardExt`）
- `OSGDiag.swift` —— NSLog + 内存快照（`task_info`）
- `FlowTrace.swift` —— `[trace] stage=...`
- `FlowPipelineDiagnostics.swift` / `FlowCaptureTailDrain.swift` / `FlowUtteranceEndCoordinator.swift` / `FlowUtterancePCMStore.swift`
- `UtteranceStreamChunker.swift` / `UtteranceBatchFallbackPolicy.swift` / `UtteranceTranscriptGuard.swift` / `UtteranceTranscriptStitcher.swift` / `TranscriptOverlapUtilities.swift` / `TranscriptLanguageDetector.swift`
- `ProgressiveDictationTranscriptAccumulator.swift`（**Mac 排除**）
- `DictationTextComposer.swift` / `FinalChunkRecovery.swift` / `PCMSampleWavEncoder.swift`（mono Float32 @16kHz → WAV）
- `PromptXMLEscaping.swift` / `HanScript.swift`（BMP 汉字谓词）
- `HostMemoryBudget.swift` / `KeyboardExtensionMemoryTelemetry.swift`（**Mac 排除**）
- `ProviderDisplayName.swift` / `AppVersionDisplay.swift`

**iOS-only 排除（`project.yml:570-586`）**：
```
DesignSystem/WaveformView.swift
DesignSystem/RecordButton.swift
DesignSystem/RecordButtonGesturePolicy.swift
Services/KeyboardState.swift
Services/KeyboardOpenSurfacePolicy.swift
Models/MicVoiceAvailability+Keyboard.swift
Models/TypingInputConfiguration.swift
Models/TypingSurfaceMetrics.swift
Typing/**
Utilities/ProgressiveDictationTranscriptAccumulator.swift
```

### 1.6 iOS 测试覆盖（108 + 16 文件）

**`OSGKeyboardTests/` (108 文件)** —— host + shared + hostsupport 端到端：
- **ASR/云 ASR**：`CloudASRServiceTests` / `CloudASRHTTPClientTests` / `CloudASRStreamingHelpersTests` / `CloudASRStreamingEventParsingTests` / `CloudASRTests` / `ASRConversionTests` / `LocalASRModelCatalogTests` / `LocalASRDownloadSourceSorterTests` / `LocalASRBiasAdapterTests` / `AlibabaVocabularySyncTests` / `FrequentTermStoreTests` / `PreviewASRControllerStateTests`
- **语音流水线**：`VoicePipelinePerformanceTests` / `FlowPhysicalAudioStressTests` / `FlowReliabilityTests` / `FlowASRPostProcessorTests` / `ChunkedUtterancePipelineTests` / `FlowBudgetAndMergeTests` / `FlowCaptureTailDrainTests` / `FlowUtteranceEndCoordinatorTests` / `FlowUtterancePCMStoreTests` / `UtteranceBatchFallbackPolicyTests` / `UtteranceStreamChunkerTests` / `UtteranceTranscriptGuardTests` / `UtteranceTranscriptStitcherTests` / `ProgressiveDictationTranscriptAccumulatorTests` / `FlowSessionBridgeTests` / `FlowSessionManagerAnalyticsTests` / `FlowSessionPolicyTests` / `FlowHandoffPolicyTests` / `FlowPiPRecoveryPolicyTests` / `FlowStartTransactionPolicyTests` / `FlowHomePiPStatusPolicyTests` / `FlowKeyboardPoliciesTests` / `KeyboardExtensionMemoryBudgetTests`
- **Polish/LLM**：`PolishStylePackTests` / `PolishStyleLearningServiceTests` / `PolishPromptComposerQuestionTests` / `PolishOutputValidatorTests` / `IntelligentPolishTests` / `LLMClientTests` / `AIModeLLMClientTests`
- **AI 特性**：`AIQuestionServiceTests` / `AIEventExtractionTests` / `AIAddressExtractionTests` / `AINoteExportTests` / `AIHintKeywordExtractorTests` / `AIHintPoolTests` / `AIUserSkillTests` / `AIUserSkillStoreTests` / `AIAgentSkillLayoutTests` / `AIHistoryAndUsageTests` / `AssistantFieldActionTests` / `AISessionStateTests` / `AIClipboardPromptTests` / `AnalyticsAIOperationTests` / `AppleNaturalLanguageCapabilityTests` / `SpeechHistoryRevisionTests` / `SpeechHistoryDayDeletionTests` / `SpeechHistoryCloudSyncTests` / `PublicContentRefreshServiceTests`
- **剪贴板/工具**：`ClipboardSkillSemanticRankerTests` / `ClipboardSemanticAnalyzerTests` / `ClipboardHistoryStoreTests` / `ClipboardHistoryPolicyTests` / `AccountCenterViewModelTests` / `AccountSnapshotLoaderTests` / `AccountAPIClientTests` / `AccountSignInCoordinatorTests` / `AccountCreditPurchaseManagerTests` / `AccountSecurityPrimitiveTests` / `ReferralProfileTests` / `EditTransactionStoreTests` / `EditableInputReferenceTests` / `EditLastInputPromptTests`
- **iCloud 同步**：`PersonalDictionaryCloudSyncTests` / `PersonalDictionaryMergeTests` / `SettingsCloudSyncTests` / `UsageStatisticsCloudSyncTests` / `KeyboardUsageRepositoryTests` / `KeyboardUsageModelTests` / `KeyboardUsageUploadCoordinatorTests` / `AnalyticsUploadCoordinatorTests` / `AnalyticsUploadSchedulingTests` / `AnalyticsRepositoryTests` / `AnalyticsModelTests` / `AnalyticsAttributionTests`
- **本地 ASR + 内存**：`LocalASRModelCatalogTests` / `KeyboardExtensionMemoryBudgetTests`
- **设置 + 工具**：`AppGroupConfigurationTests` / `AppGroupOnboardingStoreTests` / `ConfigurationStoreTests` / `HostAppURLRegistryTests` / `KeyboardTranslationConfigProtectionTests` / `KeychainTests` / `DeviceIntegrityTests` / `MicVoiceAvailabilityTests` / `OpenSourceLicenseCatalogTests` / `TipProductTests` / `EnglishTypingOnDeviceTests` / `TranscriptLanguageDetectorTests`
- **账户/Managed gateway**：`AccountAPIClientTests` / `AccountSignInCoordinatorTests` / `AccountCenterViewModelTests` / `AccountCreditPurchaseManagerTests` / `AccountSecurityPrimitiveTests` / `AccountSnapshotLoaderTests`
- **测试支持**：`AnalyticsTestSupport` / `KeyboardUsageTestSupport` / `FakeUbiquitousKeyValueStore`

**`OSGKeyboardExtTests/` (16 文件)**：
- `EnglishTypingTests` / `RimePersonalDictionaryExporterTests` / `KeyHitTestingTests` / `CandidatePanelExpandTests` / `KeyboardUsageTypingTests` / `LibrimeIntegrationTests` / `ManagedGatewayTests` / `RimeSchemaGeneratorTests` / `KeyboardSurfaceStateTests` / `AnalyticsExtensionPrivacyTests` / `PinyinNextKeyResolverTests` / `TypingTouchTrackerTests` / `FinalChunkRecoveryTests` / `KeyboardStateTests` / `EditHintSchedulerTests` / `ClipboardSuggestionLifecycleTests`

---

## 2. macOS 端完整状态

### 2.1 目标基本事实

- Bundle ID: `com.osgkeyboard.mac`（Developer ID + 公证，**沙盒关闭**）
- 最低系统：macOS 15.0。Swift 6 / strict concurrency
- 装包名：`OSGKeyboard.app`（target 名 `OSGKeyboardMac` 改 `PRODUCT_NAME`）
- 本地 ASR：**MLX Audio Qwen3-ASR 0.6B/1.7B 4-bit**（`ThirdParty/mlx-audio-swift/` SPM）
- 复用 iOS AppIcon (`OSGKeyboard/AppIcon.icon`) + iOS 资产目录（除 `AppIcon.appiconset`）

### 2.2 macOS App 目录结构（`OSGKeyboardMac/`，39 Swift 文件，无子目录）

**入口与生命周期**：
- `OSGKeyboardMacApp.swift:1` —— `@main struct OSGKeyboardMacApp: App`。**单一** `Window`（`.windowStyle(.hiddenTitleBar)`、`.defaultSize(width: 860, height: 600)`）+ `MacAppDelegate: NSApplicationDelegate + NSPopoverDelegate` 拥有 `NSStatusItem + NSPopover`（340×420 transient）+ 浮动 dictation overlay
- **不**用 `MenuBarExtra`（`OSGKeyboardMacApp.swift:104-105` 注释：与主 Window 同存时图标会消失）
- 订阅 `Notification.Name`（`.settingsDidSyncFromCloud` / `.personalDictionaryDidSyncFromCloud` / `.usageStatisticsDidSyncFromCloud` / `.speechHistoryDidSyncFromCloud`）iCloud pull 刷新
- `onOpenURL` 接 `osgkeyboard://seed-demo`（DEBUG `DemoDataSeeder`）

**侧栏/Shell**：
- `MacRootView.swift` —— `NavigationSplitView(.balanced)`，侧栏：`OSGLogoWide` 品牌头 + 5 个 `MacSection` 行（`.dashboard/.history/.dictionary/.styles/.settings`）+ "Devices" 页脚；detail 切换 `DashboardView/MacHistoryView/MacDictionaryView/MacPolishStylesView/MacSettingsView`；底部 `MacStatusFooter`
- `MacDictationViewModel.swift:12` —— `MacSection` enum
- `MacTheme.swift:114` —— `MacSystemPalette` 双模式（light 暖白 + dark stepped systemGray6→4），通过 `\.themePalette` 注入，颜色方案变更重渲染
- `MacAppearance.swift` —— `MacAppearancePreference`（system/light/dark）存 `mac.appearancePreference`，`applyToApp` 推到 `NSApp.appearance` 和每个 window

**菜单栏 UI**（Status Item + Popover）：
- `OSGKeyboardMacApp.swift:140` —— variable-length `NSStatusItem` 模板 NSImage，target/action = `togglePopover(_:)`
- Popover 内容：`NSHostingController(rootView: MacMenuBarPopover())` (`:214`)。未完成 onboarding → "open the main window" 提示；否则 `MacContentView`（品牌 + record 按钮 + 热键提示 + 状态文本 + 滚动转写 ≤120pt + 模式/翻译/连接状态 + footer）
- Popover 打开：`prepareForPopoverPresentation()` snapshot 前台 App，**OSGKeyboard 成为 key 时不丢失粘贴目标**

**录制 overlay**：
- `MacDictationOverlayController.swift` —— 一个 borderless non-activating `NSPanel`（level `floatingWindow + 1`、`.canJoinAllSpaces + .fullScreenAuxiliary + .stationary`）
- 状态机驱动 show/hide（`viewModel.$isRecording/$isPreparingToRecord/$isProcessing` CombineLatest3）
- 位置 user-draggable（双击重置底部居中），持久化到 UserDefaults（`mac.overlay.hasCustomPosition / centerX / originY`）
- `MacDictationOverlayView.swift` —— SwiftUI pill（500pt 内容宽）+ 状态点 + 一行转写 + 实时徽章 + `MiniWaveform` + stop 按钮
- `MiniWaveform` 复用 `OSGKeyboardShared/DesignSystem`

**主窗口 5 大页**：
- `DashboardView.swift` —— `GeometryReader` 垂直布局：品牌头 + 7 天图（`UsageStatsCluster layout: .split`）+ `dictationStage` 卡片（`viewModel.homePreviewText` 累计预览）+ `BottomDictationBar`（翻译选择器 + record 按钮 + ready chip）
- `MacHistoryView.swift` —— 按天分组 `SpeechHistoryStore`，每行 copy/delete context menu，"Clear" 带确认
- `MacDictionaryView.swift` —— `PersonalDictionary` 按 `Entry.Category` 分组，按使用次数 + 术语排序；搜索框过滤；`+` 弹 `MacDictionaryEntryEditor` sheet
- `MacPolishStylesView.swift` —— `PolishStylePack` 目录（内置 practical+fun + 用户），只读 prompt 详情 / 完整编辑器（`allowsAddedEmoji` 切换 + 2400 字符 prompt 限制）；学习卡：语料进度 + "Generate learned style" → `PolishStyleLearningService.generateStyle`
- `MacSettingsView.swift` —— `NavigationStack + ScrollView` 7 段：support developer (Tip) / general (appearance / interface language / recognition language / iCloud sync) / recognition method (cloud vs local) / cloud ASR provider / local ASR model catalog / polish provider / input (hotkey / auto-paste / accessibility 状态) / legal (Privacy Policy + Third-Party Licenses + Restart Onboarding + version)

**Onboarding**：
- `MacOnboardingView.swift:21` —— 6 步：`welcome → microphone → accessibility → engine → [.cloudAPI | .localModel]`，根据 `viewModel.config.engineMode` 分支
- Mic 步调 `AVCaptureDevice.requestAccess(for: .audio)`；accessibility 步打开 `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` 并 1s 后重查 `AXIsProcessTrusted`
- Cloud 步收 LLM provider + key + model；local 步显示默认 Qwen3-MLX 0.6B + 下载按钮 + 进度 + "skip" 提示
- 状态存 `mac.hasCompletedMacOnboarding`
- 注释 `MacOnboardingView.swift:7-8` —— "Sherpa identifiers and install records are retained only for migration compatibility"：**近期从 Sherpa 换到 MLX**
- Settings → About 有 "Restart Onboarding" 按钮

**Legal / Support**：
- `MacLegalSettingsViews.swift` —— `MacPrivacyPolicyView`（`WKWebView` 加载 `OSGKeyboard/Resources/PrivacyPolicy.html`，按 `uiLanguage` 切滚动锚点）+ `MacOpenSourceLicensesView`（`OpenSourceLicenseCatalog.entries(for: .macOS)` 列表）→ `MacOpenSourceLicenseDetailView`（许可证名 / upstream 链接 / 用途 / 文本）
- `MacSupportDeveloperTipRows.swift` —— StoreKit 2 `TipPurchaseManager.shared` 消耗型打赏行

**DEBUG 工具**：
- `osgkeyboard://seed-demo` URL 触发 `DemoDataSeeder.seedRichPlaceholderData`
- `MacAudioRecorder.hasLiveSnapshotSink`（DEBUG seam，见 `MacAudioRecorder.swift:143`）

### 2.3 全局热键 + 辅助功能 + 粘贴注入

**`MacHotkeyService.swift`**：
- 用**两个** `NSEvent.add*MonitorForEvents(matching: .flagsChanged)`（global + local）
- 区分左/右 Option（`NX_DEVICELALTKEYMASK = 0x20` / `NX_DEVICERALTKEYMASK = 0x40`）；`MacHotkeyTrigger`（`rightOption / leftOption / eitherOption`）
- 150ms 持有防抖（`scheduleBegin` → `Task.sleep(150ms)` → fire `onPressBegan`），松开取消未发起的 begin
- `start()` 返回 Accessibility 状态（`globalFlagsMonitor == nil` ⇒ 大概率无权限），DEBUG 下 NSLog

**`MacTextInsertionService.swift`** —— Accessibility 门控合成 ⌘V：
- `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` 按需
- `insert(_:autoPaste:targetApp:)`：清 `NSPasteboard.general` → 写转写 → snapshot 原始 pasteboard（**所有 representation，不仅是 `.string`**）→ `CGEvent + kVK_ANSI_V + cghidEventTap` 合成 ⌘V → 等 500ms 后**仅当 change count 仍匹配 post-transcript write**才恢复 snapshot（用户/clipboard-manager 写入期间不覆盖）
- `FrontmostAppTracker`（`:177`）跟踪 `NSWorkspace.didActivateApplicationNotification`，**OSGKeyboard popover 激活时**保留原始 paste 目标
- `activate(_:)` 重新激活目标 App，等最多 1s 成为 frontmost
- `shouldRestorePasteboard` + `restoreItems` 是单测 seam

### 2.4 音频捕获

**`MacAudioRecorder.swift`**：
- `MacAudioRecording` 协议
- **`AVAudioEngine.inputNode`** + 4096 帧 tap
- 输入格式 → 16kHz mono Float32 via `AVAudioConverter`
- 10 分钟 @16kHz 硬上限 + 30s trim hysteresis（卡住的热键不会无限增长 buffer）
- RMS 平滑（attack 0.5 / decay 0.15）
- 权限：`AVCaptureDevice.requestAccess(for: .audio)`；拒/受限抛 `microphoneAccessDenied`
- `makeSnapshotStream() -> AsyncStream<AudioBufferSnapshot>`
- Sink 安装按 generation 追踪，避免前一 sink 延迟终止处理器卸载新 sink
- **无输入设备选择器**（`AVAudioEngine.inputNode` 用系统默认；iOS `AudioBufferSnapshot+AVFoundation.swift` 在 `project.yml:568` 排除）

**`MacHallucinationFilter.swift`**：
- 剥 `<asr_text>` 脚手架、`language XX` 前缀、元数据噪声行（`language/emotion/event` 等）
- `silencePeakThreshold = 0.0005`（RMS 低于此跳喂 MLX stream）
- `shouldDiscardHotwordDump`（音频能量低 + 转写主要是词典热词 → 丢假触发）

### 2.5 MLX / 本地 ASR 流水线

**关键文件**：
- `MacLocalASRService.swift` —— Mac 端公共面：`selectedModelDefinition()` / `isModelInstalled(_:)` / `usesMLXLiveStreaming()` / `transcribe(samples:locale:bias:)`。MLX 后端模型走 `MacMLXStreamingASRProvider`；`.appleSpeech` 后端或未装模型时落 `MacSpeechLocalASR`。Legacy Sherpa 标识符（`sherpaQwen3/sherpaSenseVoice/sherpaParaformer`）只接受以便抛 `qwen3ModelMissing` —— **明确迁移期处理**
- `MacMLXStreamingASRProvider.swift` —— `actor`，拥有单 `Qwen3ASRModel` 缓存（`cachedModelId / cachedModel / didWarmup`）。`loadModel` 从 `LocalASRModelInstallState.modelRootURL(definition)` 读并 `Qwen3ASRModel.fromModelDirectory(root)`。`warmupIfNeeded` 用 1s 静音预热 Metal kernel。`makeSession` 构建 `StreamingConfig`（0.5s decode interval、0.2s boundary、1s boundary boost、encoder window overlap 1s、max cached windows 8、`delayPreset: .realtime`、language hint 从 `MacQwen3LanguageHint.from(locale:)`、`context: bias?.promptBias`、`temperature: 0`、512 max tokens/pass、2/2 min-agreement passes、`finalizeCompletedWindows: true`）
- `MacMLXStreamingSession.swift` —— 包装 `mlx-audio-swift` 的 `StreamingInferenceSession`。订阅 `AsyncStream<TranscriptionEvent>`（`displayUpdate/ended/provisional/confirmed/stats`）；`MacHallucinationFilter` 过滤 `display/ended`；`onDisplayUpdate` 转发 `display`；`feed(samples:)` 通过 `FlowCaptureDrainTracker.rms(of:)` 跳过低于 `silencePeakThreshold` 的数据；`stop()` 通过 `CheckedContinuation` 返回最终 `String`；`peakAudioRMS()` 暴露 hotword-dump 守卫用最大 RMS
- `MacMLXLiveCapture.swift` —— Option 持有本地 ASR 编排：建 streaming session，`TaskGroup` 内 2 个并发任务：(1) 等首 `finishSignal`（`draining.withLock { $0 = true }` → `await FlowUtteranceEndCoordinator.awaitTailCapture(policy: .macMLX)`）——**显式 `break` 单信号**，永不结束的 stream 不会挂住 group；(2) 消费 `AudioBufferSnapshot` stream，100ms chunk（1600 samples @16kHz）喂 MLX，draining 时 `drainTracker.noteAudio`。然后喂余量，调 `session.stop()`，跑 `MacHallucinationFilter.shouldDiscardHotwordDump` 丢热词-only 转写
- `MacSpeechLocalASR.swift` —— Apple Speech 兜底。16kHz PCM 写临时 WAV（`PCMSampleWavEncoder`），`SFSpeechURLRecognitionRequest` 强制 `requiresOnDeviceRecognition`（locale 无 on-device 模型时立即失败 → 清晰错误"去 系统设置 → 键盘 → 听写 下载"）。Chinese locale 应用 `CustomLanguageModelManager.applyCustomLanguageModel(to:locale:bias:)`（与 iOS 共用）。2× 音频长硬超时 + 30s floor，`RecognitionSession` 锁保护单次 resume，识别回调和超时 task 正确竞速
- `MacCloudASRChunkAdapter.swift` —— 薄 `ASRChunkTranscribing` 适配器，包装 `CloudASRClientFactory.make(store:)` 给 `MacDictationPipeline` 用

**模型目录**（`OSGKeyboard/Resources/LocalASR/local-asr-catalog.json`，2.0.1 状态）：
- `schemaVersion: 1`
- `defaultModelId: "qwen3-mlx-0.6b-4bit"`
- `runtimes: []`（**空**——runtime 随 bundle 走，MLX 内置）
- 2 个模型：
  1. **`qwen3-mlx-0.6b-4bit`** —— Qwen3-ASR 0.6B，`backend: mlx`，`runtimePlatform: macos`，`sizeBytes: 730000000`（~0.7 GB），locale `zh-CN/en-US`，支持热词（`promptOnly`），`badgeKey: mac.localASR.badge.balanced`，路径 `models/qwen3-mlx-0.6b-4bit`。两个下载源（`hfmirror`/`huggingface`）都在 `mlx-community/Qwen3-ASR-0.6B-4bit`。文件：`config.json` / `generation_config.json` / `preprocessor_config.json` / `model.safetensors`（~708MB） / `model.safetensors.index.json` / `tokenizer_config.json` / `merges.txt` / `vocab.json`
  2. **`qwen3-mlx-1.7b-4bit`** —— Qwen3-ASR 1.7B，同上形状，`sizeBytes: 1700000000`（~1.7GB），`badgeKey: mac.localASR.badge.quality`。源在 `mlx-community/Qwen3-ASR-1.7B-4bit`

**`local-asr-catalog.json` 中零 iOS 模型**。iOS app 运行时**不**用本目录——iOS 用 iOS 26 `SpeechAnalyzer + DictationTranscriber`，代码路径不同（`OSGKeyboardHostSupport/Services/ASRService.swift`，Mac 排除）。

**模型生命周期**：
- `loadModel(_:)` (`MacMLXStreamingASRProvider` 第 69-81 行) 缓存 loaded `Qwen3ASRModel` per model id。切模型失效缓存并 re-warm。`warmupIfNeeded` 每个冷模型跑一次
- 卸载（`MacLocalASRModelSettingsViewModel.deleteModel`）→ 共享 `LocalASRModelManager.deleteModel(_:catalog:)` 删磁盘权重；actor 缓存**不**自动清——下次不同 id 的 `loadModel` 自然替换

**Mac 不支持 iOS 风格的"on-device + cloud hybrid"**——只有 engine-mode 开关（`local` → MLX 或 Apple Speech；`cloud` → 已配云 ASR）。两种模式共用同一 LLM 润色步。

### 2.6 LLM 润色 + 供应商集成

- `MacDictationPipeline.swift:254` —— 跑的是**同一份** `PolishingService(store: store).polishWithOutcome(...)`（iOS `OSGKeyboardShared/Services/PolishingService.swift`）
- `PolishContext` 用 `appContext`（从目标 App bundle id 通过 `MacAppContextService` 抓）+ `dictionarySupplement`（来自 local-bias `polishFragment`），**和 iOS 同款**
- `MacSettingsView.swift:111` (`polishProviderSection`) 用 `viewModel.polishSelectableProviders`（`LLMProvider.userSelectablePresets`——**完整集，与 iOS 相同**）。行：provider / API key / baseURL / model（`MacProviderModelRow` "拉模型列表" 动作） / thinking 切换 / `MacProviderToolsRow` "Test connection" / 翻译目标
- `MacSettingsView.swift:173` (`asrProviderSection`) 用 `viewModel.asrSelectableProviders`（`LLMProvider.asrSelectablePresets`）。Volcengine 有自定义 auth-mode（API key vs App ID + Access Token）通过 `VolcengineASRFields.parse` / `updateMacVolcengine(...)`；其他供应商走通用 `baseURL/apiKey/model` 行 + "Test connection"
- **Mac 没有 Mac 专用 polish/ASR 供应商集**——供应商面和 iOS 一致（DeepSeek/OpenAI/Anthropic 兼容 LLM；Volcengine/OpenAI Realtime/Bailian/Alibaba 云 ASR）
- **MLX 供应商仅用于本地 ASR**——**无** Mac 端 MLX LLM 润色

### 2.7 持久化

| 类别 | 实现 | Key 前缀 / 位置 |
|---|---|---|
| UserDefaults | 标准 | `mac.*`（`MacHotkeyService:41` / `MacAppearance:56` / `MacDictationViewModel:103-105` / `MacDictationOverlayController:43-45`）—— 热键、auto-paste、appearance、onboarding、overlay 位置、MLX 模型选择、下载源、界面语言 |
| App Group | 共享 `AppGroupStore` | 与 iOS 同：`PersonalDictionary` / `PolishStyleCatalog+active id` / `translationTarget` / `detected appContext` / `speechHistory` / `usageStatistics` / `engineMode` / `localeId` / LLM API key & baseURL / 云 ASR provider id/apiKey/model/baseURL / iCloud-sync-enabled |
| Keychain | 共享 `Keychain` | `keychain-access-groups: [$(AppIdentifierPrefix)com.osgkeyboard.shared]`（entitlement）—— 存 LLM API key |
| iCloud KVS | 5 路全部接好 | `MacICloudSyncBootstrap.swift` 接 `AppCloudSync(makeStore:historyDefaults:)`，暴露 `settingsSync/dictionarySync/polishStyleSync/appCloudSync`，**entitlement 用 `$(TeamIdentifierPrefix)com.osgkeyboard.ios` 和 iOS 同桶** |
| 语音历史 | `SpeechHistoryStore.shared` + `SpeechHistoryStorage` | UserDefaults 后端 + iCloud `SpeechHistoryCloudSync` |
| 模型权重 | `LocalASRModelInstallState.rootDirectory()` | 由共享 `LocalASRModelManager` 管 |
| 临时文件 | `FileManager.default.temporaryDirectory` | Apple Speech WAV（`osg-mac-asr-<uuid>.wav`，`defer` 删，`MacSpeechLocalASR:71`） |

### 2.8 系统集成

- ✅ 菜单栏 status item + popover
- ✅ 全局 ⌥ 热键 + 合成 ⌘V
- ✅ URL scheme `osgkeyboard`（仅 DEBUG `osgkeyboard://seed-demo`）
- ❌ Login item / launchd（**无** `SMLoginItemSetEnabled`）
- ❌ 通知（`UNUserNotificationCenter`）—— HUD 本身就是唯一直达面
- ❌ Touch Bar
- ❌ Services / Share extensions
- ❌ Dock badge
- ✅ `LSApplicationCategoryType: public.app-category.utilities`
- ✅ `ENABLE_HARDENED_RUNTIME: YES`（Developer ID + 公证必需）
- ❌ **沙盒关闭** `com.apple.security.app-sandbox: false`（`project.yml:628`）—— Accessibility + 全局事件 tap + ⌘V 注入都禁在沙盒里
- 发行渠道：**Developer ID + 公证**，**不进** Mac App Store / TestFlight
- `applicationShouldTerminateAfterLastWindowClosed → false`（菜单栏项保活）
- `LSUIElement: false`（**不**设——启动时仍显 Dock 图标）

### 2.9 macOS 独占（iOS 没有）的能力

1. **`NSStatusItem + NSPopover` 菜单栏 UI** —— SwiftUI `MenuBarExtra` 故意不用，AppKit 为源
2. **全局 ⌥ 持有热键**（`NSEvent.add*MonitorForEvents(matching: .flagsChanged)`）区分左/右/任意 Option
3. **Accessibility 门控 ⌘V 注入**（`CGEvent + cghidEventTap + AXIsProcessTrusted`）
4. **前台 App 跟踪**（`FrontmostAppTracker`）让 popover 激活 OSGKeyboard 时不丢粘贴目标
5. **MLX Audio Qwen3 流式 ASR**（Qwen3-ASR 0.6B/1.7B 4-bit）通过 `mlx-audio-swift` SPM
6. **系统原生 macOS light/dark 调色板**（暖白 light + stepped gray6→4 dark），从 AppKit semantic colors 解析，让 window chrome 跟随 SwiftUI 颜色方案
7. **浮动 non-activating `NSPanel` HUD**（`floatingWindow + 1`），user-draggable 位置持久化
8. **Bundle-ID → `AppContext` 映射**（`MacAppContextService.swift`）—— iOS 走 `AppContextDetector` 启发式（键盘读不到前台 bundle id）
9. **手动 MLX 模型下载/暂停/恢复**，per-file 字节进度
10. **"Open Storage"** reveal-in-Finder MLX 模型根
11. **Volcengine 云 ASR auth-mode 切换**（API key vs App ID + Access Token）
12. **同 `URL scheme: osgkeyboard`** 加 `osgkeyboard://seed-demo` DEBUG seed
13. **Apple Speech on-device 兜底**（仅当未装 MLX 模型或 backend == `.appleSpeech`）
14. **`NSApplicationDelegate`-driven AppKit 生命周期**：`applicationShouldTerminateAfterLastWindowClosed → false`、status-item 创建、overlay controller 启动、热键接续
15. **`MacMLXStreamingASRProvider` actor + 模型缓存 + warmup** 保单 `Qwen3ASRModel` 驻留
16. **两列 `MacInlinePicker`（供应商行）** vs iOS `.menu` `Picker`
17. **`MacProviderSettingRow` 显式 200pt label 列** 防长凭证输入挤

### 2.10 macOS 测试覆盖（`OSGKeyboardMacTests/`，3 文件，挂在 Mac App bundle 内）

`project.yml:513-533` 覆盖 `@testable import OSGKeyboard`（host target 名 `OSGKeyboardMac` 但装包为 `OSGKeyboard.app`，所以 override `TEST_HOST`）。

1. **`MacDictationViewModelTests.swift`** —— `testCancellingButtonPreparationKeepsGateClosedUntilStartUnwinds`：替换 recorder 为 `SuspendedMacAudioRecorder`（`start()` 停 `CheckedContinuation`），验证第二次 `toggleRecording()`（取消）不重开 `isPreparingToRecord` 门
2. **`MacAudioRecorderSnapshotStreamTests.swift`** —— `testReplacingSnapshotStreamDoesNotDeadlock` + `testReplacingSnapshotStreamKeepsTheNewSinkAttached`：回归守卫，防 Option 松开时 lock 重入冻结（`AsyncStream.Continuation.finish()` 在调用线程同步跑 `onTermination`，handler 重新拿 installer 持有的同 `NSLock` 死锁主线程）。第一个测试在 global queue 装 + 2s semaphore 超时，让回归失败而非挂住套件；第二个测读 `MacAudioRecorder.hasLiveSnapshotSink`（DEBUG seam）确认新 stream 顶替前辈
3. **`MacTextInsertionServiceTests.swift`** —— `testRestoreRequiresTranscriptToStillOwnPasteboard`（pasteboard change-count 守卫）/ `testRestoringOriginallyEmptyPasteboardClearsTranscript` / `testCapturedBundleIdentifierDrivesPolishContext`（Xcode/WeChat/OSGKeyboard 自身经 `MacAppContextService.detectContext(bundleIdentifier:)`）

---

## 3. macOS 落后 iOS 的功能（按缺口大小排序）

### 3.1 完全缺失（共享代码已编进 Mac 但零调用）

| 缺失功能 | iOS 路径 | 共享代码状态 | 影响 |
|---|---|---|---|
| **剪贴板历史 + AI 技能** | `OSGKeyboard/Views/ClipboardSettingsView`、`OSGKeyboardExt/Views/ClipboardKeyboardViews` | `ClipboardHistoryStore` / `ClipboardSemanticAnalyzer` / `ClipboardSkillSemanticRanker` / `AIClipboardSkill` / `AIClipboardSkillLayoutStore` / `AIClipboardPrompt` / `ClipboardHistoryPolicy` **全部编进 Mac 二进制，无任何 Mac 文件引用** | Mac 用户能说话能润色，但**没法**让"复制即智能" |
| **AI 提示轮播 / 上下文技能** | `OSGKeyboard/Services/AIHintRefreshService`、`OSGKeyboardExt/Views/AIKeyboardView` 内的 hint carousel | `AIHintStore` / `AIHintPool` / `AIHintKeywordExtractor` / `AIHintKeywordCompressor` / `AIHintLocalCatalog` / `AIHintModels` 全部已编，**无 Mac 调用** | Mac 没有 idle 屏的"想一句"灵感卡 |
| **OSG 账户（Sign in with Apple + 积分 + 推荐）** | `OSGKeyboard/Views/Account/AccountCenterView`、`AccountPurchaseHistoryView` | `OSGKeyboardHostSupport/Features/Account/` 全部编进 Mac（`AccountAPIClient` / `SignInWithApple` / `DeviceIntegrity` / `HostPrivateAccountKeychain` / `AccountModels` / `OOBEGrantProvisioningCoordinator`），**无 Mac UI 也无调用**，且 Mac entitlement 无 `com.apple.developer.applesignin` | Mac 只能用 tip 打赏；OSG 积分体系是 iOS 独占 |
| **App Attest** | `OSGKeyboardHostSupport/Features/Account/DeviceIntegrity.swift`（`SystemAppAttestProvider`）| 已编，但 Mac 无对应 entitlement（`com.apple.developer.devicecheck.appattest-environment`）也无调用 | Mac 不在 attestation 流程里 |
| **一方分析（Analytics）** | `OSGKeyboard/Services/AnalyticsHostService`、`OSGKeyboardExt/Services/AnalyticsExtensionService` | `OSGKeyboardShared/Features/Analytics/` 12+ 文件全部编进 Mac，**零 Mac 调用** | Mac 用户行为完全无遥测；产品迭代失去数据源 |
| **助手指令（Shortcuts）** | `OSGKeyboard/Services/AIAgentShortcutInstaller`、`AIAgentShortcutRunner`、3 个 bundled `.shortcut`（`OSGExtractTodos/OSGExtractEvents/OSGSaveToNotes`） | 共享 `AIAgentSkill*` / `AIShortcutShareLink` / `AIGenericSkillExport` / `AINoteExport` / `AIMapNavigation` / `AIPhoneNumberActions` 已编，无 Mac 调用；bundled `.shortcut` **Mac 不装**（`project.yml:97-105` 仅 iOS 装） | Mac 没法"说一句把当前文本加到 Notes / 提取 Todo" |
| **CLM 用户管理 UI** | iOS 后台用 `CustomLanguageModelManager` | Mac **用**了 CLM（`OSGKeyboardMacApp.swift:117` 调 `prepareInBackgroundIfNeeded`；`MacSpeechLocalASR:67-98` 调 `applyCustomLanguageModel`），**但**无 `MacCLMSettingsView` | Mac 用户不知道 CLM 在跑；没法改 phrase 库 |
| **最后输入编辑（Edit hint / Last-input edit）** | `OSGKeyboardExt/Views/LastInputEditView`、`EditHintScheduler`、`LastInputEditCoordinator` | 已编，无 Mac 调用 | Mac 没法长按"改刚才那句" |
| **Flow 跨进程会话** | `OSGKeyboard/Services/FlowSessionManager`、`FlowPictureInPictureController`、`FlowTerminationCoordinator`、`FlowAnalyticsOperationRegistry`、`FlowASRPostProcessor`、`FlowDiagnostics`、`OSGKeyboardExt/Services/KeyboardFlowCoordinator`、`OSGKeyboardShared/Services/FlowSessionBridge*` | 已编，Mac 仅借用 `FlowSessionKeys.cloudASRWaitTimeout` 一个常量（`MacDictationViewModel.swift:498`） | **架构性差异**——Mac 单进程、单用户、单次录制；不需要也不该硬塞 |
| **自定义键盘（Rime/拼音/英文）** | 整个 `OSGKeyboardExt/Typing/` + `OSGKeyboardShared/Typing/**` + `LibrimeEngine` + `RimeResourceInstaller` + `EnglishSuggestionEngine` + `Pinyin*` + `Rime*` | **Mac target 完全排除** `Typing/**`（`project.yml:585`） | **架构性差异**——Mac 不是键盘扩展；librime 是 iOS C/Objective-C++ 框架，Mac 结构性不兼容 |
| **后台任务** | iOS `UIBackgroundModes: audio` + `BGTaskSchedulerPermittedIdentifiers: [com.osgkeyboard.ios.analytics-sync]` | Mac Info.plist **无** `BG*` keys | Mac app 不能后台运行；iOS 的 analytics 同步、Flow PiP 都没 Mac 对应 |
| **Settings 子页面** | `TypingInputSettingsView` / `AIAgentSkillsView` / `Account/*` / `HelpFeedbackView` / `ReleaseNotesSheet` / `AppGroupErrorView` / `NewContactSheet` / `KeyboardPreviewSheet` / 各种 DEBUG demo | 无 Mac 对应 | 见上表 |
| **Universal Links 启动 handoff** | iOS `applinks:osglab.com` + `AppURLHandler` 保留 `sourceApplication` | Mac entitlement 共享同 `com.apple.developer.associated-domains` 但**无** Mac-side 解析 | Mac 不能从网页/邮件 deep-link 进 Onboarding 或 Skill |

### 3.2 部分缺失

| 缺失 | iOS | macOS | 差异点 |
|---|---|---|---|
| **Onboarding 深度** | 7 步 + OOBE 4-feature 实践（用 `OOBEClientInfrastructure` 拿服务器体验金） | 6 步（welcome / mic / accessibility / engine / cloud\|local） | 无 Sign in with Apple、无 OOBE 实践 |
| **设置覆盖面** | 7 个子面板 + Account + AI Agent + Clipboard + Typing Input | 5 个段落（support / general / recognition / ASR / local ASR / polish / input / legal） | iOS 的 AI Agent / Clipboard / Typing 在 Mac 没对应；Mac 的 input 段含热键 + Accessibility 状态（iOS 没有） |
| **AI Hint / Shortcut 链接** | 提示页 + 3 bundled `.shortcut` | 仅 0（Mac 装包不含 `.shortcut`） | 整套 AI mode 体验 Mac 无 |
| **Provider 切换粒度** | iOS 通过 iOS `EnginePickerSection` + `ProviderPickerSection` 在 Settings 内 + 主页快捷 | Mac 整段 `recognitionSection` + `asrProviderSection` + `polishProviderSection` 拆开 | iOS 较紧，Mac 较松 |

### 3.3 Mac 自身落后 iOS 之处（"应该补"清单）

按"代码复用难度 + 用户价值"排序：

| 优先级 | 功能 | 现状 | 工作量 | 建议 |
|---|---|---|---|---|
| **P0** | **剪贴板历史 + AI 技能面板（Mac UI）** | 共享代码全到位，零 Mac UI | **小**——`MacClipboardHistoryView` + `MacAIClipboardSkillView`（仿 `MacHistoryView`）+ 改 `MacSettingsView` 加一个 Clipboard 段 | 立刻做。代码复用 100%，价值高 |
| **P0** | **CLM 设置页（Mac UI）** | 后台在跑（`OSGKeyboardMacApp:117`），无 UI | **小**——`MacCLMSettingsView`，仿 `MacLocalASRModelSettingsView` 模板 | 立刻做。让用户能编辑 phrase 库 |
| **P1** | **OSG 账户 + Sign in with Apple + 积分购买** | 共享代码编进 Mac，零 UI；Mac entitlement 缺 `com.apple.developer.applesignin` + 无 `SKIncludeConsumableInAppPurchaseHistory` | **中**——加 entitlement + 改 `MacICloudSyncBootstrap` 已涵盖大部分，加 `MacAccountCenterView`（仿 `AccountCenterView` 但精简）+ 改 Settings | 一周内可交付 |
| **P1** | **OSG credits 消耗型 IAP（500tks/1500tks/3000tks）** | 共享 `TipPurchaseManager` 已装；iOS 走 `AccountCreditPurchaseManager` | **中**——`MacAccountCenterView` 出来后一气呵成 | 同上 |
| **P2** | **一方分析（Mac）** | 共享 `AnalyticsClient` 等全编，零调用 | **中-大**——`MacAnalyticsHostService` + 隐私 / opt-in + 后台任务（Mac 上走 `NSProcessInfo.thermalState` 节流 + 用户同意时 `NSTask` 跑）| 半年窗口内 |
| **P2** | **AI 提示轮播 / 上下文技能（Mac）** | 共享代码全到位 | **中**——加 `MacAIHintPool` 屏 + `MacAIQuestionService` 入口 + Shortcuts bundle 装载 | 与 P0 剪贴板可联动 |
| **P3** | **助手指令集成** | 共享代码 + iOS bundled `.shortcut` | **中**——Mac 装 `.shortcut` + `AIAgentShortcutInstaller` 调起（`shortcuts://` URL 仍可用）| 与 P2 AI 提示联动 |
| **P3** | **最后输入编辑** | 共享代码全到位 | **大**——需要 Mac 端保留"刚才插入的引用"（`EditableInputReference`），但 Mac 走 Accessibility ⌘V 注入，**没有 `EditableInputReference` 的来源**——需要新协议 | 架构问题，先做 PoC |
| **P3** | **后台同步（Analytics 任务）** | 无 | **中**——`NSTask`/`SMAppService` LaunchAgent 拉 analytics；与 P2 联动 | |

### 3.4 Mac 形态上"不应该补"的功能

| 功能 | 原因 |
|---|---|
| **Flow 跨进程会话** | Mac 单进程、单用户、单次录制——Flow 设计为键盘扩展 ↔ 宿主 App 的两进程 mailbox。强行移植会引入不必要的 IPC 开销。**Mac 用 `MacDictationPipeline` + `MacDictationViewModel` + `MacDictationOverlayController` 三件套已足够** |
| **PiP keep-alive** | macOS 无系统 PiP。`MacDictationOverlayController` 的 NSPanel 已占位 |
| **Rime / 拼音 / 英文 autocorrect** | Mac 不是键盘扩展，没输入面。`LibrimeEngine` 是 iOS C/Objective-C++ xcframework，**Mac 结构性不兼容**。即便 Mac 装键盘扩展（`Designed for iPad` 那种），librime 也需要重编译 |
| **`UIBackgroundModes: audio`** | Mac 没用——按住说话时 NSPanel 是 non-activating，不需要 audio session 后台保持 |
| **`UIOpenURLContext.options.sourceApplication`** | iOS 26 only API；Mac 走 `NSWorkspace.didActivateApplicationNotification` 已解决前台 App 跟踪 |
| **`AVAudioApplication.requestRecordPermission`** | iOS 17+ only；Mac 走 `AVCaptureDevice.requestAccess(for: .audio)` |
| **App Group 跨进程 mailbox** | Mac 单进程不需要。但 `AppGroup` + iCloud KVS 是用户态多设备同步用的，**保留** |
| **iOS 风格的 idle 屏** | Mac 主窗口即 dashboard，不需要 idle 屏的"AI hint 轮播"；但 `MacAIHintPool` 屏可以放在 Dashboard 顶部，与 P2 联动 |
| **`LSApplicationQueriesSchemes`** | iOS only，Mac 无 `canOpenURL` 限制 |
| **`SKIncludeConsumableInAppPurchaseHistory` / Mac storekit 文件** | Mac App Store 与 iOS App Store 独立 SKU；目前 Mac 装包是 Developer ID 渠道，**不进 Mac App Store**，所以 storekit 不需要 |

---

## 4. 适合在 Mac 上做开发和移植的功能

### 4.1 应该现在做的（P0）

#### ① 剪贴板历史 + AI 技能面板

**为什么 Mac 适合**：共享代码 100% 到位（`ClipboardHistoryStore` / `ClipboardSemanticAnalyzer` / `ClipboardSkillSemanticRanker` / `AIClipboardSkill` / `AIClipboardPrompt`），iOS 8 个 UI 调试稳定，只需套 Mac 风格。

**具体工作**：
- 新增 `OSGKeyboardMac/Views/MacClipboardHistoryView.swift`（仿 `MacHistoryView`）
- 新增 `OSGKeyboardMac/Views/MacAIClipboardSkillView.swift`（仿 `AIAgentSkillsView`，精简为 Read/Edit/Disable）
- `MacSettingsView.swift` 加 `clipboardSection`（含 toggle 启用历史 / toggle 启用技能候选条 / "Manage Skills" 链接 / "Open History" 链接）
- `MacDictationViewModel` 订阅 `ClipboardHistoryStore.entries`（`@Published var clipboardEntries`）
- 复用 `ClipboardCaptureCoordinator` 不可（ext-only）——需要 Mac 端 `MacClipboardMonitor`（`NSPasteboard.general.changeCount` 轮询 + sanitize）

**测试**：`MacClipboardMonitorTests`（用 in-memory pasteboard 模拟）/ `MacClipboardHistoryViewModelTests`

**工作量**：1-2 周

#### ② CLM 设置页

**为什么 Mac 适合**：Mac 后台已经在跑 CLM（`OSGKeyboardMacApp:117`），只是用户管不到。

**具体工作**：
- 新增 `OSGKeyboardMac/Views/MacCLMSettingsView.swift`（仿 `MacLocalASRModelSettingsView`）
- 复用 `CustomLanguageModelManager.shared.state`（`@Published idle/preparing/ready/failed`）
- 复用 `OSGKeyboard/Resources/HostCLM/v1/OSGKeyboardCLM.bin`（已在 Mac 装包）
- 复用 `PersonalDictionary` 共享存储（用户输入的 phrase 库 + iCloud 同步）
- 提供 phrase 列表 / 编辑 / 触发"重编译"按钮

**测试**：`MacCLMSettingsViewModelTests`（验 `state` 状态机）

**工作量**：1 周

### 4.2 应该中期做的（P1）

#### ③ OSG 账户 + Sign in with Apple + 积分购买

**为什么 Mac 适合**：共享代码编进 Mac 都没报错，缺的是 entitlement + UI。

**先决条件**：
- `OSGKeyboardMac.entitlements` 加 `com.apple.developer.applesignin: [Default]`
- `OSGKeyboardMac/Info.plist` 加 `SKIncludeConsumableInAppPurchaseHistory: true`
- （选做）把 `OSGKeyboard.storekit` 内容 mirror 到 `OSGKeyboardMac.storekit` 或共享

**具体工作**：
- 加 `MacAccountCenterView`（仿 iOS `AccountCenterView` 但精简）
- 复用 `LiveAccountServices` / `AccountSessionCoordinator`（`@MainActor` state machine）
- 复用 `AccountCreditPurchaseManager`（StoreKit 2 product list → 服务器校验）
- Settings → 加 "Account" 段，含 sign-in / 积分余额 / 购买历史 / 登出 / 删号

**测试**：`MacAccountSessionCoordinatorTests`（in-memory `AccountAPIClient` fake）

**工作量**：2-3 周

#### ④ Mac App Attest / DeviceCheck

**为什么 Mac 适合**：iOS attestation 后端已经在用，Mac 端可以通过 `DCAppAttestService`（macOS 13+，需要 Mac Catalyst 但当前 `SUPPORTS_MACCATALYST: NO`）或者改用 DeviceCheck `DCDevice.generateToken`（macOS 13+ available without Catalyst）。

**先决条件**：
- `OSGKeyboardMac.entitlements` 加 `com.apple.developer.devicecheck.appattest-environment: $(APP_ATTEST_ENVIRONMENT)`
- 若走 App Attest，需要 `SUPPORTS_MACCATALYST: YES`（改大改）或改 DeviceCheck-only

**具体工作**：
- `MacDeviceIntegrityCoordinator`（仿 iOS，但用 `DCDevice`）
- `AccountAPIClient` 复用，调 `/v1/integrity/attest`

**工作量**：1-2 周（仅 Mac）；+ Catalyst 决策时间

### 4.3 应该长期做的（P2）

#### ⑤ 一方分析（Mac）

**为什么 Mac 适合**：Mac 用户行为和 iOS 同样有价值（知道用户用不用 MLX 模式、热键触发频率、词条覆盖、润色样式流行度）。

**先决条件**：
- 共享 `AnalyticsClient` / `AnalyticsRepository` 已经完备
- Mac 上加 `MacAnalyticsHostService`（仿 iOS）：监听 `viewModel.$isRecording/$isPreparingToRecord/$isProcessing` 推送事件
- 隐私 / opt-in：在 onboarding 末加一步

**挑战**：
- Mac 后台无 `BGTaskScheduler`——改用 `NSProcessInfo.thermalState` + `ProcessInfo.isLowPowerModeEnabled` 节流，**或** `SMAppService` 拉个 LaunchAgent
- `AnalyticsUploadCoordinator` 的移动策略（threshold 20 / 60s flush）要 Mac 化

**工作量**：3-4 周

#### ⑥ AI 提示轮播 / 上下文技能

**为什么 Mac 适合**：Mac dashboard 缺内容——除了使用统计，闲置时可推"想一句"灵感卡。

**具体工作**：
- `MacAIHintPool` 嵌在 `DashboardView` 顶部（仿 iOS `AIKeyboardView` 的 carousel 区域）
- 复用 `AIHintStore` / `AIHintPool` / `AIHintKeywordExtractor` / `AIHintLocalCatalog`
- 上下文技能入口放 `MacContentView`（popover 内 record 按钮旁的下拉）

**工作量**：2-3 周

#### ⑦ 助手指令集成

**为什么 Mac 适合**：Mac 上有 Shortcuts.app（更成熟），bundled `.shortcut` 装入 Mac App bundle 即可。

**具体工作**：
- 装 `OSGKeyboard/Resources/Shortcuts/*.shortcut` 进 Mac bundle
- 复用 `AIAgentShortcutInstaller` / `AIAgentShortcutRun`
- popover / dashboard 加技能快捷入口

**工作量**：1-2 周

### 4.4 不应该在 Mac 做的（但代码可以清理）

| 共享代码 | 为什么不该在 Mac 跑 | 处置 |
|---|---|---|
| `OSGKeyboardHostSupport/Features/Account/*`（Mac 已编） | App Attest 路径 iOS 专属；Mac 没 entitlement | 等 ④ 决策后从 Mac target 排除或接 UI |
| `OSGKeyboardShared/Features/Analytics/*`（Mac 已编） | 无 Mac 端调用 | 等 ⑤ 决策后从 Mac target 排除或接服务 |
| `OSGKeyboardShared/Features/ManagedGateway/*`（Mac 已编） | 是账户 grant 体系，与 ③ 绑定 | 等 ③ 决策后处理 |
| `OSGKeyboardShared/Services/AIClipboard*`（Mac 已编） | 与 ① 绑定 | ① 实现后从"无调用"变"有调用" |
| `OSGKeyboardShared/Services/AIHint*`（Mac 已编） | 与 ⑥ 绑定 | 同上 |
| `OSGKeyboardShared/Services/AIUserSkill*` / `AIAgentSkill*`（Mac 已编） | 与 ③⑦ 绑定 | 同上 |
| `OSGKeyboardShared/Services/Flow*`（Mac 已编） | Mac 架构不兼容 | **立刻**从 Mac target 排除（白付编译器开销） |
| `OSGKeyboardShared/Services/KeyboardState.swift`（Mac 已排除）| 已经是 Mac 排除 ✓ | 无 |
| `OSGKeyboardShared/Services/EditTransactionStore.swift` 等 | 与"最后输入编辑"绑定 | 见 P3 |

### 4.5 立即可清的"白编译"清单

```
OSGKeyboardShared/Services/FlowSessionBridge.swift + 所有 +* 文件
OSGKeyboardShared/Services/FlowSessionKeys.swift
OSGKeyboardShared/Services/FlowSessionDarwin.swift
OSGKeyboardShared/Services/FlowSessionPolicy.swift
OSGKeyboardShared/Services/FlowStartTransactionPolicy.swift
OSGKeyboardShared/Services/FlowKeyboardPolicies.swift
OSGKeyboardShared/Services/FlowHandoffPolicy.swift
OSGKeyboardShared/Services/UtteranceStreamChunker.swift
OSGKeyboardShared/Services/UtteranceBatchFallbackPolicy.swift
OSGKeyboardShared/Services/UtteranceTranscriptGuard.swift
OSGKeyboardShared/Services/UtteranceTranscriptStitcher.swift
OSGKeyboardShared/Services/TranscriptOverlapUtilities.swift
OSGKeyboardShared/Services/ProgressiveDictationTranscriptAccumulator.swift  # 已排除
OSGKeyboardShared/Services/EditTransactionStore.swift
OSGKeyboardShared/Services/EditUsageMetricsStore.swift
OSGKeyboardShared/Services/EditLastInputPromptComposer.swift
OSGKeyboardShared/Services/EditOutputValidator.swift
OSGKeyboardShared/Models/Flow*.swift (全部)
OSGKeyboardShared/Models/EditableInputReference.swift
OSGKeyboardShared/Models/EditSessionState.swift
OSGKeyboardShared/Models/FlowUtterance*.swift
OSGKeyboardShared/Models/FlowInactivityDuration.swift
OSGKeyboardShared/Utilities/FlowCaptureTailDrain.swift
OSGKeyboardShared/Utilities/FlowUtteranceEndCoordinator.swift
OSGKeyboardShared/Utilities/FlowUtterancePCMStore.swift
OSGKeyboardShared/Utilities/FlowTrace.swift
OSGKeyboardShared/Utilities/FlowPipelineDiagnostics.swift
OSGKeyboardShared/Utilities/HostMemoryBudget.swift
OSGKeyboardShared/Utilities/KeyboardExtensionMemoryTelemetry.swift  # 已排除
OSGKeyboardShared/Features/Analytics/  # 全部 12+ 文件
OSGKeyboardShared/Features/ManagedGateway/  # 全部 8+ 文件
OSGKeyboardHostSupport/Features/Account/  # 全部
OSGKeyboardHostSupport/Services/CloudASR/AlibabaVocabularySync.swift  # iOS-only API
OSGKeyboardHostSupport/Services/ASRChunkTranscribing.swift  # 需检查
```

（**建议**）：在 `project.yml:558-602` 给 Mac target 的 source list 加 `excludes:`，避免编译这些文件后被链接器裁掉造成的 dead-code 体积。

---

## 5. iOS 端需要"修一下"或注意的地方

报告主体是 macOS 差距，但 iOS 端顺手列出 5 个明显可改进点（不修不影响功能，但提升质量）：

1. **`OSGKeyboardHostSupport/Features/Account/*` 整块**虽然不通过 Mac UI 暴露，但通过 source include 编进 Mac 二进制——长期应从 Mac target 排除或加 `MacAccountServices` 实际使用
2. **`OSGKeyboardShared/Features/Analytics/*`** 同上——Mac 编译进二进制但无任何调用
3. **`OSGKeyboardShared/Features/ManagedGateway/*`** 同上
4. **`project.yml:570-602`** 的 Mac target source list 很长且依赖手写排除，**建议**拆出 `OSGKeyboardMacExcludes.yml` 维护
5. **`OSGKeyboardShared/Typing/EnglishSystemLexicon.swift:11`** 是**唯一**有 `import UIKit` 的 Shared 文件——是 iOS ext 独享的 QuickType 数据源。考虑改名/移动到 `OSGKeyboardExt/` 减面
6. **iOS `FlowSessionManager` ~3500 LOC** 是单一 god object；建议把 `FlowPictureInPictureController` / `FlowTerminationCoordinator` / `FlowAnalyticsOperationRegistry` 三个生命周期拥有者抽离
7. **iOS `appDelegate` 反弹 `.onOpenURL`** (`AppURLHandler.swift`) 注释里写 `UIOpenURLContext.options.sourceApplication` iOS 26 only——这个 API 在 iOS 26 还在吗？值得 verify（影响 deep-link host-return 白名单）
8. **`KeyboardViewController` `didReceiveMemoryWarning` (`:390-404`)** 强制回 voice surface——typing 引擎是最大内存消费者，但每次收到警告就退出 typing 体验略激进；考虑加 cooldown

---

## 6. 实施建议

### 6.1 短期（未来 1-2 周）

- **任务 A：从 Mac target 排除 `Flow*` / `Edit*` / `Analytics*` / `ManagedGateway*` / `Account*`（HostSupport）所有共享代码**
  - 修改 `project.yml:570-602`，加 `excludes:` 列表
  - 验证 Mac target 仍能 build & test pass
  - 节省 Mac 二进制 ~2-4 MB + 减少编译时间 ~10-15s
- **任务 B：Mac 剪贴板历史 + AI 技能面板**（P0 ①）
- **任务 C：Mac CLM 设置页**（P0 ②）

### 6.2 中期（1-2 月）

- **任务 D：OSG 账户 + Sign in with Apple + 积分**（P1 ③）
- **任务 E：App Attest 决策 + 实施**（P1 ④）

### 6.3 长期（3-6 月）

- **任务 F：Mac 一方分析**（P2 ⑤）
- **任务 G：AI 提示轮播 / 上下文技能**（P2 ⑥）
- **任务 H：助手指令集成**（P2 ⑦）

### 6.4 决策项

| 决策 | 选项 | 影响 |
|---|---|---|
| **App Attest 路径** | (a) Catalyst + `DCAppAttestService`（macOS 13+）<br>(b) 仅 `DCDevice.generateToken`（无 attestation）<br>(c) 不做 | (a) 需开 `SUPPORTS_MACCATALYST: YES` 改大改；<br>(b) 安全性较弱但改动小；<br>(c) Mac 不在 attestation 内 |
| **Mac 走 Mac App Store 还是 Developer ID** | (a) 维持 Developer ID（现状）<br>(b) 走 Mac App Store | (a) 维持沙盒关闭，Accessibility 自由；<br>(b) 需重写热键 + 注入方案（沙盒内 Accessibility 拿不到） |
| **是否上 Rime 替代方案** | (a) 不做（Mac 不是键盘）<br>(b) 内部输入法，绕过 librime | (b) 工作量极大，且与产品形态不符 |
| **Mac 是否支持 iOS 风格的"on-device + cloud hybrid"** | (a) 仅 engine-mode toggle（现状）<br>(b) 支持每句 hybrid（local first，失败 fallback cloud） | (b) 需要重新设计 MLX streaming 端 |

---

## 7. 关键引用

| 主题 | 文件 | 行号 |
|---|---|---|
| iOS 宿主入口 | `OSGKeyboard/OSGKeyboardApp.swift` | 1 |
| iOS Flow 单一拥有者 | `OSGKeyboard/Services/FlowSessionManager.swift` | 1 (~3500 LOC) |
| iOS 键盘入口 | `OSGKeyboardExt/KeyboardViewController.swift` | 33-38 |
| iOS 键盘生命周期 | `OSGKeyboardExt/KeyboardViewController.swift` | 148-655 |
| iOS 共享 ASR 协议 | `OSGKeyboardShared/Services/PolishingService.swift` | 34-105 |
| iOS HostSupport ASR 工厂 | `OSGKeyboardHostSupport/Services/ASRService.swift` | 1 |
| iOS HostSupport 云 ASR 工厂 | `OSGKeyboardHostSupport/Services/CloudASR/CloudASRClientFactory` | 44 |
| Mac 入口 | `OSGKeyboardMac/OSGKeyboardMacApp.swift` | 1 |
| Mac MLX 流式 provider | `OSGKeyboardMac/MacMLXStreamingASRProvider.swift` | 1 |
| Mac MLX 流式 session | `OSGKeyboardMac/MacMLXStreamingSession.swift` | 1 |
| Mac MLX 实时捕获编排 | `OSGKeyboardMac/MacMLXLiveCapture.swift` | 1 |
| Mac 热键 | `OSGKeyboardMac/MacHotkeyService.swift` | 1 |
| Mac 文本注入 | `OSGKeyboardMac/MacTextInsertionService.swift` | 1 |
| Mac 音频 | `OSGKeyboardMac/MacAudioRecorder.swift` | 1 |
| Mac 字幕过滤器 | `OSGKeyboardMac/MacHallucinationFilter.swift` | 1 |
| Mac 字典流水线 | `OSGKeyboardMac/MacDictationPipeline.swift` | 254 |
| Mac 模型目录 | `OSGKeyboard/Resources/LocalASR/local-asr-catalog.json` | 1-111 |
| Mac target 定义 | `project.yml` | 543-674 |
| Mac target 共享 source 排除 | `project.yml` | 558-602 |
| Mac entitlements | `OSGKeyboardMac/OSGKeyboardMac.entitlements` | 1 |

---

## 8. 附录：版本与里程碑

| 版本 | 日期 | 关键 Mac 相关变更 |
|---|---|---|
| 2.0.1 (build 90) | 2026-08-21 | (无 Mac-specific changelog 条目) |
| 2.0.0 (build 85) | 2026-08-19 | "Optional OSG account"（iOS only，但相关 HostSupport 代码编进 Mac）|
| 1.8.0 (build 72) | 2026-08-14 | "Mac Styles / Settings follow the same pairing"（设计系统共用）+ "Mac model downloads"（**MLX 模型下装载入**）|
| Pre-1.8.0 | — | Sherpa → MLX 迁移（`MacOnboardingView.swift:7-8` 注释）|

---

**报告完。**  
下次更新窗口：2026-09-XX 复审 P0 ① ② 实施情况 + 决策项 6.4 落地。
