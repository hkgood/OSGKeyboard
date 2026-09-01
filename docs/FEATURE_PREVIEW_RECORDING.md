# 功能预览片录制 / Feature preview recording

四段中文 App Store 预览片的录制与合成流程。成片位于
`docs/assets/app-preview/zh/OSGKeyboard-<slug>-6.7-zh.mp4`。

| slug | 讲什么 | 素材来源 |
|------|--------|----------|
| `voice-polish` | 语音输入与自动润色，收在趣味润色风格 | `--edit-demo` + 润色风格页 |
| `personal-style` | 从历史听写学习你的表达习惯，生成专属风格 | `--polish-styles-screenshot` |
| `clipboard-agent` | 剪贴板 AI Agent，一键回复消息 | `--clipboard-demo` |
| `ask-ai` | 轻点听写、长按问 AI | `--ai-demo` |

## 为什么不用键盘扩展录

`WhatsNewDemoDriver` 那条路（`--whats-new-host`）会让**真实键盘扩展**盖在
Notes 宿主上，画面最真。但把第三方键盘设成**当前**输入法必须点一下地球键，
`simctl` 没有对应命令，`.GlobalPreferences` 里的 `AppleKeyboards` 只决定
"已启用"而不是"当前使用"。

所以这套流程改走 app 内的 DEBUG demo host：它们渲染的是**同一批真实键盘视图**
（`AIKeyboardView`、`LastInputEditView`、`ClipboardHistoryPanelView`……，见
`project.yml` 中 app target 的 `OSGKeyboardExt/Views/*` 源），由脚本化的
`KeyboardState` 驱动，不走 ASR、不走 LLM、不联网，也就不需要任何点击。

`--preview-fullscreen` 会在键盘上方补一块 Notes / Messages 宿主文档
（`FeaturePreviewHostDocument`），把原本留给 What's New 裁剪的空白填满，
让整帧可以直接当全屏预览片用。不传这个 flag 时，各 demo view 的画面与
What's New 工作流完全一致。

## 设备要求

- **iPhone 16 Plus**：原生 1290×2796，正好是 App Store Connect 6.9" 预览位
  接受的尺寸之一，零缩放。
- **iOS 26.5 或更新**：app 用到的 `SwiftUI.View.glassEffect(_:in:)` 在 iOS 26.0
  运行时里不存在，装上去会在启动时 `Symbol not found` 崩溃。

Xcode 预置的 iPhone 16 Plus 挂在 iOS 26.0 下，需要自建一台：

```bash
xcrun simctl create "OSG-Preview-16Plus" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-16-Plus \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5
```

## 完整流程

```bash
# 1) 编译（必须带签名，否则没有 entitlements → App Group 不可用 → 启动崩溃）
xcodebuild -project OSGKeyboard.xcodeproj -scheme OSGKeyboard \
  -configuration Debug -destination "id=$UDID" \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=YES build

# 2) 干净安装。覆盖安装不会刷新 App Group 容器，
#    容器缺失时 app 会渲染 AppGroupErrorView，录出来就是一屏报错。
xcrun simctl uninstall "$UDID" com.osgkeyboard.ios
xcrun simctl install "$UDID" \
  ~/Library/Developer/Xcode/DerivedData/OSGKeyboard-*/Build/Products/Debug-iphonesimulator/OSGKeyboard.app

# 3) 录制（脚本会先校验 App Group 容器，缺失直接报错退出）
Scripts/record_feature_previews.sh "$UDID"            # 全部四段
Scripts/record_feature_previews.sh "$UDID" ask-ai     # 只录一段

# 4) 合成。需要 Pillow —— 这版 ffmpeg 没有 libfreetype / libass，
#    所有文字都由 PIL 渲染成 RGBA PNG 再 overlay。
python3 -m venv .venv && .venv/bin/pip install Pillow
.venv/bin/python Scripts/compose_feature_previews.py
```

## 已知的坑

**变帧率**。`simctl io recordVideo` 录的是 VFR，时间轴不按墙钟走：直接
`-ss` 会定位到错误位置，`-t` 截出来的长度也不对（实测 24s 的窗口出来 27.4s，
足以让成片超出 App Store 的 30 秒上限）。`compose_feature_previews.py` 会先把
每段原始素材转成 30fps CFR 再裁，所以配置里的 `trim_start` / `trim_duration`
是真实秒数。

**静态页面录不出长片**。VFR 只在画面变化时出帧，纯静态页面录 22 秒也只得到
约 5 秒素材。`Source(freeze_at=…)` 会抽一帧定格，配合 `ken_burns` 用运镜提供
动势 —— `personal-style` 就是这么做的。

**字幕 PNG 必须 `-loop 1`**。单帧输入的 pts 恒为 0，`fade` 的时间轴永远停在
起点，alpha 被钉死，字幕完全不显示。

**色彩标签会丢**。原始素材是 `tv` range / bt709 / sRGB transfer，重编码不显式
带上就变成 `unknown`，播放器猜错会明显发灰。合成脚本每一次编码都显式打标签。

**抽帧检查会骗你**。用 ffmpeg 抽出 PNG 再看，色彩管理与实际播放不同，画面会
偏灰；判断压暗层强度请量像素值，不要看缩略图。

## App 内卡片版（无字幕短循环）

同一批原始素材还会产出第二种成品：给 app 内卡片用的短循环，位于
`docs/assets/feature-cards/<slug>.mp4`，另附 `<slug>-poster.png` 作占位图。

```bash
.venv/bin/python Scripts/compose_feature_cards.py
```

与预览片的区别：**没有字幕、没有片头片尾、没有音轨**，并且裁到键盘区
（`1290×944`），画面里只有真实键盘 chrome，不含任何为讲故事补的宿主界面。

窗口都选在首尾状态相近的位置，再叠一次 0.5 秒的尾接头淡入，所以可以无限循环
播放而看不出接缝（实测首末帧平均像素差 0.19–0.57 / 255）。`personal-style` 是
静态设置页，改用推近再拉回的对称运镜，天然闭合。

裁切区取 `y=1780` 起、高 944：剪贴板面板是键盘区里最高的元素（顶边 y=1779），
屏幕最底部 72px 是键盘下方的空白内边距，一并去掉。

### 技能行必须由真实排序器产生

`AIKeyboardView` 的技能行读 `ClipboardHistoryStore.shared` 与
`ClipboardSemanticRankingStore.shared` 两个**单例**，并交给
`ClipboardSkillSemanticRanker.recommended(...)` 按剪贴板内容排序。demo view 早期
用私有 store + `AIKeyboardView.debugPreviewSkills` 强塞了一排回复风格，结果录出
一个真实 app 里**不可能出现**的键盘——排序器在通用「回复」之外最多只放
`maximumReplyRecommendations = 2` 个专门回复技能。

现在 `ClipboardHistoryDemoView` 直接喂真实单例：把要回复的那条消息 ingest 成
最新剪贴板项，调 `ranking.analyze(entry)` 并**等它出 snapshot**（分析在主 actor 外
跑，抢跑会让行退化成孤零零一个「回复」），然后由排序器决定行内容。当前这条
消息排出的是「译为英语 / 回复 / 澄清追问 / 日程」。

演示脚本只从排出来的行里挑技能点——先点通用「回复」，再点行内第一个
`supportsReplyStyle` 的技能——所以画面里点的永远是屏幕上真实存在的 chip。

app 里**没有**「点一次回复，弹出多条候选」这种交互：点一个技能生成一条。
多风格是靠技能行里并列的多个回复技能实现的，先选风格再生成。

一个容易踩的坑：`AISessionState` 的 `beginGenerating` / `receivePartialAnswer` /
`receiveAnswer` 都用 `activeUtteranceID == utteranceID` 做守卫，而这个 ID 只由
`beginPreparing` 设置。跳过 `beginPreparing` 直接 `beginGenerating`，整串调用会
**静默变成空操作**，键盘区从头到尾不出现任何答案。每一轮都要
`enter()` → `beginPreparing` → `beginGenerating`。

两个 ffmpeg 细节：`zoompan` 的 `d=1` 是按输入帧走的，而 `-loop 1` 读 PNG 默认
**25fps**，不加 `-framerate 30` 出来的片长会短 25/30；另外推拉运镜不要用单条
`zoompan` 表达式同时做进和出——它的实际出帧数对不上 `duration * FPS`，片子会
停在半路，循环处肉眼可见地跳。现在的做法是只渲染推近的一半再 `reverse` 拼接。

## 改动了 demo 时间轴之后

`Scripts/feature_preview_clips.py` 里的裁切点和字幕时间是照着实际录像量出来的。
只要改了 `EditDemoView` / `AIKeyboardDemoView` / `ClipboardHistoryDemoView` 的
时间轴，就要重录并重新对时。合成脚本会校验成片是否落在 App Store 要求的
15–30 秒、1290×2796、H.264 之内，不合规会在输出里标 `!!`。
