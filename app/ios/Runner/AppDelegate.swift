import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    ReminderChannel.register(
      with: engineBridge.pluginRegistry.registrar(forPlugin: "ReminderChannel")!.messenger())
    LiveActivityChannel.register(
      with: engineBridge.pluginRegistry.registrar(forPlugin: "LiveActivityChannel")!.messenger())
    let glass = engineBridge.pluginRegistry.registrar(forPlugin: "GlassButton")!
    // As the tab bar below: iOS 26's UIButton misses taps under the eager policy.
    glass.register(
      GlassButtonFactory(messenger: glass.messenger()), withId: "app.settlo/glass_button",
      gestureRecognizersBlockingPolicy:
        FlutterPlatformViewGestureRecognizersBlockingPolicyDoNotBlockGesture)
    let tabBar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeTabBar")!
    // Under the default eager policy, iOS 26's UITabBar never selected a tab
    // even when Flutter's arena accepted the tap (#174, see flutter#175099).
    // Hit testing decides instead: the bar gets a touch unless a Flutter
    // widget, such as a dialog's barrier, covers it.
    tabBar.register(
      NativeTabBarFactory(messenger: tabBar.messenger()), withId: "app.settlo/tab_bar",
      gestureRecognizersBlockingPolicy:
        FlutterPlatformViewGestureRecognizersBlockingPolicyDoNotBlockGesture)
  }
}

// Local reminders use Apple's notification centre; no push SDK or credentials.
// Generic copy deliberately keeps names and amounts off the lock screen.
enum ReminderChannel {
  // Activity IDs are bigint sequence values; lexical order fails at 9/10 and 999/1000.
  static func recentSeen(_ seen: Set<String>) -> [String] {
    seen.sorted {
      (Int64($0.dropFirst("manual:".count)) ?? 0) < (Int64($1.dropFirst("manual:".count)) ?? 0)
    }.suffix(500).map { $0 }
  }

  static func claimPrompt(_ trigger: String, notDetermined: Bool,
                          defaults: UserDefaults = .standard) -> Bool {
    guard notDetermined, ["remind", "instalmentLoan", "profile"].contains(trigger) else { return false }
    let key = "reminder.prompt." + trigger
    guard !defaults.bool(forKey: "reminder.prompt.answered"),
      !defaults.bool(forKey: key) else { return false }
    defaults.set(true, forKey: key)
    return true
  }

  static func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "app.settlo/reminders", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        if call.method == "openSettings" {
          DispatchQueue.main.async {
            guard let url = URL(string: UIApplication.openSettingsURLString) else {
              return result(nil)
            }
            UIApplication.shared.open(url) { _ in result(nil) }
          }
          return
        }
        if ["permissionNeeded", "permissionStatus", "claimPrompt", "requestPermission"].contains(call.method) {
          Task { @MainActor in
            let centre = UNUserNotificationCenter.current()
            let settings = await centre.notificationSettings()
            let status = settings.authorizationStatus
            if call.method == "permissionNeeded" {
              result(status == .notDetermined)
            } else if call.method == "permissionStatus" {
              result(status == .notDetermined ? "notDetermined" : status == .denied ? "denied" : "granted")
            } else if call.method == "claimPrompt" {
              result(Self.claimPrompt(call.arguments as? String ?? "",
                                      notDetermined: status == .notDetermined))
            } else {
              if status == .notDetermined {
                _ = try? await centre.requestAuthorization(options: [.alert, .sound])
              }
              let answered = await centre.notificationSettings()
              if answered.authorizationStatus != .notDetermined {
                UserDefaults.standard.set(true, forKey: "reminder.prompt.answered")
              }
              result(nil)
            }
          }
          return
        }
        if call.method == "owner" {
          let owner = call.arguments as? String
          let defaults = UserDefaults.standard
          if owner == defaults.string(forKey: "reminder.owner") { return result(nil) }
          Task { @MainActor in
            let centre = UNUserNotificationCenter.current()
            let pending = await centre.pendingNotificationRequests()
            centre.removePendingNotificationRequests(withIdentifiers:
              pending.filter { $0.identifier.hasPrefix("reminder:") }.map(\.identifier))
            let delivered = await centre.deliveredNotifications()
            centre.removeDeliveredNotifications(withIdentifiers:
              delivered.filter { $0.request.identifier.hasPrefix("reminder:") }.map { $0.request.identifier })
            defaults.set(owner, forKey: "reminder.owner")
            defaults.removeObject(forKey: "reminder.seen")
            result(nil)
          }
          return
        }
        guard call.method == "replace", let rows = call.arguments as? [[String: Any]] else {
          return result(FlutterMethodNotImplemented)
        }
        Task { @MainActor in
          let centre = UNUserNotificationCenter.current()
          let pending = await centre.pendingNotificationRequests()
          let wanted = Set(rows.compactMap { ($0["id"] as? String).map { "reminder:" + $0 } })
          centre.removePendingNotificationRequests(withIdentifiers:
            pending.filter { $0.identifier.hasPrefix("reminder:") &&
              ($0.identifier.hasPrefix("reminder:due:") || !wanted.contains($0.identifier)) }.map(\.identifier))
          if rows.isEmpty {
            let delivered = await centre.deliveredNotifications()
            centre.removeDeliveredNotifications(withIdentifiers:
              delivered.filter { $0.request.identifier.hasPrefix("reminder:") }.map { $0.request.identifier })
            return result(nil)
          }
          let settings = await centre.notificationSettings()
          guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return result(nil)
          }
          var seen = Set(UserDefaults.standard.stringArray(forKey: "reminder.seen") ?? [])
          for row in rows {
            guard let id = row["id"] as? String, let ms = row["at"] as? NSNumber,
              let body = row["body"] as? String else { continue }
            if id.hasPrefix("manual:") && seen.contains(id) { continue }
            let content = UNMutableNotificationContent()
            content.title = "SabkiJeb"
            content.body = body
            content.sound = .default
            let date = max(Date(timeIntervalSince1970: ms.doubleValue / 1000), Date().addingTimeInterval(1))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            parts.timeZone = calendar.timeZone
            parts.calendar = calendar
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            do {
              try await centre.add(UNNotificationRequest(identifier: "reminder:" + id, content: content, trigger: trigger))
              if id.hasPrefix("manual:") { seen.insert(id) }
            } catch { /* A denied notification never interrupts the app. */ }
          }
          UserDefaults.standard.set(Self.recentSeen(seen), forKey: "reminder.seen")
          result(nil)
        }
      }
  }
}
