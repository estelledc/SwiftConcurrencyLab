# 并发证据手册

每个实验先写下预测，再执行并保存结论。App 的 Logs 说明事件顺序；Xcode 工具补充“为什么”与“是否真的安全”的证据。

## 先建立可重复基线

1. 仓库移动或 Xcode 升级后先跑 `make clean`，避免 ModuleCache、PCH 与 DerivedData 继续引用旧绝对路径。
2. 日常串行执行 `make test`、`make build`、`make test-ui`。这些命令默认共用 `.DerivedData`，并发执行会争用 `build.db`，不能作为有效失败证据。
3. 要保存 UI 证据或与其他实验并行时运行 `make test-ui-evidence`。它创建一次性 Simulator 和独立 DerivedData，保存 `.xcresult`、原始 summary、build log 与脱敏 JSON receipt 到本地忽略目录 `.artifacts/ui-evidence/`，完成后删除 Simulator。只有 `receipt.json` 适合携带或分享；build log、DerivedData 和结果包会包含本机绝对路径，整个 evidence 目录不得直接发布。
4. 在「并行加载」中每次只选一种策略，运行后核对 `started -> scheduled -> completed -> uiCommit`；点 `Reset` 后再测下一种。
5. 三种策略的任务可以按不同顺序完成，但 UI 提交值必须稳定为 `profile, messages, recommendations`。

## 受限预取可靠性矩阵

`BoundedMapMonitor` 是 one-shot：每次 invocation 必须新建，顺序或并发复用都会得到 typed error，避免把两棵任务树的指标静默合并。它记录 started、success / failure / cancelled child、current / peak active 和 terminal。`testDeterministicSuccessFailureAndCancellationMatrixFor100Rounds` 用可控 gate 固定交错，逐轮要求：恰好一个 terminal、记录 terminal 时 active=0、terminal 之后无 late completion；child failure 必须带错误类型，parent cancellation 必须把已启动 sibling 全部 drain。额外测试在 stubborn sibling 尚未释放时确认 terminal 仍为空，并验证忽略取消的 operation 返回后仍被 wrapper 拒绝为 success。它证明本地 TaskGroup 合同，不证明真实网络、服务端取消或生产 SLA。

App 的 `Cancellation Probe` 把四个 child 挂在可取消等待点。UI 用例执行 Run → Cancel → Logs，要求一条 `cancelled` 且没有 `completed` / `uiCommit`。这条路径验证 UIKit Task owner 到 Core TaskGroup 的跨层行为。

Recorder Reset 通过 generation 定义清屏边界：run 开始时取得 generation，Reset 原子递增 generation 并清空；旧 run、旧 cancel terminal 或旧 uiCommit 的晚到写入都会被拒绝。UI 回归分别覆盖 Cancel → Reset 和 pending uiCommit → Logs Reset，清空后等待 1 秒仍不得重新出现旧事件。generation 只治理本进程日志，不是业务事务或持久化版本号。

## Swift 6 严格并发

App 与 UI Test target 都显式设置 `SWIFT_VERSION = 6.0` 和 `SWIFT_STRICT_CONCURRENCY = complete`。可用以下命令检查最终生效值，而不是只看工程文件：

```bash
xcodebuild -project SwiftConcurrencyLab.xcodeproj \
  -scheme SwiftConcurrencyLab \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -showBuildSettings |
  grep -E 'SWIFT_VERSION|SWIFT_STRICT_CONCURRENCY'
```

严格并发检查能发现一部分隔离与 `Sendable` 问题，但不能证明运行时没有 data race，也不能代替取消、latest-wins 与 MainActor commit 的行为测试。

## Main Thread Checker

在 Scheme 的 Run Diagnostics 开启 Main Thread Checker。运行“主线程响应性”和“cell 复用”，确认 UI 写入始终由 `@MainActor` 路径完成；它不能证明不存在 data race。

## Thread Sanitizer

为专门的诊断 branch 或临时 fixture 开启 TSan，再制造高并发共享写入。默认 App 与 `make test` 不携带故意的 data race：TSan 样本不能被当成发布路径。记录冲突的两条 stack，再用 actor 或私有 queue/barrier 修复并复测。

## Instruments

使用 Swift Concurrency Instrument 检查 Task 生命周期、取消与并行度；使用 Time Profiler 比较受限和无界预加载。记录设备、输入量、前后 trace 与结论。不要只根据 CPU 核数或一次运行宣称“更快”。

## 每次记录的最小字段

```text
实验 / commit / 预测 / 操作 / 实际 Logs / 证据截图或 trace / 因果解释 / 可迁移场景
```
