import XCTest

/// Real touches on the system tab bar from every screen pushed inside the
/// shell (#174). Widget tests can't reach UIKit, and #160's unit tests call
/// the delegate directly, so neither saw that UIKit never got the tap.
///
/// Runs on `integration_test/native_tab_bar_app.dart`; build it first, as
/// that file says.
final class RunnerUITests: XCTestCase {
  private let tabs = ["Home", "Spaces", "Loans", "Activity"]

  override func setUp() {
    continueAfterFailure = false
  }

  private func launch() -> (XCUIApplication, XCUIElement) {
    let app = XCUIApplication()
    app.launch()
    let bar = app.tabBars.firstMatch
    XCTAssertTrue(bar.waitForExistence(timeout: 30))
    return (app, bar)
  }

  /// A fresh install asks about reminders once the fakes' loans load.
  private func dismissPrompt(_ app: XCUIApplication) {
    let notNow = app.buttons["Not now"]
    if notNow.waitForExistence(timeout: 3) { notNow.tap() }
  }

  private func selected(_ bar: XCUIElement) -> [String] {
    bar.buttons.allElementsBoundByIndex.filter(\.isSelected).map(\.label)
  }

  /// A plain touch at the tab's centre. An element tap can be rerouted by
  /// XCUITest's own hit-point checks, which a finger never is.
  private func touch(_ tab: String, _ bar: XCUIElement) {
    bar.buttons[tab].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
  }

  private func tap(_ element: XCUIElement) {
    XCTAssertTrue(element.waitForExistence(timeout: 10), element.description)
    element.tap()
    sleep(1)
  }

  /// Opens a screen pushed inside the shell, by tapping as a person would,
  /// and returns the tab it belongs to.
  private func open(_ screen: String, _ app: XCUIApplication, _ bar: XCUIElement) -> String {
    dismissPrompt(app)
    defer { dismissPrompt(app) }
    let any = app.descendants(matching: .any)
    switch screen {
    case "Profile":
      tap(any.matching(NSPredicate(format: "label ENDSWITH 'Profile'")).firstMatch)
      return "Home"
    case "Space":
      touch("Spaces", bar); sleep(1)
      tap(any.matching(NSPredicate(format: "label CONTAINS 'Flat 402'")).firstMatch)
      return "Spaces"
    case "Balances":
      _ = open("Space", app, bar)
      tap(any.matching(NSPredicate(format: "label == 'Balances' OR label BEGINSWITH 'Balances'")).firstMatch)
      return "Spaces"
    default:
      touch("Loans", bar); sleep(1)
      tap(any.matching(NSPredicate(format: "label CONTAINS 'Arjun'")).firstMatch)
      return "Loans"
    }
  }

  func testEveryTabTapWorksFromEveryPushedScreen() {
    for screen in ["Profile", "Space", "Balances", "Loan"] {
      let (app, bar) = launch()
      let owner = open(screen, app, bar)
      for tab in tabs where tab != owner {
        touch(tab, bar)
        // The router confirms the tap; a refused one snaps the bar back.
        let moved = NSPredicate { _, _ in self.selected(bar) == [tab] }
        wait(for: [expectation(for: moved, evaluatedWith: nil)], timeout: 5)
        // Back to the pushed screen: its branch keeps it.
        touch(owner, bar)
        sleep(1)
        XCTAssertEqual(selected(bar), [owner], "\(screen) via \(tab)")
      }
    }
  }

  func testHomeTabFromProfileReturnsHome() {
    let (app, bar) = launch()
    _ = open("Profile", app, bar)
    let title = app.staticTexts["You"]
    XCTAssertTrue(title.waitForExistence(timeout: 10))
    touch("Home", bar)
    wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: title)], timeout: 5)
  }

  func testProfileLastRowClearsTheBar() {
    let (app, bar) = launch()
    _ = open("Profile", app, bar)
    let last = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH 'Delete account'")).firstMatch
    XCTAssertTrue(last.waitForExistence(timeout: 10))
    for _ in 0..<4 { app.swipeUp() }
    sleep(1)
    XCTAssertLessThanOrEqual(last.frame.maxY, bar.frame.minY)
  }
}
