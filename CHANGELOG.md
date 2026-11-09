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
