import 'package:flutter/material.dart';

import 'ad_error.dart';
import 'platform.dart';
import 'platform_view.dart';

/// Events of a [NativeAd] shown in an [AdfactenNativeAdView].
class NativeAdListener {
  const NativeAdListener({this.onShown, this.onClicked});

  /// The ad is on screen (the impression was recorded).
  final VoidCallback? onShown;
  final VoidCallback? onClicked;
}

/// A loaded native ad.
///
/// Show it with [AdfactenNativeAdView]. The view is rendered natively from a
/// template, so the native SDK can measure it on screen and handle taps;
/// that is what records impressions and clicks. The asset getters are here so
/// you can decide how to lay out the slot (for example skip the medium
/// template when there is no image). An ad drawn with your own Flutter
/// widgets is not tracked and earns nothing.
///
/// Call [dispose] when you no longer need the ad.
class NativeAd implements AdEventTarget {
  NativeAd._(this._id, this.placementId, Map<Object?, Object?> assets)
    : title = _text(assets['title']),
      body = _text(assets['body']),
      brand = _text(assets['brand']),
      callToAction = _text(assets['callToAction']),
      adLabel = _text(assets['adLabel']) ?? 'Ad',
      imageUrl = _text(assets['imageUrl']),
      iconUrl = _text(assets['iconUrl']),
      imageWidth = (assets['imageWidth'] as num?)?.toDouble() ?? 0,
      imageHeight = (assets['imageHeight'] as num?)?.toDouble() ?? 0,
      hasImage = assets['hasImage'] == true,
      hasIcon = assets['hasIcon'] == true;

  final int _id;
  final String placementId;

  final String? title;
  final String? body;

  /// The advertiser or brand name.
  final String? brand;
  final String? callToAction;

  /// The disclosure text the view shows, e.g. "Ad" or "Reklam".
  final String adLabel;
  final String? imageUrl;
  final String? iconUrl;

  /// Main image size in pixels as sent by the server, or 0 when unknown.
  final double imageWidth;
  final double imageHeight;

  /// Whether the main image / icon was downloaded and will be shown.
  final bool hasImage;
  final bool hasIcon;

  NativeAdListener? listener;

  bool _disposed = false;
  final ValueNotifier<double?> _measuredHeight = ValueNotifier(null);

  bool get isDisposed => _disposed;

  /// Width / height of the main image; 1.91 when unknown.
  double get imageAspectRatio {
    if (imageWidth > 0 && imageHeight > 0) {
      return (imageWidth / imageHeight).clamp(0.5, 4.0);
    }
    return 1.91;
  }

  static String? _text(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  /// Loads a native ad; its images are downloaded before the future
  /// completes. Throws [AdError] when no ad could be loaded.
  static Future<NativeAd> load(
    String placementId, {
    NativeAdListener? listener,
  }) async {
    final placement = placementId.trim();
    if (placement.isEmpty) {
      throw const AdError(AdErrorCode.invalidRequest, 'placementId is empty');
    }
    final platform = AdfactenPlatform.instance;
    final id = platform.newAdId();
    final result = await platform.invoke<Map<Object?, Object?>>('loadAd', {
      'adId': id,
      'format': 'native',
      'placementId': placement,
    });
    final ad = NativeAd._(id, placement, result ?? const {})
      ..listener = listener;
    platform.register(id, ad);
    return ad;
  }

  /// Unbinds the ad from its view and releases it. Safe to call twice.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final platform = AdfactenPlatform.instance;
    platform.unregister(_id, this);
    platform.disposeNative(_id);
  }

  @override
  void handleAdEvent(String event, Map<Object?, Object?> args) {
    if (_disposed) return;
    switch (event) {
      case 'shown':
        listener?.onShown?.call();
      case 'clicked':
        listener?.onClicked?.call();
      case 'measured':
        final h = (args['height'] as num?)?.toDouble();
        if (h != null && h > 0) _measuredHeight.value = h;
    }
  }
}

/// Layouts of [AdfactenNativeAdView].
enum NativeAdTemplate {
  /// A row: icon (or a square crop of the image), title, brand, body and a
  /// compact call-to-action button. About 90 logical pixels high. Fits lists.
  small,

  /// A card: icon, title and brand, the main image at its aspect ratio, body
  /// and a full-width call-to-action button.
  medium,
}

/// Colors and shape of an [AdfactenNativeAdView]. Unset values come from
/// the ambient [Theme].
@immutable
class NativeAdStyle {
  const NativeAdStyle({
    this.backgroundColor,
    this.titleColor,
    this.bodyColor,
    this.brandColor,
    this.callToActionBackgroundColor,
    this.callToActionTextColor,
    this.adLabelBackgroundColor,
    this.adLabelTextColor,
    this.cornerRadius,
    this.callToActionCornerRadius,
  });

  final Color? backgroundColor;
  final Color? titleColor;
  final Color? bodyColor;
  final Color? brandColor;
  final Color? callToActionBackgroundColor;
  final Color? callToActionTextColor;
  final Color? adLabelBackgroundColor;
  final Color? adLabelTextColor;
  final double? cornerRadius;
  final double? callToActionCornerRadius;

  /// Fills unset values from [theme].
  NativeAdStyle resolve(ThemeData theme) {
    final c = theme.colorScheme;
    return NativeAdStyle(
      backgroundColor: backgroundColor ?? c.surfaceContainerLow,
      titleColor: titleColor ?? c.onSurface,
      bodyColor: bodyColor ?? c.onSurfaceVariant,
      brandColor: brandColor ?? c.onSurfaceVariant,
      callToActionBackgroundColor: callToActionBackgroundColor ?? c.primary,
      callToActionTextColor: callToActionTextColor ?? c.onPrimary,
      adLabelBackgroundColor: adLabelBackgroundColor ?? c.tertiaryContainer,
      adLabelTextColor: adLabelTextColor ?? c.onTertiaryContainer,
      cornerRadius: cornerRadius ?? 12,
      callToActionCornerRadius: callToActionCornerRadius ?? 20,
    );
  }

  Map<String, Object?> toMap() => {
    'backgroundColor': backgroundColor?.toARGB32(),
    'titleColor': titleColor?.toARGB32(),
    'bodyColor': bodyColor?.toARGB32(),
    'brandColor': brandColor?.toARGB32(),
    'callToActionBackgroundColor': callToActionBackgroundColor?.toARGB32(),
    'callToActionTextColor': callToActionTextColor?.toARGB32(),
    'adLabelBackgroundColor': adLabelBackgroundColor?.toARGB32(),
    'adLabelTextColor': adLabelTextColor?.toARGB32(),
    'cornerRadius': cornerRadius,
    'callToActionCornerRadius': callToActionCornerRadius,
  };

  @override
  bool operator ==(Object other) =>
      other is NativeAdStyle &&
      other.backgroundColor == backgroundColor &&
      other.titleColor == titleColor &&
      other.bodyColor == bodyColor &&
      other.brandColor == brandColor &&
      other.callToActionBackgroundColor == callToActionBackgroundColor &&
      other.callToActionTextColor == callToActionTextColor &&
      other.adLabelBackgroundColor == adLabelBackgroundColor &&
      other.adLabelTextColor == adLabelTextColor &&
      other.cornerRadius == cornerRadius &&
      other.callToActionCornerRadius == callToActionCornerRadius;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    titleColor,
    bodyColor,
    brandColor,
    callToActionBackgroundColor,
    callToActionTextColor,
    adLabelBackgroundColor,
    adLabelTextColor,
    cornerRadius,
    callToActionCornerRadius,
  );
}

/// Shows a [NativeAd] in a native template.
///
/// ```dart
/// AdfactenNativeAdView(ad: nativeAd, template: NativeAdTemplate.medium)
/// ```
///
/// The widget fills the available width; its height follows the content,
/// measured on the native side. One ad can be shown in one view at a time.
/// Disposing the widget does not dispose the ad.
class AdfactenNativeAdView extends StatelessWidget {
  const AdfactenNativeAdView({
    super.key,
    required this.ad,
    this.template = NativeAdTemplate.medium,
    this.style,
  });

  final NativeAd ad;
  final NativeAdTemplate template;
  final NativeAdStyle? style;

  double _estimate(double width) {
    switch (template) {
      case NativeAdTemplate.small:
        return 92;
      case NativeAdTemplate.medium:
        final image = ad.hasImage ? (width - 24) / ad.imageAspectRatio : 0;
        return image + 196;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ad.isDisposed) return const SizedBox.shrink();
    final resolved = (style ?? const NativeAdStyle()).resolve(
      Theme.of(context),
    );
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return ValueListenableBuilder<double?>(
          valueListenable: ad._measuredHeight,
          builder: (context, measured, child) => SizedBox(
            width: width,
            height: measured ?? _estimate(width) * textScale,
            child: child,
          ),
          child: AdPlatformView(
            key: ValueKey(Object.hash(ad._id, template, resolved)),
            viewType: AdfactenPlatform.nativeViewType,
            creationParams: {
              'adId': ad._id,
              'template': template.name,
              'width': width,
              'style': resolved.toMap(),
            },
          ),
        );
      },
    );
  }
}
