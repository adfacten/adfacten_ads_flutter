import 'dart:async';

import 'package:adfacten_ads/adfacten_ads.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  setUpBinding();

  testWidgets('app-open ad loads and shows; errors carry codes', (
    tester,
  ) async {
    await initAds();
    await tester.pumpWidget(host(const SizedBox()));

    // A placement of another format is rejected by the server.
    await expectLater(
      pumpUntil(tester, AppOpenAd.load(config.banner)),
      throwsA(
        isA<AdError>()
            .having((e) => e.code, 'code', AdErrorCode.rejected)
            .having((e) => e.name, 'name', 'rejected')
            .having((e) => e.serverCode, 'serverCode', 'placement_mismatch'),
      ),
    );

    final ad = await pumpUntil(tester, AppOpenAd.load(config.appOpen));
    final shown = Completer<void>();
    ad.listener = FullScreenAdListener(
      onShown: shown.complete,
      onFailedToShow: shown.completeError,
    );
    await ad.show();
    await pumpUntil(tester, shown.future);

    // A second show of the same ad is refused.
    final second = Completer<AdError>();
    ad.listener = FullScreenAdListener(onFailedToShow: second.complete);
    await ad.show();
    final error = await pumpUntil(tester, second.future);
    expect(error.code, isNot(AdErrorCode.internal));
    expect(error.name, anyOf('already_shown', 'not_ready'));
  });
}
