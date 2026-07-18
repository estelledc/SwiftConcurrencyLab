# 并发证据手册

每个实验先写下预测，再执行并保存结论。App 的 Logs 说明事件顺序；Xcode 工具补充“为什么”与“是否真的安全”的证据。

## 先建立可重复基线

1. 仓库移动或 Xcode 升级后先跑 `make clean`，避免 ModuleCache、PCH 与 DerivedData 继续引用旧绝对路径。
2. 串行执行 `make test`、`make build`、`make test-ui`。`make build` 与 `make test-ui` 共用 `.DerivedData`，并发执行会争用 `build.db`，不能作为有效失败证据。
3. 在「并行加载」中每次只选一种策略，运行后核对 `started -> scheduled -> completed -> uiCommit`；点 `Reset` 后再测下一种。
4. 三种策略的任务可以按不同顺序完成，但 UI 提交值必须稳定为 `profile, messages, recommendations`。

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
