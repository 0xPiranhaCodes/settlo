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
  }
}

// Local reminders use Apple's notification centre; no push SDK or credentials.
// Generic copy deliberately keeps names and amounts off the lock screen.
enum ReminderChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "app.settlo/reminders", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
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
          if settings.authorizationStatus == .notDetermined {
            _ = try? await centre.requestAuthorization(options: [.alert, .sound])
          }
          var seen = Set(UserDefaults.standard.stringArray(forKey: "reminder.seen") ?? [])
          for row in rows {
            guard let id = row["id"] as? String, let ms = row["at"] as? NSNumber,
              let body = row["body"] as? String else { continue }
            if id.hasPrefix("manual:") && seen.contains(id) { continue }
            let content = UNMutableNotificationContent()
            content.title = "Settlo"
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
          UserDefaults.standard.set(Array(seen).sorted().suffix(500).map { $0 }, forKey: "reminder.seen")
          result(nil)
        }
      }
  }
}
