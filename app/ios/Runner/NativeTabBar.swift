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
/// iOS the standard bar; nothing tints or blurs it. Flutter's router owns the
/// selection: a tap is sent as `tap`, and `update` sets what is selected.
/// `height` reports the size UIKit wants, home indicator included.
final class NativeTabBar: NSObject, FlutterPlatformView, UITabBarDelegate {
  let bar = UITabBar()
  private let host = Host()
  private let channel: FlutterMethodChannel

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
      bar.selectedItem = items[index]
    }
    // The app's theme can differ from the system's.
    if let dark = state["dark"] as? Bool { host.overrideUserInterfaceStyle = dark ? .dark : .light }
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    channel.invokeMethod("tap", arguments: item.tag)
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
