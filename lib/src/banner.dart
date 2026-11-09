import 'package:flutter/widgets.dart';

import 'ad_error.dart';
import 'platform.dart';
import 'platform_view.dart';

/// Standard banner sizes, in logical pixels. Only these sizes are served.
enum AdSize {
  /// 320x50
  banner(320, 50, 'banner'),

  /// 320x100
  largeBanner(320, 100, 'largeBanner'),

  /// 300x250
  mediumRectangle(300, 250, 'mediumRectangle'),

  /// 728x90, for tablets.
  leaderboard(728, 90, 'leaderboard');

  const AdSize(this.width, this.height, this.wire);

  final double width;
  final double height;

  /// The value used on the method channel.
  final String wire;

  Size get size => Size(width, height);
}

/// A banner ad.
///
/// ```dart
/// AdfactenBanner(
///   placementId: 'plc_...',
///   size: AdSize.banner,
///   onFailedToLoad: (error) => setState(() => showBanner = false),
/// )
/// ```
///
/// The widget always takes the size of [size]. It loads when it is first
/// built and refreshes itself on the placement's interval (30 to 120 s of
/// visible time). The impression is counted only once the banner is actually
/// on screen. Removing the widget releases the native banner.
class AdfactenBanner extends StatefulWidget {
  const AdfactenBanner({
    super.key,
    required this.placementId,
    this.size = AdSize.banner,
    this.onLoaded,
    this.onFailedToLoad,
    this.onShown,
    this.onClicked,
  });

  final String placementId;
  final AdSize size;

  /// A creative was loaded (also after each refresh).
  final VoidCallback? onLoaded;

  /// The load failed. After a failed refresh the previous creative stays.
  final void Function(AdError error)? onFailedToLoad;

  /// The creative is on screen (the impression was recorded).
  final VoidCallback? onShown;

  final VoidCallback? onClicked;

  @override
  State<AdfactenBanner> createState() => _AdfactenBannerState();
}

class _AdfactenBannerState extends State<AdfactenBanner>
    implements AdEventTarget {
  late int _id;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    final platform = AdfactenPlatform.instance;
    _id = platform.newAdId();
    platform.register(_id, this, strong: true);
  }

  @override
  void didUpdateWidget(AdfactenBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.placementId != widget.placementId ||
        oldWidget.size != widget.size) {
      AdfactenPlatform.instance.unregister(_id, this);
      _attach();
    }
  }

  @override
  void dispose() {
    AdfactenPlatform.instance.unregister(_id, this);
    super.dispose();
  }

  @override
  void handleAdEvent(String event, Map<Object?, Object?> args) {
    if (!mounted) return;
    switch (event) {
      case 'loaded':
        widget.onLoaded?.call();
      case 'failedToLoad':
        widget.onFailedToLoad?.call(AdError.fromMap(args['error'] as Map?));
      case 'shown':
        widget.onShown?.call();
      case 'clicked':
        widget.onClicked?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size.width,
      height: widget.size.height,
      child: AdPlatformView(
        key: ValueKey(_id),
        viewType: AdfactenPlatform.bannerViewType,
        creationParams: {
          'adId': _id,
          'placementId': widget.placementId.trim(),
          'size': widget.size.wire,
        },
      ),
    );
  }
}
