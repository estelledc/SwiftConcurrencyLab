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
    init(scenario: LabScenario) { self.scenario = scenario; self.strategy = scenario.supportedStrategies.first(where: { $0 == .structured }) ?? scenario.supportedStrategies[0]; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = scenario.title; view.backgroundColor = .systemBackground
        let scrollView = UIScrollView(); let stack = UIStackView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false; stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical; stack.spacing = 16; stack.isLayoutMarginsRelativeArrangement = true; stack.directionalLayoutMargins = .init(top: 24, leading: 20, bottom: 24, trailing: 20)
        view.addSubview(scrollView); scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
        let prediction = makeLabel("先预测\n\(scenario.prediction)", style: .headline); stack.addArrangedSubview(prediction)
        let firstMove = makeLabel("第一次操作\n\(scenario.firstMove)", style: .body); stack.addArrangedSubview(firstMove)
        scenario.supportedStrategies.enumerated().forEach { index, item in strategyControl.insertSegment(withTitle: item.rawValue, at: index, animated: false) }; strategyControl.selectedSegmentIndex = scenario.supportedStrategies.firstIndex(of: strategy) ?? 0; strategyControl.accessibilityIdentifier = "strategyControl"; stack.addArrangedSubview(strategyControl)
        let strategyHint = makeLabel("当前策略\n\(strategy.summary)", style: .footnote); strategyHint.textColor = .secondaryLabel; strategyHint.accessibilityIdentifier = "strategyHint"; stack.addArrangedSubview(strategyHint)
        strategyControl.addAction(UIAction { [weak self, weak strategyHint] _ in
            guard let self else { return }
            self.strategy = self.scenario.supportedStrategies[self.strategyControl.selectedSegmentIndex]
            strategyHint?.text = "当前策略\n\(self.strategy.summary)"
        }, for: .valueChanged)
        runButton.configuration?.title = "Run Experiment"; runButton.addAction(UIAction { [weak self] _ in self?.run() }, for: .touchUpInside); runButton.accessibilityIdentifier = "runExperimentButton"; stack.addArrangedSubview(runButton)
        let cancel = UIButton(configuration: .bordered(), primaryAction: UIAction(title: "Cancel Task") { [weak self] _ in self?.runTask?.cancel(); self?.statusLabel.text = "Cancellation requested; wait for a cooperative check point." }); cancel.accessibilityIdentifier = "cancelExperimentButton"; stack.addArrangedSubview(cancel)
        statusLabel.numberOfLines = 0; statusLabel.accessibilityIdentifier = "labStatus"; statusLabel.text = "选择策略后运行；Logs 会记录真实时序。"; stack.addArrangedSubview(statusLabel)
        let proof = makeLabel("验收证据\n\(scenario.proofPrompt)", style: .body); proof.textColor = .secondaryLabel; stack.addArrangedSubview(proof)
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Logs", primaryAction: UIAction { _ in self.navigationController?.pushViewController(LogViewController.shared, animated: true) })
    }
    private func run() { runTask?.cancel(); runButton.isEnabled = false; statusLabel.text = "Running \(strategy.rawValue)…"; runTask = Task { [weak self, engine, scenario, strategy] in guard let self else { return }; let outcome = await engine.run(scenario: scenario, strategy: strategy); self.statusLabel.text = "\(outcome.summary)\n\(outcome.values.joined(separator: ", "))"; self.runButton.isEnabled = true; await LogViewController.shared.reload(from: engine.recorder) } }
    private func makeLabel(_ text: String, style: UIFont.TextStyle) -> UILabel { let label = UILabel(); label.numberOfLines = 0; label.font = .preferredFont(forTextStyle: style); label.text = text; return label }
    deinit { runTask?.cancel() }
}
