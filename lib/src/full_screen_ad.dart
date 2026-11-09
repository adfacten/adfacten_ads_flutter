import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ad_error.dart';
import 'platform.dart';

/// The reward configured on a rewarded placement, e.g. 10 `coins`.
///
/// For UI only. Credit the user from the signed server-side reward callback,
/// never from the client.
@immutable
class AdReward {
  const AdReward(this.type, this.amount);

  final String type;
  final num amount;

  static AdReward? fromMap(Object? map) {
    if (map is! Map) return null;
    final type = map['type'];
    final amount = map['amount'];
    if (type is! String || amount is! num) return null;
    return AdReward(type, amount);
  }

  @override
  bool operator ==(Object other) =>
      other is AdReward && other.type == type && other.amount == amount;

  @override
  int get hashCode => Object.hash(type, amount);

  @override
  String toString() => 'AdReward($amount $type)';
}

/// Events of an interstitial, rewarded or app-open ad.
class FullScreenAdListener {
  const FullScreenAdListener({
    this.onShown,
    this.onClicked,
    this.onClosed,
    this.onFailedToShow,
  });

  /// The ad is on screen (the impression was recorded).
  final VoidCallback? onShown;

  final VoidCallback? onClicked;

  /// The ad was dismissed. Resume your app here and load the next ad.
  final VoidCallback? onClosed;

  /// `show()` could not present the ad. Unless the code is
  /// [AdErrorCode.showFailed] (another ad on screen, app in the background),
  /// the ad cannot be used any more: dispose it and load a new one.
  final void Function(AdError error)? onFailedToShow;
}

/// Base class of [InterstitialAd], [RewardedAd] and [AppOpenAd].
///
/// A loaded ad can be shown once and is valid for about 55 minutes. After
/// `onClosed` it is disposed automatically. Call [dispose] if you drop an ad
/// without showing it; an ad that is garbage collected is released too.
sealed class FullScreenAd implements AdEventTarget {
  FullScreenAd._(this._id, this.placementId);

  final int _id;

  /// The placement (`plc_...`) this ad was loaded for.
  final String placementId;

  /// Show events. Set it before calling `show`.
  FullScreenAdListener? listener;

  bool _disposed = false;
  bool _closed = false;
  void Function(AdReward reward)? _onReward;

  /// True after [dispose] or after the ad was closed.
  bool get isDisposed => _disposed;

  /// Whether the ad can be shown now (loaded, not shown, not expired).
  Future<bool> isReady() async {
    if (_disposed) return false;
    try {
      return await AdfactenPlatform.instance.invoke<bool>('isAdReady', {
            'adId': _id,
          }) ??
          false;
    } on AdError {
      return false;
    }
  }

  Future<void> _show(void Function(AdReward reward)? onReward) async {
    if (_disposed) {
      _failLater(
        AdError(
          _closed ? AdErrorCode.alreadyShown : AdErrorCode.disposed,
          _closed
              ? 'this ad was already shown; load a new one'
              : 'the ad was disposed',
        ),
      );
      return;
    }
    final platform = AdfactenPlatform.instance;
    _onReward = onReward;
    platform.pin(_id, this);
    try {
      await platform.invoke<void>('showAd', {'adId': _id});
    } on AdError catch (e) {
      platform.unpin(_id);
      listener?.onFailedToShow?.call(e);
    }
  }

  void _failLater(AdError error) {
    final l = listener;
    scheduleMicrotask(() => l?.onFailedToShow?.call(error));
  }

  /// Releases the native ad. Safe to call more than once. If the ad is on
  /// screen it stays there until the user closes it, but no more events are
  /// delivered.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _onReward = null;
    final platform = AdfactenPlatform.instance;
    platform.unregister(_id, this);
    platform.disposeNative(_id);
  }

  @override
  void handleAdEvent(String event, Map<Object?, Object?> args) {
    if (_disposed) return;
    final l = listener;
    switch (event) {
      case 'shown':
        l?.onShown?.call();
      case 'clicked':
        l?.onClicked?.call();
      case 'reward':
        final reward = AdReward.fromMap(args['reward']);
        if (reward != null) _onReward?.call(reward);
      case 'failedToShow':
        AdfactenPlatform.instance.unpin(_id);
        l?.onFailedToShow?.call(AdError.fromMap(args['error'] as Map?));
      case 'closed':
        _closed = true;
        dispose();
        l?.onClosed?.call();
    }
  }

  static Future<T> _load<T extends FullScreenAd>(
    String format,
    String placementId,
    T Function(int id, Map<Object?, Object?> result) create, {
    String? customData,
  }) async {
    final placement = placementId.trim();
    if (placement.isEmpty) {
      throw const AdError(AdErrorCode.invalidRequest, 'placementId is empty');
    }
    final platform = AdfactenPlatform.instance;
    final id = platform.newAdId();
    final result = await platform.invoke<Map<Object?, Object?>>('loadAd', {
      'adId': id,
      'format': format,
      'placementId': placement,
      'customData': customData,
    });
    final ad = create(id, result ?? const {});
    platform.register(id, ad);
    return ad;
  }
}

/// A full-screen ad shown at natural breaks (between levels, screens).
///
/// ```dart
/// final ad = await InterstitialAd.load('plc_...');
/// ad.listener = FullScreenAdListener(onClosed: resumeGame);
/// await ad.show();
/// ```
class InterstitialAd extends FullScreenAd {
  InterstitialAd._(super.id, super.placementId) : super._();

  /// Loads an interstitial. Throws [AdError] when no ad could be loaded.
  static Future<InterstitialAd> load(String placementId) {
    return FullScreenAd._load(
      'interstitial',
      placementId,
      (id, _) => InterstitialAd._(id, placementId),
    );
  }

  /// Shows the ad full screen. Results arrive through [listener].
  Future<void> show() => _show(null);
}

/// A full-screen ad shown when the app comes to the foreground.
class AppOpenAd extends FullScreenAd {
  AppOpenAd._(super.id, super.placementId) : super._();

  /// Loads an app-open ad. Throws [AdError] when no ad could be loaded.
  static Future<AppOpenAd> load(String placementId) {
    return FullScreenAd._load(
      'appOpen',
      placementId,
      (id, _) => AppOpenAd._(id, placementId),
    );
  }

  Future<void> show() => _show(null);
}

/// A full-screen ad the user opts into in exchange for a reward.
///
/// The reward is granted server side: Adfacten calls your reward callback
/// URL, signed with your reward secret, after a valid completion. The
/// `onUserEarnedReward` callback is for UI only.
class RewardedAd extends FullScreenAd {
  RewardedAd._(super.id, super.placementId, this.reward) : super._();

  /// The reward configured on the placement, or null if the server sent none.
  final AdReward? reward;

  /// Loads a rewarded ad. [customData] (up to 256 characters) is echoed as
  /// `custom` in the server-side reward callback; the user id comes from
  /// [AdfactenConfig.userId] or `Adfacten.setUserId`.
  static Future<RewardedAd> load(String placementId, {String? customData}) {
    return FullScreenAd._load(
      'rewarded',
      placementId,
      (id, result) =>
          RewardedAd._(id, placementId, AdReward.fromMap(result['reward'])),
      customData: customData,
    );
  }

  /// Shows the ad. [onUserEarnedReward] runs once when the user completed it.
  Future<void> show({
    required void Function(AdReward reward) onUserEarnedReward,
  }) => _show(onUserEarnedReward);
}
