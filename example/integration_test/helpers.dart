import 'package:adfacten_ads/adfacten_ads.dart';
import 'package:adfacten_ads_example/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// These tests talk to the production ad server with the public test apps,
/// which always return unbilled test ads. Each full-screen format is in its
/// own file: an ad on screen cannot be closed from a test, and only one
/// Adfacten ad can be on screen at a time.
final AdConfig config = AdConfig.current;

/// Lets the app render normally, like a real run, so platform views appear
/// and the SDK can see them on screen.
void setUpBinding() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
}

Future<void> initAds() => Adfacten.initialize(
  config.appKey,
  config: const AdfactenConfig(testMode: true, logLevel: LogLevel.debug),
);

/// Waits for [done] in real time. Frames run on their own (see [setUpBinding]);
/// waiting on `tester.pump` would hang while a full-screen ad covers the
/// Flutter view, because no frames are produced then.
Future<T> pumpUntil<T>(
  WidgetTester tester,
  Future<T> done, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  var finished = false;
  done.then((_) => finished = true, onError: (Object _) => finished = true);
  final end = DateTime.now().add(timeout);
  while (!finished && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (!finished) fail('timed out after $timeout');
  return done;
}

Widget host(Widget child) => MaterialApp(
  home: Scaffold(
    body: SafeArea(child: Center(child: child)),
  ),
);
