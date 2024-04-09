import 'dart:convert';
import 'dart:io';
import 'dart:developer' as dev;
import 'dart:isolate';

import 'package:enough_icalendar/enough_icalendar.dart';
import 'package:etebase_flutter/etebase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rrule/rrule.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Future<List> getItemManager() async {
  Uri? serverUri = await getServerUri();

  late final EtebaseClient client;
  try {
    client = await getEtebaseClient();
  } on EtebaseException catch (e) {
    if (e.code == EtebaseErrorCode.urlParse) {
      return [null, null, null, null, serverUri, null, null];
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
  final cacheDir = await myReceivePort.first;

  if (!Directory(cacheDir).existsSync()) {
    return [client, null, null, null, serverUri, null, null];
  }

  late final String username;
  try {
    username = await getUsernameInCacheDir();
  } catch (error) {
    return [client, null, null, null, serverUri, null, null];
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
    return [client, null, null, null, serverUri, cacheClient, null];
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
  ];
}

class ItemListItem {
  final bool itemIsDeleted;

  final String itemUid;
  final Uint8List itemContent;
  final String? itemType;

  ItemListItem(
      {required this.itemIsDeleted,
      required this.itemUid,
      required this.itemContent,
      required this.itemType});

  static ItemListItem fromMap(Map<String, dynamic> theMap) {
    return ItemListItem(
        itemIsDeleted: theMap["itemIsDeleted"],
        itemUid: theMap["itemUid"],
        itemContent: theMap["itemContent"],
        itemType: theMap["itemType"]);
  }

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> theMap = {
      "itemIsDeleted": itemIsDeleted,
      "itemContent": itemContent,
      "itemUid": itemUid,
      "itemType": itemType
    };
    return theMap;
  }
}

class ItemListResponse {
  final EtebaseItemManager itemManager;
  final String username;
  final String cacheDir;
  final Map<EtebaseItem, ItemListItem> items;

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

Future<ItemListResponse> getItemListResponse(
    EtebaseItemManager itemManager, EtebaseClient client, String colUid) async {
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

  dev.log(
      "number of cached items in collection `$collUid`: ${itemsAtCollPath.length}",
      name: "ete_sync_app",
      time: DateTime.now(),
      level: Level.CONFIG.value);

  theMap["items"] = <EtebaseItem, Map<String, dynamic>>{};
  for (var cachedItemUID in itemsAtCollPath.map((e) => e.path)) {
    final item = await cacheClient.itemGet(itemManager, collUid, cachedItemUID);
    theMap["items"][item] = {
      "itemIsDeleted": await item.isDeleted(),
      "itemUid": await item.getUid(),
      "itemContent": await item.getContent(),
      "itemType": (await item.getMeta()).itemType,
    };
  }
  //final itemsToPutInCache = [];
  while (!done) {
    late final EtebaseItemListResponse rawItemList;
    bool loopAgainSpecial = false;
    try {
      rawItemList = await itemManager.list(EtebaseFetchOptions(
          stoken: theMap["items"].isNotEmpty ? stoken : null, limit: 50));
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
    List<EtebaseItem> itemList = await (rawItemList).getData();
    stoken = await rawItemList.getStoken();
    done = await rawItemList.isDone();

    for (final item in itemList) {
      //itemsToPutInCache.add(item);
      await cacheClient.itemSet(itemManager, colUid, item);
      final itemUid = await item.getUid();
      for (final elementKeyInMap
          in (theMap["items"] as Map<EtebaseItem, Map<String, dynamic>>).keys) {
        if ((await elementKeyInMap.getUid()) == itemUid) {
          (theMap["items"] as Map).remove(elementKeyInMap);
          break;
        }
      }
      theMap["items"][item] = {
        "itemIsDeleted": await item.isDeleted(),
        "itemUid": await item.getUid(),
        "itemContent": await item.getContent(),
        "itemType": (await item.getMeta()).itemType,
      };
    }
  }

  if (stoken != null) {
    await cacheClient.collectionSaveStoken(colUid, stoken);
  }

  theMap["items"] = (theMap["items"] as Map<EtebaseItem, Map<String, dynamic>>)
      .map((key, value) => MapEntry(
          key,
          ItemListItem(
              itemType: value["itemType"],
              itemContent: value["itemContent"],
              itemUid: value["itemUid"],
              itemIsDeleted: value["itemIsDeleted"])));

  return ItemListResponse(
    items: theMap["items"],
    cacheDir: theMap["cacheDir"],
    username: theMap["username"],
    itemManager: theMap["itemManager"],
  );
}

Future<Map<String, dynamic>> getCacheConfigInfo(EtebaseClient client) async {
  final username = await getUsernameInCacheDir();
  final cacheDir = await getCacheDir();

  Map<String, dynamic> theMap = {};
  theMap["cacheDir"] = cacheDir;
  theMap["username"] = username;
  return theMap;
}

Future<Map<String, dynamic>> getCollections(EtebaseClient client,
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

  return theMap;
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
          nextTodo.start =
              nextStartDate.copyWith(isUtc: todoComp.start?.isUtc ?? false);
        }
        if (nextDueDate != null) {
          nextTodo.due =
              nextDueDate.copyWith(isUtc: todoComp.due?.isUtc ?? false);
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
  final EtebaseItem item;
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
