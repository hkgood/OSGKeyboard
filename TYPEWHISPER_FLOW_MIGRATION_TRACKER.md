# OSGKeyboard · TypeWhisper Flow 迁移蓝图与任务追踪

> 目标：把当前“每次按语音都尝试跳转主 App”的模式，迁移为“Flow Session 会话模式”，实现**仅键盘侧连续语音输入**（会话有效期间无需反复跳转）。
>
> 维护方式：每完成一个任务，把对应复选框从 `[ ]` 改为 `[x]`，并填写“完成记录”。

---

## 1) 迁移蓝图（最终目标架构）

### 1.1 第一性目标
- 主链路不依赖每次 `openHostApp(dictate)` 成功。
- 会话有效期间，键盘只做“开始/停止”信号与结果插入。
- 跳转主 App 降级为“会话初始化/修复”路径。
- 任何异常都可恢复，不出现卡死状态。

### 1.2 目标架构
- **主 App（Session Owner）**
  - 维护 Flow 会话生命周期（active/expired/inactive）
  - 持续写心跳（heartbeat）
  - **持有唯一 continuous 音频管线**（见 §1.5）
  - 处理键盘录音状态信号并执行识别
  - 回写 `transcriptionResult/transcriptionError`
- **键盘扩展（Signal + Insert）**
  - 判断会话是否有效（active + expires + heartbeat）
  - 会话有效：写 `recording/stopped/aborted`
  - 会话无效：引导启动会话（一次性）
  - 轮询结果并 `insertText`
- **App Group（单一事实源）**
  - 所有跨进程状态仅通过共享键传递

### 1.3 关键共享键
- `flowSessionActive: Bool`
- `flowSessionExpires: TimeInterval`
- `flowHeartbeat: TimeInterval`
- `keyboardRecordingState: String` (`idle|recording|stopped|processing|aborted`)
- `transcriptionLanguage: String`
- `transcriptionResult: String`
- `transcriptionError: String`
- `audioLevels: [Float]`（键盘波形，**Phase 1 必做**）

### 1.4 状态机约束
- `recording` 仅在 `flowSessionActive = true` 且会话未过期时生效。
- `stopped` 必须最终归并到 `done|error|idle`。
- 任意异常必须显式写 `transcriptionError` 并回到 `idle`。

### 1.5 音频不变量（不可违背 — 对齐 TypeWhisper / SwiftSpeak SwiftLink）

> **历史教训**：曾用 `.playback` 静音保活 + utterance 时 `LiveDictationController.start()` 临时开麦，导致 `Session activation failed` 与双 engine 崩溃。**禁止再使用该模式。**

| # | 规则 | TypeWhisper 对应 | OSGKeyboard 实现 |
|---|------|------------------|------------------|
| A1 | 会话启动时配置 **`.playAndRecord`**（`mode: .measurement`），`setActive(true)` **一次** | `startFlowSession()` | `FlowContinuousCapture.start()` |
| A2 | 立刻 **`startContinuousRecording()`**：一个 `AVAudioEngine` + **常驻** `inputNode` tap | `startContinuousRecording()` | 同上，tap 在 `start()` 安装 |
| A3 | utterance 期间 **禁止** stop/start engine、**禁止** deactivate/reactivate session | `isRecordingAtomic` gating | `isUtteranceActive` + `beginUtterance`/`endUtterance` |
| A4 | 键盘 `recording` → 只 flip 标志 + 启动 ASR consumer；`stopped` → 结束 ASR stream + finalize | `checkKeyboardSignal()` | `FlowSessionManager.handleKeyboardSignal()` |
| A5 | **`audioLevels` 从 tap 计算**，主线程写入 App Group；**禁止**在 audio realtime 线程 `UserDefaults.synchronize()` | tap 写 levels（我们改为 main 线程 flush 更安全） | `FlowLevelStore` + `startLevelPublishing()` |
| A6 | Flow 期间 **禁止** 调用 `LiveDictationController.start()`（预览 / legacy dictate 专用） | `AudioRecordingService` 拒绝 Flow active | `FlowSessionManager` 直接用 `ASRService` |
| A7 | 会话结束才 `removeTap` / `engine.stop()` / `setActive(false)` | `endFlowSession()` | `FlowSessionManager.endSession()` |

**错误模式（已废弃，勿恢复）：**
- ❌ `.playback` + 静音 `AVAudioPlayerNode` 保活
- ❌ utterance 时 stop 保活 engine 再开第二个 engine 录音
- ❌ 复用 `LiveDictationController` 作为 Flow utterance 入口

**参考项目分工：**
- **TypeWhisper**（主参考）：`FlowSessionManager` + continuous tap + `SFSpeechAudioBufferRecognitionRequest` / batch
- **SwiftSpeak SwiftLink**（辅参考）：Darwin 通知、前台启动约束、streaming/batch 分叉
- **Legacy dictate**（保留）：`DictationCaptureView` + `LiveDictationController`，单次 handoff

### 1.6 组件职责

| 组件 | 职责 |
|------|------|
| `FlowContinuousCapture` | 会话级 engine + tap + utterance gating + levels |
| `FlowSessionManager` | 生命周期、轮询、ASR finalize、可选 polish |
| `FlowSessionBridge` | App Group 读写 |
| `LiveDictationController` | 主 App 预览、legacy `dictate` — **不用于 Flow** |
| `KeyboardViewController` | 信号 + 轮询 + insertText |

---

## 2) 详细改动清单（按文件）

## Phase 1 · 基础设施（会话能力）

### `OSGKeyboardShared/Services/FlowSessionBridge.swift`
- [x] Flow 键读写封装（active/expires/heartbeat/recordingState/result/error）
- [x] `storeAudioLevels` / `clearPendingTranscription`
- [x] 保留并兼容现有 `DictationBridge` pending transcript 接口
- [x] `clearFlowState()`

### `OSGKeyboardShared/Services/FlowContinuousCapture.swift`（新增）
- [x] `.playAndRecord` + 常驻 input tap
- [x] utterance gating → `AsyncStream<AudioBufferSnapshot>`
- [x] `FlowLevelStore`（audio 线程写、main 线程读）

### `OSGKeyboard/Services/FlowSessionManager.swift`
- [x] 会话生命周期 + heartbeat + 过期
- [x] 轮询 `keyboardRecordingState` → utterance gating → `ASRService`
- [x] 回写 `transcriptionResult/transcriptionError`
- [x] 主线程发布 `audioLevels`
- [x] **不再**使用 playback keep-alive / `LiveDictationController` for Flow

### `OSGKeyboard/Info.plist` 与 `project.yml`
- [x] `UIBackgroundModes: audio`
- [x] 麦克风 / 语音识别权限说明

---

## Phase 2 · 键盘主链路切换

### `OSGKeyboardExt/KeyboardViewController.swift`
- [x] `pressBegan()` 会话判断分流
- [x] 会话有效：写 `recording`；无效：`openHostApp(startflow)` 或提示
- [x] `pressEnded()` 写 `stopped`
- [x] 结果轮询 + `insertText`
- [ ] `KeyboardRootView` 会话 UI 细化（可选）

---

## Phase 3 · 体验与稳定性强化

### 主 App / 键盘协同
- [x] 心跳超时判死（`FlowSessionBridge.isSessionActive`）
- [x] 识别超时保护（30s finalize）
- [x] `audioLevels` 共享
- [ ] Darwin 通知（SwiftSpeak 模式，降低轮询延迟）
- [ ] 会话死掉后一键重启 UI
- [ ] `AudioRouteCoordinator`（蓝牙/路由切换）

### 测试
- [x] App Group 状态机单测
- [ ] Flow continuous capture 单测（需 device / mock）
- [ ] 端到端真机回归

---

## 3) 任务追踪面板

## A. 已完成
- [x] A1–A4：架构研究、蓝图、追踪文档
- [x] B1：Phase 1 Flow 基础设施（含音频层修正）
- [x] B2：Phase 2 键盘主链路（核心路径）

## B. 待执行
- [ ] B3：Phase 3 体验增强（Darwin、路由、恢复 UI）→ 见 §7.7 批次 F
- [ ] B4：端到端真机回归 → 见 §7.7；本地/在线主路径已通过
- [ ] **Phase 4**：§7.2–7.7 批次 A–F

---

## 5) 验收标准（Definition of Done）

### Flow 核心（Phase 1–2）
- [x] 本地 / 云端模式均可回填（真机已验证）
- [ ] 连续 20 次语音输入，会话有效期间 **无需** 反复跳主 App（待真机 F2 回归）
- [x] Console **无** `Session activation failed` / playback↔record 循环（架构已修正）
- [x] 键盘波形随说话变化（`audioLevels` 非零）
- [ ] 微信/备忘录/Safari 稳定回填（待真机 F2 回归）

### Phase 4 新增
- [x] 打开 App 后 **自动** 语音会话（权限齐全时）
- [x] 杀 App 再开 → 灵动岛立即清理，**回到 App 时自动开新会话**（不复活旧会话）
- [x] 键盘 **点按** 开始/结束；**3.5 分钟（210s）** 倒计时 + 最后 10s 变红
- [x] Onboarding **分步权限** 完整可走通
- [x] 隐私政策 URL 可访问；App 内可打开
- [ ] App Store 隐私标签与政策一致（A3 待人工）
- [x] 单测覆盖核心状态迁移

---

## 6) 真机验证清单（最小）

1. 打开 App → **自动**进入语音会话（或 Home 卡片显示「进行中」）
2. 切备忘录 → **点按**键盘麦开始 → 再点结束 → **文字出现**
3. **不跳主 App**，重复 5 次
4. 本地模式 + 云端模式各测 1 次
5. 3.5 分钟（210s）倒计时 + 最后 10 秒变红；到点自动识别
6. 杀 App 再开 → 灵动岛立即清理；回到 App 时自动开新会话（不复活旧会话）
7. 预览 sheet「开始/停止录音」仍可用（Flow 未启动时）

---

## 7) Phase 4 · 产品体验与上架合规（2026-06 拍板）

> 以下为用户/产品确认规格。**实现顺序建议：B → C → D → A → E → F。**

### 7.1 已锁定决策

| 主题 | 决定 |
|------|------|
| 麦克风交互 | **点按开始 / 再点结束**；识别中不可取消 |
| 会话未启动 | 保持现有逻辑（拉 App / 提示去主 App） |
| 权限引导 | 欢迎 → 麦克风 → 语音识别 → 键盘+完全访问 → 引擎/API；**仅首次或权限未定时** |
| 自动开语音会话 | 进 App 且权限齐全 → **自动开**；有效会话 → **续期**；**不设关闭开关** |
| 冷启动恢复 | **杀 App 不复活旧会话**；回到前台由 `activateOnForeground()` 清理孤儿灵动岛并自动开新会话（权限齐全时） |
| Home 按钮 | 自动开后 **隐藏「启动」**；**保留「结束」**；失败显示原因 + 去设置 |
| 单次录音上限 | **210s（3.5 分钟）**；键盘到点 auto `stopped`；倒计时 **A（剩余）+ C（最后 10s 变红）**，显示在按钮内 |
| 隐私政策 URL | **GitHub Pages**（仓库站点，如 `…/privacy`） |
| 自动开会话开关 | **先不加** |

### 7.2 批次 A · App Store 合规（上架前必做）

- [x] **A1** 隐私政策页面（GitHub Pages `privacy.html` / `docs/privacy`），en + zh-Hans
- [x] **A2** App 内入口：设置页 + Onboarding 底部「隐私政策」链接
- [ ] **A3** App Store Connect「App 隐私」问卷与政策一致
- [ ] **A4** 复核 / 更新 `PrivacyInfo.xcprivacy`（主 App + 键盘扩展；麦克风、UserDefaults 等）
- [x] **A5** 更新 `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription`（含 Flow 自动会话说明）
- [x] **A6** 「完全访问」专项说明（Onboarding + 设置：用途、不上传击键）
- [ ] **A7** 云端模式披露：润色时仅文字发往用户配置的 API
- [ ] **A8**（可选）支持邮箱 / 用户协议

### 7.3 批次 B · 分步权限引导

- [x] **B1** Onboarding 麦克风页（说明 + 按钮触发系统弹窗）
- [x] **B2** Onboarding 语音识别页
- [x] **B3** 键盘 + 「允许完全访问」图文 + 跳转系统设置
- [x] **B4** 与 `PermissionPrimer` 合并；仅首次 / 权限未定时展示
- [x] **B5** 权限被拒降级页（去设置）

### 7.4 批次 C · 语音会话自动化

- [x] **C1** 进 App + 权限 OK → 自动 `startSession`（`OSGKeyboardApp` / Home）
- [x] **C2** 冷启动 `checkExistingSession`（`FlowSessionManager` init）
- [x] **C3** Home 卡片 UX：进行中 + 结束；失败原因 + 去设置；隐藏手动「启动」
- [x] **C4** 与 `scenePhase.active` 续期对齐

### 7.5 批次 D · 键盘点按录音 + 3.5 分钟（210s）倒计时

- [x] **D1** `RecordButton` 改为 toggle（替换长按手势）
- [x] **D2** 识别中禁用按钮
- [x] **D3** 按钮内剩余时间倒计时（`M:SS`）
- [x] **D4** 最后 10 秒变红/橙（A+C）
- [x] **D5** 210s（3.5 分钟）到点自动 `stopped` → 「识别中…」
- [x] **D6** 无障碍 / 占位文案改为「点按说话」类

### 7.6 批次 E · 多语言完善

- [x] **E1** 键盘扩展：移除 `KeyboardL10n` 硬编码，统一 `Localizable.strings`
- [x] **E2** `KeyboardViewController` 硬编码中文迁入 strings
- [x] **E3** 批次 B/C/D/A 新增文案 en + zh-Hans 成对

### 7.7 批次 F · Phase 3 收尾

- [x] **F1** B3：会话过期键盘提示、Darwin（可选）、路由（可选）
- [ ] **F2** B4：全场景回归（含自动开、210s、杀 App 不复活/回前台自动开）— 待真机
- [x] **F3** 更新 §5 验收勾选

### 7.8 任务追踪（Phase 4）

- [x] P4-0：产品规格拍板（交互、权限、自动会话、210s、隐私 URL）
- [ ] P4-A：上架合规批次（A1/A2/A5 代码侧已完成；A3/A4 待人工）
- [x] P4-B：权限引导
- [x] P4-C：会话自动化
- [x] P4-D：键盘点按 + 倒计时
- [x] P4-E：多语言（KeyboardL10n 已移除，ExtL10n + strings）
- [x] P4-F：Phase 3 收尾（F1/F3 完成；F2 待真机回归）

---

## 4) 完成记录

| 日期 | 任务ID | 变更摘要 | 状态 |
|---|---|---|---|
| 2026-06-19 | A1-A4 | 架构研究、方案选择、蓝图与追踪文档 | Done |
| 2026-06-19 | B1-B2 | Flow IPC + 键盘链路；修正 continuous capture 音频层 | Done |
| 2026-06-19 | B4-partial | 真机：本地 + 在线 Flow 可用 | Done |
| 2026-06-19 | P4-B~F | Phase 4 UX、i18n、Darwin 会话通知、GitHub Pages 图标 | Done |

