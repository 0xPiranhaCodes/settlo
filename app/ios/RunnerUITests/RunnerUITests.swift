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
    for screen in ["Space", "Balances", "Loan"] {
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
    for screen in ["Home", "Space", "Balances", "Loan"] {
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
    for screen in ["Home", "Space"] {
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

  /// Profile is a sheet over Home (#196): the avatar opens it, and its
  /// labelled Close or a swipe down dismisses it back to Home.
  func testAvatarOpensProfileSheetThatCloseDismisses() {
    for swipe in [false, true] {
      let (app, bar) = launch()
      _ = open("Profile", app, bar)
      let title = app.staticTexts["You"]
      XCTAssertTrue(title.waitForExistence(timeout: 10))
      let close = app.buttons["Close"]
      XCTAssertTrue(close.waitForExistence(timeout: 10))
      XCTAssertGreaterThanOrEqual(close.frame.width, 44)
      XCTAssertGreaterThanOrEqual(close.frame.height, 44)
      if swipe {
        let top = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        top.press(forDuration: 0.05, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 600)))
      } else {
        close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      }
      wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: title)], timeout: 5)
      XCTAssertEqual(selected(bar), ["Home"], swipe ? "swipe" : "close")
    }
  }

  /// Home's glass bell and avatar are UIKit buttons on iOS 26 (#191): each
  /// is a labelled 44pt button that opens its screen.
  func testHeaderGlassButtonsOpenTheirScreens() {
    for (label, title) in [("Notifications", "Activity"), ("Profile", "You")] {
      let (app, bar) = launch()
      dismissPrompt(app)
      let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
      XCTAssertTrue(button.waitForExistence(timeout: 10), label)
      XCTAssertGreaterThanOrEqual(button.frame.width, 44, label)
      XCTAssertGreaterThanOrEqual(button.frame.height, 44, label)
      button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      dismissPrompt(app)  // Profile asks about reminders on a fresh install.
      // Activity is a tab, so the bar moving proves the screen opened.
      XCTAssertTrue(
        title == "Activity" ? becomes(title, bar) : app.staticTexts[title].waitForExistence(timeout: 10),
        label)
    }
  }

  func testProfileLastRowIsOnScreen() {
    let (app, bar) = launch()
    _ = open("Profile", app, bar)
    let last = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH 'Delete account'")).firstMatch
    XCTAssertTrue(last.waitForExistence(timeout: 10))
    for _ in 0..<4 { app.swipeUp() }
    sleep(1)
    XCTAssertLessThanOrEqual(last.frame.maxY, app.frame.maxY)
  }

  /// #258: switch the app theme independently of the system, then touch
  /// the visible label band using coordinates (no XCTest hit-point repair).
  func testTabBarAppearanceAndLabelTouches() {
    let (app, bar) = launch()
    dismissPrompt(app)
    for mode in ["Light", "Dark", "Light"] {
      touch("Home", bar)
      tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Profile'")).firstMatch)
      dismissPrompt(app)
      let appearance = app.descendants(matching: .any)
        .matching(NSPredicate(format: "label BEGINSWITH 'Appearance'")).firstMatch
      tap(appearance)
      tap(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", mode)).firstMatch)
      tap(app.buttons["Close"])
      sleep(2)
      let attachment = XCTAttachment(screenshot: app.screenshot())
      attachment.name = "tabbar-258-" + mode
      attachment.lifetime = .keepAlways
      add(attachment)
      for name in tabs {
        let button = bar.buttons[name]
        XCTAssertLessThanOrEqual(button.frame.maxY, app.frame.maxY)
        let point = app.coordinate(withNormalizedOffset: .zero)
          .withOffset(CGVector(dx: button.frame.midX, dy: button.frame.maxY - 8))
        point.tap()
        XCTAssertTrue(becomes(name, bar))
        dismissPrompt(app)
      }
    }
  }

  /// Issue #202: fixture screens reached by HID coordinate taps, with native
  /// glass controls included. Run once per system appearance and revision.
  func testPaletteEvidence() {
    let (app, bar) = launch()
    dismissPrompt(app)
    func shot(_ name: String) {
      sleep(2)
      let attachment = XCTAttachment(screenshot: app.screenshot())
      attachment.name = "palette-" + name
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    func hit(_ element: XCUIElement) {
      XCTAssertTrue(element.waitForExistence(timeout: 10))
      element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      sleep(1)
    }
    func tab(_ name: String) {
      touch(name, bar)
      XCTAssertTrue(becomes(name, bar), "Evidence must show the selected \(name) tab")
    }
    shot("home")
    tab("Loans"); dismissPrompt(app); shot("loans")
    tab("Activity"); shot("activity")
    tab("Spaces"); shot("spaces")
    _ = open("Balances", app, bar); shot("balances")
    hit(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Expenses'")).firstMatch)
    hit(app.buttons.matching(NSPredicate(format: "label == 'Add expense'")).firstMatch)
    shot("add-expense")
    hit(app.buttons["Close"])
    sleep(2) // Let the native sheet dismissal and its hit regions settle.
    tab("Home")
    hit(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Profile'")).firstMatch)
    dismissPrompt(app); shot("profile")
  }

  /// Issue #248: the seven dark-mode surfaces, with real native chrome.
  func testNeutralDarkEvidence() {
    let (app, bar) = launch()
    dismissPrompt(app)
    func shot(_ name: String) {
      sleep(2)
      let attachment = XCTAttachment(screenshot: app.screenshot())
      attachment.name = "dark248-" + name
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    func hit(_ label: String) {
      let element = app.buttons[label].firstMatch
      XCTAssertTrue(element.waitForExistence(timeout: 10))
      element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      sleep(2)
    }
    func tab(_ name: String) {
      touch(name, bar)
      XCTAssertTrue(becomes(name, bar))
    }
    shot("home")
    tab("Loans"); dismissPrompt(app); shot("loans")
    tab("Activity"); shot("activity")
    tab("Spaces"); shot("spaces")
    _ = open("Space", app, bar); shot("space-detail")
    hit("Add expense"); shot("add-expense")
    hit("Close")
    hit("Settle up"); shot("settle-up")
  }

  func testPaletteLoansEvidence() {
    let (app, bar) = launch()
    dismissPrompt(app)
    touch("Loans", bar)
    XCTAssertTrue(becomes("Loans", bar))
    dismissPrompt(app)
    sleep(2)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "palette-loans"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func testPaletteAuthEvidence() {
    let app = XCUIApplication()
    app.launch()
    let action = app.buttons["Continue with phone number"]
    XCTAssertTrue(action.waitForExistence(timeout: 30))
    func shot(_ name: String) {
      sleep(2)
      let attachment = XCTAttachment(screenshot: app.screenshot())
      attachment.name = "palette-" + name
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    shot("welcome")
    action.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    shot("auth")
  }

}
