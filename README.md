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
3. 读一行实验目标、真实 `Code` cue、一个 `Xcode` 动作和短 `Docs` 路径，先选 `Swift Concurrency`，再点 `Run`。
4. 打开 `Logs`，找到 `scheduled -> completed -> uiCommit` 的顺序。
5. 再切到 `GCD` 或 `Operation` 跑一次，只比较同一个问题，不同时学习所有概念。
6. 点 `Reset` 清空证据，再独立重跑一种策略；三种策略都应提交同样的 `profile, messages, recommendations` 顺序。

## 学习路线

`Learn` 包含 9 个实验：主线程响应性、并行加载、协作式取消、状态隔离、actor reentrancy、latest-wins、cell 复用、受限并发和 callback 桥接。列表只有标题；详情只保留一行目标、真实源码锚点、一个 Xcode 动作、短 Docs 路径、实验控制和紧凑结果。多值结果进入 Logs；[实验学习指南](docs/lab-guide.md) 为每个实验提供独立操作卡，包含机制、真实 source/symbol、App 与 LLDB 步骤、预期证据、取消/重置/复验、边界和思考题。当前只有「并行加载」同时实现 GCD、OperationQueue 与 Swift Concurrency，其余实验只展示已完成的结构化并发路径，不用占位结果冒充实现。

## 架构

```text
UIKit Inbox / Lab Console / Logs
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
- 所有实验共用一个事件记录器；重新运行会让旧 Task 失去 UI commit 资格，只有当前 request 能在 `@MainActor` 更新界面。
- `Info.plist` 使用现代 `UILaunchScreen` 声明，防止新设备退回 320×480 compatibility viewport；UI 测试会检查窗口宽高，避免黑色上下 letterbox 回归。
- Main Thread Checker、Thread Sanitizer、Swift Concurrency Instruments 和 Time Profiler 的观察步骤在实验说明中记录；性能结论需要 trace 对比。
- 仅使用本地虚构数据与公开 API；不接入真实服务、不包含凭证或内部资料。

如果仓库被移动过，旧 `.build` / `.DerivedData` 可能仍记录原绝对路径。先运行 `make clean`，再重跑验证；不要把派生缓存当作源码故障。

共享 `SwiftConcurrencyLab` Scheme 显式使用 LLDB、Main Thread Checker 和 Queue
Debugging；Debug 构建固定为 `-Onone`、DWARF 与 `ENABLE_TESTABILITY=YES`。
`make check` 会用 generic Simulator 构建并审计这些设置，UI 测试则默认选择与当前
Xcode Simulator SDK 同版本的 runtime。

## 固定命令

```bash
make test              # Swift Package tests
make format-check      # Swift formatting gate
make build             # iOS Simulator build
make test-ui           # XCUITest
make build-release     # Release + dSYM settings build
make verify-showcase   # public page contract
make public-scan       # privacy boundary
make check             # daily gate
make release-check     # release gate
```
