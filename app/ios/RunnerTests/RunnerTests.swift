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

  func testRouterUpdateSetsSelectionAndAppearance() {
    let tabs = makeBar()
    messenger.call(channelName, "update", ["selected": 2, "dark": true])
    XCTAssertEqual(tabs.bar.selectedItem?.title, "Loans")
    XCTAssertEqual(tabs.view().overrideUserInterfaceStyle, .dark)
  }

  func testReportsItsHeightOnLayout() {
    let tabs = makeBar()
    tabs.view().frame = CGRect(x: 0, y: 0, width: 402, height: 83)
    tabs.view().layoutIfNeeded()
    let height = messenger.sent.first { $0.method == "height" }?.arguments as? Double
    XCTAssertEqual(height, Double(tabs.bar.sizeThatFits(tabs.view().bounds.size).height))
    XCTAssertGreaterThanOrEqual(height ?? 0, 44)
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
