import AdfactenAds
import Flutter
import UIKit

final class NativeAdViewFactory: NSObject, FlutterPlatformViewFactory {
    private weak var plugin: AdfactenAdsPlugin?

    init(plugin: AdfactenAdsPlugin) {
        self.plugin = plugin
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        let params = args as? [String: Any] ?? [:]
        return MainActor.assumeIsolated {
            NativePlatformView(frame: frame, params: params, plugin: plugin)
        }
    }
}

@MainActor
private final class NativePlatformView: NSObject, FlutterPlatformView {
    private let adView: NativeTemplateView
    private let adId: Int
    private weak var plugin: AdfactenAdsPlugin?

    init(frame: CGRect, params: [String: Any], plugin: AdfactenAdsPlugin?) {
        adId = (params["adId"] as? NSNumber)?.intValue ?? -1
        self.plugin = plugin
        let style = TemplateStyle(params["style"] as? [String: Any] ?? [:])
        let small = (params["template"] as? String) == "small"
        let width = CGFloat((params["width"] as? NSNumber)?.doubleValue ?? Double(frame.width))
        adView = NativeTemplateView(frame: frame, small: small, style: style)
        super.init()

        guard let plugin, let ad = plugin.nativeAd(adId) else { return }
        adView.prepare(for: ad)
        plugin.bind(adId, to: adView)
        adView.didBind(ad)
        let id = adId
        adView.onHeight = { [weak plugin] height in plugin?.send(id, "measured", ["height": Double(height)]) }
        adView.measure(width: width)
    }

    nonisolated func view() -> UIView {
        MainActor.assumeIsolated { adView }
    }

    deinit {
        let view = adView
        let id = adId
        let plugin = self.plugin
        let unbind: @MainActor () -> Void = {
            if let plugin { plugin.unbind(id, from: view) } else { view.nativeAd = nil }
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated { unbind() }
        } else {
            Task { @MainActor in unbind() }
        }
    }
}

/// Colors and radii sent from Dart (already resolved against the app theme).
private struct TemplateStyle {
    var background = UIColor.systemBackground
    var title = UIColor.label
    var body = UIColor.secondaryLabel
    var brand = UIColor.secondaryLabel
    var ctaBackground = UIColor.systemBlue
    var ctaText = UIColor.white
    var labelBackground = UIColor.systemYellow
    var labelText = UIColor.black
    var cornerRadius: CGFloat = 12
    var ctaCornerRadius: CGFloat = 20

    init(_ map: [String: Any]) {
        func color(_ key: String) -> UIColor? {
            guard let n = map[key] as? NSNumber else { return nil }
            let argb = UInt32(truncatingIfNeeded: n.int64Value)
            return UIColor(
                red: CGFloat((argb >> 16) & 0xFF) / 255,
                green: CGFloat((argb >> 8) & 0xFF) / 255,
                blue: CGFloat(argb & 0xFF) / 255,
                alpha: CGFloat((argb >> 24) & 0xFF) / 255
            )
        }
        func number(_ key: String) -> CGFloat? {
            (map[key] as? NSNumber).map { CGFloat($0.doubleValue) }
        }
        background = color("backgroundColor") ?? background
        title = color("titleColor") ?? title
        body = color("bodyColor") ?? body
        brand = color("brandColor") ?? brand
        ctaBackground = color("callToActionBackgroundColor") ?? ctaBackground
        ctaText = color("callToActionTextColor") ?? ctaText
        labelBackground = color("adLabelBackgroundColor") ?? labelBackground
        labelText = color("adLabelTextColor") ?? labelText
        cornerRadius = number("cornerRadius") ?? cornerRadius
        ctaCornerRadius = number("callToActionCornerRadius") ?? ctaCornerRadius
    }
}

/// A `NativeAdView` laid out from one of the templates. The SDK view records the impression, the
/// viewable impression and clicks; this class only builds the layout and reports its height.
@MainActor
private final class NativeTemplateView: NativeAdView {
    private let small: Bool
    private let style: TemplateStyle
    private let content = UIStackView()
    private let title = UILabel()
    private let body = UILabel()
    private let brand = UILabel()
    private let badge = PaddedLabel()
    private let icon = UIImageView()
    private let media = UIImageView()
    private let cta = PaddedButton(type: .custom)
    private var mediaRatio: NSLayoutConstraint?
    private var measuredWidth: CGFloat = 0
    private var reportedHeight: CGFloat = 0

    var onHeight: ((CGFloat) -> Void)?

    init(frame: CGRect, small: Bool, style: TemplateStyle) {
        self.small = small
        self.style = style
        super.init(frame: frame)
        backgroundColor = style.background
        layer.cornerRadius = style.cornerRadius
        clipsToBounds = true
        configureViews()
        small ? buildSmall() : buildMedium()
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    private func configureViews() {
        func setUp(_ label: UILabel, size: CGFloat, weight: UIFont.Weight, color: UIColor, lines: Int) {
            label.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: size, weight: weight))
            label.adjustsFontForContentSizeCategory = true
            label.textColor = color
            label.numberOfLines = lines
            label.lineBreakMode = .byTruncatingTail
        }
        setUp(title, size: small ? 14 : 15, weight: .semibold, color: style.title, lines: 2)
        setUp(body, size: small ? 12 : 13, weight: .regular, color: style.body, lines: small ? 1 : 3)
        setUp(brand, size: 12, weight: .regular, color: style.brand, lines: 1)
        setUp(badge, size: 10, weight: .bold, color: style.labelText, lines: 1)
        badge.backgroundColor = style.labelBackground
        badge.layer.cornerRadius = 4
        badge.clipsToBounds = true
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)

        for image in [icon, media] {
            image.contentMode = .scaleAspectFill
            image.clipsToBounds = true
            image.layer.cornerRadius = 8
        }

        cta.backgroundColor = style.ctaBackground
        cta.setTitleColor(style.ctaText, for: .normal)
        cta.titleLabel?.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 14, weight: .semibold))
        cta.titleLabel?.adjustsFontForContentSizeCategory = true
        cta.titleLabel?.lineBreakMode = .byTruncatingTail
        cta.layer.cornerRadius = min(style.ctaCornerRadius, small ? 18 : 20)
        cta.clipsToBounds = true

        titleLabel = title
        bodyLabel = body
        brandLabel = brand
        adLabel = badge
        callToActionButton = cta
    }

    private func buildMedium() {
        content.axis = .vertical
        content.spacing = 10
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)

        let names = UIStackView(arrangedSubviews: [title, brand])
        names.axis = .vertical
        names.spacing = 2
        let badgeColumn = UIStackView(arrangedSubviews: [badge, UIView()])
        badgeColumn.axis = .vertical
        let header = UIStackView(arrangedSubviews: [icon, names, badgeColumn])
        header.axis = .horizontal
        header.spacing = 10
        header.alignment = .top
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
        ])

        cta.heightAnchor.constraint(equalToConstant: 40).isActive = true
        for v in [header, media, body, cta] { content.addArrangedSubview(v) }
        content.setCustomSpacing(8, after: media)
        iconView = icon
        mediaView = media
    }

    private func buildSmall() {
        content.axis = .horizontal
        content.spacing = 10
        content.alignment = .center
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)

        let top = UIStackView(arrangedSubviews: [badge, brand])
        top.axis = .horizontal
        top.spacing = 6
        top.alignment = .center
        let texts = UIStackView(arrangedSubviews: [top, title, body])
        texts.axis = .vertical
        texts.spacing = 2
        texts.alignment = .leading

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 56),
            icon.heightAnchor.constraint(equalToConstant: 56),
            cta.heightAnchor.constraint(equalToConstant: 36),
        ])
        cta.horizontalPadding = 14
        cta.setContentHuggingPriority(.required, for: .horizontal)
        cta.setContentCompressionResistancePriority(.required, for: .horizontal)
        texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for v in [icon, texts, cta] { content.addArrangedSubview(v) }
    }

    /// Picks the outlets that depend on the ad's assets. Call before binding.
    func prepare(for ad: NativeAd) {
        if small {
            // One thumbnail: the icon, or a square crop of the main image.
            iconView = ad.icon != nil ? icon : nil
            mediaView = ad.icon == nil && ad.image != nil ? icon : nil
        } else {
            let size = ad.imageSize
            let ratio = size.width > 0 && size.height > 0 ? min(max(size.width / size.height, 0.5), 4) : 1.91
            mediaRatio?.isActive = false
            mediaRatio = media.heightAnchor.constraint(equalTo: media.widthAnchor, multiplier: 1 / ratio)
            mediaRatio?.isActive = true
        }
    }

    /// Hides the slots the ad has no asset for. Call after binding.
    func didBind(_ ad: NativeAd) {
        brand.isHidden = ad.brand == nil
        body.isHidden = ad.body == nil
        if small {
            icon.isHidden = ad.icon == nil && ad.image == nil
        } else {
            icon.isHidden = ad.icon == nil
            media.isHidden = ad.image == nil
        }
    }

    func measure(width: CGFloat) {
        guard width > 0 else { return }
        measuredWidth = width
        let size = content.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let height = ceil(size.height)
        if height > 0, abs(height - reportedHeight) >= 0.5 {
            reportedHeight = height
            onHeight?(height)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > 0, abs(bounds.width - measuredWidth) >= 0.5 { measure(width: bounds.width) }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            reportedHeight = 0
            measure(width: bounds.width > 0 ? bounds.width : measuredWidth)
        }
    }
}

/// The "Ad" badge: a label with a little padding.
private final class PaddedLabel: UILabel {
    private let insets = UIEdgeInsets(top: 1, left: 5, bottom: 1, right: 5)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + insets.left + insets.right, height: s.height + insets.top + insets.bottom)
    }
}

/// A button with horizontal padding that still uses `setTitle(_:for:)`, which the SDK calls.
private final class PaddedButton: UIButton {
    var horizontalPadding: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + 2 * horizontalPadding, height: s.height)
    }
}
