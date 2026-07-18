import UIKit

@MainActor
final class LabListViewController: UITableViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Concurrency Lab"
    tableView.register(
      UITableViewCell.self,
      forCellReuseIdentifier: "lab"
    )
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "Logs",
      primaryAction: UIAction { [weak self] _ in
        self?.navigationController?.pushViewController(
          LogViewController.shared,
          animated: true
        )
      }
    )
  }

  override func tableView(
    _ tableView: UITableView,
    numberOfRowsInSection section: Int
  ) -> Int {
    LabScenario.allCases.count
  }

  override func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    let scenario = LabScenario.allCases[indexPath.row]
    let cell = tableView.dequeueReusableCell(
      withIdentifier: "lab",
      for: indexPath
    )
    var content = cell.defaultContentConfiguration()
    content.text = scenario.title
    cell.contentConfiguration = content
    cell.accessoryType = .disclosureIndicator
    cell.accessibilityIdentifier = "lab_\(scenario.rawValue)"
    return cell
  }

  override func tableView(
    _ tableView: UITableView,
    didSelectRowAt indexPath: IndexPath
  ) {
    let scenario = LabScenario.allCases[indexPath.row]
    navigationController?.pushViewController(
      LabDetailViewController(scenario: scenario),
      animated: true
    )
  }
}
