import UIKit

@MainActor
final class GuideViewController: UITableViewController {
    override func viewDidLoad() { super.viewDidLoad(); title = "Guide"; tableView.register(UITableViewCell.self, forCellReuseIdentifier: "guide"); tableView.accessibilityIdentifier = "guideTable" }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { LabScenario.allCases.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { let item = LabScenario.allCases[indexPath.row]; let cell = tableView.dequeueReusableCell(withIdentifier: "guide", for: indexPath); var content = cell.defaultContentConfiguration(); content.text = item.title; content.secondaryText = "预测：\(item.prediction)\n第一步：\(item.firstMove)\n证据：\(item.proofPrompt)"; content.secondaryTextProperties.numberOfLines = 0; cell.contentConfiguration = content; return cell }
}
