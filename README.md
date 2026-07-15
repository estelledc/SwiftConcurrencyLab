# SwiftConcurrencyLab

一个公开、纯 UIKit 的消息收件箱并发学习实验室。它用同一组虚构 Inbox 场景，对照 GCD、OperationQueue 和 Swift Concurrency；每一步都要求先预测、运行、看日志、解释因果，再迁移到真实 UIKit 问题。

## 运行

要求：Xcode 26.2、Swift 6 language mode、iOS 17+ Simulator。

```bash
make run
```

`make run` 会构建 App，并尝试启动默认的 `iPhone 17 Pro` 模拟器；如果本机没有这个模拟器：

```bash
make run SIMULATOR_NAME="你的 Simulator 名称"
```

日常验证再跑：

```bash
make check
make test-ui
```

## 5 分钟第一次实验

1. 打开 App，切到 `Learn`。
2. 进入「2. 顺序 await 与并行加载」。
3. 先选 `Swift Concurrency`，读「先预测 / 第一次操作 / 验收证据」三段，再点 `Run Experiment`。
4. 打开 `Logs`，找到 `scheduled -> completed -> uiCommit` 的顺序。
5. 再切到 `GCD` 或 `Operation` 跑一次，只比较同一个问题，不同时学习所有概念。

## 学习路线

`Learn` 包含 9 个实验：主线程响应性、并行加载、协作式取消、状态隔离、actor reentrancy、latest-wins、cell 复用、受限并发和 callback 桥接。每个实验会显示预测题、支持的策略和结构化 Logs。

## 架构

```text
UIKit Inbox / Lab / Guide / Logs
        ↓ @MainActor
SwiftConcurrencyCore
  ├── GCDLabRunner
  ├── OperationLabRunner
  └── StructuredConcurrencyLabRunner
        ↓
actor 模拟服务、状态与事件记录器
```

Core 同时是 Swift Package；`make test` 运行其确定性测试。App 直接编译同一份 Core 源码，避免展示层和测试对象漂移。

## 证据与边界

- 正式路径开启 Swift 6 严格并发检查；故意 data race 只允许在单独的 TSan 诊断流程中复现，不能作为默认测试或发布代码。
- 每个非结构化 UIKit `Task` 都由 ViewController 持有，并在重新运行或释放时取消。
- Main Thread Checker、Thread Sanitizer、Swift Concurrency Instruments 和 Time Profiler 的观察步骤在实验说明中记录；性能结论需要 trace 对比。
- 仅使用本地虚构数据与公开 API；不接入真实服务、不包含凭证或内部资料。

## 固定命令

```bash
make test              # Swift Package tests
make build             # iOS Simulator build
make test-ui           # XCUITest
make verify-showcase   # public page contract
make public-scan       # privacy boundary
make check             # daily gate
make release-check     # release gate
```
