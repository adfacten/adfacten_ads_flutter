import 'package:flutter/services.dart';

/// Why a load or show failed.
///
/// Each value has a stable [wire] name shared with the native Android and iOS
/// SDKs (`no_fill`, `network_error`, ...). The exact name the native SDK
/// reported is kept in [AdError.name], its numeric code in
/// [AdError.nativeCode].
enum AdErrorCode {
  /// Unexpected SDK or plugin error.
  internal('internal_error'),

  /// `Adfacten.initialize` was not called, or the app key is malformed.
  notInitialized('not_initialized'),

  /// The request was invalid, for example an empty placement id.
  invalidRequest('invalid_request'),

  /// Network failure or timeout.
  network('network_error'),

  /// No ad available right now. The SDK waits at least 30 seconds before
  /// asking again for the same placement.
  noFill('no_fill'),

  /// The ad server returned an error (5xx).
  serverError('server_error'),

  /// The ad server sent a response the SDK could not use.
  invalidResponse('invalid_response'),

  /// The ad server refused the request. See [AdError.serverCode]:
  /// `unknown_app`, `app_not_approved`, `bundle_mismatch`,
  /// `platform_mismatch`, `placement_mismatch`, `invalid_request`.
  rejected('rejected'),

  /// The ad was loaded more than about 55 minutes ago. Load a new one.
  expired('ad_expired'),

  /// The ad was already shown, or is not ready to be shown. Full-screen ads
  /// are single use.
  alreadyShown('already_shown'),

  /// A video creative needs the optional Android video module.
  videoNotSupported('video_not_supported'),

  /// The ad could not be presented (no foreground activity or view
  /// controller, or another Adfacten ad is on screen).
  showFailed('show_failed'),

  /// A load for this ad is already running.
  loadInProgress('load_in_progress'),

  /// The creative failed to render (image download, video, HTML).
  creativeFailed('creative_failed'),

  /// The app or request is child-directed (COPPA); ads are not served.
  childDirected('child_directed'),

  /// The ad was disposed before the call completed. Reported by the plugin
  /// only.
  disposed('disposed');

  const AdErrorCode(this.wire);

  /// The stable error name, shared with the native SDKs.
  final String wire;

  /// Maps a native error name to a code. `not_ready` becomes [alreadyShown],
  /// and `rejected` with server code `coppa` becomes [childDirected]. Unknown
  /// names become [internal].
  static AdErrorCode fromWire(String? value, {String? serverCode}) {
    if (value == 'rejected' && serverCode == 'coppa') return childDirected;
    if (value == 'not_ready') return alreadyShown;
    for (final code in values) {
      // Plugins before 1.0.1 sent the Dart enum name.
      if (code.wire == value || code.name == value) return code;
    }
    return AdErrorCode.internal;
  }
}

/// An ad load or show error.
class AdError implements Exception {
  const AdError(
    this.code,
    this.message, {
    this.serverCode,
    this.nativeCode,
    String? name,
  }) : _name = name;

  /// Builds an error from a channel payload (`code`, `message`, `serverCode`,
  /// `nativeCode`), where `code` is the native error name.
  factory AdError.fromMap(Map<Object?, Object?>? map) {
    if (map == null) {
      return const AdError(AdErrorCode.internal, 'unknown error');
    }
    return _fromNative(
      map['code'] as String?,
      map['message'] as String?,
      map['serverCode'] as String?,
      (map['nativeCode'] as num?)?.toInt(),
    );
  }

  factory AdError.fromPlatformException(PlatformException e) {
    final details = e.details;
    return _fromNative(
      e.code,
      e.message,
      details is Map ? details['serverCode'] as String? : null,
      details is Map ? (details['nativeCode'] as num?)?.toInt() : null,
    );
  }

  static AdError _fromNative(
    String? name,
    String? message,
    String? serverCode,
    int? nativeCode,
  ) {
    final code = AdErrorCode.fromWire(name, serverCode: serverCode);
    return AdError(
      code,
      message ?? '',
      serverCode: serverCode,
      nativeCode: nativeCode,
      name: name == null || name.isEmpty ? null : name,
    );
  }

  final AdErrorCode code;
  final String message;

  /// The ad server's machine code, when the server rejected the request
  /// (`unknown_app`, `app_not_approved`, `placement_mismatch`, `coppa`, ...).
  final String? serverCode;

  /// The error code reported by the native SDK, if any. It differs between
  /// Android and iOS; prefer [code] or [name].
  final int? nativeCode;

  final String? _name;

  /// The stable error name the native SDK reported (`no_fill`,
  /// `network_error`, `rejected`, ...), the same on Android and iOS. Falls
  /// back to [code]'s name for errors raised by the plugin itself.
  String get name => _name ?? code.wire;

  @override
  String toString() {
    final server = serverCode == null ? '' : ', serverCode: $serverCode';
    return 'AdError($name: $message$server)';
  }
}
