import Flutter
import UIKit
import XCTest
@testable import Runner

/// Records what the native side sends and delivers calls as Flutter would.
private final class FakeMessenger: NSObject, FlutterBinaryMessenger {
  var handlers: [String: FlutterBinaryMessageHandler] = [:]
  var sent: [FlutterMethodCall] = []

  func send(onChannel channel: String, message: Data?) {
    send(onChannel: channel, message: message, binaryReply: nil)
  }

  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    sent.append(FlutterStandardMethodCodec.sharedInstance().decodeMethodCall(message!))
  }

  func setMessageHandlerOnChannel(
    _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection {
    handlers[channel] = handler
    return 0
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}

  func call(_ channel: String, _ method: String, _ arguments: Any?) {
    let message = FlutterStandardMethodCodec.sharedInstance().encode(
      FlutterMethodCall(methodName: method, arguments: arguments))
    handlers[channel]?(message) { _ in }
  }
}

class RunnerTests: XCTestCase {
  private let channelName = "app.settlo/tab_bar/7"
  private let messenger = FakeMessenger()

  private func makeBar(selected: Int = 0, dark: Bool = false) -> NativeTabBar {
    NativeTabBar(
      [
        "items": [
          ["label": "Home", "symbol": "house"], ["label": "Spaces", "symbol": "person.2"],
          ["label": "Loans", "symbol": "banknote"],
          ["label": "Activity", "symbol": "waveform.path.ecg"],
        ],
        "selected": selected, "dark": dark,
      ],
      channel: FlutterMethodChannel(name: channelName, binaryMessenger: messenger))
  }

  func testBuildsSystemItemsFromFlutter() {
    let tabs = makeBar(selected: 1)
    XCTAssertEqual(tabs.bar.items?.map(\.title), ["Home", "Spaces", "Loans", "Activity"])
    XCTAssertTrue(tabs.bar.items!.allSatisfy { $0.image != nil && $0.selectedImage != nil })
    XCTAssertEqual(tabs.bar.selectedItem?.title, "Spaces")
    XCTAssertEqual(tabs.view().overrideUserInterfaceStyle, .light)
  }

  func testTapIsSentToFlutter() {
    let tabs = makeBar()
    tabs.bar.delegate?.tabBar?(tabs.bar, didSelect: tabs.bar.items![3])
    XCTAssertEqual(messenger.sent.last?.method, "tap")
    XCTAssertEqual(messenger.sent.last?.arguments as? Int, 3)
  }

  /// A bar laid out as on an iPhone 17 Pro, with the home indicator band
  /// under its buttons.
  private func laidOut(_ tabs: NativeTabBar) -> NativeTabBar {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
    tabs.view().frame = CGRect(x: 0, y: 791, width: 402, height: 83)
    window.addSubview(tabs.view())
    window.isHidden = false
    tabs.view().layoutIfNeeded()
    return tabs
  }

  private var taps: [Int] { messenger.sent.filter { $0.method == "tap" }.compactMap { $0.arguments as? Int } }

  /// Where each tab's button sits across the bar.
  private let centres: [CGFloat] = [74, 159, 243, 328]

  func testUIKitSelectionThenLiftTapsOnce() {
    let tabs = laidOut(makeBar())
    tabs.began()
    tabs.bar.delegate?.tabBar?(tabs.bar, didSelect: tabs.bar.items![3])
    tabs.lifted(at: CGPoint(x: centres[3], y: 30))
    XCTAssertEqual(taps, [3])
  }

  /// UIKit selects on a drag that leaves the bar, as natively; the lift,
  /// off the bar, adds nothing.
  func testDragOffKeepsUIKitSelection() {
    let tabs = laidOut(makeBar())
    tabs.began()
    tabs.bar.delegate?.tabBar?(tabs.bar, didSelect: tabs.bar.items![2])
    tabs.lifted(at: CGPoint(x: centres[3], y: -200))
    XCTAssertEqual(taps, [2])
  }

  /// A system gesture can cancel the touch after UIKit has selected (#188).
  func testCancelAfterUIKitSelectionKeepsIt() {
    let tabs = laidOut(makeBar())
    tabs.began()
    tabs.bar.selectedItem = tabs.bar.items![1]
    tabs.bar.delegate?.tabBar?(tabs.bar, didSelect: tabs.bar.items![1])
    tabs.lifted(at: nil)
    XCTAssertEqual(taps, [1])
    XCTAssertEqual(tabs.bar.selectedItem?.title, "Spaces")
  }

  func testCancelWithoutSelectionTapsNothing() {
    let tabs = laidOut(makeBar())
    tabs.began()
    tabs.lifted(at: nil)
    XCTAssertEqual(taps, [])
    XCTAssertEqual(tabs.bar.selectedItem?.title, "Home")
  }

  /// Near the home indicator UIKit selects nothing; the lift picks the tab
  /// under the finger, and a refusal from the router still snaps back.
  func testLiftInHomeIndicatorBandTapsTheTabUnderIt() {
    let tabs = laidOut(makeBar())
    tabs.began()
    tabs.lifted(at: CGPoint(x: centres[2], y: tabs.bar.bounds.maxY - 4))
    XCTAssertEqual(taps, [2])
    XCTAssertEqual(tabs.bar.selectedItem?.title, "Loans")
    messenger.call(channelName, "update", ["selected": 0])
    XCTAssertEqual(tabs.bar.selectedItem?.title, "Home")
  }

  /// Items are found by their buttons' frames, which need no accessibility
  /// labels: UIKit fills those only while VoiceOver or XCUITest runs (#188).
  func testFindsEveryTabByGeometryWithoutLabels() {
    let tabs = laidOut(makeBar())
    func all(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + all($0) } }
    all(tabs.bar).forEach { $0.accessibilityLabel = nil }
    let band = tabs.bar.bounds.maxY - 4
    for (index, x) in centres.enumerated() {
      for point in [CGPoint(x: x, y: 30), CGPoint(x: x, y: band), CGPoint(x: x - 38, y: 50)] {
        XCTAssertEqual(tabs.tag(at: point), index, "\(point)")
      }
    }
    XCTAssertNil(tabs.tag(at: CGPoint(x: centres[1], y: -1)))
  }

  func testFindsTabsRightToLeft() {
    let tabs = makeBar()
    tabs.bar.semanticContentAttribute = .forceRightToLeft
    _ = laidOut(tabs)
    XCTAssertEqual(centres.map { tabs.tag(at: CGPoint(x: $0, y: 30)) }, [3, 2, 1, 0])
  }

  /// VoiceOver selects with no touch on the bar, also right after one.
  func testSelectionWithoutTouchIsSentEveryTime() {
    let tabs = laidOut(makeBar())
    tabs.began()
    tabs.bar.delegate?.tabBar?(tabs.bar, didSelect: tabs.bar.items![1])
    tabs.lifted(at: CGPoint(x: centres[1], y: 30))
    tabs.bar.delegate?.tabBar?(tabs.bar, didSelect: tabs.bar.items![1])
    tabs.bar.delegate?.tabBar?(tabs.bar, didSelect: tabs.bar.items![2])
    XCTAssertEqual(taps, [1, 1, 2])
  }

  func testRouterUpdateSetsSelectionAndAppearance() {
    let tabs = makeBar()
    messenger.call(channelName, "update", ["selected": 2, "dark": true])
    XCTAssertEqual(tabs.bar.selectedItem?.title, "Loans")
    XCTAssertEqual(tabs.view().overrideUserInterfaceStyle, .dark)
  }

  func testTintIsSettloActionNotSystemBlue() {
    let tabs = makeBar()
    messenger.call(channelName, "update", ["tint": 0xFFD8B36A])
    var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
    tabs.bar.tintColor.getRed(&r, green: &g, blue: &b, alpha: &a)
    XCTAssertEqual([r, g, b, a].map { Int(($0 * 255).rounded()) }, [0xD8, 0xB3, 0x6A, 0xFF])
  }

  func testReportsItsHeightOnLayout() {
    let tabs = makeBar()
    tabs.view().frame = CGRect(x: 0, y: 0, width: 402, height: 83)
    tabs.view().layoutIfNeeded()
    let height = messenger.sent.first { $0.method == "height" }?.arguments as? Double
    XCTAssertEqual(height, Double(tabs.bar.sizeThatFits(tabs.view().bounds.size).height))
    XCTAssertGreaterThanOrEqual(height ?? 0, 44)
  }

  /// What VoiceOver reads: UIKit's own tab buttons, labelled, with the
  /// router's selection as the selected trait.
  func testTabsAreVoiceOverButtonsWithSelection() {
    enableAccessibilityRuntime()
    let tabs = makeBar(selected: 1)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
    tabs.view().frame = CGRect(x: 0, y: 778, width: 402, height: 96)
    window.addSubview(tabs.view())
    window.isHidden = false
    tabs.view().layoutIfNeeded()

    func all(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(all) }
    // iOS 26 draws each button twice (content and selection lens); VoiceOver
    // reads one per position.
    var seen = Set<String>()
    let buttons = all(tabs.bar).filter {
      $0.isAccessibilityElement && $0.accessibilityTraits.contains(.button)
        && seen.insert($0.accessibilityLabel ?? "").inserted
    }
    XCTAssertEqual(buttons.map(\.accessibilityLabel), ["Home", "Spaces", "Loans", "Activity"])
    XCTAssertEqual(
      buttons.map { $0.accessibilityTraits.contains(.selected) }, [false, true, false, false])

    messenger.call(channelName, "update", ["selected": 3])
    XCTAssertEqual(
      buttons.map { $0.accessibilityTraits.contains(.selected) }, [false, false, false, true])
  }

  func testPromptClaimsPersistAcrossReopensAndStopAfterAnswer() {
    let suite = "reminder-tests-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    for trigger in ["remind", "instalmentLoan", "profile"] {
      XCTAssertFalse(ReminderChannel.claimPrompt(trigger, notDetermined: false, defaults: defaults))
      XCTAssertTrue(ReminderChannel.claimPrompt(trigger, notDetermined: true, defaults: defaults))
      XCTAssertFalse(ReminderChannel.claimPrompt(trigger, notDetermined: true,
                                                defaults: UserDefaults(suiteName: suite)!))
    }
    defaults.removePersistentDomain(forName: suite)
    defaults.set(true, forKey: "reminder.prompt.answered")
    for trigger in ["remind", "instalmentLoan", "profile"] {
      XCTAssertFalse(ReminderChannel.claimPrompt(trigger, notDetermined: true, defaults: defaults))
    }
  }

  func testSeenCapKeepsNumericallyNewestActivityIDs() {
    let retained = ReminderChannel.recentSeen(Set((1...1001).map { "manual:\($0)" }))
    XCTAssertEqual(retained.count, 500)
    XCTAssertEqual(retained.first, "manual:502")
    XCTAssertEqual(retained.last, "manual:1001")
    XCTAssertFalse(retained.contains("manual:9"))
    XCTAssertTrue(retained.contains("manual:1000"))
  }

  func testSeenCapPreservesLargeBigintIDs() {
    XCTAssertEqual(ReminderChannel.recentSeen(["manual:9", "manual:10", "manual:9223372036854775806"]),
                   ["manual:9", "manual:10", "manual:9223372036854775806"])
  }
}

/// Turns on UIKit's accessibility runtime, as an assistive client such as
/// VoiceOver would, so views answer with what VoiceOver reads (as KIF does).
private func enableAccessibilityRuntime() {
  let root = ProcessInfo.processInfo.environment["IPHONE_SIMULATOR_ROOT"] ?? ""
  guard let lib = dlopen(root + "/usr/lib/libAccessibility.dylib", RTLD_NOW) else { return }
  typealias Toggle = @convention(c) (Bool) -> Void
  for name in ["_AXSSetAutomationEnabled", "_AXSApplicationAccessibilitySetEnabled"] {
    if let fn = dlsym(lib, name) { unsafeBitCast(fn, to: Toggle.self)(true) }
  }
  _ = Bundle(path: root + "/System/Library/AccessibilityBundles/UIKit.axbundle")?.load()
  RunLoop.current.run(until: Date().addingTimeInterval(1))
}
