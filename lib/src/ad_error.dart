import 'package:flutter/services.dart';

/// Why a load or show failed.
///
/// The Android and iOS SDKs use different numeric codes; the plugin maps both
/// to these values. The original code is kept in [AdError.nativeCode].
enum AdErrorCode {
  /// Unexpected SDK or plugin error.
  internal('internal'),

  /// `Adfacten.initialize` was not called, or the app key is malformed.
  notInitialized('notInitialized'),

  /// The request was invalid, for example an empty placement id.
  invalidRequest('invalidRequest'),

  /// Network failure or timeout.
  network('network'),

  /// No ad available right now. The SDK waits at least 30 seconds before
  /// asking again for the same placement.
  noFill('noFill'),

  /// The ad server returned an error (5xx).
  serverError('serverError'),

  /// The ad server sent a response the SDK could not use.
  invalidResponse('invalidResponse'),

  /// The ad server refused the request. See [AdError.serverCode]:
  /// `unknown_app`, `app_not_approved`, `bundle_mismatch`,
  /// `platform_mismatch`, `placement_mismatch`, `coppa`, `invalid_request`.
  rejected('rejected'),

  /// The ad was loaded more than about 55 minutes ago. Load a new one.
  expired('expired'),

  /// The ad was already shown. Full-screen ads are single use.
  alreadyShown('alreadyShown'),

  /// A video creative needs the optional Android video module.
  videoNotSupported('videoNotSupported'),

  /// The ad could not be presented (no foreground activity or view
  /// controller, or another Adfacten ad is on screen).
  showFailed('showFailed'),

  /// A load for this ad is already running.
  loadInProgress('loadInProgress'),

  /// The creative failed to render (image download, video, HTML).
  creativeFailed('creativeFailed'),

  /// The app or request is child-directed; ads are not served.
  childDirected('childDirected'),

  /// The ad was disposed before the call completed.
  disposed('disposed');

  const AdErrorCode(this.wire);

  /// The value used on the method channel.
  final String wire;

  static AdErrorCode fromWire(String? value) {
    for (final code in values) {
      if (code.wire == value) return code;
    }
    return AdErrorCode.internal;
  }
}

/// An ad load or show error.
class AdError implements Exception {
  const AdError(this.code, this.message, {this.serverCode, this.nativeCode});

  /// Builds an error from a channel payload (`code`, `message`, `serverCode`,
  /// `nativeCode`).
  factory AdError.fromMap(Map<Object?, Object?>? map) {
    if (map == null) {
      return const AdError(AdErrorCode.internal, 'unknown error');
    }
    return AdError(
      AdErrorCode.fromWire(map['code'] as String?),
      (map['message'] as String?) ?? '',
      serverCode: map['serverCode'] as String?,
      nativeCode: (map['nativeCode'] as num?)?.toInt(),
    );
  }

  factory AdError.fromPlatformException(PlatformException e) {
    final details = e.details;
    return AdError(
      AdErrorCode.fromWire(e.code),
      e.message ?? '',
      serverCode: details is Map ? details['serverCode'] as String? : null,
      nativeCode: details is Map
          ? (details['nativeCode'] as num?)?.toInt()
          : null,
    );
  }

  final AdErrorCode code;
  final String message;

  /// The ad server's machine code, when the server rejected the request
  /// (`unknown_app`, `app_not_approved`, `placement_mismatch`, ...).
  final String? serverCode;

  /// The error code reported by the native SDK, if any. It differs between
  /// Android and iOS; prefer [code].
  final int? nativeCode;

  @override
  String toString() {
    final server = serverCode == null ? '' : ', serverCode: $serverCode';
    return 'AdError(${code.name}: $message$server)';
  }
}
