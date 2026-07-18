import UIKit

@MainActor
final class LabDetailViewController: UIViewController {
  private let scenario: LabScenario
  private let engine = LabSession.engine
  private let strategyControl = UISegmentedControl()
  private let actorModeControl = UISegmentedControl()
  private let statusLabel = UILabel()
  private let runButton = UIButton(configuration: .filled())
  private let cancelButton = UIButton(configuration: .bordered())
  private let resetButton = UIButton(configuration: .bordered())

  private var strategy: ConcurrencyStrategy
  private var actorReentrancyMode: ActorReentrancyMode = .unsafe
  private var runTask: Task<Void, Never>?
  private var activeRequestID: UUID?

  init(scenario: LabScenario) {
    self.scenario = scenario
    strategy =
      scenario.supportedStrategies.first(where: {
        $0 == .structured
      }) ?? scenario.supportedStrategies[0]
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = scenario.title
    navigationItem.largeTitleDisplayMode = .never
    view.backgroundColor = .systemBackground
    configureNavigation()
    configureContent()
  }

  deinit {
    runTask?.cancel()
  }

  private func configureNavigation() {
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

  private func configureContent() {
    let scrollView = UIScrollView()
    let stack = UIStackView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.spacing = 12
    stack.isLayoutMarginsRelativeArrangement = true
    stack.directionalLayoutMargins = .init(
      top: 20,
      leading: 20,
      bottom: 28,
      trailing: 20
    )

    view.addSubview(scrollView)
    scrollView.addSubview(stack)
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.topAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.topAnchor
      ),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      stack.leadingAnchor.constraint(
        equalTo: scrollView.contentLayoutGuide.leadingAnchor
      ),
      stack.trailingAnchor.constraint(
        equalTo: scrollView.contentLayoutGuide.trailingAnchor
      ),
      stack.topAnchor.constraint(
        equalTo: scrollView.contentLayoutGuide.topAnchor
      ),
      stack.bottomAnchor.constraint(
        equalTo: scrollView.contentLayoutGuide.bottomAnchor
      ),
      stack.widthAnchor.constraint(
        equalTo: scrollView.frameLayoutGuide.widthAnchor
      ),
    ])

    let goal = makeLabel(scenario.prediction, style: .headline)
    goal.accessibilityIdentifier = "labGoal"
    stack.addArrangedSubview(goal)
    stack.addArrangedSubview(
      makeCue(
        title: "Code",
        value: "⌘⇧O \(sourceFileName)\n\(scenario.sourceAnchor)",
        identifier: "labSourceCue"
      )
    )
    stack.addArrangedSubview(
      makeCue(
        title: "Xcode",
        value: scenario.xcodeAction,
        identifier: "labActionCue"
      )
    )
    stack.addArrangedSubview(
      makeCue(
        title: "Docs",
        value: scenario.documentationPath,
        identifier: "labDocsCue"
      )
    )
    stack.addArrangedSubview(makeStrategyControl())
    if scenario == .actorReentrancy {
      stack.addArrangedSubview(makeActorModeControl())
    }

    runButton.configuration?.title = "Run"
    runButton.accessibilityIdentifier = "runExperimentButton"
    runButton.addAction(
      UIAction { [weak self] _ in self?.run() },
      for: .touchUpInside
    )

    cancelButton.configuration?.title = "Cancel"
    cancelButton.accessibilityIdentifier = "cancelExperimentButton"
    cancelButton.addAction(
      UIAction { [weak self] _ in self?.cancelActiveRun() },
      for: .touchUpInside
    )

    resetButton.configuration?.title = "Reset"
    resetButton.accessibilityIdentifier = "resetExperimentButton"
    resetButton.addAction(
      UIAction { [weak self] _ in self?.resetExperiment() },
      for: .touchUpInside
    )

    let actions = UIStackView(arrangedSubviews: [runButton, cancelButton, resetButton])
    actions.axis = .horizontal
    actions.spacing = 8
    actions.distribution = .fillEqually
    stack.addArrangedSubview(actions)

    statusLabel.numberOfLines = 0
    statusLabel.font = .preferredFont(forTextStyle: .body)
    statusLabel.accessibilityIdentifier = "labStatus"
    statusLabel.text = "Ready"
    stack.addArrangedSubview(statusLabel)
  }

  private func makeStrategyControl() -> UIView {
    guard scenario.supportedStrategies.count > 1 else {
      return makeCue(
        title: "Strategy",
        value: strategy.rawValue,
        identifier: "strategyLabel"
      )
    }

    for (index, item) in scenario.supportedStrategies.enumerated() {
      strategyControl.insertSegment(
        withTitle: item.rawValue,
        at: index,
        animated: false
      )
    }
    strategyControl.selectedSegmentIndex =
      scenario.supportedStrategies.firstIndex(of: strategy) ?? 0
    strategyControl.accessibilityIdentifier = "strategyControl"
    strategyControl.addAction(
      UIAction { [weak self] _ in
        guard let self else { return }
        strategy =
          scenario.supportedStrategies[
            strategyControl.selectedSegmentIndex
          ]
      },
      for: .valueChanged
    )
    return strategyControl
  }

  private func makeActorModeControl() -> UIView {
    for (index, mode) in ActorReentrancyMode.allCases.enumerated() {
      actorModeControl.insertSegment(withTitle: mode.rawValue, at: index, animated: false)
    }
    actorModeControl.selectedSegmentIndex =
      ActorReentrancyMode.allCases.firstIndex(of: actorReentrancyMode) ?? 0
    actorModeControl.accessibilityIdentifier = "actorReentrancyModeControl"
    actorModeControl.addAction(
      UIAction { [weak self] _ in
        guard let self else { return }
        actorReentrancyMode =
          ActorReentrancyMode.allCases[actorModeControl.selectedSegmentIndex]
      },
      for: .valueChanged
    )
    return actorModeControl
  }

  private func run() {
    runTask?.cancel()

    let requestID = UUID()
    let selectedStrategy = strategy
    let selectedActorMode = actorReentrancyMode
    activeRequestID = requestID
    runButton.isEnabled = false
    statusLabel.text = "Running \(selectedStrategy.rawValue)…"

    runTask = Task { [weak self, engine, scenario] in
      let outcome = await engine.run(
        scenario: scenario,
        strategy: selectedStrategy,
        actorReentrancyMode: selectedActorMode
      )
      guard !Task.isCancelled else { return }
      await self?.commit(
        outcome,
        requestID: requestID,
        strategy: selectedStrategy
      )
    }
  }

  private func commit(
    _ outcome: LabOutcome,
    requestID: UUID,
    strategy: ConcurrencyStrategy
  ) async {
    guard activeRequestID == requestID else { return }
    activeRequestID = nil
    runTask = nil

    await engine.recorder.record(
      runID: outcome.runID,
      strategy: strategy,
      scenario: scenario,
      phase: .uiCommit,
      "MainActor committed the latest run"
    )
    statusLabel.text = compactStatus(for: outcome)
    runButton.isEnabled = true
    await LogViewController.shared.reload()
  }

  private func cancelActiveRun() {
    runTask?.cancel()
    runTask = nil
    activeRequestID = nil
    runButton.isEnabled = true
    statusLabel.text = "Cancellation requested · inspect Logs"
  }

  private func resetExperiment() {
    let taskToCancel = runTask
    taskToCancel?.cancel()
    runTask = nil
    activeRequestID = nil
    runButton.isEnabled = false
    statusLabel.text = "Resetting…"
    Task { [weak self, engine] in
      await taskToCancel?.value
      await engine.recorder.reset()
      guard let self, activeRequestID == nil else { return }
      statusLabel.text = "Ready"
      runButton.isEnabled = true
      await LogViewController.shared.reload()
    }
  }

  private func compactStatus(for outcome: LabOutcome) -> String {
    if scenario == .actorReentrancy || scenario == .cellReuse {
      let evidence = outcome.values.prefix(2).joined(separator: " · ")
      return "\(outcome.summary) · \(evidence)"
    }
    return switch outcome.values.count {
    case 0:
      outcome.summary
    case 1:
      "\(outcome.summary) · \(outcome.values[0])"
    default:
      "\(outcome.summary) · \(outcome.values.count) values in Logs"
    }
  }

  private var sourceFileName: String {
    URL(fileURLWithPath: scenario.sourceFile).lastPathComponent
  }

  private func makeCue(
    title: String,
    value: String,
    identifier: String
  ) -> UILabel {
    let label = makeLabel(
      "\(title) · \(value)",
      style: .body,
      color: .secondaryLabel
    )
    label.accessibilityIdentifier = identifier
    return label
  }

  private func makeLabel(
    _ text: String,
    style: UIFont.TextStyle,
    color: UIColor = .label
  ) -> UILabel {
    let label = UILabel()
    label.numberOfLines = 0
    label.font = .preferredFont(forTextStyle: style)
    label.textColor = color
    label.text = text
    return label
  }
}
