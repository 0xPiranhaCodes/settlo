import Flutter
import UIKit

/// Creates the shell's system tab bar for `UiKitView('app.settlo/tab_bar')` (#157).
final class NativeTabBarFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?)
    -> FlutterPlatformView
  {
    NativeTabBar(
      args as? [String: Any] ?? [:],
      channel: FlutterMethodChannel(name: "app.settlo/tab_bar/\(viewId)", binaryMessenger: messenger))
  }
}

/// A plain UITabBar, so iOS 26 and later draw system Liquid Glass and earlier
/// iOS the standard bar; nothing blurs or covers it, and only the selected
/// item takes Settlo's tint. Flutter's router owns the selection: a tap is
/// sent as `tap`, and `update` sets what is selected.
/// `height` reports the size UIKit wants, home indicator included.
///
/// UIKit's own selection always counts, drag-off included, as in a native
/// tab bar. Near the home indicator UIKit holds a touch until the system
/// gesture fails, so iOS 26 selects nothing there (#174); only then does the
/// item under the lifted finger, found by its button's frame, count (#188).
/// Each touch sends one `tap`.
final class NativeTabBar: NSObject, FlutterPlatformView, UITabBarDelegate,
  UIGestureRecognizerDelegate
{
  let bar = UITabBar()
  private let host = Host()
  private let channel: FlutterMethodChannel
  private let finger = Finger()
  private var selected = 0
  /// Whether a touch is on the bar, and the tab it has sent, if any.
  private var touching = false
  private var sent: Int?

  init(_ args: [String: Any], channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    let items = args["items"] as? [[String: String]] ?? []
    bar.items = items.enumerated().map { index, item in
      let symbol = item["symbol"] ?? ""
      let tab = UITabBarItem(
        title: item["label"], image: UIImage(systemName: symbol),
        selectedImage: UIImage(systemName: symbol + ".fill") ?? UIImage(systemName: symbol))
      tab.tag = index
      return tab
    }
    bar.delegate = self
    bar.frame = host.bounds
    host.addSubview(bar)
    finger.delegate = self
    finger.onBegin = { [weak self] in self?.began() }
    finger.onEnd = { [weak self] point in
      // After UIKit's own selection for this touch, if it makes one.
      DispatchQueue.main.async { self?.lifted(at: point) }
    }
    bar.addGestureRecognizer(finger)
    host.bar = bar
    host.onHeight = { [weak channel] height in channel?.invokeMethod("height", arguments: height) }
    apply(args)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update" else { return result(FlutterMethodNotImplemented) }
      self?.apply(call.arguments as? [String: Any] ?? [:])
      result(nil)
    }
  }

  func view() -> UIView { host }

  private func apply(_ state: [String: Any]) {
    if let index = state["selected"] as? Int, let items = bar.items, items.indices.contains(index) {
      selected = index
      bar.selectedItem = items[index]
    }
    // The app's theme can differ from the system's.
    if let dark = state["dark"] as? Bool { host.overrideUserInterfaceStyle = dark ? .dark : .light }
    // Settlo's action token, so the selected tab is never system blue.
    if let argb = (state["tint"] as? NSNumber)?.uint32Value {
      bar.tintColor = UIColor(
        red: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
        blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat(argb >> 24) / 255)
    }
  }

  /// UIKit's own selection: a tap, a slide, a drag off the bar, or VoiceOver's.
  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) { send(item.tag) }

  private func send(_ tag: Int) {
    if touching {
      guard sent == nil else { return }
      sent = tag
    }
    channel.invokeMethod("tap", arguments: tag)
  }

  func began() {
    touching = true
    sent = nil
  }

  /// A cancelled touch has no point and selects nothing, leaving UIKit's
  /// selection, if any, in place.
  func lifted(at point: CGPoint?) {
    defer { touching = false }
    guard sent == nil, let point, let tag = tag(at: point), let items = bar.items else { return }
    bar.selectedItem = items[tag]
    send(tag)
  }

  /// The item whose button is nearest across, anywhere on the bar, as the
  /// band under the buttons belongs to them. Accessibility labels can't be
  /// used: UIKit fills them only while VoiceOver or XCUITest runs (#188).
  func tag(at point: CGPoint) -> Int? {
    guard let count = bar.items?.count, bar.bounds.contains(point) else { return nil }
    func all(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + all($0) } }
    // iOS 26 draws each button twice (content and selection lens).
    let centres = Set(
      all(bar).compactMap { $0 is UIControl ? $0.convert($0.bounds, to: bar).midX.rounded() : nil }
    ).sorted()
    guard centres.count == count else { return nil }
    let nearest = centres.indices.min { abs(centres[$0] - point.x) < abs(centres[$1] - point.x) }!
    return bar.effectiveUserInterfaceLayoutDirection == .rightToLeft ? count - 1 - nearest : nearest
  }

  func gestureRecognizer(
    _ recognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
  ) -> Bool { true }

  /// Follows a touch on the bar to where it lifts, without recognizing.
  private final class Finger: UIGestureRecognizer {
    var onBegin: (() -> Void)?
    var onEnd: ((CGPoint?) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
      onBegin?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
      onEnd?(touches.first?.location(in: view))
      state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
      onEnd?(nil)
      state = .failed
    }
  }

  /// Reports the bar's preferred height whenever layout or the safe area changes it.
  private final class Host: UIView {
    weak var bar: UITabBar?
    var onHeight: ((Double) -> Void)?
    private var reported: CGFloat = 0

    override func layoutSubviews() {
      super.layoutSubviews()
      guard let bar, bounds.width > 0 else { return }
      // UITabBar adjusts its own height on iOS 26. Flexible-height
      // autoresizing then adds the host's height delta a second time (#258).
      // Give it exactly the platform view's bounds on every layout pass.
      bar.frame = bounds
      bar.layoutIfNeeded()
      let height = bar.sizeThatFits(bounds.size).height
      if height != reported {
        reported = height
        onHeight?(Double(height))
      }
    }

    override func safeAreaInsetsDidChange() {
      super.safeAreaInsetsDidChange()
      setNeedsLayout()
    }
  }
}
