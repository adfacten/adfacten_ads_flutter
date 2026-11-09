import AdfactenAds
import Flutter
import UIKit

final class BannerViewFactory: NSObject, FlutterPlatformViewFactory {
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
            BannerPlatformView(
                frame: frame,
                adId: (params["adId"] as? NSNumber)?.intValue ?? -1,
                placementId: params["placementId"] as? String ?? "",
                size: Self.size(params["size"] as? String),
                plugin: plugin
            )
        }
    }

    private static func size(_ wire: String?) -> AdfactenBannerSize {
        switch wire {
        case "largeBanner": return .largeBanner
        case "mediumRectangle": return .mediumRectangle
        case "leaderboard": return .leaderboard
        default: return .banner
        }
    }
}

/// Hosts an `AdfactenBannerView`, centered in the platform view. Flutter releases it when the
/// widget leaves the tree, which destroys the banner.
@MainActor
private final class BannerPlatformView: NSObject, FlutterPlatformView {
    private let container: UIView
    private let banner: AdfactenBannerView

    init(frame: CGRect, adId: Int, placementId: String, size: AdfactenBannerSize, plugin: AdfactenAdsPlugin?) {
        container = UIView(frame: frame)
        container.backgroundColor = .clear
        container.clipsToBounds = true
        banner = AdfactenBannerView(placementId: placementId, size: size)
        super.init()

        banner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            banner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            banner.widthAnchor.constraint(equalToConstant: size.size.width),
            banner.heightAnchor.constraint(equalToConstant: size.size.height),
        ])

        banner.onLoaded = { [weak plugin] in plugin?.send(adId, "loaded") }
        banner.onFailed = { [weak plugin] error in plugin?.send(adId, "failedToLoad", ["error": errorMap(error)]) }
        banner.onImpression = { [weak plugin] in plugin?.send(adId, "shown") }
        banner.onClicked = { [weak plugin] in plugin?.send(adId, "clicked") }
        banner.load()
    }

    nonisolated func view() -> UIView {
        MainActor.assumeIsolated { container }
    }

    deinit {
        let banner = self.banner
        if Thread.isMainThread {
            MainActor.assumeIsolated { banner.destroy() }
        } else {
            Task { @MainActor in banner.destroy() }
        }
    }
}
