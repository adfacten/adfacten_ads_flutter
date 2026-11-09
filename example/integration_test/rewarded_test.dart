import 'dart:async';

import 'package:adfacten_ads/adfacten_ads.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  setUpBinding();

  testWidgets('rewarded loads, shows and grants the reward', (tester) async {
    await initAds();
    await Adfacten.setUserId('integration-test');
    await tester.pumpWidget(host(const SizedBox()));
    final ad = await pumpUntil(
      tester,
      RewardedAd.load(config.rewarded, customData: 'integration'),
    );
    debugPrint('rewarded: placement reward ${ad.reward}');
    final shown = Completer<void>();
    final earned = Completer<AdReward>();
    ad.listener = FullScreenAdListener(
      onShown: shown.complete,
      onFailedToShow: shown.completeError,
    );
    await ad.show(onUserEarnedReward: earned.complete);
    await pumpUntil(tester, shown.future);
    // The test creative is a 5 s video; the reward follows its end.
    final reward = await pumpUntil(
      tester,
      earned.future,
      timeout: const Duration(seconds: 40),
    );
    debugPrint('rewarded: earned $reward');
    expect(reward.amount, greaterThan(0));
  });
}
