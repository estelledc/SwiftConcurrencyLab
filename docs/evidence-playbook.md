# 并发证据手册

每个实验先写下预测，再执行并保存结论。App 的 Logs 说明事件顺序；Xcode 工具补充“为什么”与“是否真的安全”的证据。

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
