import ActivityKit
import SwiftUI
import WidgetKit

@main
struct SettloWidgets: WidgetBundle {
  var body: some Widget {
    SettleUpLiveActivity()
  }
}

/// A settle-up waiting for you to confirm it: the Dynamic Island (compact,
/// minimal, expanded) and the lock screen (canvas LiveActivity, note n32).
/// Confirm deep-links to the confirm sheet.
struct SettleUpLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: SettleUpAttributes.self) { context in
      SettleUpCard(state: context.state)
        .padding(16)
        .activityBackgroundTint(.black)
        .activitySystemActionForegroundColor(Palette.text)
        .widgetURL(context.state.confirmURL)
    } dynamicIsland: { context in
      let state = context.state
      return DynamicIsland {
        DynamicIslandExpandedRegion(.bottom) {
          SettleUpCard(state: state)
        }
      } compactLeading: {
        HStack(spacing: 6) {
          Coin(size: 18)
          Text(state.payer).font(.system(size: 13, weight: .medium)).lineLimit(1)
        }
      } compactTrailing: {
        Text("\(state.amount) pending").font(.system(size: 13, weight: .medium)).monospacedDigit()
      } minimal: {
        Coin(size: 18)
      }
      .widgetURL(state.confirmURL)
      .keylineTint(Palette.gold)
    }
  }
}

private enum Palette {
  static let gold = Color(red: 0xD8 / 255, green: 0xB3 / 255, blue: 0x6A / 255)
  static let onGold = Color(red: 0x0A / 255, green: 0x0B / 255, blue: 0x0D / 255)
  static let text = Color(red: 0xF3 / 255, green: 0xF2 / 255, blue: 0xEE / 255)
  static let secondary = Color(red: 0x9B / 255, green: 0x9D / 255, blue: 0x9A / 255)
  static let track = Color.white.opacity(0.16)
}

/// The mark used on the canvas: a gold coin with two bars.
private struct Coin: View {
  let size: CGFloat

  var body: some View {
    ZStack {
      Circle().fill(Palette.gold)
      VStack(spacing: size * 0.12) {
        ForEach(0..<2) { _ in
          Capsule().fill(Palette.onGold).frame(width: size * 0.42, height: size * 0.1)
        }
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

/// The expanded island and the lock screen: who is paying you, how much,
/// where it is, and Confirm.
private struct SettleUpCard: View {
  let state: SettleUpAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Coin(size: 26)
        Text("Settlo · \(state.space)").font(.system(size: 15)).foregroundStyle(Palette.text)
          .lineLimit(1)
        Spacer()
        Text(state.recordedAt, format: .relative(presentation: .named))
          .font(.system(size: 13)).foregroundStyle(Palette.secondary)
      }
      HStack(alignment: .firstTextBaseline) {
        Text("\(state.payer) is paying you").font(.system(size: 17)).foregroundStyle(Palette.text)
          .lineLimit(1)
        Spacer()
        // The app's amounts are IBM Plex Serif; the system serif stands in here.
        Text(state.amount).font(.system(size: 30, weight: .medium, design: .serif))
          .monospacedDigit().foregroundStyle(Palette.text)
      }
      // Requested and paid; your confirmation is the last step. Progress is neutral, never gold.
      VStack(spacing: 6) {
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            Capsule().fill(Palette.track)
            Capsule().fill(Palette.text).frame(width: geo.size.width * 2 / 3)
          }
        }
        .frame(height: 4)
        HStack {
          Text("Requested")
          Spacer()
          Text("Paid")
          Spacer()
          Text("Confirm").foregroundStyle(Palette.text)
        }
        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
      }
      Link(destination: state.confirmURL) {
        Text("Confirm received").font(.system(size: 15, weight: .medium))
          .foregroundStyle(Palette.onGold)
          .frame(maxWidth: .infinity, minHeight: 44)
          .background(Palette.gold, in: RoundedRectangle(cornerRadius: 16))
      }
    }
  }
}
