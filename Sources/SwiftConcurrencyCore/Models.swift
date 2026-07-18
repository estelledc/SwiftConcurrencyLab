import Foundation

public struct MessageID: Hashable, Codable, Sendable, Identifiable {
  public let rawValue: String
  public var id: String { rawValue }
  public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct ConversationSnapshot: Hashable, Codable, Sendable, Identifiable {
  public let id: String
  public let title: String
  public let preview: String
  public let unreadCount: Int
  public let avatarToken: String
  public init(id: String, title: String, preview: String, unreadCount: Int, avatarToken: String) {
    self.id = id
    self.title = title
    self.preview = preview
    self.unreadCount = unreadCount
    self.avatarToken = avatarToken
  }
}

public enum ConcurrencyStrategy: String, CaseIterable, Codable, Sendable, Identifiable {
  case gcd = "GCD"
  case operation = "Operation"
  case structured = "Swift Concurrency"
  public var id: String { rawValue }
}

public enum ActorReentrancyMode: String, CaseIterable, Sendable, Identifiable {
  case unsafe = "Unsafe"
  case reserved = "Reserved"

  public var id: String { rawValue }
}

public enum LabScenario: String, CaseIterable, Codable, Sendable, Identifiable {
  case responsiveUI, parallelInbox, cooperativeCancellation, isolatedUnread
  case actorReentrancy, latestWinsSearch, cellReuse, boundedPrefetch, callbackBridge
  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .responsiveUI: "1. 主线程响应性"
    case .parallelInbox: "2. 顺序 await 与并行加载"
    case .cooperativeCancellation: "3. 取消是协作式的"
    case .isolatedUnread: "4. 未读数的隔离"
    case .actorReentrancy: "5. Actor reentrancy"
    case .latestWinsSearch: "6. 搜索 latest-wins"
    case .cellReuse: "7. Cell 复用与身份校验"
    case .boundedPrefetch: "8. 受限并发预加载"
    case .callbackBridge: "9. 旧 callback 桥接"
    }
  }
  public var prediction: String {
    switch self {
    case .responsiveUI: "哪种写法会让主线程无法继续处理交互？"
    case .parallelInbox: "三份独立数据是按开始顺序还是完成顺序回来？"
    case .cooperativeCancellation: "调用 cancel 后，任务会在哪个检查点停止？"
    case .isolatedUnread: "多个写入同时发生时，最终未读数由谁保护？"
    case .actorReentrancy: "actor 在 await 后回来时，之前检查的条件还可靠吗？"
    case .latestWinsSearch: "旧查询晚回来时，为什么不能覆盖新查询？"
    case .cellReuse: "为什么 indexPath 不是异步头像的稳定身份？"
    case .boundedPrefetch: "为什么并行数设为 4，而不是一次启动全部任务？"
    case .callbackBridge: "callback 如果 resume 0 次或 2 次，await 会怎样？"
    }
  }
  public var supportedStrategies: [ConcurrencyStrategy] {
    switch self {
    case .parallelInbox:
      ConcurrencyStrategy.allCases
    default:
      [.structured]
    }
  }

  public var sourceFile: String {
    switch self {
    case .responsiveUI:
      "Sources/SwiftConcurrencyCore/Runners.swift"
    case .parallelInbox:
      "Sources/SwiftConcurrencyCore/Runners.swift"
    case .cooperativeCancellation:
      "Sources/SwiftConcurrencyCore/Runners.swift"
    case .isolatedUnread:
      "Sources/SwiftConcurrencyCore/Runners.swift"
    case .actorReentrancy:
      "Sources/SwiftConcurrencyCore/Runners.swift"
    case .latestWinsSearch:
      "Sources/SwiftConcurrencyCore/Runners.swift"
    case .cellReuse:
      "SwiftConcurrencyLab/ConversationCell.swift"
    case .boundedPrefetch:
      "Sources/SwiftConcurrencyCore/Runners.swift"
    case .callbackBridge:
      "Sources/SwiftConcurrencyCore/Support.swift"
    }
  }

  public var sourceAnchor: String {
    switch self {
    case .responsiveUI:
      "case .responsiveUI:"
    case .parallelInbox:
      "case .parallelInbox:"
    case .cooperativeCancellation:
      "case .cooperativeCancellation:"
    case .isolatedUnread:
      "case .isolatedUnread:"
    case .actorReentrancy:
      "case .actorReentrancy:"
    case .latestWinsSearch:
      "case .latestWinsSearch:"
    case .cellReuse:
      "CellReuseIdentity.canCommit"
    case .boundedPrefetch:
      "case .boundedPrefetch:"
    case .callbackBridge:
      "public static func loadAsync() async throws -> String"
    }
  }

  public var xcodeAction: String {
    switch self {
    case .responsiveUI:
      "Run 后立刻操作导航；Pause 并查看主线程是否可响应。"
    case .parallelInbox:
      "在三个 load 处停住；比较 Task、Queue 与完成顺序。"
    case .cooperativeCancellation:
      "在 Task.checkCancellation() 停住；Run 后立刻 Cancel。"
    case .isolatedUnread:
      "在 counter.increment() 停住；查看并发 Task 怎样进入 actor。"
    case .actorReentrancy:
      "在 await gate.wait() 前后停住；比较 actor state。"
    case .latestWinsSearch:
      "在 store.submit 停住；观察旧结果为何不能覆盖新查询。"
    case .cellReuse:
      "在 identity guard 停住；快速滚动 Inbox 触发复用。"
    case .boundedPrefetch:
      "在 group.addTask 停住；用 Logs 核对同时运行上限。"
    case .callbackBridge:
      "在 continuation.resume 停住；确认 callback 只恢复一次。"
    }
  }

  public var documentationPath: String {
    switch self {
    case .responsiveUI:
      "docs/lab-guide.md#lab-responsive-ui"
    case .parallelInbox:
      "docs/lab-guide.md#lab-parallel-inbox"
    case .cooperativeCancellation:
      "docs/lab-guide.md#lab-cooperative-cancellation"
    case .isolatedUnread:
      "docs/lab-guide.md#lab-isolated-unread"
    case .actorReentrancy:
      "docs/lab-guide.md#lab-actor-reentrancy"
    case .latestWinsSearch:
      "docs/lab-guide.md#lab-latest-wins-search"
    case .cellReuse:
      "docs/lab-guide.md#lab-cell-reuse"
    case .boundedPrefetch:
      "docs/lab-guide.md#lab-bounded-prefetch"
    case .callbackBridge:
      "docs/lab-guide.md#lab-callback-bridge"
    }
  }
}

public enum LabPhase: String, Codable, Sendable {
  case started, scheduled, suspended, completed, cancelled, uiCommit, warning
}
public struct LabEvent: Hashable, Codable, Sendable, Identifiable {
  public let id: Int
  public let runID: UUID
  public let strategy: ConcurrencyStrategy
  public let scenario: LabScenario
  public let phase: LabPhase
  public let message: String
  public init(
    id: Int, runID: UUID, strategy: ConcurrencyStrategy, scenario: LabScenario, phase: LabPhase,
    message: String
  ) {
    self.id = id
    self.runID = runID
    self.strategy = strategy
    self.scenario = scenario
    self.phase = phase
    self.message = message
  }
}

public struct LabOutcome: Hashable, Sendable {
  public let runID: UUID
  public let summary: String
  public let values: [String]
  public init(runID: UUID, summary: String, values: [String] = []) {
    self.runID = runID
    self.summary = summary
    self.values = values
  }
}

public protocol LabRunner: Sendable {
  var strategy: ConcurrencyStrategy { get }
  func run(_ scenario: LabScenario, recorder: LabEventRecorder) async -> LabOutcome
}
