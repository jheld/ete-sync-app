import 'dart:io';

import 'package:ete_sync_app/my_home_page.dart';
import 'package:ete_sync_app/util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:timezone/data/latest.dart' as tz;
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  if (!kIsWeb && Platform.isLinux) {
    WidgetsFlutterBinding.ensureInitialized();
    // Must add this line.
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(700, 800),
      center: true,
      //backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: "EteSync Tasks",
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  tz.initializeTimeZones();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EteSync Tasks',
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
                );
              }
            } else {
              return const Scaffold(
                  body: Column(children: [
                Text("Checking for local config data..."),
                CircularProgressIndicator()
              ]));
            }
          }),
      debugShowCheckedModeBanner: false,
    );
  }
}
