# SwiftConcurrencyLab

一个公开、纯 UIKit 的消息收件箱并发学习实验室。它用同一组虚构 Inbox 场景，对照 GCD、OperationQueue 和 Swift Concurrency；每一步都要求先预测、运行、看日志、解释因果，再迁移到真实 UIKit 问题。

## 运行

要求：Xcode 26.2、Swift 6 language mode、iOS 17+ Simulator。

```bash
make check
make run
make test-ui
```

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
