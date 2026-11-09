import 'dart:async';

import 'package:adfacten_ads/adfacten_ads.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  setUpBinding();

  testWidgets('interstitial loads and shows', (tester) async {
    await initAds();
    await tester.pumpWidget(host(const SizedBox()));
    final ad = await pumpUntil(
      tester,
      InterstitialAd.load(config.interstitial),
    );
    expect(await ad.isReady(), isTrue);
    final shown = Completer<void>();
    ad.listener = FullScreenAdListener(
      onShown: shown.complete,
      onFailedToShow: shown.completeError,
    );
    await ad.show();
    await pumpUntil(tester, shown.future);
    expect(await ad.isReady(), isFalse);
  });
}
