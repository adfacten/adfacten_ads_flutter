## 1.0.1

- Built on the native Adfacten SDK 1.0.2 for Android and iOS (CocoaPods: `AdfactenAds-1.0.2.xcframework.zip`).
- Banners retry by themselves after a failed load while they are on screen, and a placement's refresh setting
  now applies the same way on both platforms.
- Showing a native ad again, or in another view, never counts a second impression.
- New `AdError.name`: the stable error name from the native SDK (`no_fill`, `network_error`, `rejected`, ...),
  the same on Android and iOS. `AdError.code` is now derived from it; existing values are unchanged.
- The plugin reports itself to the SDK (`flutter` and the plugin version), sent with ad requests.
- New `Adfacten.pluginVersion`.

## 1.0.0

First release.

- `Adfacten.initialize` and `Adfacten.setUserId`.
- `AdfactenBanner` widget: 320x50, 320x100, 300x250 and 728x90, with auto-refresh and on-screen impressions.
- `InterstitialAd`, `RewardedAd` (with `customData` and the reward) and `AppOpenAd`, with shown, clicked, closed and
  failed-to-show callbacks.
- `NativeAd` with `AdfactenNativeAdView`: small and medium native templates, styled from the app theme or
  `NativeAdStyle`.
- Platform-neutral `AdErrorCode` plus the ad server's `serverCode`.
- Android: Adfacten Maven repository added automatically; optional video and advertising ID modules.
- iOS: Swift Package Manager, with a CocoaPods fallback that vendors the prebuilt XCFramework.
- Built on the native Adfacten SDK 1.0.0 for Android and iOS.
