import 'platform.dart';

/// How much the native SDK logs (Logcat tag `Adfacten`, iOS subsystem
/// `com.adfacten.ads`).
enum LogLevel { none, error, warn, info, debug }

/// Settings passed to [Adfacten.initialize].
///
/// Consent (IAB TCF v2, GPP, US Privacy) is read by the native SDKs from the
/// values your CMP stores (SharedPreferences / UserDefaults). Nothing needs to
/// be passed here for it.
class AdfactenConfig {
  const AdfactenConfig({
    this.testMode = false,
    this.logLevel = LogLevel.warn,
    this.childDirected = false,
    this.userId,
  });

  /// Request test ads. Test ads are never billed. Turn it off for release
  /// builds, for example with `testMode: kDebugMode`.
  final bool testMode;

  final LogLevel logLevel;

  /// The app (or this user) is directed at children (COPPA / Families).
  /// Device identifiers are then never read and Adfacten does not serve ads.
  final bool childDirected;

  /// Your own user id. Sent only with rewarded requests and echoed in the
  /// server-side reward callback. Change it later with [Adfacten.setUserId].
  final String? userId;

  Map<String, Object?> toMap() => {
    'testMode': testMode,
    'logLevel': logLevel.name,
    'childDirected': childDirected,
    'userId': userId,
  };
}

/// Entry point of the Adfacten Ads SDK.
abstract final class Adfacten {
  /// Initializes the native SDK. Call once, early (for example in `main`
  /// after `WidgetsFlutterBinding.ensureInitialized()`). Calling it again
  /// replaces the config.
  ///
  /// [appKey] is the public app key (`apk_...`) from the Adfacten panel. It
  /// is per platform: Android and iOS apps have different keys.
  static Future<void> initialize(
    String appKey, {
    AdfactenConfig config = const AdfactenConfig(),
  }) {
    return AdfactenPlatform.instance.invoke<void>('initialize', {
      'appKey': appKey.trim(),
      ...config.toMap(),
    });
  }

  /// Sets (or clears) your user id for rewarded ads, for example after login.
  static Future<void> setUserId(String? userId) {
    return AdfactenPlatform.instance.invoke<void>('setUserId', {
      'userId': userId,
    });
  }

  /// Whether the native SDK was initialized with a valid app key.
  static Future<bool> isInitialized() async {
    return await AdfactenPlatform.instance.invoke<bool>('isInitialized') ??
        false;
  }

  /// Version of the native SDK, e.g. `1.0.0`.
  static Future<String> nativeSdkVersion() async {
    return await AdfactenPlatform.instance.invoke<String>('sdkVersion') ?? '';
  }
}
