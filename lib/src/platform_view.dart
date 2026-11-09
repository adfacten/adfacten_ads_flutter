import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Hosts a native ad view.
///
/// Android uses hybrid composition: the native view sits in the real view
/// hierarchy, so the SDK's on-screen (viewability) checks and touch handling
/// see exactly what the user sees.
class AdPlatformView extends StatelessWidget {
  const AdPlatformView({
    super.key,
    required this.viewType,
    required this.creationParams,
  });

  final String viewType;
  final Map<String, Object?> creationParams;

  static const Set<Factory<OneSequenceGestureRecognizer>> _noGestures = {};

  @override
  Widget build(BuildContext context) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return PlatformViewLink(
          viewType: viewType,
          surfaceFactory: (context, controller) => AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: _noGestures,
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          ),
          onCreatePlatformView: (params) {
            return PlatformViewsService.initExpensiveAndroidView(
                id: params.id,
                viewType: viewType,
                layoutDirection:
                    Directionality.maybeOf(context) ?? TextDirection.ltr,
                creationParams: creationParams,
                creationParamsCodec: const StandardMessageCodec(),
                onFocus: () => params.onFocusChanged(true),
              )
              ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
              ..create();
          },
        );
      case TargetPlatform.iOS:
        return UiKitView(
          viewType: viewType,
          layoutDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
