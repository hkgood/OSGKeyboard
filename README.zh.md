# OSGKeyboard

> 按住说话，松开即得 AI 润色文字，插入任意 App 的光标处。
> 一款开源的 iOS 自定义键盘语音输入工具，灵感来自 [Typeless](https://typeless.com) 和 [OpenLess](https://github.com/Open-Less/openless)。

![Platform](https://img.shields.io/badge/platform-iOS%2018%2B-0078D4?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift)
![License](https://img.shields.io/badge/license-MIT-green)

[English README](./README.md)

---

## 这是什么？

OSGKeyboard 是商业语音输入工具的免费开源替代。它以 **iOS 自定义键盘扩展** 的形式运行，所以你可以在 **任何 App** 里使用 —— 微信、备忘录、邮件、ChatGPT、Claude、Cursor，无所不能。

1. 长按麦克风键
2. 自由说话
3. 松开 —— AI 帮你整理成干净的文字，自动插入光标处

**音频始终在设备本地转写**（iOS 18/19 用 `SFSpeechRecognizer`；iOS 26+ 的 `SpeechAnalyzer` 计划下版接入），**只有润色后的文本** 会发到你选择的云端 LLM。**音频永不离开你的手机。**

---

## 特性

- 🎙 **按住说话**，Typeless 风格的圆形麦克风按钮
- 🧠 **端侧 ASR**（iOS 18/19 `SFSpeechRecognizer`；iOS 26+ 的 `SpeechAnalyzer` + `DictationTranscriber` 计划下版接入）
- ✍️ **AI 润色** —— 自动加结构、补标点、修正语法、可生成列表
- 🔌 **自带 API 接入** —— 兼容任何 OpenAI 兼容协议端点（OpenAI / DeepSeek / Qwen DashScope / 自建服务器 ……）
- 🔒 **隐私优先** —— 音频不离开设备；只有润色文本会发给你选择的 LLM
- 🎨 **原生 SwiftUI** —— 暗色主题、毛玻璃、约 2000 行 Swift
- 🪶 **零依赖** —— 无 SwiftPM 包、无 CocoaPods、无 Carthage

---

## 快速开始

### 环境要求

- macOS + **Xcode 16+**（推荐 Xcode 26）
- iPhone 运行 **iOS 18.0+**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`
- 一个 OpenAI 兼容 API Key（[OpenAI](https://platform.openai.com/api-keys) / [DeepSeek](https://platform.deepseek.com/api_keys) / [Qwen DashScope](https://dashscope.console.aliyun.com/apiKey) 任一）

### 编译与运行

```bash
git clone https://github.com/<你的用户名>/OSGKeyboard.git
cd OSGKeyboard
xcodegen generate          # 生成 OSGKeyboard.xcodeproj
open OSGKeyboard.xcodeproj # 或命令行编译：
xcodebuild -project OSGKeyboard.xcodeproj -scheme OSGKeyboard \
  -destination 'generic/platform=iOS Simulator' build
```

### 在 iOS 中启用键盘

1. 在真机/模拟器上运行 App。
2. 按 3 步引导：**启用键盘** → **允许完全访问**（麦克风 + LLM 调用必须） → **粘贴 API Key**。
3. 在任意输入框，点 🌐 切换到 **OSGKeyboard**。
4. 长按麦克风键 → 说话 → 松开。✨

> **"允许完全访问"是必须的。** 没有它，iOS 会阻止键盘使用麦克风与网络。我们**绝不记录、存储或上传你的击键** —— 见 [`PrivacyInfo.xcprivacy`](./OSGKeyboard/PrivacyInfo.xcprivacy)。

---

## 架构

```
OSGKeyboard/
├── OSGKeyboard/                 # 主 iOS App（设置、Onboarding）
│   ├── Views/                   # SwiftUI 屏幕
│   ├── OSGKeyboardApp.swift     # @main 入口
│   ├── PrivacyInfo.xcprivacy    # 隐私清单
│   └── OSGKeyboard.entitlements # App Group 声明
├── OSGKeyboardExt/              # 自定义键盘扩展
│   ├── KeyboardViewController.swift   # 主体类
│   ├── Services/
│   │   ├── AudioCaptureService.swift  # AVAudioEngine → 16kHz PCM
│   │   ├── ASRService.swift           # iOS 26 + iOS 18 ASR
│   │   └── PolishingService.swift     # LLM 调用（带超时）
│   └── Views/                   # 录音按钮、波形、键盘主视图
├── OSGKeyboardShared/           # 主 App + 键盘共享 framework
│   ├── Models/                  # ProviderConfig、LLMRequest、LLMProvider
│   ├── Services/                # LLMClient（OpenAI 兼容）
│   └── Constants/               # App Group ID
├── OSGKeyboardTests/            # XCTest 单元测试
├── project.yml                  # XcodeGen 工程定义
└── .github/workflows/ci.yml     # Lint + 编译 CI
```

### 数据流

```
[长按麦克风] → AudioCaptureService → AudioBufferSnapshot (16kHz mono)
                                        ↓
                                ASRService.transcribe()
                                        ↓
                          ASREvent.final(原始转写文本)
                                        ↓
                          PolishingService.polish()
                                        ↓
                        LLMClient（OpenAI 兼容协议）
                                        ↓
                   textDocumentProxy.insertText(润色后文本)
```

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

---

## 限制

- iOS 沙盒：键盘扩展 ~60 MB 内存上限，必须开完全访问
- 密码框与部分 `WKWebView` 输入框不可用（iOS 限制）
- iOS 18/19 用 `SFSpeechRecognizer` 做端侧 ASR；iOS 26+ 的 `SpeechAnalyzer` 计划下版接入（更快、支持语种更多）
- v0.1.1 中 iOS 26+ 用户仍走 iOS 18 `SFSpeechRecognizer` 路径；iOS 26 `SpeechAnalyzer` 计划在 0.2.0 接入

---

## 许可

[MIT](./LICENSE) —— 使用、修改、商用均可。无任何担保。

---

## 致谢

- 灵感来源：[Typeless](https://typeless.com) 与桌面端开源版 [OpenLess](https://github.com/Open-Less/openless)
- 工程脚手架：[XcodeGen](https://github.com/yonaskolb/XcodeGen)
- 端侧 ASR：Apple [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer) / [SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer)

---

**注意**：把 `<你的用户名>` 替换成你的 GitHub 用户名。
