import 'package:adfacten_ads/adfacten_ads.dart';
import 'package:flutter/material.dart';

import 'app_open.dart';

/// A short list of ad events, newest first.
class EventLog extends ChangeNotifier {
  final List<String> lines = [];

  void add(String line) {
    final t = TimeOfDay.now();
    final stamp =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    debugPrint('adfacten example: $line');
    lines.insert(0, '$stamp  $line');
    if (lines.length > 50) lines.removeLast();
    notifyListeners();
  }
}

class EventLogView extends StatelessWidget {
  const EventLogView({super.key, required this.log});

  final EventLog log;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in log.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(line, key: ValueKey(line), style: style),
            ),
        ],
      ),
    );
  }
}

// Banner

class BannerPage extends StatefulWidget {
  const BannerPage({super.key, required this.placementId});

  final String placementId;

  @override
  State<BannerPage> createState() => _BannerPageState();
}

class _BannerPageState extends State<BannerPage> {
  final EventLog _log = EventLog();
  AdSize _size = AdSize.banner;
  bool _failed = false;

  @override
  void dispose() {
    _log.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fits = MediaQuery.sizeOf(context).width >= _size.width;
    return Scaffold(
      appBar: AppBar(title: const Text('Banner')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<AdSize>(
            segments: const [
              ButtonSegment(value: AdSize.banner, label: Text('320x50')),
              ButtonSegment(value: AdSize.largeBanner, label: Text('320x100')),
              ButtonSegment(
                value: AdSize.mediumRectangle,
                label: Text('300x250'),
              ),
              ButtonSegment(value: AdSize.leaderboard, label: Text('728x90')),
            ],
            selected: {_size},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              _size = s.first;
              _failed = false;
            }),
          ),
          const SizedBox(height: 24),
          if (!fits)
            const Text('728x90 is for tablets; this screen is too narrow.')
          else if (!_failed)
            Center(
              child: AdfactenBanner(
                placementId: widget.placementId,
                size: _size,
                onLoaded: () => _log.add('${_size.wire}: loaded'),
                onFailedToLoad: (e) {
                  _log.add('${_size.wire}: failed: $e');
                  // Collapse the slot instead of leaving an empty box.
                  setState(() => _failed = true);
                },
                onShown: () => _log.add('${_size.wire}: shown (impression)'),
                onClicked: () => _log.add('${_size.wire}: clicked'),
              ),
            )
          else
            Center(
              child: TextButton(
                onPressed: () => setState(() => _failed = false),
                child: const Text('Retry'),
              ),
            ),
          const SizedBox(height: 24),
          EventLogView(log: _log),
        ],
      ),
    );
  }
}

// Interstitial, rewarded, app open

enum _Format { interstitial, rewarded, appOpen }

class FullScreenPage extends StatefulWidget {
  const FullScreenPage._(this._format, this.placementId);

  factory FullScreenPage.interstitial(String placementId) =>
      FullScreenPage._(_Format.interstitial, placementId);

  factory FullScreenPage.rewarded(String placementId) =>
      FullScreenPage._(_Format.rewarded, placementId);

  factory FullScreenPage.appOpen(String placementId) =>
      FullScreenPage._(_Format.appOpen, placementId);

  final _Format _format;
  final String placementId;

  @override
  State<FullScreenPage> createState() => _FullScreenPageState();
}

class _FullScreenPageState extends State<FullScreenPage> {
  final EventLog _log = EventLog();
  FullScreenAd? _ad;
  bool _loading = false;
  int _coins = 0;

  String get _title => switch (widget._format) {
    _Format.interstitial => 'Interstitial',
    _Format.rewarded => 'Rewarded',
    _Format.appOpen => 'App open',
  };

  @override
  void dispose() {
    _ad?.dispose();
    _log.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _log.add('loading...');
    try {
      final FullScreenAd ad = switch (widget._format) {
        _Format.interstitial => await InterstitialAd.load(widget.placementId),
        _Format.rewarded => await RewardedAd.load(
          widget.placementId,
          customData: 'example',
        ),
        _Format.appOpen => await AppOpenAd.load(widget.placementId),
      };
      if (!mounted) {
        ad.dispose();
        return;
      }
      final reward = ad is RewardedAd ? ' (reward: ${ad.reward})' : '';
      _log.add('loaded$reward');
      _ad?.dispose();
      setState(() => _ad = ad);
    } on AdError catch (e) {
      _log.add('load failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _show() async {
    final ad = _ad;
    if (ad == null) return;
    setState(() => _ad = null);
    ad.listener = FullScreenAdListener(
      onShown: () => _log.add('shown (impression)'),
      onClicked: () => _log.add('clicked'),
      onClosed: () {
        FullScreenGate.closed();
        _log.add('closed');
      },
      onFailedToShow: (e) {
        FullScreenGate.closed();
        _log.add('failed to show: $e');
        ad.dispose();
      },
    );
    FullScreenGate.opened();
    switch (ad) {
      case InterstitialAd():
        await ad.show();
      case AppOpenAd():
        await ad.show();
      case RewardedAd():
        await ad.show(
          onUserEarnedReward: (reward) {
            _log.add('earned $reward');
            // UI only. Real apps credit the user from the server callback.
            setState(() => _coins += reward.amount.toInt());
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              FilledButton.tonal(
                onPressed: _loading ? null : _load,
                child: Text(_loading ? 'Loading...' : 'Load'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _ad == null ? null : _show,
                child: const Text('Show'),
              ),
              const Spacer(),
              if (widget._format == _Format.rewarded) Text('Coins: $_coins'),
            ],
          ),
          const SizedBox(height: 24),
          EventLogView(log: _log),
        ],
      ),
    );
  }
}

// Native

class NativePage extends StatefulWidget {
  const NativePage({super.key, required this.placementId});

  final String placementId;

  @override
  State<NativePage> createState() => _NativePageState();
}

class _NativePageState extends State<NativePage> {
  final EventLog _log = EventLog();
  NativeAd? _ad;
  bool _loading = false;
  NativeAdTemplate _template = NativeAdTemplate.medium;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    _log.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _log.add('loading...');
    try {
      final ad = await NativeAd.load(
        widget.placementId,
        listener: NativeAdListener(
          onShown: () => _log.add('shown (impression)'),
          onClicked: () => _log.add('clicked'),
        ),
      );
      if (!mounted) {
        ad.dispose();
        return;
      }
      _log.add('loaded: "${ad.title}" by ${ad.brand ?? '-'}');
      _ad?.dispose();
      setState(() => _ad = ad);
    } on AdError catch (e) {
      _log.add('load failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    return Scaffold(
      appBar: AppBar(title: const Text('Native')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              FilledButton.tonal(
                onPressed: _loading ? null : _load,
                child: Text(_loading ? 'Loading...' : 'Reload'),
              ),
              const SizedBox(width: 12),
              SegmentedButton<NativeAdTemplate>(
                segments: const [
                  ButtonSegment(
                    value: NativeAdTemplate.small,
                    label: Text('Small'),
                  ),
                  ButtonSegment(
                    value: NativeAdTemplate.medium,
                    label: Text('Medium'),
                  ),
                ],
                selected: {_template},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _template = s.first),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _Filler('Your content'),
          const SizedBox(height: 12),
          if (ad != null)
            AdfactenNativeAdView(ad: ad, template: _template)
          else
            const SizedBox(height: 92),
          const SizedBox(height: 12),
          const _Filler('More content'),
          const SizedBox(height: 24),
          EventLogView(log: _log),
        ],
      ),
    );
  }
}

class _Filler extends StatelessWidget {
  const _Filler(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text),
    );
  }
}
