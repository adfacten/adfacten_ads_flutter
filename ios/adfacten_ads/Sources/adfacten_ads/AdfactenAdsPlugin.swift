import AdfactenAds
import Flutter
import UIKit

/// Bridges the Dart API to the Adfacten iOS SDK.
///
/// Dart gives every ad an integer id. Loaded full-screen and native ads live in `ads` until Dart
/// disposes them (or a full-screen ad is dismissed). Events go back on the same channel as
/// `onAdEvent`. Flutter calls the plugin on the main thread, and the SDK is main-actor isolated.
@MainActor
public final class AdfactenAdsPlugin: NSObject, FlutterPlugin {
    private let channel: FlutterMethodChannel
    private var ads: [Int: AnyObject] = [:]
    /// Full-screen ads on screen with their delegates, kept alive until dismissed even if Dart
    /// disposed them. Keyed by object, since ids restart after a hot restart.
    private var presenting: [ObjectIdentifier: (ad: FullScreenAd, handler: FullScreenHandler)] = [:]
    private var pendingLoads = Set<Int>()
    private var nativeViews: [Int: WeakNativeView] = [:]
    /// Bumped on `reset` (Dart hot restart) so callbacks of older ads are dropped.
    private(set) var generation = 0

    private init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    nonisolated public static func register(with registrar: FlutterPluginRegistrar) {
        MainActor.assumeIsolated {
            let channel = FlutterMethodChannel(name: "com.adfacten.ads", binaryMessenger: registrar.messenger())
            let instance = AdfactenAdsPlugin(channel: channel)
            registrar.addMethodCallDelegate(instance, channel: channel)
            registrar.register(BannerViewFactory(plugin: instance), withId: "com.adfacten.ads/banner")
            registrar.register(NativeAdViewFactory(plugin: instance), withId: "com.adfacten.ads/native")
            registrar.publish(instance)
        }
    }

    nonisolated public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        MainActor.assumeIsolated { clearAds() }
    }

    nonisolated public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        MainActor.assumeIsolated { handleOnMain(call, result: result) }
    }

    private func handleOnMain(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "reset":
            clearAds()
            result(nil)
        case "initialize":
            initialize(args)
            result(nil)
        case "setUserId":
            Adfacten.setUserId(args["userId"] as? String)
            result(nil)
        case "isInitialized":
            result(Adfacten.isInitialized)
        case "sdkVersion":
            result(Adfacten.sdkVersion)
        case "loadAd":
            loadAd(args, result: result)
        case "showAd":
            showAd(args, result: result)
        case "isAdReady":
            result((ads[adId(args)] as? FullScreenAd)?.isReady ?? false)
        case "disposeAd":
            disposeAd(adId(args))
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func adId(_ args: [String: Any]) -> Int {
        (args["adId"] as? NSNumber)?.intValue ?? -1
    }

    private func initialize(_ args: [String: Any]) {
        let config = AdfactenConfig()
        config.testMode = args["testMode"] as? Bool ?? false
        config.childDirected = args["childDirected"] as? Bool ?? false
        config.userId = args["userId"] as? String
        switch args["logLevel"] as? String {
        case "none": config.logLevel = .none
        case "error": config.logLevel = .error
        case "info": config.logLevel = .info
        case "debug": config.logLevel = .debug
        default: config.logLevel = .warning
        }
        Adfacten.initialize(appKey: args["appKey"] as? String ?? "", config: config)
    }

    // MARK: Loading

    private func loadAd(_ args: [String: Any], result: @escaping FlutterResult) {
        let id = adId(args)
        let placementId = args["placementId"] as? String ?? ""
        let gen = generation
        pendingLoads.insert(id)

        // Returns false (and answers Dart) when the ad was disposed while loading.
        func accept() -> Bool {
            if gen == generation, pendingLoads.remove(id) != nil { return true }
            result(FlutterError(code: "disposed", message: "the ad was disposed while loading", details: nil))
            return false
        }
        func fail(_ error: Error?) {
            pendingLoads.remove(id)
            result(flutterError(error))
        }

        switch args["format"] as? String {
        case "interstitial":
            InterstitialAd.load(placementId: placementId) { [weak self] ad, error in
                guard let self, let ad else { return fail(error) }
                guard accept() else { return }
                self.ads[id] = ad
                result([String: Any]())
            }
        case "appOpen":
            AppOpenAd.load(placementId: placementId) { [weak self] ad, error in
                guard let self, let ad else { return fail(error) }
                guard accept() else { return }
                self.ads[id] = ad
                result([String: Any]())
            }
        case "rewarded":
            RewardedAd.load(placementId: placementId, customData: args["customData"] as? String) { [weak self] ad, error in
                guard let self, let ad else { return fail(error) }
                guard accept() else { return }
                self.ads[id] = ad
                result(["reward": ad.reward.map { rewardMap($0) as Any } ?? NSNull()])
            }
        case "native":
            NativeAd.load(placementId: placementId) { [weak self] ad, error in
                guard let self, let ad else { return fail(error) }
                guard accept() else { return }
                ad.onImpression = { [weak self] in self?.send(gen, id, "shown") }
                ad.onClicked = { [weak self] in self?.send(gen, id, "clicked") }
                self.ads[id] = ad
                result(nativeAssets(ad))
            }
        default:
            pendingLoads.remove(id)
            result(FlutterError(code: "invalidRequest", message: "unknown format", details: nil))
        }
    }

    // MARK: Showing

    private func showAd(_ args: [String: Any], result: @escaping FlutterResult) {
        let id = adId(args)
        guard let ad = ads[id] as? FullScreenAd else {
            return result(FlutterError(code: "disposed", message: "the ad was disposed or not loaded", details: nil))
        }
        guard let vc = Self.rootViewController() else {
            return result(FlutterError(code: "showFailed", message: "no view controller in a window", details: nil))
        }
        let handler = FullScreenHandler(id: id, generation: generation, plugin: self)
        ad.delegate = handler
        presenting[ObjectIdentifier(ad)] = (ad, handler)
        if let rewarded = ad as? RewardedAd {
            let gen = generation
            rewarded.present(from: vc) { [weak self] reward in
                self?.send(gen, id, "reward", ["reward": rewardMap(reward)])
            }
        } else {
            ad.present(from: vc)
        }
        result(nil)
    }

    fileprivate func fullScreenFinished(_ ad: FullScreenAd, id: Int, generation gen: Int, dismissed: Bool) {
        presenting[ObjectIdentifier(ad)] = nil
        if dismissed, gen == generation, ads[id] === ad { ads[id] = nil }
    }

    private static func rootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.filter { $0.activationState == .foregroundActive }
        let windows = (active.isEmpty ? scenes : active).flatMap(\.windows)
        let window = windows.first(where: \.isKeyWindow) ?? windows.first
        return window?.rootViewController
    }

    // MARK: Lifetime

    private func disposeAd(_ id: Int) {
        pendingLoads.remove(id)
        let ad = ads.removeValue(forKey: id)
        if let native = ad as? NativeAd {
            native.onImpression = nil
            native.onClicked = nil
            nativeViews.removeValue(forKey: id)?.view?.nativeAd = nil
        }
        if let ad = ad as? FullScreenAd { presenting[ObjectIdentifier(ad)]?.handler.forward = false }
    }

    private func clearAds() {
        generation += 1
        for (_, ref) in nativeViews { ref.view?.nativeAd = nil }
        nativeViews.removeAll()
        // Ads on screen stay until dismissed, but their events no longer reach Dart.
        for (_, entry) in presenting { entry.handler.forward = false }
        ads.removeAll()
        pendingLoads.removeAll()
    }

    // MARK: Native views

    func nativeAd(_ id: Int) -> NativeAd? { ads[id] as? NativeAd }

    /// An ad is bound to one view at a time: binding it elsewhere unbinds the previous view.
    func bind(_ id: Int, to view: NativeAdView) {
        guard let ad = nativeAd(id) else { return }
        if let old = nativeViews[id]?.view, old !== view { old.nativeAd = nil }
        nativeViews[id] = WeakNativeView(view: view)
        view.nativeAd = ad
    }

    func unbind(_ id: Int, from view: NativeAdView) {
        if nativeViews[id]?.view === view { nativeViews[id] = nil }
        view.nativeAd = nil
    }

    // MARK: Events

    /// Sends an ad event, unless the ad belongs to an earlier Dart isolate.
    func send(_ gen: Int, _ id: Int, _ event: String, _ extra: [String: Any] = [:]) {
        guard gen == generation else { return }
        send(id, event, extra)
    }

    func send(_ id: Int, _ event: String, _ extra: [String: Any] = [:]) {
        var args: [String: Any] = ["adId": id, "event": event]
        args.merge(extra) { _, new in new }
        channel.invokeMethod("onAdEvent", arguments: args)
    }
}

private struct WeakNativeView {
    weak var view: NativeAdView?
}

/// Delegate of one full-screen ad. `FullScreenAd.delegate` is weak, so the plugin keeps it.
@MainActor
private final class FullScreenHandler: NSObject, FullScreenAdDelegate {
    let id: Int
    let generation: Int
    weak var plugin: AdfactenAdsPlugin?
    var forward = true

    init(id: Int, generation: Int, plugin: AdfactenAdsPlugin) {
        self.id = id
        self.generation = generation
        self.plugin = plugin
    }

    private func send(_ event: String, _ extra: [String: Any] = [:]) {
        if forward { plugin?.send(generation, id, event, extra) }
    }

    func adDidPresent(_ ad: FullScreenAd) { send("shown") }

    func adDidClick(_ ad: FullScreenAd) { send("clicked") }

    func adDidDismiss(_ ad: FullScreenAd) {
        send("closed")
        plugin?.fullScreenFinished(ad, id: id, generation: generation, dismissed: true)
    }

    func ad(_ ad: FullScreenAd, didFailToPresentWithError error: Error) {
        send("failedToShow", ["error": errorMap(error)])
        plugin?.fullScreenFinished(ad, id: id, generation: generation, dismissed: false)
    }
}

// MARK: Mapping

private func rewardMap(_ reward: AdReward) -> [String: Any] {
    let amount: Any = reward.amount.rounded() == reward.amount && abs(reward.amount) < 1e15
        ? Int(reward.amount) : reward.amount
    return ["type": reward.type, "amount": amount]
}

@MainActor
private func nativeAssets(_ ad: NativeAd) -> [String: Any] {
    func value(_ s: String?) -> Any { s ?? NSNull() }
    return [
        "title": value(ad.title),
        "body": value(ad.body),
        "brand": value(ad.brand),
        "callToAction": value(ad.callToAction),
        "adLabel": ad.adLabel,
        "imageUrl": value(ad.imageURL?.absoluteString),
        "iconUrl": value(ad.iconURL?.absoluteString),
        "imageWidth": Double(ad.imageSize.width),
        "imageHeight": Double(ad.imageSize.height),
        "hasImage": ad.image != nil,
        "hasIcon": ad.icon != nil,
    ]
}

/// Maps the iOS SDK codes to the platform-neutral codes of the Dart API.
private func wireCode(_ code: AdfactenErrorCode) -> String {
    switch code {
    case .notInitialized: return "notInitialized"
    case .noFill: return "noFill"
    case .network: return "network"
    case .serverRejected: return "rejected"
    case .invalidResponse: return "invalidResponse"
    case .expired: return "expired"
    case .notReady: return "alreadyShown"
    case .presentationFailed: return "showFailed"
    case .creativeFailed: return "creativeFailed"
    case .childDirected: return "childDirected"
    @unknown default: return "internal"
    }
}

func errorMap(_ error: Error?) -> [String: Any] {
    guard let error else {
        return ["code": "internal", "message": "unknown error", "serverCode": NSNull(), "nativeCode": NSNull()]
    }
    if let e = error as? AdfactenError {
        return [
            "code": wireCode(e.code),
            "message": e.message,
            "serverCode": e.serverCode ?? NSNull(),
            "nativeCode": e.code.rawValue,
        ]
    }
    let ns = error as NSError
    let code = ns.domain == AdfactenErrorDomain ? AdfactenErrorCode(rawValue: ns.code).map(wireCode) ?? "internal" : "internal"
    return [
        "code": code,
        "message": ns.localizedDescription,
        "serverCode": ns.userInfo["serverCode"] as? String ?? NSNull(),
        "nativeCode": ns.code,
    ]
}

private func flutterError(_ error: Error?) -> FlutterError {
    let map = errorMap(error)
    return FlutterError(
        code: map["code"] as? String ?? "internal",
        message: map["message"] as? String,
        details: ["serverCode": map["serverCode"] ?? NSNull(), "nativeCode": map["nativeCode"] ?? NSNull()]
    )
}
