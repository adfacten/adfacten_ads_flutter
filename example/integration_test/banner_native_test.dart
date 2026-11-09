import 'dart:async';

import 'package:adfacten_ads/adfacten_ads.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  setUpBinding();

  setUpAll(initAds);

  testWidgets('banner loads and records an impression', (tester) async {
    final loaded = Completer<void>();
    final shown = Completer<void>();
    await tester.pumpWidget(
      host(
        AdfactenBanner(
          placementId: config.banner,
          size: AdSize.mediumRectangle,
          onLoaded: () => loaded.isCompleted ? null : loaded.complete(),
          onFailedToLoad: (e) =>
              loaded.isCompleted ? null : loaded.completeError(e),
          onShown: () => shown.isCompleted ? null : shown.complete(),
        ),
      ),
    );
    await pumpUntil(tester, loaded.future);
    await pumpUntil(tester, shown.future);
    expect(tester.getSize(find.byType(AdfactenBanner)), const Size(300, 250));
  });

  for (final template in NativeAdTemplate.values) {
    testWidgets(
      'native ad loads and records an impression (${template.name})',
      (tester) async {
        final shown = Completer<void>();
        final ad = await pumpUntil(
          tester,
          NativeAd.load(
            config.native,
            listener: NativeAdListener(onShown: shown.complete),
          ),
        );
        expect(ad.title, isNotNull);
        expect(ad.adLabel, isNotEmpty);
        await tester.pumpWidget(
          host(
            SizedBox(
              width: 360,
              child: AdfactenNativeAdView(ad: ad, template: template),
            ),
          ),
        );
        await pumpUntil(tester, shown.future);
        // The height follows the native layout.
        final height = tester.getSize(find.byType(AdfactenNativeAdView)).height;
        expect(height, greaterThan(40));
        debugPrint('native ${template.name}: "${ad.title}" height=$height');
        ad.dispose();
      },
    );
  }
}
