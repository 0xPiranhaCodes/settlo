import ActivityKit
import Flutter

/// Starts, updates and ends the settle-up Live Activity on
/// `app.settlo/live_activity` (ADR 0012). One at a time, driven by app state;
/// no push in v1.
enum LiveActivityChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "app.settlo/live_activity", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        // ActivityContent needs 16.2; on 16.1 there is simply no activity.
        guard #available(iOS 16.2, *) else { return result(nil) }
        switch call.method {
        case "show":
          guard let args = call.arguments as? [String: Any], let state = contentState(args) else {
            return result(FlutterError(code: "bad_args", message: "show needs a settle-up", details: nil))
          }
          Task {
            await show(state)
            result(nil)
          }
        case "end":
          Task {
            await end()
            result(nil)
          }
        case "requestPermission":
          // iOS asks nothing up front; people turn Live Activities off in Settings.
          result(ActivityAuthorizationInfo().areActivitiesEnabled)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
  }

  private static func contentState(_ args: [String: Any]) -> SettleUpAttributes.ContentState? {
    guard let id = args["id"] as? String, let space = args["space"] as? String,
      let payer = args["payer"] as? String, let amount = args["amount"] as? String,
      let recordedAtMs = args["recordedAtMs"] as? NSNumber, let path = args["path"] as? String
    else { return nil }
    return .init(
      id: id, space: space, payer: payer, amount: amount,
      recordedAt: Date(timeIntervalSince1970: recordedAtMs.doubleValue / 1000), path: path)
  }

  @available(iOS 16.2, *)
  private static func show(_ state: SettleUpAttributes.ContentState) async {
    let content = ActivityContent(state: state, staleDate: nil)
    // Activities outlive the app process, so one from an earlier launch is updated, not duplicated.
    let running = Activity<SettleUpAttributes>.activities
    guard let current = running.first else {
      _ = try? Activity.request(attributes: SettleUpAttributes(), content: content)
      return
    }
    await current.update(content)
    for extra in running.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
  }

  @available(iOS 16.2, *)
  private static func end() async {
    for activity in Activity<SettleUpAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}
