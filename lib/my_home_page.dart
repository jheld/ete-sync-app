import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:auto_direction/auto_direction.dart';
import 'package:enough_icalendar/enough_icalendar.dart';

import 'package:ete_sync_app/etebase_item_route.dart';
import 'package:ete_sync_app/etebase_note_route.dart';
import 'package:ete_sync_app/i_calendar_custom_parser.dart';
import 'package:ete_sync_app/util.dart';
import 'package:etebase_flutter/etebase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rrule/rrule.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:window_manager/window_manager.dart';

class AccountLoadPage extends StatefulWidget {
  const AccountLoadPage({super.key, required this.client, this.serverUri});

  final EtebaseClient client;
  final Uri? serverUri;

  @override
  State<StatefulWidget> createState() => _AccountLoadPageState();
}

class _AccountLoadPageState extends State<AccountLoadPage> {
  final _formKey = GlobalKey<FormState>();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final serverUrlController = TextEditingController();

  final _serverUrlKey = GlobalKey<FormFieldState>();

  @override
  void initState() {
    super.initState();
    serverUrlController.text = widget.serverUri?.toString() ?? "";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(),
        body: Column(children: [
          Form(
              key: _formKey,
              child: Column(children: [
                TextFormField(
                  key: _serverUrlKey,
                  controller: serverUrlController,
                  decoration: const InputDecoration(labelText: "Server URL"),
                  validator: (value) {
                    if (value != null &&
                        value.isNotEmpty &&
                        Uri.tryParse(value) == null) {
                      return "Not a valid URL.";
                    }
                    return null;
                  },
                  onFieldSubmitted: (value) async {
                    await loginValidationSubmit(context);
                  },
                ),
                TextFormField(
                  controller: usernameController,
                  decoration: const InputDecoration(labelText: "Username"),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Must be non-empty";
                    }
                    return null;
                  },
                  onFieldSubmitted: (value) async {
                    await loginValidationSubmit(context);
                  },
                ),
                TextFormField(
                  controller: passwordController,
                  decoration: const InputDecoration(labelText: "Password"),
                  obscureText: true,
                  onFieldSubmitted: (value) async {
                    await loginValidationSubmit(context);
                  },
                ),
                TextButton(
                    onPressed: () async {
                      await loginValidationSubmit(context);
                    },
                    child: const Text("Login"))
              ])),
        ]));
  }

  Future<void> loginValidationSubmit(BuildContext context) async {
    if (_formKey.currentState!.validate()) {
      bool encounteredError = false;
      final client = await EtebaseClient.create(
          "ete_sync_client",
          serverUrlController.text.isNotEmpty
              ? Uri.parse(serverUrlController.text)
              : null);
      late final EtebaseAccount etebase;
      late final String username;
      if (!(await client.checkEtebaseServer())) {
        encounteredError = true;
        _formKey.currentState!.reset();
      } else {
        final Future<SharedPreferences> prefsInstance =
            SharedPreferences.getInstance();
        final SharedPreferences prefs = await prefsInstance;
        await prefs.setString(
            "ete_base_url", Uri.parse(serverUrlController.text).toString());

        //final client = widget.client;
        username = usernameController.text;
        try {
          etebase = await EtebaseAccount.login(
              client, username, passwordController.text);
        } on EtebaseException catch (e) {
          if (kDebugMode) {
            print(e);
          }
          encounteredError = true;
          _formKey.currentState!.reset();

          //if (e.code == EtebaseErrorCode.unauthorized) {}
        }
        await prefs.setString("username", username);
      }

      if (!encounteredError) {
        final cacheDir = await getCacheDir();

        final cacheClient =
            await EtebaseFileSystemCache.create(client, cacheDir, username);
        const secureStorage = FlutterSecureStorage();
        final eteCacheAccountEncryptionValue =
            await EtebaseUtils.randombytes(client, 32);

        await secureStorage.write(
            key: eteCacheAccountEncryptionKeyString,
            value: base64Encode(eteCacheAccountEncryptionValue));

        await cacheClient.saveAccount(etebase, eteCacheAccountEncryptionValue);

        final notesCollectionData = await getCollections(client,
            etebaseAccount: etebase, collectionType: "etebase.md.note");

        final collectionMap =
            await getCollections(client, etebaseAccount: etebase);

        (collectionMap["items"] as Map).addAll(notesCollectionData["items"]);
        if (collectionMap["items"].isEmpty) {
          await etebase.logout();
        } else if (context.mounted) {
          final collectionData = await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (BuildContext context) {
                return Dialog(
                  child: Column(
                      children: (collectionMap["items"]
                              as Map<EtebaseCollection, Map<String, dynamic>>)
                          .values
                          .where((element) => !element["itemIsDeleted"])
                          .map((element) => buildCollectionListTile(
                              element, cacheDir, username, context))
                          .toList()),
                );
              });

          final collUid = collectionData["itemUid"];
          final colType = collectionData["itemCollectionType"] as String;
          final collectionManager = await etebase.getCollectionManager();
          final collection = await collectionManager.fetch(collUid);
          await cacheClient.collectionSet(collectionManager, collection);

          final itemManager =
              await collectionManager.getItemManager(collection);
          final homePageTitle = (await collection.getMeta()).name;
          if (context.mounted) {
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (BuildContext context) => MyHomePage(
                          title: homePageTitle ?? "My Tasks",
                          itemManager: itemManager,
                          client: widget.client,
                          colUid: collUid,
                          colType: colType,
                        )));
          }
        }
      }
    }
  }
}

ListTile buildCollectionListTile(Map<String, dynamic> element, String cacheDir,
    String username, BuildContext context) {
  return ListTile(
    title: Text(element["itemName"]),
    leading: Icon(Icons.square,
        color: element["itemColor"] != null &&
                (element["itemColor"] as String).isNotEmpty
            ? Color.fromRGBO(
                int.parse((element["itemColor"] as String).substring(1, 3),
                    radix: 16),
                int.parse((element["itemColor"] as String).substring(3, 5),
                    radix: 16),
                int.parse((element["itemColor"] as String).substring(5, 7),
                    radix: 16),
                1.0)
            : Colors.green),
    trailing:
        Tooltip(message: element["itemUid"], child: const Icon(Icons.info)),
    onTap: () {
      final activeCollectionFile =
          File("$cacheDir/$username/.activeCollection");
      activeCollectionFile.writeAsStringSync(element["itemUid"]);
      Navigator.maybePop(context, element);
    },
  );
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.title,
    required this.itemManager,
    required this.client,
    required this.colUid,
    required this.colType,
  });

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;
  final EtebaseItemManager itemManager;
  final EtebaseClient client;
  final String colUid;
  final String colType;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WindowListener {
  Future<ItemListResponse>? _itemListResponse;
  String? _searchText;
  DateTime? dateSearchStart;
  DateTime? dateSearchEnd;
  bool todaySearch = true;
  bool showCompleted = false;
  bool showCanceled = false;
  DateTime today = DateTime.now();
  bool cacheLoaded = false;

  final _searchTextController = TextEditingController();
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  final _selectedTasks = <String, ItemMapWrapper>{};
  final _dateSearchEndController = TextEditingController();
  final _dateSearchStartController = TextEditingController();
  Future<Map<String, dynamic>>? collections;

  Future<Map<String, dynamic>>? accountInfo;

  Timer? refreshTimer;

  final Duration timerRefreshDuration = const Duration(minutes: 5);

  @override
  void dispose() {
    widget.client.dispose();
    windowManager.removeListener(this);
    refreshTimer?.cancel();

    super.dispose();
  }

  @override
  void onWindowFocus() {
    final now = DateTime.now();

    if (now.day != today.day) {
      setState(() {
        today = now;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    setState(() {
      // Looks maybe like a funny pattern, but the intention here is to load the
      // cached based data first, let it be seen on the UI, and then run the gamut with remote fetch.
      // the caveat is that the loader indicator does not show on stage 2.
      _itemListResponse = getItemListResponse(
              widget.itemManager, widget.client, widget.colUid,
              cacheOnly: !cacheLoaded)
          .then((value) {
        setState(() {
          cacheLoaded = true;
        });

        getItemListResponse(widget.itemManager, widget.client, widget.colUid,
                cacheOnly: !cacheLoaded)
            .then((value) {
          setState(() {
            _itemListResponse = Future.value(value);
          });
          return value;
        });
        return value;
      });
      /*dateSearchStart = (dateSearchStart ?? DateTime.now())
          .copyWith(hour: 0, minute: 0, second: 0);*/
      dateSearchEnd = (dateSearchEnd ?? DateTime.now())
          .copyWith(hour: 23, minute: 59, second: 59);
      _dateSearchEndController.text =
          DateFormat("yyyy-MM-dd").format(dateSearchEnd!);
      // _dateSearchStartController.text =
      //     DateFormat("yyyy-MM-dd").format(dateSearchStart!);
      today = DateTime.now();
      collections = fetchCollections();

      accountInfo = getCacheConfigInfo(widget.client);
    });
    refreshTimer = Timer.periodic(timerRefreshDuration, (timer) {
      setState(() {
        _itemListResponse = getItemListResponse(
            widget.itemManager, widget.client, widget.colUid,
            cacheOnly: !cacheLoaded);
      });
    });
  }

  Future<Map<String, dynamic>> fetchCollections(
      {List<String> collectionTypes = const [
        "etebase.vtodo",
        "etebase.md.note"
      ]}) async {
    final Map<String, dynamic> collections = {};
    for (var collectionType in collectionTypes) {
      for (var collection in (await getCollections(widget.client,
              collectionType: collectionType))
          .entries) {
        if (collection.key == "items" &&
            collections.containsKey(collection.key)) {
          (collections[collection.key] as Map).addAll(collection.value);
        } else {
          collections[collection.key] = collection.value;
        }
      }
    }
    return collections;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleModel>(builder: (context, localeModel, child) {
      return FutureBuilder<ItemListResponse>(
          future: _itemListResponse,
          builder: (BuildContext context,
              AsyncSnapshot<ItemListResponse?> snapshot) {
            List<Widget> children = [];
            return Scaffold(
              drawer:
                  snapshot.hasData ? buildDrawer(context, localeModel) : null,
              appBar: snapshot.hasData
                  ? buildAppBar(context, snapshot.data!)
                  : null,
              floatingActionButton: !snapshot.hasData
                  ? null
                  : FloatingActionButton(
                      onPressed: () async {
                        /*Locale nextLocale = Locale("en");
                          if (Intl.getCurrentLocale() == "en") {
                            nextLocale = Locale("he");
                          }
                          EteStateWidget.of(context).onLocaleChange(nextLocale);*/
                        final itemListResponse = snapshot.data!;
                        refreshTimer?.cancel();
                        await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (BuildContext context) =>
                                        (widget.colType == "etebase.vtodo"
                                            ? EtebaseItemCreateRoute(
                                                itemManager: widget.itemManager,
                                                client: widget.client)
                                            : EtebaseItemNoteCreateRoute(
                                                itemManager: widget.itemManager,
                                                client: widget.client))))
                            .then((value) {
                          if (value != null) {
                            itemListResponse
                                    .items[value["item"] as EtebaseItem] =
                                ItemListItem.fromMap({
                              "itemContent": value["itemContent"],
                              "itemUid": value["itemUid"],
                              "itemIsDeleted": value["itemIsDeleted"],
                              "itemType": value["itemType"],
                              "itemName": value["itemName"],
                              "mtime": value["mtime"],
                            });
                            setState(() {
                              _itemListResponse =
                                  Future<ItemListResponse>.value(
                                      itemListResponse);
                            });
                          }
                        });
                        refreshTimer =
                            Timer.periodic(timerRefreshDuration, (timer) {
                          setState(() {
                            _itemListResponse = getItemListResponse(
                                widget.itemManager,
                                widget.client,
                                widget.colUid);
                          });
                        });
                      },
                      tooltip: widget.colType == "etebase.vtodo"
                          ? AppLocalizations.of(context)!.createNewTask
                          : AppLocalizations.of(context)!.createNewNote,
                      child: const Icon(Icons.add),
                    ),
              body: RefreshIndicator(
                  key: _refreshIndicatorKey,
                  onRefresh: () async {
                    setState(() {
                      _itemListResponse = getItemListResponse(
                          widget.itemManager, widget.client, widget.colUid);
                      refreshTimer?.cancel();
                      refreshTimer =
                          Timer.periodic(timerRefreshDuration, (timer) {
                        setState(() {
                          _itemListResponse = getItemListResponse(
                              widget.itemManager, widget.client, widget.colUid);
                        });
                      });
                    });
                    return _itemListResponse!.then((value) => null);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AutoDirection(
                          text: _searchTextController.text,
                          child: SearchBar(
                            controller: _searchTextController,
                            hintText: AppLocalizations.of(context)!.search,
                            leading: _searchTextController.text.isEmpty
                                ? const Icon(Icons.search)
                                : IconButton(
                                    icon: const Icon(Icons.close),
                                    tooltip:
                                        AppLocalizations.of(context)!.clear,
                                    onPressed: () {
                                      setState(() {
                                        _searchText = null;
                                        _searchTextController.text = "";
                                      });
                                    },
                                  ),
                            onSubmitted: (value) {
                              setState(() {
                                _searchText = value;
                                _searchTextController.text = value;
                              });
                            },
                            onChanged: (value) => setState(() {
                              _searchText = value;
                              _searchTextController.text = value;
                            }),
                          )),
                      buildExpansionTileTaskFinishedFilters(
                          getDateSelectionWidgets(context)),
                      buildMainContent(context, snapshot, children),
                    ],
                  )),
            );
          });
    });
  }

  Widget buildMainContent(BuildContext context,
      AsyncSnapshot<ItemListResponse?> snapshot, List<Widget> children) {
    if (snapshot.hasData && snapshot.data != null) {
      final itemListResponse = snapshot.data!;
      final itemManager = itemListResponse.itemManager;
      final itemMap = itemListResponse.items;
      if (widget.colType == "etebase.vtodo") {
        children.addAll(todoItemList(itemManager, itemMap, itemListResponse));
      } else {
        final listColumn = <Widget>[];
        final itemMapEntriesSorted = <MapEntry<EtebaseItem, ItemListItem>>[];
        for (final item in itemMap.entries) {
          if (item.value.itemIsDeleted) {
            continue;
          }
          itemMapEntriesSorted.add(item);
        }
        itemMapEntriesSorted.sort((a, b) =>
            (a.value.mtime ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
                b.value.mtime ?? DateTime.fromMillisecondsSinceEpoch(0)));
        for (final item in itemMapEntriesSorted) {
          listColumn.add(SizedBox(
              //width: 300,
              height: 100,
              child: Container(
                  decoration:
                      const BoxDecoration(border: Border(bottom: BorderSide())),
                  child: ListTile(
                    title: (item.value.itemName != null &&
                            !utf8
                                .decode(item.value.itemContent)
                                .startsWith(item.value.itemName!))
                        ? AutoDirection(
                            text: item.value.itemName!,
                            child: Text(item.value.itemName!))
                        : null,
                    subtitle: AutoDirection(
                        text: utf8.decode(item.value.itemContent),
                        child: Markdown(
                            data: utf8.decode(item.value.itemContent))),
                    onTap: () => onPressedItemNoteWidget(context, item.key,
                            itemManager, item.value.toMap(), widget.client)
                        .then((value) {
                      if (value != null) {
                        itemListResponse.items.remove(item.key);

                        itemListResponse.items[value["item"]] =
                            ItemListItem.fromMap({
                          "itemContent": value["itemContent"],
                          "itemUid": value["itemUid"],
                          "itemIsDeleted": value["itemIsDeleted"],
                          "itemType": value["itemType"],
                          "itemName": value["itemName"],
                          "mtime": value["mtime"],
                        });
                        setState(() {
                          _itemListResponse =
                              Future<ItemListResponse>.value(itemListResponse);
                        });
                        //_refreshIndicatorKey.currentState?.show();
                      } else {
                        /*setState(() {
              _itemListResponse = getItemListResponse(itemManager);
            });*/
                      }
                    }),
                  ))));
          //listColumn.add(Text(utf8.decode(item.value.itemContent)));
        }

        children.add(Column(children: listColumn));
      }
    } else {
      children.add(const Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
                padding: EdgeInsets.only(right: 24),
                child: Text("Fetching data")),
            SizedBox(width: 50, height: 50, child: CircularProgressIndicator())
          ]));
      if (snapshot.hasError) {
        children.add(Text(snapshot.error!.toString()));
      }
    }

    return Column(
      children: [
        Column(
          children: [
            Padding(
                padding: const EdgeInsets.all(8),
                child: SizedBox(
                    //width: 600,
                    height: MediaQuery.sizeOf(context).height * 0.60,
                    child: ListView.builder(
                        itemCount: children.length,
                        itemBuilder: (context, index) => children[index]))),
          ],
        ),
      ],
    );
  }

  ExpansionTile buildExpansionTileTaskFinishedFilters(
      List<Widget> dateSelectionWidgets) {
    return ExpansionTile(
        title: Text(AppLocalizations.of(context)!.filters),
        children: [
          Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: dateSelectionWidgets),
          Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(children: [
                  const Icon(Icons.check),
                  Switch(
                    value: showCompleted,
                    onChanged: (value) => setState(() {
                      showCompleted = value;
                    }),
                  )
                ]),
                Row(children: [
                  const Icon(Icons.cancel),
                  Switch(
                    value: showCanceled,
                    onChanged: (value) => setState(() {
                      showCanceled = value;
                    }),
                  )
                ]),
              ]),
        ]);
  }

  AppBar buildAppBar(BuildContext context, ItemListResponse itemListResponse) {
    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      title: Text(widget.title),
      actions: true
          ? [
              if (_selectedTasks.isNotEmpty)
                IconButton(
                    onPressed: () async {
                      bool anyWereChanged = false;
                      final cacheClient = await EtebaseFileSystemCache.create(
                          widget.client,
                          await getCacheDir(),
                          await getUsernameInCacheDir());

                      final colUid = await getCollectionUIDInCacheDir();
                      for (var entry in _selectedTasks.entries.toList()) {
                        final item = entry.value;
                        final eteItem = item.item;
                        final icalendar = item.icalendar;
                        final itemManager = widget.itemManager;
                        final compTodo = icalendar.todo!;
                        if ([TodoStatus.completed, TodoStatus.cancelled]
                            .contains(compTodo.status)) {
                          return;
                        }
                        try {
                          if (context.mounted) {
                            refreshTimer?.cancel();
                            await onPressedModifyDueDate(eteItem, icalendar,
                                    itemManager, compTodo, context)
                                .then((value) async {
                              if (value == null) {
                                return value;
                              } else {
                                anyWereChanged = true;
                              }

                              await cacheClient.itemSet(
                                  itemManager, colUid, value["item"]);

                              _selectedTasks.remove(entry.key);

                              itemListResponse.items.remove(eteItem);
                              itemListResponse
                                      .items[value["item"] as EtebaseItem] =
                                  ItemListItem.fromMap({
                                "itemContent": value["itemContent"],
                                "itemUid": value["itemUid"],
                                "itemIsDeleted": value["itemIsDeleted"],
                                "itemType": value["itemType"],
                                "itemName": value["itemName"],
                                "mtime": value["mtime"],
                              });
                              setState(() {
                                _itemListResponse =
                                    Future<ItemListResponse>.value(
                                        itemListResponse);
                              });
                              return value;
                            });
                            refreshTimer =
                                Timer.periodic(timerRefreshDuration, (timer) {
                              setState(() {
                                _itemListResponse = getItemListResponse(
                                    widget.itemManager,
                                    widget.client,
                                    widget.colUid);
                              });
                            });
                          }
                        } on Exception catch (error, stackTrace) {
                          if (kDebugMode) {
                            print(stackTrace);
                            print(error);
                          }

                          if (error is EtebaseException) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text(error.message),
                                duration: const Duration(seconds: 5),
                                action: SnackBarAction(
                                  label: 'OK',
                                  onPressed: () async {
                                    ScaffoldMessenger.of(context)
                                        .hideCurrentSnackBar();
                                  },
                                ),
                              ));
                            }
                            if (error.code == EtebaseErrorCode.conflict) {
                              final itemUpdatedFromServer = await itemManager
                                  .fetch(await eteItem.getUid());
                              final contentFromServer =
                                  await itemUpdatedFromServer.getContent();
                              if (kDebugMode) {
                                print(
                                    "------BEGIN returned from server ---------");
                                print(
                                    "ETAG: ${await itemUpdatedFromServer.getEtag()}");
                                print((VComponent.parse(
                                            utf8.decode(contentFromServer))
                                        as VCalendar)
                                    .toString());
                                print(
                                    "------END returned from server ---------");
                              }

                              final cacheClient =
                                  await EtebaseFileSystemCache.create(
                                      widget.client,
                                      await getCacheDir(),
                                      await getUsernameInCacheDir());
                              final colUid = await getCollectionUIDInCacheDir();
                              await cacheClient.itemSet(
                                  itemManager, colUid, itemUpdatedFromServer);
                              await cacheClient.dispose();

                              itemListResponse.items.remove(eteItem);

                              itemListResponse.items[itemUpdatedFromServer] =
                                  ItemListItem.fromMap({
                                "itemContent": contentFromServer,
                                "itemUid": await itemUpdatedFromServer.getUid(),
                                "itemIsDeleted":
                                    await itemUpdatedFromServer.isDeleted(),
                                "itemType":
                                    (await itemUpdatedFromServer.getMeta())
                                        .itemType,
                                "itemName":
                                    (await itemUpdatedFromServer.getMeta())
                                        .name,
                                "mtime": (await itemUpdatedFromServer.getMeta())
                                    .mtime,
                              });
                              setState(() {
                                _itemListResponse =
                                    Future<ItemListResponse>.value(
                                        itemListResponse);
                              });
                            }
                          }
                        }
                      }
                      if (anyWereChanged) {
                        setState(() {
                          _itemListResponse = getItemListResponse(
                              widget.itemManager, widget.client, widget.colUid);
                        });
                      }
                      await cacheClient.dispose();
                    },
                    icon: const Icon(Icons.snooze))
            ]
          : null,
    );
  }

  Drawer buildDrawer(BuildContext context, LocaleModel localeModel) {
    return Drawer(
        child: ListView(children: [
      DrawerHeader(
          child: Column(children: [
        const Text("Collection List"),
        ListTile(
          onTap: () async {
            String currentLanguageCode = localeModel.locale.languageCode;
            String? currentCountryCode = localeModel.locale.countryCode;

            await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    content: Column(
                        children: AppLocalizations.supportedLocales
                            .map((e) => ListTile(
                                  title: Text(e.languageCode),
                                  leading: Locale.fromSubtags(
                                                  languageCode:
                                                      currentLanguageCode,
                                                  countryCode:
                                                      currentCountryCode)
                                              .languageCode ==
                                          e.languageCode
                                      ? const Icon(Icons.check)
                                      : null,
                                  onTap: () async {
                                    final Future<SharedPreferences>
                                        prefsInstance =
                                        SharedPreferences.getInstance();
                                    final SharedPreferences prefs =
                                        await prefsInstance;
                                    await prefs.setString(
                                        "locale", e.languageCode);
                                    if (e.countryCode != null) {
                                      await prefs.setString(
                                          "countryCode", e.countryCode!);
                                    } else if (prefs.getString("countryCode") !=
                                        null) {
                                      await prefs.remove("countryCode");
                                    }

                                    if (e.languageCode != currentLanguageCode ||
                                        e.countryCode != currentCountryCode) {
                                      localeModel.set(e);
                                    }
                                    if (context.mounted) {
                                      await Navigator.maybePop(context);
                                    }
                                  },
                                ))
                            .toList()),
                    actions: [
                      TextButton(
                        child: const Text("Done"),
                        onPressed: () async {
                          await Navigator.maybePop(context);
                        },
                      )
                    ],
                  );
                });
          },
          title: Text(AppLocalizations.of(context)!.language),
          trailing: const Icon(Icons.language),
        ),
        TextButton(
            onPressed: () async {
              final Future<SharedPreferences> prefsInstance =
                  SharedPreferences.getInstance();
              final SharedPreferences prefs = await prefsInstance;
              final eteBaseUrlRawString = prefs.getString("ete_base_url");
              final serverUri = eteBaseUrlRawString != null
                  ? Uri.tryParse(eteBaseUrlRawString)
                  : null;

              const secureStorage = FlutterSecureStorage();

              final eteCacheAccountEncryptionKey = await secureStorage
                      .read(key: eteCacheAccountEncryptionKeyString)
                      .then((value) =>
                          value != null ? base64Decode(value) : value)
                  as Uint8List?;
              final cacheClient = await EtebaseFileSystemCache.create(
                  widget.client,
                  await getCacheDir(),
                  await getUsernameInCacheDir());

              final etebase = await cacheClient.loadAccount(
                  widget.client, eteCacheAccountEncryptionKey);

              await etebase.logout();
              await cacheClient.clearUser();

              if (context.mounted) {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (BuildContext context) => AccountLoadPage(
                              client: widget.client,
                              serverUri: serverUri,
                            )));
              }
            },
            child: const Text("Sign out")),
      ])),
      FutureBuilder<Map<String, dynamic>?>(
          future: accountInfo,
          builder: (BuildContext context,
              AsyncSnapshot<Map<String, dynamic>?> snapshot) {
            if (!snapshot.hasData) {
              return const Column(children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(right: 24.0),
                      child: Text("Fetching cache configuration."),
                    ),
                    CircularProgressIndicator(),
                  ],
                )
              ]);
            }
            final cacheDir = snapshot.data!["cacheDir"]!;
            final username = snapshot.data!["username"]!;
            return FutureBuilder<Map<String, dynamic>?>(
                future: collections,
                builder: (BuildContext context,
                    AsyncSnapshot<Map<String, dynamic>?> snapshot) {
                  if (snapshot.hasData) {
                    final collectionsResponse = snapshot.data!;
                    final items = collectionsResponse["items"]
                        as Map<EtebaseCollection, Map<String, dynamic>>;
                    final collItems = (items.entries
                        .where((element) => !element.value["itemIsDeleted"])
                        .map((element) => buildDrawerCollectionListTile(
                            element,
                            context,
                            cacheDir,
                            username,
                            collectionsResponse["collectionManager"]
                                as EtebaseCollectionManager))
                        .toList());
                    return Column(children: collItems);
                  } else {
                    return Column(children: [
                      const Text("Loading collection UIDs"),
                      if (snapshot.hasError) Text(snapshot.error.toString()),
                      const CircularProgressIndicator()
                    ]);
                  }
                });
          }),
    ]));
  }

  ListTile buildDrawerCollectionListTile(
      MapEntry<EtebaseCollection, Map<String, dynamic>> element,
      BuildContext context,
      cacheDir,
      username,
      EtebaseCollectionManager collectionManager) {
    final itemDataMap = element.value;

    final String itemUid = itemDataMap["itemUid"];
    final itemColor = itemDataMap["itemColor"] as String?;
    final itemName = (itemDataMap["itemName"] as String?);
    return ListTile(
      selected: itemUid == widget.colUid,
      title: Text(itemName ?? "<N/A> My Tasks"),
      leading: Icon(Icons.square,
          color: itemColor != null && itemColor.isNotEmpty
              ? buildCollectionColor(itemColor)
              : Colors.green),
      trailing: Tooltip(message: itemUid, child: const Icon(Icons.info)),
      onTap: () async {
        if (itemUid == widget.colUid) {
          Navigator.maybePop(context);
          return;
        }
        final activeCollectionFile =
            File("$cacheDir/$username/.activeCollection");
        await activeCollectionFile.writeAsString(itemUid);
        //Navigator.maybePop(context, element);

        final colType = itemDataMap["itemCollectionType"];
        final colUid = itemUid;
        final itemManager =
            (await collectionManager.getItemManager(element.key));
        final newEteClient = await getEtebaseClient();
        if (context.mounted) {
          Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (BuildContext context) => MyHomePage(
                        title: itemName ?? "My Tasks",
                        itemManager: itemManager,
                        client: newEteClient,
                        colUid: colUid,
                        colType: colType,
                      )));
        }
      },
    );
  }

  Color buildCollectionColor(String itemColorString) {
    return Color.fromRGBO(
        int.parse(itemColorString.substring(1, 3), radix: 16),
        int.parse(itemColorString.substring(3, 5), radix: 16),
        int.parse(itemColorString.substring(5, 7), radix: 16),
        1.0);
  }

  /// Returns widgets for date selection
  List<Widget> getDateSelectionWidgets(BuildContext context) {
    final dateSelectionWidgets = <Widget>[
      Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text("Today"),
            Switch(
                value: todaySearch,
                activeColor:
                    _searchTextController.text.isNotEmpty ? Colors.grey : null,
                onChanged: (bool newValue) {
                  setState(() {
                    todaySearch = newValue;
                    if (newValue) {
                      dateSearchEnd = DateTime.now()
                          .copyWith(hour: 23, minute: 59, second: 59);
                    }
                    if (!newValue && dateSearchStart == null) {
                      dateSearchStart = DateTime.now()
                          .copyWith(hour: 0, minute: 0, second: 0);
                      _dateSearchStartController.text =
                          DateFormat("yyyy-MM-dd").format(dateSearchStart!);
                    }
                  });
                }),
            const VerticalDivider()
          ]),
      SizedBox(
          width: 175,
          child: TextField(
              controller: _dateSearchStartController,
              readOnly: true,
              onTap: () async {
                await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: (dateSearchStart ?? DateTime.now())
                            .copyWith(hour: 0, minute: 0, second: 0),
                        currentDate: (DateTime.now())
                            .copyWith(hour: 0, minute: 0, second: 0))
                    .then((value) => setState(() {
                          dateSearchStart =
                              value?.copyWith(hour: 0, minute: 0, second: 0);
                          _dateSearchStartController.text =
                              dateSearchStart != null
                                  ? DateFormat("yyyy-MM-dd")
                                      .format(dateSearchStart!)
                                  : "";
                        }));
              },
              decoration: const InputDecoration(
                  icon: Icon(Icons.calendar_month),
                  label: Text("Start date range")))),
      SizedBox(
          width: 175,
          child: TextField(
              controller: _dateSearchEndController,
              readOnly: true,
              onTap: () async {
                await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: (dateSearchEnd ?? DateTime.now())
                            .copyWith(hour: 23, minute: 59, second: 59),
                        currentDate: (DateTime.now())
                            .copyWith(hour: 23, minute: 59, second: 59))
                    .then((value) => setState(() {
                          dateSearchEnd =
                              value?.copyWith(hour: 23, minute: 59, second: 59);
                          _dateSearchEndController.text = dateSearchEnd != null
                              ? DateFormat("yyyy-MM-dd").format(dateSearchEnd!)
                              : "";
                        }));
              },
              decoration: const InputDecoration(
                  icon: Icon(Icons.calendar_month),
                  label: Text("End date range")))),
    ];
    return dateSelectionWidgets;
  }

  Future<Map<String, dynamic>?> onPressedItemWidget(
      BuildContext context,
      EtebaseItem item,
      VCalendar icalendar,
      EtebaseItemManager itemManager,
      Map<String, dynamic> itemMap,
      EtebaseClient client) async {
    refreshTimer?.cancel();
    final comingBack = await Navigator.push<Map<String, dynamic>?>(
        context,
        MaterialPageRoute(
            builder: (context) => EtebaseItemRoute(
                item: item,
                icalendar: icalendar,
                itemManager: itemManager,
                itemMap: itemMap,
                client: client)));
    refreshTimer = Timer.periodic(timerRefreshDuration, (timer) {
      setState(() {
        _itemListResponse = getItemListResponse(
            widget.itemManager, widget.client, widget.colUid);
      });
    });
    return comingBack;
  }

  Future<Map<String, dynamic>?> onPressedItemNoteWidget(
      BuildContext context,
      EtebaseItem item,
      EtebaseItemManager itemManager,
      Map<String, dynamic> itemMap,
      EtebaseClient client) async {
    refreshTimer?.cancel();
    final comingBack = await Navigator.push<Map<String, dynamic>?>(
        context,
        MaterialPageRoute(
            builder: (context) => EtebaseItemNoteRoute(
                item: item,
                itemManager: itemManager,
                itemMap: itemMap,
                client: client)));
    refreshTimer = Timer.periodic(timerRefreshDuration, (timer) {
      setState(() {
        _itemListResponse = getItemListResponse(
            widget.itemManager, widget.client, widget.colUid);
      });
    });
    return comingBack;
  }

  List<Widget> todoItemList(EtebaseItemManager itemManager,
      Map<EtebaseItem, ItemListItem> itemMap, ItemListResponse fullSnapshot) {
    final client = widget.client;
    List<Widget> children = [];
    final itemsSorted = <ItemMapWrapper>[];
    final itemsByUID = <String, ItemMapWrapper>{};
    var dtToday = DateTime.now().copyWith(hour: 23, minute: 59, second: 59);
    filterItems(itemMap, itemsSorted, itemsByUID);
    itemsSorted.sort((a, b) {
      // We treat null priority as greater than low, so that it sorts after.
      final priorityIntCompare =
          (a.icalendar.todo!.priorityInt ?? (Priority.low.numericValue + 1))
              .compareTo((b.icalendar.todo!.priorityInt ??
                  (Priority.low.numericValue + 1)));

      DateTime? aDue = /*a.icalendar.todo!.start ??*/ a.icalendar.todo!.due;
      if (aDue == null && (a.icalendar.todo!.relatedTo?.isNotEmpty ?? false)) {
        aDue = /*itemsByUID[a.icalendar.todo!.relatedTo]?.icalendar.todo!.start ??*/
            itemsByUID[a.icalendar.todo!.relatedTo]?.icalendar.todo!.due;
      }
      DateTime? bDue = /*a.icalendar.todo!.start ??*/ b.icalendar.todo!.due;
      if (bDue == null && (b.icalendar.todo!.relatedTo?.isNotEmpty ?? false)) {
        bDue = /*itemsByUID[b.icalendar.todo!.relatedTo]?.icalendar.todo!.start ??*/
            itemsByUID[b.icalendar.todo!.relatedTo]?.icalendar.todo!.due;
      }
      final timeCompare = (aDue ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(bDue ?? DateTime.fromMillisecondsSinceEpoch(0));

      var compareToDay = (aDue ?? DateTime.fromMillisecondsSinceEpoch(0))
          .day
          .compareTo((bDue ?? DateTime.fromMillisecondsSinceEpoch(0)).day);
      if (compareToDay == 0) {
        if (priorityIntCompare != 0) {
          return priorityIntCompare;
        }
      } else if (compareToDay > 0) {
        if (priorityIntCompare != 0) {
          return priorityIntCompare;
        }
      }

      if (timeCompare == 0) {
        if (a.icalendar.todo!.relatedTo?.isNotEmpty ?? false) {
          if (b.icalendar.todo!.relatedTo?.isEmpty ??
              b.icalendar.todo!.relatedTo == null) {
            return 1;
          } else {
            return timeCompare;
          }
        } else {
          if (b.icalendar.todo!.relatedTo == null ||
              b.icalendar.todo!.relatedTo!.isEmpty) {
            return timeCompare;
          } else {
            return -1;
          }
        }
      } else {
        return timeCompare;
      }
    });
    for (final item in itemsSorted) {
      final eteItem = item.item;

      VCalendar? icalendar;
      icalendar = item.icalendar;

      final compTodo = icalendar.todo!;

      final statusTodo = compTodo.status;

      if (_searchText != null &&
          !(compTodo.summary?.toLowerCase() ?? "")
              .contains(_searchText!.toLowerCase())) {
        continue;
      }
      DateTime? dateForLogicStart = compTodo.start;
      DateTime? dateForLogicDue = compTodo.due;
      compTodo.due;
      if (compTodo.relatedTo != null &&
          compTodo.relatedTo!.isNotEmpty &&
          compTodo.start == null &&
          compTodo.due == null) {
        dateForLogicStart =
            itemsByUID[compTodo.relatedTo!]!.icalendar.todo!.start;
        dateForLogicDue = itemsByUID[compTodo.relatedTo!]!.icalendar.todo!.due;
        // final theIterFromMap = itemsSorted
        //     .where(
        //         (element) => element.icalendar.todo!.uid == compTodo.relatedTo)
        //     .toList();
        // if (theIterFromMap.isNotEmpty) {
        //   final icalendarRelated = theIterFromMap[0].icalendar;
        //   dateForLogicStart = icalendarRelated.todo!.start;

        //   dateForLogicDue = icalendarRelated.todo!.due;
        // }
      }

      final snoozeTimeText =
          compTodo.getProperty("X-MOZ-SNOOZE-TIME")?.textValue;
      bool isSnoozed = false;
      DateTime? snoozeTime;
      if (snoozeTimeText != null &&
          (dateForLogicStart != null || dateForLogicDue != null)) {
        snoozeTime = DateTime.parse(snoozeTimeText);
        if (snoozeTime.isAfter(dateForLogicStart ?? dateForLogicDue!)) {
          isSnoozed = true;
        }
      }

      if ((todaySearch || dateSearchEnd != null) &&
          (dateForLogicStart != null ||
              dateForLogicDue != null ||
              snoozeTime != null) &&
          (snoozeTime ?? dateForLogicStart ?? dateForLogicDue!)
                  .compareTo((todaySearch ? dtToday : dateSearchEnd!)) ==
              1 &&
          _searchTextController.text.isEmpty) {
        continue;
      }

      final actionColor = switch (compTodo.priority) {
        Priority.low => Colors.blue,
        Priority.undefined || null => Colors.grey,
        Priority.medium => Colors.orange,
        Priority.high => Colors.red,
      };
      final textDirection = Bidi.detectRtlDirectionality(compTodo.summary ?? "")
          ? TextDirection.RTL
          : TextDirection.LTR;
      final child = ListTile(
        leading: Text(
          dateForLogicDue != null
              ? (DateFormat(DateFormat.HOUR24_MINUTE).format(dateForLogicDue) +
                  (DateUtils.isSameDay(dateForLogicDue,
                          today.subtract(const Duration(days: 1)))
                      ? " ${AppLocalizations.of(context)!.yesterday}"
                      : (DateUtils.isSameDay(dateForLogicDue,
                              today.add(const Duration(days: 1)))
                          ? " ${AppLocalizations.of(context)!.tomorrow}"
                          : "")))
              : "",
          style: TextStyle(
              color: dateForLogicDue != null &&
                      DateTime.now().compareTo(dateForLogicDue) > 0
                  ? const ColorScheme.light().error
                  : null),
        ),
        title: Column(
            crossAxisAlignment: textDirection == TextDirection.RTL
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              AutoDirection(
                  text: compTodo.summary ?? "",
                  child: Text(compTodo.summary ?? "")),
              if (compTodo.description != null &&
                  compTodo.description!.isNotEmpty)
                AutoDirection(
                    text: compTodo.description ?? "",
                    child: Text(compTodo.description ?? "")),
            ]),
        selected: _selectedTasks.containsKey(item.value["itemUid"]),
        selectedTileColor: Colors.grey[100],
        subtitle: Row(
            mainAxisAlignment: textDirection == TextDirection.LTR
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: <Widget>[
              Row(
                children: [
                  dateForLogicStart != null &&
                          (dateForLogicStart.isAfter(today) ||
                              (dateForLogicStart.day < today.day))
                      ? Chip(
                          label: RichText(
                              text: TextSpan(children: [
                          TextSpan(
                              text: ((DateUtils.isSameDay(
                                          dateForLogicStart, today) ||
                                      DateUtils.isSameDay(
                                          dateForLogicStart,
                                          today.subtract(
                                              const Duration(days: 1))))
                                  ? (DateFormat.Hm()).format(dateForLogicStart)
                                  : DateFormat("yyyy-MM-dd")
                                      .format(dateForLogicStart)),
                              style: const TextStyle(color: Colors.black87)),
                          const WidgetSpan(
                              child: Icon(
                                Icons.content_paste_go,
                                color: Colors.black87,
                              ),
                              alignment: PlaceholderAlignment.middle)
                        ])))
                      : Container(),
                  if (false)
                    Chip(
                        label: RichText(
                            text: TextSpan(children: [
                      TextSpan(
                          text: dateForLogicDue != null
                              ? (DateUtils.isSameDay(dateForLogicDue, today)
                                  ? (DateFormat.Hm()).format(dateForLogicDue)
                                  : DateFormat("yyyy-MM-dd")
                                      .format(dateForLogicDue))
                              : null,
                          style: const TextStyle(color: Colors.black87)),
                      const WidgetSpan(
                          child: Icon(
                            Icons.punch_clock,
                            color: Colors.black87,
                          ),
                          alignment: PlaceholderAlignment.middle)
                    ]))),
                ],
              ),
              const VerticalDivider(),
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  mainAxisSize: MainAxisSize.max,
                  children: (compTodo.categories
                          ?.map((e) => Chip(
                                label: Text(e),
                                visualDensity: VisualDensity.compact,
                              ))
                          .toList() ??
                      [])),
              if (isSnoozed)
                Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Text(
                        "snoozed: ${DateFormat("yyyy-MM-dd HH:mm").format(snoozeTime!.toLocal())}",
                        style: TextStyle(color: Colors.orange))),
            ]),
        trailing: IconButton(
          icon: Icon(icalendar.todo!.recurrenceRule != null
              ? Icons.repeat
              : (statusTodo == TodoStatus.completed
                  ? Icons.check
                  : (statusTodo == TodoStatus.cancelled
                      ? Icons.cancel
                      : Icons.check_box_outline_blank))),
          color: actionColor,
          onPressed: statusTodo == TodoStatus.completed
              ? null
              : () async {
                  try {
                    await onPressedToggleCompletion(
                            eteItem, icalendar!, itemManager, compTodo)
                        .then((value) async {
                      final cacheClient = await EtebaseFileSystemCache.create(
                          widget.client,
                          await getCacheDir(),
                          await getUsernameInCacheDir());
                      final colUid = await getCollectionUIDInCacheDir();
                      await cacheClient.itemSet(
                          itemManager, colUid, value["item"]);
                      await cacheClient.dispose();
                      fullSnapshot.items.remove(eteItem);
                      fullSnapshot.items[value["item"]] = ItemListItem.fromMap({
                        "itemContent": value["itemContent"],
                        "itemUid": value["itemUid"],
                        "itemIsDeleted": value["itemIsDeleted"],
                        "itemType": value["itemType"],
                        "itemName": value["itemName"],
                        "mtime": value["mtime"],
                      });
                      setState(() {
                        _itemListResponse =
                            Future<ItemListResponse>.value(fullSnapshot);
                      });
                      return value;
                    });
                  } on Exception catch (error, stackTrace) {
                    if (kDebugMode) {
                      print(stackTrace);
                      print(error);
                    }

                    if (error is EtebaseException) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(error.message),
                          duration: const Duration(seconds: 5),
                          action: SnackBarAction(
                            label: 'OK',
                            onPressed: () async {
                              ScaffoldMessenger.of(context)
                                  .hideCurrentSnackBar();
                            },
                          ),
                        ));
                      }
                      if (error.code == EtebaseErrorCode.conflict) {
                        final itemUpdatedFromServer =
                            await itemManager.fetch(await eteItem.getUid());
                        final contentFromServer =
                            await itemUpdatedFromServer.getContent();
                        if (kDebugMode) {
                          print("------BEGIN returned from server ---------");
                          print(
                              "ETAG: ${await itemUpdatedFromServer.getEtag()}");
                          print(
                              (VComponent.parse(utf8.decode(contentFromServer))
                                      as VCalendar)
                                  .toString());
                          print("------END returned from server ---------");
                        }

                        final cacheClient = await EtebaseFileSystemCache.create(
                            widget.client,
                            await getCacheDir(),
                            await getUsernameInCacheDir());
                        final colUid = await getCollectionUIDInCacheDir();
                        await cacheClient.itemSet(
                            itemManager, colUid, itemUpdatedFromServer);
                        await cacheClient.dispose();

                        fullSnapshot.items.remove(eteItem);

                        fullSnapshot.items[itemUpdatedFromServer] =
                            ItemListItem.fromMap({
                          "itemContent": contentFromServer,
                          "itemUid": await itemUpdatedFromServer.getUid(),
                          "itemIsDeleted":
                              await itemUpdatedFromServer.isDeleted(),
                          "itemType":
                              (await itemUpdatedFromServer.getMeta()).itemType,
                          "itemName":
                              (await itemUpdatedFromServer.getMeta()).name,
                          "mtime":
                              (await itemUpdatedFromServer.getMeta()).mtime,
                        });
                        setState(() {
                          _itemListResponse =
                              Future<ItemListResponse>.value(fullSnapshot);
                        });
                      }
                    }
                  }
                },
        ),
        onLongPress: () {
          setState(() {
            if (!_selectedTasks.containsKey(item.value["itemUid"])) {
              _selectedTasks[item.value["itemUid"]] = item;
              //_anySelectedTasks = true;
            } else {
              _selectedTasks.remove(item.value["itemUid"]);
              if (_selectedTasks.isEmpty) {
                //_anySelectedTasks = false;
              }
            }
          });
        },
        onTap: () => onPressedItemWidget(
                context, eteItem, icalendar!, itemManager, item.value, client)
            .then((value) {
          if (value != null) {
            fullSnapshot.items.remove(eteItem);

            fullSnapshot.items[value["item"]] = ItemListItem.fromMap({
              "itemContent": value["itemContent"],
              "itemUid": value["itemUid"],
              "itemIsDeleted": value["itemIsDeleted"],
              "itemType": value["itemType"],
              "mtime": value["mtime"],
              "itemName": value["itemName"],
            });
            setState(() {
              _itemListResponse = Future<ItemListResponse>.value(fullSnapshot);
            });
            //_refreshIndicatorKey.currentState?.show();
          } else {
            /*setState(() {
              _itemListResponse = getItemListResponse(itemManager);
            });*/
          }
        }),
      );
      children.add(child);
    }
    return children;
  }

  void filterItems(
      Map<EtebaseItem, ItemListItem> itemMap,
      List<ItemMapWrapper> itemsSorted,
      Map<String, ItemMapWrapper> itemsByUID) {
    for (final entry in itemMap.entries) {
      final key = entry.key;
      final value = entry.value;
      late final VCalendar icalendar;
      if (value.itemIsDeleted) {
        continue;
      }

      try {
        icalendar = VComponent.parse(utf8.decode(value.itemContent),
            customParser: iCalendarCustomParser) as VCalendar;
      } catch (e) {
        continue;
      }

      if (icalendar.todo == null) {
        continue;
      }
      final compTodo = icalendar.todo!;

      final statusTodo = compTodo.status;

      if (statusTodo == TodoStatus.cancelled && !showCanceled) {
        continue;
      }

      if (statusTodo == TodoStatus.completed && !showCompleted) {
        continue;
      }

      itemsSorted.add(ItemMapWrapper(
          item: key, value: value.toMap(), icalendar: icalendar));
      itemsByUID[icalendar.todo!.uid] = itemsSorted.last;
    }
  }

  Future<Map<String, dynamic>> onPressedToggleCompletion(
      EtebaseItem eteItem,
      VCalendar icalendar,
      EtebaseItemManager itemManager,
      VTodo compTodo) async {
    final itemClone = await eteItem.clone();
    final todoComp = compTodo;
    bool sequenceChange = false;
    const changedStatus = TodoStatus.completed;
    /*
                            
                            sequence must change if:
                            o  "DTSTART"
                            
                            o  "DTEND"
                            
                            o  "DURATION"
                            
                            o  "DUE"
                            
                            o  "RRULE"
                            
                            o  "RDATE"
                            
                            o  "EXDATE"
                            
                            o  "STATUS"
                            */
    bool statusChanged = false;
    if (changedStatus != todoComp.status) {
      todoComp.status = changedStatus;
      sequenceChange = true;
      statusChanged = true;
    }

    todoComp.lastModified = DateTime.now();

    if (sequenceChange) {
      todoComp.sequence = (todoComp.sequence ?? 0) + 1;
    }
    final nextTodo = (statusChanged &&
            (todoComp.status == TodoStatus.completed ||
                todoComp.status == TodoStatus.cancelled))
        ? getNextOccurrence(todoComp, todoComp.recurrenceRule)
        : todoComp;

    final actualNextTodo = nextTodo ?? todoComp;
    actualNextTodo.checkValidity();
    final itemMetaClone = (await itemClone.getMeta())
        .copyWith(mtime: nextTodo?.lastModified ?? todoComp.lastModified);
    await itemClone.setMeta(itemMetaClone);
    if (kDebugMode) {
      print("--------BEGIN Intended changes---------");
      print("ETAG: ${await itemClone.getEtag()}");
      print(actualNextTodo.parent!.toString());
      print("--------END Intended changes-----------");
    }

    await itemClone.setContent(utf8.encode(actualNextTodo.parent!.toString()));
    await itemManager.transaction([itemClone]);
    await eteItem.setContent(await itemClone.getContent());
    final eteItemFromServer = await itemManager.fetch(await eteItem.getUid());
    final icalendarUpdated =
        VComponent.parse(utf8.decode(await eteItemFromServer.getContent()))
            as VCalendar;
    return {
      "item": eteItemFromServer,
      "itemSentToServer": itemClone,
      "icalendar": icalendarUpdated,
      "itemContent": (await eteItemFromServer.getContent()),
      "todo": icalendarUpdated.todo!,
      "itemIsDeleted": (await eteItemFromServer.isDeleted()),
      "itemUid": (await eteItemFromServer.getUid()),
    };
  }

  Future<Map<String, dynamic>?> onPressedModifyDueDate(
      EtebaseItem eteItem,
      VCalendar icalendar,
      EtebaseItemManager itemManager,
      VTodo compTodo,
      BuildContext context) async {
    final itemClone = await eteItem.clone();
    final todoComp = compTodo;
    bool sequenceChange = false;
    final changedStatus = todoComp.status;
    DateTime? updatedDueDate = todoComp.due;
    if (context.mounted) {
      updatedDueDate = await showDatePicker(
              context: context,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              initialDate: (todoComp.due ?? todoComp.start ?? DateTime.now()),
              currentDate: (DateTime.now()))
          .then((DateTime? date) async {
        if (date != null) {
          final time = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(
                todoComp.due ?? todoComp.start ?? DateTime.now()),
          );
          return time != null
              ? date.copyWith(hour: time.hour, minute: time.minute)
              : null;
        } else {
          return null;
        }
      });

      if (updatedDueDate == null) {
        return null;
      }
    }

    /*
                            
                            sequence must change if:
                            o  "DTSTART"
                            
                            o  "DTEND"
                            
                            o  "DURATION"
                            
                            o  "DUE"
                            
                            o  "RRULE"
                            
                            o  "RDATE"
                            
                            o  "EXDATE"
                            
                            o  "STATUS"
                            */
    bool statusChanged = false;
    if (changedStatus != todoComp.status) {
      todoComp.status = changedStatus;
      sequenceChange = true;
      statusChanged = true;
    }

    if (updatedDueDate != todoComp.due) {
      if (todoComp.start != null &&
          todoComp.due != null &&
          todoComp.due!.isAtSameMomentAs(
              todoComp.start!.add(const Duration(seconds: 1)))) {
        todoComp.start = updatedDueDate;

        updatedDueDate = updatedDueDate?.add(const Duration(seconds: 1));
      }

      todoComp.due = updatedDueDate;
      sequenceChange = true;
    }

    todoComp.lastModified = DateTime.now();

    if (sequenceChange) {
      todoComp.sequence = (todoComp.sequence ?? 0) + 1;
    }
    final nextTodo = (statusChanged &&
            (todoComp.status == TodoStatus.completed ||
                todoComp.status == TodoStatus.cancelled))
        ? getNextOccurrence(todoComp, todoComp.recurrenceRule)
        : todoComp;

    final actualNextTodo = nextTodo ?? todoComp;
    actualNextTodo.checkValidity();
    final itemMetaClone = (await itemClone.getMeta())
        .copyWith(mtime: nextTodo?.lastModified ?? todoComp.lastModified);
    await itemClone.setMeta(itemMetaClone);
    if (kDebugMode) {
      print("--------BEGIN Intended changes---------");
      print("ETAG: ${await itemClone.getEtag()}");
      print(actualNextTodo.parent!.toString());
      print("--------END Intended changes-----------");
    }

    await itemClone.setContent(utf8.encode(actualNextTodo.parent!.toString()));
    await itemManager.transaction([itemClone]);
    await eteItem.setContent(await itemClone.getContent());
    final eteItemFromServer = await itemManager.fetch(await eteItem.getUid());
    final icalendarUpdated =
        VComponent.parse(utf8.decode(await eteItemFromServer.getContent()))
            as VCalendar;
    return {
      "item": eteItemFromServer,
      "itemSentToServer": itemClone,
      "icalendar": icalendarUpdated,
      "itemContent": (await eteItemFromServer.getContent()),
      "todo": icalendarUpdated.todo!,
      "itemIsDeleted": (await eteItemFromServer.isDeleted()),
      "itemUid": (await eteItemFromServer.getUid()),
    };
  }
}
