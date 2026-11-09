import 'package:adfacten_ads/adfacten_ads.dart';
import 'package:flutter/widgets.dart';

/// Tracks whether any full-screen ad is on screen. On Android, closing a
/// full-screen ad resumes the Flutter activity, which must not count as the
/// user returning to the app.
abstract final class FullScreenGate {
  static bool open = false;
  static DateTime _closedAt = DateTime.fromMillisecondsSinceEpoch(0);

  static void opened() => open = true;

  static void closed() {
    open = false;
    _closedAt = DateTime.now();
  }

  static bool get recentlyClosed =>
      DateTime.now().difference(_closedAt) < const Duration(seconds: 2);
}

/// Keeps one app-open ad ready and shows it when the app returns from the
/// background.
class AppOpenController {
  AppOpenController(this.placementId);

  final String placementId;
  final ValueNotifier<bool> enabled = ValueNotifier(true);

  AppLifecycleListener? _lifecycle;
  AppOpenAd? _ad;
  bool _loading = false;
  DateTime? _backgroundedAt;

  void start() {
    _lifecycle = AppLifecycleListener(
      onHide: () => _backgroundedAt ??= DateTime.now(),
      onShow: _onForeground,
    );
    _load();
  }

  Future<void> _load() async {
    if (_loading || _ad != null) return;
    _loading = true;
    try {
      _ad = await AppOpenAd.load(placementId);
    } on AdError catch (e) {
      debugPrint('app open: load failed: $e');
    } finally {
      _loading = false;
    }
  }

  Future<void> _onForeground() async {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (!enabled.value ||
        FullScreenGate.open ||
        FullScreenGate.recentlyClosed) {
      return;
    }
    // Ignore short trips, e.g. a permission dialog.
    if (since == null ||
        DateTime.now().difference(since) < const Duration(seconds: 3)) {
      return;
    }
    final ad = _ad;
    if (ad == null || !await ad.isReady()) {
      _ad?.dispose();
      _ad = null;
      _load();
      return;
    }
    _ad = null;
    ad.listener = FullScreenAdListener(
      onClosed: () {
        FullScreenGate.closed();
        _load();
      },
      onFailedToShow: (e) {
        FullScreenGate.closed();
        ad.dispose();
        _load();
      },
    );
    FullScreenGate.opened();
    await ad.show();
  }

  void dispose() {
    _lifecycle?.dispose();
    _ad?.dispose();
    enabled.dispose();
  }
}
