import 'dart:io';

import 'package:ete_sync_app/my_home_page.dart';
import 'package:ete_sync_app/util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:provider/provider.dart';

import 'package:timezone/data/latest.dart' as tz;
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  await setupWindow();
  tz.initializeTimeZones();

  final locale = await getPrefLocale();

  runApp(ChangeNotifierProvider(
      create: (context) => LocaleModel(initialLocale: locale),
      child: const MyApp()));
}

/// Setup Window (for Desktop)
Future<void> setupWindow() async {
  if (!kIsWeb && Platform.isLinux) {
    WidgetsFlutterBinding.ensureInitialized();
    // Must add this line.
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(700, 800),
      center: true,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: "EteSync Tasks",
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<StatefulWidget> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  //Future<Locale> locale = Future.value(Locale(Intl.getCurrentLocale()));

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleModel>(builder: (context, localeModel, child) {
      return MaterialApp(
        title: 'EteSync Tasks',
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: localeModel.locale,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: FutureBuilder<List>(
            future: getItemManager(),
            builder: (BuildContext context, AsyncSnapshot<List> snapshot) {
              if (snapshot.hasData) {
                if (snapshot.data![1] == null) {
                  return AccountLoadPage(
                      client: snapshot.data![0], serverUri: snapshot.data![4]);
                } else {
                  return MyHomePage(
                    title: snapshot.data![3] ?? 'My Tasks',
                    client: snapshot.data![0],
                    itemManager: snapshot.data![1],
                    colUid: snapshot.data![2],
                    colType: snapshot.data![6],
                  );
                }
              } else {
                return InitialLoadingWidget(
                    error:
                        snapshot.hasError ? snapshot.error.toString() : null);
              }
            }),
        debugShowCheckedModeBanner: false,
      );
    });
  }
}

class InitialLoadingWidget extends StatelessWidget {
  const InitialLoadingWidget({
    super.key,
    this.error,
  });

  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('EteSync Task')),
        body: Center(
          child: Column(children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 24.0),
                  child: Text("Checking for local config data..."),
                ),
                if (error != null) Text(error!),
                const CircularProgressIndicator(),
              ],
            )
          ]),
        ));
  }
}
