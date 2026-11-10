import ActivityKit
import Foundation

/// The settle-up Live Activity, shared by the app (which starts, updates and
/// ends it) and the widget extension (which draws it). ADR 0012.
struct SettleUpAttributes: ActivityAttributes {
  /// Everything is state, so one activity can move to another settle-up.
  struct ContentState: Codable, Hashable {
    var id: String
    var space: String
    var payer: String
    /// Formatted by the app, e.g. `₹2,100`.
    var amount: String
    var recordedAt: Date
    /// The confirm sheet's route, e.g. `/spaces/<id>/settle-ups/<id>`.
    var path: String

    /// Opens the app on the confirm sheet.
    var confirmURL: URL { URL(string: "settlo://app\(path)")! }
  }
}
