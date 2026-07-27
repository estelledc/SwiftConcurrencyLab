import UIKit

@MainActor
enum LabSession {
  static let engine = LabEngine()
}

@MainActor
final class LogViewController: UITableViewController {
  static let shared = LogViewController()
  private var events: [LabEvent] = []
  private var resetTask: Task<Void, Never>?
  private let emptyLabel: UILabel = {
    let label = UILabel()
    label.text = "No events yet. Run an experiment first."
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.numberOfLines = 0
    label.accessibilityIdentifier = "emptyLogLabel"
    return label
  }()
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Logs"
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "event")
    tableView.accessibilityIdentifier = "labLogTable"
    let reset = UIBarButtonItem(
      title: "Reset", primaryAction: UIAction { [weak self] _ in self?.reset() })
    reset.accessibilityIdentifier = "resetLogsButton"
    navigationItem.rightBarButtonItem = reset
    updateEmptyState()
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    Task { [weak self] in await self?.reload() }
  }
  func reload() async {
    events = await LabSession.engine.recorder.events()
    tableView?.reloadData()
    updateEmptyState()
  }
  private func reset() {
    guard resetTask == nil else { return }
    navigationItem.rightBarButtonItem?.isEnabled = false
    resetTask = Task { [weak self] in
      await LabSession.engine.recorder.reset()
      await self?.reload()
      self?.resetTask = nil
      self?.navigationItem.rightBarButtonItem?.isEnabled = true
    }
  }
  private func updateEmptyState() { tableView.backgroundView = events.isEmpty ? emptyLabel : nil }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    events.count
  }
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
    -> UITableViewCell
  {
    let event = events[indexPath.row]
    let cell = tableView.dequeueReusableCell(withIdentifier: "event", for: indexPath)
    var content = cell.defaultContentConfiguration()
    content.text = "#\(event.id) \(event.strategy.rawValue) · \(event.phase.rawValue)"
    content.secondaryText = event.message
    content.secondaryTextProperties.numberOfLines = 2
    cell.contentConfiguration = content
    return cell
  }
}
