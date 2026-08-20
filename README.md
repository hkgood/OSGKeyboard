# OSGKeyboard

**开口即文字。也可以直接打字、提问、编辑。**

OSGKeyboard 是面向 iPhone、iPad 与 Mac 的语音输入工具。iOS 键盘把端侧听写、中英打字、AI 助手、剪贴板技能与可选托管积分放在同一个输入界面；Mac 提供按住 Option 即可使用的全局听写。

![Platform](https://img.shields.io/badge/iOS%20%2F%20iPadOS-26%2B-0078D4?logo=apple)
![Platform](https://img.shields.io/badge/macOS-15%2B-555?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift)
![Version](https://img.shields.io/badge/version-2.0.0-3aa05a)
![License](https://img.shields.io/badge/license-Source%20Available-blue)

[官网](https://hkgood.github.io/OSGKeyboard/) · [English](./README.en.md) · [隐私政策](https://hkgood.github.io/OSGKeyboard/privacy/) · [更新记录](./CHANGELOG.md)

<p align="center">
  <a href="https://apps.apple.com/cn/app/osgkeyboard/id6781553267">
    <img src="docs/assets/badges/ios-zh.svg" alt="立即下载 App Store 版" height="44">
  </a>
  &nbsp;
  <a href="https://github.com/hkgood/OSGKeyboard/releases/download/v1.1-mac/OSGKeyboard-1.1.dmg">
    <img src="docs/assets/badges/macos-zh.svg" alt="下载 macOS 历史版本 1.1" height="44">
  </a>
</p>

> Mac 公开 DMG 是已签名并公证的历史版本 1.1。仓库中的 macOS target 随整体源码演进到 2.0；最新源码能力可使用 Xcode 26 构建。

## 一个键盘，四种输入方式

### 语音听写

- iOS 26 默认使用 Apple `SpeechAnalyzer` 与 `DictationTranscriber` 在设备端识别
- 轻点麦克风开始或结束，转写结果直接插入当前 App 的光标位置
- 可选 AI 润色、标点整理、结构重建与润色后翻译
- 9 种内置润色风格、自定义风格、趣味风格轻度 / 重度档位与可选情绪 emoji
- Mac 菜单栏 App 支持按住 Option 全局听写；Apple Silicon 可下载 Qwen3 MLX 本地模型

### 中英打字

- 中文：全拼、微软双拼、搜狗双拼、可选模糊音、简拼排序和展开候选面板
- 英文：三格 QuickType、约 4 万词离线词表、补全、纠错与下一词建议
- 输入体验：邻键纠错、叠指连打、长按连删、双空格句号、系统 Return 语义
- 个性词库同时参与中文候选、英文建议、语音偏置与润色保护

### 统一 AI 助手

- 轻点听写，长按向 AI 提问；语音与 AI 共用一个助手入口
- 回答流式显示；仅当原输入框与光标上下文仍匹配时自动上屏
- 支持口述修改最近一次可靠的 OSGKeyboard 输入，并选择替换或追加
- 根据当前输入框显示发送、搜索、前往、完成、下一步或换行
- 一次撤销覆盖听写、AI 回答、编辑与剪贴板粘贴

### 剪贴板与技能

- 剪贴板历史默认关闭，开启后最多保存 15 条纯文本，仅存于本机 App Group
- 复制后短时间显示回复、总结、翻译等快捷技能
- 内置待办、日程与备忘录可通过 Apple 快捷指令导出；地图导航直接打开高德、百度或 Apple 地图
- 可创建自定义技能：名称、SF Symbol、提示词和可选 iCloud 快捷指令
- 最多将 8 个技能放到键盘，支持长按拖动排序

## 三种服务路径

OSGKeyboard 不把云端服务绑定为唯一选择：

1. **设备端** — 默认路径。iOS 本地听写无需账号或 API Key，原始录音不上传。
2. **自备服务商（BYOK）** — 配置自己的云端 ASR / LLM 凭证，请求直接发送到所选服务商；凭证保存在 Keychain。
3. **OSG 托管积分** — iOS / iPadOS 可选。Apple 登录后可使用托管语音与 AI，无需填写服务商凭证；首次启用前会明确说明离开设备的数据并征求同意。

本地听写和自备服务商始终可以独立使用，不要求 OSGKeyboard 账号。

## 可选账号与积分

iOS / iPadOS 账号中心支持：

- Sign in with Apple、资料管理、退出登录与 App 内账号注销
- 托管积分余额、App Store 消耗型积分包与邀请
- 服务端核验购买结果并维护积分账本
- 键盘扩展只接收短时、限权的托管服务凭证

自愿打赏 `ByRockyACoffee` 与积分包彼此独立，不解锁核心功能。

## 历史、统计与同步

- 首页集中展示近 7 天听写统计、最近历史与个性词库
- 语音历史最多保留 300 条，可按天删除
- 设置、个性词库、润色风格、历史与统计可按类型选择经私有 iCloud 同步
- API Key 默认保存在 Keychain；仅在开启 iCloud 设置同步后经 iCloud 钥匙串复制。剪贴板历史、账号令牌与打字学习不会通过 iCloud 设置同步

## 平台能力

| 能力 | iOS / iPadOS 26+ | macOS 15+ |
|---|:---:|:---:|
| 系统键盘 / 全局热键 | 自定义键盘 | 按住 Option |
| 端侧语音识别 | Apple SpeechAnalyzer | Qwen3 MLX（Apple Silicon）+ Apple Speech 回退 |
| 中文全拼 / 双拼 | 支持 | — |
| 英文补全 / 纠错 | 支持 | — |
| AI 润色与翻译 | 支持 | 支持 |
| 统一助手与语音问答 | 支持 | — |
| 剪贴板历史与技能 | 支持 | — |
| 可选 OSG 账号与托管积分 | 支持 | — |
| 个性词库、历史与统计 | 支持 | 支持 |
| iCloud 同步 | 设置、词库、历史与统计等可选同步 | 共享兼容数据 |

## 隐私原则

- **端侧优先**：使用本地识别时，原始录音不离开设备
- **主动联网**：只有明确选择云端识别、润色、AI 或技能时，相关数据才会发送
- **路径透明**：自备服务商请求直达所选服务商；托管积分请求经 `account.osglab.com`
- **击键不上传**：中文候选学习与英文建议偏好保存在本机，密码框不学习
- **剪贴板可控**：历史默认关闭、最多 15 条、仅本机保存，不会自行发送给 AI
- **凭证隔离**：用户 API Key 保存在 Keychain；账号会话令牌只在主 App 私有 Keychain
- **无广告追踪**：不集成广告、分析或追踪 SDK，不出售个人数据

完整数据类型、保留策略、账号删除与第三方服务说明见[隐私政策](https://hkgood.github.io/OSGKeyboard/privacy/)。

## 快速开始

### iPhone / iPad

1. 从 App Store 安装并打开 OSGKeyboard。
2. 按引导添加键盘、开启“完全访问”，并授予麦克风与语音识别权限。
3. 选择本地识别、自备服务商或可选托管积分。
4. 在任意输入框切换到 OSGKeyboard：轻点听写、长按问 AI，或切换到中文 / English 打字。

### Mac

1. 下载历史版 1.1 DMG，或从当前源码构建 `OSGKeyboardMac`。
2. 授予麦克风与辅助功能权限。
3. 在任意 App 按住 Option 说话，松开后插入结果。

## 从源码构建

需要：

- macOS
- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
git clone https://github.com/hkgood/OSGKeyboard.git
cd OSGKeyboard
./Scripts/generate-xcodeproj.sh
open OSGKeyboard.xcodeproj
```

- iOS / iPadOS：选择 `OSGKeyboard` scheme，在 iOS 26 模拟器或真机运行
- macOS：选择 `OSGKeyboardMac` scheme，产物为 `OSGKeyboard.app`
- 测试：按 [docs/TESTING.md](./docs/TESTING.md) 的 suite manifest 与脚本执行

工程以 [project.yml](./project.yml) 为 XcodeGen 单一事实源，`.xcodeproj` 不进入版本控制。

## 架构速览

```text
OSGKeyboard/             iOS / iPadOS 主 App、Flow 会话与设置
OSGKeyboardExt/          自定义键盘扩展
OSGKeyboardMac/          macOS 菜单栏与全局听写
OSGKeyboardShared/       共享模型、输入、同步、AI 与设计系统
OSGKeyboardHostSupport/  主 App 专用 ASR、云端客户端、账号与 StoreKit
```

iOS 的 Flow 会话由主 App 负责采音和识别；键盘扩展通过 App Group 发送轻量命令并接收结果。托管服务使用短时、按 scope 限权的 grant，不把主 App 账号令牌暴露给键盘扩展。

开发规范、测试和贡献流程见 [CONTRIBUTING.md](./CONTRIBUTING.md)。版本变化见 [CHANGELOG.md](./CHANGELOG.md)。

## 鸣谢与第三方许可

主要依赖和灵感包括 Apple Speech、librime、librime-xcframework、rime-pinyin-simp、NanoMouse、Hamster、mlx-audio-swift、Peter Norvig 的公有领域 n-gram 统计，以及 Google Material Icons。

准确版本、许可证与 OSG 自有英文词表声明见 [NOTICE-TYPING.md](./NOTICE-TYPING.md)，也可在 App 的“设置 → 关于 → 第三方许可”中查看。

## 许可

[OSGKeyboard 源码可见许可](./LICENSE)不是开源或 MIT 许可。

- 允许：个人学习、非商用本地构建与使用
- 禁止：未经授权的再分发、公开衍生版本与商业使用
- 商业许可：[rocky.hk@gmail.com](mailto:rocky.hk@gmail.com)

<p align="center">
  开口即文字 · Speak it. It's typed.
</p>
