import 'dart:io';

import 'package:adfacten_ads/adfacten_ads.dart';
import 'package:adfacten_ads/src/platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake native side: records calls and answers them like the plugins do.
class FakeNative {
  final List<MethodCall> calls = [];
  final Map<String, Object? Function(MethodCall call)> answers = {};

  List<String> get methods =>
      calls.map((c) => c.method).where((m) => m != 'reset').toList();

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    final answer = answers[call.method];
    return answer == null ? null : answer(call);
  }

  /// Delivers a native event to Dart, as the plugins do with `onAdEvent`.
  Future<void> emit(int adId, String event, [Map<String, Object?>? extra]) {
    const codec = StandardMethodCodec();
    final data = codec.encodeMethodCall(
      MethodCall('onAdEvent', {'adId': adId, 'event': event, ...?extra}),
    );
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(AdfactenPlatform.channelName, data, (_) {});
  }

  int lastAdId(String method) =>
      (calls.lastWhere((c) => c.method == method).arguments as Map)['adId']
          as int;
}

PlatformException platformError(
  String code, [
  String message = 'failed',
  String? serverCode,
  int? nativeCode,
]) => PlatformException(
  code: code,
  message: message,
  details: {'serverCode': serverCode, 'nativeCode': nativeCode},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;

  setUp(() {
    AdfactenPlatform.resetForTesting();
    native = FakeNative();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(AdfactenPlatform.channelName),
          native.handle,
        );
    // Touch the singleton so it installs its event handler after the mock.
    AdfactenPlatform.instance;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(AdfactenPlatform.channelName),
          null,
        );
  });

  group('Adfacten', () {
    test('pluginVersion matches pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec)?.group(1);
      expect(Adfacten.pluginVersion, version);
    });

    test(
      'initialize sends the key and config after resetting stale ads',
      () async {
        await Adfacten.initialize(
          ' apk_test ',
          config: const AdfactenConfig(
            testMode: true,
            logLevel: LogLevel.debug,
            childDirected: true,
            userId: 'u1',
          ),
        );
        expect(native.calls.first.method, 'reset');
        final call = native.calls[1];
        expect(call.method, 'initialize');
        expect(call.arguments, {
          'appKey': 'apk_test',
          'testMode': true,
          'logLevel': 'debug',
          'childDirected': true,
          'userId': 'u1',
          'pluginVersion': Adfacten.pluginVersion,
        });
      },
    );

    test('reset is sent only once per isolate', () async {
      await Adfacten.setUserId('a');
      await Adfacten.setUserId(null);
      expect(native.calls.where((c) => c.method == 'reset'), hasLength(1));
      expect(native.calls.last.arguments, {'userId': null});
    });

    test('version and state come from the native SDK', () async {
      native.answers['sdkVersion'] = (_) => '1.0.0';
      native.answers['isInitialized'] = (_) => true;
      expect(await Adfacten.nativeSdkVersion(), '1.0.0');
      expect(await Adfacten.isInitialized(), isTrue);
    });
  });

  group('AdError', () {
    test('maps platform exceptions', () {
      final e = AdError.fromPlatformException(
        platformError('rejected', 'nope', 'placement_mismatch', 7),
      );
      expect(e.code, AdErrorCode.rejected);
      expect(e.message, 'nope');
      expect(e.serverCode, 'placement_mismatch');
      expect(e.nativeCode, 7);
      expect(e.name, 'rejected');
      expect(e.toString(), contains('placement_mismatch'));
    });

    test('unknown codes become internal', () {
      expect(AdErrorCode.fromWire('somethingNew'), AdErrorCode.internal);
      expect(AdError.fromMap(null).code, AdErrorCode.internal);
      expect(AdError.fromMap(null).name, 'internal_error');
      final e = AdError.fromMap({'code': 'something_new', 'message': 'x'});
      expect(e.code, AdErrorCode.internal);
      expect(e.name, 'something_new');
    });

    test('every native error name maps to a code', () {
      const expected = {
        'internal_error': AdErrorCode.internal,
        'not_initialized': AdErrorCode.notInitialized,
        'invalid_request': AdErrorCode.invalidRequest,
        'network_error': AdErrorCode.network,
        'no_fill': AdErrorCode.noFill,
        'server_error': AdErrorCode.serverError,
        'invalid_response': AdErrorCode.invalidResponse,
        'rejected': AdErrorCode.rejected,
        'ad_expired': AdErrorCode.expired,
        'already_shown': AdErrorCode.alreadyShown,
        'not_ready': AdErrorCode.alreadyShown,
        'show_failed': AdErrorCode.showFailed,
        'video_not_supported': AdErrorCode.videoNotSupported,
        'load_in_progress': AdErrorCode.loadInProgress,
        'child_directed': AdErrorCode.childDirected,
        'creative_failed': AdErrorCode.creativeFailed,
      };
      expected.forEach((name, code) {
        final e = AdError.fromMap({'code': name, 'message': 'm'});
        expect(e.code, code, reason: name);
        expect(e.name, name);
      });
    });

    test('a COPPA rejection keeps its name and reads as childDirected', () {
      final e = AdError.fromPlatformException(
        platformError('rejected', 'coppa', 'coppa', 7),
      );
      expect(e.code, AdErrorCode.childDirected);
      expect(e.name, 'rejected');
    });

    test('older camelCase codes are still understood', () {
      expect(AdErrorCode.fromWire('noFill'), AdErrorCode.noFill);
      expect(AdErrorCode.fromWire('showFailed'), AdErrorCode.showFailed);
    });

    test('plugin errors use the name of their code', () {
      const e = AdError(AdErrorCode.disposed, 'gone');
      expect(e.name, 'disposed');
      expect(e.toString(), 'AdError(disposed: gone)');
    });
  });

  group('InterstitialAd', () {
    test('load passes the placement and returns an ad', () async {
      final ad = await InterstitialAd.load('plc_i');
      final call = native.calls.last;
      expect(call.method, 'loadAd');
      expect((call.arguments as Map)['format'], 'interstitial');
      expect((call.arguments as Map)['placementId'], 'plc_i');
      expect(ad.placementId, 'plc_i');
      expect(ad.isDisposed, isFalse);
    });

    test('load failure throws AdError with the server code', () async {
      native.answers['loadAd'] = (_) =>
          throw platformError('no_fill', 'no ad', null, 4);
      await expectLater(
        InterstitialAd.load('plc_i'),
        throwsA(
          isA<AdError>()
              .having((e) => e.code, 'code', AdErrorCode.noFill)
              .having((e) => e.nativeCode, 'nativeCode', 4),
        ),
      );
    });

    test('an empty placement fails without a native call', () async {
      await expectLater(
        InterstitialAd.load('  '),
        throwsA(
          isA<AdError>().having(
            (e) => e.code,
            'code',
            AdErrorCode.invalidRequest,
          ),
        ),
      );
      expect(native.methods, isEmpty);
    });

    test('show events reach the listener; close disposes the ad', () async {
      final ad = await InterstitialAd.load('plc_i');
      final id = native.lastAdId('loadAd');
      final events = <String>[];
      ad.listener = FullScreenAdListener(
        onShown: () => events.add('shown'),
        onClicked: () => events.add('clicked'),
        onClosed: () => events.add('closed'),
      );
      await ad.show();
      expect(native.calls.last.method, 'showAd');
      await native.emit(id, 'shown');
      await native.emit(id, 'clicked');
      await native.emit(id, 'closed');
      expect(events, ['shown', 'clicked', 'closed']);
      expect(ad.isDisposed, isTrue);
      expect(native.calls.last.method, 'disposeAd');
      expect(AdfactenPlatform.instance.isRegistered(id), isFalse);

      // Events after close are ignored.
      await native.emit(id, 'clicked');
      expect(events, hasLength(3));
    });

    test('showing a closed ad reports alreadyShown', () async {
      final ad = await InterstitialAd.load('plc_i');
      final id = native.lastAdId('loadAd');
      await ad.show();
      await native.emit(id, 'closed');
      AdError? error;
      ad.listener = FullScreenAdListener(onFailedToShow: (e) => error = e);
      await ad.show();
      await Future<void>.delayed(Duration.zero);
      expect(error?.code, AdErrorCode.alreadyShown);
      expect(native.calls.where((c) => c.method == 'showAd'), hasLength(1));
    });

    test('native show errors go to onFailedToShow', () async {
      final ad = await InterstitialAd.load('plc_i');
      native.answers['showAd'] = (_) =>
          throw platformError('show_failed', 'no activity');
      AdError? error;
      ad.listener = FullScreenAdListener(onFailedToShow: (e) => error = e);
      await ad.show();
      expect(error?.code, AdErrorCode.showFailed);
      expect(ad.isDisposed, isFalse);
    });

    test('failedToShow events carry the error', () async {
      final ad = await InterstitialAd.load('plc_i');
      final id = native.lastAdId('loadAd');
      AdError? error;
      ad.listener = FullScreenAdListener(onFailedToShow: (e) => error = e);
      await ad.show();
      await native.emit(id, 'failedToShow', {
        'error': {
          'code': 'ad_expired',
          'message': 'the ad expired',
          'serverCode': null,
          'nativeCode': 8,
        },
      });
      expect(error?.code, AdErrorCode.expired);
      expect(error?.nativeCode, 8);
    });

    test('dispose releases the native ad once', () async {
      final ad = await InterstitialAd.load('plc_i');
      final id = native.lastAdId('loadAd');
      ad.dispose();
      ad.dispose();
      await Future<void>.delayed(Duration.zero);
      final disposes = native.calls.where((c) => c.method == 'disposeAd');
      expect(disposes, hasLength(1));
      expect((disposes.single.arguments as Map)['adId'], id);
      expect(await ad.isReady(), isFalse);
    });

    test('isReady asks the native side', () async {
      final ad = await InterstitialAd.load('plc_i');
      native.answers['isAdReady'] = (_) => true;
      expect(await ad.isReady(), isTrue);
    });

    test('each ad gets its own id', () async {
      await InterstitialAd.load('plc_a');
      final a = native.lastAdId('loadAd');
      await AppOpenAd.load('plc_b');
      final b = native.lastAdId('loadAd');
      expect(a, isNot(b));
      expect((native.calls.last.arguments as Map)['format'], 'appOpen');
    });
  });

  group('RewardedAd', () {
    test('load sends custom data and reads the reward', () async {
      native.answers['loadAd'] = (_) => {
        'reward': {'type': 'coins', 'amount': 10},
      };
      final ad = await RewardedAd.load('plc_r', customData: 'level=3');
      final args = native.calls.last.arguments as Map;
      expect(args['format'], 'rewarded');
      expect(args['customData'], 'level=3');
      expect(ad.reward, const AdReward('coins', 10));
    });

    test('a missing reward is null', () async {
      native.answers['loadAd'] = (_) => {'reward': null};
      final ad = await RewardedAd.load('plc_r');
      expect(ad.reward, isNull);
    });

    test('the reward event calls onUserEarnedReward', () async {
      final ad = await RewardedAd.load('plc_r');
      final id = native.lastAdId('loadAd');
      AdReward? earned;
      await ad.show(onUserEarnedReward: (r) => earned = r);
      await native.emit(id, 'reward', {
        'reward': {'type': 'gems', 'amount': 2.5},
      });
      expect(earned, const AdReward('gems', 2.5));
    });
  });

  group('memory', () {
    test('an ad on screen stays registered while the app drops it', () async {
      var ad = await InterstitialAd.load('plc_i') as InterstitialAd?;
      final id = native.lastAdId('loadAd');
      var closed = false;
      ad!.listener = FullScreenAdListener(onClosed: () => closed = true);
      await ad.show();
      ad = null;
      // Pinned while showing: the close still arrives.
      await native.emit(id, 'closed');
      expect(closed, isTrue);
    });
  });

  group('NativeAd', () {
    Map<String, Object?> assets() => {
      'title': 'Title',
      'body': '  ',
      'brand': 'Brand',
      'callToAction': 'Install',
      'adLabel': 'Ad',
      'imageUrl': 'https://example.com/i.png',
      'iconUrl': null,
      'imageWidth': 1200,
      'imageHeight': 600,
      'hasImage': true,
      'hasIcon': false,
    };

    test('load exposes the assets', () async {
      native.answers['loadAd'] = (_) => assets();
      final ad = await NativeAd.load('plc_n');
      expect((native.calls.last.arguments as Map)['format'], 'native');
      expect(ad.title, 'Title');
      expect(ad.body, isNull, reason: 'blank text is null');
      expect(ad.brand, 'Brand');
      expect(ad.callToAction, 'Install');
      expect(ad.iconUrl, isNull);
      expect(ad.imageAspectRatio, 2.0);
      expect(ad.hasImage, isTrue);
      expect(ad.hasIcon, isFalse);
    });

    test('events reach the listener until disposed', () async {
      native.answers['loadAd'] = (_) => assets();
      var shown = 0;
      var clicked = 0;
      final ad = await NativeAd.load(
        'plc_n',
        listener: NativeAdListener(
          onShown: () => shown++,
          onClicked: () => clicked++,
        ),
      );
      final id = native.lastAdId('loadAd');
      await native.emit(id, 'shown');
      await native.emit(id, 'clicked');
      ad.dispose();
      await native.emit(id, 'clicked');
      expect(shown, 1);
      expect(clicked, 1);
      expect(native.calls.last.method, 'disposeAd');
    });

    testWidgets('the view sends template and style and follows the height', (
      tester,
    ) async {
      native.answers['loadAd'] = (_) => assets();
      final ad = await NativeAd.load('plc_n');
      final id = native.lastAdId('loadAd');

      final created = <Map<Object?, Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (call) async {
          if (call.method == 'create') {
            final args = call.arguments as Map;
            final params = args['params'] as Uint8List?;
            if (params != null) {
              created.add(
                const StandardMessageCodec().decodeMessage(
                      ByteData.sublistView(params),
                    )
                    as Map,
              );
            }
          }
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 320,
              child: AdfactenNativeAdView(
                ad: ad,
                template: NativeAdTemplate.small,
                style: const NativeAdStyle(titleColor: Color(0xFF112233)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(created, hasLength(1));
      expect(created.single['adId'], id);
      expect(created.single['template'], 'small');
      expect(created.single['width'], 320.0);
      expect((created.single['style'] as Map)['titleColor'], 0xFF112233);
      expect((created.single['style'] as Map)['cornerRadius'], 12.0);

      expect(tester.getSize(find.byType(AdfactenNativeAdView)).height, 92);
      await native.emit(id, 'measured', {'height': 101.5});
      await tester.pump();
      expect(tester.getSize(find.byType(AdfactenNativeAdView)).height, 101.5);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  group('AdfactenBanner', () {
    testWidgets('has the ad size and forwards events', (tester) async {
      final created = <Map<Object?, Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (call) async {
          if (call.method == 'create') {
            final args = call.arguments as Map;
            created.add(
              const StandardMessageCodec().decodeMessage(
                    ByteData.sublistView(args['params'] as Uint8List),
                  )
                  as Map,
            );
          }
          return null;
        },
      );
      final events = <String>[];
      AdError? failure;
      await tester.pumpWidget(
        Center(
          child: AdfactenBanner(
            placementId: 'plc_b',
            size: AdSize.mediumRectangle,
            onLoaded: () => events.add('loaded'),
            onShown: () => events.add('shown'),
            onClicked: () => events.add('clicked'),
            onFailedToLoad: (e) => failure = e,
          ),
        ),
      );
      await tester.pump();
      expect(tester.getSize(find.byType(AdfactenBanner)), const Size(300, 250));
      expect(created.single['placementId'], 'plc_b');
      expect(created.single['size'], 'mediumRectangle');
      final id = created.single['adId'] as int;

      await native.emit(id, 'loaded');
      await native.emit(id, 'shown');
      await native.emit(id, 'clicked');
      await native.emit(id, 'failedToLoad', {
        'error': {'code': 'no_fill', 'message': 'no ad'},
      });
      expect(events, ['loaded', 'shown', 'clicked']);
      expect(failure?.code, AdErrorCode.noFill);

      // Removing the widget stops the events.
      await tester.pumpWidget(const SizedBox());
      expect(AdfactenPlatform.instance.isRegistered(id), isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('changing the size creates a new banner', (tester) async {
      final ids = <int>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (call) async {
          if (call.method == 'create') {
            final args = call.arguments as Map;
            final params =
                const StandardMessageCodec().decodeMessage(
                      ByteData.sublistView(args['params'] as Uint8List),
                    )
                    as Map;
            ids.add(params['adId'] as int);
          }
          return null;
        },
      );
      await tester.pumpWidget(
        const Center(child: AdfactenBanner(placementId: 'plc_b')),
      );
      await tester.pumpWidget(
        const Center(
          child: AdfactenBanner(placementId: 'plc_b', size: AdSize.largeBanner),
        ),
      );
      await tester.pump();
      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(2));
      expect(tester.getSize(find.byType(AdfactenBanner)), const Size(320, 100));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });
}
