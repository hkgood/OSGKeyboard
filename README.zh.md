# OSGKeyboard

> 按一下开始，再按一下结束 —— AI 润色文字直接出现在任意 App 的光标处。
> 一款源码可见的 iOS 自定义键盘语音输入工具，灵感来自 [Typeless](https://typeless.com) 和 [OpenLess](https://github.com/Open-Less/openless)。

![Platform](https://img.shields.io/badge/platform-iOS%2026%2B-0078D4?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift)
![License](https://img.shields.io/badge/license-Source%20Available-blue)
![Version](https://img.shields.io/badge/version-0.2.1-3aa05a)

[English README](./README.md) · [隐私政策](https://hkgood.github.io/OSGKeyboard/privacy/)

---

## 这是什么？

OSGKeyboard 是商业语音输入工具的免费、源码可见替代方案。它以 **iOS 自定义键盘扩展** 的形式运行，所以你可以在 **任何 App** 里使用 —— 微信、备忘录、邮件、ChatGPT、Claude、Cursor，无所不能。

1. 按下麦克风键开始录音
2. 自由说话（单次上限 3.5 分钟 / 210 秒）
3. 再按一下结束 —— AI 自动整理成干净的文字并插入光标

默认情况下，**音频在设备本地转写**（iOS 26+ 的 `SpeechAnalyzer` + `DictationTranscriber`）——**除非你主动选择，音频不会离开你的手机**；开启润色时也只有文本会发到你选择的 LLM。你也可以显式切换到**云端识别引擎**（需二次确认的 opt-in）：该模式下你的录音会上传到你配置的识别服务商。

项目内部采用 **Flow 会话模型**：主 App 维护一个长生命周期的音频会话，键盘扩展只通过 App Group 写入"开始 / 停止"等轻量信号，润色后的文本再由主 App 回传给键盘插入。**多次录音之间无需反复跳回主 App**。

---

## 特性

- 🎙 **点按录音** —— Typeless 风格的圆形麦克风按钮，单次上限 3.5 分钟（210 秒）并实时倒计时
- 🧠 **端侧 ASR**（iOS 26+ `SpeechAnalyzer` + `DictationTranscriber`）
- ✍️ **AI 润色** —— 自动加结构、补标点、修正语法、可生成列表
- 🧩 **本地 + 云端润色开关** —— 本地模式默认仅在设备上识别；若 iOS 语音识别效果不理想（远场、噪声、方言），可开启「识别后云端润色」，默认走 DeepSeek
- 🔌 **自带 API 接入** —— 兼容任何 OpenAI 兼容协议端点（OpenAI / DeepSeek / Qwen DashScope / Moonshot / 智谱 / 自建服务器 ……）
- 🔒 **隐私优先** —— 默认端侧识别，音频不离开设备（除非显式开启云端识别引擎）；润色只发送文本给你选择的 LLM
- 🎨 **原生 SwiftUI** —— 暗色主题、毛玻璃、纯 Swift 6 实现，约 3,600 行代码
- 🪶 **零依赖** —— 无 SwiftPM 包、无 CocoaPods、无 Carthage
- 🔁 **Flow 会话** —— 多次录音无需跳回主 App，会话自动维持心跳与续期

---

## 快速开始

### 环境要求

- macOS + **Xcode 26**（与 `project.yml` 中 iOS 26 部署目标对齐）
- iPhone 运行 **iOS 26.0+**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`
- 一个 OpenAI 兼容 API Key（[OpenAI](https://platform.openai.com/api-keys) / [DeepSeek](https://platform.deepseek.com/api_keys) / [Qwen DashScope](https://dashscope.console.aliyun.com/apiKey) 任一）。如果一直使用「纯本地 ASR」引擎则无需 Key。

### 编译与运行

```bash
git clone https://github.com/hkgood/OSGKeyboard.git
cd OSGKeyboard
./Scripts/generate-xcodeproj.sh   # 通过 XcodeGen 生成 OSGKeyboard.xcodeproj
open OSGKeyboard.xcodeproj        # 或命令行编译：
xcodebuild -project OSGKeyboard.xcodeproj -scheme OSGKeyboard \
  -destination 'generic/platform=iOS Simulator' build
```

> `OSGKeyboard.xcodeproj` **不进入版本库**，由 `Scripts/generate-xcodeproj.sh` 从 `project.yml` 生成。每次 `git pull` 后若 `project.yml` 有变更，请重新执行该脚本。

### 在 iOS 中启用键盘

主 App 会引导你走完 **5 步**：

1. **欢迎** —— 介绍 OSGKeyboard
2. **麦克风** —— 申请麦克风权限
3. **语音识别** —— 申请端侧语音识别权限
4. **启用键盘 + 完全访问** —— 跳转 iOS 设置添加 OSGKeyboard 并允许完全访问
5. **引擎 + API** —— 选择本地或云端引擎，粘贴 API Key（仅云端 / 识别后云端润色需要）

完成后，在任意输入框点 🌐 切换到 **OSGKeyboard**，再点圆形麦克风键开始说话，再次点击结束。

> **"允许完全访问"是必须的。** 没有它，iOS 会阻止键盘使用麦克风与网络。我们**绝不记录、存储或上传你的击键** —— 见 [`PrivacyInfo.xcprivacy`](./OSGKeyboard/PrivacyInfo.xcprivacy) 与 [隐私政策](https://hkgood.github.io/OSGKeyboard/privacy/)。

---

## 架构

```
OSGKeyboard/
├── OSGKeyboard/                 # 主 iOS App（Flow 会话宿主）
│   ├── Services/                # FlowSessionManager、AppPermissions、SpeechHistoryStore、…
│   ├── Views/                   # SwiftUI：OnboardingView、HomeView、SettingsView、HistoryView、…
│   ├── OSGKeyboardApp.swift     # @main 入口，持有 FlowSessionManager
│   ├── PrivacyInfo.xcprivacy    # 隐私清单
│   └── OSGKeyboard.entitlements # App Group + Keychain Group
├── OSGKeyboardExt/              # 自定义键盘扩展
│   ├── KeyboardViewController.swift   # 主体类（驱动 SwiftUI）
│   ├── Services/                # AppGroupPersistor、HostAppLauncher、AudioCaptureService（旧版，未使用）
│   ├── Views/                   # KeyboardRootView、RecordButton、WaveformView
│   └── PrivacyInfo.xcprivacy
├── OSGKeyboardShared/           # 主 App + 键盘共享 framework（APPLICATION_EXTENSION_API_ONLY=YES）
│   ├── Services/                # FlowSessionBridge、FlowSessionDarwin、LLMClient、PolishingService、ASRService、Keychain、AppGroupStore、…
│   ├── Models/                  # LLMProvider、ProviderConfig、TranscriptionDelivery、AudioBufferSnapshot、…
│   ├── DesignSystem/            # Theme、ThemedRoot
│   └── Constants/               # AppGroup ID
├── OSGKeyboardTests/            # XCTest 单元测试（LLM、Keychain、ASR、Flow bridge、…）
├── OSGKeyboardExtTests/         # 键盘扩展侧单元测试
├── Scripts/                     # generate-xcodeproj.sh、patch-icon-composer.sh
├── docs/                        # GitHub Pages（隐私政策 + 落地页）
├── project.yml                  # XcodeGen 工程定义（唯一源）
└── .github/workflows/ci.yml     # Lint + 编译 CI
```

### 数据流 —— Flow 会话模型

```
[键盘点按麦克风]
  └─► KeyboardViewController.pressBegan
        └─► FlowSessionBridge.setRecordingState(.recording)  [App Group UserDefaults]
        └─► Darwin 通知："recordingState changed"
              └─► 主 App 的 FlowSessionManager 收到信号
                    └─► FlowContinuousCapture 持续把 16kHz PCM 喂给 ChunkedUtterancePipeline
                          └─► ASRService.transcribe（iOS 26 SpeechAnalyzer）
                                └─► ASREvent.partial / .final
                                      └─► UtteranceTranscriptStitcher 拼接
                                            └─► PolishingService（LLMClient）  [可选，由引擎模式决定]
                                                  └─► FlowSessionBridge.storeTranscriptionResult
[键盘轮询 + Darwin 通知]
  └─► KeyboardViewController 拿到结果
        └─► textDocumentProxy.insertText(润色后文本)
```

**引擎模式：**

- `local`（默认）—— 仅端侧 `SpeechAnalyzer` 识别，原始文本直接插入，不联网。
- `local` + 「识别后云端润色」开关（设置 → 引擎）—— 同样走端侧 ASR，但识别完成后送 LLM 润色（仅文本）再插入。适用于 iOS 识别效果不理想的场景。
- `cloud`（opt-in，需显式确认）—— **你的语音录音会上传**到你配置的识别服务商（如 OpenAI `/audio/transcriptions`、DashScope、智谱），识别文本再送 LLM 润色。请在接受服务商隐私条款的前提下选用。

**跨进程管道（主 App ↔ 键盘扩展）：**

- **App Group `group.com.osgkeyboard.shared`** —— `UserDefaults` 存放 Flow 会话状态、录音状态、音量、转写投递、绝大部分偏好。
- **共享 Keychain 组 `com.osgkeyboard.shared`** —— LLM API Key 由主 App「设置」写入，键盘扩展在每次 LLM 调用前读取。
- **Darwin 通知（`CFNotificationCenter`）** —— 轻量级"有变化"信号；具体负载仍走 App Group。

---

## 新增 LLM 提供商

打开 `OSGKeyboardShared/Models/LLMProvider.swift`，在 `presets` 数组里追加一条 `LLMProvider` 即可。默认的 `OpenAICompatibleClient` 处理任何实现了 `POST /chat/completions` 的端点。

```swift
LLMProvider(
    id: "groq",
    name: "Groq",
    defaultBaseURL: "https://api.groq.com/openai/v1",
    defaultModel: "llama-3.1-70b-versatile",
    apiKeyURL: URL(string: "https://console.groq.com/keys")
)
```

仅此而已，**无需改动其他代码**。

如需设为新用户的默认值，还需同步调整 `ProviderConfig` 中的 `defaultProviderId` 常量。

---

## 已知限制

- **仅支持 iOS 26+。** 我们已移除 26 以下 `SFSpeechRecognizer` / `AVAudioSession` 的兼容分支，让 ASR 路径全部走 iOS 26 `SpeechAnalyzer`。
- **键盘扩展约 60 MB 内存上限**（iOS 沙盒）。Flow 会话由主 App 承载，音频缓冲与 ASR 模型都在主 App 侧，不占用扩展内存。
- **必须「允许完全访问」**。否则键盘无法使用麦克风，也无法发起云端润色请求。
- **密码框与部分 `WKWebView` 输入框不可用**（iOS 系统限制，无法绕过）。
- **单次录音上限 3.5 分钟（210 秒）**。到点自动停止并提交识别，下次可立即开始新的录音。
- **杀掉主 App 后不复活旧会话**。灵动岛会立即清理；下次回到主 App 时（权限齐全）自动开启新的语音会话。
- **单次 utterance ASR 上限 3 分钟**。超出后会拆成多个 chunk 拼接识别。
- **不做端侧 LLM 润色**。本地引擎仅做 ASR；"AI 润色"始终走云端、可配置。v0.2.0 曾尝试引入端侧模型，v0.2.1 回滚以保持零 SPM 依赖。
- **URL Scheme `osgkeyboard://`** 任何 App 都可调用。OSGKeyboard 只把它用于"唤醒主 App / 续期 Flow 会话"，**不** 传递 API Key 等敏感信息。

---

## 开发指南

- **构建** —— 见本文开头的 [编译与运行](#编译与运行) 节。`project.yml` 变更后请重新执行 `./Scripts/generate-xcodeproj.sh`。
- **测试** —— `xcodebuild test -project OSGKeyboard.xcodeproj -scheme OSGKeyboard -destination 'platform=iOS Simulator,name=iPhone 17'` 会同时跑 `OSGKeyboardTests` 与 `OSGKeyboardExtTests` 两个 target。
- **CI** —— `.github/workflows/ci.yml` 在每次 push 到 `0.1` / `0.2` 分支及 PR 时跑 SwiftLint、Debug 干净构建和测试套件。
- **日志** —— `print` 仅在 Debug 启用；Release 仅保留少量跨进程状态相关的 `NSLog`。

---

## 项目状态

- **当前版本：v0.2.1**（2026-06-24）
- **默认分支：`0.2`**（2026-06-24 从 `main` 改名；旧 `main` 保留为 `0.1`）。
- 完整发布记录见 [`CHANGELOG.md`](./CHANGELOG.md)；Flow 会话模型的架构决策日志见 [`TYPEWHISPER_FLOW_MIGRATION_TRACKER.md`](./TYPEWHISPER_FLOW_MIGRATION_TRACKER.md)。

---

## 许可

[OSGKeyboard 源码可见许可协议](./LICENSE) —— 仅限个人学习与非商用本地使用；禁止商用、再分发及公开 fork。商业授权请联系 [rocky.hk@gmail.com](mailto:rocky.hk@gmail.com)。

---

## 致谢

- 灵感来源：[Typeless](https://typeless.com) 与桌面端开源版 [OpenLess](https://github.com/Open-Less/openless)
- 工程脚手架：[XcodeGen](https://github.com/yonaskolb/XcodeGen)
- 端侧 ASR：Apple [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer) / [SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer)
