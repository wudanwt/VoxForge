# VoxForge 修复任务清单（TODO）

> 来源：2026-07-07 全项目审计。每个任务自包含（背景、位置、修法、验收），可独立交给 AI 执行。
> 通用要求：每个修复先写失败测试再改代码（TDD）；每完成一项跑 `swift test`；涉及真机行为的用 `./script/build_and_run.sh --verify` 回归。
> 完成一项请把 `[ ]` 改为 `[x]` 并在末尾附提交 hash。

---

## 第一批：正确性（P0）

### [ ] T1. 修复音频 tap 回调数据竞争
- **文件**：`Sources/TypeMore/Services/AVAudioEngineLiveRecordingService.swift`、`Sources/TypeMore/Services/AVAudioEngineRecordingService.swift`
- **问题**：`installTap` 回调运行在 CoreAudio 实时线程，直接读写 `samplesRecorded`、`recordingError`、`audioFile`、`onSamples`、`didLogFirstBuffer` 等共享可变状态；主线程的 `stopStreaming()` / `resetEngineState()` 同时清空这些字段，完全无同步。停止听写与最后几个 buffer 并发时可能读到半清理状态（丢尾音、偶发报错）。
- **修法**：引入单一串行 `DispatchQueue`（如 `audioStateQueue`），tap 回调内所有共享状态读写、文件写入、`onSamples` 调用都派发到该队列；`stopStreaming`/`resetEngineState` 在同一队列上 `sync` 执行清理，保证 stop 返回后不再有回调触碰状态。注意不要在实时线程做重活——转换可留在回调线程，仅状态与分发走队列。
- **验收**：新增并发压力测试（模拟 tap 高频回调 + 并发 stop，重复多次无崩溃/无丢样本断言失败）；现有测试全绿。

### [ ] T2. 音频 buffer 改用 AsyncStream 保序转发给识别引擎
- **文件**：`Sources/TypeMore/App/AppModel.swift`（`startStreamingDictation` 约 584-592 行）
- **问题**：每个音频 buffer 都 `Task { await engine.acceptAudio(...) }`。独立非结构化 Task 之间没有执行顺序保证，buffer 可能乱序进入 actor 引擎（识别乱码）。当前未提交改动还在每个 Task 里 `MainActor.run` 更新 `lastAudioBufferOperationID`，导致录音全程每个 buffer（约 46ms 一个）两次主线程跳变。
- **修法**：用 `AsyncStream<(samples: [Float], sampleRate: Double)>` 承接录音回调（continuation.yield），启动一个消费 Task `for await` 顺序调用 `engine.acceptAudio`；首个 buffer 到达时在消费 Task 内一次性通知 MainActor 取消 audio watchdog（之后不再跳主线程）。结束/中断时 `continuation.finish()` 并取消消费 Task。
- **验收**：单测验证 N 个乱序压入的 buffer 以 yield 顺序到达 mock 引擎；audio watchdog 行为不变（无数据 2 秒仍失败）；`swift test` 全绿。

### [ ] T3. 剪贴板恢复前用 changeCount 防止覆盖用户数据
- **文件**：`Sources/TypeMore/Services/PasteboardTextInsertionService.swift`（18-24 行）
- **问题**：粘贴 1.2 秒后无条件 `clearContents()` 并写回旧内容。若用户在这 1.2 秒内自己复制了新内容，会被静默覆盖丢失。
- **修法**：`setString` 写入后记录 `NSPasteboard.general.changeCount`；1.2 秒后仅当当前 `changeCount` 仍等于记录值（即剪贴板仍是我们写的那版）才恢复 `previousString`，否则跳过。
- **验收**：将恢复逻辑抽成可注入/可测的纯函数或协议（传入记录的 changeCount 与当前 changeCount），单测覆盖"未变→恢复"“已变→不动”两种情况。

### [ ] T4. LLM 响应清洗：剥 markdown 围栏与解释性前言
- **文件**：`Sources/TypeMore/Services/OpenAICompatibleOptimizationService.swift`（62-68 行）
- **问题**：只 trim 空白。模型返回 ```` ```text\n...\n``` ```` 代码围栏包裹，或"好的，优化后的文本是：""以下是优化结果："这类前言时，会原样粘贴进目标应用。
- **修法**：新增 `static func sanitizeLLMResponse(_ text: String) -> String`：①若整体被单个 ``` 围栏包裹（可带语言标记），剥掉围栏；②去掉常见中文/英文前言行（以"好的""以下是""Here is/Here's"等开头且以冒号结尾的首行——保守匹配，只处理首行，避免误伤正文）；③再 trim。在 decode 后调用。
- **验收**：单测覆盖：纯文本不变、```` ```包裹 ````、```` ```text 包裹 ````、带前言行、正文中间含 ```（不应误剥）等用例。加入 `Tests/TypeMoreTests/LLMOptimizationTests.swift`。

---

## 第二批：可用性 / 体验（P1）

### [ ] T5. readyToSubmit 状态显示 HUD 提示（去掉 NSApp.isActive 条件）
- **文件**：`Sources/TypeMore/App/AppModel.swift`（约 850-852 行）
- **问题**：`showReadyToSubmit` 仅在 `NSApp.isActive && !NSApp.isHidden` 时显示，但听写完成时前台必然是目标应用，条件几乎恒为 false——用户永远看不到"再按一次发送回车"的提示。HUD 是 nonactivating panel，不抢焦点，可直接显示。
- **修法**：去掉条件，直接 `hudController.showReadyToSubmit(...)`，消息中带目标应用名（如"已输入到 Cursor，再按一次发送回车"）。可顺带把自动隐藏延迟从 1.1s 提到 ~3s（`DictationHUDController.showReadyToSubmit`）。
- **验收**：真机验证：向其他应用听写完成后 HUD 出现且不抢焦点。

### [ ] T6. 粘贴前验证目标应用已激活，失败则不发 Cmd+V
- **文件**：`Sources/TypeMore/Services/PasteboardTextInsertionService.swift`（`insert`/`activateTargetApp`，5-31、59-76 行）
- **问题**：`NSApp.hide` 后仅尝试 `target?.activate()`，不检查结果，固定 sleep 350ms 后直接发 Cmd+V。目标应用退出/激活慢时，文本粘进任意前台应用。
- **修法**：激活后轮询 `NSWorkspace.shared.frontmostApplication?.bundleIdentifier`（每 50ms，上限约 1.5s）直到匹配目标；匹配即发 Cmd+V（可减少无谓等待）；超时则抛出明确错误（新增 `TypeMoreError` case，如 `targetActivationFailed`），调用方（AppModel）捕获后提示"目标应用未能激活，文本已在剪贴板"且**不恢复**旧剪贴板（此时剪贴板内容就是产出物）。
- **验收**：真机验证正常粘贴路径不回归；单测覆盖错误类型与提示文案路径（用 mock TextInsertionService 验证 AppModel 降级行为）。

### [ ] T7. WhisperKit 流式 / Apple 听写失败后重建引擎
- **文件**：`Sources/TypeMore/App/AppModel.swift`（约 627-629、695-697 行；引擎属性 54-56 行）
- **问题**：启动/收尾失败路径只对 sherpa 调 `rebuildSherpaStreamingEngine()`；WhisperKit 流式与 Apple 听写失败后同一引擎实例直接复用，可能带脏状态卡死下次听写（与 v1.0.2 修的 sherpa 同类问题）。
- **修法**：把 `whisperKitStreamingEngine`、`appleSpeechAnalyzerEngine` 从 `let` 改 `var`，新增 `rebuildStreamingEngine(for backend:)` 统一重建（sherpa 分支复用现有逻辑；WhisperKit 用 `whisperKitStreamingModel` 重建；Apple 引擎在 `#available(macOS 26.0, *)` 内重建）。失败路径统一调用。
- **验收**：单测：注入会在 finish 抛错的 mock 引擎，验证失败后引擎实例被替换（或重建钩子被调用）。

### [ ] T8. 监听音频设备配置变化，录音中断流时明确报错
- **文件**：`Sources/TypeMore/Services/AVAudioEngineLiveRecordingService.swift`（必要时 `AVAudioEngineRecordingService.swift` 一并）
- **问题**：全仓库无 `.AVAudioEngineConfigurationChange` 监听。录音中拔麦克风/切默认输入设备，tap 停止供数或格式失配，会一直挂在 recording 状态直到用户手动结束。
- **修法**：`startStreaming` 时订阅 `NSNotification.Name.AVAudioEngineConfigurationChange`（对应 engine 实例），收到后通过新增的错误回调（如 `onStreamInterrupted: (Error) -> Void`）通知 AppModel；AppModel 停止当前会话、走现有失败清理路径并提示"音频输入设备已变化，听写已停止，请重试"。stop 时移除订阅。**不做**自动无缝续录（符合产品"不静默切换"原则）。
- **验收**：真机：录音中拔掉/切换输入设备，几秒内出现明确错误而非永久挂起；正常流程无回归。

### [ ] T9. 清理词典→热词断链与无谓的引擎重建
- **文件**：`Sources/TypeMore/Services/SherpaHotwordsStore.swift`、`Sources/TypeMore/App/AppModel.swift`（`refreshSherpaRecognizerAfterDictionaryChange`，约 1521 行）、`Sources/TypeMore/Services/SherpaParaformerStreamingEngine.swift`（43 行）
- **问题**：`hotwords(from _:)` 完全忽略传入词典，只写死 10 个英文词（README 说词典不作热词是有意的，但签名误导）；而词典变更却触发完整 recognizer 重建——重建后热词毫无变化，纯浪费，且预热期间无法听写。
- **修法（短期，保持现有产品行为）**：①`writeHotwords` 去掉 `dictionary` 参数（或改名 `writeBuiltinHotwords()`），调用点同步修改；②`persistPersonalDictionary` 不再调用 `refreshSherpaRecognizerAfterDictionaryChange()`（词典只影响 LLM 上下文，不需要重建识别器）；③保留函数但确认无其他调用方后删除，或注释说明。
- **验收**：修改词典条目后不触发 sherpa 预热/重建（可通过诊断日志断言无 `recognition.sherpa_engine.rebuild` 事件）；识别与 LLM 词典注入行为不变；`swift test` 全绿。

### [ ] T10. `autoSubmitAfterDictation` 死代码处理
- **文件**：`Sources/TypeMore/App/AppModel.swift`（41、812、846-848 行）
- **问题**：全仓库无任何地方置 `true`，且 812 行在 846 行检查前强制置 `false`——"听写完成自动回车"功能从未生效。
- **修法（二选一，默认选 a）**：
  a) 删除该属性及相关分支（846-848 行改为恒走 readyToSubmit）。
  b) 若要真正实现：加设置项 `autoSubmitAfterDictation` 持久化到 SettingsStore + SettingsView 开关，去掉 812 行的强制置 false。
- **验收**：方案 a：编译通过、行为不变；方案 b：开关开启时听写完成自动发回车（真机验证）。

---

## 第三批：打扫（P2）

### [ ] T11. 中断 `.inserting` 阶段的语义修正
- **文件**：`Sources/TypeMore/App/AppModel.swift`（`toggleDictation`/`interruptCurrentFlow`，约 344-355、860-892 行）
- **问题**：`.inserting` 阶段中断时 CGEvent 已发出（文本实际粘贴成功），但 `activeOperationID` 被清空导致 `saveTranscript` 跳过、HUD 显示"已中断"——状态与事实矛盾。
- **修法**：`interruptCurrentFlow` 对 `sessionState == .inserting` 直接忽略（窗口 <1 秒），或 `toggleDictation` 的 `.inserting` 分支不再映射到 interrupt。
- **验收**：插入期间连按快捷键，文本正常入历史、状态最终为 readyToSubmit。

### [ ] T12. 删除 `cancelEngineAfterStartupFailure` 相同分支死代码
- **文件**：`Sources/TypeMore/App/AppModel.swift`（1121-1125 行）：if/else 两个分支完全相同，合并为一句 `Task { await engine.cancel() }`。

### [ ] T13. `withTimeout` 改用 TaskGroup 实现
- **文件**：`Sources/TypeMore/App/AppModel.swift`（1138-1186 行）、`Sources/TypeMore/Services/SherpaParaformerStreamingEngine.swift`（约 205-253 行有一份近似拷贝）
- **问题**：手写 continuation + NSLock + 三个 Task；成功后超时 Task 仍持有引用直到 sleep 到期；两处重复实现。
- **修法**：抽成共享的 `withTimeout` 工具（`withThrowingTaskGroup`：一个跑 operation、一个 sleep 后 throw timeout，先完成者胜出并 `group.cancelAll()`），两处调用替换。
- **验收**：单测：正常完成、超时、外部取消三条路径。

### [ ] T14. 后处理 filler 删除加词边界，保留换行
- **文件**：`Sources/TypeMore/Services/CodingPromptPostProcessor.swift`、`Tests/TypeMoreTests/PostProcessorTests.swift`
- **问题**：`"就是"`"的话"等用 `replacingOccurrences` 全局删除，"你就是对的"→"你对的"；`collapseWhitespace` 把换行全部折成空格，破坏多行口述。
- **修法**：①中文 filler 仅在句首/标点后等安全位置删除（正则加边界），或仅删除连续重复出现的 filler——采取保守策略，宁可漏删不可误删；②空白折叠改为：行内多空格折一个，保留换行符。
- **验收**：新增用例："你就是对的"不变、"就是说我们要……"句首删除、多行文本保留换行；现有测试更新后全绿。

### [ ] T15. HistoryStore 读写失败不再静默
- **文件**：`Sources/TypeMore/Stores/HistoryStore.swift`
- **问题**：`load`/`save` 全 `try?` 吞错，history.json 损坏时 200 条历史静默消失。
- **修法**：`load` 失败时把损坏文件改名为 `history.corrupt-<timestamp>.json` 留存，返回空数组并通过返回值/回调让 AppModel 显示一次性提示；`save` 失败记录诊断事件。
- **验收**：单测：写入损坏 JSON → load 返回空且损坏文件被保留改名。

### [ ] T16. 历史记录自动保留策略
- **文件**：`Sources/TypeMore/Stores/HistoryStore.swift`、`SettingsStore.swift`、`Views/SettingsView.swift`（隐私 tab）
- **问题**：只有 200 条上限，无时间维度清理；口述中带出的敏感内容永久留存。
- **修法**：SettingsStore 增加 `historyRetention`（枚举：永久/30 天/7 天/1 天，默认永久保持兼容）；load 与 save 时按 `createdAt` 过滤过期记录；隐私设置页加选择器与说明文案。
- **验收**：单测：过期记录被过滤；设置持久化往返正确。

### [ ] T17. 热键注册失败不持久化坏配置
- **文件**：`Sources/TypeMore/App/AppModel.swift`（`updateHotkey`，1254-1266 行）
- **问题**：先写 SettingsStore 再注册，注册失败（快捷键被系统/他应用占用）也已持久化，重启后热键仍坏。
- **修法**：先注册，检查 `HotkeyRegistrationResult` 成功后才写 settings；失败则回滚为旧热键并重新注册旧值，`hotkeyStatusMessage` 提示原因。
- **验收**：单测：mock coordinator 返回失败时 settings 不变。

### [ ] T18. 收敛 `applicationSupportDirectory.first!` force unwrap
- **文件**：`KeychainStore.swift`、`HistoryStore.swift`、`DiagnosticsRecorder.swift`、`SherpaHotwordsStore.swift`、`AVAudioEngineRecordingService.swift`、`AVAudioEngineLiveRecordingService.swift`、`SherpaModelManager.swift`
- **修法**：新增共享工具（如 `AppDirectories.applicationSupport() throws -> URL` 或返回可选并统一兜底到 `FileManager.default.temporaryDirectory`），替换所有 `first!`。
- **验收**：`grep -rn "userDomainMask).first!" Sources/` 无结果。

### [ ] T19. 取消热键：补全或删除半成品
- **文件**：`Sources/TypeMore/App/AppModel.swift`（`updateHotkey(.cancel)` 分支）、`SettingsStore.swift`、`Views/SettingsView.swift:92`
- **问题**：设置页只读展示中断快捷键；`updateHotkey(.cancel)` 存在但无 UI 入口、SettingsStore 无持久化字段。
- **修法（推荐补全）**：SettingsStore 加 `cancelHotkey` 持久化；SettingsView 用 `HotkeyRecorderView` 替换只读展示；AppModel init 读取持久值。
- **验收**：改中断热键→重启后仍生效。

### [ ] T20. AppModel 状态机核心路径测试
- **文件**：新建 `Tests/TypeMoreTests/AppModelStateMachineTests.swift`
- **背景**：AppModel 已全依赖注入，但状态机零测试。至少覆盖：
  - idle→start→recording→finish→readyToSubmit→sendReturn→idle 全流程（mock 引擎/录音/插入）
  - 启动阶段中断（processing 时 interrupt）状态复位、watchdog 取消
  - 引擎 prepare/startSession 抛错 → failed 状态 + 引擎重建钩子被调
  - LLM optimize 抛错 → 降级用本地结果且流程继续
  - 快速双击（start 未完成时再次 toggle）不产生双会话
- **验收**：以上用例全绿，作为后续所有重构的安全网（建议在做 T1/T2 前先做本项）。

---

## 执行建议

- 顺序：**T20（安全网）→ T1-T4 → T5-T10 → T11-T19**。T20 提前做能给第一批重构兜底。
- 每项独立提交，提交信息引用任务号（如 `fix(audio): serialize tap callback state (T1)`）。
- 不要顺手做清单外的重构；发现新问题追加到本文件底部"新发现"区。

## 新发现

（执行过程中追加）
