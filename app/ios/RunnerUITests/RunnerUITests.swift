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

  /// A plain touch at an absolute point in the part of the tab's frame no
  /// neighbour's frame overlaps, as a finger lands.
  private func touch(_ tab: String, _ bar: XCUIElement, at point: CGVector) {
    let i = tabs.firstIndex(of: tab)!
    let frame = bar.buttons[tab].frame
    let minX = i > 0 ? bar.buttons[tabs[i - 1]].frame.maxX : frame.minX
    let maxX = i < tabs.count - 1 ? bar.buttons[tabs[i + 1]].frame.minX : frame.maxX
    XCUIApplication().coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
      dx: minX + (maxX - minX) * point.dx, dy: frame.minY + frame.height * point.dy)).tap()
  }

  private func becomes(_ tab: String, _ bar: XCUIElement) -> Bool {
    let moved = NSPredicate { _, _ in self.selected(bar) == [tab] }
    return XCTWaiter().wait(for: [expectation(for: moved, evaluatedWith: nil)], timeout: 5) == .completed
  }

  /// Every part of each tab's frame selects it (#174): the label band at 0.75
  /// and the lower corners were dead while icon-height taps worked.
  func testEveryPointOfEveryTabSelectsIt() {
    let grid = [0.08, 0.5, 0.92].flatMap { x in
      [0.08, 0.5, 0.75, 0.92].map { y in CGVector(dx: x, dy: y) }
    }
    for screen in ["Home", "Profile", "Space", "Balances", "Loan"] {
      let (app, bar) = launch()
      let owner = screen == "Home" ? "Home" : open(screen, app, bar)
      dismissPrompt(app)
      for tab in tabs where tab != owner {
        for point in grid {
          touch(tab, bar, at: point)
          XCTAssertTrue(becomes(tab, bar), "\(screen): \(tab) at \(point)")
          touch(owner, bar)
          XCTAssertTrue(becomes(owner, bar), "\(screen): back to \(owner)")
        }
      }
    }
  }

  /// A drag that starts on a tab and leaves the bar selects that tab, as a
  /// native tab bar does (#188).
  func testDragOffTheBarSelectsTheTab() {
    for screen in ["Home", "Profile"] {
      let (app, bar) = launch()
      if screen != "Home" { _ = open(screen, app, bar) }
      dismissPrompt(app)
      let start = bar.buttons["Activity"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      start.press(
        forDuration: 0.4, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -220)),
        withVelocity: XCUIGestureVelocity(150), thenHoldForDuration: 0.3)
      XCTAssertTrue(becomes("Activity", bar), screen)
    }
  }

  func testEdgeSwipeBackFromProfile() {
    let (app, bar) = launch()
    _ = open("Profile", app, bar)
    let title = app.staticTexts["You"]
    XCTAssertTrue(title.waitForExistence(timeout: 10))
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5)).press(
      forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
    wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: title)], timeout: 5)
    XCTAssertEqual(selected(bar), ["Home"])
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
