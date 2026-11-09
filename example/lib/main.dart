import 'package:adfacten_ads/adfacten_ads.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_open.dart';
import 'config.dart';
import 'pages.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Adfacten.initialize(
    AdConfig.current.appKey,
    config: const AdfactenConfig(testMode: true, logLevel: LogLevel.debug),
  );
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final AppOpenController _appOpen = AppOpenController(
    AdConfig.current.appOpen,
  );

  @override
  void initState() {
    super.initState();
    _appOpen.start();
  }

  @override
  void dispose() {
    _appOpen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Adfacten Ads',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2F5BEA)),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF2F5BEA),
        brightness: Brightness.dark,
      ),
      home: HomePage(appOpen: _appOpen),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.appOpen});

  final AppOpenController appOpen;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    Adfacten.nativeSdkVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final config = AdConfig.current;
    return Scaffold(
      appBar: AppBar(title: const Text('Adfacten Ads')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.view_day_outlined),
            title: const Text('Banner'),
            subtitle: const Text('320x50, 320x100, 300x250, 728x90'),
            onTap: () => _open(BannerPage(placementId: config.banner)),
          ),
          ListTile(
            leading: const Icon(Icons.fullscreen),
            title: const Text('Interstitial'),
            onTap: () =>
                _open(FullScreenPage.interstitial(config.interstitial)),
          ),
          ListTile(
            leading: const Icon(Icons.card_giftcard),
            title: const Text('Rewarded'),
            onTap: () => _open(FullScreenPage.rewarded(config.rewarded)),
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('Native'),
            subtitle: const Text('Small and medium templates'),
            onTap: () => _open(NativePage(placementId: config.native)),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('App open'),
            subtitle: const Text('Load and show by hand'),
            onTap: () => _open(FullScreenPage.appOpen(config.appOpen)),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: widget.appOpen.enabled,
            builder: (context, enabled, _) => SwitchListTile(
              secondary: const Icon(Icons.replay),
              title: const Text('App-open ad on return'),
              subtitle: const Text(
                'Shows a preloaded app-open ad when the app comes back '
                'from the background',
              ),
              value: enabled,
              onChanged: (v) => widget.appOpen.enabled.value = v,
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Test mode is on. ${defaultTargetPlatform.name} app key '
              '${config.appKey}. Native SDK $_version.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
