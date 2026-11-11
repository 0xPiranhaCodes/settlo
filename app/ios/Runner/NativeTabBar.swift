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
/// A touch selects the item it lifts on, decided here rather than by UIKit
/// (#174). Near the home indicator UIKit holds a touch until the system
/// gesture fails, so iOS 26's selection only starts once the finger is up and
/// selects nothing: the lower band of every tab, labels included, was dead.
/// And its selection lens selects on a drag that leaves the bar.
final class NativeTabBar: NSObject, FlutterPlatformView, UITabBarDelegate,
  UIGestureRecognizerDelegate
{
  let bar = UITabBar()
  private let host = Host()
  private let channel: FlutterMethodChannel
  private let finger = Finger()
  private var selected = 0

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
    bar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    host.addSubview(bar)
    finger.delegate = self
    finger.onEnd = { [weak self] point in
      // After UIKit's own selection for this touch, which is overruled.
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

  /// Only selections without a touch, such as VoiceOver's.
  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    if !finger.tracking { channel.invokeMethod("tap", arguments: item.tag) }
  }

  private func lifted(at point: CGPoint?) {
    finger.tracking = false
    guard let items = bar.items, items.indices.contains(selected) else { return }
    var view = point.flatMap { bar.hitTest($0, with: nil) }
    while let found = view, found !== bar {
      if let item = items.first(where: { $0.title == found.accessibilityLabel }) {
        bar.selectedItem = item
        return channel.invokeMethod("tap", arguments: item.tag)
      }
      view = found.superview
    }
    bar.selectedItem = items[selected]
  }

  func gestureRecognizer(
    _ recognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
  ) -> Bool { true }

  /// Follows a touch on the bar to where it lifts, without recognizing.
  private final class Finger: UIGestureRecognizer {
    var tracking = false
    var onEnd: ((CGPoint?) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
      tracking = true
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
