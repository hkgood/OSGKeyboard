# OSGKeyboard

**开口即文字。**

在 iPhone、iPad 和 Mac 上，用说的代替打字。任意 App 里开口，润色好的文字直接落到光标处。

![Platform](https://img.shields.io/badge/iOS%20%2F%20iPadOS-26%2B-0078D4?logo=apple)
![Platform](https://img.shields.io/badge/macOS-15%2B-555?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift)
![Version](https://img.shields.io/badge/version-1.7.5-3aa05a)
![License](https://img.shields.io/badge/license-Source%20Available-blue)

[官网](https://hkgood.github.io/OSGKeyboard/) · [English](./README.en.md) · [隐私政策](https://hkgood.github.io/OSGKeyboard/privacy/)

<p align="center">
  <a href="https://apps.apple.com/cn/app/osgkeyboard/id6781553267">
    <img src="docs/assets/badges/ios-zh.svg" alt="立即下载 App Store 版" height="40">
  </a>
  &nbsp;
  <a href="https://github.com/hkgood/OSGKeyboard/releases/download/v1.1-mac/OSGKeyboard-1.1.dmg">
    <img src="docs/assets/badges/macos-zh.svg" alt="下载 macOS 历史版本 1.1" height="40">
  </a>
</p>

---

## 为什么用它

- **真的随处可用** — 微信、备忘录、Notion、Cursor、邮件……光标在哪，文字就落在哪
- **说完就能用** — 点按（iOS）或按住 Option（Mac）开口，AI 自动补标点、整理结构，不用自己改稿
- **中英都能打** — iOS 键盘内建全拼 / 双拼中文候选，以及英文补全、纠错与下一词预测
- **默认不上传录音** — iOS 本地识别、Mac 可选本地模型；只有你主动开启云端引擎时，音频才会离开设备
- **模型随你选** — 本地识别无需 API Key；润色与 AI 模式使用你配置的 DeepSeek、OpenAI、Anthropic、OpenRouter 等服务
- **Mac 也能全局听写** — 菜单栏常驻，屏幕底部浮层实时反馈，说完自动插入当前 App

---

## 三步开始

1. **安装并授权** — iOS 添加键盘并开启「完全访问」；Mac 授予麦克风与辅助功能
2. **选引擎** — 本地识别可直接使用；需要润色或 AI 模式时再填入自己的 API Key
3. **开口说话** — 切换到 OSGKeyboard 键盘，或按住 Option 键，文字即出现

> iOS 首次打开会走 6 步引导：权限 → 键盘 → 识别引擎 → 润色模型，约 2 分钟完成。

---

## 核心能力

| | iOS / iPadOS | macOS |
|---|:---:|:---:|
| 自定义键盘 / 全局热键 | ✅ | ✅ Option 按住说话 |
| 中文输入（全拼 / 微软双拼 / 搜狗双拼） | ✅ 可选模糊音 | — |
| 英文输入（补全 / 纠错 / 下一词） | ✅ 离线词表 + 个性词库加权 | — |
| 本地语音识别 | ✅ Apple SpeechAnalyzer | ✅ Qwen3 MLX 流式（默认 0.6B 4-bit）+ Apple Speech 回退 |
| AI 文本润色 | ✅ | ✅ |
| 语音 AI 问答（显式插入 / 发送） | ✅ | — |
| 语音编辑上次输入 | ✅ | — |
| 润色后翻译 | ✅ | ✅ |
| 个性词库 | ✅ iCloud 同步；保护润色并参与英文补全 | ✅ |
| 听写历史 | ✅ | ✅ |
| 听写浮层 | —（静默后台保活） | ✅ 底部胶囊浮层 |

---

## 隐私

- **默认本地识别** — 录音在设备上转写，不经过我们的服务器
- **润色只发文字** — 发给 LLM 的是转写文本，以及用于衔接的少量光标附近文字，不是原始音频
- **服务商由你选择** — 只有你在设置中主动选择云端识别、润色、AI 或技能时，相关音频或文字才会直接发给你配置的服务商
- **剪贴板默认关闭** — 历史最多 15 条、仅保存在本机；只有你主动运行剪贴板技能、在 AI 提问中点名剪贴板或粘贴后润色时，正文才会离开设备
- **不上传击键** — 中文候选学习与英文补全/纠错学习仅留在设备 App Group；密码框关闭英文建议与纠错，普通击键不会上传
- **密钥与模型归你控制** — API Key 保存在 Keychain，可选经 iCloud 钥匙串同步；Mac 本地模型下载后保存在本机，端侧推理不上传录音
- 详见 [隐私政策](https://hkgood.github.io/OSGKeyboard/privacy/)

---

## 获取

**iPhone / iPad（App Store）**

<a href="https://apps.apple.com/cn/app/osgkeyboard/id6781553267">
  <img src="docs/assets/badges/ios-zh.svg" alt="立即下载 App Store 版" height="40">
</a>

**Mac（历史版本 1.1，Developer ID 签名并公证）**

<a href="https://github.com/hkgood/OSGKeyboard/releases/download/v1.1-mac/OSGKeyboard-1.1.dmg">
  <img src="docs/assets/badges/macos-zh.svg" alt="下载 macOS 历史版本 1.1" height="40">
</a>

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

## 鸣谢

OSGKeyboard 的语音与键盘能力建立在这些优秀项目和平台之上：

- [Typeless](https://typeless.com) — voice-first 输入体验的产品灵感
- [Apple SpeechAnalyzer](https://developer.apple.com/documentation/speech) — iOS 端侧语音识别
- [librime](https://github.com/rime/librime) 与 [librime-xcframework](https://github.com/ghostflyby/librime-xcframework) — iOS 中文输入引擎及静态框架
- [NanoMouse](https://github.com/xjwhnxjwhn/nanomouse) 与 [Hamster](https://github.com/imfuxiao/Hamster) — iOS Rime 生命周期和架构参考
- [rime-pinyin-simp](https://github.com/rime/rime-pinyin-simp)、[Jieba](https://github.com/fxsjy/jieba)、[phrase-pinyin-data](https://github.com/mozillazg/phrase-pinyin-data) 与 [pinyin-data](https://github.com/mozillazg/pinyin-data) — 拼音、词语与词频数据
- [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) — macOS 本地 Qwen3 MLX 流式识别
- [Google Material Icons](https://github.com/google/material-design-icons) — iOS App 图标字体

具体版本和许可证见 [第三方许可说明](./NOTICE-TYPING.md)（含中文 Rime 依赖与 OSG 自有英文词表说明），也可在 App 的「设置 → 关于 → 第三方许可」中查看。

---

## 许可

[源码可见许可](./LICENSE)（并非开源许可）— 仅允许个人学习与非商用本地使用；禁止未经授权的分发与公开衍生版本，商用请联系 [rocky.hk@gmail.com](mailto:rocky.hk@gmail.com)。

---

<p align="center">
  开口即文字 · Speak it. It's typed.
</p>
