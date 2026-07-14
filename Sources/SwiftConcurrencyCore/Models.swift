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
        self.id = id; self.title = title; self.preview = preview; self.unreadCount = unreadCount; self.avatarToken = avatarToken
    }
}

public enum ConcurrencyStrategy: String, CaseIterable, Codable, Sendable, Identifiable {
    case gcd = "GCD"
    case operation = "Operation"
    case structured = "Swift Concurrency"
    public var id: String { rawValue }
    public var summary: String {
        switch self {
        case .gcd: "DispatchQueue、DispatchGroup、barrier 与 WorkItem"
        case .operation: "依赖图、并发上限、取消与状态机"
        case .structured: "async/await、TaskGroup、actor 与 MainActor"
        }
    }
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
        case .actorReentrancy, .callbackBridge: [.structured]
        case .isolatedUnread: [.gcd, .operation, .structured]
        default: ConcurrencyStrategy.allCases
        }
    }
}

public enum LabPhase: String, Codable, Sendable { case started, scheduled, suspended, completed, cancelled, uiCommit, warning }
public struct LabEvent: Hashable, Codable, Sendable, Identifiable {
    public let id: Int
    public let runID: UUID
    public let strategy: ConcurrencyStrategy
    public let scenario: LabScenario
    public let phase: LabPhase
    public let message: String
    public init(id: Int, runID: UUID, strategy: ConcurrencyStrategy, scenario: LabScenario, phase: LabPhase, message: String) {
        self.id = id; self.runID = runID; self.strategy = strategy; self.scenario = scenario; self.phase = phase; self.message = message
    }
}

public struct LabOutcome: Hashable, Sendable {
    public let runID: UUID
    public let summary: String
    public let values: [String]
    public init(runID: UUID, summary: String, values: [String] = []) { self.runID = runID; self.summary = summary; self.values = values }
}

public protocol LabRunner: Sendable {
    var strategy: ConcurrencyStrategy { get }
    func run(_ scenario: LabScenario, recorder: LabEventRecorder) async -> LabOutcome
}
