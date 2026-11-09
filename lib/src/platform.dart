import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ad_error.dart';

/// Receives native events for one ad instance.
abstract interface class AdEventTarget {
  void handleAdEvent(String event, Map<Object?, Object?> args);
}

/// The method channel and the table that routes native events to ads.
///
/// Every ad gets an id from [newAdId]. Native events carry that id. Loaded
/// full-screen and native ads are held weakly so an ad the app drops is
/// released on the native side too; ads on screen are held strongly until
/// they close.
class AdfactenPlatform {
  AdfactenPlatform._() {
    channel.setMethodCallHandler(_onNativeCall);
  }

  static AdfactenPlatform? _instance;

  static AdfactenPlatform get instance => _instance ??= AdfactenPlatform._();

  /// Drops the singleton. Tests only.
  @visibleForTesting
  static void resetForTesting() {
    _instance?.channel.setMethodCallHandler(null);
    _instance = null;
  }

  static const String channelName = 'com.adfacten.ads';
  static const String bannerViewType = 'com.adfacten.ads/banner';
  static const String nativeViewType = 'com.adfacten.ads/native';

  final MethodChannel channel = const MethodChannel(channelName);

  final Map<int, WeakReference<AdEventTarget>> _weak = {};
  final Map<int, AdEventTarget> _strong = {};
  int _nextId = 1;
  Future<void>? _ready;

  late final Finalizer<int> _finalizer = Finalizer<int>((id) {
    _weak.remove(id);
    _strong.remove(id);
    _invokeQuietly('disposeAd', {'adId': id});
  });

  int newAdId() => _nextId++;

  /// Routes events for [id] to [target]. With [strong] false the target may
  /// be garbage collected; its native ad is then disposed.
  void register(int id, AdEventTarget target, {bool strong = false}) {
    if (strong) {
      _strong[id] = target;
    } else {
      _weak[id] = WeakReference(target);
      _finalizer.attach(target, id, detach: target);
    }
  }

  /// Keeps [target] alive while it is on screen.
  void pin(int id, AdEventTarget target) => _strong[id] = target;

  void unpin(int id) => _strong.remove(id);

  void unregister(int id, AdEventTarget target) {
    _weak.remove(id);
    _strong.remove(id);
    _finalizer.detach(target);
  }

  @visibleForTesting
  bool isRegistered(int id) => _weak.containsKey(id) || _strong.containsKey(id);

  /// Calls [method] after the native side dropped ads left over from a
  /// previous Dart isolate (hot restart).
  Future<T?> invoke<T>(String method, [Map<String, Object?>? args]) async {
    await (_ready ??= channel.invokeMethod<void>('reset').catchError((_) {}));
    try {
      return await channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw AdError.fromPlatformException(e);
    } on MissingPluginException {
      throw const AdError(
        AdErrorCode.internal,
        'the adfacten_ads plugin is not available on this platform',
      );
    }
  }

  void _invokeQuietly(String method, Map<String, Object?> args) {
    invoke<void>(method, args).catchError((Object _) {});
  }

  void disposeNative(int id) => _invokeQuietly('disposeAd', {'adId': id});

  Future<Object?> _onNativeCall(MethodCall call) async {
    if (call.method != 'onAdEvent') return null;
    final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
    final id = (args['adId'] as num?)?.toInt();
    final event = args['event'] as String?;
    if (id == null || event == null) return null;
    final target = _strong[id] ?? _weak[id]?.target;
    if (target == null) return null;
    try {
      target.handleAdEvent(event, args);
    } catch (e, st) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'adfacten_ads',
          context: ErrorDescription('while handling the ad event "$event"'),
        ),
      );
    }
    return null;
  }
}
