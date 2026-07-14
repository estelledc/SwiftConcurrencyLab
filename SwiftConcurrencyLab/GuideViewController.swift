import UIKit

@MainActor
final class GuideViewController: UITableViewController {
    override func viewDidLoad() { super.viewDidLoad(); title = "Guide"; tableView.register(UITableViewCell.self, forCellReuseIdentifier: "guide"); tableView.accessibilityIdentifier = "guideTable" }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { LabScenario.allCases.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { let item = LabScenario.allCases[indexPath.row]; let cell = tableView.dequeueReusableCell(withIdentifier: "guide", for: indexPath); var content = cell.defaultContentConfiguration(); content.text = item.title; content.secondaryText = "预测 → 运行 → 查看 Logs → 用自己的话解释：\(item.prediction)"; content.secondaryTextProperties.numberOfLines = 0; cell.contentConfiguration = content; return cell }
}
