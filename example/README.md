# adfacten_ads example

Every Adfacten ad format in one app: banner (all sizes), interstitial, rewarded, native (small and medium
templates) and app open, including an app-open ad shown when the app returns from the background.

It is preconfigured with Adfacten's public test apps (`lib/config.dart`), which always receive test ads that are
never billed. The ad server checks the bundle id, so the app id is `com.adfacten.sample` on both platforms.

```sh
flutter run
```

Integration tests that load and show each format against the ad server (one full-screen format per file,
because an ad on screen cannot be closed from a test):

```sh
flutter test integration_test/banner_native_test.dart
flutter test integration_test/interstitial_test.dart
flutter test integration_test/rewarded_test.dart
flutter test integration_test/app_open_test.dart
```

To try your own app, put its app key and placement ids from the Adfacten panel in `lib/config.dart` and change
the bundle id / application id to the one registered for it.
