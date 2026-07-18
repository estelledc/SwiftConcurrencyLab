# 实验学习指南

App 只负责选择策略、触发实验和显示紧凑结果；完整原理、操作与复验都在这里。每次只做一张卡：

1. 先写下预测。
2. 用 `⌘⇧O` 打开卡片给出的真实文件，再用符号或源码锚点定位。
3. 按卡片设置断点并运行 App。
4. 用 App 状态、Logs、LLDB/Debugger 三类证据回答思考题。
5. 先 `Cancel`，再到 `Logs → Reset` 清空事件，独立复验。

> `Cancel` 只发出取消请求；任务必须运行到挂起点或显式检查点才会真正停止。实验页 `Reset` 会先取消当前 Task、清空页面状态和 Logs；Logs 页自己的 `Reset` 只清空事件。

<!-- lab-card:responsiveUI -->
<a id="lab-responsive-ui"></a>
## 1. 主线程响应性

### 定位与机制

这个实验位于“任务执行位置 → 主线程能否继续处理输入 → 最终 UI 提交”的链路。`await` 的关键不是“自动切到后台”，而是当前 Task 在等待期间可以挂起，让执行器运行其他工作；真正的 UIKit 写入仍由 `@MainActor` 的 `LabDetailViewController.commit` 完成。

### 真实代码定位

- Source：`Sources/SwiftConcurrencyCore/Runners.swift`
- 主锚点：`case .responsiveUI:`
- 关联符号：`StructuredConcurrencyLabRunner.run(_:recorder:)`
- UI 提交：`SwiftConcurrencyLab/LabDetailViewController.swift` → `commit(_:requestID:strategy:)`

### App 操作

1. Learn →「1. 主线程响应性」。
2. 点 `Run` 后立即点 `Logs`、返回，再重新进入实验。
3. 交互应持续可用；回到实验后查看紧凑状态。

### Xcode / LLDB 操作

1. `⌘⇧O` 输入 `Runners.swift`，在 `case .responsiveUI:` 和 `commit` 各设断点。
2. 在第一个断点继续执行；等待期间用 Debug bar 的 Pause 暂停一次，查看 Debug navigator 的主线程。
3. 在 LLDB 输入 `thread list`，再选主线程输入 `thread backtrace`。
4. 到 `commit` 断点执行 `po Thread.isMainThread`，结果应为 `true`。

### 预期真实证据

- Logs 至少包含 `started → scheduled → completed → uiCommit`。
- `commit` 只命中一次，且位于主线程/`@MainActor` 隔离路径。
- 等待模拟服务时，导航和 Logs 仍可响应。

### Cancel / Reset / 复验

- 运行后立即点 `Cancel`；本实验很短，可能已完成，这说明“点了 Cancel”不等于“必然观察到取消”。
- 打开 `Logs → Reset`，确认出现空状态。
- 重新运行并在 `SimulatedMailboxService.load` 内暂停更久，再验证主线程栈没有同步等待这段延迟。

### 误区与边界

- 误区：`async` 函数天然在后台线程运行。正确理解：隔离域与执行器决定执行位置，`await` 只表示可能挂起。
- 边界：本实验证明的是“当前实现没有在主线程同步等待”，不等于 CPU 密集工作天然安全；CPU 重活仍需明确移出 MainActor 并用 Time Profiler 验证。

### 思考题

如果把模拟延迟换成主线程上的同步 `Thread.sleep`，App、主线程 backtrace 和 Logs 的顺序会分别发生什么变化？

<!-- lab-card:parallelInbox -->
<a id="lab-parallel-inbox"></a>
## 2. 顺序 await 与并行加载

### 定位与机制

这个实验比较三种 fan-out/fan-in：`async let`、GCD + continuation、`OperationQueue`。三个请求可以按不同顺序完成，但最终按输入顺序提交，说明“并发完成顺序”和“业务结果顺序”是两个独立设计。

### 真实代码定位

- Source：`Sources/SwiftConcurrencyCore/Runners.swift`
- 主锚点：`case .parallelInbox:`
- 关联符号：`StructuredConcurrencyLabRunner.run`、`GCDLabRunner.run`、`OperationLabRunner.run`
- 核心语句：`async let profile`、`group.addTask`、`queue.addOperation`

### App 操作

1. Learn →「2. 顺序 await 与并行加载」。
2. 先选 `Swift Concurrency` 点 `Run`，打开 Logs 记下事件。
3. Reset 后依次选择 `GCD`、`Operation`；每次只比较一种策略。

### Xcode / LLDB 操作

1. 在三种 runner 的 `run` 入口分别设断点，并给断点加条件或名称，避免混淆。
2. Swift Concurrency 路径在三个 `async let` 后设断点；GCD 路径在 `group.addTask` 内设断点；Operation 路径在 `queue.addOperation` 内设断点。
3. LLDB 执行 `thread list`、`thread backtrace`；在 GCD/Operation 断点执行 `frame variable index value`。
4. 在 Xcode Debug navigator 展开 Threads/Queues，比较 Task、Dispatch queue 与 Operation worker 的呈现方式。

### 预期真实证据

- 三种策略的状态都归一为 `profile, messages, recommendations`，App 显示 `3 values in Logs`。
- Logs 每轮都有 `started`、三个 `scheduled`、`completed`、`uiCommit`。
- worker 的命中/完成顺序可以变化，但 `LabOutcome.values` 的顺序稳定。

### Cancel / Reset / 复验

- 每种策略完成后都先去 `Logs → Reset`，避免把不同 run 的事件混在一起。
- Swift Concurrency 运行中点 `Cancel`，观察当前实现是否在 service 挂起点响应；GCD/Operation 的底层工作不会因为外层 UIKit Task 取消而自动撤回。
- 重新运行同一策略 3 次，确认“稳定提交顺序”可重复。

### 误区与边界

- 误区：并发就应该按完成先后直接更新 UI。正确理解：业务常需要显式恢复输入顺序或 latest-wins。
- 边界：三种实现只用于对照任务模型，不代表它们取消语义等价；GCD 和 Operation 路径在这里主要证明 fan-out/fan-in。

### 思考题

如果产品要“哪个请求先完成就先渲染哪个区块”，你会保留当前排序，还是把输出改成带资源 ID 的增量事件？为什么？

<!-- lab-card:cooperativeCancellation -->
<a id="lab-cooperative-cancellation"></a>
## 3. 取消是协作式的

### 定位与机制

取消首先只是 `Task` 上的状态。代码要在 `Task.checkCancellation()`、可取消的 `await`，或主动读取 `Task.isCancelled` 时协作退出；没有观察点的同步循环不会因为 `cancel()` 被强制终止。

### 真实代码定位

- Source：`Sources/SwiftConcurrencyCore/Runners.swift`
- 主锚点：`case .cooperativeCancellation:`
- 关联符号：`Task.checkCancellation()`、`SimulatedMailboxService.load`
- UI 入口：`LabDetailViewController.cancelActiveRun()`

### App 操作

1. Learn →「3. 取消是协作式的」。
2. 点 `Run` 后立刻点 `Cancel`。
3. 打开 Logs，查找 `cancelled · Task observed cancellation`；如果没出现，说明任务已在请求到达前完成，Reset 后重试。

### Xcode / LLDB 操作

1. 在 `Task.checkCancellation()` 和 `catch is CancellationError` 两处设断点。
2. Run 后点 Cancel；断在检查点时执行 `thread backtrace`，确认调用链来自 `StructuredConcurrencyLabRunner.run`。
3. 在 LLDB 执行 `p Task<Never, Never>.isCancelled` 可能受泛型上下文限制；优先直接在源码临时使用 Debugger expression `po Task.isCancelled`，若 LLDB 无法推断就以 catch 断点与 Logs 为准。
4. 添加 Swift Error Breakpoint，只勾选 `CancellationError`，观察错误被当前 `catch` 消费而不是崩溃。

### 预期真实证据

- 取消在显式检查点或 `Task.sleep` 挂起处被观察，进入 `catch is CancellationError`。
- Logs 记录 `.cancelled`，不会伪造 `.completed`。
- UI 立即显示“Cancellation requested”，但底层何时退出要由断点/Logs 证明。

### Cancel / Reset / 复验

- 第一次立即 Cancel；第二次等待两步后再 Cancel，比较最后一个 `step N resumed`。
- 每轮使用 `Logs → Reset` 清空事件。
- 第三次不取消，预期经过 6 个检查点并显示完成；这是一条必要的对照组。

### 误区与边界

- 误区：`Task.cancel()` 类似杀线程。正确理解：它设置取消状态并唤醒部分可取消挂起点。
- 边界：`try?` 可能吞掉 `CancellationError`；真实业务要决定是传播、转换为状态，还是在清理后重新抛出。

### 思考题

如果循环中的每一步变成 200 ms 的纯同步计算，你应把取消检查放在哪里，才能兼顾响应速度和检查开销？

<!-- lab-card:isolatedUnread -->
<a id="lab-isolated-unread"></a>
## 4. 未读数的隔离

### 定位与机制

20 个 child Task 并发请求写入同一个未读数。`UnreadCounter` 是 actor，调用方必须 `await counter.increment()`；actor 隔离把共享可变状态的访问串行化，而 `TaskGroup` 仍允许各 child Task 并发调度。

### 真实代码定位

- Source：`Sources/SwiftConcurrencyCore/Runners.swift`
- 主锚点：`case .isolatedUnread:`
- 关联符号：`UnreadCounter.increment()`、`withTaskGroup(of:)`
- actor 定义：`Sources/SwiftConcurrencyCore/Support.swift` → `public actor UnreadCounter`

### App 操作

1. Learn →「4. 未读数的隔离」。
2. 连续运行 3 次，每次记录状态中的 `unread=20`。
3. 打开 Logs，确认每轮只有最新 request 获得 UI commit。

### Xcode / LLDB 操作

1. 在 `group.addTask` 和 `UnreadCounter.increment()` 各设断点。
2. 在 increment 断点启用“Automatically continue after evaluating actions”，加入 Log action 打印命中次数，避免手动继续 20 次。
3. 暂停时查看 Debug navigator 的 Tasks；执行 `thread list`，不要把“线程数”误当“Task 数”。
4. 在 `counter.snapshot()` 后设断点，执行 `frame variable count`。

### 预期真实证据

- 每轮结果稳定为 `unread=20`。
- 同一 actor 的 `increment` 不会同时执行两个隔离状态修改。
- Core 测试用 100 次并发 increment 验证结果为 100，和 App 的 20 次样本相互补充。

### Cancel / Reset / 复验

- Run 后立即 Cancel；child TaskGroup 的取消传播由实际挂起/检查点决定，这个极短任务可能已完成。
- `Logs → Reset` 后重跑 3 次，结果都应一致。
- 可临时把计数提升到 1,000 便于观察，但复验后恢复；不要用 Debug 时序偶然性当正确性证明。

### 误区与边界

- 误区：actor 意味着内部代码永不交错。正确理解：actor 在不跨 `await` 的同步隔离片段内互斥；跨 `await` 可能 reentrant。
- 边界：actor 解决数据隔离，不自动保证业务操作的事务性、公平性或顺序符合产品语义。

### 思考题

如果一次业务更新要求“读取旧值、请求网络、再按旧值写回”，为什么仅把字段放进 actor 仍可能出错？

<!-- lab-card:actorReentrancy -->
<a id="lab-actor-reentrancy"></a>
## 5. Actor reentrancy

### 定位与机制

actor 方法执行到 `await` 时会让出执行权，其他调用可以进入同一个 actor。实验用可控 gate 保证两个 unsafe 调用都在旧条件后挂起，稳定产生 `accepted=2`、`remaining=-1`；`PinQuota.reservedPin` 则在等待前先增加 `reserved`，把“资格占用”纳入 actor 状态。

### 真实代码定位

- Source：`Sources/SwiftConcurrencyCore/Runners.swift`
- 主锚点：`case .actorReentrancy:`
- 关联符号：`PinQuota.unsafePin(using:)`、`PinQuota.reservedPin(using:)`、`AsyncGate.waitUntilWaiters(_:)`
- 机制对照：`Sources/SwiftConcurrencyCore/Support.swift` → `unsafePin(using:)` 与 `reservedPin(using:)`

### App 操作

1. Learn →「5. Actor reentrancy」，选择 `Unsafe` 后点 Run。
2. 记录 `accepted=2`、`remaining=-1`；切到 `Reserved` 再 Run。
3. 修复组必须是 `accepted=1`、`remaining=0`。点实验页 `Reset` 后状态回到 Ready，Logs 同时清空。

### Xcode / LLDB 操作

1. 在 `unsafePin` 与 `reservedPin` 的 guard、`await gate.wait()` 前后、`remaining -= 1` 各设断点。
2. Unsafe 模式观察两个调用都到达 gate；Reserved 模式观察第二个调用在 guard 返回。执行 `frame variable`。
3. 在 await 前后各执行 `thread backtrace`，比较续执行栈；不要假设恢复到同一线程。
4. 使用 Xcode 的 Swift Concurrency Instrument 录制一次，查看两个 Task 的挂起与恢复区间。

### 预期真实证据

- Unsafe：两个请求都通过 await 前的检查，最终 `accepted=2`、`remaining=-1`。
- Reserved：await 前 `reserved` 已经变为 1，第二个请求不能重复占用，最终 `accepted=1`、`remaining=0`。
- Core 测试等待确切 waiter 数再开 gate，不依赖偶然调度顺序。

### Cancel / Reset / 复验

- 先跑 Unsafe 负对照，再跑 Reserved 正对照，不需要改源码。
- 两组完成后点实验页 `Reset`；它取消当前页面 Task、作废 requestID，并清空事件。
- 连续各跑 3 次，数值合同必须完全相同。

### 误区与边界

- 误区：actor 方法从入口到返回是完整锁区。正确理解：每个跨 actor `await` 都是状态可能变化的边界。
- 边界：这里用 reservation 修复配额问题；真实系统还要处理取消后释放 reservation，否则可能泄漏资格。

### 思考题

如果等待 gate 的 Task 被取消，`reserved` 应在什么位置回滚？使用 `defer` 是否一定足够？

<!-- lab-card:latestWinsSearch -->
<a id="lab-latest-wins-search"></a>
## 6. 搜索 latest-wins

### 定位与机制

旧搜索可能晚于新搜索返回。latest-wins 不能只依赖取消，因为底层工作可能忽略取消；提交结果时还要验证稳定身份。`LatestValueStore.begin("swift")` 建立当前查询身份，`submit` 只允许匹配者写入。

### 真实代码定位

- Source：`Sources/SwiftConcurrencyCore/Runners.swift`
- 主锚点：`case .latestWinsSearch:`
- 关联符号：`LatestValueStore.begin(_:)`、`LatestValueStore.submit(query:result:)`
- 故意边界：旧请求调用 `ignoreCancellation: true`

### App 操作

1. Learn →「6. 搜索 latest-wins」。
2. 点 Run；同一轮会并发发出慢的 `old` 和快的 `swift`。
3. 状态最终只能是 `swift-result`，重复 3 次。

### Xcode / LLDB 操作

1. 在 old/latest 两个 closure 和两个 `store.submit` 调用处设断点。
2. 给断点添加 Log action，分别输出 `old submit`、`swift submit`，自动继续以保留真实竞态顺序。
3. 在 `LatestValueStore.submit` 内执行 `frame variable query result`，观察旧结果到达但不满足身份条件。
4. 在 Debug navigator 查看两个 child Task；需要分析时用 Swift Concurrency Instrument 保存 trace。

### 预期真实证据

- `swift` 请求更早完成；`old` 即使更晚提交，也不能覆盖当前值。
- App 状态始终显示 `identity guard 保留最新查询 · swift-result`。
- Core 测试重复运行 10 次，防止一次偶然顺序被误当成可靠实现。

### Cancel / Reset / 复验

- Run 后立即 Cancel，观察旧请求仍可能因为 `ignoreCancellation` 继续到底层完成。
- `Logs → Reset` 后重跑；Reset 只是清屏，不会停止忽略取消的底层工作。
- 连续快速 Run 两次，旧 requestID 即使完成也没有 UI commit 资格。

### 误区与边界

- 误区：取消旧任务就足以保证最新结果。正确理解：取消是优化，提交前的 identity guard 才是正确性边界。
- 边界：示例把“当前查询”和“结果”复用一个字符串字段以保持最小化；生产代码应使用独立 token/request ID 与显式状态。

### 思考题

如果两个相同文本的查询先后发出，仅比较 query 字符串够不够？什么时候必须使用递增 generation 或 UUID？

<!-- lab-card:cellReuse -->
<a id="lab-cell-reuse"></a>
## 7. Cell 复用与身份校验

### 定位与机制

UITableViewCell 会离开屏幕后被新模型复用。异步头像 Task 属于“当前 represented model”，因此配置新模型和 `prepareForReuse` 都要取消旧 Task，提交前还要比较 `representedID`；Run 使用可控 gate 真实执行“配置旧 ID → 取消 → 配置新 ID → 新结果提交 → 旧结果恢复并被拒绝”。

### 真实代码定位

- Source：`SwiftConcurrencyLab/ConversationCell.swift`
- 主锚点：`CellReuseIdentity.canCommit`
- 关联符号：`ConversationCell.configure(with:)`、`prepareForReuse()`
- 可重复工作负载：`runCellReuseProbe()`；数据入口：`InboxViewController.tableView(_:cellForRowAt:)`

### App 操作

1. Learn →「7. Cell 复用与身份校验」点 Run。
2. 状态必须显示 `committed=message-new` 与 `rejected=message-old`；Logs 还会记录旧任务 cancel 和 stale commit rejected。
3. 再到 Inbox 快速上下滚动，把相同 guard 放回真实 UITableViewCell 场景观察。

### Xcode / LLDB 操作

1. 在 `runCellReuseProbe()`、`configure(with:)`、`prepareForReuse()` 和 `CellReuseIdentity.canCommit` 各设断点。
2. 在 probe 的旧 commit 调用处检查 `Task.isCancelled`；在真实 cell guard 处检查 `representedID` 与 `id`。
3. LLDB 执行 `frame variable id token` 与 `po self.representedID`。
4. 打开 Debug View Hierarchy，选择可见 cell，核对屏幕层级；它只能显示当前 UI，异步身份仍要靠变量与断点证明。

### 预期真实证据

- Run 的事件顺序固定为 configure old、cancel old、configure new、commit new、reject old。
- 结果固定为 `committed=message-new`、`rejected=message-old`、`cancelled=true`，不再是静态 message fixture。
- 真实 cell 复用时旧 `avatarTask` 被取消，旧 Task 即使恢复也会被共享 identity guard 挡住。
- 快速滚动后可见行的头像 token 与当前会话一致。

### Cancel / Reset / 复验

- Learn 页的 Cancel/Reset 只控制该实验 runner，不控制 Inbox 每个 cell 自己持有的 Task。
- 点实验页 Reset 清空当前结果和事件；返回 Inbox 触发多轮复用。
- 临时放慢 engineering 头像延迟可扩大复现窗口，复验后恢复原值并重跑 UI 测试。

### 误区与边界

- 误区：`prepareForReuse` 里 cancel 就绝对安全。正确理解：底层操作可能忽略取消，所以提交前仍需身份校验。
- 边界：本例在 `@MainActor` 上更新 UILabel；真实图片解码、缓存和预取还需要独立的资源所有权与内存策略。

### 思考题

Diffable Data Source 改变了 indexPath 的稳定性吗？为什么 item identifier 仍然应当参与异步提交校验？

<!-- lab-card:boundedPrefetch -->
<a id="lab-bounded-prefetch"></a>
## 8. 受限并发预加载

### 定位与机制

一次启动全部预加载会放大连接、内存和调度压力。`boundedMap` 先启动 `limit` 个 child Task，每完成一个才补一个；结果附带输入 index，最后排序恢复输入顺序。

### 真实代码定位

- Source：`Sources/SwiftConcurrencyCore/Runners.swift`
- 主锚点：`case .boundedPrefetch:`
- 关联符号：`boundedMap(_:limit:operation:)`
- 调度点：`group.addTask` 与 `while let result = try await group.next()`

### App 操作

1. Learn →「8. 受限并发预加载」。
2. 点 Run；样本输入是 12 个 preview、并发上限 4。
3. App 显示 `12 values in Logs`，Logs 中应有 `limit=4` 的 scheduled 事件。

### Xcode / LLDB 操作

1. 在 `boundedMap` 初始填充循环、`group.next()` 和补任务的 `group.addTask` 处设断点。
2. 在 LLDB 执行 `frame variable limit results`；每次补位时观察 results 增长。
3. 使用 Swift Concurrency Instrument 录制 Task 时间线，数任一时刻同时处于 operation 区间的任务。
4. 用 Time Profiler 对比 `limit=1` 与 `limit=4`；记录 trace，不凭一次墙钟时间下结论。

### 预期真实证据

- Core 测试中的 probe 观测最大并发恰好为 3（测试输入 limit=3），且结果保持输入顺序。
- App 样本固定调度 12 项并宣告 limit=4。
- 结果数量为 12，且不会因为完成顺序变化而乱序提交。

### Cancel / Reset / 复验

- Run 后立即 Cancel，确认 child TaskGroup 接收父任务取消；具体退出点仍取决于 operation 是否检查取消。
- `Logs → Reset` 后正常跑一次作为对照。
- 分别以 limit 1、4、12 在隔离修改中录制 trace；恢复 4 后运行 Core tests。

### 误区与边界

- 误区：并发上限应该等于 CPU 核数。正确理解：限制取决于任务性质、服务限流、内存与延迟目标。
- 边界：这个实现会等待全部结果后返回，不是流式消费；大数据集可能需要 `AsyncSequence` 或增量提交。

### 思考题

当某一个 child Task 失败时，当前 throwing TaskGroup 会怎样处理其余任务？产品需要“全失败”还是“部分成功”？

<!-- lab-card:callbackBridge -->
<a id="lab-callback-bridge"></a>
## 9. 旧 callback 桥接

### 定位与机制

continuation 把 callback 的一次完成转换成 async 函数的一次恢复。checked continuation 会在调试时帮助发现 double-resume；never-resume 则让等待方永久挂起，因此桥接层必须审计 callback 的所有分支。

### 真实代码定位

- Source：`Sources/SwiftConcurrencyCore/Support.swift`
- 主锚点：`public static func loadAsync() async throws -> String`
- 关联符号：`LegacyCallbackAPI.load(_:)`、`withCheckedThrowingContinuation`
- 恢复点：`continuation.resume(with: $0)`

### App 操作

1. Learn →「9. 旧 callback 桥接」。
2. 点 Run，状态应显示 `legacy-result`。
3. 打开 Logs，确认 completed 后只有一个 uiCommit。

### Xcode / LLDB 操作

1. 在 `loadAsync` 入口、callback closure、`continuation.resume` 三处设断点。
2. 命中 callback 时执行 `thread list` 与 `thread backtrace`，确认 callback 来自 global queue。
3. 继续到 App 的 `commit`，执行 `po Thread.isMainThread`，确认 UI 提交回到 MainActor。
4. 只在临时诊断代码中复制一次 `resume` 观察 checked continuation 的运行时错误；完成后撤销该故意故障。

### 预期真实证据

- callback 命中一次、continuation resume 一次、await 返回一次。
- App 状态为 `checked continuation 恰好 resume 一次 · legacy-result`。
- Core 测试 `testLegacyBridgeReturnsOnce` 通过；没有 double-resume crash 或永久等待。

### Cancel / Reset / 复验

- Run 后立即 Cancel；当前 legacy API 没有取消句柄，callback 仍可能到达，但 requestID/Task 取消会阻止过期 UI commit。
- `Logs → Reset` 后正常运行一次，确认完成链。
- 若真实 API 提供 cancel token，应把 Task cancellation handler 映射到 token，再补一条“取消后不 resume 业务结果”的测试。

### 误区与边界

- 误区：换成 continuation 后旧 API 自动获得结构化取消。正确理解：continuation 只桥接完成，不创造底层取消能力。
- 边界：checked continuation 的诊断主要服务 Debug；Release 中不能依赖它代替完整分支测试与 API 契约。

### 思考题

一个 callback API 既可能同步回调、也可能异步回调时，桥接层的对象生命周期、取消竞态和 exactly-once 约束应如何测试？

## 学完后的最小验收

你应当能不看答案解释：

1. Task、线程、queue、actor 分别解决什么问题，为什么不能互换。
2. 取消为什么必须有观察点，latest-wins 为什么还要 identity guard。
3. actor 为什么仍有 reentrancy，如何把业务不变量跨过 `await`。
4. 为什么 Debugger/Logs 证明单次运行机制，Core/UI tests 证明可重复契约，二者缺一不可。

继续阅读：[并发证据手册](evidence-playbook.md)。
