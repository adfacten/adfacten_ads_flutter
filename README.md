# Adfacten Ads for Flutter

Banner, interstitial, rewarded, native and app-open ads from the Adfacten network, for Android and iOS.

The plugin is a thin layer over the native Adfacten SDKs ([Android](https://github.com/adfacten/adfacten-android-sdk),
[iOS](https://github.com/adfacten/adfacten-ios-sdk)): ad requests, rendering, viewability and click handling all
happen natively, so impressions are counted the same way as in native apps.

- Android: minSdk 24. iOS: 15.0 or later.
- Flutter 3.32 or later.
- Built on the native Adfacten SDK 1.0.2 (Android `com.adfacten:ads:1.0.2`, iOS `AdfactenAds` 1.0.2).
- Full documentation: [developers.adfacten.com/mobile-sdk-en](https://developers.adfacten.com/mobile-sdk-en)

## Install

Until the package is on pub.dev, add it from GitHub:

```yaml
dependencies:
  adfacten_ads:
    git:
      url: https://github.com/adfacten/adfacten_ads_flutter
      ref: 1.0.1
```

### Android

Nothing else is needed in most apps: the plugin adds Adfacten's Maven repository
(`https://cdn.adfacten.com/maven/`) to the build.

If your app declares repositories only in `settings.gradle(.kts)` (`dependencyResolutionManagement` with
`RepositoriesMode.FAIL_ON_PROJECT_REPOS` or `PREFER_SETTINGS`), add the repository there:

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven("https://cdn.adfacten.com/maven/") { content { includeGroup("com.adfacten") } }
    }
}
```

Optional native modules, set in `android/gradle.properties`:

| Property | Default | |
|---|---|---|
| `adfacten.video` | `true` | VAST video for interstitial and rewarded ads (Media3 ExoPlayer, about 1.5 MB). With `false` only image and HTML creatives are requested, which lowers fill. |
| `adfacten.gaid` | `false` | Reads the Google advertising ID and App Set ID. Adds the `AD_ID` permission to your manifest; declare it in Play Console. |

### iOS

Swift Package Manager is used when it is enabled for your app (the default in current Flutter versions). The
plugin depends on [adfacten-ios-sdk](https://github.com/adfacten/adfacten-ios-sdk) and Xcode fetches it on the
first build.

With CocoaPods (SPM turned off), `pod install` downloads the prebuilt `AdfactenAds.xcframework` from
`cdn.adfacten.com`, checks its SHA-256 and vendors it. No Podfile changes are needed.

## Initialize

Call once, early. App keys are per platform: your Android and iOS apps have different keys in the Adfacten
panel (*Apps*), and each app is registered with its bundle id / application id.

```dart
import 'dart:io';

import 'package:adfacten_ads/adfacten_ads.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Adfacten.initialize(
    Platform.isIOS ? 'apk_your_ios_key' : 'apk_your_android_key',
    config: const AdfactenConfig(testMode: kDebugMode),
  );
  runApp(const MyApp());
}
```

| `AdfactenConfig` | Default | |
|---|---|---|
| `testMode` | `false` | Test ads only, never billed. |
| `logLevel` | `LogLevel.warn` | Native logs (Logcat tag `Adfacten`, iOS subsystem `com.adfacten.ads`). |
| `childDirected` | `false` | COPPA / Families. See [Privacy](#privacy). |
| `userId` | `null` | Your user id for rewarded server callbacks. Change it later with `Adfacten.setUserId`. |

Show your consent dialog (CMP) before loading ads; see [Privacy](#privacy).

## Banner

```dart
AdfactenBanner(
  placementId: 'plc_your_banner',
  size: AdSize.banner,
  onLoaded: () {},
  onFailedToLoad: (error) => debugPrint('banner: ${error.name}'),
  onShown: () {},   // the impression
  onClicked: () {},
)
```

Sizes: `AdSize.banner` (320x50), `largeBanner` (320x100), `mediumRectangle` (300x250), `leaderboard` (728x90,
tablets). The widget always has exactly that size.

The banner loads when it is first built and refreshes on the placement's interval (30 to 120 seconds), counting
only time while it is on screen and the app is in the foreground. If a load fails (no fill, network or server
error), it tries again on the same timer while it is on screen, never sooner than the SDK's back-off for that
placement. A rejected request (app or placement not approved, COPPA) stops it. So keep the widget in the tree if
you want an empty slot to fill later; removing it on `onFailedToLoad` stops the retries.

The impression is recorded only once the creative is actually visible, so a banner in a list that is never
scrolled to costs nothing. Removing the widget releases the native banner. Changing `placementId` or `size`
creates a new banner.

## Interstitial

```dart
InterstitialAd? _interstitial;

Future<void> _load() async {
  try {
    _interstitial = await InterstitialAd.load('plc_your_interstitial');
  } on AdError catch (e) {
    debugPrint('no interstitial: $e');
  }
}

Future<void> _showAtBreak() async {
  final ad = _interstitial;
  _interstitial = null;
  if (ad == null) return _continue();
  ad.listener = FullScreenAdListener(
    onShown: () {},
    onClicked: () {},
    onClosed: () {
      _continue();
      _load(); // get the next one ready
    },
    onFailedToShow: (error) {
      ad.dispose();
      _continue();
      _load();
    },
  );
  await ad.show();
}
```

Each loaded ad can be shown once and is valid for about 55 minutes; `await ad.isReady()` tells whether it can
still be shown. After `onClosed` the ad is disposed automatically. Call `dispose()` on an ad you drop without
showing it (an ad that is garbage collected is released as well).

## Rewarded

```dart
final ad = await RewardedAd.load('plc_your_rewarded', customData: 'level=3');
debugPrint('reward: ${ad.reward}'); // e.g. 10 coins, as set on the placement
ad.listener = FullScreenAdListener(onClosed: _resume);
await ad.show(onUserEarnedReward: (reward) {
  // UI only: show "+10 coins". Credit the user from your server callback.
});
```

Video plays to the end before the reward; closing early asks the user to confirm and forfeits it.

### Server-side verification

Never grant value from `onUserEarnedReward`; it runs on the device. After a valid completion Adfacten calls the
reward callback URL set in the panel:

```
GET https://your.server/reward?user_id=…&custom=…&reward_type=coins&reward_amount=10
    &transaction_id=<impression id>&placement=plc_…&ts=<unix>[&test=1]&sig=<hex>
```

`user_id` comes from `AdfactenConfig.userId` / `Adfacten.setUserId`, `custom` from `customData` (up to 256
characters). `sig` is `HMAC-SHA256(reward secret, raw query string)`, where the raw query string is everything
after `?` up to (not including) `&sig=`, exactly as received. Respond with 2xx; calls are retried until you do.
`transaction_id` is unique, so store it and ignore repeats. Skip rewards with `test=1` in production.

## Native

```dart
NativeAd? _native;

Future<void> _loadNative() async {
  final ad = await NativeAd.load(
    'plc_your_native',
    listener: NativeAdListener(onShown: () {}, onClicked: () {}),
  );
  setState(() => _native = ad);
}

@override
void dispose() {
  _native?.dispose();
  super.dispose();
}

// in build():
if (_native != null)
  AdfactenNativeAdView(
    ad: _native!,
    template: NativeAdTemplate.medium,
    style: const NativeAdStyle(cornerRadius: 16),
  ),
```

Templates:

- `NativeAdTemplate.small`: a row with the icon (or a square crop of the image), ad label, brand, title, one
  line of body and a compact button. About 80 to 90 logical pixels high; fits lists and feeds.
- `NativeAdTemplate.medium`: a card with icon, title and brand, the main image at its aspect ratio, body and a
  full-width button.

The view fills the available width and takes the height of its content. Colors default to the ambient `Theme`
(so dark mode works); override any of them with `NativeAdStyle`.

Why templates rather than your own Flutter widgets: an impression is billable only when the native SDK can see
the ad's view on screen and handle taps on it. Flutter widgets are drawn on a single canvas the native SDK
cannot inspect, so the plugin renders the ad with native views inside a platform view, laid out from a
template. The asset getters on `NativeAd` (`title`, `body`, `brand`, `callToAction`, `imageUrl`, `hasImage`, …)
are there to help you choose a template or decide whether to show the slot; an ad drawn with your own widgets
is not tracked and earns nothing.

One ad is shown in one view at a time. Disposing the widget does not dispose the ad, so you can keep the ad
while a list item scrolls away and back; dispose it when the screen goes away. Showing the same ad again, or in
another view, never counts a second impression.

## App open

Load ahead of time and show it when the app comes back to the foreground:

```dart
class AppOpenManager {
  AppOpenManager() {
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    load();
  }

  late final AppLifecycleListener _lifecycle;
  AppOpenAd? _ad;

  void dispose() {
    _lifecycle.dispose();
    _ad?.dispose();
  }

  Future<void> load() async {
    try {
      _ad = await AppOpenAd.load('plc_your_app_open');
    } on AdError {
      _ad = null;
    }
  }

  Future<void> _onResume() async {
    final ad = _ad;
    if (ad == null || !await ad.isReady()) return load();
    _ad = null;
    ad.listener = FullScreenAdListener(onClosed: load, onFailedToShow: (_) => load());
    await ad.show();
  }
}
```

On Android, a full-screen ad runs in its own activity, so closing an interstitial or rewarded ad also resumes
your app. Skip the app-open ad right after another full-screen ad closes, and after very short trips to the
background. The example app (`example/lib/app_open.dart`) shows one way to do this.

## Errors

Loads throw, and `onFailedToLoad` / `onFailedToShow` receive, an `AdError`. `AdError.name` is the stable error
name reported by the native SDK, the same on Android and iOS; `AdError.code` is the matching Dart enum.

| `AdError.name` | `AdError.code` | Meaning |
|---|---|---|
| `no_fill` | `noFill` | No ad right now. The SDK then waits at least 30 seconds before asking again for that placement. |
| `network_error` | `network` | Network error or timeout. |
| `server_error` | `serverError` | The ad server had an error (5xx). |
| `rejected` | `rejected` | The server refused the request. See `serverCode`: `unknown_app`, `app_not_approved`, `bundle_mismatch`, `platform_mismatch`, `placement_mismatch`, `test_only`. With `serverCode` `coppa` the code is `childDirected`. |
| `child_directed` | `childDirected` | The app or request is child-directed (iOS). |
| `not_initialized` | `notInitialized` | `Adfacten.initialize` was not called, or the app key is malformed. |
| `invalid_request` | `invalidRequest` | For example an empty placement id. |
| `ad_expired` | `expired` | The ad is older than about 55 minutes. Load a new one. |
| `already_shown`, `not_ready` | `alreadyShown` | The ad was already shown or is not loaded. Load a new one. |
| `show_failed` | `showFailed` | No foreground activity / view controller, or another Adfacten ad is on screen. The ad can be shown later. |
| `creative_failed`, `video_not_supported`, `invalid_response`, `load_in_progress`, `internal_error` | | Less common; see the message. |
| `disposed` | `disposed` | The ad was disposed before the call finished (plugin only). |

`serverCode` is the ad server's machine code and `nativeCode` the native SDK's own numeric code, which differs
between platforms. Prefer `name` or `code`.

## Test mode

Use `testMode: true` (for example `kDebugMode`) while integrating. Test ads look and track like real ones but are
never billed, and rewarded callbacks carry `test=1`. Apps under review, apps with test mode on in the panel,
apps whose app-ads.txt is not verified, emulators and the iOS simulator always get test ads.

The example app is preconfigured with Adfacten's public test apps and runs as is:

```sh
cd example
flutter run
```

Turn test mode off for release builds.

## Privacy

- **Consent (GDPR / TCF v2, GPP, US Privacy):** the native SDKs read the standard IAB keys your CMP stores
  (`IABTCF_*`, `IABGPP_*`, `IABUSPrivacy_String` in SharedPreferences / UserDefaults). Show the CMP before loading
  ads. Without purpose 1 consent where GDPR applies, no advertising ID is sent.
- **iOS App Tracking Transparency:** the SDK never shows the ATT prompt. If you ask for it (for example with the
  `app_tracking_transparency` package) and the user allows tracking, the IDFA is used; otherwise the IDFV or a
  random install id. Add `NSUserTrackingUsageDescription` to `Info.plist` if you ask. The SDK ships its own
  `PrivacyInfo.xcprivacy`; see the [iOS SDK README](https://github.com/adfacten/adfacten-ios-sdk#app-store-privacy-answers)
  for the App Store privacy answers.
- **Android advertising ID:** read only with `adfacten.gaid=true` (or if your app already includes
  `play-services-ads-identifier`), respecting the user's opt-out. That module adds the
  `com.google.android.gms.permission.AD_ID` permission. See the
  [Android SDK README](https://github.com/adfacten/adfacten-android-sdk#11-google-play-data-safety) for the Play
  Data safety answers.
- **Children:** set `childDirected: true` for child-directed apps or users. Device identifiers are then never
  read, and Adfacten does not serve ads to such traffic.
- Clicks always open in the browser or the store, never inside your app.

## License

Apache License 2.0. See [LICENSE](LICENSE).
