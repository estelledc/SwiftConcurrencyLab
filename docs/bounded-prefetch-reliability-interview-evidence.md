# 受限预取并发可靠性：面试证据卡

更新日期：2026-07-24

> 当前状态：这是公开基线 `4b840aed6eee352b3c5aaf7347eb66e8b8dd7b0f` 之上的未提交、未发布本地候选。本文记录当前工作树能复验的工程合同，不把本地实验写成线上业务成果。

## 一句话结论

本轮把 `boundedMap` 从“最多同时跑 4 个任务”的成功路径示例，重构为覆盖成功、typed failure、父任务取消和 UIKit Reset 竞态的可靠性 harness：终态只能记录一次，且只能在所有 child Task 离开 TaskGroup 后记录；Reset 通过 generation 拒绝旧任务继续写 UI 日志。

## 为什么值得改

当前 iOS / Swift 岗位反复要求的不只是会写 `async/await`，而是能把并发代码变成可测试、可诊断、可回归的系统：

- [Apple Agentic OS Experiences](https://jobs.apple.com/en-ca/details/200643348-0836/software-engineer-agentic-os-experiences?team=SFTWR) 强调并发架构、UI framework、性能与可靠性。
- [Apple Swift Platform Experience SDET](https://jobs.apple.com/en-us/details/200665196/software-development-engineer-in-test-swift-platform-experience?team=APPST) 强调 test harness、诊断、Xcode / Simulator 与回归自动化。
- 同类 AI 产品 iOS 岗位也反复强调客户端质量、架构设计、持续迭代与重构；具体公司映射保留在个人求职材料，不写入公开项目仓库。

原项目已经能证明“限制并发数并保持输入顺序”，但缺少三个招聘方会追问的边界：失败发生后何时算真正结束、取消如何跨 Core 与 UIKit 传播、Reset 后旧任务能否重新污染界面和日志。

## 主链路

```text
UIKit Run
  -> StructuredConcurrencyLabRunner 捕获 recorder generation
  -> boundedMap(input, limit, one-shot monitor)
  -> TaskGroup 启动最多 limit 个 child
  -> 每完成一个才补一个，结果按输入 index 还原顺序
  -> TaskGroup scope 完全退出
  -> 记录 success / typed failure / cancelled 唯一 terminal
  -> MainActor 只提交当前 request
  -> recorder 只接受当前 generation 的 uiCommit
```

核心入口：

- `Sources/SwiftConcurrencyCore/Runners.swift`：`boundedMap`、`BoundedMapMonitor`、`BoundedPrefetchMode`。
- `Sources/SwiftConcurrencyCore/Support.swift`：带 generation 的 `LabEventRecorder`。
- `SwiftConcurrencyLab/LabDetailViewController.swift`：Run / Cancel / Reset 与 `@MainActor` 提交。
- `Tests/SwiftConcurrencyCoreTests/BoundedMapReliabilityTests.swift`：确定性成功、失败、取消矩阵。
- `SwiftConcurrencyLabUITests/SwiftConcurrencyLabUITests.swift`：跨 Core / UIKit 的可见状态回归。

## 四个关键合同

### 1. Terminal-after-drain

`Task.cancel()` 或 `group.cancelAll()` 只发出取消请求，不代表 child 已经退出。`boundedMap` 因此在 `withThrowingTaskGroup` 的 scope 返回或抛错后才调用 `recordTerminal`。

可断言的不变量是：

- 每次 invocation 恰好一个 terminal。
- terminal 发生时 `activeAtTerminal == 0`。
- terminal 之后 `lateCompletionCount == 0`。
- child failure 保留实际错误类型；父取消才记录 `.cancelled`。

### 2. Operation 返回后再次检查取消

取消是协作式的。业务 operation 可能吞掉 `Task.sleep` 的取消并正常返回，因此 wrapper 在调用 operation 前后都执行 `Task.checkCancellation()`。这阻止“父任务已经取消，但忽略取消的 operation 晚返回后仍被计为成功”。

### 3. Monitor 是 one-shot

`BoundedMapMonitor` 的生命周期只有 `fresh -> running -> finished`。同一 monitor 被顺序或并发复用时返回 typed `alreadyUsed`，而不是把两棵 Task tree 的 active、terminal 和错误计数静默合并。

### 4. UIKit 用 request identity 与 generation 分两层拒绝旧写回

- `activeRequestID` 决定哪个运行结果还能更新当前页面。
- `LabEventRecorder.generation` 决定哪个运行还能追加日志；Reset 递增 generation 并清空事件。
- Cancel 先取消当前 Task，再持有 drain task 等它真正结束；没有活动任务时 Cancel 是 no-op。
- Reset 会等待当前 run、cancel drain 和 pending uiCommit log 全部结束，再推进 generation、清空记录并恢复按钮。
- MainActor 页面状态先同步完成线性化，再异步串行写 `uiCommit`；因此“完成后再点 Cancel”不能把 completed 状态重标为 cancelled。

这里的“先后”是 recorder actor 接收并串行化事件的顺序，不等于多个 Task 或用户点击在墙钟时间上的物理发生顺序。

## 本轮关闭的失败模式

| 失败模式 | 旧风险 | 当前防线 |
|---|---|---|
| failure/cancel 后过早宣布 terminal | sibling 仍在运行，日志却显示已经结束 | terminal 只在 TaskGroup scope drain 后记录 |
| typed failure 与父取消同时发生 | 真实 child error 被误标为 CancellationError | terminal 分类只依据实际捕获错误 |
| operation 忽略取消 | 已取消任务晚返回并被计为成功 | operation 前后双重 cancellation check |
| monitor 被复用 | 两次运行的计数和 terminal 混在一起 | one-shot lifecycle + typed `alreadyUsed` |
| completed 后点击 Cancel | 页面把已完成结果改写为“取消中” | MainActor 先清空 active owner；无活动任务时 Cancel no-op |
| Cancel 后立刻 Reset | 旧 cancelled terminal 重新出现在空日志中 | 等待 drain + generation 拒绝旧事件 |
| pending uiCommit 后在 Logs Reset | Reset 后旧 uiCommit 又写回来 | 等待 pending log + generation 拒绝旧写入 |
| UI 证据共用 DerivedData / Simulator | 并行运行可能争用 `build.db` 或污染设备状态 | 一次性 Simulator、独立 DerivedData、`.xcresult` 和脱敏 receipt |
| README 测试数手写漂移 | 页面仍显示旧的 6 Core / 2 UI | audit 从全部 Swift 测试源扫描当前数量 |

## 验证结果

### 当前候选总门

2026-07-24 在当前未提交工作树执行 `make release-check`：

| 门禁 | 结果 | 能证明什么 |
|---|---:|---|
| Swift Package Core | 26/26 passed | 算法合同、generation 与既有并发实验回归 |
| XCUITest | 8/8 passed，0 failed，0 skipped | Simulator 上的页面路径和四类新增竞态合同 |
| Debug generic Simulator build | passed | 当前工程与严格并发设置可构建 |
| Release generic Simulator build | passed | Release 配置及 dSYM 路径可构建 |
| format / project / showcase / public scan | passed | 格式、项目配置、公开页面计数和隐私扫描合同 |

权威 result bundle 摘要：iPhone 17 Pro、iOS Simulator 26.2、8 passed、0 failed、0 skipped。结果包位于本地忽略目录 `.DerivedData/Logs/Test/`，没有提交到仓库。

### 隔离 UI receipt

`make test-ui-evidence` 还在一次性 Simulator 与独立 DerivedData 中完成同一当前树的 8/8。可携带收据为：

```text
.artifacts/ui-evidence/run-GJ16nK/receipt.json
result=Passed, total=8, passed=8, failed=0, skipped=0
simulator=iPhone 17 Pro, os=26.2
```

命令退出前已 shutdown 并删除一次性 Simulator，随后设备列表中不存在对应名称。整个 artifact 目录、build log、DerivedData 与 `.xcresult` 会包含本机绝对路径，只有脱敏 `receipt.json` 适合单独分享。

### 新增重点用例

Core 的 9 个可靠性用例覆盖：

1. success 必须等待全部 child drain。
2. injected typed failure 必须等待 stubborn siblings drain。
3. typed failure 与 parent cancel 同时出现时不能重标。
4. parent cancellation 的终态与 child drain。
5. operation 忽略取消直到 gate 释放后的二次检查。
6. monitor 顺序复用失败关闭。
7. monitor 并发复用失败关闭。
8. success / failure / cancellation 各 100 轮可控交错矩阵。
9. App cancellation probe 只有一个 cancelled terminal，没有 completed。

UI 的 8 个用例中，4 个直接覆盖本轮跨层语义：cancel-before-terminal、commit-before-cancel、Cancel→Reset、pending-uiCommit→Logs Reset。

最终独立代码复审结论为 P0=0、P1=0；这是本地审查意见，不是第三方认证、公开 CI 或生产 sign-off。

## 100 轮为什么不是“稳定性 100%”

100 轮使用 `AsyncGate` 和 fault injection 固定关键交错，每轮验证相同的不变量。它的价值是让竞态可复现、让错误收敛到具体合同；它不是随机压力测试，也没有代表线上调度分布。

因此可以说“100 轮确定性矩阵逐轮通过”，不能说“线上稳定率 100%”或“消除了全部竞态”。

## 不能声称什么

- 数据与等待均为本地 synthetic `Task.sleep`、gate 和 fault injection；没有真实网络、服务端取消、LLM 或生产预取流量。
- `started/active/peak/terminal/lateCompletion` 是正确性观测，不是 CPU、内存、吞吐或延迟性能指标。
- UI 结果来自 iOS Simulator，不是真机测试。
- Swift 6 strict concurrency 通过不等于 TSan 通过，也不证明运行时不存在 data race。
- 没有生产 p50 / p95、SLA、容量、能耗或线上稳定性结论。
- recorder actor 的序号不是用户点击或多个 Task 的墙钟时间线。
- 当前工作树未提交、未推送、未发布；不能写成线上交付、公开版本或外部采用。

## 面试讲法

### 30 秒版本

我把一个受限 TaskGroup 示例改成了并发可靠性 harness。关键不是调用 `cancelAll`，而是定义什么时候才能宣布结束：只有 TaskGroup 全部 child drain 后才能记录唯一 terminal。我用 gate 和 fault injection 分别覆盖成功、typed failure 和父取消，再在 UIKit 用 request identity 与 recorder generation 阻止 Cancel / Reset 后的旧 UI 和日志写回。当前本地门禁是 Core 26/26、Simulator UI 8/8 和 Release 构建通过。

### 60 秒版本

原项目只能证明并发上限和输入顺序，但招聘 JD 更关心故障传播、诊断和回归。我先给 `boundedMap` 增加 one-shot actor monitor，记录 active、peak、child outcome 与三类 terminal。terminal 放到 TaskGroup scope 退出之后，operation 前后都检查取消，避免 stubborn child 晚返回被误算成功；typed failure 也不会因为父任务同时取消而被重标。然后把合同接到 UIKit：Cancel 持有 drain task，commit 在 MainActor 上先取得所有权，Reset 等待 run、drain 和日志写入后递增 generation，旧 generation 的 terminal 与 uiCommit 都被拒绝。最后用 100 轮可控交错、4 条跨层竞态 UI 用例和独立 `.xcresult` receipt 验证。边界是全程本地 synthetic、Simulator，不能外推为性能或生产稳定性。

## 高频追问

1. 为什么不在收到第一个错误时马上记录 failure？
   - 因为 Swift 取消是协作式的，其他 child 可能仍在执行；过早记录会把“已请求结束”冒充“已经结束”。
2. 为什么 `cancelAll` 不够？
   - 它只传播取消请求。child 可以延迟检查、捕获取消，甚至短暂忽略取消，所以必须等待 task-group scope drain。
3. 为什么 operation 后还要 `Task.checkCancellation()`？
   - operation 可能吞掉取消并正常返回；wrapper 必须阻止这个结果进入成功路径。
4. 为什么 monitor 不能复用？
   - 指标描述一棵 Task tree。复用会让 active 与 terminal 的归属不再可解释，所以显式失败优于静默合并。
5. failure 与 cancellation 同时出现时如何分类？
   - 依据实际离开 group 的错误分类；不能因为父 Task 此刻是 cancelled 就覆盖 typed child failure。
6. request ID 和 generation 为什么都需要？
   - request ID 保护当前页面 owner，generation 保护跨页面共享日志和 Reset 边界；两者作用域不同。
7. Reset 为什么要等 pending uiCommit？
   - 否则旧 commit 可能在清空之后到达，形成“空日志又复活”的可见竞态。
8. 100 轮测试为什么不是普通 sleep-loop？
   - gate 固定关键交错和 waiter 数，失败能稳定复现；单纯 sleep 依赖调度器时机，容易既慢又假通过。
9. 这些指标能证明性能更好吗？
   - 不能。它们只证明并发合同；性能需要 Instruments trace、可比负载和 p50 / p95 口径。
10. 下一步最有价值的证据是什么？
   - 真机上的取消 / Reset 回归、专门的 TSan 诊断 fixture，以及接入可取消真实 transport 后的协议级测试；三者都不能用当前 Simulator 结果代替。

## 安全的候选简历句

> 构建 Swift 6 并发可靠性 harness，以可控交错验证受限 TaskGroup 的成功、typed failure 与父取消传播；100 轮矩阵逐轮要求唯一 terminal、child drain 后 active=0、无 late completion，并用 UIKit request identity / Reset generation 与独立 Simulator `.xcresult` 回归阻止过期 UI / log 写回。

使用限制：这句话只应与 XcodeDebuggingLab、SwiftMessengerLab 合并成一条“iOS Labs 工程技能证据”，并在面试中主动说明本地 synthetic、Simulator 和未发布边界；不能把它包装成真实业务项目或生产性能成果。

## 建议阅读与复验顺序

1. 先读本文的“四个关键合同”和“不能声称什么”。
2. 阅读 `boundedMap` 与 `BoundedMapMonitor`，自己回答 terminal 为什么在 group scope 外。
3. 阅读 100 轮矩阵，画出 success / failure / cancellation 三条时序。
4. 阅读 `LabDetailViewController`，解释 request ID、drain task、generation 各自保护什么。
5. 运行 `make test`，再运行 `make test-ui-evidence`；需要发布候选验收时才运行 `make release-check`。
6. 不看本文，用 60 秒版本复述；如果解释不了 failure 与 cancellation 的分类，就暂时不要把候选句写入正式简历。
