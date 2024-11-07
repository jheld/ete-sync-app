import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:enough_icalendar/enough_icalendar.dart';
import 'package:ete_sync_app/etebase_item_model.dart';
import 'package:ete_sync_app/etebase_note_model.dart';
import 'package:ete_sync_app/i_calendar_custom_parser.dart';
import 'package:etebase_flutter/etebase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rrule/rrule.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

Future<String> getCacheDir() async {
  final value =
      "${(await getApplicationSupportDirectory()).path}/ete_sync_fs_cache";
  return value;
}

const eteCacheAccountEncryptionKeyString = "eteCacheAccountEncryptionKey";

Future<String> getUsernameInCacheDir() async {
  final userNames =
      Directory(await getCacheDir()).listSync().map((e) => e.path).toList();
  late final String username;
  if (userNames.length == 1) {
    username = userNames.first.split("/").last;
  } else if (userNames.isEmpty) {
    throw Exception("No usernames in the cache.");
  } else {
    throw Exception("More than one username in the cache");
  }

  return username;
}

Future<String> getCollectionUIDInCacheDir() async {
  final cacheDir = (await getCacheDir());
  final username = await getUsernameInCacheDir();
  final collectionUIDNames = Directory("$cacheDir/$username/cols/").listSync();
  if (collectionUIDNames.isEmpty) {
    throw Exception("No collections in cache dir.");
  }
  if (collectionUIDNames.length == 1) {
    return collectionUIDNames.first.path.split("/").last;
  } else {
    final activeCollectionFile = File("$cacheDir/$username/.activeCollection");
    if (activeCollectionFile.existsSync()) {
      final activeCollectionName =
          activeCollectionFile.readAsStringSync().replaceAll("\n", "");
      if (collectionUIDNames
          .map((e) => e.path.split("/").last)
          .contains(activeCollectionName)) {
        return activeCollectionName;
      } else {
        throw Exception(
            "Active collection name in user's cache dir does not exist in the user's collection list in cache.");
      }
    }
    throw Exception("Too many collections to naively pick.");
  }
}

Future<Locale> getPrefLocale() async {
  final Future<SharedPreferences> prefsInstance =
      SharedPreferences.getInstance();
  final SharedPreferences prefs = await prefsInstance;

  final theCurrentLocale =
      (prefs.getString("locale")) ?? Intl.getCurrentLocale();
  final theCurrentCountryCode = prefs.getString("countryCode") ??
      (prefs.getString("locale") != null
          ? null
          : (theCurrentLocale.contains("_")
              ? theCurrentLocale.split("_")[1]
              : null));

  return Locale(theCurrentLocale, theCurrentCountryCode);
}

Future<Uri?> getServerUri() async {
  final Future<SharedPreferences> prefsInstance =
      SharedPreferences.getInstance();
  final SharedPreferences prefs = await prefsInstance;
  final eteBaseUrlRawString = prefs.getString("ete_base_url");
  final serverUri =
      eteBaseUrlRawString != null ? Uri.tryParse(eteBaseUrlRawString) : null;
  return serverUri;
}

Future<EtebaseClient> getEtebaseClient() async {
  final Future<SharedPreferences> prefsInstance =
      SharedPreferences.getInstance();
  final SharedPreferences prefs = await prefsInstance;
  final eteBaseUrlRawString = prefs.getString("ete_base_url");
  final serverUri =
      eteBaseUrlRawString != null ? Uri.tryParse(eteBaseUrlRawString) : null;
  final client = await EtebaseClient.create('my-client', serverUri);
  return client;
}

Future<String> dbFilePath() async {
  return "${(await getApplicationSupportDirectory()).path}/ete_base_db.db";
}

Future<List> getItemManager() async {
  final db = sqlite3.open(await dbFilePath());
  Uri? serverUri = await getServerUri();

  late final EtebaseClient client;
  try {
    client = await getEtebaseClient();
  } on EtebaseException catch (e) {
    if (e.code == EtebaseErrorCode.urlParse) {
      return [null, null, null, null, serverUri, null, null, db, null, null];
    }
    rethrow;
  }
  ReceivePort myReceivePort = ReceivePort();
  RootIsolateToken rootIsolateToken = RootIsolateToken.instance!;
  await Isolate.spawn<List>((args) async {
    final SendPort mySendPort = args[0];
    final RootIsolateToken rootIsolateToken = args[1];
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
    final cacheDir = await getCacheDir();
    mySendPort.send(cacheDir);
  }, [myReceivePort.sendPort, rootIsolateToken]);
  final cacheDir = await myReceivePort.first as String;

  if (!Directory(cacheDir).existsSync()) {
    return [client, null, null, null, serverUri, null, null, db, null, null];
  }

  late final String username;
  try {
    final Future<SharedPreferences> prefsInstance =
        SharedPreferences.getInstance();
    final SharedPreferences prefs = await prefsInstance;
    String? usernameInPref = prefs.getString("username");
    if (usernameInPref == null) {
      throw Exception("No username in preferences.");
    }
    username = usernameInPref;
  } catch (error) {
    return [
      client,
      null,
      null,
      null,
      serverUri,
      null,
      null,
      db,
      username,
      cacheDir
    ];
  }
  const secureStorage = FlutterSecureStorage();

  final eteCacheAccountEncryptionKey = await secureStorage
          .read(key: eteCacheAccountEncryptionKeyString)
          .then((value) => value != null ? base64Decode(value) : value)
      as Uint8List?;
  final cacheClient =
      await EtebaseFileSystemCache.create(client, cacheDir, username);

  late final EtebaseAccount etebase;
  try {
    etebase =
        await cacheClient.loadAccount(client, eteCacheAccountEncryptionKey);
  } catch (error) {
    return [
      client,
      null,
      null,
      null,
      serverUri,
      cacheClient,
      null,
      db,
      username,
      cacheDir,
    ];
  }
  final collUid = await getCollectionUIDInCacheDir();

  final collectionManager = await etebase.getCollectionManager();

  final collection = await collectionManager.fetch(collUid);
  await cacheClient.collectionSet(collectionManager, collection);

  final itemManager = await collectionManager.getItemManager(collection);

  await cacheClient.dispose();

  return [
    client,
    itemManager,
    collUid,
    (await collection.getMeta()).name,
    serverUri,
    cacheClient,
    await collection.getCollectionType(),
    db,
    username,
    cacheDir,
  ];
}

class ItemListItem {
  final bool itemIsDeleted;

  final String itemUid;
  final Uint8List itemContent;
  final String? itemType;
  final String? itemName;
  final DateTime? mtime;

  ItemListItem(
      {required this.itemIsDeleted,
      required this.itemUid,
      required this.itemContent,
      required this.itemType,
      required this.itemName,
      required this.mtime});

  static ItemListItem fromMap(Map<String, dynamic> theMap) {
    return ItemListItem(
      itemIsDeleted: theMap["itemIsDeleted"],
      itemUid: theMap["itemUid"],
      itemContent: theMap["itemContent"],
      itemType: theMap["itemType"],
      itemName: theMap["itemName"],
      mtime: theMap["mtime"],
    );
  }

  static ItemListItem fromEtebaseItemModel(EtebaseItemModel theMap) {
    return ItemListItem(
      itemIsDeleted: theMap.itemIsDeleted,
      itemUid: theMap.itemUid,
      itemContent: theMap.itemContent,
      itemType: theMap.itemType,
      itemName: theMap.itemName,
      mtime: theMap.mtime,
    );
  }

  static ItemListItem fromEtebaseNoteModel(EtebaseNoteModel theMap) {
    return ItemListItem(
      itemIsDeleted: theMap.itemIsDeleted,
      itemUid: theMap.itemUid,
      itemContent: theMap.itemContent,
      itemType: theMap.itemType,
      itemName: theMap.itemName,
      mtime: theMap.mtime,
    );
  }

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> theMap = {
      "itemIsDeleted": itemIsDeleted,
      "itemContent": itemContent,
      "itemUid": itemUid,
      "itemType": itemType,
      "itemName": itemName,
      "mtime": mtime,
    };
    return theMap;
  }
}

class ItemListResponse {
  final EtebaseItemManager itemManager;
  final String username;
  final String cacheDir;

  final Map<Uint8List, ItemListItem> items;

  ItemListResponse(
      {required this.itemManager,
      required this.username,
      required this.cacheDir,
      required this.items});

  Map<String, dynamic> toMap() {
    final theMap = <String, dynamic>{};

    theMap["itemManager"] = itemManager;
    theMap["username"] = username;
    theMap["cacheDir"] = cacheDir;
    theMap["items"] = items.map((key, value) => MapEntry(key, value.toMap()));
    return theMap;
  }
}

class CollectionListItem {
  final bool itemIsDeleted;

  final String itemUid;
  final Uint8List itemContent;
  final String? itemType;
  final String? itemName;
  final String itemCollectionType;
  final String? itemColor;

  CollectionListItem(
      {required this.itemIsDeleted,
      required this.itemUid,
      required this.itemContent,
      required this.itemType,
      required this.itemName,
      required this.itemCollectionType,
      required this.itemColor});

  static CollectionListItem fromMap(Map<String, dynamic> theMap) {
    return CollectionListItem(
      itemIsDeleted: theMap["itemIsDeleted"],
      itemUid: theMap["itemUid"],
      itemContent: theMap["itemContent"],
      itemType: theMap["itemType"],
      itemName: theMap["itemName"],
      itemColor: theMap["itemColor"],
      itemCollectionType: theMap["itemCollectionType"],
    );
  }

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> theMap = {
      "itemIsDeleted": itemIsDeleted,
      "itemUid": itemUid,
      "itemContent": itemContent,
      "itemName": itemName,
      "itemColor": itemColor,
      "itemType": itemType,
      "itemCollectionType": itemCollectionType,
    };
    return theMap;
  }
}

class CollectionListResponse {
  final EtebaseCollectionManager collectionManager;
  final String username;
  final String cacheDir;
  final Map<EtebaseCollection, CollectionListItem> items;

  CollectionListResponse(
      {required this.collectionManager,
      required this.username,
      required this.cacheDir,
      required this.items});

  Map<String, dynamic> toMap() {
    final theMap = <String, dynamic>{};
    theMap["collectionManager"] = collectionManager;
    theMap["username"] = username;
    theMap["cacheDir"] = cacheDir;
    theMap["items"] = items.map((key, value) => MapEntry(key, value.toMap()));
    return theMap;
  }
}

Future<ItemListResponse> getItemListResponse(
    EtebaseItemManager itemManager, EtebaseClient client, String colUid,
    {bool cacheOnly = false, Database? db}) async {
  final dbHandler = db ?? sqlite3.open(await dbFilePath());
  bool done = false;
  String? stoken;
  Map<String, dynamic> theMap = {};

  final username = await getUsernameInCacheDir();
  final cacheDir = await getCacheDir();

  final cacheClient =
      await EtebaseFileSystemCache.create(client, cacheDir, username);
  const secureStorage = FlutterSecureStorage();

  final eteCacheAccountEncryptionKey = await secureStorage
          .read(key: eteCacheAccountEncryptionKeyString)
          .then((value) => value != null ? base64Decode(value) : value)
      as Uint8List?;

  final etebase =
      await cacheClient.loadAccount(client, eteCacheAccountEncryptionKey);
  final collUid = await getCollectionUIDInCacheDir();
  final collectionManager = await etebase.getCollectionManager();

  late final EtebaseCollection collection;
  try {
    collection = await cacheClient.collectionGet(collectionManager, collUid);
  } catch (e) {
    collection = await collectionManager.fetch(colUid);
    await cacheClient.collectionSet(collectionManager, collection);
  }

  final cacheItemManager = await collectionManager.getItemManager(collection);
  theMap["itemManager"] = cacheItemManager;
  theMap["username"] = username;
  theMap["cacheDir"] = cacheDir;
  stoken = await cacheClient.collectionLoadStoken(colUid);
  final itemsAtCollPath =
      Directory("$cacheDir/$username/cols/$collUid/items").listSync().toList();

  theMap["items"] = <Uint8List, Map<String, dynamic>>{};
  // for (var cachedItemUID in itemsAtCollPath.map((e) => e.path)) {
  //   final item = await cacheClient.itemGet(itemManager, collUid, cachedItemUID);
  //   final itemByteBuffer = await itemManager.cacheSaveWithContent(item);
  //   theMap["items"][itemByteBuffer] = {
  //     "itemIsDeleted": await item.isDeleted(),
  //     "itemUid": await item.getUid(),
  //     "itemContent": await item.getContent(),
  //     "itemType": (await item.getMeta()).itemType,
  //     "itemName": (await item.getMeta()).name,
  //     "mtime": (await item.getMeta()).mtime,
  //   };
  // }
  //final itemsToPutInCache = [];
  while (!done && !cacheOnly) {
    bool loopAgainSpecial = false;
    try {
      final EtebaseItemListResponse rawItemList = await itemManager.list(
          EtebaseFetchOptions(
              stoken: itemsAtCollPath.isNotEmpty ? stoken : null, limit: 50));

      List<EtebaseItem> itemList = await (rawItemList).getData();
      stoken = await rawItemList.getStoken();
      done = await rawItemList.isDone();
      final changesSince = <Uint8List, ItemListItem>{};
      for (final item in itemList) {
        //itemsToPutInCache.add(item);
        await cacheClient.itemSet(itemManager, colUid, item);
        final itemByteBuffer = await itemManager.cacheSaveWithContent(item);
        final itemUid = await item.getUid();
        for (final elementKeyInMap
            in (theMap["items"] as Map<Uint8List, Map<String, dynamic>>).keys) {
          if (elementKeyInMap == itemByteBuffer) {
            (theMap["items"] as Map).remove(elementKeyInMap);
            break;
          }
        }
        final theItemListItemAsMap = {
          "itemIsDeleted": await item.isDeleted(),
          "itemUid": itemUid,
          "itemContent": await item.getContent(),
          "itemType": (await item.getMeta()).itemType,
          "itemName": (await item.getMeta()).name,
          "mtime": (await item.getMeta()).mtime,
        };
        //theMap["items"][itemByteBuffer] = theItemListItemAsMap;
        changesSince[itemByteBuffer] =
            ItemListItem.fromMap(theItemListItemAsMap);
      }

      dbRowsInsert(changesSince.entries, dbHandler,
          await collection.getCollectionType());
    } on EtebaseException catch (e) {
      switch (e.code) {
        case EtebaseErrorCode.generic:
          if (e.message == "operation timed out") {
            loopAgainSpecial = true;
          }
        default:
          rethrow;
      }
    }

    if (loopAgainSpecial) {
      continue;
    }
  }

  if (stoken != null) {
    await cacheClient.collectionSaveStoken(colUid, stoken);
  }

  (theMap["items"] as Map<Uint8List, Map<String, dynamic>>).clear();
  theMap["items"] = (theMap["items"] as Map<Uint8List, Map<String, dynamic>>)
      .map((key, value) => MapEntry(
          key,
          ItemListItem(
            itemType: value["itemType"],
            itemContent: value["itemContent"],
            itemUid: value["itemUid"],
            itemIsDeleted: value["itemIsDeleted"],
            itemName: value["itemName"],
            mtime: value["mtime"],
          )));
  cacheClient.dispose();
  return ItemListResponse(
    items: theMap["items"],
    cacheDir: theMap["cacheDir"],
    username: theMap["username"],
    itemManager: theMap["itemManager"],
  );
}

void dbRowsInsert(Iterable<MapEntry<Uint8List, ItemListItem>> value,
    Database db, String colType) async {
  String sqlTable =
      colType == "etebase.vtodo" ? "etebase_item_model" : "etebase_note_model";
  String sqlStatement =
      '''INSERT or replace INTO $sqlTable (itemUid, itemName, itemContent, itemType, mtime, itemIsDeleted, byteBuffer) VALUES (?,?,?,?,?,?,?);''';
  if (colType == "etebase.vtodo") {
    sqlStatement =
        '''INSERT or replace INTO $sqlTable (itemUid, itemName, itemContent, itemType, mtime, itemIsDeleted, byteBuffer, startTime, endTime, snoozeTime, relatedTo, summary, uid, status) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?);''';
  }

  final executionStatements = value.map((entry) {
    final lKey = entry.key;
    final lItem = entry.value;
    return [
      lItem.itemUid,
      lItem.itemName,
      lItem.itemContent,
      lItem.itemType,
      lItem.mtime?.toUtc().toIso8601String(),
      lItem.itemIsDeleted ? 1 : 0,
      base64Encode(lKey),
    ];
  }).toList() as List<List<dynamic>>;

  for (var element in executionStatements) {
    if (colType == "etebase.vtodo") {
      late final VCalendar icalendar;
      /*if (element[5] == 1) {
        continue;
      }*/

      try {
        icalendar = VComponent.parse(utf8.decode(element[2]),
            customParser: iCalendarCustomParser) as VCalendar;
        element.add(icalendar.todo!.start?.toIso8601String());
        element.add(icalendar.todo!.due?.toIso8601String());
        final aSnoozeTimeText =
            icalendar.todo!.getProperty("X-MOZ-SNOOZE-TIME")?.textValue;

        DateTime? aSnoozeTime;
        if (aSnoozeTimeText != null &&
            (icalendar.todo!.start != null || icalendar.todo!.due != null)) {
          aSnoozeTime = DateTime.parse(aSnoozeTimeText);
          if (!aSnoozeTime
              .isAfter(icalendar.todo!.start ?? icalendar.todo!.due!)) {
            aSnoozeTime = null;
          }
        }

        element.add(aSnoozeTime?.toIso8601String());
        element.add(icalendar.todo!.relatedTo);
        element.add(icalendar.todo!.summary);
        element.add(icalendar.todo!.uid);
        element.add(icalendar.todo!.status.name);
      } catch (e) {
        element.add(null);
        element.add(null);
        element.add(null);
        element.add(null);
        element.add(null);
        element.add(null);
        element.add(null);
        //continue;
      }
    }

    final stmt = db.prepare(sqlStatement);
    //stmt..execute(element);
    stmt.execute(element);

    stmt.dispose();
  }
}

Future<Map<String, dynamic>> getCacheConfigInfo(EtebaseClient client) async {
  final username = await getUsernameInCacheDir();
  final cacheDir = await getCacheDir();

  Map<String, dynamic> theMap = {};
  theMap["cacheDir"] = cacheDir;
  theMap["username"] = username;
  return theMap;
}

Future<CollectionListResponse> getCollections(EtebaseClient client,
    {EtebaseAccount? etebaseAccount,
    String collectionType = "etebase.vtodo"}) async {
  final username = await getUsernameInCacheDir();
  final cacheDir = await getCacheDir();
  final cacheClient =
      await EtebaseFileSystemCache.create(client, cacheDir, username);
  const secureStorage = FlutterSecureStorage();

  final eteCacheAccountEncryptionKey = etebaseAccount == null
      ? await secureStorage
              .read(key: eteCacheAccountEncryptionKeyString)
              .then((value) => value != null ? base64Decode(value) : value)
          as Uint8List?
      : null;

  final etebase = etebaseAccount ??
      await cacheClient.loadAccount(client, eteCacheAccountEncryptionKey);

  String? stoken = await cacheClient.loadStoken();

  final collManager = await etebase.getCollectionManager();

  Map<String, dynamic> theMap = {};
  theMap["items"] = <EtebaseCollection, Map<String, dynamic>>{};
  theMap["username"] = username;
  theMap["cacheDir"] = cacheDir;
  theMap["collectionManager"] = collManager;

  bool done = false;

  final itemsAtCollPath =
      Directory("$cacheDir/$username/cols/").listSync().toList();

  for (var cachedItemUID in itemsAtCollPath.map((e) => e.path)) {
    final item = await cacheClient.collectionGet(collManager, cachedItemUID);

    if (await item.getCollectionType() != collectionType) {
      continue;
    }
    theMap["items"][item] = {
      "itemIsDeleted": await item.isDeleted(),
      "itemUid": await item.getUid(),
      "itemContent": await item.getContent(),
      "itemName": (await item.getMeta()).name,
      "itemColor": (await item.getMeta()).color,
      "itemType": (await item.getMeta()).itemType,
      "itemCollectionType": (await item.getCollectionType()),
    };
  }

  while (!done) {
    EtebaseCollectionListResponse rawItemList = await collManager.list(
        collectionType,
        EtebaseFetchOptions(
            stoken: theMap["items"].isNotEmpty ? stoken : null, limit: 50));
    List<EtebaseCollection> itemList = await rawItemList.getData();
    stoken = await rawItemList.getStoken();
    done = await rawItemList.isDone();

    for (final item in itemList) {
      final itemUid = await item.getUid();
      for (final elementKeyInMap
          in (theMap["items"] as Map<EtebaseCollection, Map<String, dynamic>>)
              .keys) {
        if ((await elementKeyInMap.getUid()) == itemUid) {
          (theMap["items"] as Map).remove(elementKeyInMap);
          break;
        }
      }

      await cacheClient.collectionSet(collManager, item);
      theMap["items"][item] = {
        "itemIsDeleted": await item.isDeleted(),
        "itemUid": await item.getUid(),
        "itemContent": await item.getContent(),
        "itemName": (await item.getMeta()).name,
        "itemColor": (await item.getMeta()).color,
        "itemType": (await item.getMeta()).itemType,
        "itemCollectionType": (await item.getCollectionType()),
      };
    }
  }
  if (stoken != null) {
    await cacheClient.saveStoken(stoken);
  }

  theMap["items"] =
      (theMap["items"] as Map<EtebaseCollection, Map<String, dynamic>>)
          .map((key, value) => MapEntry(
              key,
              CollectionListItem(
                itemIsDeleted: value["itemIsDeleted"],
                itemUid: value["itemUid"],
                itemContent: value["itemContent"],
                itemName: value["itemName"],
                itemColor: value["itemColor"],
                itemType: value["itemType"],
                itemCollectionType: value["itemCollectionType"],
              )));

  return CollectionListResponse(
    items: theMap["items"],
    cacheDir: theMap["cacheDir"],
    username: theMap["username"],
    collectionManager: theMap["collectionManager"],
  );
  //return (theMap["items"] as Map<EtebaseCollection, Map<String, dynamic>>)
  //    .keys
  //    .toList();
}

VTodo? getNextOccurrence(VTodo todoComp, Recurrence? recurrenceRule) {
  if (recurrenceRule != null) {
    final frequencyT = switch (recurrenceRule.frequency) {
      RecurrenceFrequency.secondly => Frequency.secondly,
      RecurrenceFrequency.minutely => Frequency.minutely,
      RecurrenceFrequency.hourly => Frequency.hourly,
      RecurrenceFrequency.daily => Frequency.daily,
      RecurrenceFrequency.weekly => Frequency.weekly,
      RecurrenceFrequency.monthly => Frequency.monthly,
      RecurrenceFrequency.yearly => Frequency.yearly,
    };
    if (recurrenceRule.count != null && recurrenceRule.count! <= 1) {
      return null; // end of reccurence
    } else {
      var rrule = RecurrenceRule(
          frequency: frequencyT,
          until: recurrenceRule.until?.toUtc(),
          count: null,
          interval: recurrenceRule.interval,
          bySeconds: recurrenceRule.bySecond ?? [],
          byMinutes: recurrenceRule.byMinute ?? [],
          byHours: recurrenceRule.byHour ?? [],
          byWeekDays: recurrenceRule.byWeekDay
                  ?.map((value) => ByWeekDayEntry(value.weekday, value.week))
                  .toList() ??
              [],
          byMonthDays: recurrenceRule.byMonthDay ?? [],
          byYearDays: recurrenceRule.byYearDay ?? [],
          byWeeks: recurrenceRule.byWeek ?? [],
          byMonths: recurrenceRule.byMonth ?? []);
      final instancesStart =
          (todoComp.start ?? todoComp.due!).copyWith(isUtc: true);
      final instances = rrule.getInstances(start: instancesStart).iterator;
      DateTime? nextInstance;
      while (instances.moveNext()) {
        final instance = instances.current;
        if (instance.compareTo(instancesStart) == 1) {
          nextInstance = instance;
          break;
        }
      }
      if (nextInstance != null) {
        final nextStartDate = todoComp.start != null ? nextInstance : null;
        DateTime? nextDueDate = todoComp.due != null ? nextInstance : null;
        if (nextStartDate != null && nextDueDate != null) {
          final offset = todoComp.due!.difference(todoComp.start!);
          nextDueDate = nextDueDate.add(offset);
        }
        final nextTodo = todoComp;

        //nextTodo.uid = (const Uuid()).v4();
        if (nextStartDate != null) {
          nextTodo.start = nextStartDate
              .copyWith(isUtc: todoComp.start?.isUtc ?? false)
              .toUtc();
        }
        if (nextDueDate != null) {
          nextTodo.due =
              nextDueDate.copyWith(isUtc: todoComp.due?.isUtc ?? false).toUtc();
        }

        if (todoComp.recurrenceRule?.count != null &&
            todoComp.recurrenceRule!.count! > 0) {
          nextTodo.recurrenceRule =
              recurrenceRule.copyWith(count: recurrenceRule.count! - 1);
        }
        nextTodo.status = TodoStatus.needsAction;
        nextTodo.lastModified = DateTime.now();
        return nextTodo;
      }
    }

    return null;
  } else {
    return null;
  }
}

class ItemMapWrapper {
  final Uint8List item;
  final Map<String, dynamic> value;
  final VCalendar icalendar;

  ItemMapWrapper(
      {required this.item, required this.value, required this.icalendar});
}

class LocaleModel extends ChangeNotifier {
  Locale locale = Locale(Intl.getCurrentLocale());

  LocaleModel({Locale? initialLocale}) {
    if (initialLocale != null && locale != initialLocale) {
      locale = initialLocale;
    }
  }

  void set(Locale newLocale) {
    locale = newLocale;

    notifyListeners();
  }
}
