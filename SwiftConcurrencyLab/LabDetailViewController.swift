import UIKit

@MainActor
final class LabDetailViewController: UIViewController {
    private let scenario: LabScenario
    private let engine = LabEngine()
    private var runTask: Task<Void, Never>?
    private var strategy: ConcurrencyStrategy
    private let strategyControl = UISegmentedControl()
    private let statusLabel = UILabel()
    private let runButton = UIButton(configuration: .filled())
    init(scenario: LabScenario) { self.scenario = scenario; self.strategy = scenario.supportedStrategies[0]; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = scenario.title; view.backgroundColor = .systemBackground
        let stack = UIStackView(); stack.translatesAutoresizingMaskIntoConstraints = false; stack.axis = .vertical; stack.spacing = 16; stack.isLayoutMarginsRelativeArrangement = true; stack.directionalLayoutMargins = .init(top: 24, leading: 20, bottom: 24, trailing: 20); view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor), stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)])
        let prediction = UILabel(); prediction.numberOfLines = 0; prediction.font = .preferredFont(forTextStyle: .headline); prediction.text = "先预测：\n\(scenario.prediction)"; stack.addArrangedSubview(prediction)
        scenario.supportedStrategies.enumerated().forEach { index, item in strategyControl.insertSegment(withTitle: item.rawValue, at: index, animated: false) }; strategyControl.selectedSegmentIndex = 0; strategyControl.addAction(UIAction { [weak self] _ in self?.strategy = self?.scenario.supportedStrategies[self?.strategyControl.selectedSegmentIndex ?? 0] ?? .structured }, for: .valueChanged); strategyControl.accessibilityIdentifier = "strategyControl"; stack.addArrangedSubview(strategyControl)
        runButton.configuration?.title = "Run Experiment"; runButton.addAction(UIAction { [weak self] _ in self?.run() }, for: .touchUpInside); runButton.accessibilityIdentifier = "runExperimentButton"; stack.addArrangedSubview(runButton)
        let cancel = UIButton(configuration: .bordered(), primaryAction: UIAction(title: "Cancel Task") { [weak self] _ in self?.runTask?.cancel(); self?.statusLabel.text = "Cancellation requested; wait for a cooperative check point." }); cancel.accessibilityIdentifier = "cancelExperimentButton"; stack.addArrangedSubview(cancel)
        statusLabel.numberOfLines = 0; statusLabel.accessibilityIdentifier = "labStatus"; statusLabel.text = "选择策略后运行；Logs 会记录真实时序。"; stack.addArrangedSubview(statusLabel)
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Logs", primaryAction: UIAction { _ in self.navigationController?.pushViewController(LogViewController.shared, animated: true) })
    }
    private func run() { runTask?.cancel(); runButton.isEnabled = false; statusLabel.text = "Running \(strategy.rawValue)…"; runTask = Task { [weak self, engine, scenario, strategy] in guard let self else { return }; let outcome = await engine.run(scenario: scenario, strategy: strategy); self.statusLabel.text = "\(outcome.summary)\n\(outcome.values.joined(separator: ", "))"; self.runButton.isEnabled = true; await LogViewController.shared.reload(from: engine.recorder) } }
    deinit { runTask?.cancel() }
}
