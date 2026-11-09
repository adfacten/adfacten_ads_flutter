import 'package:flutter/foundation.dart';

/// App key and placements of Adfacten's public test apps. They always get
/// test ads, which are never billed. The server checks the bundle id, so the
/// example uses `com.adfacten.sample` on both platforms.
///
/// To try your own app, replace these with the values from the Adfacten panel
/// (Apps > your app) and change the bundle id to yours.
class AdConfig {
  const AdConfig({
    required this.appKey,
    required this.banner,
    required this.interstitial,
    required this.rewarded,
    required this.native,
    required this.appOpen,
  });

  final String appKey;
  final String banner;
  final String interstitial;
  final String rewarded;
  final String native;
  final String appOpen;

  static const android = AdConfig(
    appKey: 'apk_3cnu84fqX8ucMX9XPyeQYHrR',
    banner: 'plc_034uZ7K1c31r4F5eyGyUpC',
    interstitial: 'plc_034uZ7K1i1xnu0Ksljnmy4',
    rewarded: 'plc_034uZ7K1nrWgf7S5ATCLrI',
    native: 'plc_034uZ7K1o0SSewGeBCGY9P',
    appOpen: 'plc_034uZ7K1o901BKzbEbWDjK',
  );

  static const ios = AdConfig(
    appKey: 'apk_r2FjVF7YUGb3ITZZUt6ENHH1',
    banner: 'plc_034uZ7K268zGmUPhbl0LgL',
    interstitial: 'plc_034uZ7K26J5FvjnFBJjThJ',
    rewarded: 'plc_034uZ7K2CBEP9L6EQszuIk',
    native: 'plc_034uZ7K2I1fWOEzDnkJpwt',
    appOpen: 'plc_034uZ7K2IBiNmiy9FGrHNe',
  );

  static AdConfig get current =>
      defaultTargetPlatform == TargetPlatform.iOS ? ios : android;
}
