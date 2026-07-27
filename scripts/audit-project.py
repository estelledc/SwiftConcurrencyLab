#!/usr/bin/env python3
"""Audit the executable Xcode-learning contract, not just file existence."""

from pathlib import Path
import plistlib
import re
import sys

root = Path(__file__).resolve().parents[1]
project = root / "SwiftConcurrencyLab.xcodeproj/project.pbxproj"
scheme = (
    root
    / "SwiftConcurrencyLab.xcodeproj/xcshareddata/xcschemes/SwiftConcurrencyLab.xcscheme"
)
guide = root / "docs/lab-guide.md"
models_path = root / "Sources/SwiftConcurrencyCore/Models.swift"
support_path = root / "Sources/SwiftConcurrencyCore/Support.swift"
detail_path = root / "SwiftConcurrencyLab/LabDetailViewController.swift"
log_path = root / "SwiftConcurrencyLab/LogViewController.swift"
list_path = root / "SwiftConcurrencyLab/LabListViewController.swift"
info_path = root / "SwiftConcurrencyLab/Info.plist"
makefile_path = root / "Makefile"
ui_tests_path = root / "SwiftConcurrencyLabUITests/SwiftConcurrencyLabUITests.swift"
ui_evidence_path = root / "scripts/run-ui-evidence.sh"
ui_receipt_path = root / "scripts/write-ui-receipt.py"

required_files = [
    project,
    scheme,
    guide,
    models_path,
    support_path,
    detail_path,
    log_path,
    list_path,
    info_path,
    makefile_path,
    ui_tests_path,
    ui_evidence_path,
    ui_receipt_path,
]
missing = [str(path.relative_to(root)) for path in required_files if not path.is_file()]
if missing:
    raise SystemExit("missing project learning artifacts: " + ", ".join(missing))

project_text = project.read_text(encoding="utf-8")
scheme_text = scheme.read_text(encoding="utf-8")
guide_text = guide.read_text(encoding="utf-8")
models = models_path.read_text(encoding="utf-8")
support = support_path.read_text(encoding="utf-8")
detail = detail_path.read_text(encoding="utf-8")
log_view = log_path.read_text(encoding="utf-8")
lab_list = list_path.read_text(encoding="utf-8")
makefile = makefile_path.read_text(encoding="utf-8")
ui_tests = ui_tests_path.read_text(encoding="utf-8")
ui_evidence = ui_evidence_path.read_text(encoding="utf-8")
ui_receipt = ui_receipt_path.read_text(encoding="utf-8")

required_project_settings = [
    'DEBUG_INFORMATION_FORMAT = dwarf;',
    "ENABLE_TESTABILITY = YES;",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;",
    'SWIFT_OPTIMIZATION_LEVEL = "-Onone";',
    "SWIFT_STRICT_CONCURRENCY = complete;",
    "SWIFT_VERSION = 6.0;",
    'DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";',
    "SWIFT_COMPILATION_MODE = wholemodule;",
    'SWIFT_OPTIMIZATION_LEVEL = "-O";',
    "VALIDATE_PRODUCT = YES;",
]
required_scheme_settings = [
    'buildConfiguration = "Debug"',
    'selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"',
    'disableMainThreadChecker = "NO"',
    'queueDebuggingEnabled = "Yes"',
    'viewDebuggingEnabled = "Yes"',
]
missing_settings = [
    setting for setting in required_project_settings if setting not in project_text
]
missing_settings += [
    setting for setting in required_scheme_settings if setting not in scheme_text
]
if missing_settings:
    raise SystemExit(
        "missing debuggable project settings: " + ", ".join(missing_settings)
    )

with info_path.open("rb") as stream:
    info = plistlib.load(stream)
if info.get("UILaunchScreen") != {}:
    raise SystemExit(
        "Info.plist must declare an empty UILaunchScreen dictionary to avoid "
        "the legacy 320x480 compatibility viewport"
    )

required_make_targets = [
    "format-check:",
    "build-ci:",
    "build-release:",
    "test-ui:",
    "test-ui-evidence:",
    "audit:",
    "release-check:",
]
missing_make_targets = [target for target in required_make_targets if target not in makefile]
if missing_make_targets:
    raise SystemExit("Makefile gate missing: " + ", ".join(missing_make_targets))
if "simctl shutdown all" in makefile:
    raise SystemExit("UI tests must not shut down simulators owned by other labs")

required_ui_evidence_markers = [
    "simctl create",
    "simctl delete",
    "simctl list --json",
    'payload.get("devicetypes"',
    "mktemp -d",
    "-derivedDataPath",
    "-resultBundlePath",
    "-only-testing:SwiftConcurrencyLabUITests",
    "xcresulttool get test-results summary",
    "write-ui-receipt.py",
]
missing_ui_evidence_markers = [
    marker for marker in required_ui_evidence_markers if marker not in ui_evidence
]
if missing_ui_evidence_markers:
    raise SystemExit(
        "hermetic UI evidence runner missing: "
        + ", ".join(missing_ui_evidence_markers)
    )
for marker in ["schemaVersion", "totalTestCount", "failedTests", "resultBundle"]:
    if marker not in ui_receipt:
        raise SystemExit(f"portable UI receipt missing: {marker}")

required_ui_contracts = [
    "windowFrame.width",
    "windowFrame.height",
    "320-point compatibility mode",
    '"labDocsCue"',
    "The lab list should show titles only.",
    '"actorReentrancyModeControl"',
    '"boundedPrefetchModeControl"',
    '"resetExperimentButton"',
    "accepted=2",
    "rejected=message-old",
    "Swift Concurrency · cancelled",
    "testCancelThenResetDoesNotAllowTheOldTerminalToReappear",
    "testLogsResetRejectsAPendingOldUICommit",
]
missing_ui_contracts = [
    marker for marker in required_ui_contracts if marker not in ui_tests
]
if missing_ui_contracts:
    raise SystemExit(
        "UI regression coverage missing: " + ", ".join(missing_ui_contracts)
    )

for marker in ["guard eventGeneration == generation", "generation += 1"]:
    if marker not in support:
        raise SystemExit(f"recorder generation boundary missing: {marker}")
for marker in ["guard resetTask == nil", "rightBarButtonItem?.isEnabled = false"]:
    if marker not in log_view:
        raise SystemExit(f"Logs reset serialization missing: {marker}")

for verbose_marker in ["firstMove", "proofPrompt", "strategy.summary"]:
    if verbose_marker in detail:
        raise SystemExit(f"App detail regressed into a lesson reader: {verbose_marker}")

required_console_markers = [
    '"labSourceCue"',
    '"labActionCue"',
    '"labDocsCue"',
    "scenario.sourceFile",
    "scenario.sourceAnchor",
    "scenario.xcodeAction",
    "scenario.documentationPath",
    "compactStatus(for: outcome)",
    "await taskToCancel?.value",
    "await pendingCommitLogTask?.value",
    "await pendingCancelDrainTask?.value",
    "guard let taskToCancel = runTask",
    "uiCommitLogTask = Task",
    "guard resetTask == nil",
    "resetButton.isEnabled = false",
    "boundedPrefetchMode: selectedBoundedPrefetchMode",
    "await engine.recorder.reset()",
]
missing_console_markers = [
    marker for marker in required_console_markers if marker not in detail
]
if missing_console_markers:
    raise SystemExit(
        "compact console lost real code, Xcode or Docs cues: "
        + ", ".join(missing_console_markers)
    )

for verbose_result in ["outcome.values.joined", "content.secondaryText"]:
    if verbose_result in detail or verbose_result in lab_list:
        raise SystemExit(f"App regressed into verbose result/lesson text: {verbose_result}")

for field in ["sourceFile", "sourceAnchor", "xcodeAction", "documentationPath"]:
    if f"var {field}: String" not in models:
        raise SystemExit(f"scenario metadata missing {field}")


def switch_values(property_name: str) -> dict[str, str]:
    """Read explicit one-case/one-string Swift switch entries."""
    start_token = f"public var {property_name}: String"
    start = models.find(start_token)
    if start == -1:
        raise SystemExit(f"missing metadata property: {property_name}")
    next_property = models.find("\n  public var ", start + len(start_token))
    block = models[start : next_property if next_property != -1 else len(models)]
    pairs = re.findall(r'case \.(\w+):\s*\n\s*"([^"]+)"', block)
    if len(pairs) != 9:
        raise SystemExit(
            f"{property_name} must have 9 explicit case mappings; found {len(pairs)}"
        )
    return dict(pairs)


source_files = switch_values("sourceFile")
source_anchors = switch_values("sourceAnchor")
xcode_actions = switch_values("xcodeAction")
documentation_paths = switch_values("documentationPath")

labs = [
    {
        "id": "responsiveUI",
        "source": "Sources/SwiftConcurrencyCore/Runners.swift",
        "anchor": "case .responsiveUI:",
        "doc_anchor": "lab-responsive-ui",
        "evidence": ["uiCommit", "Thread.isMainThread", "thread backtrace"],
    },
    {
        "id": "parallelInbox",
        "source": "Sources/SwiftConcurrencyCore/Runners.swift",
        "anchor": "case .parallelInbox:",
        "doc_anchor": "lab-parallel-inbox",
        "evidence": ["profile, messages, recommendations", "3 values in Logs"],
    },
    {
        "id": "cooperativeCancellation",
        "source": "Sources/SwiftConcurrencyCore/Runners.swift",
        "anchor": "case .cooperativeCancellation:",
        "doc_anchor": "lab-cooperative-cancellation",
        "evidence": ["CancellationError", ".cancelled"],
    },
    {
        "id": "isolatedUnread",
        "source": "Sources/SwiftConcurrencyCore/Runners.swift",
        "anchor": "case .isolatedUnread:",
        "doc_anchor": "lab-isolated-unread",
        "evidence": ["unread=20", "UnreadCounter.increment"],
    },
    {
        "id": "actorReentrancy",
        "source": "Sources/SwiftConcurrencyCore/Runners.swift",
        "anchor": "case .actorReentrancy:",
        "doc_anchor": "lab-actor-reentrancy",
        "evidence": ["accepted=2", "remaining=-1", "accepted=1", "remaining=0"],
    },
    {
        "id": "latestWinsSearch",
        "source": "Sources/SwiftConcurrencyCore/Runners.swift",
        "anchor": "case .latestWinsSearch:",
        "doc_anchor": "lab-latest-wins-search",
        "evidence": ["swift-result", "ignoreCancellation"],
    },
    {
        "id": "cellReuse",
        "source": "SwiftConcurrencyLab/ConversationCell.swift",
        "anchor": "CellReuseIdentity.canCommit",
        "doc_anchor": "lab-cell-reuse",
        "evidence": ["committed=message-new", "rejected=message-old", "cancelled=true"],
    },
    {
        "id": "boundedPrefetch",
        "source": "Sources/SwiftConcurrencyCore/Runners.swift",
        "anchor": "case .boundedPrefetch:",
        "doc_anchor": "lab-bounded-prefetch",
        "evidence": ["limit=4", "12 values in Logs"],
    },
    {
        "id": "callbackBridge",
        "source": "Sources/SwiftConcurrencyCore/Support.swift",
        "anchor": "public static func loadAsync() async throws -> String",
        "doc_anchor": "lab-callback-bridge",
        "evidence": ["legacy-result", "continuation.resume"],
    },
]

required_card_sections = [
    "### 定位与机制",
    "### 真实代码定位",
    "### App 操作",
    "### Xcode / LLDB 操作",
    "### 预期真实证据",
    "### Cancel / Reset / 复验",
    "### 误区与边界",
    "### 思考题",
]

for index, lab in enumerate(labs):
    lab_id = lab["id"]
    expected_doc_path = f"docs/lab-guide.md#{lab['doc_anchor']}"
    if source_files.get(lab_id) != lab["source"]:
        raise SystemExit(f"{lab_id} sourceFile metadata drifted")
    if source_anchors.get(lab_id) != lab["anchor"]:
        raise SystemExit(f"{lab_id} sourceAnchor metadata drifted")
    if documentation_paths.get(lab_id) != expected_doc_path:
        raise SystemExit(f"{lab_id} documentationPath metadata drifted")
    action = xcode_actions.get(lab_id, "")
    if not action or len(action) > 80:
        raise SystemExit(f"{lab_id} must have one compact Xcode action")

    source_path = root / lab["source"]
    if not source_path.is_file():
        raise SystemExit(f"{lab_id} source file is missing: {lab['source']}")
    if lab["anchor"] not in source_path.read_text(encoding="utf-8"):
        raise SystemExit(f"{lab_id} source anchor is not present: {lab['anchor']}")

    marker = f"<!-- lab-card:{lab_id} -->"
    if guide_text.count(marker) != 1:
        raise SystemExit(f"{lab_id} must have exactly one detailed docs card")
    start = guide_text.index(marker)
    if index + 1 < len(labs):
        end = guide_text.index(f"<!-- lab-card:{labs[index + 1]['id']} -->")
    else:
        end = guide_text.index("## 学完后的最小验收")
    card = guide_text[start:end]
    required_card_tokens = [
        f'<a id="{lab["doc_anchor"]}">',
        lab["source"],
        lab["anchor"],
        "Run",
        "Cancel",
        "Reset",
        "LLDB",
        *required_card_sections,
        *lab["evidence"],
    ]
    missing_tokens = [token for token in required_card_tokens if token not in card]
    if missing_tokens:
        raise SystemExit(
            f"{lab_id} docs card is incomplete: " + ", ".join(missing_tokens)
        )

print(
    "SwiftConcurrencyLab project audit passed: 9 real source anchors, "
    "9 detailed operation cards, compact App cues, full-size launch metadata, "
    "Debug/Release settings and shared LLDB diagnostics are present."
)
