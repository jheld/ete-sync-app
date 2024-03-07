import 'dart:io';

import 'package:ete_sync_app/my_home_page.dart';
import 'package:ete_sync_app/util.dart';
import 'package:flutter/material.dart';

import 'package:etebase_flutter/etebase_flutter.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:timezone/data/latest.dart' as tz;

Future<void> main() async {
  await dotenv.load(fileName: "assets/.env");
  tz.initializeTimeZones();
  final client = await getEtebaseClient(); // uses default server
  try {
    await client.checkEtebaseServer();
    runApp(const MyApp());
  } finally {
    await client.dispose();
  }
}

Future<List> getItemManager() async {
  final client = await getEtebaseClient();
  final collUid = getCollectionUIDInCacheDir();

  if (!Directory(cacheDir).existsSync()) {
    return [client, null, collUid];
  }
  late final String username;
  try {
    username = getUsernameInCacheDir();
  } catch (error) {
    return [client, null, collUid];
  }
  final cacheClient =
      await EtebaseFileSystemCache.create(client, cacheDir, username);

  late final EtebaseAccount etebase;
  try {
    etebase = await cacheClient.loadAccount(client);
  } catch (error) {
    return [client, null, collUid];
  }

  final collectionManager = await etebase.getCollectionManager();
  final collection = await collectionManager.fetch(collUid);
  await cacheClient.collectionSet(collectionManager, collection);

  final itemManager = await collectionManager.getItemManager(collection);
  await cacheClient.dispose();
  return [client, itemManager, collUid];
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EteSync Tasks',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a blue toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: FutureBuilder<List>(
          future: getItemManager(),
          builder: (BuildContext context, AsyncSnapshot<List> snapshot) {
            if (snapshot.hasData) {
              if (snapshot.data![1] == null) {
                return AccountLoadPage(client: snapshot.data![0]);
              } else {
                return MyHomePage(
                  title: 'My Tasks',
                  client: snapshot.data![0],
                  itemManager: snapshot.data![1],
                  colUid: snapshot.data![2],
                );
              }
            } else {
              return const CircularProgressIndicator();
            }
          }),
    );
  }
}

class AccountLoadPage extends StatefulWidget {
  const AccountLoadPage({super.key, required this.client});

  final EtebaseClient client;

  @override
  State<StatefulWidget> createState() => _AccountLoadPageState();
}

class _AccountLoadPageState extends State<AccountLoadPage> {
  final _formKey = GlobalKey<FormState>();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(),
        body: Column(children: [
          Form(
              key: _formKey,
              child: Column(children: [
                TextFormField(
                  controller: usernameController,
                ),
                TextFormField(
                  controller: passwordController,
                  obscureText: true,
                ),
                TextButton(
                    onPressed: () async {
                      if (_formKey.currentState!.validate()) {
                        final etebase = await EtebaseAccount.login(
                            this.widget.client,
                            usernameController.text,
                            passwordController.text);

                        final username = getUsernameInCacheDir();

                        final cacheClient = await EtebaseFileSystemCache.create(
                            this.widget.client, cacheDir, username);
                        await cacheClient.saveAccount(etebase);

                        final collUid = getCollectionUIDInCacheDir();
                        final collectionManager =
                            await etebase.getCollectionManager();
                        final collection =
                            await collectionManager.fetch(collUid);
                        await cacheClient.collectionSet(
                            collectionManager, collection);

                        final itemManager =
                            await collectionManager.getItemManager(collection);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (BuildContext context) => MyHomePage(
                                    title: "My Tasks",
                                    itemManager: itemManager,
                                    client: this.widget.client,
                                    colUid: collUid)));
                      }
                    },
                    child: Text("Login"))
              ])),
        ]));
  }
}
