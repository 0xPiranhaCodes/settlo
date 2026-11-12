import Flutter
import UIKit

/// Creates a header action for `UiKitView('app.settlo/glass_button')` (#191).
final class GlassButtonFactory: NSObject, FlutterPlatformViewFactory {
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
    GlassButton(
      args as? [String: Any] ?? [:],
      channel: FlutterMethodChannel(
        name: "app.settlo/glass_button/\(viewId)", binaryMessenger: messenger))
  }
}

/// One circular header action as iOS 26's `UIButton.Configuration.glass()`,
/// which samples the Flutter content behind it. A tap is sent as `tap`;
/// `update` replaces the label, symbol or title, badge, colours and state.
/// The badge is a UILabel on the button, so Flutter draws no overlay above
/// the platform view.
final class GlassButton: NSObject, FlutterPlatformView {
  let button = UIButton(type: .system)
  let badge = UILabel()
  private let host = Host()
  private let channel: FlutterMethodChannel

  init(_ args: [String: Any], channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    button.frame = host.bounds
    button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    host.addSubview(button)
    badge.textAlignment = .center
    badge.font = .systemFont(ofSize: 12, weight: .medium)
    badge.layer.masksToBounds = true
    badge.isAccessibilityElement = false  // The button's label says the count.
    badge.isUserInteractionEnabled = false
    host.addSubview(badge)
    host.badge = badge
    button.addAction(
      UIAction { [weak self] _ in self?.channel.invokeMethod("tap", arguments: nil) },
      for: .primaryActionTriggered)
    apply(args)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update" else { return result(FlutterMethodNotImplemented) }
      self?.apply(call.arguments as? [String: Any] ?? [:])
      result(nil)
    }
  }

  func view() -> UIView { host }

  func apply(_ args: [String: Any]) {
    var config: UIButton.Configuration
    if #available(iOS 26, *) { config = .glass() } else { config = .gray() }
    config.cornerStyle = .capsule
    config.contentInsets = .zero
    if let symbol = args["symbol"] as? String {
      config.image = UIImage(
        systemName: symbol,
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
    }
    if let asset = args["asset"] as? String, let image = Self.image(asset) {
      config.image = image.withRenderingMode(.alwaysOriginal)
    }
    if let title = args["title"] as? String {
      config.attributedTitle = AttributedString(
        title, attributes: .init([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]))
    }
    if let argb = args["foreground"] as? Int { config.baseForegroundColor = color(argb) }
    button.configuration = config
    button.isEnabled = args["enabled"] as? Bool ?? true
    button.accessibilityLabel = args["label"] as? String
    let decorative = args["decorative"] as? Bool ?? false
    button.isUserInteractionEnabled = !decorative
    // A decorative mark reads as the header it stands for, not a button.
    // Setting traits replaces UIKit's own, so a disabled one says so.
    button.accessibilityTraits =
      decorative ? .header : button.isEnabled ? .button : [.button, .notEnabled]
    if let dark = args["dark"] as? Bool { host.overrideUserInterfaceStyle = dark ? .dark : .light }
    let count = args["badge"] as? String
    badge.text = count
    badge.isHidden = count == nil
    if let argb = args["badgeColor"] as? Int { badge.backgroundColor = color(argb) }
    if let argb = args["badgeText"] as? Int { badge.textColor = color(argb) }
    host.setNeedsLayout()
  }

  /// A `settlo_core` asset such as `assets/brand/x.png`, from its 3x file.
  static func image(_ asset: String) -> UIImage? {
    let url = URL(fileURLWithPath: asset)
    let path = url.deletingLastPathComponent().appendingPathComponent("3.0x")
      .appendingPathComponent(url.lastPathComponent).relativePath
    let key = FlutterDartProject.lookupKey(forAsset: path, fromPackage: "settlo_core")
    guard let file = Bundle.main.path(forResource: key, ofType: nil),
      let data = FileManager.default.contents(atPath: file)
    else { return nil }
    return UIImage(data: data, scale: 3)
  }

  private func color(_ argb: Int) -> UIColor {
    UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat((argb >> 24) & 0xFF) / 255)
  }

  /// Places the badge as SBell does: a 24pt capsule over the top-right edge.
  final class Host: UIView {
    weak var badge: UILabel?

    override func layoutSubviews() {
      super.layoutSubviews()
      guard let badge else { return }
      let width = max(18, badge.intrinsicContentSize.width + 10)
      badge.frame = CGRect(x: bounds.maxX + 4 - width, y: -2, width: width, height: 24)
      badge.layer.cornerRadius = 12
    }
  }
}
