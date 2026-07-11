# OSGKeyboard

**开口即文字。**

在 iPhone、iPad 和 Mac 上，用说的代替打字。任意 App 里开口，润色好的文字直接落到光标处。

![Platform](https://img.shields.io/badge/iOS%20%2F%20iPadOS-26%2B-0078D4?logo=apple)
![Platform](https://img.shields.io/badge/macOS-14%2B-555?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift)
![Version](https://img.shields.io/badge/version-0.5.3-3aa05a)
![License](https://img.shields.io/badge/license-Source%20Available-blue)

[官网](https://hkgood.github.io/OSGKeyboard/) · [English](./README.en.md) · [隐私政策](https://hkgood.github.io/OSGKeyboard/privacy/)

---

## 为什么用它

- **真的随处可用** — 微信、备忘录、Notion、Cursor、邮件……光标在哪，文字就落在哪
- **说完就能用** — 点按（iOS）或按住 Option（Mac）开口，AI 自动补标点、整理结构，不用自己改稿
- **默认不上传录音** — iOS 本地识别、Mac 可选本地模型；只有你主动开启云端引擎时，音频才会离开设备
- **模型随你选** — 内置润色开箱即用；也可接入 DeepSeek、OpenAI、Anthropic、OpenRouter 等任意兼容 API
- **Mac 也能全局听写** — 菜单栏常驻，屏幕底部浮层实时反馈，说完自动插入当前 App

---

## 三步开始

1. **安装并授权** — iOS 添加键盘并开启「完全访问」；Mac 授予麦克风与辅助功能
2. **选引擎** — 本地识别 + 内置润色（零配置），或填入自己的 API Key
3. **开口说话** — 切换到 OSGKeyboard 键盘，或按住 Option 键，文字即出现

> iOS 首次打开会走 6 步引导：权限 → 键盘 → 识别引擎 → 润色模型，约 2 分钟完成。

---

## 核心能力

| | iOS / iPadOS | macOS |
|---|:---:|:---:|
| 自定义键盘 / 全局热键 | ✅ | ✅ Option 按住说话 |
| 本地语音识别 | ✅ Apple SpeechAnalyzer | ✅ SenseVoice / Qwen3 |
| AI 文本润色 | ✅ | ✅ |
| 润色后翻译 | ✅ | ✅ |
| 个性词库 | ✅ iCloud 同步 | ✅ |
| 听写历史 | ✅ | ✅ |
| 灵动岛 / 听写浮层 | ✅ Live Activity | ✅ 底部胶囊浮层 |

---

## 隐私

- **默认本地识别** — 录音在设备上转写，不经过我们的服务器
- **润色只发文字** — 发给 LLM 的是转写文本，不是原始音频
- **不记录击键** — 键盘扩展不采集、不上传你的日常输入内容
- 详见 [隐私政策](https://hkgood.github.io/OSGKeyboard/privacy/)

---

## 获取

**从源码构建**（需 macOS + Xcode 26）：

```bash
git clone https://github.com/hkgood/OSGKeyboard.git
cd OSGKeyboard
./Scripts/generate-xcodeproj.sh
open OSGKeyboard.xcodeproj
```

- iOS：选择 `OSGKeyboard` scheme，跑在 iPhone / iPad 模拟器或真机
- macOS：选择 `OSGKeyboardMac` scheme，编译产物为 `OSGKeyboard.app`

开发细节、架构说明与贡献指南见 [README.en.md](./README.en.md) 与 [CONTRIBUTING.md](./CONTRIBUTING.md)。

---

## 许可

[源码可见许可](./LICENSE) — 个人学习与非商用本地使用；商用请联系 [rocky.hk@gmail.com](mailto:rocky.hk@gmail.com)。

---

<p align="center">
  灵感来自 <a href="https://typeless.com">Typeless</a> · 端侧识别基于 Apple SpeechAnalyzer · Mac 本地模型基于 Sherpa-ONNX
</p>
