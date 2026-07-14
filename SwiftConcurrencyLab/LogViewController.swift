import UIKit

@MainActor
final class LogViewController: UITableViewController {
    static let shared = LogViewController()
    private var events: [LabEvent] = []
    override func viewDidLoad() { super.viewDidLoad(); title = "Logs"; tableView.register(UITableViewCell.self, forCellReuseIdentifier: "event"); tableView.accessibilityIdentifier = "labLogTable" }
    func reload(from recorder: LabEventRecorder) async { events = await recorder.events(); tableView?.reloadData() }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { events.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { let event = events[indexPath.row]; let cell = tableView.dequeueReusableCell(withIdentifier: "event", for: indexPath); var content = cell.defaultContentConfiguration(); content.text = "#\(event.id) \(event.strategy.rawValue) · \(event.phase.rawValue)"; content.secondaryText = event.message; content.secondaryTextProperties.numberOfLines = 2; cell.contentConfiguration = content; return cell }
}
